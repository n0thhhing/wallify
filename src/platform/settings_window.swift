import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class SettingsModel: ObservableObject {
    @Published var snapshot = WallifySettingsSnapshot()
    @Published var renderer = WallifyRendererStats()
    @Published var loginEnabled = false
    @Published var loginError: String?
    @Published var accountConnected = false
    @Published var accountError: String?

    func refresh() {
        wallify_settings_get_snapshot(&snapshot)
        wallify_debug_renderer_stats(&renderer)
        loginEnabled = launchAtLoginEnabled()
        accountConnected = spotifyAccount.connected
        accountError = spotifyAccount.lastError
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
    @State private var page: String? = "General"
    @State private var confirmRestore = false
    @AppStorage(spotifyClientIDKey) private var clientID = ""
    private let pages = [
        ("General", "slider.horizontal.3"), ("Appearance", "paintbrush"),
        ("Playback", "play.circle"), ("Desktop", "rectangle.on.rectangle"),
        ("Advanced", "wrench.and.screwdriver")
    ]

    var body: some View {
        Group {
            if #available(macOS 13, *) {
                // The system split view gives the modern floating sidebar and puts the page title in the toolbar.
                NavigationSplitView {
                    sidebar.navigationSplitViewColumnWidth(200).modifier(NoSidebarToggle())
                } detail: {
                    Form { pageContent }.formStyle(.grouped).navigationTitle(page ?? "General")
                }
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 190)
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(page ?? "General").font(.title2.bold()).padding([.horizontal, .top], 20)
                            .accessibilityAddTraits(.isHeader)
                        ScrollView { Form { pageContent }.padding(20) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .onChange(of: page) { _ in model.refresh() }
        .alert("Restore Default Settings?", isPresented: $confirmRestore) {
            Button("Restore Defaults", role: .destructive) {
                wallify_settings_restore_defaults()
                model.refresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All Wallify preferences will be reset.") }
        .onAppear { model.refresh() }
    }

    private var sidebar: some View {
        List(selection: $page) {
            ForEach(pages, id: \.0) { title, symbol in Label(title, systemImage: symbol).tag(title) }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private var pageContent: some View {
        switch page ?? "General" {
        case "General":
            section("Widget") {
                picker(14, model.snapshot.position_locked ? "Turn off Lock Position to change the widget size." : "")
                    .disabled(model.snapshot.position_locked)
                picker(13, "Where Wallify reads what's playing.")
            }
            section("Idle Behavior", footer: "Paused tracks always stay visible.") {
                picker(26, "")
                picker(15, model.snapshot.stopped_behavior == 0 ? "" : "Choose Show Companion above to use this.")
                    .disabled(model.snapshot.stopped_behavior != 0)
            }
            section("Media Keys") {
                picker(18, "Route F7, F8 and F9 through Wallify.")
            }
            section("Spotify Account", footer: "Needed for Like and Up Next. In your Spotify app's settings, add \(SpotifyAccount.redirectURI) as a redirect URI.") {
                TextField("Client ID", text: $clientID, prompt: Text("32-character client ID"))
                buttonRow("Account", model.accountError ?? (model.accountConnected ? "Connected" : "Not connected"),
                          model.accountConnected ? "Disconnect" : "Connect…") {
                    if model.accountConnected { spotifyAccount.disconnect() } else { spotifyAccount.connect { NSWorkspace.shared.open($0) } }
                    model.refresh()
                }
                .disabled(!model.accountConnected && !validSpotifyClientID(clientID.trimmingCharacters(in: .whitespaces)))
            }
            section("Startup") {
                if #available(macOS 13, *) {
                    Toggle(isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })) {
                        label("Launch at Login", model.loginError ?? "")
                    }.toggleStyle(.switch)
                    buttonRow("Login Items", "", "Open…") { SMAppService.openSystemSettingsLoginItems() }
                    buttonRow("Permissions", "Spotify control, system audio and your Spotify account.", "Review…") { showOnboarding() }
                } else {
                    Text("Launch at Login requires macOS 13 or later.").foregroundColor(.secondary)
                }
            }
        case "Appearance":
            section("Material") {
                toggle(5, "")
                toggle(0, "Ambient color from the album artwork.")
                picker(11, model.snapshot.glow ? "" : "Turn on Artwork Glow to adjust this.").disabled(!model.snapshot.glow)
                toggle(1, model.snapshot.native_glass ? "Turn off Native Glass to use this." : "Animated background gradient.")
                    .disabled(model.snapshot.native_glass)
                picker(10, model.snapshot.native_glass ? "Turn off Native Glass to use this." : "").disabled(model.snapshot.native_glass)
            }
            section("Artwork") {
                toggle(19, "")
                toggle(20, "A subtle fade behind text in 1 × 1 mode.")
                picker(21, "")
            }
            section("Motion") {
                toggle(2, "")
                picker(16, model.snapshot.animations ? "" : "Turn on Animations to use this.")
                    .disabled(!model.snapshot.animations)
                picker(12, model.snapshot.animations ? "" : "Turn on Animations to use this.").disabled(!model.snapshot.animations)
                toggle(3, "")
            }
        case "Playback":
            section("Visibility") {
                toggle(6, "")
                toggle(24, model.snapshot.hide_text ? "Turn off Hide Track Text to use this." : "Open the track or search the artist when clicked.")
                    .disabled(model.snapshot.hide_text)
                toggle(7, "")
                toggle(8, "")
                toggle(9, "")
            }
            section("Progress") {
                if #available(macOS 14.2, *) {
                    let blocked = model.snapshot.hide_progress || !model.snapshot.animations
                    toggle(23, blocked ? "Needs the progress bar shown and Animations on." :
                           model.snapshot.waveform ? audioWaveform.status : "Live audio on the progress bar. Nothing is saved.")
                        .disabled(blocked)
                    if model.snapshot.waveform && !blocked {
                        buttonRow("Audio Capture Permission", "", "Open…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                } else { Text("Audio waveform requires macOS 14.2 or later.").foregroundColor(.secondary) }
                picker(22, "")
            }
            section("Scrolling") {
                picker(27, "Scroll on the widget to change the volume or seek.")
            }
            section("Text") {
                toggle(28, "Shown under the progress bar in place of the times. Sends the title and artist to lrclib.net.")
                picker(17, "")
            }
        case "Desktop":
            section("Position", footer: "Drag the widget to move it. Placement is remembered for each display.") {
                toggle(25, "Prevents dragging and resizing. Playback controls stay usable.")
                if !terminalMode {
                    Picker(selection: Binding(get: { NSScreen.screens.firstIndex { $0 == WidgetPanel.current?.screen } ?? 0 }, set: {
                        if NSScreen.screens.indices.contains($0) { moveWidgetToDisplay(NSScreen.screens[$0]); model.refresh() }
                    })) {
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in Text(screen.localizedName).tag(index) }
                    } label: { Text("Display") }
                }
                buttonRow("Reset Position", "Back to the top-left corner of its display.", "Reset") {
                    wallify_settings_reset_position(); model.refresh()
                }
            }
        default:
            section("Renderer", footer: model.renderer.profiling != 0 ? nil : "Launch with WALLIFY_PROFILE=1 ./run -d -f to measure frame times.") {
                valueRow("Metal", model.renderer.ready != 0 ? deviceName : "Unavailable")
                if model.renderer.profiling != 0 {
                    valueRow("Frame", String(format: "Scene %.3f ms • GPU %.3f ms • %.2f MiB textures",
                                             model.renderer.scene_ms, model.renderer.gpu_ms, Double(model.renderer.texture_bytes) / 1048576))
                    buttonRow("Measurements", "", "Refresh") { model.refresh() }
                }
            }
            section("Diagnostics") {
                toggle(4, "Live runtime and diagnostics.")
                buttonRow("Inspector", "", "Open") { wallify_open_inspector() }
                valueRow("Build", WallifyBuildIdentity.label)
                valueRow("Placement", "Margins \(model.snapshot.margin_left), \(model.snapshot.margin_top) • Grid \(model.snapshot.grid_x), \(model.snapshot.grid_y)")
            }
            section("Configuration", footer: configURL.path) {
                if #available(macOS 13, *) {
                    LabeledContent("Config File") {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([configURL]) }
                        Button("Open") { NSWorkspace.shared.open(configURL) }
                    }
                } else {
                    buttonRow("Config File", "", "Open") { NSWorkspace.shared.open(configURL) }
                }
                buttonRow("Restore Defaults", "Reset every Wallify preference.", "Restore…", role: .destructive) { confirmRestore = true }
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

    private func section<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title).accessibilityAddTraits(.isHeader)
        } footer: {
            if let footer { Text(footer).textSelection(.enabled) }
        }
    }

    // Titles, option labels and snapshot fields come from the shared settings table.
    @ViewBuilder private func toggle(_ key: Int32, _ detail: String) -> some View {
        if let spec = settingSpec(key), case .bool(_, let field) = spec.storage {
            Toggle(isOn: model.toggle(key, field)) { label(spec.title, detail) }
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder private func picker(_ key: Int32, _ detail: String) -> some View {
        if let spec = settingSpec(key), case .choice(_, let field) = spec.storage {
            Picker(selection: model.selection(key, field)) {
                ForEach(spec.labels.indices, id: \.self) { Text(spec.labels[$0]).tag(Int32($0)) }
            } label: { label(spec.title, detail) }
            .accessibilityLabel(spec.title)
        }
    }

    // A labeled row with its action button on the trailing edge, as in System Settings.
    @ViewBuilder private func buttonRow(_ title: String, _ detail: String, _ button: String,
                                        role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        if #available(macOS 13, *) {
            LabeledContent { Button(button, role: role, action: action) } label: { label(title, detail) }
        } else {
            HStack { label(title, detail); Spacer(minLength: 12); Button(button, role: role, action: action) }
        }
    }

    @ViewBuilder private func valueRow(_ title: String, _ value: String) -> some View {
        if #available(macOS 13, *) {
            LabeledContent(title) { Text(value).textSelection(.enabled) }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(title); Spacer(minLength: 12)
                Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
        }
    }

    // On macOS 13+ a grouped form styles a second Text as the row's subtitle.
    @ViewBuilder private func label(_ title: String, _ detail: String) -> some View {
        if #available(macOS 13, *) {
            Text(title)
            if !detail.isEmpty { Text(detail) }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundColor(.secondary) }
            }
        }
    }
}

// A settings sidebar should not collapse, matching System Settings.
private struct NoSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) { content.toolbar(removing: .sidebarToggle) } else { content }
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
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                 backing: .buffered, defer: false)
            panel.title = "Wallify Settings"
            panel.toolbarStyle = .unified
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.tabbingMode = .disallowed
            panel.collectionBehavior = .fullScreenAuxiliary
            // A hosting controller bridges the split view's toolbar and title into the window.
            panel.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            panel.contentMinSize = NSSize(width: 720, height: 500)
            panel.center()
            panel.setFrameAutosaveName("Wallify.SettingsWindow")
            window = panel
        }
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshIfVisible() { if window?.isVisible == true { model.refresh() } }
}

@_cdecl("wallify_show_settings_window")
public func showSettingsWindow() { DispatchQueue.main.async { SettingsWindow.shared.show() } }

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
