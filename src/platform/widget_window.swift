import AppKit

@MainActor private final class WidgetLabelLink: NSAccessibilityElement {
    let artist: Bool
    init(artist: Bool) {
        self.artist = artist
        super.init()
        setAccessibilityRole(.link)
        setAccessibilityHelp(artist ? "Search for this artist" : "Open this track; search when no track link is available")
    }
    override func accessibilityPerformPress() -> Bool {
        openMediaLabel(artist: artist)
        return true
    }
}

@MainActor
final class WidgetView: NSView {
    static weak var current: WidgetView?
    static var contextEvent: NSEvent?
    private lazy var labelLinks = [WidgetLabelLink(artist: false), WidgetLabelLink(artist: true)]
    private var keyboardLabel = -1

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Wallify" }

    override func accessibilityChildren() -> [Any]? {
        sceneLock.lock()
        let state = widgetStatePointer().pointee, layout = sceneLayout, idle = spotifyIsIdle()
        sceneLock.unlock()
        guard state.setting_clickable_names, !idle, !state.setting_hide_text else { return [] }
        return labelLinks.compactMap { link in
            let rect = layout.labelBounds(link.artist, state: state)
            guard rect.w > 0, let window else { return nil }
            let title = withUnsafeBytes(of: state.global_title) { String(decoding: $0.prefix(state.global_title_len), as: UTF8.self) }
            link.setAccessibilityLabel(link.artist ? trackArtist(state) : title)
            link.setAccessibilityParent(self)
            link.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h), to: nil)))
            return link
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            sceneLock.lock()
            let state = widgetStatePointer(), geometry = sceneLayout.inputGeometry(state.pointee)
            let available = spotifyIsIdle() ? [] : [geometry.title, geometry.artist].enumerated().filter { $0.element.w > 0 }.map { $0.offset }
            if !available.isEmpty {
                let index = available.firstIndex(of: keyboardLabel) ?? (event.modifierFlags.contains(.shift) ? 0 : -1)
                keyboardLabel = available[(index + (event.modifierFlags.contains(.shift) ? available.count - 1 : 1)) % available.count]
                state.pointee.global_hover_target = Int32(keyboardLabel + 8)
            }
            sceneLock.unlock()
            requestWidgetFrame()
        } else if [36, 49, 76].contains(event.keyCode), keyboardLabel >= 0 {
            if !event.isARepeat { openMediaLabel(artist: keyboardLabel == 1) }
        } else { super.keyDown(with: event) }
    }

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private func pointer(_ event: NSEvent, kind: Int32) {
        keyboardLabel = -1
        let point = convert(event.locationInWindow, from: nil)
        wallify_pointer(point.x, point.y, kind)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pointer(event, kind: 1)
    }
    override func mouseUp(with event: NSEvent) { pointer(event, kind: 2) }
    override func mouseMoved(with event: NSEvent) { pointer(event, kind: 0) }
    override func mouseDragged(with event: NSEvent) { pointer(event, kind: 0) }
    override func mouseExited(with event: NSEvent) { wallify_pointer(-1, -1, 0) }

    override func rightMouseDown(with event: NSEvent) {
        // Retain the original event for synchronous native context-menu tracking.
        Self.contextEvent = event
        pointer(event, kind: 3)
    }

    override func rightMouseUp(with event: NSEvent) {}
}

@MainActor
final class WidgetPanel: NSPanel {
    static weak var current: WidgetPanel?
    var hiddenForStoppedMusic = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Preserve the desktop panel's existing AppKit appearance selectors.
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func _hasActiveControls() -> Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func _hasMainAppearance() -> Bool { true }

    @objc func occlusionChanged(_ notification: Notification) {
        wallify_set_window_visible(occlusionState.contains(.visible) ? 1 : 0)
    }
}

func refreshStoppedPresentation() {
    DispatchQueue.main.async { updateStoppedPresentation() }
}

@MainActor func updateStoppedPresentation() {
    guard !terminalMode, let panel = WidgetPanel.current else { return }
    sceneLock.lock()
    let hidden = stoppedWidgetHidden(widgetStatePointer().pointee)
    sceneLock.unlock()
    guard panel.hiddenForStoppedMusic != hidden else { return }
    panel.hiddenForStoppedMusic = hidden
    if hidden {
        panel.orderOut(nil)
        widget_hide_snap_outline()
        stopIdleAnimation()
        wallify_set_window_visible(0)
    } else {
        panel.orderFrontRegardless()
        // The animation worker sleeps while occluded. Metadata must restore
        // visibility and wake it independently, or a hidden widget never returns.
        wallify_set_window_visible(1)
        requestWidgetFrame()
    }
}

@_cdecl("wallify_create_widget_panel")
@MainActor public func createWidgetPanel(_ width: Int32, _ height: Int32) -> UnsafeMutableRawPointer {
    let panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: Int(width), height: Int(height)),
                            styleMask: .borderless, backing: .buffered, defer: false)
    panel.title = "Wallify"
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
    WidgetPanel.current = panel
    NotificationCenter.default.addObserver(panel, selector: #selector(WidgetPanel.occlusionChanged(_:)),
                                           name: NSWindow.didChangeOcclusionStateNotification, object: panel)
    // The Swift renderer consumes this retained reference at the C boundary.
    return Unmanaged.passRetained(panel).toOpaque()
}

@_cdecl("wallify_create_widget_view")
@MainActor public func createWidgetView(_ width: Int32, _ height: Int32) -> UnsafeMutableRawPointer {
    let view = WidgetView(frame: NSRect(x: 0, y: 0, width: Int(width), height: Int(height)))
    WidgetView.current = view
    return Unmanaged.passRetained(view).toOpaque()
}

@_cdecl("wallify_context_menu_event")
@MainActor public func contextMenuEvent() -> UnsafeMutableRawPointer? {
    WidgetView.contextEvent.map { Unmanaged.passUnretained($0).toOpaque() }
}

@_cdecl("wallify_clear_context_menu_event")
@MainActor public func clearContextMenuEvent() { WidgetView.contextEvent = nil }

func widgetPanelOrigin(visibleFrame: NSRect, height: CGFloat, left: Int32, top: Int32) -> NSPoint {
    NSPoint(x: visibleFrame.minX + CGFloat(left), y: visibleFrame.maxY - CGFloat(top) - height)
}

func widgetScreenOffsets(primaryFrame: NSRect, visibleFrame: NSRect) -> NSPoint {
    NSPoint(x: visibleFrame.minX, y: primaryFrame.maxY - visibleFrame.maxY)
}

@_cdecl("wallify_move_panel_now")
@MainActor public func moveWidgetPanelNow(_ left: Int32, _ top: Int32) {
    guard let panel = WidgetPanel.current, let screen = panel.screen ?? NSScreen.main else { return }
    panel.setFrameOrigin(widgetPanelOrigin(visibleFrame: screen.visibleFrame, height: panel.frame.height, left: left, top: top))
}

@_cdecl("wallify_move")
public func moveWidgetPanel(_ left: Int32, _ top: Int32) {
    DispatchQueue.main.async { moveWidgetPanelNow(left, top) }
}

@_cdecl("wallify_panel_window_number")
@MainActor public func widgetPanelWindowNumber() -> Int { WidgetPanel.current?.windowNumber ?? 0 }

@_cdecl("wallify_panel_offsets")
@MainActor public func widgetPanelOffsets(_ x: UnsafeMutablePointer<Double>?, _ y: UnsafeMutablePointer<Double>?) -> Bool {
    guard let panel = WidgetPanel.current, let primary = NSScreen.screens.first ?? NSScreen.main,
          let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return false }
    let offsets = widgetScreenOffsets(primaryFrame: primary.frame, visibleFrame: screen.visibleFrame)
    x?.pointee = offsets.x
    y?.pointee = offsets.y
    return true
}
