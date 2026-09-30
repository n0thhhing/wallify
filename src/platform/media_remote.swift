import Darwin

func withMediaRemoteSymbol(_ name: String, body: (UnsafeMutableRawPointer) -> Void) {
    guard let library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else { return }
    defer { dlclose(library) }
    guard let symbol = dlsym(library, name) else { return }
    body(symbol)
}

@_cdecl("wallify_system_media_command")
public func sendSystemMediaCommand(_ command: UInt32) {
    withMediaRemoteSymbol("MRMediaRemoteSendCommand") { symbol in
        typealias Send = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(symbol, to: Send.self)(command, nil)
    }
}

@_cdecl("wallify_system_media_seek")
public func seekSystemMedia(_ elapsed: Double) {
    withMediaRemoteSymbol("MRMediaRemoteSetElapsedTime") { symbol in
        typealias Seek = @convention(c) (Double) -> Void
        unsafeBitCast(symbol, to: Seek.self)(elapsed)
    }
}
