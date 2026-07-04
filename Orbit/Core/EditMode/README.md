# EditMode

## Description
Orbit's integration with Blizzard's Edit Mode: selection, dragging, snapping, the anchor graph, and position persistence for every movable Orbit frame, plus taint-safe suppression of native Blizzard frames.

## Purpose
The spatial management layer. All positioning data flows through here between the user's drag and SavedVariables, and Blizzard-frame replacement (Park) is centralized here so taint discipline lives in one place.

## Implementation
SavedVariables → `Frame/Position/Persistence.lua:RestorePosition` (on attach, spec change, profile change) → live frames. User drag/resize/nudge (`Frame/Selection/`) → `Frame/Snap.lua` detection → anchor or free position → staged in `PositionManager.lua` (ephemeral buffer) → `FlushToStorage` writes via `Persistence:WriteAnchor/WritePosition` → `plugin:SetSetting`. Flush fires on `EditMode.Exit`, PLAYER_LOGOUT (covers `/reload`), and profile switch.

| File | Role |
|---|---|
| EditMode.lua | Enter/Exit callback API, combat auto-exit, exit-flush hook |
| PositionManager.lua | ephemeral position/anchor staging buffer |
| NativeFrame.lua | taint-safe Blizzard frame suppression (Park/Unpark/KeepAliveHidden/SecureHide) |
| MountedVisibility.lua | hide frames while mounted (all mounted checks live here, not in plugins) |
| Frame/EditFrame.lua | `Engine.Frame` public surface over Anchor/Snap/Selection/Persistence/Guard |
| Frame/Factory.lua, Orientation.lua, Guard.lua, NudgeRepeat.lua | frame factory, L/R orientation, combat guard, nudge repeat |
| Frame/Snap.lua, Selection.lua | snap detection; selection overlay + snap-target registry |
| Frame/Position/, Frame/Selection/ | anchor graph + persistence; drag/nudge/resize interactions (own READMEs) |
| Handle/HandleCore.lua | shared handle infrastructure (also used by Canvas Mode) |
| Preview/PreviewFrame.lua | preview-frame construction (Tracked, PlayerPower, PlayerCastBar, DamageMeterUI) |

Anchor graph (`Position/Anchor.lua` + `AnchorGraph.lua`) keeps **two** parent tables: the *physical* graph (where frames are attached right now) and the *logical* graph (the user-intended parent). Two skip states: **virtual** (`SetFrameVirtual` — content-empty frames) and **disabled** (`SetFrameDisabled` — profile/spec disable). When a parent is skipped, `ReconcileChain` promotes its children to the nearest non-skipped ancestor with `skipLogical=true` so logical intent survives; `RestoreLogicalChildren` pulls them home when the parent un-skips. `ScheduleReconcileChain/ScheduleReconcileAll` collapse bulk toggles into one next-frame flush (`C_Timer.After(0)`); a flush landing in combat re-queues via `CombatManager:QueueUpdate`.

Restore path: `ResolveAnchor` walks the candidate chain `[target, live ancestors above target, saved ancestry]` — ancestry is captured at drag-stop (`BuildAncestry`, nearest-first, capped at `MAX_ANCESTRY_DEPTH = 10`; legacy `anchor.fallback` is treated as 1-element ancestry). If the target is missing from `_G` (load-order race, or spec-locked plugin whose OnLoad never ran), the intent is stashed in `Persistence.pendingByTarget` via `QueuePendingAnchor`; `DrainPendingFor` re-attempts when the target's frame attaches, `DrainAllPending` sweeps on PLAYER_ENTERING_WORLD. Entries dedup per (target, child).

Per-spec anchor routing: `WriteAnchor/WritePosition` write into SpecData when the plugin is spec-scoped (`IsSpecScopedIndex`), the target sets `frame.orbitAnchorTargetPerSpec = true` (Tracked), or spec data already exists (stickiness). Reads check the spec slot first, then the global setting. `plugin.settingsArePerSpec = true` opts out entirely (Tracked partitions per-record — a second layer would desync). `RestoreAffectedBySpecChange` (PLAYER_SPECIALIZATION_CHANGED, deferred two frames) re-restores **only** `IsSpecScopedIndex` plugins; `RestoreAffectedByProfileChange` (ORBIT_PROFILE_CHANGED) walks every attached frame because SpecData is account-scoped and survives profile switches.

## Gotchas
- **Edit Mode lifecycle**: listen via `EventRegistry:RegisterCallback("EditMode.Enter"/"EditMode.Exit", …)`. Never `EditModeManagerFrame:HookScript("OnShow"/"OnHide")` — the hook rides the secure execution chain that runs `ResetPartyFrames` on exit; EventRegistry fires after it settles.
- **Never write to `EditModeManagerFrame`** (no SetPoint/SetAlpha/EnableMouse/Hide/Show). Drive it only via `securecall("HideUIPanel"/"ShowUIPanel", EditModeManagerFrame)` — this is how combat auto-exit works.
- **`NativeFrame:Park`** is the only sanctioned way to suppress a Blizzard frame. Recipe: `UnregisterAllEvents` → `HideBase or Hide` (skips Blizzard's tainted `HideOverride`) → `SetParent(OrbitHiddenParent)` → `hooksecurefunc` re-claim hooks on Show/SetShown/SetParent. It deliberately does **not** touch anchors, alpha, or mouse, and never `RegisterStateDriver`s a Blizzard frame — all were verified taint vectors (writes to `CompactPartyFrame` tainted `healthBar:GetStatusBarColor()` after Edit Mode exit). Call out of combat (plugin OnLoad); idempotent; `Unpark` neuters the hooks for live toggles.
- `NativeFrame:KeepAliveHidden` is the softer variant when Orbit scrapes a Blizzard manager's children (PlayerBuffs reparents `BuffFrame.auraFrames`) — hide + re-hide hooks only, no UnregisterAllEvents/SetParent, so the native update loop keeps running. `:SecureHide` (state driver) is kept only for action/status-tracking bars where the driver is the documented contract. `:Hide` has no restore path short of `/reload`.
- **Rescue check**: once `ResolveAnchor` or `PromoteGrandchild` has physically re-anchored a frame past its skipped logical parent, `SetFrameVirtual/SetFrameDisabled` must not re-park it — `IsRescued` (logical parent ≠ physical parent, logical skipped, physical live) suppresses the park, else the frame teleports off-screen after being correctly placed.
- The spec-change re-restore is **opt-in by `IsSpecScopedIndex`**, never by mixin presence: Blizzard fires PLAYER_SPECIALIZATION_CHANGED on group joins and instance transitions, and walking every attached frame caused a visible stall.
- `PositionManager` is ephemeral with no user cancel affordance; `DiscardChanges` is used only by profile switching. `FlushToStorage` wipes the *entire* buffer — leftover Active entries would out-prioritize saved settings on every later restore.
- Cycle detection must use `AnchorGraph:WouldCreateCycle()` (pure-data, no `GetNumPoints`). Position format is `{ point, relativeTo, relativePoint, x, y }`; all offsets go through `Pixel:Snap()`.
- Blizzard grid/snap-preview tap-in (`Drag.lua` installs `GetScaledSelectionSides`/`GetScaledSelectionCenter`/`GetFrameMagneticEligibility` shims + `SetSnapPreviewFrame`) is **one-way**: Orbit never calls `EditModeMagnetismManager:RegisterFrame`, so Blizzard frames can't snap to Orbit frames, and nothing crosses a secure boundary. `Snap.lua:DetectSnap` reads `magneticGridLines` with Blizzard's own `magnetismRange` (8 px) as synthetic candidates; Orbit anchor candidates (`ANCHOR_THRESHOLD` 10 px) beat grid/UIParent candidates per axis, and the drop lands through `Pixel:Snap` so the red preview line and the actual drop agree.
- `frame.orbitSelectionOutset = N` (set before `AttachSettingsListener`) grows the selection highlight N px per side.
- Canvas Mode delegation (`Frame:EnterCanvasMode/ToggleCanvasMode` → `Engine.CanvasMode`) and `Engine.CanvasMode:IsActive()` guard reads in selection/drag are legitimate cross-domain touches.

## Secrets
Minimal surface: `Handle/HandleCore.lua` guards native-frame width/height with `issecretvalue` before comparison, and `Position/Anchor.lua` guards child alpha in the merge-border visibility check. Orbit-frame geometry is never secret.

## References
`Frame/Position/README.md` (axis model, sync flags) · `Frame/Selection/README.md` (drag lifecycle) · `../CanvasMode/README.md` · skills: `/wow-frames` (secure templates, Park context), `/pixel` (Snap/Multiple) · Blizzard source: `agent/wow-ui-source/Interface/AddOns/Blizzard_EditMode/`.
