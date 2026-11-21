"""Run session.sh against simulated macOS power controls. No admin access needed."""
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(__file__).with_name("session.sh").read_text()


class SessionTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.write("power", "AC")
        self.write("charge", "95")
        self.write("state", "No")
        self.write("lid", "No")
        self.script = SOURCE.replace("cd / || exit 1", "cd . || exit 1")
        commands = {
            "/usr/bin/pmset": """
if [ "$1" = -g ]; then
    echo "Now drawing from '$(cat power) Power'"
    echo " -InternalBattery-0 (id=123)   $(cat charge)%; discharging; present: true"
    exit
fi
if [ "$1" = displaysleepnow ]; then echo sleep >> display; exit; fi
echo "$2" >> changes
if [ "$2" = 1 ]; then
    [ ! -f reject ] || exit 1
    echo Yes > state
else
    echo No > state
fi""",
            "/usr/sbin/ioreg": """
lid=$(cat lid)
echo "$lid" >> samples
echo '"SleepDisabled" = '$(cat state)
echo '"AppleClamshellState" = '"$lid"
""",
            "/bin/sleep": "exec /bin/sleep 0.02",
        }
        for system_path, body in commands.items():
            stub = self.root / Path(system_path).name
            stub.write_text("#!/bin/sh\n" + body + "\n")
            stub.chmod(0o700)
            self.script = self.script.replace(system_path, "'" + str(stub) + "'")

    def write(self, key, value):
        tmp = self.root / (key + ".tmp")
        tmp.write_text(value)
        tmp.replace(self.root / key)

    def start(self):
        self.worker = subprocess.Popen(["/bin/sh", "-p", "-c", self.script],
                                       cwd=self.root, stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.addCleanup(self.worker.stdin.close)
        self.addCleanup(self.worker.wait, 2)
        self.addCleanup(self.worker.terminate)

    def wait_for_override(self):
        for _ in range(200):
            if (self.root / "state").read_text().strip() == "Yes":
                return
            time.sleep(0.01)
        self.fail("Override never became active")

    def check_restored(self):
        self.assertEqual(self.worker.wait(2), 0)
        self.assertEqual((self.root / "changes").read_text().splitlines(), ["1", "0"])
        self.assertEqual((self.root / "state").read_text().strip(), "No")

    def lines(self, name):
        path = self.root / name
        return path.read_text().splitlines() if path.exists() else []

    def sample_lid(self, value):
        count = self.lines("samples").count(value)
        self.write("lid", value)
        for _ in range(300):
            if self.lines("samples").count(value) >= count + 3:
                return
            time.sleep(0.01)
        self.fail(f"Lid state {value} was never sampled repeatedly")

    def test_display_sleeps_once_each_time_lid_closes(self):
        self.start()
        self.wait_for_override()
        for lid, expected in [("No", 0), ("Unknown", 0), ("Yes", 1), ("Unknown", 1),
                              ("Yes", 1), ("No", 1), ("Yes", 2)]:
            self.sample_lid(lid)
            self.assertEqual(self.lines("display"), ["sleep"] * expected)
            self.assertEqual(self.lines("changes"), ["1"])
        self.worker.stdin.close()
        self.check_restored()

    def test_already_closed_at_start(self):
        self.write("lid", "Yes")
        self.start()
        self.wait_for_override()
        self.sample_lid("Yes")
        self.assertEqual(self.lines("display"), ["sleep"])

    def test_app_disappears(self):
        self.start()
        self.wait_for_override()
        self.worker.stdin.close()
        self.check_restored()

    def test_unplug_and_reconnect_keeps_session(self):
        self.start()
        self.wait_for_override()
        for power in ["Battery", "AC", "Battery"]:
            self.write("power", power)
            self.sample_lid("No")
            self.assertEqual(self.lines("changes"), ["1"])
        self.write("charge", "10")
        self.check_restored()

    def test_existing_override(self):
        self.write("state", "Yes")
        self.start()
        self.assertNotEqual(self.worker.wait(2), 0)
        self.assertFalse((self.root / "changes").exists())

    def test_start_on_battery(self):
        self.write("power", "Battery")
        self.write("charge", "11")
        self.start()
        self.wait_for_override()
        self.sample_lid("Yes")
        self.assertEqual(self.lines("display"), ["sleep"])
        self.worker.stdin.close()
        self.check_restored()

    def test_low_battery_at_start(self):
        self.write("power", "Battery")
        self.write("charge", "10")
        self.start()
        self.assertNotEqual(self.worker.wait(2), 0)
        self.assertFalse((self.root / "changes").exists())

    def test_battery_read_failure_restores(self):
        self.write("power", "Battery")
        self.start()
        self.wait_for_override()
        self.write("charge", "unknown")
        self.check_restored()

    def test_apply_failure(self):
        self.write("reject", "")
        self.start()
        self.assertNotEqual(self.worker.wait(2), 0)
        self.assertEqual((self.root / "state").read_text().strip(), "No")


if __name__ == "__main__":
    unittest.main()
