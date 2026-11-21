# Installed under /private/etc by the one-time setup. stdin is the app's session pipe.
cd / || exit 1
export LC_ALL=C
enough_power() {
    /usr/bin/pmset -g batt | /usr/bin/awk -v ac="Now drawing from 'AC Power'" -v bat="Now drawing from 'Battery Power'" '
        NR == 1 { plugged_in = ($0 == ac); battery = ($0 == bat) }
        battery && /InternalBattery/ && match($0, /[[:space:]][0-9]+%;/) {
            charge = substr($0, RSTART + 1, RLENGTH - 3) + 0
        }
        END { exit !(plugged_in || (charge > 10 && charge <= 100)) }'
}
power_property() {
    /usr/sbin/ioreg -r -d 1 -c IOPMrootDomain |
        /usr/bin/awk -v key="\"$1\"" '$1 == key && $2 == "=" {print $3; exit}'
}

fail() { echo "$1" >&2; exit 1; }

enough_power || fail 'Connect power or charge the battery above 10% to start.'
[ "$(power_property SleepDisabled)" = No ] || fail 'Sleep is already disabled or its state is unavailable.'
# An explicit fd preserves piped stdin for the background reader even in a noninteractive shell.
exec 3<&0
/bin/cat <&3 >/dev/null &
reader=$!
exec 3<&-
restore() {
    kill "$reader" 2>/dev/null || :
    /usr/bin/pmset disablesleep 0 && [ "$(power_property SleepDisabled)" = No ] ||
        { echo 'Restore failed. Run sudo pmset disablesleep 0 in Terminal.' >&2; exit 1; }
}
trap restore EXIT
trap 'exit 0' HUP INT TERM
/usr/bin/pmset disablesleep 1 && [ "$(power_property SleepDisabled)" = Yes ] ||
    fail 'macOS did not confirm the sleep override.'
display_sleep_sent=0
while kill -0 "$reader" 2>/dev/null && enough_power; do
    case "$(power_property AppleClamshellState)" in
        Yes)
            if [ "$display_sleep_sent" = 0 ]; then
                if /usr/bin/pmset displaysleepnow >/dev/null 2>&1; then display_sleep_sent=1; fi
            fi ;;
        No) display_sleep_sent=0 ;;
    esac
    /bin/sleep 2
done
