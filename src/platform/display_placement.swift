import AppKit
import ColorSync

struct DisplayPlacement: Codable, Equatable {
    var left: Int32 = 8, top: Int32 = 8

    func clamped(to visible: NSSize, widget: NSSize) -> DisplayPlacement {
        DisplayPlacement(left: Int32(max(0, min(Double(left), max(0, visible.width - widget.width)))),
                         top: Int32(max(0, min(Double(top), max(0, visible.height - widget.height)))))
    }
}

struct DisplayPlacements: Codable {
    var preferredDisplay: String?
    var positions: [String: DisplayPlacement] = [:]

    func connectedDisplay(_ ids: [String]) -> String? {
        if let preferredDisplay, ids.contains(preferredDisplay) { return preferredDisplay }
        return ids.first
    }

    mutating func remember(_ id: String, placement: DisplayPlacement) {
        positions[id] = placement
        if preferredDisplay == nil { preferredDisplay = id }
    }
}

@MainActor private var displayPlacements = DisplayPlacements()
@MainActor private var activeDisplay: String?
@MainActor private var placementsURL: URL?

@MainActor func widgetDisplayID(_ screen: NSScreen) -> String? {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
          let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
    // Display numbers and screen-array order can change after reconnecting.
    // ColorSync's display UUID lets the saved position follow the same monitor.
    return CFUUIDCreateString(nil, uuid) as String
}

@MainActor func loadWidgetDisplayPlacements() {
    guard !terminalMode else { return }
    let url = URL(fileURLWithPath: String(cString: wallify_settings_path())).deletingLastPathComponent()
        .appendingPathComponent("display-placements.json")
    placementsURL = url
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 131_072 else { throw CocoaError(.fileReadTooLarge) }
        let saved = try JSONDecoder().decode(DisplayPlacements.self, from: bytes)
        guard saved.positions.count <= 512 else { throw CocoaError(.fileReadCorruptFile) }
        displayPlacements = saved
    } catch { NSLog("Wallify: display placements could not be loaded: %@", error.localizedDescription) }
}

@MainActor func widgetPlacementScreen() -> NSScreen? {
    guard placementsURL != nil else { return WidgetPanel.current?.screen ?? NSScreen.main }
    let screens = NSScreen.screens
    if let activeDisplay, let screen = screens.first(where: { widgetDisplayID($0) == activeDisplay }) { return screen }
    let id = displayPlacements.connectedDisplay(screens.compactMap { widgetDisplayID($0) })
    return screens.first(where: { widgetDisplayID($0) == id }) ?? screens.first
}

@MainActor func rememberWidgetDisplayPlacement() {
    guard let url = placementsURL, let panel = WidgetPanel.current, let screen = widgetPlacementScreen(),
          let id = widgetDisplayID(screen) else { return }
    sceneLock.lock()
    let state = widgetStatePointer().pointee
    sceneLock.unlock()
    // Settings and snap animations can save before AppKit handles the queued
    // move. Persist the requested margins, rather than yesterday's window frame.
    let placement = DisplayPlacement(left: state.widget_margin_left, top: state.widget_margin_top)
        .clamped(to: screen.visibleFrame.size, widget: panel.frame.size)
    displayPlacements.remember(id, placement: placement)
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(displayPlacements).write(to: url, options: .atomic)
    } catch { NSLog("Wallify: display placements could not be saved: %@", error.localizedDescription) }
}

@MainActor func restoreWidgetDisplayPlacement(fallback: DisplayPlacement = DisplayPlacement()) {
    guard let panel = WidgetPanel.current else { return }
    activeDisplay = nil
    guard let screen = widgetPlacementScreen() else { return }
    activeDisplay = widgetDisplayID(screen)
    let saved = activeDisplay.flatMap { displayPlacements.positions[$0] } ?? fallback
    let placement = saved.clamped(to: screen.visibleFrame.size, widget: panel.frame.size)
    sceneLock.lock()
    let state = widgetStatePointer()
    state.pointee.global_panel_dragging = false
    state.pointee.panel_snap_active = false; state.pointee.panel_save_after_snap = false
    state.pointee.widget_margin_left = placement.left; state.pointee.widget_margin_top = placement.top
    sceneLock.unlock()
    moveWidgetPanelNow(placement.left, placement.top)
    widget_hide_snap_outline()
    settingsPositionChanged()
    requestWidgetFrame()
}

@MainActor func moveWidgetToDisplay(_ screen: NSScreen) {
    guard let id = widgetDisplayID(screen) else { return }
    rememberWidgetDisplayPlacement()
    displayPlacements.preferredDisplay = id
    restoreWidgetDisplayPlacement()
    rememberWidgetDisplayPlacement()
    saveConfiguration()
}
