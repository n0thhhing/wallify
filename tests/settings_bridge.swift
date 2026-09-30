import Foundation

// Link the real Settings model against a small in-memory native bridge.
private var current = WallifySettingsSnapshot()
private var lastBool: (Int32, Bool)?
private var lastInt: (Int32, Int32)?

@_cdecl("wallify_settings_get_snapshot")
func snapshotStub(_ output: UnsafeMutablePointer<WallifySettingsSnapshot>?) { output?.pointee = current }

@_cdecl("wallify_settings_apply_bool")
func boolStub(_ key: Int32, _ value: Bool) { lastBool = (key, value); current.glow = value }

@_cdecl("wallify_settings_apply_int")
func intStub(_ key: Int32, _ value: Int32) { lastInt = (key, value); current.media_source = value }

@_cdecl("wallify_debug_renderer_stats")
func rendererStub(_ output: UnsafeMutablePointer<WallifyRendererStats>?) { output?.pointee = WallifyRendererStats() }

@_cdecl("wallify_settings_restore_defaults")
func defaultsStub() {}
@_cdecl("wallify_settings_reset_position")
func positionStub() {}
@_cdecl("wallify_open_inspector")
func inspectorStub() {}
@_cdecl("wallify_settings_path")
func pathStub() -> UnsafePointer<CChar>? { nil }

@main
struct SettingsBridgeCheck {
    @MainActor static func main() {
        let model = SettingsModel()
        current.glow = false
        current.media_source = 3
        model.refresh()
        let glow = model.toggle(0, \.glow)
        let source = model.selection(13, \.media_source)
        precondition(!glow.wrappedValue && source.wrappedValue == 3)
        glow.wrappedValue = true
        precondition(lastBool?.0 == 0 && lastBool?.1 == true && model.snapshot.glow)
        source.wrappedValue = 2
        precondition(lastInt?.0 == 13 && lastInt?.1 == 2 && model.snapshot.media_source == 2)
        current.glow = false
        current.media_source = 1
        model.refresh()
        precondition(!glow.wrappedValue && source.wrappedValue == 1)
        precondition(hasSettingsFlag() == ProcessInfo.processInfo.arguments.contains("--settings"))
        print("Swift settings bridge checks passed")
    }
}
