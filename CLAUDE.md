# CLAUDE.md

<!-- cspell:ignore callees pathofbuildingcommunity pathofbuilding modcache -->

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## MCP Tools: code-review-graph

This project may have a knowledge-graph MCP server (`code-review-graph`)
configured. **When its tools are available in the session, prefer them over
Grep/Glob/Read for exploration** — they are faster, cheaper, and give
structural context (callers, dependents, test coverage):

- `semantic_search_nodes` / `query_graph` — find code, trace callers/callees/imports/tests
- `get_impact_radius` / `get_affected_flows` — blast radius of a change
- `detect_changes` + `get_review_context` — risk-scored code review with snippets
- `get_architecture_overview` + `list_communities` — high-level structure
- `refactor_tool` — plan renames, find dead code

If these tools are **not** available in the current session, use the standard
Grep/Glob/Read tools as normal.

## Project overview

A fork of PathOfBuildingCommunity/PathOfBuilding-PoE2 — an offline build
planner for Path of Exile 2. The codebase is ~100% Lua (5.1 / LuaJIT). The
project's core value is correctly modelling PoE2's stat math; correctness of
numeric calculations outranks everything else.

## Commands

Tests use [Busted](https://lunarmodules.github.io/busted/) with LuaJIT inside
a pre-built container (`ghcr.io/pathofbuildingcommunity/pathofbuilding-tests`).
No local Lua toolchain is needed — only Docker (or Podman).

```bash
docker compose run --rm busted-tests                          # full suite
docker compose run --rm busted-tests --exclude-tags builds,data  # unit tests only (what CI calls "unit")
docker compose run --rm busted-tests --tags builds            # build snapshot tests (slow)
docker compose run --rm busted-tests --tags data              # data file validation only
docker compose run --rm busted-tests --filter="pattern"       # single test by describe/it name (Lua pattern)
```

Notes:
- The compose service is named `busted-tests` (not `tests`).
- The compose volume is mounted read-only, so `--coverage` cannot write
  `luacov.report.out` through compose. CI works around this with a plain
  `docker run` that bind-mounts only the report file writable (see
  `.github/workflows/ci.yml`).
- Busted config is in `.busted`: it runs from `src/` with
  `HeadlessWrapper.lua` as the helper and discovers specs in `spec/`.
- Baseline on `dev`: the full suite is **green — there are no known failures**.
  (Ward regen/bypass, formerly the two known failures, were implemented in
  0.20.0.) If a test fails, treat it as a regression: verify it also fails on
  unmodified `dev` before assuming it is pre-existing, and never "fix" a
  failure by weakening assertions.

CI (`.github/workflows/ci.yml`) runs three matrix suites on PRs to `dev`:
unit (`--exclude-tags builds,data`), builds, and data — plus a coverage job.

## Architecture

### Entry points

- `src/Launch.lua` — GUI entry point (SimpleGraphic-based desktop app).
  It loads `src/Modules/Main.lua`, which loads everything else.
- `src/HeadlessWrapper.lua` — headless bootstrap that stubs all rendering
  callbacks so PoB runs under a plain Lua interpreter. This is what the test
  suite boots through, and the model for any scripted/automated use of PoB.
- `runtime/lua/` — bundled Lua libraries available at runtime.

### The modifier system (the heart of PoB)

Everything a character "has" is a **mod**: `mod(Name, Type, Value, source, modFlags, keywordFlags, ...tags)`.

- `src/Modules/ModParser.lua` — converts modifier *text* (from items, passive
  nodes, etc.) into structured mods via Lua patterns. The single most
  load-bearing file in the project.
- `src/Modules/ModTools.lua` — the `mod()`/`flag()` constructors.
- `src/Classes/ModDB.lua`, `ModList.lua`, `ModStore.lua` — storage and lookup
  for mods, with summing/flag-matching semantics (`BASE`, `INC`, `MORE`,
  `OVERRIDE`, `FLAG` mod types).
- `src/Data/SkillStatMap.lua` — maps skill gem stats onto mods (same syntax,
  source auto-filled). **Hand-maintained**: a new gem stat with no entry here
  (and no local `statMap` in its `src/Data/Skills/*.lua` file) silently
  contributes nothing.
- `src/Data/Global.lua` — `ModFlag`/`KeywordFlag` bitflag definitions.
- `src/Data/ModCache.lua` — generated cache of `parseMod` results for every
  mod line in the data files. Entry format: `c["line"] = {modList, extra}`;
  `nil` modList or non-empty `extra` text means the line is (partially)
  unsupported. Never hand-edit it — regenerate with `REGENERATE_MOD_CACHE=1`
  (CI's `check_modcache` job in `.github/workflows/test.yml` does this too,
  see `src/Modules/Main.lua:122`). Commit the regenerated file with any
  ModParser or data change.

Read `docs/modSyntax.md` and `docs/addingMods.md` before touching any of this.

### The calculation pipeline

Calc engine files live flat in `src/Modules/` (there is **no** `Calcs/`
subdirectory):

- `Calcs.lua` — public entry (`calcs.buildOutput`, `calcs.calcFullDPS`, node/misc calculators used by the UI for "what-if" diffs).
- `CalcSetup.lua` — builds the calculation environment: collects mods from tree, items, skills into per-actor ModDBs.
- `CalcPerform.lua` — orchestrates a full calculation pass (`calcs.perform`).
- `CalcOffence.lua` — DPS. Attacks run **per-hand passes**: inside a pass, the local `output` is `actor.output.MainHand`/`OffHand` and `globalOutput` is `actor.output`; hand results are merged with `combineStat`. Misattributing output to the wrong table is the classic bug here — read `docs/calcOffence.md` first.
- `CalcDefence.lua` — life/ES/mana pools, mitigation, EHP.
- `CalcActiveSkill.lua`, `CalcTriggers.lua`, `CalcMirages.lua` — skill setup, trigger rates, mirage actors.
- `CalcSections.lua` + `CalcBreakdown.lua` — definitions for the Calcs tab breakdown UI.

`Build.lua` (a Module) ties the tabs together; UI tab classes
(`CalcsTab`, `ItemsTab`, `TreeTab`, …) live in `src/Classes/`.

### Game data

- `src/Data/` — gems (`Gems.lua`, `Skills/`), item bases (`Bases/`), uniques,
  mods for crafting (`Mod*.lua`), bosses, minions.
- `src/TreeData/` — passive tree data per game version. **Current game version
  is 0.5** — the live tree is `src/TreeData/0_5/tree.lua`; older `0_1`–`0_4`
  directories exist only for loading legacy builds. Don't validate new-mechanic
  work against pre-0_5 tree data.
- `src/Export/` — scripts that regenerate `src/Data/` from the game's GGPK
  files. Data files are largely **generated** — prefer fixing the exporter or
  following the existing generated format over hand-editing structure.
  The exporter **cannot run in CI or agent sessions**: it is GUI-only
  (launched via `src/Export/Launch.lua` through the SimpleGraphic runtime),
  needs a local PoE2 install, and uses a Windows-only extractor
  (`bun_extract_file.exe`, see `CONTRIBUTING.md`). The generated files
  committed under `src/Data/` and `src/TreeData/` are therefore the source of
  truth for agents — work from them, never try to re-export.
- `src/GameVersions.lua` — supported game version constants
  (`latestTreeVersion`, `treeVersionList`, …).

### Documentation worth reading before non-trivial changes

`docs/rundown.md` (file-by-file tour), `docs/calcOffence.md`,
`docs/modSyntax.md`, `docs/addingMods.md`, `docs/addingSkills.md`.

## Critical rules

1. **Never break numeric calculations.** If you touch any `src/Modules/Calc*.lua`
   file, you MUST add or update tests in `spec/System/` that assert specific
   stat values within tolerance (±0.01 for DPS, exact for hit point pools).

2. **Modifier parsing is fragile.** Any `ModParser.lua` change requires test
   cases for the new modifier strings in `spec/System/TestModParser_spec.lua`
   and a passing full suite.

3. **Data file changes need validation.** After modifying anything in
   `src/Data/`, run `docker compose run --rm busted-tests --tags data`.

4. **Lua nil-safety is your responsibility.** No type system. Guard chained
   accesses (`t and t.field and t.field.sub`). Nil reference crashes are the
   #1 source of bug reports.

5. **Performance matters in calculation hot loops.** Avoid table allocations
   inside per-pass calc code; cache frequently-accessed table fields in locals.

## Validation before opening a PR

1. Full suite passes: `docker compose run --rm busted-tests`
2. Coverage did not drop (compare `luacov.report.out` against the base branch)
3. Commit messages follow Conventional Commits (`feat:`, `fix:`, `refactor:`, …)

## Fork & PR rules

1. **NEVER open PRs against the upstream repo**
   (`PathOfBuildingCommunity/PathOfBuilding-PoE2`). All PRs target this fork
   (`jay9297/PathOfBuilding-PoE2`), base branch `dev`. Upstream sync is done
   by merging upstream's `dev` locally, not via PRs.

2. This fork runs automated AI workflows (`ai-fix.yml` triggered by the
   `ai-fix` issue label, `ai-review.yml`, `auto-merge.yml`). See
   "AI Workflow Escape Hatches" in `README.md` for how to control them.
