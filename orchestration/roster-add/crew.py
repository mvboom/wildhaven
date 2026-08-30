"""
Wildhaven Species Content Crew — raw orchestration (no CrewAI dependency).

Four agents coordinate to turn a short species brief into a game-ready
AnimalDefinition entry for Wildhaven (a kids' wildlife town-building game):

    Habitat Designer -> {Schema Writer, Content Writer} -> QA Validator

Output matches the real schema at project/scripts/definitions/animal_definition.gd,
so a passing result can be dropped straight into project/data/animals/<id>.tres.

Two ways to run it, auto-selected (override with CREW_BACKEND=sdk|cli):

  - "cli"  (default if the `claude` CLI is on PATH): shells out to `claude -p`,
    reusing this machine's already-authenticated Claude Code session (a Claude
    subscription plan's included usage, no separate API key needed).
  - "sdk": calls the Anthropic Messages API directly via `pip install -r
    requirements.txt`; needs ANTHROPIC_API_KEY with its own API billing
    (see README.md for a venv-based setup).

Run: python3 crew.py "Otter"
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field

try:
    import anthropic
except ImportError:
    anthropic = None

MODEL = "claude-sonnet-5"
BACKEND = os.environ.get("CREW_BACKEND") or ("cli" if shutil.which("claude") else "sdk")

# ---------------------------------------------------------------------------
# Shared contract, mirrored from project/scripts/definitions/animal_definition.gd.
# Kept here (not just in prompts) so the QA agent checks real output
# deterministically instead of trusting the other agents' self-reports.
# ---------------------------------------------------------------------------

HABITAT_TAGS = [
    "water", "forest", "open_grass", "quiet", "cover", "flowers",
    "sand", "rocks", "cultivated", "house",
]
BARE_TAGS = ["open_grass", "quiet"]          # tags untouched land emits on its own
PERSONALITIES = ["Shy", "Bold"]
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
RADIUS_BAND = (8, 12)

# The wildlife reference sites this devcontainer's firewall already allowlists for
# fact-card research (.devcontainer/wildhaven-firewall.sh) — the same sites the real
# content-writer subagent cites from (see project/data/animals/fox.tres's dual-sourced
# fact_text comment). The Content Writer researches across these instead of trusting a
# single caller-supplied URL.
APPROVED_SOURCES = [
    "animaldiversity.org",
    "nationalzoo.si.edu",
    "wildlifetrusts.org",
    "kids.nationalgeographic.com",
    "education.nationalgeographic.org",
]


@dataclass
class SpeciesBrief:
    name: str
    ecology_notes: str = ""                   # optional design-judgment hint for the
                                               # Habitat Designer; not sourced content
    search_terms: str = ""                    # optional alternate/scientific names to help
                                               # the Content Writer when the plain species
                                               # name is ambiguous or search-thin
    # The full roster this project has any real record of: the three shipped floor species
    # plus the nine cleared-pool species already imported/attributed/import-tested
    # (game-design/content-pipeline-status.md). The pool nine are NOT decided roster members
    # yet — this list is context for plausible avoids candidates, never a menu to pick from
    # by default (see the Habitat Designer prompt below).
    known_roster_ids: list = field(default_factory=lambda: [
        "fox", "rabbit", "human",
        "deer", "stag", "horse", "donkey", "cow", "bull", "alpaca", "husky", "shiba_inu",
    ])


def _client() -> "anthropic.Anthropic":
    if anthropic is None:
        raise RuntimeError("pip install anthropic first.")
    return anthropic.Anthropic()


def _strip_json_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
        if text.endswith("```"):
            text = text.rsplit("```", 1)[0]
    return text.strip()


def _extract_json_object(text: str) -> str:
    """Best-effort extraction of the first balanced top-level {...} object in `text`,
    for responses that slip in stray prose before/after the JSON despite instructions
    (e.g. "I couldn't find much, but here's what I have: {...}"). Returns `text`
    unchanged if no balanced object is found, so the caller's own error still surfaces."""
    start = text.find("{")
    if start == -1:
        return text
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text


def _parse_json_response(raw_text: str) -> dict:
    """Parses a model turn's text as JSON, tolerating minor formatting drift (code
    fences, stray prose wrapped around the object) before giving up. Raises ValueError
    with a preview of the raw text on failure — a bare JSONDecodeError alone doesn't
    show what was actually returned, which is the thing you need to see to fix a
    prompt or diagnose a bad response."""
    candidate = _strip_json_fences(raw_text)
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        pass

    extracted = _extract_json_object(candidate)
    try:
        return json.loads(extracted)
    except json.JSONDecodeError as e:
        preview = raw_text[:300].replace("\n", " ")
        raise ValueError(
            f"Could not parse JSON from model response: {e}. Raw (first 300 chars): {preview!r}"
        ) from e


def _call_json_sdk(system: str, user: str, use_web_tools: bool = False) -> dict:
    """web_search/web_fetch are SERVER-side tools — Anthropic's infrastructure runs
    the search/fetch and returns results as content blocks in the same response, no
    client-side tool_result round-trip needed. The only client-side case is
    `pause_turn`, which fires if the server-side loop hits its 10-iteration cap;
    resend once per shared/tool-use-concepts.md's documented pattern."""
    kwargs = {}
    if use_web_tools:
        kwargs["tools"] = [
            {"type": "web_search_20260209", "name": "web_search", "allowed_domains": APPROVED_SOURCES},
            {"type": "web_fetch_20260209", "name": "web_fetch", "allowed_domains": APPROVED_SOURCES},
        ]

    messages = [{
        "role": "user",
        "content": user + "\n\nRespond with ONLY a JSON object, no prose, no markdown fences.",
    }]
    resp = _client().messages.create(model=MODEL, max_tokens=2048, system=system, messages=messages, **kwargs)

    if resp.stop_reason == "pause_turn":
        messages.append({"role": "assistant", "content": resp.content})
        resp = _client().messages.create(model=MODEL, max_tokens=2048, system=system, messages=messages, **kwargs)

    text = next(block.text for block in reversed(resp.content) if block.type == "text")
    return _parse_json_response(text)


def _call_json_cli(system: str, user: str, tools: str = "") -> dict:
    """Runs one agent turn through the `claude` CLI in headless print mode,
    reusing whatever this machine is already logged into Claude Code with. Claude
    Code already runs its own internal tool-use loop, so enabling WebFetch/WebSearch
    here needs no extra plumbing on our side — it just takes longer to return.

    --safe-mode: skips CLAUDE.md/skills/plugins/hooks auto-loading (this
    crew's prompts are fully self-contained) while keeping auth, model
    selection, and built-in tools working normally.
    --allowedTools: "" for pure text-generation calls (the common case); a
    space-separated tool list (e.g. "WebFetch WebSearch") for the one agent
    that actually needs to research something.
    """
    result = subprocess.run(
        [
            "claude", "-p", "--safe-mode",
            "--allowedTools", tools,
            "--system-prompt", system,
            "--output-format", "json",
            "--model", MODEL,
            user + "\n\nRespond with ONLY a JSON object, no prose, no markdown fences.",
        ],
        capture_output=True, text=True, check=True, timeout=180,
    )
    envelope = json.loads(result.stdout)
    if envelope.get("is_error"):
        raise RuntimeError(f"claude CLI turn failed: {envelope.get('result')}")
    return _parse_json_response(envelope["result"])


def _call_json(system: str, user: str, needs_web: bool = False) -> dict:
    if BACKEND == "cli":
        return _call_json_cli(system, user, tools="WebFetch WebSearch" if needs_web else "")
    return _call_json_sdk(system, user, use_web_tools=needs_web)


# ---------------------------------------------------------------------------
# Agent 1 — Habitat Designer
# Input:  a SpeciesBrief
# Output: habitat/tuning JSON (habitat_needs, personality, avoids, radii, ...)
# ---------------------------------------------------------------------------

HABITAT_DESIGNER_SYSTEM = f"""You are Wildhaven's Habitat Designer agent.

Wildhaven is a kids' (ages 6-10) wildlife town-building game. Players terraform empty
land into terrain tiles; animals move in once the tiles near a home site satisfy that
species' habitat needs.

Given a species brief, decide its habitat data. Output JSON with exactly these keys:
- "habitat_needs": array of 1-3 tags, EACH must be one of {HABITAT_TAGS}
- "personality": one of {PERSONALITIES}
- "avoids": array of species ids (lowercase, no spaces) this species keeps distance
  from. **EMPTY IS THE EXPECTED ANSWER FOR MOST SPECIES.** Most animals have no
  documented real-world avoidance relationship worth modeling — the shipped roster
  has exactly ONE such pair (fox avoids rabbit, and vice versa), a genuine
  size-appropriate predator/prey relationship, by design. Only include an
  id when you can state a REAL, size-appropriate, sourced-in-spirit reason this
  SPECIFIC species would be wary of that SPECIFIC other one. Never include an id
  just because it appears in "Existing roster ids" below — that list is context for
  what other species exist, not a menu of things to be wary of, and most of it will
  have no real relationship to the species you're deciding. A domesticated or
  farm-tolerant species must NOT avoid "human" — living near people is what
  farm_tolerant means, not something to fear.
- "farm_tolerant": boolean, can it live on cultivated land
- "scout_radius": int in [{RADIUS_BAND[0]}, {RADIUS_BAND[1]}] — how far it scores land
  when picking a home site (wider-ranging animals get a higher number)
- "tiles_per_individual": int, qualifying tiles needed per resident (rarer/pickier
  species = higher number; 4-6 is typical for a common species)
- "max_individuals": int, hard per-site cap (6 is the roster default)
- "rationale": 1-2 sentences on why these tags fit the species' real habitat

HARD RULE — the inert-land invariant: `habitat_needs` must NOT be satisfiable by
untouched land alone. Untouched land only ever emits {BARE_TAGS}. If every tag you
choose is in that list, the species would move in on land the player never shaped,
which breaks the game's core rule that habitat is always player-made. At least one
chosen tag must fall outside {BARE_TAGS}.
"""


def habitat_designer(brief: SpeciesBrief) -> dict:
    user = f"Species: {brief.name}\n"
    if brief.ecology_notes:
        user += f"Ecology notes: {brief.ecology_notes}\n"
    user += f"Existing roster ids (for avoids): {brief.known_roster_ids}"
    return _call_json(HABITAT_DESIGNER_SYSTEM, user)


# ---------------------------------------------------------------------------
# Agent 2 — Schema Writer
# Input:  a SpeciesBrief + the Habitat Designer's JSON
# Output: a valid `.tres` resource body (AnimalDefinition schema)
# ---------------------------------------------------------------------------

SCHEMA_WRITER_SYSTEM = """You are Wildhaven's Schema Writer agent.

You turn a Habitat Designer's decisions into a valid Godot `.tres` resource body
matching the `AnimalDefinition` schema (project/scripts/definitions/animal_definition.gd).
You do not invent habitat data — you only encode the JSON you're given, plus a lowercase
snake_case `id` derived from the species name, and a placeholder `model_scene` path
`res://assets/animals/<id>/<Name>.tscn` (a real model isn't imported yet).

Output JSON with exactly these keys:
- "id": lowercase id, must match ^[a-z][a-z0-9_]*$
- "display_name": the species' player-facing name
- "tres_body": the full `[resource]` block as it would appear in the `.tres` file,
  as a single string with real newlines, in this exact field order: script, id,
  display_name, habitat_needs, personality, avoids, farm_tolerant, scout_radius,
  capacity_radius, tiles_per_individual, max_individuals, model_scene, fact_text.
  Leave fact_text as the literal string PLACEHOLDER — the Content Writer fills it
  in later and this agent never authors copy.
  Set capacity_radius = 0 (the CAPACITY_RADIUS_FOLLOWS_SCOUT sentinel, meaning
  "equal to scout_radius") unless the Habitat Designer gave a reason to diverge.
"""


def schema_writer(brief: SpeciesBrief, design: dict) -> dict:
    user = f"Species: {brief.name}\nHabitat Designer output: {json.dumps(design)}"
    return _call_json(SCHEMA_WRITER_SYSTEM, user)


# ---------------------------------------------------------------------------
# Agent 3 — Content Writer
# Input:  a species name only — this agent researches its own facts, it is
#         not handed a pre-selected source (runs independently of Schema
#         Writer — both depend only on the brief / Habitat Designer output,
#         not on each other)
# Output: fact_text + a per-step checklist log naming the source(s) used
# ---------------------------------------------------------------------------

CONTENT_WRITER_SYSTEM = f"""You are Wildhaven's Content Writer agent.

Audience: kids 6-10. Research the species yourself using your web_search and
web_fetch tools — you are not handed a source. Only these reference sites are
reachable (search/fetch anything else and it will fail):
{chr(10).join(f"- {s}" for s in APPROVED_SOURCES)}

Every fact card must pass this checklist:
1. Traces to at least one of the sites above — no invented facts. Cross-reference
   a second site when the first source is thin or you're unsure of a detail.
2. 1-2 sentences.
3. Warm, gentle tone — never snarky, never scary.
4. No predation, death, or threat framing. Any "avoids" relationship between species
   is voiced as "keeps its distance," never as danger.

If you are given alternate search terms, try those too before giving up — a common
name (e.g. a breed or a farm-animal name) can be thin or ambiguous on these sites
where a more specific term is not.

IF YOU STILL CANNOT FIND USABLE INFORMATION after searching: this is a normal,
expected outcome, not a failure to explain away. Do NOT write an apology or any
prose outside the JSON object — you must ALWAYS return exactly the JSON shape
below. Set "fact_text" to the literal string "PLACEHOLDER" followed by a short
space-separated reason (e.g. "PLACEHOLDER - no usable source found on approved
sites after searching <what you tried>"), and explain what you searched and why it
came up empty in "checklist_log.source".

Output JSON with exactly these keys:
- "fact_text": the 1-2 sentence fact card, OR the PLACEHOLDER form described above
- "checklist_log": object with keys "source" (name which site(s) you drew from, or
  what you searched and why nothing was usable), "length", "tone", "predation" —
  each a short pass/fail note explaining why
"""


def content_writer(brief: SpeciesBrief) -> dict:
    user = f"Species: {brief.name}"
    if brief.search_terms:
        user += f'\nIf "{brief.name}" alone is thin or ambiguous, also try: {brief.search_terms}'
    return _call_json(CONTENT_WRITER_SYSTEM, user, needs_web=True)


# ---------------------------------------------------------------------------
# Agent 4 — QA Validator
# Input:  the merged draft from Schema Writer + Content Writer
# Output: {"passed": bool, "problems": [...]}
#
# Deterministic by design, mirroring AnimalDefinition.validate() and the real
# project's qa-engineer role: mechanism is machine-checked, not judged by an
# LLM. This is also what keeps the crew's "runs without crashing" guarantee —
# the gate a game-ready asset must clear can't itself be a source of flaky
# LLM output.
# ---------------------------------------------------------------------------

def qa_validator(schema: dict, design: dict, content: dict, known_ids: list) -> dict:
    problems = []

    sid = schema.get("id", "")
    if not sid or not ID_PATTERN.match(sid):
        problems.append(f'`id` "{sid}" breaks the roster convention.')

    if not schema.get("display_name"):
        problems.append("`display_name` is empty.")

    personality = design.get("personality")
    if personality not in PERSONALITIES:
        problems.append(f'`personality` "{personality}" is not one of {PERSONALITIES}.')

    needs = design.get("habitat_needs", [])
    if not needs:
        problems.append("`habitat_needs` is empty.")
    for tag in needs:
        if tag not in HABITAT_TAGS:
            problems.append(f'`habitat_needs` tag "{tag}" is not in the shared vocabulary.')
    if needs and all(t in BARE_TAGS for t in needs):
        problems.append(
            f"`habitat_needs` {needs} is satisfiable by untouched land — breaks the inert-land invariant."
        )

    scout = design.get("scout_radius", 0)
    if not (RADIUS_BAND[0] <= scout <= RADIUS_BAND[1]):
        problems.append(f"`scout_radius` {scout} sits outside the {RADIUS_BAND} band.")

    if design.get("tiles_per_individual", 0) < 1:
        problems.append("`tiles_per_individual` must be >= 1.")
    if design.get("max_individuals", 0) < 1:
        problems.append("`max_individuals` must be >= 1.")

    fact_text = content.get("fact_text", "")
    if not fact_text:
        problems.append("`fact_text` is empty.")
    elif fact_text.strip().upper().startswith("PLACEHOLDER"):
        problems.append("`fact_text` is still a placeholder.")

    fatal_problems = list(problems)
    for avoid_id in design.get("avoids", []):
        if not ID_PATTERN.match(avoid_id):
            problems.append(f'`avoids` entry "{avoid_id}" is not in id form.')
            fatal_problems.append(problems[-1])
        elif avoid_id not in known_ids:
            problems.append(f'`avoids` entry "{avoid_id}" has no AnimalDefinition yet (non-fatal).')

    return {"passed": len(fatal_problems) == 0, "problems": problems}


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def _progress(message: str) -> None:
    """Progress goes to stderr, never stdout — stdout stays pure JSON so the
    crew's output can still be piped into `jq` or redirected to a file."""
    print(message, file=sys.stderr, flush=True)


def run_crew(brief: SpeciesBrief) -> dict:
    _progress(f"[1/4] Habitat Designer ({brief.name})...")
    t0 = time.perf_counter()
    design = habitat_designer(brief)
    _progress(f"[1/4] Habitat Designer done ({time.perf_counter() - t0:.1f}s)")

    # Schema Writer and Content Writer both depend only on `design`/`brief`, not on
    # each other, so they're independent calls — safe to parallelize with threads if
    # wall-clock matters. Run sequentially here to keep the reference implementation
    # dependency-free.
    _progress("[2/4] Schema Writer...")
    t0 = time.perf_counter()
    schema = schema_writer(brief, design)
    _progress(f"[2/4] Schema Writer done ({time.perf_counter() - t0:.1f}s)")

    _progress("[3/4] Content Writer...")
    t0 = time.perf_counter()
    # The one agent that does live web research, so it's the one agent whose failure
    # modes are genuinely "not found" rather than "broken": a slow/ambiguous search can
    # time out, and a model response can occasionally slip formatting past
    # _parse_json_response's fallback. Both are now first-class, non-crashing outcomes —
    # the run still completes and produces an inspectable, honestly-marked PLACEHOLDER
    # result, the same convention the real game's AnimalDefinition.fact_text already uses
    # for "content not written yet" (see project/scripts/definitions/animal_definition.gd).
    try:
        content = content_writer(brief)
    except subprocess.TimeoutExpired:
        elapsed = time.perf_counter() - t0
        _progress(f"[3/4] Content Writer TIMED OUT after {elapsed:.1f}s — leaving fact_text undefined")
        content = {
            "fact_text": "PLACEHOLDER - Content Writer's research step timed out before returning a result",
            "checklist_log": {"source": "n/a (timeout)", "length": "n/a", "tone": "n/a", "predation": "n/a"},
        }
    except (ValueError, json.JSONDecodeError) as e:
        elapsed = time.perf_counter() - t0
        _progress(f"[3/4] Content Writer response could not be parsed ({elapsed:.1f}s) — leaving fact_text undefined")
        content = {
            "fact_text": f"PLACEHOLDER - Content Writer's response could not be parsed as JSON ({e})",
            "checklist_log": {"source": "n/a (parse failure)", "length": "n/a", "tone": "n/a", "predation": "n/a"},
        }
    else:
        _progress(f"[3/4] Content Writer done ({time.perf_counter() - t0:.1f}s)")

    fact_text_escaped = content["fact_text"].replace('"', '\\"')
    tres_body = re.sub(
        r'fact_text\s*=\s*"PLACEHOLDER"',
        f'fact_text = "{fact_text_escaped}"',
        schema["tres_body"],
    )

    _progress("[4/4] QA Validator...")
    t0 = time.perf_counter()
    qa = qa_validator(schema, design, content, brief.known_roster_ids)
    _progress(f"[4/4] QA Validator done ({time.perf_counter() - t0:.1f}s) — passed={qa['passed']}")

    return {
        "species": brief.name,
        "habitat_design": design,
        "schema": schema,
        "content": content,
        "tres_body": tres_body,
        "qa": qa,
    }


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "Otter"
    search_terms = sys.argv[2] if len(sys.argv) > 2 else ""
    result = run_crew(SpeciesBrief(name=name, search_terms=search_terms))
    print(json.dumps(result, indent=2))
