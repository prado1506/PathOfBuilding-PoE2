# Advisor — Developer notes

<!-- cspell:ignore pathofbuilding pathofbuildingcommunity headlessly maxhit deadend -->

Working notes for the **Advisor** feature (native, fully-offline deterministic
build-advisor tab). Tracking epic: [#85](https://github.com/jay9297/PathOfBuilding-PoE2/issues/85).

## Where development happens

This repository (`jay9297/PathOfBuilding-PoE2`) **is** the dev fork. All Advisor work lives
on the epic branch `feat/advisor-epic`; each sub-issue (#77–#84) is built on its own
`feat/advisor-NN-*` branch off the epic branch and merged back up. The epic branch is the
single unit reviewed against `dev`.

> The upstream community repo is the `origin` remote here; the fork is the `fork` remote.
> PRs target `fork/dev` — **never** upstream (see `CLAUDE.md` › Fork & PR rules).

## Running

- **Headless** (verified, CI path): the build loads under a plain LuaJIT interpreter via
  `src/HeadlessWrapper.lua`, which stubs the rendering callbacks. This is how the test
  suite boots and is the model for any scripted use — `loadBuildFromXML(...)` then read
  `build.calcsTab.mainOutput`. The Advisor logic module (`src/Modules/Advisor.lua`) is
  designed to be exercised entirely on this path.
- **GUI** (SimpleGraphic desktop runtime): launched via `src/Launch.lua`. Not available in
  the headless/CI environment used for this work; verify UI changes on a desktop checkout.

## Tests

The suite uses [Busted](https://lunarmodules.github.io/busted/) with LuaJIT inside the
pre-built container image `ghcr.io/pathofbuildingcommunity/pathofbuilding-tests`.

`CLAUDE.md` documents the `docker compose` form. This dev machine has **no Docker** — only
Podman, and no compose provider — so use a plain `podman run` that mirrors
`docker-compose.yml` (image, `HOME=/tmp`, read-only `/workdir` mount, `busted --lua=luajit`
entrypoint):

```bash
# Full unit suite (what CI calls "unit"): excludes slow build-snapshot + data tags
podman run --rm -e HOME=/tmp -v ./:/workdir:ro -w /workdir \
  --security-opt no-new-privileges:true \
  --entrypoint busted ghcr.io/pathofbuildingcommunity/pathofbuilding-tests:latest \
  --lua=luajit --exclude-tags builds,data

# Just the Advisor specs (fast inner-loop while iterating)
podman run --rm -e HOME=/tmp -v ./:/workdir:ro -w /workdir \
  --security-opt no-new-privileges:true \
  --entrypoint busted ghcr.io/pathofbuildingcommunity/pathofbuilding-tests:latest \
  --lua=luajit --filter="Advisor"

# Data-file validation (run after any src/Data change)
#   ... --lua=luajit --tags data
```

On a machine with Docker, the documented `docker compose run --rm busted-tests ...` forms
in `CLAUDE.md` work identically.

**Baseline** on `feat/advisor-epic` (off `dev`): the full unit suite is
**green — 481 successes / 0 failures / 0 errors / 0 pending** (~9.5 min). Treat any new
failure as a regression.

## Rebasing on upstream

The fork's `dev` tracks the upstream community `dev` (the `origin` remote). To pick up an
upstream release:

```bash
git fetch origin
git switch dev && git merge origin/dev      # fast-forward / merge upstream into fork dev
git push fork dev
git switch feat/advisor-epic && git rebase dev   # replay the epic on the new base
```

The feature keeps its surface area small to make this cheap — see the touched-files list in
`ADVISOR.md` (added in #84).

## Upstream files touched

The Advisor feature is intentionally isolated to keep upstream rebases cheap. The only
modified upstream file is `src/Modules/Build.lua`, with three small additions:

| Location | Change |
|---|---|
| tab instantiation (~L519) | `self.advisorTab = new("AdvisorTab", self)` |
| mode-button row (~L347) | `modeAdvisor` button + `locked` + dynamic high-severity `label` badge |
| draw dispatch (~L1363) | `elseif self.viewMode == "ADVISOR" then self.advisorTab:Draw(...)` |

Everything else is new, self-contained files:

- `src/Classes/AdvisorTab.lua` — UI tab
- `src/Modules/Advisor.lua` — analysis logic
- `spec/Modules/Advisor_spec.lua` — unit tests
- `spec/System/TestAdvisorSmoke_spec.lua` — headless smoke test
- `ADVISOR.md`, `ADVISOR-DEV.md` — docs

Because the upstream surface is one file with three additive hunks, rebasing on an
upstream release rarely conflicts; if it does, re-apply the three hunks above.
