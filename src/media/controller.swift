import Foundation
import Darwin

func monotonicTime() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

final class MediaSourceRouter {
    private let lock = NSLock()
    private var checked: Double = -.infinity
    private var cached: UInt8 = 0

    func resolve(_ configured: UInt8, now: Double, probe: () -> Bool) -> UInt8 {
        guard configured == 3 else { return configured }
        lock.lock()
        defer { lock.unlock() }
        if now < checked || now - checked >= 2 {
            cached = probe() ? 2 : 0
            checked = now
        }
        return cached
    }
}

private let sourceRouter = MediaSourceRouter()

func queryMediaSource(_ source: UInt8, capacity: Int = 1024) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: capacity)
    let count = bytes.withUnsafeMutableBufferPointer {
        source == 2 ? querySpotifast($0.baseAddress, UInt(capacity)) : querySpotify($0.baseAddress, UInt(capacity))
    }
    return Array(bytes.prefix(Int(count)))
}

func activeMediaSource() -> UInt8 {
    sceneLock.lock()
    let configured = widgetStatePointer().pointee.setting_source
    sceneLock.unlock()
    return sourceRouter.resolve(configured, now: monotonicTime()) {
        let reply = queryMediaSource(2, capacity: 32)
        return !reply.isEmpty && reply != Array("CLOSED".utf8)
    }
}

// MediaRemote commands use next=4/previous=5; direct backend commands use 4/3.
func backendCommand(_ command: UInt32) -> Int32? {
    switch command {
    case 0, 1, 2: return Int32(command)
    case 3: return 1
    case 4: return 4
    case 5: return 3
    default: return nil
    }
}

@_cdecl("wallify_native_media_command")
public func executeMediaCommand(_ command: UInt32) {
    guard let direct = backendCommand(command) else { return }
    switch activeMediaSource() {
    case 1: controlSpotify(direct)
    case 2: controlSpotifast(direct)
    default: sendSystemMediaCommand(command)
    }
}

@_cdecl("wallify_native_media_seek")
public func executeMediaSeek(_ target: Double) {
    guard target.isFinite, target >= 0 else { return }
    switch activeMediaSource() {
    case 1: seekSpotify(target)
    case 2: seekSpotifast(target)
    default: seekSystemMedia(target)
    }
}

func optimisticPlayback(_ state: UnsafeMutablePointer<WallifyWidgetState>, now: Double) -> UInt32 {
    let rate: Double = state.pointee.global_rate > 0 ? 0 : 1
    let position = playbackPosition(state.pointee.playback_clock, now: now, duration: state.pointee.global_duration)
    requestPlayback(&state.pointee.playback_state, rate > 0, now)
    state.pointee.global_rate = rate
    state.pointee.global_elapsed = position
    synchronizePlayback(&state.pointee.playback_clock, position, rate, now, state.pointee.global_duration, true)
    state.pointee.global_rate_lock = 1
    state.pointee.global_rate_lock_until = now + 1.5
    return rate > 0 ? 0 : 1
}

@_cdecl("wallify_native_toggle_playback")
public func toggleWidgetPlayback() {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    enqueueMediaCommand(optimisticPlayback(widgetStatePointer(), now: monotonicTime()))
    requestWidgetFrame()
}

@_cdecl("wallify_native_media_key")
public func handleWidgetMediaKey(_ code: Int32) {
    sceneLock.lock()
    let target = widgetStatePointer().pointee.setting_media_key_target
    sceneLock.unlock()
    guard target != 0, let command: UInt32 = code == 16 ? 2 : code == 19 ? 4 : code == 20 ? 5 : nil else { return }
    if target == 1 {
        if code == 16 { toggleWidgetPlayback() } else { enqueueMediaCommand(command) }
    } else if let direct = backendCommand(command) {
        if target == 2 { controlSpotify(direct) } else if target == 3 { controlSpotifast(direct) }
    }
}

func utf8Prefix(_ bytes: [UInt8], limit: Int) -> [UInt8] {
    var count = min(bytes.count, max(0, limit))
    if count < bytes.count {
        while count > 0 && bytes[count] & 0xc0 == 0x80 { count -= 1 }
    }
    return Array(bytes.prefix(count))
}

func updateTrackText(_ title: [UInt8], _ artist: [UInt8], state: UnsafeMutablePointer<WallifyWidgetState>) {
    let t = utf8Prefix(title, limit: 256), a = utf8Prefix(artist, limit: 256)
    withUnsafeMutableBytes(of: &state.pointee.global_title) { $0.copyBytes(from: t) }
    withUnsafeMutableBytes(of: &state.pointee.global_artist) { $0.copyBytes(from: a) }
    state.pointee.global_title_len = t.count
    state.pointee.global_artist_len = a.count
}

final class MediaCoordinator {
    private var source: UInt8?
    private var artworkURL = [UInt8]()
    private var noTrackMisses = 0
    private var emptyPolls = 0
    private var emptyArtPolls = 0
    private let clearArtwork: () -> Void
    private let extractColor: () -> Void
    private let download: ([UInt8]) -> Void
    private let cancel: () -> Void

    init(clear: @escaping () -> Void = { wallify_clear_artwork() },
         extract: @escaping () -> Void = { wallify_extract_color() },
         download: @escaping ([UInt8]) -> Void = { bytes in
             bytes.withUnsafeBufferPointer { downloadArtwork($0.baseAddress, UInt($0.count)) }
         }, cancel: @escaping () -> Void = { cancelArtworkDownload() }) {
        clearArtwork = clear; extractColor = extract; self.download = download; self.cancel = cancel
    }

    func select(_ next: UInt8) {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        guard source != next else { return }
        cancel()
        source = next
        _ = stateFlag(0, 1, false)
        _ = stateFlag(1, 1, false)
        noTrackMisses = 0; emptyPolls = 0; emptyArtPolls = 0; artworkURL = []
        widgetStatePointer().pointee.artwork_refresh_pending = true
        widgetStatePointer().pointee.global_title_len = 0
    }

    private func clearTrack(title: String = "", artist: String = "") {
        let state = widgetStatePointer()
        updateTrackText(Array(title.utf8), Array(artist.utf8), state: state)
        state.pointee.global_rate = 0
        state.pointee.global_elapsed = 0
        state.pointee.global_duration = 0
        state.pointee.global_has_artwork = false
        clearArtwork()
        requestWidgetFrame()
    }

    // Returns the retry interval for empty/CLOSED/NO_TRACK replies.
    func apply(_ bytes: [UInt8], source: UInt8, spotifyRunning: Bool = false, now: Double) -> Double? {
        sceneLock.lock()
        defer { sceneLock.unlock() }
        let state = widgetStatePointer()
        if source != 0 {
            guard !bytes.isEmpty else { return 2 }
            let closed = bytes == Array("CLOSED".utf8)
            if closed && source == 1 && spotifyRunning {
                _ = stateFlag(0, 1, false)
                return 2
            }
            if stateFlag(0, 1, closed) != closed { artworkURL = []; requestWidgetFrame() }
            if closed {
                cancel(); _ = stateFlag(1, 1, false); noTrackMisses = 0
                let title = source == 2 ? "Spotifast is Closed" : "Spotify is Closed"
                if widgetTitle() != title { clearTrack(title: title, artist: "Click to Launch") }
                return 2
            }
            if bytes == Array("NO_TRACK".utf8) {
                noTrackMisses = min(3, noTrackMisses + 1)
                if noTrackMisses < 3 && stateFlag(1, 0, false) { return 2 }
                cancel(); _ = stateFlag(1, 1, false)
                let title = source == 2 ? "Spotifast" : "Spotify"
                if widgetTitle() != title { clearTrack(title: title, artist: "No Track Playing") }
                return 2
            }
        } else if bytes.isEmpty {
            emptyPolls = min(3, emptyPolls + 1)
            if emptyPolls >= 3 && (state.pointee.global_title_len > 0 || state.pointee.global_rate > 0 || state.pointee.global_has_artwork) {
                clearTrack()
            }
            return nil
        } else { emptyPolls = 0 }
        guard let item = parseMediaPayload(bytes, format: source == 0 ? 2 : source == 2 ? 1 : 0) else { return nil }
        func text(_ span: WallifyMediaSpan) -> [UInt8] { Array(bytes[span.offset..<span.offset + span.count]) }
        let title = utf8Prefix(text(item.title), limit: 256), artist = utf8Prefix(text(item.artist), limit: 256)
        if source == 0 && title.isEmpty { return nil }
        noTrackMisses = 0
        if source == 1 && !title.isEmpty { _ = stateFlag(1, 1, true) }
        let titleChanged = withUnsafeBytes(of: state.pointee.global_title) { Array($0.prefix(state.pointee.global_title_len)) != title }
        let artistChanged = withUnsafeBytes(of: state.pointee.global_artist) { Array($0.prefix(state.pointee.global_artist_len)) != artist }
        let accept = acceptPlayback(&state.pointee.playback_state, item.rate > 0, now, titleChanged)
        if now >= state.pointee.global_rate_lock_until || titleChanged {
            state.pointee.global_rate_lock = 0; state.pointee.global_rate_lock_until = 0
        }
        let elapsedChanged = abs(item.elapsed - state.pointee.global_elapsed) > (source == 0 ? 0 : 1.5)
        let art = text(item.artwork)
        let artChanged = source != 0 && art != artworkURL
        guard titleChanged || artistChanged || item.rate != state.pointee.global_rate || elapsedChanged ||
              item.duration != state.pointee.global_duration || artChanged || (state.pointee.artwork_refresh_pending && item.has_artwork) else { return nil }
        updateTrackText(title, artist, state: state)
        if accept && !state.pointee.global_is_dragging && (state.pointee.global_rate_lock == 0 || titleChanged) {
            synchronizePlayback(&state.pointee.playback_clock, item.elapsed, item.rate, now, item.duration, titleChanged)
            state.pointee.global_rate = item.rate
            state.pointee.global_elapsed = item.elapsed
        }
        state.pointee.global_duration = item.duration
        if source != 0 {
            if !art.isEmpty && artChanged { artworkURL = art; download(art) }
            else if art.isEmpty && titleChanged { cancel(); artworkURL = []; state.pointee.global_has_artwork = false }
        } else {
            if titleChanged || artistChanged { state.pointee.artwork_refresh_pending = true; emptyArtPolls = 0 }
            if item.has_artwork && state.pointee.artwork_refresh_pending {
                state.pointee.artwork_refresh_pending = false
                // The helper deduplicates artwork writes; the current image can already be in art.raw.
                _ = rename("/tmp/mrc_artwork", "/tmp/art.raw")
                state.pointee.global_has_artwork = true
                extractColor()
            } else if !item.has_artwork && state.pointee.artwork_refresh_pending {
                emptyArtPolls = min(30, emptyArtPolls + 1)
                if emptyArtPolls >= 30 {
                    state.pointee.artwork_refresh_pending = false
                    state.pointee.global_has_artwork = false
                    clearArtwork()
                }
            }
        }
        requestWidgetFrame()
        return nil
    }
}

@_cdecl("wallify_native_artwork_downloaded")
public func receiveArtwork(_ available: Bool) {
    sceneLock.lock()
    defer { sceneLock.unlock() }
    widgetStatePointer().pointee.global_has_artwork = available
    widgetStatePointer().pointee.artwork_refresh_pending = available
    if available { wallify_extract_color() }
    requestWidgetFrame()
}

@_cdecl("wallify_metadata_loop")
public func runMetadataWorker() {
    let coordinator = MediaCoordinator()
    while true {
        let source = activeMediaSource()
        coordinator.select(source)
        if source == 0 {
            runNowPlayingHelper { bytes in
                guard activeMediaSource() == 0 else { return false }
                _ = coordinator.apply(bytes, source: 0, now: monotonicTime())
                return true
            }
            Thread.sleep(forTimeInterval: 2)
        } else {
            let reply = autoreleasepool { queryMediaSource(source) }
            let running = source == 1 && reply == Array("CLOSED".utf8) && isSpotifyRunning() != 0
            let retry = coordinator.apply(reply, source: source, spotifyRunning: running, now: monotonicTime())
            if let retry { Thread.sleep(forTimeInterval: retry) }
            else if source == 1 { _ = waitForSpotifyEvent(2000) }
            else { Thread.sleep(forTimeInterval: 1) }
        }
    }
}
