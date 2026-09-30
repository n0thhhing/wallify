import AppKit

// Link the real Settings model against a small in-memory native bridge.
private var current = WallifySettingsSnapshot()
private var lastBool: (Int32, Bool)?
private var lastInt: (Int32, Int32)?
private var playbackCommands: [String] = []
private var lastPointer: (Double, Double, Int32)?
private var visible = Int32(0)

@_cdecl("wallify_pointer")
@MainActor func pointerStub(_ x: Double, _ y: Double, _ kind: Int32) {
    if kind == 3 { precondition(contextMenuEvent() != nil) }
    lastPointer = (x, y, kind)
}
@_cdecl("wallify_set_window_visible")
func visibilityStub(_ value: Int32) { visible = value }
@_cdecl("wallify_media_key_event")
func mediaKeyStub(_ key: Int32) {}

@_cdecl("wallify_menu_play_pause")
func playStub() { playbackCommands.append("play_pause") }
@_cdecl("wallify_menu_previous")
func previousStub() { playbackCommands.append("previous") }
@_cdecl("wallify_menu_next")
func nextStub() { playbackCommands.append("next") }

@_cdecl("wallify_settings_get_snapshot")
func snapshotStub(_ output: UnsafeMutablePointer<WallifySettingsSnapshot>?) { output?.pointee = current }

@_cdecl("wallify_settings_apply_bool")
func boolStub(_ key: Int32, _ value: Bool) {
    lastBool = (key, value)
    switch key {
    case 0: current.glow = value
    case 1: current.aurora = value
    case 2: current.animations = value
    case 3: current.dim_paused = value
    case 5: current.native_glass = value
    default: break
    }
}

@_cdecl("wallify_settings_apply_int")
func intStub(_ key: Int32, _ value: Int32) {
    lastInt = (key, value)
    switch key {
    case 10: current.frame_strength = value
    case 13: current.media_source = value
    case 14: current.widget_mode = value
    case 15: current.idle_style = value
    case 16: current.track_transition = value
    default: break
    }
}

@_cdecl("wallify_debug_renderer_stats")
func rendererStub(_ output: UnsafeMutablePointer<WallifyRendererStats>?) { output?.pointee = WallifyRendererStats() }

@_cdecl("wallify_settings_restore_defaults")
func defaultsStub() {}
@_cdecl("wallify_settings_reset_position")
func positionStub() {}
@_cdecl("wallify_open_inspector")
func inspectorStub() {}

@main
struct SettingsBridgeCheck {
    @MainActor static func main() {
        checkSpotifyBridge()
        checkSpotifastBridge()
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
        _ = NSApplication.shared
        let status = StatusMenu()
        status.refresh()
        precondition(status.menu.items[1].title == "Nothing Playing")
        precondition(status.menu.items[2].title == "Choose music to get started")
        current.playing = true
        status.refresh()
        precondition(status.play.title == "Pause")
        for (name, key) in [("Media Source", 13), ("Widget Mode", 14), ("Idle Companion", 15),
                            ("Track Transition", 16), ("Frame", 10)] {
            let items = status.menu.items.first { $0.title == name }!.submenu!.items
            for (value, item) in items.enumerated() {
                status.choose(item)
                precondition(lastInt?.0 == Int32(key) && lastInt?.1 == Int32(value))
                precondition(items.filter { $0.state == .on }.count == 1 && item.state == .on)
            }
        }
        let toggles = status.menu.items.first { $0.title == "Quick Controls" }!.submenu!.items
        for item in toggles {
            let previous = item.state
            // A stale displayed checkmark must not change the toggle's meaning.
            item.state = previous == .on ? .off : .on
            status.toggle(item)
            precondition(lastBool?.0 == Int32(item.tag))
            precondition(item.state != previous)
        }
        status.playPause(); status.previous(); status.next()
        precondition(playbackCommands == ["play_pause", "previous", "next"])
        checkConfigurationPaths()
        checkWidgetWindow()
        for key in [16, 19, 20] {
            let down = mediaKeyAction(data: (key << 16) | 0x0A00)
            let up = mediaKeyAction(data: (key << 16) | 0x0B00)
            precondition(down?.key == Int32(key) && down?.pressed == true)
            precondition(up?.key == Int32(key) && up?.pressed == false)
        }
        for key in [0, 1, 2, 7] {
            precondition(mediaKeyAction(data: (key << 16) | 0x0A00) == nil)
            precondition(mediaKeyAction(data: (key << 16) | 0x0B00) == nil)
        }
        withMediaRemoteSymbol("WallifyMissingMediaRemoteSymbol") { _ in
            preconditionFailure("A missing MediaRemote symbol must be ignored")
        }
        print("Swift settings bridge checks passed")
    }

    @MainActor static func checkWidgetWindow() {
        let panel = Unmanaged<NSPanel>.fromOpaque(createWidgetPanel(200, 100)).takeRetainedValue()
        let view = Unmanaged<WidgetView>.fromOpaque(createWidgetView(200, 100)).takeRetainedValue()
        panel.contentView = view
        precondition(panel.canBecomeKey && !panel.canBecomeMain)
        precondition(!panel.isOpaque && !panel.hasShadow && !panel.hidesOnDeactivate)
        precondition(panel.level.rawValue == NSWindow.Level.normal.rawValue - 1)
        precondition(panel.collectionBehavior.contains([.canJoinAllSpaces, .stationary]))
        precondition(view.isFlipped && !view.acceptsFirstResponder && view.acceptsFirstMouse(for: nil))
        view.updateTrackingAreas()
        view.updateTrackingAreas()
        precondition(view.trackingAreas.count == 1)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 30),
                                       modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
        precondition(lastPointer?.0 == 20 && lastPointer?.1 == 70 && lastPointer?.2 == 1)
        view.mouseUp(with: event)
        precondition(lastPointer?.2 == 2)
        view.mouseDragged(with: event)
        precondition(lastPointer?.2 == 0)
        view.rightMouseDown(with: event)
        precondition(lastPointer?.2 == 3)
        let retainedEvent = Unmanaged<NSEvent>.fromOpaque(contextMenuEvent()!).takeUnretainedValue()
        precondition(retainedEvent === event)
        clearContextMenuEvent()
        precondition(contextMenuEvent() == nil)
        view.mouseExited(with: event)
        precondition(lastPointer?.0 == -1 && lastPointer?.1 == -1 && lastPointer?.2 == 0)
        (panel as! WidgetPanel).occlusionChanged(Notification(name: NSWindow.didChangeOcclusionStateNotification))
        precondition(visible == (panel.occlusionState.contains(.visible) ? 1 : 0))
        panel.orderOut(nil)
    }

    static func checkSpotifastBridge() {
        precondition((0...4).map { spotifastControlVerb(Int32($0))! } == ["play", "pause", "playpause", "previous", "next"])
        precondition(spotifastControlVerb(-1) == nil && spotifastControlVerb(5) == nil)
        precondition(spotifastSeekVerb(12.345) == "seek-to 12345" && spotifastSeekVerb(-1) == "seek-to 0")
        precondition(spotifastSeekVerb(.nan) == nil && spotifastSeekVerb(.infinity) == nil && spotifastSeekVerb(Double.greatestFiniteMagnitude) == nil)
        precondition(String(decoding: spotifastQueryResult(nil), as: UTF8.self) == "CLOSED")
        for stopped in ["fastpotify:now stopped\n", "fastpotify:now\r\n", " stopped "] {
            precondition(String(decoding: spotifastQueryResult(Array(stopped.utf8)), as: UTF8.self) == "NO_TRACK")
        }
        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        precondition(listener >= 0)
        defer { Darwin.close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        precondition(bound == 0 && Darwin.listen(listener, 4) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        precondition(named == 0)
        let port = UInt16(bigEndian: address.sin_port)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            func acceptClient() -> Int32 {
                let socket = Darwin.accept(listener, nil, nil)
                precondition(socket >= 0)
                return socket
            }
            func expect(_ verb: String, on socket: Int32) {
                var request: [UInt8] = []
                var byte: UInt8 = 0
                repeat {
                    precondition(Darwin.read(socket, &byte, 1) == 1)
                    request.append(byte)
                } while byte != 10
                precondition(String(decoding: request, as: UTF8.self) == "fastpotify:\(verb)\n")
            }
            func send(_ text: String, on socket: Int32) {
                let bytes = Array(text.utf8)
                precondition(bytes.withUnsafeBytes { Darwin.write(socket, $0.baseAddress!, $0.count) } == bytes.count)
            }
            let first = acceptClient()
            expect("nowplaying", on: first)
            send("fastpotify:now ", on: first)
            send("playing\tTrack\tArtist\n", on: first)
            expect("nowplaying", on: first)
            send("incomplete", on: first)
            Darwin.close(first)
            let second = acceptClient()
            expect("nowplaying", on: second)
            send("fastpotify:now paused\tTrack\tArtist\n", on: second)
            let control = acceptClient()
            expect("next", on: control)
            send("ok\n", on: control)
            Darwin.close(control)
            expect("nowplaying", on: second)
            send("fastpotify:now stopped\n", on: second)
            Darwin.close(second)
            done.signal()
        }
        let connection = SpotifastConnection(port: port)
        precondition(connection.request("nowplaying\nnext") == nil)
        precondition(connection.request(String(repeating: "x", count: 116)) == nil)
        let first = connection.request("nowplaying", persistent: true)!
        precondition(String(decoding: first, as: UTF8.self) == "fastpotify:now playing\tTrack\tArtist\n")
        let second = connection.request("nowplaying", persistent: true)!
        precondition(String(decoding: second, as: UTF8.self) == "fastpotify:now paused\tTrack\tArtist\n")
        precondition(connection.request("next") == Array("ok\n".utf8))
        precondition(spotifastQueryResult(connection.request("nowplaying", persistent: true)) == Array("NO_TRACK".utf8))
        precondition(done.wait(timeout: .now() + 2) == .success)
    }

    static func checkSpotifyBridge() {
        precondition(spotifyBundleIdentifier == "com.spotify.client")
        let lines = spotifyQueryScript.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let artwork = lines.firstIndex(of: "set tArt to artwork url of current track")!
        precondition(lines[artwork - 1] == "try" && lines[artwork + 1] == "end try")
        precondition(spotifyQueryScript.contains("set tArt to \"\""))
        precondition(spotifyQueryScript.contains("set {tName, tArtist, tState, tPos, tDur}"))
        precondition(spotifyQueryScript.contains("return \"NO_TRACK\"") && spotifyQueryScript.contains("return \"CLOSED\""))
        for command: Int32 in 0...4 {
            let script = spotifyControlScript(command)!
            precondition(script.contains("tell application \"Spotify\""))
            precondition(script.contains("to activate") == (command == 0 || command == 2))
        }
        precondition(spotifyControlScript(5) == nil && spotifyControlScript(-1) == nil)
        precondition(spotifySeekScript(12.346)!.hasSuffix("12.35"))
        precondition(spotifySeekScript(.nan) == nil && spotifySeekScript(.infinity) == nil && spotifySeekScript(-1) == nil)
        let events = SpotifyEvents()
        precondition(events.takeState() == -1 && events.wait(milliseconds: 0) == 0)
        events.notify()
        events.notify()
        precondition(events.wait(milliseconds: 0) == 1)
        precondition(events.takeState() == -1 && events.wait(milliseconds: 0) == 0)
        events.notify()
        precondition(events.takeState() == 1 && events.takeState() == -1)
        precondition(events.wait(milliseconds: 0) == 1)
        let wake = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            precondition(events.wait(milliseconds: 1000) == 1)
            wake.signal()
        }
        events.notify()
        precondition(wake.wait(timeout: .now() + 2) == .success)
        var buffer = [UInt8](repeating: 0xFF, count: 8)
        buffer.withUnsafeMutableBufferPointer {
            precondition(copySpotifyResult("é|||track", to: $0.baseAddress!, capacity: 5) == 5)
        }
        precondition(Array(buffer.prefix(5)) == Array("é|||".utf8) && buffer[5] == 0xFF)
        buffer.withUnsafeMutableBufferPointer {
            precondition(copySpotifyResult("", to: $0.baseAddress!, capacity: 8) == 0)
            precondition(copySpotifyResult("track", to: $0.baseAddress!, capacity: 0) == 0)
        }
    }

    static func checkConfigurationPaths() {
        let files = FileManager.default
        let scratch = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? files.removeItem(at: scratch) }
        let resources = scratch.appendingPathComponent("Wallify.app/Contents/Resources", isDirectory: true)
        let home = scratch.appendingPathComponent("home", isDirectory: true)
        do {
            try files.createDirectory(at: resources, withIntermediateDirectories: true)
            try "bundled settings".write(to: resources.appendingPathComponent("widget-settings.conf"),
                                        atomically: true, encoding: .utf8)
            let bundle = scratch.appendingPathComponent("Wallify.app")
            let support = prepareConfiguration(bundleURL: bundle, resourceURL: resources, home: home)
            precondition(support == home.appendingPathComponent("Library/Application Support/Wallify/widget-settings.conf").path)
            let seeded = try String(contentsOfFile: support, encoding: .utf8)
            precondition(seeded == "bundled settings")
            try "saved preferences".write(toFile: support, atomically: true, encoding: .utf8)
            _ = prepareConfiguration(bundleURL: bundle, resourceURL: resources, home: home)
            let preserved = try String(contentsOfFile: support, encoding: .utf8)
            precondition(preserved == "saved preferences")
            let override = home.appendingPathComponent(".config/Wallify/widget-settings.conf")
            try files.createDirectory(at: override.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "override".write(to: override, atomically: true, encoding: .utf8)
            precondition(prepareConfiguration(bundleURL: bundle, resourceURL: resources, home: home) == override.path)
            precondition(prepareConfiguration(bundleURL: scratch.appendingPathComponent("wallify"), resourceURL: nil, home: home) == "widget-settings.conf")
        } catch { preconditionFailure("Configuration check failed: \(error)") }
    }
}
