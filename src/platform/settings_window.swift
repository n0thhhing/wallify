import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class SettingsModel: ObservableObject {
    @Published var snapshot = WallifySettingsSnapshot()
    @Published var renderer = WallifyRendererStats()
    @Published var loginEnabled = false
    @Published var loginError: String?

    func refresh() {
        wallify_settings_get_snapshot(&snapshot)
        wallify_debug_renderer_stats(&renderer)
        loginEnabled = launchAtLoginEnabled()
    }

    func toggle(_ key: Int32, _ field: KeyPath<WallifySettingsSnapshot, Bool>) -> Binding<Bool> {
        Binding(get: { self.snapshot[keyPath: field] }, set: {
            wallify_settings_apply_bool(key, $0)
            self.refresh()
        })
    }

    func selection(_ key: Int32, _ field: KeyPath<WallifySettingsSnapshot, Int32>) -> Binding<Int32> {
        Binding(get: { self.snapshot[keyPath: field] }, set: {
            wallify_settings_apply_int(key, $0)
            self.refresh()
        })
    }

    func setLogin(_ enabled: Bool) {
        loginError = nil
        if #available(macOS 13, *) {
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                loginError = error.localizedDescription
                NSLog("Wallify: launch at login failed: %@", error.localizedDescription)
            }
        }
        refresh()
    }
}

@MainActor
private struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var page = "General"
    @State private var confirmRestore = false
    private let pages = [
        ("General", "slider.horizontal.3"), ("Appearance", "paintbrush"),
        ("Playback", "play.circle"), ("Performance", "gauge.with.dots.needle.67percent"),
        ("Desktop", "rectangle.on.rectangle")
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pages, id: \.0) { title, symbol in
                    Button { page = title; model.refresh() } label: {
                        Label(title, systemImage: symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(page == title ? Color.accentColor.opacity(0.18) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == title ? .isSelected : [])
                }
                Spacer()
                Button("Restore Defaults…") { confirmRestore = true }
            }
            .padding(18)
            .frame(width: 170)
            .background(.regularMaterial)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(page).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    pageContent
                }
                .padding(20)
                .frame(maxWidth: 650, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .alert("Restore Default Settings?", isPresented: $confirmRestore) {
            Button("Restore Defaults", role: .destructive) {
                wallify_settings_restore_defaults()
                model.refresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All Wallify preferences will be reset.") }
        .onAppear { model.refresh() }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case "General":
            section("Widget") {
                picker("Widget Size", "Choose the widget footprint.", 14, \.widget_mode,
                       ["1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2"])
                picker("Media Source", "Choose where Wallify reads playback information.", 13, \.media_source,
                       ["Now Playing", "Spotify", "Spotifast", "Auto"])
            }
            section("Idle Behavior") {
                picker("When Music Stops", "Paused tracks stay visible. Choose what happens when no track is available.", 26, \.stopped_behavior,
                       ["Show Companion", "Keep Last Track", "Hide Widget"])
                picker("Companion", model.snapshot.stopped_behavior == 0 ? "Shown when nothing is playing." : "Choose Show Companion above to enable this setting.", 15, \.idle_style,
                       ["Pixel Cat", "Banana Cat", "Spotify", "Raccoon"])
                    .disabled(model.snapshot.stopped_behavior != 0)
            }
            section("Media Keys") {
                picker("Media Key Target", "Route F7, F8 and F9 through Wallify.", 18, \.media_key_target,
                       ["Off", "Active", "Spotify", "Spotifast"])
            }
            section("Startup") {
                if #available(macOS 13, *) {
                    Toggle("Launch at Login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                    if let error = model.loginError { Text(error).foregroundColor(.red) }
                } else {
                    Text("Launch at Login requires macOS 13 or later.").foregroundColor(.secondary)
                }
            }
        case "Appearance":
            section("Material") {
                toggle("Native Glass", "Use the macOS glass material.", 5, \.native_glass)
                toggle("Artwork Glow", "Use album artwork to create ambient color.", 0, \.glow)
                picker("Glow Intensity", model.snapshot.glow ? "Control the strength of the ambient glow." : "Enable Artwork Glow to adjust its intensity.", 11, \.glow_intensity,
                       ["Low", "Normal", "High"]).disabled(!model.snapshot.glow)
                toggle("Aurora", model.snapshot.native_glass ? "Turn off Native Glass to use the animated background." : "Animated background gradient.", 1, \.aurora).disabled(model.snapshot.native_glass)
                picker("Custom Border", model.snapshot.native_glass ? "Turn off Native Glass to adjust the custom border." : "Border strength for the custom material.", 10, \.frame_strength,
                       ["Off", "Subtle", "Strong"]).disabled(model.snapshot.native_glass)
            }
            section("Artwork") {
                toggle("Artwork Border", "Add a fine edge around album artwork.", 19, \.artwork_border)
                toggle("Compact Contrast", "Add a subtle fade behind text in 1 × 1 mode.", 20, \.compact_gradient)
                picker("Artwork Corners", "Choose the album artwork corner radius.", 21, \.artwork_radius,
                       ["Soft", "Rounded", "Large"])
            }
            section("Motion") {
                toggle("Animations", "Animate resizing and state changes.", 2, \.animations)
                picker("Track Transition", model.snapshot.animations ? "Effect used when artwork changes." : "Enable Animations to see transition effects.", 16, \.track_transition,
                       ["Default", "Cinematic", "Ripple", "Card Flip", "Vinyl", "Glitch"])
                    .disabled(!model.snapshot.animations)
                picker("Animation Speed", model.snapshot.animations ? "Control the speed of transitions." : "Enable Animations to adjust their speed.", 12, \.animation_speed,
                       ["Slow", "Normal", "Fast"]).disabled(!model.snapshot.animations)
                toggle("Dim When Paused", "Lower artwork brightness while paused.", 3, \.dim_paused)
            }
        case "Playback":
            section("Visibility") {
                toggle("Hide Track Text", "Hide the title and artist labels.", 6, \.hide_text)
                toggle("Clickable Track and Artist Names", model.snapshot.hide_text ? "Turn off Hide Track Text to make names clickable." : "Open track links and artist searches when clicking their names.", 24, \.clickable_names)
                    .disabled(model.snapshot.hide_text)
                toggle("Hide Progress Bar", "Hide the playback progress bar.", 7, \.hide_progress)
                toggle("Playback Controls", "Show previous, play/pause and next.", 8, \.show_controls)
                toggle("Time Labels", "Show elapsed and remaining time.", 9, \.show_timestamps)
            }
            section("Progress") {
                if #available(macOS 14.2, *) {
                    toggle("System Audio Waveform", "Show live audio along the progress bar. Requires system audio capture permission; audio is never saved.", 23, \.waveform)
                        .disabled(model.snapshot.hide_progress || !model.snapshot.animations)
                    if model.snapshot.hide_progress || !model.snapshot.animations {
                        Text("To use Waveform, show the progress bar in Playback and enable Animations in Appearance.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Text(model.snapshot.waveform ? audioWaveform.status : "Off").font(.caption).foregroundColor(.secondary)
                    if model.snapshot.waveform {
                        Button("Open Capture Permissions") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                } else { Text("Audio waveform requires macOS 14.2 or later.").foregroundColor(.secondary) }
                picker("Progress Thickness", "Choose the visual weight of the progress bar.", 22, \.progress_thickness,
                       ["Thin", "Standard", "Thick"])
            }
            section("Typography") {
                picker("Font Size", "Scale title, artist and playback labels.", 17, \.font_scale,
                       ["Small", "Normal", "Large"])
            }
        case "Performance":
            section("Renderer") {
                Text(model.renderer.ready != 0 ? "Metal ready • \(deviceName)" : "Metal renderer unavailable")
                if model.renderer.profiling != 0 {
                    Text(String(format: "Scene %.3f ms • GPU %.3f ms • %.2f MiB textures",
                                model.renderer.scene_ms, model.renderer.gpu_ms,
                                Double(model.renderer.texture_bytes) / 1048576))
                } else {
                    Text("Performance measurements are off.")
                        .foregroundColor(.secondary)
                }
                Button("Refresh") { model.refresh() }
            }
            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 20) {
                    section("Diagnostics") {
                        toggle("Debug Console", "Show live Wallify runtime and diagnostics.", 4, \.debug_hud)
                        Button("Open Inspector") { wallify_open_inspector() }
                        Text("For CPU/GPU measurements, run from the project folder:")
                            .font(.caption).foregroundColor(.secondary)
                        Text("WALLIFY_PROFILE=1 ./run -d -f")
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    section("Configuration") {
                        Text(configURL.path).font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([configURL]) }
                            Button("Open Config") { NSWorkspace.shared.open(configURL) }
                        }
                    }
                }
                .padding(.top, 12)
            }
        default:
            section("Position") {
                toggle("Lock Position", "Prevent accidental dragging. Playback controls remain usable.", 25, \.position_locked)
                if !terminalMode {
                    Text("Display: \(WidgetPanel.current?.screen?.localizedName ?? "Unavailable")")
                    Menu("Move to Display") {
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                            Button("\(index + 1) — \(screen.localizedName)") { moveWidgetToDisplay(screen); model.refresh() }
                        }
                    }
                }
                Text("Margins: \(model.snapshot.margin_left), \(model.snapshot.margin_top) • Grid: \(model.snapshot.grid_x), \(model.snapshot.grid_y)")
                Text("Drag within this display, or use Move to Display. Placement is remembered separately for each monitor.").foregroundColor(.secondary)
                Button("Reset Position") { wallify_settings_reset_position(); model.refresh() }
            }
        }
    }

    private var configURL: URL { URL(fileURLWithPath: String(cString: wallify_settings_path())) }
    private var deviceName: String {
        var name = model.renderer.device_name
        return withUnsafePointer(to: &name) {
            $0.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(4)
        } label: { Text(title).accessibilityAddTraits(.isHeader) }
    }

    private func toggle(_ title: String, _ detail: String, _ key: Int32,
                        _ field: KeyPath<WallifySettingsSnapshot, Bool>) -> some View {
        Toggle(isOn: model.toggle(key, field)) { label(title, detail) }
            .toggleStyle(.switch)
    }

    private func picker(_ title: String, _ detail: String, _ key: Int32,
                        _ field: KeyPath<WallifySettingsSnapshot, Int32>, _ options: [String]) -> some View {
        HStack {
            label(title, detail)
            Spacer(minLength: 12)
            Picker(title, selection: model.selection(key, field)) {
                ForEach(options.indices, id: \.self) { Text(options[$0]).tag(Int32($0)) }
            }
            .labelsHidden().frame(width: 160).accessibilityLabel(title)
        }
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail).font(.caption).foregroundColor(.secondary)
        }
    }
}

@MainActor
private final class SettingsWindow {
    static let shared = SettingsWindow()
    let model = SettingsModel()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
            panel.title = "Wallify Settings"
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.tabbingMode = .disallowed
            panel.collectionBehavior = .fullScreenAuxiliary
            panel.contentView = NSHostingView(rootView: SettingsView(model: model))
            panel.contentMinSize = NSSize(width: 720, height: 500)
            panel.center()
            panel.setFrameAutosaveName("Wallify.SettingsWindow")
            window = panel
        }
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.orderOut(nil) }
    func refreshIfVisible() { if window?.isVisible == true { model.refresh() } }
}

@_cdecl("wallify_show_settings_window")
public func showSettingsWindow() { DispatchQueue.main.async { SettingsWindow.shared.show() } }

@_cdecl("wallify_close_settings_window")
public func closeSettingsWindow() { DispatchQueue.main.async { SettingsWindow.shared.close() } }

@_cdecl("wallify_settings_notify_position_changed")
public func settingsPositionChanged() { refreshSettingsUI() }

@_cdecl("wallify_refresh_settings_ui")
public func refreshSettingsUI() { DispatchQueue.main.async { SettingsWindow.shared.refreshIfVisible() } }

@_cdecl("wallify_has_settings_flag")
public func hasSettingsFlag() -> Bool {
    ProcessInfo.processInfo.arguments.contains { $0 == "--settings" || $0 == "-s" }
}

@_cdecl("wallify_launch_at_login_enabled")
public func launchAtLoginEnabled() -> Bool {
    if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
    return false
}

@_cdecl("wallify_launch_at_login_set")
public func setLaunchAtLogin(_ enabled: Bool) -> Bool {
    if #available(macOS 13, *) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch { NSLog("Wallify: launch at login failed: %@", error.localizedDescription) }
    }
    return false
}
