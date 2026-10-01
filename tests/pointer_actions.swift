import AppKit

func checkPointerActions() {
    let state = widgetStatePointer(), original = widgetStatePointer().pointee
    defer { state.pointee = original }
    var geometry = WallifyInputGeometry()
    geometry.card = WallifyCardRect(x: 8, y: 8, w: 524, h: 164, radius: 26)
    geometry.art = WallifyCardRect(x: 24, y: 24, w: 132, h: 132, radius: 14)
    geometry.bar = WallifyCardRect(x: 172, y: 70, w: 344, h: 33, radius: 3)
    geometry.bar_x = 172; geometry.bar_width = 344
    geometry.buttons = (WallifyCardRect(x: 283, y: 117, w: 30, h: 30, radius: 15),
                        WallifyCardRect(x: 324, y: 112, w: 40, h: 40, radius: 20),
                        WallifyCardRect(x: 375, y: 117, w: 30, h: 30, radius: 15))
    geometry.controls_visible = true; geometry.progress_visible = true
    state.pointee.global_is_dragging = false; state.pointee.global_panel_dragging = false
    state.pointee.global_duration = 200; state.pointee.global_rate = 1
    func pointer(_ x: Double, _ y: Double, _ kind: Int32, mouse: NSPoint = .zero, idle: Bool = false,
                 snap: WallifyPanelSnap = WallifyPanelSnap()) -> [PointerAction] {
        reducePointer(x, y, kind: kind, mouse: mouse, now: 10, width: 540, height: 180, geometry: geometry, state: state, idle: idle) { _, _ in snap }
    }
    _ = pointer(344, 132, 1)
    precondition(pointer(344, 132, 2).contains(.toggle))
    _ = pointer(344, 132, 1)
    _ = pointer(344, 132, 3)
    precondition(!pointer(344, 132, 2).contains(.toggle))
    _ = pointer(298, 132, 1)
    precondition(!pointer(390, 132, 2).contains(.command(4)))
    _ = pointer(344, 84, 1)
    precondition(state.pointee.global_is_dragging && state.pointee.global_elapsed == 100)
    _ = pointer(-100, 84, 0)
    precondition(state.pointee.global_elapsed == 0)
    precondition(pointer(999, 84, 2).contains(.seek(200)))
    precondition(!state.pointee.global_is_dragging && state.pointee.global_rate_lock_until == 10.5)
    _ = pointer(60, 60, 0)
    precondition(pointer(999, 999, 0).contains(.redraw))
    precondition(pointer(999, 999, 0).isEmpty)
    state.pointee.widget_margin_left = 8; state.pointee.widget_margin_top = 8
    state.pointee.panel_snap_active = true
    precondition(pointer(60, 60, 1, mouse: NSPoint(x: 100, y: 100)).contains(.startDrag))
    precondition(!state.pointee.panel_snap_active)
    let movement = pointer(60, 60, 0, mouse: NSPoint(x: 120, y: 80))
    precondition(movement.contains(.move(28, 28)) && !movement.contains(.redraw))
    precondition(!state.pointee.panel_position_dirty)
    precondition(state.pointee.widget_margin_left == 28 && state.pointee.widget_margin_top == 28)
    var snap = WallifyPanelSnap()
    snap.found = true; snap.distance_sq = 100; snap.margin_left = 188; snap.margin_top = 8
    precondition(!pointer(60, 60, 2, mouse: NSPoint(x: 120, y: 80), snap: snap).contains(.save))
    precondition(state.pointee.panel_snap_active && state.pointee.panel_snap_target_left == 188 && state.pointee.panel_save_after_snap)
    state.pointee.animation_time = 30; state.pointee.setting_idle_style = 1
    _ = pointer(60, 60, 1, mouse: .zero, idle: true)
    precondition(pointer(60, 60, 2, mouse: .zero, idle: true).contains(.save))
    precondition(state.pointee.cat_pet_until == 32.5)
    _ = pointer(344, 84, 1)
    precondition(pointer(344, 84, 3) == [.hidePreview, .menu, .redraw])
    precondition(!state.pointee.global_is_dragging && !state.pointee.global_panel_dragging)
    precondition(pointer(.nan, 1, 1).isEmpty)
}
