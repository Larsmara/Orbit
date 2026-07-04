# Infrastructure

## Description
Low-level services the entire addon depends on: event dispatch, pixel math, combat-state deferral, error trapping, and async scheduling. No knowledge of plugins, skinning, or config UI.

## Purpose
The foundation layer — everything above it (rest of Core, Plugins, sub-addons) builds on these primitives. May depend only on `Core/Shared/` and libs.

## Implementation
| File | Role |
|---|---|
| EventBus.lua | pub/sub wrapping WoW events and custom `ORBIT_*` events |
| Pixel.lua | pixel-snapping math (`Snap`, `Multiple`); fires `ORBIT_DISPLAY_SIZE_CHANGED` on scale change |
| CombatManager.lua | combat-state tracking; `QueueUpdate(callback)` defers protected work until regen |
| ErrorHandler.lua | `Wrap` at trust boundaries; failures print to chat and ring-buffer (max 50) into `OrbitErrorLogDB` |
| Async.lua | keyed `Debounce` / `Throttle` schedulers |
| Animation.lua | hover fade only: `ApplyHoverFade` / `StopHoverFade` |
| KeybindSystem.lua | keybind resolution for action bar buttons and tracked abilities |
| TickMixin.lua | tick-mark overlays for status bars (recharge segments) |
| StrataEngine.lua | root-container frame-level allocation (`GetFrameLevel`, `PopulateDefaults`) |
| HealerAuraRegistry.lua | class/spec healer aura slot registry |
| Profiler.lua | opt-in CPU profiler (`Begin`/`End`; Spotlight → Tools → Performance Profiler) |

New systems attach to `Orbit.Engine` or `Orbit` and load via a `<Script>` entry in `Infrastructure.xml` in dependency order — never listed in the `.toc`.

## Gotchas
- `OrbitErrorLogDB` is a separate SavedVariable from `OrbitDB` on purpose — a corrupt error log cannot take down user settings. Don't merge them.
- Nothing here may reference a plugin, skinning module, or config widget; this module loads before everything except Shared and libs.
- `CombatManager:QueueUpdate` has a queue-size cap and logs an error when hit — it is a combat-deferral valve, not an unbounded work queue.
- StrataEngine allocates root-container Z-index only (no scope-level bump controls); a new plugin adds itself to `PopulateDefaults()` and calls `GetFrameLevel("Global_HUD", "Orbit_PluginName")` in OnLoad. Entity ordering is profile-persisted; only `_volatileBase` is session-only.
- Animation.lua is deliberately scoped to hover fade — nothing else.
- Systems are stateless or own explicit init/teardown; prefer `EventBus:Fire` over direct cross-system calls; no UI frame creation beyond internal event frames.

## References
`Core/Shared/README.md`, `CLAUDE.md` (pcall policy, error-handling boundaries), /pixel (Snap vs Multiple), /wow-frames.
