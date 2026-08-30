# Pilot 2 — UI screen: title screen

**Session rule:** fresh Claude Code session, this brief as the opening context.
**Agents:** `ui-engineer` only.
**Prerequisite:** pilot 1 complete (its world scene is the New Game target).
**Toolchain:** see `docs/phase0/mcp-setup.md`.

## Scope — in
- The minimal menu shell per gdd.md Plan → phase 1: a title screen with the game's
  working title and a **New Game** button that loads pilot 1's world scene directly.
- A **Quit** button.
- Kid-legible sizing per the GDD's Accessibility notes (big tap targets); placeholder
  font/art acceptable — `[COPY]` placeholders for any strings not in the GDD.

## Scope — out (do not build)
Continue/load flow, world presets, Settings, any other screen or overlay, final art,
final copy, music.

## Done criteria
1. `ui-engineer` reports: project boots to the title screen, New Game transitions
   into the world scene, Quit exits — verified via `run_project`/`get_debug_output`.
2. Human: local-editor run-through; the transition works by feel.

## Session close
Run the measurement checklist (`docs/phase0/measurement.md`). Work unit column:
`pilot-2 title screen`.
