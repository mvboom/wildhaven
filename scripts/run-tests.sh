#!/usr/bin/env bash
#
# Wildhaven headless test runner.
#
# Usage:
#   bash scripts/run-tests.sh              # every suite
#   bash scripts/run-tests.sh rabbit       # only suites whose filename contains "rabbit"
#   bash scripts/run-tests.sh -q           # quiet: summary lines only, full output on failure
#
# Exit code is 0 only when every suite passes, so this is usable as a gate. A suite is
# also failed if its output contains a bare "SCRIPT ERROR" even when it exits 0 — see
# the comment above that check for why.
#
# WHY A SHELL LOOP AND NOT A GDSCRIPT AGGREGATOR:
#   project/tests/qa_test_case.gd is `class_name QATestCase extends SceneTree`, so every
#   test IS a SceneTree. A second SceneTree cannot be instantiated from inside a running
#   one, so an in-engine runner would mean refactoring QATestCase off SceneTree and
#   touching all ~29 test files. Not worth it. One process per suite costs ~1.5-3s, so a
#   full run is ~45-90s: fine as a gate, too slow for a tight edit loop — hence the filter.
#
# WHY `--import` RUNS FIRST:
#   `--headless --path project --quit` is a PARSE check only. It does not import, so a
#   `--script` run cannot resolve a newly added `class_name` and reports false green.
#   See gdd.md -> Technical Strategy #2 and qa_test_case.gd's header note.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
TESTS_DIR="$PROJECT_DIR/tests"
GODOT="${GODOT_PATH:-$REPO_ROOT/godot/Godot_v4.7-stable_mono_linux.x86_64}"

QUIET=0
FILTER=""
for arg in "$@"; do
	case "$arg" in
		-q|--quiet) QUIET=1 ;;
		-h|--help) sed -n '3,10p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
		*) FILTER="$arg" ;;
	esac
done

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot binary not found or not executable: $GODOT" >&2
	echo "       Set GODOT_PATH, or check godot/ for the engine binary." >&2
	exit 2
fi

# --- Import pass (once) -------------------------------------------------------
echo "==> Importing project (registers class_name, rebuilds import cache)"
IMPORT_LOG="$("$GODOT" --headless --path "$PROJECT_DIR" --import 2>&1)"
IMPORT_RC=$?
if [[ $IMPORT_RC -ne 0 ]]; then
	echo "ERROR: import pass failed (exit $IMPORT_RC). Every suite below would report" >&2
	echo "       false results, so stopping here." >&2
	echo "$IMPORT_LOG" >&2
	exit 2
fi

# --- Collect suites -----------------------------------------------------------
mapfile -t SUITES < <(find "$TESTS_DIR" -maxdepth 1 -name 'test_*.gd' -type f | sort)

if [[ -n "$FILTER" ]]; then
	mapfile -t SUITES < <(printf '%s\n' "${SUITES[@]}" | grep -- "$FILTER" || true)
fi

if [[ ${#SUITES[@]} -eq 0 ]]; then
	if [[ -n "$FILTER" ]]; then
		echo "No suites matched filter: $FILTER" >&2
	else
		echo "No test_*.gd files found in $TESTS_DIR" >&2
	fi
	exit 2
fi

# --- Run ----------------------------------------------------------------------
echo "==> Running ${#SUITES[@]} suite(s)"
echo

PASSED=0
FAILED=0
FAILED_NAMES=()

for suite_path in "${SUITES[@]}"; do
	name="$(basename "$suite_path" .gd)"
	out="$("$GODOT" --headless --path "$PROJECT_DIR" --script "res://tests/$name.gd" 2>&1)"
	rc=$?

	# A recoverable GDScript runtime error (bad `as` cast, null dereference,
	# out-of-bounds index) inside a helper called from a test's _initialize()/_process()
	# does not raise the exit code: the engine prints "SCRIPT ERROR: ...", unwinds only
	# the enclosing function, and hands control back to the caller. Any check()/check_eq()
	# calls after that point in the helper simply never run. QATestCase.finish() derives
	# the exit code solely from the `_failed` counter, which those skipped checks never
	# touched, so the process still quits 0 and this loop would otherwise call it a PASS
	# while assertions silently vanished. Grepping the captured output for the literal
	# marker the engine prints on this path closes that hole without touching
	# qa_test_case.gd or the ~20 suites exposed to it.
	#
	# Match "SCRIPT ERROR" specifically, not a bare "ERROR": legitimate test paths call
	# push_error() on purpose (a save refusing a future save_version, an unknown building
	# id being skipped) and those lines print "ERROR"/"USER ERROR" without ever being a
	# sign anything was skipped. Matching on bare "ERROR" would turn those into false reds.
	script_error=0
	if [[ "$out" == *"SCRIPT ERROR"* ]]; then
		script_error=1
	fi

	if [[ $rc -eq 0 && $script_error -eq 0 ]]; then
		PASSED=$((PASSED + 1))
		printf '  PASS  %s\n' "$name"
		[[ $QUIET -eq 0 ]] && printf '%s\n' "$out" | sed 's/^/        /'
	elif [[ $rc -eq 0 && $script_error -eq 1 ]]; then
		FAILED=$((FAILED + 1))
		FAILED_NAMES+=("$name")
		printf '  FAIL  %s (SCRIPT ERROR in output — assertions may have been silently skipped)\n' "$name"
		# Always show output for a failure, even in quiet mode — that is the whole point.
		printf '%s\n' "$out" | sed 's/^/        /'
	else
		FAILED=$((FAILED + 1))
		FAILED_NAMES+=("$name")
		printf '  FAIL  %s (exit %d)\n' "$name" "$rc"
		# Always show output for a failure, even in quiet mode — that is the whole point.
		printf '%s\n' "$out" | sed 's/^/        /'
	fi
done

# --- Summary ------------------------------------------------------------------
echo
echo "================================================================"
printf 'Suites: %d total, %d passed, %d failed\n' "${#SUITES[@]}" "$PASSED" "$FAILED"
if [[ $FAILED -gt 0 ]]; then
	echo "Failed suites:"
	for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
	echo "================================================================"
	exit 1
fi
echo "================================================================"
exit 0
