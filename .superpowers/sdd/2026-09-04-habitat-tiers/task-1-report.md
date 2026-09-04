# Task 1 Report: HabitatNeed, HabitatLimit, HabitatTier Schema Implementation

## Summary

Successfully implemented three pure schema Resource classes (`HabitatNeed`, `HabitatLimit`, `HabitatTier`) and their associated test suite. All code transcribed exactly from the task brief without modification. All 13 assertions pass.

## Implementation Details

### Files Created

1. **`project/scripts/definitions/habitat_need.gd`** (63 lines)
   - Resource representing a positive habitat requirement within a tier
   - Sentinel constants: `RADIUS_FOLLOWS_SCOUT` (0), `GATE_ONLY` (0)
   - Radius bounds: `RADIUS_MIN` (2), `RADIUS_MAX` (16) per OQ-B ruling
   - Public methods: `effective_radius(fallback_radius: int)`, `is_gate_only()`, `validate()`
   - Three fields: `tag`, `radius`, `tiles_per_individual`

2. **`project/scripts/definitions/habitat_limit.gd`** (44 lines)
   - Resource representing an exclusion constraint within a tier ("at most N of tag within radius")
   - Reuses sentinel `RADIUS_FOLLOWS_SCOUT` from `HabitatNeed`
   - References `HabitatNeed.RADIUS_MIN/MAX` for validation bounds
   - Public methods: `effective_radius(fallback_radius: int)`, `validate()`
   - Three fields: `tag`, `radius`, `max_count`

3. **`project/scripts/definitions/habitat_tier.gd`** (70 lines)
   - Resource representing one viable tier configuration for a species
   - Encapsulates positive requirements (`needs: Array[HabitatNeed]`) and exclusions (`limits: Array[HabitatLimit]`)
   - Public methods: `max_radius(fallback_radius: int)`, `validate()`
   - Five fields: `id`, `needs`, `limits`, `max_individuals`, `arrival_group_size`
   - `max_radius()` uses typed loop iteration (`for need: HabitatNeed in needs:`)

4. **`project/tests/test_habitat_tier_schema.gd`** (86 lines)
   - Comprehensive test suite exercising all three classes
   - Five test functions covering: sentinel resolution, gate-only logic, defaults, max radius calculation, and validation
   - Tests verify both valid and invalid data scenarios

### Code Style Conformance

- `@tool` attribute on all Resource classes for editor-time availability
- Static typing throughout, including typed loop variables
- All public members documented with `##` doc comments
- Sentinel constants documented with their semantic meaning
- `validate()` returns `Array[String]` (non-fatal, never raises)
- Matches surrounding codebase style from `animal_definition.gd`

### Test Results

```
bash scripts/run-tests.sh habitat_tier_schema
```

**Output:**
```
==> Importing project (registers class_name, rebuilds import cache)
==> Running 1 suite(s)

  PASS  test_habitat_tier_schema
        === habitat tier schema ===
          PASS  sentinel radius follows the fallback
          PASS  explicit radius overrides the fallback
          PASS  divisor 0 reads as GATE_ONLY
          PASS  divisor 4 does not read as GATE_ONLY
          PASS  a limit defaults to allowing none at all
          PASS  limit sentinel radius follows the fallback
          PASS  max_radius spans needs AND limits
          PASS  an empty tier falls back to the species radius
          PASS  a need with no tag is a problem
          PASS  radius 30 is outside the 2-16 band
          PASS  a negative max_count is a problem
          PASS  a tier with no needs is a problem
          PASS  a well-formed tier validates clean
        --- habitat tier schema: 13 passed, 0 failed ---
        habitat tier schema OK

================================================================
Suites: 1 total, 1 passed, 0 failed
================================================================
```

**Result:** PASS, 13 assertions

## Deviations from Brief

None. Code transcribed exactly as specified in the task brief. All class signatures, field names, method names, constants, and validation logic match verbatim.

## Validation

- All 13 test assertions pass
- No tuning values or simulation logic present (schema-only)
- `validate()` non-fatal by design (returns array, never raises)
- No circular dependencies: `HabitatLimit` and `HabitatTier` reference `HabitatNeed` for bounds only
- Sentinel resolution through `effective_radius(int fallback)` method (takes `int`, not `AnimalDefinition`)

## Git Commit

```
Commit: 55a6554
Branch: feature/habitat-tiers
Message: Task 1: Add HabitatNeed, HabitatLimit, HabitatTier schema classes
```

Files changed:
- `project/scripts/definitions/habitat_need.gd` (new)
- `project/scripts/definitions/habitat_limit.gd` (new)
- `project/scripts/definitions/habitat_tier.gd` (new)
- `project/tests/test_habitat_tier_schema.gd` (new)

## Self-Review

- ✓ All three Resource classes extend proper base and use `@tool`
- ✓ All export fields match brief specification exactly
- ✓ All sentinel constants documented with semantic meaning
- ✓ Typed loop iteration used throughout (`for x: Type in ...`)
- ✓ All public members carry `##` documentation
- ✓ `validate()` returns `Array[String]`, never mutates, never raises
- ✓ Test file exercises positive and negative cases
- ✓ No untracked dependencies or coupling beyond what's specified
- ✓ Code matches surrounding house style

Ready for Task 2 (habitat tier constants proposal and AnimalDefinition refactoring).
