const std = @import("std");

pub const CFTypeRef = *anyopaque;
pub const CFDictionaryRef = *anyopaque;
pub const CFStringRef = *anyopaque;
pub const CFNumberRef = *anyopaque;
pub const CFTypeID = c_ulong;
pub const kCFStringEncodingUTF8: u32 = 0x08000100;
pub const kCFNumberFloat64Type = 13;

extern "c" fn dlopen(path: [*c]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: *anyopaque, symbol: [*c]const u8) ?*anyopaque;
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
extern "c" fn write(fd: c_int, buf: [*c]const u8, count: usize) isize;
extern "c" fn fopen(filename: [*c]const u8, mode: [*c]const u8) ?*anyopaque;
extern "c" fn fwrite(ptr: *const anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn usleep(useconds: c_uint) c_int;

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
var sema: ?*anyopaque = null;

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

        var current_title: [256]u8 = undefined;
        var current_artist: [256]u8 = undefined;
        @memset(&current_title, 0);
        @memset(&current_artist, 0);

        var has_title = false;
        var has_artist = false;
        var has_artwork = false;
        var rate: f64 = 0.0;
        var elapsed: f64 = 0.0;
        var duration: f64 = 0.0;

        if (CFDictionaryGetValue(dict, titleKey)) |titleRef| {
            if (CFGetTypeID(titleRef) == CFStringGetTypeID()) {
                _ = CFStringGetCString(@ptrCast(titleRef), &current_title, current_title.len, kCFStringEncodingUTF8);
                has_title = true;
            }
        }
        
        if (CFDictionaryGetValue(dict, artistKey)) |artistRef| {
            if (CFGetTypeID(artistRef) == CFStringGetTypeID()) {
                _ = CFStringGetCString(@ptrCast(artistRef), &current_artist, current_artist.len, kCFStringEncodingUTF8);
                has_artist = true;
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
                    const file = fopen("/tmp/mrc_artwork", "wb");
                    if (file) |f| {
                        _ = fwrite(ptr, 1, @intCast(len), f);
                        _ = fclose(f);
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
            // Title|||Artist|||HasArtwork|||PlaybackRate|||ElapsedTime|||Duration
            const msg = std.fmt.bufPrint(&buf, "{s}|||{s}|||{d}|||{d:.2}|||{d:.2}|||{d:.2}\n", .{
                current_title[0..title_len], 
                current_artist[0..artist_len], 
                if (has_artwork) @as(u8, 1) else @as(u8, 0),
                rate, elapsed, duration
            }) catch "\n";
            _ = write(1, msg.ptr, msg.len);
        } else {
            _ = write(1, "\n", 1);
        }
    } else {
        _ = write(1, "\n", 1);
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
    const handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", 1);
    if (handle) |h| {
        if (dlsym(h, "MRMediaRemoteGetNowPlayingInfo")) |get_ptr| {
            MRGetNowPlayingInfo = @as(*const fn (*anyopaque, *const BlockLiteral) callconv(.c) void, @ptrCast(@alignCast(get_ptr)));
        }
    }
    }
    if (MRGetNowPlayingInfo) |MRGet| {
        if (sema == null) sema = dispatch_semaphore_create(0);
        MRGet(dispatch_get_global_queue(0, 0), &get_block);
        
        // 250ms timeout using dispatch_time(DISPATCH_TIME_NOW, 250_000_000)
        const timeout = dispatch_time(0, 250_000_000);
        if (dispatch_semaphore_wait(sema.?, timeout) != 0) {
            _ = write(1, "\n", 1);
        }
    }
}

export fn mrc_sendCommand(cmd: c_uint) void {
    const handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", 1);
    if (handle) |h| {
        if (dlsym(h, "MRMediaRemoteSendCommand")) |cmd_ptr| {
            MRMediaRemoteSendCommand = @as(*const fn (c_uint, ?*anyopaque) callconv(.c) void, @ptrCast(@alignCast(cmd_ptr)));
        }
    }
    if (MRMediaRemoteSendCommand) |send_func| {
        send_func(cmd, null);
        _ = usleep(100000); 
    }
}

export fn mrc_seekTo(target: f64) void {
    const handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", 1);
    if (handle) |h| {
        if (dlsym(h, "MRMediaRemoteSetElapsedTime")) |set_ptr| {
            const MRSetElapsedTime = @as(*const fn (f64) callconv(.c) void, @ptrCast(@alignCast(set_ptr)));
            MRSetElapsedTime(target);
            _ = usleep(100000); 
        }
    }
}
