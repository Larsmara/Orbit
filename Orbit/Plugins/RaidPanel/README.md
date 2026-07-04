# RaidPanel

## Description
Dock-style raid-leader panel: current difficulty, ready check, role poll, 8 target/world markers, clear markers, and ping restriction, rendered as circular (or square) icons with arc-wrap layout.

## Purpose
One-click access to the raid-management actions a leader uses constantly, replacing Blizzard's CompactRaidFrameManager. Visible when in a group with lead or assist (or in the Always Show display mode).

## Implementation
Slot definitions, marker sprite mapping, and `WORLD_MARKER_ORDER` live in `RaidPanelData.lua`. `RaidPanel.lua` is the plugin root: it builds the dock, parks `CompactRaidFrameManager` via `OrbitEngine.NativeFrame:Park` (unparked in `OnDisable`), applies VE alpha via `Orbit.OOCFadeMixin:ApplyOOCFade(dock, self, 1)`, and re-evaluates visibility on `GROUP_ROSTER_UPDATE`, `PARTY_LEADER_CHANGED`, `PLAYER_ENTERING_WORLD`, `PLAYER_DIFFICULTY_CHANGED`, and `PLAYER_REGEN_ENABLED`. Icons come from the `RaidPanelIcon.lua` factory (`SecureActionButtonTemplate` buttons; secure attrs for markers, `PostClick` for menus/actions/sheen). `RaidPanelLayout.lua` is pure arc-wrap math (mirrors PortalLayout); orientation is auto-detected from screen position via `Frame:RegisterOrientationCallback`. `RaidPanelVisibility.lua` owns `ShouldShow()` (in-group + lead/assist) and `IsRaidLeaderTier()` (drives Always Show's slot set). `RaidPanelMenus.lua` builds the Difficulty and Ping Restriction dropdowns with `MenuUtil`.

Settings (`DisplayShape`, `DisplayMode`, `IconSize`, `Spacing`, `Compactness`) follow PluginMixin; shared labels reuse `PLU_PORTAL_*`, panel-specific keys use `PLU_RAIDPANEL_*`.

## Gotchas
- Marker slots use Blizzard's built-in `raidtarget` (`type1`) and `worldmarker` (`shift-type1`) secure actions. Never override `OnClick` on any slot — it replaces the template's secure dispatch and breaks every marker slot sharing the factory.
- The world-marker attribute must be the suffixed `shift-marker1`. Bare `shift-marker` is not in the `SecureButton_GetModifiedAttribute` cascade and silently falls through to plain `marker`, placing the raid-target index as a world marker.
- The two marker index sets differ: `marker` is raid-target sprite order 1..8; `shift-marker1` holds `WORLD_MARKER_ORDER[i]` (`{5,6,3,2,7,1,4,8}`), the inversion of the live `PlaceRaidMarker(i)→symbol` map read in-game. It is not Blizzard's `WORLD_RAID_MARKER_ORDER` (that feeds a different CRF indirection).
- `ClearRaidMarker()` / `RemoveRaidTargets()` are protected — they throw `ADDON_ACTION_FORBIDDEN` from insecure `PostClick` even during a hardware event. Clear Markers is a secure `macro` whose `macrotext1` `/click`s two hidden delegate buttons (`EnsureClearDelegates`, created once out of combat) that run `worldmarker action=clear` and `raidtarget action=clear-all` on a fully secure path.
- Never hardcode slash tokens (`/tm`, `/wm`, `/clearworldmarker`) in a macrotext — they are localized via `GlobalStrings` and silently no-op on non-enUS clients. `SECURE_ACTIONS` type/attribute names and `/click` are locale-stable.
- Ready Check / Role Poll carry no `type` attribute: `DoReadyCheck` / `InitiateRolePoll` are not protected, so plain `PostClick` calls are valid — no macro needed.
- Secure attributes are written outside combat only; `pendingRefresh` defers rebinds and visibility changes to `PLAYER_REGEN_ENABLED`. The dock itself is an insecure `Frame`; only the icon children are secure.
- `GM-raidMarker-reset` has no `-hover`/`-pressed` atlas variants. Setting a nonexistent atlas blanks the highlight (no mouseover) and the pushed texture (icon vanishes on click) — the slot deliberately falls back to the yellow-tint highlight; don't add variants back.
- In Always Show mode a shift-click world marker without lead/assist plays `Icon.PlayDenied` (red pulse + error sound) from `PostClick`; the secure dispatch still fires and no-ops server-side, so there is no taint concern.
- Edit mode overrides `ShouldShow` — the dock always shows while `Orbit:IsEditMode()` is true, read live on every call (no cached flag), so mid-edit `/reload` and `EditMode.Exit` both settle correctly. Icons get mouse disabled and secure attrs cleared so selection/snap overlays work.
- `ApplyOOCFade` in `OnLoad` is mandatory: without it VE writes settings but never applies alpha to the dock (verified missing, then added).
- `Spacing == 0` flips per-icon borders to a single merged group border + one dock backdrop (same convention as ActionBars / CooldownLayout / TrackedContainer); switching back must call `Skin:ClearIconGroupBorder`.
- VE registry pairing: `RaidPanel` (FRAME_REGISTRY) exposes the dock; `BlizzRaidManager` (BLIZZARD_REGISTRY, `ownedBy = "Raid Panel"`, defined in `Core/Plugin/VisibilityEngine.lua`) is hidden from the VE table while this plugin owns the parked frame.

## References
- `Core/Plugin/VisibilityEngine.lua` — `BlizzRaidManager` entry; `Core/EditMode/` for edit-mode integration.
- Blizzard source: `Blizzard_FrameXML/SecureTemplates.lua` (`SECURE_ACTIONS.raidtarget` / `worldmarker`), `RaidMarkersDocumentation.lua` (protected flags).
- Skills: `/wow-frames` (secure templates), `/pixel` (borders).
