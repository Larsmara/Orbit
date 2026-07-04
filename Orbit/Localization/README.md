# Localization

## Description
All player-facing strings for the Orbit addon suite, resolved once at load into `Orbit.L` — a flat `KEY = "translated string"` table. Consumers do `local L = Orbit.L` at file top and use `L.KEY` at the call site.

## Purpose
One central registry so no user-visible English is ever hardcoded (schemas, config, slash output, popups, errors, tours), with load-time validation (collisions, format-string placeholders) and a pre-commit lint instead of runtime surprises.

## Implementation
`Orbit.toc` loads `Localization\Localization.xml` between `Core\Libs\Libs.xml` and `Core\Init.lua` — `Boot.lua` first, then the domain files — so `Orbit.L` exists when plugin schema `label = L.KEY` fields are evaluated at file-load time. Each `Domains/*.lua` file owns exactly one key prefix and is a locale-table declaration (`enUS = {...}, deDE = {...}, ...`) followed by `Orbit.Localization.Install(LOCALE_STRINGS, "Name")`. Prefixes: `CMN_` Common, `CFG_` Config, `PLG_` PluginManager, `PLU_` Plugins, `CMD_` SlashCmds, `MSG_` Messages, `TOUR_` Tours (full table in root `CLAUDE.md`).

`Boot.lua` seeds `Orbit.L` (a metatable `__index` logs undefined reads when `Orbit.DEBUG_LOCALIZATION` is on), resolves the active locale from the dev override `OrbitDB.AccountSettings.LocaleOverride` falling back to `GetLocale()`, and `Install` merges each domain into `Orbit.L`: `enGB`→`enUS` / `esMX`→`esES` aliasing, per-key enUS fallback, cross-domain collision errors, and `_F` placeholder-count validation. `Orbit.Localization.Rebuild()` re-resolves the locale and re-merges every registered domain at runtime, firing `ORBIT_LOCALE_REBUILT` so consumers that baked `label = L.KEY` at file load (e.g. CanvasMode schemas) can rebuild; it runs on `ADDON_LOADED` if the override wasn't visible at file-load time.

Locale override for testing: Spotlight → Tools → Orbit Language (open Spotlight, type `orbit`) calls `Orbit.Localization.SetLocaleOverride(code)`, which writes `OrbitDB.AccountSettings.LocaleOverride` and prints "Please Reload UI"; pick Default to clear it.

Adding a string:
1. Pick the domain by prefix; add the key to that file's `enUS` table.
2. Use `L.NEW_KEY` at the call site.
3. Translate the key into **all 8** non-English locales in the same file. Full parity is policy — the per-key enUS fallback is a safety net, not a workflow; a key left untranslated shows English to non-English players and regresses parity (call it out in your PR if you genuinely can't translate it).
4. Run `python .scripts/check-localization.py` before commit (`VERBOSE=1` also lists unused keys). It verifies every `L.KEY` reference resolves, prefix isolation (each prefix in exactly one file), and no cross-domain collisions; it is the CI gate in `lint.yml`.

Supported locales: `enUS` (+`enGB`), `deDE`, `frFR`, `esES` (+`esMX`), `ptBR`, `ruRU`, `koKR`, `zhCN`, `zhTW`. Aliases resolve inside `Install` — never declare them in domain files.

## Gotchas
- Save domain files **UTF-8 without BOM**. A BOM makes WoW's Lua loader silently fall back to enUS for the whole file; `.editorconfig` enforces this for editors that honor it.
- `_F` suffix = format string: use `:format()` at the call site, never concatenate. `Install` validates placeholder *count* per locale (a mismatch logs via `geterrorhandler()` and falls back to enUS so `:format()` never throws) but not *order* — a locale whose grammar reorders arguments must use positional specifiers (`%1$s`, `%2$d`); reordered bare `%s` silently binds the wrong argument and neither `Install` nor the lint catches it.
- Never split a prefix across files, and never invent a prefix without adding a domain file *and* updating `PREFIXES` in `.scripts/check-localization.py`.
- `SetLocaleOverride` never calls `ReloadUI()`: it is protected and the user-action context is gone once the click handler returns (`ADDON_ACTION_BLOCKED`). The user types `/reload`; `Boot.lua` reads the override on the next load.
- Debug undefined keys in-session with `/run Orbit.DEBUG_LOCALIZATION = true` — zero cost when off, since the `__index` only fires for missing keys.
- Deliberately outside this system: `Core/Shared/TooltipParser.lua` keeps a file-local locale table — its strings are runtime regex patterns for tooltip duration parsing, never displayed to the user.

## References
- Root `CLAUDE.md` — prefix→domain table and the summary rules.
- `.scripts/check-localization.py` and `.github/workflows/lint.yml` — the lint gate.
- `Boot.lua` — install/merge/override/rebuild mechanics.
- `QoL/Spotlight/Index/Help/Topics/Tools.lua` — the Orbit Language menu.
