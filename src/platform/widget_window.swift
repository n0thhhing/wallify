import AppKit

// One VoiceOver element of the Metal-drawn widget. Elements are reused so VoiceOver keeps its focus.
@MainActor private final class WidgetElement: NSAccessibilityElement {
    var press: (() -> Void)?
    var step: ((Double) -> Void)?
    init(_ role: NSAccessibility.Role, help: String? = nil) {
        super.init()
        setAccessibilityRole(role)
        if let help { setAccessibilityHelp(help) }
    }
    override func accessibilityPerformPress() -> Bool { press.map { $0(); return true } ?? false }
    override func accessibilityPerformIncrement() -> Bool { step.map { $0(1); return true } ?? false }
    override func accessibilityPerformDecrement() -> Bool { step.map { $0(-1); return true } ?? false }
}

// Caller holds sceneLock.
private func currentElapsed() -> Double {
    let state = widgetStatePointer().pointee
    return state.global_rate == 0 || state.global_is_dragging ? state.global_elapsed :
        playbackPosition(state.playback_clock, now: monotonicTime(), duration: state.global_duration)
}

// Posted when the track or play state changes, not on every position update.
func announceWidgetChange() {
    DispatchQueue.main.async {
        guard let view = WidgetView.current else { return }
        NSAccessibility.post(element: view, notification: .valueChanged)
        NSAccessibility.post(element: view, notification: .layoutChanged)
    }
}

@MainActor
final class WidgetView: NSView {
    static weak var current: WidgetView?
    static var contextEvent: NSEvent?
    private let titleElement = WidgetElement(.staticText), artistElement = WidgetElement(.staticText)
    private let controls = [WidgetElement(.button), WidgetElement(.button), WidgetElement(.button)]
    private let progress = WidgetElement(.slider, help: "Adjust to seek 10 seconds")
    private let idleElement = WidgetElement(.button)
    private let lyricElement = WidgetElement(.staticText)
    private let likeElement = WidgetElement(.button)
    private let upNextElement = WidgetElement(.staticText)
    private var keyboardLabel = -1

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Wallify" }
    override func accessibilityValue() -> Any? {
        sceneLock.lock(); defer { sceneLock.unlock() }
        let state = widgetStatePointer().pointee
        guard !spotifyIsIdle() else { return "Nothing playing" }
        let title = withUnsafeBytes(of: state.global_title) { String(decoding: $0.prefix(state.global_title_len), as: UTF8.self) }
        return "\(state.global_rate > 0 ? "Playing" : "Paused"): \(title), \(trackArtist(state))"
    }

    override func accessibilityChildren() -> [Any]? {
        sceneLock.lock()
        let state = widgetStatePointer().pointee, layout = sceneLayout, idle = spotifyIsIdle(), elapsed = currentElapsed()
        sceneLock.unlock()
        guard let window else { return [] }
        func place(_ element: WidgetElement, _ rect: WallifyCardRect, _ label: String) -> WidgetElement {
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(label)
            element.setAccessibilityFrame(window.convertToScreen(convert(NSRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h), to: nil)))
            return element
        }
        if idle {
            // The Spotify launcher opens the player; the pixel companions are decoration.
            guard state.setting_idle_style == 0 else { return [place(idleElement, layout.card, "Nothing playing")] }
            idleElement.press = { if state.setting_source == 2 { openSpotifast() } else { openSpotify() } }
            return [place(idleElement, layout.card, state.setting_source == 2 ? "Open Spotifast" : "Open Spotify")]
        }
        var children = [WidgetElement]()
        let g = layout.geometry
        if !state.setting_hide_text {
            let title = withUnsafeBytes(of: state.global_title) { String(decoding: $0.prefix(state.global_title_len), as: UTF8.self) }
            for (element, artist) in [(titleElement, false), (artistElement, true)] {
                let clickable = layout.labelBounds(artist, state: state)
                let row = artist ? cardRect(g.text_x, g.artist_y, g.text_width, g.artist_y - g.title_y) :
                    cardRect(g.text_x, g.title_y, g.text_width, g.artist_y - g.title_y)
                // Clickable names become links that open the track or search the artist.
                element.setAccessibilityRole(clickable.w > 0 ? .link : .staticText)
                element.press = clickable.w > 0 ? { openMediaLabel(artist: artist) } : nil
                let text = artist ? trackArtist(state) : title
                if !text.isEmpty { children.append(place(element, clickable.w > 0 ? clickable : row, text)) }
            }
        }
        if layout.controlsVisible(state.setting_show_controls) {
            let labels = ["Previous Track", state.global_rate > 0 ? "Pause" : "Play", "Next Track"]
            let actions: [() -> Void] = [{ enqueueMediaCommand(5) }, { toggleWidgetPlayback() }, { enqueueMediaCommand(4) }]
            for index in 0..<3 {
                controls[index].press = actions[index]
                children.append(place(controls[index], layout.buttonBounds(index), labels[index]))
            }
        }
        if state.setting_mode == 4, let next = upNextStore.cachedLine() {
            children.append(place(upNextElement, cardRect(g.art_x, g.art_y + g.art_size - 52, g.art_size, 52), "Up next: " + next))
        }
        let like = layout.likeBounds()
        if like.w > 0, let liked = likeStore.state {
            likeElement.press = { likeStore.toggle() }
            children.append(place(likeElement, like, liked ? "Remove from Liked Songs" : "Save to Liked Songs"))
        }
        if state.setting_lyrics, g.compact_mix <= 0.12, let lyric = lyricsStore.cachedFrame(at: elapsed), lyric.line != "♪" {
            children.append(place(lyricElement, cardRect(g.text_x, g.timestamp_y, g.text_width, 18), lyric.line))
        }
        if layout.progressVisible(state.setting_hide_progress) && state.global_duration > 0 {
            progress.setAccessibilityMinValue(0)
            progress.setAccessibilityMaxValue(state.global_duration)
            progress.setAccessibilityValue(elapsed)
            progress.setAccessibilityValueDescription("\(formatTimestamp(elapsed)) of \(formatTimestamp(state.global_duration))")
            progress.step = { [weak self] direction in
                seekWidget(by: 10 * direction)
                if let self { NSAccessibility.post(element: self.progress, notification: .valueChanged) }
            }
            children.append(place(progress, cardRect(g.bar_x, g.bar_y - 6, g.bar_w, g.bar_h + 12), "Playback position"))
        }
        return children
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

    override func rightMouseUp(with event: NSEvent) {
        // Start popup tracking after the click so its release cannot dismiss the menu.
        Self.contextEvent = event
        pointer(event, kind: 3)
    }

    override func scrollWheel(with event: NSEvent) {
        // Momentum scrolling would overshoot volume and seek targets.
        guard event.momentumPhase.isEmpty else { return }
        sceneLock.lock()
        let state = widgetStatePointer().pointee
        sceneLock.unlock()
        guard state.setting_scroll_action != 0, !state.global_panel_dragging, !state.global_is_dragging, !spotifyIsIdle() else {
            return super.scrollWheel(with: event)
        }
        let amount = scrollAmount(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                                  inverted: event.isDirectionInvertedFromDevice)
        guard amount != 0 else { return }
        if state.setting_scroll_action == 1 { adjustVolume(by: amount) } else { seekWidget(by: amount) }
    }
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
    @objc func screensChanged(_ notification: Notification) {
        restoreWidgetDisplayPlacement()
        refreshSettingsUI()
    }
}

func refreshStoppedPresentation() {
    DispatchQueue.main.async { updateStoppedPresentation() }
}

@MainActor func updateStoppedPresentation() {
    guard !terminalMode, let panel = WidgetPanel.current else { return }
    sceneLock.lock()
    let state = widgetStatePointer(), hidden = stoppedWidgetHidden(widgetStatePointer().pointee)
    if hidden {
        state.pointee.global_panel_dragging = false; state.pointee.global_is_dragging = false
        state.pointee.global_click_target = 0
        state.pointee.panel_snap_active = false; state.pointee.panel_save_after_snap = false
    }
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
    NotificationCenter.default.addObserver(panel, selector: #selector(WidgetPanel.screensChanged(_:)),
                                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
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
    guard let panel = WidgetPanel.current, let screen = widgetPlacementScreen() else { return }
    let placement = DisplayPlacement(left: left, top: top).clamped(to: screen.visibleFrame.size, widget: panel.frame.size)
    panel.setFrameOrigin(widgetPanelOrigin(visibleFrame: screen.visibleFrame, height: panel.frame.height, left: placement.left, top: placement.top))
    WidgetView.current?.layer?.contentsScale = screen.backingScaleFactor
    sceneLock.lock()
    widgetStatePointer().pointee.widget_margin_left = placement.left
    widgetStatePointer().pointee.widget_margin_top = placement.top
    sceneLock.unlock()
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
