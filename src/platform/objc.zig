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

/// Unified Objective-C message dispatcher leveraging Zig's comptime `@Fn` and `@call`.
///
/// ## Background & Objective-C ABI Requirements
/// In the Apple Objective-C runtime (both ARM64 and x86_64), `objc_msgSend` is an assembly trampoline
/// with no fixed C prototype. Crucially, it must NEVER be called through a C variadic signature (`...`)
/// because the Darwin ARM64 ABI passes variadic arguments on the stack, whereas fixed parameters are
/// passed directly in CPU registers (`x0`–`x7` for integers/pointers and `d0`–`d7` for floats).
/// Calling `objc_msgSend` therefore requires casting it to a function pointer whose exact parameter
/// types and return type match the target method selector.
///
/// ## Implementation
/// Rather than writing hardcoded switch branches for every parameter count, this function:
/// 1. Prepends the mandatory Objective-C receiver (`id` / `Ref`) and selector (`SEL` / `Ref`) to `args`.
/// 2. Dynamically generates parameter type arrays and attributes at comptime.
/// 3. Uses Zig 0.16's `@Fn` builtin to construct the exact C function type: `*const fn (Ref, Ref, ...) callconv(.c) R`.
/// 4. Dispatches the call via `@call(.auto, f, full_args)` with zero runtime overhead.
///
/// Example: `send(void, panel, "setAlphaValue:", .{@as(f64, 1.0)});`
pub fn send(comptime R: type, obj: Ref, selector: [*:0]const u8, args: anytype) R {
    const sel = sel_registerName(selector);
    const Args = @TypeOf(args);
    const info = @typeInfo(Args);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("send expects a tuple of arguments, e.g. .{} or .{arg1, arg2}");
    }
    const full_args = .{ obj, sel } ++ args;
    const full_info = @typeInfo(@TypeOf(full_args)).@"struct";

    comptime var param_types: [full_info.fields.len]type = undefined;
    comptime var param_attrs: [full_info.fields.len]std.builtin.Type.Fn.Param.Attributes = undefined;
    inline for (full_info.fields, 0..) |field, i| {
        param_types[i] = field.type;
        param_attrs[i] = .{ .@"noalias" = false };
    }

    const FnType = @Fn(&param_types, &param_attrs, R, .{ .@"callconv" = .c, .varargs = false });
    const f: *const FnType = @ptrCast(&objc_msgSend);
    return @call(.auto, f, full_args);
}
