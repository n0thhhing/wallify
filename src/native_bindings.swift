import AppKit

// Stable callbacks used by AppKit and the optional C++ Inspector.
@_cdecl("wallify_settings_get_snapshot")
func settingsSnapshotBridge(_ output: UnsafeMutablePointer<WallifySettingsSnapshot>?) { widgetSettingsSnapshot(output) }
@_cdecl("wallify_settings_apply_bool")
func settingsBoolBridge(_ key: Int32, _ value: Bool) { applyWidgetBool(key, value) }
@_cdecl("wallify_settings_apply_int")
func settingsIntBridge(_ key: Int32, _ value: Int32) { applyWidgetInt(key, value) }
@_cdecl("wallify_settings_restore_defaults")
func settingsDefaultsBridge() { restoreWidgetDefaults() }
@_cdecl("wallify_settings_reset_position")
func settingsPositionBridge() { resetWidgetPosition() }
@_cdecl("wallify_menu_play_pause")
func menuPlaybackBridge() { toggleWidgetPlayback() }
@_cdecl("wallify_menu_previous")
func menuPreviousBridge() { enqueueMediaCommand(5) }
@_cdecl("wallify_menu_next")
func menuNextBridge() { enqueueMediaCommand(4) }
@_cdecl("wallify_media_key_event")
func mediaKeyBridge(_ code: Int32) { handleWidgetMediaKey(code) }
@_cdecl("wallify_execute_media_command")
func commandBridge(_ command: UInt32) { executeMediaCommand(command) }
@_cdecl("wallify_execute_media_seek")
func seekBridge(_ target: Double) { executeMediaSeek(target) }
@_cdecl("wallify_artwork_downloaded")
func artworkBridge(_ available: Bool) { receiveArtwork(available) }
@_cdecl("wallify_clear_artwork")
func clearArtworkBridge() { clearSceneArtwork() }
@_cdecl("wallify_extract_color")
func extractColorBridge() { markSceneArtworkDirty() }
@_cdecl("wallify_set_window_visible")
func visibleBridge(_ visible: Int32) { setWidgetVisible(visible != 0) }
@_cdecl("wallify_context_menu_selected")
func contextMenuBridge(_ tag: Int32) { enqueueContextSelection(tag) }
@_cdecl("wallify_open_inspector")
func openInspectorBridge() { showInspector() }
@_cdecl("widget_debug_window_show")
func showDebugBridge() {
    sceneLock.lock(); let enabled = widgetStatePointer().pointee.setting_debug; sceneLock.unlock()
    if enabled { showInspector() } else { hideInspector() }
}
@_cdecl("widget_debug_window_hide")
func hideDebugBridge() { hideInspector() }

@_cdecl("wallify_pointer")
@MainActor func pointerBridge(_ x: Double, _ y: Double, _ kind: Int32) {
    sceneLock.lock()
    var geometry = sceneLayout.inputGeometry(widgetStatePointer().pointee)
    sceneLock.unlock()
    handleWidgetPointer(x, y, kind, &geometry)
}
@_cdecl("widget_start_drag")
@MainActor func dragBridge(_ left: Int32, _ top: Int32, _ width: Double) { DesktopInteraction.shared.startDrag(left: left, top: top) }
@_cdecl("widget_nearby_panel_snap")
@MainActor func snapBridge(_ left: Int32, _ top: Int32, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> WallifyPanelSnap {
    DesktopInteraction.shared.nearby(left: left, top: top, x: x, y: y, width: width, height: height)
}
@_cdecl("widget_show_snap_outline")
@MainActor func showOutlineBridge(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
    DesktopInteraction.shared.outline = WallifyWindowRect(x: x, y: y, width: width, height: height)
    showSnapPreview(x, y, width, height, 26)
}
@_cdecl("widget_hide_snap_outline")
func hideOutlineBridge() { hideSnapPreview() }
@_cdecl("widget_set_snap_debug")
func snapDebugBridge(_ mix: Double, _ width: Double, _ height: Double, _ dragging: Bool) {
    DispatchQueue.main.async {
        let desktop = DesktopInteraction.shared
        desktop.modeMix = mix; desktop.width = width; desktop.height = height; desktop.dragging = dragging
        showDebugBridge()
    }
}
@_cdecl("wallify_debug_get_snapshot")
@MainActor func debugSnapshotBridge(_ output: UnsafeMutablePointer<WallifyDebugSnapshot>?) { output?.pointee = inspectorSnapshot() }
@_cdecl("wallify_debug_set_bool")
func debugBoolBridge(_ key: Int32, _ value: Int32) { applyWidgetBool(key, value != 0) }
@_cdecl("wallify_debug_set_int")
@MainActor func debugIntBridge(_ key: Int32, _ value: Int32) { applyInspectorInt(key, value) }
