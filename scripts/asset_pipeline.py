"""Wildhaven Asset Pipeline -- raw asset in, built game out.

Takes a path under source-content/assets/ and carries it through assess, import,
content generation, wiring, attribution, validation and build, halting exactly once at
a review checkpoint where a human rules every tuning value.

Design: docs/superpowers/specs/2026-08-30-asset-pipeline-design.md

Run:
  python3 scripts/asset_pipeline.py "<path>" --as animal
  python3 scripts/asset_pipeline.py --selftest      # no LLM calls, no git, no writes
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assetpipe.harness import Checks

ADAPTERS = ("animal", "building", "terrain")


def selftest() -> int:
    from assetpipe import audit, formats, dedupe
    c = Checks()
    formats.selftest_cases(c)
    audit.selftest_cases(c)
    dedupe.selftest_cases(c)
    return c.report("SELFTEST")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("asset", nargs="?", help="Path to a file under source-content/assets/")
    parser.add_argument(
        "--as", dest="adapter", choices=ADAPTERS,
        help="Content type. REQUIRED for a real run -- never inferred from the path, "
             "because the same model can legitimately be an animal or a static prop.",
    )
    parser.add_argument("--selftest", action="store_true",
                        help="Run every deterministic check. No LLM calls, no git, no writes.")
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    if not args.asset:
        parser.error("an asset path is required (or --selftest)")
    if not args.adapter:
        parser.error("--as {animal|building|terrain} is required")
    print("not yet implemented")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
