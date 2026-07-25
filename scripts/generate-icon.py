#!/usr/bin/env python3
"""
Generate the AutoSignDisplay Apple TV app icon assets.

Design: a wooden signpost with three directional signs radiating outward
(fork-in-the-road iconography), in front of a soft blue sky gradient.
Produces parallax layers (Back / Middle / Front) for the home-screen and
App Store icons, both Top Shelf images, and writes the Contents.json
manifests Xcode consumes.

Run:
    python3 scripts/generate-icon.py [--preview]

`--preview` also writes flattened composite previews to /tmp so the
result can be eyeballed before shipping.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parent.parent
BRAND = REPO_ROOT / "AutoSignDisplay/Assets.xcassets/App Icon & Top Shelf Image.brandassets"

# tvOS visible layer sizes (per Apple HIG)
HOME_ICON = (400, 240)
STORE_ICON = (1280, 768)
TOP_SHELF = (1920, 720)
TOP_SHELF_WIDE = (2320, 720)

# Palette
SKY_TOP = (25, 47, 89)
SKY_BOT = (74, 129, 183)
POST_LIGHT = (150, 100, 60)
POST_MID = (110, 72, 40)
POST_DARK = (68, 45, 25)
POST_TOP_CAP = (60, 40, 22)
LEFT_SIGN = (232, 93, 59)      # warm red-orange
RIGHT_SIGN = (59, 174, 93)     # fresh green
DIAG_SIGN = (245, 200, 66)     # sunny yellow
OUTLINE = (28, 20, 15)
SIGN_HIGHLIGHT = (255, 255, 255, 60)
SHADOW_RGBA = (0, 0, 0, 110)

# Supersample factor for antialiasing
SS = 4


# ---------- primitives ----------

def make_gradient(size, top_rgb, bot_rgb):
    """Vertical linear gradient (opaque RGBA)."""
    w, h = size
    img = Image.new("RGBA", size)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(top_rgb[0] * (1 - t) + bot_rgb[0] * t)
        g = int(top_rgb[1] * (1 - t) + bot_rgb[1] * t)
        b = int(top_rgb[2] * (1 - t) + bot_rgb[2] * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))
    return img


def make_arrow_sign(size, color, outline_w):
    """Right-pointing pentagon on a transparent canvas.
    Flat edge on the left (attaches to post), tip on the right.
    """
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    body_end = int(w * 0.72)
    tip_x = w - 1
    pts = [
        (0, 0),
        (body_end, 0),
        (tip_x, h // 2),
        (body_end, h - 1),
        (0, h - 1),
    ]
    d.polygon(pts, fill=color, outline=OUTLINE, width=outline_w)
    # Subtle top highlight
    d.line([(int(w * 0.05), int(h * 0.20)),
            (body_end - int(w * 0.05), int(h * 0.20))],
           fill=SIGN_HIGHLIGHT, width=max(2, outline_w // 2))
    return img


def paste_with_shadow(canvas, layer, position, blur_radius, offset=(0, 0)):
    """Paste `layer` onto `canvas` with a soft drop shadow."""
    x, y = position
    # Shadow: alpha of layer tinted black, blurred
    alpha = layer.split()[-1]
    shadow = Image.new("RGBA", layer.size, SHADOW_RGBA)
    shadow.putalpha(alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur_radius))
    canvas.alpha_composite(shadow, (x + offset[0], y + offset[1]))
    canvas.alpha_composite(layer, (x, y))


# ---------- composition ----------

def draw_post(canvas):
    """Signpost onto a transparent RGBA canvas."""
    w, h = canvas.size
    d = ImageDraw.Draw(canvas)
    post_w = int(w * 0.05)
    center_x = w // 2
    post_top = int(h * 0.15)
    post_bot = int(h * 0.92)
    outline_w = max(2, SS)

    # Main post face
    d.rectangle(
        [center_x - post_w // 2, post_top, center_x + post_w // 2, post_bot],
        fill=POST_MID, outline=OUTLINE, width=outline_w,
    )
    # Left highlight strip (light)
    hl_w = max(2, post_w // 4)
    d.rectangle(
        [center_x - post_w // 2 + outline_w // 2, post_top + outline_w // 2,
         center_x - post_w // 2 + hl_w, post_bot - outline_w // 2],
        fill=POST_LIGHT,
    )
    # Right shadow strip (dark)
    d.rectangle(
        [center_x + post_w // 2 - hl_w, post_top + outline_w // 2,
         center_x + post_w // 2 - outline_w // 2, post_bot - outline_w // 2],
        fill=POST_DARK,
    )
    # Cap on top
    cap_h = int(h * 0.02)
    cap_overhang = post_w // 3
    d.rectangle(
        [center_x - post_w // 2 - cap_overhang, post_top - cap_h,
         center_x + post_w // 2 + cap_overhang, post_top + cap_h // 2],
        fill=POST_TOP_CAP, outline=OUTLINE, width=outline_w,
    )
    # Base ground (a small mound / dirt)
    base_h = int(h * 0.05)
    base_w = int(post_w * 4.5)
    d.ellipse(
        [center_x - base_w // 2, post_bot - base_h,
         center_x + base_w // 2, post_bot + base_h],
        fill=POST_DARK, outline=OUTLINE, width=outline_w,
    )


def draw_signs(canvas):
    """Three directional signs onto a transparent RGBA canvas."""
    w, h = canvas.size
    center_x = w // 2
    outline_w = max(2, SS)

    # Sign geometry
    sign_w = int(w * 0.38)   # horizontal length of a sign (body + tip)
    sign_h = int(h * 0.16)   # vertical height
    post_w_half = int(w * 0.025)

    # Top sign — pointing up-and-to-the-right (diagonal, yellow)
    top_y_center = int(h * 0.24)
    diag = make_arrow_sign((sign_w, sign_h), DIAG_SIGN, outline_w)
    rotated = diag.rotate(20, resample=Image.BICUBIC, expand=True)
    rw, rh = rotated.size
    # anchor: near center_x + a bit right so the flat edge overlaps the post
    tx = center_x - int(sign_w * 0.15)
    ty = top_y_center - rh // 2
    paste_with_shadow(canvas, rotated, (tx, ty), blur_radius=SS * 3,
                      offset=(SS * 2, SS * 3))

    # Middle sign — pointing LEFT (red)
    mid_y_center = int(h * 0.50)
    left = make_arrow_sign((sign_w, sign_h), LEFT_SIGN, outline_w)
    left = left.transpose(Image.FLIP_LEFT_RIGHT)
    lx = center_x - sign_w + post_w_half
    ly = mid_y_center - sign_h // 2
    paste_with_shadow(canvas, left, (lx, ly), blur_radius=SS * 3,
                      offset=(SS * 2, SS * 3))

    # Bottom sign — pointing RIGHT (green)
    bot_y_center = int(h * 0.73)
    right = make_arrow_sign((sign_w, sign_h), RIGHT_SIGN, outline_w)
    rx = center_x - post_w_half
    ry = bot_y_center - sign_h // 2
    paste_with_shadow(canvas, right, (rx, ry), blur_radius=SS * 3,
                      offset=(SS * 2, SS * 3))


def compose_layers(size):
    """Return (back, middle, front) RGBA at `size`, drawn supersampled."""
    w, h = size
    sw, sh = w * SS, h * SS

    back_ss = make_gradient((sw, sh), SKY_TOP, SKY_BOT)
    middle_ss = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw_post(middle_ss)
    front_ss = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw_signs(front_ss)

    back = back_ss.resize(size, Image.LANCZOS)
    middle = middle_ss.resize(size, Image.LANCZOS)
    front = front_ss.resize(size, Image.LANCZOS)
    return back, middle, front


def compose_top_shelf(size):
    """Flat (non-layered) top shelf image at `size`."""
    w, h = size
    sw, sh = w * SS, h * SS
    canvas = make_gradient((sw, sh), SKY_TOP, SKY_BOT)
    # Draw signpost + signs onto a 5:3 sub-region centered horizontally
    icon_w = int(sh * 5 / 3)      # match icon aspect
    icon_h = sh
    icon_layer = Image.new("RGBA", (icon_w, icon_h), (0, 0, 0, 0))
    draw_post(icon_layer)
    draw_signs(icon_layer)
    x = (sw - icon_w) // 2
    canvas.alpha_composite(icon_layer, (x, 0))
    return canvas.resize(size, Image.LANCZOS)


# ---------- manifest / IO ----------

MANIFEST_TV_1X = {
    "images": [{"filename": "Content.png", "idiom": "tv", "scale": "1x"}],
    "info": {"author": "xcode", "version": 1},
}

TOP_SHELF_MANIFEST = {
    "images": [
        {"filename": "TopShelf.png", "idiom": "tv", "scale": "1x"},
        {"filename": "TopShelf@2x.png", "idiom": "tv", "scale": "2x"},
    ],
    "info": {"author": "xcode", "version": 1},
}

TOP_SHELF_WIDE_MANIFEST = {
    "images": [
        {"filename": "TopShelfWide.png", "idiom": "tv", "scale": "1x"},
        {"filename": "TopShelfWide@2x.png", "idiom": "tv", "scale": "2x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def write_layer(stack_dir, layer_name, image):
    """Drop Content.png into <stack>/<layer>.imagestacklayer/Content.imageset/."""
    imageset = stack_dir / f"{layer_name}.imagestacklayer" / "Content.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    image.save(imageset / "Content.png", "PNG")
    (imageset / "Contents.json").write_text(json.dumps(MANIFEST_TV_1X, indent=2) + "\n")


def write_layered_icon(stack_dir, size):
    back, middle, front = compose_layers(size)
    write_layer(stack_dir, "Back", back)
    write_layer(stack_dir, "Middle", middle)
    write_layer(stack_dir, "Front", front)


def write_top_shelf(imageset_dir, base_size, filename_1x, filename_2x, manifest):
    imageset_dir.mkdir(parents=True, exist_ok=True)
    img1 = compose_top_shelf(base_size)
    img2 = compose_top_shelf((base_size[0] * 2, base_size[1] * 2))
    img1.save(imageset_dir / filename_1x, "PNG")
    img2.save(imageset_dir / filename_2x, "PNG")
    (imageset_dir / "Contents.json").write_text(json.dumps(manifest, indent=2) + "\n")


def flatten(size):
    """Composite Back+Middle+Front into a single opaque preview."""
    back, middle, front = compose_layers(size)
    out = back.copy()
    out.alpha_composite(middle)
    out.alpha_composite(front)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true",
                    help="Also write flattened preview PNGs to /tmp for review")
    args = ap.parse_args()

    home_stack = BRAND / "App Icon.imagestack"
    store_stack = BRAND / "App Icon - App Store.imagestack"
    top_shelf = BRAND / "Top Shelf Image.imageset"
    top_shelf_wide = BRAND / "Top Shelf Image Wide.imageset"

    print("Rendering home-screen layered icon (400×240)…")
    write_layered_icon(home_stack, HOME_ICON)

    print("Rendering App Store layered icon (1280×768)…")
    write_layered_icon(store_stack, STORE_ICON)

    print("Rendering Top Shelf (1920×720 + @2x)…")
    write_top_shelf(top_shelf, TOP_SHELF,
                    "TopShelf.png", "TopShelf@2x.png", TOP_SHELF_MANIFEST)

    print("Rendering Top Shelf Wide (2320×720 + @2x)…")
    write_top_shelf(top_shelf_wide, TOP_SHELF_WIDE,
                    "TopShelfWide.png", "TopShelfWide@2x.png",
                    TOP_SHELF_WIDE_MANIFEST)

    if args.preview:
        home_preview = Path("/tmp/autosigndisplay_icon_home.png")
        store_preview = Path("/tmp/autosigndisplay_icon_store.png")
        flatten(HOME_ICON).save(home_preview)
        flatten(STORE_ICON).save(store_preview)
        print(f"Preview: {home_preview}")
        print(f"Preview: {store_preview}")

    print("Done.")


if __name__ == "__main__":
    main()
