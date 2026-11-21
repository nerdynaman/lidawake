<img src="assets/icon.svg" width="64" height="64" alt="">

# LidAwake

Created in [T3 Code](https://t3.codes).

A single menu-bar switch for keeping an Apple silicon Mac awake with the lid closed. While the switch is on, LidAwake 1.3 requests display sleep when macOS reports a closed lid. It checks about every two seconds. The command can also turn off connected external displays. Opening the lid leaves wake behavior to macOS. Built on macOS 26.7.1 (25G241).

## Use

1. If upgrading, switch the previous version off, wait for **Off**, and quit it. Open the new LidAwake.app in Finder. Click **Lid** in the menu bar.
2. Select **Keep awake with lid closed**, and approve the one-time macOS administrator prompt. Future sessions on this account reuse that approval, including after quitting the app or restarting the Mac. Wait for **On · battery** or **On · plugged in**. Upgrading from 1.2 asks once to replace its privileged helper. Another tool that already disabled sleep must end its session first.
3. You can unplug or reconnect the charger during a session. To stop, uncheck the switch or quit. On battery, the session ends at 10% charge or if the charge level is unavailable, allowing normal sleep. Start a new session manually after charging.
4. To test on the Air, start a T3 task there, lock the screen, and fully close the lid. Check for fresh output on the Pro a few minutes later. Reopen the lid to use the screen again. A partly open lid may still register as open.

## Permissions and recovery

On first use, macOS asks an administrator to install a read-only, root-owned copy of session.sh under /private/etc and a sudoers rule for your numeric user ID. The installer checks the rule with visudo before activating it. To inspect exactly what will run, pass **--print-setup** to the app executable. macOS handles the password dialog.

The rule lets processes running as your account start this one fixed helper command with a clean environment. The helper uses a system-wide lock, allows the sleep override on external power or above 10% battery, and restores normal sleep when the battery reaches the cutoff or the app’s pipe closes. The authorization survives reboot and deleting the app. A change to the installed helper or removal of the rule requires setup again.

To revoke access, turn the switch off, wait for **Off**, and quit. Run this in Terminal from the account that enabled LidAwake:

    sudo /bin/rm -f "/private/etc/sudoers.d/lidawake-$(id -u)" "/private/etc/lidawake-session-$(id -u)-v1"

The override is a system setting. A hard power loss, a forcibly killed helper, or a restoration failure can leave it set. If that happens and LidAwake was responsible, open Terminal and run:

    sudo /usr/bin/pmset disablesleep 0

Avoid running another sleep override during a session because both tools would write the same setting. Remote access must already be configured independently.

## Build from source

With Apple's Command Line Tools installed, run **./build.sh** in the source directory. The resulting app is **build/LidAwake.app**. The build uses the local Apple compiler, system frameworks, and an ad hoc signature. The binary has no Apple Developer ID notarization. Building locally is an option if a transferred copy triggers Gatekeeper.

Run **python3 test_session.py** for the simulated power and cleanup tests. After building, run **python3 test_permission.py** to check the one-time setup and relaunch in a temporary directory. Run **build/LidAwake.app/Contents/MacOS/LidAwake --status** for read-only power diagnostics.
