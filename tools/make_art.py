#!/usr/bin/env python3
"""Generates Kart Clash's full-resolution 2D art: app icons (Android, iOS, web),
the boot splash and store graphics. Everything is drawn here from shapes, so the
art is original and can be regenerated at any size.

Usage:  python3 tools/make_art.py            (needs Pillow: pip install pillow)
Title text uses the Inter font (SIL Open Font License) when it's installed, else
Pillow's default font.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # supersampling factor

NAVY = (20, 27, 51)
NAVY_DARK = (11, 16, 34)
NAVY_LIGHT = (31, 42, 82)
ORANGE = (255, 122, 26)
ORANGE_DARK = (204, 84, 10)
GOLD = (255, 210, 63)
TEAL = (25, 195, 177)
PINK = (255, 79, 216)
WHITE = (245, 247, 255)
TYRE = (28, 28, 36)
RIM = (170, 178, 200)

FONT_PATHS = [
    "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
    "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def font(size):
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def canvas(w, h, color=(0, 0, 0, 0)):
    img = Image.new("RGBA", (w * SS, h * SS), color)
    return img, ImageDraw.Draw(img)


def finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def radial_bg(w, h, inner, outer, center=(0.5, 0.45), radius=0.75):
    """Radial gradient background (drawn small and scaled up: smooth and fast)."""
    sw, sh = max(w // 8, 2), max(h // 8, 2)
    small = Image.new("RGB", (sw, sh))
    px = small.load()
    cx, cy = center[0] * sw, center[1] * sh
    rmax = radius * math.hypot(sw, sh) * 0.5
    for y in range(sh):
        for x in range(sw):
            t = min(math.hypot(x - cx, y - cy) / rmax, 1.0)
            t = t * t * (3 - 2 * t)
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return small.resize((w * SS, h * SS), Image.BICUBIC).convert("RGBA")


def poly(d, pts, fill, cx, cy, s):
    d.polygon([(cx + x * s, cy + y * s) for x, y in pts], fill=fill)


def circle(d, x, y, r, fill):
    d.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def draw_kart(img, cx, cy, s, body=ORANGE, accent=GOLD, pods=True):
    """Three-quarter front view of the kart. (cx, cy) is the centre, s the scale
    (1 unit ~ s px; the kart is about 200 units wide)."""
    d = ImageDraw.Draw(img, "RGBA")
    # Shadow.
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse((cx - 108 * s, cy + 46 * s, cx + 108 * s, cy + 78 * s), fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(8 * s))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img, "RGBA")
    # Rear wheels (peeking out behind).
    for wx in (-78, 78):
        d.rounded_rectangle((cx + (wx - 20) * s, cy - 18 * s, cx + (wx + 20) * s, cy + 30 * s), radius=10 * s, fill=TYRE)
    # Body: wedge with a raised nose.
    dark = tuple(int(c * 0.78) for c in body)
    poly(d, [(-96, 22), (96, 22), (84, -6), (-84, -6)], dark, cx, cy, s)
    poly(d, [(-84, -6), (84, -6), (62, -30), (-62, -30)], body, cx, cy, s)
    poly(d, [(-70, 22), (70, 22), (58, 44), (-58, 44)], tuple(int(c * 0.62) for c in body), cx, cy, s)
    # Racing stripe and number plate.
    poly(d, [(-14, -30), (14, -30), (18, -6), (-18, -6)], WHITE, cx, cy, s)
    poly(d, [(-14, -6), (14, -6), (16, 22), (-16, 22)], WHITE, cx, cy, s)
    d.rounded_rectangle((cx - 30 * s, cy + 24 * s, cx + 30 * s, cy + 40 * s), radius=4 * s, fill=accent)
    # Cockpit and driver.
    d.rounded_rectangle((cx - 40 * s, cy - 58 * s, cx + 40 * s, cy - 28 * s), radius=10 * s, fill=NAVY_DARK)
    circle(d, cx, cy - 74 * s, 26 * s, WHITE)
    d.chord((cx - 26 * s, cy - 100 * s, cx + 26 * s, cy - 48 * s), 200, 340, fill=accent)
    d.rounded_rectangle((cx - 20 * s, cy - 80 * s, cx + 20 * s, cy - 66 * s), radius=6 * s, fill=NAVY_DARK)
    d.rounded_rectangle((cx - 14 * s, cy - 78 * s, cx - 2 * s, cy - 72 * s), radius=3 * s, fill=(120, 220, 255))
    # Rocket pods on the sides.
    if pods:
        for sx in (-1, 1):
            x0 = cx + sx * 104 * s
            d.rounded_rectangle((x0 - 16 * s, cy - 40 * s, x0 + 16 * s, cy - 4 * s), radius=8 * s, fill=(60, 66, 86))
            for k in (-7, 7):
                circle(d, x0 + k * s, cy - 22 * s, 6 * s, (255, 90, 40))
                circle(d, x0 + k * s, cy - 22 * s, 3 * s, GOLD)
    # Front wheels.
    for wx in (-92, 92):
        d.rounded_rectangle((cx + (wx - 22) * s, cy + 8 * s, cx + (wx + 22) * s, cy + 66 * s), radius=12 * s, fill=TYRE)
        d.rounded_rectangle((cx + (wx - 10) * s, cy + 24 * s, cx + (wx + 10) * s, cy + 50 * s), radius=5 * s, fill=RIM)
    # Headlights.
    for hx in (-60, 60):
        circle(d, cx + hx * s, cy + 6 * s, 9 * s, (255, 246, 200))


def sparks(img, cx, cy, s, count=14, seed=3):
    import random
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(count):
        a = rnd.uniform(0, math.tau)
        r0 = rnd.uniform(130, 170)
        r1 = r0 + rnd.uniform(18, 40)
        col = rnd.choice([GOLD, ORANGE, PINK, TEAL])
        d.line((cx + math.cos(a) * r0 * s, cy + math.sin(a) * r0 * s * 0.8,
                cx + math.cos(a) * r1 * s, cy + math.sin(a) * r1 * s * 0.8), fill=col, width=max(int(5 * s), 1))


def burst(img, cx, cy, r, color, alpha=150):
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    circle(gd, cx, cy, r, color + (alpha,))
    glow = glow.filter(ImageFilter.GaussianBlur(r * 0.45))
    img.alpha_composite(glow)


def title(img, text, cx, cy, size, fill=WHITE, outline=NAVY_DARK, stroke=None):
    d = ImageDraw.Draw(img, "RGBA")
    f = font(size)
    stroke = stroke if stroke is not None else max(size // 10, 2)
    # Drop shadow.
    d.text((cx + size * 0.05, cy + size * 0.07), text, font=f, anchor="mm", fill=(0, 0, 0, 120),
           stroke_width=stroke, stroke_fill=(0, 0, 0, 120))
    d.text((cx, cy), text, font=f, anchor="mm", fill=fill, stroke_width=stroke, stroke_fill=outline)


# --- Outputs -----------------------------------------------------------------------

def icon(size, rounded=True, transparent_corners=True):
    """Square app icon (used for the project icon, web and the stores)."""
    W = size
    img = radial_bg(W, W, (52, 68, 130), NAVY_DARK, center=(0.5, 0.4), radius=1.0)
    s = W * SS / 300.0
    cx, cy = W * SS / 2, W * SS * 0.56
    burst(img, cx, cy - 20 * s, 120 * s, ORANGE, 120)
    sparks(img, cx, cy - 10 * s, s * 0.85)
    draw_kart(img, cx, cy, s * 0.95)
    if rounded:
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.size[0] - 1, img.size[1] - 1), radius=int(img.size[0] * 0.2), fill=255)
        bg = Image.new("RGBA", img.size, (0, 0, 0, 0) if transparent_corners else NAVY_DARK + (255,))
        bg.paste(img, (0, 0), mask)
        img = bg
    return finish(img, W, W)


def adaptive_foreground(size=432):
    """Android adaptive icon foreground: kart inside the 66% safe zone, transparent."""
    W = size
    img, _ = canvas(W, W)
    s = W * SS / 300.0 * 0.66
    draw_kart(img, W * SS / 2, W * SS * 0.54, s)
    return finish(img, W, W)


def adaptive_background(size=432):
    W = size
    img = radial_bg(W, W, (52, 68, 130), NAVY_DARK, center=(0.5, 0.42), radius=1.0)
    burst(img, W * SS / 2, W * SS * 0.5, W * SS * 0.25, ORANGE, 110)
    return finish(img, W, W)


def wide_art(w, h, with_tagline=True):
    """Splash / store banner: kart on the left, title on the right (or centred)."""
    img = radial_bg(w, h, (46, 60, 120), NAVY_DARK, center=(0.5, 0.45), radius=1.1)
    d = ImageDraw.Draw(img, "RGBA")
    W, H = w * SS, h * SS
    # Speed lines.
    for i in range(14):
        y = H * (0.18 + i * 0.05)
        x0 = W * (0.02 + (i * 37 % 11) * 0.02)
        d.line((x0, y, x0 + W * (0.12 + (i % 3) * 0.05), y), fill=(255, 255, 255, 28), width=int(6 * SS))
    s = H / 420.0
    kx, ky = W * 0.5, H * 0.62
    burst(img, kx, ky - 30 * s, 150 * s, ORANGE, 110)
    sparks(img, kx, ky - 20 * s, s, count=18)
    draw_kart(img, kx, ky, s)
    title(img, "KART  CLASH", W * 0.5, H * 0.18, int(H * 0.16), fill=WHITE, outline=ORANGE_DARK)
    if with_tagline:
        f = font(int(H * 0.045))
        d = ImageDraw.Draw(img, "RGBA")
        d.text((W * 0.5, H * 0.92), "Arena kart battles  -  solo, LAN and online", font=f, anchor="mm", fill=(200, 210, 240))
    return finish(img, w, h)


def save(img, rel):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", rel, img.size)


def main():
    save(icon(1024), "assets/icons/icon.png")
    save(icon(1024, rounded=False).convert("RGB"), "assets/icons/icon_ios_1024.png")  # iOS: no alpha, square
    save(icon(512, rounded=False).convert("RGB"), "docs/store/google_play_icon_512.png")
    save(adaptive_foreground(), "assets/icons/android_adaptive_foreground.png")
    save(adaptive_background().convert("RGB"), "assets/icons/android_adaptive_background.png")
    save(icon(192), "assets/icons/android_icon_192.png")
    save(wide_art(1920, 1080, with_tagline=False).convert("RGB"), "assets/splash/splash.png")
    save(wide_art(1024, 500).convert("RGB"), "docs/store/google_play_feature_1024x500.png")
    save(wide_art(1024, 1024).convert("RGB"), "docs/store/promo_square_1024.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
