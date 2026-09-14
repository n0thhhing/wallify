with open("src/graphics/render.zig", "r") as f:
    text = f.read()

text = text.replace(".dx = @as(f32, @floatCast(x)),", ".dx = @as(f32, @floatCast(x * scale)),")
text = text.replace(".dy = @as(f32, @floatCast(y)),", ".dy = @as(f32, @floatCast(y * scale)),")
text = text.replace(".dw = @as(f32, @floatFromInt(cached_w)) / @as(f32, @floatFromInt(state.render_scale)),", ".dw = @as(f32, @floatFromInt(cached_w)),")
text = text.replace(".dh = @as(f32, @floatFromInt(cached_h)) / @as(f32, @floatFromInt(state.render_scale)),", ".dh = @as(f32, @floatFromInt(cached_h)),")

text = text.replace(".dw = @as(f32, @floatFromInt(visible_w_px)) / @as(f32, @floatFromInt(state.render_scale)),", ".dw = @as(f32, @floatFromInt(visible_w_px)),")

with open("src/graphics/render.zig", "w") as f:
    f.write(text)

