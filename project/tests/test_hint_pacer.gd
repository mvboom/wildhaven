extends QATestCase
## The cadence half of the News Report build-hint design — how OFTEN a hint fires, never
## whether one may. The Hints toggle stays enforced in `NewsReportScheduler.advance()`;
## nothing here can fire an event.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_hint_pacer.gd


func _initialize() -> void:
	begin("hint pacer")
	_check_bands_widen_as_species_are_hosted()
	_check_activity_halves_and_idleness_doubles()
	_check_the_idle_boost_cannot_compound()
	_check_activity_expires()
	finish()


## The decay driver is hosted count, ruled 2026-09-08: a returning player picks up where they
## left off (it round-trips through `world_snapshot.gd` already), and the fade ties to the
## thing the hints teach — once you can attract animals you stop being told how.
func _check_bands_widen_as_species_are_hosted() -> void:
	var pacer := HintPacer.new()
	var zero: float = pacer.next_interval(0)
	var few: float = pacer.next_interval(2)
	var some: float = pacer.next_interval(4)
	var many: float = pacer.next_interval(9)
	check(zero < few, "0 hosted is more frequent than 2 (%.0f < %.0f)" % [zero, few])
	check(few < some, "2 hosted is more frequent than 4 (%.0f < %.0f)" % [few, some])
	check(some < many, "4 hosted is more frequent than 9 (%.0f < %.0f)" % [some, many])
	check_eq(pacer.next_interval(-1), zero,
		"a nonsense negative count is treated as the learning band, never as an error")


## Exactly one multiplier always applies — "built recently" and "idle" are two sides of one
## predicate, never summed. See the spec's §9 note.
func _check_activity_halves_and_idleness_doubles() -> void:
	var idle := HintPacer.new()
	var idle_interval: float = idle.next_interval(0)

	var busy := HintPacer.new()
	busy.notice_activity()
	var busy_interval: float = busy.next_interval(0)

	check(busy_interval < idle_interval,
		"a player who just built waits less for the next hint (%.0f < %.0f)"
		% [busy_interval, idle_interval])
	check(is_equal_approx(idle_interval / busy_interval, 4.0),
		"the two multipliers are x2.0 and x0.5, so idle is 4x busy: got %.2f"
		% (idle_interval / busy_interval))


## PILLAR 1 GUARD. gdd.md: "hints never expire or repeat with urgency." The idle multiplier
## makes the game louder the longer a player does not act, which brushes that line; it was
## accepted with the mitigation that it is applied ONCE and cannot stack toward an
## arbitrarily fast rate. A pacer left idle for an hour must pace exactly like one left idle
## for one tick.
func _check_the_idle_boost_cannot_compound() -> void:
	var brief := HintPacer.new()
	brief.advance(1.0)
	var long := HintPacer.new()
	long.advance(3600.0)
	check_eq(long.next_interval(0), brief.next_interval(0),
		"an hour of idleness paces identically to a moment of it")


## The built-recently window is a window, not a latch.
func _check_activity_expires() -> void:
	var pacer := HintPacer.new()
	pacer.notice_activity()
	check(pacer.built_recently(), "a placement marks the player as building")
	pacer.advance(HintPacer.BUILT_RECENTLY_SECONDS + 1.0)
	check(not pacer.built_recently(),
		"...and that lapses once the window passes, without a second placement")
