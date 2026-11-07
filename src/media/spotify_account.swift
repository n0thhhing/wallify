import AppKit
import CryptoKit
import Network
import Security

// Spotify Web API access for Like and Up Next. Uses the PKCE authorization-code flow, which needs no
// client secret: the user's client ID comes from Settings, the refresh token lives in the Keychain and
// the access token only in memory. Nothing here logs a token.
final class SpotifyAccount: @unchecked Sendable {
    static let redirectURI = "http://127.0.0.1:43219/callback"
    static let scopes = "user-library-read user-library-modify user-read-playback-state"
    typealias Send = (URLRequest, @escaping (Data?, Int) -> Void) -> Void

    private let lock = NSLock()
    private var accessToken: String?
    private var expiry = 0.0
    private var refreshToken: String?
    private var listener: NWListener?
    private var failure: String?
    private let send: Send
    private let store: (String?) -> Void
    let clientID: () -> String

    init(send: @escaping Send, load: () -> String?, store: @escaping (String?) -> Void, clientID: @escaping () -> String) {
        self.send = send
        self.store = store
        self.clientID = clientID
        refreshToken = load()
    }

    var connected: Bool { lock.lock(); defer { lock.unlock() }; return refreshToken != nil }
    var lastError: String? { lock.lock(); defer { lock.unlock() }; return failure }

    // MARK: Login

    func connect(open: (URL) -> Void) {
        let client = clientID()
        guard validSpotifyClientID(client) else { fail("Enter your Spotify app's client ID first."); return }
        let verifier = randomURLSafe(64), state = randomURLSafe(16)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client), URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI), URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "code_challenge", value: pkceChallenge(verifier)),
            URLQueryItem(name: "state", value: state)
        ]
        guard listen(expecting: state, verifier: verifier) else { return }
        open(components.url!)
    }

    func disconnect() {
        lock.lock()
        accessToken = nil; refreshToken = nil; failure = nil
        lock.unlock()
        store(nil)
        refreshSettingsUI()
    }

    // Exchanges the authorization code from the callback for tokens.
    func complete(code: String, verifier: String) {
        tokenRequest(["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
                      "client_id": clientID(), "code_verifier": verifier]) { [self] token in
            if token == nil { fail("Spotify did not accept the login. Check the client ID and redirect URI.") }
            refreshSettingsUI()
        }
    }

    // MARK: API

    // Calls https://api.spotify.com/v1 + path, refreshing the access token when needed and retrying once on 401.
    func request(_ method: String, _ path: String, completion: @escaping (Data?, Int) -> Void) {
        withToken { [self] token in
            guard let token, let url = URL(string: "https://api.spotify.com/v1" + path) else { completion(nil, 401); return }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = method
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            send(request) { [self] data, status in
                guard status == 401 else { completion(data, status); return }
                lock.lock(); accessToken = nil; lock.unlock()
                withToken { [self] retry in
                    guard let retry else { completion(nil, 401); return }
                    var again = request
                    again.setValue("Bearer " + retry, forHTTPHeaderField: "Authorization")
                    send(again, completion)
                }
            }
        }
    }

    private func withToken(_ done: @escaping (String?) -> Void) {
        lock.lock()
        if let token = accessToken, monotonicTime() < expiry - 60 { lock.unlock(); done(token); return }
        let refresh = refreshToken
        lock.unlock()
        guard let refresh else { done(nil); return }
        tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID()], done: done)
    }

    private func tokenRequest(_ form: [String: String], done: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(form).utf8)
        send(request) { [self] data, status in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard status == 200, let access = json?["access_token"] as? String else {
                // A rejected refresh token means access was revoked; show the account as disconnected.
                if form["grant_type"] == "refresh_token" && json?["error"] as? String == "invalid_grant" { disconnect() }
                done(nil)
                return
            }
            let newRefresh = json?["refresh_token"] as? String
            lock.lock()
            accessToken = access
            expiry = monotonicTime() + ((json?["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
            if let newRefresh { refreshToken = newRefresh }
            failure = nil
            lock.unlock()
            if let newRefresh { store(newRefresh) }
            done(access)
        }
    }

    private func fail(_ message: String) {
        lock.lock(); failure = message; lock.unlock()
        refreshSettingsUI()
    }

    // MARK: Loopback callback

    // Accepts one /callback request on 127.0.0.1 only, then stops; gives up after five minutes.
    private func listen(expecting state: String, verifier: String) -> Bool {
        lock.lock(); listener?.cancel(); listener = nil; lock.unlock()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 43219)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { fail("Port 43219 is busy; close the other login and retry."); return false }
        let queue = DispatchQueue(label: "Wallify.spotify.login")
        listener.newConnectionHandler = { [self] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, _, _ in
                let result = spotifyCallback(String(decoding: data ?? Data(), as: UTF8.self), expectedState: state)
                let page = result.code != nil ? "Wallify is connected to Spotify. You can close this tab." :
                    "Wallify could not connect to Spotify. You can close this tab and try again."
                let response = "HTTP/1.1 \(result.handled ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\n" +
                    "Connection: close\r\n\r\n<!doctype html><title>Wallify</title><p style=\"font: 15px -apple-system\">\(page)</p>"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                guard result.handled else { return }
                stopListening()
                if let code = result.code { complete(code: code, verifier: verifier) }
                else { fail(result.error ?? "Spotify login was cancelled.") }
            }
        }
        listener.start(queue: queue)
        lock.lock(); self.listener = listener; lock.unlock()
        queue.asyncAfter(deadline: .now() + 300) { [weak listener, self] in
            lock.lock(); let current = self.listener === listener; lock.unlock()
            if current { stopListening() }
        }
        return true
    }

    private func stopListening() {
        lock.lock(); listener?.cancel(); listener = nil; lock.unlock()
    }
}

// Parses the browser's request line. Only /callback with the matching state counts.
func spotifyCallback(_ request: String, expectedState: String) -> (handled: Bool, code: String?, error: String?) {
    let parts = request.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2, parts[0] == "GET", let components = URLComponents(string: "http://127.0.0.1" + parts[1]),
          components.path == "/callback" else { return (false, nil, nil) }
    let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    guard items["state"] == expectedState else { return (true, nil, "The login response did not match; try again.") }
    if let code = items["code"], !code.isEmpty { return (true, code, nil) }
    return (true, nil, items["error"].map { "Spotify login failed: \($0)." })
}

func validSpotifyClientID(_ value: String) -> Bool {
    value.count == 32 && value.allSatisfy(\.isHexDigit)
}

func pkceChallenge(_ verifier: String) -> String {
    base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
}

func randomURLSafe(_ bytes: Int) -> String {
    var data = Data(count: bytes)
    let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
    precondition(status == errSecSuccess, "Secure random bytes are unavailable")
    return base64URL(data)
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func formEncoded(_ form: [String: String]) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return form.sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
}

// MARK: Keychain and shared instance

private let keychainQuery: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "Wallify Spotify",
                                              kSecAttrAccount: "refresh_token"]

private func loadRefreshToken() -> String? {
    var query = keychainQuery
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

private func storeRefreshToken(_ token: String?) {
    SecItemDelete(keychainQuery as CFDictionary)
    guard let token else { return }
    var item = keychainQuery
    item[kSecValueData] = Data(token.utf8)
    item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    if status != errSecSuccess { NSLog("Wallify: saving the Spotify login to the Keychain failed (%d)", status) }
}

let spotifyClientIDKey = "SpotifyClientID"
private let usesKeychain = Bundle.main.bundleIdentifier != nil

let spotifyAccount = SpotifyAccount(
    send: { request, completion in
        URLSession.shared.dataTask(with: request) { data, response, _ in
            completion(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }.resume()
    },
    // The test binary has no bundle identifier; keep it away from the real Keychain, which would prompt on every build.
    load: { usesKeychain ? loadRefreshToken() : nil }, store: { if usesKeychain { storeRefreshToken($0) } },
    clientID: { (UserDefaults.standard.string(forKey: spotifyClientIDKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) })

// Whether the current Spotify track is in Liked Songs; nil hides the heart (not connected, not Spotify, or unknown).
final class LikeStore: @unchecked Sendable {
    private let lock = NSLock()
    private var trackID = ""
    private var liked: Bool?
    private let account: SpotifyAccount
    init(account: SpotifyAccount) { self.account = account }

    var state: Bool? { lock.lock(); defer { lock.unlock() }; return liked }

    // Called with the current Spotify track URI ("spotify:track:…"), or "" when Spotify is not the source.
    func track(_ uri: String) {
        let id = uri.hasPrefix("spotify:track:") ? String(uri.dropFirst("spotify:track:".count)) : ""
        lock.lock()
        guard id != trackID else { lock.unlock(); return }
        trackID = id
        liked = nil
        lock.unlock()
        requestWidgetFrame()
        guard !id.isEmpty, account.connected else { return }
        account.request("GET", "/me/tracks/contains?ids=" + id) { [self] data, status in
            let saved = status == 200 ? (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Bool] })?.first : nil
            lock.lock()
            if trackID == id { liked = saved }
            lock.unlock()
            requestWidgetFrame()
        }
    }

    // Flips immediately, then reverts if Spotify rejects the change.
    func toggle() {
        lock.lock()
        guard let current = liked, !trackID.isEmpty else { lock.unlock(); return }
        let id = trackID
        liked = !current
        lock.unlock()
        requestWidgetFrame()
        announceWidgetChange()
        account.request(current ? "DELETE" : "PUT", "/me/tracks?ids=" + id) { [self] _, status in
            guard !(200..<300).contains(status) else { return }
            lock.lock()
            if trackID == id { liked = current }
            lock.unlock()
            requestWidgetFrame()
        }
    }
}

let likeStore = LikeStore(account: spotifyAccount)

// "Next title — artist" from the Spotify queue, fetched once per track while it is shown (2 × 2 only).
final class UpNextStore: @unchecked Sendable {
    private let lock = NSLock()
    private var key = ""
    private var next: String?
    private let account: SpotifyAccount
    init(account: SpotifyAccount) { self.account = account }

    func line(title: String, artist: String) -> String? {
        let key = title + "\u{1f}" + artist
        lock.lock()
        defer { lock.unlock() }
        guard key != self.key else { return next }
        self.key = key
        next = nil
        guard account.connected else { return nil }
        account.request("GET", "/me/player/queue") { [self] data, status in
            let line = status == 200 ? data.flatMap(upNextLine) : nil
            lock.lock()
            if self.key == key { next = line }
            lock.unlock()
            if line != nil { requestWidgetFrame() }
        }
        return nil
    }

    func cachedLine() -> String? { lock.lock(); defer { lock.unlock() }; return next }
}

func upNextLine(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let first = (json["queue"] as? [[String: Any]])?.first, let name = first["name"] as? String else { return nil }
    let artists = (first["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
    return artists.isEmpty ? name : name + " — " + artists.joined(separator: ", ")
}

let upNextStore = UpNextStore(account: spotifyAccount)
