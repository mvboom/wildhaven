"""The audit gate -- deterministic, free, and run before anything is copied.

Policy is game-design/art.md's, not this file's: Quaternius CC0 primary, Synty SIMPLE as
the animals-only paid fallback, NEVER Synty POLYGON. "No cleared source -> stop and
report" (asset-import-pipeline.md step 2) is a hard stop, not a prompt.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

LICENSE_FILENAMES = ("License.txt", "LICENSE", "LICENSE.txt", "license.txt", "License.md")

# Ordered: the POLYGON veto is checked before the Synty clearance so a file naming both
# cannot clear itself.
_VETOES = ("polygon",)
_CLEARED = (
    ("cc0", "CC0-1.0"),
    ("creative commons zero", "CC0-1.0"),
    ("public domain", "CC0-1.0"),
)

_SYNTY_SANCTIONED_LINE = "simple"


@dataclass
class AuditResult:
    passed: bool
    problems: list[str] = field(default_factory=list)
    evidence: dict = field(default_factory=dict)


# How far below the pack root a licence file is still considered THIS pack's licence.
# formats.pack_root() deliberately returns the TOPMOST folder under source-content/assets/
# (see its own docstring), and a Google Drive export wraps a pack in a timestamped folder
# holding a second copy of the pack's own name -- so `Buildings pack - Aug 2017-2026...Z-1-001/
# Buildings pack - Aug 2017/License.txt` sits one level below the root this is handed. Ten of
# the fourteen packs in the drop are shaped that way; a root-only lookup reported "no licence
# file in pack" for every one of them while the file was plainly on disk. 2 rather than 1
# because some packs also repeat the licence per format folder (Buildings Pack - Jan 2019 ships
# it at the root AND under FBX/ and Blends/) -- the shallowest level that has any candidate is
# the one that answers, so the deeper copies only ever matter for a pack that lacks a root one.
_LICENSE_SEARCH_DEPTH = 2


def license_files(pack: Path) -> list[Path]:
    """Every candidate licence file for `pack`, from the SHALLOWEST level that has one.

    Shallowest-level-wins, not first-hit-anywhere: a pack that states its licence at its own
    root has answered, and a stray per-folder copy deeper in must not get a vote. Within a
    level, LICENSE_FILENAMES order is preserved, so the root-level behaviour is exactly what
    it was before nested packs were searched at all.
    """
    for depth in range(_LICENSE_SEARCH_DEPTH + 1):
        prefix = "*/" * depth
        hits: list[Path] = []
        for name in LICENSE_FILENAMES:
            for path in sorted(pack.glob(prefix + name)):
                if path.is_file() and path not in hits:
                    hits.append(path)
        if hits:
            return hits
    return []


def _verdict(path: Path, label: str) -> tuple[str, str]:
    """One licence file's (license_id, evidence). Empty id means NOT CLEARED."""
    low = path.read_text(errors="ignore").casefold()
    if any(v in low for v in _VETOES):
        return "", f"{label}: names a vetoed licence family"
    for needle, license_id in _CLEARED:
        if needle in low:
            return license_id, f"{label}: matched {needle!r}"
    if "synty" in low:
        if _SYNTY_SANCTIONED_LINE in low:
            return "Synty Store EULA (SIMPLE)", f"{label}: matched Synty SIMPLE"
        return "", (f"{label}: Synty pack that is not SIMPLE — art.md sanctions the "
                    f"SIMPLE line only, and the absence of POLYGON does not make a "
                    f"pack SIMPLE")
    return "", f"{label}: no cleared licence recognised"


def license_of(pack: Path) -> tuple[str, str]:
    """(license_id, evidence). An empty id means NOT CLEARED -- never 'unknown, proceed'."""
    candidates = license_files(pack)
    if not candidates:
        return "", "no licence file in pack"
    verdicts = [_verdict(p, p.relative_to(pack).as_posix()) for p in candidates]
    # DISAGREEMENT IS A REFUSAL, not a tie-break. Sibling folders at the same level naming
    # different licences is a pack this gate cannot read a single answer off, and picking
    # whichever sorted first would clear an asset on a licence that may not cover it.
    if len({license_id for license_id, _ in verdicts}) > 1:
        return "", ("licence files disagree: "
                    + "; ".join(evidence for _, evidence in verdicts))
    return verdicts[0]


def _make_evidence(resolution, probe, license_id, license_evidence):
    """Always return the full key set, using empty/sentinel values when probe is absent."""
    if probe is None:
        return {
            "license": license_id, "license_evidence": license_evidence,
            "format": "", "format_reason": resolution.reason,
            "clips": [], "meshes": -1, "nodes": -1, "skins": -1,
            "silhouette": "DEFERRED -- human rules at the checkpoint",
        }
    return {
        "license": license_id, "license_evidence": license_evidence,
        "format": resolution.chosen, "format_reason": resolution.reason,
        "clips": probe.clips, "meshes": probe.meshes,
        "nodes": probe.nodes, "skins": probe.skins,
        "silhouette": "DEFERRED -- human rules at the checkpoint",
    }


def gate(resolution, required_clips: list[str], pack: Path,
         adapter_name: str = "") -> AuditResult:
    problems: list[str] = []
    license_id, license_evidence = license_of(pack)

    if not license_id:
        problems.append(f"no cleared licence: {license_evidence}")

    if license_id.startswith("Synty") and adapter_name != "animal":
        problems.append(
            f"Synty SIMPLE is sanctioned for ANIMALS ONLY (art.md:70 — 'Animals only; "
            f"humans stay Quaternius'); this is a {adapter_name!r} import")

    if not resolution.chosen or resolution.probe is None:
        problems.append(f"no importable format: {resolution.reason}")
        return AuditResult(
            False, problems,
            _make_evidence(resolution, resolution.probe, license_id, license_evidence))

    probe = resolution.probe
    missing = [clip for clip in required_clips if clip not in probe.clips]
    if missing:
        problems.append(
            "missing required animation clip(s) %s -- found %s. A model with no walk "
            "cycle cannot roam; this is the Quaternius-chickens failure, caught before "
            "import." % (", ".join(missing), probe.clips or "none")
        )

    return AuditResult(
        passed=not problems,
        problems=problems,
        evidence=_make_evidence(resolution, probe, license_id, license_evidence),
    )


def selftest_cases(c) -> None:
    import tempfile
    from assetpipe.formats import ModelProbe, Resolution

    with tempfile.TemporaryDirectory() as td:
        d = Path(td)

        cc0 = d / "cc0pack"; cc0.mkdir()
        (cc0 / "License.txt").write_text("This work is licensed under CC0 1.0 Universal.")
        c.eq(license_of(cc0)[0], "CC0-1.0", "CC0 licence recognised")

        poly = d / "polypack"; poly.mkdir()
        (poly / "License.txt").write_text("Synty Studios POLYGON asset licence")
        c.eq(license_of(poly)[0], "", "Synty POLYGON is not a cleared licence")

        bare = d / "nolicence"; bare.mkdir()
        c.eq(license_of(bare)[0], "", "missing licence file yields no licence")

        synty_no_simple = d / "synty_nosimple"; synty_no_simple.mkdir()
        (synty_no_simple / "License.txt").write_text("Synty Studios proprietary asset licence")
        c.eq(license_of(synty_no_simple)[0], "", "Synty without SIMPLE is not cleared")

        synty_simple = d / "synty_simple"; synty_simple.mkdir()
        (synty_simple / "License.txt").write_text("Synty Studios SIMPLE asset licence")
        c.eq(license_of(synty_simple)[0], "Synty Store EULA (SIMPLE)", "Synty SIMPLE is cleared")

        unrecognized = d / "unrecognized"; unrecognized.mkdir()
        (unrecognized / "License.txt").write_text("All Rights Reserved")
        c.eq(license_of(unrecognized)[0], "", "licence file matching no pattern yields no licence")

        # The Drive-export shape: the pack folder handed to the gate wraps a second copy of
        # the pack's own name, and the licence is in THAT. Reported "no licence file in pack"
        # for ten of the fourteen packs in the drop before license_files() searched below root.
        nested = d / "Pack - Aug 2017-20260829T202339Z-1-001"
        (nested / "Pack - Aug 2017").mkdir(parents=True)
        (nested / "Pack - Aug 2017" / "License.txt").write_text("CC0 1.0 Universal")
        c.eq(license_of(nested)[0], "CC0-1.0", "a licence one level below the pack root is found")
        c.eq(license_of(nested)[1], "Pack - Aug 2017/License.txt: matched 'cc0'",
             "...and the evidence names the path, not a bare filename a reviewer cannot locate")

        # Shallowest level wins outright: a per-format copy deeper in gets no vote, so it
        # cannot drag a pack that already answered at its own root into the disagreement path.
        shadowed = d / "shadowed"; (shadowed / "FBX").mkdir(parents=True)
        (shadowed / "License.txt").write_text("CC0 1.0 Universal")
        (shadowed / "FBX" / "License.txt").write_text("Synty Studios POLYGON asset licence")
        c.eq(license_of(shadowed)[0], "CC0-1.0", "the root licence answers; a deeper copy does not")

        # ...but siblings AT that level disagreeing is a refusal, never a sorted-order tie-break.
        conflict = d / "conflict"
        (conflict / "a").mkdir(parents=True); (conflict / "b").mkdir(parents=True)
        (conflict / "a" / "License.txt").write_text("CC0 1.0 Universal")
        (conflict / "b" / "License.txt").write_text("Synty Studios POLYGON asset licence")
        c.eq(license_of(conflict)[0], "", "licence files that disagree clear nothing")
        c.check("disagree" in license_of(conflict)[1], "...and the evidence says why")

        rigged = Resolution("fbx", d / "Pig.fbx",
                            ModelProbe(fmt="fbx", clips=["Idle", "Jump"]), "r", {})
        r = gate(rigged, required_clips=["Idle", "Walk"], pack=cc0)
        c.check(not r.passed, "Pig fails the animal gate for want of a Walk cycle")
        c.check(any("Walk" in p for p in r.problems), "problem names the missing clip")
        c.eq(r.evidence["clips"], ["Idle", "Jump"], "evidence carries the clip list")

        ok = Resolution("gltf", d / "Wolf.gltf",
                        ModelProbe(fmt="gltf", clips=["Gallop", "Idle", "Walk"],
                                   meshes=1, nodes=53, skins=1), "r", {})
        c.check(gate(ok, ["Idle", "Walk"], cc0).passed, "a rigged, cleared model passes")

        c.check(not gate(ok, ["Idle", "Walk"], poly).passed, "POLYGON pack is a hard stop")
        c.check(gate(ok, [], cc0).passed, "static content needs no clips")

        unresolved = Resolution("", None, None, "no importable format", {})
        c.check(not gate(unresolved, [], cc0).passed, "unresolved format fails the gate")

        # Synty SIMPLE with animal adapter passes
        animal_synty = Resolution("fbx", d / "Antelope.fbx",
                                   ModelProbe(fmt="fbx", clips=["Idle", "Walk"], meshes=1, nodes=10, skins=1),
                                   "r", {})
        c.check(gate(animal_synty, ["Idle", "Walk"], synty_simple, adapter_name="animal").passed,
                "Synty SIMPLE pack passes for animals")

        # Synty SIMPLE with building adapter fails
        r_building = gate(animal_synty, ["Idle", "Walk"], synty_simple, adapter_name="building")
        c.check(not r_building.passed, "Synty SIMPLE pack fails for buildings")
        c.check(any("Animals only" in p for p in r_building.problems),
                "problem names the animals-only rule")

        # Synty SIMPLE with adapter_name omitted (default "") must fail CLOSED
        r_omitted = gate(animal_synty, ["Idle", "Walk"], synty_simple)
        c.check(not r_omitted.passed, "Synty SIMPLE pack fails when adapter_name is omitted")
        c.check(any("Animals only" in p for p in r_omitted.problems),
                "problem names animals-only rule when adapter_name omitted (fail-CLOSED)")

        # Both return paths have same evidence key set
        resolved_evidence_keys = set(gate(ok, ["Idle", "Walk"], cc0).evidence.keys())
        unresolved_evidence_keys = set(gate(unresolved, [], cc0).evidence.keys())
        c.eq(sorted(resolved_evidence_keys), sorted(unresolved_evidence_keys),
             "resolved and unresolved gates have same evidence key set")
