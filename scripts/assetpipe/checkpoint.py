"""The interactive checkpoint: rule the proposals in the terminal, then continue.

WHY THIS EXISTS. Every value at the checkpoint is the human's to rule, and until now the
only way to rule them was to hand-edit `runs/<id>/review.json` or drive `/add-asset` from a
Claude Code session. The second path cannot reach stage 6 at all when the pipeline runs
inside a sandboxed shell: `claude -p` comes up logged out because the session credential is
deny-listed, and the SDK is blocked by DNS. Neither is fixable without weakening the
sandbox. Run from a real terminal, both work -- so the checkpoint belongs there too, and
this turns the pipeline into one command from asset path to build.

`review.json` remains the contract. This writes through `review.apply_rulings` exactly as
`/add-asset` does, so the file-editing and skill paths keep working unchanged; interactive
mode is an additional way in, not a replacement.

The prompt loop takes its I/O as parameters. That is not indirection for its own sake: it
is what lets the selftest drive the whole interaction from a scripted list of answers and
assert the rulings that come out, rather than testing an interactive loop by reading it.
"""

from __future__ import annotations

ABANDON = "a"
ACCEPT_ALL = "A"
SKIP = "s"
EXPLAIN = "?"

_TRUE = {"y", "yes", "true", "t", "1"}
_FALSE = {"n", "no", "false", "f", "0"}


def parse_value(raw: str, kind: str):
    """One typed value from what the operator typed, or ValueError saying what was wanted.

    Refusing beats guessing: a mistyped tuning value that parsed to something plausible
    would be ruled by the human in name only.
    """
    raw = raw.strip()
    if kind == "int":
        try:
            return int(raw)
        except ValueError:
            raise ValueError(f"expected an int, got {raw!r}") from None
    if kind == "float":
        try:
            return float(raw)
        except ValueError:
            raise ValueError(f"expected a float, got {raw!r}") from None
    if kind == "bool":
        low = raw.lower()
        if low in _TRUE:
            return True
        if low in _FALSE:
            return False
        raise ValueError(f"expected a bool (y/n, true/false, 1/0), got {raw!r}")
    if kind == "tags":
        # An empty list is a real ruling -- an animal that avoids nothing, a building that
        # emits no tags -- so "" is [] rather than a refusal.
        return [t.strip() for t in raw.split(",") if t.strip()]
    if kind == "vec2i":
        parts = [p.strip() for p in raw.replace("x", ",").split(",") if p.strip()]
        if len(parts) != 2:
            raise ValueError(f"expected two ints as NxN or N,N, got {raw!r}")
        try:
            return [int(parts[0]), int(parts[1])]
        except ValueError:
            raise ValueError(f"expected two ints as NxN or N,N, got {raw!r}") from None
    return raw


def render_decision(decision: dict, kind: str) -> str:
    """The one-line prompt for a field: what is proposed, where it came from, how sure."""
    proposal = decision.get("proposal")
    shown = "(none)" if proposal is None else (
        ", ".join(str(x) for x in proposal) if isinstance(proposal, list) else str(proposal))
    return (f"  {decision['field']:<22} proposal: {shown:<28} "
            f"{decision.get('source', '')} ({decision.get('confidence', '?')}) [{kind}]")


def prompt_rulings(payload: dict, kinds: dict, input_fn, output_fn):
    """Walk the unruled decisions and collect the human's rulings.

    Returns a {field: value} mapping, or None if the operator abandoned. A SKIPped field is
    simply absent from the mapping, so it stays null and `resume` refuses while naming it --
    the null-blocks-resume rule is not weakened by having a friendlier way to reach it.
    """
    rulings: dict = {}
    accept_rest = False
    decisions = [d for d in payload.get("decisions", []) if d.get("value") is None]

    output_fn(f"{len(decisions)} field(s) await your ruling. Enter accepts the proposal; "
              f"type a value to override; {EXPLAIN}=sourcing, {SKIP}=skip, "
              f"{ACCEPT_ALL}=accept all remaining, {ABANDON}=abandon.")

    for decision in decisions:
        field = decision["field"]
        kind = kinds.get(field, "str")
        if accept_rest:
            rulings[field] = decision.get("proposal")
            continue
        output_fn(render_decision(decision, kind))
        while True:
            answer = input_fn(f"  {field}> ")
            stripped = answer.strip()
            if stripped == ABANDON:
                return None
            if stripped == SKIP:
                output_fn(f"  skipped {field} -- it stays unruled and will block resume.")
                break
            if stripped == EXPLAIN:
                output_fn(f"  {field}: {decision.get('source', '(no source recorded)')} "
                          f"| confidence {decision.get('confidence', '?')} | expects {kind}")
                continue
            if stripped == ACCEPT_ALL:
                accept_rest = True
                rulings[field] = decision.get("proposal")
                break
            if stripped == "":
                rulings[field] = decision.get("proposal")
                break
            try:
                rulings[field] = parse_value(answer, kind)
                break
            except ValueError as exc:
                output_fn(f"  {exc} -- try again, or {SKIP} to skip.")
    return rulings


def selftest_cases(c) -> None:
    # --- parse_value, per FieldSpec.kind ------------------------------------
    c.eq(parse_value("10", "int"), 10, "int parsed")
    c.eq(parse_value("0.35", "float"), 0.35, "float parsed")
    c.eq(parse_value("Bold", "enum"), "Bold", "enum passes through as a string")
    c.eq(parse_value("water, cover", "tags"), ["water", "cover"],
         "tags split on commas and trimmed")
    c.eq(parse_value("", "tags"), [], "an empty tag list is a real, empty list")
    c.eq(parse_value("2x2", "vec2i"), [2, 2], "vec2i accepts NxN")
    c.eq(parse_value("1, 3", "vec2i"), [1, 3], "vec2i accepts N,N")
    for raw in ("y", "yes", "TRUE", "1"):
        c.eq(parse_value(raw, "bool"), True, f"bool accepts {raw!r}")
    for raw in ("n", "no", "False", "0"):
        c.eq(parse_value(raw, "bool"), False, f"bool accepts {raw!r}")

    for raw, kind in (("ten", "int"), ("x", "float"), ("maybe", "bool"),
                      ("2x2x2", "vec2i"), ("2", "vec2i")):
        raised = False
        try:
            parse_value(raw, kind)
        except ValueError:
            raised = True
        c.check(raised, f"parse_value({raw!r}, {kind!r}) refuses rather than guessing")

    # --- prompt_rulings -----------------------------------------------------
    def payload():
        return {"decisions": [
            {"field": "scout_radius", "proposal": 8, "value": None,
             "source": "roster.md band 8-12", "confidence": "low"},
            {"field": "farm_tolerant", "proposal": True, "value": None,
             "source": "roster.md farm column", "confidence": "med"},
            {"field": "habitat_needs", "proposal": ["cultivated"], "value": None,
             "source": "roster.md habitat table", "confidence": "med"},
        ]}
    kinds = {"scout_radius": "int", "farm_tolerant": "bool", "habitat_needs": "tags"}

    def drive(answers):
        out = []
        it = iter(answers)
        result = prompt_rulings(payload(), kinds, lambda _p: next(it), out.append)
        return result, "\n".join(out)

    r, _ = drive(["", "", ""])
    c.eq(r, {"scout_radius": 8, "farm_tolerant": True, "habitat_needs": ["cultivated"]},
         "empty input accepts each proposal as-is")

    r, _ = drive(["10", "n", "water, quiet"])
    c.eq(r, {"scout_radius": 10, "farm_tolerant": False,
             "habitat_needs": ["water", "quiet"]},
         "typed values override the proposals, parsed by kind")

    r, _ = drive([ACCEPT_ALL])
    c.eq(r, {"scout_radius": 8, "farm_tolerant": True, "habitat_needs": ["cultivated"]},
         "A accepts every remaining proposal without further prompting")

    r, _ = drive(["12", ACCEPT_ALL])
    c.eq(r, {"scout_radius": 12, "farm_tolerant": True, "habitat_needs": ["cultivated"]},
         "A after an override keeps the override and accepts the rest")

    r, _ = drive(["", ABANDON])
    c.eq(r, None, "a abandons the whole checkpoint")

    r, _ = drive(["", SKIP, ""])
    c.check("farm_tolerant" not in r,
            "s leaves a field unruled, so resume refuses and names it")
    c.eq(sorted(r), ["habitat_needs", "scout_radius"], "the other fields still ruled")

    r, out = drive([EXPLAIN, "", "", ""])
    c.check("roster.md band 8-12" in out, "? prints the field's sourcing")
    c.eq(r["scout_radius"], 8, "? re-prompts the same field rather than consuming it")

    r, out = drive(["ten", "9", "", ""])
    c.check("int" in out.lower(), "a bad value explains what was expected")
    c.eq(r["scout_radius"], 9, "and re-prompts rather than crashing or skipping")

    line = render_decision(payload()["decisions"][0], "int")
    for token in ("scout_radius", "8", "roster.md band 8-12", "low"):
        c.check(token in line, f"the prompt line shows {token}")
