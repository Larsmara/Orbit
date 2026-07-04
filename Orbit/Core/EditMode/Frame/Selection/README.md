# Selection

## Description
Interaction handlers for selected Edit Mode frames — drag, nudge, resize, and the selection tooltip.

## Purpose
Once a frame is selected (overlay wired in `../Selection.lua`), these files translate mouse and keyboard input into position/anchor/size changes and hand off to the anchor graph (`../Position/Anchor.lua`) and persistence.

## Implementation
| File | Role |
|---|---|
| AnchorLines.lua | `Engine.AnchorLines` gradient edge-bar renderer (`Ensure/ShowOn/Hide`); shared by selection overlays and the datatext snap preview (`Plugins/Datatexts/BaseDatatext.lua`) |
| Drag.lua | drag-to-move, mouse-down selection, mouse-wheel padding; owns the drag lifecycle |
| Nudge.lua | arrow-key pixel nudge |
| Resize.lua | drag-to-resize handle; writes width/height settings (square mode for aspect-locked frames) |
| Tooltip.lua | selection position/anchor tooltip |
| PeekHide.lua | transient hide of the selection overlay during tooltip peek |

Drag lifecycle (`Drag.lua`): all transient state lives in one table, `parent._drag`, created in `OnDragStart` and destroyed in `OnDragStop`. The move primitive is `BeginMove` → `UpdateMove` → `EndMove`; drag stop is a thin orchestrator over `TeardownDrag` (unconditional visual/state teardown) → `ResolveDrop` (snap detection, returns a decision table `kind = "anchor" | "free" | "precision"`) → `CommitDrop` (applies the decision and persists via the drag callback).

## Gotchas
- `parent.orbitIsDragging` stays a plain frame flag outside `_drag` because external code reads it: `../Position/Persistence.lua` refuses to reposition a mid-drag frame, and the tooltip and onboarding tour read it too.
- Manual-move fallback: `BeginMove` calls WoW's `StartMoving`; if the frame fails to re-latch a follow point (`GetNumPoints() == 0` — an Orbit rounded-corner `MaskTexture` bound onto the frame can cause this), it clears WoW's moving state and tracks the cursor by hand (`drag.manual`). Don't assume native move always works.
- Combat handling is two-tier: `TeardownDrag` + `EndMove` always run; only the position commit (`BreakAnchor` + `ResolveDrop`/`CommitDrop`) is combat-guarded. Blocking teardown would leave a stuck overlay.
- Fail-safe: `OnDragStart` snapshots the resolved position into `drag.restorePoint`; if the drop can't resolve a position the frame restores there instead of dumping to screen origin.
- `OnDragStop` can fire without a matching `OnDragStart` — every `parent._drag` field is optional.
- New drag-internal state goes in `parent._drag`, never as loose fields on the frame or overlay. The move primitive owns `StartMoving`/`StopMovingOrSizing` — never call those WoW methods from the drag handlers.
- `Drag.lua` also owns the Blizzard snap-preview tap-in (shim methods + `SetSnapPreviewFrame`); see `../../README.md` for why it is one-way and taint-free.

## References
`../../README.md` (Edit Mode data flow, grid tap-in) · `../Position/README.md` (anchor graph, persistence) · skills: `/pixel`, `/wow-frames`.
