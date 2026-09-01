class_name GameUI
extends CanvasLayer
## The UI shell — the node that makes the simulation playable. Tier 1 rows 2 and 7, wired.
##
## It owns nothing but wiring. Every piece of behaviour lives in a single-purpose file
## (`GameHud`, `TapRouter`, `FactCard`, `TapCue`, `NeighborhoodPreview`, `CameraRig`), and this
## class connects them to `WorldRoot`'s public API and to each other:
##
##   WorldRoot.wood_changed        -> GameHud.set_wood              (read-only, never flashes)
##   WorldRoot.resident_arrived    -> FactCard                      (row 7's signature moment, FIRST-EVER arrival only)
##   WorldRoot.resident_arrived    -> NotificationFeed               (row 7, every REPEAT arrival)
##   WorldRoot.resident_arrived    -> GameHud counters + FieldGuide (row 11, a resident landed)
##   WorldRoot.resident_departed   -> GameHud counters + FieldGuide (row 11, on top of row 10)
##   WorldRoot.tile_changed        -> TapRouter.invalidate_preview  (row 6's live preview)
##   WorldRoot.displacement_warned -> NotificationFeed               (row 10's informed consent, non-blocking)
##   WorldRoot.resident_relocated  -> DisplacementNotice            (row 10, outcome one — UNCHANGED, still the toast)
##   WorldRoot.resident_departed   -> DisplacementNotice            (row 10, outcome two — UNCHANGED, still the toast)
##   SettingsOverlay.hints_toggled -> NewsReportPresenter            (row 12, suppresses live)
##   left-click                    -> TapRouter                     (Pillar 3's one gesture)
##
## THE UI KEEPS NO LIST OF RESIDENTS. It used to (`resident_index.gd`, deleted), built from
## `resident_arrived` payloads and therefore hit-testing arrival-time positions — which went
## stale the moment residents began to wander. `WorldRoot.resident_record_at()` answers the
## question against live positions now, so `resident_arrived` here does exactly one thing: fire
## the card.
##
## THE WORLD IS FOUND, NOT ADDRESSED. `WorldRoot.instance()` and
## `get_viewport().get_camera_3d()` mean this scene holds no path into a tree it does not
## own — drop it into any scene that has a world and a camera and it wires itself.
##
## SAFE WITHOUT A WORLD. Every connection is guarded, so `scenes/ui/GameUI.tscn` can be
## opened and reviewed on its own in the editor without a running simulation.

## Tier 1 row 11. `human.tres`'s own comment names this literal: "this entry's `display_name`
## is 'Villager' and the HUD counter is 'Village Population'". Kept as one named constant
## rather than repeated string literals, matching the precedent `displacement_copy.gd`
## already set for the same id (`FLOOR_SPECIES_IDS`). **Judgment call, flagged under
## Proposals:** nothing in `AnimalDefinition`'s schema marks a species as "the villager
## species" data-side, so Village Population is one hardcoded id away from silently reading
## 0 forever if that id is ever renamed.
const VILLAGER_SPECIES_ID: String = "human"

@onready var hud: GameHud = %HUD
@onready var fact_card: FactCard = %FactCard
@onready var tap_cue: TapCue = %TapCue
@onready var tap_router: TapRouter = %TapRouter
@onready var displacement_notice: DisplacementNotice = %DisplacementNotice
@onready var menu_window: MenuWindow = %MenuWindow
@onready var news_report_toast: NewsReportToast = %NewsReportToast
@onready var crosshair: Crosshair = %Crosshair
@onready var news_report_presenter: NewsReportPresenter = %NewsReportPresenter
@onready var notification_feed: NotificationFeed = %NotificationFeed

var _world: WorldRoot = null
var _camera: Camera3D = null

## Snapshotted once, the first time `bind_world()` binds a world — everything hosted BEFORE
## this session (or earlier in it, appended below) is in here. `species_hosted_ids()` cannot
## be checked live at `resident_arrived` time for this: `HomeSiteRegistry.register()` already
## marks a species hosted before the signal fires, so there is no "before this arrival" moment
## left at that layer. This snapshot is what supplies one instead.
var _known_before_session: Array[String] = []


func _ready() -> void:
	# → D-44, 90°-step camera rotation.
	hud.rotate_cw_pressed.connect(_on_rotate_cw_pressed)
	hud.rotate_ccw_pressed.connect(_on_rotate_ccw_pressed)
	# Tab and [?] are two doors to one room — the `[?]` button exists because Tab is not
	# discoverable to a 6-10-year-old who has never used a keyboard shortcut.
	hud.help_pressed.connect(_on_help_pressed)
	# Leaving a mode leaves its preview behind with it: the next poll re-reads from scratch
	# rather than showing a band computed under the other mode's cursor.
	hud.mode_changed.connect(func(_mode: GameHud.Mode) -> void: tap_router.invalidate_preview())
	# Settings (the Hints toggle, Master Volume) moved off MenuWindow entirely onto its own
	# Title-screen-reachable page (2026-08-25 human decision) — there is no longer a live
	# `SettingsOverlay` instance in-game for `news_report_presenter` to listen to mid-session.
	# `NewsReportPresenter` still reads `GameplaySettings.hints_enabled()` fresh in its own
	# `bind_world()`, so a change made between sessions takes effect on the next one.
	# `WorldRoot` builds its grid in its own `_ready()`, which runs after this scene's if the
	# UI is a child of it. One deferred frame guarantees the palettes read a finished world.
	call_deferred("bind_world")


func _process(_delta: float) -> void:
	if _camera == null or _world == null:
		bind_world()
	# Finding #2 of the 2026-08-09 final review: `Crosshair`'s own docstring names every
	# overlay this suppresses for ("a FactCard, the Field Guide, Settings, the Catalog
	# panel") — this used to pass only the first, then missed CatalogPanel on its own
	# addition (Task 4 review, same bug reproduced once already fixed for FieldGuide). Task 5
	# folded Field Guide/Settings/Catalog into the single MenuWindow, so one check now covers
	# all three.
	crosshair.set_suppressed(fact_card.is_open() or menu_window.is_open())


## Connects to the live world and camera. Idempotent, and public so a headless test can call
## it instead of waiting on frames.
func bind_world() -> void:
	var world: WorldRoot = WorldRoot.instance()
	var camera: Camera3D = null
	if is_inside_tree():
		camera = get_viewport().get_camera_3d()

	if world != null and world != _world:
		_world = world
		_known_before_session = world.species_hosted_ids()
		if not world.wood_changed.is_connected(_on_wood_changed):
			world.wood_changed.connect(_on_wood_changed)
		if not world.resident_arrived.is_connected(_on_resident_arrived):
			world.resident_arrived.connect(_on_resident_arrived)
		if not world.tile_changed.is_connected(_on_tile_changed):
			world.tile_changed.connect(_on_tile_changed)
		# ROW 10. All three are connected together or not at all: a build that showed the
		# consequences without the warning would be silent displacement, which gdd.md names as a
		# rejected alternative ("breaks 'nothing unexplained'").
		if not world.displacement_warned.is_connected(_on_displacement_warned):
			world.displacement_warned.connect(_on_displacement_warned)
		if not world.resident_relocated.is_connected(_on_resident_relocated):
			world.resident_relocated.connect(_on_resident_relocated)
		if not world.resident_departed.is_connected(_on_resident_departed):
			world.resident_departed.connect(_on_resident_departed)
		hud.set_wood(world.get_wood())
		hud.build_palettes(world)
		_refresh_counters(world)
		# Row 12. Binds (or rebinds) the nudge/News Report clock to this world, starting the
		# ~3 s countdown on a brand-new save and skipping straight to the ambient cadence
		# otherwise (`WorldRoot.is_new_world`).
		news_report_presenter.bind(world, news_report_toast)

	if camera != null:
		_camera = camera
		var rig := camera as CameraRig
		if rig != null:
			rig.menu_window = menu_window

	tap_router.attach(_world, hud, fact_card, notification_feed, tap_cue, crosshair)


func world() -> WorldRoot:
	return _world


func camera() -> Camera3D:
	return _camera


## Tier 1 row 11's three counters, read fresh from `WorldRoot` and handed to `GameHud` exactly
## the way `_on_wood_changed` already hands it `wood_changed`'s payload — this class does the
## reading, `GameHud` only ever receives plain integers.
func _refresh_counters(world: WorldRoot) -> void:
	if world == null:
		return
	hud.set_species_hosted(world.species_hosted_count())
	# Total animal individuals, not distinct species and not villagers — ruled by the human,
	# overriding the row-10 inference `game_hud.gd`'s header comment used to document.
	# Village Population's individuals are subtracted out of `total_residents()` rather than
	# double-counted into a second counter.
	hud.set_currently_resident(world.total_residents() - world.population_of(VILLAGER_SPECIES_ID))
	hud.set_village_population(world.population_of(VILLAGER_SPECIES_ID))


# --- Signal handlers ---------------------------------------------------------------------

## Pillar 1's indicator test, implemented as an absence: the number is assigned, and nothing
## else happens. No tween, no flash, no low-balance styling.
func _on_wood_changed(amount: int) -> void:
	hud.set_wood(amount)


## Row 7's signature moment, but only on a species' FIRST-EVER arrival — the payoff the
## core loop exists to deliver (gdd.md -> Core Loop step 4). Every repeat arrival of an
## already-known species routes to `notification_feed` instead, and Inspect-tap replay
## (`TapRouter._show_species_card()`) always routes there too, never back to this card
## (spec.md -> "Not depth axes" still applies to Pillar 4's curiosity path — it just isn't
## this widget any more).
func _on_resident_arrived(species_id: String, _world_position: Vector3) -> void:
	var species: AnimalDefinition = tap_router.species_definition(species_id)
	if species != null:
		if _known_before_session.has(species_id):
			notification_feed.show_fact(species.display_name, species.effective_fact_text())
		else:
			_known_before_session.append(species_id)
			fact_card.show_species(species)
	# A move-in changes what the land under the cursor is (somebody now lives there), and it is
	# not one of the `tile_changed` events, so it is invalidated explicitly.
	tap_router.invalidate_preview()
	# Row 11. Species Hosted, Currently Resident and (for the villager) Village Population can
	# all move on an arrival, and the Field Guide's flat list gains a row live if it is open.
	_refresh_counters(_world)
	if menu_window.is_open():
		menu_window.refresh_from(_world)


## An edit landed. The preview under a resting cursor must follow it — beat 4 of the First 60
## Seconds is exactly "paint a tile and watch the read change".
func _on_tile_changed(_x: int, _z: int) -> void:
	tap_router.invalidate_preview()


## ROW 10, THE WARNING. **One dialogue per emission**, summarising every affected home — the
## payload already is one gesture's worth, so there is nothing here to batch, dedupe or
## rate-limit, and "a warning is never suppressed while its consequence proceeds" holds because
## nothing in this path can decline to show one.
##
## A warning arriving while an older one is still on screen replaces it. It cannot happen in one
## settlement (one emission, one dialogue) and it is the right answer when it does: two gestures
## have settled, and the newer one describes the world the player is looking at.
func _on_displacement_warned(warning: Dictionary) -> void:
	notification_feed.show_warning(warning)


## Outcome one, and the one that runs most often. `from_tile` is a grid coordinate, so it is put
## back through `WorldRoot.grid_to_world()` for the marker's start — the UI keeps no map of its
## own and never converts coordinates by hand.
func _on_resident_relocated(
	species_id: String, from_tile: Vector2i, _to_tile: Vector2i, world_position: Vector3
) -> void:
	var from_position: Vector3 = world_position
	if _world != null:
		from_position = _world.grid_to_world(from_tile.x, from_tile.y)
	displacement_notice.note_relocation(
		species_id, _display_name_of(species_id), from_position, world_position
	)
	# Somebody's home is no longer where it was, so the read under a resting cursor changed.
	tap_router.invalidate_preview()


## Outcome two. `individuals` is deliberately unused: the copy names a **family**, never a
## headcount — "a family moving is a family, not a headcount" — and gdd.md's own line is "The fox
## family moved away to find a new home." Rendering the number here would put a count into a
## sentence the content pass wrote specifically without one.
func _on_resident_departed(
	species_id: String, _home_tile: Vector2i, _individuals: int, world_position: Vector3
) -> void:
	displacement_notice.note_departure(
		species_id, _display_name_of(species_id), world_position
	)
	tap_router.invalidate_preview()
	# Row 11. A departure can drop Currently Resident and Village Population (never Species
	# Hosted — that record is permanent, gdd.md -> Gentle Displacement), and the Field Guide's
	# list loses a row live if it is open. "A counter going down is normal" (gdd.md -> Economy).
	_refresh_counters(_world)
	if menu_window.is_open():
		menu_window.refresh_from(_world)


## `AnimalDefinition.display_name` — data, not copy. Only ever reaches the screen through
## `DisplacementCopy`'s `{display_name}` fallback, which no floor species can hit.
func _display_name_of(species_id: String) -> String:
	var species: AnimalDefinition = tap_router.species_definition(species_id)
	return species_id if species == null else species.display_name


## The `[?]` button's whole job: open the same window Tab already opens, on the same tab.
## `menu_window.open_at_tab()` needs a world to refresh the Field Guide against — `_world` may
## still be null the instant before the first `bind_world()` deferred call runs, in which case
## this is a harmless no-op tap rather than a crash.
func _on_help_pressed() -> void:
	if _world == null:
		return
	menu_window.open_at_tab(_world, MenuWindow.FIELD_GUIDE_TAB_INDEX)


## → D-44, 90°-step camera rotation.
func _on_rotate_cw_pressed() -> void:
	var rig := _camera as CameraRig
	if rig != null:
		rig.rotate_clockwise()


func _on_rotate_ccw_pressed() -> void:
	var rig := _camera as CameraRig
	if rig != null:
		rig.rotate_counterclockwise()
