from pathlib import Path


def replace_exact(path: Path, old: str, new: str) -> None:
    text = path.read_text()

    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected exactly 1 occurrence, found {count}:\n{old}"
        )

    path.write_text(text.replace(old, new))


# state.zig: make both compact and expanded card X positions 0,
# and make the card Y position 0.
state = Path("src/state.zig")

replace_exact(
    state,
    "pub const card_x_compact: f64 = 8.0;",
    "pub const card_x_compact: f64 = 0.0;",
)

replace_exact(
    state,
    "pub const card_y: f64 = 35.0;",
    "pub const card_y: f64 = 0.0;",
)


# render.zig: use the centralized Layout.card_y value instead
# of hardcoding the Y position.
render = Path("src/graphics/render.zig")

replace_exact(
    render,
    "const card_y: isize = 35;",
    "const card_y: isize = @intFromFloat(state.Layout.card_y);",
)

print("Patched card origin to (0, 0) through state.Layout.")
