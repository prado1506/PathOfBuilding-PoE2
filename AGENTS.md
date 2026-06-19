<!-- cspell:ignore callees pathofbuildingcommunity pathofbuilding modcache -->
<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

This project may have a knowledge-graph MCP server (`code-review-graph`)
configured. **When its tools are available in the session, prefer them over
Grep/Glob/Read for exploration** — they are faster, cheaper (fewer tokens),
and give structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools first

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`
- **Planning refactors**: `refactor_tool` for renames and dead code

If these tools are **not** available in the current session, use the standard
Grep/Glob/Read tools as normal.

---

# Path of Building 2 — Agent Instructions

You are working on a fork of PathOfBuildingCommunity/PathOfBuilding-PoE2, an
offline build planner for Path of Exile 2. The codebase is ~100% Lua
(5.1 / LuaJIT). The project's core value is correctly modelling PoE2's stat
math; correctness of numeric calculations outranks everything else.

## Critical rules

1. **Never break numeric calculations.** If you touch any
   `src/Modules/Calc*.lua` file, you MUST add or update tests in
   `spec/System/` that assert specific stat values within tolerance
   (±0.01 for DPS, exact for hit point pools).

2. **Modifier parsing is fragile.** `src/Modules/ModParser.lua` is the single
   most load-bearing file. Any change requires:
   - Test cases for the new modifier strings in `spec/System/TestModParser_spec.lua`
   - A passing full suite (`docker compose run --rm busted-tests`)

3. **Data file changes need validation.** Game data lives in `src/Data/`.
   After modifying any data file, run
   `docker compose run --rm busted-tests --tags data`.

4. **Lua nil-safety is your responsibility.** Lua has no type system. Guard
   chained accesses (`t and t.field and t.field.sub`). Nil reference crashes
   are the #1 source of bug reports in PoB.

5. **Performance matters in calculation hot loops.** Avoid table allocations
   inside per-pass calc code; cache frequently-accessed table fields in locals.

## How to test changes

Tests use Busted with LuaJIT inside a pre-built container
(`ghcr.io/pathofbuildingcommunity/pathofbuilding-tests`). Only Docker (or
Podman) is needed — no local Lua toolchain.

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
  `luacov.report.out` through compose. CI uses a plain `docker run` that
  bind-mounts only the report file writable (see `.github/workflows/ci.yml`).
- Busted config is in `.busted`: it runs from `src/` with
  `HeadlessWrapper.lua` as the helper and discovers specs in `spec/`.
- Baseline on `dev`: the full suite is **green — there are no known failures**.
  (Ward regen/bypass, formerly the two known failures, were implemented in
  0.20.0.) If a test fails, treat it as a regression: verify it also fails on
  unmodified `dev` before assuming it is pre-existing, and never "fix" a
  failure by weakening assertions.

## How to validate before opening a PR

1. Full suite passes: `docker compose run --rm busted-tests`
2. Coverage did not drop: compare `luacov.report.out` against the base branch
3. Commit messages follow Conventional Commits (`feat:`, `fix:`, `refactor:`, …)

## Project structure

- `src/Launch.lua` — GUI entry point; loads `src/Modules/Main.lua`, which loads everything else.
- `src/HeadlessWrapper.lua` — headless bootstrap (what the test suite and any scripted use of PoB boots through).
- `src/Modules/Calc*.lua` — the calculation engine, flat files (there is **no** `Calcs/` subdirectory): `Calcs.lua` (public entry), `CalcSetup.lua`, `CalcPerform.lua`, `CalcOffence.lua`, `CalcDefence.lua`, `CalcActiveSkill.lua`, `CalcTriggers.lua`, `CalcMirages.lua`, plus `CalcSections.lua`/`CalcBreakdown.lua` for the breakdown UI.
- `src/Modules/ModParser.lua` — converts modifier text into structured mods; `src/Modules/ModTools.lua` has the `mod()`/`flag()` constructors.
- `src/Classes/` — UI tab classes and the mod storage classes (`ModDB.lua`, `ModList.lua`, `ModStore.lua`).
- `src/Data/` — game data: gems, item bases, uniques, crafting mods. Largely **generated** by `src/Export/` from GGPK files — prefer fixing the exporter over hand-editing structure. The exporter itself cannot run in CI or agent sessions (GUI-only, needs a local PoE2 install and a Windows-only extractor), so the committed generated files are the source of truth for agents.
- `src/Data/SkillStatMap.lua` is **hand-maintained**: a new gem stat with no entry here (and no local `statMap` in its `src/Data/Skills/*.lua` file) silently contributes nothing.
- `src/Data/ModCache.lua` — generated cache of `parseMod` results (`c["line"] = {modList, extra}`; `nil` modList or non-empty `extra` ⇒ line is (partially) unsupported). Never hand-edit; regenerate with `REGENERATE_MOD_CACHE=1` (CI's `check_modcache` job also does this) and commit it with any ModParser or data change.
- `src/TreeData/` — passive tree data per game version. **Current game version is 0.5** — the live tree is `src/TreeData/0_5/tree.lua`; `0_1`–`0_4` exist only for loading legacy builds.
- `spec/System/` — Busted test suite (`*_spec.lua`).
- `runtime/lua/` — bundled Lua libraries available at runtime.
- `docs/` — read `rundown.md`, `calcOffence.md`, `modSyntax.md`, `addingMods.md`, `addingSkills.md` before non-trivial changes.

In `CalcOffence.lua`, attacks run **per-hand passes**: inside a pass the local
`output` is `actor.output.MainHand`/`OffHand` and `globalOutput` is
`actor.output`; hand results are merged with `combineStat`. Misattributing
output to the wrong table is the classic bug — read `docs/calcOffence.md` first.

## Fork rules

1. **NEVER open PRs against the upstream repo** (`PathOfBuildingCommunity/PathOfBuilding-PoE2`). All PRs must target the fork (`jay9297/PathOfBuilding-PoE2`), base branch `dev`.

2. **Default push target is `fork`.** All `git push` and PR operations default to `fork/dev`. The git config enforces this via `remote.pushDefault=fork` and `branch.dev.remote=fork`.

3. **Upstream sync is via local merge, not PR.** To sync with upstream: `git fetch origin && git merge origin/dev` on the local `dev` branch, then push to fork.

4. This fork runs automated AI workflows (`ai-fix.yml` triggered by the `ai-fix` issue label, `ai-review.yml`, `auto-merge.yml`). See "AI Workflow Escape Hatches" in `README.md` for how to control them.
