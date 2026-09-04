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

const BUILD_TIMESTAMP: String = "2026-09-04 02:51 UTC"
