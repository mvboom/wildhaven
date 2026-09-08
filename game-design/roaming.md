# Roaming — terrain-aware wander

Owns how a resident chooses **where** it may walk. The motion itself (waypoint cadence,
pathing, separation, animation) stays `ResidentRoamer`'s and is not restated here.

Status: built 2026-09-08. Tier 1 row 6's "Roam quality" depth bucket
(`spec.md` line 182), so this is a scoped purchase, not new scope.

---

## 1. What this buys

Today every resident wanders a uniform 3-tile disc around its home and terrain is invisible
to it — a rabbit is as happy standing in a rock field as in a meadow, and painting a wide
beautiful meadow next door changes nothing about where anyone goes.

The goal is two things the player can feel:

1. **Animals keep to terrain that suits them.** A fox belongs at the forest edge, not in the
   middle of a cultivated field.
2. **Painting more of a species' terrain visibly widens where it roams.** The reward for
   terraforming is that the world's animals spread into what you made. This is the half that
   matters — it turns terraforming into something animals answer.
3. **A region-equipped roamer ranges further than before, full stop.** `WANDER_RADIUS_TILES`
   (3 tiles) stops being the binding radius; a resident with a usable region instead ranges up
   to `min(effective_capacity_radius, site.radius)` — 8 tiles for twelve of the fifteen shipped
   species, 10 for deer, 12 for fox and stag. That is a 3–4× widening of both visible roam
   range and walk-leg length over the old uniform 3-tile disc, independent of terrain quality.
   Approved by the human during design (§6's constants table).

Neither of the first two is a new mechanic the player must learn. Both are the existing world
reacting. The third is a direct, intended consequence of buying the first two: roaming a wider
neighbourhood is what lets an animal answer terrain painted more than 3 tiles from its home at
all.

---

## 2. What exists today

`ResidentRoamer._pick_waypoint()` draws a point from a disc of `min(WANDER_RADIUS_TILES,
site.radius)` around the home, clamped only to the world's edge. There is no terrain test
anywhere in the roaming path.

The data needed to add one is already built and already maintained:

| Piece | Where | Note |
|---|---|---|
| Per-tile habitat tags, as a cached bitmask | `WorldGrid.tile_tag_mask(x, z)` | Refreshed incrementally by every tile writer |
| Tag array → mask | `WorldGrid.tags_mask(tags)` | Static |
| A species' wanted tags | `AnimalDefinition.habitat_needs` | Authored per `.tres` |
| Neighbourhood radius | `AnimalDefinition.effective_capacity_radius()` | 8–12 across the shipped roster |
| Whether a tile can be walked | `WorldNavigation._tile_blocked()` | Private today; see §5 |

So the expensive part — resolving what a tile emits — is done. The predicate is one AND.

---

## 3. Decisions

Ruled by the human, 2026-09-08. **Each still needs a `D-NN` entry in `decisions.md`;
numbering is the human's to allocate.**

**3.1 A liked tile is one emitting ANY tag in `habitat_needs` (OR, not AND).**
`habitat_needs` is an AND *scored over a radius* by `CapacityEvaluator`, and no terrain
emits more than two tags, so a per-tile AND yields **zero** tiles for 7 of the 15 species.
OR is the only reading that both works per-tile and derives from data already authored —
which means it can never drift from the roster the way a parallel hand-authored field would.

**3.2 The region is liked tiles PLUS tiles orthogonally adjacent to a liked tile.**
The fox needs `forest` alone and `forest.tres` sets `blocks_movement = true`, so without
this the fox — and only the fox — has an empty region. Adjacency makes it pad the forest
fringe, which is both what a real fox does and what reads better on screen than an animal
inside the trees. As one universal rule it needs no fox special case, and every species
gains a soft border instead of a hard stencil. Orthogonal (4-neighbour) only: adjacency
through a diagonal corner reads as a gap, not a border.

**3.3 The region is a connected fill from the home, capped at the capacity radius.**
The fill crosses only qualifying tiles, so the region is contiguous and every point in it is
reachable — pathing stays short, and a patch of liked terrain cut off by water or buildings
is correctly ignored rather than sending an animal on a long detour to reach it.

**3.4 Rebuild is lazy, driven by a version stamp.**
Zero cost during a paint drag, which matters because `paint_tile()` already spends 2.8 ms
per tile. Animals notice new terrain within one wander cycle (2–6 s), which reads as them
wandering over to look rather than as a hard snap.

---

## 4. Mechanism

### 4.1 The unit

A new `project/scripts/world/roam_region.gd` — `class_name RoamRegion extends RefCounted`.

`ResidentRoamer` is already 460+ dense lines carrying wander, avoids, separation, pathing
and animation. Terrain awareness is a sixth responsibility and gets its own class instead.
`RoamRegion` owns exactly one question — *which world points may this resident walk to* —
and exposes essentially one method, `pick_point()` (§4.5). It needs no roamer, no
AnimationPlayer and no scene to test.

### 4.2 The predicate

A tile joins the region when **both** hold:

- **liked** — `(grid.tile_tag_mask(x, z) & needs_mask) != 0`, or that holds for any of its
  four orthogonal neighbours (§3.2); where `needs_mask = WorldGrid.tags_mask(species.habitat_needs)`
- **walkable** — `WorldNavigation.is_tile_walkable(grid, x, z)`

### 4.3 The fill

Breadth-first from the home tile, crossing only qualifying tiles, bounded by

```
radius = min(species.effective_capacity_radius(), site.radius)
```

The `site.radius` term is not currently binding — every shipped species has
`capacity_radius = 0`, so `effective_capacity_radius() == scout_radius <= site.radius` — but
it makes containment within the home neighbourhood structural rather than a property of
today's data, and keeps `test_resident_wander.gd`'s existing containment assertion true by
construction.

**The home tile is seeded unconditionally**, walkable or not: a den tile carries a
navigation reservation and a House tile is occupied, so a resident must always be permitted
to stand on its own home.

### 4.4 Invalidation

`WorldGrid` gains a monotonic `terrain_version: int`, bumped in `_refresh_tag_mask()` —
whose own comment already reads *"called by every writer that changes what a tile holds"*,
making it the one seam no writer can bypass. `RoamRegion` records the version it built at
and rebuilds when the two differ.

**Terrain is not the whole predicate, though (§4.2): walkability is the other half, and it has
its own seam.** A den reservation (`WorldNavigation.set_den_tile_blocked()`, used when a
resident moves in) changes what `is_tile_walkable()` returns without touching
`WorldGrid.terrain_version` at all — deliberately: a den reservation is not a terrain edit, and
`set_den_tile_blocked()` only calls `mark_dirty()`, the navmesh's own staleness flag. So
`RoamRegion` also records `WorldNavigation.rebuilds_run` — the same exact-work counter the
navmesh coalescing already exposes — and rebuilds when EITHER it or `terrain_version` has moved.
Two staleness inputs, not one; each an integer compare, so the steady-state cost is still
nothing and invalidation is still structural rather than a promise anyone has to remember to
keep — it is just two compares now, not one.

### 4.5 Picking a point, and how avoids survive

`pick_point(rng, away_from: Array[Vector3]) -> Vector3` draws a tile uniformly from the
region, then offsets uniformly within that tile, so residents do not line up on tile centres.

**This has to carry row 9's avoids biasing (D-29), which today lives in `_pick_angle()`.**
That mechanism biases the *angle* drawn from the disc — with waypoints now drawn from a tile
list, an angle is no longer what is being chosen, so the behaviour has to be re-expressed or
it is silently lost.

It is re-expressed as rejection sampling: draw up to `AVOID_BIAS_SAMPLES` candidate tiles and
keep the first whose direction from home falls inside `AVOID_BIAS_HALF_ARC_RADIANS` of the
away-from-threats direction; if none does, keep the last drawn. This preserves D-29's two
load-bearing properties exactly — only *which* point within the already-bounded area is
chosen changes, and the region is never widened — while costing nothing when `away_from` is
empty, which is the common case. `away_from` is supplied by the existing
`_nearby_avoid_provider`, still called once per wander cycle and never per frame.

### 4.6 Fallback

`ResidentRoamer._init()` gains a trailing `roam_region: RoamRegion = null`. When it is null,
**or the region holds fewer than `MIN_REGION_TILES`**, `_pick_waypoint()` uses today's
uniform disc unchanged.

This is the same degradation idiom the file already uses for `world_navigation` ("a roamer
with no navigation degrades to the pre-navigation straight-line behavior rather than
erroring"). It keeps every existing caller and test working untouched, and it stops a
species whose terrain has been painted away from collapsing into a stationary animal.

---

## 5. Files

| File | Change |
|---|---|
| `project/scripts/world/roam_region.gd` | **New.** The predicate, the fill, the version stamp, `pick_point()` |
| `project/scripts/world/world_grid.gd` | `terrain_version: int`, bumped in `_refresh_tag_mask()` |
| `project/scripts/world/world_navigation.gd` | New public `is_tile_walkable(grid, x, z)` wrapping the existing private `_tile_blocked()` — one source of truth, so a waypoint can never land where `find_path()` refuses to go |
| `project/scripts/world/resident_roamer.gd` | Optional trailing `roam_region`; `_pick_waypoint()` delegates or falls back |
| `project/scripts/world/resident_presentation.gd` | Constructs the region — it already resolves the species and holds the grid |
| `project/tests/test_roam_region.gd` | **New.** See §8 |
| `project/tests/test_terrain_version.gd` | **New.** Pins `WorldGrid.terrain_version`'s bump contract in isolation — every writer that changes what a tile holds, and no-op writes don't move it |
| `project/tests/test_tile_walkable.gd` | **New.** Pins `WorldNavigation.is_tile_walkable()` against every `_tile_blocked()` cause (occupied, den reservation, `blocks_movement`) plus out-of-bounds and a null grid |

---

## 6. Constants — the human's

Per `.claude/CLAUDE.md`, agents propose with sources and the human decides. Both are new;
**no GDD or `spec.md` number exists for either.**

| Constant | Proposed | Reasoning |
|---|---|---|
| `RoamRegion.AVOID_BIAS_SAMPLES` | 8 | Candidate tiles drawn before giving up on the away-from-threats cone (§4.5). Enough that a cone covering half the region is almost always hit, small enough to stay free. |
| `RoamRegion.MIN_REGION_TILES` | 6 | The fox measured 3 tiles on a randomly-mixed probe grid (§7, Table A) — an animal that small is effectively stationary. 6 gives a resident somewhere to actually go before the disc fallback takes over. Still comfortably below Table B's contiguous fox figures (1 tile embedded, 25 tiles on the fringe): a fox with no usable region genuinely has nowhere better to go than the disc fallback. |
| `ResidentRoamer.WANDER_RADIUS_TILES` | 3.0, unchanged | Stops being the binding constant for a region-equipped roamer and survives only as the fallback disc's radius. |

---

## 7. Measured cost

`RoamRegion.rebuild()` visits every tile it *tests* — up to five `tile_tag_mask` reads plus one
`is_tile_walkable` per tile — whether or not that tile ends up qualifying, so build cost tracks
region size (and its boundary), not the other way around: **a larger region is a slower
build**, never a faster one.

**Table A — uniformly-random terrain (the original measurement).** One `RoamRegion` build,
128×128 grid, every tile independently assigned one of the nine terrains at random, measured
headless 2026-09-08:

| Species | `habitat_needs` | Radius | Build | Region |
|---|---|---|---|---|
| rabbit | `open_grass` | 8 | 0.17 ms | 42 tiles |
| deer | `open_grass, forest` | 10 | 0.32 ms | 81 tiles |
| stag | `forest, rocks` | 12 | 0.32 ms | 85 tiles |
| fox | `forest` | 12 | 0.02 ms | 3 tiles |

A uniform random mix scatters each terrain into small, disconnected specks, so the connected
fill (§3.3) runs out of qualifying neighbours almost immediately. **This is the shape that
minimises the fill's own cost, not a representative one** — real player-painted terrain is
laid down in contiguous patches (a meadow, a quarry, a forest), and a contiguous patch of liked
terrain is exactly what does NOT run out of neighbours. Table A therefore *understates* both
build cost and region size for terrain as it is actually painted in play, in some cases by an
order of magnitude. It is kept here as a data point, not as the figure that matters.

**Table B — contiguous terrain (the figure that matters).** One `RoamRegion` build per species,
grid large enough to hold the whole capacity-radius disc, measured headless 2026-09-08. Rabbit
and deer: the full radius disc painted `grass` (`open_grass`). Stag: the full radius disc
painted `rock` (`rocks` — one of its two OR'd needs, and walkable, unlike `forest`). Fox: a
large contiguous `forest` block with home on the walkable fringe tile just outside it — the
"belongs at the forest edge" scenario §3.2 is written for, run contiguous instead of random:

| Species | Paint | Radius | Build | Region | Bytes (tiles × 8) |
|---|---|---|---|---|---|
| rabbit | full-disc `grass` | 8 | 0.51 ms | 197 tiles | 1,576 B |
| deer | full-disc `grass` | 10 | 0.78 ms | 317 tiles | 2,536 B |
| stag | full-disc `rock` | 12 | 1.12 ms | 441 tiles | 3,528 B |
| fox | forest-edge fringe | 12 | 0.21 ms | 25 tiles | 200 B |

Stag is the honest worst case among the shipped roster: ~1.1 ms and ~450 tiles at radius 12,
roughly the area of the full radius-12 disc (π·12² ≈ 452) — a completely rock-covered
neighbourhood is walkable and liked everywhere, so almost nothing is excluded. Grid size does
not materially affect any of this: the fill is bounded by `radius`, not by world size, so a
128×128 grid and the smaller grid actually used here cost the same.

Fox is the interesting exception, and worth stating plainly. Table B's fox row places home on
the fringe, just outside the trees — the scenario §3.2 is written for. A second run of the same
probe placing home several tiles INSIDE a solid forest patch instead (still contiguous, still
`forest`, nothing else changed) measured a region of **one tile** at 0.01 ms: home only, forced
in by §4.3's unconditional seed. Because `forest` is the fox's only need tag and Forest blocks
movement, the connected fill cannot cross the blocked interior to reach any walkable ground,
even though such ground exists just past the trees. Painting more forest around a fox that is
already inside it does not widen its region; it can only shrink it further. The fox's growth
story is about the *edge* being reachable and lengthening, not about the interior being
roamable — consistent with §3.2's own reasoning for why the fox needs the adjacency rule at all.

**Steady state is still zero** — no version moves, so nothing rebuilds; this holds regardless of
which table applies.

**During an active paint drag**, each `RoamRegion` rebuilds at most once per wander cycle
(§3.4), not once per edit — a burst of edits between two wander cycles still costs one rebuild,
the same coalescing the navmesh already does. A wander cycle is `PAUSE_MIN/MAX_SECONDS`
(2–6 s, mean 4 s = 240 frames at 60 fps), so at the full `ROAMER_BUDGET` of 256 residents, on
average `256 / 240 ≈ 1.1` roamers complete a cycle — and therefore pay a rebuild, if the world
changed since their last one — on any given frame. At Table B's worst per-rebuild cost (stag,
1.12 ms), that is **≈1.2 ms/frame added during an active drag**, alongside the 2.4 ms the
navmesh rebuild already spends per painted tile: **≈3.6 ms of a 16.7 ms frame budget (~22%),
comfortably inside it**, with headroom for the rest of a frame's normal work. This is worse
than the previous (random-grid-derived) ~0.34 ms/frame estimate by roughly 3–4×, which is the
direct consequence of Table A having understated region size.

**Memory is per-region, not a flat per-roamer figure**, and scales with the same contiguity
Table B measures: 200 B (fox, forest-edge) to 3,528 B (stag, full rock disc) per roamer holding
a region, against Table A's un-corrected "under 700 bytes" claim. At `ROAMER_BUDGET` = 256, a
population entirely of Table B's worst case (stag, 3,528 B each) is 256 × 3,528 B ≈ 882 KB; a
roster-mixed population is well under that.

---

## 8. Testing

`test_roam_region.gd`, new:

- the predicate in its three states — liked, adjacent-to-liked, neither
- a blocked tile is excluded even when liked
- every region tile is within `min(effective_capacity_radius, site.radius)` of home
- the region is contiguous
- the home tile is present even when blocked
- a version bump rebuilds; no bump does not
- **the growth property, stated as the player feels it**: paint liked terrain adjacent to an
  existing region, assert the region grows to include it
- **a den reservation invalidates the region on its own**, with no `WorldGrid.terrain_version`
  bump and nobody calling `rebuild()` explicitly — `WorldNavigation.set_den_tile_blocked()` on a
  tile already in the region removes it, proving §4.4's second staleness input actually works
- a null `WorldNavigation` degrades to "everything is walkable" — pinned so a future change to
  that fallback fails a test rather than surfacing as an animal wandering into trees
- **a region-equipped roamer never picks a waypoint outside its region** (this lives in
  `test_roam_region.gd`, not `test_resident_wander.gd` — see below)

`test_resident_wander.gd` was **not** extended for this row — despite an earlier draft of this
doc claiming it was. The equivalent coverage instead landed as
`test_roam_region.gd::_check_roamer_uses_the_region()`, which builds a real
`RoamRegion`-equipped `ResidentRoamer` and asserts every waypoint it picks lands inside the
region. `test_resident_wander.gd`'s own assertions are genuinely untouched: every roamer it
builds passes no region and therefore still takes the disc path.

---

## 9. Out of scope

- **Personality bias.** Shy animals hanging back and Bold ones approaching stays unbuilt.
- **Flocking**, and any group-level movement.
- **Changing `blocks_movement` on forest.** Considered and rejected (§3.2); the fox uses the
  fringe instead.
- **Sharing one region between residents of the same home.** Measured cost does not justify
  the shared-lifetime complexity; each roamer holds its own.
- **Relocation.** Row 10 already frees and rebuilds presentation on a move, so a relocated
  resident gets a fresh region with no work here.
