#!/usr/bin/env bash
#
# Wildhaven build command — produces a real, runnable build for one target.
#
# Usage:
#   bash scripts/build-game.sh <target> [debug|release]
#
# Targets:
#   desktop           Linux desktop binary (godot/Godot_v4.7-stable_mono_linux.x86_64)
#   web-threaded      Web/HTML5, thread_support=true  (needs COOP/COEP to run — see
#                      scripts/serve-web-build.py)
#   web-singlethread  Web/HTML5, thread_support=false (no special headers needed to run)
#
# [debug|release] defaults to debug (faster export, matches this project's own
# --export-debug convention elsewhere). Release is what actually matters for a real
# performance read, since debug export can behave differently under WASM.
#
# Each target's engine binary + export preset name + output location live in their own
# config file under scripts/build-configs/<target>.env — edit those to tweak a target's
# settings without touching this script. Godot-level settings for each target (thread
# support, texture compression, etc.) live in project/export_presets.cfg's own per-target
# preset, exactly as Godot's own export system expects.
#
# WHY DIFFERENT TARGETS USE DIFFERENT ENGINE BINARIES: Godot 4's Mono/.NET editor cannot
# export to Web at all (a hard engine limitation — confirmed directly: "Exporting to Web is
# currently not supported in Godot 4 when using C#/.NET"). This project is pure GDScript, so
# the standard (non-Mono) editor exports it identically for every platform it's needed for;
# each target's own .env file says which binary it needs, so this script never has to guess.
#
# Output lands in builds/<target>/ at the repo root (gitignored — build artifacts are never
# committed).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/project"
CONFIG_DIR="$REPO_ROOT/scripts/build-configs"

usage() {
	echo "Usage: bash scripts/build-game.sh <target> [debug|release]"
	echo ""
	echo "Targets:"
	for cfg in "$CONFIG_DIR"/*.env; do
		echo "  $(basename "$cfg" .env)"
	done
	exit 1
}

TARGET="${1:-}"
MODE="${2:-debug}"

if [[ -z "$TARGET" ]]; then
	usage
fi

CONFIG_FILE="$CONFIG_DIR/$TARGET.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Unknown target: $TARGET" >&2
	usage
fi

if [[ "$MODE" != "debug" && "$MODE" != "release" ]]; then
	echo "Unknown mode: $MODE (expected 'debug' or 'release')" >&2
	usage
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

GODOT_ABS="$REPO_ROOT/$GODOT_BIN"
OUTPUT_FILE_ABS="$REPO_ROOT/$OUTPUT_FILE"
OUTPUT_DIR_ABS="$REPO_ROOT/$OUTPUT_DIR"

if [[ ! -x "$GODOT_ABS" ]]; then
	echo "Engine binary not found or not executable: $GODOT_ABS" >&2
	echo "(configured in $CONFIG_FILE)" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR_ABS"

# Stamp project/scripts/build_info.gd with this build's date/time BEFORE importing, so the
# freshly-written constant (not a stale cached one) is what actually gets exported. See
# build_info.gd's own header — this is the only place BUILD_TIMESTAMP is ever written.
BUILD_INFO_FILE="$PROJECT_DIR/scripts/build_info.gd"
BUILD_TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M UTC')"
cat > "$BUILD_INFO_FILE" << EOF
class_name BuildInfo
extends RefCounted
## Stamped by scripts/build-game.sh immediately before every export — see that script's
## own header comment for the exact mechanism (it rewrites this file's BUILD_TIMESTAMP
## constant, then imports/exports, so the freshly-written value is what actually ships).
##
## The value committed to git is a placeholder. It has no meaning by itself — it's whatever
## the last export (by anyone, on any machine) happened to leave behind. Only trust
## BUILD_TIMESTAMP from inside an actual exported build; an editor/dev run just reads
## whatever the last export wrote here, if any.

const BUILD_TIMESTAMP: String = "$BUILD_TIMESTAMP"
EOF
echo "==> Stamped build_info.gd: $BUILD_TIMESTAMP"

echo "==> Importing project (registers class_name, rebuilds import cache)"
"$GODOT_ABS" --headless --path "$PROJECT_DIR" --import

echo "==> Exporting '$TARGET' ($MODE) via preset \"$PRESET_NAME\" -> $OUTPUT_FILE"
if [[ "$MODE" == "release" ]]; then
	"$GODOT_ABS" --headless --path "$PROJECT_DIR" --export-release "$PRESET_NAME" "$OUTPUT_FILE_ABS"
else
	"$GODOT_ABS" --headless --path "$PROJECT_DIR" --export-debug "$PRESET_NAME" "$OUTPUT_FILE_ABS"
fi

echo "==> Done: $OUTPUT_FILE_ABS"
