"""Generates the iOS launch-screen image from the app's background photo.

The native launch screen is shown before Flutter draws anything, so it has
to look exactly like StartupScreen's first frame, otherwise the switch
between them flashes. StartupScreen draws assets/background.jpg at 30%
opacity (BoxFit.cover) over #0A0F0A; this pre-blends the same thing into
one image, which LaunchScreen.storyboard shows with aspect-fill (the native
equivalent of BoxFit.cover) over the same colour.

Re-run whenever assets/background.jpg or StartupScreen's colours change:
    python3 tool/generate_launch_image.py
"""

import json
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SOURCE = os.path.join(ROOT, "assets", "background.jpg")
IMAGESET = os.path.join(
    ROOT, "ios", "Runner", "Assets.xcassets", "LaunchImage.imageset"
)

SPLASH_COLOR = (0x0A, 0x0F, 0x0A)  # StartupScreen's Scaffold background
PHOTO_OPACITY = 0.3  # StartupScreen's Opacity around the photo
OUTPUT_SIZE = (1920, 1080)  # dimmed to 30%, full 4K resolution isn't visible


def main():
    photo = Image.open(SOURCE).convert("RGB")
    base = Image.new("RGB", photo.size, SPLASH_COLOR)
    # Image.blend and Flutter's Opacity both blend in sRGB, so this matches.
    launch = Image.blend(base, photo, PHOTO_OPACITY).resize(
        OUTPUT_SIZE, Image.LANCZOS
    )

    for name in os.listdir(IMAGESET):
        if name.endswith(".png"):
            os.remove(os.path.join(IMAGESET, name))
    launch.save(os.path.join(IMAGESET, "LaunchImage.png"), optimize=True)

    with open(os.path.join(IMAGESET, "Contents.json"), "w") as f:
        json.dump(
            {
                "images": [
                    {
                        "idiom": "universal",
                        "filename": "LaunchImage.png",
                        "scale": "1x",
                    }
                ],
                "info": {"version": 1, "author": "xcode"},
            },
            f,
            indent=2,
        )
        f.write("\n")
    print(f"wrote {IMAGESET}/LaunchImage.png {OUTPUT_SIZE}")


if __name__ == "__main__":
    main()
