# Wildhaven Species Content Crew — Architecture

```mermaid
flowchart TD
    Brief["Species Brief\n(name, ecology notes, source)"] --> Designer
    Vocab[("Shared habitat tag vocabulary\n+ inert-land invariant")] --> Designer

    Designer["Agent 1: Habitat Designer\nhabitat_needs, personality,\navoids, radii, tiles_per_individual"]

    Designer -->|habitat design JSON| SchemaWriter
    Designer -->|habitat design JSON, context only| ContentWriter
    Brief --> ContentWriter

    SchemaContract[("AnimalDefinition schema contract\n(animal_definition.gd)")] --> SchemaWriter
    Checklist[("GDD fact-card checklist\nsource / length / tone / predation")] --> ContentWriter

    SchemaWriter["Agent 2: Schema Writer\ndraft .tres resource body"]
    ContentWriter["Agent 3: Content Writer\nfact_text + checklist log"]

    SchemaWriter -->|draft .tres fields| Merge["Merge fact_text into .tres body"]
    ContentWriter -->|fact_text + checklist log| Merge

    Merge --> QA
    Roster[("Existing roster ids\ne.g. fox avoids rabbit")] --> QA

    QA["Agent 4: QA Validator\ndeterministic schema check\n(mirrors AnimalDefinition.validate)"]

    QA -->|"passed: true"| Artifact[["Game-ready .tres\n+ validation report"]]
    QA -->|"passed: false, problems"| Designer
```

**Data flow, in order:**

1. A `SpeciesBrief` (name + 2-4 sourced ecology facts) enters the crew.
2. **Habitat Designer** turns it into habitat/tuning data, checked against the
   inert-land invariant (a species can't be satisfiable by land the player never touched).
3. Its output fans out to two agents that run independently, since neither depends on
   the other's output:
   - **Schema Writer** encodes it as a valid `AnimalDefinition` `.tres` body.
   - **Content Writer** drafts the fact card against the GDD's four-step checklist.
4. The orchestrator merges the fact card into the `.tres` body (string substitution,
   not an agent step — no judgment involved).
5. **QA Validator** deterministically re-checks the merged result against the same
   rules `AnimalDefinition.validate()` enforces in the real game. A failure returns
   a `problems` list; in a longer-running crew this would loop back to the Habitat
   Designer with the QA report attached (shown as the dashed feedback path above; the
   reference implementation runs one pass and reports the failure instead of auto-retrying).
