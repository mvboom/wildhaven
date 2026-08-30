# Cleared Pool — Fact-Card copy (Deer, Stag, Horse, Donkey, Cow, Bull, Alpaca, Husky, Shiba Inu)

**Status: PROPOSED — awaiting step 3/4 design lock and step 8 human sign-off, and HOMELESS
in the same way as `fox-news-report-pool.md`, `rabbit-news-report-pool.md`, and
`displacement-copy.md`.** None of these nine species has a `roster.md` row, a step-3 design
proposal, or an `AnimalDefinition` `.tres` yet (`content-pipeline-status.md` → Roster: all
nine `data_entry_location` = "not started"). This file is **step 5 (Copy) run ahead of
steps 3/4** because the human asked for the cheapest available depth to be prepared while
the design proposal is pending — the same "batch by step, not by item" logic
`content-pipeline-status.md` already applies to this pool. **Do not transcribe any line
below into a `.tres` until roster.md carries a decided row for that species** (habitat
needs, personality, farm-tolerance — none of which is this document's call).

Produced by `content-writer`, 2026-08-06, against spec.md → **Fact-Card Content Checklist**
and the stricter reading of it in this dispatch's brief (no diet, hunting, or
predator/prey mention **even obliquely** — stricter than "never as threat" alone). Every
source below was fetched live during this pass (see each species' **Retrieval trace**); no
claim is drafted from memory.

## Graph check — run once, for all nine

**No cleared-pool species carries a proposed `avoids` entry.** Checked against
`roster.md` → "The cleared pool" (*"Each needs a step-3 proposal (habitat needs,
personality, **avoids**, farm-tolerance) and a human decision before it gets a row above —
nothing here is decided"*) and `art.md` → "Newly Available Animals" (the suggested-needs
column lists no avoids for any of the nine; Husky/Shiba Inu are named only as *"the natural
candidate for row 9's second avoids pair,"* a proposal, not a value). **The pairwise
symmetry requirement (gdd.md/roster.md → Compatibility) therefore does not apply to any
line in this file — skipped explicitly, not silently.** If a future step-3 proposal adds an
avoids entry to any of these nine (Husky ↔ Shiba Inu is the likeliest), this file's lines
still pass on their own (none names another species, a diet, or a threat), but the new pair
will need its own symmetric avoids-framing line, the way `fox-news-report-pool.md` and
`rabbit-news-report-pool.md` supply one for Rabbit ↔ Fox — not written here, since it isn't
needed yet.

## Register check — baby-animal terms, run against the whole roster

D-19's lesson (read shipped copy, not just sources): "kits" is Fox's, "baby rabbits" is
Rabbit's. Baby-animal terms used below and checked against both:

| Species | Term used | Collision? |
|---|---|---|
| Deer | fawn | none — not used elsewhere on the roster |
| Stag | (none — card is about an adult trait) | n/a |
| Horse | foal | none |
| Donkey | (none — card is about a sound, not a baby) | n/a |
| Cow | (none — card is about adult coat pattern) | n/a |
| Bull | (none — card is about an adult working trait) | n/a |
| Alpaca | cria | none |
| Husky | (none — card is about a bred trait) | n/a |
| Shiba Inu | — no card shipped, see below | n/a |

No collisions found. US English throughout (no UK spellings carried into shipped copy,
even though two sources quoted below are UK sites and use UK spelling/units in their own
sentences — quoted verbatim in the citation, never in the `fact_text` itself).

---

## Deer

**Species choice, documented the way rabbit.tres documents its species choice:** the
imported model is a generic "Deer," with no species pinned by art.md. I picked the
**white-tailed deer (*Odocoileus virginianus*)** over red deer, specifically so Deer and
Stag do not source the same real animal under two roster entries — Stag below is sourced
against red deer (*Cervus elaphus*), the species Wildlife Trusts' page and the word "stag"
itself point to.

**Proposed `fact_text`:**
> "A deer fawn is born with a soft, spotted coat, and by its first winter the white spots
> are gone and its coat has turned a grayish brown."

**Retrieval trace**
- Source fetched: `https://animaldiversity.org/accounts/Odocoileus_virginianus/`
- Query/section looked at: "Physical Description" section, fawn coloration and molt.
- Exact quoted chunk retrieved: *"At birth, fawns are spotted with white in coloration
  and weight between 1.5 and 2.5 kg. Their coats become grayish lose their spots by their
  first winter."* (The source's own sentence has a grammatical gap — "grayish lose" —
  reproduced here exactly as scraped from the live page, not cleaned up; the meaning read
  is "become grayish **and** lose their spots.")
- Exact output line produced: the `fact_text` above. Original words throughout — no
  phrase copied from the source sentence.

**Checklist**
1. Source — PASS. Animal Diversity Web, approved.
2. Length/tone — PASS. One sentence, plain vocabulary, warm, no drama.
3. Tone (worldbuilding) — PASS. Gentle, descriptive, no snark, no fear.
4. Predation — PASS. **A companion sentence in the same ADW paragraph was cut, not
   laundered:** *"Fawns withhold their feces and urine until the mother arrives, at which
   point she ingests whatever the fawn voids to deny predators any sign of the fawn."* This
   is exactly rabbit-news-report-pool.md's "cut during drafting" standard — real behavior,
   entirely predation-framed, no safe rewrite exists that doesn't launder a threat out of
   it. Also cut: the ADW herd/grazing sentence ("does have been observed to graze
   together in herds") — this dispatch's brief bans **diet** mention even obliquely, and
   "graze" is a diet word.
5. Graph — N/A, no avoids entry (see above).

---

## Stag

**Species choice:** red deer (*Cervus elaphus*) — "stag" is specifically the term for an
adult male red deer (also used more loosely for other deer species, but red deer is the
species Wildlife Trusts names outright), which also matches art.md's "trophy" framing for
this entry.

**Proposed `fact_text`:**
> "A stag is a male red deer, and every year it grows a brand-new set of branching antlers
> that are bigger than the year before."

**Retrieval trace**
- Source 1 fetched: `https://animaldiversity.org/accounts/Cervus_elaphus/`
  - Query/section: antler size and who grows them.
  - Exact quoted chunk: *"widely branching antlers as long as 1.1 to 1.5 m from tip to tip
    are found on males only"*
- Source 2 fetched: `https://www.wildlifetrusts.org/wildlife-explorer/mammals/red-deer`
  - Query/section: the species profile page (male/female naming, antler growth cycle).
  - Exact quoted chunks:
    - *"A male red deer is called a 'stag', a female is called a 'hind'."*
    - *"Males have large, branching antlers, increasing in size as they get older."*
    - *"Within a few weeks of shedding old antlers, new ones will start to grow."*
- Exact output line produced: the `fact_text` above — "male red deer" and "every year…
  bigger than the year before" are original wording built from the four quotes, not
  copied phrasing.

**Checklist**
1. Source — PASS. ADW + The Wildlife Trusts, both approved.
2. Length/tone — PASS. One sentence, concrete, upbeat ("brand-new," "bigger than the year
   before" reads as growth, not competition).
3. Tone — PASS.
4. Predation — PASS, **and one clause was deliberately cut**: the same Wildlife Trusts
   page states antlers are grown and used *"During the autumnal breeding season, known as
   the 'rut,' males bellow to proclaim their territory and will fight over the
   females, sometimes injuring each other with their sharp antlers."* That is combat
   framing (gdd.md's ban covers combat, not only predation) and stays out entirely — the
   card keeps only the growth fact (antlers get bigger with age, regrow after shedding)
   and drops every word about why stags grow them or what they do with them.
5. Graph — N/A.

---

## Horse

**Proposed `fact_text`:**
> "A newborn foal can already stand up on its own in about an hour, and it can walk just a
> few hours after that."

**Retrieval trace**
- Source fetched: `https://animaldiversity.org/accounts/Equus_caballus/`
- Query/section: foal development ("Reproduction" / "Development" section).
- Exact quoted chunk retrieved: *"Foals are born precocial and well-developed, usually
  being able to stand within an hour of birth and walk within four to five hours"*
- Exact output line produced: the `fact_text` above.
- **Note on a second source checked and rejected:** `kids.nationalgeographic.com` has no
  domestic-horse page (`facts/horse` returns 404); its one live equine page is
  *Przewalski's horse* (*Equus ferus przewalskii*), a different species from the domestic
  horse this entry is meant to represent, so it was not used. Recorded so nobody re-runs
  this search expecting a Nat Geo Kids domestic-horse page to exist.

**Checklist**
1. Source — PASS. ADW, approved.
2. Length/tone — PASS. Two short sentences (could read as one with "and"), plain
   vocabulary, an achievement framing kids like ("already," "on its own").
3. Tone — PASS.
4. Predation — PASS. No mention of why standing quickly matters in the wild (every source
   ties it to keeping up with a herd against threats); the card states only the milestone
   itself.
5. Graph — N/A.

---

## Donkey

**Proposed `fact_text`:**
> "A donkey's 'hee-haw' call is so loud, it can be heard from almost two miles away."

**Retrieval trace**
- Source fetched: `https://animaldiversity.org/accounts/Equus_asinus/`
- Query/section: vocalization / communication section.
- Exact quoted chunk retrieved: *"Donkeys use a "hee-haw" sound that can travel up to 3 km
  away."*
- Exact output line produced: the `fact_text` above — **3 km converted to "almost two
  miles"** for a US-register card (3 km ≈ 1.86 mi); the underlying fact is unchanged, only
  the unit.

**Checklist**
1. Source — PASS. ADW, approved.
2. Length/tone — PASS. One sentence, concrete, fun ("so loud" is upbeat, not scary).
3. Tone — PASS.
4. Predation — PASS. No predation angle exists in this fact at all.
5. Graph — N/A.

---

## Cow

**CORRECTED by the consistency-check pass (2026-08-06) — see note below the checklist.**

**Proposed `fact_text`:**
> "A cow's short coat can come in many colors — black, white, reddish brown, or brown —
> so no two cows have to match."

**Retrieval trace**
- Source fetched: `https://animaldiversity.org/accounts/Bos_taurus/`
- Query/section: "Physical Description," coat color.
- Exact quoted chunk retrieved: *"The body is covered in short hair, the color of which
  varies from black through white, reddish brown, and brown."*
- Exact output line produced: the `fact_text` above — original wording built from the
  quote's color list, not copied phrasing.

**Checklist**
1. Source — PASS. ADW, approved.
2. Length/tone — PASS. One sentence, concrete, warm.
3. Tone — PASS.
4. Predation — PASS. No diet, no predation, nothing about "cattle" as a category beyond
   appearance.
5. Graph — N/A.

**Why this replaced the original "Holstein black-and-white spots" line:** the original
draft's own Proposal #4 (below) flagged that the claim was "strongest if the imported/
eventual model actually reads as black-and-white patterned" and recommended a one-line
check against the actual asset — a check the original draft did not run. Running it now:
`project/assets/animals/cow/Cow.gltf`'s materials are `Main`
(`baseColorFactor` ≈ [0.24, 0.11, 0.03, 1]), `Main_Light` (≈ [0.48, 0.40, 0.29, 1]),
`Muzzle` (≈ [0.43, 0.18, 0.08, 1]), and `Horns` (≈ [0.41, 0.36, 0.18, 1]) — all warm
brown/tan values (R > G > B throughout in every one), plus `Hooves` and
`Eye_Black`/`Eye_White`, the small parts every animal in this pack has. **There is no
black material and no white body material anywhere in the mesh, and no spot/pattern
texture — the model is a solid brown/tan cow**, not a black-and-white Holstein. The
original line's central visual claim ("black-and-white spots… like a fingerprint or a
snowflake") is a real, well-sourced fact about Holstein cattle specifically, but it does
not describe the animal this card sits on top of in-game — the exact visual-claim-vs-
actual-asset break the checklist's "concrete" requirement exists to prevent. A six-year-
old tapping a plain brown cow and reading "black-and-white spots" is a broken card, not
a subtle one. The replacement line above uses the same ADW page's general coat-color
sentence instead, which is true of the actual brown/tan model (brown is one of the four
colors the source names) and makes no pattern claim the mesh would need a texture to
support.

---

## Bull

**Distinctness note (the mesh-recolor risk):** Cow and Bull share Cow's base mesh in the
imported asset (`content-pipeline-status.md` → `bull`: *"Bull's mesh is the same base
mesh as Cow… may read as a recolor rather than a distinct silhouette"*). This card is
deliberately about a **different aspect of the real animal** than Cow's card (a working
trait, not an appearance trait), so the two cards cannot read as the same fact with the
species name swapped even where the model itself might.

**Proposed `fact_text`:**
> "Bulls are big and strong, and for thousands of years people have used them to help pull
> heavy loads and plows."

**Retrieval trace**
- Source fetched: `https://animaldiversity.org/accounts/Bos_taurus/`
- Query/section: "Physical Description," working-animal use.
- Exact quoted chunk retrieved: *"They can be used as working animals for plowing and
  moving heavy loads."*
- Exact output line produced: the `fact_text` above.

**Checklist**
1. Source — **PASS, but flagged as thin.** The ADW sentence is about *Bos taurus*
   generally, not gendered to bulls specifically — historically, working cattle were
   overwhelmingly male (oxen), which is the real-world basis for attributing the trait to
   "Bulls" here, but the source itself does not say "bulls." **I looked for a
   bull-specific alternative and could not clear one:** ADW's only explicit sex-linked
   trait for this species is the one-word tag "male larger" under Sexual Dimorphism, with
   no supporting sentence or number, which is too thin to write a sentence from without
   inventing detail the source doesn't supply. Nat Geo Kids has no cow/cattle page at all
   (`facts/cow` → 404). The Wildlife Trusts does mention cattle (conservation grazing,
   e.g. a Luing bull named "Casanova" on one Trust's blog), but that content is about the
   game-adjacent real-world practice of using cattle for habitat management, not a
   transferable child-fact about bulls, and the one bull-named example lives on a
   `/blog/` path, which the checklist excludes ("no blog scraping"). **Recommend the human
   treat this line as provisional** and revisit if a better-sourced, more distinctly
   "bull" fact turns up later — flagged rather than shipped confidently.
2. Length/tone — PASS. One sentence, plain vocabulary, upbeat (a "helper" framing, not a
   power/dominance framing).
3. Tone — PASS.
4. Predation — PASS, **and one clause was cut for a stricter reason than predation: it is
   combat-adjacent.** The same ADW page states: *"Dominant males maintain this status
   until defeated by younger males in challenges."* This is a real, sourced, otherwise
   "safe" (non-predation) behavior, but "defeated… in challenges" reads as combat, which
   gdd.md's ban covers explicitly alongside predation (*"No predation, combat, death, or
   danger — simulated or implied"*). Cut outright, not softened.
5. Graph — N/A.

---

## Alpaca

**Proposed `fact_text`:**
> "Baby alpacas are called crias, and grown alpacas hum to each other — especially when
> something around them changes."

**Retrieval trace**
- Source fetched: `https://animaldiversity.org/accounts/Lama_pacos/`
- Query/section: "Reproduction" (terminology) and "Communication and Perception"
  (vocalization).
- Exact quoted chunks retrieved:
  - *"Crias is the term used to designate alpaca offspring up to 6 months of age."*
  - *"The most common is the humming vocalization, which is produced under a variety of
    circumstances, such as distress or a change in the environment."*
- Exact output line produced: the `fact_text` above.
- **Note on a trimmed source clause:** the humming quote's own text pairs "distress" with
  "a change in the environment" as two examples of when alpacas hum. The card keeps only
  "a change in the environment" and drops "distress" entirely — the fear-word is not
  needed to make the sentence true (humming *is* triggered by environmental change on its
  own, per the source), and keeping it would be the same predation-with-the-fear-word-left-in
  trap the checklist names for Rabbit's cover framing, just for an emotional state instead
  of a physical threat.

**Checklist**
1. Source — PASS. ADW, approved.
2. Length/tone — PASS. One sentence (two clauses), concrete, warm, teaches a real word
   ("cria").
3. Tone — PASS.
4. Predation/fear — PASS after the "distress" trim described above.
5. Graph — N/A.

---

## Husky

**Proposed `fact_text`:**
> "Huskies were bred to be strong pullers — people used them to help pull heavy loads and
> sleds."

**Retrieval trace**
- Source fetched: `https://animaldiversity.org/accounts/Canis_lupus_familiaris/`
- Query/section: "Behavior," selective breeding for working roles.
- Exact quoted chunk retrieved (full sentence, husky-relevant clause in context):
  *"They have been selectively bred for millenia for various behaviors, sensory
  capabilities, and physical attributes, including dogs bred for herding livestock
  (collies, sheperds, etc.), different kinds of hunting (pointers, hounds, etc.), catching
  rats (small terriers), guarding (mastiffs, chows), helping fishermen with nets
  (Newfoundlands, poodles), **pulling loads (huskies, St. Bernard's)**, guarding carriages
  and horsemen (dalmatians), and as companion dogs."*
- Exact output line produced: the `fact_text` above, built only from the bolded clause.
- **Banned-vocabulary note for future editors, matching the format fox.tres and human.tres
  use for the same situation:** this single ADW sentence is a list, and other items in the
  same list name banned words directly — "hunting," "catching rats" (a predation-adjacent
  frame even if the target is vermin, not wildlife), "guarding." The card rests on the
  "pulling loads (huskies…)" clause alone and never shows the rest of the sentence's work.
  Do not extend this citation to imply ADW singles out huskies for anything beyond
  pulling loads — it does not.

**Checklist**
1. Source — PASS. ADW, approved. (No breed-specific approved source exists for Husky
   beyond this general-dog-species clause — see the retrieval notes for what was checked
   and came up empty, in the Shiba Inu section below, since the same search covered both.)
2. Length/tone — PASS. One sentence, plain vocabulary, upbeat ("strong," "helped" — a
   partnership frame).
3. Tone — PASS.
4. Predation — PASS. The sentence this is drawn from names "hunting" for other breeds in
   the same list; that clause is excluded entirely, per the banned-vocabulary note above.
5. Graph — N/A. (Husky ↔ Shiba Inu is named in roster.md as the *candidate* for a future
   avoids pair, but carries no `avoids` value yet — nothing to symmetry-check today.)

---

## Shiba Inu — UNDER-SOURCED, no `fact_text` proposed

**No line is proposed for Shiba Inu.** I could not clear step 1 (approved source) for any
Shiba-Inu-specific, non-predation fact, and the brief's standard is to flag this rather
than fabricate or ship a weak substitute dressed up as equivalent to the other eight.

**What was checked and came up empty:**
- `kids.nationalgeographic.com/animals/mammals/facts/shiba-inu` and
  `/siberian-husky` → both 404. Nat Geo Kids has no breed-specific dog pages for either of
  this pool's two dogs (recorded so nobody re-runs this exact search).
- `animaldiversity.org` has one general domestic-dog account
  (`Canis_lupus_familiaris`) which supplied Husky's card via a clause naming huskies
  directly. **The same account never mentions Shiba Inu by name anywhere**, and using the
  same general sentence for Shiba Inu (rather than Husky) would be exactly the "generic
  copy with the species name swapped" failure mode this dispatch's brief calls out for
  Cow/Bull — worse here, since the source doesn't even name the breed.
- `education.nationalgeographic.org` — searched for dog-domestication/breed content; what
  turned up (a 2015–2016 domestication-genetics article, a general "domesticated animals"
  explainer) lives on `nationalgeographic.com`, not the `education.` subdomain the
  checklist approves, and none of it is breed-specific to Shiba Inu.
- A widely repeated claim ("National Geographic found Shiba Inus are the dog breed most
  genetically similar to wolves") surfaces on several secondary/blog sites but **traces to
  no page on either approved National Geographic domain** that I could locate — it is not
  used here, and should not be, until someone finds the primary source it claims to be
  quoting, if it exists at all.

**Recommendation:** leave Shiba Inu's `fact_text` unwritten rather than ship a generic
"dogs come in many breeds" line dressed as a Shiba Inu fact. If/when this species reaches
step 5 for real, worth a wider source search (a Nat Geo Kids "dog breeds" roundup article,
if one exists and covers it, or a properly-scoped Nat Geo Society Education resource) — not
attempted exhaustively here because this file's job was breadth across nine species, not
an unbounded search for one.

---

## Proposals for the human

1. **Land the schema gap first.** All nine lines above (eight written, one flagged) are
   homeless in exactly the way `fox-news-report-pool.md`, `rabbit-news-report-pool.md`, and
   `displacement-copy.md` already are — `AnimalDefinition` has no field yet for any of
   this, and none of these nine species even has a `roster.md` row. This is now the
   **fourth** body of verified/checklist-passed copy waiting on the same fix. Verification
   is measured at ~2.7× drafting cost (pilot 3) — the more of this accumulates unlanded,
   the larger the loss if a schema gap ever causes any of it to be redone from scratch
   rather than transcribed.
2. **Bull's line is provisional, not a rejection — flagged above.** If the human or a
   future design pass turns up a genuinely bull-specific approved-source fact, prefer it
   over the working-animal line shipped here.
3. **Shiba Inu needs either a wider source search or a design decision to accept a weaker
   card than its roster-mates.** I did not manufacture a line to make the count "9 of 9" —
   see the section above for exactly what was checked.
4. **RESOLVED by the 2026-08-06 consistency-check pass.** The original Cow card named the
   Holstein breed's black-and-white spots and flagged itself here as needing a check
   against the actual asset. That check has now been run: `Cow.gltf`'s materials are all
   brown/tan (no black, no white body material, no pattern texture), so the original line
   was a real visual-claim-vs-asset mismatch, not just an open risk. The `fact_text` above
   has been rewritten to ADW's general coat-color sentence, which the actual brown/tan
   model supports. **No further action needed on this item** — recorded so nobody
   re-opens it believing it's still pending.