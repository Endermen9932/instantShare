#!/usr/bin/env python3
"""Renders the InstantShare icon for Android, Linux, Windows and the web.

Run from the repository root: python3 tool/generate_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
S = 1024  # master size
APP_ID = "io.github.endermen9932.instant_share"
TOP = (0x1E, 0x6F, 0xF2)
BOTTOM = (0x6A, 0x3D, 0xE8)


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
    return img


def glyph(size, scale):
    """White QR-like mark: three finder patterns and a forward chevron.

    scale is the share of the canvas the mark spans (adaptive icons need it
    inside the central safe zone).
    """
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    span = size * scale
    o = (size - span) / 2
    u = span / 7  # grid unit

    def finder(cx, cy):
        x, y = o + cx * u, o + cy * u
        r = u * 0.55
        d.rounded_rectangle([x, y, x + 3 * u, y + 3 * u], radius=r * 1.6, fill=255)
        d.rounded_rectangle([x + 0.55 * u, y + 0.55 * u, x + 2.45 * u, y + 2.45 * u],
                            radius=r, fill=0)
        d.rounded_rectangle([x + 1.0 * u, y + 1.0 * u, x + 2.0 * u, y + 2.0 * u],
                            radius=r * 0.6, fill=255)

    finder(0, 0)
    finder(4, 0)
    finder(0, 4)
    # Bottom-right: a bold "»" for the transfer.
    w = 0.62 * u
    for shift in (0.0, 1.35):
        x0 = o + (4.0 + shift) * u
        pts = [(x0, o + 4.0 * u), (x0 + 1.5 * u, o + 5.5 * u), (x0, o + 7.0 * u)]
        d.line(pts, fill=255, width=round(w), joint="curve")
        for px, py in (pts[0], pts[2]):
            d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=255)
        tip = pts[1]
        d.ellipse([tip[0] - w / 2, tip[1] - w / 2, tip[0] + w / 2, tip[1] + w / 2], fill=255)
    return img


def full_icon(size, radius_ratio=0.23, scale=0.56):
    """Gradient squircle with the mark, transparent corners."""
    big = S
    bg = gradient(big).convert("RGBA")
    mark = glyph(big, scale)
    white = Image.new("RGBA", (big, big), (255, 255, 255, 255))
    bg.paste(white, (0, 0), mark)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1],
                                           radius=big * radius_ratio, fill=255)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def square_icon(size, scale=0.5):
    """Full-bleed variant for maskable/adaptive use."""
    bg = gradient(S).convert("RGBA")
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    bg.paste(white, (0, 0), glyph(S, scale))
    return bg.resize((size, size), Image.LANCZOS)


def save(img, rel):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def main():
    master = full_icon(S)
    save(master, "assets/icon/icon.png")

    # Android legacy icons and adaptive layers (108dp canvas, 66dp safe zone).
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, f in densities.items():
        res = f"android/app/src/main/res/mipmap-{name}"
        save(full_icon(round(48 * f)), f"{res}/ic_launcher.png")
        layer = round(108 * f)
        fg = Image.new("RGBA", (layer, layer), (0, 0, 0, 0))
        white = Image.new("RGBA", (layer, layer), (255, 255, 255, 255))
        fg.paste(white, (0, 0), glyph(S, 0.5).resize((layer, layer), Image.LANCZOS))
        save(fg, f"{res}/ic_launcher_foreground.png")
        save(gradient(layer).convert("RGBA"), f"{res}/ic_launcher_background.png")
    adaptive = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""
    p = ROOT / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(adaptive)

    # Web / PWA.
    save(full_icon(192), "web/icons/Icon-192.png")
    save(full_icon(512), "web/icons/Icon-512.png")
    save(square_icon(192, 0.46), "web/icons/Icon-maskable-192.png")
    save(square_icon(512, 0.46), "web/icons/Icon-maskable-512.png")
    save(full_icon(64), "web/favicon.png")

    # Linux (.deb) icons.
    for size in (48, 64, 128, 256, 512):
        save(full_icon(size), f"packaging/linux/icons/{size}x{size}/{APP_ID}.png")

    # Windows .ico with the usual sizes.
    ico = ROOT / "windows/runner/resources/app_icon.ico"
    master.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


if __name__ == "__main__":
    main()
