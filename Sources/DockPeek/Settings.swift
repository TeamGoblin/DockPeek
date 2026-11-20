import Foundation

/// UserDefaults keys + typed accessors. Views use @AppStorage with these keys
/// so the preview bubble reacts live to changes made in Settings.
enum Pref {
    // General
    static let enabled = "enabled"
    static let activationDelay = "activationDelay"            // ms
    static let includeAllSpaces = "includeAllSpaces"
    static let includeMinimized = "includeMinimized"
    static let includePalettes = "includePalettes"
    static let orderBy = "orderBy"                            // OrderBy.rawValue
    static let currentSpaceFirst = "currentSpaceFirst"
    static let fullSizePreview = "fullSizePreview"
    static let hideOnDockClick = "hideOnDockClick"
    static let hideOnPreviewClick = "hideOnPreviewClick"
    static let skipSingleWindow = "skipSingleWindow"

    // Appearance
    static let theme = "theme"                                // Theme.rawValue
    static let showAppName = "showAppName"
    static let showCloseButton = "showCloseButton"
    static let showMinimizedIndicator = "showMinimizedIndicator"
    static let dockDistance = "dockDistance"                  // px
    static let bubbleSize = "bubbleSize"                      // 0...1
    static let perRow = "perRow"
    static let animation = "animation"                        // PopupAnimation.rawValue
    static let drawTriangle = "drawTriangle"
    static let drawHighlight = "drawHighlight"
    static let shadeInvisible = "shadeInvisible"

    // Advanced
    static let deactivationDelay = "deactivationDelay"        // ms
    static let fullPreviewDelayFirst = "fullPreviewDelayFirst"            // ms
    static let fullPreviewDelaySubsequent = "fullPreviewDelaySubsequent"  // ms
    static let refreshThumbnails = "refreshThumbnails"
    static let refreshInterval = "refreshInterval"            // s

    static let defaults: [String: Any] = [
        enabled: true,
        activationDelay: 0.0,
        includeAllSpaces: true,
        includeMinimized: true,
        includePalettes: false,
        orderBy: OrderBy.creation.rawValue,
        currentSpaceFirst: false,
        fullSizePreview: true,
        hideOnDockClick: true,
        hideOnPreviewClick: true,
        skipSingleWindow: false,

        theme: Theme.dark.rawValue,
        showAppName: true,
        showCloseButton: true,
        showMinimizedIndicator: true,
        dockDistance: 0.0,
        bubbleSize: 0.3,
        perRow: 5,
        animation: PopupAnimation.fade.rawValue,
        drawTriangle: true,
        drawHighlight: true,
        shadeInvisible: true,

        deactivationDelay: 0.0,
        fullPreviewDelayFirst: 500.0,
        fullPreviewDelaySubsequent: 200.0,
        refreshThumbnails: false,
        refreshInterval: 1.0,
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }

    static func restoreDefaults() {
        for key in defaults.keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    private static var d: UserDefaults { .standard }
    static var isEnabled: Bool { d.bool(forKey: enabled) }
    static var activationDelaySec: Double { max(0, d.double(forKey: activationDelay)) / 1000 }
    static var deactivationDelaySec: Double { max(0, d.double(forKey: deactivationDelay)) / 1000 }
    static var fullPreviewFirstSec: Double { max(0, d.double(forKey: fullPreviewDelayFirst)) / 1000 }
    static var fullPreviewSubsequentSec: Double { max(0, d.double(forKey: fullPreviewDelaySubsequent)) / 1000 }
    static var wantsAllSpaces: Bool { d.bool(forKey: includeAllSpaces) }
    static var wantsMinimized: Bool { d.bool(forKey: includeMinimized) }
    static var wantsPalettes: Bool { d.bool(forKey: includePalettes) }
    static var order: OrderBy { OrderBy(rawValue: d.string(forKey: orderBy) ?? "") ?? .creation }
    static var wantsCurrentSpaceFirst: Bool { d.bool(forKey: currentSpaceFirst) }
    static var wantsFullSizePreview: Bool { d.bool(forKey: fullSizePreview) }
    static var wantsHideOnDockClick: Bool { d.bool(forKey: hideOnDockClick) }
    static var wantsHideOnPreviewClick: Bool { d.bool(forKey: hideOnPreviewClick) }
    static var wantsSkipSingle: Bool { d.bool(forKey: skipSingleWindow) }
    static var currentTheme: Theme { Theme(rawValue: d.string(forKey: theme) ?? "") ?? .dark }
    static var distance: Double { d.double(forKey: dockDistance) }
    static var currentAnimation: PopupAnimation { PopupAnimation(rawValue: d.string(forKey: animation) ?? "") ?? .fade }
    static var wantsRefresh: Bool { d.bool(forKey: refreshThumbnails) }
    static var refreshSec: Double { max(0.25, d.double(forKey: refreshInterval)) }

    /// Thumbnail box size derived from the "Bubble size" slider.
    static func thumbSize(bubble: Double) -> CGSize {
        let w = 140 + bubble * 260
        return CGSize(width: w.rounded(), height: (w * 0.62).rounded())
    }
}

enum OrderBy: String, CaseIterable, Identifiable {
    case creation, recent, title
    var id: String { rawValue }
    var label: String {
        switch self {
        case .creation: return "Creation time"
        case .recent: return "Most recently used"
        case .title: return "Window title"
        }
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: return "Vibrant Dark"
        case .light: return "Vibrant Light"
        case .system: return "Match System"
        }
    }
}

enum PopupAnimation: String, CaseIterable, Identifiable {
    case none, fade, pop
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .fade: return "Fade in"
        case .pop: return "Snap in"
        }
    }
}
