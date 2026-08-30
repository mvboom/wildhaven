# `assets/placeholder/` — grey-box primitives, authored in-repo

**Everything in this directory was authored in this repository from Godot primitives
(`BoxMesh` + `StandardMaterial3D`). There is no third-party source, no import, no
licence, and nothing to attribute.**

That is the entire reason this directory exists as its own top-level asset category
rather than living under `animals/`, `terrain/`, `buildings/`, or `props/`. Those four
categories hold *imported* assets, every one of which carries an entry in
`project/attribution/sources/*.tres`. A hand-made grey-box filed alongside them would
read to an asset audit as an import with a missing attribution record — an
unattributed-third-party-asset finding, which is the most expensive kind of false
positive this project can generate. Keeping the primitives in a category of their own
makes "no source" a structural fact instead of a claim.

**These are placeholders, not art.** Every colour, size and proportion in here is a
PLACEHOLDER at a stated baseline, flagged in each scene's own header comment and listed
in the build report's Proposals. They exist so the simulation systems (Tier 1 rows 3, 4
and 5) can be built and validated against real data entries without waiting on the art
pass. Slab dimensions track `project/scripts/grid_manager.gd`'s `TILE_SIZE`,
`TILE_HEIGHT` and `TILE_GAP`; the tree proportions are copied from the same file's
`_add_tree()`.

**Convention:** each scene's origin sits at the tile's **top surface** (ground level), so
a slab hangs below `y = 0` and anything standing on the tile is placed at `y >= 0`. This
matches how `grid_manager.gd` positions its tile bodies.

**Retirement:** each of these is replaced one-for-one by the imported asset for the same
item as the art pass lands (see `game-design/content-pipeline-status.md` →
`project_location`). Replacing one means repointing a single `model_scene` field in the
matching `project/data/**/*.tres`; nothing else references them.
