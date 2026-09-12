const std = @import("std");

pub const Ref = ?*anyopaque;

pub const DictionaryCallbacks = extern struct {
    version: isize,
    retain: Ref,
    release: Ref,
    copyDescription: Ref,
    equal: Ref,
    hash: Ref,
};

pub extern "c" var kCFTypeDictionaryKeyCallBacks: DictionaryCallbacks;
pub extern "c" var kCFTypeDictionaryValueCallBacks: DictionaryCallbacks;

pub extern "c" fn CFRelease(?*const anyopaque) void;
pub extern "c" fn CFRetain(?*const anyopaque) ?*const anyopaque;
pub extern "c" fn CFStringCreateWithBytes(alloc: Ref, bytes: [*]const u8, numBytes: isize, encoding: u32, isExternalRepresentation: u8) Ref;
pub extern "c" fn CFStringGetCString(theString: Ref, buffer: [*]u8, bufferSize: isize, encoding: u32) u8;
pub extern "c" fn CFStringGetLength(theString: Ref) isize;
pub extern "c" fn CFGetTypeID(cf: Ref) usize;
pub extern "c" fn CFStringGetTypeID() usize;
pub extern "c" fn CFDictionaryGetValue(theDict: Ref, key: ?*const anyopaque) Ref;
pub extern "c" fn CFArrayGetCount(theArray: Ref) isize;
pub extern "c" fn CFArrayGetValueAtIndex(theArray: Ref, idx: isize) Ref;
pub extern "c" fn CFNumberGetValue(number: Ref, numberType: c_int, value: *anyopaque) bool;
pub extern "c" fn CFDictionaryCreate(allocator: Ref, keys: [*]const Ref, values: [*]const Ref, numValues: isize, keyCallBacks: *const anyopaque, valueCallBacks: *const anyopaque) Ref;
pub extern "c" fn CFAttributedStringCreate(allocator: Ref, str: Ref, attributes: Ref) Ref;
pub extern "c" fn CFURLCreateFromFileSystemRepresentation(allocator: Ref, buffer: [*]const u8, bufLen: isize, isDirectory: u8) Ref;
pub extern "c" fn CFNotificationCenterGetDistributedCenter() Ref;
pub extern "c" fn CFNotificationCenterAddObserver(center: Ref, observer: Ref, callback: *const fn (Ref, Ref, Ref, Ref, Ref) callconv(.c) void, name: Ref, object: Ref, suspensionBehavior: isize) void;

pub fn string(bytes: []const u8) Ref {
    return CFStringCreateWithBytes(null, bytes.ptr, @intCast(bytes.len), 0x08000100, 0);
}
