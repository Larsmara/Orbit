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
local MOUNT_COLOR = { 1, 1, 1 }
local ILVL_COLOR = { 1, 0.82, 0 }
local GUILD_COLOR = { 0.25, 1, 0.25 }
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

-- unitOverride lets the config preview (no live SetUnit) still resolve allegiance tint from a chosen unit.
local function ApplyOrbitSkin(tt, unitOverride)
    if IsSecretTooltip(tt) then return end
    if not tt._orbitBg then
        local bg = tt:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tt)
        tt._orbitBg = bg
        Skin:RegisterMaskedSurface(tt, bg)
    end
    local base = Skin:GetBackgroundColor()
    local d = Get("TooltipDarken", 0)
    local c = { r = base.r * (1 - d), g = base.g * (1 - d), b = base.b * (1 - d), a = base.a }
    tt._orbitBg:SetColorTexture(c.r, c.g, c.b, c.a or 1)
    tt._orbitBg:Show()
    if tt.NineSlice then tt.NineSlice:Hide() end
    local _, unit = tt:GetUnit()
    local tint = AllegianceTint(unitOverride or unit)
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
-- Guild is tooltip line 2 for guilded players; colour it green (matching the config preview) and append rank when enabled.
local function StyleGuildLine(self, unit)
    if not UnitIsPlayer(unit) then return end
    local gname, grank = GetGuildInfo(unit)
    if not gname or not canaccessvalue(gname) then return end
    local line = self.TextLeft2
    local text = line and line:GetText()
    if not text or not canaccessvalue(text) or not text:find(gname, 1, true) then return end
    if Get("TooltipGuildRank", true) and grank and canaccessvalue(grank) then
        line:SetText(text .. " - " .. grank)
    end
    line:SetTextColor(GUILD_COLOR[1], GUILD_COLOR[2], GUILD_COLOR[3])
end

-- Mount reads scan the unit's buffs for a mount aura; OOC-gated by the caller so the 12.1 secret aura path is never hit.
local function AppendMount(self, unit, before)
    local mountName
    AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
        local spellID = aura and aura.spellId
        if spellID and canaccessvalue(spellID) then
            local mountID = C_MountJournal.GetMountFromSpell(spellID)
            if mountID then
                mountName = C_MountJournal.GetMountInfoByID(mountID)
                return true
            end
        end
    end, true)
    if mountName then
        before()
        self:AddLine(L.PLU_TIP_MOUNT_F:format(mountName), MOUNT_COLOR[1], MOUNT_COLOR[2], MOUNT_COLOR[3])
    end
end

-- Inspect is async and range/rate-limited, so item level lands one INSPECT_READY later; cache per-GUID keeps re-hovers instant.
local ilvlCache = {}
local pendingGUID, pendingUnit

-- White label + gold value on one line: base colour is white, the number carries its own colour escape.
local function ShowIlvl(self, ilvl, before)
    before()
    local value = ("|cff%02x%02x%02x%d|r"):format(ILVL_COLOR[1] * 255, ILVL_COLOR[2] * 255, ILVL_COLOR[3] * 255, ilvl)
    self:AddLine(L.PLU_TIP_ILVL_F:format(value), 1, 1, 1)
end

local function AppendIlvl(self, unit, before)
    if not UnitIsPlayer(unit) then return end
    if UnitIsUnit(unit, "player") then
        local _, equipped = GetAverageItemLevel()
        ShowIlvl(self, math.floor((equipped or 0) + 0.5), before)
        return
    end
    local guid = UnitGUID(unit)
    if not guid or not canaccessvalue(guid) then return end
    local cached = ilvlCache[guid]
    if cached then ShowIlvl(self, cached, before); return end
    if CanInspect(unit) then
        pendingGUID, pendingUnit = guid, unit
        NotifyInspect(unit)
    end
end

-- Inspect landed after the tooltip built, so re-drive SetUnit (a safe secure delegate) to rebuild with the cache hit — an AddLine now would append below other addons instead of under the identity block. Cache is set first so the rebuild's AppendIlvl short-circuits and doesn't re-inspect.
local function OnInspectReady(guid)
    if not Tooltips._enabled or guid ~= pendingGUID then return end
    local unit = pendingUnit
    pendingGUID, pendingUnit = nil, nil
    ClearInspectPlayer()
    if not unit or UnitGUID(unit) ~= guid then return end
    local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
    if not ilvl or ilvl == 0 then return end
    ilvlCache[guid] = math.floor(ilvl + 0.5)
    if GameTooltip:IsShown() and not IsSecretTooltip(GameTooltip) then
        local _, ttUnit = GameTooltip:GetUnit()
        if ttUnit and UnitGUID(ttUnit) == guid then GameTooltip:SetUnit(ttUnit) end
    end
end

-- Registered at file load (before third-party addons like Raider.IO), so these lines append while the tooltip still holds only Blizzard's base block — landing directly under the identity lines rather than below other addons' content. OOC-only keeps mount/ilvl off the 12.1 secret path.
local function OnUnitIdentity(self)
    if not Tooltips._enabled or not MANAGED_SET[self] then return end
    if IsSecretTooltip(self) then return end
    if UnitAffectingCombat("player") then return end
    local _, unit = self:GetUnit()
    if not unit or not canaccessvalue(unit) then return end
    -- One blank line separates these from the identity block; added lazily so a still-loading ilvl doesn't leave a stray spacer.
    local spaced = false
    local function spacer()
        if not spaced then self:AddLine(" "); spaced = true end
    end
    if Get("TooltipShowIlvl", false) then AppendIlvl(self, unit, spacer) end
    if Get("TooltipShowMount", false) then AppendMount(self, unit, spacer) end
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

    StyleGuildLine(self, unit)

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
    self:RefreshPreview()
end

function Tooltips:ApplyStyle()
    local orbit = self._enabled and IsOrbitStyle()
    for _, tt in ipairs(MANAGED) do
        if orbit then ApplyOrbitSkin(tt) else RemoveOrbitSkin(tt) end
    end
    self:RefreshPreview()
end

-- [ CONFIG PREVIEW ]---------------------------------------------------------------------------------
-- A standalone GameTooltip driven from the live player + current settings so the config panel shows the actual result. Not in MANAGED, so the global post-calls skip it — lines are built here instead.
local PREVIEW_GAP = 16

local function AppendMountPreview(tt, spacer)
    local mounted
    AppendMount(tt, "player", function() spacer(); mounted = true end)
    if mounted then return end
    -- Not mounted: illustrate with the first collected mount (real, localized name — no hardcoded string).
    local ids = C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountIDs()
    for _, id in ipairs(ids or {}) do
        local mname, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(id)
        if collected and mname then
            spacer()
            tt:AddLine(L.PLU_TIP_MOUNT_F:format(mname), MOUNT_COLOR[1], MOUNT_COLOR[2], MOUNT_COLOR[3])
            return
        end
    end
end

local function BuildPreviewLines(tt)
    local classFile = UnitClassBase("player")
    local cc = classFile and ClassColor(classFile)
    tt:AddLine(UnitName("player") or PLAYER, cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1)

    local gname, grank = GetGuildInfo("player")
    if gname then
        if Get("TooltipGuildRank", true) and grank then gname = gname .. " - " .. grank end
        tt:AddLine(gname, GUILD_COLOR[1], GUILD_COLOR[2], GUILD_COLOR[3])
    end
    tt:AddLine(("%s %d %s (%s)"):format(LEVEL, UnitLevel("player"), UnitRace("player") or "", PLAYER), 1, 1, 1)
    tt:AddLine(UnitClass("player") or "", 1, 1, 1)
    tt:AddLine(UnitFactionGroup("player") == "Horde" and FACTION_HORDE or FACTION_ALLIANCE, 1, 1, 1)

    local spaced = false
    local function spacer() if not spaced then tt:AddLine(" "); spaced = true end end
    if Get("TooltipShowIlvl", false) then AppendIlvl(tt, "player", spacer) end
    if Get("TooltipShowMount", false) then AppendMountPreview(tt, spacer) end
    if Get("TooltipShowTarget", false) then
        tt:AddLine(" ")
        tt:AddLine(TARGET .. ": " .. (UnitExists("target") and UnitName("target") or (UnitName("player") or PLAYER)),
            TARGET_NPC_COLOR[1], TARGET_NPC_COLOR[2], TARGET_NPC_COLOR[3])
    end
end

-- Canonical custom-tooltip order: own (clears lines) → point → lines → show → skin. Showing an empty tooltip first would auto-hide it.
local function RenderPreview(tt, anchor)
    tt:SetOwner(anchor, "ANCHOR_NONE")
    tt:ClearAllPoints()
    tt:SetPoint("LEFT", anchor, "RIGHT", PREVIEW_GAP, 0)
    BuildPreviewLines(tt)
    if not Get("TooltipHideInstruction", true) then
        tt:AddLine(L.PLU_TIP_PREVIEW_HINT, 0, 1, 0)
    end
    -- Static sample bar (unit-health OnUpdate neutered — the preview has no unit) so the Hide Health Bar toggle is visible.
    local bar = tt.StatusBar
    if Get("TooltipHideHealthBar", true) then
        bar:Hide()
    else
        bar:SetScript("OnUpdate", nil)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.72)
        bar:SetStatusBarColor(0.2, 0.75, 0.2)
        bar:Show()
    end
    tt:SetScale(Get("TooltipScale", 1.0))
    tt:Show()
    if IsOrbitStyle() then
        ApplyOrbitSkin(tt, "player")
    else
        RemoveOrbitSkin(tt)
        local tint = AllegianceTint("player")
        SetBorderColor(tt, tint and tint.r or 1, tint and tint.g or 1, tint and tint.b or 1)
    end
end

function Tooltips:RefreshPreview()
    if not self._previewActive or not self._preview then return end
    RenderPreview(self._preview, self._previewAnchor)
end

function Tooltips:ShowPreview(anchorFrame)
    if not anchorFrame then return end
    self._previewActive = true
    self._previewAnchor = anchorFrame
    if not self._preview then
        local tt = CreateFrame("GameTooltip", "OrbitTooltipPreview", anchorFrame, "GameTooltipTemplate")
        tt:SetFrameStrata("TOOLTIP")
        tt:SetClampedToScreen(true)
        -- The template's data mixin clears manually-added lines on data-refresh events; unregister so our content persists.
        tt:UnregisterAllEvents()
        self._preview = tt
    end
    self._preview:SetParent(anchorFrame)
    RenderPreview(self._preview, anchorFrame)
end

function Tooltips:HidePreview()
    self._previewActive = false
    if self._preview then self._preview:Hide() end
end

-- [ HOOKS ]------------------------------------------------------------------------------------------
function Tooltips:Install()
    if self._installed then return end
    self._installed = true

    -- WorldFrame is protected; EnableMouseMotion is blocked mid-combat (an in-combat /reload runs Install in lockdown), so defer past combat.
    Orbit.CombatManager:QueueUpdate(function() WorldFrame:EnableMouseMotion(true) end)

    local inspect = CreateFrame("Frame")
    inspect:RegisterEvent("INSPECT_READY")
    inspect:SetScript("OnEvent", function(_, _, guid) OnInspectReady(guid) end)

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

-- Register the identity enrichment at file load — running before third-party tooltip addons is what places its lines under the identity block. Guarded by _enabled, so it's inert until Enable().
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitIdentity)
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
