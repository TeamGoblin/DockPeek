import AppKit
import ApplicationServices

struct DockItem: Equatable {
    let element: AXUIElement
    let title: String
    let appURL: URL?
    /// Icon frame, top-left-origin global coords.
    let frame: CGRect

    static func == (a: DockItem, b: DockItem) -> Bool { CFEqual(a.element, b.element) }
}

/// Watches the Dock's accessibility tree and reports which application icon
/// the mouse is hovering (the Dock "selects" items under the cursor).
@MainActor
final class DockObserver {
    var onHoverChange: ((DockItem?) -> Void)?
    private(set) var hovered: DockItem?

    private var observer: AXObserver?
    private var dockList: AXUIElement?
    private var dockPID: pid_t = 0
    private var watchdog: Timer?
    private var poller: Timer?
    /// Dock list frame in AppKit coords, refreshed periodically (cheap mouse-vs-dock test).
    private var cachedDockFrame: NSRect?
    private var lastFrameRefresh = Date.distantPast

    func start() {
        attach()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.dock" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.attach() }
        }
        // Re-attach if the Dock restarted or permission was granted after launch.
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let pid = Self.dockApp()?.processIdentifier ?? 0
                if self.observer == nil || pid != self.dockPID { self.attach() }
            }
        }
    }

    /// Frame of the whole Dock list (top-left coords).
    var dockFrame: CGRect? { dockList?.frame }

    private static func dockApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        dockList = nil
    }

    private func attach() {
        detach()
        guard AXIsProcessTrusted(), let dock = Self.dockApp() else { return }
        dockPID = dock.processIdentifier
        let app = AXUIElementCreateApplication(dockPID)
        guard let list = app.elements(kAXChildrenAttribute).first(where: { $0.role == kAXListRole }) else { return }

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<DockObserver>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.selectionChanged() }
        }
        guard AXObserverCreate(dockPID, callback, &obs) == .success, let obs else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(obs, list, kAXSelectedChildrenChangedNotification as CFString, refcon) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        dockList = list
        cachedDockFrame = list.frame.map(Coords.toAppKit)
        lastFrameRefresh = Date()
        if poller == nil {
            poller = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        }
    }

    /// The Dock doesn't always post a "selection changed" when the mouse leaves it
    /// (e.g. after clicking into a window). If we keep a stale hovered item, re-hovering
    /// the same icon looks like "no change" and no bubble appears. So we also verify
    /// against the real mouse position.
    private func poll() {
        guard let list = dockList else { return }
        if Date().timeIntervalSince(lastFrameRefresh) > 1 {
            cachedDockFrame = list.frame.map(Coords.toAppKit)
            lastFrameRefresh = Date()
        }
        let loc = NSEvent.mouseLocation
        var inDock = cachedDockFrame?.insetBy(dx: -4, dy: -4).contains(loc) ?? false
        if !inDock, let h = hovered, Coords.toAppKit(h.frame).insetBy(dx: -4, dy: -4).contains(loc) {
            inDock = true  // magnified icon poking above the list frame
        }
        if !inDock && hovered != nil {
            // Double-check with a fresh frame (Dock may have moved / un-hidden) before clearing.
            if let fresh = list.frame.map(Coords.toAppKit) {
                cachedDockFrame = fresh
                lastFrameRefresh = Date()
                inDock = fresh.insetBy(dx: -4, dy: -4).contains(loc)
            }
        }
        if inDock {
            selectionChanged()
        } else if hovered != nil {
            hovered = nil
            onHoverChange?(nil)
        }
    }

    private func selectionChanged() {
        let item = currentItem()
        guard item != hovered else { return }
        hovered = item
        onHoverChange?(item)
    }

    private func currentItem() -> DockItem? {
        guard let list = dockList, let el = list.elements(kAXSelectedChildrenAttribute).first else { return nil }
        guard el.subrole == "AXApplicationDockItem", let frame = el.frame else { return nil }
        return DockItem(element: el, title: el.title ?? "", appURL: el.url, frame: frame)
    }
}
