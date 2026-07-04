# LibOrbitColorPicker-1.0

## Description
Standalone LibStub color picker with a gradient bar, drag-and-drop pins, class-color and recent-color swatches, and a built-in guided tour. Supports single-color and multi-color (gradient) modes. Orbit-authored — editable, not vendored.

## Purpose
Gives every Orbit consumer one picker for both static colors and progress-mapped color curves (health bars, timer text), instead of Blizzard's single-color `ColorPickerFrame`.

## Implementation
A caller passes saved data into `lib:Open(options)`; the picker edits a pin list; the callback returns the result. Data flow: `initialData` (`{ pins = ... }` curve table or plain `{ r, g, b, a }`) → internal pin list → `C_CurveUtil.CreateColorCurve()` rebuilt on every pin change → `callback(result, wasCancelled)` fired on each change and on close.

| API | Does |
|---|---|
| `lib:Open(options)` | open with `initialData`, `forceSingleColor`, `hasDesaturation`, `recentColorsDb` (array ref enabling the 8-slot history row), `callback(result, wasCancelled)`, `onOpen(picker)` (fires after deferred init — consumers hook it for first-open tours), `anchor` (`{ frame, point, relativePoint, x, y }`; default fixed top-left of screen) |
| `lib:IsOpen()` | true while the picker frame is shown |
| `lib:GetColorCurve()` | last built native ColorCurve, or nil |
| `lib:StartTour()` / `EndTour()` / `ToggleTour()` | 6-stop guided tour (also on the top-left info button) |

Callback result: apply with pins → `{ curve = <native ColorCurve>, pins = { { position = 0..1, color = {r,g,b,a}, type = "class"? } }, desaturated = bool? }` (`desaturated` only when `hasDesaturation` was set); clear all pins → `nil`; cancel (escape / close) → the pre-edit snapshot with `wasCancelled = true`.

Modes: `forceSingleColor = true` keeps exactly one pin (swatch drags replace it); multi-color allows unlimited pins — drag swatches onto the bar to add, drag handles to move, right-click to remove, arrow keys nudge (shift = fine).

## Gotchas
- **Persist `pins` (and `desaturated`), never `curve`** — `curve` is a transient native object rebuilt from pins on each open, a convenience for immediate use only. Reopen by passing the saved `{ pins = ... }` back as `initialData`.
- Branch on `wasCancelled` and discard the cancel payload; the picker has already rolled its own state back, including the recent-colors history (recents commit only on apply).
- Clearing all pins delivers `nil` — every consumer must supply its own default-color fallback.
- `type = "class"` pins resolve to the player's current class color. In single-color mode a manual edit (wheel, value slider, hex) demotes the pin to a plain color so the picked value is honored verbatim; an alpha-only change does not demote (class pins render at full alpha).
- Entering combat closes the picker as a cancel (`PLAYER_REGEN_DISABLED`) because `SetPropagateKeyboardInput` is protected in combat; a picker opened during combat runs keyboard-disabled until `PLAYER_REGEN_ENABLED`.
- The tour tooltip frame is lazy-built on first `StartTour()` — non-tour users pay zero cost at file load.
- All UI strings (labels, tooltips, tour) live in the `CP_LOCALE` table at the bottom of `LibOrbitColorPicker-1.0.lua`, resolved once at file load via `GetLocale()` — 9 languages (enUS/enGB, deDE, frFR, esES/esMX, ptBR, ruRU, koKR, zhCN, zhTW). Extend by adding keys to every locale block.
- `checkerboard.tga` (alpha preview) is located via `debugstack` path matching — renaming the library directory breaks it.

## References
- `LibOrbitColorPicker-1.0.lua` / `.xml` — the whole library; `LICENSE` (MIT).
- Depends on `LibStub` only. Load with the silent flag: `LibStub("LibOrbitColorPicker-1.0", true)`.
- Orbit consumers sample curves via `OrbitEngine.ColorCurve:SampleColorCurve()`.
