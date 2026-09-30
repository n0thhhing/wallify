import Foundation
import Darwin

// Notifications retain callbacks into MediaRemote, so keep the framework loaded.
private let metadataLibrary = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)

private func metadataSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    guard let library = metadataLibrary else { return nil }
    return dlsym(library, name)
}

final class NowPlayingNotifications {
    static let names = ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]
    private let center: NotificationCenter
    private let semaphore = DispatchSemaphore(value: 0)
    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
        observers = Self.names.map { name in
            center.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { [semaphore] _ in
                semaphore.signal()
            }
        }
    }

    deinit { observers.forEach { center.removeObserver($0) } }

    func wait(timeout: DispatchTime = .now() + 2) -> Int32 {
        semaphore.wait(timeout: timeout) == .success ? 1 : 0
    }
}

private var metadataNotifications: NowPlayingNotifications?

@_cdecl("mrc_notifications_init")
public func initializeMetadataNotifications() {
    let initialize = {
        guard metadataNotifications == nil else { return }
        metadataNotifications = NowPlayingNotifications()
        if let symbol = metadataSymbol("MRMediaRemoteRegisterForNowPlayingNotifications") {
            typealias Register = @convention(c) (DispatchQueue) -> Void
            unsafeBitCast(symbol, to: Register.self)(DispatchQueue.global(qos: .utility))
        }
    }
    if Thread.isMainThread { initialize() } else { DispatchQueue.main.sync(execute: initialize) }
}

@_cdecl("mrc_wait_for_notification")
public func waitForMetadataNotification() -> Int32 { metadataNotifications?.wait() ?? 0 }

final class NowPlayingOutput {
    private var lastTitle: String?
    private var lastArtist: String?
    private var lastArtwork: Data?
    private var hasArtwork = false
    private let artworkURL: URL

    init(artworkURL: URL = URL(fileURLWithPath: "/tmp/mrc_artwork")) { self.artworkURL = artworkURL }

    func line(_ info: [String: Any]?, now: Date = Date()) -> String {
        guard let info = info else { return "\n" }
        func text(_ key: String) -> String? {
            guard let value = info["kMRMediaRemoteNowPlayingInfo" + key] as? String,
                  value.utf8.count < 256 else { return nil }
            return value
        }
        func number(_ key: String) -> Double {
            guard let value = info["kMRMediaRemoteNowPlayingInfo" + key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return 0 }
            return value.doubleValue
        }
        let title = text("Title")
        let artist = text("Artist")
        let rate = number("PlaybackRate")
        var elapsed = number("ElapsedTime")
        if let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
            let delta = now.timeIntervalSince(timestamp)
            if delta.isFinite && delta > 0 && rate > 0 { elapsed += delta * rate }
        }
        let duration = number("Duration")
        if lastTitle != (title ?? "") || lastArtist != (artist ?? "") || !hasArtwork {
            hasArtwork = false
            if let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, !artwork.isEmpty {
                if artwork == lastArtwork {
                    hasArtwork = true
                } else {
                    do {
                        try artwork.write(to: artworkURL, options: .atomic)
                        lastArtwork = artwork
                        hasArtwork = true
                    } catch {
                        NSLog("metadata: artwork write failed: %@", error.localizedDescription)
                    }
                }
            } else { lastArtwork = nil }
        }
        guard title != nil || artist != nil else { return "\n" }
        lastTitle = title ?? ""
        lastArtist = artist ?? ""
        return String(format: "%@|||%@|||%d|||%.2f|||%.2f|||%.2f\n",
                      locale: Locale(identifier: "en_US_POSIX"), title ?? "", artist ?? "",
                      hasArtwork ? 1 : 0, rate, elapsed, duration)
    }
}

// Each query owns its completion token. A delayed callback cannot publish a
// stale line or satisfy the next query's wait after this query times out.
final class NowPlayingReply {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var info: [String: Any]?

    func complete(_ dictionary: NSDictionary?) {
        lock.lock()
        info = dictionary as? [String: Any]
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: DispatchTime) -> [String: Any]? {
        guard semaphore.wait(timeout: timeout) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return info
    }
}

private let nowPlayingOutput = NowPlayingOutput()

private func writeMetadataLine(_ line: String) {
    let bytes = Array(line.utf8)
    bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.write(STDOUT_FILENO, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { exit(0) }
            offset += count
        }
    }
}

@_cdecl("mrc_printNowPlayingInfo")
public func printNowPlayingInfo() {
    initializeMetadataNotifications()
    autoreleasepool {
        guard let symbol = metadataSymbol("MRMediaRemoteGetNowPlayingInfo") else { writeMetadataLine("\n"); return }
        typealias Get = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
        let reply = NowPlayingReply()
        unsafeBitCast(symbol, to: Get.self)(DispatchQueue.global()) { reply.complete($0) }
        writeMetadataLine(nowPlayingOutput.line(reply.wait(timeout: .now() + .milliseconds(100))))
    }
}

@_cdecl("mrc_sendCommand")
public func sendMetadataCommand(_ command: UInt32) {
    guard let symbol = metadataSymbol("MRMediaRemoteSendCommand") else { return }
    typealias Send = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Void
    unsafeBitCast(symbol, to: Send.self)(command, nil)
    Thread.sleep(forTimeInterval: 0.1)
}
