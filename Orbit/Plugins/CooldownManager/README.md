# CooldownManager

## Description
Hooks Blizzard's native cooldown viewer system (`EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`, `BuffBarCooldownViewer`) to provide skinned, repositionable cooldown displays, plus drag-and-drop injection of custom spells/items into the essential/utility viewers.

## Purpose
Keeps Blizzard's viewers as the data source (which spells, when they're on cooldown) while Orbit owns position, layout, skin, text, and glows. Fully decoupled from the Tracked plugin, which renders user-authored surfaces from scratch.

## Implementation
| File | Role |
|---|---|
| CooldownManager.lua | plugin (`Orbit_CooldownViewer`); one Orbit anchor per viewer, `VIEWER_MAP` (system index → Blizzard viewer + anchor), spec-data helpers |
| CooldownViewerHooks.lua | `hooksecurefunc` on viewer item mixins (`OnCooldownIDSet`, `OnActiveStateChanged`) and on viewer `UpdateLayout`/`RefreshLayout`/`SetPoint`/`Hide` to re-layout and re-anchor |
| CooldownLayout.lua | icon grid math; out-of-combat spellID caching; native timer color curves |
| CooldownText.lua | timer/charges/stacks/keybind text, fonts, canvas preview setup |
| CooldownGlows.lua | pandemic glows (hooks `ShowPandemicStateFrame`/`HidePandemicStateFrame`) and proc glows (`ActionButtonSpellAlertManager`), both rendered by `GlowController`; per-spell glow/colour/alert store; shift-right-click menu via `Orbit.SpellGlows:OpenMenu` |
| CooldownSettings.lua | settings schema with layout/glow/colour sub-tabs |
| ViewerInjection.lua | drag-drop injection; owns its cursor watcher; per-spec persistence |

Shared dependencies in `Core/Shared/`: `CooldownUtils.lua` (icon dimensions, `BuildSkinSettings` with `iconBorder = true`), `TooltipParser.lua` (active/cooldown duration extraction), `CooldownDragDrop.lua` (cursor → spell/item resolution, `BuildInjectedItemEntry`).

Data lands per character and per spec in `OrbitDB` spec data via `GetSpecData`/`SetSpecData`: injected items (`InjectedItems`) and the per-spell glow/colour/alert store keyed by cooldownID (`GetSpellGlowValue`/`SetSpellGlowValue`/`SpellGlowLookup`). Injected frames are CDM-owned, parented to the Orbit anchor, and positioned relative to native icons via `afterNativeIndex` with cross-parent `SetPoint`. Equipment-slot tracking auto-updates injected trinkets on gear change; Spotlight's Flush Cooldowns action clears all injected icons.

## Gotchas
- The glow store lives in spec data, never `GlobalSettings` — that is profile-cloned theme data, so a profile or spec switch would wipe it.
- Injected frames must never be parented to Blizzard's secure viewer (taint); `SetPoint` against a native icon works fine without shared parentage.
- `ViewerInjection` owns its own `StartCursorWatcher`. It used to piggyback on a shared cursor watcher in the old Tracked plugin's `TrackedUpdater.lua`, and drop handling silently broke the moment that file was deleted — keep the flow self-contained.
- Proc alert sounds fire once per proc edge and are cooldownID-stamped so button reassignment re-arms them.
- Zero dependencies on `Orbit_Tracked`. Sub-files reach the parent via `Orbit:GetPlugin("Orbit_CooldownViewer")` — acceptable intra-domain reference.
- Cooldown update paths run on `OnUpdate`: no allocations, no string concatenation.
- Glow types come from `Constants` (`PandemicGlow.Type`, `Glow.Type`); never hardcode glow type ids.

## Secrets
Live `GetSpellID` reads on viewer items are secret in combat. `CooldownLayout` caches `orbitCachedSpellID` out of combat (drop-time capture); every consumer — glow lookups, TTS alert name resolution, aura matching — reads the cache and guards comparisons with `issecretvalue` first (`cached == spellID`, `wasSetFromAura`). Timer text coloring goes through native color curves (`ColorCurve:ToNativeColorCurve`) so remaining-time never touches Lua arithmetic; desaturation uses a static `C_CurveUtil` curve.

## References
- `Core/Shared/README.md` (CooldownUtils, CooldownDragDrop, GlowController, SpellGlows, TooltipParser).
- `Plugins/Tracked/README.md` (the decoupled sibling), `Plugins/CooldownViewerExtensions/README.md`.
- Skills: `/wow-secrets` (C_CooldownViewer classification), `/ki-abilities`, `/wow-frames`.
- Blizzard source: `agent/wow-ui-source/` Blizzard_CooldownViewer.
