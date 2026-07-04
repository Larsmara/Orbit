# MenuItems

## Description
Plugins for Blizzard's native utility bars: micro menu, bag bar, and queue status indicator.

## Purpose
Captures Blizzard's native buttons into Orbit containers so they gain Orbit positioning, scaling, and fade behavior without reimplementing the buttons themselves. All three mix in `Orbit.NativeBarMixin` (Core/Plugin) for shared scale, capture, and mouseover-fade helpers.

## Implementation
| File | Role |
|---|---|
| MicroMenu.lua | `Orbit_MicroMenu` ("Menu Bar") — captures micro menu buttons; Scale/Padding/Rows layout |
| BagBar.lua | `Orbit_BagBar` — captures bag slot buttons; Scale/Orientation/Direction |
| QueueStatus.lua | `Orbit_QueueStatus` — repositions the queue status eye |

MicroMenu captures the children of Blizzard's `MicroMenu` via `NativeBarMixin:CaptureFromNativeParent` at load and hooks `MicroMenu.AddButton` with `hooksecurefunc` to capture buttons Blizzard adds later. QueueStatus stubs out `MicroMenuMixin.UpdateQueueStatusAnchors` so Blizzard stops re-anchoring the eye. All three follow the standard plugin flow: `defaults` in `RegisterPlugin`, position via `OrbitEngine.Frame:AttachSettingsListener`/`RestorePosition`, opacity via `OOCFadeMixin` and `ApplyMouseOver`.

## Gotchas
- Button capture must null-check before reparenting — some buttons don't exist in all game modes. `CaptureFromNativeParent` bails and sets `self.conflicted` when another addon has already claimed the native container.
- Hover fade uses the implicit hover pattern — `Orbit.Animation:ApplyHoverFade` polls `MouseIsOver` geometry on a throttled `OnUpdate` — not native mouse enter/leave events, so it works across captured children without per-button scripts.
- QueueStatus sets its Edit Mode frame level to 50 (selection renders at level+100) so its selection overlay beats the minimap's.
- `Performance` and `CombatTimer` moved to the Datatexts plugin as free-floating datatexts — don't rebuild them here.

## References
- `Core/Plugin/NativeBarMixin.lua` — capture, scale, and mouseover helpers all three plugins rely on.
- `Plugins/Datatexts/README.md` — destination of the migrated datatexts.
- Skills: `/wow-frames`.
