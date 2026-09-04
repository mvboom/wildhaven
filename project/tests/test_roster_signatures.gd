extends QATestCase
## THE DISTINCTNESS GUARANTEE. Fifteen species, fifteen distinct habitat signatures —
## the defect this whole design exists to fix was four species sharing one recipe
## (`open_grass, cultivated` on Horse, Cow, Bull and Alpaca alike).
##
## FIFTEEN, NOT SIXTEEN: the design's own spec table (§9) lists Chicken, but no
## `AnimalDefinition` exists for it — the asset was never purchased (see roster.md).
## `project/data/animals/` carries exactly fifteen `.tres` files. Chicken's row is
## skipped; `coop` (emitted by ChickenCoop) has no consuming species yet, same as the
## already-dormant `sand` tag.
##
## This suite asserts STRUCTURE, not tuning: that signatures differ, that categories are
## coherent, that the graph is acyclic. Individual divisors are the human's and may move
## freely without touching this file.
##
## Run:
##   bash scripts/run-tests.sh roster_signatures

func _init() -> void:
	begin("roster signatures")
	var roster: Array[AnimalDefinition] = _load_roster()
	check(roster.size() >= 15, "the roster has at least fifteen species (found %d)" % roster.size())
	_check_all_validate(roster)
	_check_signatures_are_distinct(roster)
	_check_categories(roster)
	_check_emitters(roster)
	_check_graph_acyclic(roster)
	finish()


func _check_all_validate(roster: Array[AnimalDefinition]) -> void:
	var ids: PackedStringArray = []
	for def: AnimalDefinition in roster:
		ids.append(def.id)
	for def: AnimalDefinition in roster:
		var problems: Array[String] = def.validate(ids)
		check(problems.is_empty(), "\"%s\" validates clean" % def.id, "\n        ".join(problems))


## The whole point of the design, asserted directly.
func _check_signatures_are_distinct(roster: Array[AnimalDefinition]) -> void:
	var seen: Dictionary = {}
	for def: AnimalDefinition in roster:
		var signature: String = _signature(def)
		if seen.has(signature):
			check(false, "\"%s\" has a distinct signature" % def.id,
				"identical to \"%s\": %s" % [seen[signature], signature])
		else:
			seen[signature] = def.id
			check(true, "\"%s\" has a distinct signature" % def.id)


func _check_categories(roster: Array[AnimalDefinition]) -> void:
	for def: AnimalDefinition in roster:
		check(
			def.category() != "",
			"\"%s\" matches a design category" % def.id,
			"neither person, wild, nor domesticated"
		)


func _check_emitters(roster: Array[AnimalDefinition]) -> void:
	var emitters: Dictionary = {}
	for def: AnimalDefinition in roster:
		for tag: String in def.emits_tags:
			emitters[tag] = def.id
	check_eq(emitters.get("people", ""), "human", "the villager is what emits `people`")
	check_eq(emitters.get("deer", ""), "deer", "the deer is what emits `deer`")
	check_eq(emitters.size(), 2, "exactly two species emit anything")


func _check_graph_acyclic(roster: Array[AnimalDefinition]) -> void:
	var cycle: Array[String] = HabitatGraph.find_cycle(roster)
	check(cycle.is_empty(), "the shipped dependency graph is acyclic", str(cycle))


## A canonical, order-independent string form of a species' habitat requirements.
func _signature(def: AnimalDefinition) -> String:
	var parts: Array[String] = []
	for tier: HabitatTier in def.effective_tiers():
		var tier_parts: Array[String] = []
		for need: HabitatNeed in tier.needs:
			tier_parts.append("%s/%d@%d" % [need.tag, need.tiles_per_individual, need.radius])
		for limit: HabitatLimit in tier.limits:
			tier_parts.append("!%s<=%d@%d" % [limit.tag, limit.max_count, limit.radius])
		tier_parts.sort()
		parts.append("|".join(tier_parts))
	parts.sort()
	return "//".join(parts)


func _load_roster() -> Array[AnimalDefinition]:
	var found: Array[AnimalDefinition] = []
	for path: String in _tres_paths("res://data/animals"):
		var res: Resource = load(path)
		if res is AnimalDefinition:
			found.append(res as AnimalDefinition)
	return found


func _tres_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			paths.append_array(_tres_paths("%s/%s" % [dir_path, entry]))
		elif entry.ends_with(".tres"):
			paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return paths
