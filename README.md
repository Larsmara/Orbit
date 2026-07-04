# Orbit

<p align="center">

[![Join Discord](https://img.shields.io/badge/Discord-Join%20Server-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/ffmN6cUd3u) [![GitHub Issues](https://img.shields.io/badge/GitHub-Issues-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/MoONSHO7/Orbit/issues)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-BD5FFF?style=for-the-badge&logo=buymeacoffee&logoColor=white)](https://www.buymeacoffee.com/moonsho7)

</p>

Orbit is a modular UI suite for World of Warcraft built directly into Blizzard's native Edit Mode. No complex setup, no heavy overhaul — high-end extensions for the default UI, designed to feel like Blizzard wrote them.

## Features

| | |
|---|---|
| **Edit Mode native** | every Orbit frame is selectable, draggable, and resizable in Blizzard's own Edit Mode |
| **Canvas Mode** | a dedicated dialog for fine-tuning individual components inside a single frame |
| **Cooldown Manager** | talent-aware spell tracking with charge displays and per-spec layouts |
| **Tracked** | user-authored cooldown / aura tracker that complements Cooldown Manager |
| **Unit frames** | player, target, focus, and boss frames with sync-size and shared skinning |
| **Group frames** | party and raid frames with aura layout and dispel highlighting |
| **Action bars** | skinned native bars with full Edit Mode integration |
| **Cast bars** | player and unit cast bars with target / boss focus |
| **Class resources** | advanced power displays per class and spec |
| **Status widget** | radial XP / reputation / honor / currency orb with a right-click source menu and milestone / reward flourishes |
| **Damage meter** | multi-instance, minimal-chrome meter on top of Blizzard's native damage / healing pipeline |
| **Raid panel** | dock-style raid-leader toolbar — difficulty, ready check, role poll, world markers, and ping restriction, shown only with lead / assist |
| **Datatexts** | corner-triggered drawer with stats, performance, currency, and utility readouts |
| **Minimap** | reskinned minimap with clean compartment flyout and Canvas Mode component placement |
| **Menu items** | bag bar and micro-menu reskins |
| **Spotlight** | hotkey-driven universal search across bags, gear, mounts, pets, toys, macros, and more |
| **Pixel-perfect** | auto-detected UI scale and snap-to-physical-pixel rendering at any resolution |
| **Smart profiles** | account-shared layouts with per-character spec data where it matters |

## Modular plugin system

Each component is a plugin that can be disabled. If you only want the Cooldown Manager, you can turn everything else off and Orbit becomes a single tool. Plugins live in `Orbit/Plugins/` and are independently toggled in the settings panel.

## For developers

If you'd like to contribute — bug fixes, plugins, translations, anything — start with **[CONTRIBUTE.md](CONTRIBUTE.md)**. It walks through the architecture, the three rendering systems (live frames / Edit Mode / Canvas Mode), the data-flow rules, and the conventions every PR is expected to follow.

## Support

If Orbit has improved your gameplay and you'd like to support continued development, the Buy Me A Coffee link above is genuinely appreciated — but the most valuable contribution is feedback in Discord and reproducible bug reports on GitHub.
