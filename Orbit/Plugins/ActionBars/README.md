# ActionBars

## Description
Replaces Blizzard's action bars with a configurable grid-based system: up to 8 standard bars (WoW 12.0's 180-slot hard limit) plus pet and stance bars.

## Purpose
Suppresses the native bars and reparents their buttons into Orbit containers so layout, skinning, text, and visibility are all Orbit-controlled while Blizzard's secure button machinery keeps doing the casting.

## Implementation
| File | Role |
|---|---|
| ActionBars.lua | plugin (`Orbit_ActionBars`); bar creation, button reparenting, visibility drivers, spell-state coloring, proc glow hooks |
| ActionBarsContainer.lua | per-bar container frame and button grid |
| ActionBarsPreview.lua | canvas mode previews |
| ActionBarsText.lua | keybind/macro/count text overlays and quality-overlay re-leveling |

Native bars are hidden and their buttons reparented into containers; visibility is macro-conditional state drivers (`BASE_VISIBILITY_DRIVER`, `BAR1_BASE_DRIVER`, `PET_BAR_BASE_DRIVER` at file top) via `RegisterStateDriver`. Spell-state events (`PLAYER_TARGET_CHANGED`, `ACTIONBAR_UPDATE_USABLE`, `SPELL_UPDATE_USABLE` leading-edge throttled, `ACTION_RANGE_CHECK_UPDATE`) arrive on the EventBus and drive `RefreshIconColor`, tinting icons for out-of-range/out-of-mana/unusable from settings colors cached until a settings change invalidates them. Proc glows come from `hooksecurefunc` on `ActionButtonSpellAlertManager.ShowAlert/HideAlert`, rendered by `GlowController`. Skinning is `Orbit.Skin.ActionButtonSkin` (Core/Skinning); `IconPadding = 0` swaps per-icon borders for a single `ApplyIconGroupBorder` group border, and containers set `mergeBorders = true` in `anchorOptions` so anchored bars merge borders across bars.

## Gotchas
- Never `hooksecurefunc` Blizzard's `ActionButton.Update` / `.UpdateUsable`. Under 12.0.5+ secret-value strictness those method hooks taint the secure call frame, which propagates into `ActionButton_ApplyCooldown` (rejects secret `start`/`duration`) and `UpdateShownButtons` (blocks `SetShown` in combat). Spell-state coloring is event-driven for exactly this reason.
- Pet bar driver is `[petbattle][vehicleui] hide; [pet,nooverridebar,nopossessbar] show; hide` — the positive `pet` form with override/possess exclusions. `[nopet]` alone leaks the bar during mind-control/possession.
- Pet events (`UNIT_PET`, `PET_BAR_UPDATE`, `PET_UI_UPDATE`, `UPDATE_VEHICLE_ACTIONBAR`, `PLAYER_CONTROL_GAINED`, entering world) only re-run `LayoutButtons` — Blizzard's `PetActionButtonMixin` still drives icon/cooldown updates on the reparented buttons. A 50ms trailing-edge debounce coalesces `UNIT_PET` (fires before action info loads) with the following `PET_BAR_UPDATE` (fires once loaded).
- State drivers are registered at container creation and in `ApplySettings` only; WoW re-evaluates macro conditions automatically, so never re-register them from event handlers.
- Drivers are unregistered in Edit Mode so bars stay shown and selectable; `ApplyAll` restores them on exit.
- Reparenting must preserve secure frame references for combat; all grid math must be pixel-snapped.
- Blizzard creates `ProfessionQualityOverlayFrame` (item-quality diamond) lazily with no frame level, so it renders under the Orbit border; `ABText:ApplyQualityOverlay` raises it to `Constants.Levels.IconGlow`, hooked on the button's `UpdateProfessionQuality`. Placement stays at Blizzard's default — the diamond is not a canvas component.
- Pet bar is index 9, stance bar index 10 (special bars — no OOC fade, content-driven icon count).

## Secrets
The plugin never intercepts Blizzard's cooldown paths, so secret `start`/`duration` values stay inside Blizzard code (see the hook gotcha above). `RefreshIconColor` branches on `IsUsableAction`/`C_Spell.IsSpellInRange` results, which are non-secret for the player's own action buttons — the tint colors themselves come from Orbit settings, not secret data.

## References
- `Core/Skinning/` (ActionButtonSkin), `Core/Shared/GlowController.lua`, `Core/Plugin/NativeBarMixin.lua`.
- Skills: `/wow-frames` (state drivers, secure templates), `/wow-secrets`, `/pixel`.
- Blizzard source: `agent/wow-ui-source/` ActionButton/ActionBar files.
