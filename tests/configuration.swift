import Foundation

func checkConfigurationStorage() {
    var value = widgetStatePointer().pointee
    parseConfiguration("""
    [Appearance]
    artwork_glow = no # comment
    native_glass = yes
    show_controls = invalid
    widget_mode = 1
    media_source = fastpotify
    widget_grid_x = 255
    widget_grid_y = 2
    artwork_radius = 300
    """, into: &value)
    precondition(!value.setting_glow && value.setting_native_glass && value.setting_show_controls)
    precondition(value.setting_mode == 2 && value.setting_source == 2)
    precondition(value.widget_grid_x == 20 && value.widget_margin_left == 3608 && value.widget_margin_top == 368)
    precondition(value.setting_artwork_radius == 1)
    parseConfiguration("widget_margin_left = -2\nwidget_margin_top = -999\nwidget_grid_x = 3", into: &value)
    precondition(value.widget_margin_left == 0 && value.widget_margin_top == -180)
    let content = renderConfiguration(value)
    var restored = WallifyWidgetState()
    parseConfiguration(content, into: &restored)
    precondition(configurationValues(restored) == configurationValues(value))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wallify-config-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try! persistConfiguration("old", to: url)
    try! persistConfiguration(content, to: url)
    precondition(try! String(contentsOf: url, encoding: .utf8) == content)
    do {
        try persistConfiguration("bad", to: url.appendingPathComponent("missing/config"))
        preconditionFailure("Saving under a file should fail")
    } catch {}
    precondition(try! String(contentsOf: url, encoding: .utf8) == content)
}
