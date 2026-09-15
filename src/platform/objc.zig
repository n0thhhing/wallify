const std = @import("std");
const Ref = @import("core_foundation.zig").Ref;

pub extern "objc" fn objc_getClass(name: [*:0]const u8) Ref;
pub extern "objc" fn sel_registerName(name: [*:0]const u8) Ref;
pub extern "objc" fn objc_msgSend() void;
pub extern "objc" fn objc_allocateClassPair(superclass: Ref, name: [*:0]const u8, extraBytes: usize) Ref;
pub extern "objc" fn objc_registerClassPair(cls: Ref) void;
pub extern "objc" fn class_addMethod(cls: Ref, name: Ref, imp: *const anyopaque, types: [*:0]const u8) bool;

pub extern "c" fn dispatch_async_f(queue: Ref, context: Ref, work: *const fn (Ref) callconv(.c) void) void;
pub extern "c" var _dispatch_main_q: u8;

pub fn dispatch_get_main_queue() Ref {
    return @ptrCast(&_dispatch_main_q);
}

// Unified Objective-C message sender replacing numbered send0/1/2/3/4 calls.
// Accepts an arbitrary tuple of arguments: send(ReturnType, obj, "selector", .{ arg1, arg2, ... }).
pub fn send(comptime R: type, obj: Ref, selector: [*:0]const u8, args: anytype) R {
    const sel = sel_registerName(selector);
    const Args = @TypeOf(args);
    const info = @typeInfo(Args);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("send expects a tuple of arguments, e.g. .{} or .{arg1, arg2}");
    }
    return switch (args.len) {
        0 => {
            const f: *const fn (Ref, Ref) callconv(.c) R = @ptrCast(&objc_msgSend);
            return f(obj, sel);
        },
        1 => {
            const f: *const fn (Ref, Ref, @TypeOf(args[0])) callconv(.c) R = @ptrCast(&objc_msgSend);
            return f(obj, sel, args[0]);
        },
        2 => {
            const f: *const fn (Ref, Ref, @TypeOf(args[0]), @TypeOf(args[1])) callconv(.c) R = @ptrCast(&objc_msgSend);
            return f(obj, sel, args[0], args[1]);
        },
        3 => {
            const f: *const fn (Ref, Ref, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2])) callconv(.c) R = @ptrCast(&objc_msgSend);
            return f(obj, sel, args[0], args[1], args[2]);
        },
        4 => {
            const f: *const fn (Ref, Ref, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2]), @TypeOf(args[3])) callconv(.c) R = @ptrCast(&objc_msgSend);
            return f(obj, sel, args[0], args[1], args[2], args[3]);
        },
        5 => {
            const f: *const fn (Ref, Ref, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2]), @TypeOf(args[3]), @TypeOf(args[4])) callconv(.c) R = @ptrCast(&objc_msgSend);
            return f(obj, sel, args[0], args[1], args[2], args[3], args[4]);
        },
        6 => {
            const f: *const fn (Ref, Ref, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2]), @TypeOf(args[3]), @TypeOf(args[4]), @TypeOf(args[5])) callconv(.c) R = @ptrCast(&objc_msgSend);
            return f(obj, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
        },
        else => @compileError("Too many arguments for send (max supported is 6)"),
    };
}
