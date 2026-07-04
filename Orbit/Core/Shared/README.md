# Shared

## Description
Project-wide constants, media registrations, and shared cross-plugin services: the glow stack, cooldown metadata, drag-drop resolution, the private tooltip, and secret-value helpers. Loads before all other Core modules.

## Purpose
Single source of truth for constants, plus the home of behavior shared by multiple plugins that belongs to no one domain (glows, cooldown data, drop zones). Depends only on libs.

## Implementation
| File | Role |
|---|---|
| Constants.lua | all project constants: colors, `C.Levels`, `C.BorderStyle`, cooldown indices, glow configs, aura skin presets |
| Media.lua | LibSharedMedia font/texture registrations |
| Tooltip.lua | `Orbit.Tooltip` — private `GameTooltipTemplate` frame (`OrbitTooltip`) all Orbit hover tooltips use |
| WhitelistedSpells.lua | raw category tables (`CLASS_RESOURCES`, `HEALER_AURAS`, `RAID_BUFFS`, `COMBAT_RES`) read by `UnitDisplay/GroupAuraFilters.lua`; no query API |
| PlayerDummies.lua | dummy unit data for config-panel previews |
| SecretValueUtils.lua | `SafeUnitPowerPercent` (pcall'd C sink), `NumericOrNil` (issecretvalue gate) |
| CooldownData.lua / CooldownLearn.lua / TooltipParser.lua | cooldown metadata + duration learning (flow below) |
| CooldownUtils.lua / CooldownDragDrop.lua | icon dimension math; pure cursor → cooldown-ability resolver and saved-entry builders (`TrackedItems`/`InjectedItems`/`TrackedBarSpell`) |
| GlowUtils.lua / GlowController.lua / SpellGlows.lua / DropZoneGlow.lua | glow stack (flow below) |
| IconCastState.lua | range/usable/ready tinting + OOR shadow + ready flash, refcounted `C_Spell.EnableSpellRangeCheck` |

Glow flow: `GlowUtils` builds LibOrbitGlow option tables from DB settings → `GlowController` is the single owner of all glow rendering (state on `frame._orbitGlow`; native Blizzard overlay suppression; pandemic wrapper frames). `SpellGlows` layers the per-icon conditional glow menu (proc/pandemic/active + sounds) and the shared `SPELL_ACTIVATION_OVERLAY` proc driver; it owns no storage — every surface passes get/set closures to `OpenMenu`. `DropZoneGlow:Attach(zoneFrame, r, g, b, outset)` wraps drop zones; a shared 0.1s ticker gates visibility on `CooldownDragDrop:IsDraggingCooldownAbility()` AND the zone being visible.

Cooldown metadata flow: `CooldownData` keeps a spellID → cooldownInfo reverse lookup over C_CooldownViewer, rebuilt lazily on spec/talent events. `ResolveActiveDuration` walks curated overrides → tooltip parse (`TooltipParser`) → aura-learn watch (`CooldownLearn` — one self-disabling UNIT_AURA listener; `Request` one-shot multi-subscriber, `RequestOnce` keyed dedupe shared by Tracked + ViewerInjection).

## Gotchas
- Constants.lua and Media.lua hold declarations only — no logic, no references to other modules. Extract magic numbers here or to the consuming file's top-level constants; never duplicate a value inline.
- All glow rendering goes through `GlowController`; no consumer calls LibOrbitGlow (`LCG.Show`/`Hide`) directly.
- `SpellGlows` surfaces must call `UnregisterProc` when a pooled icon is released or changes type, or the next occupant inherits proc state.
- `IconCastState` release paths must `Untrack`, or the next occupant inherits tint state and range-check streams leak (the `EnableSpellRangeCheck` refcount never drops).
- Never own the global `GameTooltip` from addon code — it taints Blizzard's secret-handling unit-tooltip pipeline (`SetWorldCursor`) in 12.0+. Alias `local GameTooltip = Orbit.Tooltip`.
- `CooldownData:GetBaseCooldownSeconds` returns nil for base-cd-0/secret spells so callers keep last-known values instead of zeroing.
- `DropZoneGlow` renders at Background strata / frame level 0 beneath the zone's own textures; `outset` accepts a number or a function (CDM passes a function to track live `GlobalSettings.BorderSize`).

## Secrets
`SecretValueUtils.NumericOrNil` gates with `issecretvalue` before any Lua op — `or 0` does not catch a secret (secrets are truthy) and `string.format` on one throws. `SafeUnitPowerPercent` pcalls `UnitPowerPercent` with the `CurveConstants.ScaleTo100` curve — a permitted throwing-C-API boundary. `CooldownDragDrop` issecretvalue-guards its `GetSpellBaseCooldown` / `C_Spell.GetSpellCharges` comparisons so drop acceptance never throws in combat; the tooltip parse is the in-combat final word for spells those APIs won't report.

## References
/wow-secrets, /unsecreted, /ki-abilities (CooldownManager/Tracked consumers), `Core/UnitDisplay/README.md` (aura-side consumers), `Core/Libs/` (LibOrbitGlow).
