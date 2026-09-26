"""Generates the 1024x1024 master app icon: the same eco_rounded Material
icon used on the splash screen, rendered directly from Flutter's own
bundled MaterialIcons font, on the splash screen's deep-eco-black
background with its green glow.

Usage:
    python3 tool/generate_app_icon.py
    # then resize into ios/Runner/Assets.xcassets/AppIcon.appiconset/,
    # e.g. via `sips -z <px> <px> <file>` for each required size.

An earlier version of this hand-drew a leaf shape from circle
intersections, but that read as a coffee bean rather than a leaf.
Rendering the actual Icons.eco_rounded glyph (codepoint 0xf6f2 in
MaterialIcons-Regular.otf - see packages/flutter/lib/src/material/icons.dart
in the Flutter SDK) guarantees it matches the in-app icon exactly.
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import glob
import os

SIZE = 1024
BG = (10, 15, 10)        # 0A0F0A - deep eco-black, matches splash screen
GLOW = (24, 60, 45)      # subtle green glow layer, matches splash's box-shadow halo
ICON_COLOR = (105, 240, 174)  # 69F0AE - Colors.greenAccent, matches splash icon

ECO_ROUNDED_CODEPOINT = 0xF6F2  # Icons.eco_rounded
VERTICAL_SHIFT = 0.05  # fraction of SIZE to nudge the glyph down by

FLUTTER_ROOT = os.environ.get("FLUTTER_ROOT", os.path.expanduser("~/Applications/flutter"))
FONT_CANDIDATES = glob.glob(
    os.path.join(FLUTTER_ROOT, "bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf")
)
if not FONT_CANDIDATES:
    raise SystemExit(
        "Couldn't find MaterialIcons-Regular.otf under $FLUTTER_ROOT/bin/cache/artifacts/material_fonts/. "
        "Set FLUTTER_ROOT or point FONT_CANDIDATES at your Flutter SDK."
    )
FONT_PATH = FONT_CANDIDATES[0]

img = Image.new('RGB', (SIZE, SIZE), BG)
cx, cy = SIZE // 2, SIZE // 2

# Soft radial glow behind the icon, like the splash screen's box-shadow halo.
glow_mask = Image.new('L', (SIZE, SIZE), 0)
gd = ImageDraw.Draw(glow_mask)
gr = SIZE * 0.40
gd.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=255)
glow_mask = glow_mask.filter(ImageFilter.GaussianBlur(SIZE * 0.09))
glow_layer = Image.new('RGB', (SIZE, SIZE), GLOW)
img = Image.composite(glow_layer, img, glow_mask)

# The eco_rounded glyph itself, straight from Flutter's own icon font.
# Icon fonts' em-square metrics rarely match their glyph's visual bounds,
# so draw it once to measure the actual ink, then re-draw shifted so that
# ink - not the font's baseline/ascent box - is centered on the canvas.
font = ImageFont.truetype(FONT_PATH, size=int(SIZE * 0.62))
glyph = chr(ECO_ROUNDED_CODEPOINT)
probe = ImageDraw.Draw(Image.new('RGB', (SIZE, SIZE)))
left, top, right, bottom = probe.textbbox((cx, cy), glyph, font=font, anchor="mm")
glyph_cx, glyph_cy = (left + right) / 2, (top + bottom) / 2
draw = ImageDraw.Draw(img)
draw.text(
    (cx + (cx - glyph_cx), cy + (cy - glyph_cy) + SIZE * VERTICAL_SHIFT),
    glyph,
    font=font,
    fill=ICON_COLOR,
    anchor="mm",
)

out = os.path.join(os.path.dirname(__file__), 'app_icon_master.png')
img.save(out)
print(f"Saved {out}")
