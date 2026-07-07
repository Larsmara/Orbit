-- [ OBJECTIVES SETTINGS ]----------------------------------------------------------------------------
---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine
local L = Orbit.L

local C = Orbit.ObjectivesConstants
local SYSTEM_ID = C.SYSTEM_ID

local Plugin = Orbit:GetPlugin("Objectives")

local function OnChange(plugin, systemIndex, key)
    return function(val)
        plugin:SetSetting(systemIndex, key, val)
        -- Coalesce rapid changes: a slider drag fires onChange every frame, so apply once next frame.
        if not plugin._applyPending then
            plugin._applyPending = true
            RunNextFrame(function()
                plugin._applyPending = false
                plugin:ApplySettings()
            end)
        end
    end
end

local function FontSizePx(v) return v .. "px" end

local function FormatLabel(v)
    if v == C.FORMAT_MIN then return L.PLU_OBJ_FORMAT_COMPACT end
    if v == C.FORMAT_MAX then return L.PLU_OBJ_FORMAT_LARGE end
    return L.PLU_OBJ_FORMAT_STANDARD
end

function Plugin:AddSettings(dialog, systemFrame)
    local systemIndex = systemFrame and systemFrame.systemIndex or SYSTEM_ID
    local SB = OrbitEngine.SchemaBuilder

    local schema = {
        hideNativeSettings = true,
        controls = {},
    }

    local tabs = { L.PLU_OBJ_TAB_LAYOUT, L.PLU_OBJ_TAB_BEHAVIOUR, L.PLU_OBJ_TAB_COLOURS }
    SB:SetTabRefreshCallback(dialog, self, systemFrame)
    local currentTab = SB:AddSettingsTabs(schema, dialog, tabs, L.PLU_OBJ_TAB_LAYOUT)

    if currentTab == L.PLU_OBJ_TAB_LAYOUT then
        table.insert(schema.controls, {
            type = "slider",
            key = "Width",
            label = L.CMN_WIDTH,
            min = C.WIDTH_MIN,
            max = C.WIDTH_MAX,
            step = C.WIDTH_STEP,
            default = C.DEFAULT_WIDTH,
            onChange = OnChange(self, systemIndex, "Width"),
        })

        table.insert(schema.controls, {
            type = "slider",
            key = "Height",
            label = L.CMN_HEIGHT,
            min = C.HEIGHT_MIN,
            max = C.HEIGHT_MAX,
            step = C.HEIGHT_STEP,
            default = C.DEFAULT_HEIGHT,
            onChange = OnChange(self, systemIndex, "Height"),
        })

        table.insert(schema.controls, {
            type = "slider",
            key = "Format",
            label = L.PLU_OBJ_FORMAT,
            min = C.FORMAT_MIN,
            max = C.FORMAT_MAX,
            step = 1,
            default = C.FORMAT_DEFAULT,
            formatter = FormatLabel,
            onChange = OnChange(self, systemIndex, "Format"),
        })

        table.insert(schema.controls, {
            type = "slider",
            key = "HeaderFontSize",
            label = L.PLU_OBJ_HEADER_FONT_SIZE,
            min = C.HEADER_FONT_SIZE_MIN,
            max = C.HEADER_FONT_SIZE_MAX,
            step = C.HEADER_FONT_SIZE_STEP,
            default = C.HEADER_FONT_SIZE_DEFAULT,
            formatter = FontSizePx,
            onChange = OnChange(self, systemIndex, "HeaderFontSize"),
        })

        table.insert(schema.controls, {
            type = "slider",
            key = "TitleFontSize",
            label = L.PLU_OBJ_TITLE_FONT_SIZE,
            min = C.TITLE_FONT_SIZE_MIN,
            max = C.TITLE_FONT_SIZE_MAX,
            step = C.TITLE_FONT_SIZE_STEP,
            default = C.TITLE_FONT_SIZE_DEFAULT,
            formatter = FontSizePx,
            onChange = OnChange(self, systemIndex, "TitleFontSize"),
        })

        table.insert(schema.controls, {
            type = "slider",
            key = "ObjectiveFontSize",
            label = L.PLU_OBJ_OBJECTIVE_FONT_SIZE,
            min = C.OBJECTIVE_FONT_SIZE_MIN,
            max = C.OBJECTIVE_FONT_SIZE_MAX,
            step = C.OBJECTIVE_FONT_SIZE_STEP,
            default = C.OBJECTIVE_FONT_SIZE_DEFAULT,
            formatter = FontSizePx,
            onChange = OnChange(self, systemIndex, "ObjectiveFontSize"),
        })

        table.insert(schema.controls, {
            type = "slider",
            key = "BackgroundOpacity",
            label = L.PLU_OBJ_BG_OPACITY,
            min = C.BG_OPACITY_MIN,
            max = C.BG_OPACITY_MAX,
            step = C.BG_OPACITY_STEP,
            default = C.BG_OPACITY_DEFAULT,
            formatter = function(v) return v .. "%" end,
            onChange = OnChange(self, systemIndex, "BackgroundOpacity"),
        })

        table.insert(schema.controls, {
            type = "checkbox",
            key = "ShowBorder",
            label = L.PLU_OBJ_SHOW_BORDER,
            default = false,
            onChange = OnChange(self, systemIndex, "ShowBorder"),
        })

    elseif currentTab == L.PLU_OBJ_TAB_BEHAVIOUR then
        table.insert(schema.controls, {
            type = "dropdown",
            key = "SortMode",
            label = L.PLU_OBJ_SORT,
            default = C.SORT_DEFAULT,
            options = {
                { text = L.PLU_OBJ_SORT_TRACKED, value = "tracked" },
                { text = L.PLU_OBJ_SORT_PROXIMITY, value = "proximity" },
                { text = L.PLU_OBJ_SORT_PROGRESS, value = "progress" },
                { text = NAME, value = "name" },
            },
            onChange = OnChange(self, systemIndex, "SortMode"),
        })

        local progressTooltip = { { title = L.CFG_FORMAT_TOOLTIP_TITLE } }
        for _, token in ipairs(C.PROGRESS_TOKENS) do
            table.insert(progressTooltip, { key = token.key, value = token.sample })
        end
        table.insert(progressTooltip, { hint = L.CFG_FORMAT_TOOLTIP_HINT })

        table.insert(schema.controls, {
            type = "formatinput",
            key = "ProgressBarLabelFormat",
            label = L.PLU_OBJ_PROGRESS_BAR_LABEL,
            default = C.PROGRESS_FORMAT_DEFAULT,
            tooltipLines = progressTooltip,
            validate = function(str) return self:ValidateProgressFormat(str) end,
            onChange = OnChange(self, systemIndex, "ProgressBarLabelFormat"),
        })

        table.insert(schema.controls, {
            type = "checkbox",
            key = "ShowQuestCount",
            label = L.PLU_OBJ_SHOW_QUEST_COUNT,
            default = true,
            onChange = OnChange(self, systemIndex, "ShowQuestCount"),
        })

        table.insert(schema.controls, {
            type = "checkbox",
            key = "AutoCollapseCombat",
            label = L.PLU_OBJ_AUTO_COLLAPSE_COMBAT,
            default = false,
            onChange = OnChange(self, systemIndex, "AutoCollapseCombat"),
        })

        table.insert(schema.controls, {
            type = "checkbox",
            key = "SmoothScroll",
            label = L.PLU_OBJ_SMOOTH_SCROLL,
            tooltip = L.PLU_OBJ_SMOOTH_SCROLL_TT,
            default = true,
            onChange = OnChange(self, systemIndex, "SmoothScroll"),
        })

        table.insert(schema.controls, {
            type = "checkbox",
            key = "ZoneFilter",
            label = L.PLU_OBJ_ZONE_FILTER,
            tooltip = L.PLU_OBJ_ZONE_FILTER_TT,
            default = false,
            onChange = OnChange(self, systemIndex, "ZoneFilter"),
        })

        table.insert(schema.controls, {
            type = "checkbox",
            key = "ZoneWorldQuests",
            label = L.PLU_OBJ_ZONE_WQ,
            tooltip = L.PLU_OBJ_ZONE_WQ_TT,
            default = false,
            onChange = OnChange(self, systemIndex, "ZoneWorldQuests"),
        })

    elseif currentTab == L.PLU_OBJ_TAB_COLOURS then
        table.insert(schema.controls, {
            type = "solidcolor",
            key = "HeaderColor",
            label = L.PLU_OBJ_HEADER_COLOUR,
            default = C.HEADER_COLOR_DEFAULT,
            onChange = OnChange(self, systemIndex, "HeaderColor"),
        })

        table.insert(schema.controls, {
            type = "solidcolor",
            key = "TitleColor",
            label = L.PLU_OBJ_TITLE_COLOUR,
            default = C.TITLE_COLOR_DEFAULT,
            onChange = OnChange(self, systemIndex, "TitleColor"),
        })

        table.insert(schema.controls, {
            type = "solidcolor",
            key = "CompletedColor",
            label = L.PLU_OBJ_COMPLETED_COLOUR,
            default = C.COMPLETED_COLOR_DEFAULT,
            onChange = OnChange(self, systemIndex, "CompletedColor"),
        })

        table.insert(schema.controls, {
            type = "solidcolor",
            key = "FocusColor",
            label = L.PLU_OBJ_FOCUS_COLOUR,
            default = C.FOCUS_COLOR_DEFAULT,
            onChange = OnChange(self, systemIndex, "FocusColor"),
        })
    end

    OrbitEngine.Config:Render(dialog, systemFrame, self, schema)
end
