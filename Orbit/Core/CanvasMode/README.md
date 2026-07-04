# CanvasMode

## Description
Orbit's intra-frame component editor: a dialog (opened by double-clicking a frame in Edit Mode) that renders a frame's internal components (text, icons, auras, cast bars) as draggable previews with per-component overrides, dock/undock, and viewport zoom.

## Purpose
Edit Mode positions whole frames; Canvas Mode designs *inside* one frame. It stays plugin-agnostic — any plugin opts in with `Plugin.canvasMode = true` and the standard settings contract below.

## Implementation
Edits are buffered in `SettingsTransaction.lua` (`Begin/Set/SetPosition/Rollback/Clear` — there is no commit step). Each edit fires `ORBIT_CANVAS_SETTINGS_CHANGED` on the EventBus so live/preview frames update without touching SavedVariables (`PluginMixin` resolves the active transaction inside `GetSetting`). Apply (`DialogActions.lua`) writes settings directly via `plugin:SetSetting`, clears the transaction, and triggers `ApplySettings` on live frames and Edit Mode previews in one pass; Cancel/ESC rolls the transaction back.

Entry: `CanvasEdit.lua` (`Enter/Exit/Toggle`, gated on `frame.orbitPlugin.canvasMode == true` and not `frame.disableCanvasMode`; `EditMode.Exit` force-exits). `Dialog.lua`/`Viewport.lua` own the window, tab filtering, zoom/pan, and the sync toggle; `CanvasModeDrag.lua` + `ComponentRegistry.lua` + `ComponentHandle.lua` own component drag; `SnapEngine.lua`/`SmartGuides.lua` own snapping and guide lines; `Dock.lua` is the disabled-component dock; `ComponentSettings*.lua` is the per-component override panel (schema, widgets, previews); `Creators/Registry.lua` + per-type creators build draggable previews; `IconCanvasPreview.lua` builds icon-grid previews (Tracked, CooldownManager); `OverrideUtils.lua` is the override read/write door.

Settings contract, per `systemIndex`: `ComponentPositions` (`{[key] = {anchorX, anchorY, offsetX, offsetY, justifyH, posX, posY, baseSize?}}`), `DisabledComponents`, and — for `supportsGlobalSync` plugins — `UseGlobalTextStyle`, `GlobalComponentPositions`, `GlobalDisabledComponents` written to systemIndex 1. Per-component style overrides flush via `ComponentSettings:FlushPendingPluginSettings()`.

Plugin onboarding (full walkthrough: `canvasmode.md` / the `/canvas-mode` skill): 1) `Plugin.canvasMode = true`; 2) the plugin's `ApplySettings` consumes positions via `PositionUtils.ApplyTextPosition` or equivalent; 3) optional `defaults.ComponentPositions`/`DisabledComponents` (or dynamic `GetDefaultComponentPositions/GetDefaultDisabledComponents` for context-scoped defaults like GroupFrames per-tier) to power "reset positions"; 4) only for a new component type: a creator in `Creators/` plus a `DetectCreatorType` entry in `CanvasModeDrag.lua` when structural duck-typing can't identify it. Optional: `canvasPreviewText`/`GetCanvasPreviewText` for worst-case preview strings. `PluginMixin` already provides `OnCanvasApply`, `IsComponentDisabled`, `GetComponentPositions` — override only the first two, never the third. Component keys are PascalCase with dot-notation sub-components (`CastBar.Timer`).

## Gotchas
- During a live drag only the edge-magnet applies (components glide 1:1); the 2 px grid quantization and final anchor resolution run once on release via `FinalizeComponentPosition`. Never re-introduce grid snapping into the per-frame `DragUpdate` path. Snap constants live only in `SnapEngine.lua`. Drag functions are hot — no allocations, no string concat.
- Selection feedback is the shared flat outline (`Skin:ApplySelectionOutline`, states drag > selected > hover), not a fill and not the themed highlight border — a fill washes out the glyph and exposes container/glyph size mismatches as off-center margins. The datatext drawer-active highlight uses the same primitive so the two read identically.
- Text components are sized to the *measured* glyph (re-measured one frame after creation via `C_Timer.After(0)` + `ReanchorContainer`), never a char-count estimate, so the snap collision box matches the glyph; visual margin comes from marker overshoot, grab area from `SetHitRectInsets`.
- `baseSize` in a position record exists only for icon previews with `preview.scalesTextWithSize` (set by `IconCanvasPreview`) — it lets `PositionUtils.ApplyTextPosition` scale text offsets by `currentIconSize / baseSize`. All other components omit it and keep fixed-pixel offsets; do not add it broadly or existing layouts shift.
- The generic `ApplyStyle` models only font/size/color. Overrides that change *content* (DamageMeter number format) are handled by the plugin's own preview via `container.ApplyCustomOverride(key, value, overrides)` — canvas core stays plugin-agnostic.
- The health-format text box (`formatinput` control) reads its tokens/validator from `OrbitEngine.UnitButton` (`HEALTH_TOKENS`, `ValidateHealthFormat`, `LegacyHealthModeToFormatString`) — UnitDisplay owns the canon; canvas only renders it. Existing users are seeded from legacy `HealthTextMode` without rewriting saved data.
- Canvas code may depend on Edit Mode infrastructure (`HandleCore`, `Pixel`), never on specific plugins; the dialog must render correctly whichever plugin is active. Dock/dialog color constants at file top.

## Secrets
Preview creation reads geometry and text off *live* frames, which can carry secrets in 12.0+: `ComponentHelpers.lua` and `Creators/Registry.lua` filter size/position reads through `issecretvalue` before any comparison; `FontStringCreator.lua` drops secret `GetText()` values (a live FontString may hold `SetText(UnitName(unit))` output); `ComponentHandle.lua` and `TextureCreator.lua` substitute fallbacks for secret dimensions/sprite indices. Guard *before* the operation, never after.

## References
`canvasmode.md` (onboarding walkthrough) · `../EditMode/README.md` (entry delegation, HandleCore) · `../UnitDisplay/` (health-format tokens) · skills: `/canvas-mode` (creator registry), `/wow-secrets`, `/pixel`.
