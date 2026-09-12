const std = @import("std");
const Ref = @import("core_foundation.zig").Ref;

pub extern "c" var kCTFontAttributeName: Ref;
pub extern "c" var kCTForegroundColorAttributeName: Ref;

pub extern "c" fn CTFontCreateUIFontForLanguage(fontType: u32, size: f64, language: Ref) Ref;
pub extern "c" fn CTLineCreateWithAttributedString(attrString: Ref) Ref;
pub extern "c" fn CTLineGetTypographicBounds(line: Ref, ascent: ?*f64, descent: ?*f64, leading: ?*f64) f64;
pub extern "c" fn CTLineCreateTruncatedLine(line: Ref, width: f64, truncationType: u32, truncationToken: Ref) Ref;
pub extern "c" fn CTLineDraw(line: Ref, context: Ref) void;

pub const kCTFontUIFontSystem: u32 = 0;
pub const kCTFontUIFontEmphasizedSystem: u32 = 2;
pub const kCTLineTruncationEnd: u32 = 2;
