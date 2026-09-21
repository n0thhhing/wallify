#!/usr/bin/env python3
"""Encode an RGBA PNG in Wallify's RLE format (requires Pillow)."""
import argparse
from pathlib import Path
from PIL import Image


def encode(pixels):
    output = bytearray()
    index = 0
    while index < len(pixels):
        end = index + 1
        while end < len(pixels) and end - index < 127 and pixels[end] == pixels[index]:
            end += 1
        output.append(128 | (end - index))
        output.extend(pixels[index])
        index = end
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    with Image.open(args.source) as image:
        rgba = image.convert("RGBA")
        args.destination.write_bytes(encode(list(rgba.getdata())))
        print(f"Encoded {rgba.width}x{rgba.height} to {args.destination}")
