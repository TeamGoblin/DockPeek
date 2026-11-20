import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab().tabItem { Label("Appearance", systemImage: "paintbrush") }
            AdvancedTab().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
        .padding(.top, 8)
    }
}

/// Number field + stepper bound to a Double preference.
struct NumberRow: View {
    let label: String
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    @AppStorage private var value: Double

    init(_ label: String, key: String, unit: String, range: ClosedRange<Double>, step: Double) {
        self.label = label
        self.unit = unit
        self.range = range
        self.step = step
        _value = AppStorage(wrappedValue: (Pref.defaults[key] as? Double) ?? 0, key)
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .onChange(of: value) { _, v in
                        let clamped = min(max(v, range.lowerBound), range.upperBound)
                        if clamped != v { value = clamped }
                    }
                Stepper("", value: $value, in: range, step: step).labelsHidden()
                Text(unit).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
            }
        }
    }
}

struct GeneralTab: View {
    @AppStorage(Pref.enabled) private var enabled = true
    @AppStorage(Pref.includeAllSpaces) private var allSpaces = true
    @AppStorage(Pref.includeMinimized) private var minimized = true
    @AppStorage(Pref.includePalettes) private var palettes = false
    @AppStorage(Pref.orderBy) private var orderBy = OrderBy.creation.rawValue
    @AppStorage(Pref.currentSpaceFirst) private var currentFirst = false
    @AppStorage(Pref.fullSizePreview) private var fullSize = true
    @AppStorage(Pref.hideOnDockClick) private var hideDock = true
    @AppStorage(Pref.hideOnPreviewClick) private var hidePreview = true
    @AppStorage(Pref.skipSingleWindow) private var skipSingle = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable window previews", isOn: $enabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                NumberRow("Activation delay", key: Pref.activationDelay, unit: "ms", range: 0...2000, step: 50)
            }
            Section("Include") {
                Toggle("Windows from all Spaces", isOn: $allSpaces)
                Toggle("Minimized / hidden windows", isOn: $minimized)
                Toggle("Palettes and utility windows", isOn: $palettes)
            }
            Section("Order") {
                Picker("Order by", selection: $orderBy) {
                    ForEach(OrderBy.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Put current Space windows first", isOn: $currentFirst)
            }
            Section("Behaviour") {
                Toggle("Show full size preview on hover", isOn: $fullSize)
                Toggle("Hide when a Dock item is clicked", isOn: $hideDock)
                Toggle("Hide when a preview is clicked", isOn: $hidePreview)
                Toggle("Don't show if the app has only one window", isOn: $skipSingle)
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceTab: View {
    @AppStorage(Pref.theme) private var theme = Theme.dark.rawValue
    @AppStorage(Pref.showAppName) private var appName = true
    @AppStorage(Pref.showCloseButton) private var closeButton = true
    @AppStorage(Pref.showMinimizedIndicator) private var indicator = true
    @AppStorage(Pref.bubbleSize) private var bubbleSize = 0.3
    @AppStorage(Pref.perRow) private var perRow = 5
    @AppStorage(Pref.animation) private var animation = PopupAnimation.fade.rawValue
    @AppStorage(Pref.drawTriangle) private var triangle = true
    @AppStorage(Pref.drawHighlight) private var highlight = true
    @AppStorage(Pref.shadeInvisible) private var shade = true

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Popup animation", selection: $animation) {
                    ForEach(PopupAnimation.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("Elements") {
                Toggle("Application name", isOn: $appName)
                Toggle("Close button", isOn: $closeButton)
                Toggle("Space number / hidden indicator", isOn: $indicator)
            }
            Section("Size & layout") {
                NumberRow("Distance from the Dock", key: Pref.dockDistance, unit: "px", range: 0...60, step: 1)
                LabeledContent("Bubble size") {
                    HStack {
                        Text("Small").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $bubbleSize, in: 0...1)
                        Text("Large").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 260)
                }
                Stepper("Previews per row: \(perRow)", value: $perRow, in: 1...10)
            }
            Section("Style") {
                Toggle("Draw triangle below bubble", isOn: $triangle)
                Toggle("Draw highlight gradient", isOn: $highlight)
                Toggle("Shade invisible windows (minimized, hidden, other Spaces)", isOn: $shade)
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedTab: View {
    @AppStorage(Pref.refreshThumbnails) private var refresh = false
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var screenOK = CGPreflightScreenCaptureAccess()
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Timing") {
                NumberRow("Preview deactivation delay", key: Pref.deactivationDelay, unit: "ms", range: 0...3000, step: 50)
                NumberRow("Full size preview delay (first)", key: Pref.fullPreviewDelayFirst, unit: "ms", range: 0...5000, step: 50)
                NumberRow("Full size preview delay (subsequent)", key: Pref.fullPreviewDelaySubsequent, unit: "ms", range: 0...5000, step: 50)
            }
            Section("Thumbnails") {
                Toggle("Refresh thumbnails while the bubble is open", isOn: $refresh)
                NumberRow("Refresh every", key: Pref.refreshInterval, unit: "s", range: 0.25...10, step: 0.25)
                    .disabled(!refresh)
            }
            Section("Permissions") {
                permissionRow("Accessibility", ok: axTrusted, pane: "Privacy_Accessibility")
                permissionRow("Screen Recording", ok: screenOK, pane: "Privacy_ScreenCapture")
            }
            Section {
                Button("Restore Defaults") { Pref.restoreDefaults() }
            }
        }
        .formStyle(.grouped)
        .onReceive(poll) { _ in
            axTrusted = AXIsProcessTrusted()
            screenOK = CGPreflightScreenCaptureAccess()
        }
    }

    private func permissionRow(_ name: String, ok: Bool, pane: String) -> some View {
        LabeledContent(name) {
            HStack {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? .green : .orange)
                Text(ok ? "Granted" : "Not granted").foregroundStyle(.secondary)
                if !ok {
                    Button("Open Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("DockPeek").font(.title.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Window previews for the Dock. Native on Apple Silicon.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Quit DockPeek") { NSApp.terminate(nil) }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "DockPeek Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
