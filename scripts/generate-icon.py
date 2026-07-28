#!/usr/bin/env python3
"""
Generate the AutoSignDisplay Apple TV app icon assets.

Design derives from Princeton's campus wayfinding signage (reference photographs
in examples/, which is gitignored):

  - Charcoal matte bodies, not pure black.
  - Princeton orange used sparingly. On the physical blade signs it appears at the
    squared-off end, which is where the stripe lands here.
  - Dark poles, blades mounted across them.
  - Crisp geometry — straight edges, no curves.

The blades are flat: a charcoal pentagon and an orange stripe, nothing else. The
pole alone keeps its extrusion, offset up and to the left. That mix is deliberate,
and it also buys something: while the blades were extruded, only their left end
face was ever visible, so the orange stripe had to sit on the left and every arrow
was forced to point right. Flat blades have no hidden side, so a blade can be
mirrored to point the other way and keep its stripe. The middle one is.

The pole's extrusion is axonometric rather than perspective — depth is a constant
offset, so nothing converges and the shape survives being scaled down.

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
BODY_TOP = (68, 68, 73)        # the pole's side face, catching light from above
PRINCETON_ORANGE = (231, 117, 0)
POLE_FRONT = (34, 34, 38)
POLE_FLUTE = (58, 58, 64)

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


def draw_blade(canvas, center, half_len, half_height, degrees, flip=False):
    """One flat double-ended blade, crossed by the pole at its midpoint.

    Squared end carries an orange stripe; the far end is an arrow point. The arrow
    is part of the pentagon silhouette rather than an applied shape, so it holds up
    when the icon is scaled down. The face is otherwise bare.

    `flip` mirrors the blade about its own midpoint, swapping which end points. It
    is a plain sign flip on the local x coordinates: with no extrusion there is no
    hidden face to worry about, so a mirrored blade keeps its stripe.
    """
    d = ImageDraw.Draw(canvas)
    cx, cy = center
    arrow = int(half_height * 1.7)
    stripe = max(2, int(half_height * 0.42))
    s = -1 if flip else 1

    def place(local):
        return rotate_points([(cx + s * x, cy + y) for x, y in local], degrees, center)

    d.polygon(place([
        (-half_len, -half_height),
        (half_len - arrow, -half_height),
        (half_len, 0),
        (half_len - arrow, half_height),
        (-half_len, half_height),
    ]), fill=BODY_FRONT)

    # Stripe across the squared end, spanning the blade's full height. It reads as
    # vertical because it tilts with the blade, the way a painted end would.
    d.polygon(place([
        (-half_len, -half_height),
        (-half_len + stripe, -half_height),
        (-half_len + stripe, half_height),
        (-half_len, half_height),
    ]), fill=PRINCETON_ORANGE)


# ---------- composition ----------

def blade_layout(w, h):
    """Blades crossed by the pole at their midpoints, tilted slightly apart.

    The middle blade is mirrored, so the three point up-right, up-left, and
    down-right — three directions rather than one fanned out.

    Two proportions are load-bearing:

    - Length to height. The physical blades are roughly 5:1; a first pass at 12:1
      read as a comb. Shortening the blades is the way to keep that ratio; thinning
      them instead brings the comb back.
    - Tilt. Enough to read as askew, little enough that the blades clear one another.
      At 13 degrees the fan collided on the left, where the upward-tilted blade's low
      end meets the next blade's high end, and the overlap buried the pole.
    """
    cx = int(w * 0.50)
    half_height = int(h * 0.065)
    return [
        {"center": (cx, int(h * 0.25)), "half_len": int(w * 0.260), "degrees": -6.5},
        {"center": (cx, int(h * 0.50)), "half_len": int(w * 0.285), "degrees": 2.0,
         "flip": True},
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
                   half_height, blade["degrees"], blade.get("flip", False))

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


def write_layer(stack_dir, layer_name, renditions):
    """`renditions` is a list of (image, filename, scale)."""
    layer_dir = stack_dir / f"{layer_name}.imagestacklayer"
    imageset = layer_dir / "Content.imageset"
    imageset.mkdir(parents=True, exist_ok=True)

    # The layer itself carries no image — the artwork lives in Content.imageset below.
    # Written explicitly because Xcode's template left one layer holding an unassigned
    # slot ({"idiom": "tv"} with no filename) while its siblings had none, and that
    # drift outlived several regenerations.
    (layer_dir / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    for image, filename, _ in renditions:
        image.save(imageset / filename, "PNG")
    manifest = {
        "images": [
            {"filename": filename, "idiom": "tv", "scale": scale}
            for _, filename, scale in renditions
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (imageset / "Contents.json").write_text(json.dumps(manifest, indent=2) + "\n")


def write_layered_icon(stack_dir, size, include_2x=False):
    """Write the Back/Middle/Front layers of one imagestack.

    The home-screen icon needs both scales — Apple rejects the upload otherwise
    (ITMS-90709: "missing an image for the background layer with a scale value of
    '2'"), and it names only the first missing layer, so all three must be present.
    The App Store icon is single-scale; adding a 2x there is not expected.

    Rendered at each size rather than upscaled: the artwork is drawn from geometry
    and supersampled, so a native 800x480 pass is sharper than a resized 400x240.
    """
    scales = [(size, "Content.png", "1x")]
    if include_2x:
        scales.append(((size[0] * 2, size[1] * 2), "Content@2x.png", "2x"))

    rendered = {name: [] for name in ("Back", "Middle", "Front")}
    for render_size, filename, scale in scales:
        back, middle, front = render_layers(render_size)
        for name, image in (("Back", back), ("Middle", middle), ("Front", front)):
            rendered[name].append((image, filename, scale))

    for name, renditions in rendered.items():
        write_layer(stack_dir, name, renditions)


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

    print("Rendering home-screen layered icon (400x240 @1x, 800x480 @2x)…")
    write_layered_icon(BRAND / "App Icon.imagestack", HOME_ICON, include_2x=True)

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
