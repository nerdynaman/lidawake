import Foundation

// Both files live under root-owned directories. The grant matches this exact command and arguments.
let helperPath = "/private/etc/lidawake-session-\(getuid())-v1"
let rulePath = "/private/etc/sudoers.d/lidawake-\(getuid())"
let sessionCommand = ["/usr/bin/env", "-i", "/usr/bin/lockf", "-k", "-t", "0",
                      "/private/var/run/local.lidawake.lock", "/bin/sh", "-p", helperPath]
let sessionRule = "#\(getuid()) ALL=(root) NOPASSWD: NOSETENV: " + sessionCommand.joined(separator: " ")

func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func setupCommand() -> String {
    """
    set -eu
    umask 077
    stage=$(/usr/bin/mktemp -d /private/etc/.lidawake.XXXXXXXX)
    trap '/bin/rm -rf "$stage"' EXIT
    /usr/bin/printf '%s\\n' \(shellQuote(sessionScript)) > "$stage/helper"
    /usr/bin/printf '%s\\n' \(shellQuote(sessionRule)) > "$stage/rule"
    /usr/sbin/visudo -c -f "$stage/rule"
    /usr/sbin/chown root:wheel "$stage/helper" "$stage/rule"
    /bin/chmod 0444 "$stage/helper"
    /bin/chmod 0440 "$stage/rule"
    /bin/mv -f "$stage/helper" \(helperPath)
    /bin/mv -f "$stage/rule" \(rulePath)
    """
}

// A cancelled authorization leaves the switch off. Never keep or handle the password ourselves.
func ensurePermission() throws -> Bool {
    if FileManager.default.fileExists(atPath: rulePath),
       (try? String(contentsOfFile: helperPath, encoding: .utf8)) == sessionScript + "\n" {
        return true
    }
    let setup = Process()
    setup.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    setup.arguments = ["-e", "on run argv\n do shell script (item 1 of argv) with administrator privileges\nend run", setupCommand()]
    let errors = Pipe()
    setup.standardError = errors
    setup.standardOutput = FileHandle.nullDevice
    try setup.run()
    let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    setup.waitUntilExit()
    if setup.terminationStatus == 0 { return true }
    if detail.contains("(-128)") { return false }
    throw NSError(domain: "LidAwake", code: Int(setup.terminationStatus),
                  userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "Permission setup failed." : detail])
}
