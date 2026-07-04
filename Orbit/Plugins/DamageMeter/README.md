# DamageMeter

## Description
Multi-instance, minimal-chrome damage/healing/etc. meter rendered by Orbit on top of Blizzard's native 12.0 data pipeline (`C_DamageMeter.*` + `DAMAGE_METER_*` events). Blizzard's own DamageMeter UI is hidden; Orbit frames do all rendering.

## Purpose
Blizzard ships the data, we ship the UI. Users create up to `DM.MaxMeters` (5) meters, one metric each (e.g. DPS + HPS + interrupts). A seed meter at id 1 is auto-created and undeletable so at least one meter always exists; new meters come from the settings-dialog footer button, metric selection and delete from the in-world context menu (shift+right-click or title click).

## Implementation
| file | role |
|---|---|
| `DamageMeterConstants.lua` | every constant: system id, `MaxMeters`, seed id, enums, `DefaultDef`, `ORBIT_DAMAGEMETER_*` signal names |
| `DamageMeter.lua` | registration, lifecycle, meter-def factory (`CreateMeter`/`DeleteMeter`/`EnsureSeedMeter`), view-mode transitions, `damageMeterEnabled` CVar, per-meter Get/Set routing through `MeterDefs[id]` |
| `DamageMeterData.lua` | thin adapter over `C_DamageMeter.*`; sink-only, never arithmetic on returned numbers |
| `DamageMeterEventBridge.lua` | forwards `DAMAGE_METER_*` to `ORBIT_DAMAGEMETER_*` on `Orbit.EventBus` |
| `DamageMeterDisable.lua` | `DisableBlizzardMeter`: hides the Blizzard `DamageMeter` frame + all session windows (combat-guarded); the `damageMeterEnabled` CVar = 0 keeps `UpdateShownState` from re-showing it |
| `DamageMeterSettings.lua` | two-tab dialog: Layout (per-meter styling into `MeterDefs[id]`), Behaviour (per-meter `autoSwitch` + a plugin-global proxy for the `damageMeterResetOnNewInstance` CVar); footer New Meter button |
| `DamageMeterUI.lua` | multi-instance frame factory; chart / breakdown / history views, mouse-wheel rank scroll, edit-mode dummy preview; exposes the breakdown-frame trio the popup module reuses |
| `DamageMeterBreakdownPopup.lua` | transient Mouseover/Detached breakdown windows; synthetic def = live styling + hovered source; nothing persisted, self-hide on combat start / profile change / Edit Mode / delete / `/reload` |
| `DamageMeterComparison.lua` | `OrbitDamageMeterComparison` popup comparing a source against per-spec averages |

Lifecycle: `OnLoad` → ensure Blizzard addon loaded + CVar → event bridge → UI → `RebuildAllMeters` (→ `EnsureSeedMeter` → `NormalizeMeterDefs` → `ScrubStaleAnchors` → teardown stale frames → layout). `PLAYER_ENTERING_WORLD` re-ensures the addon and (0.5s later) `DisableBlizzardMeter`. `ORBIT_PROFILE_CHANGED` → `RebuildAllMeters`. `ApplySettings` self-heals: rebuild if the frame registry and `MeterDefs` disagree, else relayout. `NormalizeMeterDefs` backfills partial defs from `DM.DefaultDef`; `ScrubStaleAnchors` snapshots a dangling anchor target into `def.position` and clears it.

Skin inherits `Orbit.db.GlobalSettings` (font, bar texture, border) — no per-meter override. Anchoring uses the standard Orbit snap system with only `orbitWidthSync`: T/B stacking propagates root width down the stack; L/R placement is a plain anchor with no height sync (height = `barCount × barHeight + gaps`, always the plugin's). Removed vs the earlier draft: phases, session archive, chat report, quadrant flipping — update the file table if reintroducing.

## Gotchas
- `ApplySettings` only re-renders/relayouts — it must NEVER call Blizzard's DamageMeter mutators, which taints the entry data provider.
- Frames build eagerly at `OnLoad` (the plugin can be enabled mid-session; deferring to PEW would draw nothing until a zone change), but `DisableBlizzardMeter` stays on PEW because `Blizzard_DamageMeter` loads lazily and the root frame may not exist at `OnLoad`.
- `InCombatLockdown()` is NOT a sufficient secret gate: it can read false while a struct field is already secret, and a throttled hover/ticker/click can fire in that window — guard each secret-prone value at its boundary.
- Secrets never un-secret: a bar's cached `_source.sourceGUID` captured mid-fight keeps the breakdown issecretvalue-blocked after combat, and leaving combat fires no `DAMAGE_METER_*` update — `PLAYER_REGEN_ENABLED` sets `_renderDirty` so the next ticker re-renders from a fresh, now-plain fetch.
- Parent deletion never walks into anchored children; the child's def detects the stale target on the next rebuild (`ScrubStaleAnchors`) and reverts to a free position on its own.
- Popup border/background are coerced frame-wide (a popup is one panel, never per-bar); `FitAllSpells` overrides bar count with the source's spell count (capped `MaxBarsStretch`) so popups need no scroll.
- The reset-on-new-instance setting stays plugin-global — it proxies a CVar that resets Blizzard's shared session pipeline every meter reads from.
- Bars always stack rank 1 at the top, fill grows left-to-right; edit-mode vertical resize writes `TotalHeight`, converted to barCount.

## Secrets
`totalAmount`, `amountPerSecond`, `maxAmount`, `durationSeconds`, `deathTimeSeconds` are potentially secret in combat. The render path only writes them to C++ sinks: `StatusBar:SetMinMaxValues/SetValue`, `FontString:SetFormattedText` with `AbbreviateLargeNumbers` (the C-side formatter Blizzard's own entry mixin uses). Never compared, never arithmetic-ed; `combatSources` is server-ranked, so no Lua sort.

- `SafeFormatDuration(seconds)` (`DamageMeterUI.lua`) is the only legal duration→string path — it issecretvalue-guards before the floor/modulo math; secret values render as `""` until combat ends. History bar scaling skips the max-duration scan entirely when any entry is secret (denominator 1.0) rather than arithmeticing.
- `sourceGUID`/`sourceCreatureID` and `name` are secret in combat, and `name` is ConditionalSecret independently of the GUID — guarding the GUID alone is not enough.
- `Data:ResolveSessionSource` is the single chokepoint for the `C_DamageMeter.GetCombatSession*` calls (all `AllowedWhenUntainted`, so a secret arg throws): it returns nil when either identifier is secret, covering every caller (breakdown render, wheel, row count, comparison, popup).
- Capture sites (drill-in, `TargetFromSource`) reject or blank a secret GUID/name before it lands in a def — otherwise it later throws in `UpdateMeterDef`'s equality check or `BuildTitleText`'s `~= ""`. Gather/compare/atlas sites (`GatherSpellMatrix`, `GetSpecMatches`, `PickHistoryAtlas`) guard before any `~=`/table-key/`:sub`; downstream layout math runs only on laundered plain numbers.
- `RenderBreakdownPopups` is combat-guarded (source GUIDs go secret in combat).

## References
- Skills: `/wow-secrets` (current classification — re-run before trusting any field), `/unsecreted` (verifying whether a flagged violation is real).
- Blizzard source: `agent/wow-ui-source` — `Blizzard_DamageMeter` (entry mixin, session windows, `UpdateShownState`).
- `Core/Plugin/README.md` (settings routing, profile lifecycle); the anchor/snap system in `Core/Frame/`.
