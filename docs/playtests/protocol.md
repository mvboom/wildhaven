# Playtest Protocol

> **Human-run. There is no agent for this.** `qa-engineer` explicitly excludes playtesting
> and playability judgment — camera feel, tap-model learnability, fun — and that boundary
> stays: agents verify mechanics, never experience. This document exists so the step-5
> checkpoint has a repeatable shape, not so it can be delegated.
>
> Referenced by [gdd.md](../../game-design/gdd.md) → **Milestones** (early playtest
> checkpoint, end of step 5) and → **Scope** (the complete-loop test). Results feed the
> week 2–3 velocity review, which decides what gets deepened.

## Who and when

**Testers:** actual kids in the target range (6–10). v1's practical target is fluent
readers 8–10, so record the tester's age and reading fluency — a stall in a 7-year-old and
a stall in a 10-year-old mean different things.

**When:** first at the end of Phase 5, the first point the loop is playable end to end
(terrain → a move-in → a surviving save). Not only at the end — camera feel and tap
learnability are worth catching while there is still budget to act on them.

**Session length:** ~20 minutes, unassisted. If they stop early, that is data.

## The pass/fail bar

The **complete-loop test** from gdd.md, verbatim: a stranger must be able to experience the
entire core loop in one sitting, stop, and come back —

> start a new game → terraform → gather resources → build → an animal genuinely moves in →
> learn something real → the world grows at the mist → quit → load, world intact.

**Unaided** is the operative word. Any beat that needs an adult to explain it is a failure
of that beat, not of the tester.

**Explicitly out of scope for v1:** session-two retention — whether they *want* to come
back tomorrow. That was ruled outside v1's definition of done during the GDD restructure.
Note it if you see it; do not grade on it.

## The observation script

Run the six beats of gdd.md's **First 60 Seconds** as a checklist. For each: did it happen,
how long did it take, and did the tester need help?

| # | Beat | Target | Watch for |
|---|---|---|---|
| 1 | New Game → name → in | 0:00 | Do they understand they are in the world? Any hunt for a menu? |
| 2 | First News Report fires | ~0:03 | Read or ignored? Does the nudge point at terrain the shipped roster actually reads? |
| 3 | First tap teaches the model | ~0:10 | **The critical beat.** Do they learn "pick a mode, then tap" from one tap, with no tutorial? |
| 4 | Cause becomes visible | ~0:20 | Does the qualitative preview mean anything to them, or is it noise? |
| 5 | Stockpile invites a build | ~0:40 | Do they spend without being told to? |
| 6 | **The payoff — first move-in** | ≤2:00 from first paint, **hard ceiling 5:00** | Fact card fires. Time this one precisely — it is a spec commitment, not a hope. |

### The question that matters most

**Did they connect terraforming to the move-in without being told?**

That causal link is the game's entire premise — the inverted builder win condition. If a
tester enjoys the session but cannot say *why* the animal came, the game is pretty and the
design has not landed. Ask afterward, in their words: *"How did that rabbit get there?"*

### Also record

- **Where they hesitated**, and for how long. Hesitation is more useful than failure — it
  shows where the model is unclear while it is still recoverable.
- **What they tried that doesn't exist.** Attempts at un-built affordances are the cheapest
  feature research available.
- **Anything that startled or upset them.** Pillar 1 and 2 are absolute; a single instance
  is a finding, not a data point to average away.
- **The quit → reload moment.** Did the world come back the way they left it? Did they
  notice or care?

## What a failure buys

gdd.md already names the pressure valve, and it is deliberately narrow: if kids stall
before the first move-in, the fix is **content** (a more directive nudge, a lower-requirement
starter species) or **the arrival-delay constant** — **never a forced tutorial**. A tutorial
gate would break Pillar 3.

Anything else a playtest surfaces is a depth purchase, priced at the velocity review against
[tier1-status.md](../../game-design/tier1-status.md)'s hours ledger.

## Recording results

One file per session: `docs/playtests/<YYYY-MM-DD>-<tester>.md`.

```markdown
# Playtest — <date>

**Tester:** age, reading fluency, prior exposure to the game (first session? nth?)
**Build:** commit or tier1-status snapshot
**Duration:** actual, and whether they stopped early

## The six beats
<per beat: happened y/n, time, help needed y/n, notes>

## Complete-loop test
<pass/fail per stage: new game / terraform / gather / build / move-in / learn / mist / quit-reload>

## "How did that rabbit get there?"
<their words, verbatim>

## Hesitations
## Attempts at things that don't exist
## Anything that startled or upset them
## My read
<what I think this means — kept separate from what was observed>
```

Keeping observation and interpretation in separate sections is the whole discipline here.
The observations stay true when the interpretation turns out wrong.
