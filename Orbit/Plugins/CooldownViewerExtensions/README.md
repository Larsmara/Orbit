# CooldownViewerExtensions

## Description
Registrar plugin that adds extra side tabs to Blizzard's `CooldownViewerSettings` frame and bridges spell drags out of that panel to Orbit drop targets. Consumers (currently `Orbit_Tracked`) call `RegisterTab`; it never registers tabs of its own.

## Purpose
The tabs are not specific to Tracked — any plugin that spawns editable elements from the cooldown viewer settings panel can add a tab without knowing about Blizzard's `LargeSideTabButtonTemplate` or coupling to Tracked. As its own plugin, Tracked can be disabled or rewritten without breaking the registration API. It is infrastructure that lives under `Plugins/` because it needs the plugin lifecycle and `liveToggle = false`.

## Implementation
| File | Role |
|---|---|
| CooldownViewerExtensionsPlugin.lua | registration (`Orbit_CooldownViewerExtensions`), `RegisterTab` API, `ADDON_LOADED` hook for `Blizzard_CooldownViewer`, deferred build queue, anchor chain |
| CooldownSettingsDragBridge.lua | captures the spellID dragged out of the panel and dispatches to any frame exposing `:OnCooldownSettingsDrop(spellID)` |

`RegisterTab{ id, atlas, tooltipText, onClick }`: builds immediately if `CooldownViewerSettings` is loaded, otherwise queues until `Blizzard_CooldownViewer` fires `ADDON_LOADED`. Duplicate ids are ignored (idempotent, safe from multiple consumers' `OnLoad`). The first tab anchors below `CooldownViewerSettings.AurasTab` (-3 y gap, matching Blizzard's spacing); later tabs chain in registration order, which is deterministic at load time.

Drag bridge: Blizzard's internal panel drag (`BeginOrderChange`) never populates `GetCursorInfo`, so the normal cursor-based drop path is blind here. Instead a `GameTooltip:HookScript("OnUpdate")` continuously caches `tooltip:GetSpell()`; `GLOBAL_MOUSE_DOWN` over a panel spell (verified by walking the tooltip owner's parent chain to `CooldownViewerSettings`) arms the cached spellID, and `GLOBAL_MOUSE_UP` walks `GetMouseFoci()` and calls `OnCooldownSettingsDrop(spellID)` on the first frame that implements it. Spell-only — the panel never shows items — and dispatch reuses the same `DragDrop:BuildTrackedItemEntry`/`BuildTrackedBarPayload` builders as the spellbook/action-bar drop paths.

## Gotchas
- Accepted exception to "plugins never call other plugins": consumers reach it via `Orbit:GetPlugin("Orbit_CooldownViewerExtensions"):RegisterTab{...}` because `RegisterTab` operates on a live frame handle an EventBus signal cannot supply. Treat it as a registrar, not a peer plugin.
- Tabs are parented to `UIParent`, not `CooldownViewerSettings`. Each tab carries `hooksecurefunc(tab, "SetChecked")` and `SetCustomOnMouseUpHandler` hooks that Blizzard's click dispatch can invoke; as children of the panel those callbacks would write to a child of a secure Blizzard frame on its secure stack and taint the panel's attribute chain. Visibility syncs via `parent:HookScript("OnShow"/"OnHide")` — script-handler hooks don't propagate method-level taint.
- Strata is pinned to `DIALOG`, not matched to the panel: `CooldownViewerSettings` sets no strata (default `MEDIUM`) and would render below `HIGH` frames like raid frames.
- The deleted first-generation bridge hooked `CooldownViewerSettingsItemMixin.OnDragStart` — a mixin-table hook that tainted every panel item and propagated into CDM viewer children. The tooltip read is pure (`GetSpell()` is read-only); never reintroduce mixin hooks here.
- `_lastBuiltTab` tracks the chain tail across `BuildPendingTabs` flushes. Consumers call `RegisterTab` back-to-back (Tracked registers Icons then Bars); if the panel is already open the first call flushes before the second queues, and without the tail pointer the second tab would re-anchor to `AurasTab` and overlap the first.
- Extension tabs never call `SetDisplayMode` — each click is a fire-and-forget action and the panel's content stays on whatever the user last selected. The plugin has no settings, no persistent state, no spec data, and cannot be disabled from the Orbit panel (`liveToggle = false`).

## References
- Consumers: `Plugins/Tracked/README.md`; sibling: `Plugins/CooldownManager/README.md`.
- Skills: `/wow-frames` (taint, hook patterns).
- Blizzard source: `agent/wow-ui-source/` Blizzard_CooldownViewer (CooldownViewerSettings, LargeSideTabButtonTemplate).
