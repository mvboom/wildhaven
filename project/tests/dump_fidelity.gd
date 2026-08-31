extends SceneTree
## Prints one asset's runtime manifest as JSON, so Python can consume it.
## The wrapper path comes from WILDHAVEN_WRAPPER; markers fence the payload because
## Godot writes its own banner to stdout.
##
## Run:
##   WILDHAVEN_WRAPPER=res://assets/animals/sheep/Sheep.tscn \
##     $GODOT_PATH --headless --path project --script res://tests/dump_fidelity.gd

func _initialize() -> void:
	var path: String = OS.get_environment("WILDHAVEN_WRAPPER")
	if path.is_empty():
		push_error("WILDHAVEN_WRAPPER is not set")
		quit(2)
		return
	print("<<<MANIFEST>>>" + JSON.stringify(FidelityProbe.probe(path)) + "<<<END>>>")
	quit(0)
