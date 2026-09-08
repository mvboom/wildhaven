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
	_check_band_boundaries()
	_check_idleness_shortens_and_activity_lengthens_the_interval()
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


## Boundary coverage for `EARLY_MAX_HOSTED` and `SETTLED_MAX_HOSTED` — the widening check above
## only samples 0, 2, 4, 9, which cannot catch a `<` vs `<=` transposition at the boundaries
## themselves. Exercised on freshly-constructed pacers, where the multiplier is always
## `IDLE_MULTIPLIER` (a fresh pacer starts NOT "built recently" — see `_since_activity`'s
## initial value), which isolates the band choice from the activity multiplier.
func _check_band_boundaries() -> void:
	var expected_band_by_hosted_count := {
		0: HintPacer.BAND_LEARNING,
		1: HintPacer.BAND_EARLY,
		2: HintPacer.BAND_EARLY,
		3: HintPacer.BAND_SETTLED,
		4: HintPacer.BAND_SETTLED,
		5: HintPacer.BAND_SETTLED,
		6: HintPacer.BAND_RARE,
	}
	for hosted_count in expected_band_by_hosted_count:
		var band: float = expected_band_by_hosted_count[hosted_count]
		var pacer := HintPacer.new()
		check_eq(pacer.next_interval(hosted_count), band * HintPacer.IDLE_MULTIPLIER,
			"hosted_count %d maps to the %.0f s band" % [hosted_count, band])


## Corrected 2026-09-08 against the operator's stated requirement: "if they are not building,
## we show more hints; if they are we show less often." A stuck/idle player gets the SHORTER
## interval (more frequent hints, since they're the one the feature exists to help); an
## engaged player who just placed something gets the LONGER interval (left alone). Exactly
## one multiplier always applies — "built recently" and "idle" are two sides of one
## predicate, never summed. See spec §9/§10.1.
func _check_idleness_shortens_and_activity_lengthens_the_interval() -> void:
	var idle := HintPacer.new()
	var idle_interval: float = idle.next_interval(0)

	var busy := HintPacer.new()
	busy.notice_activity()
	var busy_interval: float = busy.next_interval(0)

	check(idle_interval < busy_interval,
		"a player who has NOT built recently is offered the next hint sooner (%.0f < %.0f)"
		% [idle_interval, busy_interval])
	check(is_equal_approx(busy_interval / idle_interval, 4.0),
		"the two multipliers are x0.5 (idle) and x2.0 (built recently), so an engaged player "
		+ "waits 4x longer than an idle one: got %.2f" % (busy_interval / idle_interval))


## PILLAR 1 GUARD. gdd.md: "hints never expire or repeat with urgency." spec §10.1: "the idle
## boost is capped, not compounding — it multiplies the band once and cannot stack toward an
## arbitrarily fast rate." That guarantee lives in `next_interval()`'s exclusive multiplier
## selection, not in the `advance()` clamp (a clamped-vs-unclamped `_since_activity` is
## unobservable through `built_recently()` once past the window, which is why a bare
## fresh-vs-idle comparison does not exercise it). So this drives varied interleavings of
## `notice_activity()` / `advance()` — long idle, repeated activity, activity immediately
## followed by a long idle — and asserts the result is ALWAYS exactly one of the two fixed
## outcomes, never a third value a compounding bug would produce.
func _check_the_idle_boost_cannot_compound() -> void:
	var scenarios: Array[HintPacer] = []

	var untouched := HintPacer.new()
	scenarios.append(untouched)

	var brief_idle := HintPacer.new()
	brief_idle.advance(1.0)
	scenarios.append(brief_idle)

	var long_idle := HintPacer.new()
	long_idle.advance(3600.0)
	scenarios.append(long_idle)

	var repeated_activity := HintPacer.new()
	for _i in range(20):
		repeated_activity.notice_activity()
		repeated_activity.advance(0.5)
	scenarios.append(repeated_activity)

	var active_then_long_idle := HintPacer.new()
	active_then_long_idle.notice_activity()
	active_then_long_idle.advance(7200.0)
	scenarios.append(active_then_long_idle)

	var interleaved := HintPacer.new()
	interleaved.advance(3600.0)
	interleaved.notice_activity()
	interleaved.advance(3600.0)
	interleaved.notice_activity()
	interleaved.advance(1.0)
	scenarios.append(interleaved)

	for hosted_count in [0, 1, 2, 3, 4, 5, 6, 9]:
		var band: float = _expected_band(hosted_count)
		var busy_outcome: float = band * HintPacer.BUILT_RECENTLY_MULTIPLIER
		var idle_outcome: float = band * HintPacer.IDLE_MULTIPLIER
		for pacer in scenarios:
			var interval: float = pacer.next_interval(hosted_count)
			check(is_equal_approx(interval, busy_outcome) or is_equal_approx(interval, idle_outcome),
				"next_interval(%d) is exactly band*%.1f or band*%.1f, never a third value (got %.2f)"
				% [hosted_count, HintPacer.BUILT_RECENTLY_MULTIPLIER, HintPacer.IDLE_MULTIPLIER,
					interval])


func _expected_band(hosted_count: int) -> float:
	if hosted_count <= 0:
		return HintPacer.BAND_LEARNING
	elif hosted_count <= HintPacer.EARLY_MAX_HOSTED:
		return HintPacer.BAND_EARLY
	elif hosted_count <= HintPacer.SETTLED_MAX_HOSTED:
		return HintPacer.BAND_SETTLED
	return HintPacer.BAND_RARE


## The built-recently window is a window, not a latch.
func _check_activity_expires() -> void:
	var pacer := HintPacer.new()
	pacer.notice_activity()
	check(pacer.built_recently(), "a placement marks the player as building")
	pacer.advance(HintPacer.BUILT_RECENTLY_SECONDS + 1.0)
	check(not pacer.built_recently(),
		"...and that lapses once the window passes, without a second placement")
