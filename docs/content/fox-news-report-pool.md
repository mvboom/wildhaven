# Fox — News Report copy pool

**Status: written and checklist-passed, but HOMELESS.** `AnimalDefinition` has no field for
News Report copy (gdd.md describes a per-animal text pool "reusing the fact-card pipeline",
but no schema row exists). This file exists so pilot 3's step-5 output is not lost. Move it
into data once the schema gains a field — see "GDD gaps" in `costs.md`.

Produced by `content-writer` during the pilot-3 Add-a-Fox pipeline run, 2026-07-20.

## Sourcing status — read before shipping any of this

The **fact card** was verified against sources and now ships in
`project/data/animals/fox.tres`. **The lines below were NOT part of that verification pass**
— they were drafted while the container firewall blocked every approved wildlife source.

Tone and predation checks passed. Factual claims did not get checked. Two lines below draw on
claims that later verification found problematic in the fact card, and are flagged inline.

Sources are now reachable (see gdd.md → Fact-card content pipeline). Verify before use.

## Sub-pools

These fire at different moments and must not be drawn interchangeably — that structure is
part of what the eventual schema field needs to support.

### Discovery / hint — fires pre-move-in, soft-hints `forest` + `cover`

- "Word has it a fox is looking for a new home — somewhere with plenty of trees and quiet places to tuck into…"
- "A fox has been seen at the edge of the woods, looking around like someone reading a map. It seems to want thick cover and tall trees."
- "Rumor from the treetops: a fox family would like a shady stretch of forest with lots of leafy corners to curl up in…"

### Move-in announcement

- "A fox has moved into the forest! Keep an eye on the shady spots — foxes like to stay under cover."
- "Good news from the woods: a fox family has settled in and made a den among the trees."

### Ambient / flavor — also usable as welcome-back lines

- "Someone heard a funny chattering sound coming from the trees last night."
- "The fox kits were out tumbling in the leaves all morning." ⚠️ **Suspect** — verification found fox activity is nocturnal/crepuscular across all sources, and kit play is undocumented. "All morning" repeats the exact error corrected in the fact card. Rewrite toward dusk or drop.
- "A fox was spotted curled up in a sunbeam with its tail draped over its nose like a blanket."
- "Both fox parents have been busy around the den today." ✅ Consistent with verified sources (ADW, Nat Geo Kids: both parents care for young).
- "A fox stood very still at dawn with its ears turned forward, listening to the whole forest at once."
- "The fox has been napping in the ferns where the light comes through green."
- "Whoever saw the fox today says its coat has a color all its own." — pairs with the per-individual `variation_seed` coat tint; reads correctly before *and* after that lands.

### Avoidance relocation — announced after the fact, no terraform warning

Written to match the register of gdd.md's existing example ("found a quieter corner of the meadow"). **Both are symmetric or single-subject by design** — see the symmetry rule in gdd.md → Compatibility.

- "The fox found a quieter corner of the woods, with a little more room to itself."
- "The fox family moved their den deeper into the trees, where there's more space to spread out."

### Symmetric avoids framing

Supplied as replacements for the asymmetric sample line in gdd.md. **The GDD line has since been corrected**; these remain available as in-game strings.

- "Foxes and rabbits each like plenty of space of their own."
- "Foxes and rabbits both do best with a good stretch of room between them."

## Known gaps

- **Pool size is a guess.** Six ambient lines will repeat quickly if ambient News fires
  often. The fire rate was unknown at drafting time; size the pool once it is set.
- ~~**No rabbit-side relocation line.**~~ **CLOSED** — Rabbit cleared its audit in pilot 3b
  and `rabbit-news-report-pool.md` supplies two relocation lines that mirror the fox's
  one-for-one, so whichever party relocates the announcement reads identically in shape.
- **Banned-vocabulary note for future editors:** the evidence that both fox parents help
  raise the kits is *food provisioning by the male* — which is banned vocabulary. Copy can
  rest on the conclusion ("both parents help") but can never show its work.
