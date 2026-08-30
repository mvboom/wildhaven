class_name MistBoundary
extends Node3D
## Tier 1 row 13 (Mist) — the VISUAL layer only. `WorldGrid`/`MistReveal`/`WorldRoot` already
## own the mechanical reveal (deterministic growth, the invisible collision boundary, the
## `grown`/`mist_revealed` signals) — see their own file headers. This node adds nothing to
## that contract: it only READS `WorldRoot`'s already-public, already-stable surface
## (`mist_revealed`, `grid_size()`, `grid_to_world()`), the exact way `GameUI`/`CameraRig`
## already do, and it never opens `world_grid.gd`, `mist_reveal.gd`, or `world_root.gd`.
##
## WHAT WAS MISSING BEFORE THIS FILE (see the build report): the reveal and its invisible
## collision wall were fully built, but nothing rendered at the world's edge at all — a
## player just saw the terrain grid stop. gdd.md -> World Structure: "ringed by mist that
## unfurls as you build near it"; "the mist is a curtain, not a gate." This is a PROPOSAL for
## the human (see the build report), not a settled decision — the shader's own header repeats
## the same flag for every look-affecting uniform.
##
## FLOOR SHAPE ONLY (spec.md #19). Four flat panels standing at the grid's current rectangular
## extent, rebuilt from scratch — freed and redrawn, the instant `WorldRoot.mist_revealed`
## fires. (Pre-D-41, this mirrored `TerrainView._rebuild_boundary_walls()`'s own instant-rebuild
## pattern for the separate, invisible movement-blocking collision wall; that wall and its
## rebuild function were removed under D-41 along with first-person movement, but this curtain's
## own instant-rebuild behavior is unchanged.) No organic chunk shape, no
## sprouting/dissolve animation: row 13's own thin_form is "instant, no sprouting," and organic
## edges are explicitly spec.md #19's DEPTH, not this pass's to build.
##
## RINGS THE WHOLE EXTENT, INCLUDING THE PERMANENT LOW CORNER. `WorldGrid.grow()`'s own
## disclosed trade-off is that only the high-x/high-z edges can ever recede — `x == 0`/`z == 0`
## is a permanent map boundary, not mist, in this thin form. This node dresses all four edges
## identically anyway: nothing distinguishes "will never recede" from "hasn't receded yet" to
## the six-year-old standing at either one, and gdd.md's "ringed by mist" describes what the
## player sees, not the save-format trade-off behind it. Flagged again under Proposals.
##
## THE SAME EDGE MATH THE OLD COLLISION WALL USED, BY CONSTRUCTION, NOT BY COPYING A NUMBER.
## This node computes its min/max edges from `WorldRoot.grid_to_world(0, 0)` /
## `grid_to_world(width - 1, depth - 1)`, `WorldGrid.TILE_SIZE`, and
## `TerrainView.BOUNDARY_WALL_THICKNESS` (both public consts, read rather than duplicated as
## bare literals). D-41 removed the movement-blocking collision wall this once had to stay in
## lock-step with (`TerrainView._build_boundary_walls()`, deleted); `BOUNDARY_WALL_THICKNESS`
## itself was deliberately kept, since this curtain still reads it for its own panel-overlap
## margin below.
##
## THE LOOK ITSELF IS NOT MACHINE-CHECKABLE. `test_mist_boundary.gd` asserts the geometry's
## bounds track the grid's revealed extent and that a rebuild fires exactly once per
## `mist_revealed` (never zero, never twice) — never that the shader reads as "atmospheric"
## on screen. That eyeball call is explicitly the human's, not this suite's.

## How tall each curtain panel is, in world units (1 unit = 1 tile, person-scale). PROPOSAL,
## a look-pass judgment call — no GDD number exists. Chosen tall enough that the shader's own
## height fade (see the .gdshader) can clear well before the top edge, so the mesh's own hard
## top never reads as a hard line against the sky.
const PANEL_HEIGHT: float = 6.0

## The shader resource. One file, shared by every panel on every rebuild — see `_material`.
const MIST_SHADER: Shader = preload("res://assets/shaders/mist_curtain.gdshader")

## Test-visible only: how many times `_rebuild()` has actually run (initial bind counts as
## one). Not read by anything else in the game — exists so a headless suite can assert a
## reveal rebuilds the curtain exactly once, the same invariant `WorldGrid.grown` itself
## guards ("never twice, even when one edit is near two edges at once").
var rebuild_count: int = 0

## Test-visible only: the XZ rectangle the last `_rebuild()` computed (min_x, min_z, width,
## depth), before the boundary-wall thickness margin is added. Lets a headless suite assert
## the geometry tracks the grid's revealed extent without inspecting mesh vertices directly.
var last_bounds: Rect2 = Rect2()

var _world: WorldRoot = null
var _material: ShaderMaterial = null
var _panels: Array[MeshInstance3D] = []


func _ready() -> void:
	# Same ordering fix `GameUI`/`CameraRig` already use: `WorldRoot` builds its grid in its
	# own `_ready()`, which — for a sibling node under the same `Main.tscn` root — runs AFTER
	# this node's `_ready()` in Godot's children-before-parent ready order. One deferred frame
	# guarantees `WorldRoot.instance()` already has a real, sized grid attached.
	call_deferred("bind_world")


func _process(_delta: float) -> void:
	if _world == null:
		bind_world()


## Connects to the live world. Idempotent and public so a headless test can call it directly
## instead of waiting on frames — the same shape `GameUI.bind_world()` already has.
func bind_world() -> void:
	var world: WorldRoot = WorldRoot.instance()
	if world == null or world == _world:
		return
	_world = world
	if not world.mist_revealed.is_connected(_on_mist_revealed):
		world.mist_revealed.connect(_on_mist_revealed)
	_rebuild()


func _on_mist_revealed(_new_tiles: Array[Vector2i]) -> void:
	_rebuild()


## Frees every panel the last call placed and redraws all four at the grid's CURRENT extent —
## never an animated transition, matching the shader's own "instant, no sprouting" contract.
func _rebuild() -> void:
	for panel: MeshInstance3D in _panels:
		if is_instance_valid(panel):
			panel.queue_free()
	_panels = []

	if _world == null:
		return
	var size: Vector2i = _world.grid_size()
	if size.x <= 0 or size.y <= 0:
		return

	if _material == null:
		_material = _make_material()

	var near: Vector3 = _world.grid_to_world(0, 0)
	var far: Vector3 = _world.grid_to_world(size.x - 1, size.y - 1)
	var half_tile: float = WorldGrid.TILE_SIZE * 0.5
	var thickness: float = TerrainView.BOUNDARY_WALL_THICKNESS

	var min_x: float = minf(near.x, far.x) - half_tile
	var max_x: float = maxf(near.x, far.x) + half_tile
	var min_z: float = minf(near.z, far.z) - half_tile
	var max_z: float = maxf(near.z, far.z) + half_tile
	last_bounds = Rect2(min_x, min_z, max_x - min_x, max_z - min_z)

	# Overlap by a full thickness at both ends (the same shape the old, now-deleted movement-
	# blocking collision wall used) so the four curtain panels meet solidly at the corners with
	# no visible gap.
	var span_x: float = (max_x - min_x) + thickness * 2.0
	var span_z: float = (max_z - min_z) + thickness * 2.0
	var centre_x: float = (min_x + max_x) * 0.5
	var centre_z: float = (min_z + max_z) * 0.5

	# West / east: panels running along Z, rotated so their width axis (local X) lies along
	# world Z.
	_add_panel(Vector3(min_x - thickness * 0.5, 0.0, centre_z), span_z, 90.0)
	_add_panel(Vector3(max_x + thickness * 0.5, 0.0, centre_z), span_z, 90.0)
	# South / north: panels running along X, unrotated.
	_add_panel(Vector3(centre_x, 0.0, min_z - thickness * 0.5), span_x, 0.0)
	_add_panel(Vector3(centre_x, 0.0, max_z + thickness * 0.5), span_x, 0.0)

	rebuild_count += 1


func _add_panel(center: Vector3, width: float, yaw_degrees: float) -> void:
	var panel := MeshInstance3D.new()
	panel.name = "MistPanel"
	panel.mesh = _make_quad_mesh(width, PANEL_HEIGHT)
	panel.material_override = _material
	panel.position = center
	panel.rotation_degrees.y = yaw_degrees
	# A translucent fog card casting a hard shadow would read as a lit solid object — exactly
	# what the shader's own `unshaded` render mode is already avoiding.
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	_panels.append(panel)


## One flat quad, `width` along local X, `height` along local Y, resting on Y = 0. Built by
## hand from a raw `ArrayMesh` rather than `QuadMesh` so this file controls the facing axis
## directly instead of reasoning about `QuadMesh.orientation` — with `cull_disabled` on the
## shader, winding order does not matter.
func _make_quad_mesh(width: float, height: float) -> ArrayMesh:
	var half_w: float = width * 0.5
	var vertices := PackedVector3Array([
		Vector3(-half_w, 0.0, 0.0),
		Vector3(half_w, 0.0, 0.0),
		Vector3(half_w, height, 0.0),
		Vector3(-half_w, height, 0.0),
	])
	var normals := PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK,
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = MIST_SHADER
	return material


## Test-visible only: how many curtain panels currently exist (always 4 once bound — one per
## edge, including the permanent low-corner boundary; see this file's own header).
func panel_count() -> int:
	return _panels.size()
