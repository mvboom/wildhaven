#!/usr/bin/env python3
"""Deterministic inventory of `source-content/assets/`, and the diff against what
ASSET_AUDIT.md already records.

This is the cheap half of the `/asset-audit` skill: it answers "what is on disk, and
which of it has nobody looked at yet" without an agent dispatch and without reading
~1,600 file paths into a context window.

The record of what has been *considered* lives in
`source-content/assets/ASSET_AUDIT.md`, inside the generated block delimited by the
BEGIN/END markers below. Rows carry a `Status` the pipeline owns:

  new       -- scanner has seen the pack; no human/agent has assessed it yet
  assessed  -- the audit doc carries a decision for this pack (used, rejected, or
               deliberately deferred), so a sweep should not re-litigate it

`--write` never invents a status: packs already in the table keep theirs, packs seen
for the first time are written as `new`. Flipping a row to `assessed` is a deliberate
act (`--set-status`), performed only once the decision prose is actually in the doc.

Usage:
  asset-manifest.py                      print the current on-disk inventory table
  asset-manifest.py --diff               compare disk against ASSET_AUDIT.md's record
  asset-manifest.py --models PACK        list a pack's models (formats, animated flag)
  asset-manifest.py --unused [PACK]      cleared content NOT in project/assets/ yet
  asset-manifest.py --write              rewrite the generated block in ASSET_AUDIT.md
  asset-manifest.py --set-status PACK S  set one pack's Status to new|assessed
  asset-manifest.py --json               machine-readable dump of the scan

PACK is matched case-insensitively as a substring of the pack folder name; an
ambiguous match is an error listing the candidates rather than a guess.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO_ROOT / "source-content" / "assets"
AUDIT_DOC = ASSETS_DIR / "ASSET_AUDIT.md"

BEGIN_MARKER = "<!-- BEGIN ASSET MANIFEST -->"
END_MARKER = "<!-- END ASSET MANIFEST -->"

# Extensions that count as a *model*. Identity is the basename, so Barn.gltf,
# Barn.fbx and Barn.obj are one model shipped in three formats, not three models.
MODEL_EXTS = {".gltf", ".glb", ".fbx", ".obj", ".blend"}
# .blend is recorded as a format but never establishes a model on its own -- a pack
# that ships only .blend files needs Blender, which is not in this pipeline.
IDENTITY_EXTS = MODEL_EXTS - {".blend"}

STATUSES = ("new", "assessed")

# Byte signatures that mean "this file carries animation data". glTF/GLB name the
# array outright; binary FBX names its animation nodes. Both are heuristics reported
# as a hint -- asset-import-pipeline.md's step 2 still confirms a real idle/walk clip
# before anything is imported.
ANIM_SIGNATURES = ((b'"animations"', {".gltf", ".glb"}), (b"AnimationStack", {".fbx"}))

READ_CAP = 8 * 1024 * 1024  # bytes scanned per file when sniffing for animation data


def _contains(path: Path, needle: bytes) -> bool:
    """Stream-search a file for `needle`, capped so a huge mesh cannot stall a sweep."""
    overlap = len(needle) - 1
    read = 0
    tail = b""
    try:
        with path.open("rb") as handle:
            while read < READ_CAP:
                chunk = handle.read(1 << 20)
                if not chunk:
                    break
                read += len(chunk)
                if needle in tail + chunk:
                    return True
                tail = chunk[-overlap:] if overlap else b""
    except OSError:
        return False
    return False


def _sniff_animated(files: list[Path]) -> bool | None:
    """True/False if a format we can inspect was present, None if we could not tell."""
    inspectable = False
    for path in files:
        ext = path.suffix.lower()
        for needle, exts in ANIM_SIGNATURES:
            if ext in exts:
                inspectable = True
                if _contains(path, needle):
                    return True
    return False if inspectable else None


LOOSE_PACK = "(loose files)"


def scan_pack(pack_dir: Path, name: str | None = None, recurse: bool = True) -> dict:
    """One pack folder, or (recurse=False) the loose model files sitting at the root.

    Loose files are how single-model poly.pizza downloads arrive -- they are content
    like any other, and a sweep that only walked subfolders would silently miss them.
    """
    models: dict[str, dict] = {}
    fingerprint_lines: list[str] = []
    walk = pack_dir.rglob("*") if recurse else pack_dir.iterdir()
    for path in sorted(walk):
        if not path.is_file():
            continue
        if any(part.startswith(".") for part in path.relative_to(pack_dir).parts):
            continue
        ext = path.suffix.lower()
        if ext not in MODEL_EXTS:
            continue
        rel = path.relative_to(pack_dir).as_posix().lower()
        try:
            size = path.stat().st_size
        except OSError:
            size = -1
        fingerprint_lines.append(f"{rel}|{size}")
        if ext not in IDENTITY_EXTS:
            continue
        key = path.stem.lower()
        entry = models.setdefault(key, {"name": path.stem, "formats": set(), "files": []})
        entry["formats"].add(ext.lstrip("."))
        entry["files"].append(path)

    for entry in models.values():
        entry["animated"] = _sniff_animated(entry["files"])

    blob = "\n".join(sorted(fingerprint_lines)).encode("utf-8")
    fingerprint = hashlib.sha256(blob).hexdigest()[:12] if fingerprint_lines else "empty"

    all_formats: set[str] = set()
    for entry in models.values():
        all_formats |= entry["formats"]
    if any(line.endswith(".blend") or ".blend|" in line for line in fingerprint_lines):
        all_formats.add("blend")

    animated_yes = sum(1 for e in models.values() if e["animated"] is True)
    inspectable = sum(1 for e in models.values() if e["animated"] is not None)
    if inspectable == 0:
        animated = "unknown"
    elif animated_yes == 0:
        animated = "no"
    else:
        animated = f"yes ({animated_yes}/{len(models)})"

    return {
        "pack": name or pack_dir.name,
        "models": models,
        "model_count": len(models),
        "formats": sorted(all_formats),
        "animated": animated,
        "fingerprint": fingerprint,
    }


def scan(assets_dir: Path = ASSETS_DIR) -> list[dict]:
    if not assets_dir.is_dir():
        sys.exit(f"error: assets directory not found: {assets_dir}")
    packs = [
        scan_pack(d)
        for d in sorted(assets_dir.iterdir())
        if d.is_dir() and not d.name.startswith(".")
    ]
    loose = scan_pack(assets_dir, name=LOOSE_PACK, recurse=False)
    if loose["model_count"]:
        packs.append(loose)
    return sorted(packs, key=lambda p: p["pack"].lower())


# ------------------------------------------------------------- project usage

def _norm(name: str) -> str:
    """Comparison key: lowercase, alphanumerics only."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


PROJECT_ASSETS = REPO_ROOT / "project" / "assets"
USAGE_EXTS = MODEL_EXTS | {".tscn"}


def project_usage(assets_dir: Path = PROJECT_ASSETS) -> set[str]:
    """Lowercased basenames of every model/scene under `project/assets/`.

    `assessed` only ever meant "we know what is in this pack" -- it was being read as
    "we decided against it", which is how nine SecondAge houses and fifteen animated
    villagers sat unused inside already-cleared packs. Usage is a separate axis from
    status, so it gets measured separately.

    Matching is by normalized basename -- lowercased, punctuation stripped -- because
    imports drop the separators (`Houses_FirstAge_1_Level1` ships as
    `HousesFirstAge1Level1.tscn`). Two known imprecisions, both acceptable for a
    pointer rather than a proof:
      * a model renamed on import (`Male_Casual` -> `Man.glb`) reads as unused;
      * a generic name (`House`, `Well`, `Barn`) can match an import sourced from a
        different pack, reading as used.
    Treat a count here as "worth a look", never as a verified import record --
    content-pipeline-status.md is the record.
    """
    names: set[str] = set()
    if not assets_dir.is_dir():
        return names
    for path in assets_dir.rglob("*"):
        if path.is_file() and path.suffix.lower() in USAGE_EXTS:
            names.add(_norm(path.stem))
    return names


def pack_usage(pack: dict, used: set[str]) -> tuple[int, list[str]]:
    """(imported count, unused model names) for one pack."""
    unused = [e["name"] for e in sorted(pack["models"].values(), key=lambda e: e["name"].lower())
              if _norm(e["name"]) not in used]
    return pack["model_count"] - len(unused), unused


# ---------------------------------------------------------------- audit doc I/O

ROW_RE = re.compile(r"^\|(?P<cells>.*)\|\s*$")


def read_record(doc: Path = AUDIT_DOC) -> dict[str, dict]:
    """Recorded rows keyed by pack name. Empty dict when the block is absent."""
    if not doc.is_file():
        return {}
    text = doc.read_text(encoding="utf-8")
    if BEGIN_MARKER not in text or END_MARKER not in text:
        return {}
    block = text.split(BEGIN_MARKER, 1)[1].split(END_MARKER, 1)[0]
    rows: dict[str, dict] = {}
    for line in block.splitlines():
        match = ROW_RE.match(line.strip())
        if not match:
            continue
        cells = [c.strip() for c in match.group("cells").split("|")]
        if len(cells) < 6 or cells[0] in ("Pack", "") or set(cells[0]) <= {"-", ":"}:
            continue
        rows[cells[0].strip("`")] = {
            "pack": cells[0].strip("`"),
            "model_count": cells[1],
            "formats": cells[2],
            "animated": cells[3],
            "status": cells[4],
            "fingerprint": cells[5].strip("`"),
        }
    return rows


def render_table(packs: list[dict], record: dict[str, dict]) -> str:
    lines = [
        "| Pack | Models | Formats | Animated | Status | Fingerprint |",
        "|---|---|---|---|---|---|",
    ]
    for pack in packs:
        prior = record.get(pack["pack"])
        status = prior["status"] if prior and prior["status"] in STATUSES else "new"
        # A pack whose bytes changed since it was assessed is unassessed again --
        # the decision on record was made about different content.
        if prior and prior.get("fingerprint") != pack["fingerprint"]:
            status = "new"
        lines.append(
            "| `%s` | %d | %s | %s | %s | `%s` |"
            % (
                pack["pack"],
                pack["model_count"],
                ", ".join(pack["formats"]) or "-",
                pack["animated"],
                status,
                pack["fingerprint"],
            )
        )
    return "\n".join(lines)


def write_block(packs: list[dict], doc: Path = AUDIT_DOC) -> str:
    record = read_record(doc)
    table = render_table(packs, record)
    body = (
        f"{BEGIN_MARKER}\n"
        "<!-- Generated by scripts/asset-manifest.py --write. Do not hand-edit rows;\n"
        "     change a Status with --set-status so the fingerprint stays in sync. -->\n\n"
        f"{table}\n\n"
        f"{END_MARKER}"
    )
    text = doc.read_text(encoding="utf-8") if doc.is_file() else ""
    if BEGIN_MARKER in text and END_MARKER in text:
        head = text.split(BEGIN_MARKER, 1)[0]
        tail = text.split(END_MARKER, 1)[1]
        doc.write_text(head + body + tail, encoding="utf-8")
    else:
        section = (
            "\n## Pack inventory (generated)\n\n"
            "Machine-written by `scripts/asset-manifest.py`. `Status` is `new` until a\n"
            "decision for that pack exists in the prose above, then `assessed`.\n\n"
            f"{body}\n"
        )
        doc.write_text(text.rstrip("\n") + "\n" + section, encoding="utf-8")
    return table


def set_status(pattern: str, status: str, doc: Path = AUDIT_DOC) -> str:
    if status not in STATUSES:
        sys.exit(f"error: status must be one of {', '.join(STATUSES)}")
    record = read_record(doc)
    if not record:
        sys.exit("error: no manifest block in ASSET_AUDIT.md -- run --write first")
    pack = resolve_pack(pattern, list(record))
    text = doc.read_text(encoding="utf-8")
    head, rest = text.split(BEGIN_MARKER, 1)
    block, tail = rest.split(END_MARKER, 1)
    out = []
    for line in block.splitlines():
        if line.strip().startswith(f"| `{pack}` |"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            cells[4] = status
            line = "| " + " | ".join(cells) + " |"
        out.append(line)
    body = "\n".join(out)
    if not body.endswith("\n"):
        body += "\n"
    doc.write_text(head + BEGIN_MARKER + body + END_MARKER + tail, encoding="utf-8")
    return pack


def resolve_pack(pattern: str, candidates: list[str]) -> str:
    needle = pattern.lower()
    hits = [c for c in candidates if needle in c.lower()]
    if not hits:
        sys.exit(f"error: no pack matches {pattern!r}")
    if len(hits) > 1:
        exact = [c for c in hits if c.lower() == needle]
        if len(exact) == 1:
            return exact[0]
        joined = "\n  ".join(hits)
        sys.exit(f"error: {pattern!r} is ambiguous:\n  {joined}")
    return hits[0]


# ------------------------------------------------------------------- reporting


def cmd_diff(packs: list[dict]) -> int:
    record = read_record()
    if not record:
        print("No manifest block in ASSET_AUDIT.md -- everything on disk is unrecorded.")
        print("Run: python3 scripts/asset-manifest.py --write\n")

    on_disk = {p["pack"]: p for p in packs}
    by_fingerprint: dict[str, list[str]] = {}
    for pack in packs:
        by_fingerprint.setdefault(pack["fingerprint"], []).append(pack["pack"])

    new, changed, unassessed, unchanged = [], [], [], []
    for name, pack in on_disk.items():
        prior = record.get(name)
        if prior is None:
            new.append(pack)
        elif prior["fingerprint"] != pack["fingerprint"]:
            changed.append((pack, prior))
        elif prior["status"] != "assessed":
            unassessed.append(pack)
        else:
            unchanged.append(pack)
    removed = [name for name in record if name not in on_disk]

    # A pack whose bytes match an already-assessed pack is a re-download, not work.
    duplicates = []
    for fingerprint, names in by_fingerprint.items():
        if len(names) < 2:
            continue
        assessed = [n for n in names if record.get(n, {}).get("status") == "assessed"]
        duplicates.append((fingerprint, sorted(names), assessed))

    def show(title: str, rows: list[str]) -> None:
        print(f"{title} ({len(rows)})")
        for row in rows:
            print(f"  {row}")
        if not rows:
            print("  --")
        print()

    def summarize(pack: dict) -> str:
        return "%-62s %4d models  %-22s %s" % (
            pack["pack"],
            pack["model_count"],
            ", ".join(pack["formats"]) or "-",
            pack["animated"],
        )

    print(f"Scanned {len(packs)} pack folders under {ASSETS_DIR.relative_to(REPO_ROOT)}\n")
    show("NEW PACKS (never recorded)", [summarize(p) for p in new])
    show(
        "CHANGED PACKS (content differs from the recorded fingerprint)",
        ["%s  %s -> %s" % (p["pack"], prior["fingerprint"], p["fingerprint"]) for p, prior in changed],
    )
    show("RECORDED BUT UNASSESSED (Status = new)", [summarize(p) for p in unassessed])
    show(
        "DUPLICATE CONTENT (identical fingerprints)",
        [
            "%s  <-  %s%s"
            % (
                names[0],
                ", ".join(names[1:]),
                "  [a copy is already assessed]" if assessed else "",
            )
            for _, names, assessed in duplicates
        ],
    )
    show("RECORDED BUT MISSING FROM DISK", removed)

    # Assessed does not mean used. Surface how much of each cleared pack is actually
    # in the game, so unimported content inside a cleared pack cannot hide.
    used = project_usage()
    rows = []
    for pack in sorted(unchanged, key=lambda p: p["pack"].lower()):
        imported, unused = pack_usage(pack, used)
        if imported:
            rows.append(
                "%-62s %3d/%-3d imported   %d unused"
                % (pack["pack"], imported, pack["model_count"], len(unused))
            )
    show("ASSESSED PACKS ALREADY DRAWN FROM (--unused \"<pack>\" lists the rest)", rows)
    print(f"UNCHANGED AND ASSESSED ({len(unchanged)})")

    needs_work = new or changed or unassessed
    print()
    print("Verdict: %s" % ("new content to assess" if needs_work else "nothing new"))
    return 0


def cmd_models(packs: list[dict], pattern: str, animated_only: bool) -> int:
    pack = next(p for p in packs if p["pack"] == resolve_pack(pattern, [p["pack"] for p in packs]))
    entries = sorted(pack["models"].values(), key=lambda e: e["name"].lower())
    if animated_only:
        entries = [e for e in entries if e["animated"] is True]
    print(f"{pack['pack']} -- {len(entries)} models\n")
    for entry in entries:
        flag = {True: "animated", False: "static", None: "unknown"}[entry["animated"]]
        print("  %-46s %-18s %s" % (entry["name"], ", ".join(sorted(entry["formats"])), flag))
    return 0


def cmd_unused(packs: list[dict], pattern: str | None) -> int:
    used = project_usage()
    targets = packs
    if pattern:
        name = resolve_pack(pattern, [p["pack"] for p in packs])
        targets = [p for p in packs if p["pack"] == name]
    for pack in targets:
        imported, unused = pack_usage(pack, used)
        if not pattern and imported == 0:
            continue  # a pack nothing was ever drawn from is not news
        print("%s -- %d/%d imported, %d unused" % (pack["pack"], imported, pack["model_count"], len(unused)))
        if pattern:
            for name in unused:
                entry = pack["models"][name.lower()]
                flag = {True: "animated", False: "static", None: "unknown"}[entry["animated"]]
                print("  %-46s %-18s %s" % (name, ", ".join(sorted(entry["formats"])), flag))
        print()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--diff", action="store_true", help="compare disk against ASSET_AUDIT.md")
    parser.add_argument("--write", action="store_true", help="rewrite the generated block in ASSET_AUDIT.md")
    parser.add_argument("--models", metavar="PACK", help="list one pack's models")
    parser.add_argument("--animated-only", action="store_true", help="with --models, animated models only")
    parser.add_argument("--set-status", nargs=2, metavar=("PACK", "STATUS"), help="set a pack's Status")
    parser.add_argument(
        "--unused",
        nargs="?",
        const="",
        metavar="PACK",
        help="what is on disk but not in project/assets/ (bare: per-pack summary)",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable dump")
    args = parser.parse_args()

    if args.set_status:
        pack = set_status(args.set_status[0], args.set_status[1])
        print(f"{pack}: Status = {args.set_status[1]}")
        return 0

    packs = scan()

    if args.json:
        print(
            json.dumps(
                [
                    {
                        "pack": p["pack"],
                        "model_count": p["model_count"],
                        "formats": p["formats"],
                        "animated": p["animated"],
                        "fingerprint": p["fingerprint"],
                        "models": [
                            {
                                "name": e["name"],
                                "formats": sorted(e["formats"]),
                                "animated": e["animated"],
                            }
                            for e in sorted(p["models"].values(), key=lambda e: e["name"].lower())
                        ],
                    }
                    for p in packs
                ],
                indent=2,
            )
        )
        return 0
    if args.unused is not None:
        return cmd_unused(packs, args.unused or None)
    if args.models:
        return cmd_models(packs, args.models, args.animated_only)
    if args.write:
        print(write_block(packs))
        return 0
    if args.diff:
        return cmd_diff(packs)

    print(render_table(packs, read_record()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
