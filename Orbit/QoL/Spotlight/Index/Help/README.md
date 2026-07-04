# Help

## Description
The `help` Spotlight kind: a curated catalog of Orbit actions and hidden-interaction explainers, surfaced only when a query leads with `help` or `orbit` (`prefixOnly` — it never appears in normal item/spell search).

## Purpose
In-client discoverability for Orbit features that have no visible affordance — reset menus, tool actions, and explainers for non-obvious interactions — without building a dedicated help window.

## Implementation
`Topics/*.lua` (one file per topic, pure localized data) call `Orbit.Spotlight.Index.Help:Register(entries)` at file load; `HelpRegistry.lua` accumulates them. The source at `../Sources/Help.lua` reads `GetAll()` at build time and stamps `kind`, `icon` (default `Interface\common\help-i`), and `lowerName = Fold(topic .. name .. keywords)` — so topic ("help damage meter"), label ("help reset"), and keywords ("help cooldown manager" on a CDM-topic entry) all match.

Entry contract (all strings are `PLU_SPT_HELP_*` keys in `Localization/Domains/Plugins.lua`):

```lua
{
    id       = "<unique>",             -- Recents key; stable string
    topic    = L.PLU_SPT_HELP_TOP_*,   -- right-aligned row label; folded into the search bag
    name     = L.PLU_SPT_HELP_*,       -- row label and tooltip title
    desc     = L.PLU_SPT_HELP_*_TT,    -- white tooltip body
    note     = L.PLU_SPT_HELP_*_NOTE,  -- optional second body section, blank-line separated
    keywords = L.PLU_SPT_HELP_*,       -- optional extra search terms, not displayed
    trigger  = L.PLU_SPT_HELP_T_*,     -- explainer only: green accent line ("Shift + Right-click")
    onClick  = function(entry, row) end, -- action/menu only; row = menu anchor
    keepOpen = true,                   -- explainer & menu: don't close Spotlight on click
}
```

Three entry shapes share the one kind:
- **action** — `onClick` calls the owning Orbit module directly (e.g. `Orbit.API:PrintVersion()`, `Orbit.OptionsPanel:ToggleEditMode()`); the row closes Spotlight after firing.
- **menu** — `onClick` opens `MenuUtil.CreateContextMenu(row, ...)` anchored to the row; `keepOpen = true` keeps Spotlight under the menu. Long lists cap height with `root:SetScrollMode(...)` (~10 rows, wheel scroll) and hide the bar via `menu.ScrollBar:Hide()` on the returned frame.
- **explainer** — `trigger` + `desc` (+ optional `note`) render a tooltip teaching a non-obvious interaction; `keepOpen = true` lets the user read several in a row.

Adding: extend an existing `Topics/<X>.lua`, or create a new topic file and register it in `Spotlight.xml` after `HelpRegistry.lua` and before `Sources\Help.lua`; add the `PLU_SPT_HELP_*` keys in every locale; run `python .scripts/check-localization.py`.

## Gotchas
- Actions must call the owning module directly — never route through the chat parser; `/orbit` only toggles Edit Mode.
- Explainers must stay accurate against the real interaction — cite the owning plugin's code when authoring one. Actions are nearly free to add (terse descriptions are fine).
- Reuse the shared `PLU_SPT_HELP_T_*` trigger keys for modifier/click phrases instead of minting near-duplicates.

## References
- `../../README.md` — Spotlight (kinds table, matcher, row activation and `keepOpen` handling).
- `HelpRegistry.lua`, `../Sources/Help.lua` — the build path.
- `Orbit/Localization/README.md` — key workflow and lint.
