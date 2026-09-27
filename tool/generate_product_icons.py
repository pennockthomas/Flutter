"""Generates simple flat product illustrations for checklist items.

Each icon is drawn at a large size then downscaled for a clean, anti-aliased
edge, matching the flat / minimal style used elsewhere in the app.

Usage: python3 tool/generate_product_icons.py
Output: assets/products/<name>.png (transparent background, RGBA)
"""

from PIL import Image, ImageDraw
import os

SCALE = 4  # draw big, downsample for AA
SIZE = 240 * SCALE
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "products")


def _new_canvas():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def draw_metal_lunchbox():
    img = _new_canvas()
    d = ImageDraw.Draw(img)
    s = SCALE

    def pt(x, y):
        return (x * s, y * s)

    # ground shadow
    d.ellipse([pt(60, 208)[0], pt(60, 208)[1], pt(180, 224)[0], pt(180, 224)[1]],
              fill=(0, 0, 0, 20))

    # carry handle (rounded loop) — approximate with a thick arc via pieslice + rect
    handle_color = (107, 113, 120, 255)
    hw = 8 * s
    d.line([pt(58, 68), pt(58, 46)], fill=handle_color, width=hw)
    d.line([pt(182, 68), pt(182, 46)], fill=handle_color, width=hw)
    d.arc([pt(58, 10), pt(182, 82)], start=180, end=360, fill=handle_color, width=hw)
    # round the line caps
    for x, y in [(58, 68), (182, 68), (58, 10), (182, 10)]:
        r = hw / 2
        d.ellipse([x * s - r, y * s - r, x * s + r, y * s + r], fill=handle_color)

    # body
    body_color = (199, 205, 211, 255)
    outline = (138, 146, 155, 255)
    body_box = [pt(30, 68)[0], pt(30, 68)[1], pt(210, 218)[0], pt(210, 218)[1]]
    d.rounded_rectangle(body_box, radius=22 * s, fill=body_color, outline=outline, width=2 * s)

    # highlight strip
    highlight = (228, 232, 235, 180)
    d.rounded_rectangle(
        [pt(52, 78)[0], pt(52, 78)[1], pt(66, 208)[0], pt(66, 208)[1]],
        radius=7 * s,
        fill=highlight,
    )

    # lid seam
    d.line([pt(32, 108), pt(208, 108)], fill=outline, width=2 * s)

    # latch
    d.rounded_rectangle(
        [pt(105, 98)[0], pt(105, 98)[1], pt(135, 116)[0], pt(135, 116)[1]],
        radius=3 * s,
        fill=handle_color,
    )

    return img.resize((240, 240), Image.LANCZOS)


ICONS = {
    "metal_lunchbox": draw_metal_lunchbox,
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in ICONS.items():
        out_path = os.path.join(OUT_DIR, f"{name}.png")
        fn().save(out_path)
        print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
