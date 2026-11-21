"""Run the first and second launch against a temporary policy directory. No sudo."""
import os
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
uid = os.getuid()
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / "sudoers.d").mkdir()
    # Keep the real setup and visudo check, replace only privileged filesystem targets,
    # ownership change, and the macOS UI which normally authenticates the installer.
    fake_auth = root / "osascript"
    fake_auth.write_text(f'#!/bin/sh\necho prompt >> "{root}/prompts"\nexec /bin/sh -c "$3"\n')
    fake_auth.chmod(0o700)
    permission = (here / "Permission.swift").read_text().replace("/private/etc", tmp)
    permission = permission.replace("/usr/bin/osascript", str(fake_auth)).replace("/usr/sbin/chown root:wheel", "/usr/bin/true")
    (root / "Permission.swift").write_text(permission)
    (root / "main.swift").write_text('import Foundation\nif try !ensurePermission() { exit(1) }\n')
    probe = root / "probe"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(Path(tempfile.gettempdir()) / "lidawake-swift-cache"),
                    str(root / "main.swift"), str(root / "Permission.swift"), str(here / "build/Session.swift"),
                    "-o", str(probe)], check=True)
    subprocess.run([probe], check=True)
    subprocess.run([probe], check=True)
    assert (root / "prompts").read_text().splitlines() == ["prompt"]
    helper = root / f"lidawake-session-{uid}-v1"
    rule = root / "sudoers.d" / f"lidawake-{uid}"
    assert helper.read_bytes() == (here / "session.sh").read_bytes()
    assert helper.stat().st_mode & 0o777 == 0o444
    assert rule.stat().st_mode & 0o777 == 0o440
    assert rule.read_text() == (f"#{uid} ALL=(root) NOPASSWD: NOSETENV: /usr/bin/env -i "
                                f"/usr/bin/lockf -k -t 0 /private/var/run/local.lidawake.lock /bin/sh -p {helper}\n")
    rule.unlink()
    subprocess.run([probe], check=True)
    assert (root / "prompts").read_text().splitlines() == ["prompt", "prompt"]
    print("First setup, prompt-free relaunch, exact rule and reapproval after removal passed.")
