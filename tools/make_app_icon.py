#!/usr/bin/env python3
"""Generate original Armoury-inspired app icons. Not an ASUS/ROG trademark copy."""
from __future__ import annotations

import io
import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "WindowsGameRuntimeASUSSelfHealing.WinUI" / "Assets"
PUBLIC = Path("/workspace/public")

BG = (11, 12, 16, 255)
HEX_FILL = (28, 32, 40, 255)
HEX_EDGE = (210, 216, 224, 255)
HEX_INNER = (18, 20, 26, 255)
STEEL = (160, 168, 180, 255)
CRIMSON = (225, 6, 0, 255)
CRIMSON_DARK = (150, 8, 8, 255)
CIRCUIT = (92, 102, 118, 255)


def hexagon(cx: float, cy: float, r: float) -> list[tuple[float, float]]:
    pts: list[tuple[float, float]] = []
    start = -math.pi / 2
    for i in range(6):
        a = start + i * math.pi / 3
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = size * 0.045
    radius = size * 0.22
    d.rounded_rectangle(
        [pad, pad, size - 1 - pad, size - 1 - pad],
        radius=radius,
        fill=BG,
    )

    cx = cy = size / 2
    r = size * 0.34
    outer = hexagon(cx, cy, r)
    d.polygon(outer, fill=HEX_FILL)
    d.line(outer + [outer[0]], fill=HEX_EDGE, width=max(2, size // 42))

    inner = hexagon(cx, cy, r * 0.78)
    d.polygon(inner, fill=HEX_INNER)
    d.line(inner + [inner[0]], fill=STEEL, width=max(1, size // 90))

    if size >= 48:
        w = max(1, size // 128)
        for i in range(6):
            a = -math.pi / 2 + i * math.pi / 3
            x1 = cx + math.cos(a) * r * 0.22
            y1 = cy + math.sin(a) * r * 0.22
            x2 = cx + math.cos(a) * r * 0.62
            y2 = cy + math.sin(a) * r * 0.62
            d.line([(x1, y1), (x2, y2)], fill=CIRCUIT, width=w)
        core_r = size * 0.035
        d.ellipse([cx - core_r, cy - core_r, cx + core_r, cy + core_r], fill=STEEL)

    slash_w = size * 0.09
    dx = size * 0.22
    dy = size * 0.28
    slash = [
        (cx - dx - slash_w * 0.35, cy + dy),
        (cx - dx + slash_w, cy + dy),
        (cx + dx + slash_w * 0.35, cy - dy),
        (cx + dx - slash_w, cy - dy),
    ]
    d.polygon(slash, fill=CRIMSON)
    d.line([slash[0], slash[3]], fill=CRIMSON_DARK, width=max(1, size // 180))
    return img


def write_png_ico(path: Path, images: list[Image.Image]) -> None:
    blobs: list[tuple[int, int, bytes]] = []
    for im in images:
        buf = io.BytesIO()
        im.save(buf, format="PNG")
        blobs.append((im.size[0], im.size[1], buf.getvalue()))
    count = len(blobs)
    header = struct.pack("<HHH", 0, 1, count)
    offset = 6 + 16 * count
    entries = bytearray()
    payload = bytearray()
    for w, h, blob in blobs:
        ww = 0 if w >= 256 else w
        hh = 0 if h >= 256 else h
        entries += struct.pack("<BBBBHHII", ww, hh, 0, 0, 1, 32, len(blob), offset)
        payload += blob
        offset += len(blob)
    path.write_bytes(header + entries + payload)


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    master = draw_icon(1024).filter(ImageFilter.UnsharpMask(radius=1.2, percent=80, threshold=2))
    png256 = master.resize((256, 256), Image.Resampling.LANCZOS)
    png32 = draw_icon(128).resize((32, 32), Image.Resampling.LANCZOS)
    png256.save(ASSETS / "app.png", "PNG")
    png32.save(ASSETS / "app-32.png", "PNG")

    sizes = (16, 24, 32, 48, 64, 128, 256)
    frames = []
    for s in sizes:
        src = draw_icon(s * 4) if s <= 64 else master
        frames.append(src.resize((s, s), Image.Resampling.LANCZOS))
    ico = ASSETS / "app.ico"
    write_png_ico(ico, frames)

    PUBLIC.mkdir(parents=True, exist_ok=True)
    png256.save(PUBLIC / "app-icon.png", "PNG")
    print("wrote", ico, ico.stat().st_size, "bytes", "frames", sizes)


if __name__ == "__main__":
    main()
