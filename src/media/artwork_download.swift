import Foundation

final class ArtworkDownload {
    private let lock = NSLock()
    private let session: URLSession
    private let destination: URL
    private let changed: (Bool) -> Void
    private var generation: UInt64 = 0
    private var task: URLSessionDataTask?

    init(session: URLSession = .shared, destination: URL = URL(fileURLWithPath: "/tmp/art.raw"),
         changed: @escaping (Bool) -> Void) {
        self.session = session
        self.destination = destination
        self.changed = changed
    }

    @discardableResult func cancel() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        task?.cancel()
        task = nil
        return generation
    }

    func start(_ address: String) {
        let token = cancel()
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            complete(nil, status: 0, generation: token)
            return
        }
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 15)
        let next = session.dataTask(with: request) { [weak self] data, response, error in
            self?.complete(error == nil ? data : nil, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                           generation: token)
        }
        lock.lock()
        if token == generation {
            task = next
            next.resume()
        } else { next.cancel() }
        lock.unlock()
    }

    func complete(_ data: Data?, status: Int, generation token: UInt64) {
        // Match the state → downloader order used by metadata source changes.
        sceneLock.lock()
        defer { sceneLock.unlock() }
        lock.lock()
        defer { lock.unlock() }
        guard token == generation else { return }
        task = nil
        var published = false
        if (200..<300).contains(status), let data = data, !data.isEmpty {
            do {
                try data.write(to: destination, options: .atomic)
                published = true
            } catch { NSLog("artwork: write failed: %@", error.localizedDescription) }
        }
        if !published { try? FileManager.default.removeItem(at: destination) }
        // Serialize publication and the host callback with new requests. The host
        // only refreshes artwork/state and does not re-enter this downloader.
        changed(published)
    }
}

private let artworkDownload = ArtworkDownload { wallify_artwork_downloaded($0) }

@_cdecl("wallify_download_artwork")
public func downloadArtwork(_ bytes: UnsafePointer<UInt8>?, _ count: UInt) {
    guard let bytes = bytes, count > 0, count <= 4096,
          let address = String(bytes: UnsafeBufferPointer(start: bytes, count: Int(count)), encoding: .utf8) else {
        artworkDownload.cancel()
        return
    }
    artworkDownload.start(address)
}

@_cdecl("wallify_cancel_artwork_download")
public func cancelArtworkDownload() { artworkDownload.cancel() }
