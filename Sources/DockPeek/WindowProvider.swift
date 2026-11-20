import AppKit
import ScreenCaptureKit

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let title: String
    /// Top-left-origin global coords.
    let frame: CGRect
    let pid: pid_t
    let ax: AXUIElement?
    let isMinimized: Bool
    let isHidden: Bool
    let isOnScreen: Bool
    /// Desktop number when the window lives on a Space other than the current one.
    let spaceNumber: Int?
    let scWindow: SCWindow?

    /// Minimized, hidden, or on another Space.
    var isInvisible: Bool { isMinimized || isHidden || !isOnScreen }
}

@MainActor
final class WindowProvider {
    static let shared = WindowProvider()

    /// Last good capture per window — minimized windows can't always be captured,
    /// so we fall back to whatever we saw last.
    private var cache: [CGWindowID: CGImage] = [:]

    func cached(_ id: CGWindowID) -> CGImage? { cache[id] }

    func runningApp(for item: DockItem) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let url = item.appURL?.standardizedFileURL.resolvingSymlinksInPath() {
            if let app = apps.first(where: { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == url }) {
                return app
            }
        }
        return apps.first { $0.localizedName == item.title && $0.activationPolicy == .regular }
    }

    func windows(for app: NSRunningApplication) async -> [WindowInfo] {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var axByID: [CGWindowID: AXUIElement] = [:]
        for w in axApp.elements(kAXWindowsAttribute) {
            if let id = w.windowID { axByID[id] = w }
        }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return []
        }
        let spaces = SpaceSnapshot()
        let hidden = app.isHidden
        var result: [WindowInfo] = []

        for sc in content.windows where sc.owningApplication?.processID == pid && sc.windowLayer == 0 {
            let id = sc.windowID
            let ax = axByID[id]
            let title = (sc.title?.isEmpty == false ? sc.title : ax?.title) ?? ""
            var minimized = false
            var spaceNumber: Int?

            if let ax {
                minimized = ax.bool(kAXMinimizedAttribute) ?? false
                if !Pref.wantsPalettes, let sr = ax.subrole, sr != kAXStandardWindowSubrole { continue }
            } else {
                // Not visible to AX: lives on another Space, belongs to a hidden app, or is junk.
                guard sc.frame.width >= 100, sc.frame.height >= 60, !title.isEmpty else { continue }
                let ws = spaces.spaces(for: id)
                if ws.isEmpty && !hidden { continue }
                if !hidden && !Pref.wantsAllSpaces { continue }
            }

            if !sc.isOnScreen && !minimized && !hidden {
                let ws = spaces.spaces(for: id)
                if let s = ws.first(where: { !spaces.currentSpaces.contains($0) }) {
                    spaceNumber = spaces.numberBySpace[s]
                }
                if !Pref.wantsAllSpaces && spaceNumber != nil { continue }
            }
            if (minimized || hidden) && !Pref.wantsMinimized { continue }

            result.append(WindowInfo(
                id: id, title: title, frame: sc.frame, pid: pid, ax: ax,
                isMinimized: minimized, isHidden: hidden, isOnScreen: sc.isOnScreen,
                spaceNumber: spaceNumber, scWindow: sc
            ))
        }

        sort(&result)
        let live = Set(content.windows.map(\.windowID))
        cache = cache.filter { live.contains($0.key) }
        return result
    }

    private func sort(_ list: inout [WindowInfo]) {
        switch Pref.order {
        case .creation:
            list.sort { $0.id < $1.id }
        case .title:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent:
            // CGWindowList returns windows front-to-back.
            let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
            var rank: [CGWindowID: Int] = [:]
            for (i, w) in info.enumerated() {
                if let n = w[kCGWindowNumber as String] as? CGWindowID { rank[n] = i }
            }
            list.sort {
                if $0.isMinimized != $1.isMinimized { return !$0.isMinimized }
                return (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max)
            }
        }
        if Pref.wantsCurrentSpaceFirst {
            let front = list.filter { !$0.isInvisible }
            let back = list.filter { $0.isInvisible }
            list = front + back
        }
    }

    // MARK: Capture

    func capture(_ w: WindowInfo, maxSize: CGSize) async -> CGImage? {
        // Minimized windows usually capture as blank; prefer the last real image.
        if w.isMinimized, let c = cache[w.id] { return c }
        guard let sc = w.scWindow, sc.frame.width > 0, sc.frame.height > 0 else { return cache[w.id] }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let aspect = sc.frame.width / sc.frame.height
        var width = maxSize.width * scale
        var height = width / aspect
        if height > maxSize.height * scale {
            height = maxSize.height * scale
            width = height * aspect
        }
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, Int(width))
        cfg.height = max(1, Int(height))
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        cfg.scalesToFit = true

        do {
            let filter = SCContentFilter(desktopIndependentWindow: sc)
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            if w.isMinimized, cache[w.id] != nil { return cache[w.id] }
            cache[w.id] = img
            return img
        } catch {
            return cache[w.id]
        }
    }

    // MARK: Actions

    func focus(_ w: WindowInfo, app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        if let ax = w.ax, w.isMinimized {
            ax.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        let ok = Private.focus(pid: w.pid, windowID: w.id)
        if let ax = w.ax {
            ax.set(kAXMainAttribute, kCFBooleanTrue)
            ax.perform(kAXRaiseAction)
        }
        if !ok { app.activate() }
    }

    func close(_ w: WindowInfo) {
        guard let ax = w.ax else { return }
        if let button = ax.element(kAXCloseButtonAttribute) { button.perform(kAXPressAction) }
    }

    func newWindow(for app: NSRunningApplication) {
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let src = CGEventSource(stateID: .hidSystemState)
            let keyN: CGKeyCode = 0x2D
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: keyN, keyDown: down)
                e?.flags = .maskCommand
                e?.postToPid(app.processIdentifier)
            }
        }
    }
}
