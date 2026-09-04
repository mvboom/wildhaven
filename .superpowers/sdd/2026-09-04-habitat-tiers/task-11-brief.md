### Task 11: Full-suite verification and the documentation fold-back list

**Files:**
- Test: no new files
- Report only

**Interfaces:** consumes everything.

This task produces no code. It produces the evidence that the work is done and the list of design-doc edits the human needs to make.

- [ ] **Step 1: Run the entire suite**

Run: `bash scripts/run-tests.sh`
Expected: every suite PASS, exit 0.

If anything fails, fix the cause — never the assertion — and re-run. Do not report completion on a red suite.

- [ ] **Step 2: Verify the two invariants that no single task owns**

Run: `bash scripts/run-tests.sh new_terrains`
Confirm in the output: `wild grass still emits nothing — the inert-land invariant holds`.

Run: `bash scripts/run-tests.sh roster_signatures`
Confirm in the output: `the shipped dependency graph is acyclic` and sixteen distinct-signature PASS lines.

- [ ] **Step 3: Verify Gentle Displacement survives tiers**

Spec § 11 states two consequences no single task owns. Check both:

Run: `bash scripts/run-tests.sh gentle_displacement`
Expected: PASS. Tiers change what `capacity()` returns, and the displacement trigger reads
`capacity(h, S) < population(h, S)` — so this suite is the regression gate on the whole
formula rewrite, not just on displacement.

Then report these two as **human playtest items**, since neither is headless-checkable:
- **A tier fall is a thinning, not a vanishing.** Dropping from a herd tier to a pair tier
  should warn once and remove the surplus, not evict the site. Copy should read like
  *"the herd will thin to a pair — the rest will find a wider field."*
- **Two-level cascades coalesce into ONE warning.** `deer → stag` and
  `human → people → dogs` both mean a single settled gesture can displace two species.
  The settlement rule should summarise them together; a chain of separate popups would
  break the "one warning per settled gesture" rule the GDD states.

- [ ] **Step 4: Capture the numbers the human asked to watch**

Report, from the suite output:
- total suites run and total assertions passed
- the roster's widest per-need radius actually used (grep the `.tres` files for `radius = `) — this is the performance budget the human ruled at 16

- [ ] **Step 5: Write the documentation fold-back list**

The design docs are still stale. Produce a list, for the human, of exactly which files need which edits — do **not** edit them, since `decisions.md` entries and GDD changes are the human's:

- `game-design/gdd.md` → Habitat Suitability: the capacity formula is now max-over-tiers; `quiet` left the vocabulary; residents emit tags
- `game-design/roster.md` → the Already-Defined Roster table is superseded by spec § 9; sixteen species, not fourteen (`pig`, `sheep`, `pug` were already shipped but untabled)
- `game-design/terrain.md` → three new terrains; the tag-source mapping table
- `game-design/buildings.md` → nine buildings now emit tags; Farmhouse is a new placeable; the "House at 2×2 form" line is superseded
- `game-design/spec.md` → Open Questions #5, #7, #20, #23 are all affected; the radius band changed
- `decisions.md` → a new `D-NN` recording the habitat-tiers ruling and the six OQ rulings of 2026-09-04

- [ ] **Step 6: Report**

Report the full-suite result, the two invariant confirmations, the numbers from Step 3, and the fold-back list. Remind the human that **every habitat value in the sixteen species `.tres` files and in `farmhouse.tres` is a proposal awaiting their sign-off**, and that no git command has been run.
