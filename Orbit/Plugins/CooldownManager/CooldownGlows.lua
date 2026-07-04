---@type Orbit
local Orbit = Orbit
local Constants = Orbit.Constants
local GC = Orbit.Engine.GlowController
local GU = Orbit.Engine.GlowUtils

local CDM = Orbit:GetPlugin("Orbit_CooldownViewer")
if not CDM then return end

local ESSENTIAL_INDEX = Constants.Cooldown.SystemIndex.Essential
local UTILITY_INDEX = Constants.Cooldown.SystemIndex.Utility
local BUFFICON_INDEX = Constants.Cooldown.SystemIndex.BuffIcon
local PANDEMIC_KEY = "orbitPandemic"
local GLOW_STORE_INDEX = 0
local KIND_KEYS = { glow = "glows", color = "colors", alert = "alerts" }

-- [ PER-SPELL GLOW STORE ] --------------------------------------------------------------------------
-- Native CDM icons have no per-instance record, so per-icon glow/colour/alert choices are keyed by cooldownID in the plugin's spec data (per-character, per-spec — cooldownIDs are spec-bound). Never GlobalSettings: that blob is profile-cloned theme data and a profile/spec switch would wipe these.
local function GlowStore(create)
    local store = CDM:GetSpecData(GLOW_STORE_INDEX, "SpellGlows")
    if not store and create then
        store = {}
        CDM:SetSpecData(GLOW_STORE_INDEX, "SpellGlows", store)
    end
    return store
end

-- cooldownIDs read from live buttons can be secret in combat; a secret table key throws, so gate every access.
function CDM:GetSpellGlowValue(cid, kind, cond)
    if not cid or issecretvalue(cid) then return nil end
    local store = GlowStore(false)
    local entry = store and store[cid]
    local values = entry and entry[KIND_KEYS[kind]]
    return values and values[cond] or nil
end

function CDM:SetSpellGlowValue(cid, kind, cond, value)
    if not cid or issecretvalue(cid) then return end
    local store = GlowStore(true)
    local entry = store[cid]
    if not entry then entry = {}; store[cid] = entry end
    local kindKey = KIND_KEYS[kind]
    local values = entry[kindKey]
    if not values then values = {}; entry[kindKey] = values end
    values[cond] = value
end

function CDM:HasSpellGlowOverride(cid, cond)
    if not cid or issecretvalue(cid) then return false end
    local store = GlowStore(false)
    local entry = store and store[cid]
    if not entry then return false end
    local glow = entry.glows and entry.glows[cond]
    local color = entry.colors and entry.colors[cond]
    return glow ~= nil or color ~= nil
end

-- Per-cooldown Type/Color override the viewer setting when set; everything else falls back unchanged (additive).
function CDM:SpellGlowLookup(cid, prefix, fallback)
    local cond = (prefix == "ProcGlow" and "proc") or (prefix == "PandemicGlow" and "pandemic") or nil
    return function(k)
        if cond and k == prefix .. "Type" then
            local t = self:GetSpellGlowValue(cid, "glow", cond)
            if t ~= nil then return t end
        end
        if cond and k == prefix .. "Color" then
            local c = self:GetSpellGlowValue(cid, "color", cond)
            if c ~= nil then return c end
        end
        return fallback(k)
    end
end

-- Pre-release builds stored these in the profile-cloned GlobalSettings; purge live + profile copies so stale data never resurfaces via a profile switch.
local function PurgeLegacyGlowStores(gs)
    if not gs then return end
    gs.CDMSpellGlows, gs.CDMSpellGlowColors, gs.CDMSpellAlerts = nil, nil, nil
end
PurgeLegacyGlowStores(Orbit.db and Orbit.db.GlobalSettings)
for _, profile in pairs((Orbit.db and Orbit.db.profiles) or {}) do
    PurgeLegacyGlowStores(profile.GlobalSettings)
end

-- CDM GetSpellID reads are secret in combat; CooldownLayout caches the id out of combat so alerts (TTS spell names) keep working mid-fight.
local function AlertSpellID(button)
    return button.orbitCachedSpellID or (button.GetSpellID and button:GetSpellID())
end

-- [ DEFERRED HIDE BATCHING ] ------------------------------------------------------------------------
-- Defer hides 1 frame so Blizzard's HideAll → Re-Show (hundreds/sec in raids) cancels pending hide, eliminating flicker.
local pendingProcHides = {}
local procHideScheduled = false
local pendingPandemicHides = {}
local pandemicHideScheduled = false

local function FlushProcHides()
    procHideScheduled = false
    for button in pairs(pendingProcHides) do
        GC:HideProc(button)
        button._orbitProcAlertedCid = nil
    end
    wipe(pendingProcHides)
end

local PANDEMIC_DEFER_INTERVAL = 0.2

local function FlushPandemicHides()
    pandemicHideScheduled = false
    for icon in pairs(pendingPandemicHides) do
        local pi = icon.PandemicIcon
        if pi and pi:IsShown() then
            -- Blizzard's ground truth says pandemic IS active — abort hide
            pendingPandemicHides[icon] = nil
        elseif GC:IsActive(icon, PANDEMIC_KEY) then
            GC:HidePandemic(icon)
            if not icon._orbitGlow then icon._orbitGlow = { active = {} } end
            icon._orbitGlow.suppressPandemic = nil
        end
    end
    wipe(pendingPandemicHides)
end

local function DeferProcHide(button)
    pendingProcHides[button] = true
    if not procHideScheduled then
        procHideScheduled = true
        C_Timer.After(0, FlushProcHides)
    end
end

local function DeferPandemicHide(icon)
    pendingPandemicHides[icon] = true
    if not pandemicHideScheduled then
        pandemicHideScheduled = true
        C_Timer.After(PANDEMIC_DEFER_INTERVAL, FlushPandemicHides)
    end
end

-- [ PROC GLOW HOOKS ] -------------------------------------------------------------------------------
-- Self-write the memo on first hit — pre-layout alerts can fire before CooldownLayout populates orbitCDMSystemIndex, and the find walk is O(viewers × icons).
local function FindSystemIndexForButton(button)
    if button.orbitCDMSystemIndex then return button.orbitCDMSystemIndex end
    for systemIndex, data in pairs(CDM.viewerMap) do
        if data.viewer and data.viewer.GetItemFrames then
            for _, icon in ipairs(data.viewer:GetItemFrames()) do
                if icon == button then
                    button.orbitCDMSystemIndex = systemIndex
                    return systemIndex
                end
            end
        end
    end
    return nil
end

function CDM:HookProcGlow()
    if self.procGlowHooked or not ActionButtonSpellAlertManager then return end
    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, button)
        local si = FindSystemIndexForButton(button)
        if not si then return end
        pendingProcHides[button] = nil
        local lookup = function(k) return self:GetSetting(si, k) end
        local cid = button.GetCooldownID and button:GetCooldownID()
        if cid and not issecretvalue(cid) then
            lookup = self:SpellGlowLookup(cid, "ProcGlow", lookup)
            -- Blizzard re-issues ShowAlert on every viewer refresh through one proc window; alert only on the show edge (cid-stamped so button reassignment re-arms).
            if button._orbitProcAlertedCid ~= cid then
                button._orbitProcAlertedCid = cid
                Orbit.SpellGlows:FireAlert(self:GetSpellGlowValue(cid, "alert", "proc"), AlertSpellID(button))
            end
        end
        GC:ShowProc(button, lookup, "ProcGlow", Constants.Glow.DefaultColor)
    end)
    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, button)
        local si = FindSystemIndexForButton(button)
        if not si then return end
        DeferProcHide(button)
    end)
    self.procGlowHooked = true
end

-- [ NATIVE GLOW MENU ] ------------------------------------------------------------------------------
-- Shift-right-click a native CDM icon → per-spell glow menu. Uses GLOBAL_MOUSE_DOWN + GetMouseFoci, NOT HookScript on the native frames — hooking their scripts taints the CDM viewer children (same reason CooldownSettingsDragBridge avoids it).
function CDM:HookNativeGlowMenu()
    if self._nativeGlowMenuHooked then return end
    self._nativeGlowMenuHooked = true
    local plugin = self
    local f = CreateFrame("Frame")
    f:RegisterEvent("GLOBAL_MOUSE_DOWN")
    f:SetScript("OnEvent", function(_, _, button)
        if button ~= "RightButton" or not IsShiftKeyDown() or InCombatLockdown() then return end
        -- Native CDM item frames are click-through (mouse not click-enabled), so GetMouseFoci never returns them. Hit-test by geometry instead — IsMouseOver works regardless of mouse-enabled state.
        for _, entry in pairs(plugin.viewerMap) do
            local viewer = entry.viewer
            if viewer and viewer:IsShown() and viewer.GetItemFrames then
                for _, item in ipairs(viewer:GetItemFrames()) do
                    if item:IsShown() and item.GetCooldownID and item:IsMouseOver() then
                        local cid = item:GetCooldownID()
                        local sid = item.GetSpellID and item:GetSpellID()
                        if Orbit.DEBUG_GLOWMENU then print("|cff66ccff[GlowMenu]|r hit item sid:", tostring(sid), "cid:", tostring(cid)) end
                        if sid and cid then
                            Orbit.SpellGlows:OpenMenu(item, {
                                id = sid, itemType = "spell",
                                supported = { proc = true, pandemic = true },
                                get = function(cond) return plugin:GetSpellGlowValue(cid, "glow", cond) end,
                                set = function(cond, t) plugin:SetSpellGlowValue(cid, "glow", cond, t); plugin:MarkPandemicDirty() end,
                                getColor = function(cond) return plugin:GetSpellGlowValue(cid, "color", cond) end,
                                setColor = function(cond, c) plugin:SetSpellGlowValue(cid, "color", cond, c); plugin:MarkPandemicDirty() end,
                                getAlert = function(cond) return plugin:GetSpellGlowValue(cid, "alert", cond) end,
                                setAlert = function(cond, v) plugin:SetSpellGlowValue(cid, "alert", cond, v) end,
                            })
                            return
                        end
                    end
                end
            end
        end
        if Orbit.DEBUG_GLOWMENU then print("|cff66ccff[GlowMenu]|r shift-rclick: no CDM item under cursor") end
    end)
end

-- [ GLOW TRANSPARENCY FIX ] -------------------------------------------------------------------------
function CDM:FixGlowTransparency(glowFrame, alpha)
    if not glowFrame or not alpha then return end
    if glowFrame.ProcLoopAnim and glowFrame.ProcLoopAnim.alphaRepeat then
        glowFrame.ProcLoopAnim.alphaRepeat:SetFromAlpha(alpha)
        glowFrame.ProcLoopAnim.alphaRepeat:SetToAlpha(alpha)
    end
    if glowFrame.ProcStartAnim then
        for _, anim in pairs({ glowFrame.ProcStartAnim:GetAnimations() }) do
            if anim:GetObjectType() == "Alpha" then
                local order = anim:GetOrder()
                if order == 0 then anim:SetFromAlpha(alpha); anim:SetToAlpha(alpha)
                elseif order == 2 then anim:SetFromAlpha(alpha) end
            end
        end
    end
end

-- [ PANDEMIC GLOW ] ---------------------------------------------------------------------------------
local GlowType = Constants.Glow.Type

local function SuppressPandemicIcon(icon)
    local pi = icon.PandemicIcon
    if not pi then return end
    local state = icon._orbitGlow
    local suppress = state and state.suppressPandemic
    if not suppress then return end
    if not pi._orbitGlowHooked then
        hooksecurefunc(pi, "SetAlpha", function(self, a)
            local s = icon._orbitGlow
            if a ~= 0 and s and s.suppressPandemic then self:SetAlpha(0) end
        end)
        hooksecurefunc(pi, "Show", function(self)
            local s = icon._orbitGlow
            if s and s.suppressPandemic then self:SetAlpha(0) end
        end)
        pi._orbitGlowHooked = true
    end
    if pi:GetAlpha() ~= 0 then pi:SetAlpha(0) end
end

local function SetPandemicSuppress(icon, suppress)
    if not icon._orbitGlow then icon._orbitGlow = { active = {} } end
    icon._orbitGlow.suppressPandemic = suppress or nil
end

local HookPandemicIcon
HookPandemicIcon = function(icon, plugin, systemIndex)
    if icon._orbitPandemicHooked then return end
    if not icon.ShowPandemicStateFrame then return end
    icon._orbitPandemicHooked = true
    local function OnPandemicShow(self)
        pendingPandemicHides[self] = nil
        local cid = self.GetCooldownID and self:GetCooldownID()
        if cid and issecretvalue(cid) then cid = nil end
        if cid and not self._orbitPandemicAlerted then
            self._orbitPandemicAlerted = true
            Orbit.SpellGlows:FireAlert(plugin:GetSpellGlowValue(cid, "alert", "pandemic"), AlertSpellID(self))
        end
        local lk = function(k) return plugin:GetSetting(systemIndex, k) end
        if cid then lk = plugin:SpellGlowLookup(cid, "PandemicGlow", lk) end
        local glowType = lk("PandemicGlowType") or GlowType.None
        SetPandemicSuppress(self, true)
        SuppressPandemicIcon(self)
        if glowType == GlowType.None then
            GC:StopPandemic(self)
            return
        end
        if not GC:IsActive(self, PANDEMIC_KEY) then
            local typeName, options = GU:BuildOptionsFromLookup(lk, "PandemicGlow", Constants.Glow.DefaultColor, PANDEMIC_KEY)
            if typeName and options then
                options.frameLevel = Constants.Levels.IconGlow
                GC:ShowPandemic(self, typeName, options, 1)
            end
        else
            GC:ShowPandemicAlpha(self, 1)
        end
    end
    local function OnPandemicHide(self)
        self._orbitPandemicAlerted = nil
        if GC:IsActive(self, PANDEMIC_KEY) then
            DeferPandemicHide(self)
        end
    end
    hooksecurefunc(icon, "ShowPandemicStateFrame", function(self)
        SuppressPandemicIcon(self)
        OnPandemicShow(self)
    end)
    hooksecurefunc(icon, "HidePandemicStateFrame", function(self)
        OnPandemicHide(self)
    end)
    hooksecurefunc(icon, "Hide", function(self)
        pendingPandemicHides[self] = nil
        GC:StopPandemic(self)
        SetPandemicSuppress(self, nil)
    end)
end

-- GC hashes options after injecting pixelScale; mirror that here or the stored-vs-fresh compare below never matches and the glow restarts every pass.
local function CompleteOptionsHash(options)
    if not options then return nil end
    options.pixelScale = Orbit.Engine.Pixel:GetScale()
    return GU:GetOptionsHash(options)
end

function CDM:CheckPandemicFrames(viewer, systemIndex)
    if not viewer then return end
    local icons = viewer.GetItemFrames and viewer:GetItemFrames()
    if not icons then return end
    -- One systemIndex-level build shared by every icon without a per-spell override; overrides rebuild per icon (rare).
    local baseLk = function(k) return self:GetSetting(systemIndex, k) end
    local baseGlowType = baseLk("PandemicGlowType") or GlowType.None
    local baseTypeName, baseOptions = GU:BuildOptionsFromLookup(baseLk, "PandemicGlow", Constants.Glow.DefaultColor, PANDEMIC_KEY)
    local baseHash = CompleteOptionsHash(baseOptions)
    for _, icon in ipairs(icons) do
        HookPandemicIcon(icon, self, systemIndex)
        local cid = icon.GetCooldownID and icon:GetCooldownID()
        local glowType, typeName, options, hash = baseGlowType, baseTypeName, baseOptions, baseHash
        if self:HasSpellGlowOverride(cid, "pandemic") then
            local lk = self:SpellGlowLookup(cid, "PandemicGlow", baseLk)
            glowType = lk("PandemicGlowType") or GlowType.None
            typeName, options = GU:BuildOptionsFromLookup(lk, "PandemicGlow", Constants.Glow.DefaultColor, PANDEMIC_KEY)
            hash = CompleteOptionsHash(options)
        end
        local activeType = GC:GetActiveType(icon, PANDEMIC_KEY)
        if activeType and (activeType ~= typeName or (icon._orbitGlow and icon._orbitGlow.active[PANDEMIC_KEY] and icon._orbitGlow.active[PANDEMIC_KEY].hash ~= hash)) then
            GC:StopPandemic(icon)
        end
        if icon.PandemicIcon and icon.PandemicIcon:IsShown() then
            SetPandemicSuppress(icon, true)
            SuppressPandemicIcon(icon)
            if glowType ~= GlowType.None and typeName and options then
                -- GC mutates and may retain the options table; showing icons take a copy so the hoisted base stays shared-safe.
                local shown = {}
                for k, v in pairs(options) do shown[k] = v end
                shown.frameLevel = Constants.Levels.IconGlow
                GC:ShowPandemic(icon, typeName, shown, 1)
            end
        end
    end
end

function CDM:ClearAllPandemicGlows()
    wipe(pendingPandemicHides)
    for _, entry in pairs(CDM.viewerMap) do
        if entry.viewer and entry.viewer.GetItemFrames then
            local icons = entry.viewer:GetItemFrames()
            if icons then
                for _, icon in ipairs(icons) do
                    GC:StopPandemic(icon)
                    SetPandemicSuppress(icon, nil)
                end
            end
        end
    end
end
