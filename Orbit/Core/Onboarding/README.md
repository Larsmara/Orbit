# Onboarding

## Description
First-run experiences: the welcome dialog (keybind setup) and the Edit Mode tour — an anchoring playground with sequential task-gated stops — plus the post-tour feature hints.

## Purpose
Teaches new users Edit Mode, Canvas Mode, and the datatext drawer using Orbit's real controls: the playground is a genuine plugin whose frames open the standard settings dialog, so nothing learned is fake.

## Implementation
- `WelcomeDialog.lua` — shown `SHOW_DELAY` after `PLAYER_LOGIN`, gated on `AccountSettings.WelcomeComplete` (set on dismiss; `WhatsNew` self-suppresses on fresh installs so this fills the first-run slot). "Set Keybinds" opens `OrbitWelcomeKeybinds`, whose capture mirrors Blizzard's KeybindListener (`GetConvertedKeyOrButton` → `IsKeyPressIgnoredForBinding` → `CreateKeyChordStringUsingMetaKeyState` → `SetBinding` → `SaveBindings`). `ApplyDefaultBinds` (idempotent, only binds unbound actions) seeds Spotlight → `NUMPADMINUS` (fallback `SHIFT-=`) and HUD Map → `NUMPADPLUS` (fallback `SHIFT--`). It references only binding action strings (`ORBIT_SPOTLIGHT_TOGGLE`, `ORBIT_MINIMAP_TOGGLEVIEW`), never the modules — inward-only dependencies hold. "Start Tour" enables once the keybind box closes, then calls `Tour:OpenAndStart()`.
- `TourPlugin.lua` — registers `"Orbit_Tour"` via the real `Orbit:RegisterPlugin`, frames via `FrameFactory:Create`, settings via `SchemaBuilder`.
- `EditModeTour.lua` — dark overlay + 9 sequential stops (`TOUR_EM_STEP1..9`) with task-gated Next buttons, drag/anchor/nudge tracking, and snap isolation. `StartTour` sets `AccountSettings.TourComplete` on entry (no re-trigger across reloads); Spotlight's "Replay the Tour" force-starts past the flag. `OpenAndStart` opens Edit Mode via `securecall("ShowUIPanel", EditModeManagerFrame)` and defers `StartTour` by `EDIT_MODE_OPEN_DELAY` so entry can build the frame selections; it is combat-guarded. Ending the tour (Done or early Exit) flips both hint flags `nil → false` (pending).
- Hints: the Canvas Mode hint (above PlayerFrame) shows on EditMode.Enter while pending and is cleared by `Engine.CanvasMode:Toggle`; the Datatext Drawer hint (screen TOPLEFT) is a main-screen hint — shows on EditMode.Exit, hides on Enter — cleared by opening the drawer, and suppressed (still pending) while the Datatexts plugin is disabled. Both re-show until cleared (`CanvasHintComplete`/`DrawerHintComplete`).

## Gotchas
- NEVER `:Hide()`, `HideUIPanel(EMF)`, or `CheckHideAndLockEditMode` to suppress EditModeManagerFrame during the tour — all three fire `OnHide` → `OnEditModeExit` → `ResetPartyFrames` → tainted `CompactUnitFrame_UpdateHealthColor` (secret-value compare crash, 12.0.5+). Hide it visually with `SetAlpha(0)` + `EnableMouse(false)` and restore on tour end. Actually exiting Edit Mode (the tour-exit dialog) goes through `securecall("HideUIPanel", EditModeManagerFrame)` — never a bare call.
- All onboarding UI — overlay, playground frames, selection overlays, settings dialog, tooltips — sits at `TOOLTIP` strata during the tour. Save each frame's original strata/level on start and restore on end. An OnUpdate poller re-elevates every tick because other systems (DeselectAll, UpdateVisuals, dialog open/close) keep resetting strata.
- ESC handling is per-frame `OnKeyDown`, not `UISpecialFrames`. The tour overlay consumes ESCAPE (shows `OrbitTourExitDialog`; other keys propagate so arrow nudging works). The welcome dialog deliberately swallows ESC — it closes only via Start Tour or the X; the keybind box closes on ESC except mid-capture, where the listening button consumes it to cancel.
- Snap isolation: playground frames snap only to each other via a `GetSnapTargets` override for the tour's duration.
- Never destroy `Selection.selections`, `dragCallbacks`, or `selectionCallbacks` for tour frames — the factory owns them; hide/show the overlays instead.
- EMF OnShow/OnHide hooks for hint lifecycle install once at module load; `originalCanvasToggle`/`originalDrawerToggle` upvalues guard against stacking the per-feature Toggle hooks across re-shows.
- No custom settings UI: playground frames open the real `OrbitSettingsDialog` with standard `SchemaBuilder` controls.
- The numpad default-bind fallback is a conflict heuristic, not numpad detection — no API can detect a physical numpad.

## References
`Core/EditMode/README.md` (loads after `EditMode.xml`; needs `FrameSelection`, `FrameAnchor`, `SelectionResize`, `FrameFactory`), `Core/Config/README.md` (settings dialog), `Orbit/Localization/README.md` (`TOUR_` keys), /wow-frames (taint-safe Blizzard frame handling).
