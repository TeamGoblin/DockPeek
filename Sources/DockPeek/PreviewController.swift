import AppKit
import SwiftUI

/// Hosting view that reacts to the first click even though our app is never active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PreviewPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Large "where is this window" overlay shown after hovering a thumbnail.
final class FullPreviewWindow: NSPanel {
    private let imageView = NSImageView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        contentView = imageView
    }

    func show(_ image: NSImage, windowFrame: CGRect) {
        var rect = Coords.toAppKit(windowFrame)
        // Keep it on a screen even if the real window sits partly off-screen.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main {
            rect = rect.intersection(screen.visibleFrame).isEmpty ? screen.visibleFrame.insetBy(dx: 80, dy: 80) : rect
        }
        imageView.image = image
        setFrame(rect, display: true)
        alphaValue = 0.97
        orderFrontRegardless()
    }

    func update(_ image: NSImage) { imageView.image = image }
}

@MainActor
final class PreviewController {
    let dock = DockObserver()
    private let model = PreviewModel()
    private let panel = PreviewPanel()
    private let effect = NSVisualEffectView()
    private lazy var hosting = FirstMouseHostingView(rootView: PreviewView(model: model))
    private let fullPreview = FullPreviewWindow()

    private var currentItem: DockItem?
    private var currentApp: NSRunningApplication?
    private var suppressedItem: DockItem?
    private var showWork: DispatchWorkItem?
    private var fullWork: DispatchWorkItem?
    private var trackTimer: Timer?
    private var refreshTimer: Timer?
    private var lastInside = Date()
    private var shownFullThisSession = false
    private var loadGeneration = 0
    private var clickMonitor: Any?

    private var isVisible: Bool { panel.isVisible }

    init() {
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        panel.contentView = effect
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        model.onSelect = { [weak self] w in self?.select(w) }
        model.onClose = { [weak self] w in self?.act { WindowProvider.shared.close(w) } }
        model.onNewWindow = { [weak self] in
            guard let self, let app = self.currentApp else { return }
            self.hide()
            WindowProvider.shared.newWindow(for: app)
        }
        model.onHoverChange = { [weak self] w in self?.hoverWindow(w) }
    }

    func start() {
        dock.onHoverChange = { [weak self] item in self?.dockHoverChanged(item) }
        dock.start()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.globalClick() }
        }
    }

    // MARK: Dock hover

    private func dockHoverChanged(_ item: DockItem?) {
        guard Pref.isEnabled else { hide(); return }
        guard let item else {
            suppressedItem = nil
            showWork?.cancel()
            return  // the tracking timer decides when to hide
        }
        if item == suppressedItem { return }
        suppressedItem = nil
        lastInside = Date()
        if item == currentItem && isVisible { return }

        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.show(item) }
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isVisible ? 0 : Pref.activationDelaySec), execute: work)
    }

    private func show(_ item: DockItem) async {
        guard let app = WindowProvider.shared.runningApp(for: item) else { hide(); return }
        let windows = await WindowProvider.shared.windows(for: app)
        guard dock.hovered == item, Pref.isEnabled else { return }  // mouse moved on meanwhile
        if windows.isEmpty || (Pref.wantsSkipSingle && windows.count == 1) { hide(); return }

        let wasVisible = isVisible
        let switchingApp = currentApp?.processIdentifier != app.processIdentifier
        currentItem = item
        currentApp = app
        fullWork?.cancel()
        fullPreview.orderOut(nil)
        model.hovered = nil
        model.appName = app.localizedName ?? item.title
        model.appIcon = app.icon
        if switchingApp { model.thumbnails = [:] }
        model.windows = windows
        for w in windows {
            if let c = WindowProvider.shared.cached(w.id) { model.thumbnails[w.id] = NSImage(cgImage: c, size: .zero) }
        }
        layoutPanel()
        present(animated: !wasVisible)
        loadThumbnails()
        startTimers()
    }

    // MARK: Layout

    private func dockEdge(icon: NSRect, dockRect: NSRect, screen: NSScreen) -> ArrowEdge {
        if dockRect.height > dockRect.width {
            return dockRect.midX < screen.frame.midX ? .left : .right
        }
        return .bottom
    }

    private func layoutPanel() {
        guard let item = currentItem else { return }
        let icon = Coords.toAppKit(item.frame)
        let dockRect = dock.dockFrame.map(Coords.toAppKit) ?? icon
        let center = CGPoint(x: icon.midX, y: icon.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        let edge = dockEdge(icon: icon, dockRect: dockRect, screen: screen)
        model.arrowEdge = edge
        effect.appearance = appearance()

        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let sf = screen.frame
        let gap = CGFloat(Pref.distance)
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), max(lo, hi)) }

        var origin = CGPoint.zero
        var offset: CGFloat = 0
        switch edge {
        case .bottom:
            origin.x = clamp(icon.midX - size.width / 2, sf.minX + 6, sf.maxX - size.width - 6)
            origin.y = dockRect.maxY + gap
            offset = icon.midX - origin.x
        case .left:
            origin.x = dockRect.maxX + gap
            origin.y = clamp(icon.midY - size.height / 2, sf.minY + 6, sf.maxY - size.height - 6)
            offset = origin.y + size.height - icon.midY
        case .right:
            origin.x = dockRect.minX - gap - size.width
            origin.y = clamp(icon.midY - size.height / 2, sf.minY + 6, sf.maxY - size.height - 6)
            offset = origin.y + size.height - icon.midY
        }
        model.arrowOffset = offset
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        hosting.frame = effect.bounds
        effect.maskImage = BubbleGeometry.maskImage(
            size: size, edge: edge, offset: offset,
            drawArrow: UserDefaults.standard.bool(forKey: Pref.drawTriangle))
        panel.invalidateShadow()
    }

    private func appearance() -> NSAppearance? {
        switch Pref.currentTheme {
        case .dark: return NSAppearance(named: .vibrantDark)
        case .light: return NSAppearance(named: .vibrantLight)
        case .system: return nil
        }
    }

    private func present(animated: Bool) {
        let anim = animated ? Pref.currentAnimation : .none
        switch anim {
        case .none:
            panel.alphaValue = 1
            model.popScale = 1
            panel.orderFrontRegardless()
        case .fade, .pop:
            panel.alphaValue = 0
            model.popScale = anim == .pop ? 0.92 : 1
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
            if anim == .pop {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { model.popScale = 1 }
            }
        }
    }

    // MARK: Thumbnails

    private func loadThumbnails() {
        loadGeneration += 1
        let gen = loadGeneration
        let size = Pref.thumbSize(bubble: UserDefaults.standard.double(forKey: Pref.bubbleSize))
        for w in model.windows {
            Task { @MainActor in
                guard let img = await WindowProvider.shared.capture(w, maxSize: size),
                      gen == self.loadGeneration else { return }
                self.model.thumbnails[w.id] = NSImage(cgImage: img, size: .zero)
            }
        }
    }

    private func reloadWindows() async {
        guard let app = currentApp, isVisible else { return }
        let windows = await WindowProvider.shared.windows(for: app)
        guard isVisible, app == currentApp else { return }
        if windows.isEmpty { hide(); return }
        model.windows = windows
        layoutPanel()
        loadThumbnails()
    }

    // MARK: Actions

    private func select(_ w: WindowInfo) {
        guard let app = currentApp else { return }
        WindowProvider.shared.focus(w, app: app)
        if Pref.wantsHideOnPreviewClick {
            // The mouse is over the bubble, not the Dock icon, so don't suppress the icon:
            // re-hovering it should show previews again right away.
            hide()
        }
    }

    /// Runs a window action, then refreshes the bubble once the app has reacted.
    private func act(_ action: () -> Void) {
        fullWork?.cancel()
        fullPreview.orderOut(nil)
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Task { @MainActor in await self.reloadWindows() }
        }
    }

    private func hoverWindow(_ w: WindowInfo?) {
        fullWork?.cancel()
        guard let w, Pref.wantsFullSizePreview else {
            fullPreview.orderOut(nil)
            return
        }
        let delay = shownFullThisSession ? Pref.fullPreviewSubsequentSec : Pref.fullPreviewFirstSec
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.showFull(w) }
        }
        fullWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func showFull(_ w: WindowInfo) async {
        guard model.hovered == w.id, isVisible else { return }
        shownFullThisSession = true
        if let img = model.thumbnails[w.id] { fullPreview.show(img, windowFrame: w.frame) }
        guard let big = await WindowProvider.shared.capture(w, maxSize: w.frame.size),
              model.hovered == w.id, isVisible else { return }
        let image = NSImage(cgImage: big, size: .zero)
        if fullPreview.isVisible { fullPreview.update(image) } else { fullPreview.show(image, windowFrame: w.frame) }
        model.thumbnails[w.id] = image
    }

    // MARK: Hide / tracking

    private func globalClick() {
        guard isVisible else { return }
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        if let hovered = dock.hovered {
            guard Pref.wantsHideOnDockClick else { return }
            suppressedItem = hovered
        }
        hide()
    }

    private func startTimers() {
        if trackTimer == nil {
            trackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.track() }
            }
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
        if Pref.wantsRefresh {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: Pref.refreshSec, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.loadThumbnails() }
            }
        }
    }

    private func track() {
        guard isVisible else { return }
        let loc = NSEvent.mouseLocation
        var inside = panel.frame.insetBy(dx: -4, dy: -4).contains(loc) || dock.hovered != nil
        if !inside, let item = currentItem {
            // Corridor between the dock icon and the bubble so the mouse can travel up.
            let icon = Coords.toAppKit(item.frame)
            let strip: NSRect
            switch model.arrowEdge {
            case .bottom: strip = NSRect(x: icon.minX, y: icon.minY, width: icon.width, height: panel.frame.minY - icon.minY)
            case .left: strip = NSRect(x: icon.minX, y: icon.minY, width: panel.frame.minX - icon.minX, height: icon.height)
            case .right: strip = NSRect(x: panel.frame.maxX, y: icon.minY, width: icon.maxX - panel.frame.maxX, height: icon.height)
            }
            inside = strip.insetBy(dx: -6, dy: -2).contains(loc)
        }
        if inside {
            lastInside = Date()
        } else if Date().timeIntervalSince(lastInside) > max(Pref.deactivationDelaySec, 0.15) {
            hide()
        }
    }

    func hide() {
        showWork?.cancel()
        fullWork?.cancel()
        fullPreview.orderOut(nil)
        panel.orderOut(nil)
        trackTimer?.invalidate()
        trackTimer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        currentItem = nil
        model.hovered = nil
        shownFullThisSession = false
        loadGeneration += 1
    }
}
