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


def license_of(pack: Path) -> tuple[str, str]:
    """(license_id, evidence). An empty id means NOT CLEARED -- never 'unknown, proceed'."""
    for name in LICENSE_FILENAMES:
        path = pack / name
        if not path.is_file():
            continue
        text = path.read_text(errors="ignore")
        low = text.casefold()
        if any(v in low for v in _VETOES):
            return "", f"{name}: names a vetoed licence family"
        for needle, license_id in _CLEARED:
            if needle in low:
                return license_id, f"{name}: matched {needle!r}"
        if "synty" in low:
            if _SYNTY_SANCTIONED_LINE in low:
                return "Synty Store EULA (SIMPLE)", f"{name}: matched Synty SIMPLE"
            return "", (f"{name}: Synty pack that is not SIMPLE — art.md sanctions the "
                        f"SIMPLE line only, and the absence of POLYGON does not make a "
                        f"pack SIMPLE")
        return "", f"{name}: no cleared licence recognised"
    return "", "no licence file in pack"


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

    if license_id.startswith("Synty") and adapter_name and adapter_name != "animal":
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

        # Both return paths have same evidence key set
        resolved_evidence_keys = set(gate(ok, ["Idle", "Walk"], cc0).evidence.keys())
        unresolved_evidence_keys = set(gate(unresolved, [], cc0).evidence.keys())
        c.eq(sorted(resolved_evidence_keys), sorted(unresolved_evidence_keys),
             "resolved and unresolved gates have same evidence key set")
