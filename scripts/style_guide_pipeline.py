"""
Wildhaven Style Guide GER Pipeline -- Generator / Evaluator (scored) / Refiner.

Wildhaven's PRODUCTION mechanism for Gentle Displacement copy (-> D-49; originally built
for archive/mark-vanderboom-assignment-7/, then adopted going forward rather than
shelved, mirroring D-48's fact-card pipeline adoption -- see that folder's README and
game-design/style-guide-pipeline.md).

Content type: per-species Gentle Displacement warning/departure/relocation lines -- the
WARN_/DEPART_/MOVE_ constants and _WARN_HOME/_WARN_STRUCTURE/_DEPART/_MOVE lookup tables
in project/scripts/ui/displacement_copy.gd. Nine cleared-pool species (Deer, Stag, Horse,
Donkey, Cow, Bull, Alpaca, Husky, Shiba Inu) have no line of their own today and fall
through to WARN_GENERIC/DEPART_GENERIC/MOVE_GENERIC (see docs/content/displacement-copy.md
-> "Warning -- home lines": "WARN_GENERIC covers the nine cleared-pool species, which have
no copy of any kind yet"). This pipeline closes that gap, one species at a time.

The style guide this pipeline enforces (quoted from docs/content/displacement-copy.md and
gdd.md -> Systems in Play -> Gentle Displacement -- neither invented here). THREE
constraint types, unlike the fact-card pipeline's single predation-ban/register rule:

  1. TONE/VOICE       -- the "plain game voice," never the News Report bulletin voice:
                          factual, upbeat, disclosure not deterrence -- no plea, no
                          judgment, no urgency, no residue afterward.
  2. VOCABULARY/
     FRAMING           -- the villager doctrine: never combine the player's action and
                          the family's hardship in one sentence; destination, not cause;
                          no loss-coded vocabulary ("lost", "nowhere", "kicked out"...);
                          never names another roster species or a habitat-tag id.
  3. FORMATTING/
     STRUCTURE         -- the Read-Aloud constraint: one complete sentence, no em dashes,
                          parentheses, or bare fragments; names the affected home by
                          family ("the {species} family").

Unlike the fact-card pipeline's binary Evaluator, assignment 7 requires a SCORED
Evaluator -- SCORE: [X/10] + REASON -- and a Refiner that rewrites using that REASON
specifically, not a blind retry.

Loop, per candidate line:
  Generator -- drafts a WARN/DEPART/MOVE line (LLM call, --generator-model). `--demo`
               mode uses one of three FIXED adversarial prompts, each engineered to trip
               exactly one constraint type, for the assignment's required 3
               before/after violation-class demonstration. Real mode drafts genuinely
               on-style copy for a real cleared-pool species.
  Evaluator -- deterministic sweep (banned loss-vocabulary, em dash/parens, the closed
               species-name graph check, family-naming, sentence count) feeds forward as
               evidence, then an LLM judge (a DIFFERENT model than the Generator, same
               integrity rationale as the fact-card pipeline) scores 1-10 against all
               three constraint types and returns SCORE + REASON.
  Refiner   -- a separate LLM call, re-prompted with the Evaluator's REASON verbatim,
               targeting a perfect 10/10 -- the assignment's own Refiner prompt, almost
               verbatim.
  The loop caps at --max-refine attempts (default 3, mirroring the fact-card pipeline's
  circuit breaker as a safety net, not a scored requirement here) and keeps the
  highest-scoring draft if 10/10 is never reached ("escalated", same vocabulary as the
  fact-card pipeline's Circuit Breaker).

Two ways to run it, auto-selected (same convention as scripts/fact_card_pipeline.py):
  GER_BACKEND=cli (default if `claude` is on PATH) | GER_BACKEND=sdk (needs
  ANTHROPIC_API_KEY, `pip install anthropic`).

Run (from repo root or scripts/, either works):
  python3 scripts/style_guide_pipeline.py --demo
  python3 scripts/style_guide_pipeline.py bull shiba_inu
  python3 scripts/style_guide_pipeline.py bull --line-type warn
  python3 scripts/style_guide_pipeline.py --selftest   # Evaluator only, no LLM calls

Scope, explicitly (-> D-49): Gentle Displacement copy ONLY (warning/departure/relocation
lines). Not News Reports, not the first-time nudge, not fact cards -- those stay their
own remit (D-48's fact-card pipeline; content-writer.md's hand-drafted remit for the
rest).
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
    """Walks upward from `start` looking for the real UI script this pipeline patches,
    rather than assuming a fixed parent-count -- this file is intentionally COPIED to
    more than one location (the live tool at scripts/, plus a submission snapshot in
    archive/mark-vanderboom-assignment-7/ -- see that folder's README), and a
    `parents[N]` assumption would silently miscompute every path the moment it's run
    from the "wrong" copy."""
    marker = Path("project") / "scripts" / "ui" / "displacement_copy.gd"
    for candidate in (start, *start.parents):
        if (candidate / marker).exists():
            return candidate
    raise RuntimeError(f"Could not locate the Wildhaven repo root above {start} (no {marker} found).")


REPO_ROOT = _find_repo_root(Path(__file__).resolve().parent)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roster_data  # noqa: E402  (needs REPO_ROOT above)
RosterSpecies = roster_data.RosterSpecies
DISPLACEMENT_COPY_PATH = REPO_ROOT / "project" / "scripts" / "ui" / "displacement_copy.gd"
OUTPUT_DIR = Path(__file__).resolve().parent / "style_guide_pipeline_output"

MODEL_IDS = {
    "haiku": "claude-haiku-4-5-20251001",
    "opus": "claude-opus-5",
    "sonnet": "claude-sonnet-5",
}

LINE_TYPES = ("warn", "depart", "move")

# Loss-coded vocabulary the villager doctrine bans outright (docs/content/displacement-copy.md
# -> "a displaced villager family is never described as losing a home, only as finding one").
LOSS_WORDS = [
    "lose", "loses", "losing", "lost",
    "kicked out", "kick out", "kicks out",
    "nowhere", "vanish", "vanishes", "vanished", "gone",
    "homeless",
]

# Read-Aloud punctuation ban (docs/content/displacement-copy.md: "no em dashes, parentheses,
# glyphs, or bare fragments"). Matches a literal em dash, en dash, ASCII double-hyphen used as
# a dash, and parentheses.
FORBIDDEN_PUNCT_PATTERN = re.compile(r"[—–()]|--")

# Curly quotes and apostrophes are fine (already used roster-wide); anything else non-ASCII
# reads as a "glyph" the Read-Aloud voice can't handle.
ALLOWED_NON_ASCII = set("‘’“”")

MAX_SENTENCES = 1


# The roster is DERIVED from project/data/animals/*.tres -- see scripts/roster_data.py.
# It feeds the closed-graph check: a displacement line may not name any OTHER roster
# species. Deriving it means a newly imported species joins the graph the moment its
# .tres exists, and a missing data dir raises instead of quietly shrinking the check.
ROSTER = roster_data.load_roster(REPO_ROOT)


# ---------------------------------------------------------------------------
# LLM call plumbing (cli/sdk backends) -- identical convention to
# scripts/fact_card_pipeline.py; model is a per-call parameter since Generator,
# Evaluator and Refiner deliberately use independently-chosen models.
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


def _call_json_sdk(system: str, user: str, model: str) -> dict:
    messages = [{
        "role": "user",
        "content": user + "\n\nRespond with ONLY a JSON object, no prose, no markdown fences.",
    }]
    resp = _client().messages.create(model=model, max_tokens=1024, system=system, messages=messages)
    # The Messages API returns usage but no dollar figure, and this repo has no
    # pricing table -- so tokens are real and usd is explicitly unknown.
    _record_cost(resp.usage.input_tokens, resp.usage.output_tokens, 0.0, False)
    text = next(block.text for block in reversed(resp.content) if block.type == "text")
    return _parse_json_response(text)


def _call_json_cli(system: str, user: str, model: str) -> dict:
    result = subprocess.run(
        [
            "claude", "-p", "--safe-mode",
            "--allowedTools", "",
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


def _call_json(system: str, user: str, model: str) -> dict:
    if BACKEND == "cli":
        return _call_json_cli(system, user, model)
    return _call_json_sdk(system, user, model)


def _progress(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# The style guide, quoted (not invented) from docs/content/displacement-copy.md and
# gdd.md -> Systems in Play -> Gentle Displacement. Shared verbatim between the
# Generator, the Evaluator's LLM judge and the Refiner so all three are grading/writing
# against the exact same rules.
# ---------------------------------------------------------------------------

STYLE_GUIDE = """Wildhaven's Gentle Displacement copy -- warning, departure and
relocation lines for animals whose home the player's own action affects. Every line
must satisfy THREE constraint types:

1. TONE/VOICE -- the "plain game voice," never the News Report bulletin voice.
   gdd.md: "The displacement warning is deliberately NOT that voice; consent copy must
   never sound like flavor." Factual, upbeat, disclosure not deterrence: no "please", no
   "poor", no "sadly", no "are you sure", no pleading, no judgment of the player, no
   urgency, and no residue afterward (nothing refers back to the warning later).

2. VOCABULARY/FRAMING -- the villager doctrine (gdd.md, decided, not re-openable here):
   "a displaced villager family is never described as losing a home, only as finding
   one." The warning names the HABITAT, never the loss. Departure/relocation carry the
   DESTINATION, not the cause. The copy may NEVER put the player's action and the
   family's hardship in one sentence, nor leave a family with nowhere named to go. No
   loss-coded words: "lose", "lost", "losing", "nowhere", "kicked out", "vanish",
   "gone", "homeless". Never names another Wildhaven species (not even as an adjective)
   and never names a habitat-tag identifier (water/forest/open_grass/quiet/cover/
   flowers/sand/rocks/cultivated/house) -- the same closed-graph rule the fact-card
   pipeline enforces, applied here too.

3. FORMATTING/STRUCTURE -- the Read-Aloud constraint (every line must be readable by a
   screen reader and by a pre-fluent 6-year-old): exactly ONE complete sentence, no em
   dashes, no parentheses, no bare fragments. Names the affected home BY FAMILY -- "the
   {display_name} family" -- never just "they" or "it".
"""

DEMO_LINE_KIND = {
    "warn": "a WARNING line -- fires while the player can still change course, naming the "
            "habitat the family will need to look for.",
    "depart": "a DEPARTURE line -- fires after the family has moved away to find a home "
              "elsewhere.",
    "move": "a RELOCATION line -- fires when the family found a new spot and moved there.",
}


# ---------------------------------------------------------------------------
# Generator
# ---------------------------------------------------------------------------

GENERATOR_SYSTEM = f"""You are Wildhaven's Content Writer, drafting Gentle Displacement
copy for a kids' (ages 6-10) wildlife town-building game.

{STYLE_GUIDE}

Output JSON with exactly one key: "text" -- the single line of copy.
"""

ADVERSARIAL_GENERATOR_SYSTEM = f"""You are drafting a DELIBERATELY BROKEN test case for
Wildhaven's Gentle Displacement copy -- a kids' (ages 6-10) wildlife town-building game.
This draft exists ONLY to test whether an automated Evaluator catches a specific style
violation. Do not announce that you are breaking a rule inside the text itself -- write
it as if it were a real, if flawed, attempt.

The full style guide this draft must APPEAR to follow but is instructed to violate in one
specific way (below):

{STYLE_GUIDE}

Output JSON with exactly one key: "text" -- the single line of copy.
"""


def generator(
    species: RosterSpecies,
    line_type: str,
    model: str,
    adversarial_instruction: str | None = None,
) -> str:
    kind = DEMO_LINE_KIND[line_type]
    user = (
        f"Species: {species.display_name}\n"
        f"Habitat needs: {', '.join(species.tags)}\n"
        f"Write {kind}\n"
    )
    if adversarial_instruction:
        user += (
            f"\nFor this test draft specifically, deliberately violate the style guide "
            f"this way: {adversarial_instruction}\n"
        )
        system = ADVERSARIAL_GENERATOR_SYSTEM
    else:
        system = GENERATOR_SYSTEM
    result = _call_json(system, user, model)
    return str(result.get("text", ""))


# ---------------------------------------------------------------------------
# Evaluator, part 1: deterministic (fast, free, catches what a keyword sweep can)
# ---------------------------------------------------------------------------

def deterministic_evaluate(text: str, species: RosterSpecies, line_type: str) -> dict:
    problems: list[str] = []
    stripped = text.strip()
    if not stripped:
        problems.append("text is empty.")
        return {"passed": False, "problems": problems}

    lowered = stripped.lower()

    for word in LOSS_WORDS:
        if re.search(rf"\b{re.escape(word)}\b", lowered):
            problems.append(
                f'uses banned loss-coded word "{word}" -- the villager doctrine requires '
                f"finding a home, never losing one."
            )

    if FORBIDDEN_PUNCT_PATTERN.search(stripped):
        problems.append(
            "contains an em dash, en dash, parenthetical, or double-hyphen -- breaks the "
            "Read-Aloud one-complete-sentence constraint."
        )

    for ch in stripped:
        if ord(ch) > 0x7E and ch not in ALLOWED_NON_ASCII:
            problems.append(f'contains a non-Read-Aloud-safe glyph ("{ch}").')
            break

    if "{" in stripped or "}" in stripped:
        problems.append(
            "contains an unresolved template placeholder (a literal { or } character) -- "
            "this file's {display_name} syntax belongs only in the *_GENERIC fallback "
            "templates, never in a per-species line."
        )

    for other_id, other in ROSTER.items():
        if other_id == species.id:
            continue
        for name in {other_id.replace("_", " "), other.display_name.lower()}:
            if re.search(rf"\b{re.escape(name)}\b", lowered):
                problems.append(
                    f'names another roster species ("{other.display_name}") -- breaks the '
                    f"closed predation graph."
                )
                break

    for tag in ("water", "forest", "open_grass", "quiet", "cover", "flowers", "sand",
                "rocks", "cultivated", "house"):
        if re.search(rf"\b{re.escape(tag)}\b", lowered):
            problems.append(f'names the habitat-tag identifier "{tag}" directly.')

    family_phrase = f"{species.display_name.lower()} family"
    if family_phrase not in lowered:
        problems.append(
            f'does not name the affected home by family ("the {species.display_name} '
            f'family") -- required structural rule.'
        )

    sentence_count = len([s for s in re.split(r"(?<=[.!?])\s+", stripped) if s.strip()])
    if sentence_count > MAX_SENTENCES:
        problems.append(f"{sentence_count} sentences -- displacement lines are exactly one sentence.")
    if sentence_count == 0:
        problems.append("no sentence-ending punctuation found -- not recognizable as one sentence.")

    if line_type in ("depart", "move"):
        if not any(p in lowered for p in (" to ", " into ", " toward", " for ")):
            problems.append(
                "no destination phrase found -- departure/relocation lines must name "
                "somewhere the family is going, not just that they left."
            )

    return {"passed": len(problems) == 0, "problems": problems}


# ---------------------------------------------------------------------------
# Evaluator, part 2: LLM judge -- a DIFFERENT model than the Generator, scores 1-10
# ---------------------------------------------------------------------------

JUDGE_SYSTEM = f"""You are Wildhaven's independent style-guide judge -- a DIFFERENT model
from whichever one drafted this line, specifically so you are not grading your own work.

{STYLE_GUIDE}

A separate deterministic sweep already caught some mechanical issues (listed below, if
any) -- do not just repeat them uncritically, but you MAY agree with them and you should
weigh them into your score. Your real job is everything a keyword sweep can't catch:
oblique tone problems, subtle framing that still puts the player's action next to the
family's hardship even without a banned word, an implied loss with no explicit "lost",
and whether the line actually reads as one clean, complete, Read-Aloud-safe sentence.

Grade the draft 1-10 against the three constraint types above. Output your response
strictly as JSON with exactly these keys:
- "score": integer 1-10 (10 = perfect, ships as-is; anything below 10 has a real issue)
- "reason": a detailed explanation of which constraint type(s) were violated and why, or
  why it scored full marks
"""


def llm_judge_evaluate(text: str, species: RosterSpecies, line_type: str, det: dict, model: str) -> dict:
    user = (
        f"Species: {species.display_name}\n"
        f"Line type: {line_type}\n"
        f'Draft: "{text}"\n'
    )
    if det["problems"]:
        user += "\nDeterministic sweep already found:\n" + "\n".join(f"- {p}" for p in det["problems"])
    else:
        user += "\nDeterministic sweep found nothing."
    result = _call_json(JUDGE_SYSTEM, user, model)
    score = int(result.get("score", 1))
    score = max(1, min(10, score))
    if det["problems"] and score >= 10:
        # The deterministic layer is non-negotiable -- a mechanical violation caps the
        # score even if the LLM judge missed it or the judge's own text disagrees.
        score = 9
    return {"score": score, "reason": str(result.get("reason", ""))}


# ---------------------------------------------------------------------------
# Refiner -- a separate LLM call, given the Evaluator's REASON verbatim
# ---------------------------------------------------------------------------

REFINER_SYSTEM = f"""You are Wildhaven's style-guide Refiner. You are given a line of
Gentle Displacement copy and an Evaluator's REASON explaining what's wrong with it.
Rewrite the line so it scores a perfect 10/10 against the style guide below. Fix
specifically what the REASON describes -- do not just try a different draft blind.

{STYLE_GUIDE}

Output JSON with exactly one key: "text" -- the rewritten single line of copy.
"""


def refiner(original_text: str, reason: str, species: RosterSpecies, line_type: str, model: str) -> str:
    kind = DEMO_LINE_KIND[line_type]
    user = (
        f"Species: {species.display_name}\n"
        f"Habitat needs: {', '.join(species.tags)}\n"
        f"This is {kind}\n"
        f'Original text: "{original_text}"\n'
        f"Evaluator's REASON: {reason}\n"
    )
    result = _call_json(REFINER_SYSTEM, user, model)
    return str(result.get("text", ""))


# ---------------------------------------------------------------------------
# The loop: Generator -> Evaluator -> Refiner, up to --max-refine attempts
# ---------------------------------------------------------------------------

def run_one_candidate(
    species: RosterSpecies,
    line_type: str,
    generator_model: str,
    evaluator_model: str,
    refiner_model: str,
    max_refine: int,
    adversarial_instruction: str | None = None,
) -> dict:
    _progress(f"    generating initial draft ({generator_model})...")
    text = generator(species, line_type, generator_model, adversarial_instruction)
    attempts = []

    for attempt_num in range(1, max_refine + 1):
        det = deterministic_evaluate(text, species, line_type)
        judge = llm_judge_evaluate(text, species, line_type, det, evaluator_model)
        attempts.append({
            "attempt": attempt_num,
            "text": text,
            "deterministic": det,
            "score": judge["score"],
            "reason": judge["reason"],
        })
        _progress(f"    attempt {attempt_num}: SCORE {judge['score']}/10 -- {judge['reason'][:90]}")

        if judge["score"] >= 10:
            return {"status": "accepted", "text": text, "score": judge["score"], "attempts": attempts}

        if attempt_num == max_refine:
            break

        _progress(f"    refining ({refiner_model})...")
        text = refiner(text, judge["reason"], species, line_type, refiner_model)

    best = max(attempts, key=lambda a: a["score"])
    return {"status": "escalated", "text": best["text"], "score": best["score"], "attempts": attempts}


# ---------------------------------------------------------------------------
# Demo mode: 3 fixed adversarial cases, one per required violation class
# ---------------------------------------------------------------------------

DEMO_CASES = [
    {
        "violation_class": "tone",
        "species_id": "bull",
        "line_type": "warn",
        "adversarial_instruction": (
            "Write it in an urgent, guilt-tripping tone that pleads with the player and "
            "questions their choice, as if scolding them for what they're about to do."
        ),
    },
    {
        "violation_class": "vocabulary_framing",
        "species_id": "shiba_inu",
        "line_type": "depart",
        "adversarial_instruction": (
            "Say the family lost their home because of what the player did, and don't "
            "say where they're going -- leave it open-ended, as if they have nowhere to go."
        ),
    },
    {
        "violation_class": "formatting",
        "species_id": "husky",
        "line_type": "warn",
        "adversarial_instruction": (
            "Write it as a run-on line with an em dash and a parenthetical aside, and "
            "keep it vague about which family is affected."
        ),
    },
]


def run_demo(generator_model: str, evaluator_model: str, refiner_model: str, max_refine: int) -> dict:
    results = []
    for case in DEMO_CASES:
        species = ROSTER[case["species_id"]]
        _progress(f"=== DEMO [{case['violation_class']}]: {species.display_name} ({case['line_type']}) ===")
        result = run_one_candidate(
            species, case["line_type"], generator_model, evaluator_model, refiner_model,
            max_refine, adversarial_instruction=case["adversarial_instruction"],
        )
        results.append({
            "violation_class": case["violation_class"],
            "species_id": case["species_id"],
            "species_display_name": species.display_name,
            "line_type": case["line_type"],
            "adversarial_instruction": case["adversarial_instruction"],
            "before": result["attempts"][0]["text"],
            "before_score": result["attempts"][0]["score"],
            "before_reason": result["attempts"][0]["reason"],
            "after": result["text"],
            "after_score": result["score"],
            "status": result["status"],
            "attempts": result["attempts"],
        })
    return {"demo_cases": results}


# ---------------------------------------------------------------------------
# Real mode: one species, one or more line types, on-style content generation
# ---------------------------------------------------------------------------

def run_species(
    species_id: str,
    line_types: list[str],
    generator_model: str,
    evaluator_model: str,
    refiner_model: str,
    max_refine: int,
) -> dict:
    species = ROSTER.get(species_id)
    if species is None:
        raise ValueError(f'Unknown species id "{species_id}" -- not in ROSTER.')

    _progress(f"=== {species.display_name} ({species_id}) -- {', '.join(line_types)} ===")
    results = {}
    for line_type in line_types:
        _progress(f"  {line_type}:")
        results[line_type] = run_one_candidate(
            species, line_type, generator_model, evaluator_model, refiner_model, max_refine,
        )
        marker = "ACCEPTED" if results[line_type]["status"] == "accepted" else "ESCALATED"
        _progress(f"  {line_type}: {marker} (score {results[line_type]['score']}/10) -- \"{results[line_type]['text']}\"")

    return {
        "species_id": species_id,
        "species_display_name": species.display_name,
        "generator_model": generator_model,
        "evaluator_model": evaluator_model,
        "refiner_model": refiner_model,
        "max_refine": max_refine,
        "line_results": results,
    }


# ---------------------------------------------------------------------------
# Dual write: archive JSON (grading/audit evidence) + live displacement_copy.gd
# ---------------------------------------------------------------------------

def write_output_json(name: str, result: dict) -> Path:
    """Merges `result["line_results"]` into any prior log for this name instead of
    overwriting it -- a species run for one --line-type must not destroy another
    line-type's evidence from an earlier run against the same species (a real gap this
    pipeline's own first re-run hit: re-running Shiba Inu for --line-type move alone
    clobbered its already-logged warn/depart attempts)."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{name}.json"
    if "line_results" in result and path.exists():
        try:
            prior = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            prior = None
        if prior and "line_results" in prior:
            merged = dict(prior["line_results"])
            merged.update(result["line_results"])
            result = {**result, "line_results": merged}
    path.write_text(json.dumps(result, indent=2))
    return path


# Shared with the sign-off gate (roster_data.verified_line_types) rather than restated,
# so the writer and the gate can never disagree about which constant a line type lives in.
_CONST_PREFIX = roster_data.LINE_TYPE_PREFIX
_ANCHOR_CONST = {"warn": "WARN_GENERIC", "depart": "DEPART_GENERIC", "move": "MOVE_GENERIC"}
_DICT_NAMES = {"warn": ["_WARN_STRUCTURE", "_WARN_HOME"], "depart": ["_DEPART"], "move": ["_MOVE"]}


def _upsert_const(text: str, const_name: str, const_line: str, anchor_const: str) -> str:
    """Idempotent: replaces an existing `const NAME: String = ...` line in place if this
    pipeline already wrote one on a prior run, otherwise inserts right after
    `anchor_const`'s declaration (always present -- it's the *_GENERIC fallback)."""
    existing = re.compile(rf"^const {re.escape(const_name)}: String = .*$", re.MULTILINE)
    if existing.search(text):
        return existing.sub(lambda _m: const_line, text, count=1)
    anchor = re.compile(rf"^(const {re.escape(anchor_const)}: String = .*)$", re.MULTILINE)
    if not anchor.search(text):
        raise RuntimeError(f"anchor const {anchor_const} not found in {DISPLACEMENT_COPY_PATH}")
    return anchor.sub(lambda m: m.group(1) + "\n" + const_line, text, count=1)


def _upsert_dict_entry(text: str, dict_name: str, key: str, value_const: str) -> str:
    block = re.compile(rf"(const {re.escape(dict_name)}: Dictionary = \{{\n)(.*?)(\n\}})", re.DOTALL)
    m = block.search(text)
    if not m:
        raise RuntimeError(f"{dict_name} dictionary block not found in {DISPLACEMENT_COPY_PATH}")
    header, body, footer = m.group(1), m.group(2), m.group(3)
    key_pattern = re.compile(rf'^\t"{re.escape(key)}": .*$', re.MULTILINE)
    new_line = f'\t"{key}": {value_const},'
    if key_pattern.search(body):
        body = key_pattern.sub(lambda _m: new_line, body, count=1)
    else:
        body = body.rstrip("\n") + "\n" + new_line
    return text[:m.start()] + header + body + footer + text[m.end():]


def write_displacement_copy(species_id: str, display_name: str, line_type: str, text: str) -> str:
    """Patches project/scripts/ui/displacement_copy.gd in place: adds/replaces this
    species' WARN_/DEPART_/MOVE_ const (inline-flagged pipeline-generated, awaiting
    content-writer/human sign-off -- the same posture scripts/fact_card_pipeline.py's
    .tres writes use) and wires it into the relevant lookup table(s)."""
    if not DISPLACEMENT_COPY_PATH.exists():
        return f"WARNING: {DISPLACEMENT_COPY_PATH} does not exist -- not written"

    const_name = f"{_CONST_PREFIX[line_type]}_{species_id.upper()}"
    escaped = json.dumps(text, ensure_ascii=False)
    const_line = (
        f"const {const_name}: String = {escaped}  "
        f"# pipeline-generated ({time.strftime('%Y-%m-%d')}, scripts/style_guide_pipeline.py) "
        f"-- AWAITING CONTENT-WRITER SIGN-OFF"
    )

    content = DISPLACEMENT_COPY_PATH.read_text()
    content = _upsert_const(content, const_name, const_line, _ANCHOR_CONST[line_type])
    for dict_name in _DICT_NAMES[line_type]:
        content = _upsert_dict_entry(content, dict_name, species_id, const_name)
    DISPLACEMENT_COPY_PATH.write_text(content)
    return f"wrote {const_name} to {DISPLACEMENT_COPY_PATH.relative_to(REPO_ROOT)} ({', '.join(_DICT_NAMES[line_type])})"


def _plan_line_types(species_id: str, line_types: list) -> tuple:
    """Split the requested line types into (regenerate, leave alone).

    The sign-off gate is per LINE TYPE because the writer is: a species with one verified
    type and two unverified ones regenerates the two and skips the one, instead of either
    overwriting human-approved copy or refusing the species outright.
    """
    verified = roster_data.verified_line_types(
        species_id, REPO_ROOT / roster_data.DISPLACEMENT_COPY, line_types)
    return [lt for lt in line_types if lt not in verified], verified


# ---------------------------------------------------------------------------
# Self-test: proves the deterministic Evaluator catches each violation class, no LLM
# calls -- runnable for grading without API access.
# ---------------------------------------------------------------------------

def selftest() -> int:
    bull = ROSTER["bull"]
    shiba = ROSTER["shiba_inu"]
    cases = [
        ("The bull family has lost their home and has nowhere to go.", "bull", "warn",
         ["lost", "nowhere"], False),
        ("The husky family will look for a new spot -- somewhere quieter (maybe near the barn).",
         "husky", "warn", ["em dash", "parenthetical"], False),
        ("The bull family will look for grass, unlike the fox family nearby.",
         "bull", "warn", ["fox"], False),
        ("They will look for a new home somewhere sunny.", "bull", "warn",
         ["does not name"], False),
        # A real defect this pipeline's first production run actually shipped and this
        # check now catches: a Refiner rewrite that leaves the {display_name} template
        # token unresolved instead of substituting the real species name.
        ("The {display_name} family is settling into their new home with a big yard.",
         "shiba_inu", "move", ["template placeholder"], False),
        ("The shiba inu family moved away to find a new home in the hills.", "shiba_inu",
         "depart", None, True),
        ("The bull family will look for open, grassy fields to graze in.", "bull", "warn",
         None, True),
    ]
    ok = True
    for text, species_id, line_type, expect_substrs, expect_pass in cases:
        species = ROSTER[species_id]
        result = deterministic_evaluate(text, species, line_type)
        got_pass = result["passed"]
        status = "PASS" if got_pass == expect_pass else "FAIL"
        if got_pass != expect_pass:
            ok = False
        if expect_substrs:
            for substr in expect_substrs:
                if not any(substr.lower() in p.lower() for p in result["problems"]):
                    ok = False
                    status = "FAIL"
        print(f"[{status}] passed={got_pass} (expected {expect_pass}): {text[:70]}...")
        for p in result["problems"]:
            print(f"         - {p}")

    print()
    # REGRESSION, review CRITICAL 2: the sign-off gate was per-species while this
    # pipeline's writer is per-line-type, so a default `--line-type all` run overwrote
    # human-approved DEPART_/MOVE_ lines whenever WARN_ was still marked AWAITING.
    # Against real displacement_copy.gd: fox is signed off on all three, horse on none.
    _all = list(LINE_TYPES)
    _fox_todo, _fox_kept = _plan_line_types("fox", _all)
    _fox_ok = _fox_todo == [] and _fox_kept == _all
    print(f"[{'PASS' if _fox_ok else 'FAIL'}] fox's signed-off copy is left alone on "
          f"every line type (regenerate {_fox_todo}, keep {_fox_kept})")
    ok = ok and _fox_ok

    _horse_todo, _horse_kept = _plan_line_types("horse", _all)
    _horse_ok = _horse_todo == _all and _horse_kept == []
    print(f"[{'PASS' if _horse_ok else 'FAIL'}] horse's still-AWAITING copy is fully "
          f"regenerable (regenerate {_horse_todo}, keep {_horse_kept})")
    ok = ok and _horse_ok

    _prefix_ok = _CONST_PREFIX is roster_data.LINE_TYPE_PREFIX
    print(f"[{'PASS' if _prefix_ok else 'FAIL'}] the writer's const prefixes ARE the "
          f"gate's -- they cannot drift apart")
    ok = ok and _prefix_ok

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
    parser.add_argument("species", nargs="*", help='Cleared-pool species id(s), e.g. "bull" "shiba_inu"')
    parser.add_argument("--line-type", choices=[*LINE_TYPES, "all"], default="all")
    parser.add_argument("--demo", action="store_true", help="Run the 3 fixed before/after violation-class demo cases")
    parser.add_argument("--generator-model", choices=list(MODEL_IDS), default="haiku")
    parser.add_argument("--evaluator-model", choices=list(MODEL_IDS), default=None,
                         help="Must differ from --generator-model. Default: the other of haiku/opus.")
    parser.add_argument("--refiner-model", choices=list(MODEL_IDS), default=None,
                         help="Default: same as --generator-model.")
    parser.add_argument("--max-refine", type=int, default=3, help="Refine attempts before escalating (default 3)")
    parser.add_argument("--dry-run", action="store_true", help="Write the archive JSON only; do not touch displacement_copy.gd")
    parser.add_argument("--selftest", action="store_true", help="Run the deterministic Evaluator against known-bad drafts, no LLM calls")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    evaluator_model = args.evaluator_model or ("opus" if args.generator_model != "opus" else "haiku")
    if evaluator_model == args.generator_model:
        parser.error(f"--evaluator-model must differ from --generator-model (both are {evaluator_model!r})")
    refiner_model = args.refiner_model or args.generator_model

    generator_model_id = MODEL_IDS[args.generator_model]
    evaluator_model_id = MODEL_IDS[evaluator_model]
    refiner_model_id = MODEL_IDS[refiner_model]

    if args.demo:
        result = run_demo(generator_model_id, evaluator_model_id, refiner_model_id, args.max_refine)
        json_path = write_output_json("demo", result)
        _progress(f"  archive log: {json_path.relative_to(REPO_ROOT)}")
        for case in result["demo_cases"]:
            print(f"\n[{case['violation_class']}] {case['species_display_name']} ({case['line_type']})")
            print(f"  BEFORE (score {case['before_score']}/10): {case['before']}")
            print(f"  REASON: {case['before_reason']}")
            print(f"  AFTER  (score {case['after_score']}/10): {case['after']}")
        return 0

    if not args.species:
        parser.error("at least one species id is required (or pass --demo / --selftest)")

    line_types = list(LINE_TYPES) if args.line_type == "all" else [args.line_type]

    exit_code = 0
    for species_id in args.species:
        species_id = species_id.lower().replace(" ", "_")
        if species_id not in ROSTER:
            print(f"ERROR: unknown species id {species_id!r} -- not in ROSTER", file=sys.stderr)
            exit_code = 1
            continue
        # Refuse only copy a HUMAN has verified, and only the LINE TYPES they verified.
        # Three states exist per line type: verified copy is protected; copy this pipeline
        # generated but nobody has reviewed (still marked AWAITING CONTENT-WRITER SIGN-OFF)
        # is regenerable; a line type with no copy at all -- including a newly imported
        # species -- is the target. The old CLEARED_POOL_IDS allowlist could not tell the
        # second state from the first; its per-species replacement could not tell one line
        # type from another, and so both overwrote signed-off DEPART_/MOVE_ lines on a
        # default run and locked them out when only WARN_ had been signed off.
        todo, verified = _plan_line_types(species_id, line_types)
        if verified:
            print(
                f"NOTE: leaving {species_id!r}'s human-verified "
                f"{', '.join(verified)} copy alone -- refusing to overwrite it. (Copy "
                f"still marked {roster_data.AWAITING_MARKER!r} would be regenerable.)",
                file=sys.stderr,
            )
        if not todo:
            print(
                f"ERROR: every requested line type for {species_id!r} "
                f"({', '.join(line_types)}) is already human-verified -- nothing to "
                f"generate.",
                file=sys.stderr,
            )
            exit_code = 1
            continue

        before = run_cost()
        result = run_species(species_id, todo, generator_model_id, evaluator_model_id, refiner_model_id, args.max_refine)
        # This species' own spend, not the invocation's running total -- so a caller
        # reading one log (the asset pipeline's stage 8 does) gets that species' cost.
        result["cost"] = cost_delta(before, run_cost())
        json_path = write_output_json(species_id, result)
        _progress(f"  cost: {format_cost(result['cost'])}")
        _progress(f"  archive log: {json_path.relative_to(REPO_ROOT)}")

        if args.dry_run:
            _progress("  --dry-run: not writing to displacement_copy.gd")
        else:
            for line_type, line_result in result["line_results"].items():
                summary = write_displacement_copy(species_id, result["species_display_name"], line_type, line_result["text"])
                _progress(f"  {line_type}: {summary}")
                if line_result["status"] == "escalated":
                    exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
