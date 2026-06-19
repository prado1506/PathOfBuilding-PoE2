# Advisor

<!-- cspell:ignore maxhit deadend headlessly -->

A native, fully-offline **Advisor** tab for this PoB2 fork. It reads the live,
already-calculated build (`build.calcsTab.mainOutput`, `build.skillsTab`,
`build.spec`) and surfaces rule-based improvement findings. **No LLM, no network** —
pure deterministic Lua over PoB's own engine output, so every number it cites is the
same value PoB shows.

## Architecture

| File | Role |
|---|---|
| `src/Modules/Advisor.lua` | Pure logic: `Advisor.analyze(build) -> { finding, ... }`. No UI refs; unit-testable headlessly. |
| `src/Classes/AdvisorTab.lua` | UI only: renders findings grouped by category with filters, click-to-jump, and live refresh. |
| `spec/Modules/Advisor_spec.lua` | Unit tests for every check against crafted `mainOutput` / skill / tree fixtures. |
| `spec/System/TestAdvisorSmoke_spec.lua` | Headless smoke test over a real engine-calculated build. |

## Finding shape

```lua
{
  id       = "res.fire.uncapped",  -- stable id
  severity = "high",               -- "high" | "med" | "low" | "info"
  category = "Survivability",      -- Survivability | Skills | Attributes | Spirit | Tree
  title    = "Fire Resistance is below cap",
  detail   = "Fire Res 58% (-17% under the cap).",   -- cites exact numbers
  fix      = "Add ~17% Fire Resistance on gear, runes, or the tree.",
  jump     = { mode = "ITEMS" },   -- optional: tab the finding navigates to
}
```

Findings are sorted by severity (`high=3, med=2, low=1, info=0`) then category then title.

## Check catalogue

| id | flags | severity |
|---|---|---|
| `res.<elem>.uncapped` | Fire/Cold/Lightning/Chaos resistance below cap (chaos ignored under Chaos Inoculation) | high (elem), med (chaos) |
| `res.<elem>.surplus` | Elemental resistance wasted over the cap | info |
| `ehp.low` | Effective HP below a level-scaled heuristic floor | med |
| `recovery.none` | No meaningful life/ES regen or leech | med |
| `mitigation.none` | No meaningful armour / evasion / block / suppression layer | med |
| `maxhit.weakest` | Weakest damage type by maximum hit taken | info |
| `support.inapplicable.<name>` | Support gem whose skill-type tags do not match the active skill | high |
| `support.empty.<skill>` | Socket group with an active skill but no supports | info |
| `support.duplicate.<gameId>` | Same support gem socketed twice in a group | med |
| `attr.unmet.<Attr>.<gem>` | Gem Str/Dex/Int requirement exceeds the character's attribute | high |
| `spirit.over` | Spirit over-reserved (negative unreserved) | high |
| `spirit.unused` | Large unreserved Spirit pool | info |
| `tree.adjacent.<id>` | Unallocated notable directly adjacent to the allocated tree | info |
| `tree.deadend.<id>` | Allocated travel node that reaches no notable/keystone/socket | med |
| `tree.floating` | Allocated nodes not connected to the class start | med |

## Adding a new check

1. Append a `t_insert(Advisor.checks, function(build, out, findings) ... end)` block in
   `src/Modules/Advisor.lua`. Each check appends 0..n findings using the shape above.
   Read engine values from `out` (= `build.calcsTab.mainOutput`); guard every access
   (`out.Foo and ...`) — a build mid-edit may be missing keys, and a crashing check must
   never break the tab (`Advisor.analyze` pcall-wraps each check).
2. Add a unit test in `spec/Modules/Advisor_spec.lua` using `healthyOutput(overrides)` (or
   a crafted skill/tree fixture) and `byId(findings, "<your.id>")`.
3. Document the new id in the catalogue table above.

No UI change is needed — `AdvisorTab` renders whatever `Advisor.analyze` returns.

## Running

See `ADVISOR-DEV.md` for the headless/test commands and the upstream rebase workflow.
