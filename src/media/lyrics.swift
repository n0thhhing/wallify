import Foundation

// Synced lyrics from LRCLIB (lrclib.net). Only used while the Lyrics setting is on, because each new
// track sends its title, artist and duration to that service. One track is kept at a time.
final class LyricsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var key = ""
    private var lines: [(time: Double, text: String)] = []

    // What the lyric row shows at `time`, starting a fetch when the track changes; nil when the track has no
    // synced lyrics, so the row falls back to the time labels.
    func frame(title: String, artist: String, duration: Double, at time: Double) -> LyricFrame? {
        let key = title + "\u{1f}" + artist
        lock.lock()
        defer { lock.unlock() }
        if key != self.key {
            self.key = key
            lines = []
            if !title.isEmpty { fetch(title: title, artist: artist, duration: duration, key: key) }
        }
        return lyricFrame(lines, at: time)
    }

    // The current frame without fetching, for accessibility and frame pacing.
    func cachedFrame(at time: Double) -> LyricFrame? {
        lock.lock()
        defer { lock.unlock() }
        return lyricFrame(lines, at: time)
    }

    private func fetch(title: String, artist: String, duration: Double, key: String) {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)] +
            (duration > 0 ? [URLQueryItem(name: "duration", value: String(Int(duration.rounded())))] : [])
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue("Wallify (https://github.com/n0thhhing/wallify)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [self] data, _, _ in
            let synced = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["syncedLyrics"] as? String
            let parsed = synced.map(parseSyncedLyrics) ?? []
            lock.lock()
            let current = self.key == key
            if current { lines = parsed }
            lock.unlock()
            if current && !parsed.isEmpty { requestWidgetFrame() }
        }.resume()
    }
}

let lyricsStore = LyricsStore()

struct LyricFrame: Equatable {
    var line: String, previous: String
    var progress: Double        // 0 → 1 over the line-change transition
    var untilNext: Double?      // seconds until the next line starts
}

let lyricTransition = 0.35

// Instrumental gaps and the intro show a note, so the row stays a lyric row for the whole song.
func lyricFrame(_ lines: [(time: Double, text: String)], at time: Double) -> LyricFrame? {
    guard !lines.isEmpty else { return nil }
    func shown(_ text: String) -> String { text.isEmpty ? "♪" : text }
    let index = lines.lastIndex { $0.time <= time }
    let start = index.map { lines[$0].time } ?? 0
    let next = lines[(index ?? -1) + 1 ..< lines.count].first { $0.time > time }
    let line = index.map { shown(lines[$0].text) } ?? "♪"
    let previous = index.map { $0 > 0 ? shown(lines[$0 - 1].text) : "♪" } ?? ""
    // A repeated line (two gaps in a row, a repeated chorus line) does not animate.
    return LyricFrame(line: line, previous: previous,
                      progress: previous == line ? 1 : min(1, max(0, (time - start) / lyricTransition)),
                      untilNext: next.map { $0.time - time })
}

// LRC lines look like "[01:23.45]text"; a line may carry several time tags, and metadata tags are skipped.
func parseSyncedLyrics(_ text: String) -> [(time: Double, text: String)] {
    var result: [(time: Double, text: String)] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(raw)
        var times: [Double] = []
        while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let parts = rest[rest.index(after: rest.startIndex)..<close].split(separator: ":")
            if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) { times.append(minutes * 60 + seconds) }
            rest = rest[rest.index(after: close)...]
        }
        let line = rest.trimmingCharacters(in: .whitespaces)
        result += times.map { (time: $0, text: line) }
    }
    return result.sorted { $0.time < $1.time }
}
