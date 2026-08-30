class_name QATestCase
extends SceneTree
## Minimal headless test base for Wildhaven QA scripts.
##
## Run with:
##   $GODOT_PATH --headless --path project --script res://tests/<test>.gd
##
## NOTE: `--headless --path ... --quit` is a PARSE check only. It does NOT import.
## After adding or changing any script that declares a `class_name`, run
##   $GODOT_PATH --headless --path project --import
## first, or `--script` runs will fail to resolve the new global class.
##
## Exit code is 0 only when every assertion passed; 1 otherwise, so these are usable
## as CI gates.

var _passed: int = 0
var _failed: int = 0
var _suite: String = "suite"


func begin(suite_name: String) -> void:
	_suite = suite_name
	print("=== %s ===" % _suite)


func check(condition: bool, label: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
		if detail != "":
			print("        %s" % detail)
	return condition


func check_eq(actual: Variant, expected: Variant, label: String) -> bool:
	return check(
		actual == expected,
		label,
		"expected %s (%s), got %s (%s)" % [
			expected, type_string(typeof(expected)), actual, type_string(typeof(actual))
		]
	)


## Reports a known-pending condition. Never affects the exit code — it exists so an
## intentional placeholder is visible in the log without being counted as a defect.
func note_expected_pending(label: String, detail: String = "") -> void:
	print("  PEND  %s" % label)
	if detail != "":
		print("        %s" % detail)


func finish() -> void:
	print("--- %s: %d passed, %d failed ---" % [_suite, _passed, _failed])
	if _failed > 0:
		printerr("%s FAILED (%d assertion(s))" % [_suite, _failed])
		quit(1)
	else:
		print("%s OK" % _suite)
		quit(0)
