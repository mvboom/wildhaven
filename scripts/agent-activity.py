#!/usr/bin/env python3
"""Which agents are defined, which are actually working, and which are idle.

Why this exists: `token-report.py` answers "what did this session cost, per subagent."
It cannot answer "is any agent in our roster sitting unused" — that needs the defined
roster cross-referenced against dispatch history across *all* sessions. The idle list is
the point: an agent nobody dispatches is either dead weight or a blocked lane, and both
are worth knowing before planning the next step.

Usage:
    python3 scripts/agent-activity.py                 # all sessions, cumulative
    python3 scripts/agent-activity.py <session-id>    # one session only
    python3 scripts/agent-activity.py --by-task       # every dispatch, newest last

Reads the same transcripts as token-report.py and imports its parsing, so the two can
never disagree about what a token is.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "docs" / "phase0"))

try:
    from importlib import import_module

    _tr = import_module("token-report")
except ModuleNotFoundError:  # pragma: no cover - name has a hyphen on some setups
    import importlib.util

    _spec = importlib.util.spec_from_file_location(
        "token_report", REPO / "docs" / "phase0" / "token-report.py"
    )
    _tr = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_tr)

PROJECT_DIR = _tr.PROJECT_DIR
AGENT_DIR = REPO / ".claude" / "agents"

# Agents the harness supplies. Not part of the project roster, but worth showing
# separately rather than silently dropping — they cost real tokens.
BUILTIN = {"Explore", "Plan", "general-purpose", "claude", "claude-code-guide",
           "statusline-setup", "fork"}


def defined_roster():
    """Agent name -> first line of its description, from .claude/agents/*.md."""
    roster = {}
    for path in sorted(AGENT_DIR.glob("*.md")):
        desc = ""
        for line in path.read_text().splitlines():
            if line.startswith("description:"):
                desc = line[len("description:"):].strip()
                break
        roster[path.stem] = desc
    return roster


def dispatches(session_id=None):
    """Yield (session_id, agent_type, description, billable, mtime) per dispatch."""
    if session_id:
        session_dirs = [PROJECT_DIR / session_id]
    else:
        session_dirs = [p for p in PROJECT_DIR.iterdir() if p.is_dir()]

    for sdir in session_dirs:
        subagents = sdir / "subagents"
        if not subagents.is_dir():
            continue
        for meta_path in sorted(subagents.glob("*.meta.json"), key=lambda p: p.stat().st_mtime):
            transcript = meta_path.with_suffix("").with_suffix(".jsonl")
            if not transcript.exists():
                continue
            try:
                meta = json.loads(meta_path.read_text())
            except json.JSONDecodeError:
                continue
            yield (
                sdir.name,
                meta.get("agentType", "?"),
                meta.get("description", "?"),
                _tr.billable(_tr.totals(transcript)),
                meta_path.stat().st_mtime,
            )


def main_loop_total(session_id=None):
    """Orchestration cost — the line that scales with dispatch count, not agent work."""
    paths = ([PROJECT_DIR / f"{session_id}.jsonl"] if session_id
             else list(PROJECT_DIR.glob("*.jsonl")))
    return sum(_tr.billable(_tr.totals(p)) for p in paths if p.exists())


def report(session_id=None, by_task=False):
    roster = defined_roster()
    rows = list(dispatches(session_id))

    if by_task:
        rows.sort(key=lambda r: r[4])
        width = max((len(r[1]) for r in rows), default=10)
        print(f"{'agent':{width}}  {'billable':>10}  description")
        print("-" * (width + 14 + 50))
        for _sid, agent, desc, bill, _mt in rows:
            print(f"{agent:{width}}  {bill:>10,}  {desc}")
        return

    counts, tokens = defaultdict(int), defaultdict(int)
    for _sid, agent, _desc, bill, _mt in rows:
        counts[agent] += 1
        tokens[agent] += bill

    agent_total = sum(tokens.values())
    orchestration = main_loop_total(session_id)
    grand = agent_total + orchestration

    scope = f"session {session_id}" if session_id else "all sessions"
    print(f"Wildhaven agent activity — {scope}\n")

    def block(title, names):
        if not names:
            return
        print(title)
        width = max(len(n) for n in names)
        for name in sorted(names, key=lambda n: -tokens[n]):
            share = (tokens[name] / grand * 100) if grand else 0.0
            print(f"  {name:{width}}  {counts[name]:>3} dispatch(es)  "
                  f"{tokens[name]:>11,}  {share:>5.1f}%")
        print()

    project = [n for n in roster if counts[n]]
    idle = [n for n in roster if not counts[n]]
    builtin = [n for n in counts if n not in roster and n in BUILTIN]
    unknown = [n for n in counts if n not in roster and n not in BUILTIN]

    block("PROJECT AGENTS — working", project)
    block("BUILT-IN AGENTS", builtin)
    block("UNRECOGNISED agentType (renamed or deleted definition?)", unknown)

    if idle:
        print("PROJECT AGENTS — NEVER DISPATCHED")
        width = max(len(n) for n in idle)
        for name in sorted(idle):
            print(f"  {name:{width}}  {roster[name][:88]}")
        print("\n  An idle agent is either dead weight or a blocked lane. Check which.\n")

    print(f"{'agents':>28}  {agent_total:>11,}")
    print(f"{'main loop (orchestration)':>28}  {orchestration:>11,}"
          f"   {orchestration / agent_total:.2f}:1" if agent_total else "")
    print(f"{'TOTAL':>28}  {grand:>11,}")
    print(f"\n  {len(rows)} dispatch(es). Orchestration scales with dispatch count, not "
          f"agent work\n  (gdd.md -> Technical Strategy #5): many small dispatches cost "
          f"proportionally more.")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:]]
    by_task = "--by-task" in args
    args = [a for a in args if not a.startswith("--")]
    report(args[0] if args else None, by_task=by_task)
