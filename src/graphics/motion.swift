import Foundation

@_cdecl("wallify_icon_scale")
public func playbackIconScale(_ mix: Double, _ playing: Bool) -> Double {
    let progress = playing ? mix : 1 - mix
    if progress < 0.5 {
        let t = progress / 0.5
        return 1 - 0.5 * t * t
    }
    let remaining = (1 - progress) / 0.5
    return 1 - 0.5 * remaining * remaining * remaining
}

@_cdecl("wallify_icon_advance")
public func advancePlaybackIcon(_ mix: Double, _ playing: Bool, _ dt: Double) -> Double {
    var progress = playing ? mix : 1 - mix
    var remaining = max(0, dt)
    if progress < 0.5 {
        let used = min(remaining, (0.5 - progress) * 0.18)
        progress += used / 0.18
        remaining -= used
    }
    progress = min(1, progress + remaining / 0.48)
    return playing ? progress : 1 - progress
}
