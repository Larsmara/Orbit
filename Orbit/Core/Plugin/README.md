# Plugin

## Description
Plugin lifecycle infrastructure: registration, settings resolution, profile persistence, and the shared behavior mixins (OOC fade, visibility, native bar wrappers) plugins opt into. Canonical home of the profile lifecycle.

## Purpose
Defines how plugins register with Orbit, how a setting resolves and persists across profiles, and the per-profile visibility/fade system. Plugins never touch `OrbitDB` directly — every read and write routes through the doors here.

## Implementation
| File | Role |
|---|---|
| Registry.lua | `Engine:RegisterSystem` / `GetSystem`; `Engine.SystemMixin` base (frozen) |
| PluginMixin.lua | settings doors, spec/char-scoped storage, standard event wiring |
| ProfileManager.lua | `Orbit.Profile` — CRUD, switching, spec mapping, import/export, migrations |
| DefaultProfile.lua | layout-only seed for a clean install |
| VisibilityEngine / FadeProfiles / OOCFadeMixin / VisibilityState | per-profile visibility + fade stack |
| NativeBarMixin.lua | shared scale/layout for native Blizzard bar wrappers |

Settings resolution (`PluginMixin:GetSetting`): global-inherit key → `Orbit.db.GlobalSettings`; else Canvas transaction pending value → `Orbit.runtime.Layouts[layout][system][systemIndex][key]` (a pointer into the active profile's `Layouts`, re-pointed on switch) → `indexDefaults` → schema `defaults`. `SetSetting` writes to the runtime layout. Spec data lives at `Orbit.db.SpecData[charKey][specID][systemIndex][key]` (`Get/SetSpecData`); spec-independent char data at `Orbit.db.CharData[charKey][system][key]` (`Get/SetCharData`). Sanctioned cross-cutting reads: `Orbit:GetTheme(key)` and `Orbit:ReadPluginSetting(system, systemIndex, key)` — both on the `Orbit` namespace, not PluginMixin.

Profile lifecycle (ProfileManager.lua): each `Orbit.db.profiles[name]` owns `Layouts`, `GlobalSettings`, `DisabledPlugins`, `HideBlizzardFrames`, `Visibility`. `Initialize` seeds the "Global" profile from defaults, restores the per-character active profile from `Orbit.db.charActiveProfiles[charKey]`, and points `Orbit.runtime.Layouts` at it. `SetActiveProfile` (combat-deferred via `CombatManager:QueueUpdate`) flushes positions and GlobalSettings into the outgoing profile, clones the incoming profile's `GlobalSettings` into `Orbit.db.GlobalSettings`, live-toggles or reload-prompts plugins whose enabled/hidden state changed, re-applies all plugins (priority-first, then a deferred full sweep + anchor reconcile), and fires `ORBIT_PROFILE_CHANGED`. Spec switching: `PLAYER_SPECIALIZATION_CHANGED` → debounced `CheckSpecProfile` → `Orbit.db.specMappings[specID]`, gated by the per-class opt-in `Orbit.db.classSpecProfiles`; unmapped specs fall back to Global. Export/import: LibSerialize + LibDeflate strings prefixed `--OrbitProfile--`, single-profile or full collection.

Event wiring: `RegisterStandardEvents()` subscribes a debounced `ApplySettings` to `ORBIT_PLAYER_ENTERING_WORLD`, `ORBIT_COLORS_CHANGED`, and EditMode enter/exit. Live Canvas preview is a separate opt-in: `WatchCanvasChanges()` is the single `ORBIT_CANVAS_SETTINGS_CHANGED` subscriber, dispatching through the `OnCanvasLivePreview` hook.

Visibility stack: per-frame settings (VisibilityEngine) and named fade groups (FadeProfiles) live in the active profile's blob `profile.Visibility = { frames, fade }`, lazily seeded and resolved fresh each access via `Profile:GetActiveVisibility` — there is no account-wide layer. Changes fire `ORBIT_VISIBILITY_CHANGED` (drives apply) and `ORBIT_FADE_PROFILES_CHANGED` (drives the config UI). `OOCFadeMixin` (Orbit + insecure Blizzard frames) and `VisibilityEngine.ApplySecureBlizzardFrame` (secure Blizzard frames) consume the resolved fade as a multiplicative `math.min` cap — FadeProfiles runs no competing SetAlpha loop of its own.

## Gotchas
- Defaults live in exactly one of two layers: the plugin's `defaults = {}` schema block is the per-setting source of truth; `DefaultProfile.lua` seeds only what a schema cannot express — positions/anchors, per-instance state (DamageMeter `MeterDefs`, datatext placements, StrataEngine order), cross-instance conflicts one shared mixin default can't carry, and the GlobalSettings theme. Echoing a schema default in DefaultProfile is duplication that drifts. Never persist runtime caches (`_sorted`) or migration sentinels in either site.
- FadeProfiles conditions evaluate via `SecureCmdOptionParse` — the secure game-state axis, not secret values; the catalog is runtime-validated at load. Profiles are priority-ordered (list position, top wins); the highest-priority firing profile's target is the resolved alpha. 0% is legal — the frame is invisible but clickable; Reveal All is the safety net.
- The Mouseover condition is `perFrame` (no macro conditional exists for "cursor over THIS frame") and unsupported on secure Blizzard frames: a profile containing Mouseover applies NO fade at all to its secure Blizzard members — `GetResolvedAlpha`, the only thing `ApplySecureBlizzardFrame` reads, excludes mouseover profiles. Intentional: pair Mouseover with Orbit/insecure frames; fade secure frames with a plain profile. `maxOpacity` (the high range-slider handle) caps only the mouseover-reveal path; non-mouseover profiles pin at `fade`.
- VisibilityEngine holds no plugin names: Orbit frames register at load from `Plugins/VisibilityManifest.lua` via `VE:RegisterFrame`; `BLIZZARD_REGISTRY.ownedBy` is a documented, graceful-degrading exception.
- `MigrateVisibilityToProfiles` is one-time (gate: `AccountSettings.VisibilityPerProfileV1`) — it relocated the old account-wide `VisibilityEngine`/`FadeProfiles` roots per-profile and strips legacy per-plugin `Opacity`/`OutOfCombatFade`/`ShowOnMouseover` keys from every layout.
- Mixins are stateless — state lives on the frame. Never add plugin-specific logic to PluginMixin; one plugin's need lives in that plugin. Any profile mutation must fire `ORBIT_PROFILE_CHANGED`.
- Profiles are user-named ("Healer", "Tank M+"), never auto-generated from specs. "Global" is the fallback and cannot be renamed or deleted. Plugins may declare `disabledSpecs = { [specID] = true }` to hard-disable per spec (greys the manager checkbox; `IsPluginEnabled` returns false).
- `VisibilityState.ApplyState` defers its whole body via CombatManager when combat-locked and caches the last driver to skip redundant `RegisterStateDriver` calls.
- New mixin files load via a `<Script>` entry in `Plugin.xml` (profile-related files via `Profiles.xml`), never listed in the `.toc`.

## References
`Core/README.md` (full data architecture), `Plugins/README.md` (new-plugin checklist), `Plugins/VisibilityManifest.lua`, `Core/EditMode/README.md` (positions, anchor graph), /wow-frames (state drivers, combat lockdown).
