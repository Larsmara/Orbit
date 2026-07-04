# Datatexts

## Description
Free-floating informational datatexts (fps, gold, durability, stats, social counts, and more) delivered through a corner-triggered sliding drawer. Each datatext can be dragged out of the drawer, positioned anywhere on screen, and styled by Orbit's global font/texture/border settings.

## Purpose
Successor to the old `MenuItems/Performance.lua` and `MenuItems/CombatTimer.lua`, expanded into a self-contained ecosystem. Datatexts are deliberately not Orbit plugins and have no Edit Mode integration — the drawer's open/closed state is the lock/unlock model (closed = locked, click/tooltip active; open = draggable).

## Implementation
`Datatexts.lua` registers the single plugin (`Orbit_Datatexts`) whose defaults hold the two persistence tables. `BaseDatatext.lua` is the base class (frame creation, drag, tooltip, click/scroll handlers, event registration); each file in `Elements/` extends `DT.BaseDatatext:New("Name")`, implements `Init()`, and calls `Register()` — load order is `Elements/Elements.xml`. `DatatextManager.lua` owns the registry, the shared update scheduler (ticker pools), category metadata, and persistence: positions in `datatextPositions` and per-datatext options (e.g. "only show in instance") in `datatextOptions`, both read/written through `plugin:Get/SetSetting(1, …)` so they travel with profile switches. `DatatextManager:ApplyInstanceVisibility` re-evaluates options on zone changes and drawer open/close. `DrawerUI.lua` creates the four 4×4 px invisible corner triggers (TOOLTIP strata) and the animated drawer panel, sorted alphabetically. `Util/` holds `Formatting.lua` (numbers/money/time, RingBuffer), `Graph.lua` (tooltip sparklines), and `Menu.lua` (context menus). `Elements/StatDatatext.lua` is the shared combat-rating scaffold that Crit/Haste/Mastery/Versatility build on.

To add a datatext: new file in `Elements/`, extend `BaseDatatext`, implement `Init()` (frame, update func, handlers, then `Register()`), add a `<Script>` line to `Elements/Elements.xml`.

## Gotchas
- Hover tooltips must use the private `Orbit.Tooltip` frame, never the global `GameTooltip` — every file aliases `local GameTooltip = Orbit.Tooltip` at the top. Owning the global tooltip from addon code taints it and breaks Blizzard's secret-handling unit-tooltip pipeline (WoW 12.0+).
- Datatexts are internal objects managed centrally by `DatatextManager` (position, enabled state) — never register one as an Orbit plugin or wire it into Edit Mode.
- Each datatext file is self-contained; no cross-datatext dependencies.
- Drag in the drawer moves non-secure frames C-side under the cursor; secure frames move on a combat-guarded frame-synced OnUpdate instead (`DrawerUI.lua`).
- Strings go through `Orbit.L` with the `PLU_DT_*` prefix.

## Secrets
Combat-rating stats route every operand through `Orbit.SecretValueUtils.NumericOrNil` before arithmetic — one secret operand poisons a sum (see `Elements/Versatility.lua`, which adds two ratings). The shared rating-side guard lives once in `StatDatatext.lua`; each stat's `getPercent` owns its percent guard. `Speed.lua` gates on `issecretvalue(speed)` before formatting. Hearthstone reads `C_Container.GetItemCooldown` and displays via cooldown-safe formatting.

## References
- `Core/Shared/SecretValueUtils.lua` — `NumericOrNil`.
- Skills: `/wow-secrets` (rating/speed guards), `/unsecreted`.
