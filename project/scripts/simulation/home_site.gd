class_name HomeSite
extends RefCounted
## One home neighbourhood — a tile position, the species living there, and the radius it
## allocates tiles over.
##
## gdd.md -> Level & world design: "Home sites are tile positions evaluated over the species
## radius; the move-in prop (den, burrow, nest) is decoration ... and a house is a home site
## with a fixed footprint." There is no prop here — that is row 6 depth — and residents
## occupy no tiles.
##
## TWO KINDS, one class:
##   * a **settled** site, created when a resident lands — `species_id` is set;
##   * a **structure** site, created the moment a House is placed — `species_id` is empty
##     until someone settles it, and `structure_tags` holds the building's `emitted_tags`.
##     A structure site exists from placement because buildings.md says a House *is* a home
##     site, and because being in the registry from placement is what makes it the OLDER
##     site in the exclusivity tie-break — which is what stops a villager from settling on a
##     field beside a house instead of in it.
##
## A site is per-species: two species settling the same tile are two sites. That falls out of
## the capacity formula, which is only ever evaluated for a `(home site, species)` pair.

## Grid coordinates of the site.
var position: Vector2i = Vector2i.ZERO

## The species living here, in `AnimalDefinition.id` form. Empty on an unclaimed structure
## site.
var species_id: String = ""

## For a structure site, the building's `emitted_tags`. **Only a species that needs one of
## these tags may claim the site** — otherwise a rabbit could take a House's home site
## simply by qualifying on the grass around it.
var structure_tags: Array[String] = []

## The radius this site allocates tiles over — the species' `scout_radius`, which is the
## radius that picked the site. Capacity counts over `capacity_radius` instead (-> D-27 #1);
## v1's default makes the two equal, and a species that diverges would count acreage over a
## radius wider or narrower than the one it allocates. That is deliberate and expressible;
## nothing in the floor roster does it.
var radius: int = 0

## Monotonic creation order. **This is the tie-break in the exclusivity rule**: where two
## sites are equidistant from a tile, the tile goes to the older site (gdd.md -> Habitat
## Suitability), which is the one with the lower sequence.
var sequence: int = 0

## Instantiated resident nodes. `residents.size()` is `population(h, S)` in the formula.
var residents: Array[Node3D] = []


func _init(
	site_position: Vector2i,
	site_species_id: String,
	site_radius: int,
	site_sequence: int,
	site_structure_tags: Array[String] = []
) -> void:
	position = site_position
	species_id = site_species_id
	radius = site_radius
	sequence = site_sequence
	structure_tags = site_structure_tags


func population() -> int:
	return residents.size()


func is_vacant() -> bool:
	return species_id == ""


func is_structure() -> bool:
	return not structure_tags.is_empty()


## True when this structure's tags satisfy one of the species' habitat needs — i.e. this
## building is a home *for that species*.
func serves(species: AnimalDefinition) -> bool:
	if species == null or structure_tags.is_empty():
		return false
	for tag: String in species.habitat_needs:
		if structure_tags.has(tag):
			return true
	return false


## Squared tile distance. Squared so the exclusivity comparison stays integer — no sqrt in
## the hot path, and no float ties that should have been exact.
func distance_squared_to(tile: Vector2i) -> int:
	var d: Vector2i = tile - position
	return d.x * d.x + d.y * d.y


func covers(tile: Vector2i) -> bool:
	return distance_squared_to(tile) <= radius * radius
