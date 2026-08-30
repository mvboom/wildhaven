#!/usr/bin/env python3
"""Per-agent token report from Claude Code session transcripts.

Why this exists: `/cost` reports subscription-level usage, not per-session token
splits, so measurement.md step 1 cannot be satisfied from the CLI. The transcripts
carry exact per-message `usage` objects, so the split is recoverable — retroactively,
and broken out per subagent.

Usage:
    python3 docs/phase0/token-report.py                 # all sessions, newest first
    python3 docs/phase0/token-report.py <session-id>    # one session, per-agent rows

Transcript layout (Claude Code, verified 2026-07-20):
    ~/.claude/projects/<project-slug>/<session-id>.jsonl            # main loop
    ~/.claude/projects/<project-slug>/<session-id>/subagents/
        agent-<id>.jsonl        # that subagent's messages
        agent-<id>.meta.json    # {agentType, description, model, ...}

Subagent usage does NOT appear in the main-loop file — the two must be summed for a
session total.
"""

import json
import sys
from pathlib import Path

PROJECT_DIR = Path.home() / ".claude" / "projects" / "-workspaces-habitown"
FIELDS = (
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
)


def totals(jsonl_path):
    """Sum usage fields across every assistant message in a transcript."""
    acc = dict.fromkeys(FIELDS, 0)
    with open(jsonl_path) as fh:
        for line in fh:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue  # partial trailing write on a live session
            usage = (entry.get("message") or {}).get("usage")
            if not usage:
                continue
            for field in FIELDS:
                acc[field] += usage.get(field, 0)
    return acc


def billable(t):
    """Fresh tokens only. Cache reads are excluded — they price differently."""
    return t["input_tokens"] + t["output_tokens"] + t["cache_creation_input_tokens"]


def agents(session_id):
    """Yield (label, totals) per subagent, in spawn order."""
    subagent_dir = PROJECT_DIR / session_id / "subagents"
    if not subagent_dir.is_dir():
        return
    for meta_path in sorted(subagent_dir.glob("*.meta.json"), key=lambda p: p.stat().st_mtime):
        transcript = meta_path.with_suffix("").with_suffix(".jsonl")
        if not transcript.exists():
            continue
        meta = json.loads(meta_path.read_text())
        label = f"{meta.get('agentType', '?')}: {meta.get('description', '?')}"
        yield label, totals(transcript)


def report(session_id):
    main_path = PROJECT_DIR / f"{session_id}.jsonl"
    if not main_path.exists():
        sys.exit(f"no transcript for session {session_id}")

    rows = [("main loop", totals(main_path))] + list(agents(session_id))
    width = max(len(label) for label, _ in rows)

    header = f"{'':{width}}  {'input':>9} {'output':>9} {'cache-rd':>11} {'cache-wr':>9} {'billable':>9}"
    print(header)
    print("-" * len(header))
    for label, t in rows:
        print(
            f"{label:{width}}  {t['input_tokens']:>9,} {t['output_tokens']:>9,} "
            f"{t['cache_read_input_tokens']:>11,} {t['cache_creation_input_tokens']:>9,} "
            f"{billable(t):>9,}"
        )
    print("-" * len(header))
    grand = {f: sum(t[f] for _, t in rows) for f in FIELDS}
    print(
        f"{'SESSION TOTAL':{width}}  {grand['input_tokens']:>9,} {grand['output_tokens']:>9,} "
        f"{grand['cache_read_input_tokens']:>11,} {grand['cache_creation_input_tokens']:>9,} "
        f"{billable(grand):>9,}"
    )


def list_sessions():
    paths = sorted(
        PROJECT_DIR.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True
    )
    for path in paths:
        t = totals(path)
        n_agents = len(list((PROJECT_DIR / path.stem / "subagents").glob("*.meta.json"))) \
            if (PROJECT_DIR / path.stem / "subagents").is_dir() else 0
        print(
            f"{path.stem}  {billable(t):>9,} billable (main loop)"
            f"  {n_agents} subagent(s)"
        )


if __name__ == "__main__":
    if len(sys.argv) > 1:
        report(sys.argv[1])
    else:
        list_sessions()
