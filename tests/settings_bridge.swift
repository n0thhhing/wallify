import AppKit
import QuartzCore
import Metal
import ImageIO

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

// Renderer callbacks are supplied by native.m in the app.
private var idleTestTexture: MTLTexture?
private let idleTestSurface = CALayer()
@_cdecl("wallify_copy_idle_texture")
func idleTextureStub(_ textureID: Int32) -> UnsafeMutableRawPointer? {
    guard let texture = idleTestTexture, textureID == 0 else { return nil }
    return Unmanaged.passRetained(texture as AnyObject).toOpaque()
}
@_cdecl("wallify_idle_surface")
func idleSurfaceStub() -> UnsafeMutableRawPointer? { Unmanaged.passUnretained(idleTestSurface).toOpaque() }
@_cdecl("wallify_width")
func widthStub() -> Int32 { 200 }
@_cdecl("wallify_height")
func heightStub() -> Int32 { 100 }

@main
struct SettingsBridgeCheck {
    @MainActor static func main() {
        checkSpotifyBridge()
        checkSpotifastBridge()
        checkIdleAnimation()
        checkNowPlayingHelper()
        checkRasterGraphics()
        checkDesktopGlass()
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

    @MainActor static func checkDesktopGlass() {
        precondition(widgetPanelOrigin(visibleFrame: NSRect(x: -1920, y: 24, width: 1920, height: 1023),
                                       height: 180, left: 20, top: 30) == NSPoint(x: -1900, y: 837))
        precondition(widgetScreenOffsets(primaryFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                                         visibleFrame: NSRect(x: -1920, y: 24, width: 1920, height: 1023)) == NSPoint(x: -1920, y: 33))
        let panel = Unmanaged<NSPanel>.fromOpaque(createWidgetPanel(200, 100)).takeRetainedValue()
        let metalView = Unmanaged<NSView>.fromOpaque(createWidgetView(200, 100)).takeRetainedValue()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        container.addSubview(metalView)
        panel.contentView = container
        precondition(widgetPanelWindowNumber() == panel.windowNumber)
        if let screen = panel.screen ?? NSScreen.main {
            moveWidgetPanelNow(20, 30)
            precondition(panel.frame.origin == widgetPanelOrigin(visibleFrame: screen.visibleFrame, height: panel.frame.height, left: 20, top: 30))
        }
        let owner = DesktopGlass()
        let geometry = DesktopGlassGeometry(rect: NSRect(x: 10, y: 7, width: 180, height: 76), radius: 16, active: true)
        owner.update(geometry, panel: panel, metalView: metalView, size: NSSize(width: 200, height: 100))
        if #available(macOS 26.0, *) {
            let glass = container.subviews.first as! NSGlassEffectView
            precondition(glass.frame == NSRect(x: 10, y: 17, width: 180, height: 76))
            precondition(glass.cornerRadius == 16 && glass.tintColor == nil)
            precondition(metalView.superview === glass.contentView)
            precondition(metalView.frame == NSRect(x: -10, y: -17, width: 200, height: 100))
            owner.update(DesktopGlassGeometry(rect: geometry.rect, radius: 16, active: false),
                         panel: panel, metalView: metalView, size: NSSize(width: 200, height: 100))
            precondition(glass.isHidden && metalView.superview === container && metalView.frame == container.bounds)
            owner.update(geometry, panel: panel, metalView: metalView, size: NSSize(width: 200, height: 100))
            precondition(!glass.isHidden && container.subviews.count == 1 && metalView.superview === glass.contentView)
        } else { precondition(metalView.superview === container && metalView.frame == container.bounds) }
        owner.update(DesktopGlassGeometry(rect: geometry.rect, radius: 16, active: false),
                     panel: panel, metalView: metalView, size: NSSize(width: 200, height: 100))
        precondition(metalView.autoresizingMask == [.width, .height])
        panel.orderOut(nil)
    }

    static func checkRasterGraphics() {
        _ = NSApplication.shared
        let text = Array("Music 🎵 café".utf8)
        let measured = text.withUnsafeBufferPointer { rasterTextWidth($0.baseAddress, UInt($0.count), 20, 0) }
        precondition(measured > 0)
        precondition(rasterTextWidth(nil, 0, 20, 0) == 0)
        let invalid: [UInt8] = [0xFF]
        invalid.withUnsafeBufferPointer { precondition(rasterTextWidth($0.baseAddress, 1, 20, 0) == 0) }
        precondition(rasterContext(nil, width: 10, height: 10) == nil)
        var pixels = [UInt32](repeating: 0, count: 160 * 64)
        pixels.withUnsafeMutableBufferPointer { buffer in
            precondition(rasterContext(buffer.baseAddress, width: UInt.max, height: 1) == nil)
            text.withUnsafeBufferPointer {
                drawRasterText(buffer.baseAddress, 160, 64, $0.baseAddress, UInt($0.count), 10, 5, 60, 20, 0, 0, 255, 255, 255)
            }
        }
        precondition(pixels.contains { $0 != 0 })
        for y in 0..<64 {
            precondition(pixels[(y * 160)..<(y * 160 + 10)].allSatisfy { $0 == 0 })
            precondition(pixels[(y * 160 + 70)..<(y * 160 + 160)].allSatisfy { $0 == 0 })
        }
        let short = Array("Hi".utf8)
        func rasterColumns(right: Int32) -> [Int] {
            var buffer = [UInt32](repeating: 0, count: 160 * 64)
            buffer.withUnsafeMutableBufferPointer { destination in
                short.withUnsafeBufferPointer {
                    drawRasterText(destination.baseAddress, 160, 64, $0.baseAddress, UInt($0.count), 10, 5, 100, 20, 1, right, 255, 0, 0)
                }
            }
            return (0..<160).filter { x in (0..<64).contains { buffer[$0 * 160 + x] != 0 } }
        }
        let left = rasterColumns(right: 0), right = rasterColumns(right: 1)
        precondition(!left.isEmpty && !right.isEmpty && right.first! > left.last!)
        for kind: Int32 in 0...3 {
            var icon = [UInt32](repeating: 0, count: 96 * 96)
            icon.withUnsafeMutableBufferPointer { drawRasterIcon($0.baseAddress, 96, 96, 48, 48, kind, 0, 1, 2) }
            precondition(icon.contains { $0 != 0 })
        }
        precondition(drawRasterSymbol(nil, 0) == 0 && drawRasterSymbol(nil, -1) == 0)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: scratch) }
        var sourcePixels = [UInt32](repeating: 0xFF0000FF, count: 4)
        sourcePixels.withUnsafeMutableBufferPointer {
            let image = rasterContext($0.baseAddress, width: 2, height: 2)!.makeImage()!
            let destination = CGImageDestinationCreateWithURL(scratch as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            precondition(CGImageDestinationFinalize(destination))
        }
        var decoded = [UInt32](repeating: 0, count: 4)
        decoded.withUnsafeMutableBufferPointer { buffer in
            let path = Array(scratch.path.utf8)
            path.withUnsafeBufferPointer {
                precondition(artworkRasterPixels(buffer.baseAddress, 2, 2, $0.baseAddress, UInt($0.count)))
            }
            precondition(!decodeArtwork(scratch.appendingPathExtension("missing"), pixels: buffer.baseAddress, width: 2, height: 2))
        }
        precondition(decoded == sourcePixels)
    }

    static func checkNowPlayingHelper() {
        let center = NotificationCenter()
        let notifications = NowPlayingNotifications(center: center)
        precondition(notifications.wait(timeout: .now()) == 0)
        for name in NowPlayingNotifications.names {
            center.post(name: Notification.Name(name), object: nil)
            precondition(notifications.wait(timeout: .now()) == 1)
        }
        precondition(notifications.wait(timeout: .now()) == 0)
        let late = NowPlayingReply()
        precondition(late.wait(timeout: .now()) == nil)
        late.complete(["title": "late"])
        let next = NowPlayingReply()
        precondition(next.wait(timeout: .now()) == nil)
        next.complete(["title": "current"])
        precondition(next.wait(timeout: .now())?["title"] as? String == "current")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { preconditionFailure(error.localizedDescription) }
        let art = directory.appendingPathComponent("artwork")
        let output = NowPlayingOutput(artworkURL: art)
        let now = Date(timeIntervalSince1970: 1000)
        var info: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "Track",
                                   "kMRMediaRemoteNowPlayingInfoArtist": "Artist",
                                   "kMRMediaRemoteNowPlayingInfoPlaybackRate": 2,
                                   "kMRMediaRemoteNowPlayingInfoElapsedTime": 10,
                                   "kMRMediaRemoteNowPlayingInfoDuration": 120,
                                   "kMRMediaRemoteNowPlayingInfoTimestamp": now.addingTimeInterval(-3)]
        precondition(output.line(info, now: now) == "Track|||Artist|||0|||2.00|||16.00|||120.00\n")
        info["kMRMediaRemoteNowPlayingInfoArtworkData"] = Data([1, 2, 3])
        precondition(output.line(info, now: now).contains("|||1|||"))
        precondition((try? Data(contentsOf: art)) == Data([1, 2, 3]))
        try? FileManager.default.removeItem(at: art)
        _ = output.line(info, now: now)
        precondition(!FileManager.default.fileExists(atPath: art.path))
        info["kMRMediaRemoteNowPlayingInfoTitle"] = "Another track"
        info["kMRMediaRemoteNowPlayingInfoArtworkData"] = nil
        precondition(output.line(info, now: now).contains("|||0|||"))
        info["kMRMediaRemoteNowPlayingInfoArtworkData"] = Data([4, 5])
        precondition(output.line(info, now: now).contains("|||1|||"))
        precondition((try? Data(contentsOf: art)) == Data([4, 5]))
        info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        precondition(output.line(info, now: now).contains("|||0.00|||10.00|||"))
        info["kMRMediaRemoteNowPlayingInfoTimestamp"] = now.addingTimeInterval(10)
        info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        precondition(output.line(info, now: now).contains("|||1.00|||10.00|||"))
        precondition(output.line(nil) == "\n" && output.line([:]) == "\n")
        precondition(output.line(["kMRMediaRemoteNowPlayingInfoTitle": 42]) == "\n")
        precondition(output.line(["kMRMediaRemoteNowPlayingInfoTitle": String(repeating: "é", count: 128)]) == "\n")
        precondition(output.line(["kMRMediaRemoteNowPlayingInfoTitle": "Track", "kMRMediaRemoteNowPlayingInfoPlaybackRate": true]) == "Track||||||0|||0.00|||0.00|||0.00\n")
        let unwritable = NowPlayingOutput(artworkURL: directory.appendingPathComponent("missing/artwork"))
        precondition(unwritable.line(info, now: now).contains("|||0|||"))
    }

    static func checkIdleAnimation() {
        let layer = CALayer()
        idleKeyframes(layer, property: "opacity", values: [NSNumber(value: 0.5), NSNumber(value: 0.5)],
                      period: 2, phase: 0.5, speed: 2, started: 10)
        precondition(layer.opacity == 0.5 && layer.animation(forKey: "opacity") == nil)
        idleKeyframes(layer, property: "opacity", values: [NSNumber(value: 0.5), NSNumber(value: 1)],
                      period: 2, phase: 2.5, speed: 2, started: 10)
        let animation = layer.animation(forKey: "opacity") as! CAKeyframeAnimation
        precondition(animation.calculationMode == .discrete && animation.duration == 1)
        precondition(animation.beginTime == 10 && animation.timeOffset == 0.25 && animation.repeatCount.isInfinite)
        precondition(animation.keyTimes == [0, 0.5])
        var first = DrawCommand()
        first.dx = 30; first.dy = 40; first.dw = 20; first.dh = 10
        first.clip_x = 5; first.clip_y = 10; first.clip_h = 100
        first.r = 1; first.alpha = 0.5; first.sw = 0.25; first.sh = 0.5
        var second = first
        second.dx = 35; second.alpha = 1; second.sx = 0.25
        let root = CALayer()
        idleCommandLayers(root, frames: [first, second], frameCount: 2, commandCount: 1,
                          image: nil, period: 2, phase: 0, speed: 1, started: 0)
        let child = root.sublayers!.first!
        precondition(child.position == CGPoint(x: 25, y: 60))
        precondition(child.bounds == CGRect(x: 0, y: 0, width: 20, height: 10))
        precondition(child.contentsRect == CGRect(x: 0, y: 0, width: 0.25, height: 0.5))
        precondition(child.magnificationFilter == .nearest && child.anchorPoint == .zero)
        precondition(child.animation(forKey: "bounds") == nil && child.animation(forKey: "position") != nil)
        precondition(child.animation(forKey: "contentsRect") != nil && child.animation(forKey: "opacity") != nil)
        precondition(!startIdleAnimation(nil, 0, 1, nil, 0, 0, 1, 0, 1))
        withUnsafePointer(to: &first) {
            precondition(!startIdleAnimation($0, 1, 1, nil, 0, 0, 1, 0, 0))
            precondition(!startIdleAnimation($0, 1, 1, nil, UInt.max, 2, 1, 0, 1))
            precondition(!startIdleAnimation($0, 1, 1, nil, 0, 0, 1, 0, 1))
        }
        let device = MTLCreateSystemDefaultDevice()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared
        idleTestTexture = device.makeTexture(descriptor: descriptor)!
        let pixel: [UInt8] = [255, 0, 0, 255]
        pixel.withUnsafeBytes {
            idleTestTexture!.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        idleTestSurface.bounds = CGRect(x: 0, y: 0, width: 200, height: 160)
        first.clip_w = 100; first.clip_radius = 6
        withUnsafePointer(to: &first) {
            precondition(startIdleAnimation($0, 1, 1, nil, 0, 0, 1, 0, 1))
        }
        first.dx = 200
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        let attached = idleTestSurface.sublayers!.first!
        precondition(attached.frame == CGRect(x: 5, y: 50, width: 100, height: 100))
        precondition(attached.isGeometryFlipped && attached.masksToBounds && attached.cornerRadius == 6)
        precondition(attached.sublayers!.first!.position == CGPoint(x: 25, y: 60))
        let image = attached.sublayers!.first!.contents as! CGImage
        precondition(image.width == 1 && image.height == 1)
        stopIdleAnimation()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        precondition(idleTestSurface.sublayers?.isEmpty != false)
        idleTestTexture = nil
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
