with open("src/state.zig", "r") as f:
    text = f.read()

text = text.replace("pub var global_anim_art_t: f64 = 1.0;", "pub var global_anim_art_t: f64 = 1.0;\npub var global_hover_target: HitTarget = .none;\npub var global_click_target: HitTarget = .none;")

with open("src/state.zig", "w") as f:
    f.write(text)
