#!/usr/bin/env python3
"""
Generate the AutoSignDisplay Apple TV app icon assets.

Design derives from Princeton's campus wayfinding signage (reference photographs
in examples/, which is gitignored):

  - Charcoal matte bodies, not pure black.
  - Light grey dimensional lettering, suggested here as blank nameplates: real
    text is illegible at icon size.
  - Princeton orange used sparingly. On the physical blade signs it appears on
    the end cap, which is exactly where it lands here.
  - Fluted dark poles with a collar bracket at each blade.
  - Crisp prism geometry — a front face plus one side face, no curves.

Projection is axonometric rather than perspective: depth is a constant offset for
every face, so nothing converges and the shapes stay readable when the icon is
scaled to the home-screen size.

The depth direction is up and to the LEFT, which matters. Only the left end face
and the top face are visible under that offset; the right end is always occluded
by the body. So the flat orange cap has to sit on a blade's left end, and the
arrow therefore points right. Blades fan across different angles to read as
pointing different ways — mirroring one to point left would put its cap on the
hidden side and lose the orange entirely.

Run:
    python3 scripts/generate-icon.py [--preview]

`--preview` also writes flattened composites to /tmp for review.
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

# Palette sampled from the signage photographs.
SKY_TOP = (238, 235, 230)      # warm daylight stone, like campus paving
SKY_BOTTOM = (206, 200, 192)
BODY_FRONT = (46, 46, 49)      # charcoal blade face
BODY_TOP = (68, 68, 73)        # same body catching light from above
BODY_EDGE = (94, 94, 100)      # thin highlight along a lit edge
NAMEPLATE = (198, 198, 203)    # dimensional lettering grey
PRINCETON_ORANGE = (231, 117, 0)
ORANGE_SHADE = (188, 92, 0)    # the cap's own shaded edge
POLE_FRONT = (34, 34, 38)
POLE_FLUTE = (58, 58, 64)
SHADOW_RGBA = (60, 55, 50, 90)

SS = 4  # supersample factor


# ---------- primitives ----------

def make_gradient(size, top_rgb, bottom_rgb):
    """Vertical linear gradient, opaque."""
    w, h = size
    img = Image.new("RGBA", size)
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        draw.line(
            [(0, y), (w, y)],
            fill=(
                int(top_rgb[0] * (1 - t) + bottom_rgb[0] * t),
                int(top_rgb[1] * (1 - t) + bottom_rgb[1] * t),
                int(top_rgb[2] * (1 - t) + bottom_rgb[2] * t),
                255,
            ),
        )
    return img


def draw_pole(canvas, w, h, depth):
    """Charcoal pole, right of centre, drawn before the blades so they read as
    mounted in front of it.

    No fluting lines: at icon size they vanish into noise, and the reference
    reads as a plain dark post from any distance.
    """
    d = ImageDraw.Draw(canvas)
    cx = int(w * 0.50)
    half = int(w * 0.021)
    top = int(h * 0.100)
    bottom = int(h * 0.905)
    dx, dy = depth

    # Left side face, visible because the depth axis runs up-left.
    d.polygon([(cx - half, top), (cx - half + dx, top + dy),
               (cx - half + dx, bottom + dy), (cx - half, bottom)],
              fill=BODY_TOP)
    # Cap the top so the post ends as a solid rather than an open extrusion.
    d.polygon([(cx - half, top), (cx + half, top),
               (cx + half + dx, top + dy), (cx - half + dx, top + dy)],
              fill=BODY_TOP)
    d.rectangle([cx - half, top, cx + half, bottom], fill=POLE_FRONT)

    # Plinth, as on the pylon bases in the photographs. Anchors the composition.
    plinth_h = int(h * 0.055)
    grow = int(w * 0.010)
    d.polygon([(cx - half - grow, bottom - plinth_h),
               (cx - half - grow + dx, bottom - plinth_h + dy),
               (cx - half - grow + dx, bottom + dy),
               (cx - half - grow, bottom)],
              fill=BODY_TOP)
    d.rectangle([cx - half - grow, bottom - plinth_h,
                 cx + half + grow, bottom],
                fill=POLE_FLUTE)
    return cx, half


def rotate_points(points, degrees, origin):
    """Rotate screen-space points about `origin`. Positive angles tip clockwise,
    since y grows downward."""
    angle = math.radians(degrees)
    ca, sa = math.cos(angle), math.sin(angle)
    ox, oy = origin
    return [
        (ox + (x - ox) * ca - (y - oy) * sa,
         oy + (x - ox) * sa + (y - oy) * ca)
        for x, y in points
    ]


def offset(points, depth):
    dx, dy = depth
    return [(x + dx, y + dy) for x, y in points]


def draw_blade(canvas, center, half_len, half_height, degrees, depth):
    """One double-ended blade, crossed by the post at its midpoint.

    Flat end on the left, carrying the orange cap; arrow point on the right. The
    body is a pentagon, so the arrow is part of the silhouette rather than an
    applied decoration.
    """
    d = ImageDraw.Draw(canvas)
    cx, cy = center
    arrow = int(half_height * 1.7)

    front = rotate_points([
        (cx - half_len, cy - half_height),
        (cx + half_len - arrow, cy - half_height),
        (cx + half_len, cy),
        (cx + half_len - arrow, cy + half_height),
        (cx - half_len, cy + half_height),
    ], degrees, center)

    # Upper silhouette: flat top run, then the arrow's leading bevel.
    upper = [front[0], front[1], front[2]]
    d.polygon(upper + list(reversed(offset(upper, depth))), fill=BODY_TOP)

    # Flat end cap — the orange, on the visible side.
    cap = [front[0], front[4]]
    d.polygon([cap[0]] + offset(cap, depth) + [cap[1]], fill=PRINCETON_ORANGE)

    # Front face last, covering the seams where the other faces meet it.
    d.polygon(front, fill=BODY_FRONT)
    d.line([front[0], front[1]], fill=BODY_EDGE, width=max(1, SS // 2))
    d.line([front[1], front[2]], fill=BODY_EDGE, width=max(1, SS // 2))

    draw_lettering(d, center, half_len, half_height, arrow, degrees)


def draw_lettering(d, center, half_len, half_height, arrow, degrees):
    """Word shapes standing in for the dimensional lettering.

    Drawn as rotated quads rather than rounded rectangles: Pillow cannot rotate a
    rounded rectangle, and at icon size the corner radius is invisible anyway.
    """
    cx, cy = center
    left = cx - half_len + int(half_len * 0.22)
    right = cx + half_len - arrow - int(half_len * 0.14)
    if right <= left:
        return

    bar_h = max(2, int(half_height * 0.52))
    gap = max(2, int((right - left) * 0.09))
    weights = (0.38, 0.22)
    total = sum(weights)
    available = (right - left) - gap * (len(weights) - 1)

    x = left
    for weight in weights:
        segment = int(available * (weight / total))
        quad = [(x, cy - bar_h // 2), (x + segment, cy - bar_h // 2),
                (x + segment, cy + bar_h // 2), (x, cy + bar_h // 2)]
        d.polygon(rotate_points(quad, degrees, center), fill=NAMEPLATE)
        x += segment + gap


# ---------- composition ----------

def blade_layout(w, h):
    """Blades crossed by the post at their midpoints, tilted slightly apart.

    Two proportions are load-bearing:

    - Length to height. The physical blades are roughly 5:1; a first pass at 12:1
      read as a comb. Shortening the blades is the way to keep that ratio — thinning
      them instead brings the comb back and mushes the lettering at dock size.
    - Tilt. Enough to read as askew, little enough that the blades clear one another.
      At 13 degrees the fan collided on the left, where the upward-tilted blade's low
      end meets the next blade's high end, and the overlap buried the post.
    """
    cx = int(w * 0.50)
    half_height = int(h * 0.065)
    return [
        {"center": (cx, int(h * 0.25)), "half_len": int(w * 0.260), "degrees": -6.5},
        {"center": (cx, int(h * 0.50)), "half_len": int(w * 0.285), "degrees": 2.0},
        {"center": (cx, int(h * 0.75)), "half_len": int(w * 0.240), "degrees": 6.5},
    ], half_height


def render_layers(size):
    """Return (back, middle, front) RGBA at `size`, drawn supersampled.

    Split for the tvOS parallax effect: sky behind, pole in the middle, blades in
    front, so the signage lifts off the background when the icon is focused.
    """
    w, h = size
    sw, sh = w * SS, h * SS
    depth = (-int(sw * 0.030), -int(sh * 0.045))

    back_ss = make_gradient((sw, sh), SKY_TOP, SKY_BOTTOM)

    middle_ss = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw_pole(middle_ss, sw, sh, depth)

    front_ss = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    blades, half_height = blade_layout(sw, sh)
    for blade in blades:
        draw_blade(front_ss, blade["center"], blade["half_len"],
                   half_height, blade["degrees"], depth)

    resample = Image.LANCZOS
    return (back_ss.resize(size, resample),
            middle_ss.resize(size, resample),
            front_ss.resize(size, resample))


def render_flat(size, icon_aspect=None):
    """Single flattened image. `icon_aspect` centres the artwork in a wider
    canvas, for the Top Shelf sizes."""
    w, h = size
    if icon_aspect is None:
        back, middle, front = render_layers(size)
        out = back.copy()
        out.alpha_composite(middle)
        out.alpha_composite(front)
        return out

    canvas = make_gradient(size, SKY_TOP, SKY_BOTTOM)
    art_w = int(h * icon_aspect)
    _, middle, front = render_layers((art_w, h))
    x = (w - art_w) // 2
    canvas.alpha_composite(middle, (x, 0))
    canvas.alpha_composite(front, (x, 0))
    return canvas


# ---------- manifests / IO ----------

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
    imageset = stack_dir / f"{layer_name}.imagestacklayer" / "Content.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    image.save(imageset / "Content.png", "PNG")
    (imageset / "Contents.json").write_text(json.dumps(MANIFEST_TV_1X, indent=2) + "\n")


def write_layered_icon(stack_dir, size):
    back, middle, front = render_layers(size)
    write_layer(stack_dir, "Back", back)
    write_layer(stack_dir, "Middle", middle)
    write_layer(stack_dir, "Front", front)


def write_top_shelf(imageset_dir, base_size, name_1x, name_2x, manifest):
    imageset_dir.mkdir(parents=True, exist_ok=True)
    aspect = HOME_ICON[0] / HOME_ICON[1]
    render_flat(base_size, aspect).save(imageset_dir / name_1x, "PNG")
    render_flat((base_size[0] * 2, base_size[1] * 2), aspect).save(imageset_dir / name_2x, "PNG")
    (imageset_dir / "Contents.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true",
                    help="Also write flattened preview PNGs to /tmp for review")
    args = ap.parse_args()

    print("Rendering home-screen layered icon (400x240)…")
    write_layered_icon(BRAND / "App Icon.imagestack", HOME_ICON)

    print("Rendering App Store layered icon (1280x768)…")
    write_layered_icon(BRAND / "App Icon - App Store.imagestack", STORE_ICON)

    print("Rendering Top Shelf (1920x720 + @2x)…")
    write_top_shelf(BRAND / "Top Shelf Image.imageset", TOP_SHELF,
                    "TopShelf.png", "TopShelf@2x.png", TOP_SHELF_MANIFEST)

    print("Rendering Top Shelf Wide (2320x720 + @2x)…")
    write_top_shelf(BRAND / "Top Shelf Image Wide.imageset", TOP_SHELF_WIDE,
                    "TopShelfWide.png", "TopShelfWide@2x.png", TOP_SHELF_WIDE_MANIFEST)

    if args.preview:
        for label, size in (("home", HOME_ICON), ("store", STORE_ICON)):
            path = Path(f"/tmp/autosigndisplay_icon_{label}.png")
            render_flat(size).save(path)
            print(f"Preview: {path}")

    print("Done.")


if __name__ == "__main__":
    main()
