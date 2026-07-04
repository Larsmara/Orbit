# Minimap

## Description
Reparents Blizzard's `Minimap` render surface into a clean Orbit container, strips the default chrome, and exposes every satellite element (zone text, clock, coords, zoom, tracking, compartment drawer, reparented Blizzard indicators) as an individually positionable Canvas Mode component. Also offers an alternate full-screen HUD view (splatter mask, toggled via the `ORBIT_MINIMAP_TOGGLEVIEW` key binding).

## Purpose
Gives the minimap Orbit's border/backdrop system, shape choice (square / round / splatter), and free component placement — none of which Blizzard's `MinimapCluster` layout allows. Canvas Mode is the single source of truth for component visibility and position; there are no per-component settings checkboxes.

## Implementation
`MinimapCapture.lua` captures `Minimap`/`MinimapCluster` on load: hides the cluster via `OrbitEngine.NativeFrame:Hide(cluster, { unregisterEvents = false, clearScripts = false })`, strips compass/border/zone-button/tracking art, reparents `InstanceDifficulty`, `MailFrame`, `CraftingOrderFrame`, and `ExpansionLandingPageMinimapButton` into the overlay, and installs FrameGuard so foreign code can't steal the surface. `MinimapComponents.lua` creates and updates the Orbit-authored components (Clock, Coords, ZoneText, ZoomButtons, CalendarInvites) and resolves shape/mask (`MinimapConstants.lua` — `Orbit.MinimapConstants`, single source for SYSTEM_ID, sizes, mask paths, `BORDER_RING_OPTIONS`). `MinimapCompartment.lua` collects LibDBIcon + legacy minimap buttons into a hover-reveal drawer. `Minimap.lua` orchestrates: plugin registration (`Orbit_Minimap`, `canvasMode = true`), `ApplySettings()` sizes the container, skins the border, restores canvas positions via `OrbitEngine.ComponentDrag`, applies per-component font/size/color overrides via `OrbitEngine.OverrideUtils`, and re-captures the surface if a reload left it parented elsewhere. `MinimapSettings.lua` builds the settings UI.

Defaults carry per-component `ComponentPositions` and `DisabledComponents`; click actions (left/middle/right) are configurable, plus `View`/`Hud_*` keys for the HUD view.

## Gotchas
- FarmHud compatibility is deliberate and load-bearing: on FarmHud show, `FrameGuard:Suspend` releases the SetParent snap-back so FarmHud may own the surface; `_farmHudActive` gates the surface sync and the recapture check inside `ApplySettings` (mount/shapeshift visibility events would otherwise fight FarmHud's layout). `RegisterForeignAddOnObject` tells FarmHud about our container. FarmHud may load after Orbit — the hook is deferred.
- The compartment anchors to our container, not the `Minimap` surface — FarmHud reparents the surface away from our frame.
- The square shape inherits the global Border Style and its colour; the per-minimap `BorderColor` control only appears for round shapes whose Border Ring draws a tinted element (`blizzard` / `round` / `void`). A rounded global border style draws rounded corners the flat square `SetMaskTexture` surface can't follow — those corners stay square. Don't "fix" this by masking; it's a render-surface limit.
- Difficulty icon mode and text mode are separate internal canvas components (`DifficultyIcon` / `DifficultyText`), each with its own bounds and saved position — one component switching between two geometries broke preview sizing/alignment.
- `MASK_ROUND` clips minimap, HybridMinimap, background, and border to the same pixel-identical circle asset; keep them on the shared mask or edges drift.
- The cluster is hidden with events and scripts intact (`unregisterEvents = false`) — reparented indicators still rely on Blizzard's own event wiring.
- Live-toggle is supported (enable/disable without reload); the drag-resize handle drives the `Size` setting clamped to the slider's 100–400 range.

## References
- `Core/Canvas/` (`/canvas-mode` skill) — component drag, overrides, previews.
- `OrbitEngine.NativeFrame`, `OrbitEngine.FrameGuard`, `OrbitEngine.ComponentDrag`, `OrbitEngine.OverrideUtils` in `Core/`.
- Blizzard source: `agent/wow-ui-source` `Blizzard_Minimap/Minimap.xml` (cluster layout, 215x226 border anchoring quirk noted in `MinimapConstants.lua`).
- Skills: `/canvas-mode`, `/wow-frames`, `/pixel`.
