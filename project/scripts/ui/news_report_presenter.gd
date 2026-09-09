class_name NewsReportPresenter
extends Node
## Tier 1 row 12 — wires `NewsReportScheduler` and `NewsReportContent` to a live
## `NewsReportToast`. Owns no visible node of its own; `GameUI` instances one alongside the
## toast, the same shape it already uses for every other single-purpose behaviour file
## (`TapRouter`, `TapCue`, …).

var _scheduler: NewsReportScheduler = null
var _toast: NewsReportToast = null
var _world: WorldRoot = null
var _content_rng := RandomNumberGenerator.new()
var _coach: OnboardingCoach = null

## The adaptive cadence (spec.md §11 / `hint_pacer.gd`). Built alongside the scheduler in
## `bind()` and handed straight to it — this file's own copy exists only so `_process()` has
## something to `advance()` and `notice_activity()` has something to poke; the scheduler is
## what actually reads it.
var _pacer: HintPacer = null

## The species named LAST report, fed back into `pick_species()`'s no-repeat filter. Its own
## field, not `_hinted_species_ids` below — "hinted at some point this session" (that dict) and
## "hinted immediately previously" (this) are different questions, and `_hinted_species_ids`
## is documented session-only/unpersisted for a future Field Guide column that has nothing to
## do with ranking.
var _last_species_id: String = ""

## Species a News Report has named this session, newest last. SESSION-ONLY — nothing here is
## saved or restored (see Proposals): a reload starts this empty again, which is honest given
## nothing persists it yet, rather than pretending a save-crossing memory that does not exist.
## Exposed so a future Field Guide "hinted at" column (gdd.md -> Objectives & Progression;
## `field_guide.gd`'s own header names this exact gap) has something to read without this file
## changing shape.
var _hinted_species_ids: Dictionary = {}


func _ready() -> void:
	_content_rng.randomize()
	set_process(false)


## Wires this presenter to a live world and the toast it renders through. Safe to call every
## frame the way `GameUI.bind_world()` already does for everything else — a repeat call with
## the same world is a no-op past updating the toast reference.
func bind(world: WorldRoot, toast: NewsReportToast) -> void:
	_toast = toast
	if world == null or world == _world:
		return
	_world = world
	_scheduler = NewsReportScheduler.new()
	_pacer = HintPacer.new()
	_scheduler.set_pacer(_pacer)
	# ARM THE FIRST-HINT ONE-SHOT BEFORE ANYTHING ELSE BELOW CAN CONSUME IT. Operator ruling,
	# 2026-09-08: "For a new game, the first suggested villager build should come even faster
	# than the first 30-60s" — see `HintPacer.FIRST_HINT_SECONDS`. Gated on `is_new_world` only
	# — a loaded save must be completely unaffected.
	#
	# WHY IT HAS TO GO HERE AND NOT AFTER `set_hints_enabled()` BELOW: `set_hints_enabled(false)`
	# itself calls `retire_nudge()`, which calls `_next_cadence()` — the exact call that consumes
	# the one-shot. `GameplaySettings.hints_enabled()` is a GLOBAL setting that outlives any one
	# world, so a player who turned Hints off in a previous session and then starts a BRAND-NEW
	# world still has it off here. Arming after that call would mean the one-shot gets spent by
	# `retire_nudge()`'s cadence roll — on an interval nobody will ever see sped up, since Hints
	# are off — rather than by the real nudge-driven roll in `NewsReportScheduler.advance()` at
	# ~3 s, which is the call this design actually means to speed up. Arming first means that
	# even in this edge case the one-shot survives to fire on the first report the player
	# actually sees, whenever Hints are turned back on.
	#
	# THE OTHER TRAP THIS SAME ORDERING AVOIDS: `retire_nudge()`, called several lines below
	# (only reached for a NON-new world), ALSO calls `_next_cadence()`. Gating the arm call on
	# `is_new_world` — not just placing it early — is what keeps a loaded save from ever
	# touching the pacer's one-shot at all; `_first_hint_armed` starts `false` and nothing here
	# sets it true unless this world is genuinely brand-new.
	if world.is_new_world:
		_pacer.arm_first_hint()
	# BEFORE ANYTHING BELOW CAN ARM AN INTERVAL. Both `set_hints_enabled(false)` and
	# `retire_nudge()` roll `_next_cadence()`, which asks the pacer for a band keyed on the
	# hosted count — and until this call the scheduler's count is still its `0` default. Pushing
	# it only from `_process()` meant a returning save with eight species hosted armed its FIRST
	# interval in the learning band (the shortest one in the game) and only corrected itself
	# after that first report had already fired. One misfire per load is still a misfire on the
	# beat spec.md §11 exists to get right, so the count is now current before the clock starts.
	_push_hosted_count()
	_scheduler.set_hints_enabled(GameplaySettings.hints_enabled())
	if not world.is_new_world:
		# Only a brand-new save gets the first-time nudge (gdd.md -> Player Interface &
		# Controls: "every brand-new save shows one dismissable popup"). A loaded save, or a
		# scene opened directly (tests, F6 in the editor), starts straight into the ambient
		# cadence. `_pacer._first_hint_armed` is still `false` here — the guard above never set
		# it for this world — so this `retire_nudge()`'s own `_next_cadence()` call rolls the
		# ordinary band, exactly as it always has.
		_scheduler.retire_nudge()
	set_process(true)


## The Hints toggle's write path from `SettingsOverlay`. `GameplaySettings` already holds the
## persisted value; this hands the live scheduler the same one so a mid-session flip takes
## effect on the very next `advance()` rather than the next `bind()`.
func set_hints_enabled(enabled: bool) -> void:
	if _scheduler != null:
		_scheduler.set_hints_enabled(enabled)


func hinted_species_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _hinted_species_ids.keys():
		out.append(id)
	return out


## `GameUI` hands the live coach over so the 3-second nudge beat (D-37, unchanged) starts the
## coach rather than firing a toast. ONE HINT AT A TIME: the coach's beat 1 replaces the old
## placeholder nudge toast, it does not accompany it.
func set_coach(coach: OnboardingCoach) -> void:
	_coach = coach


func _process(delta: float) -> void:
	if _scheduler == null or _toast == null:
		return
	if _pacer != null:
		_pacer.advance(delta)
	# OUTSIDE the pacer guard on purpose. The hosted count is the SCHEDULER's input, not the
	# pacer's — nesting the push inside `if _pacer != null` coupled it to an object that has no
	# say in it, so a scheduler running on the D-37 fallback path (or one whose pacer was
	# detached mid-session by `set_pacer(null)`, a supported call) would quietly stop being told
	# how many species are hosted and hand a stale count back the moment a pacer returned.
	_push_hosted_count()
	match _scheduler.advance(delta):
		NewsReportScheduler.EVENT_NUDGE:
			if _coach != null:
				_coach.notice_nudge_due()
		NewsReportScheduler.EVENT_REPORT:
			_fire_report()


## The scheduler's view of how many species are hosted, refreshed from the live world. One
## place, called from both `bind()` and `_process()`, so "the count the cadence is keyed on" can
## never be current in one path and stale in the other.
func _push_hosted_count() -> void:
	if _scheduler == null or _world == null:
		return
	_scheduler.set_hosted_count(_world.species_hosted_count())


## Any placement. Fed from `GameUI`'s existing paint route — the same call site that already
## drives `OnboardingCoach.notice_painted()`, so activity has ONE input path, not two.
func notice_activity() -> void:
	if _pacer != null:
		_pacer.notice_activity()


func built_recently() -> bool:
	return _pacer != null and _pacer.built_recently()


## The next report's text, composed but not shown. Split out of `_fire_report()` so a
## headless suite can read what would be rendered without driving a real toast through a
## real frame.
func compose_next_report() -> String:
	if _world == null or _world.roster == null:
		return ""

	# THE ZERO-FOREST REPORT, AHEAD OF THE ROSTER — the one general (non-species) entry in the
	# pool (`NewsReportContent.NO_FOREST_REPORT`, whose header carries the reasoning). A world
	# with no Forest earns no Wood at all, and Forest is free, so this is the only stalled
	# state in v1 the player cannot read off the HUD.
	#
	# BUT ONLY ONCE THE STOCKPILE HAS RUN DOWN (`LOW_WOOD_FLOOR`; operator ruling, 2026-09-08).
	# No trees is not the same as stuck: a brand-new world holds 100 Wood, several builds'
	# worth, and the feed's job in that first stretch is to point the player at a villager or
	# an animal to build FOR. Reading the live balance is what makes "new game" need no flag,
	# no timer and no saved state — a fresh world keeps this branch shut by itself until the
	# player has actually spent, while a loaded save down at 5 Wood with no trees qualifies on
	# the very next cycle.
	#
	# IT PRE-EMPTS, BUT ONLY EVERY OTHER CYCLE, and the alternation costs no new state: writing
	# `NO_FOREST_ID` into `_last_species_id` makes the existing no-repeat rule do the work.
	# Operator ruling, 2026-09-08. An unconditional pre-empt would replay one identical
	# sentence for as long as the player has no trees, which is exactly what spec.md §10.1
	# rules out — "an idle stretch reads as the world talking about different animals, not as
	# one nag repeated." Alternating still names the problem every other report while the feed
	# stays a feed.
	#
	# `NO_FOREST_ID` matches no roster id, so the cycle AFTER this one filters nothing out and
	# picks from the whole roster as usual. It is deliberately NOT recorded in
	# `_hinted_species_ids`, which means "a species a report has named" and feeds a future
	# Field Guide column.
	if (
		_world.grid != null
		and _world.grid.forest_tile_count() == 0
		and _world.get_wood() < NewsReportContent.LOW_WOOD_FLOOR
		and _last_species_id != NewsReportContent.NO_FOREST_ID
	):
		_last_species_id = NewsReportContent.NO_FOREST_ID
		return NewsReportContent.NO_FOREST_REPORT

	var species: AnimalDefinition = NewsReportContent.pick_species(
		_world.roster.species(), _world.grid, _content_rng, _world, {}, _last_species_id
	)
	if species == null:
		return ""
	var line: String = NewsReportContent.hint_line(species, _world, _content_rng)
	if line.is_empty():
		# `hint_line()`'s own guard: a starter tier with no NEEDS at all composes nothing, and
		# `_fire_report()` correctly shows nothing for it. A species that was never actually
		# named to the player must not be recorded as if it had been — recording it here would
		# both spend a no-repeat cycle (`_last_species_id`) on a report nobody saw and plant a
		# false entry in `_hinted_species_ids`, which is reserved for a future Field Guide
		# "hinted at" column and documents itself as species a report has NAMED.
		return ""
	# Recorded together, in the one place both are known true, so the two can never diverge.
	_last_species_id = species.id
	_hinted_species_ids[species.id] = true
	return line


func _fire_report() -> void:
	var line: String = compose_next_report()
	if not line.is_empty():
		_toast.show_text(line)
