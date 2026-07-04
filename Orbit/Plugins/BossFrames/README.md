# BossFrames

## Description
Unit frames for boss encounters (boss1–boss5) with health, power, cast bars, auras, and raid markers.

## Purpose
Boss display during encounters, built on the shared unit display stack (`UnitButton`, `UnitFrameMixin`, `AuraMixin`, `StatusIconMixin` from Core/UnitDisplay) so it stays a thin composition rather than a parallel unit-frame implementation.

## Implementation
| File | Role |
|---|---|
| BossFrame.lua | plugin (`Orbit_BossFrames`); frame creation, events, settings, aura containers |
| BossFrameCastBar.lua | per-frame cast bar creation and update |
| BossFrameHelpers.lua | `AnchorToPosition` helper shared with the canvas aura preview |
| BossFramePreview.lua | canvas mode previews |

`OnLoad` eagerly creates all `MAX_BOSS_FRAMES = 5` frames via `OrbitEngine.UnitButton:Create` (secure targeting). Per-unit data arrives through `RegisterUnitEvent` — `UNIT_HEALTH`/`UNIT_MAXHEALTH` plus absorb/heal-prediction events feed the health StatusBar, `UNIT_POWER_*`/`UNIT_DISPLAYPOWER` the power bar, `UNIT_AURA` the buff/debuff containers via `UpdateAuraContainer`. A separate event frame listens for `INSTANCE_ENCOUNTER_ENGAGE_UNIT`, `PLAYER_REGEN_DISABLED/ENABLED`, and `UNIT_TARGETABLE_CHANGED` to drive how many frames show (all 5 in Edit Mode/preview). Cast bars register `UNIT_SPELLCAST_*` per unit. Aura containers are canvas-draggable via `ComponentDrag` with `MakeAuraPositionCallback`; all settings flow through the standard `defaults` block and `ApplySettings`.

## Gotchas
- `BossFrameCastBar.lua` predates the consolidation rule and reimplements the cast-bar update loop instead of using `CastBarMixin`. This is tracked technical debt: new cast bars MUST use `CastBarMixin`; do not extend the reimplementation with features that belong in the mixin.
- The boss cast bar uses the unified border pattern (one border wrapping icon + bar via `UpdateBarInsets`) matching target/focus in `Skin.CastBar` — keep it in sync with that style.
- Frames are allocated eagerly, never on demand; the aura preview must share `BossFrameHelpers:AnchorToPosition` with the live path for canvas parity.

## Secrets
Health and power values flow straight into StatusBar sinks (`SetMinMaxValues`/`SetValue`) with no Lua arithmetic. Cast timing uses duration objects passed to `SetTimerDuration`, and the timer text is driven by a per-cast `C_CurveUtil` curve mapping remaining% → remaining seconds so the `OnUpdate` never does arithmetic on secret `startMs`/`endMs`. `UnitCastingDuration`/`UnitChannelDuration` are called through `pcall` as throwing C API boundaries.

## References
- `Core/UnitDisplay/` (UnitButton, UnitFrameMixin, CastBarMixin, aura mixins) and its README.
- `Plugins/UnitFrames/README.md` for the target/focus cast bar style this mirrors.
- Skills: `/wow-secrets` (curves, duration objects), `/wow-frames`, `/wow-filters` (aura display).
