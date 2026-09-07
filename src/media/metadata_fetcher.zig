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
extern "c" fn dispatch_semaphore_create(value: isize) *anyopaque;
extern "c" fn dispatch_semaphore_signal(dsema: *anyopaque) isize;
extern "c" fn dispatch_semaphore_wait(dsema: *anyopaque, timeout: u64) isize;
extern "c" fn dispatch_time(when: u64, delta: i64) u64;
extern "c" fn _dispatch_main_q() *anyopaque;
extern "c" fn dispatch_get_global_queue(identifier: isize, flags: usize) *anyopaque;
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

var MRGetNowPlayingInfo: ?*const fn (*anyopaque, *const BlockLiteral) callconv(.c) void = null;
var MRMediaRemoteSendCommand: ?*const fn (c_uint, ?*anyopaque) callconv(.c) void = null;
var MRMediaRemoteSetElapsedTime: ?*const fn (f64) callconv(.c) void = null;
var mr_lib: ?std.DynLib = null;
var sema: ?*anyopaque = null;

fn getMRLib() ?*std.DynLib {
    if (mr_lib == null) {
        mr_lib = std.DynLib.open("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote") catch null;
    }
    return if (mr_lib != null) &mr_lib.? else null;
}

fn completion_handler(block: *anyopaque, info: ?CFDictionaryRef) callconv(.c) void {
    _ = block;
    if (info) |dict| {
        const titleKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoTitle", kCFStringEncodingUTF8);
        const artistKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoArtist", kCFStringEncodingUTF8);
        const artworkKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoArtworkData", kCFStringEncodingUTF8);
        const rateKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoPlaybackRate", kCFStringEncodingUTF8);
        const elapsedKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoElapsedTime", kCFStringEncodingUTF8);
        const durationKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoDuration", kCFStringEncodingUTF8);
        const timestampKey = CFStringCreateWithCString(null, "kMRMediaRemoteNowPlayingInfoTimestamp", kCFStringEncodingUTF8);

        var current_title = std.mem.zeroes([256]u8);
        var current_artist = std.mem.zeroes([256]u8);
        var rate: f64 = 0.0;
        var elapsed: f64 = 0.0;
        var duration: f64 = 0.0;
        var has_artwork = false;
        var has_title = false;
        var has_artist = false;

        if (CFDictionaryGetValue(dict, titleKey)) |titleRef| {
            if (CFGetTypeID(titleRef) == CFStringGetTypeID()) {
                if (CFStringGetCString(@ptrCast(titleRef), &current_title, 256, kCFStringEncodingUTF8)) {
                    has_title = true;
                }
            }
        }
        
        if (CFDictionaryGetValue(dict, artistKey)) |artistRef| {
            if (CFGetTypeID(artistRef) == CFStringGetTypeID()) {
                if (CFStringGetCString(@ptrCast(artistRef), &current_artist, 256, kCFStringEncodingUTF8)) {
                    has_artist = true;
                }
            }
        }

        if (CFDictionaryGetValue(dict, rateKey)) |rateRef| {
            if (CFGetTypeID(rateRef) == CFNumberGetTypeID()) {
                _ = CFNumberGetValue(@ptrCast(rateRef), kCFNumberFloat64Type, &rate);
            }
        }

        if (CFDictionaryGetValue(dict, elapsedKey)) |valRef| {
            if (CFGetTypeID(valRef) == CFNumberGetTypeID()) {
                _ = CFNumberGetValue(@ptrCast(valRef), kCFNumberFloat64Type, &elapsed);
            }
        }
        
        if (CFDictionaryGetValue(dict, timestampKey)) |tsRef| {
            if (CFGetTypeID(tsRef) == CFDateGetTypeID()) {
                const ts = CFDateGetAbsoluteTime(tsRef);
                const now = CFAbsoluteTimeGetCurrent();
                elapsed += (now - ts) * rate;
            }
        }


        if (CFDictionaryGetValue(dict, durationKey)) |valRef| {
            if (CFGetTypeID(valRef) == CFNumberGetTypeID()) {
                _ = CFNumberGetValue(@ptrCast(valRef), kCFNumberFloat64Type, &duration);
            }
        }

        if (CFDictionaryGetValue(dict, artworkKey)) |artworkRef| {
            if (CFGetTypeID(artworkRef) == CFDataGetTypeID()) {
                const len = CFDataGetLength(artworkRef);
                const ptr = CFDataGetBytePtr(artworkRef);
                if (len > 0 and ptr != null) {
                    const art_fd = std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/mrc_artwork", .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch -1;
                    if (art_fd >= 0) {
                        defer _ = std.posix.system.close(art_fd);
                        _ = std.posix.system.write(art_fd, ptr.?, @intCast(len));
                        has_artwork = true;
                    }
                }
            }
        }

        CFRelease(@ptrCast(titleKey));
        CFRelease(@ptrCast(artistKey));
        CFRelease(@ptrCast(artworkKey));
        CFRelease(@ptrCast(rateKey));
        CFRelease(@ptrCast(elapsedKey));
        CFRelease(@ptrCast(durationKey));
        CFRelease(@ptrCast(timestampKey));

        if (has_title or has_artist) {
            const title_len = std.mem.indexOfScalar(u8, &current_title, 0) orelse 256;
            const artist_len = std.mem.indexOfScalar(u8, &current_artist, 0) orelse 256;
            
            var buf: [1024]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s}|||{s}|||{}|||{d:.2}|||{d:.2}|||{d:.2}\n", .{
                current_title[0..title_len], 
                current_artist[0..artist_len], 
                @as(u8, if (has_artwork) 1 else 0),
                rate, elapsed, duration
            }) catch "\n";
            _ = std.posix.system.write(std.posix.STDOUT_FILENO, msg.ptr, msg.len);
        } else {
            _ = std.posix.system.write(std.posix.STDOUT_FILENO, "\n", 1);
        }
    } else {
        _ = std.posix.system.write(std.posix.STDOUT_FILENO, "\n", 1);
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
    if (MRGetNowPlayingInfo == null) {
        if (getMRLib()) |lib| {
            MRGetNowPlayingInfo = lib.lookup(*const fn (*anyopaque, *const BlockLiteral) callconv(.c) void, "MRMediaRemoteGetNowPlayingInfo");
        }
    }
    if (MRGetNowPlayingInfo) |MRGet| {
        if (sema == null) sema = dispatch_semaphore_create(0);
        MRGet(dispatch_get_global_queue(0, 0), &get_block);
        
        // 250ms timeout using dispatch_time(DISPATCH_TIME_NOW, 250_000_000)
        const timeout = dispatch_time(0, 250_000_000);
        if (dispatch_semaphore_wait(sema.?, timeout) != 0) {
            _ = std.posix.system.write(std.posix.STDOUT_FILENO, "\n", 1);
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

export fn mrc_seekTo(target: f64) void {
    if (MRMediaRemoteSetElapsedTime == null) {
        if (getMRLib()) |lib| {
            MRMediaRemoteSetElapsedTime = lib.lookup(*const fn (f64) callconv(.c) void, "MRMediaRemoteSetElapsedTime");
        }
    }
    if (MRMediaRemoteSetElapsedTime) |set_func| {
        set_func(target);
        sleep_us(100000); 
    }
}
