class_name ResidentRoamer
extends RefCounted
## One resident's waypoint wander — Tier 1 row 6's thin form, the "waypoint wander" clause.
##
## gdd.md -> Level & world design: "**Animals occupy no tiles** — they roam the walkable
## surface freely within their home neighbourhood's capacity." So: pick a waypoint inside the
## home site's radius, walk to it, pause, pick another. That is the whole state machine.
##
## THIS IS PRESENTATION-LAYER MOTION, NOT SIMULATION. A resident moving is **not** one of the
## four habitat triggers (terraform, building add/remove, resident arrive, resident depart).
## Nothing here marks a neighbourhood dirty, re-qualifies anything, or touches
## `HabitatSimulation.evaluations_run` — the zero that gdd.md -> Performance's whole CPU
## argument rests on stays a zero while every resident in the world is walking around.
##
## OBSTACLE AVOIDANCE AND ANIMAL-ANIMAL SEPARATION WERE PULLED FORWARD (2026-08-24, direct
## human request) FROM spec.md -> Tier 1 -> What Deepening Buys, row 6's "Roam quality" depth
## bucket. Residents path around buildings, Forest terrain, and other residents' den tiles
## (`WorldNavigation`, `_world_navigation`/`_path` above) and steer softly away from other
## residents (`_nearby_resident_provider`/`_separation_nudge()`) — soft steering, not hard
## collision, a deliberate choice: it reduces overlap, it does not guarantee zero.
##
## STILL NOT BUILT:
##   * no personality bias — Shy animals do not hang back, Bold ones do not approach;
##   * no flocking, and Rock terrain does not block movement (only Forest does, in this
##     pass — human's call to revisit);
##   * no turn easing beyond per-corner re-facing — facing snaps at the moment a waypoint or
##     a path corner is reached, while the animal is standing still or already at that
##     corner, which is the cheapest form that still never walks backwards;
##   * gentle relocation is row 10.
##
## The floor is that the world reads as ALIVE rather than as a diorama. How good it looks is a
## later purchase.
##
## AVOIDS DISTANCE-KEEPING (row 9, D-29). Piggybacked on the pause -> walk cadence that
## already exists for wander: `_pick_angle()` is the ONLY place this file asks "is an avoided
## species nearby", and it runs once per wander cycle (every `PAUSE_MIN/MAX_SECONDS`), never
## per frame — no second timer, no per-frame cost added to an idle resident. It never widens
## the roam radius: only WHICH ANGLE within the already-clamped disc gets picked changes, so
## "freely within their home neighbourhood" stays structural (`_radius`, above, is untouched).
##
## ANIMATION IS PICKED BY CAPABILITY, NOT SPECIES. `AnimalClips` resolves each optional clip
## (Run/Gallop, Eating, Wave, idle variants) by name against whatever THIS model's
## AnimationPlayer actually carries; an unresolved clip is `""` and simply never gets rolled.
## Rabbit has none of them and always walks/idles exactly as it always has — no per-species
## config anywhere in this file or in roster data. `_begin_walk()` rolls Walk vs. a faster
## travel clip once per leg; `_begin_pause()` rolls plain Idle vs. a flavor clip once per pause.
## Both still only ever fire from the same once-per-transition call sites `_play()` always used.
##
## SELF-HEALING AGAINST A FROZEN LOCOMOTION CLIP. The bug this closes: a clip imported as
## non-looping plays once, freezes on its last pose, and `_play()`'s "already this clip" guard
## then never re-fires it — while `tick()` keeps moving the resident regardless, so it glides
## mid-stride. The real fix is the asset import (`animation/loop_mode` set to Linear on every
## locomotion clip in the roster — see each species' `.import` file), but `_ensure_playing()`
## below is a second, independent line of defense: any frame the player has stopped but this
## roamer still expects a clip playing, it re-triggers. Cheap — one `is_playing()` check per
## tick — and it means a future species imported without loop set reproduces as nothing worse
## than this safety net.

enum State { PAUSED, WALKING }

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for walk speed**;
## this is not a stated baseline being transcribed, it is a starting value chosen so the motion
## reads as an unhurried amble at person scale (one tile = one world unit, gdd.md -> Level &
## world design). Tiles per second.
const WALK_SPEED_TILES_PER_SECOND: float = 0.6

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for a run/gallop
## speed.** Only used on a leg where `AnimalClips.run_clip()` resolved something for this
## model (rabbit never rolls this). 1.75x is a conservative starting ratio — real quadrupeds'
## gallop is closer to 2.5-3x their walk, but a village reads calmer with a smaller gap, and
## legibility (an observer can still tell "this one is hurrying" without it looking frantic)
## mattered more here than realism.
const RUN_SPEED_MULTIPLIER: float = 1.75
const RUN_SPEED_TILES_PER_SECOND: float = WALK_SPEED_TILES_PER_SECOND * RUN_SPEED_MULTIPLIER

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for how often a travel
## leg is a run instead of a walk.** Chosen low enough that running reads as an occasional
## flourish, not the normal gait — most legs should still be an amble per row 6's "unhurried"
## framing.
const RUN_PROBABILITY: float = 0.18

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for idle-flavor
## frequency.** How often a pause plays a flavor clip (Eating, Wave, an idle variant) instead
## of plain Idle, on species that have one. Kept a minority of pauses so Idle stays the
## recognizable "at rest" read and flavor stays a flourish, not the norm.
const IDLE_FLAVOR_PROBABILITY: float = 0.3

## PLACEHOLDER — the human owns these. **No GDD or spec.md number exists for pause length.**
## Randomised so a group of residents does not step off in lockstep. Seconds.
const PAUSE_MIN_SECONDS: float = 2.0
const PAUSE_MAX_SECONDS: float = 6.0

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for the waypoint-pick
## radius.** gdd.md bounds it from above but not below: roaming is "within their home
## neighbourhood", so this is clamped to the home site's own radius at construction and can
## never exceed it however it is tuned. In tiles.
const WANDER_RADIUS_TILES: float = 3.0

## How close counts as arrived, in tiles. Not a design value — it exists so the final step of
## a walk cannot overshoot and oscillate.
const ARRIVAL_EPSILON_TILES: float = 0.02

## Yaw applied on top of "point the model's +Z along the direction of travel".
##
## Zero because the glTF 2.0 specification fixes the convention: +Y is up and **the front of
## an asset faces +Z**, so aligning +Z with the travel direction is correct by spec for every
## glTF/FBX-imported model in the roster. It is a named constant rather than a bare `0.0`
## because a single non-conforming asset would otherwise need code surgery: set this to `PI`
## for a model authored facing -Z. The camera never rotates (gdd.md -> Player Interface), so a
## resident walking backwards is very visible and this is worth being explicit about.
const FACING_YAW_OFFSET_RADIANS: float = 0.0

## DECIDED 2026-08-01 (-> D-29). No GDD or spec.md baseline exists for this row (row 9 is a
## new build, not a stated constant being transcribed); sized relative to the floor pair's
## already-decided radii — Rabbit `scout_radius` 8, Fox 12, and this file's own wander radius
## 3 — so distance-keeping reads as deliberate without ever competing with habitat placement
## itself. In tiles; world units, since one tile is one world unit.
const AVOID_DISTANCE_TILES: float = 5.0

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for the bias arc.**
## Half-width of the cone (either side of straight-away-from-the-threat) the next waypoint's
## angle is drawn from once a species to avoid is within `AVOID_DISTANCE_TILES`. `PI * 0.5`
## (90 deg either side, 180 deg total) biases firmly away without collapsing onto one exact
## point — still keeps the same distance distribution over the same disc.
const AVOID_BIAS_HALF_ARC_RADIANS: float = PI * 0.5

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for separation
## distance.** How close two residents (any species, unlike `AVOID_DISTANCE_TILES` which is
## mutual-avoids-only) can get before a soft steering nudge starts pushing them apart.
## Smaller than a tile on purpose — animals occupy no tiles (gdd.md), so this is about
## visual overlap, not a hitbox. Soft steering, not hard collision (human-confirmed):
## reduces overlap, does not guarantee zero.
const SEPARATION_DISTANCE_TILES: float = 0.6

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for separation
## strength.** Tiles/second of push at zero distance (linearly interpolated to zero push at
## `SEPARATION_DISTANCE_TILES`) — comparable to `WALK_SPEED_TILES_PER_SECOND` so a nudge can
## actually resolve an overlap within a step or two rather than being imperceptibly weak or
## visibly snapping residents apart.
const SEPARATION_STRENGTH_TILES_PER_SECOND: float = 0.6


var _resident: Node3D = null
var _home: Vector3 = Vector3.ZERO
var _radius: float = 0.0
var _bounds: Rect2 = Rect2()
var _rng: RandomNumberGenerator = null

var _species_id: String = ""
var _avoid_ids: Array[String] = []
## A Callable taking no arguments and returning `Array[Vector3]` — the current world positions
## of every live resident this one should keep distance from, already filtered to within
## `AVOID_DISTANCE_TILES`. Bound by `ResidentPresentation.present()`, the only thing that
## knows the whole roster of live roamers; unset (`Callable()`, invalid) costs nothing beyond
## the `is_valid()` check every wander cycle.
var _nearby_avoid_provider: Callable = Callable()

## A Callable taking no arguments and returning `Array[Vector3]` — every OTHER live
## resident's current position within `SEPARATION_DISTANCE_TILES`, ANY species (unlike
## `_nearby_avoid_provider`, no mutual-avoids filter). Bound by
## `ResidentPresentation.present()`. Unlike the avoid provider (called once per wander
## cycle), this is called every tick a resident is WALKING — see `_separation_nudge()`.
var _nearby_resident_provider: Callable = Callable()

var _player: AnimationPlayer = null
var _idle_clip: String = ""
var _walk_clip: String = ""
var _run_clip: String = ""
var _eat_clip: String = ""
var _wave_clip: String = ""
var _idle_variant_clips: Array[String] = []

## The clip this roamer most recently asked to play, regardless of whether `_play()` actually
## called `.play()` (it skips that call when the clip is already current). `_ensure_playing()`
## reads this, not `_idle_clip`/`_walk_clip` directly, since PAUSED/WALKING can now each play
## more than one clip (flavor idle, run vs. walk).
var _expected_clip: String = ""
## This leg's travel speed, tiles/second — `WALK_SPEED_TILES_PER_SECOND` or
## `RUN_SPEED_TILES_PER_SECOND`, chosen once in `_begin_walk()`.
var _travel_speed: float = WALK_SPEED_TILES_PER_SECOND

var _state: State = State.PAUSED
var _pause_remaining: float = 0.0

## The corners of the current travel leg, from `WorldNavigation.find_path()` — or, with no
## `_world_navigation` bound (every caller before the animal-navigation pass, and every
## test that does not pass one), a single-point path straight to the picked waypoint:
## BYTE-IDENTICAL to the old straight-line behavior. `_path_index` is which corner is being
## walked toward now.
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0

## Bound at construction (`_init()`'s last argument). Null is a supported, tested state —
## a roamer with no navigation degrades to the pre-navigation straight-line behavior rather
## than erroring.
var _world_navigation: WorldNavigation = null


## `home_world` is the home site's world position; `home_radius_tiles` is the site's own
## radius, which the wander radius is clamped to. `bounds_xz` is the walkable surface in world
## XZ — waypoints are clamped into it so nobody strolls off the edge of the world. `species_id`
## and `avoid_ids` are this resident's own species id and its `avoids` list (normalized); both
## default empty so a caller that does not care about avoids gets the old uniform pick.
func _init(
	resident: Node3D,
	home_world: Vector3,
	home_radius_tiles: float,
	bounds_xz: Rect2,
	rng: RandomNumberGenerator,
	species_id: String = "",
	avoid_ids: Array[String] = [],
	world_navigation: WorldNavigation = null
) -> void:
	_resident = resident
	_home = home_world
	_radius = maxf(0.0, minf(WANDER_RADIUS_TILES, home_radius_tiles))
	_bounds = bounds_xz
	_rng = rng if rng != null else RandomNumberGenerator.new()
	_species_id = AnimalDefinition.normalize_id(species_id)
	_avoid_ids = avoid_ids
	_world_navigation = world_navigation

	_player = AnimalClips.find_player(_resident)
	_idle_clip = AnimalClips.idle_clip(_player)
	_walk_clip = AnimalClips.walk_clip(_player)
	_run_clip = AnimalClips.run_clip(_player)
	_eat_clip = AnimalClips.eat_clip(_player)
	_wave_clip = AnimalClips.wave_clip(_player)
	_idle_variant_clips = AnimalClips.idle_variant_clips(_player, _idle_clip)

	_begin_pause()


func is_valid() -> bool:
	return _resident != null and is_instance_valid(_resident)


func resident() -> Node3D:
	return _resident


func home() -> Vector3:
	return _home


func wander_radius() -> float:
	return _radius


func species_id() -> String:
	return _species_id


## This resident's own `avoids` list. **Not the whole symmetric relationship** — gdd.md's
## avoids relation "may be declared on either species... the resolver must union both
## directions rather than trusting one side" (`AnimalDefinition.avoids`'s own doc), so a
## caller resolving "should A keep distance from B" must check BOTH `A.avoid_ids()` and
## `B.avoid_ids()`, never this alone. `ResidentPresentation._nearby_avoid_positions()` does.
func avoid_ids() -> Array[String]:
	return _avoid_ids


## Bound once at construction by `ResidentPresentation.present()`. Public setter rather than a
## constructor argument because the provider closes over the roamer it belongs to, which does
## not exist until `_init()` returns.
func set_nearby_avoid_provider(provider: Callable) -> void:
	_nearby_avoid_provider = provider


func set_nearby_resident_provider(provider: Callable) -> void:
	_nearby_resident_provider = provider


## "Walk" or "Idle" — the state, not the clip name. Public so a headless check can assert the
## animation state actually switches instead of trusting that it does.
func state_name() -> String:
	return "Walk" if _state == State.WALKING else "Idle"


## The clip currently playing, or `""` where the model has no AnimationPlayer.
func current_clip() -> String:
	if _player == null or not is_instance_valid(_player):
		return ""
	return _player.current_animation


## Advances one resident. Called from `ResidentPresentation.tick()`, never from the simulation.
func tick(delta: float) -> void:
	if not is_valid():
		return
	_ensure_playing()
	if _state == State.PAUSED:
		_pause_remaining -= delta
		if _pause_remaining <= 0.0:
			_begin_walk()
		return

	var corner: Vector3 = _path[_path_index]
	var to_corner: Vector3 = corner - _resident.position
	to_corner.y = 0.0
	var remaining: float = to_corner.length()
	var step: float = _travel_speed * delta
	if remaining <= maxf(step, ARRIVAL_EPSILON_TILES):
		_resident.position = corner
		_path_index += 1
		if _path_index >= _path.size():
			_begin_pause()
		else:
			_face(_path[_path_index] - _resident.position)
		return
	var move: Vector3 = (to_corner / remaining) * step
	_resident.position += move + _separation_nudge(delta)


func _begin_pause() -> void:
	_state = State.PAUSED
	_pause_remaining = _rng.randf_range(PAUSE_MIN_SECONDS, PAUSE_MAX_SECONDS)
	_play(_pick_idle_clip())


func _begin_walk() -> void:
	var waypoint: Vector3 = _pick_waypoint()
	var direction: Vector3 = waypoint - _resident.position
	direction.y = 0.0
	if direction.length_squared() <= ARRIVAL_EPSILON_TILES * ARRIVAL_EPSILON_TILES:
		_begin_pause()  # the dice landed on where we already stand; wait and try again
		return

	if _world_navigation != null:
		_path = _world_navigation.find_path(_resident.position, waypoint)
	else:
		_path = PackedVector3Array()
	if _path.is_empty():
		# No navigation bound, OR the waypoint is genuinely unreachable (boxed in). Either
		# way this is not an error: a direct single-point path reproduces the exact
		# pre-navigation straight-line behavior, and an unreachable waypoint simply gets
		# walked toward directly rather than leaving the resident frozen — the same "try
		# again next cycle" spirit as the dice-landed-on-ourselves case above, just one leg
		# later once the next `_begin_walk()` picks a fresh waypoint.
		_path = PackedVector3Array([waypoint])
	_path_index = 0
	_face(_path[_path_index] - _resident.position)

	_state = State.WALKING
	if _run_clip != "" and _rng.randf() < RUN_PROBABILITY:
		_travel_speed = RUN_SPEED_TILES_PER_SECOND
		_play(_run_clip)
	else:
		_travel_speed = WALK_SPEED_TILES_PER_SECOND
		_play(_walk_clip)


## Plain Idle most pauses; on a species that has one, occasionally a flavor clip instead
## (`IDLE_FLAVOR_PROBABILITY`) — Eating, Wave, or an idle variant, picked uniformly among
## whichever of those this model actually resolved.
func _pick_idle_clip() -> String:
	var flavors: Array[String] = _idle_variant_clips.duplicate()
	if _eat_clip != "":
		flavors.append(_eat_clip)
	if _wave_clip != "":
		flavors.append(_wave_clip)
	if flavors.is_empty() or _rng.randf() >= IDLE_FLAVOR_PROBABILITY:
		return _idle_clip
	return flavors[_rng.randi_range(0, flavors.size() - 1)]


## A point in the disc of `_radius` around the home site, clamped to the walkable surface.
## `sqrt` on the radius keeps the distribution uniform over AREA rather than bunching every
## waypoint near the den. The ANGLE alone is biased away from a nearby avoided species when
## one is within reach (`_pick_angle()`) — the disc, the radius and the area distribution are
## exactly what they were before row 9.
func _pick_waypoint() -> Vector3:
	var angle: float = _pick_angle()
	var distance: float = _radius * sqrt(_rng.randf())
	var point := Vector3(
		_home.x + cos(angle) * distance,
		_home.y,
		_home.z + sin(angle) * distance
	)
	if _bounds.size.x > 0.0 and _bounds.size.y > 0.0:
		point.x = clampf(point.x, _bounds.position.x, _bounds.end.x)
		point.z = clampf(point.z, _bounds.position.y, _bounds.end.y)
	return point


## Uniform over `[0, TAU)` with nothing nearby to avoid — the pre-row-9 behaviour, byte
## identical. Once the provider reports at least one avoided resident within
## `AVOID_DISTANCE_TILES`, the angle is instead drawn from a cone of half-width
## `AVOID_BIAS_HALF_ARC_RADIANS` centred on the direction FROM the average threat position
## TOWARD the home site — "away", in the same (x maps to cos, z maps to sin) convention
## `_pick_waypoint()` already uses, so this never needs its own coordinate mapping.
func _pick_angle() -> float:
	if not _nearby_avoid_provider.is_valid():
		return _rng.randf_range(0.0, TAU)
	var threats: Array = _nearby_avoid_provider.call()
	if threats == null or threats.is_empty():
		return _rng.randf_range(0.0, TAU)

	var away_x: float = 0.0
	var away_z: float = 0.0
	for threat: Vector3 in threats:
		var dx: float = _home.x - threat.x
		var dz: float = _home.z - threat.z
		var len: float = sqrt(dx * dx + dz * dz)
		if len > 0.0001:
			away_x += dx / len
			away_z += dz / len

	if away_x * away_x + away_z * away_z <= 0.0001:
		# Threats surround the home evenly (or all sit exactly on it) — no direction reads as
		# "away" more than any other, so fall back to the old uniform pick rather than guess.
		return _rng.randf_range(0.0, TAU)

	var away_angle: float = atan2(away_z, away_x)
	return away_angle + _rng.randf_range(-AVOID_BIAS_HALF_ARC_RADIANS, AVOID_BIAS_HALF_ARC_RADIANS)


## Points the model's +Z along the direction of travel (see FACING_YAW_OFFSET_RADIANS).
func _face(direction: Vector3) -> void:
	_resident.rotation.y = atan2(direction.x, direction.z) + FACING_YAW_OFFSET_RADIANS


func _play(clip: String) -> void:
	_expected_clip = clip
	if clip == "" or _player == null or not is_instance_valid(_player):
		return
	if _player.current_animation == clip:
		return
	_player.play(clip)


## The second line of defense against a frozen locomotion clip (see the class doc). If the
## expected clip has stopped advancing — the exact symptom a non-looping locomotion import
## produces — re-triggers it. `current_animation == _expected_clip` guards against re-firing
## mid-transition to a different clip that simply hasn't started playing yet.
func _ensure_playing() -> void:
	if _expected_clip == "" or _player == null or not is_instance_valid(_player):
		return
	if _player.current_animation == _expected_clip and not _player.is_playing():
		_player.play(_expected_clip)


## Soft per-tick push away from any OTHER resident within `SEPARATION_DISTANCE_TILES` —
## reduces walking-through-each-other, does NOT guarantee it (soft steering, not hard
## collision — human-confirmed decision). Only applied while WALKING: a PAUSED resident
## does not need to dodge, and nudging a standing-still pose would fight its "at rest" read.
func _separation_nudge(delta: float) -> Vector3:
	if not _nearby_resident_provider.is_valid():
		return Vector3.ZERO
	var nearby: Array = _nearby_resident_provider.call()
	if nearby == null or nearby.is_empty():
		return Vector3.ZERO
	var push := Vector3.ZERO
	for other_position: Vector3 in nearby:
		var away: Vector3 = _resident.position - (other_position as Vector3)
		away.y = 0.0
		var dist: float = away.length()
		if dist <= 0.0001 or dist >= SEPARATION_DISTANCE_TILES:
			continue
		var strength: float = (SEPARATION_DISTANCE_TILES - dist) / SEPARATION_DISTANCE_TILES
		push += (away / dist) * strength
	return push * SEPARATION_STRENGTH_TILES_PER_SECOND * delta
