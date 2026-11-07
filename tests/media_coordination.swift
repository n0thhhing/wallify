import Foundation

func checkMediaCoordination() {
    checkSpotifyNotificationReply()
    checkSpotifyAccount()
    precondition(automationStatus(OSStatus(noErr)) == .granted && automationStatus(OSStatus(errAEEventNotPermitted)) == .denied)
    precondition(automationStatus(OSStatus(procNotFound)) == .notRunning && automationStatus(OSStatus(errAEEventWouldRequireUserConsent)) == .undecided)
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
    state.pointee.setting_source = 1
    media.select(1)
    func apply(_ reply: String, _ now: Double, running: Bool = false) {
        _ = media.apply(Array(reply.utf8), source: 1, spotifyRunning: running, now: now)
    }
    apply("CLOSED", 8)
    precondition(widgetTitle() == "Spotify is Closed" && spotifyIsIdle())
    apply("Track|||Artist|||paused|||42|||180|||", 9)
    precondition(widgetTitle() == "Track" && !spotifyIsIdle())
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
    precondition(widgetTitle() == "café" && state.pointee.global_duration == 181 && clears == 2 && state.pointee.media_stopped)
    state.pointee.setting_stopped_behavior = 1
    precondition(!spotifyIsIdle() && !stoppedWidgetHidden(state.pointee))
    state.pointee.setting_stopped_behavior = 2
    precondition(stoppedWidgetHidden(state.pointee))
    state.pointee.setting_stopped_behavior = 0
    precondition(spotifyIsIdle())
    precondition(state.pointee.playback_clock.rate == 0 && state.pointee.playback_state.pending == -1)
    state.pointee.setting_source = 0
    apply("Late reply|||Old source|||playing|||99|||180", 19)
    precondition(widgetTitle() == "café" && state.pointee.global_rate == 0)
    media.select(0)
    _ = media.apply(Array("Title|||Artist|||0|||1|||5|||30".utf8), source: 0, now: 20)
    precondition(widgetTitle() == "Title" && state.pointee.global_rate == 1)
    for t in [21.0, 22.0] { _ = media.apply([], source: 0, now: t) }
    precondition(widgetTitle() == "Title")
    _ = media.apply([], source: 0, now: 23)
    precondition(widgetTitle() == "Title" && state.pointee.media_stopped && clears == 3 && cancellations >= 2)
    precondition(state.pointee.playback_clock.rate == 0 && state.pointee.playback_clock.elapsed == 5)
    _ = media.apply(Array("No artwork|||Artist|||0|||0|||5|||30".utf8), source: 0, now: 24)
    for t in 25...54 { _ = media.apply(Array("No artwork|||Artist|||0|||0|||5|||30".utf8), source: 0, now: Double(t)) }
    precondition(!state.pointee.artwork_refresh_pending)
    var replies = [String]()
    runNowPlayingHelper(script: #"$|=1; print "$$\n"; print "Title|||Artist|||0|||1|||0|||30\n"; sleep 10;"#) {
        replies.append(String(decoding: $0, as: UTF8.self))
        return false // source switch closes, terminates and reaps this exact child
    }
    precondition(replies == ["Title|||Artist|||0|||1|||0|||30"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wallify-artwork-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let incoming = directory.appendingPathComponent("incoming"), published = directory.appendingPathComponent("published")
    var refreshes = 0
    let artworkMedia = MediaCoordinator(clear: {}, extract: { refreshes += 1 }, download: { _ in }, cancel: {},
                                        artworkSource: incoming, artworkDestination: published)
    artworkMedia.select(0)
    let paused = Array("Artwork|||Artist|||1|||0|||0|||30".utf8)
    try! Data([1]).write(to: incoming)
    _ = artworkMedia.apply(paused, source: 0, now: 100)
    precondition(refreshes == 1 && !state.pointee.artwork_refresh_pending)
    try! Data([2]).write(to: incoming)
    _ = artworkMedia.apply(paused, source: 0, now: 101)
    precondition(refreshes == 2 && (try! Data(contentsOf: published)) == Data([2]))
    artworkMedia.select(1)
    precondition(widgetTitle().isEmpty && state.pointee.global_artist_len == 0 && state.pointee.global_duration == 0)
    precondition(!state.pointee.global_has_artwork && state.pointee.playback_state.pending == -1)
    _ = artworkMedia.apply(paused, source: 0, now: 102)
    precondition(widgetTitle().isEmpty)
    state.pointee.setting_source = 3
    media.select(2)
    _ = media.apply(Array("fastpotify:now paused\tAuto Track\tArtist\tAlbum\t1200\t90000\t70\toff\toff\t\tno\tDevice\n".utf8), source: 2, now: 103)
    precondition(widgetTitle() == "Auto Track" && !state.pointee.media_stopped)
    media.select(0)
    precondition(widgetTitle() == "Auto Track" && state.pointee.media_stopped)
}

// The payload Spotify posts on play/pause (captured from Spotify 1.2): position in seconds, duration in ms.
func checkSpotifyNotificationReply() {
    let info: [AnyHashable: Any] = ["Name": "Internet Buzzwords", "Artist": "NEET", "Player State": "Playing",
        "Playback Position": 23.785, "Duration": 121304, "Track ID": "spotify:track:4H6SycLgj3UkYozVnFcgQ5"]
    let event = spotifyNotificationReply(info, artwork: "https://i.scdn.co/image/a")!
    precondition(event.trackID == "spotify:track:4H6SycLgj3UkYozVnFcgQ5")
    let payload = parseMediaPayload(event.reply, format: 0)!
    precondition(payload.rate == 1 && abs(payload.elapsed - 23.785) < 1e-9 && abs(payload.duration - 121.304) < 1e-9)
    let text = String(decoding: event.reply, as: UTF8.self)
    precondition(text.hasPrefix("Internet Buzzwords|||NEET|||playing|||") && text.contains("|||https://i.scdn.co/image/a|||"))
    var paused = info; paused["Player State"] = "Paused"
    precondition(parseMediaPayload(spotifyNotificationReply(paused, artwork: "")!.reply, format: 0)!.rate == 0)
    // Stopped events omit the track; the worker then falls back to AppleScript.
    precondition(spotifyNotificationReply(["Player State": "Stopped"], artwork: "") == nil)
}

// Spotify login: PKCE, callback parsing and token handling against a fake network.
func checkSpotifyAccount() {
    // RFC 7636 appendix B test vector.
    precondition(pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    precondition(randomURLSafe(64).count == 86 && !randomURLSafe(16).contains("="))
    precondition(validSpotifyClientID(String(repeating: "a1", count: 16)) && !validSpotifyClientID("abc") && !validSpotifyClientID(String(repeating: "z", count: 32)))
    precondition(spotifyCallback("GET /callback?code=abc&state=s1 HTTP/1.1\r\n", expectedState: "s1") == (true, "abc", nil))
    precondition(spotifyCallback("GET /callback?code=abc&state=evil HTTP/1.1", expectedState: "s1").code == nil)
    precondition(spotifyCallback("GET /callback?error=access_denied&state=s1 HTTP/1.1", expectedState: "s1").error == "Spotify login failed: access_denied.")
    precondition(!spotifyCallback("GET /favicon.ico HTTP/1.1", expectedState: "s1").handled)

    var responses: [(String, Int)] = [], requests: [URLRequest] = [], stored: [String?] = []
    let account = SpotifyAccount(send: { request, completion in
        requests.append(request)
        let (body, status) = responses.removeFirst()
        completion(Data(body.utf8), status)
    }, load: { "refresh-1" }, store: { stored.append($0) }, clientID: { "client" })
    precondition(account.connected)
    // First call refreshes the access token, keeping a rotated refresh token.
    responses = [(#"{"access_token":"a1","expires_in":3600,"refresh_token":"refresh-2"}"#, 200), ("{}", 200)]
    var status = 0
    account.request("GET", "/me/player/queue") { _, code in status = code }
    precondition(status == 200 && requests.count == 2 && stored == ["refresh-2"])
    let form = String(decoding: requests[0].httpBody!, as: UTF8.self)
    precondition(form == "client_id=client&grant_type=refresh_token&refresh_token=refresh-1")
    precondition(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer a1" && requests[1].url!.path == "/v1/me/player/queue")
    // A 401 refreshes once and retries with the new token.
    responses = [("", 401), (#"{"access_token":"a2","expires_in":3600}"#, 200), ("{}", 204)]
    account.request("PUT", "/me/tracks?ids=x") { _, code in status = code }
    precondition(status == 204 && requests.last!.value(forHTTPHeaderField: "Authorization") == "Bearer a2" && requests.last!.httpMethod == "PUT")
    // A revoked refresh token disconnects and clears the Keychain entry.
    responses = [("", 401), (#"{"error":"invalid_grant"}"#, 400)]
    account.request("GET", "/me/tracks/contains?ids=x") { _, code in status = code }
    precondition(status == 401 && !account.connected && stored.last! == nil)

    let likeAccount = SpotifyAccount(send: { request, completion in
        requests.append(request)
        let (body, code) = responses.removeFirst()
        completion(Data(body.utf8), code)
    }, load: { "refresh" }, store: { _ in }, clientID: { "client" })
    let likes = LikeStore(account: likeAccount)
    responses = [(#"{"access_token":"t","expires_in":3600}"#, 200), ("[true]", 200)]
    likes.track("spotify:track:abc")
    precondition(likes.state == true && requests.last!.url!.query == "ids=abc")
    responses = [("", 200)]
    likes.toggle()
    precondition(likes.state == false && requests.last!.httpMethod == "DELETE")
    responses = [("", 500)]  // a failed save puts the heart back
    likes.toggle()
    precondition(likes.state == false && requests.last!.httpMethod == "PUT")
    likes.track("")
    precondition(likes.state == nil)
    let queue = #"{"currently_playing":{"name":"Now"},"queue":[{"name":"Clozapine","artists":[{"name":"NEET"},{"name":"Guest"}]},{"name":"Later"}]}"#
    precondition(upNextLine(Data(queue.utf8)) == "Clozapine — NEET, Guest")
    precondition(upNextLine(Data(#"{"queue":[]}"#.utf8)) == nil && upNextLine(Data("oops".utf8)) == nil)
}
