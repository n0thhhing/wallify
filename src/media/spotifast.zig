const std = @import("std");
const macos = @import("../platform/macos.zig");

pub const INSTANCE_PORT: u16 = 47113;

pub const SpotifastControl = enum(c_int) {
    play = 0,
    pause = 1,
    play_pause = 2,
    previous_track = 3,
    next_track = 4,
};

pub const SpotifastPayload = struct {
    title: []const u8,
    artist: []const u8,
    playing: bool,
    elapsed: f64,
    duration: f64,
    artwork_url: []const u8,
};

const c = struct {
    const AF_INET: c_int = 2;
    const SOCK_STREAM: c_int = 1;
    const SOL_SOCKET: c_int = 0xffff;
    const SO_RCVTIMEO: c_int = 0x1006;
    const SO_SNDTIMEO: c_int = 0x1005;
    const SO_NOSIGPIPE: c_int = 0x1022;

    const Timeval = extern struct {
        tv_sec: c_long,
        tv_usec: i32,
    };

    const SockaddrIn = extern struct {
        sin_len: u8 = @sizeOf(SockaddrIn),
        sin_family: u8 = 2,
        sin_port: u16,
        sin_addr: [4]u8,
        sin_zero: [8]u8 = [_]u8{0} ** 8,
    };

    extern "c" fn socket(domain: c_int, sock_type: c_int, protocol: c_int) c_int;
    extern "c" fn connect(sock: c_int, address: *const anyopaque, address_len: u32) c_int;
    extern "c" fn setsockopt(sock: c_int, level: c_int, option_name: c_int, option_value: ?*const anyopaque, option_len: u32) c_int;
    extern "c" fn close(fd: c_int) c_int;
    extern "c" fn read(fd: c_int, buf: [*]u8, nbytes: usize) isize;
    extern "c" fn write(fd: c_int, buf: [*]const u8, nbytes: usize) isize;
};

var query_socket: c_int = -1;
var query_socket_lock: std.atomic.Mutex = .unlocked;

fn lockQuerySocket() void {
    while (!query_socket_lock.tryLock()) {
        std.atomic.spinLoopHint();
    }
}

fn unlockQuerySocket() void {
    query_socket_lock.unlock();
}

fn closeQuerySocket() void {
    if (query_socket >= 0) {
        _ = c.close(query_socket);
        query_socket = -1;
    }
}

fn configureQuerySocket(sock: c_int) void {
    const timeout = c.Timeval{ .tv_sec = 0, .tv_usec = 300_000 };
    _ = c.setsockopt(sock, c.SOL_SOCKET, c.SO_RCVTIMEO, &timeout, @sizeOf(c.Timeval));
    _ = c.setsockopt(sock, c.SOL_SOCKET, c.SO_SNDTIMEO, &timeout, @sizeOf(c.Timeval));
    const no_sigpipe: c_int = 1;
    _ = c.setsockopt(sock, c.SOL_SOCKET, c.SO_NOSIGPIPE, &no_sigpipe, @sizeOf(no_sigpipe));
}

fn connectQuerySocket() !void {
    if (query_socket >= 0) return;

    const sock = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (sock < 0) return error.SocketCreationFailed;
    configureQuerySocket(sock);

    const target_addr = c.SockaddrIn{
        .sin_port = std.mem.nativeToBig(u16, INSTANCE_PORT),
        .sin_addr = [4]u8{ 127, 0, 0, 1 },
    };

    if (c.connect(sock, &target_addr, @sizeOf(c.SockaddrIn)) != 0) {
        _ = c.close(sock);
        return error.ConnectionFailed;
    }

    query_socket = sock;
}

/// Sends a one-line request using a reusable loopback connection.
/// If Spotifast closes the connection after a request, the next call reconnects.
fn sendPersistentQuery(verb: []const u8, buf: []u8) !usize {
    lockQuerySocket();
    defer unlockQuerySocket();

    var attempts: usize = 0;
    while (attempts < 2) : (attempts += 1) {
        connectQuerySocket() catch {
            closeQuerySocket();
            if (attempts == 1) return error.ConnectionFailed;
            continue;
        };

        var req_buf: [128]u8 = undefined;
        const req = try std.fmt.bufPrint(&req_buf, "fastpotify:{s}\n", .{verb});
        const written = c.write(query_socket, req.ptr, req.len);
        if (written != @as(isize, @intCast(req.len))) {
            closeQuerySocket();
            continue;
        }

        var total_read: usize = 0;
        while (total_read < buf.len) {
            const n = c.read(query_socket, buf.ptr + total_read, buf.len - total_read);
            if (n <= 0) break;
            total_read += @intCast(n);
            if (std.mem.indexOfScalar(u8, buf[0..total_read], '\n')) |_| break;
        }

        if (total_read > 0) return total_read;

        closeQuerySocket();
    }

    return error.ReadFailed;
}

/// Sends a one-line request to the Spotifast single-instance loopback socket
/// and reads the response line into `buf`.
// AppleScript is way too slow (20-50ms per query) and causes the UI to stutter.
// Talking to the Spotifast daemon over a local TCP socket gives us sub-millisecond latency
// without having to mess with macOS IPC or C bindings.
pub fn sendSocketRequest(verb: []const u8, buf: []u8) !usize {
    const sock = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (sock < 0) return error.SocketCreationFailed;
    defer _ = c.close(sock);
    configureQuerySocket(sock);

    const target_addr = c.SockaddrIn{
        .sin_port = std.mem.nativeToBig(u16, INSTANCE_PORT),
        .sin_addr = [4]u8{ 127, 0, 0, 1 },
    };

    if (c.connect(sock, &target_addr, @sizeOf(c.SockaddrIn)) != 0) {
        return error.ConnectionFailed;
    }

    var req_buf: [128]u8 = undefined;
    const req = try std.fmt.bufPrint(&req_buf, "fastpotify:{s}\n", .{verb});
    const written = c.write(sock, req.ptr, req.len);
    if (written != @as(isize, @intCast(req.len))) return error.WriteFailed;

    var total_read: usize = 0;
    while (total_read < buf.len) {
        const n = c.read(sock, buf.ptr + total_read, buf.len - total_read);
        if (n <= 0) {
            if (total_read > 0) break;
            return error.ReadFailed;
        }
        total_read += @intCast(n);
        if (std.mem.indexOfScalar(u8, buf[0..total_read], '\n')) |_| break;
    }
    return total_read;
}

pub export fn widget_open_spotifast() callconv(.c) void {
    // If running, raise its window via socket:
    var reply_buf: [64]u8 = undefined;
    if (sendSocketRequest("show", &reply_buf)) |_| {
        return;
    } else |_| {}

    // Otherwise launch application via NSWorkspace
    const main_q = macos.dispatch_get_main_queue();
    const Work = struct {
        fn run(_: macos.Ref) callconv(.c) void {
            const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
            defer macos.send(void, pool, "release", .{});

            const ws = macos.send(macos.Ref, macos.objc_getClass("NSWorkspace"), "sharedWorkspace", .{});
            const bundle_id = macos.string("me.paolino.fastpotify");
            defer macos.CFRelease(bundle_id);

            const app_url = macos.send(macos.Ref, ws, "URLForApplicationWithBundleIdentifier:", .{bundle_id});
            if (app_url != null) {
                const conf = macos.send(macos.Ref, macos.objc_getClass("NSWorkspaceOpenConfiguration"), "configuration", .{});
                _ = macos.send(void, ws, "openApplicationAtURL:configuration:completionHandler:", .{ app_url, conf, @as(macos.Ref, null) });
                return;
            }

            // Fallback: try openURL with spotify:
            const url_str = macos.string("spotify:");
            defer macos.CFRelease(url_str);
            const url = macos.send(macos.Ref, macos.objc_getClass("NSURL"), "URLWithString:", .{url_str});
            _ = macos.send(bool, ws, "openURL:", .{url});
        }
    };
    macos.dispatch_async_f(main_q, null, Work.run);
}

pub export fn widget_is_spotifast_running() callconv(.c) c_int {
    const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
    defer macos.send(void, pool, "release", .{});

    const bundle_id = macos.string("me.paolino.fastpotify");
    defer macos.CFRelease(bundle_id);

    const apps = macos.send(macos.Ref, macos.objc_getClass("NSRunningApplication"), "runningApplicationsWithBundleIdentifier:", .{bundle_id});
    if (apps != null) {
        const count = macos.send(usize, apps, "count", .{});
        if (count > 0) return 1;
    }
    return 0;
}

pub export fn widget_spotifast_control(cmd: SpotifastControl) callconv(.c) void {
    const verb = switch (cmd) {
        .play => "play",
        .pause => "pause",
        .play_pause => "playpause",
        .previous_track => "previous",
        .next_track => "next",
    };
    var buf: [64]u8 = undefined;
    _ = sendSocketRequest(verb, &buf) catch {};
}

pub export fn widget_spotifast_seek(position: f64) callconv(.c) void {
    const pos_ms: u64 = @intFromFloat(@max(0.0, position * 1000.0));
    var verb_buf: [64]u8 = undefined;
    const verb = std.fmt.bufPrint(&verb_buf, "seek-to {d}", .{pos_ms}) catch return;
    var reply_buf: [64]u8 = undefined;
    _ = sendSocketRequest(verb, &reply_buf) catch {};
}

pub fn parseSpotifastPayload(raw: []const u8) ?SpotifastPayload {
    // Format: "fastpotify:now <state>\t<title>\t<artists>\t<album>\t<position_ms>\t<duration_ms>\t<volume>\t<shuffle>\t<repeat>\t<art_url>\t<saved>\t<device>"
    const prefix = "fastpotify:now ";
    const data = if (std.mem.startsWith(u8, raw, prefix))
        raw[prefix.len..]
    else
        raw;

    const trimmed = std.mem.trim(u8, data, " \r\n");
    if (std.mem.eql(u8, trimmed, "stopped") or trimmed.len == 0) {
        return null;
    }

    var spl = std.mem.splitScalar(u8, trimmed, '\t');
    const pstate = spl.next() orelse return null;
    const title = spl.next() orelse return null;
    const artist = spl.next() orelse return null;
    _ = spl.next(); // album
    const pos_ms_raw = spl.next() orelse "0";
    const dur_ms_raw = spl.next() orelse "0";
    _ = spl.next(); // volume
    _ = spl.next(); // shuffle
    _ = spl.next(); // repeat
    const art = spl.next() orelse "";

    const pos_ms = std.fmt.parseFloat(f64, pos_ms_raw) catch 0.0;
    const dur_ms = std.fmt.parseFloat(f64, dur_ms_raw) catch 0.0;

    return .{
        .title = title,
        .artist = artist,
        .playing = std.mem.eql(u8, pstate, "playing"),
        .elapsed = pos_ms / 1000.0,
        .duration = dur_ms / 1000.0,
        .artwork_url = art,
    };
}

/// Queries Spotifast for playback information.
/// Returns:
///   number of bytes copied into buf, with content:
///   - "CLOSED" if Spotifast is not running
///   - "NO_TRACK" if running but stopped / no track
///   - raw string starting with "fastpotify:now ..." on success
pub export fn widget_query_spotifast(buf: [*]u8, max_len: usize) callconv(.c) usize {
    var socket_buf: [2048]u8 = undefined;
    const read_len = sendPersistentQuery("nowplaying", &socket_buf) catch {
        const closed_str = "CLOSED";
        const copy_len = @min(closed_str.len, max_len);
        @memcpy(buf[0..copy_len], closed_str[0..copy_len]);
        return copy_len;
    };

    const trimmed = std.mem.trim(u8, socket_buf[0..read_len], " \r\n");
    if (std.mem.eql(u8, trimmed, "fastpotify:now stopped") or
        std.mem.eql(u8, trimmed, "fastpotify:now") or
        std.mem.eql(u8, trimmed, "stopped"))
    {
        const no_track = "NO_TRACK";
        const copy_len = @min(no_track.len, max_len);
        @memcpy(buf[0..copy_len], no_track[0..copy_len]);
        return copy_len;
    }

    const copy_len = @min(read_len, max_len);
    @memcpy(buf[0..copy_len], socket_buf[0..copy_len]);
    return copy_len;
}

test "parseSpotifastPayload basic" {
    const raw = "fastpotify:now playing\tTrack Name\tArtist Name\tAlbum Name\t35000\t210000\t70\toff\toff\thttps://example.com/art.jpg\tno\tSpotifast\n";
    const payload = parseSpotifastPayload(raw) orelse return error.TestFailed;
    try std.testing.expectEqualStrings("Track Name", payload.title);
    try std.testing.expectEqualStrings("Artist Name", payload.artist);
    try std.testing.expect(payload.playing);
    try std.testing.expectApproxEqAbs(35.0, payload.elapsed, 0.001);
    try std.testing.expectApproxEqAbs(210.0, payload.duration, 0.001);
    try std.testing.expectEqualStrings("https://example.com/art.jpg", payload.artwork_url);
}

test "parseSpotifastPayload stopped" {
    const raw = "fastpotify:now stopped\n";
    try std.testing.expect(parseSpotifastPayload(raw) == null);
}
