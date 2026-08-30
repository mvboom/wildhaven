# Phase-0 Toolchain: godot-mcp + in-container Godot

**Verified:** 2026-07-20. `get_godot_version` → `4.7.stable.mono.official.5b4e0cb0f`;
`get_project_info` reads `/workspaces/habitown/project`. The spec's A1 gate is PASSED.

## What is actually wired (differs from spec §A1's assumption)

The spec assumed the GDAI MCP plugin running inside the local Godot editor. What is
actually installed — and works — is the **godot-mcp** server driving a Godot binary
directly:

- Binary: `/workspaces/habitown/godot/Godot_v4.7-stable_mono_linux.x86_64`
  (in-workspace; `ENV GODOT_PATH` set in `.devcontainer/Dockerfile`).
- Server: `godot-mcp`, connected to Claude Code as MCP server name `godot`.
- Project: `/workspaces/habitown/project` ("Habitat Town", Godot 4.7, GL Compatibility).

Consequence: engine operations do **not** require the user's editor to be running.
This softens the expected "editor must be up" API constraint — record the revised
version in the GDD's API Constraints section during synthesis: *agent engine work is
editor-independent; only human visual review requires the editor.*

## Capability table

| Capability | Tool(s) | Notes |
|---|---|---|
| Version / project metadata | `get_godot_version`, `get_project_info`, `list_projects` | verified working |
| Scene authoring | `create_scene`, `add_node`, `save_scene` | agents' main build lane |
| Asset handling | `load_sprite`, `export_mesh_library`, `get_uid`, `update_project_uids` | Tech Art lane |
| Run & observe | `run_project`, `get_debug_output`, `stop_project` | **NOT AVAILABLE — do not use.** `run_project` reports false success: it returns "started in debug mode", the process dies instantly on display-server init (no `libX11`/`libwayland-client`/`libfontconfig`), and `get_debug_output` then returns "No active Godot process". Empty output reads as "no errors" — this produced a false-green QA pass in pilot 1. Use the headless lane below. |
| Editor | `launch_editor` | in-container; user's visual review normally happens in their LOCAL editor instead |

Anything not covered by a tool above (shader authoring, .tres resource files, GDScript
bodies, project settings) is written as **plain text files** with Read/Write/Edit — Godot
scenes and resources are text formats. That is the normal complement, not the fallback.

## Review split

- **Agents:** build scenes/scripts/resources via the tools above; validate **headless**
  (see below). Never by `run_project` + `get_debug_output` — that lane reports false
  success in this container.
- **Human:** visual and taste review in the local Godot editor on the same checkout
  (the picture-book eyeball test — gdd.md, Content Pipelines step 8). Editor-up is a
  review-time requirement only, never a build-time one.

## The validation lane (primary, not a fallback)

Authoring in pure text mode (`.tscn`/`.gd`/`.tres` via file tools) is the normal complement
to the MCP tools, and headless invocation is the *only* working validation path.

**Order matters, and getting it wrong fails green:**

```bash
G=/workspaces/habitown/godot/Godot_v4.7-stable_mono_linux.x86_64
$G --headless --path /workspaces/habitown/project --import                    # 1. REQUIRED FIRST
$G --headless --path /workspaces/habitown/project --quit                      # 2. parse check
$G --headless --path /workspaces/habitown/project --script res://tests/<t>.gd # 3. real assertions
```

1. **`--import` is what actually imports assets and registers global `class_name`s.**
   Skipping it is the trap: `--quit` alone returns **exit 0 on a project Godot has never
   successfully imported**, and a following `--script` then fails with
   `Parse Error: Could not find base class`. A CI gate built on `--quit` reports clean on a
   broken project.
2. `--quit` is a parse/import check only.
3. `--script` against a `SceneTree` script is the only way to prove a resource actually
   *resolves* — a `.tres` with a broken `script_class` still loads as a plain `Resource`
   with its fields intact as metadata, so field-by-field checks pass green on a broken
   binding. Assert `res is <YourClass>` before anything else.

Note the Godot binary is **not on `PATH`**. A `fontconfig` warning prints on every headless
invocation — cosmetic, ignore it.

Record any tool misbehavior in `costs.md`'s note column — it is an API-constraints finding.
