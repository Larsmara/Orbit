# Spotlight

## Description
Hotkey-driven universal search across bags, equipped gear, spellbook, toys, mounts, pets, heirlooms, professions, currencies, macros, quest items, and a curated `help` catalog. Account-wide QoL — no user-arranged UI.

## Purpose
One search box for everything the player owns or can do. Always enabled: `Spotlight:Enable()` runs unconditionally on `PLAYER_LOGIN`, there is no on/off toggle. Other modules toggle it via `Orbit.EventBus:Fire("ORBIT_SPOTLIGHT_TOGGLE")`; the key binding lives in `Orbit/Bindings.xml` at the addon root (WoW rejects `<Binding>` elsewhere).

## Implementation
Data enters from one source file per kind in `Index/Sources/`. Each declares `kind`, `events`, `persistent`, optional `signature()`, and `Build()` returning entries:

```lua
{ kind, id, name, lowerName, icon, secure = { type = "...", ... } | onClick = function(entry) end }
```

`Index/IndexManager.lua` registers every source's events, dirty-marks sources on event fire, and rebuilds the master list debounced (0.5 s). Persistent sources (mounts, pets, toys, heirlooms) cache in `Orbit.db.AccountSettings.SpotlightIndex`, version-gated (`CACHE_VERSION`) and invalidated when the source's declared signature changes; volatile sources rebuild from live APIs. Nothing builds at login — first build happens on first Open.

Query path: `UI/SpotlightFrame.lua` (center-anchored on `UIParent`, input debounced 50 ms) folds the query via `Search/Tokenize.lua` (lowercase + diacritic strip — the same fold precomputed into entry `lowerName` at index time), then `Search/Matcher.lua` ranks exact > prefix > word-start > substring with a bounded fuzzy fallback and `KIND_PRIORITY` ordering. Results render into `UI/ResultRow.lua` secure-action-button rows, pooled lazily by `UI/RowPool.lua`; `UI/ClickOutsideCatcher.lua` closes on outside mouse-down. Supporting index files: `ItemKeywords.lua` folds localized type/slot/binding terms into item `lowerName` so items match by attribute ("ring", "warbound"); `MountTypeTags.lua` adds ground/flying/aquatic/dragonriding tags; `Recents.lua` boosts recently activated entries; `Favorites.lua` handles right-click favoriting. The `help` kind is authored content — see `Index/Help/README.md`.

Kinds are data-driven from the `Spotlight.Kinds` table in `Spotlight.lua`: one row (`kind`, `settingKey`, `labelKey`, optional `aliasTokens` = extra exact-match prefix words) drives the config toggle in `Core/Config/Advanced/QoL.lua`, the enabled-kinds filter, and the row's kind label. Settings, all in `Orbit.db.AccountSettings`: `Spotlight_Src_<Source>` (per-source toggle), `Spotlight_MaxResults` (10–100, default 100), `Spotlight_Scale` (0.70–1.30; applied via `SetScale` on each Open, borders re-skinned against the new effective scale), `Spotlight_Fuzzy`, `Spotlight_HidePassives`, `SpotlightIndex` (internal cache).

Adding a source: new `Index/Sources/<Name>.lua` per the contract → `<Script>` line in `Spotlight.xml` before `IndexManager.lua` → one `Spotlight.Kinds` row → `PLU_SPT_SRC_<NAME>` key in every locale (`Localization/Domains/Plugins.lua`) → entry in `KIND_PRIORITY` (`Search/Matcher.lua`).

## Gotchas
- Activation is mouse-only by design. Programmatic `row:Click()` from a Lua keyboard handler taints the secure dispatch (`ADDON_ACTION_FORBIDDEN` on protected verbs), so Spotlight never intercepts Enter/arrows — only hardware left-click fires the untainted secure attributes. The EditBox propagates non-typing keys so global bindings still work while focused.
- `Toggle()`/`Open()` short-circuit in combat with a print, and the frame auto-closes on `PLAYER_REGEN_DISABLED`; while closed no secure attributes are rewritten, so combat lockdown can't be tripped. It also closes on `PLAYER_SPECIALIZATION_CHANGED` to drop stale spellbook attributes before they dispatch the old spec's spells.
- `ResultRow:Bind` rebinds a source's bare `type` attribute as `type1`: `SecureActionButtonTemplate` treats bare `type` as an any-button fallback that would swallow right-click. With only `type1` set, right-click falls through to Lua `PostClick` → favorite toggle (mounts/pets/toys only). The handler mutates `entry.favorite` in place — the same table is shared with the master index and the SavedVariables cache.
- Mount favoriting goes through display-index-based `C_MountJournal.SetIsFavorite`, so mounts hidden by the journal's filter can't be toggled; `canFavorite == false` mounts (faction-restricted etc.) are skipped silently.
- Shift+left-click inserts a chat link; rows bind `shift-type1 = "macro"` with empty macrotext so the shift-click can't use/consume the entry. Left-drag picks the entry up onto the cursor and closes Spotlight.

## References
- `Index/Help/README.md` — the authored help kind.
- `../README.md` — QoL conventions (account-wide settings, loader pattern).
- `Core/Config/Advanced/QoL.lua` — settings panel.
- `/wow-frames` — secure templates and taint rules behind the activation design.
