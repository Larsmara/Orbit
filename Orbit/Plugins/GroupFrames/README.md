# GroupFrames

## Description
Unified unit frames for party (party1–4) and raid (raid1–40) members. One plugin adapts layout, sizing, and behavior across four group-size tiers: Party (1–5), Mythic (6–20), Heroic (21–30), World (31–40).

## Purpose
Replaces the separate PartyFrames and RaidFrames plugins with a single tier-aware container. Each tier has independent settings (width, height, spacing, layout mode, component positions); syncing settings between tiers is opt-in.

## Implementation
`GROUP_ROSTER_UPDATE` / `PLAYER_ROLES_ASSIGNED` (and zone transitions) drive tier evaluation in `GroupFrame.lua` using member count plus instance constraints (`GetInstanceInfo()` maxPlayers locks mythic raids at 20). On a tier change the plugin saves the old tier's position, restores the new tier's, and re-applies layout. `GroupFrameFactory.lua` (`Orbit.GroupFrameFactoryMixin`) creates unit buttons and registers per-unit events via `RegisterUnitEvent`; health/power render through StatusBar sinks with gradient/curve skinning. `GroupFrameLayout.lua` (`Orbit.GroupFrameLayoutMixin`) positions frames per tier — party stacking vs. raid grid with sort modes — with combat-guarded entry points; `GroupFrameHelpers.lua` supplies layout constants, sort modes, border merging, and membership utilities. Buffs/debuffs go through `Orbit.AuraMixin:UpdateAuraContainer` with per-frame pools; private auras via `Orbit.PrivateAuraMixin`. `GroupFrameSettings.lua` builds the tier-selector schema with sub-tabs; `GroupFramePreview.lua` renders canvas/edit-mode previews with mock data that must match live frames exactly.

Tier-scoped keys (`Position`, `Anchor`, `ComponentPositions`, `DisabledComponents`, plus all schema defaults) are routed through the `TIER_KEYS` table in the plugin's `GetSetting`/`SetSetting` overrides, landing under `Tiers[tier]` in the profile.

## Gotchas
- `ApplySettings` must never call `RestoreTierPosition` — that call path caused the "snap back to default on group join" regression. The only legitimate movers of the container are `OnLoad`, tier transitions (`CheckTierChange`), combat-end replay (`PLAYER_REGEN_ENABLED`), Edit Mode exit, and the settings tier dropdown.
- The plugin deliberately does not implement `IsSpecScopedIndex`, excluding it from Persistence's spec-change bulk restore (see `Core/EditMode/README.md`) — the container is authoritative over its own anchor.
- `Buffs`/`Debuffs` use a fingerprint cache (`container._auraFingerprint`) that skips icon rebuilds when the aura set is unchanged. Any settings-changing entry point must call `Orbit.AuraMixin:InvalidateContainerLayout(frame)` per frame first (as `ApplySettings` does) or containers keep stale layout.
- Canvas mode reset needs `GetDefaultComponentPositions` / `GetDefaultDisabledComponents` because `plugin.defaults.ComponentPositions` doesn't exist at the flat level — defaults live per tier in `TIER_DEFAULTS`.
- Combat lockdown: `UpdateFrameUnits` and settings application defer via `Orbit.CombatManager:QueueUpdate`; tier transitions during combat wait for `PLAYER_REGEN_ENABLED`. No manual show/hide of unit buttons in combat.
- Raid frame update functions must stay O(1) per frame; frame recycling must reset all state.
- Selection, aggro, and dispel highlights all use `Skin:ApplyHighlightBorder`.

## Secrets
`UnitGUID` is secret in combat — the roster diff checks `issecretvalue(newGuid)` before any nil/boolean test and treats secret as nil. Name sorting guards `issecretvalue(nameA/nameB)` on the legacy path and bails rather than compare. Health/power values flow only into StatusBar sinks (`SetMinMaxValues`/`SetValue`); backdrop and dispel coloring use ColorCurves (`Orbit.DispelIndicatorMixin:InvalidateDispelCurve` on settings change), never Lua arithmetic on unit values.

## References
- `Core/UnitDisplay/` — shared mixins (`AuraMixin`, `StatusIconMixin`, `DispelIndicatorMixin`, `PrivateAuraMixin`, `UnitFrameMixin`); add shared features there, group-specific ones in `GroupFrame.lua`.
- `Core/EditMode/README.md` — persistence/spec-restore contract.
- Skills: `/wow-secrets`, `/wow-filters` (aura display), `/wow-frames` (secure unit buttons).
