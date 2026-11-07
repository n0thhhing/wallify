import Foundation

// Synced lyrics from LRCLIB (lrclib.net). Only used while the Lyrics setting is on, because each new
// track sends its title, artist and duration to that service. One track is kept at a time.
final class LyricsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var key = ""
    private var lines: [(time: Double, text: String)] = []

    // The line playing at `time`, starting a fetch when the track changes. Empty lines are instrumental gaps.
    func line(title: String, artist: String, duration: Double, at time: Double) -> String? {
        let key = title + "\u{1f}" + artist
        lock.lock()
        defer { lock.unlock() }
        if key != self.key {
            self.key = key
            lines = []
            if !title.isEmpty { fetch(title: title, artist: artist, duration: duration, key: key) }
        }
        return currentLine(at: time)
    }

    // The current line without fetching, for accessibility on the main thread.
    func cachedLine(at time: Double) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return currentLine(at: time)
    }

    private func currentLine(at time: Double) -> String? {
        guard let line = lines.last(where: { $0.time <= time }), !line.text.isEmpty else { return nil }
        return line.text
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
