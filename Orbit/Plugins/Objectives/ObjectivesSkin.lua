-- [ OBJECTIVES SKIN ]--------------------------------------------------------------------------------
-- Pure styling primitives for our pooled widgets: inputs are our entry records, never Blizzard blocks or QuestCache.
---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine
local LSM = LibStub("LibSharedMedia-3.0")

local C = Orbit.ObjectivesConstants
local SYSTEM_ID = C.SYSTEM_ID
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT

local Plugin = Orbit:GetPlugin("Objectives")

Orbit.ObjectivesSkin = {}
local Skin = Orbit.ObjectivesSkin

Skin.cache = {
    font           = nil,
    titleSize      = C.TITLE_FONT_SIZE_DEFAULT,
    objectiveSize  = C.OBJECTIVE_FONT_SIZE_DEFAULT,
    headerSize     = C.HEADER_FONT_SIZE_DEFAULT,
    progressSegs   = nil,
    titleColor     = C.TITLE_COLOR_DEFAULT,
    completedColor = C.COMPLETED_COLOR_DEFAULT,
    focusColor     = C.FOCUS_COLOR_DEFAULT,
    headerColor    = C.HEADER_COLOR_DEFAULT,
    headerIsClass  = false,
    objectiveColor = C.OBJECTIVE_COLOR_DEFAULT,
    barTexture     = nil,
    barBorder      = nil,
    spacing        = C.FORMAT_SPACING[C.FORMAT_DEFAULT],
}

-- Bumped whenever the bar texture/border theme changes, so pooled bars re-skin lazily instead of every pass.
Skin._barStyleEpoch = 0
-- Bumped whenever the font path/outline/shadow changes, so ApplyFont re-applies lazily instead of ~700 SetFont calls every pass.
Skin._fontEpoch = 0

-- [ CLASSIFICATION / TAG TABLES ]--------------------------------------------------------------------
local POI_COLORS = {
    [Enum.QuestClassification.Important]      = { r = 0.90, g = 0.58, b = 0.18 },
    [Enum.QuestClassification.Legendary]      = { r = 1.00, g = 0.50, b = 0.00 },
    [Enum.QuestClassification.Campaign]       = { r = 0.80, g = 0.60, b = 0.20 },
    [Enum.QuestClassification.Calling]        = { r = 0.25, g = 0.70, b = 0.90 },
    [Enum.QuestClassification.Meta]           = { r = 0.68, g = 0.38, b = 0.90 },
    [Enum.QuestClassification.Recurring]      = { r = 0.25, g = 0.50, b = 1.00 },
    [Enum.QuestClassification.Questline]      = { r = 0.85, g = 0.75, b = 0.35 },
    [Enum.QuestClassification.Normal]         = { r = 1.00, g = 0.82, b = 0.00 },
    [Enum.QuestClassification.BonusObjective] = { r = 0.20, g = 0.80, b = 0.30 },
    [Enum.QuestClassification.Threat]         = { r = 0.85, g = 0.20, b = 0.20 },
    [Enum.QuestClassification.WorldQuest]     = { r = 0.20, g = 0.70, b = 0.55 },
}
local POI_CLASSIFICATION_ATLAS = {
    [Enum.QuestClassification.Campaign]       = "Quest-Campaign-Available",
    [Enum.QuestClassification.Important]      = "importantavailablequesticon",
    [Enum.QuestClassification.Legendary]      = "UI-QuestPoiLegendary-QuestBang",
    [Enum.QuestClassification.Calling]        = "Quest-DailyCampaign-Available",
    [Enum.QuestClassification.Meta]           = "quest-wrapper-available",
    [Enum.QuestClassification.Recurring]      = "quest-recurring-available",
    [Enum.QuestClassification.BonusObjective] = "Bonus-Objective-Star",
    [Enum.QuestClassification.Threat]         = "questlog-questtypeicon-raid",
    [Enum.QuestClassification.WorldQuest]     = "Worldquest-icon",
    [Enum.QuestClassification.Questline]      = "questlog-questtypeicon-story",
}
local POI_TAG_ATLAS = {
    [Enum.QuestTag.Dungeon]  = "questlog-questtypeicon-dungeon",
    [Enum.QuestTag.Raid]     = "questlog-questtypeicon-raid",
    [Enum.QuestTag.Group]    = "questlog-questtypeicon-group",
    [Enum.QuestTag.PvP]      = "questlog-questtypeicon-pvp",
    [Enum.QuestTag.Heroic]   = "questlog-questtypeicon-heroic",
    [Enum.QuestTag.Scenario] = "questlog-questtypeicon-scenario",
    [Enum.QuestTag.Account]  = "questlog-questtypeicon-account",
    [Enum.QuestTag.Delve]    = "questlog-questtypeicon-delves",
}
local POI_TAG_COLOR = {
    [Enum.QuestTag.Dungeon]  = C.TAG_COLOR_GROUP,
    [Enum.QuestTag.Raid]     = C.TAG_COLOR_RAID,
    [Enum.QuestTag.Group]    = C.TAG_COLOR_GROUP,
    [Enum.QuestTag.PvP]      = C.TAG_COLOR_PVP,
    [Enum.QuestTag.Heroic]   = C.TAG_COLOR_GROUP,
    [Enum.QuestTag.Scenario] = C.TAG_COLOR_GROUP,
    [Enum.QuestTag.Account]  = C.TAG_COLOR_ACCOUNT,
    [Enum.QuestTag.Delve]    = C.TAG_COLOR_GROUP,
}
local POI_ATLAS_DEFAULT  = "QuestNormal"
local POI_ATLAS_COMPLETE = "QuestTurnin"

-- [ HELPERS ]----------------------------------------------------------------------------------------
local function ResolveColor(raw, fallback)
    if type(raw) == "table" and raw.type == "class" and OrbitEngine.ClassColor then
        local cc = OrbitEngine.ClassColor:GetCurrentClassColor()
        return { r = cc.r, g = cc.g, b = cc.b, a = raw.a or 1 }
    end
    return C.ValidateColor(raw, fallback)
end

-- [ PROGRESS FORMAT ]--------------------------------------------------------------------------------
-- Progress values are non-secret, so the % math here is safe (unlike health bars).
local PB_FORMATTERS = {
    ["%"]        = function(cur, max) return string.format("%.0f%%", (cur / max) * 100) end,
    ["CurrentK"] = function(cur, max) return AbbreviateNumbers(math.floor(cur)) end,
    ["Current"]  = function(cur, max) return tostring(math.floor(cur)) end,
    ["MaxK"]     = function(cur, max) return AbbreviateNumbers(math.floor(max)) end,
    ["Max"]      = function(cur, max) return tostring(math.floor(max)) end,
}

-- Token keys longest-first so "CurrentK"/"MaxK" match before "Current"/"Max".
local PB_KEYS = {}
for _, t in ipairs(C.PROGRESS_TOKENS) do PB_KEYS[#PB_KEYS + 1] = t.key end
table.sort(PB_KEYS, function(a, b) return #a > #b end)

local function ParseProgressFormat(str)
    str = strtrim(str or "")
    local segs, buffer = {}, ""
    local function flush()
        if buffer ~= "" then segs[#segs + 1] = { sep = buffer }; buffer = "" end
    end
    local i, n = 1, #str
    while i <= n do
        local matched
        for _, key in ipairs(PB_KEYS) do
            if str:sub(i, i + #key - 1):lower() == key:lower() then matched = key; break end
        end
        if matched then
            flush()
            segs[#segs + 1] = { token = matched }
            i = i + #matched
        else
            buffer = buffer .. str:sub(i, i)
            i = i + 1
        end
    end
    flush()
    return segs
end

-- Valid when the format contains at least one value token — drives the settings input's valid/invalid border.
function Plugin:ValidateProgressFormat(str)
    if type(str) ~= "string" then return false end
    for _, seg in ipairs(ParseProgressFormat(str)) do
        if seg.token then return true end
    end
    return false
end

function Skin:FormatProgress(cur, max)
    local segs = self.cache.progressSegs
    if not segs or not max or max == 0 then return nil end
    local out = {}
    for _, seg in ipairs(segs) do
        if seg.token then
            out[#out + 1] = tostring(PB_FORMATTERS[seg.token](cur, max))
        else
            out[#out + 1] = seg.sep
        end
    end
    return table.concat(out)
end

-- [ CACHE ]------------------------------------------------------------------------------------------
-- Resolve every per-pass setting once (font/sizes/colours/format) so the render loop never re-reads DB.
function Skin:RefreshCache(plugin)
    local c = self.cache
    local fontName = Orbit:GetTheme("Font")
    c.font = (fontName and LSM:Fetch("font", fontName)) or STANDARD_TEXT_FONT
    c.titleSize     = plugin:GetSetting(SYSTEM_ID, "TitleFontSize") or C.TITLE_FONT_SIZE_DEFAULT
    c.objectiveSize = plugin:GetSetting(SYSTEM_ID, "ObjectiveFontSize") or C.OBJECTIVE_FONT_SIZE_DEFAULT
    c.headerSize    = plugin:GetSetting(SYSTEM_ID, "HeaderFontSize") or C.HEADER_FONT_SIZE_DEFAULT
    local pbFormat = plugin:GetSetting(SYSTEM_ID, "ProgressBarLabelFormat")
    if not pbFormat or pbFormat == "" then pbFormat = C.PROGRESS_FORMAT_DEFAULT end
    c.progressSegs   = ParseProgressFormat(pbFormat)
    c.titleColor     = ResolveColor(plugin:GetSetting(SYSTEM_ID, "TitleColor"), C.TITLE_COLOR_DEFAULT)
    c.completedColor = ResolveColor(plugin:GetSetting(SYSTEM_ID, "CompletedColor"), C.COMPLETED_COLOR_DEFAULT)
    c.focusColor     = ResolveColor(plugin:GetSetting(SYSTEM_ID, "FocusColor"), C.FOCUS_COLOR_DEFAULT)
    local headerRaw = plugin:GetSetting(SYSTEM_ID, "HeaderColor")
    c.headerColor   = ResolveColor(headerRaw, C.HEADER_COLOR_DEFAULT)
    c.headerIsClass = type(headerRaw) == "table" and headerRaw.type == "class"

    local newTexture, newBorder = Orbit:GetTheme("Texture"), Orbit:GetTheme("BorderSize")
    if newTexture ~= c.barTexture or newBorder ~= c.barBorder then
        c.barTexture, c.barBorder = newTexture, newBorder
        self._barStyleEpoch = self._barStyleEpoch + 1
    end

    local format = plugin:GetSetting(SYSTEM_ID, "Format") or C.FORMAT_DEFAULT
    c.spacing = C.FORMAT_SPACING[format] or C.FORMAT_SPACING[C.FORMAT_DEFAULT]

    c.showCount = plugin:GetSetting(SYSTEM_ID, "ShowQuestCount") ~= false
    -- Header dividers always render (no user toggle).
    c.sepOn     = true

    -- Theme font changes aren't a settings event, so diff them here (like the bar epoch) and bump so ApplyFont re-applies.
    local newOutline, newShadow = Orbit:GetTheme("FontOutline"), Orbit:GetTheme("FontShadow")
    if c.font ~= self._fontKey or newOutline ~= self._fontOutline or newShadow ~= self._fontShadow then
        self._fontKey, self._fontOutline, self._fontShadow = c.font, newOutline, newShadow
        self._fontEpoch = self._fontEpoch + 1
    end
end

-- [ FONT ]-------------------------------------------------------------------------------------------
-- SetFontWithShadow is ~8 frame calls + a DB read; skip it when this FontString already carries the current font epoch + size (the common case every pass).
function Skin:ApplyFont(fontString, size)
    if not fontString or not fontString.SetFont then return end
    if fontString._fontEpoch == self._fontEpoch and fontString._fontSize == size then return end
    Orbit.Skin:SetFontWithShadow(fontString, self.cache.font or STANDARD_TEXT_FONT, size or 12)
    fontString._fontEpoch, fontString._fontSize = self._fontEpoch, size
end

-- [ POI COLOUR / ATLAS ]-----------------------------------------------------------------------------
-- Reads pre-resolved entry fields (providers use C_QuestInfoSystem etc.), never the POIButton path that writes the shared QuestCache.
function Skin:GetPOIColor(entry)
    if entry.isSuperTracked then return self.cache.focusColor end
    if entry.isComplete then return self.cache.completedColor end
    local cls = entry.classification
    if cls == Enum.QuestClassification.Legendary then return POI_COLORS[Enum.QuestClassification.Legendary] end
    if entry.tagID and POI_TAG_COLOR[entry.tagID] then return POI_TAG_COLOR[entry.tagID] end
    if entry.isCampaign then return POI_COLORS[Enum.QuestClassification.Campaign] end
    if cls and cls ~= Enum.QuestClassification.Normal and POI_COLORS[cls] then return POI_COLORS[cls] end
    return self.cache.titleColor
end

function Skin:GetPOIAtlas(entry)
    if entry.isComplete then return POI_ATLAS_COMPLETE end
    if entry.isCampaign then return POI_CLASSIFICATION_ATLAS[Enum.QuestClassification.Campaign] end
    local cls = entry.classification
    if cls and POI_CLASSIFICATION_ATLAS[cls] then return POI_CLASSIFICATION_ATLAS[cls] end
    if entry.tagID and POI_TAG_ATLAS[entry.tagID] then return POI_TAG_ATLAS[entry.tagID] end
    return POI_ATLAS_DEFAULT
end

-- Highlight brighten on hover (Render calls this on OnEnter/OnLeave).
function Skin:ApplyTitleColor(fontString, entry, highlighted)
    local col = self:GetPOIColor(entry)
    if highlighted then
        fontString:SetTextColor(math.min(1, col.r * C.HIGHLIGHT_BRIGHTEN), math.min(1, col.g * C.HIGHLIGHT_BRIGHTEN), math.min(1, col.b * C.HIGHLIGHT_BRIGHTEN))
    else
        fontString:SetTextColor(col.r, col.g, col.b)
    end
end

-- [ STATUS/PROGRESS BAR STYLE ]----------------------------------------------------------------------
-- Applies the Orbit bar look (LSM texture, themed bg, masked surfaces, border) to one of our StatusBars.
function Skin:ApplyBarStyle(bar)
    local textureName = Orbit:GetTheme("Texture")
    local barTexture = (textureName and LSM:Fetch("statusbar", textureName)) or LSM:Fetch("statusbar", "Solid")
    bar:SetStatusBarTexture(barTexture)
    if not bar._orbitBG then
        local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetAllPoints(bar)
        bar._orbitBG = bg
    end
    local bgColor = Orbit.Skin:GetBackgroundColor()
    bar._orbitBG:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a or C.BAR_BG_ALPHA)

    Orbit.Skin:RegisterMaskedSurface(bar, bar._orbitBG)
    local fill = bar:GetStatusBarTexture()
    if fill then Orbit.Skin:RegisterMaskedSurface(bar, fill) end

    local borderSize = Orbit:GetTheme("BorderSize") or 1
    Orbit.Skin:SkinBorder(bar, bar, borderSize)
end

-- [ HEADER SEPARATOR ]-------------------------------------------------------------------------------
function Skin:ApplyHeaderSeparator(header, sep, show, color, isClass)
    if not sep then return end
    if not show then sep:Hide(); return end
    local thickness = OrbitEngine.Pixel:Multiple(C.HEADER_SEPARATOR_HEIGHT, header:GetEffectiveScale())
    sep:SetHeight(thickness)
    sep:ClearAllPoints()
    sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, -thickness)
    sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, -thickness)
    local alpha = isClass and C.SEPARATOR_ALPHA_CLASS or C.SEPARATOR_ALPHA
    sep:SetColorTexture(color.r, color.g, color.b, alpha)
    sep:Show()
end
