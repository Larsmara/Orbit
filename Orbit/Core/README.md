# Core

## Description
Root of the Orbit engine. Shared infrastructure, plugin lifecycle, rendering, configuration UI, Edit Mode, Canvas Mode, skinning, and unit display mixins — everything plugins consume. Core has zero knowledge of any specific plugin.

## Purpose
Keeps plugins thin and coherent: all cross-cutting concerns (events, pixel math, combat safety, settings resolution, positioning) live here exactly once. Dependencies flow strictly inward — plugins depend on Core, Core never depends on plugins.

## Implementation
Boot: `Init.lua` (ADDON_LOADED bootstrap, plugin registration, SavedVariables seeding, PLAYER_LOGIN → `Orbit:OnLoad()`, PLAYER_LOGOUT → PositionManager/GlobalSettings flush). `API.lua` is the programmatic/debug API (`Orbit.API:GetState/ResetProfile/HardReset/UnlockFrames/InspectPlugin`); slash commands live in `Config/Entry/SlashCommands.lua`.

| Directory | Role |
|---|---|
| Infrastructure/ | low-level systems (EventBus, Pixel, CombatManager, animation) |
| Plugin/ | plugin lifecycle: registration, PluginMixin, ProfileManager |
| Shared/ | constants, media, SecretValueUtils, glow controller |
| Color/ | class/reaction color resolution, curve engine |
| Skinning/ | borders, textures, icons, cast bars, action buttons |
| UnitDisplay/ | unit frame mixins (health, auras, cast bars, status icons) |
| EditMode/ | frame positioning engine (drag, anchor graph, persistence) |
| CanvasMode/ | intra-frame component editor dialog |
| Config/ | settings UI (SchemaBuilder, renderer, widgets, panels) |
| Onboarding/ | first-run guided tours |
| Libs/, assets/ | vendored libraries, bundled media |

Data architecture — strict boundaries for what persists where in `OrbitDB`:
- `Orbit.db.AccountSettings` — true account-wide application data (color history, tutorial flags, minimap icon). Immune to ProfileManager. Access only via `Orbit:GetAccountData/SetAccountData`.
- `Orbit.db.GlobalSettings` — the aesthetic theme for the *active profile* (fonts, border sizes, bar textures), cloned per profile switch. Read via `Orbit:GetTheme(key)`, never indexed directly.
- `Orbit.db.profiles[name]` — per-profile layout data: plugin settings, positions, anchors. Plugins reach it only through `PluginMixin:GetSetting/SetSetting`.
- `Orbit.db.SpecData[charKey][specID][sysIdx][key]` — per-character per-spec, via `GetSpecData/SetSpecData`.
- `Orbit.db.CharData[charKey][system][key]` — per-character spec-independent (quest-watch shadow state), via `GetCharData/SetCharData`. Immune to profiles and spec.

## Gotchas
- **Never store non-theme application data in `GlobalSettings`.** ProfileManager clones `profile.GlobalSettings` over the live `Orbit.db.GlobalSettings` block on every profile activation — which fires on login and `/reload` — so un-flushed application data parked there is permanently erased. Account-wide data belongs in `AccountSettings`.
- `SpecData` is wiped on class change (`SpecDataMeta` guard in `Init.lua`) — SpecIDs are class-bound; surviving data would be stale after a PTR copy or faction/realm service.
- No file in Core may reference a plugin by name; new engine-level systems go in `Infrastructure/`, new shared unit-frame behavior in `UnitDisplay/`, visual rendering in `Skinning/`, config widgets in `Config/Widgets/`.
- Constants belong in `Shared/Constants.lua`, never inline.

## Secrets
Core owns the engine-wide secret-value helpers in `Shared/SecretValueUtils.lua` (guards + `Orbit.DEBUG_SECRETS`-gated chat diagnostics). Per-module handling is documented in each module's README; classification and sink patterns live in the `/wow-secrets` skill.

## References
`Core/Plugin/README.md` (profile lifecycle, default-values rules) · `Plugins/README.md` (new-plugin checklist) · `EditMode/README.md`, `CanvasMode/README.md` · skills: `/wow-secrets`, `/wow-frames`, `/pixel`, `/canvas-mode`.
