class_name HabitatGraph
extends RefCounted
## The acyclicity check over resident-emitted tags.
##
## Two real edges ship: `human -> people -> {pug, shiba_inu, husky, pig, sheep}` and
## `deer -> deer -> stag`. Neither closes a loop. This check exists so the THIRD one added
## does not: a cycle makes capacity oscillate forever across the dirty queue, because each
## species' arrival re-marks the neighbourhood dirty, which re-evaluates the other, which
## arrives, which re-marks... It is the one genuinely new failure mode tiers introduce.


## Species ids participating in a dependency cycle, or an empty array when the graph is
## acyclic. Ids are returned unsorted; callers use only emptiness and the names.
static func find_cycle(species: Array[AnimalDefinition]) -> Array[String]:
	# tag -> ids of species that EMIT it
	var emitters: Dictionary = {}
	for def: AnimalDefinition in species:
		if def == null:
			continue
		for tag: String in def.emits_tags:
			if not emitters.has(tag):
				emitters[tag] = [] as Array[String]
			(emitters[tag] as Array[String]).append(def.id)

	# id -> ids it depends on (it needs a tag they emit)
	var edges: Dictionary = {}
	for def: AnimalDefinition in species:
		if def == null:
			continue
		var depends_on: Array[String] = []
		for tier: HabitatTier in def.effective_tiers():
			for need: HabitatNeed in tier.needs:
				if not emitters.has(need.tag):
					continue
				for emitter_id: String in emitters[need.tag] as Array[String]:
					# Self-emission (deer needing `deer`) is a POPULATION THRESHOLD, not a
					# cycle: more deer make more deer possible, which terminates because
					# deer also need finite land. Only cross-species loops diverge.
					if emitter_id != def.id and not depends_on.has(emitter_id):
						depends_on.append(emitter_id)
		edges[def.id] = depends_on

	var offenders: Array[String] = []
	var permanent: Dictionary = {}
	var in_stack: Dictionary = {}
	for def: AnimalDefinition in species:
		if def == null or permanent.has(def.id):
			continue
		_visit(def.id, edges, permanent, in_stack, offenders)
	return offenders


## Depth-first visit. A node reached while already on the stack closes a cycle.
static func _visit(
	id: String,
	edges: Dictionary,
	permanent: Dictionary,
	in_stack: Dictionary,
	offenders: Array[String]
) -> void:
	if permanent.has(id):
		return
	if in_stack.has(id):
		if not offenders.has(id):
			offenders.append(id)
		return
	in_stack[id] = true
	for next_id: String in edges.get(id, [] as Array[String]) as Array[String]:
		_visit(next_id, edges, permanent, in_stack, offenders)
	in_stack.erase(id)
	permanent[id] = true
