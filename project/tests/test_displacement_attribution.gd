extends QATestCase
## WHO CAUSED THIS DISPLACEMENT — Tier 1 row 10's attribution rule.
##
## gdd.md's pillar promises disclosure for a precise thing: "Any loss is the warned, reversible
## result of the player's **own settled choice**, never the game's initiative." Two different
## events open a settlement gesture, and only one of them is that:
##
##   * `GentleDisplacement.on_edit()`   — the player painted, built or removed something.
##   * `GentleDisplacement.on_arrival()` — an animal landed. Landing rebuilds the whole
##     tile-exclusivity map (nearest site wins), so a NEIGHBOURING home can lose ground it was
##     counting on and fall under its own population. Real, and worth acting on — but nobody
##     touched the game.
##
## Before this rule existed, both showed the same panel. In a settled world the second fires
## continuously (arrivals land one individual at a time, forever), so the player got a warning
## every few seconds reading `DisplacementCopy.LEAD_MIXED` — "This will be a different kind of
## place." — whose own definition is "a mode the UI cannot attribute", because there was no
## player action to attribute. That is not disclosure; it is a false statement about a change
## the player never made.
##
## WHAT THIS SUITE PINS, and why each half is here:
##   1. `SettlementWindow` carries the flag and merges it by OR — pure timer bookkeeping, no
##      capacity arithmetic anywhere, so these checks are independent of the roster and the grid.
##   2. `GameUI` gates all three surfaces on it — the warning panel, the relocation banner and
##      the departure banner — driven through the REAL `WorldRoot` signals on `Main.tscn`.
##   3. The ordering the `GameUI` latch depends on: `_settle()` emits the warning and applies
##      its consequences synchronously, so a consequence can never reach the UI before its own
##      warning has set the flag. Asserted directly, so making settlement asynchronous fails
##      here rather than silently mislabelling a banner.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_displacement_attribution.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _ui: GameUI = null
var _notice: DisplacementNotice = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("displacement attribution")

	_check_window_carries_the_flag()
	_check_merge_is_sticky_by_or()
	_check_settlement_emits_before_it_acts()
	_check_reconcile_after_load_arms_silently()

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	var ui_node: Node = _world.get_node_or_null("GameUI")
	if not check(ui_node is GameUI, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui = ui_node as GameUI
	_ui.bind_world()
	_notice = _ui.displacement_notice

	_check_player_caused_warning_is_shown()
	_check_arrival_caused_warning_is_silent()
	_check_consequence_banners_follow_the_same_rule()

	finish()
	return true


# --- 1. The window carries the flag ------------------------------------------------------

func _check_window_carries_the_flag() -> void:
	var window := SettlementWindow.new()

	var edit_id: int = window.touch(Vector2i(4, 4), ["4,4,rabbit"] as Array[String], true)
	check(edit_id > 0, "an edit-armed gesture opens (id %d)" % edit_id)
	var settled: Array[Dictionary] = window.advance(SettlementWindow.GRACE_WINDOW_SECONDS)
	if not check_eq(settled.size(), 1, "...and settles once the grace window elapses"):
		return
	check(SettlementWindow.is_player_caused(settled[0]),
		"AN EDIT IS THE PLAYER'S: the settled gesture reports player_caused")

	var arrival_id: int = window.touch(Vector2i(9, 9), ["9,9,deer"] as Array[String], false)
	check(arrival_id > 0, "an arrival-armed gesture opens (id %d)" % arrival_id)
	settled = window.advance(SettlementWindow.GRACE_WINDOW_SECONDS)
	if not check_eq(settled.size(), 1, "...and settles the same way — the timer does not care"):
		return
	check(not SettlementWindow.is_player_caused(settled[0]),
		"AN ARRIVAL IS NOT: the settled gesture reports player_caused false")

	# NON-VACUITY: the two checks above ran against the same class on the same window, so a
	# reader can see the flag really does distinguish them rather than one path being unreachable.
	check_eq(SettlementWindow.is_player_caused({}), false,
		"a gesture dictionary with no flag at all reads false, and does not error")


func _check_merge_is_sticky_by_or() -> void:
	# THE CASE THAT MATTERS: an animal lands and arms a neighbourhood; the player then edits that
	# same neighbourhood before it settles. The gestures merge, and the player MUST still be told
	# — under-reporting here would drop a real warning about their own edit.
	var window := SettlementWindow.new()
	var key: Array[String] = ["12,12,fox"] as Array[String]
	window.touch(Vector2i(12, 12), key, false)
	window.touch(Vector2i(13, 12), key, true)
	var settled: Array[Dictionary] = window.advance(SettlementWindow.GRACE_WINDOW_SECONDS)
	if not check_eq(settled.size(), 1, "the two touches merged into ONE gesture"):
		return
	check(SettlementWindow.is_player_caused(settled[0]),
		"ARRIVAL THEN EDIT: the merged gesture is player-caused — OR, so a real edit is never lost")

	# ...and the other order, because a merge must not depend on which arrived first.
	window = SettlementWindow.new()
	window.touch(Vector2i(12, 12), key, true)
	window.touch(Vector2i(13, 12), key, false)
	settled = window.advance(SettlementWindow.GRACE_WINDOW_SECONDS)
	if not check_eq(settled.size(), 1, "...the reverse order also merges into one gesture"):
		return
	check(SettlementWindow.is_player_caused(settled[0]),
		"EDIT THEN ARRIVAL: still player-caused — the flag is sticky in both directions")

	# NON-VACUITY: two arrivals merging stay false, so the OR above is not a machine stuck on true.
	window = SettlementWindow.new()
	window.touch(Vector2i(12, 12), key, false)
	window.touch(Vector2i(13, 12), key, false)
	settled = window.advance(SettlementWindow.GRACE_WINDOW_SECONDS)
	if not check_eq(settled.size(), 1, "...two arrivals also merge into one gesture"):
		return
	check(not SettlementWindow.is_player_caused(settled[0]),
		"ARRIVAL THEN ARRIVAL: stays false — the merge really is OR, not a constant")


## REGRESSION, and it is a regression because this shipped wrong once. `reconcile_after_load()`
## first passed `player_caused = true`, on the reasoning that a reload cannot know what caused a
## home to be over capacity and should resolve the unknown toward disclosure.
##
## THE MEASUREMENT THAT KILLED THAT REASONING: this function re-arms every home over capacity at
## load **from any cause**, and the dominant cause is the relocation cascade, not a pending player
## edit. On a played-in world it re-armed 38 homes and produced 38 player-caused warnings — 38
## panels — on a load with nobody touching the game. Read structurally, because reproducing a
## genuinely over-capacity world here would drag in the capacity arithmetic this suite is
## deliberately independent of; the behavioural half is covered by the probe that found it.
func _check_reconcile_after_load_arms_silently() -> void:
	var source: String = (
		load("res://scripts/simulation/gentle_displacement.gd") as GDScript
	).source_code
	var at: int = source.find("func reconcile_after_load(")
	if not check(at >= 0, "gentle_displacement.gd declares reconcile_after_load()"):
		return
	var next_func: int = source.find("\nfunc ", at + 1)
	var body: String = source.substr(at, next_func - at) if next_func > at else source.substr(at)
	check(body.contains("_window.touch("),
		"...and it arms the settlement window, so this check is not vacuous")
	check(not body.contains("], true)"),
		"THE LOAD PATH ARMS SILENTLY: reconcile_after_load() must not mark its gestures "
		+ "player-caused — it re-arms every over-capacity home from any cause, so a played-in "
		+ "world would show one panel per home on load with no player input")
	check(body.contains("], false)"),
		"...it passes the flag explicitly as false rather than relying on the default")


# --- 2. The ordering the GameUI latch rests on -------------------------------------------

func _check_settlement_emits_before_it_acts() -> void:
	# `GameUI` reads `player_caused` off the warning and applies it to the relocation/departure
	# banners that follow. That is only sound because `_settle()` emits the warning and calls
	# `_apply()` in the SAME synchronous call — gdd.md's "warning first and acting after". Read
	# structurally, since reproducing a real displacement here would drag in the capacity
	# arithmetic this suite is deliberately independent of.
	var source: String = (
		load("res://scripts/simulation/gentle_displacement.gd") as GDScript
	).source_code
	var settle_at: int = source.find("func _settle(")
	if not check(settle_at >= 0, "gentle_displacement.gd declares _settle()"):
		return
	var next_func: int = source.find("\nfunc ", settle_at + 1)
	var body: String = source.substr(settle_at, next_func - settle_at) if next_func > settle_at \
		else source.substr(settle_at)
	var emit_at: int = body.find("displacement_warned.emit(")
	var apply_at: int = body.find("_apply(home)")
	check(emit_at >= 0, "..._settle() emits displacement_warned")
	check(apply_at >= 0, "..._settle() applies the consequences itself, in the same function")
	check(emit_at >= 0 and apply_at > emit_at,
		"WARNING FIRST, ACTING AFTER: the emit precedes _apply() inside one synchronous call, "
		+ "which is what lets GameUI's latch label the banners that follow")
	check(not body.contains("call_deferred") and not body.contains("await"),
		"...and nothing defers or awaits between them, so no consequence can outrun its warning")


# --- 3. The three surfaces, on the real signals ------------------------------------------

func _warning(player_caused: bool) -> Dictionary:
	# The payload's shape is `GentleDisplacement`'s; only the fields the notice actually renders
	# need to be real. One departing fox family, which is the copy path with no destination.
	return {
		"gesture_id": 1,
		"species_ids": ["fox"] as Array[String],
		"read_aloud": true,
		"player_caused": player_caused,
		"homes": [{
			"home_tile": Vector2i(10, 10),
			"world_position": _world.grid_to_world(10, 10),
			"species_id": "fox",
			"display_name": "Fox",
			"is_structure_home": false,
			"capacity": 0,
			"population": 1,
			"outcome": GentleDisplacement.OUTCOME_DEPART,
			"individuals": 1,
			"destination_tile": Vector2i(-1, -1),
			"copy_key": GentleDisplacement.COPY_KEY_DEPART,
		}],
	}


func _check_player_caused_warning_is_shown() -> void:
	_notice.dismiss_warning()
	_notice.clear_moments()
	check(not _notice.warning_visible(), "no warning is on screen to start with")

	_world.displacement_warned.emit(_warning(true))

	check(_notice.warning_visible(),
		"A PLAYER-CAUSED WARNING IS SHOWN — row 10's disclosure is intact for real edits")
	check(_notice.warning_text() != "",
		"...and it carries rendered copy (%d chars)" % _notice.warning_text().length())
	_notice.dismiss_warning()


func _check_arrival_caused_warning_is_silent() -> void:
	_notice.dismiss_warning()
	check(not _notice.warning_visible(), "the panel is closed again")

	_world.displacement_warned.emit(_warning(false))

	check(not _notice.warning_visible(),
		"AN ARRIVAL-CAUSED WARNING SHOWS NOTHING — the game does not warn about its own initiative")
	check_eq(_notice.warning_text(), "",
		"...and leaves no residue behind it either")

	# A missing flag is treated as not-player-caused. Nothing emits such a payload today, but the
	# default decides what a future caller that forgets the field does, so it is pinned.
	_world.displacement_warned.emit({
		"gesture_id": 2, "homes": [], "species_ids": [] as Array[String], "read_aloud": true,
	})
	check(not _notice.warning_visible(),
		"...and a payload with NO player_caused field at all is silent too (the default is false)")


func _check_consequence_banners_follow_the_same_rule() -> void:
	# The banner is the other half of the noise: a home that relocates or departs narrates itself
	# on the top-centre toast. An arrival-caused settlement must be silent there as well, or the
	# player still gets a line every few seconds for a deer shuffling between two spots.
	var anchor: Vector3 = _world.grid_to_world(10, 10)

	_notice.dismiss_warning()
	_notice.clear_moments()
	_world.displacement_warned.emit(_warning(false))
	_world.resident_relocated.emit("fox", Vector2i(10, 10), Vector2i(12, 10), anchor)
	_world.resident_departed.emit("fox", Vector2i(10, 10), 1, anchor)
	check_eq(_notice.queued_moments(), 0,
		"AN ARRIVAL-CAUSED RELOCATION AND DEPARTURE QUEUE NO BANNER AT ALL")
	check(not _notice.banner_visible(), "...and nothing is on the banner")

	# NON-VACUITY, and the half that proves the gate narrows rather than deletes: the identical
	# two signals after a PLAYER-caused warning do queue their lines.
	_notice.dismiss_warning()
	_notice.clear_moments()
	_world.displacement_warned.emit(_warning(true))
	_notice.dismiss_warning()
	_world.resident_relocated.emit("fox", Vector2i(10, 10), Vector2i(12, 10), anchor)
	_world.resident_departed.emit("fox", Vector2i(10, 10), 1, anchor)
	check(_notice.queued_moments() > 0,
		"A PLAYER-CAUSED RELOCATION AND DEPARTURE STILL DO (%d queued) — the rule narrows this "
			% _notice.queued_moments()
		+ "surface to the player's own edits, it does not remove it")
	_notice.clear_moments()
