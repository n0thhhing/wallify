import AppKit

let spotifyBundleIdentifier = "com.spotify.client"

final class SpotifyEvents {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var pending: Int32 = -1
    private var helperPID: Int32 = -1
    private var observer: NSObjectProtocol?

    func observe() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: nil) { [self] _ in notify() }
    }

    func notify() {
        lock.lock()
        let signal = pending == -1
        pending = 1
        let pid = helperPID
        lock.unlock()
        if signal { semaphore.signal() }
        if pid > 0 { _ = kill(pid, SIGUSR1) }
    }

    func takeState() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let state = pending
        pending = -1
        return state
    }

    func wait(milliseconds: UInt64) -> Int32 {
        let duration = Int(min(milliseconds, UInt64(Int.max / 1_000_000)))
        guard semaphore.wait(timeout: .now() + .milliseconds(duration)) == .success else { return 0 }
        _ = takeState()
        return 1
    }

    func setHelperPID(_ pid: Int32) {
        lock.lock()
        helperPID = pid
        lock.unlock()
    }
}

private let spotifyEvents = SpotifyEvents()

@_cdecl("widget_spotify_observe")
public func observeSpotify() { spotifyEvents.observe() }
@_cdecl("widget_spotify_take_state")
public func takeSpotifyState() -> Int32 { spotifyEvents.takeState() }
@_cdecl("widget_spotify_wait_for_event")
public func waitForSpotifyEvent(_ milliseconds: UInt64) -> Int32 { spotifyEvents.wait(milliseconds: milliseconds) }
@_cdecl("widget_spotify_set_helper_pid")
public func setSpotifyHelperPID(_ pid: Int32) { spotifyEvents.setHelperPID(pid) }

@_cdecl("widget_open_spotify")
public func openSpotify() {
    DispatchQueue.main.async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spotifyBundleIdentifier) else {
            NSLog("spotify: official Spotify app was not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error { NSLog("spotify: launch failed: %@", error.localizedDescription) }
        }
    }
}

@_cdecl("widget_is_spotify_running")
public func isSpotifyRunning() -> Int32 {
    autoreleasepool {
        NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundleIdentifier).isEmpty ? 0 : 1
    }
}

func spotifyControlScript(_ command: Int32) -> String? {
    let action: String
    switch command {
    case 0: action = "play"
    case 1: action = "pause"
    case 2: action = "playpause"
    case 3: action = "previous track"
    case 4: action = "next track"
    default: return nil
    }
    var script = "if application \"Spotify\" is running then\ntell application \"Spotify\" to \(action)\n"
    if command == 0 || command == 2 { script += "else\ntell application \"Spotify\" to activate\n" }
    return script + "end if"
}

func spotifySeekScript(_ position: Double) -> String? {
    guard position.isFinite && position >= 0 else { return nil }
    return String(format: "tell application \"Spotify\" to set player position to %.2f",
                  locale: Locale(identifier: "en_US_POSIX"), position)
}

@_cdecl("widget_spotify_control")
public func controlSpotify(_ command: Int32) {
    guard let source = spotifyControlScript(command) else { return }
    autoreleasepool { _ = NSAppleScript(source: source)?.executeAndReturnError(nil) }
}

@_cdecl("widget_spotify_seek")
public func seekSpotify(_ position: Double) {
    guard let source = spotifySeekScript(position) else { return }
    autoreleasepool { _ = NSAppleScript(source: source)?.executeAndReturnError(nil) }
}

let spotifyQueryScript = """
if application "Spotify" is running then
  tell application "Spotify"
    try
      set {tName, tArtist, tState, tPos, tDur} to {name of current track, artist of current track, player state as string, player position as string, duration of current track}
      set tDur to (tDur / 1000.0) as string
      set tArt to ""
      try
        set tArt to artwork url of current track
      end try
      return tName & "|||" & tArtist & "|||" & tState & "|||" & tPos & "|||" & tDur & "|||" & tArt
    on error
      return "NO_TRACK"
    end try
  end tell
else
  return "CLOSED"
end if
"""

// Only the metadata worker uses this cached script.
private var cachedSpotifyQuery: NSAppleScript?

func copySpotifyResult(_ result: String, to buffer: UnsafeMutablePointer<UInt8>, capacity: UInt) -> UInt {
    let bytes = Array(result.utf8)
    let count = min(UInt(bytes.count), capacity)
    bytes.withUnsafeBufferPointer { source in
        if count > 0 { buffer.update(from: source.baseAddress!, count: Int(count)) }
    }
    return count
}

@_cdecl("widget_query_spotify")
public func querySpotify(_ buffer: UnsafeMutablePointer<UInt8>?, _ capacity: UInt) -> UInt {
    guard let buffer = buffer, capacity > 0 else { return 0 }
    return autoreleasepool {
        if cachedSpotifyQuery == nil { cachedSpotifyQuery = NSAppleScript(source: spotifyQueryScript) }
        guard let result = cachedSpotifyQuery?.executeAndReturnError(nil).stringValue else { return 0 }
        return copySpotifyResult(result, to: buffer, capacity: capacity)
    }
}
