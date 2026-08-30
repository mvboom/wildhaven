"""LLM backend and the propose-values stage.

Backend selection copies scripts/fact_card_pipeline.py's convention exactly so the three
pipelines behave identically on the same machine: "cli" shells out to `claude -p`,
reusing this machine's authenticated Claude Code session; "sdk" calls the Messages API
with ANTHROPIC_API_KEY. Override with ASSET_BACKEND.

THIS STAGE PROPOSES; IT NEVER DECIDES. Decision.value stays None regardless of how
confident the model sounds -- "all tuning values are the human's" (.claude/CLAUDE.md).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess

from assetpipe.review import Decision

MODEL_IDS = {
    "haiku": "claude-haiku-4-5-20251001",
    "sonnet": "claude-sonnet-5",
    "opus": "claude-opus-5",
}
BACKEND = os.environ.get("ASSET_BACKEND") or ("cli" if shutil.which("claude") else "sdk")

SYSTEM = """You are Wildhaven's content design assistant.

Wildhaven is a kids' (ages 6-10) wildlife town-building game. You are given one new
piece of content and the schema fields it needs.

Return a PROPOSAL for each field, with a source and a confidence. You are NOT deciding
anything: a human rules every value afterwards. A field you cannot source is better
omitted than guessed -- omission is recorded honestly as "unproposed"; a fabricated
source is not recoverable.

Output JSON only, no prose, no markdown fences:
{"<field>": {"proposal": <value>, "source": "<where this comes from>",
             "confidence": "high"|"med"|"low"}}
"""


def build_prompts(spec, display: str, probe, notes: str) -> tuple[str, str]:
    lines = [f"Content type: {spec.name} ({spec.schema})",
             f"Name: {display}",
             f"Model format: {probe.fmt}",
             f"Animation clips present: {probe.clips or 'none'}",
             f"Notes: {notes or '(none)'}", "", "Fields to propose:"]
    for f in spec.fields:
        lines.append(f"- {f.name} ({f.kind}) -- sourcing: {f.source_hint}")
    return SYSTEM, "\n".join(lines)


def call_json(system: str, user: str, model: str) -> tuple[dict, dict]:
    if BACKEND == "cli":
        proc = subprocess.run(
            ["claude", "-p", "--safe-mode", "--system-prompt", system,
             "--output-format", "json", "--model", model, user],
            capture_output=True, text=True, check=True, timeout=180)
        envelope = json.loads(proc.stdout)
        usage = envelope.get("usage", {})
        return _loads(envelope.get("result", "")), {
            "in": usage.get("input_tokens", 0), "out": usage.get("output_tokens", 0),
            "usd": envelope.get("total_cost_usd", 0.0), "model": model}
    import anthropic
    client = anthropic.Anthropic()
    msg = client.messages.create(model=model, max_tokens=2048, system=system,
                                 messages=[{"role": "user", "content": user}])
    return _loads(msg.content[0].text), {
        "in": msg.usage.input_tokens, "out": msg.usage.output_tokens,
        "usd": 0.0, "model": model}


def _loads(text: str) -> dict:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(text)


def to_decisions(spec, proposals: dict) -> list[Decision]:
    out: list[Decision] = []
    for f in spec.fields:
        got = proposals.get(f.name) or {}
        out.append(Decision(
            field=f.name,
            proposal=got.get("proposal"),
            source=got.get("source") or f.source_hint,
            confidence=got.get("confidence", "unproposed") if got else "unproposed",
            value=None,
        ))
    return out


def propose(spec, display: str, probe, notes: str,
            model: str = MODEL_IDS["sonnet"]) -> tuple[list[Decision], dict]:
    system, user = build_prompts(spec, display, probe, notes)
    parsed, usage = call_json(system, user, model)
    return to_decisions(spec, parsed), usage


def selftest_cases(c) -> None:
    from assetpipe.adapters import animal
    from assetpipe.formats import ModelProbe

    c.check(BACKEND in ("cli", "sdk"), "a backend is selected without network access")
    c.check("haiku" in MODEL_IDS and "opus" in MODEL_IDS, "model aliases available")

    sys_prompt, user_prompt = build_prompts(
        animal.SPEC, "Pig", ModelProbe(fmt="fbx", clips=["Idle", "Walk"]), "farm animal")
    for f in animal.SPEC.fields:
        c.check(f.name in user_prompt, f"prompt asks for {f.name}")
        c.check(f.source_hint in user_prompt, f"prompt carries {f.name}'s sourcing hint")
    c.check("PROPOSAL" in sys_prompt.upper(), "system prompt frames output as proposals")
    c.check("Idle" in user_prompt and "Walk" in user_prompt, "prompt states the real clips")

    ds = to_decisions(animal.SPEC, {"scout_radius": {"proposal": 10, "confidence": "med"}})
    by_name = {d.field: d for d in ds}
    c.eq(by_name["scout_radius"].proposal, 10, "proposal recorded")
    c.eq(by_name["scout_radius"].confidence, "med", "confidence recorded")
    c.check(all(d.value is None for d in ds), "no proposal becomes a value")
    c.eq(by_name["personality"].confidence, "unproposed",
         "a field the model skipped still reaches the checkout, marked unproposed")
