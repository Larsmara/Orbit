# StatusWidget

## Description
A circular (radial) progression orb that replaces Blizzard's bottom XP/reputation/honor bar. Right-click picks the at-rest fill source (auto / XP / reputation / honor / housing / currency) and a hover+Shift secondary; the hollow centre is a flourish hub that replays suppressed Blizzard toasts (Great Vault, social, mail, loot, loot rolls, milestones, reward alerts, repair) and becomes a Mythic+ tracker during a key.

## Purpose
One glanceable orb instead of Blizzard's tracking bar plus a dozen toast frames. Self-contained plugin (system id `Orbit_StatusWidget`) — depends only on Core; the QoL `NpcAutomation` repair integration is inverted via the `ORBIT_NPC_REPAIRED` EventBus event so QoL never reaches into this plugin.

## Implementation
Fill path: `BuildRecord` runs a resting cascade — `_BuildForSource(PrimarySource)`, falling to `_BuildForSource(SecondarySource)` when the primary record is `empty` (tracks nothing), and marking `_restEmpty` when both are empty so the ring hides at rest. Hover+Shift peeks the secondary directly (re-resolved on `MODIFIER_STATE_CHANGED`). Each builder (`XPRecord` / `BuildRepRecord` / `HonorRecord` / `CurrencyRecord` / `HousingRecord` / `MythicPlusRecord`) returns `{mode, name, level, current, max, color[, empty]}`; `RenderFill` drives a paused Cooldown swipe via `CooldownFrame_SetDisplayAsPercentage` + `SetSwipeColor`, zeroing it on `empty`. Housing favor is async — `GetCurrentHouseLevelFavor` is a request, so `Housing.lua` caches the `HOUSE_LEVEL_FAVOR_UPDATED` payload and `_HousingTracked`/`_HousingReady` gate the menu entry and auto preference.

Flourish path: every centre event goes through `Plugin:Enqueue` (`FlourishQueue.lua`) — 3s buffer, 5s idle linger, `selfPaced` for the loot reel, end animation skipped when a request waits. The queue calls the matching `_Render*` after `_EnterEvent`/`_ClearCenterFX` reset the centre; the durability warning and idle centre number yield to any flourish.

| file | role |
|---|---|
| `StatusWidget.lua` | frame build, mode resolution, radial fill, settings, centre-FX hub (`_RenderMilestone`, impact set, durability warning) |
| `FlourishQueue.lua` | `Plugin:Enqueue` serialization: buffer/linger timing, `_FqAdvance`/`_FqBurstDone` |
| `GreatVault.lua` | wraps `EventToastManagerFrame.DisplayToast`, drains vault toasts into `PlayVaultFlourish`; `/orbitvault` |
| `SocialToast.lua` | `hooksecurefunc(AlertFrame_ShowNewAlert)` capture of `SocialToastTemplate` frames; `/orbitsocial` |
| `Mail.lua` | `UPDATE_PENDING_MAIL` false→true `HasNewMail()` transition → `PlayMailFlourish`; `/orbitmail` |
| `Loot.lua` | `BOSS_KILL`/`ENCOUNTER_LOOT_RECEIVED` + `SHOW_LOOT_TOAST` reel; suppresses BossBanner + loot alerts; `/orbitloot` |
| `LootRoll.lua` | `START_LOOT_ROLL` styled roll panels + bonus roll; suppresses GroupLootFrames; `/orbitroll`, `/orbitbonus` |
| `Milestones.lua` | `PLAYER_LEVEL_UP` / `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` / `HONOR_LEVEL_UPDATE` productions; `/orbitlevel` |
| `AlertToasts.lua` | reward-alert matcher (achievement/mount/pet/...) → icon flourish; `/orbittoast` |
| `Repair.lua` | `ORBIT_NPC_REPAIRED` → crosshair + coin-cost flourish; `/orbitrepair` |
| `FillModes.lua` | `CurrencyRecord`, eligible-currency picker, currency-gain flourish |
| `Housing.lua` | House Favor async cache + fill source |
| `MythicPlus.lua` | key tracker: timer fill, centre timer + forces %, side info panel, toast silencing; `/orbitmplus` |
| `Animation.lua` | hover/event reveal (slide/rotate/fade) on `frame.Content`, never the frame anchor |
| `SourceMenu.lua` | right-click radio menus writing `PrimarySource`/`SecondarySource` (+ per-slot currency ids) |

Blizzard bar suppression: `NativeFrame:SecureHide(StatusTrackingBarManager)` on load, plus `Orbit:RegisterBlizzardHider` for the PluginManager's Both-disabled tri-state; the plugin is `liveToggle`, so `OnDisable` hands the bar back unless the tri-state still hides it. Blizzard's `DurabilityFrame` is force-hidden the same way (flag-gated `Show`/`SetShown` hook, since the orb renders its own durability warning) and handed back via `SetAlerts` on live-disable; its VisibilityEngine row is `ownedBy = "Status Widget"`. All settings via `PluginMixin` (scale, per-mode colours, per-toast Replace/Show toggles, `Animation`, `MPlusEnabled`; `MPlusCollapsed` is persisted view state with no schema control).

## Gotchas
- Hidden-at-rest is data-driven, not the Animation dropdown: when `_restEmpty`, `RestingTarget` returns 0 even at `ANIM_NONE` (which now honors `progress` as alpha). `UpdateBar` calls `ConcealOrb` last to reconcile it once `_restEmpty` + durability state is fresh. Anything actioned re-reveals — `RestingTarget` returns 1 for hover / `_event` / M+ / `_DuraWarnActive`, so flourishes, keys and durability warnings always show; the frame keeps `EnableMouse` so an invisible orb stays hoverable. EditMode forces 1 so an empty orb is still draggable.
- Toast suppression MUST be `hooksecurefunc` on `AlertFrame_ShowNewAlert`, never a global replacement — replacing the global taints secure code that reads the environment (surfaced as `CompactUnitFrame_UpdateHealthColor` "execution tainted by Orbit").
- GroupLootFrame suppression must be `HookScript("OnShow")` per frame: the XML bound `OnShow` to the original function reference, so a `hooksecurefunc` on the global never fires; hooking `GroupLootContainer_Update` instead collapses the container's layout slot.
- Prey-hunt mode was removed (revisit only with a taint-safe design): reading live UIWidget payloads / scanning monster chat during a hunt tainted Orbit's shared execution. Corollary: instanced-run event reads use dedicated `CreateFrame` listeners, never the shared EventBus frame (`Loot.lua`, `MythicPlus.lua` follow this).
- Live-toggle teardown: the framework's disable only hides the frame — it can't reach raw `C_Timer`s, the three UIParent-parented OnUpdate drivers, or the permanent suppression hooks. `OnDisable` quiesces and nils the drivers itself; `_disabled` no-ops `Enqueue` and makes the hooks pass Blizzard's UI through.
- M+ silencing (`_MPlusSilencing` = `_mplusActive`) is deliberately distinct from `_disabled` — silencing drops toasts, `_disabled` hands them back to Blizzard. `Enqueue` is the silencing chokepoint; each Blizzard-suppression hook ORs it in.
- A FlipBook reverts the texture's texcoords after `OnFinished`, so the vault FX's held final frame lives on a separate static texture whose texcoords are copied inside `OnFinished` before the revert.
- M+ math: with Challenger's Peril (affix 152) the +2/+3 deadlines are `(par-90)*0.8+90` / `(par-90)*0.6+90`; the death penalty is already inside `GetWorldElapsedTime` — adding `timeLost` again double-counts (both bugs shipped once, since fixed).
- Bonus roll (`LootRoll.lua` `_ShowBonusRoll`): the server fires `SPELL_CONFIRMATION_PROMPT` on *every* eligible boss kill — Blizzard's own frame is what suppresses it when the player holds none of the required coin (`GetCurrencyInfo().quantity == 0`), so the replacement must replicate that gate (with the `currencyID == 0 → BONUS_ROLL_REQUIRED_CURRENCY` fallback) or it shows on every kill. The `/orbitbonus` preview (nil spellID) is exempt.
- `ENCOUNTER_LOOT_RECEIVED` args follow BossBanner (`encounterID, itemID, itemLink, quantity, playerName, className`) — the auto-generated docs mislabel slots 5-6.
- `BackdropColor` tints a dedicated `BackdropRing` texture, not the track: the track art is baked near-black and `SetVertexColor` multiplies, so it can only darken.
- `showToastWindow` is read once at `VARIABLES_LOADED` with no live callback — `EnforceToastCVar` forces it on and also calls `BNToastFrame:SetToastsEnabled(true)` to re-register events without a `/reload`.
- Cracked-metal durability art: shading is baked into RGB with alpha carrying only plate shape — baking shading into alpha made shadowed plates translucent (read as glass; took several passes to spot). Durability is a timed warning, not a fill source, and it outranks the M+ centre.
- The swipe orientation is tuned to the baked asset — if a `/reload` shows it mirrored, flip `FILL_REVERSE` / adjust `FILL_ROTATION`. `SetSwipeTexture` has no filterMode arg, so the fill ships as a mip-chained `.blp` (the `.tga` stays as fallback) to stay crisp at low Scale.
- `Animation.lua` animates `frame.Content` only — never the frame itself — so the EditMode/`RestorePosition` anchor is untouched; the frame keeps its mouse footprint while concealed.

## Secrets
`CooldownFrame_SetDisplayAsPercentage` does Lua arithmetic, so `RenderFill` guards `issecretvalue(current)`/`issecretvalue(max)` (and `max <= 0`) first; a secret value holds the last displayed percentage. `GetXPExhaustion` is issecretvalue-dropped (XP goes secret in encounters). M+ run data (timer, deaths, key level, affixes, completion) is non-secret; scenario forces and boss `completed` flags are issecretvalue-guarded as belt-and-suspenders. Loot and roll fields are non-secret. Re-run `/wow-secrets` before relying on new fields.

## References
- `Core/EditMode/README.md` — the `SecureHide` state-driver contract for status tracking bars.
- Radial assets: `Core/assets/Radial/orbit-radial-*.tga` (+ `.blp` fill), generated by `_scratch_renown/gen_v5.py` / `tga2blp.py`.
- Blizzard source: `agent/wow-ui-source` — `EventToastManager.xml` (vault FlipBook params), `ScenarioTimerMixin`, BossBanner.
- Skills: `/wow-secrets`, `/wow-frames`, `/pixel`. Reveal animation modelled on Orbit-Dock-Portal's `PortalReveal`.
