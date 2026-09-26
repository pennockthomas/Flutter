"""Generates the 1024x1024 master app icon (a green leaf on the same
deep-eco-black/glow background as the splash screen).

Usage:
    python3 tool/generate_app_icon.py
    # then resize into ios/Runner/Assets.xcassets/AppIcon.appiconset/,
    # e.g. via `sips -z <px> <px> <file>` for each required size.

No image-generation tool was available when this was first written, so the
leaf is drawn from primitives: a vesica/lens (intersection of two offset
circles) for the body, plus a vein+stem line rotated 90 degrees from the
circles' axis so it crosses the leaf's pointed tips rather than running
along the circles themselves.
"""

from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math
import os

SIZE = 1024
BG = (10, 15, 10)          # 0A0F0A - deep eco-black, matches splash screen
GLOW = (24, 60, 45)        # subtle green glow layer
LEAF = (105, 240, 174)     # 69F0AE - Colors.greenAccent, matches splash icon
VEIN = (8, 58, 38)         # darker green for the vein/stem

img = Image.new('RGB', (SIZE, SIZE), BG)
cx, cy = SIZE // 2, SIZE // 2

# Soft radial glow behind the leaf, like the splash screen's box-shadow halo.
glow_mask = Image.new('L', (SIZE, SIZE), 0)
gd = ImageDraw.Draw(glow_mask)
gr = SIZE * 0.40
gd.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=255)
glow_mask = glow_mask.filter(ImageFilter.GaussianBlur(SIZE * 0.09))
glow_layer = Image.new('RGB', (SIZE, SIZE), GLOW)
img = Image.composite(glow_layer, img, glow_mask)

# Leaf: intersection of two circles (a vesica/lens) whose centers sit on a
# diagonal, so the leaf's long axis is naturally tilted like a real leaf.
angle = math.radians(40)  # tilt of the leaf's long axis from horizontal
half_span = SIZE * 0.20
r = SIZE * 0.40

ax = cx - half_span * math.cos(angle)
ay = cy - half_span * math.sin(angle)
bx = cx + half_span * math.cos(angle)
by = cy + half_span * math.sin(angle)

mask_a = Image.new('L', (SIZE, SIZE), 0)
mask_b = Image.new('L', (SIZE, SIZE), 0)
ImageDraw.Draw(mask_a).ellipse([ax - r, ay - r, ax + r, ay + r], fill=255)
ImageDraw.Draw(mask_b).ellipse([bx - r, by - r, bx + r, by + r], fill=255)
leaf_mask = ImageChops.multiply(mask_a, mask_b)

leaf_color = Image.new('RGB', (SIZE, SIZE), LEAF)
img.paste(leaf_color, (0, 0), leaf_mask)

# Vein across the leaf, plus a short stem past one end - both help it read
# as a leaf rather than an abstract lens. Rotated 90 degrees from the
# leaf's long (tip-to-tip) axis per feedback, so it now crosses the short
# axis instead of running tip-to-tip.
bbox = leaf_mask.getbbox()
x0, y0, x1, y1 = bbox
tip_a = (x1 - (x1 - x0) * 0.08, y1 - (y1 - y0) * 0.08)
tip_b = (x0 + (x1 - x0) * 0.08, y0 + (y1 - y0) * 0.08)


def rotate_point(px, py, ox, oy, angle_rad):
    dx, dy = px - ox, py - oy
    cos_a, sin_a = math.cos(angle_rad), math.sin(angle_rad)
    return (ox + dx * cos_a - dy * sin_a, oy + dx * sin_a + dy * cos_a)


angle_90 = math.radians(90)
tip_a = rotate_point(tip_a[0], tip_a[1], cx, cy, angle_90)
tip_b = rotate_point(tip_b[0], tip_b[1], cx, cy, angle_90)

draw = ImageDraw.Draw(img)
vein_width = max(4, int(SIZE * 0.013))
draw.line([tip_a, tip_b], fill=VEIN, width=vein_width)

stem_len = SIZE * 0.07
dx, dy = tip_a[0] - tip_b[0], tip_a[1] - tip_b[1]
length = math.hypot(dx, dy)
stem_end = (tip_a[0] + dx / length * stem_len, tip_a[1] + dy / length * stem_len)
draw.line([tip_a, stem_end], fill=VEIN, width=vein_width)

out = os.path.join(os.path.dirname(__file__), 'app_icon_master.png')
img.save(out)
print(f"Saved {out}")
