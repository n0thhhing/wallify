import AppKit

enum PointerAction: Equatable {
    case redraw, menu, startDrag, hidePreview, preview(Double, Double, Double, Double)
    case dragDebug(Bool), save, openIdle, toggle, command(UInt32), seek(Double)
    case move(Int32, Int32)
}

// The reducer shares geometry with rendering and leaves native side effects to the caller.
func reducePointer(_ x: Double, _ y: Double, kind: Int32, mouse: NSPoint, now: Double,
                   width: Double, height: Double, geometry: WallifyInputGeometry,
                   state: UnsafeMutablePointer<WallifyWidgetState>, idle: Bool,
                   snap: (Int32, Int32) -> WallifyPanelSnap) -> [PointerAction] {
    guard x.isFinite, y.isFinite, mouse.x.isFinite, mouse.y.isFinite, now.isFinite else { return [] }
    var actions = [PointerAction]()
    state.pointee.pointer_x = x; state.pointee.pointer_y = y
    let click = kind == 1, release = kind == 2
    if kind == 3 {
        state.pointee.global_is_dragging = false; state.pointee.global_panel_dragging = false
        state.pointee.global_click_target = 0
        state.pointee.global_hover_target = 0
        return [.hidePreview, .menu, .redraw]
    }
    func contains(_ rect: WallifyCardRect) -> Bool {
        roundedContains(rect.x, rect.y, rect.w, rect.h, rect.radius, x, y)
    }
    let buttons = [geometry.buttons.0, geometry.buttons.1, geometry.buttons.2]
    var target: Int32 = 1
    if geometry.controls_visible && !idle, let index = buttons.firstIndex(where: contains) { target = Int32(index + 5) }
    else if geometry.progress_visible && !idle && contains(geometry.bar) { target = 4 }
    else if contains(geometry.art) { target = 3 }
    else if contains(geometry.card) { target = 2 }
    var changed = state.pointee.global_hover_target != target
    state.pointee.global_hover_target = target
    if click {
        changed = changed || state.pointee.global_click_target != target
        state.pointee.global_click_target = target
        if state.pointee.global_duration > 0 && target == 4 {
            state.pointee.global_is_dragging = true; changed = true
        }
        if contains(geometry.card) && !(5...7).contains(target) && !state.pointee.global_is_dragging {
            state.pointee.global_panel_dragging = true
            state.pointee.widget_drag_start_mouse_x = mouse.x; state.pointee.widget_drag_start_mouse_y = mouse.y
            state.pointee.widget_drag_start_margin_left = state.pointee.widget_margin_left
            state.pointee.widget_drag_start_margin_top = state.pointee.widget_margin_top
            // A new drag cancels the previous snap so the panel follows the pointer immediately.
            state.pointee.panel_snap_active = false; state.pointee.panel_save_after_snap = false
            actions.append(.startDrag); changed = true
        }
    }
    if state.pointee.global_panel_dragging {
        if !click && !release {
            let left = Double(state.pointee.widget_drag_start_margin_left) + (mouse.x - state.pointee.widget_drag_start_mouse_x).rounded()
            let top = Double(state.pointee.widget_drag_start_margin_top) + (state.pointee.widget_drag_start_mouse_y - mouse.y).rounded()
            let nextLeft = Int32(max(0, min(Double(Int32.max), left)))
            let nextTop = Int32(max(-180, min(Double(Int32.max), top)))
            if nextLeft != state.pointee.widget_margin_left || nextTop != state.pointee.widget_margin_top {
                state.pointee.widget_margin_left = nextLeft; state.pointee.widget_margin_top = nextTop
                state.pointee.panel_position_dirty = false
                actions.append(.move(nextLeft, nextTop))
            }
        }
        let live = snap(state.pointee.widget_margin_left, state.pointee.widget_margin_top)
        let span = max(width, height), previewRadius = max(180, span * 0.45), commitRadius = max(150, span * 0.32)
        actions.append(.dragDebug(true))
        if !release {
            actions.append(live.found && live.distance_sq <= previewRadius * previewRadius ?
                .preview(live.outline_x, live.outline_y, live.outline_width, live.outline_height) : .hidePreview)
        } else {
            let idleClick = idle && abs(mouse.x - state.pointee.widget_drag_start_mouse_x) < 5 && abs(mouse.y - state.pointee.widget_drag_start_mouse_y) < 5
            if idleClick {
                if state.pointee.setting_idle_style != 0 { state.pointee.cat_pet_until = state.pointee.animation_time + 2.5 }
                else { actions.append(.openIdle) }
            }
            if !idleClick && live.found && live.distance_sq <= commitRadius * commitRadius {
                state.pointee.panel_snap_active = true; state.pointee.panel_snap_elapsed = 0
                state.pointee.panel_snap_start_left = state.pointee.widget_margin_left
                state.pointee.panel_snap_start_top = state.pointee.widget_margin_top
                state.pointee.panel_snap_target_left = max(0, live.margin_left)
                state.pointee.panel_snap_target_top = max(-180, live.margin_top)
                state.pointee.panel_save_after_snap = true
            }
            state.pointee.global_panel_dragging = false
            actions += [.dragDebug(false), .hidePreview]
            if !state.pointee.panel_snap_active { actions.append(.save) }
        }
        if changed || click || release { actions.append(.redraw) }
        return actions
    }
    if idle {
        if release {
            if state.pointee.setting_idle_style != 0 { state.pointee.cat_pet_until = state.pointee.animation_time + 2.5; changed = true }
            else { actions.append(.openIdle) }
        }
        if changed { actions.append(.redraw) }
        return actions
    }
    if release && !state.pointee.global_is_dragging && state.pointee.global_click_target == target {
        switch target {
        case 5: actions.append(.command(5))
        case 6: actions.append(.toggle)
        case 7: actions.append(.command(4))
        default: break
        }
    }
    if state.pointee.global_is_dragging && geometry.bar_width > 0 {
        let position = state.pointee.global_duration * min(1, max(0, (x - geometry.bar_x) / geometry.bar_width))
        state.pointee.global_elapsed = position
        if release {
            state.pointee.global_is_dragging = false
            synchronizePlayback(&state.pointee.playback_clock, position, state.pointee.global_rate, now, state.pointee.global_duration, true)
            state.pointee.global_rate_lock = 1; state.pointee.global_rate_lock_until = now + 0.5
            actions.append(.seek(position)); changed = true
        } else { actions.append(.redraw) }
    }
    if release { state.pointee.global_click_target = 0 }
    if changed { actions.append(.redraw) }
    return actions
}

@_cdecl("wallify_native_pointer")
@MainActor public func handleWidgetPointer(_ x: Double, _ y: Double, _ kind: Int32, _ geometry: UnsafePointer<WallifyInputGeometry>?) {
    guard let geometry else { return }
    let state = widgetStatePointer(), width = Double(wallify_width()), height = Double(wallify_height())
    sceneLock.lock()
    let actions = reducePointer(x, y, kind: kind, mouse: NSEvent.mouseLocation, now: monotonicTime(),
                                width: width, height: height, geometry: geometry.pointee, state: state, idle: spotifyIsIdle()) {
        widget_nearby_panel_snap($0, $1, 0, 0, width, height)
    }
    sceneLock.unlock()
    for action in actions {
        switch action {
        case .redraw: requestWidgetFrame()
        case let .move(left, top): moveWidgetPanelNow(left, top)
        case .menu: showWidgetContextMenu()
        case .startDrag: widget_start_drag(state.pointee.widget_margin_left, state.pointee.widget_margin_top, width)
        case .hidePreview: widget_hide_snap_outline()
        case let .preview(x, y, w, h): widget_show_snap_outline(x, y, w, h)
        case .dragDebug(let dragging): widget_set_snap_debug(state.pointee.mode_mix, width, height, dragging)
        case .save: saveConfiguration()
        case .openIdle: if state.pointee.setting_source == 2 { openSpotifast() } else { openSpotify() }
        case .toggle: toggleWidgetPlayback()
        case .command(let command): enqueueMediaCommand(command)
        case .seek(let position): enqueueMediaSeek(position)
        }
    }
}
