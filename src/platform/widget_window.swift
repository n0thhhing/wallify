import AppKit

@MainActor
final class WidgetView: NSView {
    static var contextEvent: NSEvent?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private func pointer(_ event: NSEvent, kind: Int32) {
        let point = convert(event.locationInWindow, from: nil)
        wallify_pointer(point.x, point.y, kind)
    }

    override func mouseDown(with event: NSEvent) { pointer(event, kind: 1) }
    override func mouseUp(with event: NSEvent) { pointer(event, kind: 2) }
    override func mouseMoved(with event: NSEvent) { pointer(event, kind: 0) }
    override func mouseDragged(with event: NSEvent) { pointer(event, kind: 0) }
    override func mouseExited(with event: NSEvent) { wallify_pointer(-1, -1, 0) }

    override func rightMouseDown(with event: NSEvent) {
        // Store the original event before Zig synchronously opens the context menu.
        Self.contextEvent = event
        pointer(event, kind: 3)
    }

    override func rightMouseUp(with event: NSEvent) {}
}

@MainActor
final class WidgetPanel: NSPanel {
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
    NotificationCenter.default.addObserver(panel, selector: #selector(WidgetPanel.occlusionChanged(_:)),
                                           name: NSWindow.didChangeOcclusionStateNotification, object: panel)
    // The Objective-C renderer takes ownership with __bridge_transfer.
    return Unmanaged.passRetained(panel).toOpaque()
}

@_cdecl("wallify_create_widget_view")
@MainActor public func createWidgetView(_ width: Int32, _ height: Int32) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(WidgetView(frame: NSRect(x: 0, y: 0, width: Int(width), height: Int(height)))).toOpaque()
}

@_cdecl("wallify_context_menu_event")
@MainActor public func contextMenuEvent() -> UnsafeMutableRawPointer? {
    WidgetView.contextEvent.map { Unmanaged.passUnretained($0).toOpaque() }
}

@_cdecl("wallify_clear_context_menu_event")
@MainActor public func clearContextMenuEvent() { WidgetView.contextEvent = nil }
