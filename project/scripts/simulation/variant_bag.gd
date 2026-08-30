class_name VariantBag
extends RefCounted
## Per-species SHUFFLE BAG over `AnimalDefinition.model_scenes` indices — the thing that
## decides which look a newly arrived resident wears.
##
## WHY A BAG AND NOT A ROLL. The human's stated requirement is "every villager look should
## appear before any look repeats". An independent `randi() % 18` per villager does not do
## that: by the birthday problem a repeat is more likely than not by the 6th villager. A bag
## deals out a shuffled permutation of `0 .. count-1` and only reshuffles once it is empty,
## so with 18 looks the 18th villager is the first that CAN repeat anything.
##
## WHY IT IS NOT A HASH OF THE RESIDENT'S INDEX (the bug this replaces). `pick_variant(index)`
## was keyed on a resident's slot within its OWN home site's `residents` array, which is not a
## global identity — the first resident at every home site in the world hashed to the same
## variant, so with home sites typically holding one or two residents nearly every villager in
## the world wore variant 15. See `AnimalDefinition.legacy_variant_index()`, which keeps that
## derivation alive for exactly one purpose: reading saves written before the fix.
##
## THIS OBJECT IS NOT SAVED, AND DOES NOT NEED TO BE. What a resident wears is persisted per
## resident (`WorldSnapshot`'s 4th element of a `residents` entry), so a load reproduces looks
## from the file rather than by replaying the bag. `consume()` exists only so the bag a loaded
## world carries on with is aware of the looks already standing in it.
##
## ONE BAG PER SIMULATION, not one global bag: `HabitatSimulation` owns the instance, so two
## worlds open at once (a test's `probe` world beside its `source` world) do not deal from each
## other's bag.

## The "no variant" sentinel, shared with `AnimalDefinition.NO_VARIANT`. Returned when a
## species has no `model_scenes` at all — a content defect the caller reports, not a value
## this class should invent an index for.
const NO_VARIANT: int = -1

## RNG kept per instance rather than reaching for `Array.shuffle()`, which draws from the
## engine's global RNG: a seeded instance is what lets a test assert the permutation property
## instead of the distribution of a global stream.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## species_id -> {"count": int, "queue": Array[int], "last": int}. `queue` is consumed from
## the BACK (`pop_back` is O(1); the order is already random, so which end is arbitrary).
var _bags: Dictionary = {}


func _init(rng_seed: int = 0) -> void:
	if rng_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = rng_seed


## The next look for a `species_id` whose `model_scenes` holds `variant_count` entries.
##
## Returns `NO_VARIANT` for a species with no models at all, and always `0` for a
## single-variant species (most of the roster) — no bag is allocated in either case.
##
## A `variant_count` that no longer matches the bag's is treated as a new species pool and
## starts a fresh bag: a `.tres` gaining or losing a look mid-session must not deal an index
## that is now out of range.
func next(species_id: String, variant_count: int) -> int:
	if variant_count <= 0:
		return NO_VARIANT
	if variant_count == 1:
		return 0

	var state: Dictionary = _state_for(species_id, variant_count)
	var queue: Array = state["queue"] as Array
	if queue.is_empty():
		queue = _fresh_bag(variant_count, int(state["last"]))
		state["queue"] = queue

	var picked: int = int(queue.pop_back())
	state["last"] = picked
	return picked


## Marks `variant_index` as already spent for this species WITHOUT dealing a new look.
##
## Called once per restored resident at load. The persisted look is used verbatim (that is the
## whole point of persisting it); this only stops the bag from immediately dealing a look that
## is already standing in the loaded world, which would read as a repeat to the player even
## though no bag rule was broken. A no-op when the index is not in the current bag.
func consume(species_id: String, variant_count: int, variant_index: int) -> void:
	if variant_count <= 1 or variant_index < 0 or variant_index >= variant_count:
		return
	var state: Dictionary = _state_for(species_id, variant_count)
	var queue: Array = state["queue"] as Array
	if queue.is_empty():
		queue = _fresh_bag(variant_count, int(state["last"]))
		state["queue"] = queue
	var at: int = queue.find(variant_index)
	if at >= 0:
		queue.remove_at(at)


## How many looks are left in this species' current bag. Introspection for tests; no
## simulation code should branch on it.
func remaining(species_id: String) -> int:
	if not _bags.has(species_id):
		return 0
	return ((_bags[species_id] as Dictionary)["queue"] as Array).size()


## Drops every bag. Used by a test that wants a known starting state; nothing in the game
## calls it.
func reset() -> void:
	_bags.clear()


## Pins the RNG and drops every bag, so a suite can assert the permutation property against a
## reproducible stream. Test-only; the game never seeds this — a villager's look is meant to
## vary between worlds.
func set_rng_seed(value: int) -> void:
	_rng.seed = value
	_bags.clear()


func _state_for(species_id: String, variant_count: int) -> Dictionary:
	var state: Dictionary = _bags.get(species_id, {}) as Dictionary
	if state.is_empty() or int(state["count"]) != variant_count:
		state = {"count": variant_count, "queue": [] as Array, "last": NO_VARIANT}
		_bags[species_id] = state
	return state


## A freshly shuffled permutation of `0 .. count-1`.
##
## THE SEAM RULE — the conservative option, and a PROPOSAL not a decision. Where one bag runs
## out and the next begins, nothing in a plain reshuffle stops the last look of the old bag
## being the first look of the new one, which is the one repeat a player would actually notice
## (two villagers in a row wearing the same thing). The last element — the one `pop_back()`
## takes first — is therefore swapped away from the previously dealt index. This is the
## strictest reading of "every look appears before any look repeats"; the looser reading
## (reshuffle blind, accept the seam collision) is a legitimate alternative and is the human's
## call, not this file's.
func _fresh_bag(count: int, last: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(i)
	_shuffle(out)
	if count > 1 and last != NO_VARIANT and int(out[count - 1]) == last:
		var swap_with: int = _rng.randi_range(0, count - 2)
		var held: int = int(out[count - 1])
		out[count - 1] = out[swap_with]
		out[swap_with] = held
	return out


## Fisher-Yates against this instance's RNG. `Array.shuffle()` would use the global one, which
## a test cannot pin without disturbing every other system drawing from it.
func _shuffle(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var held: Variant = values[i]
		values[i] = values[j]
		values[j] = held
