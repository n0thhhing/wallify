import Foundation

func playbackPosition(_ clock: WallifyPlaybackClock, now: Double, duration: Double) -> Double {
    let dt = max(0, now - clock.sampled_at)
    let correction = clock.correction * max(0, 1 - dt / 0.4)
    return min(max(0, duration), max(0, clock.elapsed + dt * clock.rate + correction))
}

@_cdecl("wallify_playback_position")
public func playbackPositionBridge(_ clock: UnsafePointer<WallifyPlaybackClock>?, _ now: Double, _ duration: Double) -> Double {
    guard let clock = clock else { return 0 }
    return playbackPosition(clock.pointee, now: now, duration: duration)
}

@_cdecl("wallify_playback_sync")
public func synchronizePlayback(_ clock: UnsafeMutablePointer<WallifyPlaybackClock>?, _ elapsed: Double,
                                _ rate: Double, _ now: Double, _ duration: Double, _ snap: Bool) {
    guard let clock = clock else { return }
    let delta = playbackPosition(clock.pointee, now: now, duration: duration) - elapsed
    clock.pointee = WallifyPlaybackClock(elapsed: elapsed, sampled_at: now, rate: rate,
                                       correction: !snap && abs(delta) < 2 ? delta : 0)
}

@_cdecl("wallify_playback_request")
public func requestPlayback(_ intent: UnsafeMutablePointer<WallifyPlaybackIntent>?, _ playing: Bool, _ now: Double) {
    intent?.pointee = WallifyPlaybackIntent(pending: playing ? 1 : 0, deadline: now + 1.5, confirmed_since: -1)
}

@_cdecl("wallify_playback_accept")
public func acceptPlayback(_ intent: UnsafeMutablePointer<WallifyPlaybackIntent>?, _ playing: Bool,
                           _ now: Double, _ trackChanged: Bool) -> Bool {
    guard let intent = intent else { return false }
    if trackChanged {
        intent.pointee = WallifyPlaybackIntent(pending: -1, deadline: 0, confirmed_since: -1)
        return true
    }
    if intent.pointee.pending >= 0 {
        if playing == (intent.pointee.pending == 1) {
            if intent.pointee.confirmed_since < 0 { intent.pointee.confirmed_since = now }
            if now >= intent.pointee.deadline && now - intent.pointee.confirmed_since >= 0.4 {
                intent.pointee.pending = -1
            }
            return true
        }
        intent.pointee.confirmed_since = -1
        if now < intent.pointee.deadline { return false }
        intent.pointee.pending = -1
    }
    // External changes have no local intent to protect; accept the first snapshot.
    return true
}
