#!/usr/bin/env python3
"""Regenerate the scatter in project/assets/terrain/wild_grass/WildGrass.tscn.

WHY THIS FILE EXISTS. WildGrass.tscn's header has always said "re-run the generator to
change anything below; do not hand-edit the MultiMesh buffer" — but that generator was a
one-off headless script that was never committed. This is that script, made real and
re-runnable, so the instruction in the scene header is now true.

WHAT IT FIXES (2026-09-08 human report: "looks very repetitive since it only has a small
amount of grass in the middle of the tile"). The 2026-08-16 density pass added a 4-clump
override on top of the shared grass-family scatter, and that override constrained the clump
centres so tightly that every one of the 32 blades landed inside +/-0.28 of tile centre —
the middle ~56% of the tile. Measured against the rest of the family:

    GrassCommonShort  36 blades  +/-0.418
    GrassClover       26 blades  +/-0.414
    Meadow            24 blades  +/-0.413
    Snowfield         26 blades  +/-0.414
    Scrub             16 blades  +/-0.399
    WildGrass         32 blades  +/-0.279   <- the only tile that misses the edge

Every wild-grass tile was therefore a green blob ringed by bare slab, with nothing at all
over the seams, so the tile boundary read as a hard grid. The three bare-dirt floor patches
made it worse: all three sat in the SAME quadrant (x -0.06..-0.19, z -0.07..-0.18), putting
an identical dark smudge in the identical corner of every tile in the world.

WHAT IT PRESERVES. Everything the human has already ruled on:
  * 32 blades, scale baseline 0.065 with +/-18% jitter, free Y rotation (2026-08-16).
  * CLUMPED, not evenly scattered — 4 uneven clumps with real bare ground between them.
    An even scatter would read as a mown lawn, which is the opposite of "untouched", and
    the distinction from true Grass is this tile's whole job.
  * Uneven clump sizes 10/6/10/6, as the 2026-08-16 rebuild set them.
  * ONE variant (-> D-56). This changes the single scene's contents; it adds nothing to
    `model_scenes`, so `_supports_mixed()` stays false and the four assertions that pin
    the variant count are untouched.
  * Slab tint, patch tint, patch sizes, slab geometry — all read from the scene, never
    rewritten.

WHAT IT CHANGES. Only the scatter LAYOUT:
  * Clump centres are now placed one per tile quadrant with jitter, so clumps land near
    edges and corners instead of huddling at centre. Blades reach the +/-0.42 envelope the
    rest of the grass family already uses, so growth crosses the seams and the tile
    boundary stops being visible as a line of bare slab.
  * The 3 bare-dirt patches are spread across the tile with a minimum separation instead
    of stacking in one corner.

Run:  python3 scripts/generate_wild_grass_scatter.py
"""

from __future__ import annotations

import math
import random
import re
import struct
from pathlib import Path

SCENE = Path(__file__).resolve().parent.parent / "project/assets/terrain/wild_grass/WildGrass.tscn"

# The 2026-08-16 density/height settlement. Not ours to re-tune.
SEED = 20260816

# DENSITY RAISED 2026-09-08 (human report, second pass: "it still does not look random when
# multiple tiles are next to each other ... there just aren't enough tufts of grass"). This
# supersedes the 2026-08-16 count of 32, which that day's own feedback had itself raised from 4
# ("more instances (30+)") — the same complaint, one step further along.
#
# DENSITY IS THE ACTUAL ANTI-REPETITION LEVER HERE, which is why the count moved rather than
# the layout moving again. Wild grass is ONE scene stamped on every tile (-> D-56), so its
# content is a lattice by construction and no amount of relaying the scatter changes that; what
# changes is whether the eye can RESOLVE the repeating unit. At 32 sparse tufts every tile is a
# readable little arrangement you can match against its neighbour. At this count the tufts read
# as continuous ground cover and the unit stops being legible. Adding variants is the other
# way out of a lattice and D-56 closed it, so density is the lever that is left.
BLADE_COUNT = 96

# Eight uneven clumps rather than four, for the same reason: four clump blobs per tile is
# itself a shape you can recognise repeating. Sizes stay deliberately uneven — equal clumps
# read as planted rows.
CLUMP_SIZES = [18, 8, 14, 10, 16, 8, 12, 10]
SCALE_BASELINE = 0.065
SCALE_JITTER = 0.18                 # +/-18%

# The shared grass-family envelope (GrassCommonShort et al. measure +/-0.418). Bringing
# WildGrass into line with it IS the fix; do not shrink this back toward centre.
SCATTER_LIMIT = 0.42

# Clump centres are placed on a jittered RING rather than one per quadrant. The radius floor
# is the real fix: because wild grass is a single scene repeated on every tile (-> D-56), any
# band of the tile that is systematically bare becomes a CONTINUOUS bare line across the whole
# world — which is the grid-of-dots read itself. Pushing all four clumps outward guarantees
# growth near all four edges, so the seams are covered.
#
# THE RING IS WHY THIS IS NOT A 2x2 QUADRANT GRID, which is what it was first written as. A
# quadrant layout puts the gaps between clumps on the two axes, leaving an axis-aligned bare
# cross through the tile centre — and a bare cross repeated on every tile is just the same
# lattice again, shifted half a tile. Angular jitter of +/-40 degrees around each of four
# evenly spaced spokes, plus a random base rotation, keeps the four uneven clumps and the real
# bare ground between them while making sure no bare gap runs straight along an axis.
# Clump centres are rejection-sampled across the WHOLE tile with a minimum separation, not
# placed on a ring or a 2x2 grid. Both of those were tried and both fail the same way: they put
# the bare gaps in a fixed geometric relationship to the tile (a quadrant grid leaves an
# axis-aligned bare cross through the centre; a ring leaves a bare middle), and a fixed bare
# shape repeated on every tile is just the lattice again in another guise. Free placement with
# a separation floor keeps the clumps apart without giving the gaps between them a shape.
CLUMP_CENTRE_LIMIT = 0.40
CLUMP_MIN_SEPARATION = 0.20
BLADE_SPREAD = 0.09                 # gaussian sigma of a blade around its clump centre

# THE SEAM BAND IS WHAT THIS TILE IS ACTUALLY JUDGED ON. `SCATTER_LIMIT` keeps every blade
# 0.08 from the tile edge, so two abutting tiles always leave a bare strip of 2 * 0.08 = 0.16
# centred on their shared seam. That floor is inherent to the family envelope and is what
# Grass, Meadow, Scrub and Snowfield all already live with. Wild grass did NOT: at its old
# +/-0.279 reach the strip was 0.44 — nearly half a tile of bare slab around every tile, which
# is the "repetitive, grass only in the middle" report. Getting to the 0.16 floor is the fix.
SEAM_BAND_FLOOR = 2.0 * (0.5 - SCATTER_LIMIT)
SEAM_BAND_TOLERANCE = 0.01

# The layout is CHOSEN, not just drawn: draw many candidates from the one seeded stream, keep
# only those that reach the seam floor, and among those take the one whose clumpiness is
# closest to TARGET_CLUMPINESS. Deterministic — same seed, same stream, same winner.
#
# THE TARGET IS A BAND, NOT A MINIMUM, AND THAT IS A CORRECTION. This first selected the MOST
# clumped passing candidate, on the reasoning that clumping is the documented "untouched"
# character that separates this tile from true Grass. That optimises for precisely the wrong
# thing once you remember there is only one scene (-> D-56): a tight clump is a distinctive
# BLOB SHAPE, a distinctive shape is a landmark, and a landmark stamped on every tile is what
# the eye matches tile-to-tile. Maximising clumpiness was therefore maximising the legibility
# of the repeat — the human's own report ("the grass is repetitive too") is what surfaced it.
#
# So aim just below uniform instead: enough irregularity that it never reads as a mown lawn,
# not so much that any tuft group becomes a recognisable feature. 1.0 is uniform; lower is
# clumpier. Raising this toward 1.0 hides the tiling better and reads flatter; lowering it
# reads wilder and repeats more visibly.
TARGET_CLUMPINESS = 0.92
LAYOUT_CANDIDATES = 300

# BARE-DIRT PATCH CONTRAST — the single loudest source of the repeat, per the human's
# 2026-09-08 screenshot. Numbers alone had pointed at the grass scatter; the frame showed the
# patches are what actually draws the grid. They are flat, hard-edged, axis-aligned quads in a
# dark brown (0.42, 0.34, 0.2) sitting on an olive slab (0.55, 0.52, 0.3) — a contrast step big
# enough that the eye latches onto them and reads their positions as a lattice, while the tufts
# are close enough to the slab in hue to register as mere noise beside them. Because wild grass
# is one scene per tile (-> D-56) every tile carries the SAME three stamps in the same places,
# so the higher their contrast the more legible the tiling.
#
# The fix is contrast, not removal: the patches still earn their place as "untended, patchy
# ground", they just must not out-shout the grass. This blends them most of the way back to the
# slab, leaving a soft mottle instead of a stamp. It is a look value, so it is a dial — raise
# BLEND toward 1.0 for the old hard brown, lower it for a subtler tile.
SLAB_COLOUR = (0.55, 0.52, 0.30)
PATCH_COLOUR_FULL = (0.42, 0.34, 0.20)
PATCH_CONTRAST_BLEND = 0.35

PATCH_COUNT = 3
PATCH_CENTRE_LIMIT = 0.30           # keeps a rotated patch's corners inside the slab
PATCH_MIN_SEPARATION = 0.28         # stops the three from re-stacking in one quadrant


def f32(value: float) -> float:
    """Round-trip through float32 so what we print is what Godot will actually store."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def fmt(value: float) -> str:
    value = f32(value)
    if value == 0.0:
        return "0"
    return f"{value:.8g}"


def _seam_band(values: list[float]) -> float:
    """Width of the bare strip straddling the seam when this tile is repeated."""
    ordered = sorted(values)
    return (ordered[0] + 0.5) + (0.5 - ordered[-1])


def _clumpiness(points: list[tuple[float, float]]) -> float:
    """Mean nearest-neighbour distance over what a uniform scatter would give. <1 is clumped."""
    total = 0.0
    for i, (x, z) in enumerate(points):
        total += min(
            math.hypot(x - ox, z - oz) for j, (ox, oz) in enumerate(points) if j != i
        )
    uniform = 0.5 * math.sqrt((2.0 * SCATTER_LIMIT) ** 2 / len(points))
    return (total / len(points)) / uniform


def _candidate(rng: random.Random) -> list[tuple[float, float, float, float]]:
    """One clumped candidate layout: (x, z, uniform_scale, y_rotation) per blade."""
    centres: list[tuple[float, float]] = []
    attempts = 0
    while len(centres) < len(CLUMP_SIZES) and attempts < 500:
        attempts += 1
        cx = rng.uniform(-CLUMP_CENTRE_LIMIT, CLUMP_CENTRE_LIMIT)
        cz = rng.uniform(-CLUMP_CENTRE_LIMIT, CLUMP_CENTRE_LIMIT)
        if any(math.hypot(cx - ox, cz - oz) < CLUMP_MIN_SEPARATION for ox, oz in centres):
            continue
        centres.append((cx, cz))
    if len(centres) < len(CLUMP_SIZES):
        return []

    blades: list[tuple[float, float, float, float]] = []
    for size, (cx, cz) in zip(CLUMP_SIZES, centres):
        for _ in range(size):
            x = max(-SCATTER_LIMIT, min(SCATTER_LIMIT, cx + rng.gauss(0.0, BLADE_SPREAD)))
            z = max(-SCATTER_LIMIT, min(SCATTER_LIMIT, cz + rng.gauss(0.0, BLADE_SPREAD)))
            scale = SCALE_BASELINE * (1.0 + rng.uniform(-SCALE_JITTER, SCALE_JITTER))
            blades.append((x, z, scale, rng.uniform(0.0, math.tau)))

    assert len(blades) == BLADE_COUNT, f"clump sizes must sum to {BLADE_COUNT}"
    return blades


def blade_transforms(rng: random.Random) -> list[tuple[float, float, float, float]]:
    """The seam-covering candidate whose clumpiness sits closest to TARGET_CLUMPINESS."""
    best: list[tuple[float, float, float, float]] | None = None
    best_score = float("inf")
    for _ in range(LAYOUT_CANDIDATES):
        blades = _candidate(rng)
        if not blades:
            continue
        limit = SEAM_BAND_FLOOR + SEAM_BAND_TOLERANCE
        if _seam_band([b[0] for b in blades]) > limit:
            continue
        if _seam_band([b[1] for b in blades]) > limit:
            continue
        score = abs(_clumpiness([(b[0], b[1]) for b in blades]) - TARGET_CLUMPINESS)
        if score < best_score:
            best, best_score = blades, score
    if best is None:
        raise SystemExit("no candidate layout reached the seam-coverage floor")
    return best


def buffer_literal(blades: list[tuple[float, float, float, float]]) -> str:
    """MultiMesh transform_format=1 packs each instance as the 3x4 matrix, row-major."""
    floats: list[str] = []
    for x, z, s, theta in blades:
        c, sn = math.cos(theta) * s, math.sin(theta) * s
        floats += [fmt(c), "0", fmt(sn), fmt(x)]     # row 0: xx yx zx ox
        floats += ["0", fmt(s), "0", "0"]            # row 1: xy yy zy oy
        floats += [fmt(-sn), "0", fmt(c), fmt(z)]    # row 2: xz yz zz oz
    return ", ".join(floats)


def patch_placements(rng: random.Random) -> list[tuple[float, float, float]]:
    """(x, z, y_rotation) per bare-dirt patch, spread rather than stacked."""
    placed: list[tuple[float, float, float]] = []
    while len(placed) < PATCH_COUNT:
        x = rng.uniform(-PATCH_CENTRE_LIMIT, PATCH_CENTRE_LIMIT)
        z = rng.uniform(-PATCH_CENTRE_LIMIT, PATCH_CENTRE_LIMIT)
        if any(math.hypot(x - px, z - pz) < PATCH_MIN_SEPARATION for px, pz, _ in placed):
            continue
        placed.append((x, z, rng.uniform(0.0, math.tau)))
    return placed


def fmt_colour(value: float) -> str:
    """Godot writes colour components short (`0.42`), not at float32 precision (`0.41999999`).

    `fmt()` is right for the transform buffers and WRONG here: it round-trips through float32
    and prints 8 significant digits, so building a match string with it produced
    `Color(0.41999999, ...)`, which matches nothing in the scene, and the tint rewrite silently
    did nothing while still reporting success. Hence the assert at the call site.
    """
    return f"{value:.6g}"


def patch_colour() -> tuple[float, float, float]:
    return tuple(
        slab + PATCH_CONTRAST_BLEND * (full - slab)
        for slab, full in zip(SLAB_COLOUR, PATCH_COLOUR_FULL)
    )


def patch_transform(x: float, z: float, theta: float) -> str:
    c, s = math.cos(theta), math.sin(theta)
    parts = [fmt(c), "0", fmt(-s), "0", "1", "0", fmt(s), "0", fmt(c), fmt(x), "0.001", fmt(z)]
    return "Transform3D(" + ", ".join(parts) + ")"


def main() -> int:
    source = SCENE.read_text()
    rng = random.Random(SEED)

    blades = blade_transforms(rng)
    updated, n = re.subn(
        r"(buffer = PackedFloat32Array\()[^)]*(\))",
        lambda m: m.group(1) + buffer_literal(blades) + m.group(2),
        source,
        count=1,
    )
    if n != 1:
        raise SystemExit("could not find the MultiMesh buffer in WildGrass.tscn")

    # `instance_count` is the authority on how many of the buffer's transforms Godot actually
    # draws — a buffer longer than the count is silently truncated, so writing one without the
    # other renders a fraction of the blades and looks exactly like the sparseness this script
    # exists to fix. Rewrite them together, always.
    updated, n = re.subn(
        r"(instance_count = )\d+", rf"\g<1>{len(blades)}", updated, count=1
    )
    if n != 1:
        raise SystemExit("could not find the MultiMesh instance_count in WildGrass.tscn")

    # Every patch material carries the same tint; they are separate sub-resources only because
    # each patch is its own MeshInstance3D. Rewrite all of them, and leave the slab's own
    # albedo alone — it is matched by value and skipped.
    def colour_literal(rgb: tuple[float, float, float]) -> str:
        return "albedo_color = Color(%s, %s, %s, 1)" % tuple(fmt_colour(c) for c in rgb)

    slab_literal = colour_literal(SLAB_COLOUR)
    tint_literal = colour_literal(patch_colour())
    rewritten = 0

    def _tint(match: re.Match[str]) -> str:
        nonlocal rewritten
        if match.group(0) == slab_literal:
            return match.group(0)
        rewritten += 1
        return tint_literal

    updated = re.sub(r"albedo_color = Color\([^)]*\)", _tint, updated)
    if rewritten != PATCH_COUNT:
        raise SystemExit(f"expected to retint {PATCH_COUNT} patch materials, retinted {rewritten}")

    for index, (x, z, theta) in enumerate(patch_placements(rng)):
        pattern = rf'(\[node name="FloorPatch_{index}"[^\]]*\]\ntransform = )Transform3D\([^)]*\)'
        updated, n = re.subn(pattern, lambda m: m.group(1) + patch_transform(x, z, theta), updated, count=1)
        if n != 1:
            raise SystemExit(f"could not find FloorPatch_{index}'s transform in WildGrass.tscn")

    SCENE.write_text(updated)

    reach = max(max(abs(b[0]), abs(b[1])) for b in blades)
    seam_x = _seam_band([b[0] for b in blades])
    seam_z = _seam_band([b[1] for b in blades])
    print(
        f"{SCENE.name}: {len(blades)} blades, reach +/-{reach:.3f}, "
        f"seam band {seam_x:.3f}/{seam_z:.3f} (floor {SEAM_BAND_FLOOR:.3f}), "
        f"clumpiness {_clumpiness([(b[0], b[1]) for b in blades]):.2f} (1.0 = uniform), "
        f"{PATCH_COUNT} patches spread"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
