-- [ TOOLTIPS ]---------------------------------------------------------------------------------------
local _, Orbit = ...
local L = Orbit.L
local Skin = Orbit.Skin
local Constants = Orbit.Constants
local OrbitTooltip = Orbit.Tooltip

Orbit.Tooltips = {}
local Tooltips = Orbit.Tooltips

-- [ CONSTANTS ]--------------------------------------------------------------------------------------
local ANCHOR_DEFAULT = 4
local STYLE_ORBIT = 2
local ANCHOR_MODES = {
    [2] = "ANCHOR_CURSOR",
    [3] = "ANCHOR_CURSOR_LEFT",
    [4] = "ANCHOR_CURSOR_RIGHT",
}
local SCALED_TOOLTIPS = {
    "GameTooltip", "OrbitTooltip", "ItemRefTooltip", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    "ShoppingTooltip1", "ShoppingTooltip2", "FriendsTooltip", "ReputationParagonTooltip",
}
local NINE_SLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}
local ID_COLOR = { 0.6, 0.8, 1 }
local TARGET_SELF_COLOR = { 1, 0.5, 0.5 }
local TARGET_NPC_COLOR = { 0.8, 0.8, 0.8 }
local ALLIANCE_COLOR = { r = 0.2, g = 0.45, b = 0.95 }
local HORDE_COLOR = { r = 0.9, g = 0.15, b = 0.15 }

local MANAGED = { GameTooltip, OrbitTooltip }
local MANAGED_SET = { [GameTooltip] = true, [OrbitTooltip] = true }

local canaccessvalue = canaccessvalue or function() return true end
local issecretvalue = issecretvalue or function() return false end

-- A tooltip showing secret data reports a secret width; any non-delegate Orbit write to it then taints Blizzard's own line processing, which throws on the secret colour (combat world-POI tooltips) — so leave secret tooltips untouched and let the taint never plant.
local function IsSecretTooltip(tt)
    return tt and issecretvalue(tt:GetWidth())
end

-- [ SETTINGS ]---------------------------------------------------------------------------------------
local function Get(key, default)
    local db = Orbit.db and Orbit.db.AccountSettings
    if not db then return default end
    local v = db[key]
    if v == nil then return default end
    return v
end

-- [ COLOR HELPERS ]----------------------------------------------------------------------------------
local function ClassColor(classFile)
    local CC = Orbit.Engine and Orbit.Engine.ClassColor
    if CC then return CC:GetOverrides(classFile) end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

local function ReactionColor(unit)
    local reaction = UnitReaction(unit, "player")
    if not reaction or not canaccessvalue(reaction) then return nil end
    local RC = Orbit.Engine and Orbit.Engine.ReactionColor
    if not RC then return nil end
    if reaction >= 5 then return RC:GetOverride("FRIENDLY")
    elseif reaction == 4 then return RC:GetOverride("NEUTRAL")
    else return RC:GetOverride("HOSTILE") end
end

local function SetBorderColor(tt, r, g, b)
    local ns = tt.NineSlice
    if not ns then return end
    for _, piece in ipairs(NINE_SLICE_PIECES) do
        local region = ns[piece]
        if region then region:SetVertexColor(r, g, b) end
    end
end

local function AllegianceTint(unit)
    if not unit or not canaccessvalue(unit) then return nil end
    if not Get("TooltipAllegiance", false) then return nil end
    local faction = UnitFactionGroup(unit)
    if faction and canaccessvalue(faction) then
        if faction == "Alliance" then return ALLIANCE_COLOR
        elseif faction == "Horde" then return HORDE_COLOR end
    end
    return nil
end

-- [ ORBIT SKIN ]-------------------------------------------------------------------------------------
local function IsOrbitStyle()
    return Get("TooltipStyle", 2) == STYLE_ORBIT
end

local function BorderSize()
    local gs = Orbit.db and Orbit.db.GlobalSettings
    return (gs and gs.BorderSize) or Constants.Settings.BorderSize.Default
end

-- Blizzard reuses one GameTooltipStatusBar across every show, so capture its native anchor + texture once — that's the only way Blizzard style can fully undo an Orbit merge.
local function SnapshotHealthBar(bar)
    if bar._orbitSnapshot then return end
    bar._orbitSnapshot = true
    bar._origPoints = {}
    for i = 1, bar:GetNumPoints() do
        bar._origPoints[i] = { bar:GetPoint(i) }
    end
    local tex = bar:GetStatusBarTexture()
    bar._origAtlas = tex and tex:GetAtlas()
    bar._origTexture = tex and tex:GetTexture()
end

local function RestoreHealthBar(bar)
    if not bar or not bar._orbitSnapshot then return end
    if bar.Overlay then bar.Overlay:Hide() end
    if bar._orbitBg then bar._orbitBg:Hide() end
    bar:ClearAllPoints()
    for _, p in ipairs(bar._origPoints) do bar:SetPoint(unpack(p)) end
    if bar._origAtlas then
        bar:GetStatusBarTexture():SetAtlas(bar._origAtlas)
    elseif bar._origTexture then
        bar:SetStatusBarTexture(bar._origTexture)
    end
end

-- Hang the health bar flush below the body and draw ONE border around body+bar (the mb overlay), the body's own border hidden, so they read as a single frame.
local function MergeHealthBar(tt, bar, bgColor, tint)
    SnapshotHealthBar(bar)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", tt, "BOTTOMRIGHT", 0, 0)
    Skin:SkinStatusBar(bar, Orbit:GetTheme("Texture"), nil)
    if not bar._orbitBg then
        bar._orbitBg = bar:CreateTexture(nil, "BACKGROUND")
        bar._orbitBg:SetAllPoints(bar)
    end
    bar._orbitBg:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 1)
    bar._orbitBg:Show()
    if bar.Overlay then bar.Overlay:Show() end

    Skin:ClearNineSliceBorder(tt)
    if tt._borderFrame then tt._borderFrame:Hide() end
    if not tt._mergeBorder then
        tt._mergeBorder = CreateFrame("Frame", nil, tt, "BackdropTemplate")
    end
    local mb = tt._mergeBorder
    mb:SetFrameLevel(tt:GetFrameLevel() + Constants.Levels.Border)
    mb:ClearAllPoints()
    mb:SetPoint("TOPLEFT", tt, "TOPLEFT", 0, 0)
    mb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    mb:Show()
    if not mb._registered then
        mb._registered = true
        Skin:RegisterMaskedSurface(mb, tt._orbitBg)
        Skin:RegisterMaskedSurface(mb, bar._orbitBg)
        Skin:RegisterMaskedSurface(mb, bar:GetStatusBarTexture())
        if bar.Overlay then Skin:RegisterMaskedSurface(mb, bar.Overlay) end
    end
    Skin:SkinBorder(mb, mb, BorderSize(), tint)
    Skin:UpdateRoundedMask(mb)
end

local function ApplyOrbitSkin(tt)
    if IsSecretTooltip(tt) then return end
    if not tt._orbitBg then
        local bg = tt:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tt)
        tt._orbitBg = bg
        Skin:RegisterMaskedSurface(tt, bg)
    end
    local c = Skin:GetBackgroundColor()
    tt._orbitBg:SetColorTexture(c.r, c.g, c.b, c.a or 1)
    tt._orbitBg:Show()
    if tt.NineSlice then tt.NineSlice:Hide() end
    local _, unit = tt:GetUnit()
    local tint = AllegianceTint(unit)
    local bar = tt.StatusBar
    if bar and bar:IsShown() and not Get("TooltipHideHealthBar", true) then
        MergeHealthBar(tt, bar, c, tint)
    else
        if tt._mergeBorder then tt._mergeBorder:Hide() end
        Skin:SkinBorder(tt, tt, BorderSize(), tint)
    end
end

local function RemoveOrbitSkin(tt)
    if tt._orbitBg then tt._orbitBg:Hide() end
    if tt._mergeBorder then tt._mergeBorder:Hide() end
    Skin:ClearNineSliceBorder(tt)
    if tt._borderFrame then tt._borderFrame:Hide() end
    if tt.NineSlice then tt.NineSlice:Show() end
    RestoreHealthBar(tt.StatusBar)
end

-- [ FEATURES ]---------------------------------------------------------------------------------------
-- Guild is tooltip line 2 for guilded players.
local function AppendGuildRank(self, unit)
    if not UnitIsPlayer(unit) then return end
    local gname, grank = GetGuildInfo(unit)
    if not gname or not grank or not canaccessvalue(gname) or not canaccessvalue(grank) then return end
    local line = self.TextLeft2
    local text = line and line:GetText()
    if text and canaccessvalue(text) and text:find(gname, 1, true) then
        line:SetText(text .. " - " .. grank)
    end
end

-- Post-call runs insecure; unit reads are secret in combat, hence the canaccessvalue guards.
local function OnUnitTooltip(self)
    if not Tooltips._enabled or not MANAGED_SET[self] then return end
    if IsSecretTooltip(self) then return end
    local _, unit = self:GetUnit()
    if not unit or not canaccessvalue(unit) then return end

    if Get("TooltipHideCombat", true) and UnitAffectingCombat("player") and WorldFrame:IsMouseMotionFocus() then
        self:Hide()
        return
    end

    if UnitIsPlayer(unit) then
        local classFile = UnitClassBase(unit)
        if classFile and canaccessvalue(classFile) then
            local c = ClassColor(classFile)
            if c and self.TextLeft1 then self.TextLeft1:SetTextColor(c.r, c.g, c.b) end
        end
    end
    if not IsOrbitStyle() then
        local t = AllegianceTint(unit)
        if t then SetBorderColor(self, t.r, t.g, t.b) end
    end

    if Get("TooltipGuildRank", true) then
        AppendGuildRank(self, unit)
    end

    if Get("TooltipShowTarget", false) then
        local target = unit .. "target"
        if UnitExists(target) then
            local name = UnitName(target)
            if name and canaccessvalue(name) then
                local r, g, b = TARGET_NPC_COLOR[1], TARGET_NPC_COLOR[2], TARGET_NPC_COLOR[3]
                if UnitIsUnit(target, "player") then
                    r, g, b = TARGET_SELF_COLOR[1], TARGET_SELF_COLOR[2], TARGET_SELF_COLOR[3]
                elseif UnitIsPlayer(target) then
                    local classFile = UnitClassBase(target)
                    local c = classFile and canaccessvalue(classFile) and ClassColor(classFile)
                    if c then r, g, b = c.r, c.g, c.b end
                else
                    local c = ReactionColor(target)
                    if c then r, g, b = c.r, c.g, c.b end
                end
                local colored = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
                self:AddLine(" ")
                self:AddLine(TARGET .. ": " .. colored, TARGET_NPC_COLOR[1], TARGET_NPC_COLOR[2], TARGET_NPC_COLOR[3])
            end
        end
    end
end

local function AppendID(self, data, formatKey)
    if not Tooltips._enabled or not MANAGED_SET[self] then return end
    if IsSecretTooltip(self) then return end
    if not Get("TooltipShowIDs", false) then return end
    local id = data and data.id
    if id and canaccessvalue(id) then
        self:AddLine(L[formatKey]:format(id), ID_COLOR[1], ID_COLOR[2], ID_COLOR[3])
    end
end

-- [ SCALE & STYLE ]----------------------------------------------------------------------------------
function Tooltips:ApplyScale()
    local scale = self._enabled and Get("TooltipScale", 1.0) or 1.0
    for _, name in ipairs(SCALED_TOOLTIPS) do
        local f = _G[name]
        if f and f.SetScale then f:SetScale(scale) end
    end
end

function Tooltips:ApplyStyle()
    local orbit = self._enabled and IsOrbitStyle()
    for _, tt in ipairs(MANAGED) do
        if orbit then ApplyOrbitSkin(tt) else RemoveOrbitSkin(tt) end
    end
end

-- [ HOOKS ]------------------------------------------------------------------------------------------
function Tooltips:Install()
    if self._installed then return end
    self._installed = true

    -- WorldFrame is protected; EnableMouseMotion is blocked mid-combat (an in-combat /reload runs Install in lockdown), so defer past combat.
    Orbit.CombatManager:QueueUpdate(function() WorldFrame:EnableMouseMotion(true) end)

    -- hooksecurefunc runs in the caller's context, so re-owning stays secure when Blizzard drives the tooltip.
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not Tooltips._enabled or not tooltip or not parent then return end
        local mode = ANCHOR_MODES[Get("TooltipAnchor", ANCHOR_DEFAULT)]
        if mode then tooltip:SetOwner(parent, mode) end
    end)

    -- OnShow re-fits the skin because the tooltip resizes to its content on every show.
    for _, tt in ipairs(MANAGED) do
        local sb = tt.StatusBar
        if sb then
            sb:HookScript("OnShow", function(bar)
                if not Tooltips._enabled or IsSecretTooltip(tt) then return end
                if Get("TooltipHideHealthBar", true) then
                    bar:Hide()
                elseif IsOrbitStyle() then
                    ApplyOrbitSkin(tt)
                else
                    RestoreHealthBar(bar)
                end
            end)
        end
        tt:HookScript("OnHide", function(self)
            if Tooltips._enabled and not IsOrbitStyle() and not IsSecretTooltip(self) then SetBorderColor(self, 1, 1, 1) end
        end)
        tt:HookScript("OnShow", function(self)
            if Tooltips._enabled and IsOrbitStyle() then ApplyOrbitSkin(self) end
        end)
    end

    -- Re-drive SetUnit without the instruction line to strip it; runs in UnitFrame_OnEnter's secure context, so no flicker and no taint.
    hooksecurefunc("UnitFrame_UpdateTooltip", function(frame)
        if not Tooltips._enabled or not Get("TooltipHideInstruction", true) then return end
        if frame.unit and GameTooltip:SetUnit(frame.unit) and not IsSecretTooltip(GameTooltip) then GameTooltip:Show() end
    end)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(self, data) AppendID(self, data, "PLU_TIP_SPELL_ID_F") end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(self, data) AppendID(self, data, "PLU_TIP_ITEM_ID_F") end)
    end
end

-- [ LIFECYCLE ]--------------------------------------------------------------------------------------
function Tooltips:Enable()
    self._enabled = true
    self:Install()
    self:ApplyScale()
    self:ApplyStyle()
end

function Tooltips:Disable()
    self._enabled = false
    self:ApplyScale()
    self:ApplyStyle()
end

-- [ AUTO-ENABLE ON LOGIN ]---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    C_Timer.After(0.5, function()
        if Get("Tooltips", true) then
            Tooltips:Enable()
        end
    end)
    loader:UnregisterAllEvents()
end)
