# QoL

## Description
Standalone, always-on quality-of-life behaviors layered over the Blizzard UI: `MoveMore` (draggable Blizzard panels), `Mouse` (cursor highlight overlay), `Tooltips` (tooltip scale/anchor/hide + class-color, target and ID enrichment), `UserInterface` (UI scale below Blizzard's floor + class-color tweaks), `QuestAutomation` (auto accept/turn-in quests), `NpcAutomation` (auto gossip/sell-junk/repair), and `Spotlight` (hotkey universal search, decomposed into `Spotlight/`).

## Purpose
Home for features that fail the Edit Mode placement test — no movable frame, no edit- or canvas-mode footprint — so they live outside the plugin system entirely. Unlike plugins they are account-wide and do not participate in Orbit profiles.

## Implementation
Each module is one PascalCase file registering `Orbit.ModuleName` with `Enable()`/`Disable()`. A loader frame on `PLAYER_LOGIN` defers briefly (`C_Timer.After`), reads the module's flag from `Orbit.db.AccountSettings`, and calls `Enable()` if set; Spotlight alone enables unconditionally. Single-file modules load directly from `Orbit.toc` (no XML bundle); decomposed modules load their own bundle (`QoL\Spotlight\Spotlight.xml`).

Settings land in `Orbit.db.AccountSettings` — runtime modules read the table directly. The config UI is `Core/Config/Advanced/QoL.lua`: an accordion panel (sections: UserInterface, Colors, MoveMore, Mouse, Tooltips, Automation, Spotlight) whose file-local `Get/SetAccountSetting` helpers write the same table. Adding a section = one builder function returning its content height plus one `sectionDefs` row with a localized `PLU_QOL_SEC_*` label.

**Design choice — one visual language for every panel (the "Automation" premium style):** section builders lay out through the shared `BuildGrouped(body, groups)` — each group is an `AddGroupHeader` (GameFontNormal label + 1px gold divider `1,0.82,0,0.3`), then full-width rows (`full` — master toggles, buttons, descriptions; height from `GetHeight` or an explicit `{frame,h}` for async ones), then per-type reflowing grids with fixed column counts: **checkboxes 3-col** (`checks`), **sliders 2-col** (`sliders`), **dropdowns 2-col** (`dropdowns`). Grid cells dual-anchor (TOPLEFT+TOPRIGHT) so sliders/dropdowns lay out their label+value; all grids reflow on `OnSizeChanged`. `AddGroupHeader` is the *only* section-header style — `Layout:CreateSectionHeader` (large font, no divider) is reserved for the panel title. Colors/Spotlight keep bespoke inner grids (pickers; the 3-col category grid reflows the same way) but route headers through `AddGroupHeader` so the whole tab reads as one system.

## Gotchas
- Account-wide only. Never store QoL state in `Orbit.db.profiles[...]` or generic `Orbit.db` keys — profile switches would wipe or fork it.
- Modules must not depend on other plugins or on other QoL modules.
- Decomposed modules keep all state inside the `Orbit.ModuleName` namespace (sub-tables per file) — no module-level mutable state in source files.
- These modules touch protected Blizzard frames; gate with `Orbit:SafeAction(callback)` or `InCombatLockdown()` before modifying them.
- `Tooltips` must stay taint-safe: it only *enriches* via `AddTooltipPostCall` and hooks Blizzard's `GameTooltip_SetDefaultAnchor` (runs in the caller's context) — it never drives/owns the shared tooltip from an OnEnter. Every read of unit identity (secret in combat) is gated behind `canaccessvalue()`.
- User-visible strings go through `Orbit.L` (`PLU_*` keys) — see `Orbit/Localization/README.md`.

## References
- `QoL/Spotlight/README.md` — the one decomposed module.
- `Plugins/README.md` — where designable (draggable) UI goes instead; placement test in root `CLAUDE.md`.
- `Core/Config/Advanced/QoL.lua` — the settings panel.
- `Orbit/Localization/README.md` — string workflow.
