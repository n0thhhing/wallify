import AppKit

let spotifyBundleIdentifier = "com.spotify.client"

func spotifyTrackURL(_ identifier: String) -> URL? {
    let parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "spotify", ["track", "episode"].contains(parts[1]),
          parts[2].utf8.count == 22, parts[2].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
    return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
}

func currentSpotifyTrackURL(title: String, artist: String) -> URL? {
    guard isSpotifyRunning() != 0 else { return nil }
    return autoreleasepool {
        let script = """
            tell application id "com.spotify.client"
                try
                    return {name of current track, artist of current track, id of current track}
                end try
            end tell
            """
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(nil),
              result.atIndex(1)?.stringValue == title, result.atIndex(2)?.stringValue == artist,
              let identifier = result.atIndex(3)?.stringValue else { return nil }
        return spotifyTrackURL(identifier)
    }
}

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
  tell application id "com.spotify.client"
    try
      set {tName, tArtist, tState, tPos, tDur} to {name of current track, artist of current track, player state as string, player position as string, duration of current track}
      set tDur to (tDur / 1000.0) as string
      set tArt to ""
      try
        set tArt to artwork url of current track
      end try
      return tName & "|||" & tArtist & "|||" & tState & "|||" & tPos & "|||" & tDur & "|||" & tArt
    on error message number code
      if code is -1728 then return "NO_TRACK"
      error message number code
    end try
  end tell
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
        // A cached script can retain an application target across quit/relaunch.
        guard isSpotifyRunning() != 0 else {
            cachedSpotifyQuery = nil
            return copySpotifyResult("CLOSED", to: buffer, capacity: capacity)
        }
        if cachedSpotifyQuery == nil { cachedSpotifyQuery = NSAppleScript(source: spotifyQueryScript) }
        var error: NSDictionary?
        guard let result = cachedSpotifyQuery?.executeAndReturnError(&error).stringValue else {
            NSLog("spotify: metadata query failed: %@", error ?? [:])
            cachedSpotifyQuery = nil
            return 0
        }
        return copySpotifyResult(result, to: buffer, capacity: capacity)
    }
}
