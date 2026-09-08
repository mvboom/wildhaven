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

Neither is a new mechanic the player must learn. Both are the existing world reacting.

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
and rebuilds inside `pick_point()` when the two differ. Missed invalidation is structurally
impossible: it is an integer compare, not bookkeeping.

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

---

## 6. Constants — the human's

Per `.claude/CLAUDE.md`, agents propose with sources and the human decides. Both are new;
**no GDD or `spec.md` number exists for either.**

| Constant | Proposed | Reasoning |
|---|---|---|
| `RoamRegion.AVOID_BIAS_SAMPLES` | 8 | Candidate tiles drawn before giving up on the away-from-threats cone (§4.5). Enough that a cone covering half the region is almost always hit, small enough to stay free. |
| `RoamRegion.MIN_REGION_TILES` | 6 | The fox measured 3 tiles on a randomly-mixed probe grid (§7) — an animal that small is effectively stationary. 6 gives a resident somewhere to actually go before the disc fallback takes over. |
| `ResidentRoamer.WANDER_RADIUS_TILES` | 3.0, unchanged | Stops being the binding constant for a region-equipped roamer and survives only as the fallback disc's radius. |

---

## 7. Measured cost

One `RoamRegion` build, 128×128 grid, measured headless 2026-09-08 with the algorithm above:

| Species | `habitat_needs` | Radius | Build | Region |
|---|---|---|---|---|
| rabbit | `open_grass` | 8 | 0.17 ms | 42 tiles |
| deer | `open_grass, forest` | 10 | 0.32 ms | 81 tiles |
| stag | `forest, rocks` | 12 | 0.32 ms | 85 tiles |
| fox | `forest` | 12 | 0.02 ms | 3 tiles |

**Steady state is zero** — the version does not move, so nothing rebuilds. During an active
paint drag every roamer rebuilds once per wander cycle: ~0.34 ms/frame at the full
`ROAMER_BUDGET` of 256, against the 2.4 ms the navmesh rebuild already spends per painted
tile. Memory is under 700 bytes per roamer.

The measurement grid mixes all nine terrains uniformly at random, which is the *pessimal*
shape for a connected fill — real player-painted terrain is contiguous, so regions in play
should be larger and builds no slower.

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

`test_resident_wander.gd`, extended: a region-equipped roamer never picks a waypoint outside
its region. Its existing assertions are untouched — every roamer it builds passes no region
and therefore still takes the disc path.

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
