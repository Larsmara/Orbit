local _, addonTable = ...
local Orbit = addonTable
local Skin = Orbit.Skin
local Engine = Orbit.Engine
local LSM = LibStub("LibSharedMedia-3.0")
local Constants = Orbit.Constants

local SHADOW_OFFSET_X = 2
local SHADOW_OFFSET_Y = -2

-- [ FONT SKINNING ]----------------------------------------------------------------------------------
function Skin:GetFontOutline()
    return Orbit.db.GlobalSettings.FontOutline or "OUTLINE"
end

function Skin:GetFontShadow()
    return Orbit.db.GlobalSettings.FontShadow or false
end

function Skin:ApplyFontShadow(fontString)
    if not fontString then return end
    if self:GetFontShadow() then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(SHADOW_OFFSET_X, SHADOW_OFFSET_Y)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

local SHADOW_BACKING_FONT = "GameFontHighlight"

-- SetFont that re-backs the FontString with a font object first, else SetShadow silently won't render after an inline SetFont (bare-fontstring trap); preserves color/justify that SetFontObject resets.
function Skin:SetFontWithShadow(fontString, path, size, flags)
    if not fontString or not fontString.SetFont then return end
    local r, g, b, a = fontString:GetTextColor()
    local jh = fontString.GetJustifyH and fontString:GetJustifyH()
    local jv = fontString.GetJustifyV and fontString:GetJustifyV()
    fontString:SetFontObject(SHADOW_BACKING_FONT)
    fontString:SetFont(path, size, flags or self:GetFontOutline())
    fontString:SetTextColor(r, g, b, a)
    if jh then fontString:SetJustifyH(jh) end
    if jv then fontString:SetJustifyV(jv) end
    self:ApplyFontShadow(fontString)
end

function Skin:SkinText(fontString, settings)
    if not fontString then
        return
    end

    local size = settings.textSize or 12

    local font = "Fonts\\FRIZQT__.TTF"
    if settings.font then
        font = LSM:Fetch("font", settings.font) or font
    end

    self:SetFontWithShadow(fontString, font, size)

    if settings.textColor then
        local c = settings.textColor
        fontString:SetTextColor(c.r, c.g, c.b, c.a or 1)
    end
end

-- [ UNITFRAME TEXT STYLING ]-------------------------------------------------------------------------
function Skin:ApplyUnitFrameText(fontString, alignment, fontPath, textSize)
    if not fontString then
        return
    end

    -- Get font from global settings or fallback
    if not fontPath then
        local globalFontName = Orbit.db.GlobalSettings.Font
        fontPath = LSM:Fetch("font", globalFontName) or Constants.Settings.Font.FallbackPath
    end

    textSize = textSize or Constants.UI.UnitFrameTextSize
    local padding = Constants.UnitFrame.TextPadding

    self:SetFontWithShadow(fontString, fontPath, textSize)
    fontString:ClearAllPoints()

    local fsScale = fontString:GetEffectiveScale()
    if alignment == "LEFT" then
        fontString:SetPoint("LEFT", Engine.Pixel:Multiple(padding, fsScale), 0)
        fontString:SetJustifyH("LEFT")
    else
        fontString:SetPoint("RIGHT", Engine.Pixel:Multiple(-padding, fsScale), 0)
        fontString:SetJustifyH("RIGHT")
    end
end
