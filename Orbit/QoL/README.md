# QoL

## Description
Standalone, always-on quality-of-life behaviors layered over the Blizzard UI: `MoveMore` (draggable Blizzard panels), `Mouse` (cursor highlight overlay), `UserInterface` (UI scale below Blizzard's floor + class-color tweaks), `QuestAutomation` (auto accept/turn-in quests), `NpcAutomation` (auto gossip/sell-junk/repair), and `Spotlight` (hotkey universal search, decomposed into `Spotlight/`).

## Purpose
Home for features that fail the Edit Mode placement test — no movable frame, no edit- or canvas-mode footprint — so they live outside the plugin system entirely. Unlike plugins they are account-wide and do not participate in Orbit profiles.

## Implementation
Each module is one PascalCase file registering `Orbit.ModuleName` with `Enable()`/`Disable()`. A loader frame on `PLAYER_LOGIN` defers briefly (`C_Timer.After`), reads the module's flag from `Orbit.db.AccountSettings`, and calls `Enable()` if set; Spotlight alone enables unconditionally. Single-file modules load directly from `Orbit.toc` (no XML bundle); decomposed modules load their own bundle (`QoL\Spotlight\Spotlight.xml`).

Settings land in `Orbit.db.AccountSettings` — runtime modules read the table directly. The config UI is `Core/Config/Advanced/QoL.lua`: an accordion panel (sections: UserInterface, Colors, MoveMore, Mouse, Automation, Spotlight) whose file-local `Get/SetAccountSetting` helpers write the same table. Adding a section = one builder function returning its content height plus one `sectionDefs` row with a localized `PLU_QOL_SEC_*` label.

## Gotchas
- Account-wide only. Never store QoL state in `Orbit.db.profiles[...]` or generic `Orbit.db` keys — profile switches would wipe or fork it.
- Modules must not depend on other plugins or on other QoL modules.
- Decomposed modules keep all state inside the `Orbit.ModuleName` namespace (sub-tables per file) — no module-level mutable state in source files.
- These modules touch protected Blizzard frames; gate with `Orbit:SafeAction(callback)` or `InCombatLockdown()` before modifying them.
- User-visible strings go through `Orbit.L` (`PLU_*` keys) — see `Orbit/Localization/README.md`.

## References
- `QoL/Spotlight/README.md` — the one decomposed module.
- `Plugins/README.md` — where designable (draggable) UI goes instead; placement test in root `CLAUDE.md`.
- `Core/Config/Advanced/QoL.lua` — the settings panel.
- `Orbit/Localization/README.md` — string workflow.
