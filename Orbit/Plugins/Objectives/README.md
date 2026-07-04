# Objectives

## Description
Reparents Blizzard's `ObjectiveTrackerFrame` into a scrollable Orbit container with configurable size, border, backdrop, and a hook-based skin (global font, Orbit progress bars, quest-type-coloured titles, slim atlas POI icons). All skinning is `hooksecurefunc`-based and idempotent — no template replacements, no widget-pool manipulation.

## Purpose
Give the objective tracker Orbit's theme and layout control (Edit Mode drag, Visibility Engine fade/opacity) without rebuilding Blizzard's tracker logic. Also adds behaviours Blizzard lacks: per-module collapse persistence, combat auto-collapse, and current-zone quest / world-quest filtering.

## Implementation
| file | role |
|---|---|
| `ObjectivesConstants.lua` | constants + shared `ValidateColor()` |
| `ObjectivesPlugin.lua` | registration, capture, ScrollFrame, container sizing, collapse persistence, border/backdrop, VE |
| `ObjectivesSkin.lua` | hook-based skinning: headers, blocks, POI, progress/timer bars, UI widgets |
| `ObjectivesZoneFilter.lua` | zone quest filter + area world-quest tracker (watch-list management) |
| `ObjectivesSettings.lua` | Layout / Behaviour / Colours tabs |

Capture: on `ADDON_LOADED` (Blizzard_ObjectiveTracker) the tracker is reparented into `OrbitObjectivesScrollChild`, the scroll child of a native `ScrollFrame` (`OrbitObjectivesScroll`) inside `OrbitObjectivesContainer`; `FrameGuard:Protect` keeps it. `tracker.GetAvailableHeight` is overridden to a constant (`MAX_TRACKER_HEIGHT` 50000) so Blizzard renders all blocks; `tracker.UpdateHeight` is replaced to measure real content height (`topModulePadding + Σ contentsHeight + moduleSpacing·(n−1)`) into the scroll child, so the ScrollFrame derives its own scroll range. Height/empty-state recompute is driven from a `hooksecurefunc` on the container `Update` (Blizzard only calls `UpdateHeight` on `OnShow`). Box height = `min(Height setting, content + 2·inset)`.

Skinning: hooks are installed once in `InstallSkinHooks`; every callback no-ops unless `_enabled` (set by `SetSkinEnabled` from `IsOrbitStyle()`, i.e. `StyleMode ~= "Blizzard"`). Structural machinery (capture, scroll, content height, width fit, border, collapse, VE) is style-independent; only the cosmetic skin is gated. Hooked targets: per-module `AddBlock`/`GetProgressBar`/`GetTimerBar`, `ObjectiveTrackerBlockMixin.AddObjective`, `ObjectiveTrackerQuestPOIBlockMixin.AddPOIButton`, the UIWidget template `Setup` mixins, and each header's `SetCollapsed`. POI title colour priority: super-tracked > completed > classification/tag colours > `TitleColor`; `SUPER_TRACKING_CHANGED` re-skins all POI buttons. Progress-bar labels are reformatted via a `SetText`/`SetFormattedText` hook using the token format in `ProgressBarLabelFormat`.

Zone filter: two default-off toggles (`ZoneFilter`, `ZoneWorldQuests`) driven by `ZONE_CHANGED*`/`QUEST_*`/`QUEST_WATCH_LIST_CHANGED`/`PLAYER_ENTERING_WORLD`, coalesced to the next frame. `EvaluateZoneFilter` adds in-zone quests / removes out-of-zone ones via `AddQuestWatch`/`RemoveQuestWatch` against the current map set (zone + ancestors to continent); a quest the user untracks while in-zone lands in a per-zone `suppressed` set (keyed by `GetZoneKey`, the zone-level map) and isn't re-added until the zone key changes — leave → return. `EvaluateWorldQuestZone` tracks on-map WQs via `AddWorldQuestWatch` (zone-level map set only) and mirrors the same dismiss-suppression (`suppressedWQ`), detecting a dismiss as a Manual WQ watch that vanished between passes (Automatic proximity expiry is ignored). Five shadow sets persist per-character in `plugin:GetCharData("ZoneFilterState")`; disabling re-watches what was removed and wipes the sets.

Persistence: collapse state → `Orbit.db.AccountSettings.ObjectivesCollapseState` via `SetCollapsed` hooks, restored in `ApplySettings`. Position via the standard engine with `orbitForceAnchorPoint = "TOPRIGHT"` and `orbitWidthSync = true`. VE: the container registers in `Plugins/VisibilityManifest.lua` and gets `OOCFadeMixin:ApplyOOCFade`; the Blizzard frame's own VE row is `ownedBy = "Objectives"`, and a Blizzard hider (`NativeFrame:SecureHide`) covers the plugin-disabled state.

## Gotchas
- The two root causes of the long scroll saga (both in `CaptureTracker`): the tracker inherits `UIParentRightManagedFrameTemplate`, which is screen-clamped — inside a viewport the clamp pins it to the screen edge and corrupts the scroll range, so `SetClampedToScreen(false)`; and `SetClipsChildren` does not clip a child in a different strata, so the LOW-strata tracker must be moved into the ScrollFrame's strata or it renders outside the box.
- `ScenarioObjectiveTracker` is header-only (font, no block/bar hooks): its content frames share Blizzard's widget pool, and calling methods on them taints the pool and breaks other UI. Its collapse math reads `headerHeight`, so it keeps native header height too.
- There is no taint-safe way to override `ShouldDisplayQuest` (mixin return value; a full override taints), so the zone filter manages the watch list instead — the SmartQuestTracker pattern. The watch APIs are `AllowedWhenUntainted` and unprotected, so no combat gating is needed.
- `C_QuestLog.AddQuestWatch` is 1-arg: our adds read back as `Manual`, indistinguishable from user pins — so "ours to manage" is a persisted flag set, never the watch type (relying on watch type made our own auto-tracks un-removable). WQ watches are added as Manual (Automatic is engine-capped) and gated on the 5-slot Manual cap, else a 6th add evicts the oldest user pin.
- `C_TaskQuest.GetQuestsOnMap` returns nil transiently (post-login/zone-in, before POIs stream in); the WQ removal pass is gated on it so an empty read can't un-watch every tracked WQ, and `QUEST_LOG_UPDATE` re-drives the add once data arrives.
- A world quest's zone is `C_TaskQuest.GetQuestZoneID`, **not** `GetQuestUiMapID` — the latter returns 0 for world quests, which silently rejected every one from the in-zone filter (the WQ tracker tracked nothing).
- Never auto-remove: genuine manual pins, the super-tracked quest, complete/turn-in-ready quests, zoneless quests (`GetQuestUiMapID == 0`). Our own Add/Remove re-fires `QUEST_WATCH_LIST_CHANGED`, converging via one extra idempotent pass; the scheduler clears `_zoneFilterUpdating` at the start of every pass, so an error mid-pass can't strand the guard and permanently disable the filter (it self-heals on the next event).
- Box height is deliberately position-independent: an earlier screen-relative cap made height (and scroll range) depend on where the frame sat. The ScrollFrame owns overflow; the box is just the user's height clamped to content (Kaliel's Tracker's `maxHeight` model).
- `IsTrackerEmpty` must drop its `IsShown()` gate while the master is collapsed — Blizzard hides collapsed modules but their `contentsHeight` stays positive, so a collapsed tracker would otherwise lose its chrome. Always non-empty in Edit Mode so the frame stays grabbable.
- The old content-height formula (`header + Σ contentsHeight`) omitted `topModulePadding` and `moduleSpacing` — that's why the last section used to clip.
- `orbitForceAnchorPoint = "TOPRIGHT"` exists because `Snap:NormalizePosition` collapses a tall right-side frame's vertical token to center, making `SetHeight` grow symmetrically; `HoldTopAnchor` self-heals stale centered saves each session (`RestorePosition` restores verbatim).
- `InCombatLockdown()` is checked before any reparent/`SetPoint`/`Show` on the tracker, deferred via `CombatManager:QueueUpdate`.
- `StyleMode` changes are reload-gated: the skin strips Blizzard textures irreversibly within a session. Blizzard style needs two fit-ups for the native left-edge clip: a `BLIZZARD_LEFT_PAD` content shift and `FitNativeHeaderBackground` re-anchoring (the header atlas is fixed-width, CENTER-anchored).
- Objectives is not spec-scoped, so the shared spec-restore skips it even though Blizzard re-anchors the tracker on spec change — `ORBIT_PLAYER_SPECIALIZATION_CHANGED` triggers `ReassertLayout` (re-`RestorePosition` + `ApplySettings`).
- Header click-collapse routes through `Plugin:ToggleCollapse` (instant, primes the `dirty` flag, settles with `Update(true)`); programmatic paths call `SetCollapsed` directly. Label-hook writes are guarded by `_orbitUpdating` against recursion.
- Combat auto-collapse is transient: the `_combatCollapsing` flag gates it out of `SaveCollapseState` so a reload/disconnect mid-combat can't persist the collapsed state as the saved layout, and `PLAYER_REGEN_ENABLED` always restores the pre-combat state regardless of the current setting (the settings dialog itself auto-hides in combat, but the guard covers the reload path).
- `MigrateColorSettings`/`MigrateLegacySettings` fold legacy colour-curve and retired keys on first load; `ValidateColor` accepts both formats.

## Secrets
Quest and objective tracker data is plain Lua in and out of combat — the module's constraint is taint, not secrets. Progress-bar percentage arithmetic on objective values is safe.

## References
- `Plugins/VisibilityManifest.lua`, `Core/EditMode/README.md` (`SecureHide`), `Core/Plugin/README.md` (settings/profile lifecycle).
- Blizzard source: `agent/wow-ui-source` — `Blizzard_ObjectiveTracker` (module mixins, `topModulePadding`, header layout).
- Skills: `/wow-frames` (hooks, secure templates), `/pixel` (separator/header pixel snapping).
- Feature roadmap: `FEATURE-PLAN.md` in this directory.
