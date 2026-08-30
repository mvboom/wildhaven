This is a game called Wildhaven.

The ACTIVE documentation for this project is located in the `game-design/` folder.
The `archive/` folder should NEVER be used unless explicitly referenced.

## The doc map — what lives where

`game-design/gdd.md` is the **only live GDD**. Everything else below is authoritative
for its own slice; nothing supersedes the GDD, but the GDD defers to these for detail.

| Doc | Owns |
|---|---|
| [gdd.md](../game-design/gdd.md) | The design contract — pillars, loop, systems, scope, the 15-row Tier 1 table |
| [spec.md](../game-design/spec.md) | The field-level build contract — data schemas, screen layouts, pacing constants, Open Questions |
| [roster.md](../game-design/roster.md) · [terrain.md](../game-design/terrain.md) · [buildings.md](../game-design/buildings.md) | Per-content-type design — the decided values, i.e. the artifact of Content Pipeline step 3 |
| [art.md](../game-design/art.md) | Art direction, sourcing policy, licensing decisions |
| [asset-import-pipeline.md](../game-design/asset-import-pipeline.md) | The runnable import procedure (tech-art's slice of the content flow) |
| [fact-card-pipeline.md](../game-design/fact-card-pipeline.md) | The runnable fact-card generation procedure (content-writer's automated slice of the content flow) |
| [style-guide-pipeline.md](../game-design/style-guide-pipeline.md) | The runnable Gentle Displacement copy procedure (content-writer's scored GER pipeline for the cleared pool) |
| [content-pipeline-status.md](../game-design/content-pipeline-status.md) | Per-item content state — the record, not the procedure |
| [systems-pipeline.md](../game-design/systems-pipeline.md) | The five-step flow for the 15 Tier-1 systems rows |
| [tier1-status.md](../game-design/tier1-status.md) | Per-row systems state — owners, constants, hours actuals |
| [next-steps.md](../game-design/next-steps.md) | Current build assessment and recommended order — where the project actually stands |
| [future.md](../game-design/future.md) | Deferred and cut work |
| [release-checklist.md](../game-design/release-checklist.md) | The ship gates |

Decisions are logged as `D-NN` in `decisions.md`; open questions are `#NN` in `spec.md`.

## Ground rules

- **The human runs all git.** Agents run no git commands — report changed file paths instead.
- **All tuning values are the human's.** Agents propose with sources; the human decides.
- Validation is headless-only, and `--import` must run **before** `--script` — a bare
  `--quit` is a parse check that reports false green. Use `bash scripts/run-tests.sh`.

## Measurement

| Command | Answers |
|---|---|
| `bash scripts/run-tests.sh [filter]` | Does the suite pass? |
| `python3 scripts/agent-activity.py [session-id]` | Which agents are working, which are **idle**, and what orchestration costs |
| `python3 docs/phase0/token-report.py [session-id]` | Per-session, per-subagent token split (no arg lists sessions) |

`agent-activity.py` with no argument is cumulative across all sessions; pass a session id
to see that session's idle list, which is the number worth watching — an agent nobody
dispatches is either dead weight or a blocked lane. `--by-task` lists every dispatch.
The ledger of record is `costs.md`.

## The engine

Godot. The engine binaries are in `godot/`; you should not have to reference this at all.
The game project itself is `project/` — this is where the game lives and functionality is added.
