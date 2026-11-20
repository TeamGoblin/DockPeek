import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let previews = PreviewController()
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()
        setUpStatusItem()
        requestPermissions()
        previews.start()
    }

    /// Re-opening the app (e.g. double-clicking it in Finder) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) || !CGPreflightScreenCaptureAccess() {
            if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
            settings.show()
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockPeek")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: "Window Previews Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = Pref.isEnabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)

        if !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "⚠︎ Permissions needed…", action: #selector(openSettings), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let s = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        s.target = self
        menu.addItem(s)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DockPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleEnabled() {
        UserDefaults.standard.set(!Pref.isEnabled, forKey: Pref.enabled)
        if !Pref.isEnabled { previews.hide() }
    }

    @objc private func openSettings() { settings.show() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
