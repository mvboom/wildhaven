extends Node
## THROWAWAY VISUAL POC for docs/superpowers/specs/2026-08-23-notification-surfaces-design.md.
## Not part of the shipped game flow — a human runs this scene directly to eyeball spacing,
## sizing, and motion before any real signal wiring changes land (Tasks 3-5 of
## docs/superpowers/plans/2026-08-23-notification-surfaces.md). Safe to delete once the human
## has signed off, or keep as a permanent debug harness — the human's call.
##
## Controls:
##   1 — add one fact-card-shaped entry
##   2 — add one displacement-warning-shaped entry (two affected families)
##   3 — add a BURST: three of each at once, back to back — the exact case ("a TON of popups
##       when animals come and go") this whole redesign exists to fix

@onready var _feed: NotificationFeed = %NotificationFeed

var _counter: int = 0


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key: InputEventKey = event as InputEventKey
	if key.keycode == KEY_1:
		_add_fact()
	elif key.keycode == KEY_2:
		_add_warning()
	elif key.keycode == KEY_3:
		for i: int in range(3):
			_add_fact()
			_add_warning()


func _add_fact() -> void:
	_counter += 1
	_feed.show_fact(
		"Fox",
		"Foxes have excellent hearing and can rotate their ears toward quiet sounds. (#%d)" % _counter
	)


func _add_warning() -> void:
	_counter += 1
	_feed.show_warning({
		"mode": DisplacementCopy.MODE_BUILD,
		"homes": [
			{"species_id": "rabbit", "display_name": "Rabbit", "is_structure_home": false, "binding_need": ""},
			{"species_id": "fox", "display_name": "Fox", "is_structure_home": false, "binding_need": ""},
		],
	})
