const std = @import("std");

pub const CFTypeRef = *anyopaque;
pub const CFDictionaryRef = *anyopaque;
pub const CFStringRef = *anyopaque;
pub const CFNumberRef = *anyopaque;
pub const CFTypeID = c_ulong;
pub const kCFStringEncodingUTF8: u32 = 0x08000100;
pub const kCFNumberFloat64Type = 13;

extern "c" fn CFDictionaryGetValue(dict: CFDictionaryRef, key: CFStringRef) ?CFTypeRef;
extern "c" fn CFGetTypeID(cf: CFTypeRef) CFTypeID;
extern "c" fn CFStringGetTypeID() CFTypeID;
extern "c" fn CFDataGetTypeID() CFTypeID;
extern "c" fn CFNumberGetTypeID() CFTypeID;
extern "c" fn CFDataGetBytePtr(theData: CFTypeRef) [*c]const u8;
extern "c" fn CFDataGetLength(theData: CFTypeRef) isize;
extern "c" fn CFStringGetCString(theString: CFStringRef, buffer: [*c]u8, bufferSize: isize, encoding: u32) bool;
extern "c" fn CFStringCreateWithCString(alloc: ?*anyopaque, cStr: [*c]const u8, encoding: u32) CFStringRef;
extern "c" fn CFDateGetTypeID() CFTypeID;
extern "c" fn CFDateGetAbsoluteTime(theDate: CFTypeRef) f64;
extern "c" fn CFAbsoluteTimeGetCurrent() f64;
extern "c" fn CFNumberGetValue(number: CFNumberRef, theType: c_long, valuePtr: *anyopaque) bool;
extern "c" fn CFRelease(cf: CFTypeRef) void;
extern "c" fn atexit(function: *const fn () callconv(.c) void) c_int;
extern "c" fn dispatch_semaphore_create(value: isize) *anyopaque;
extern "c" fn dispatch_semaphore_signal(dsema: *anyopaque) isize;
extern "c" fn dispatch_semaphore_wait(dsema: *anyopaque, timeout: u64) isize;
extern "c" fn dispatch_time(when: u64, delta: i64) u64;
extern "c" fn _dispatch_main_q() *anyopaque;
extern "c" fn dispatch_get_global_queue(identifier: isize, flags: usize) *anyopaque;
extern "c" fn mrc_notifications_init() void;
extern "c" fn mrc_wait_for_notification() c_int;
fn sleep_us(us: u64) void {
    const ts = std.posix.timespec{
        .sec = @intCast(us / 1_000_000),
        .nsec = @intCast((us % 1_000_000) * 1_000),
    };
    _ = std.posix.system.nanosleep(&ts, null);
}

extern "c" var _NSConcreteGlobalBlock: anyopaque;

const BlockDescriptor = extern struct {
    reserved: c_ulong,
    size: c_ulong,
};
const BlockLiteral = extern struct {
    isa: *anyopaque,
    flags: c_int,
    reserved: c_int,
    invoke: *const fn (*anyopaque, ?CFDictionaryRef) callconv(.c) void,
    descriptor: *const BlockDescriptor,
};

const IsPlayingBlockLiteral = extern struct {
    isa: *anyopaque,
    flags: c_int,
    reserved: c_int,
    invoke: *const fn (*anyopaque, bool) callconv(.c) void,
    descriptor: *const BlockDescriptor,
};

var MRGetNowPlayingInfo: ?*const fn (*anyopaque, *const BlockLiteral) callconv(.c) void = null;
var MRGetNowPlayingIsPlaying: ?*const fn (*anyopaque, *const IsPlayingBlockLiteral) callconv(.c) void = null;
var MRMediaRemoteSendCommand: ?*const fn (c_uint, ?*anyopaque) callconv(.c) void = null;
var MRMediaRemoteSetElapsedTime: ?*const fn (f64) callconv(.c) void = null;
var mr_lib: ?std.DynLib = null;
var sema: ?*anyopaque = null;
var is_playing_sema: ?*anyopaque = null;
var is_playing_val: bool = false;
var last_mrc_art_hash: u64 = 0;
var last_mrc_title = std.mem.zeroes([256]u8);
var last_mrc_artist = std.mem.zeroes([256]u8);
var last_mrc_title_len: usize = 0;
var last_mrc_artist_len: usize = 0;
var last_mrc_track_valid = false;
var last_mrc_has_artwork = false;

fn getMRLib() ?*std.DynLib {
    if (mr_lib == null) {
        mr_lib = std.DynLib.open("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote") catch null;
    }
    return if (mr_lib != null) &mr_lib.? else null;
}

fn writeStdoutAndCheck(msg: []const u8) void {
    const res = std.posix.system.write(std.posix.STDOUT_FILENO, msg.ptr, msg.len);
    if (res <= 0) {
        std.process.exit(0);
    }
}

fn is_playing_handler(_: *anyopaque, playing: bool) callconv(.c) void {
    is_playing_val = playing;
    if (is_playing_sema) |s| {
        _ = dispatch_semaphore_signal(s);
    }
}

const is_playing_desc = BlockDescriptor{ .reserved = 0, .size = @sizeOf(IsPlayingBlockLiteral) };
const is_playing_block = IsPlayingBlockLiteral{
    .isa = &_NSConcreteGlobalBlock,
    .flags = (1 << 28) | (1 << 29),
    .reserved = 0,
    .invoke = is_playing_handler,
    .descriptor = &is_playing_desc,
};

var g_titleKey: ?CFStringRef = null;
var g_artistKey: ?CFStringRef = null;
var g_artworkKey: ?CFStringRef = null;
var g_rateKey: ?CFStringRef = null;
var g_elapsedKey: ?CFStringRef = null;
var g_durationKey: ?CFStringRef = null;
var g_timestampKey: ?CFStringRef = null;
var cleanup_registered = false;

fn cleanupCachedCFKeys() callconv(.c) void {
    if (g_titleKey) |key| { CFRelease(key); g_titleKey = null; }
    if (g_artistKey) |key| { CFRelease(key); g_artistKey = null; }
    if (g_artworkKey) |key| { CFRelease(key); g_artworkKey = null; }
    if (g_rateKey) |key| { CFRelease(key); g_rateKey = null; }
    if (g_elapsedKey) |key| { CFRelease(key); g_elapsedKey = null; }
    if (g_durationKey) |key| { CFRelease(key); g_durationKey = null; }
    if (g_timestampKey) |key| { CFRelease(key); g_timestampKey = null; }
}

fn registerCleanup() void {
    if (!cleanup_registered) {
        _ = atexit(cleanupCachedCFKeys);
        cleanup_registered = true;
    }
}

// PERF: By statically caching these CoreFoundation string references after the first initialization,
// we prevent the Perl daemon from repeatedly churning heap allocations and stalling the main thread
// every 150ms when polling MediaRemote dictionary payloads.
fn completion_handler(block: *anyopaque, info: ?CFDictionaryRef) callconv(.c) void {
    _ = block;
    if (info) |dict| {
        if (g_titleKey == null) {
            registerCleanup();
            g_titleKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoTitle", kCFStringEncodingUTF8);
            g_artistKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoArtist", kCFStringEncodingUTF8);
            g_artworkKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoArtworkData", kCFStringEncodingUTF8);
            g_rateKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoPlaybackRate", kCFStringEncodingUTF8);
            g_elapsedKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoElapsedTime", kCFStringEncodingUTF8);
            g_durationKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoDuration", kCFStringEncodingUTF8);
            g_timestampKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoTimestamp", kCFStringEncodingUTF8);
        }
        const titleKey = g_titleKey.?;
        const artistKey = g_artistKey.?;
        const artworkKey = g_artworkKey.?;
        const rateKey = g_rateKey.?;
        const elapsedKey = g_elapsedKey.?;
        const durationKey = g_durationKey.?;
        const timestampKey = g_timestampKey.?;

        var current_title = std.mem.zeroes([256]u8);
        var current_artist = std.mem.zeroes([256]u8);
        var rate: f64 = 0.0;
        var has_rate = false;
        var elapsed: f64 = 0.0;
        var duration: f64 = 0.0;
        var has_artwork = false;

        var has_title = false;
        if (CFDictionaryGetValue(dict, titleKey)) |valRef| {
            if (CFGetTypeID(valRef) == CFStringGetTypeID()) {
                has_title = CFStringGetCString(@ptrCast(valRef), &current_title, 256, kCFStringEncodingUTF8);
            }
        }

        var has_artist = false;
        if (CFDictionaryGetValue(dict, artistKey)) |valRef| {
            if (CFGetTypeID(valRef) == CFStringGetTypeID()) {
                has_artist = CFStringGetCString(@ptrCast(valRef), &current_artist, 256, kCFStringEncodingUTF8);
            }
        }

        if (CFDictionaryGetValue(dict, rateKey)) |rateRef| {
            if (CFGetTypeID(rateRef) == CFNumberGetTypeID()) {
                if (CFNumberGetValue(@ptrCast(rateRef), kCFNumberFloat64Type, &rate)) {
                    has_rate = true;
                }
            }
        }

        if (!has_rate) {
            rate = if (is_playing_val) 1.0 else 0.0;
        }

        if (CFDictionaryGetValue(dict, elapsedKey)) |valRef| {
            if (CFGetTypeID(valRef) == CFNumberGetTypeID()) {
                _ = CFNumberGetValue(@ptrCast(valRef), kCFNumberFloat64Type, &elapsed);
            }
        }

        if (CFDictionaryGetValue(dict, timestampKey)) |valRef| {
            if (CFGetTypeID(valRef) == CFDateGetTypeID()) {
                const ts = CFDateGetAbsoluteTime(valRef);
                const now = CFAbsoluteTimeGetCurrent();
                const delta = now - ts;
                if (delta > 0 and rate > 0) {
                    elapsed += delta * rate;
                }
            }
        }

        if (CFDictionaryGetValue(dict, durationKey)) |valRef| {
            if (CFGetTypeID(valRef) == CFNumberGetTypeID()) {
                _ = CFNumberGetValue(@ptrCast(valRef), kCFNumberFloat64Type, &duration);
            }
        }

        const title_len = std.mem.indexOfScalar(u8, &current_title, 0) orelse 256;
        const artist_len = std.mem.indexOfScalar(u8, &current_artist, 0) orelse 256;
        const track_changed = !last_mrc_track_valid or
            title_len != last_mrc_title_len or
            artist_len != last_mrc_artist_len or
            !std.mem.eql(u8, current_title[0..title_len], last_mrc_title[0..last_mrc_title_len]) or
            !std.mem.eql(u8, current_artist[0..artist_len], last_mrc_artist[0..last_mrc_artist_len]);

        // Album art can arrive shortly after the title/artist notification.
        // Retry while it is missing, but skip the expensive payload work once
        // the current track already has artwork.
        if (track_changed or !last_mrc_has_artwork) {
            last_mrc_has_artwork = false;
            if (CFDictionaryGetValue(dict, artworkKey)) |artworkRef| {
                if (CFGetTypeID(artworkRef) == CFDataGetTypeID()) {
                    const len = CFDataGetLength(artworkRef);
                    const ptr = CFDataGetBytePtr(artworkRef);
                    if (len > 0 and ptr != null) {
                        const art_slice = ptr[0..@intCast(len)];
                        const art_hash = std.hash.Wyhash.hash(0, art_slice);
                        if (art_hash == last_mrc_art_hash) {
                            last_mrc_has_artwork = true;
                        } else {
                            const art_fd = std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/mrc_artwork_tmp", .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch -1;
                            if (art_fd >= 0) {
                                defer _ = std.posix.system.close(art_fd);
                                var written: usize = 0;
                                const target_len: usize = @intCast(len);
                                var write_err = false;
                                while (written < target_len) {
                                    const res = std.posix.system.write(art_fd, ptr + written, target_len - written);
                                    if (res <= 0) {
                                        write_err = true;
                                        break;
                                    }
                                    written += @intCast(res);
                                }
                                if (!write_err and written == target_len) {
                                    if (std.posix.system.rename("/tmp/mrc_artwork_tmp", "/tmp/mrc_artwork") == 0) {
                                        last_mrc_art_hash = art_hash;
                                        last_mrc_has_artwork = true;
                                    }
                                }
                            }
                        }
                    } else {
                        last_mrc_art_hash = 0;
                    }
                } else {
                    last_mrc_art_hash = 0;
                }
            } else {
                last_mrc_art_hash = 0;
            }
        }
        has_artwork = last_mrc_has_artwork;

        // Keys are cached globally, no release needed.

        if (has_title or has_artist) {
            var buf: [1024]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s}|||{s}|||{}|||{d:.2}|||{d:.2}|||{d:.2}\n", .{ current_title[0..title_len], current_artist[0..artist_len], @as(u8, if (has_artwork) 1 else 0), rate, elapsed, duration }) catch "\n";
            writeStdoutAndCheck(msg);
        } else {
            writeStdoutAndCheck("\n");
        }

        if (has_title or has_artist) {
            const copy_title_len = @min(title_len, last_mrc_title.len);
            const copy_artist_len = @min(artist_len, last_mrc_artist.len);
            if (copy_title_len > 0) @memcpy(last_mrc_title[0..copy_title_len], current_title[0..copy_title_len]);
            if (copy_artist_len > 0) @memcpy(last_mrc_artist[0..copy_artist_len], current_artist[0..copy_artist_len]);
            last_mrc_title_len = copy_title_len;
            last_mrc_artist_len = copy_artist_len;
            last_mrc_track_valid = true;
        }
    } else {
        writeStdoutAndCheck("\n");
    }
    _ = dispatch_semaphore_signal(sema.?);
}

const desc = BlockDescriptor{ .reserved = 0, .size = @sizeOf(BlockLiteral) };
const get_block = BlockLiteral{
    .isa = &_NSConcreteGlobalBlock,
    .flags = (1 << 28) | (1 << 29),
    .reserved = 0,
    .invoke = completion_handler,
    .descriptor = &desc,
};

export fn mrc_printNowPlayingInfo() void {
    mrc_notifications_init();
    if (MRGetNowPlayingInfo == null) {
        if (getMRLib()) |lib| {
            MRGetNowPlayingInfo = lib.lookup(*const fn (*anyopaque, *const BlockLiteral) callconv(.c) void, "MRMediaRemoteGetNowPlayingInfo");
        }
    }
    if (MRGetNowPlayingIsPlaying == null) {
        if (getMRLib()) |lib| {
            MRGetNowPlayingIsPlaying = lib.lookup(*const fn (*anyopaque, *const IsPlayingBlockLiteral) callconv(.c) void, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        }
    }

    // Playback rate is normally present in the Now Playing dictionary.
    // Avoid a second MediaRemote round-trip on every update; the cached value
    // is only used when the dictionary omits the rate.
    if (MRGetNowPlayingInfo) |MRGet| {
        if (sema == null) sema = dispatch_semaphore_create(0);
        // A previous request can leave a completion token behind. Drain it so
        // this wait always corresponds to the request we issue below.
        while (dispatch_semaphore_wait(sema.?, dispatch_time(0, 0)) == 0) {}
        MRGet(dispatch_get_global_queue(0, 0), &get_block);

        // Keep the fallback short so delayed artwork is picked up quickly;
        // normal metadata changes arrive through MediaRemote notifications.
        const timeout = dispatch_time(0, 100_000_000);
        if (dispatch_semaphore_wait(sema.?, timeout) != 0) {
            writeStdoutAndCheck("\n");
        }
    }
}

export fn mrc_sendCommand(cmd: c_uint) void {
    if (MRMediaRemoteSendCommand == null) {
        if (getMRLib()) |lib| {
            MRMediaRemoteSendCommand = lib.lookup(*const fn (c_uint, ?*anyopaque) callconv(.c) void, "MRMediaRemoteSendCommand");
        }
    }
    if (MRMediaRemoteSendCommand) |send_func| {
        send_func(cmd, null);
        sleep_us(100000);
    }
}
