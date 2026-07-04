# UnitDisplay

## Description
Shared mixins for every unit frame type — player, target, focus, party, raid, boss: health/power/cast bars, auras, indicators, group headers, and their canvas previews.

## Purpose
Any behavior shared by two or more unit-frame plugins lives here exactly once. Mixins are feature modules: each owns its behavior plus the config schema and canvas preview for that feature.

## Implementation
| File | Role |
|---|---|
| UnitFrameMixin / SecondaryUnitFrameMixin | base unit frame behavior; target-of-target/focus-target |
| UnitButton.lua + UnitButton/ (Core, Health, Text, Portrait, Prediction, Canvas, PortraitRingData) | secure clickable unit button, split by concern |
| UnitPowerBarMixin / ResourceBarMixin / CastBarMixin | power bars, class resources, cast bars |
| AuraMixin / AuraSnapshotCache / AuraLayout / AuraPreview | aura display, incremental caches, grid math, previews |
| GroupFrameMixin / GroupFrameEventHandler / GroupAuraFilters / GroupCanvasRegistration | party/raid headers, event fan-out, filter rules, canvas registration |
| HealerAuraTicker / PandemicGlow / DispelIndicatorMixin / StatusIconMixin / AggroIndicatorMixin / PrivateAuraMixin | timed/conditional indicators |
| UnitAuraGridMixin / UnitAuraGridReparenting | grid aura display; reparents Blizzard `BuffFrame.auraFrames` into an Orbit grid |
| PreviewAnimator.lua | shared OnUpdate-throttled animator for edit-mode previews; idles when no preview is open |

Aura data flow: `GroupFrameEventHandler` builds a per-event snapshot (`frame._auraSnapshot`) from two `C_UnitAuras.GetUnitAuras` calls (HARMFUL + HELPFUL); every consumer — containers, single icons, healer auras, dispel — reads the snapshot with zero additional C-API fetches. `AuraSnapshotCache` patches per-frame caches incrementally from partial `UNIT_AURA` `updateInfo`. `AuraMixin` skips unchanged rebuilds via a `_auraFingerprint` keyed by aura instance IDs. `HealerAuraTicker` is a singleton 0.05s ticker driving curve-based swipe/timer visuals, self-cancelling when no icons remain.

Health text (`UnitButtonText.lua`): a typed format string (`SetHealthTextFormat`) parsed into segments from `UnitButton.HEALTH_TOKENS` (`%`, `Current`, `CurrentK`, `Max`, `MaxK`, `&` mouseover divider — matched longest-first; Canvas Mode reads the token table for its input tooltip). `ValidateHealthFormat` rejects a second `&` or a token repeated within one side. `""` (blank — renders no value) is distinct from `nil` (falls back to the legacy `HealthTextMode` preset); live frame and Canvas preview key off the same `type(fmt) == "string"` test so they never diverge. Per-component previews fall back to the other `&` side so the component stays selectable; group-frame preview rows pass `noFallback=true` for exact at-rest parity.

## Gotchas
- Mixins are stateless — state lives on the frame. After populating a mixin table, `table.freeze` it (12.0.5+) so a stray write fails loud. A mixin is justified only when two or more plugins share the behavior; never reference a plugin by name.
- Feature-module exception: mixins may render their own settings (`Engine.Config:Render` from `Add*Settings`) and register canvas components (`CanvasMode.CreateDraggableComponent`) — cohesion, not a layering inversion. But "is this frame being canvas-edited" must be read from the shared `Orbit.canvasActiveFrame` flag (published by CanvasMode), never `Engine.CanvasMode:IsActive`/`.currentFrame`.
- Settings-changing call sites (plugin `ApplySettings`) must call `AuraMixin:InvalidateContainerLayout(frame)`, or the fingerprint keeps the stale layout. Read `ComponentPositions` via `plugin:GetComponentPositions` (transaction-aware), never raw `GetSetting`.
- `AuraSnapshotCache:Build` returns one module-wide recycled scratch snapshot — consumers must fully drain it before the next `Build` and never retain a reference past dispatch.
- Status beats value in health text: disconnected shows `PLAYER_OFFLINE`, dead/ghost shows `DEAD` (plain booleans from `UnitIsConnected`/`UnitIsDeadOrGhost`) regardless of the format string, including a blank one.
- Tooltip taint: driving the shared global `GameTooltip` from an Orbit OnEnter poisons it and Blizzard's later secret arithmetic (world-quest POI rewards, progress bars) throws. `UnitButton` sidesteps this by assigning Blizzard's own `UnitFrame_OnEnter`/`UnitFrame_OnLeave` *directly* as the handlers — a Blizzard-defined function runs with secure taint on hardware enter, so the shared tooltip is driven clean AND third-party enhancers (Raider.IO/Leatrix, which bail unless `tooltip == GameTooltip`) still fire. Mouseover highlight rides a `HookScript` so it never touches the tooltip. Never wrap `UnitFrame_OnEnter` in an Orbit closure — that re-taints. Aura icons (`AuraMixin`) can't use this (no Blizzard aura-OnEnter), so they stay on the private `Orbit.Tooltip` (shadow at file top), losing enhancers but taint-free. Crux to re-verify per patch: whether `SetScript` from tainted code keeps the Blizzard handler secure (taintLog); if not, fall back to the shared-global-owned-via-`UIParent` hybrid, then to the private tooltip.
- New files load via `UnitDisplay.xml` (`UnitButton/UnitButton.xml` for the button split) after their dependencies.

## Secrets
`UnitHealth`/`UnitHealthMax` are secret in 12.0: full tokens forward the raw secret to the FontString sink; `CurrentK`/`MaxK` abbreviate via `AbbreviateNumbers` + a cached `CreateAbbreviateConfig` (both accept secrets, unlike Lua arithmetic). `RenderHealthText` combines several secret values through `SetFormattedText` (C-side) — never Lua concatenation, which throws on a secret. `HealerAuraTicker` converts secret remaining time through an identity `C_CurveUtil` curve (`durObj:EvaluateRemainingPercent`) before Lua-side coloring via `Engine.ColorCurve`. `DispelIndicatorMixin`: `aura.dispelName` is secret in encounters, so per-type textures are alpha-driven through `GetAuraDispelTypeColor` per-type curves — `SetAlpha` accepts secrets, so the matching texture wins in C++; the resolved curve is cached on the plugin (`_dispelCurveCache`, invalidated via `InvalidateDispelCurve`).

## References
/wow-secrets, /wow-filters (aura filtering), /canvas-mode (component registration), `Core/Skinning/README.md`, `Core/Shared/README.md` (WhitelistedSpells, glow stack), `agent/wow-ui-source/` (CompactUnitFrame, BuffFrame).
