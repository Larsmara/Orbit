# Skinning

## Description
The visual rendering pipeline: borders, masks, status-bar textures, fonts, gradients, icon skinning, cast/class bars, action buttons. Transforms settings into pixels.

## Purpose
Plugins never build visual elements directly — they call `Orbit.Skin` methods, so every frame renders identically from the one theme (`Orbit.db.GlobalSettings`, read via `Orbit:GetTheme` / `Skin:ResolveStyle`).

## Implementation
| File | Role |
|---|---|
| Skin.lua | border/mask core: `SkinBorder`, `CreateBackdrop`, style + tint resolution, mask registry, LSM border reconciliation |
| StatusBarSkin.lua | `SkinStatusBar`, `AddOverlay`, `ApplyAbsorbTexture`; `OVERLAY_RENDER` blend/tile map |
| FontSkin.lua | outline/shadow from GlobalSettings: `GetFontOutline/Shadow`, `ApplyFontShadow`, `SkinText`, `ApplyUnitFrameText` |
| GradientBackground.lua | paints the `UnitFrameBackdropColourCurve` onto `.bg` (gradient) or resolves it flat (`GetBackgroundColor`) |
| HighlightBorder.lua | tinted overlay for aggro/selection/dispel; respects group-border merge state |
| SelectionOutline.lua | flat pixel outline (`ApplySelectionOutline`); `Skin.SELECTION_ACCENT` shared by Canvas selection + datatext drawer |
| GroupBorder.lua | border merging for anchored frames at zero padding; `SuspendMergeGroup`/`ResumeMergeGroup` |
| Icons.lua / IconLayout.lua / IconMonitor.lua | icon skinning, grid math, visibility-driven relayout |
| CastBar.lua / ClassBar.lua / ActionButtonSkinning.lua / Masque.lua / VisualsExtendedMixin.lua | cast bars, class power, action buttons, Masque bridge, rare/elite badges |
| MediaValidation.lua | `IsMediaFileValid` via `C_UIFileAsset.IsKnownFile` (12.0.7+; returns true on older clients) |

Border pipeline: `ResolveStyle("BorderStyle"/"IconBorderStyle")` maps the theme key to a styleEntry — `nil` for the flat built-in `"orbit"` style and unresolved LSM borders, `{ edgeFile }` for `lsm:` borders (drawn by `ApplyNineSliceBorder`, sized by the `BorderEdgeSize`/`BorderOffset` sliders), or a slice entry `{ edgeFile, mask, sliceMargin, rounded = true }` (via `Constants.BorderStyle.Rounded`) for `"orbit-soft"/"orbit-rounded"/"orbit-rounder"`. `SkinBorder` dispatches to flat pixel backdrop / edge-file / `ApplyRoundedBorder`. Tint resolves through `ResolveBorderTint` (`BorderColor`/`IconBorderColor`); an explicit `color` arg to `SkinBorder` overrides on all three paths (e.g. the gold bonus loot-roll border).

Rounded mask system: frames register their fill/bg/icon textures via `RegisterMaskedSurface(frame, tex)` (~24 sites). Under a rounded style, `ApplyRoundedBorder` renders the slice border on an inset overlay and attaches a shared `SetTextureSliceMargins` mask to every registered surface; `GroupBorder` masks the merged bounding box so a merge group rounds only its four outer corners, restoring per-frame masks on un-merge. Flat and LSM styles clear stale masks. `GetRoundedSwipeTexture` feeds Orbit-built cooldown swipes so they round too.

Group borders merge on a debounced `ORBIT_BORDER_LAYOUT_CHANGED` listener; Edit Mode `Drag.lua` calls `SuspendMergeGroup`/`ResumeMergeGroup` so groups un-merge for the duration of a drag. `ApplyIconGroupBorder` wraps an icon container in one border when Icon Padding = 0 (per-icon nine-slice is skipped).

## Gotchas
- A `nil` styleEntry is the pipeline-wide "flat pixel border" signal — `SkinBorder`'s flat path, `GroupBorder.isPixelMode`, `HighlightBorder`'s pixel path, and `ApplyIconGroupBorder`'s else branch all key on it. Preserve that invariant when adding paths.
- `SkinBorder` clones the style table before setting `.color` — never mutate the shared `Constants.BorderStyle` entries.
- `ResolveBorderTint` nil means "no tint" (`{ none = true }`, the default; set by right-clicking the swatch) — the texture renders its natural art. Any real color, black included, tints. `ResolveBorderColor` still maps none → black for solid fills (pixel WHITE8x8, tick marks) that must have a color.
- Tiled fills (absorb/necrotic patterns) use UV-repeat — `REPEAT` wrap + `SetTexCoord` > 1 — never `SetHorizTile`: WoW cannot corner-mask `SetHorizTile` textures, so they would break under rounded styles. `StatusBarSkin.TILING_FILLS` routes a named texture through the bar's `TiledPattern` this way; it is currently empty (the Orbit absorb textures render as plain stretched fills).
- Blizzard-named cooldowns keep square swipes deliberately (taint); only Orbit-built cooldowns take the rounded swipe texture.
- Rounded styles bake thickness into the texture (no size slider); the flat style is driven by the `PixelBorderSize` slider (0–5, 0 = none).
- Skinning functions are idempotent — same settings twice, same pixels. Pixel-snap only via `Engine.Pixel:Snap`/`Multiple`. Border colors are `{ r, g, b, a }` tables. No frame creation outside this domain except internal overlays/backdrops.
- New files: add to `Skins.xml` after their dependencies; new skin functions accept `(frame, settings)` and return nothing.

## References
/pixel (dimensions, offsets, pixel-perfect rendering), `Core/Shared/Constants.lua` (`BorderStyle`), `Core/Color/README.md` (curve sampling), `Config/Panels/Tabs/GlobalTab.lua` (the style pickers driving this pipeline).
