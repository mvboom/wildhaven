#!/usr/bin/env bash
#
# Serve a Web build produced by scripts/build-game.sh, on a specific port, by target name.
#
# Usage:
#   bash scripts/serve-web-build.sh <web-threaded|web-singlethread> [port]
#
# Defaults: web-threaded -> 8070, web-singlethread -> 8080 (matching prior local testing).
#
# The actual server (COOP/COEP headers + real HTTP Range support, both of which a plain
# `python3 -m http.server` lacks and a Godot Web export — especially a threaded one — needs)
# lives in scripts/serve-web-build.py. This wrapper just resolves <target> to its build
# directory the same way scripts/build-game.sh does, via the same scripts/build-configs/
# .env files, so the two commands never disagree about where a target's build lives.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$REPO_ROOT/scripts/build-configs"

usage() {
	echo "Usage: bash scripts/serve-web-build.sh <web-threaded|web-singlethread> [port]"
	exit 1
}

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
	usage
fi

case "$TARGET" in
	web-threaded) DEFAULT_PORT=8070 ;;
	web-singlethread) DEFAULT_PORT=8080 ;;
	*)
		echo "Unknown web target: $TARGET (expected web-threaded or web-singlethread)" >&2
		usage
		;;
esac

CONFIG_FILE="$CONFIG_DIR/$TARGET.env"
if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "No config file for target: $TARGET (expected $CONFIG_FILE)" >&2
	exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

OUTPUT_DIR_ABS="$REPO_ROOT/$OUTPUT_DIR"
PORT="${2:-$DEFAULT_PORT}"

if [[ ! -f "$OUTPUT_DIR_ABS/index.html" ]]; then
	echo "No build found at $OUTPUT_DIR_ABS/index.html" >&2
	echo "Run: bash scripts/build-game.sh $TARGET" >&2
	exit 1
fi

echo "==> Serving $TARGET from $OUTPUT_DIR_ABS on port $PORT"
exec python3 "$REPO_ROOT/scripts/serve-web-build.py" "$OUTPUT_DIR_ABS" "$PORT"
