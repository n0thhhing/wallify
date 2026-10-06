import AppKit
import Darwin
import ImageIO
import Metal
import UniformTypeIdentifiers

let terminalMode = CommandLine.arguments.contains("--cli")

func terminalPixelSize(width: Double, height: Double, scale: Double) -> (width: Int, height: Int) {
    (max(1, Int(ceil(width * scale))), max(1, Int(ceil(height * scale))))
}

enum TerminalEvent: Equatable {
    case key(UInt8), mouse(Int, Int, Int, Bool)
    case graphics(Int, String), deviceAttributes
}

struct TerminalInput {
    private var bytes = [UInt8]()
    private var controlString = false
    private var escaped = false
    private var controlBytes = [UInt8]()

    mutating func feed(_ incoming: [UInt8]) -> [TerminalEvent] {
        bytes += incoming
        var events = [TerminalEvent](), offset = 0
        while offset < bytes.count {
            let byte = bytes[offset]
            if controlString {
                if byte == 7 || escaped && byte == 92 {
                    if escaped && !controlBytes.isEmpty { controlBytes.removeLast() }
                    if controlBytes.first == 71 {
                        let reply = String(decoding: controlBytes.dropFirst(), as: UTF8.self).split(separator: ";", maxSplits: 1)
                        if reply.count == 2,
                           let field = reply[0].split(separator: ",").first(where: { $0.hasPrefix("i=") }),
                           let id = Int(field.dropFirst(2)) { events.append(.graphics(id, String(reply[1]))) }
                    }
                    controlString = false; controlBytes.removeAll()
                } else {
                    controlBytes.append(byte)
                    if controlBytes.count > 4096 { controlBytes.removeAll() }
                }
                escaped = byte == 27; offset += 1; continue
            }
            if byte != 27 { events.append(.key(byte)); offset += 1; continue }
            guard offset + 1 < bytes.count else { break }
            if [95, 80, 93].contains(bytes[offset + 1]) {
                controlString = true; escaped = false; controlBytes.removeAll(); offset += 2; continue
            }
            guard bytes[offset + 1] == 91 else { offset += 2; continue }
            guard let end = bytes[(offset + 2)...].firstIndex(where: { (64...126).contains($0) }) else { break }
            if bytes[offset + 2] == 60, [77, 109].contains(bytes[end]) {
                let fields = String(decoding: bytes[(offset + 3)..<end], as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
                if fields.count == 3, let button = Int(fields[0]), let x = Int(fields[1]), let y = Int(fields[2]),
                   (0...255).contains(button), (1...1_000_000).contains(x), (1...1_000_000).contains(y) {
                    events.append(.mouse(button, x - 1, y - 1, bytes[end] == 109))
                }
            } else if bytes[end] == 99 && bytes[offset + 2] == 63 { events.append(.deviceAttributes) }
            else if bytes[end] == 68 { events.append(.key(112)) }
            else if bytes[end] == 67 { events.append(.key(110)) }
            offset = end + 1
        }
        bytes.removeFirst(offset)
        if bytes.count > 4096 { bytes.removeAll() }
        return events
    }
}

func kittyPassthrough(_ command: String, tmux: Bool) -> String {
    tmux ? "\u{1b}Ptmux;\(command.replacingOccurrences(of: "\u{1b}", with: "\u{1b}\u{1b}"))\u{1b}\\" : command
}

func queryTerminalGraphics(tmux: Bool) throws -> Bool {
    let id = Int(UInt32.random(in: 3...UInt32.max))
    let query = "\u{1b}_Gi=\(id),s=1,v=1,a=q,t=d,f=24;AAAA\u{1b}\\\u{1b}[c"
    try FileHandle.standardOutput.write(contentsOf: Data(kittyPassthrough(query, tmux: tmux).utf8))
    let deadline = monotonicTime() + 2
    var parser = TerminalInput(), descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    while monotonicTime() < deadline {
        let result = poll(&descriptor, 1, Int32(max(1, (deadline - monotonicTime()) * 1000)))
        if result < 0 { if errno == EINTR { continue }; return false }
        if result == 0 { return false }
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { return false }
        for event in parser.feed(Array(bytes.prefix(count))) {
            if case .graphics(let replyID, let status) = event, replyID == id { return status == "OK" }
            if event == .deviceAttributes { return false }
        }
    }
    return false
}

func kittyImage(_ png: Data, id: Int, columns: Int, rows: Int, tmux: Bool) -> String {
    let payload = Array(png.base64EncodedString().utf8)
    var result = ""
    for start in stride(from: 0, to: payload.count, by: 4096) {
        let end = min(start + 4096, payload.count), more = end < payload.count ? 1 : 0
        let header = start == 0 ? "a=T,f=100,i=\(id),p=1,C=1,q=2,c=\(columns),r=\(rows),m=\(more)" : "m=\(more),q=2"
        let command = "\u{1b}_G\(header);\(String(decoding: payload[start..<end], as: UTF8.self))\u{1b}\\"
        result += kittyPassthrough(command, tmux: tmux)
    }
    return result
}

@MainActor final class TerminalDisplay {
    static var current: TerminalDisplay?
    private var original = termios()
    private var active = false
    private var input = TerminalInput()
    private var sources = [DispatchSourceProtocol]()
    private var target: MTLTexture?
    private var imageID = 1
    private var column = 0, row = 0
    private var drag: (x: Int, y: Int, column: Int, row: Int)?
    private var moved = false
    private let tmux = ProcessInfo.processInfo.environment["TMUX"] != nil
    private var pixelMouse = false
    private let scale = Double(NSScreen.main?.backingScaleFactor ?? 1)

    private func dimensions() -> (columns: Int, rows: Int, cellWidth: Double, cellHeight: Double) {
        var size = winsize()
        _ = ioctl(STDIN_FILENO, TIOCGWINSZ, &size)
        let columns = max(1, Int(size.ws_col)), rows = max(1, Int(size.ws_row))
        return (columns, rows, size.ws_xpixel > 0 ? Double(size.ws_xpixel) / Double(columns) : 8,
                size.ws_ypixel > 0 ? Double(size.ws_ypixel) / Double(rows) : 16)
    }

    func start() throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw NSError(domain: "Wallify", code: 1, userInfo: [NSLocalizedDescriptionKey: "--cli requires an interactive terminal supporting the Kitty graphics protocol."])
        }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw POSIXError(.ENOTTY) }
        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { throw POSIXError(.ENOTTY) }
        do {
            guard try queryTerminalGraphics(tmux: tmux) else {
                throw NSError(domain: "Wallify", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Terminal did not confirm Kitty graphics protocol support. In tmux, enable allow-passthrough."])
            }
        } catch {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            throw error
        }
        active = true
        atexit { MainActor.assumeIsolated { TerminalDisplay.current?.restore() } }
        var size = winsize()
        _ = ioctl(STDIN_FILENO, TIOCGWINSZ, &size)
        pixelMouse = !tmux && size.ws_xpixel > 0 && size.ws_ypixel > 0
        do { try write("\u{1b}[?1049h\u{1b}[?25l\u{1b}[?1003h\u{1b}[?1006h" + (pixelMouse ? "\u{1b}[?1016h" : "")) }
        catch { restore(); throw error }
        let reader = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        reader.setEventHandler { [self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            if count == 0 { finish(); return }
            if count < 0 { if errno != EINTR { finish() }; return }
            for event in input.feed(Array(buffer.prefix(count))) { handle(event) }
        }
        sources.append(reader); reader.resume()
        for number in [SIGINT, SIGTERM, SIGHUP, SIGWINCH] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [self] in
                if number == SIGWINCH { requestWidgetFrame() } else { finish() }
            }
            sources.append(source); source.resume()
        }
        signal(SIGPIPE, SIG_IGN)
    }

    private func write(_ value: String) throws { try FileHandle.standardOutput.write(contentsOf: Data(value.utf8)) }

    func restore() {
        guard active else { return }
        active = false
        for source in sources { source.cancel() }
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        let deletion = "\u{1b}_Ga=d,d=I,i=1,q=2\u{1b}\\\u{1b}_Ga=d,d=I,i=2,q=2\u{1b}\\"
        try? write(kittyPassthrough(deletion, tmux: tmux) +
            "\u{1b}[?1016l\u{1b}[?1003l\u{1b}[?1006l\u{1b}[?25h\u{1b}[?1049l")
    }

    private func finish() { restore(); Darwin.exit(0) }

    private func handle(_ event: TerminalEvent) {
        switch event {
        case .key(3), .key(113): finish()
        case .key(32): toggleWidgetPlayback()
        case .key(112): enqueueMediaCommand(5)
        case .key(110): enqueueMediaCommand(4)
        case .key(49...53):
            if case let .key(key) = event { applyWidgetInt(14, Int32(key - 49)) }
        case .key(109):
            sceneLock.lock(); let source = widgetStatePointer().pointee.setting_source; sceneLock.unlock()
            applyWidgetInt(13, Int32((source + 1) % 4))
        case .key(115): showSettingsWindow()
        case .mouse(let button, let x, let y, let release): pointer(button, x, y, release)
        default: break
        }
    }

    private func pointer(_ button: Int, _ x: Int, _ y: Int, _ release: Bool) {
        let cells = dimensions(), pixelX = pixelMouse ? Double(x) : (Double(x) + 0.5) * cells.cellWidth
        let pixelY = pixelMouse ? Double(y) : (Double(y) + 0.5) * cells.cellHeight
        if button & 3 == 2 { if !release && button & 32 == 0 { showWidgetContextMenu() }; return }
        guard button & 64 == 0 else { return }
        sceneLock.lock()
        defer { sceneLock.unlock() }
        let state = widgetStatePointer(), layout = sceneLayout, geometry = layout.inputGeometry(state.pointee)
        let pixels = terminalPixelSize(width: layout.width, height: layout.height, scale: scale)
        let columns = max(1, Int(ceil(Double(pixels.width) / cells.cellWidth)))
        let rows = max(1, Int(ceil(Double(pixels.height) / cells.cellHeight)))
        column = min(column, max(0, cells.columns - columns)); row = min(row, max(0, cells.rows - rows))
        let localX = (pixelX - Double(column) * cells.cellWidth) * layout.width / (Double(columns) * cells.cellWidth)
        let localY = (pixelY - Double(row) * cells.cellHeight) * layout.height / (Double(rows) * cells.cellHeight)
        let pressed = !release && button & 32 == 0 && button & 3 == 0
        if let start = drag {
            if !release {
                column = max(0, min(cells.columns - columns, start.column + Int(pixelX / cells.cellWidth) - start.x))
                row = max(0, min(cells.rows - rows, start.row + Int(pixelY / cells.cellHeight) - start.y))
                moved = moved || column != start.column || row != start.row
            } else {
                drag = nil
                if !moved && spotifyIsIdle() && state.pointee.setting_idle_style != 0 {
                    state.pointee.cat_pet_until = state.pointee.animation_time + 2.5
                } else if !moved && spotifyIsIdle() {
                    if state.pointee.setting_source == 2 { openSpotifast() } else { openSpotify() }
                }
            }
            requestWidgetFrame(); return
        }
        func contains(_ rect: WallifyCardRect) -> Bool { roundedContains(rect.x, rect.y, rect.w, rect.h, rect.radius, localX, localY) }
        let controls = geometry.controls_visible && !spotifyIsIdle() &&
            [geometry.buttons.0, geometry.buttons.1, geometry.buttons.2].contains(where: contains)
        let progress = geometry.progress_visible && !spotifyIsIdle() && state.pointee.global_duration > 0 && contains(geometry.bar)
        let label = !spotifyIsIdle() && (contains(geometry.title) || contains(geometry.artist))
        if pressed && contains(geometry.card) && !controls && !progress && !label {
            drag = (Int(pixelX / cells.cellWidth), Int(pixelY / cells.cellHeight), column, row); moved = false; return
        }
        let actions = reducePointer(localX, localY, kind: release ? 2 : pressed ? 1 : 0,
            mouse: NSPoint(x: pixelX, y: -pixelY), now: monotonicTime(), width: layout.width, height: layout.height,
            geometry: geometry, state: state, idle: spotifyIsIdle(), snap: { _, _ in WallifyPanelSnap() })
        for action in actions {
            switch action {
            case .redraw: requestWidgetFrame()
            case .toggle: toggleWidgetPlayback()
            case .command(let command): enqueueMediaCommand(command)
            case .seek(let position): enqueueMediaSeek(position)
            case .openTrack: openMediaLabel(artist: false)
            case .searchArtist: openMediaLabel(artist: true)
            default: break
            }
        }
    }

    func present(_ renderer: MetalRenderer, size: SIMD2<Float>, statics: UnsafePointer<DrawCommand>, staticCount: Int,
                 dynamics: UnsafePointer<DrawCommand>, dynamicCount: Int, textures: [MTLTexture?]) {
        guard active, let device = renderer.device, let command = renderer.queue?.makeCommandBuffer() else { return }
        let (width, height) = terminalPixelSize(width: Double(size.x), height: Double(size.y), scale: scale)
        if target?.width != width || target?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
            target = device.makeTexture(descriptor: descriptor)
        }
        guard let target, renderer.encodeScene(command, target: target, staticCommands: statics, staticCount: staticCount,
            dynamicCommands: dynamics, dynamicCount: dynamicCount, size: size, scale: CGFloat(scale), textures: textures) else { return }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return }
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        let cells = dimensions(), columns = max(1, Int(ceil(Double(width) / cells.cellWidth)))
        let rows = max(1, Int(ceil(Double(height) / cells.cellHeight)))
        column = min(column, max(0, cells.columns - columns)); row = min(row, max(0, cells.rows - rows))
        imageID = imageID == 1 ? 2 : 1
        // ponytail: PNG encodes each frame; use shared memory if terminal transfer becomes a bottleneck.
        let frame = kittyImage(png as Data, id: imageID, columns: columns, rows: rows, tmux: tmux)
        let deletion = "\u{1b}_Ga=d,d=I,i=\(imageID == 1 ? 2 : 1),q=2\u{1b}\\"
        do {
            try write("\u{1b}[\(row + 1);\(column + 1)H" + frame +
                kittyPassthrough(deletion, tmux: tmux))
        } catch { finish() }
    }
}
