# Extras

## Description
Small, standalone single-file plugins that do not fit a larger bounded context.

## Purpose
Self-contained HUD features too small to justify their own domain folder. If a file here grows to need siblings, promote it to its own domain directory instead of expanding this folder.

## Implementation
| File | Role |
|---|---|
| TalkingHead.lua | `Orbit_TalkingHead` — reskins and repositions the talking head dialog |
| MinimapButton.lua | `Orbit_MinimapButton` — animated Orbit launcher button |

TalkingHead creates a `UIParent`-parented container and hooks `TalkingHeadFrame_PlayCurrent` once `Blizzard_TalkingHeadUI` loads (immediately if already loaded, otherwise via its own `ADDON_LOADED` watcher). MinimapButton is a standard Edit Mode frame (draggable, layered animated atlases); left-click toggles Edit Mode via `securecall("Show/HideUIPanel", EditModeManagerFrame)` plus the Global options dialog, right-click opens advanced settings, and its single setting is Scale. Both persist position through the standard `OrbitEngine.Frame:AttachSettingsListener` / `RestorePosition` flow and register with `defaults` inline in `RegisterPlugin`.

There is no `Extras.xml` bundle — each file is listed directly in `Orbit.toc`. A new extras plugin means a new `.toc` line.

## Gotchas
- Extras plugins must not depend on other plugins, and must stay one file — promote to a domain directory the moment a second file is needed.
- Schema defaults go in the `RegisterPlugin` `defaults` block, never `DefaultProfile.lua` (that file is a ProfileManager-owned layout snapshot).

## References
- `Plugins/README.md` — full new-plugin checklist.
- Skills: `/wow-frames`.
