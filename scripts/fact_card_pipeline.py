"""
Wildhaven Fact-Card GER Pipeline — Generator / Evaluator / Refiner / Circuit Breaker.

Wildhaven's PRODUCTION mechanism for fact-card content (→ D-48; originally built for
archive/mark-vanderboom-assignment-6/, then adopted going forward rather than shelved —
see that folder's README for the assignment write-up and the pipeline's origin evidence).
For fact-card copy specifically, run this instead of hand-drafting; see
.claude/agents/content-writer.md and game-design/fact-card-pipeline.md.

Content type: animal fact-card copy (`AnimalDefinition.fact_text_pool` — see
project/scripts/definitions/animal_definition.gd and decisions.md -> D-47). The rule
this pipeline enforces is gdd.md's two-register rule + operational predation ban
(gdd.md lines 48/66/69/184) plus the closed predation-graph check (roster.md ->
Compatibility): a fact card must never depict/allude to hunting or predation, and must
never name another roster species.

Loop, per candidate card:
  Generator  -- drafts a 1-2 sentence fact_text (LLM call, --generator-model).
  Evaluator  -- TWO independent checks, both must pass:
                1. deterministic (banned vocabulary, closed predation graph, register,
                   length, non-duplicate) -- fast, free, the hard gate.
                2. LLM judge, using a DIFFERENT model than the generator
                   (--evaluator-model) -- catches oblique predation framing regex can't
                   ("bred to work alongside hunters in the field") and general fit,
                   plus semantic (not just exact-string) duplicates against cards
                   already accepted this run.
  Refiner    -- re-prompts the Generator with the Evaluator's specific problems.
  Circuit
  Breaker    -- after --max-refine failed attempts, stop and escalate for human review
                rather than ship a bad card.

Two ways to run it, auto-selected (override with GER_BACKEND=sdk|cli), same convention
as archive/mark-vanderboom-assignment-3/crew.py:
  - "cli" (default if the `claude` CLI is on PATH): shells out to `claude -p`, reusing
    this machine's already-authenticated Claude Code session.
  - "sdk": calls the Anthropic Messages API directly (`pip install anthropic`; needs
    ANTHROPIC_API_KEY).

Run (from repo root or scripts/, either works):
  python3 scripts/fact_card_pipeline.py "Shiba Inu" --count 2
  python3 scripts/fact_card_pipeline.py "Bull" --count 1
  python3 scripts/fact_card_pipeline.py --selftest   # no LLM calls; proves the Evaluator catches bad drafts

Scope, explicitly (→ D-48): fact cards ONLY. News Report pools and first-time-nudge
copy are NOT covered here and stay content-writer.md's hand-drafted remit — this
pipeline hasn't been validated against those content types' own rules (e.g. News
Report's four-sub-pool structure), and generalizing it blind was out of scope for its
adoption. Extending it there is a future decision, not an assumption.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

try:
    import anthropic
except ImportError:
    anthropic = None

BACKEND = os.environ.get("GER_BACKEND") or ("cli" if shutil.which("claude") else "sdk")


def _find_repo_root(start: Path) -> Path:
    """Walks upward from `start` looking for the real AnimalDefinition schema, rather
    than assuming a fixed parent-count -- this file is intentionally COPIED to more than
    one location (the live tool at scripts/, plus a submission snapshot in
    archive/mark-vanderboom-assignment-6/ -- see that folder's README), and a
    `parents[N]` assumption would silently miscompute every path the moment it's run
    from the "wrong" copy."""
    marker = Path("project") / "scripts" / "definitions" / "animal_definition.gd"
    for candidate in (start, *start.parents):
        if (candidate / marker).exists():
            return candidate
    raise RuntimeError(f"Could not locate the Wildhaven repo root above {start} (no {marker} found).")


REPO_ROOT = _find_repo_root(Path(__file__).resolve().parent)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roster_data  # noqa: E402  (needs REPO_ROOT above)
RosterSpecies = roster_data.RosterSpecies
DATA_DIR = REPO_ROOT / "project" / "data" / "animals"
OUTPUT_DIR = Path(__file__).resolve().parent / "fact_card_pipeline_output"
CONTENT_STATUS_PATH = REPO_ROOT / "game-design" / "content-pipeline-status.md"

MODEL_IDS = {
    "haiku": "claude-haiku-4-5-20251001",
    "opus": "claude-opus-5",
    "sonnet": "claude-sonnet-5",
}

# The pipeline's own approved-source list. Matches spec.md's Fact-Card Content
# Checklist's working set, plus Wikipedia added at the human's direction for this
# pipeline (not yet a change to spec.md's official checklist -- that's the human's call
# to make separately). Reachability of these domains from inside this devcontainer is
# gated by .devcontainer/wildhaven-firewall.sh.
APPROVED_SOURCES = [
    "animaldiversity.org",
    "nationalzoo.si.edu",
    "wildlifetrusts.org",
    "kids.nationalgeographic.com",
    "education.nationalgeographic.org",
    "en.wikipedia.org",
    "www.wikipedia.org",
]

# Word-boundary matched against the operational predation ban (gdd.md:48/66/184).
# The core set is the same one proven out in project/tests/test_human_schema.gd;
# extended with the words test_fox_schema.gd / test_rabbit_schema.gd additionally
# check for, since this pipeline has to cover any species, not just one.
BANNED_WORDS = [
    "hunt", "hunter", "hunters", "hunting", "hunts",
    "gather", "gatherer", "gatherers", "gathering", "gathers",
    "prey", "predator", "predators",
    "kill", "kills", "killing", "killed",
    "catch", "catches", "catching", "caught",
    "eat", "eats", "eaten",
    "escape", "escapes", "escaping",
    "danger", "dangerous", "fear", "afraid", "threat", "threatens",
]

# Roster-wide terminology rule (test_human_schema.gd's D-19-derived sweep): real-world
# claims may not use game-world-specific register.
REGISTER_BANNED = ["town", "towns", "village", "villages", "villager", "villagers"]

MAX_SENTENCES = 2


# The roster is DERIVED from project/data/animals/*.tres, not restated here -- see
# scripts/roster_data.py for why. It feeds (a) the closed-predation-graph check -- a card
# must name no OTHER roster species -- and (b) telling the Generator about a species' own
# avoids partner, since that is exactly the copy that is hardest to keep predation-free
# ("keeps its distance from Husky" reads dangerously close to a predator/prey line if
# worded carelessly). Deriving it means a newly imported species is in the graph the
# moment its .tres exists, with no hand edit -- and a missing data dir raises rather than
# silently shrinking the graph this evaluator depends on.
ROSTER = roster_data.load_roster(REPO_ROOT)


# ---------------------------------------------------------------------------
# LLM call plumbing (cli/sdk backends), adapted from crew.py -- model is now a
# per-call parameter instead of a module constant, since the Generator and the
# Evaluator's LLM judge deliberately use different models.
# ---------------------------------------------------------------------------

def _strip_json_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
        if text.endswith("```"):
            text = text.rsplit("```", 1)[0]
    return text.strip()


def _extract_json_object(text: str) -> str:
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


# ---------------------------------------------------------------------------
# Cost ledger
# ---------------------------------------------------------------------------
# Stage 6 of the asset pipeline prints what its own LLM work cost; stage 8 -- which runs
# a full GER loop per candidate -- printed nothing, so the most expensive stage of a run
# was the one with no number against it. Every backend already returns the numbers; they
# were simply dropped on the floor. Key shape matches scripts/assetpipe/llm.py so the two
# ledgers can be added together.
_COST = {"in": 0, "out": 0, "usd": 0.0, "usd_known": True}


def _record_cost(tokens_in: int, tokens_out: int, usd: float, usd_known: bool) -> None:
    _COST["in"] += tokens_in
    _COST["out"] += tokens_out
    _COST["usd"] += usd
    # Sticky: one call through a backend that reports no dollar figure makes the whole
    # total unknown. Printing a partial sum as if it were the full one would present real
    # spend as free -- the same reasoning _format_cost_line already applies upstream.
    _COST["usd_known"] = _COST["usd_known"] and usd_known


def run_cost() -> dict:
    return dict(_COST)


def cost_delta(before: dict, after: dict) -> dict:
    """This species' share of the ledger, so a multi-species invocation does not write
    the running total into every log it produces."""
    return {"in": after["in"] - before["in"], "out": after["out"] - before["out"],
            "usd": round(after["usd"] - before["usd"], 6),
            "usd_known": after["usd_known"]}
def format_cost(cost: dict) -> str:
    """Never print $0.00 for real spend: the SDK backend reports no dollar figure, so a
    total that includes one says so instead of implying the run was free."""
    tokens = f"{cost.get('in', 0):,} in / {cost.get('out', 0):,} out tokens"
    if cost.get("usd_known", True):
        return f"${cost.get('usd', 0.0):.4f} ({tokens})"
    return f"{tokens} (dollar cost not reported by this backend)"


def _client() -> "anthropic.Anthropic":
    if anthropic is None:
        raise RuntimeError("pip install anthropic first.")
    return anthropic.Anthropic()


def _call_json_sdk(system: str, user: str, model: str, use_web_tools: bool = False) -> dict:
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
    resp = _client().messages.create(model=model, max_tokens=1024, system=system, messages=messages, **kwargs)
    if resp.stop_reason == "pause_turn":
        messages.append({"role": "assistant", "content": resp.content})
        resp = _client().messages.create(model=model, max_tokens=1024, system=system, messages=messages, **kwargs)
    # The Messages API returns usage but no dollar figure, and this repo has no
    # pricing table -- so tokens are real and usd is explicitly unknown.
    _record_cost(resp.usage.input_tokens, resp.usage.output_tokens, 0.0, False)
    text = next(block.text for block in reversed(resp.content) if block.type == "text")
    return _parse_json_response(text)


def _call_json_cli(system: str, user: str, model: str, tools: str = "") -> dict:
    result = subprocess.run(
        [
            "claude", "-p", "--safe-mode",
            "--allowedTools", tools,
            "--system-prompt", system,
            "--output-format", "json",
            "--model", model,
            user + "\n\nRespond with ONLY a JSON object, no prose, no markdown fences.",
        ],
        capture_output=True, text=True, check=True, timeout=180,
    )
    envelope = json.loads(result.stdout)
    usage = envelope.get("usage") or {}
    _record_cost(usage.get("input_tokens", 0), usage.get("output_tokens", 0),
                 envelope.get("total_cost_usd", 0.0), True)
    if envelope.get("is_error"):
        raise RuntimeError(f"claude CLI turn failed: {envelope.get('result')}")
    return _parse_json_response(envelope["result"])


def _call_json(system: str, user: str, model: str, needs_web: bool = False) -> dict:
    if BACKEND == "cli":
        return _call_json_cli(system, user, model, tools="WebFetch WebSearch" if needs_web else "")
    return _call_json_sdk(system, user, model, use_web_tools=needs_web)


def _progress(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Generator
# ---------------------------------------------------------------------------

GENERATOR_SYSTEM = f"""You are Wildhaven's fact-card Content Writer.

Wildhaven is a kids' (ages 6-10) wildlife town-building game. Fact cards are the game's
entire teaching channel: a 1-2 sentence real fact about a species, shown when it moves
in and replayed on every curious tap.

Research the species using your web_search/web_fetch tools. Only these reference sites
are reachable:
{chr(10).join(f"- {s}" for s in APPROVED_SOURCES)}

Every fact card must satisfy Wildhaven's GDD (gdd.md's operational predation ban, the
two-register rule) and spec.md's Fact-Card Content Checklist:
1. Traces to at least one approved site above -- no invented facts.
2. Exactly 1-2 sentences, plain vocabulary, upbeat tone.
3. NO predation, diet, hunting, danger, or threat framing -- not even obliquely. A fact
   about an "avoids" relationship (see below) must be voiced as "keeps its distance,"
   never as danger, escape, or safety.
4. Must NOT name any other Wildhaven species by name -- INCLUDING as a descriptive
   adjective ("fox-like face" is rejected exactly like naming Fox outright; the check
   cannot tell the difference, so don't reach for another species' name at all).
5. Must NOT use game-world-specific words: never "town" or "village" (real-world claims
   describe the real world, not Wildhaven's own game state).
6. Original wording -- never copied text from the source.

If you cannot find a usable, predation-free, source-verified fact after searching: this
is a normal, expected outcome. Return fact_text as the literal string "PLACEHOLDER"
followed by a short reason, and explain what you searched in source_note. Do not write
apology prose outside the JSON object.

Output JSON with exactly these keys:
- "fact_text": the 1-2 sentence fact, or the PLACEHOLDER form above
- "source_note": which approved site(s) the fact traces to, or what was searched and why it came up empty
"""


def generator(
    species: RosterSpecies,
    model: str,
    previous_draft: str | None = None,
    previous_problems: list[str] | None = None,
) -> dict:
    user = f"Species: {species.display_name}\n"
    if species.avoids:
        partners = ", ".join(ROSTER[a].display_name for a in species.avoids if a in ROSTER)
        user += (
            f"This species has an in-game 'avoids' relationship with: {partners}. "
            f"If your fact happens to relate to that, voice it only as neutral distance-keeping, "
            f"never as danger -- but do NOT name {partners} in the fact_text itself (rule 4).\n"
        )
    if previous_draft is not None:
        user += (
            f"\nA PREVIOUS DRAFT was rejected:\n\"{previous_draft}\"\n"
            f"Rejected for:\n" + "\n".join(f"- {p}" for p in (previous_problems or [])) + "\n"
            f"Write a NEW draft that specifically fixes these issues. Do not repeat the same "
            f"wording or the same underlying fact if the issue was about the fact itself."
        )
    return _call_json(GENERATOR_SYSTEM, user, model, needs_web=True)


# ---------------------------------------------------------------------------
# Evaluator, part 1: deterministic (the hard gate -- fast, free, non-negotiable)
# ---------------------------------------------------------------------------

def deterministic_evaluate(fact_text: str, species: RosterSpecies, already_accepted: list) -> dict:
    problems: list[str] = []

    stripped = fact_text.strip()
    if not stripped:
        problems.append("fact_text is empty.")
        return {"passed": False, "problems": problems}
    if stripped.upper().startswith("PLACEHOLDER"):
        problems.append("fact_text is a PLACEHOLDER (Generator could not source a usable fact).")
        return {"passed": False, "problems": problems}

    lowered = stripped.lower()

    for banned in BANNED_WORDS:
        if re.search(rf"\b{re.escape(banned)}\b", lowered):
            problems.append(f'uses banned predation-adjacent word "{banned}" (gdd.md\'s operational predation ban).')

    for banned in REGISTER_BANNED:
        if re.search(rf"\b{re.escape(banned)}\b", lowered):
            problems.append(f'uses game-world term "{banned}" -- violates the two-register rule (gdd.md).')

    # Closed predation-graph check (roster.md -> Compatibility): a card may not name
    # any OTHER roster species, by id or by display name.
    for other_id, other in ROSTER.items():
        if other_id == species.id:
            continue
        for name in {other_id, other.display_name.lower()}:
            if re.search(rf"\b{re.escape(name)}\b", lowered):
                problems.append(f'names another roster species ("{other.display_name}") -- breaks the closed predation graph.')
                break

    sentence_count = len([s for s in re.split(r"(?<=[.!?])\s+", stripped) if s.strip()])
    if sentence_count > MAX_SENTENCES:
        problems.append(f"{sentence_count} sentences -- spec.md's checklist caps fact cards at {MAX_SENTENCES}.")
    if sentence_count == 0:
        problems.append("no sentence-ending punctuation found -- not recognizable as 1-2 sentences.")

    normalized = re.sub(r"[^a-z0-9 ]", "", lowered).strip()
    for prior in already_accepted:
        prior_normalized = re.sub(r"[^a-z0-9 ]", "", prior.lower()).strip()
        if normalized == prior_normalized:
            problems.append("duplicates a card already accepted for this species in this run.")

    return {"passed": len(problems) == 0, "problems": problems}


# ---------------------------------------------------------------------------
# Evaluator, part 2: LLM judge, using a DIFFERENT model than the Generator.
# Catches what regex can't -- oblique predation framing, tone that's technically
# keyword-clean but still reads wrong for a 6-year-old.
# ---------------------------------------------------------------------------

JUDGE_SYSTEM = """You are Wildhaven's independent fact-card judge -- a DIFFERENT model
from whichever one drafted this card, specifically so you are not grading your own
work. You do not see who wrote the draft or why.

Wildhaven is a kids' (6-10) wildlife town-building game with an operational predation
ban: no content anywhere may depict, name, or ALLUDE to hunting, danger, animals eating
animals, or fear -- even obliquely, even through a historical/working-animal framing
that keyword filters would miss (example of a FAILURE: "bred to help hunters retrieve
game" -- no banned word appears, but it's still hunting-adjacent).

A separate deterministic check already caught banned keywords, other-species names, and
length. Your job is ONLY the things a keyword list cannot catch:
1. Oblique predation/hunting/danger framing that uses no banned word.
2. Tone that isn't warm/upbeat/plain for a 6-year-old.
3. A claim that doesn't sound plausible/source-grounded for a children's educational fact.
4. If "Already-accepted cards" are listed below, whether this draft covers a genuinely
   DIFFERENT underlying fact from every one of them -- not just different wording of the
   same fact. Two cards that are both fundamentally "about the same trait, reworded" are
   duplicates even with zero shared vocabulary (e.g. "sees almost all the way around
   itself" and "has wide-angle vision" are the SAME fact restated, not two facts).

Do not re-flag anything a keyword sweep would already catch (obvious words like "hunt"
or "prey") -- assume that layer is handled. Only report what's specifically YOUR job.

Output JSON with exactly these keys:
- "passed": boolean
- "problems": array of strings (empty if passed)
"""


def llm_judge_evaluate(fact_text: str, species: RosterSpecies, model: str, already_accepted: list) -> dict:
    user = f'Species: {species.display_name}\nDraft fact card: "{fact_text}"'
    if already_accepted:
        user += "\nAlready-accepted cards for this species (the draft must cover a different fact than ALL of these):\n"
        user += "\n".join(f'- "{t}"' for t in already_accepted)
    result = _call_json(JUDGE_SYSTEM, user, model, needs_web=False)
    return {"passed": bool(result.get("passed", False)), "problems": list(result.get("problems", []))}


# ---------------------------------------------------------------------------
# Refiner + Circuit Breaker
# ---------------------------------------------------------------------------

def run_one_candidate(
    species: RosterSpecies,
    generator_model: str,
    evaluator_model: str,
    max_refine: int,
    already_accepted: list,
) -> dict:
    """One Generator -> Evaluator -> Refiner loop, up to `max_refine` attempts, then
    Circuit Breaker escalation. Returns a dict with the full attempt log plus either
    {"status": "accepted", "fact_text": ...} or {"status": "escalated"}."""
    attempts = []
    previous_draft: str | None = None
    previous_problems: list[str] | None = None

    for attempt_num in range(1, max_refine + 1):
        _progress(f"    attempt {attempt_num}/{max_refine}: generating ({generator_model})...")
        try:
            draft = generator(species, generator_model, previous_draft, previous_problems)
        except (subprocess.TimeoutExpired, ValueError, json.JSONDecodeError, RuntimeError) as e:
            attempts.append({"attempt": attempt_num, "error": f"Generator call failed: {e}"})
            previous_draft, previous_problems = "(generator call failed)", [str(e)]
            continue

        fact_text = str(draft.get("fact_text", ""))
        det = deterministic_evaluate(fact_text, species, already_accepted)

        judge = {"passed": True, "problems": [], "skipped": True}
        if det["passed"]:
            _progress(f"    attempt {attempt_num}: deterministic PASS, judging ({evaluator_model})...")
            try:
                judge = llm_judge_evaluate(fact_text, species, evaluator_model, already_accepted)
                judge["skipped"] = False
            except (subprocess.TimeoutExpired, ValueError, json.JSONDecodeError, RuntimeError) as e:
                judge = {"passed": False, "problems": [f"LLM judge call failed: {e}"], "skipped": False}
        else:
            _progress(f"    attempt {attempt_num}: deterministic FAIL ({len(det['problems'])} problem(s)) -- skipping judge, refining")

        combined_problems = det["problems"] + judge["problems"]
        passed = det["passed"] and judge["passed"]

        attempts.append({
            "attempt": attempt_num,
            "fact_text": fact_text,
            "source_note": draft.get("source_note", ""),
            "deterministic": det,
            "llm_judge": judge,
            "passed": passed,
        })

        if passed:
            return {"status": "accepted", "fact_text": fact_text, "attempts": attempts}

        previous_draft, previous_problems = fact_text, combined_problems

    return {"status": "escalated", "attempts": attempts}


def run_species(
    species_id: str,
    count: int,
    generator_model: str,
    evaluator_model: str,
    max_refine: int,
    subject=None,
) -> dict:
    # `subject` lets a BUILDING flow through this same loop for --target building_text.
    # The closed-predation-graph check below still runs against the animal ROSTER: a
    # building's fact card must not name a species either.
    species = subject or ROSTER.get(species_id)
    if species is None:
        raise ValueError(f'Unknown id "{species_id}" -- not in the derived roster.')

    _progress(f"=== {species.display_name} ({species_id}) -- generating {count} candidate(s) ===")
    accepted: list[str] = []
    candidates = []
    for i in range(1, count + 1):
        _progress(f"  candidate {i}/{count}:")
        result = run_one_candidate(species, generator_model, evaluator_model, max_refine, accepted)
        candidates.append(result)
        if result["status"] == "accepted":
            accepted.append(result["fact_text"])
            _progress(f"  candidate {i}/{count}: ACCEPTED -- \"{result['fact_text']}\"")
        else:
            _progress(f"  candidate {i}/{count}: CIRCUIT BREAKER -- escalated after {max_refine} attempts")

    return {
        "species_id": species_id,
        "species_display_name": species.display_name,
        "generator_model": generator_model,
        "evaluator_model": evaluator_model,
        "max_refine": max_refine,
        "requested_count": count,
        "accepted_fact_texts": accepted,
        "candidates": candidates,
    }


# ---------------------------------------------------------------------------
# Dual write: archive JSON (grading evidence) + live .tres (usable content)
# ---------------------------------------------------------------------------

def write_output_json(result: dict) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{result['species_id']}.json"
    path.write_text(json.dumps(result, indent=2))
    return path


def write_tres(species_id: str, accepted_fact_texts: list, target: str = "animal_pool") -> str:
    """Patches a .tres file in place with this run's accepted candidates, and drops a
    header note marking the copy as pipeline-generated and awaiting step-8 human
    sign-off -- the same convention human.tres already uses for agent-proposed copy
    elsewhere in this project. Does NOT touch human_signoff or content-pipeline-status.md;
    that stays the human's call. Returns a short description of what happened, for the
    run summary."""
    if not accepted_fact_texts:
        return "no accepted candidates -- .tres left untouched"

    # Both patterns are STRICT -- they match the field only in the exact shape the real
    # .tres files use (verified: every animal fact_text_pool is a single-line
    # Array[String]([...]); every building fact_text is a single-line quoted string). A
    # loose `^fact_text_pool = .*$` would let a malformed field be silently overwritten
    # instead of refused, weakening a guard this production script already had.
    if target == "building_text":
        tres_path = REPO_ROOT / "project" / "data" / "buildings" / f"{species_id}.tres"
        field_pattern = re.compile(r'^fact_text = ".*"$', re.MULTILINE)
        replacement = f"fact_text = {json.dumps(accepted_fact_texts[0], ensure_ascii=False)}"
    else:
        tres_path = DATA_DIR / f"{species_id}.tres"
        field_pattern = re.compile(r"^fact_text_pool = Array\[String\]\(\[.*\]\)$",
                                   re.MULTILINE)
        inner = ", ".join(json.dumps(t, ensure_ascii=False) for t in accepted_fact_texts)
        replacement = f"fact_text_pool = Array[String]([{inner}])"

    if not tres_path.exists():
        return f"WARNING: {tres_path} does not exist -- .tres not written"

    text = tres_path.read_text()
    # Idempotency: strip any note this pipeline left on a PRIOR run before adding a fresh
    # one, so re-running against the same species doesn't accumulate duplicate comment lines.
    prior_note_pattern = re.compile(
        r"^; (?:fact_text_pool|fact_text) REPLACED by (?:archive/mark-vanderboom-assignment-6/ger_pipeline\.py"
        r"|scripts/fact_card_pipeline\.py).*\n",
        re.MULTILINE,
    )
    text = prior_note_pattern.sub("", text)

    if not field_pattern.search(text):
        return f"WARNING: no {replacement.split('=')[0].strip()} line found in {tres_path} -- .tres not written"

    note = (
        f"; {replacement.split('=')[0].strip()} REPLACED by scripts/fact_card_pipeline.py "
        f"({time.strftime('%Y-%m-%d')}) -- AWAITING STEP-8 HUMAN SIGN-OFF, not yet reviewed.\n"
    )
    new_replacement = note.rstrip("\n") + "\n" + replacement
    new_text = field_pattern.sub(lambda _m: new_replacement, text, count=1)
    tres_path.write_text(new_text)
    return f"wrote {len(accepted_fact_texts)} card(s) to {tres_path.relative_to(REPO_ROOT)}"


def update_content_pipeline_status(species_id: str, accepted_fact_texts: list, any_escalated: bool) -> str:
    """Updates ONLY the `copy_content_location` row of `species_id`'s own section in
    content-pipeline-status.md (→ D-48) -- the field this pipeline actually produces,
    per that file's "every field has exactly one write-owner" rule. Does not touch
    `status` (recomputing it needs data_entry/attribution/validation state this script
    has no visibility into) or any other species' section. A missing section or row is
    reported, not silently skipped -- a tracker that's drifted from reality is a defect
    worth surfacing, the same principle asset-import-pipeline.md's Standalone Audit Mode
    applies to its own slice of the content pipeline."""
    if not CONTENT_STATUS_PATH.exists():
        return f"WARNING: {CONTENT_STATUS_PATH} not found -- tracker not updated"

    text = CONTENT_STATUS_PATH.read_text()
    section_pattern = re.compile(
        rf"(^### `{re.escape(species_id)}` .*?\n)(.*?)(?=^### |\Z)",
        re.MULTILINE | re.DOTALL,
    )
    section_match = section_pattern.search(text)
    if section_match is None:
        return f"WARNING: no `### \\`{species_id}\\`` section in {CONTENT_STATUS_PATH.name} -- tracker not updated"

    header, body = section_match.group(1), section_match.group(2)
    row_pattern = re.compile(r"^\| `copy_content_location` \|.*\|$", re.MULTILINE)
    if not row_pattern.search(body):
        return f"WARNING: no copy_content_location row in {species_id}'s section -- tracker not updated"

    log_ref = f"`scripts/fact_card_pipeline_output/{species_id}.json`"
    if not accepted_fact_texts:
        new_row = (
            f"| `copy_content_location` | **CIRCUIT BREAKER ESCALATED** "
            f"({time.strftime('%Y-%m-%d')}) by `scripts/fact_card_pipeline.py` -- no candidate "
            f"cleared the Evaluator after its refine budget; existing content (if any) left "
            f"untouched. Full attempt log: {log_ref} |"
        )
    else:
        partial_note = (
            " (at least one OTHER requested candidate was also circuit-breaker-escalated this "
            "run -- see the log)" if any_escalated else ""
        )
        new_row = (
            f"| `copy_content_location` | **{len(accepted_fact_texts)} card(s) generated** "
            f"({time.strftime('%Y-%m-%d')}) by `scripts/fact_card_pipeline.py` (Generator/Evaluator/"
            f"Refiner/Circuit-Breaker loop, cross-model validated) -- landed directly in "
            f"`project/data/animals/{species_id}.tres`'s `fact_text_pool`, **awaiting step-8 human "
            f"sign-off**{partial_note}. Full attempt log: {log_ref} |"
        )

    new_body = row_pattern.sub(lambda _m: new_row, body, count=1)
    new_text = text[:section_match.start()] + header + new_body + text[section_match.end():]
    CONTENT_STATUS_PATH.write_text(new_text)
    return f"updated {species_id}'s copy_content_location row in {CONTENT_STATUS_PATH.relative_to(REPO_ROOT)}"


# ---------------------------------------------------------------------------
# Self-test: proves the deterministic Evaluator actually catches violations,
# with no LLM calls -- runnable for grading without API access.
# ---------------------------------------------------------------------------

def selftest() -> int:
    # With the ROSTER hardcode gone this fixture is a DATA dependency: renaming
    # project/data/animals/shiba_inu.tres used to turn the whole selftest into a KeyError
    # traceback, which reads as "the suite is broken" rather than "the suite's fixture
    # moved". An explicit failed check says which, and names what was actually derived.
    shiba = ROSTER.get("shiba_inu")
    if shiba is None:
        print("[FAIL] the selftest's fixture species 'shiba_inu' is not in the derived "
              "ROSTER -- project/data/animals/shiba_inu.tres was renamed or removed. "
              f"Derived instead: {sorted(ROSTER) or 'nothing'}.")
        print("SELFTEST FAILED")
        return 1
    cases = [
        ("Shiba Inus were originally bred in Japan to hunt small game in mountainous terrain.",
         "hunt", False),
        ("Shiba Inus keep their distance from Husky the same way most dogs do.",
         "husky", False),
        # NOTE: an earlier version of this case used "fox-like face" and the Evaluator
        # correctly REJECTED it -- "fox" is both a common descriptive adjective and a
        # roster species id, and the closed-predation-graph check (rightly) can't tell
        # the difference, matching test_human_schema.gd's own stricter substring rule.
        # Real finding, kept as a negative control rather than papered over: a
        # generator prompted for Shiba Inu copy has to be told not to reach for that
        # word at all, not just when it's dangerous.
        ("Shiba Inus are one of Japan's oldest dog breeds, known for their curled tail and confident personality.",
         None, True),
        ("PLACEHOLDER -- no cleared source found",
         "PLACEHOLDER", False),
        ("This breed has been part of many households in Japan for centuries. It is known for its "
         "fox-like face. It also has a curled tail that is easy to recognize.",
         "sentences", False),
    ]
    ok = True
    for text, expect_problem_substr, expect_pass in cases:
        result = deterministic_evaluate(text, shiba, already_accepted=[])
        got_pass = result["passed"]
        status = "PASS" if got_pass == expect_pass else "FAIL"
        if got_pass != expect_pass:
            ok = False
        print(f"[{status}] passed={got_pass} (expected {expect_pass}): {text[:70]}...")
        for p in result["problems"]:
            print(f"         - {p}")

    dup_result = deterministic_evaluate(
        "Shiba Inus are one of Japan's oldest dog breeds.",
        shiba,
        already_accepted=["Shiba Inus are one of Japan's oldest dog breeds."],
    )
    dup_ok = not dup_result["passed"] and any("duplicate" in p for p in dup_result["problems"])
    print(f"[{'PASS' if dup_ok else 'FAIL'}] duplicate-in-run check")
    ok = ok and dup_ok

    import tempfile as _tf, pathlib as _pl, sys as _sys
    _mod = _sys.modules[__name__]
    with _tf.TemporaryDirectory() as _td:
        _root = _pl.Path(_td)
        (_root / "project" / "data" / "animals").mkdir(parents=True)
        (_root / "project" / "data" / "buildings").mkdir(parents=True)
        _animal = _root / "project" / "data" / "animals" / "pig.tres"
        _animal.write_text('id = "pig"\nfact_text_pool = Array[String](["old"])\n')
        _bldg = _root / "project" / "data" / "buildings" / "well.tres"
        _bldg.write_text('id = "well"\nfact_text = "old"\n')
        _bad = _root / "project" / "data" / "animals" / "broken.tres"
        _bad.write_text('id = "broken"\nfact_text_pool = "not an array"\n')
        _saved = (_mod.REPO_ROOT, _mod.DATA_DIR)
        try:
            _mod.REPO_ROOT = _root
            _mod.DATA_DIR = _root / "project" / "data" / "animals"
            write_tres("pig", ["new one", "new two"], target="animal_pool")
            write_tres("well", ["a well fact"], target="building_text")
            _missing = write_tres("nosuch", ["x"], target="animal_pool")
            _refused = write_tres("broken", ["x"], target="animal_pool")
        finally:
            _mod.REPO_ROOT, _mod.DATA_DIR = _saved

        _animal_ok = 'fact_text_pool = Array[String](["new one", "new two"])' in _animal.read_text()
        print(f"[{'PASS' if _animal_ok else 'FAIL'}] animal pool written correctly")
        ok = ok and _animal_ok

        _bldg_ok = 'fact_text = "a well fact"' in _bldg.read_text() and "fact_text_pool" not in _bldg.read_text()
        print(f"[{'PASS' if _bldg_ok else 'FAIL'}] building text written correctly")
        ok = ok and _bldg_ok

        _missing_ok = "WARNING" in _missing
        print(f"[{'PASS' if _missing_ok else 'FAIL'}] missing file reported as warning")
        ok = ok and _missing_ok

        _refused_ok = "WARNING" in _refused and '"not an array"' in _bad.read_text()
        print(f"[{'PASS' if _refused_ok else 'FAIL'}] malformed field refused (regression test for strict guard)")
        ok = ok and _refused_ok

    print()
    _tres_count = len(list((REPO_ROOT / roster_data.ANIMALS_DIR).glob("*.tres")))
    _derived_ok = len(ROSTER) == _tres_count and _tres_count > 0
    print(f"[{'PASS' if _derived_ok else 'FAIL'}] ROSTER is derived from the data dir "
          f"({len(ROSTER)} species from {_tres_count} .tres files), not hardcoded")
    ok = ok and _derived_ok


    # Cost ledger. The asset pipeline's stage 8 reads the `cost` key this writes, so the
    # accumulation, the sticky usd_known flag and the per-species delta are all load-bearing.
    _before = run_cost()
    _record_cost(10, 100, 0.01, True)
    _record_cost(5, 50, 0.02, True)
    _delta = cost_delta(_before, run_cost())
    _ledger_ok = (_delta["in"] == 15 and _delta["out"] == 150
                  and round(_delta["usd"], 4) == 0.03 and _delta["usd_known"])
    print(f"[{'PASS' if _ledger_ok else 'FAIL'}] cost ledger accumulates tokens and dollars "
          f"per species (got {_delta})")
    ok = ok and _ledger_ok

    _record_cost(1, 1, 0.0, False)
    _unknown_ok = not run_cost()["usd_known"] and "not reported" in format_cost(run_cost())
    print(f"[{'PASS' if _unknown_ok else 'FAIL'}] one backend with no price makes the whole "
          f"total unknown, and the printed line says so instead of showing a partial sum")
    ok = ok and _unknown_ok

    _fmt_ok = format_cost({"in": 16, "out": 5564, "usd": 0.2884, "usd_known": True}) \
        == "$0.2884 (16 in / 5,564 out tokens)"
    print(f"[{'PASS' if _fmt_ok else 'FAIL'}] cost line matches the shape stage 6 already prints")
    ok = ok and _fmt_ok

    print("SELFTEST " + ("PASSED" if ok else "FAILED"))
    return 0 if ok else 1


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("species", nargs="*", help='Species display name(s), e.g. "Shiba Inu" "Bull"')
    parser.add_argument("--count", type=int, default=1, help="Fact cards to generate per species (default 1)")
    parser.add_argument("--generator-model", choices=list(MODEL_IDS), default="haiku")
    parser.add_argument("--evaluator-model", choices=list(MODEL_IDS), default=None,
                         help="Must differ from --generator-model. Default: the other of haiku/opus.")
    parser.add_argument("--max-refine", type=int, default=3, help="Circuit breaker threshold (default 3)")
    parser.add_argument("--dry-run", action="store_true", help="Write the archive JSON only; do not touch project/data/animals/*.tres")
    parser.add_argument(
        "--target", choices=("animal_pool", "building_text"), default="animal_pool",
        help="Where accepted copy is written. animal_pool: fact_text_pool in "
             "project/data/animals/<id>.tres (default, unchanged behaviour). "
             "building_text: the single fact_text field in project/data/buildings/<id>.tres.",
    )
    parser.add_argument("--selftest", action="store_true", help="Run the Evaluator against known-bad drafts, no LLM calls, exit nonzero on failure")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    if not args.species:
        parser.error("at least one species is required (or pass --selftest)")

    evaluator_model = args.evaluator_model or ("opus" if args.generator_model != "opus" else "haiku")
    if evaluator_model == args.generator_model:
        parser.error(f"--evaluator-model must differ from --generator-model (both are {evaluator_model!r})")

    generator_model_id = MODEL_IDS[args.generator_model]
    evaluator_model_id = MODEL_IDS[evaluator_model]

    # --target building_text resolves against project/data/buildings/, not the animals
    # roster -- without this the flag Task 13 added is unreachable, because a building
    # display name can never appear in ROSTER.
    if args.target == "building_text":
        lookup, what = roster_data.load_buildings(REPO_ROOT), "building"
    else:
        lookup, what = ROSTER, "species"
    by_display_name = {s.display_name.lower(): s.id for s in lookup.values()}

    exit_code = 0
    for name in args.species:
        species_id = by_display_name.get(name.lower()) or (
            name.lower() if name.lower() in lookup else None)
        if species_id is None:
            print(f"ERROR: unknown {what} {name!r} -- not in the derived roster",
                  file=sys.stderr)
            exit_code = 1
            continue

        before = run_cost()
        result = run_species(species_id, args.count, generator_model_id,
                             evaluator_model_id, args.max_refine,
                             subject=lookup.get(species_id))
        # This species' own spend, not the invocation's running total -- so a caller
        # reading one log (the asset pipeline's stage 8 does) gets that species' cost.
        result["cost"] = cost_delta(before, run_cost())
        json_path = write_output_json(result)
        _progress(f"  cost: {format_cost(result['cost'])}")
        _progress(f"  archive log: {json_path.relative_to(REPO_ROOT)}")

        if args.dry_run:
            _progress("  --dry-run: not writing to project/data/animals/*.tres or the tracker")
        else:
            summary = write_tres(species_id, result["accepted_fact_texts"], target=args.target)
            _progress(f"  live content: {summary}")
            any_escalated = any(c["status"] == "escalated" for c in result["candidates"])
            tracker_summary = update_content_pipeline_status(species_id, result["accepted_fact_texts"], any_escalated)
            _progress(f"  tracker: {tracker_summary}")

        if not result["accepted_fact_texts"]:
            exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
