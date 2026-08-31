#!/usr/bin/env python3
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
import json
import re
import subprocess
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assetpipe.harness import Checks
from assetpipe import checkpoint, ratchets, tracker, blender, attribution, audit, dedupe, formats, importer, llm, review, runlog, worktree, godot, fingerprint, declared
from assetpipe.adapters import animal, building, terrain

ADAPTERS = ("animal", "building", "terrain")
ADAPTER_MODULES = {"animal": animal, "building": building, "terrain": terrain}


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.casefold()).strip("_")


def _resolution_report(asset, resolution) -> list:
    """Lines describing what resolution chose AND what it turned down.

    The rejection reasons used to reach review.json only -- and a gate failure aborts
    before that file is written. So an operator who pointed at a .blend saw
    "missing Walk" and never learnt that Blender could not be launched, which was the
    one piece of text that said what to do. The rejections are the actionable half of a
    resolution; they belong on stdout at the moment it happens.
    """
    lines = [f"[1/10] format...... {resolution.chosen or 'NONE'} -- {resolution.reason}"]
    pointed = asset.suffix.lower().lstrip(".")
    if resolution.chosen and pointed and pointed != resolution.chosen:
        lines.append(
            f"       note....... you pointed at {asset.name}, so this run uses the "
            f"{resolution.chosen} instead of the {pointed}")
    for ext, why in sorted(resolution.rejected.items()):
        lines.append(f"       rejected... {ext}: {why}")
    return lines


def _selftest_cli(c) -> None:
    # A rejected candidate's reason is the only actionable text in a resolution, and it
    # used to reach review.json ONLY -- which a gate failure aborts before writing. An
    # operator who pointed at a .blend then saw "missing Walk" and never learnt that
    # Blender could not be launched. These assert the reasons reach stdout.
    from assetpipe.formats import ModelProbe, Resolution
    _res = Resolution("fbx", Path("/p/FBX/Pig.fbx"),
                      ModelProbe(fmt="fbx", clips=["Idle"]), "fbx is highest-ranked",
                      {"blend": "Blender could not be launched; set BLENDER_PATH",
                       "obj": "no skeleton or animation"})
    _lines = "\n".join(_resolution_report(Path("/p/Blends/Pig.blend"), _res))
    c.check("Blender could not be launched" in _lines,
            "a rejected candidate's reason reaches the operator, not just review.json")
    c.check("no skeleton" in _lines, "every rejection is reported, not only the first")
    c.check("Pig.blend" in _lines and "fbx" in _lines,
            "the report says the resolved format differs from the file pointed at")

    _same = Resolution("blend", Path("/p/Blends/Pig.blend"),
                       ModelProbe(fmt="blend", clips=["Idle", "Walk"]), "blend wins", {})
    _lines_same = "\n".join(_resolution_report(Path("/p/Blends/Pig.blend"), _same))
    c.check("instead of" not in _lines_same,
            "no substitution note when the chosen format is the one pointed at")





    import json as _json
    import tempfile as _tf



    # --- --accept-all ---------------------------------------------------------
    # A run nobody is watching still has to be HONEST about what happened: the .tres
    # header asserted "Every value below was ruled by the human at this run's checkpoint",
    # which under this flag is a false statement written into a file people read later to
    # find out where a tuning value came from.
    c.check("--accept-all" in _parser().format_help(), "the flag is offered")
    c.check(_parser().parse_args(["--selftest"]).accept_all is False,
            "and is off unless asked for -- the checkpoint is the default")

    _hdr_auto = _tres_header("Pig", "run-1", {"asset": "a", "resolved_format":
                             {"chosen": "blend", "reason": "r"}}, auto_accepted=True)
    c.check("not ruled by a human" in _hdr_auto.lower(),
            "an auto-accepted run says so in the header of the file it writes")
    c.check("--accept-all" in _hdr_auto, "and names the flag that did it")
    c.check("ruled by the human" not in _hdr_auto,
            "and does NOT also claim the human ruled them")

    _hdr_human = _tres_header("Pig", "run-1", {"asset": "a", "resolved_format":
                              {"chosen": "blend", "reason": "r"}}, auto_accepted=False)
    c.check("ruled by the human" in _hdr_human,
            "a checkpointed run still records that a human ruled the values")
    c.check("--accept-all" not in _hdr_human, "and does not mention a flag it never used")

    # The halt path is the safety-critical one: a field with no proposal must stop the run
    # rather than resume it, and it must stop WITHOUT calling resume() at all.
    with _tf.TemporaryDirectory() as _td:
        _log = Path(_td) / "runs" / "r1"; _log.mkdir(parents=True)
        _pl = {"decisions": [{"field": "a", "proposal": 3, "value": None},
                             {"field": "b", "proposal": None, "value": None}]}
        _rc = _accept_all_checkpoint("r1", Path(_td), _log, _pl)
        c.eq(_rc, 0, "the run ends cleanly rather than proceeding on a null")
        _written = _json.loads((_log / "review.json").read_text())
        c.eq({d["field"]: d["value"] for d in _written["decisions"]},
             {"a": 3, "b": None},
             "the proposals that existed are recorded; the one that did not stays null")
        c.check(review.unruled(_written) == ["b"],
                "so resume still refuses and names the field nobody ruled")

    import inspect as _insp
    c.check('"auto_accepted": bool(accept_all)' in _insp.getsource(run),
            "the payload records how it was ruled, which is what the .tres header reads")

    # --- the roster ratchets, asked at the checkpoint -------------------------
    # test_attribution.gd's source count and test_resident_wander.gd's EXPECTED_CLIPS both
    # fail BECAUSE content was added -- by design, so that shipping a new source or a new
    # species is a decision. They used to be discovered as a red suite at stage 10, after
    # the token spend, with no hint which of 94 suites cared. Now they are checkpoint
    # fields with measured proposals.
    _row = {"idle": "Idle", "walk": "Walk", "run": "Run", "idle_flavors": []}
    _ds = _ratchet_decisions("animal", "pig", _row, entry_is_new=True, already_pinned=False)
    _by = {d.field: d for d in _ds}
    c.eq(sorted(_by), [ratchets.CLIP_ROW_FIELD, ratchets.NEW_SOURCE_FIELD],
         "both ratchets are offered when both apply")
    c.eq(_by[ratchets.NEW_SOURCE_FIELD].proposal, True,
         "recording a source this run creates is proposed, not assumed")
    c.eq(_by[ratchets.CLIP_ROW_FIELD].proposal,
         '{"idle": "Idle", "walk": "Walk", "run": "Run", "idle_flavors": []}',
         "the clip row is proposed as editable text, prefilled with what was MEASURED")
    for _d in _ds:
        c.eq(_d.confidence, "measured",
             f"{_d.field} is measured, never an LLM proposal")
        c.eq(_d.value, None, "and unruled, so it reaches the checkpoint like any other")
        c.check(_d.source, f"{_d.field} states where its proposal came from")

    c.eq(_ratchet_decisions("animal", "pig", _row, False, False)[0].field,
         ratchets.CLIP_ROW_FIELD,
         "an existing pack's entry needs no source ruling -- only the clip row is asked")
    c.eq(_ratchet_decisions("animal", "pig", _row, False, True), [],
         "a species already pinned with an existing pack asks nothing")
    c.eq(_ratchet_decisions("animal", "pig", None, False, False), [],
         "a model whose clips could not be measured offers no row to rule")
    c.eq([d.field for d in _ratchet_decisions("building", "silo", None, True, False)],
         [ratchets.NEW_SOURCE_FIELD],
         "buildings and terrain are not in EXPECTED_CLIPS, so only the source ratchet applies")

    # The ratchet fields must never reach the .tres: render_tres writes every key it is
    # given, so an unfiltered `values` would emit `ratchet_clip_row = "..."` into a
    # resource the schema has no such field on.
    _values = {"scout_radius": 8, ratchets.NEW_SOURCE_FIELD: True,
               ratchets.CLIP_ROW_FIELD: "{}"}
    c.eq(_adapter_values(_values), {"scout_radius": 8},
         "adapter values exclude the ratchet fields")
    c.eq(_ratchet_values(_values),
         {ratchets.NEW_SOURCE_FIELD: True, ratchets.CLIP_ROW_FIELD: "{}"},
         "and the ratchet rulings are separated out for the test files")
    c.check(all(f.startswith(_RATCHET_PREFIX) for f in ratchets.FIELD_KINDS),
            "every ratchet field carries the prefix the split relies on")
    for _mod in ADAPTER_MODULES.values():
        for _f in _mod.SPEC.fields:
            c.check(not _f.name.startswith(_RATCHET_PREFIX),
                    f"no real adapter field collides with the prefix ({_f.name})")

    # The checkpoint has to know how to parse each one, or the prompt takes them as strings.
    _kinds = _field_kinds(animal.SPEC)
    c.eq(_kinds[ratchets.NEW_SOURCE_FIELD], "bool", "the source ratchet prompts as a bool")
    c.eq(_kinds[ratchets.CLIP_ROW_FIELD], "str", "the clip row prompts as editable text")

    # ORDERING: the rulings must reach the test files BEFORE the suite reads them, or the
    # run reports a failure it had already been told how to fix.
    import inspect as _inspect
    _stages = _inspect.getsource(_resume_stages)
    c.check(_stages.index("ratchets.apply(") < _stages.index("godot.run_tests("),
            "ratchets are applied before the suite runs, not after")
    _resume_src = _inspect.getsource(resume)
    c.check("_adapter_values(ruled)" in _resume_src,
            "the .tres is written from the adapter's fields alone")
    c.check("_ratchet_values(ruled)" in _resume_src,
            "and the ratchet rulings are handed to the stage that owns the test files")

    # --- stage 8's cost line -------------------------------------------------
    # Stage 6 prints what it spent; stage 8 runs a full GER loop per candidate through
    # BOTH copy pipelines and printed nothing, so the most expensive stage of a run was
    # the one with no number against it. Both pipelines now write their per-species cost
    # into the log they already produce, in llm.py's key shape, so the two add up.
    with _tf.TemporaryDirectory() as _td:
        _tree = Path(_td)
        for _dir, _cost in (
                ("fact_card_pipeline_output",
                 {"in": 120, "out": 3000, "usd": 0.15, "usd_known": True}),
                ("style_guide_pipeline_output",
                 {"in": 80, "out": 2000, "usd": 0.10, "usd_known": True})):
            _d = _tree / "scripts" / _dir
            _d.mkdir(parents=True)
            _d.joinpath("pig.json").write_text(_json.dumps({"cost": _cost}))

        _total = _copy_cost(_tree, "pig")
        c.eq(_total["in"], 200, "both pipelines' input tokens are summed")
        c.eq(_total["out"], 5000, "and their output tokens")
        c.eq(round(_total["usd"], 4), 0.25, "and their dollars")
        c.check(_total["usd_known"], "a dollar figure is claimed only when both knew one")

        # An SDK-backed run reports tokens but no price. One such call makes the whole
        # total unknown -- printing the other half as the total would show real spend as
        # nearly free, the same rule _format_cost_line already applies at the checkpoint.
        (_tree / "scripts" / "style_guide_pipeline_output" / "pig.json").write_text(
            _json.dumps({"cost": {"in": 80, "out": 2000, "usd": 0.0,
                                  "usd_known": False}}))
        c.check(not _copy_cost(_tree, "pig")["usd_known"],
                "one backend with no price makes the summed dollar figure unknown")
        c.check("not reported" in _format_cost_line(_copy_cost(_tree, "pig")),
                "and the printed line says so rather than showing $0.10")

        # A log that predates this change, or a stage that never ran, contributes
        # nothing rather than crashing the stage that is only REPORTING on it.
        c.eq(_copy_cost(_tree, "goose"), None, "no logs at all yields no cost line")
        (_tree / "scripts" / "fact_card_pipeline_output" / "old.json").write_text(
            _json.dumps({"candidates": []}))
        c.eq(_copy_cost(_tree, "old"), None, "a log with no cost key yields none either")

    # --- stage 7's tracker stub ----------------------------------------------
    # content-pipeline-status.md's field owners all patch a section they assume exists;
    # nothing created it, so a new species could not be recorded by the pipeline that
    # imported it. These cover the rows stage 7 can honestly state, not tracker.py's
    # placement logic (tracker.selftest_cases owns that).
    _rows = dict(_tracker_rows(
        {"asset": "source-content/assets/Farm Animals by @Quaternius/Blends/Pig.blend",
         "deferred": [{"check": "silhouette",
                       "evidence": {"license": "CC0-1.0",
                                    "license_evidence": "License.txt: matched 'cc0'",
                                    "clips": ["Idle", "Walk"]}}]},
        "20260830-pig-45cd", "project/data/animals/pig.tres",
        "project/assets/animals/pig/Pig.tscn"))
    c.check("CC0-1.0" in _rows["source"], "the audited licence is recorded, not guessed")
    c.check("Farm Animals by @Quaternius" in _rows["source"], "and the pack it came from")
    c.check("2" in _rows["pre_import_audit"], "the clip count the audit actually found")
    c.eq(_rows["project_location"], "`project/assets/animals/pig/Pig.tscn`",
         "the wrapper is the project location, never the raw model")
    c.eq(_rows["data_entry_location"], "`project/data/animals/pig.tres`", "the .tres")
    c.check("pending" in _rows["copy_content_location"],
            "copy is pending -- stage 8 owns this row and overwrites it")
    for _f in ("attribution_status", "validation_status", "human_signoff", "status"):
        c.check(_f in _rows, f"the stub carries a `{_f}` row for its owner to fill")
    c.check("\U0001f6a7" in _rows["status"], "a new item starts in-progress, never done")
    c.check("not" in _rows["human_signoff"].lower(),
            "sign-off is never claimed by the pipeline")

    # --- stage 8's style_guide verdict ---------------------------------------
    # rc=1 from style_guide_pipeline means "at least one line ESCALATED" -- the
    # circuit breaker kept the best draft, wrote it, and marked it AWAITING
    # CONTENT-WRITER SIGN-OFF (style_guide_pipeline.py:900). The Pig run reported
    # "wrote NOTHING ... run it by hand for the real error" over three lines that were
    # sitting in displacement_copy.gd, sending the operator after an error that did not
    # exist. The log is the evidence; rc alone is not.
    with _tf.TemporaryDirectory() as _td:
        _tree = Path(_td)
        _out = _tree / "scripts" / "style_guide_pipeline_output"
        _out.mkdir(parents=True)
        _out.joinpath("pig.json").write_text(_json.dumps({"line_results": {
            "warn": {"status": "escalated", "score": 8,
                     "text": "The pig family needs farmland and grassland."},
            "depart": {"status": "escalated", "score": 8, "text": "d"},
            "move": {"status": "accepted", "score": 10, "text": "m"}}}))

        _line = _style_guide_report(_tree, "pig", 1)
        c.check("wrote 3 line(s)" in _line,
                "an escalated run reports what it WROTE, not that it wrote nothing")
        c.check("2 escalated" in _line, "and how many fell short of the bar")
        c.check("warn" in _line and "depart" in _line,
                "naming the line types the human must review")
        c.check("NOTHING" not in _line, "the false 'wrote NOTHING' claim is gone")
        c.check("sign-off" in _line.lower(),
                "the operator is told the copy landed awaiting sign-off")

        c.eq(_style_guide_report(_tree, "pig", 0),
             "style_guide_pipeline (WARN/DEPART/MOVE)",
             "rc=0 keeps the plain success line")

        # No log at all IS the real failure this message used to claim: the run died
        # before writing anything, and only then is "run it by hand" the right advice.
        _hard = _style_guide_report(_tree, "goose", 1)
        c.check("no log" in _hard and "goose" in _hard,
                "a missing log is reported as a genuine failure")
        c.check("by hand" in _hard, "and that is where the by-hand advice belongs")

    # --- interactive checkpoint wiring ---------------------------------------
    # checkpoint.py owns the prompt loop; these cover only the two things
    # asset_pipeline.py adds: the kinds map the loop is driven with, and what the
    # operator's answers turn into -- resume, halt, or abandon.
    _kinds = _field_kinds(animal.SPEC)
    for _f in animal.SPEC.fields:
        c.eq(_kinds[_f.name], _f.kind, f"{_f.name}'s kind comes from its FieldSpec")

    def _drive(answers, payload):
        it = iter(answers)
        return _interactive_checkpoint(payload, _kinds, lambda _p: next(it), lambda _l: None)

    def _payload():
        return {"decisions": [
            {"field": "scout_radius", "proposal": 8, "value": None, "source": "s",
             "confidence": "low"},
            {"field": "farm_tolerant", "proposal": True, "value": None, "source": "s",
             "confidence": "low"},
        ]}

    _action, _ruled = _drive(["", ""], _payload())
    c.eq(_action, "resume", "ruling every field resumes the run without a second command")
    c.eq([d["value"] for d in _ruled["decisions"]], [8, True],
         "the rulings are written into the payload through apply_rulings")

    _action, _ruled = _drive([checkpoint.SKIP, ""], _payload())
    c.eq(_action, "halt", "a skipped field halts instead of resuming")
    c.check(review.unruled(_ruled) == ["scout_radius"],
            "and the skipped field is still unruled, so resume names it")

    _action, _ruled = _drive([checkpoint.ABANDON], _payload())
    c.eq(_action, "abandon", "a abandons the run")
    c.eq(_ruled, None, "an abandoned checkpoint writes no rulings")

    c.check("--no-interactive" in _parser().format_help(),
            "--no-interactive is offered for non-TTY and scripted use")
    c.check(not _should_prompt(interactive=True, isatty=False),
            "a non-TTY run never prompts, so CI and piped runs halt as before")
    c.check(not _should_prompt(interactive=False, isatty=True),
            "--no-interactive forces the old file-based behaviour on a TTY")
    c.check(_should_prompt(interactive=True, isatty=True),
            "a plain terminal run prompts")

    c.eq(slug("Shiba Inu"), "shiba_inu", "display name to id")
    c.eq(slug("Common Tree 1"), "common_tree_1", "digits preserved")
    c.eq(slug("Pig"), "pig", "single word")
    c.eq(sorted(ADAPTER_MODULES), ["animal", "building", "terrain"],
         "three adapters registered")
    for name, module in ADAPTER_MODULES.items():
        c.eq(module.SPEC.name, name, f"{name} module's SPEC matches its key")
        c.check(hasattr(module, "decisions"), f"{name} exposes decisions()")

    import inspect
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        log_path = Path(td) / "build.log"
        log_path.write_text("exporting...\ndone\n")
        c.check(build_log_clean(log_path), "a clean build log passes")
        log_path.write_text("exporting...\nERROR: Cannot open file\ndone\n")
        c.check(not build_log_clean(log_path),
                "an ERROR: line fails the build even though the script exits 0")

        # Spec's required selftest: the GER pipelines must run from the WORKTREE's
        # own copy. They resolve their repo root from __file__, so invoking the main
        # checkout's copy would patch the main checkout while we believe we are
        # sandboxed. Assert the invocation is cwd-anchored to the worktree.
        src = Path("scripts/asset_pipeline.py").read_text()
        c.check('"scripts/fact_card_pipeline.py"' in src and "cwd=tree" in src,
                "fact_card_pipeline is invoked with cwd=tree, not the main checkout")
        c.check("REPO_ROOT / \"scripts\"" not in src,
                "no absolute main-checkout path is built for the GER pipelines")

        # Both GER copy pipelines are wired per the design's adapter table (line 181):
        # fact_card_pipeline -> fact_text_pool, style_guide_pipeline -> WARN_/DEPART_/
        # MOVE_. Missing the second one ships a new animal with no Gentle Displacement
        # lines, falling through to WARN_GENERIC.
        c.check('"scripts/style_guide_pipeline.py"' in src,
                "style_guide_pipeline is invoked for the Gentle Displacement copy")
        c.check('payload["adapter"] == "animal"' in src,
                "style_guide_pipeline is guarded to animals only -- buildings and "
                "terrain have no WARN_/DEPART_/MOVE_ lines")

        payload = {"decisions": [{"field": "cost", "proposal": 40, "value": None,
                                  "source": "s", "confidence": "med"}]}
        c.check(not review.ready(payload), "resume refuses an unruled review")
        payload["decisions"][0]["value"] = 25
        c.check(review.ready(payload), "resume proceeds once every field is ruled")

        # REGRESSION, whole-branch review IMPORTANT 8: buildings' copy row targets the
        # buildings directory, and terrain has no copy row at all.
        c.check('cmd += ["--target", "building_text"]' in src,
                "the fact-card pipeline is given --target building_text for buildings")
        c.check('if adapter_name == "terrain":' in src,
                "terrain skips the fact-card pipeline -- its spec copy row is 'none'")

        # REGRESSION, whole-branch review IMPORTANT 7: both copy pipelines ran with
        # check=False and printed a success line regardless of outcome.
        copy_src = inspect.getsource(_copy_stage)
        c.eq(copy_src.count("check=False).returncode"), 2,
             "both copy pipelines' return codes are captured, not discarded")
        c.eq(copy_src.count("FAILED rc={rc}"), 1,
             "fact_card's non-zero return reports the code instead of printing success")
        c.check("if rc == 0:" in copy_src,
                "fact_card's success line is printed only on a zero return code")
        c.eq(copy_src.count("ROSTER is DERIVED"), 1,
             "fact_card's failure message describes the DERIVED roster, not the hardcode "
             "da039b1 removed -- it used to send the operator editing a list that no "
             "longer exists")
        # style_guide's verdict moved into _style_guide_report, because its rc conflates
        # "escalated, and written" with "failed, and wrote nothing". Its return code is
        # still captured; what changed is that the LOG decides which message is printed.
        c.check("_style_guide_report(tree, ident, rc)" in copy_src,
                "style_guide's outcome is reported from its log, not from rc alone")
        sg_src = inspect.getsource(_style_guide_report)
        c.check("line_results" in sg_src and "escalated" in sg_src,
                "and that report reads the run's own per-line verdicts")

        # REGRESSION, whole-branch review IMPORTANT 5: the ruled model_scale never reached
        # the wrapper, which is the only place scale lives.
        stages_src = inspect.getsource(_resume_stages)
        c.check("importer.rescale_wrapper(wrapper, scale)" in stages_src,
                "resume rewrites the wrapper with the ruled scale, not the 0.2 run() wrote")
        c.check('values.get("model_scale")' in stages_src,
                "the scale rewritten is the one from the review, not a constant")
        code_only = [line for line in stages_src.splitlines()
                     if not line.lstrip().startswith("#")]
        c.check(not any("0.2" in line for line in code_only),
                "resume hardcodes no scale of its own")

        # REGRESSION, review CRITICAL 1: both write_wrapper call sites built the model
        # filename from the SOURCE's suffix, so a converted .blend produced a .tscn
        # pointing at Pig.blend -- a file copy_model deliberately never writes. The
        # filename must come from what copy_model WROTE, so the next converting format
        # cannot reintroduce this. The joint behaviour is asserted in
        # importer.selftest_cases; this guards the call sites.
        run_src = inspect.getsource(run)
        c.check("chosen_path.suffix" not in run_src,
                "run() no longer names the wrapper's model file after the SOURCE suffix")
        # Structural rather than a token count: the .import path is now built from the
        # same name too, so counting occurrences would drift every time another consumer
        # of the written filename is added. What must hold is that EVERY write_wrapper
        # call site takes it.
        _sites = [i for i in range(len(run_src))
                  if run_src.startswith("importer.write_wrapper(", i)]
        c.eq(len(_sites), 2, "run() writes the wrapper exactly twice -- before and after "
                             "the AnimationPlayer probe")
        for _at in _sites:
            c.check("copied.model.name" in run_src[_at:_at + 300],
                    "this write_wrapper call uses the filename copy_model actually wrote")
        c.check("copied.model.name" in run_src[run_src.index(".import"):][:400],
                "and so does the .import path whose loop modes are rewritten")

        # REGRESSION, whole-branch review IMPORTANT 17: copy_license_text was implemented,
        # hardened, tested and never called.
        c.check("attribution.copy_license_text" in inspect.getsource(_preserve_license),
                "stage 9 preserves the pack's licence text offline")
        c.check("_preserve_license(pack, project, tree)" in stages_src,
                "stage 9 actually invokes it")

    # REGRESSION, whole-branch review IMPORTANT 4/14: resume()'s validation dispatch
    # reached only animal.py, so an unknown hotbar_category was written straight through.
    c.check(_validate(building, "building", "well", None, {"hotbar_category": "workshop"}),
            "an unknown hotbar_category is caught by the path resume() uses")
    c.eq(_validate(building, "building", "well", None,
                   {"hotbar_category": "farm_building"}), [],
         "a known hotbar_category passes that path")
    c.check(_validate(terrain, "terrain", "wild_grass", terrain.MODE_NEW_TYPE,
                      {"emitted_tags": ["forest"]}),
            "terrain new_type gets the inert-land check through resume()'s path")
    c.eq(_validate(terrain, "terrain", "wild_grass", terrain.MODE_VARIANT,
                   {"model_scale": 1.0}), [],
         "variant mode writes no terrain id, so the inert-land check does not apply")
    c.eq(_validate(animal, "animal", "pig", None,
                   {"habitat_needs": ["forest"], "avoids": [], "scout_radius": 10,
                    "capacity_radius": 0, "tiles_per_individual": 5,
                    "max_individuals": 6, "personality": "Shy"}), [],
         "animal's existing validation still runs through the shared path")

    # PROMOTED MINOR: formats.pack_root's unguarded relative_to raised a bare ValueError
    # from inside run()'s try -- after the worktree existed, stranding it.
    with tempfile.TemporaryDirectory() as td:
        outside = Path(td) / "Loose.fbx"
        outside.write_bytes(b"\x00")
        problems = validate_asset_path(outside)
        c.check(any("not under" in p for p in problems),
                "an asset outside the assets root is refused before the worktree exists")
        c.check(any("is not a file" in p
                    for p in validate_asset_path(Path(td) / "nope.fbx")),
                "a nonexistent asset is refused too")
        inside_root = Path(td) / "assets"
        (inside_root / "Pack" / "FBX").mkdir(parents=True)
        good = inside_root / "Pack" / "FBX" / "Pig.fbx"
        good.write_bytes(b"\x00")
        c.eq(validate_asset_path(good, assets_root=inside_root), [],
             "a real asset under the assets root passes")

    # REGRESSION, review MINOR: the suite is offline, and resolve() asks
    # _blender_available() for every .blend candidate -- which with no override is
    # shutil.which("blender") followed by a real launch. On this machine that started
    # /snap/bin/blender, the exact build that dies under a confined sandbox after burning
    # the timeout, and made the verdict machine-dependent.
    c.check("_pinned_blender" in inspect.getsource(formats.selftest_cases),
            "format resolution's cases pin BLENDER_PATH -- the suite never launches the "
            "machine's own Blender")

    c.check("traceback.print_exc()" in inspect.getsource(run),
            "run()'s handler prints the traceback, not just str(exc)")
    c.check("traceback.print_exc()" in inspect.getsource(resume),
            "resume() has a broad handler that prints the traceback")
    c.check("worktree KEPT at" in inspect.getsource(resume),
            "resume()'s handler names the worktree it kept")

    # REGRESSION, whole-branch review IMPORTANT 9: --abandon could not clean up a crashed
    # run, and the stranded worktree then blocked every future run at preflight.
    c.eq(worktree_of("20260830-shiba_inu-ab12", Path("/r")),
         (Path("/r/.worktrees/asset-shiba_inu"), "asset/shiba_inu"),
         "worktree path and branch are recoverable from the run id alone")

    with tempfile.TemporaryDirectory() as td:
        import subprocess as _sp
        repo = Path(td) / "repo"
        (repo / "project").mkdir(parents=True)
        (repo / "project" / "a.tres").write_text("one\n")
        for args in (["init", "-b", "main"], ["add", "."],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "init"]):
            _sp.run(["git", *args], cwd=repo, check=True, capture_output=True)
        worktree.create(repo, "asset/pig", repo / ".worktrees" / "asset-pig")

        run_id = "20260830-pig-ab12"
        c.check(not (repo / "runs" / run_id / "review.json").is_file(),
                "the crashed-run fixture has no review.json, as a crash before stage 1 does")
        c.eq(abandon_run(run_id, repo), 0,
             "abandon_run succeeds when review.json is absent")
        c.check(not (repo / ".worktrees" / "asset-pig").exists(),
                "the stranded worktree is actually removed")
        c.eq(preflight_names(repo), [],
             "and preflight is unblocked afterwards")

    c.check('"incomplete": True' in src,
            "run() writes an abandon-able stub before any stage runs")
    c.check('payload.get("incomplete")' in inspect.getsource(resume),
            "resume refuses that stub -- its empty decisions list is not 'nothing to rule'")


def preflight_names(repo: Path) -> list[str]:
    return [p for p in worktree.preflight(repo) if "stale worktree" in p]


def selftest() -> int:
    from assetpipe.adapters import base
    c = Checks()
    attribution.selftest_cases(c)
    formats.selftest_cases(c)
    fingerprint.selftest_cases(c)
    declared.selftest_cases(c)
    audit.selftest_cases(c)
    dedupe.selftest_cases(c)
    review.selftest_cases(c)
    runlog.selftest_cases(c)
    worktree.selftest_cases(c)
    importer.selftest_cases(c)
    blender.selftest_cases(c)
    checkpoint.selftest_cases(c)
    tracker.selftest_cases(c)
    ratchets.selftest_cases(c)
    base.selftest_cases(c)
    animal.selftest_cases(c)
    building.selftest_cases(c)
    terrain.selftest_cases(c)
    llm.selftest_cases(c)
    godot.selftest_cases(c)
    _selftest_cli(c)
    return c.report("SELFTEST")


def _field_kinds(spec) -> dict:
    """Field name to FieldSpec.kind, so the prompt loop parses what the operator types
    as the type the .tres will hold rather than as a string. The ratchet fields are not
    on any AdapterSpec -- they belong to the test files, not the schema -- so their kinds
    are merged in here, or the prompt would take a bool answer as the string "y"."""
    return {f.name: f.kind for f in spec.fields} | dict(ratchets.FIELD_KINDS)


def _should_prompt(interactive: bool, isatty: bool) -> bool:
    """Prompting requires both a terminal to prompt on and the operator not having
    opted out. Off a TTY -- CI, a piped run, this pipeline driven from a Claude Code
    Bash call -- `input` would raise on the first field, so the run halts at
    review.json exactly as it always did."""
    return interactive and isatty


def _interactive_checkpoint(payload: dict, kinds: dict, input_fn, output_fn):
    """Rule the checkpoint in the terminal. Returns (action, payload):
    "resume" with every field ruled, "halt" when the operator skipped some (the
    skipped ones stay null, so `resume` still refuses and names them), or
    ("abandon", None). Side effects belong to the caller -- this decides only."""
    rulings = checkpoint.prompt_rulings(payload, kinds, input_fn, output_fn)
    if rulings is None:
        return "abandon", None
    ruled = review.apply_rulings(payload, rulings)
    return ("resume" if review.ready(ruled) else "halt"), ruled


def _format_cost_line(cost: dict) -> str:
    """cost carries in/out/usd/usd_known. The SDK backend reports no dollar figure
    (llm.py: "the Messages API returns no dollar figure and this repo has no pricing
    table") -- printing $0.00 in that case would present a real spend as free. Only
    print a dollar figure when every stage that contributed cost knew its own price."""
    tokens = f"{cost.get('in', 0):,} in / {cost.get('out', 0):,} out tokens"
    if cost.get("usd_known", True):
        return f"${cost.get('usd', 0.0):.4f} ({tokens})"
    return f"{tokens} (dollar cost not reported by this backend)"


def validate_asset_path(asset: Path, assets_root: Path = formats.ASSETS_ROOT) -> list[str]:
    """Checked BEFORE the worktree is created, and that ordering is the point.

    formats.pack_root() calls Path.relative_to() unguarded, so an asset outside
    source-content/assets/ raised a bare ValueError from inside run()'s try -- by which
    time the worktree existed. It was then stranded (--abandon had no review.json to read)
    and blocked every later run at preflight. Failing here costs nothing.
    """
    problems: list[str] = []
    if not asset.is_file():
        problems.append(f"{asset} is not a file")
        return problems
    try:
        formats.pack_root(asset, assets_root)
    except ValueError:
        problems.append(
            f"{asset} is not under {assets_root}/ -- this pipeline only imports assets "
            f"that live in the source-content drop, because the pack folder is where the "
            f"licence and the attribution entry are found")
    return problems


def _validate(module, adapter_name: str, ident: str, mode: str | None,
              values: dict) -> list[str]:
    """Every adapter's pre-write validation, in one place.

    resume() used to call module.validate_values(values) behind a hasattr guard, and only
    animal.py had one -- so buildings wrote an unvalidated hotbar_category and terrain got
    no pass at all. building.py now has validate_values; terrain's check needs the IDENT,
    which a validate_values(values) signature cannot carry, so it is called directly, and
    only in new_type mode -- variant mode writes no .tres and defines no terrain id.
    """
    problems: list[str] = []
    if hasattr(module, "validate_values"):
        problems += module.validate_values(values)
    if adapter_name == "terrain" and mode == terrain.MODE_NEW_TYPE:
        problems += module.check_new_type(ident, values)
    return problems


def run(asset: Path, adapter_name: str, repo: Path, notes: str = "",
        dry_run: bool = False, variant_of: str | None = None,
        interactive: bool = True, accept_all: bool = False) -> int:
    module = ADAPTER_MODULES[adapter_name]
    spec = module.SPEC
    display = asset.stem
    ident = slug(display)
    mode = "variant" if variant_of else ("new_type" if adapter_name == "terrain" else None)

    problems = validate_asset_path(asset) + worktree.preflight(repo)
    if problems:
        for p in problems:
            print(f"PREFLIGHT: {p}")
        return 1

    run_id = runlog.new_run_id(ident)
    log = runlog.RunLog(repo / "runs", run_id)
    base_branch = worktree.current_branch(repo)
    branch = f"asset/{ident}"
    tree = worktree.create(repo, branch, repo / ".worktrees" / f"asset-{ident}")
    print(f"[0/10] worktree..... {tree}  ({worktree.seed_import_cache(repo, tree)})")

    # Written BEFORE any stage runs, so --abandon always has something to read. review.json
    # used to appear only at the checkpoint; a crash in stages 1-6 therefore left
    # abandon_run raising FileNotFoundError, and the stranded worktree then blocked every
    # future run at preflight. `incomplete` is what stops resume() acting on a stub.
    review.write(log.dir / "review.json", {
        "run_id": run_id, "asset": str(asset), "adapter": adapter_name,
        "worktree": str(tree), "branch": branch, "base_branch": base_branch,
        "mode": mode, "variant_of": variant_of, "decisions": [], "incomplete": True,
    })

    project = tree / "project"
    try:
        # required_clips goes IN, not just to the gate afterwards: whichever source
        # covers more of what the gate will demand wins, so we never pick a clip-rich
        # source that lacks Walk and then reject the asset as unusable at stage 2 while a
        # usable sibling sat beside it.
        resolution = formats.resolve(asset, spec.needs_rig,
                                     required_clips=spec.required_clips)
        for line in _resolution_report(asset, resolution):
            print(line)

        gate = audit.gate(resolution, spec.required_clips, formats.pack_root(asset),
                          adapter_name=spec.name)
        if not gate.passed:
            for p in gate.problems:
                print(f"[2/10] audit....... FAIL {p}")
            worktree.abandon(repo, tree, branch)
            return 1
        print(f"[2/10] audit....... PASS (licence {gate.evidence['license']}, "
              f"{len(gate.evidence['clips'])} clips)")

        dupe = dedupe.check(asset, project / "assets",
                            tree / "game-design" / "content-pipeline-status.md")
        if dupe.is_dupe:
            print(f"[3/10] dedupe...... HALT already present: {dupe.matches[:3]}")
            worktree.abandon(repo, tree, branch)
            return 1
        print("[3/10] dedupe...... no match")

        # The wrapper's model file is the one copy_model WROTE, never the source's
        # suffix: a .blend is converted, so the source is Pig.blend and the artifact is
        # Pig.gltf. Naming it after the source produced a .tscn referencing a file the
        # pipeline deliberately never copies.
        copied = importer.copy_model(resolution, project, spec.category, ident, display)
        importer.write_wrapper(project, spec.category, ident, display,
                               copied.model.name,
                               0.2, gate.evidence["license"], None, spec.schema)
        print(f"[4/10] import...... {len(copied.files)} file(s) -> "
              f"{importer.dest_dir(project, spec.category, ident)}")

        godot.import_project(tree, repo)
        scene_res = f"assets/{spec.category}/{ident}/{display}.tscn"
        idx = godot.anim_index(tree, scene_res, repo) if spec.required_clips else -1
        if idx >= 0:
            importer.write_wrapper(project, spec.category, ident, display,
                                   copied.model.name, 0.2,
                                   gate.evidence["license"], idx, spec.schema)
            godot.import_project(tree, repo)
        godot.write_import_test(tree, ident, display, spec.category,
                                resolution.probe.clips, spec.required_clips)
        heuristic = set(resolution.probe.clips)
        # Measured through AnimalClips, the resolver the GAME uses -- the pre-gate's clip
        # list cannot say which of the three naming conventions this model follows, and
        # that is precisely what test_resident_wander.gd's table pins.
        clip_row = godot.clip_row(tree, scene_res, repo) if adapter_name == "animal" else None

        # A locomotion clip that does not loop plays once and freezes while the model keeps
        # moving -- test_resident_wander.gd calls that "the glide bug". Godot leaves
        # `_subresources={}` on a fresh import, so the loop flags have to be written, and
        # the set to write is exactly what was just measured: idle, walk, run, flavours.
        looped: list[str] = []
        if clip_row:
            import_file = (importer.dest_dir(project, spec.category, ident)
                           / f"{copied.model.name}.import")
            if import_file.is_file():
                looped = [clip_row["idle"], clip_row["walk"], clip_row["run"],
                          *clip_row["idle_flavors"]]
                import_file.write_text(
                    importer.set_loop_modes(import_file.read_text(), looped))
                godot.import_project(tree, repo)

        print(f"[5/10] verify...... AnimationPlayer index {idx}; "
              f"{len(heuristic)} clips from the pre-gate"
              + (f"; resolves idle={clip_row['idle']} walk={clip_row['walk']}"
                 f"; {len([c for c in looped if c])} clip(s) set to loop"
                 if clip_row else ""))

        # cost's usd_known starts True: a dry run or a run whose only stage was free
        # made no unpriced spend, so there is nothing to warn about.
        usd_known = True
        if dry_run:
            decisions = module.decisions(resolution.probe, mode) \
                if spec.name == "terrain" else module.decisions(resolution.probe)
            print("[6/10] values...... --dry-run: proposals skipped, fields unruled")
        else:
            decisions, usage = llm.propose(spec, display, resolution.probe, notes)
            if spec.name == "terrain" and mode == "variant":
                keep = {d.field for d in module.decisions(resolution.probe, mode)}
                decisions = [d for d in decisions if d.field in keep]
            usd_known = usage.get("usd_known", True)
            log.record(6, "values", runlog.stage_key(ident, resolution.chosen),
                       {"fields": [d.field for d in decisions]}, usage)
            print(f"[6/10] values...... {len(decisions)} proposed")

        # The roster ratchets: guards that fire because content was ADDED. Asked here, with
        # measured proposals, rather than met as an unexplained red suite at stage 10.
        decisions += _ratchet_decisions(
            adapter_name, ident, clip_row,
            entry_is_new=_entry_is_new(project, asset, gate.evidence.get("license", "")),
            already_pinned=ratchets.clips_pinned(
                _read_or_empty(tree / "project" / "tests" / ratchets.WANDER_TEST), ident))

        cost = log.total_cost()
        cost["usd_known"] = usd_known

        payload = {
            "run_id": run_id, "asset": str(asset), "adapter": adapter_name,
            "worktree": str(tree), "branch": branch, "base_branch": base_branch,
            "mode": mode, "variant_of": variant_of, "incomplete": False,
            # Read back by _tres_header: the generated resource states its own provenance,
            # and "a human ruled this" must not be written about a run where none did.
            "auto_accepted": bool(accept_all),
            "resolved_format": {"chosen": resolution.chosen, "reason": resolution.reason,
                                "rejected": resolution.rejected},
            "decisions": [d.to_dict() for d in decisions],
            "deferred": [{"check": "silhouette", "evidence": gate.evidence}],
            "cost": cost,
        }
        review.write(log.dir / "review.json", payload)

        if dry_run:
            # --dry-run makes no LLM calls and decides nothing a human must rule on --
            # leaving the worktree behind would strand a branch with no checkpoint to
            # resolve it. review.json is still written, for inspection only.
            worktree.abandon(repo, tree, branch)
            print(f"\n=== DRY RUN COMPLETE === worktree abandoned; nothing awaits your ruling")
            print(f"  {log.dir / 'review.json'}  (informational only)")
            return 0

        print(f"\n=== CHECKPOINT === {len(review.unruled(payload))} field(s) await your ruling")
        print(f"  cost: {_format_cost_line(cost)}")

        if accept_all:
            return _accept_all_checkpoint(run_id, repo, log.dir, payload)

        if _should_prompt(interactive, sys.stdin.isatty()):
            try:
                action, ruled = _interactive_checkpoint(
                    payload, _field_kinds(spec), input, print)
            except (EOFError, KeyboardInterrupt):
                # Ctrl-D or Ctrl-C mid-prompt is not a ruling. Fall through to the
                # file-based halt with the run intact -- nothing typed so far is kept,
                # because a half-answered checkpoint is not a decision.
                print("\n  interrupted; nothing ruled.")
                action, ruled = "halt", payload
            if action == "abandon":
                return abandon_run(run_id, repo)
            review.write(log.dir / "review.json", ruled)
            if action == "resume":
                return resume(run_id, repo)
            payload = ruled
            print(f"  {len(review.unruled(payload))} field(s) still unruled.")

        print(f"  {log.dir / 'review.json'}")
        print(f"  resume:  python3 scripts/asset_pipeline.py --resume {run_id}")
        print(f"  abandon: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 0

    except Exception as exc:
        # The traceback, not just str(exc). This handler spans every stage, and several
        # of them raise messages that name no location at all (a bare ValueError, a
        # subprocess timeout); an unattributable one-liner on the first real run of a
        # 10-stage pipeline is not a diagnosis.
        print(f"FAILED: {type(exc).__name__}: {exc}")
        traceback.print_exc()
        print(f"worktree left intact for inspection: {tree}")
        print(f"clean it up with: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 1


def build_log_clean(log_path: Path) -> bool:
    """build-game.sh exits 0 even when the export is broken -- Godot writes
    project.binary and reports success while omitting files the game needs to boot.
    /deploy-game greps for ^ERROR: for exactly this reason; so do we."""
    return not any(line.startswith("ERROR:")
                   for line in log_path.read_text().splitlines())


def build(repo: Path) -> tuple[bool, str]:
    log_path = repo / "runs" / "last-build.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(["bash", "scripts/build-game.sh", "web-singlethread", "release"],
                          cwd=repo, capture_output=True, text=True, timeout=3600)
    log_path.write_text(proc.stdout + proc.stderr)
    ok = proc.returncode == 0 and build_log_clean(log_path)
    return ok, str(log_path)


def worktree_of(run_id: str, repo: Path) -> tuple[Path, str]:
    """Where run() would have put this run's worktree and branch.

    run_id is "<yyyymmdd>-<ident>-<hex4>" and slug() never emits a hyphen, so the ident is
    recoverable from it -- which is what lets --abandon clean up a run that died before
    it wrote anything at all.
    """
    ident = "-".join(run_id.split("-")[1:-1])
    return repo / ".worktrees" / f"asset-{ident}", f"asset/{ident}"


def abandon_run(run_id: str, repo: Path) -> int:
    """Destroy a run's worktree and branch. Must work on a CRASHED run.

    A run that died before its checkpoint used to leave abandon_run raising
    FileNotFoundError on the missing review.json -- and the stranded worktree then blocked
    every future run at preflight, with no supported way out. run() now writes a stub
    immediately, and this falls back to deriving the paths from the run id when even that
    is absent.
    """
    path = repo / "runs" / run_id / "review.json"
    if path.is_file():
        payload = review.read(path)
        tree, branch = Path(payload["worktree"]), payload["branch"]
    else:
        tree, branch = worktree_of(run_id, repo)
        print(f"no review.json for {run_id}; derived worktree {tree} and branch {branch} "
              f"from the run id")
    worktree.abandon(repo, tree, branch)
    print(f"abandoned {run_id}: worktree and branch removed")
    print(f"evidence kept: {repo / 'runs' / run_id}")
    return 0


def resume(run_id: str, repo: Path) -> int:
    log_dir = repo / "runs" / run_id
    payload = review.read(log_dir / "review.json")

    if payload.get("incomplete"):
        # The stub run() writes before stage 1, so --abandon always has something to read.
        # It carries no decisions, which would otherwise read as "nothing left to rule".
        print(f"cannot resume {run_id}: it never reached its checkpoint. This review.json "
              f"is the stub --abandon needs, not a ruling sheet.")
        print(f"  abandon: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 1

    unruled = review.unruled(payload)
    if unruled:
        print(f"cannot resume: {len(unruled)} field(s) still unruled: {unruled}")
        print("Every tuning value is the human's. Rule them in "
              f"{log_dir / 'review.json'}, or via /add-asset.")
        return 1

    module = ADAPTER_MODULES[payload["adapter"]]
    adapter_name = payload["adapter"]
    tree = Path(payload["worktree"])
    mode = payload.get("mode")
    project = tree / "project"
    ident = slug(Path(payload["asset"]).stem)
    display = Path(payload["asset"]).stem
    ruled = {d["field"]: d["value"] for d in payload["decisions"]}
    # The ratchet rulings belong to the TEST FILES, not the resource: render_tres writes
    # every key it is handed, and no schema declares a `ratchet_*` field.
    values = _adapter_values(ruled)

    problems = _validate(module, adapter_name, ident, mode, values)
    if problems:
        for p in problems:
            print(f"VALIDATION: {p}")
        return 1

    try:
        return _resume_stages(run_id, repo, payload, module, adapter_name, tree, project,
                              mode, ident, display, values, _ratchet_values(ruled))
    except Exception as exc:
        # resume() is the function that touches the OPERATOR'S REAL REPOSITORY, and the
        # stages below raise messages that name no location: terrain.write()'s inert-land
        # RuntimeError, regenerate_credits' RuntimeError, attribution.AmbiguousEntry. A
        # raw traceback here would leave the operator holding a worktree with no statement
        # of what it contains or how to get rid of it.
        print(f"FAILED at resume: {type(exc).__name__}: {exc}")
        traceback.print_exc()
        print(f"worktree KEPT at {tree} -- nothing was merged and the main checkout is "
              f"untouched.")
        print(f"clean it up with: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 1


def _resume_stages(run_id: str, repo: Path, payload: dict, module, adapter_name: str,
                   tree: Path, project: Path, mode: str | None, ident: str, display: str,
                   values: dict, ratchet_rulings: dict | None = None) -> int:
    header = _tres_header(display, run_id, payload,
                          bool(payload.get("auto_accepted")))

    # The ruled model_scale has to reach the artifact. run() wrote the wrapper BEFORE the
    # checkpoint with a hardcoded 0.2 (it must, so Godot can probe the AnimationPlayer),
    # and every adapter strips model_scale before rendering its .tres -- so the wrapper is
    # the only place scale lives, and nothing was putting the ruling into it. A building
    # ruled 1.0 shipped at 0.2; in terrain variant mode, where scale is the ONLY field the
    # human is asked for, the checkpoint was entirely decorative.
    scale = values.get("model_scale")
    if scale is None:
        print("[7/10] scale....... no model_scale in this review -- wrapper left as run() "
              "wrote it")
    else:
        wrapper = importer.dest_dir(project, module.SPEC.category, ident) / f"{display}.tscn"
        print(f"[7/10] scale....... {importer.rescale_wrapper(wrapper, scale)}")

    if mode == "variant":
        # A tree has no .tres of its own: it is appended to an existing terrain type's
        # model_scenes, and style_picker_popup derives its label from the directory name.
        host = project / "data" / "terrain" / f"{payload['variant_of']}.tres"
        summary = module.append_variant(
            host, f"res://assets/terrain/{ident}/{display}.tscn")
        print(f"[7/10] data entry.. {host.name}: {summary}")
    else:
        path = module.write(project, ident, display, values, header)
        print(f"[7/10] data entry.. {path.relative_to(tree)}")

    # BEFORE the copy stage, deliberately: fact_card_pipeline patches this item's
    # `copy_content_location` row and reports "tracker not updated" when the section is
    # absent -- which it always was, for anything the pipeline had just imported.
    wrapper_rel = (importer.dest_dir(project, module.SPEC.category, ident)
                   / f"{display}.tscn").relative_to(tree)
    # A terrain variant has no .tres of its own -- it was appended to the host type's
    # model_scenes -- so its data-entry row names the host, not a file that never exists.
    tres_path = (project / "data" / "terrain" / f"{payload['variant_of']}.tres"
                 if mode == "variant"
                 else project / "data" / module.SPEC.data_dir / f"{ident}.tres")
    tres_rel = tres_path.relative_to(tree)
    print(f"[7/10] tracker..... " + tracker.ensure_section(
        tree / "game-design" / "content-pipeline-status.md",
        module.SPEC.category, ident, display,
        _tracker_rows(payload, run_id, str(tres_rel), str(wrapper_rel))))

    _copy_stage(adapter_name, tree, display, ident, payload)

    # Extending an existing pack's entry is the common path. A pack with NO entry used to
    # halt here: authoring one was called a licensing decision. But stage 2 has already
    # CLEARED the licence from the pack's own License.txt -- refusing to record what that
    # gate accepted meant the pipeline would import art and ship it uncredited. Using the
    # asset and crediting it are one decision, so the entry is generated from the same
    # evidence. What is still refused is a licence whose OBLIGATIONS the file does not
    # state (a store EULA): that halts, because guessing there is a compliance failure.
    pack = formats.pack_root(Path(payload["asset"]))
    try:
        entry = attribution.find_entry(project, "Quaternius", pack.name)
    except attribution.AmbiguousEntry as exc:
        print(f"[9/10] credits..... HALT {exc}")
        return 1

    # Before the entry, so its license_file names a file that is actually on disk.
    _preserve_license(pack, project, tree)

    if entry is None:
        evidence = (payload.get("deferred") or [{}])[0].get("evidence", {})
        try:
            entry = attribution.new_entry_for_pack(
                project, pack, "Quaternius", evidence.get("license", ""),
                evidence.get("license_evidence", "no evidence recorded"), [display])
        except attribution.UnautomatableLicence as exc:
            print(f"[9/10] credits..... HALT {exc}")
            return 1
        print(f"[9/10] credits..... new entry {entry.relative_to(tree)} "
              f"({evidence.get('license', '')}, assets_used=[{display!r}])")
    else:
        print(f"[9/10] credits..... {attribution.extend_assets_used(entry, [display])}")
    godot.regenerate_credits(tree, repo)

    # BEFORE the suite runs, so what runs is the tree the human ruled. Both guards are
    # deliberate -- ruling no leaves one failing, and that is a choice, not a surprise.
    for line in ratchets.apply(project / "tests", project / "attribution" / "sources",
                               ident, ratchet_rulings or {}):
        print(f"[10/10] ratchets... {line}")

    passed, output = godot.run_tests(tree, repo=repo)
    print(f"[10/10] tests...... {'PASS' if passed else 'FAIL'}")
    if not passed:
        print(output[-2000:])
        return 1

    worktree.commit_all(tree, f"feat(content): add {display} via asset pipeline ({run_id})")
    try:
        worktree.merge(repo, payload["branch"], payload["base_branch"])
    except worktree.MainBranchRefused as exc:
        print(f"\n{exc}")
        print(f"worktree kept at {tree}")
        return 2

    worktree.abandon(repo, tree, payload["branch"])
    ok, log_path = build(repo)
    print(f"build....... {'OK' if ok else 'FAILED'} ({log_path})")
    return 0 if ok else 1


def _accept_all_checkpoint(run_id: str, repo: Path, log_dir: Path,
                           payload: dict) -> int:
    """--accept-all: take every proposal and carry straight on to the remaining stages.

    A field with NO proposal is NOT accepted -- there is nothing to accept -- so the run
    halts on those exactly as an unruled review always has, naming them. Everything else
    is written through the same apply_rulings the prompt and the hand-edited review.json
    both use, so there is one path into a ruling and one shape of record.
    """
    rulings, unproposed = checkpoint.accept_all(payload)
    ruled = review.apply_rulings(payload, rulings)
    review.write(log_dir / "review.json", ruled)

    print(f"  --accept-all: took {len(rulings)} proposal(s) as ruled. NO HUMAN RULED "
          f"THESE -- the .tres header and {log_dir / 'review.json'} both say so.")
    for field, value in rulings.items():
        print(f"    {field} = {value!r}")
    if unproposed:
        print(f"  {len(unproposed)} field(s) had no proposal to accept: "
              f"{', '.join(unproposed)}")
        print(f"  Rule them in {log_dir / 'review.json'}, then: "
              f"python3 scripts/asset_pipeline.py --resume {run_id}")
        return 0
    return resume(run_id, repo)


def _tres_header(display: str, run_id: str, payload: dict,
                 auto_accepted: bool) -> str:
    """The comment block at the top of the generated .tres.

    Its last line is a PROVENANCE CLAIM, and someone reading this file later to find out
    where a number came from will believe it. "Ruled by the human" is true of a
    checkpointed run and false of an --accept-all one, so the two runs say different
    things.
    """
    provenance = (
        "; The values below were NOT ruled by a human: this run used --accept-all, so "
        "every one is\n; the pipeline's own proposal. See the run's review.json for each "
        "field's sourcing and\n; confidence before trusting any of them.\n"
        if auto_accepted else
        "; Every value below was ruled by the human at this run's checkpoint.\n")
    return (f"; {display} — generated by scripts/asset_pipeline.py run {run_id}\n"
            f"; Source: {payload['asset']}\n"
            f"; Format: {payload['resolved_format']['chosen']} "
            f"({payload['resolved_format']['reason']})\n"
            + provenance)


def _read_or_empty(path: Path) -> str:
    return path.read_text() if path.is_file() else ""


def _entry_is_new(project: Path, asset: Path, license_id: str) -> bool:
    """Whether stage 9 will AUTHOR an attribution entry rather than extend one.

    False for a licence stage 9 refuses to automate: that run halts at stage 9 with no
    entry written, so asking the operator to bump a count nothing will change would be
    a question with no consequence.
    """
    if license_id not in attribution.AUTOMATABLE_LICENCES:
        return False
    try:
        return attribution.find_entry(
            project, "Quaternius", formats.pack_root(asset).name) is None
    except attribution.AmbiguousEntry:
        # Stage 9 halts on this rather than crediting a guess; nothing gets added.
        return False


_RATCHET_PREFIX = "ratchet_"


def _adapter_values(values: dict) -> dict:
    """The ruled fields the adapter's .tres actually has.

    render_tres writes EVERY key it is handed, so a ratchet ruling left in here would emit
    `ratchet_clip_row = "..."` into a resource whose schema declares no such field.
    """
    return {k: v for k, v in values.items() if not k.startswith(_RATCHET_PREFIX)}


def _ratchet_values(values: dict) -> dict:
    return {k: v for k, v in values.items() if k.startswith(_RATCHET_PREFIX)}


def _ratchet_decisions(adapter_name: str, ident: str, clip_row: dict | None,
                       entry_is_new: bool, already_pinned: bool) -> list[review.Decision]:
    """The roster ratchets that apply to THIS run, as checkpoint fields.

    Offered only when they would actually fire -- a pack that already has an entry needs
    no source ruling, a species already in EXPECTED_CLIPS needs no row -- so the
    checkpoint never asks a question whose answer changes nothing. Confidence is
    "measured", not an LLM's: the clip names come from AnimalClips running against the
    model this run just imported.
    """
    out: list[review.Decision] = []
    if entry_is_new:
        out.append(review.Decision(
            field=ratchets.NEW_SOURCE_FIELD, proposal=True,
            source=(f"{ratchets.ATTRIBUTION_TEST} pins the number of attribution sources "
                    f"on disk so that adding one is a decision, not a side effect. This "
                    f"run creates an entry; yes updates that count, no leaves the guard "
                    f"to fail at stage 10"),
            confidence="measured", value=None))
    if adapter_name == "animal" and clip_row is not None and not already_pinned:
        out.append(review.Decision(
            field=ratchets.CLIP_ROW_FIELD, proposal=ratchets.row_literal(clip_row),
            source=(f"{ratchets.WANDER_TEST} pins every roster species' exact clip names; "
                    f"`{ident}` is new, so the table must gain a row or the suite refuses "
                    f"to run. Prefilled with what AnimalClips resolved on the imported "
                    f"model -- edit it to override, or answer empty to leave it unpinned"),
            confidence="measured", value=None))
    return out


def _tracker_rows(payload: dict, run_id: str, tres_rel: str,
                  wrapper_rel: str) -> list[tuple[str, str]]:
    """The rows stage 7 can state as fact, and pending markers for the rest.

    Every other field has its own write-owner (content-pipeline-status.md's rule), so the
    stub claims none of them: stage 8's fact_card_pipeline overwrites
    copy_content_location, and attribution, validation and sign-off stay visibly open.
    """
    evidence = (payload.get("deferred") or [{}])[0].get("evidence", {})
    pack = formats.pack_root(Path(payload["asset"])).name
    licence = evidence.get("license", "unrecorded")
    clips = evidence.get("clips", [])
    today = time.strftime("%Y-%m-%d")
    return [
        ("category_attributes",
         f"proposed by `scripts/asset_pipeline.py` run `{run_id}` and ruled by the human "
         f"at its checkpoint \u2014 per-field sourcing is in the `.tres` header"),
        ("source", f"Quaternius, \"{pack}\" \u2014 {licence} "
                   f"({evidence.get('license_evidence', 'no evidence recorded')})"),
        ("pre_import_audit",
         f"done ({today}) \u2014 {len(clips)} animation clip(s) confirmed"
         + (f" including {', '.join(clips[:4])}" if clips else "")
         + f"; licence cleared as {licence}. Silhouette/style fit DEFERRED \u2014 the "
           f"pipeline does not eyeball art, so it is part of human sign-off"),
        ("project_location", f"`{wrapper_rel}`"),
        ("data_entry_location", f"`{tres_rel}`"),
        ("copy_content_location",
         "pending \u2014 `scripts/fact_card_pipeline.py` owns this row and writes it at "
         "stage 8"),
        ("attribution_status", "pending \u2014 stage 9 records the entry and regenerates "
                               "`project/CREDITS.md`"),
        ("validation_status", "pending \u2014 stage 10 runs the headless suite"),
        ("human_signoff", "not started"),
        ("status", "\U0001f6a7 \u2014 imported by the asset pipeline; copy, attribution, "
                   "validation and sign-off still open"),
    ]


COPY_LOG_DIRS = ("fact_card_pipeline_output", "style_guide_pipeline_output")


def _copy_cost(tree: Path, ident: str) -> dict | None:
    """What stage 8's two GER runs cost, summed from the logs they already write.

    None when neither log carries a cost -- a log written before this existed, or a
    pipeline that never ran. A reporting step must not fail the stage it reports on.
    """
    total = {"in": 0, "out": 0, "usd": 0.0, "usd_known": True}
    found = False
    for dirname in COPY_LOG_DIRS:
        log = tree / "scripts" / dirname / f"{ident}.json"
        if not log.is_file():
            continue
        try:
            cost = json.loads(log.read_text()).get("cost")
        except (json.JSONDecodeError, OSError):
            continue
        if not cost:
            continue
        found = True
        total["in"] += cost.get("in", 0)
        total["out"] += cost.get("out", 0)
        total["usd"] += cost.get("usd", 0.0)
        total["usd_known"] = total["usd_known"] and cost.get("usd_known", True)
    return total if found else None


def _style_guide_report(tree: Path, ident: str, rc: int) -> str:
    """What stage 8's Gentle Displacement run actually did.

    style_guide_pipeline returns 1 when ANY line type escalated -- the GER circuit
    breaker never reached the 10/10 bar, so it kept the highest-scoring draft, WROTE it
    into displacement_copy.gd and marked it AWAITING CONTENT-WRITER SIGN-OFF. That is a
    quality verdict on copy that exists, not a failure to produce copy, and reading it
    as the latter cost a real run an hour of chasing an error that was never raised.
    The per-run log carries the verdict; the return code cannot distinguish the two.
    """
    if rc == 0:
        return "style_guide_pipeline (WARN/DEPART/MOVE)"

    log = tree / "scripts" / "style_guide_pipeline_output" / f"{ident}.json"
    if not log.is_file():
        return (f"style_guide_pipeline FAILED rc={rc} and left no log at "
                f"{log.relative_to(tree)} -- nothing was generated for {ident!r}. Run it "
                f"by hand for the real error: python3 scripts/style_guide_pipeline.py "
                f"{ident} --line-type all")

    results = json.loads(log.read_text()).get("line_results", {})
    escalated = [lt for lt, r in results.items() if r.get("status") == "escalated"]
    if not escalated:
        return (f"style_guide_pipeline rc={rc} with no escalated line in "
                f"{log.relative_to(tree)} -- read it; the failure is elsewhere.")

    scores = ", ".join(f"{lt} {results[lt].get('score', '?')}/10" for lt in escalated)
    return (f"style_guide_pipeline wrote {len(results)} line(s) into "
            f"displacement_copy.gd, {len(escalated)} escalated ({scores}) -- the best "
            f"draft was kept and marked AWAITING CONTENT-WRITER SIGN-OFF, so this is a "
            f"copy-quality verdict for the human, not a failed write. Log: "
            f"{log.relative_to(tree)}")


def _copy_stage(adapter_name: str, tree: Path, display: str, ident: str,
                payload: dict) -> None:
    """The GER copy pipelines, per the design's adapter table.

    fact_card takes a DISPLAY name; style_guide takes a species ID. Both run from the
    WORKTREE's copy (cwd=tree) because they resolve their repo root from __file__ --
    invoking the main checkout's copy would patch the main checkout while this run
    believes it is sandboxed.

    Both were invoked with check=False and a success line printed regardless of outcome.
    Both USED TO carry a hardcoded ROSTER that a newly imported species was by definition
    absent from, so both exited non-zero with "unknown species" -- and the animal run then
    died at stage 10 on AnimalDefinition.validate() rejecting an empty fact_text_pool, with
    nothing connecting that failure back to here. That limitation is gone: the ROSTER is
    now DERIVED from project/data/animals/*.tres (scripts/roster_data.py), which stage 7
    writes before this stage runs, so a new species is in it the moment its .tres exists.
    A non-zero return therefore no longer means "add it to the list" -- it means the copy
    run itself failed -- but it still means NO copy was written and stage 10 will still
    fail, so this reports honestly rather than halting.
    """
    if adapter_name == "terrain":
        # The spec's terrain copy row is "none": terrain has no fact cards and no
        # WARN_/DEPART_/MOVE_ lines. Running fact_card_pipeline here would look for
        # project/data/animals/<id>.tres, which for a terrain type does not exist.
        print("[8/10] copy........ skipped -- the spec's terrain copy row is 'none'")
        return

    cmd = ["python3", "scripts/fact_card_pipeline.py", display, "--count", "2"]
    if adapter_name == "building":
        # Task 13 added --target building_text for exactly the spec's building row.
        # Without it the run patches project/data/animals/<id>.tres instead of
        # project/data/buildings/<id>.tres -- the wrong file, or none at all.
        cmd += ["--target", "building_text"]
    rc = subprocess.run(cmd, cwd=tree, check=False).returncode
    if rc == 0:
        print("[8/10] copy........ fact_card_pipeline (worktree copy)")
    else:
        print(f"[8/10] copy........ FAILED rc={rc} -- fact_card_pipeline wrote NOTHING. "
              f"Its ROSTER is DERIVED from project/data/animals/*.tres, so check stage 7 "
              f"really wrote {ident}.tres, then run it by hand for the real error. Stage "
              f"10 will fail for an animal until {display!r} has copy: "
              f"AnimalDefinition.validate() rejects an empty fact_text_pool.")

    # Gentle Displacement copy is ANIMALS ONLY -- displacement_copy.gd has WARN_/DEPART_/
    # MOVE_ lines per species; buildings and terrain have none. Without this a new animal
    # ships with fact cards but falls through to WARN_GENERIC, which is exactly the gap
    # style_guide_pipeline.py exists to close.
    if payload["adapter"] == "animal":
        rc = subprocess.run(["python3", "scripts/style_guide_pipeline.py", ident,
                             "--line-type", "all"], cwd=tree, check=False).returncode
        print(f"[8/10] copy........ {_style_guide_report(tree, ident, rc)}")

    cost = _copy_cost(tree, ident)
    if cost is not None:
        print(f"[8/10] copy........ cost: {_format_cost_line(cost)}")


def _preserve_license(pack: Path, project: Path, tree: Path) -> None:
    """Keep the pack's licence text in the repo alongside the credit.

    art.md's rule is that a link can rot and a compliance review must be answerable
    offline. attribution.copy_license_text() was implemented and traversal-hardened but
    never called by any stage. An already-present file is left alone: the three licences
    on disk today were curated by hand, and overwriting one would be a silent edit to a
    compliance record.
    """
    filename = attribution.license_filename("Quaternius", pack.name)
    dest = project / "assets" / "licenses" / filename
    if dest.is_file():
        print(f"[9/10] licence..... {filename} already preserved")
        return
    copied = attribution.copy_license_text(pack, project, filename)
    if copied is None:
        print(f"[9/10] licence..... no License.txt in {pack.name!r} -- nothing to preserve "
              f"offline; the entry's license_url stays the only record")
    else:
        print(f"[9/10] licence..... {copied.relative_to(tree)} preserved offline")


def _parser() -> argparse.ArgumentParser:
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
    parser.add_argument("--notes", default="", help="Optional design hint passed to stage 6")
    parser.add_argument("--variant-of", metavar="TERRAIN_ID", default=None,
                        help="Terrain adapter only: append this model as a style variant "
                             "of an existing terrain type (e.g. --variant-of forest) "
                             "instead of writing a new terrain type.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Run every deterministic stage, skip the paid ones, then abandon")
    parser.add_argument("--resume", metavar="RUN_ID", help="Continue a run past its checkpoint")
    parser.add_argument("--abandon", metavar="RUN_ID", help="Destroy a run's worktree and branch")
    parser.add_argument("--no-interactive", dest="interactive", action="store_false",
                        help="Halt at review.json instead of prompting for rulings")
    parser.add_argument("--accept-all", action="store_true",
                        help="Take every proposal as the ruling without prompting, then "
                             "continue. The .tres header records that no human ruled them")
    return parser


def main() -> int:
    args = _parser().parse_args()

    if args.selftest:
        return selftest()
    if args.resume:
        if args.accept_all:
            # Same flag, same meaning, for a run already halted at its checkpoint.
            log_dir = Path.cwd() / "runs" / args.resume
            payload = review.read(log_dir / "review.json")
            payload["auto_accepted"] = True
            return _accept_all_checkpoint(args.resume, Path.cwd(), log_dir, payload)
        return resume(args.resume, Path.cwd())
    if args.abandon:
        return abandon_run(args.abandon, Path.cwd())
    if not args.asset:
        _parser().error("an asset path is required (or --selftest)")
    if not args.adapter:
        _parser().error("--as {animal|building|terrain} is required")
    if args.variant_of and args.adapter != "terrain":
        _parser().error("--variant-of applies only to --as terrain")
    return run(Path(args.asset), args.adapter, Path.cwd(), args.notes or "",
               args.dry_run, args.variant_of, args.interactive, args.accept_all)


if __name__ == "__main__":
    raise SystemExit(main())
