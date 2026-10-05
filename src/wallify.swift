import AppKit

@main
struct WallifyApp {
    @MainActor static func main() {
        #if DEBUG_INSPECTOR
        wallify_debug_console_install()
        #endif
        preparePlatform()
        initializeApplication()
        loadConfiguration()
        if terminalMode { TerminalDisplay.current = TerminalDisplay() }
        let state = widgetStatePointer(), (width, height) = modeDimensions(widgetStatePointer().pointee.setting_mode)
        state.pointee.mode_from = state.pointee.setting_mode
        state.pointee.mode_mix = 1; state.pointee.mode_transition_active = false
        state.pointee.mode_start_width = width; state.pointee.mode_target_width = width
        state.pointee.mode_start_height = height; state.pointee.mode_target_height = height
        observeSpotify()
        guard createMetalWidget(Int32(width), Int32(height), state.pointee.widget_margin_left, state.pointee.widget_margin_top) else {
            NSLog("Wallify: could not create the Metal widget")
            exit(1)
        }
        NSLog("Wallify: Swift widget ready, mode=%d source=%d", state.pointee.setting_mode, state.pointee.setting_source)
        do { try TerminalDisplay.current?.start() }
        catch {
            FileHandle.standardOutput.write(Data(("Wallify: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
        #if DEBUG_INSPECTOR
        if !terminalMode { showInspector() }
        #endif
        initializeFrameWakeups()
        requestWidgetFrame()
        drawSwiftUIFrame()
        Thread.detachNewThread { runAnimationWorker() }
        Thread.detachNewThread { runMetadataWorker() }
        if hasSettingsFlag() { showSettingsWindow() }
        runApplication()
    }
}
