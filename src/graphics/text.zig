pub extern "c" fn widget_text_width(utf8: [*]const u8, length: usize, font_size: f64, bold: c_int) f64;
pub extern "c" fn widget_text(pixels: [*]u32, width: usize, height: usize, utf8: [*]const u8, length: usize, x: f64, y: f64, max_width: f64, font_size: f64, bold: c_int, right_align: c_int, r: u8, g: u8, b: u8) void;
