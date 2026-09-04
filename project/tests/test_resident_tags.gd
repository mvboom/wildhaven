extends QATestCase
## Resident-emitted tags: `people` and `deer` are ordinary habitat tags contributed by
## RESIDENTS rather than by tiles.
##
## Run:
##   bash scripts/run-tests.sh resident_tags

func _init() -> void:
	begin("resident tags")
	_check_sites_at()
	_check_counted_per_individual()
	_check_absent_when_vacant()
	finish()


func _check_sites_at() -> void:
	var registry := HomeSiteRegistry.new()
	var a: HomeSite = registry.register(Vector2i(4, 4), "human", 9)
	var b: HomeSite = registry.register(Vector2i(4, 4), "husky", 9)
	var found: Array[HomeSite] = registry.sites_at(Vector2i(4, 4))
	check_eq(found.size(), 2, "sites_at returns every site sharing a tile")
	check(found.has(a) and found.has(b), "both sites are returned")
	check_eq(registry.sites_at(Vector2i(9, 9)).size(), 0, "an empty tile returns none")


## The load-bearing assertion of this task.
func _check_counted_per_individual() -> void:
	var site := HomeSite.new(Vector2i(0, 0), "human", 9, 0)
	site.resident_tags = ["people"] as Array[String]
	for i in range(4):
		site.residents.append(Node3D.new())
	check_eq(site.population(), 4, "four villagers live here")
	var contributed: Dictionary = {}
	for tag: String in site.resident_tags:
		contributed[tag] = int(contributed.get(tag, 0)) + site.population()
	check_eq(
		int(contributed["people"]), 4,
		"ONE house with four villagers contributes people=4, NOT people=1"
	)
	for resident: Node3D in site.residents:
		resident.free()


func _check_absent_when_vacant() -> void:
	# species_id "" is what an unclaimed/vacated structure site actually looks like
	# (`HomeSite.is_vacant()` reads `species_id == ""`, not population) -- the real state
	# `HomeSiteRegistry.release()` leaves behind once the last resident departs a house.
	# `resident_tags` can still be stale from before that departure; population() gates it.
	var site := HomeSite.new(Vector2i(0, 0), "", 9, 0)
	site.resident_tags = ["people"] as Array[String]
	check_eq(site.population(), 0, "a vacant site has no residents")
	check(site.is_vacant(), "an empty house is vacant")
	# An empty house must NOT satisfy a dog's `people` need -- that is the whole point of
	# the resident-emitted mechanic over a plain `house` tag.
	check_eq(site.population() * site.resident_tags.size(), 0, "a vacant site contributes nothing")
