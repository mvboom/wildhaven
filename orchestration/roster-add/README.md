# Wildhaven Species Content Crew

**Game:** Wildhaven — a kids' (ages 6–10) wildlife town-building game. Players terraform
empty land into terrain tiles; animals move into home sites once the nearby tiles satisfy
that species' real-world habitat needs. Full design: [../../game-design/gdd.md](../../game-design/gdd.md).

## What this crew produces

Given a species name and a few sourced ecology facts, the crew produces a **game-ready
species definition** for Wildhaven: a validated `.tres` data entry matching the game's real
`AnimalDefinition` schema ([project/scripts/definitions/animal_definition.gd](../../project/scripts/definitions/animal_definition.gd)),
plus a kid-appropriate fact card, plus a pass/fail validation report. A passing result can
be dropped straight into `project/data/animals/<id>.tres` — see
[project/data/animals/fox.tres](../../project/data/animals/fox.tres) for what a shipped
entry looks like.

This mirrors a real bottleneck in the project: species content (habitat tags, tuning
numbers, fact-card copy) is the majority of the work still ahead of Wildhaven's launch —
see [game-design/next-steps.md](../../game-design/next-steps.md), which measures the
content pipeline as the best-understood part of the remaining budget. This crew automates
the first draft of that pipeline end to end.

## The crew (4 agents, raw orchestration — `crew.py`)

Each agent is a Python function with an explicit input/output contract, calling the Anthropic API with a role-specific system prompt.

| # | Agent | Input | Output |
|---|---|---|---|
| 1 | **Habitat Designer** | species name + ecology notes + source | `habitat_needs`, `personality`, `avoids`, `farm_tolerant`, `scout_radius`, `tiles_per_individual`, `max_individuals` — checked against the inert-land invariant (a species can never be satisfiable by land the player never shaped) |
| 2 | **Schema Writer** | Habitat Designer's output | a valid `.tres` resource body matching `AnimalDefinition`, field-for-field |
| 3 | **Content Writer** | species name + ecology notes + source (independent of #2 — no shared dependency) | `fact_text` + a per-step checklist log (source / length / tone / predation) |
| 4 | **QA Validator** | the merged `.tres` + fact card | `{"passed": bool, "problems": [...]}` — deterministic, mirroring `AnimalDefinition.validate()` |

No agent is removable: without #1 there's no habitat data to encode; without #2 there's no
valid Godot resource; without #3 there's no fact card; without #4 nothing is *known* to be
game-ready rather than merely produced. See [diagram.md](diagram.md) for the full data-flow
diagram, including why QA's output can also route back to the Habitat Designer.

**Why QA is deterministic, not another LLM call:** the real project's `qa-engineer` agent
explicitly excludes playtesting judgment and runs machine-checkable assertions instead
(`game-design/tier1-status.md`). Making the crew's gate a rule-based re-check of the same
invariants `AnimalDefinition.validate()` enforces keeps that same separation — and keeps the
one step every output must pass from being itself a source of flaky LLM output.

## Running it

Two backends — `crew.py` auto-detects which to use (force one with `CREW_BACKEND=cli` or
`CREW_BACKEND=sdk`):

**Option A — this devcontainer's own Claude Code login (no separate API key)**
```bash
python3 crew.py "Otter"
```
Shells out to the `claude` CLI in headless print mode (`claude -p --safe-mode ...`), reusing
whichever Claude subscription this machine is already authenticated with — no
`ANTHROPIC_API_KEY` or `pip install` needed. This is how the example run below was actually
produced.

**Option B — the Anthropic API directly (portable outside this devcontainer)**
```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
export ANTHROPIC_API_KEY=...
CREW_BACKEND=sdk .venv/bin/python crew.py "Otter"
```

Either way, prints the full crew result (habitat design, schema, content, merged `.tres`
body, QA report) as JSON.

## Example run

The trace below is a **real, live-captured run** — `python3 crew.py "Otter"` via the CLI
backend, in this devcontainer, for a species not currently in Wildhaven's roster. Nothing
below is hand-authored; it's the crew's actual `stdout`.

**Input brief:**
```
Species: Otter
Ecology notes: River otters live in family groups near water, are playful, and forage
along banks and reeds.
Source: https://kids.nationalgeographic.com/animals/mammals/facts/north-american-river-otter
```

**1. Habitat Designer →**
```json
{
  "habitat_needs": ["water", "cover", "quiet"],
  "personality": "Shy",
  "avoids": ["human", "fox"],
  "farm_tolerant": false,
  "scout_radius": 10,
  "tiles_per_individual": 5,
  "max_individuals": 6,
  "rationale": "River otters forage along banks and reeds and need water plus shoreline cover to den and hide, and being wary of people and predators they favor quiet, undisturbed stretches over cultivated or busy land."
}
```

**2. Schema Writer →** (independent of Content Writer — no shared dependency)
```json
{
  "id": "otter",
  "display_name": "Otter",
  "tres_body": "[resource]\nscript = ExtResource(\"1\")\nid = \"otter\"\ndisplay_name = \"Otter\"\nhabitat_needs = [\"water\", \"cover\", \"quiet\"]\npersonality = \"Shy\"\navoids = [\"human\", \"fox\"]\nfarm_tolerant = false\nscout_radius = 10\ncapacity_radius = 0\ntiles_per_individual = 5\nmax_individuals = 6\nmodel_scene = \"res://assets/animals/otter/Otter.tscn\"\nfact_text = \"PLACEHOLDER\""
}
```

**3. Content Writer →**
```json
{
  "fact_text": "River otters live together in family groups near rivers and streams, and they love to play! They spend their days searching for food along the banks and among the reeds.",
  "checklist_log": {
    "source": "Pass - both facts (family groups near water, playful, foraging along banks/reeds) come directly from the provided source notes; nothing invented.",
    "length": "Pass - exactly 2 sentences.",
    "tone": "Pass - warm, friendly phrasing with an exclamation to convey playfulness, no snark.",
    "predation": "Pass - no mention of predators, danger, or death; only cheerful family and foraging activity."
  }
}
```

**4. QA Validator →**
```json
{ "passed": true, "problems": [] }
```

**One honest caveat:** the live Schema Writer's `tres_body` isn't byte-identical to
[project/data/animals/fox.tres](../../project/data/animals/fox.tres)'s syntax — it wrote
plain `[...]` arrays and a bare `model_scene` string instead of fox.tres's
`Array[String]([...])` and `ExtResource(...)` reference form. QA still passes because it
checks the *structured* fields (`habitat_needs`, `personality`, radii, …), not the `.tres`
text byte-for-byte — but turning this into a literally drop-in file would need either a
stricter Schema Writer prompt (a worked example of the exact `ExtResource(...)` syntax) or a
small deterministic formatter between Schema Writer and merge, same as QA already is
deterministic rather than trusted from the LLM.
