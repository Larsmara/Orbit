# UnitFrames

## Description
Player, target, and focus unit frames plus their extensions: power bars, class resource bar, cast bars, buffs/debuffs, pet frame, and target-of-target / target-of-focus.

## Purpose
Displays the three primary singleton unit frames. Every extension is a standalone plugin rather than an embedded child, so each manages its own frame, settings schema, and Edit Mode entry while the parent frame plugin governs whether it is enabled.

## Implementation
Three unit directories (`Player/`, `Target/`, `Focus/`), each with its own XML bundle setting load order. Every file registers its own plugin via `Orbit:RegisterPlugin` (e.g. `Orbit_TargetFrame`, `Orbit_FocusCastBar`). Main frames (`PlayerFrame.lua`, `TargetFrame.lua`, `FocusFrame.lua`) mix in `Orbit.UnitFrameMixin` + `VisualsExtendedMixin` + `StatusIconMixin` (player adds `AggroIndicatorMixin`) and create their secure frame through `OrbitEngine.UnitButton:Create` from Core/UnitDisplay. Power bars mix in `Orbit.UnitPowerBarMixin` and cast bars `Orbit.CastBarMixin`, both taking `sharedDefaults` from the mixin. Buffs/debuffs mix in `Orbit.AuraMixin` + `Orbit.UnitAuraGridMixin` and build through `CreateAuraGridPlugin`; `PlayerBuffs.lua` reuses Blizzard's `BuffFrame` buttons (`useBlizzardButtons`, `NativeFrame:KeepAliveHidden`). ToT/ToF use `Orbit.SecondaryUnitFrameMixin`. `Player/` additionally owns the class resource bar (`PlayerResources.lua` with `ContinuousBarRenderer.lua` / `DiscreteBarRenderer.lua` strategies, constants and settings split into their own files).

Sub-frame enablement is parent-owned: each sub-plugin's `IsEnabled()` reads the parent frame plugin's setting via `Orbit:ReadPluginSetting` (e.g. `Orbit_FocusFrame` → `EnableDebuffs`); `PlayerBuffs` is always enabled.

## Gotchas
- Player/Target/Focus share the structural template but drift exists (`Player/` has the resource/renderer subsystems). Adding a feature to one — check whether all three need it.
- Declare schema defaults inline in the `defaults = { … }` block passed to `RegisterPlugin`. Never edit `DefaultProfile.lua` — it is a saved-layout snapshot owned by ProfileManager, not the plugin-schema default site.
- New cast bars must use `CastBarMixin`. Known divergence: `PlayerCastBar.lua` (and `BossFrameCastBar.lua`) predate the rule and reimplement the update loop — tracked technical debt, don't copy them.
- `PlayerBuffs` sets `SetCVar("buffDurations", 0)` on load and restores it on logout/disable — Blizzard's own duration text would double up with Orbit's.
- Target/focus frames must handle rapid unit changes gracefully (no stale data flash).
- Shared behavior belongs in Core/UnitDisplay mixins, not duplicated per unit.

## Secrets
Health/power values flow only into StatusBar sinks via the Core/UnitDisplay mixins. `ContinuousBarRenderer.lua` is the model: mana color resolves through `UnitPowerPercent` with a native ColorCurve (`OrbitEngine.ColorCurve:ToNativeColorCurve`, gated by `SecretValueUtils.CanUseUnitPowerPercent`, called under pcall as a throwing C API); all other progress math is guarded with `issecretvalue(current/max)` before any division. Cast bar and resource coloring are ColorCurve-driven (`*ColorCurve` settings keys), never Lua arithmetic on unit values.

## References
- `Core/UnitDisplay/` — `UnitButton`, `UnitFrameMixin`, `UnitPowerBarMixin`, `CastBarMixin`, `AuraMixin`, `UnitAuraGridMixin`, `SecondaryUnitFrameMixin`.
- `Plugins/BossFrames/` — the other cast-bar reimplementation named in the tech-debt note.
- Skills: `/wow-secrets` (curves, `UnitPowerPercent`), `/wow-filters` (buff/debuff filtering), `/wow-frames` (secure unit buttons).
