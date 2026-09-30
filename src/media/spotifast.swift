import AppKit
import Darwin

private let spotifastBundleIdentifier = "me.paolino.fastpotify"

final class SpotifastConnection {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private let port: UInt16

    init(port: UInt16 = 47113) { self.port = port }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    private func connectSocket() -> Int32? {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        var noSignal: Int32 = 1
        guard setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal))) == 0 else {
            Darwin.close(socket)
            return nil
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { Darwin.close(socket); return nil }
        return socket
    }

    func request(_ verb: String, persistent: Bool = false) -> [UInt8]? {
        guard !verb.contains("\n"), !verb.contains("\r"), verb.utf8.count < 116 else { return nil }
        if !persistent {
            guard let socket = connectSocket() else { return nil }
            defer { Darwin.close(socket) }
            return exchange(verb, socket: socket)
        }
        lock.lock()
        defer { lock.unlock() }
        for _ in 0..<2 {
            if descriptor < 0 { descriptor = connectSocket() ?? -1 }
            if descriptor >= 0 {
                if let reply = exchange(verb, socket: descriptor) { return reply }
                Darwin.close(descriptor)
                descriptor = -1
            }
        }
        return nil
    }

    private func exchange(_ verb: String, socket: Int32) -> [UInt8]? {
        let request = Array("fastpotify:\(verb)\n".utf8)
        let written = request.withUnsafeBytes { bytes -> Bool in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(socket, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard written else { return nil }
        var reply = [UInt8](repeating: 0, count: 2048)
        var offset = 0
        while offset < reply.count {
            let count = reply.withUnsafeMutableBytes {
                Darwin.read(socket, $0.baseAddress!.advanced(by: offset), $0.count - offset)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return nil }
            offset += count
            if reply[..<offset].contains(10) { return Array(reply[..<offset]) }
        }
        // An incomplete line must not contaminate the next persistent query.
        return nil
    }
}

private let spotifastConnection = SpotifastConnection()

func spotifastControlVerb(_ command: Int32) -> String? {
    switch command {
    case 0: return "play"
    case 1: return "pause"
    case 2: return "playpause"
    case 3: return "previous"
    case 4: return "next"
    default: return nil
    }
}

func spotifastSeekVerb(_ position: Double) -> String? {
    let milliseconds = max(0, position * 1000)
    guard position.isFinite, milliseconds < Double(UInt64.max) else { return nil }
    return "seek-to \(UInt64(milliseconds))"
}

@_cdecl("widget_spotifast_control")
public func controlSpotifast(_ command: Int32) {
    if let verb = spotifastControlVerb(command) { _ = spotifastConnection.request(verb) }
}

@_cdecl("widget_spotifast_seek")
public func seekSpotifast(_ position: Double) {
    if let verb = spotifastSeekVerb(position) { _ = spotifastConnection.request(verb) }
}

@_cdecl("widget_is_spotifast_running")
public func isSpotifastRunning() -> Int32 {
    autoreleasepool {
        NSRunningApplication.runningApplications(withBundleIdentifier: spotifastBundleIdentifier).isEmpty ? 0 : 1
    }
}

@_cdecl("widget_open_spotifast")
public func openSpotifast() {
    if spotifastConnection.request("show") != nil { return }
    DispatchQueue.main.async {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: spotifastBundleIdentifier) {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error { NSLog("spotifast: launch failed: %@", error.localizedDescription) }
            }
        } else if !workspace.open(URL(string: "spotify:")!) {
            NSLog("spotifast: application and spotify URL handler were not found")
        }
    }
}

func spotifastQueryResult(_ reply: [UInt8]?) -> [UInt8] {
    guard let reply = reply else { return Array("CLOSED".utf8) }
    let trimmed = String(decoding: reply, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \r\n"))
    if ["fastpotify:now stopped", "fastpotify:now", "stopped"].contains(trimmed) { return Array("NO_TRACK".utf8) }
    return reply
}

@_cdecl("widget_query_spotifast")
public func querySpotifast(_ buffer: UnsafeMutablePointer<UInt8>?, _ capacity: UInt) -> UInt {
    guard let buffer = buffer, capacity > 0 else { return 0 }
    let result = spotifastQueryResult(spotifastConnection.request("nowplaying", persistent: true))
    let count = min(UInt(result.count), capacity)
    result.withUnsafeBufferPointer { bytes in
        if count > 0 { buffer.update(from: bytes.baseAddress!, count: Int(count)) }
    }
    return count
}
