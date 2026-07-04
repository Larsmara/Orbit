# Color

## Description
Color resolution systems: convert abstract identifiers (class, reaction, curve position) into concrete `{ r, g, b, a }` values.

## Purpose
Decouples color logic from rendering — plugins and skinning ask "what color should this be?" and the resolvers answer without knowing who asked.

## Implementation
| File | Role |
|---|---|
| ClassColorResolver.lua | `Engine.ClassColor` — class → rgb, with per-class user overrides stored in `AccountSettings` (`ClassColor_<CLASS>`, key strings memoized for the hot health-text path); PRIEST defaults to near-white |
| ReactionColorResolver.lua | `Engine.ReactionColor` — reaction (hostile/neutral/friendly) plus renown/paragon → rgb; overrides in `AccountSettings` (`ReactionColor_<TYPE>`) |
| ColorCurveEngine.lua | `Engine.ColorCurve` — evaluates multi-pin color curves at a clamped 0–1 position (`SampleColorCurve` / `SampleColorCurveUnpacked`); `class`-typed pins resolve through `ClassColor`. Powers gradient bars and dynamic timer colors |

Overrides flow account-wide (profile-immune) through the `AccountSettings` doors, never `OrbitDB` layout. New resolvers expose `Engine.<Name>`, resolve input → `{ r, g, b, a }`, and load via a `<Script>` entry in `Color.xml` — never the `.toc`.

## Gotchas
- Resolvers hold no frame references and no per-call mutable state; persistent override state belongs in `AccountSettings` only.
- `Engine.ColorCurve` is the only curve/gradient sampler in the codebase — never reimplement curve sampling elsewhere.
- Color tables are `{ r, g, b, a }`, never indexed arrays.
- Curve data carries lazily built runtime caches (`_sorted`, `_hasClassPin`) derived from `pins` — never persist them in defaults or profiles.

## Secrets
`SampleColorCurve` does Lua arithmetic on its position argument, so it must receive a plain number. Secret progress values are converted upstream through a `C_CurveUtil` identity curve first (see `UnitDisplay/HealerAuraTicker.lua`), then fed here.

## References
`Core/UnitDisplay/README.md` (curve consumers), `Core/Skinning/README.md` (tint application), /wow-secrets (curve patterns for secret values).
