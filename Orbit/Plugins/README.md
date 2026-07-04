# Plugins

## Description
All Orbit plugins. Each subdirectory is one plugin and one bounded context; `VisibilityManifest.lua` is the single Plugins-layer file allowed to enumerate plugins by name, feeding the Visibility config panel without making Core plugin-aware.

## Purpose
Plugins are the designable feature layer: every plugin exposes a frame the user can move, resize, or restyle in Edit Mode or Canvas Mode. The deciding question is "can the user drag it in Edit Mode?" — yes → here; no → `QoL/`.

| Directory | Plugin |
|---|---|
| ActionBars/ | action bar containers, button layout, text overlays |
| BossFrames/ | boss unit frames (boss1–boss5) |
| CooldownManager/ | Blizzard cooldown viewers, skinned and repositionable |
| CooldownViewerExtensions/ | side-tab registrar for Blizzard's CooldownViewerSettings |
| DamageMeter/ | multi-instance meter on top of `C_DamageMeter` |
| Datatexts/ | free-floating datatexts with corner-triggered drawer |
| Extras/ | standalone one-file plugins (TalkingHead, MinimapButton) |
| GroupFrames/ | party + raid unit frames |
| MenuItems/ | micro menu, bag bar, queue status |
| Minimap/ | minimap replacement with canvas-mode components |
| Objectives/ | reparented, skinned objective tracker |
| RaidPanel/ | raid-leader panel and marker management |
| StatusWidget/ | radial XP/rep/honor/currency orb with toast replays |
| Tracked/ | user-authored tracked ability icons and bars |
| UnitFrames/ | player, target, focus frames and sub-frames |

## Implementation
Lifecycle: Core calls `RegisterPlugin` at load, then `OnLoad()`, then `ApplySettings()`. The config panel calls `AddSettings(dialog, systemFrame)` to build the schema; every `SetSetting` write is followed by the plugin re-running `ApplySettings()`.

New-plugin checklist:
1. Create a directory under `Plugins/` and a main file (`MyPlugin.lua`).
2. Register: `Orbit:RegisterPlugin("My Plugin", SYSTEM_ID, { defaults = { ... }, OnLoad = function(self) ... end })`. Schema defaults live in this `defaults` block and never in `DefaultProfile.lua` — that file is a saved-layout snapshot owned by ProfileManager.
3. Implement `OnLoad()` and `ApplySettings()`.
4. Implement `AddSettings(dialog, systemFrame)`: build a `schema` table, wire tabs with `OrbitEngine.SchemaBuilder:AddSettingsTabs(schema, dialog, tabsList, defaultTab, self)` (returns the active tab), render with `OrbitEngine.Config:Render(dialog, systemFrame, self, schema)`.
5. Add each `.lua` file as a `<Script>` entry in the plugin's `.xml` bundle, dependencies before consumers (Extras has no bundle — its files go directly in `Orbit.toc`).

Settings flow through `PluginMixin` (`GetSetting`/`SetSetting`, spec-scoped `Get/SetSpecData`); position persistence through `OrbitEngine.Frame:AttachSettingsListener` / `RestorePosition`; visuals through `Orbit.Skin`.

## Gotchas
- Plugins may depend on any Core module but never on other plugins. Inter-plugin communication goes through `Orbit.EventBus`, never direct calls. Sole sanctioned exception: `CooldownViewerExtensions:RegisterTab` (see its README).
- Each plugin owns its frames, events, and settings — one bounded context per directory.
- Decompose on multiple responsibilities, never on line count. Constants at file top; no magic numbers.
- Adding a plugin frame to the Visibility panel means adding a row to `VisibilityManifest.lua` — Core's VisibilityEngine stays plugin-agnostic.

## References
- `Core/README.md` — data architecture; `Core/Plugin/README.md` — plugin lifecycle and profile handling.
- Skills: `/canvas-mode` for draggable component types, `/wow-frames` for new frames and secure templates.
- Non-designable behaviors live in `QoL/`; independently installable features in `Orbit-Dock-*` sub-addons.
