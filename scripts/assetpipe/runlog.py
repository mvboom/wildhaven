"""Per-run evidence: stage cache, and the token/cost ledger.

runs/ lives in the MAIN checkout and is gitignored -- never inside the worktree. Abandon
destroys the worktree; it must not destroy the evidence. An abandoned run still yields
its per-stage cost, which is what makes per-asset cost measurable at all.
"""

from __future__ import annotations

import hashlib
import json
import time
import uuid
from pathlib import Path


def new_run_id(slug: str) -> str:
    return f"{time.strftime('%Y%m%d')}-{slug}-{uuid.uuid4().hex[:4]}"


def stage_key(*parts: object) -> str:
    """Stable hash of a stage's inputs. A changed key invalidates that stage and,
    via invalidate_from, everything after it."""
    joined = "\x00".join(json.dumps(p, sort_keys=True, default=str) for p in parts)
    return hashlib.sha256(joined.encode()).hexdigest()[:16]


class RunLog:
    def __init__(self, root: Path, run_id: str) -> None:
        self.run_id = run_id
        self.dir = Path(root) / run_id
        self.stages = self.dir / "stages"
        self.stages.mkdir(parents=True, exist_ok=True)

    def _path(self, n: int, name: str) -> Path:
        return self.stages / f"{n:02d}-{name}.json"

    def cached(self, n: int, name: str, key: str) -> dict | None:
        path = self._path(n, name)
        if not path.is_file():
            return None
        blob = json.loads(path.read_text())
        return blob["result"] if blob.get("key") == key else None

    def record(self, n: int, name: str, key: str, result: dict,
               cost: dict | None) -> None:
        self._path(n, name).write_text(json.dumps(
            {"n": n, "name": name, "key": key, "result": result, "cost": cost,
             "at": time.strftime("%Y-%m-%dT%H:%M:%S")}, indent=2))

    def invalidate_from(self, n: int) -> None:
        for path in self.stages.glob("*.json"):
            if int(path.name[:2]) >= n:
                path.unlink()

    def total_cost(self) -> dict:
        totals = {"in": 0, "out": 0, "usd": 0.0}
        for path in sorted(self.stages.glob("*.json")):
            cost = json.loads(path.read_text()).get("cost")
            if not cost:
                continue
            totals["in"] += cost.get("in", 0)
            totals["out"] += cost.get("out", 0)
            totals["usd"] += cost.get("usd", 0.0)
        return totals


def selftest_cases(c) -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        root = Path(td) / "runs"
        rid = new_run_id("pig")
        c.check(rid.startswith(time.strftime("%Y%m%d") + "-pig-"), "run id is dated and slugged")
        c.eq(len(rid.split("-")[-1]), 4, "run id ends in a 4-char suffix")

        c.eq(stage_key("a", "b"), stage_key("a", "b"), "same inputs, same key")
        c.check(stage_key("a", "b") != stage_key("a", "c"), "different inputs, different key")

        log = RunLog(root, rid)
        c.eq(log.cached(1, "resolve", "k1"), None, "nothing cached initially")
        log.record(1, "resolve", "k1", {"chosen": "fbx"}, None)
        c.eq(log.cached(1, "resolve", "k1"), {"chosen": "fbx"}, "recorded result replays")
        c.eq(log.cached(1, "resolve", "k2"), None, "a changed key misses the cache")

        log.record(6, "values", "k6", {"cost": 40}, {"model": "haiku", "in": 812,
                                                     "out": 244, "usd": 0.004})
        log.record(8, "copy", "k8", {"lines": 3}, {"model": "opus", "in": 100,
                                                   "out": 50, "usd": 0.02})
        c.eq(round(log.total_cost()["usd"], 4), 0.024, "costs sum across stages")
        c.eq(log.total_cost()["in"], 912, "input tokens sum")

        log.invalidate_from(8)
        c.eq(log.cached(8, "copy", "k8"), None, "invalidated stage misses")
        c.eq(log.cached(6, "values", "k6"), {"cost": 40}, "earlier stage survives")
        c.eq(round(log.total_cost()["usd"], 4), 0.004,
             "cost of an invalidated stage is dropped, not double-counted")
