"""Tiny selftest collector, mirroring scripts/fact_card_pipeline.py's selftest()
convention (print [PASS]/[FAIL] per case, then SELFTEST PASSED/FAILED, exit 0/1).

Kept separate from the checks themselves so every module can contribute cases to one
run without importing a test framework -- this repo deliberately has none.
"""

from __future__ import annotations


class Checks:
    def __init__(self) -> None:
        self.ok: bool = True
        self._lines: list[str] = []

    def check(self, cond: bool, label: str) -> bool:
        status = "PASS" if cond else "FAIL"
        if not cond:
            self.ok = False
        self._lines.append(f"[{status}] {label}")
        return bool(cond)

    def eq(self, got: object, want: object, label: str) -> bool:
        cond = got == want
        if not cond:
            label = f"{label} (got {got!r}, want {want!r})"
        return self.check(cond, label)

    def report(self, name: str) -> int:
        for line in self._lines:
            print(line)
        print(f"{name}: " + ("PASSED" if self.ok else "FAILED"))
        return 0 if self.ok else 1


def _selftest() -> int:
    c = Checks()
    c.check(True, "true passes")
    c.eq(2 + 2, 4, "eq passes")
    assert c.ok is True
    d = Checks()
    d.check(False, "false fails")
    assert d.ok is False
    print("[PASS] harness records pass/fail correctly")
    print("SELFTEST PASSED")
    return 0
