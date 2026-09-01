#!/usr/bin/env bash
#
# Wildhaven tag-economy report — the scoreboard for the roster/tag retune.
#
# Usage:
#   bash scripts/habitat-report.sh
#
# Prints tag sources, sourced-but-unwanted tags, inert buildables, and recipe collisions.
# ALWAYS exits 0: this is a report, never a gate. The hard gate is
# project/tests/test_field_guide_reachability.gd, run by scripts/run-tests.sh.
#
# `--import` runs first for the same reason run-tests.sh does it: a bare --script run cannot
# resolve a newly added `class_name` and reports false green.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
GODOT="${GODOT_PATH:-$REPO_ROOT/godot/Godot_v4.7-stable_mono_linux.x86_64}"

if [[ ! -x "$GODOT" ]]; then
	echo "ERROR: Godot binary not found or not executable: $GODOT" >&2
	echo "       Set GODOT_PATH, or check godot/ for the engine binary." >&2
	exit 2
fi

"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1
"$GODOT" --headless --path "$PROJECT_DIR" --script res://tests/habitat_report.gd

exit 0
