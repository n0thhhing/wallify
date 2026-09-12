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

pub fn send0(comptime R: type, obj: Ref, selector: [*:0]const u8) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel);
}

pub fn send1(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a);
}

pub fn send2(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A, comptime B: type, b: B) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A, B) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a, b);
}

pub fn send3(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A, comptime B: type, b: B, comptime C: type, c: C) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A, B, C) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a, b, c);
}

pub fn send4(comptime R: type, obj: Ref, selector: [*:0]const u8, comptime A: type, a: A, comptime B: type, b: B, comptime C: type, c: C, comptime D: type, d: D) R {
    const sel = sel_registerName(selector);
    const f = @as(*const fn (Ref, Ref, A, B, C, D) callconv(.c) R, @ptrCast(&objc_msgSend));
    return f(obj, sel, a, b, c, d);
}
