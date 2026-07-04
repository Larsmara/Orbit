# Config

## Description
The schema-driven settings UI: plugins declare their settings as declarative schemas, Config renders them as tabbed panels of widgets.

## Purpose
One rendering pipeline for every Orbit setting, so controls look and behave identically everywhere. Plugins own data; Config owns presentation.

## Implementation
```
Config/
  Schema/    -- SchemaBuilder + renderer + layout engine
  Panels/    -- Orbit Options shell + Tabs/ (Global, Textures, Edit Mode, Profiles) + settings dialog + advanced shell
  Entry/     -- /orbit slash, addon compartment button
  Advanced/  -- addon-settings content builders (PluginManager, FadeProfiles, QoL)
  Widgets/   -- self-contained controls (slider, checkbox, dropdown, pickers, ConfirmPopup, ValueSwatch)
  WhatsNew.lua / ChangelogData.lua -- post-update changelog popup
```

Flow: `/orbit` (or `/orb`, or the compartment button) → `OptionsPanel:ToggleEditMode()` — the shared Edit Mode + options toggle. `OrbitOptionsPanel.lua` is the dialog shell only: tab registry `Panel.Tabs`, `TAB_ORDER` (exposed as `Panel.TabOrder`), open/refresh lifecycle, and `Panel._helpers` (`CreateGlobalSettingsPlugin`, `RefreshAllPreviews`) consumed by the tab files. Each `Panels/Tabs/*.lua` registers a plugin + `schema()` pair. `Schema/SchemaBuilder.lua` composes the common per-plugin groups (`AddSizeSettings`, `AddColorSettings`, `AddColorCurveSettings`, `AddOrientationSettings`, `AddGlowSettings`, `AddSettingsTabs`; `MakePluginOnChange`/`SetTabRefreshCallback` are the live-apply plumbing) — individual controls are plain schema-tree tables, not builder methods. `Schema/ConfigRenderer.lua` walks the tree and instantiates `Widgets/`; `ConfigLayout.lua` owns the 3-column grid and tab bar. A widget's `onChange` writes via `plugin:SetSetting`; the plugin reacts in `ApplySettings`. Plugin dialogs: the plugin implements `AddSettings(dialog, systemFrame)` and wires standard tabs with `SchemaBuilder:AddSettingsTabs`.

GlobalTab: border style dropdowns list `Constants.BorderStyle.Styles` above a divider, LibSharedMedia borders below. The flat style shows the `PixelBorderSize` slider (0–5); the rounded slice styles show no slider (thickness baked into the texture); LSM styles show `BorderEdgeSize`/`BorderOffset` instead. Style changes fire `ORBIT_BORDER_SIZE_CHANGED` and rebuild the tab (conditional sliders). Font/border rows carry value-column color swatches (`FontColorCurve`/`BorderColor`/`IconBorderColor`), hidden for styles with no color. ColorsTab is the "Textures" tab — the file keeps its legacy name (plugin id `OrbitColors`).

## Gotchas
- Tabs are keyed by the localized label (`Orbit.L`), never a raw English string: register in `Panel.Tabs[L.CFG_TAB_X]` and add the key to `TAB_ORDER` in `OrbitOptionsPanel.lua`.
- Tab files reference `Panel._helpers` at load time — they must appear in `Config.xml` after `OrbitOptionsPanel.lua`.
- Config never calls plugin methods directly; it writes `plugin:SetSetting` and the plugin reacts via `ApplySettings`. Schemas are declarative — no imperative UI code in schema definitions.
- Widgets are self-contained (`Create(parent, schema, onChange)`), registered in `ConfigRenderer.lua`, and read/write only through `plugin:GetSetting/SetSetting`. Dimensions come from constants.
- Every value-column swatch/checkbox routes through `ValueSwatch.lua` (`Layout:ApplyValueColorSwatch` / `ApplyValueCheckbox`), right-aligned off `Constants.Widget.ValueInset`, so controls line up across Dropdown/ColorCurvePicker/TexturePicker/FontPicker.
- Confirmations use `Layout:ShowConfirm` (`ConfirmPopup.lua`, skinned to the Canvas Mode frame), not Blizzard `StaticPopupDialogs`.
- `/orbit` has no subcommands — its entire body is `ToggleEditMode()`. Former subcommands live in Spotlight with their logic on the owning module (`Orbit.API`, `VisibilityEngine:ResetAll`, `Localization.SetLocaleOverride`).
- `Panels/Tabs/ProfilesTab.lua` owns the widget registrations used only there (`profileactive`, `profileselect`, `collapseheader`, `checkheader`, `statusmessage`).

## References
`Core/Plugin/README.md` (settings resolution and profile lifecycle), `Core/Skinning/README.md` (what the border styles render), `Orbit/Localization/README.md` (`CFG_` keys), /canvas-mode (the other editing surface).
