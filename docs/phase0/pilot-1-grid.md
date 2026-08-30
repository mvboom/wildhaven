# Pilot 1 — Gameplay slice: grid + tile placement spike

**Session rule:** fresh Claude Code session, this brief as the opening context.
**Agents:** `gameplay-engineer` (build), then `qa-engineer` (validation).
**Doubles as:** real phase-1 progress (gdd.md, Plan → Phases of Work).
**Toolchain:** see `docs/phase0/mcp-setup.md` (godot-mcp, editor-independent).

## Scope — in
- A world scene in `/workspaces/habitown/project` with a fine grid on a small test
  world (16×16 is plenty for the spike; the ~36×36 start size is NOT required yet).
- Tap-to-place ONE terrain type: tap a grass tile → it becomes forest, with a visible
  change (placeholder visuals fine — colored tiles acceptable at spike stage).
- A camera stub: fixed angle per the GDD's no-rotation rule; zoom/pan NOT required.
- Project scaffolding as needed (folder structure, main scene) — dispatch it
  distinctly where possible so it logs as `[setup]`.

## Scope — out (do not build)
Terrain palette UI, resources/costs, habitat tags, save/load, multiple terrain
types, mist, animals. The spike is: grid exists, tap changes a tile, project runs.

## Done criteria

> **CORRECTED after pilot 3.** Criteria 1–2 originally required verification via
> `run_project` / `get_debug_output`. That lane does not work in this container — the
> process dies on display-server init and `get_debug_output` returns empty, so **absence
> of output was read as absence of errors.** Pilot 1's original pass therefore did not
> verify what it claimed. Its grid logic appears sound (pilot 3's fox spawn test loaded
> `Main.tscn` and it built its 256 tiles correctly, which is independent evidence), but
> if this spike is ever re-run, use the criteria below.

1. `gameplay-engineer` reports the world scene loading and tap placement working, proven
   by a headless `--script` run that asserts a tile actually changes state — not by
   `run_project`, and not by any check whose pass condition is empty output.
2. `qa-engineer` reports a passing smoke check via the headless lane in
   `docs/phase0/mcp-setup.md`: `--import` first, then `--quit`, then `--script` with real
   assertions. A check that cannot fail is not a check.
3. Human: open the project in the local editor, confirm the scene loads and the tap
   behavior works. Taste review not required at spike stage.

## Session close
Run the measurement checklist (`docs/phase0/measurement.md`). Work unit column:
`pilot-1 grid spike`; scaffolding rows flagged `[setup]`.
