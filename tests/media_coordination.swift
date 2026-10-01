import Foundation

func checkMediaCoordination() {
    let state = widgetStatePointer()
    let original = state.pointee
    let closed = stateFlag(0, 0, false), track = stateFlag(1, 0, false)
    defer { state.pointee = original; _ = stateFlag(0, 1, closed); _ = stateFlag(1, 1, track) }
    let router = MediaSourceRouter()
    var probes = 0
    precondition(router.resolve(1, now: 0) { probes += 1; return true } == 1 && probes == 0)
    precondition(router.resolve(3, now: 0) { probes += 1; return true } == 2)
    precondition(router.resolve(3, now: 1) { probes += 1; return false } == 2 && probes == 1)
    precondition(router.resolve(3, now: 2) { probes += 1; return false } == 0 && probes == 2)
    precondition((0...5).map { backendCommand(UInt32($0))! } == [0, 1, 2, 1, 4, 3])
    precondition(backendCommand(6) == nil && utf8Prefix(Array("café".utf8), limit: 4) == Array("caf".utf8))
    var downloads = [[UInt8]](), clears = 0, cancellations = 0
    let media = MediaCoordinator(clear: { clears += 1 }, extract: {}, download: { downloads.append($0) }, cancel: { cancellations += 1 })
    media.select(1)
    func apply(_ reply: String, _ now: Double, running: Bool = false) {
        _ = media.apply(Array(reply.utf8), source: 1, spotifyRunning: running, now: now)
    }
    state.pointee.global_is_dragging = false
    apply("café|||Artist|||playing|||42|||180|||https://example.com/a", 10)
    precondition(widgetTitle() == "café" && state.pointee.global_rate == 1 && stateFlag(1, 0, false))
    precondition(downloads.count == 1 && !spotifyIsIdle())
    apply("", 11); apply("CLOSED", 12, running: true); apply("NO_TRACK", 13)
    precondition(widgetTitle() == "café" && state.pointee.global_rate == 1)
    // An artwork-only or duration-only change must reach the renderer too.
    apply("café|||Artist|||playing|||42|||181|||https://example.com/b", 14)
    precondition(downloads.count == 2 && state.pointee.global_duration == 181)
    precondition(optimisticPlayback(state, now: 14) == 1)
    apply("café|||Artist|||playing|||42|||181|||https://example.com/b", 14.1)
    precondition(state.pointee.global_rate == 0)
    apply("café|||Artist|||paused|||42|||181|||https://example.com/b", 14.2)
    apply("NO_TRACK", 16); apply("NO_TRACK", 17)
    precondition(widgetTitle() == "café")
    apply("NO_TRACK", 18)
    precondition(widgetTitle() == "Spotify" && state.pointee.global_duration == 0 && clears == 1)
    precondition(state.pointee.playback_clock.rate == 0 && state.pointee.playback_state.pending == -1)
    media.select(0)
    _ = media.apply(Array("Title|||Artist|||0|||1|||5|||30".utf8), source: 0, now: 20)
    precondition(widgetTitle() == "Title" && state.pointee.global_rate == 1)
    for t in [21.0, 22.0] { _ = media.apply([], source: 0, now: t) }
    precondition(widgetTitle() == "Title")
    _ = media.apply([], source: 0, now: 23)
    precondition(widgetTitle().isEmpty && clears == 2 && cancellations >= 2)
    precondition(state.pointee.playback_clock.rate == 0 && state.pointee.playback_clock.elapsed == 0)
    var replies = [String]()
    runNowPlayingHelper(script: #"$|=1; print "$$\n"; print "Title|||Artist|||0|||1|||0|||30\n"; sleep 10;"#) {
        replies.append(String(decoding: $0, as: UTF8.self))
        return false // source switch closes, terminates and reaps this exact child
    }
    precondition(replies == ["Title|||Artist|||0|||1|||0|||30"])
}
