# Tracked

## Description
User-authored cooldown surfaces: free-form icon-grid containers and single-payload bars for any spell
or item, spawned from Orbit's "Tracked Icons" / "Tracked Bars" tabs on Blizzard's
`CooldownViewerSettings` frame.

## Purpose
Blizzard's CooldownViewer tracks a fixed, Blizzard-curated spell set. Tracked lets the user build
arbitrary cooldown displays per spec — draggable, anchorable, canvas-editable Orbit frames. Tab
registration and all Blizzard-frame hooks live in `Plugins/CooldownViewerExtensions/`; Tracked itself
never touches Blizzard frames.

## Implementation
Data enters by drag-drop from spellbook/bags (cursor resolution + payload builders in
`Core/Shared/CooldownDragDrop.lua`) or from the open settings panel via
`Orbit.CooldownSettingsDragBridge`. `BuildTrackedBarPayload` captures everything a bar needs at drop
time (type, id, `maxCharges`, tooltip-parsed `activeDuration`/`cooldownDuration`, item `useSpellId`),
which fixes the bar's render mode: charges / active_cd / cd_only.

- `TrackedPlugin.lua` — record store, id allocation, create/delete, `RefreshForCurrentSpec`,
  `GetSetting`/`SetSetting` redirect (systemIndex → record), virtual/disabled state sync.
- `TrackedContainer.lua` — icons-mode frame: sparse 2D grid keyed `"x,y"`, 8-way neighbor drop
  zones, per-container cursor watcher, event-driven update + 0.3s visual poll gated per-icon.
- `TrackedIconItem.lua` — stateless per-icon factory (swipe, phase curves, charge text, glows);
  the container owns the ticker.
- `TrackedBar.lua` — single-payload bar, three render modes, 0.1s ticker that self-suspends at ready.
- `TrackedSettings.lua` — schema dispatch (icons vs bars); `TrackedTour.lua` — one-shot tab tooltip.

Each container is one flat record: `OrbitDB.GlobalSettings.TrackedContainers[id] = { id, mode =
"icons"|"bar", spec, grid|payload, settings }`. `id` comes from the account-scoped monotonic counter
`Orbit.db.NextTrackedContainerId` and doubles as the plugin systemIndex. All settings (position,
anchor, canvas ComponentPositions, colors) land on `record.settings`; non-record indices fall through
to the standard layout DB so global Texture/Font inheritance still flows. Spec/profile changes
(`ORBIT_PLAYER_SPECIALIZATION_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED`, `ORBIT_PROFILE_CHANGED`,
world-enter) drive `RefreshForCurrentSpec`; `TRAIT_CONFIG_UPDATED` (debounced) rebuilds every bar
payload via `BuildTrackedBarPayload` and re-applies.

## Gotchas
- **Why the rewrite happened.** The old plugin shared spec-scoped slot ranges and "transformed"
  frames between icon/bar modes on spec swap — the most fragile code in the addon. Now: distinct
  frame type per record, never repurposed; globally-unique counter ids, never reused; flat record
  table filtered by each record's `spec`/`mode` fields. Do not reintroduce per-spec sub-trees, id
  reuse, or mode transforms — a new mode (e.g. ring) is a new file plus new build/settings branches.
- **Frames are never destroyed.** WoW can't destroy frames; every record keeps a long-lived frame
  that stays in the AnchorGraph as a routing node. Spec swap only toggles
  `Anchor:SetFrameDisabled` — that is what lets a chain `FrameA > Tracked > FrameC` collapse to
  `FrameA > FrameC` off-spec (`PromoteGrandchild`, logical anchor retained) and snap back on return
  (`RestoreLogicalChildren`). Tearing frames down would dangle FrameC's logical pointer.
- **Two-pass spec refresh.** `RefreshForCurrentSpec` disables all off-spec frames first, then
  enables on-spec ones. A single pass iterates `pairs` in arbitrary order, so two same-slot records
  (one per spec) could both be live anchor targets mid-swap and a reconcile could route children to
  the wrong frame.
- **Empty containers are virtual.** An empty container must not trap anchored children, so
  `RefreshContainerVirtualState` flags it virtual on every Apply. Four engine side effects are
  controlled: (1) the engine parks virtual frames — immediately `RestorePosition` to undo;
  (2) `SetFrameVirtual` writes `frame.orbitDisabled`, which would kill edit-mode selection —
  `_SyncOrbitDisabledFlag` re-derives it from the disabled axis only; (3) `frame.orbitNoSnap = true`
  stops the empty frame snapping onto others as a child; (4) `Selection:GetSnapTargets` filters
  skipped frames so nothing snaps onto it. Virtual composes with disabled (skipped = either).
- **Per-spec anchor routing.** Tracked frames set `frame.orbitAnchorTargetPerSpec = true`: any
  consumer anchoring TO a Tracked frame gets its saved anchor partitioned per-spec by
  `FramePersistence:WriteAnchor` (via `SetSpecData`), even if the consumer plugin isn't spec-scoped —
  SpecA and SpecB own different frame names, so one global anchor field can't serve both. Tracked
  itself sets `plugin.settingsArePerSpec = true`, OPTING OUT of that routing for its own saves:
  records are already per-spec via their `spec` field, and spec data is per-character so it would
  not survive a profile export.
- **Descendant cleanup on delete.** `DeleteContainer` must walk `GetAnchoredChildren` (break anchor,
  wipe saved Anchor) and `GetLogicalChildren` (clear logical anchor) and null any saved consumer
  anchor naming the deleted frame — otherwise the ghost frame's `_G` entry survives `/reload` and
  children re-attach to an invisible frame.
- **Deletion is shift-right-click, combat-gated.** The only deletion gesture plugin-wide (item →
  container → bar payload → bar ladder); no delete buttons. Handlers no-op in `InCombatLockdown()`
  because delete/relayout runs SetPoint on anchored descendants.
- **Cursor polling is per-consumer.** Each frame owns its own cursor watcher. A previous shared
  cross-domain poll silently broke ViewerInjection when Tracked was removed — never centralize it.
  Always reuse `Orbit.CooldownDragDrop` for cursor resolution and payload builders.
- **Target-debuff active phases cannot be shown.** The icon active phase is cast-driven (SELF auras
  only). For a target debuff, `expirationTime`/`spellId` are secret in combat and even the secure
  sink path needs an `auraInstanceID` obtainable only via a secret comparison — no addon-reachable
  path. Rejected alternative: reparenting native CooldownViewer item frames into Tracked cells. The
  blocker isn't taint — the native viewer pools and re-anchors those frames on every refresh, so
  extraction desyncs the pool, layout, and settings panel. Doing it properly means replacing the
  native viewers wholesale (a CooldownManager rewrite, deferred). Keep such spells on CDM.

## Secrets
- Bars convert secret remaining-percent to numerics via file-local curves fed to
  `DurationObject:EvaluateRemainingPercent`: `INVERSE_CURVE` (cd_only fill), `ONCD_CURVE` (0/1
  on-cooldown flag for color state), a cached per-(active,cd) V-shape fill curve (active_cd
  fallback fill), `RECHARGE_PROGRESS_CURVE`/`RECHARGE_ALPHA_CURVE` (charges segment),
  `IDENTITY_CURVE` (time-text fallback: pct × last-known non-secret total).
- Charges mode is sink-plus-capture: `payload.maxCharges` is captured non-secret at drop time
  (issecretvalue-guarded) so `SetMinMaxValues` is safe, while secret `currentCharges` pipes straight
  into `StatusBar:SetValue`/`SetText` (C++ sinks). `TRAIT_CONFIG_UPDATED` payload rebuild keeps the
  cached max honest when talents change it.
- Icon mode uses `Cooldown:SetCooldownFromDurationObject(durObj, true)` — the secret never enters Lua.
- Live `cdInfo.startTime/duration` go secret under encounter restriction: every read is
  issecretvalue-guarded BEFORE arithmetic, falling back to cast-clock or cached totals.

## References
- `Plugins/CooldownViewerExtensions/README.md` — tab registration, settings-panel drag bridge.
- `Core/Shared/CooldownDragDrop.lua` — shared cursor/payload logic; `Core/Shared/DropZoneGlow.lua`.
- `Core/Plugin/VisibilityEngine.lua` — TrackedIcons/TrackedBars umbrella entries (sentinels 1/2,
  below `Constants.Tracked.SystemIndexBase`).
- Engine `FramePersistence` / `FrameAnchor` — anchor routing, virtual/disabled semantics.
- Skills: `/wow-secrets`, `/ki-abilities`, `/canvas-mode`. Blizzard source:
  `agent/wow-ui-source/.../Blizzard_CooldownViewer/`.
