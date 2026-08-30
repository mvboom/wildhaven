"""The review contract -- the single source of truth for what a human ruled.

`value: null` blocks resume. That is the project's "all tuning values are the human's"
rule made mechanical: no stage can write a final tuning value, and the pipeline cannot
proceed past the checkpoint until every decision carries one.

Note the deliberate use of a null sentinel rather than falsiness: a cost of 0 and a
`blocks_movement` of false are real rulings.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass
class Decision:
    field: str
    proposal: object
    source: str
    confidence: str
    value: object = None

    def to_dict(self) -> dict:
        return asdict(self)


def write(path: Path, payload: dict) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))
    return path


def read(path: Path) -> dict:
    return json.loads(path.read_text())


def unruled(payload: dict) -> list[str]:
    return [d["field"] for d in payload.get("decisions", []) if d.get("value") is None]


def ready(payload: dict) -> bool:
    return not unruled(payload)


def apply_rulings(payload: dict, rulings: dict) -> dict:
    known = {d["field"] for d in payload.get("decisions", [])}
    unknown_fields = set(rulings) - known
    if unknown_fields:
        raise KeyError(f"no such decision(s) in this review: {sorted(unknown_fields)}")
    updated = json.loads(json.dumps(payload))
    for decision in updated["decisions"]:
        if decision["field"] in rulings:
            decision["value"] = rulings[decision["field"]]
    return updated


def selftest_cases(c) -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "review.json"
        payload = {
            "run_id": "20260830-pig-abcd", "adapter": "animal",
            "decisions": [
                {"field": "cost", "proposal": 40, "value": None,
                 "source": "barn.tres baseline", "confidence": "med"},
                {"field": "footprint", "proposal": [2, 2], "value": None,
                 "source": "mesh AABB", "confidence": "high"},
            ],
        }
        write(path, payload)
        c.eq(read(path)["run_id"], "20260830-pig-abcd", "round-trips")

        c.eq(unruled(payload), ["cost", "footprint"], "both fields start unruled")
        c.check(not ready(payload), "unruled payload is not ready to resume")

        ruled = apply_rulings(payload, {"cost": 25})
        c.eq(unruled(ruled), ["footprint"], "ruling one field leaves the other")
        c.check(not ready(ruled), "a partially ruled payload still blocks")

        done = apply_rulings(ruled, {"footprint": [1, 1]})
        c.eq(unruled(done), [], "all fields ruled")
        c.check(ready(done), "fully ruled payload is ready")
        c.eq([d["value"] for d in done["decisions"]], [25, [1, 1]], "rulings stored")

        zeroed = apply_rulings(payload, {"cost": 0, "footprint": [1, 1]})
        c.check(ready(zeroed), "a ruling of 0 is a real ruling, not an absent one")

        unknown = False
        try:
            apply_rulings(payload, {"nonesuch": 1})
        except KeyError as exc:
            unknown = "nonesuch" in str(exc)
        c.check(unknown, "ruling an unknown field is an error, not a silent no-op")
