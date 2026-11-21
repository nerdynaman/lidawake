import AppKit
import IOKit.ps

func onAC() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
    return source as String == kIOPSACPowerValue
}

func sleepDisabled() -> Bool? {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return nil }
    defer { IOObjectRelease(root) }
    return IORegistryEntryCreateCFProperty(root, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? Bool
}

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggle = NSMenuItem(title: "Keep awake with lid closed", action: #selector(change), keyEquivalent: "")
    private let status = NSMenuItem()
    private var runner: Process?
    private var lease: Pipe?
    private var timer: Timer?
    private var stopping = false

    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        status.isEnabled = false
        toggle.target = self
        menu.addItem(status)
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LidAwake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        let disabled = sleepDisabled()
        let active = runner != nil && disabled == true && !stopping
        var message = "Off"
        if runner != nil {
            message = stopping ? "Restoring normal sleep…" : (active ? (onAC() ? "On · plugged in" : "On · battery") : "Starting…")
        } else if disabled == nil { message = "Sleep status unavailable" }
        else if disabled == true { message = "Sleep already disabled on this Mac" }
        status.title = message
        toggle.state = active ? .on : .off
        toggle.isEnabled = !stopping && (runner != nil || disabled == false)
        item.button?.title = active ? "Lid ●" : "Lid"
        item.button?.toolTip = "LidAwake · " + message
        item.button?.setAccessibilityLabel("LidAwake, " + message)
    }

    private func releaseLease() {
        try? lease?.fileHandleForWriting.close()
        lease = nil
    }

    @objc func change() {
        if runner != nil {
            stopping = true
            releaseLease()
            refresh()
            return
        }
        guard sleepDisabled() == false else { refresh(); return }
        let pipe = Pipe()
        let auth = Process()
        let errors = Pipe()
        do {
            guard try ensurePermission(), sleepDisabled() == false else { refresh(); return }
            lease = pipe
            auth.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            auth.arguments = ["-n", "--"] + sessionCommand
            auth.standardInput = pipe
            auth.standardError = errors
            auth.standardOutput = FileHandle.nullDevice
            auth.terminationHandler = { process in
                let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                DispatchQueue.main.async {
                    self.timer?.invalidate()
                    self.timer = nil
                    self.runner = nil
                    self.stopping = false
                    self.releaseLease()
                    self.refresh()
                    if process.terminationStatus != 0 && !detail.contains("(-128)") {
                        self.alert(detail.isEmpty ? "macOS could not complete the session." : detail)
                    }
                }
            }
            try auth.run()
            runner = auth
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
            refresh()
        } catch {
            releaseLease()
            alert(error.localizedDescription)
        }
    }

    private func alert(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "LidAwake"
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationWillTerminate(_ note: Notification) { releaseLease() }
}

if CommandLine.arguments.contains("--status") {
    print("External AC power: \(onAC()). Sleep disabled: \(sleepDisabled().map(String.init) ?? "unknown").")
} else if CommandLine.arguments.contains("--print-setup") {
    print(setupCommand())
} else {
    let app = NSApplication.shared
    let delegate = Controller()
    app.delegate = delegate
    app.run()
}
