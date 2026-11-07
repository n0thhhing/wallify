import AppKit
import Combine
import CoreServices
import SwiftUI

// Automation permission for Apple Events to Spotify. `prompt` shows the system dialog when undecided,
// which blocks, so callers run it off the main thread.
enum AutomationStatus: Equatable { case granted, denied, undecided, notRunning }

func spotifyAutomationStatus(prompt: Bool) -> AutomationStatus {
    var target = AEAddressDesc()
    let bundle = Array(spotifyBundleIdentifier.utf8)
    guard AECreateDesc(typeApplicationBundleID, bundle, bundle.count, &target) == noErr else { return .undecided }
    defer { AEDisposeDesc(&target) }
    return automationStatus(AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, prompt))
}

func automationStatus(_ status: OSStatus) -> AutomationStatus {
    switch Int(status) {
    case Int(noErr): return .granted
    case Int(errAEEventNotPermitted): return .denied
    case Int(procNotFound): return .notRunning
    default: return .undecided
    }
}

@MainActor
private final class OnboardingModel: ObservableObject {
    @Published var automation = AutomationStatus.undecided
    @Published var waveform = false
    @Published var account = false

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = spotifyAutomationStatus(prompt: false)
            DispatchQueue.main.async { self.automation = status }
        }
        var snapshot = WallifySettingsSnapshot()
        wallify_settings_get_snapshot(&snapshot)
        waveform = snapshot.waveform
        account = spotifyAccount.connected
    }

    func allowAutomation() {
        guard automation != .denied else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            return
        }
        if automation == .notRunning { openSpotify() }
        DispatchQueue.global(qos: .userInitiated).async {
            let status = spotifyAutomationStatus(prompt: true)
            DispatchQueue.main.async { self.automation = status }
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let close: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Wallify").font(.title2.bold())
                Text("Wallify needs a few permissions to show and control your music. You can change these later in Settings.")
                    .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            row("music.note", "Control Spotify", "Lets Wallify read the current track and play, pause and skip.", automationText) {
                Button(automationButton) { model.allowAutomation() }.disabled(model.automation == .granted)
            }
            row("waveform", "System Audio (optional)", "Draws the live waveform on the progress bar. Audio is never saved.",
                model.waveform ? "On; macOS asks for access the first time it starts." : "Off") {
                Button(model.waveform ? "Turn Off" : "Turn On") {
                    wallify_settings_apply_bool(23, !model.waveform); model.refresh()
                }
            }
            row("person.crop.circle", "Spotify Account (optional)", "Adds the Like button and Up Next.",
                model.account ? "Connected" : "Not connected") {
                Button("Open Settings…") { showSettingsWindow() }.disabled(model.account)
            }
            HStack {
                Spacer()
                Button("Done") { close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { model.refresh() }
        .onReceive(timer) { _ in model.refresh() }  // statuses change in System Settings while this is open
    }

    private var automationText: String {
        switch model.automation {
        case .granted: return "Allowed"
        case .denied: return "Not allowed. Turn on Spotify for Wallify in System Settings → Privacy & Security → Automation."
        case .notRunning: return "Open Spotify to set this up."
        case .undecided: return "Not set up yet"
        }
    }
    private var automationButton: String {
        model.automation == .denied ? "Open Settings…" : model.automation == .granted ? "Allowed" : "Allow…"
    }

    private func row<Action: View>(_ symbol: String, _ title: String, _ detail: String, _ status: String,
                                   @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundColor(.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(status).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action()
        }
    }
}

@MainActor
private final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private let model = OnboardingModel()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled, .closable],
                                 backing: .buffered, defer: false)
            panel.title = "Set Up Wallify"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: OnboardingView(model: model) { [weak panel] in panel?.close() })
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private let onboardingShownKey = "OnboardingShown"

@MainActor func showOnboarding() { OnboardingWindow.shared.show() }

// Shown once, on the first launch.
@MainActor func showOnboardingIfNeeded() {
    guard !UserDefaults.standard.bool(forKey: onboardingShownKey) else { return }
    UserDefaults.standard.set(true, forKey: onboardingShownKey)
    showOnboarding()
}
