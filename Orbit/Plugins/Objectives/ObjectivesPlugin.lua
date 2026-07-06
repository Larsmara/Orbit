---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine

-- [ CONSTANTS ]--------------------------------------------------------------------------------------
local C = Orbit.ObjectivesConstants
local SYSTEM_ID = C.SYSTEM_ID

-- [ PLUGIN REGISTRATION ]----------------------------------------------------------------------------
local Plugin = Orbit:RegisterPlugin("Objectives", SYSTEM_ID, {
    defaults = {
        Scale = C.DEFAULT_SCALE,
        Width = C.DEFAULT_WIDTH,
        Height = C.DEFAULT_HEIGHT,
        HeaderColor = C.HEADER_COLOR_DEFAULT,
        ShowBorder = false,
        BackgroundOpacity = C.BG_OPACITY_DEFAULT,
        AutoCollapseCombat = false,
        ZoneFilter = false,
        ZoneWorldQuests = false,
        ShowQuestCount = true,
        Format = C.FORMAT_DEFAULT,
        Opacity = C.OPACITY_DEFAULT,
        ProgressBarLabelFormat = C.PROGRESS_FORMAT_DEFAULT,
        TitleFontSize = C.TITLE_FONT_SIZE_DEFAULT,
        ObjectiveFontSize = C.OBJECTIVE_FONT_SIZE_DEFAULT,
        HeaderFontSize = C.HEADER_FONT_SIZE_DEFAULT,
        TitleColor = C.TITLE_COLOR_DEFAULT,
        CompletedColor = C.COMPLETED_COLOR_DEFAULT,
        FocusColor = C.FOCUS_COLOR_DEFAULT,
    },
    displayName = Orbit.L.PLG_NAME_OBJECTIVES,
})

_G.BINDING_NAME_ORBIT_OBJECTIVES_TOGGLE = Orbit.L.PLU_OBJ_BINDING_TOGGLE

Mixin(Plugin, Orbit.NativeBarMixin)

-- [ MIGRATION ]--------------------------------------------------------------------------------------
local COLOR_KEYS = { "TitleColor", "CompletedColor", "FocusColor" }

local function MigrateColorSettings(plugin)
    for _, key in ipairs(COLOR_KEYS) do
        local raw = plugin:GetSetting(SYSTEM_ID, key)
        local clean = C.ValidateColor(raw, nil)
        if clean and clean ~= raw then
            plugin:SetSetting(SYSTEM_ID, key, clean)
        end
    end
end

-- Retire dropped keys (StyleMode, legacy curve/progress) and wipe old collapse state that keyed Blizzard module globals (had a "_main" entry) so it re-keys to our section keys.
local function MigrateLegacySettings(plugin)
    if plugin:GetSetting(SYSTEM_ID, "ClassColorHeaders") == true then
        plugin:SetSetting(SYSTEM_ID, "HeaderColor", { r = 1, g = 1, b = 1, a = 1, type = "class" })
    end
    plugin:SetSetting(SYSTEM_ID, "ClassColorHeaders", nil)

    local mode = plugin:GetSetting(SYSTEM_ID, "ProgressBarMode")
    if (mode == "XY" or mode == "Both")
        and plugin:GetSetting(SYSTEM_ID, "ProgressBarLabelFormat") == C.PROGRESS_FORMAT_DEFAULT then
        plugin:SetSetting(SYSTEM_ID, "ProgressBarLabelFormat", mode == "XY" and "Current / Max" or "Current / Max (%)")
    end
    plugin:SetSetting(SYSTEM_ID, "ProgressBarMode", nil)
    plugin:SetSetting(SYSTEM_ID, "SkinProgressBars", nil)
    plugin:SetSetting(SYSTEM_ID, "BlizzardProgressBars", nil)
    plugin:SetSetting(SYSTEM_ID, "StyleMode", nil)

    local cs = Orbit.db and Orbit.db.AccountSettings and Orbit.db.AccountSettings.ObjectivesCollapseState
    if cs and cs._main ~= nil then Orbit.db.AccountSettings.ObjectivesCollapseState = {} end
end

-- True when an anchor's width-sync owns our width (top/bottom edge).
local function IsWidthSynced(frame)
    if not frame.orbitWidthSync then return false end
    local FA = OrbitEngine.FrameAnchor
    local anchor = FA and FA.anchors[frame]
    if not anchor then return false end
    local Axis = OrbitEngine.Axis
    local edgeAxis = Axis and Axis.ForEdge(anchor.edge)
    return (edgeAxis and edgeAxis.perpendicular == Axis.horizontal) or false
end

-- [ LIFECYCLE ]--------------------------------------------------------------------------------------
function Plugin:OnLoad()
    if not Orbit:IsPluginEnabled(self.name) then return end

    MigrateColorSettings(self)
    MigrateLegacySettings(self)

    self.frame = CreateFrame("Frame", "OrbitObjectivesContainer", UIParent)
    -- Pixel-lock every dynamic size change (content-fit, resize, width-sync) to the physical grid.
    OrbitEngine.Pixel:Enforce(self.frame)
    self.frame:SetSize(C.DEFAULT_WIDTH, C.DEFAULT_HEIGHT)
    self.frame:SetClampedToScreen(true)
    self.frame.systemIndex = SYSTEM_ID
    self.frame.editModeName = self.displayName
    self.frame.orbitResizeBounds = {
        minW = C.WIDTH_MIN,
        maxW = C.WIDTH_MAX,
        minH = C.HEIGHT_MIN,
        maxH = C.HEIGHT_MAX,
        widthKey = "Width",
        heightKey = "Height",
    }
    self.frame.anchorOptions = { horizontal = true, vertical = true }
    -- Force the saved/restored anchor to keep a TOP component so the box grows downward on resize instead of re-centering.
    self.frame.orbitForceAnchorPoint = "TOPRIGHT"
    -- When docked top/bottom to another Orbit frame, match that frame's width.
    self.frame.orbitWidthSync = true

    -- ScrollFrame clips only its own scroll child, so the Edit Mode selection/resize handles (siblings of the child) stay visible.
    self.scrollFrame = CreateFrame("ScrollFrame", "OrbitObjectivesScroll", self.frame)
    self.scrollFrame:SetClipsChildren(false)
    self.scrollFrame:EnableMouseWheel(true)
    self.scrollFrame:SetScript("OnMouseWheel", function(_, delta) self:OnScroll(delta) end)
    self.scrollFrame:SetScript("OnScrollRangeChanged", function() self:UpdateScrollClip() end)

    self.scrollChild = CreateFrame("Frame", "OrbitObjectivesScrollChild", self.scrollFrame)
    self.scrollChild:SetSize(C.DEFAULT_WIDTH, C.DEFAULT_HEIGHT)
    self.scrollFrame:SetScrollChild(self.scrollChild)
    self.scrollFrame:SetScript("OnSizeChanged", function(_, w) self.scrollChild:SetWidth(w) end)

    self.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", C.DEFAULT_ANCHOR_X, C.DEFAULT_ANCHOR_Y)

    OrbitEngine.Frame:AttachSettingsListener(self.frame, self, SYSTEM_ID)
    OrbitEngine.Frame:RestorePosition(self.frame, self, SYSTEM_ID)

    -- Re-apply only on a genuine anchor CHANGE: the engine re-fires this with the same parent/edge/padding on every edit-mode open.
    self.frame.OnAnchorChanged = function(_, parent, edge, padding)
        if parent == self._anchorParent and edge == self._anchorEdge and padding == self._anchorPadding then return end
        self._anchorParent, self._anchorEdge, self._anchorPadding = parent, edge, padding
        self:ApplySettings()
    end

    -- The taint launder: this OnUpdate frame is created here on a clean stack and never touched again, so FullLayout (which Show()s pooled rows) always runs clean no matter how many tainted hook paths call ScheduleRefresh.
    self:RegisterUpdate(function(_, elapsed)
        self._pollAccum = (self._pollAccum or 0) + elapsed
        if self._pollAccum < C.REFRESH_POLL_INTERVAL then return end
        self._pollAccum = 0
        if not self._refreshPending then return end
        self._refreshPending = false
        self:FullLayout()
    end)

    self:RegisterStandardEvents()
    -- Replace the standard heavy edit-mode Enter/Exit (a full ApplySettings re-anchors + re-Shows the reparented Blizzard scenario block every toggle) with a height-only resize. A genuine move still re-applies via OnAnchorChanged.
    OrbitEngine.EditMode:UnregisterCallbacks(self)
    OrbitEngine.EditMode:RegisterCallbacks({
        Enter = function() self:OnEditModeToggle() end,
        Exit = function() self:OnEditModeToggle() end,
    }, self)
    self:RegisterVisibilityEvents()
    self:InstallEventHandlers()

    Orbit.EventBus:On("ORBIT_BORDER_SIZE_CHANGED", function() self:ApplySettings() end, self)
    Orbit.EventBus:On("ORBIT_GLOBAL_BACKDROP_CHANGED", function()
        -- Bar background reads the global backdrop, but the bar re-skin is epoch-gated on texture/border only — bump so it re-applies.
        Orbit.ObjectivesSkin._barStyleEpoch = Orbit.ObjectivesSkin._barStyleEpoch + 1
        self:ApplySettings()
    end, self)
    Orbit.EventBus:On("ORBIT_PLAYER_SPECIALIZATION_CHANGED", function() self:ScheduleRefresh() end, self)
    -- StatusWidget's M+ orb owns the keystone display; drop our duplicate scenario block while it does.
    Orbit.EventBus:On("ORBIT_MPLUS_OWNERSHIP_CHANGED", function(_, hidden)
        self._mplusOwned = hidden and true or false
        self:ScheduleRefresh()
    end, self)
    -- Recover current ownership on boot: StatusWidget loads first, so on a reload mid-key its one-shot event fired before we listened — pull the flag it already set.
    local sw = Orbit:GetPlugin("Status Widget")
    if sw and sw.IsBlizzardMPlusHidden then self._mplusOwned = sw:IsBlizzardMPlusHidden() end

    local function Boot()
        -- The manager assigns its modules at PLAYER_ENTERING_WORLD (after this Boot); hook Init so our removal runs once they exist.
        if ObjectiveTrackerManager and not self._initHooked then
            self._initHooked = true
            hooksecurefunc(ObjectiveTrackerManager, "Init", function() self:SuppressBlizzardTracker() end)
        end
        self:SuppressBlizzardTracker()
        self:ApplySettings()
        self:ScheduleRefresh()
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_ObjectiveTracker") then
        Boot()
    else
        self._addonLoader = CreateFrame("Frame")
        self._addonLoader:RegisterEvent("ADDON_LOADED")
        self._addonLoader:SetScript("OnEvent", function(f, _, addonName)
            if addonName == "Blizzard_ObjectiveTracker" then
                Boot()
                f:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
end

-- [ BLIZZARD SUPPRESSION ]---------------------------------------------------------------------------
-- Quest-family modules whose Update renders the POI number-buttons that write the shared QuestCache (the WorldMap taint). We remove them from Blizzard's container so they never render, and render them ourselves.
local BLIZZARD_REMOVE = {
    "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "WorldQuestObjectiveTracker",
    "BonusObjectiveTracker", "AchievementObjectiveTracker", "ProfessionsRecipeTracker",
    "MonthlyActivitiesObjectiveTracker", "AdventureObjectiveTracker", "InitiativeTasksObjectiveTracker",
}

-- Coalesced next-frame entry point: schedule the reparent one frame out so it lands after Blizzard's own Init / managed-frame layout / edit-mode restore instead of racing them.
function Plugin:SuppressBlizzardTracker()
    if not ObjectiveTrackerFrame then return end
    if InCombatLockdown() then
        Orbit.CombatManager:QueueUpdate(function() self:SuppressBlizzardTracker() end)
        return
    end
    if self._suppressScheduled then return end
    self._suppressScheduled = true
    C_Timer.After(0, function()
        self._suppressScheduled = false
        self:ApplyBlizzardSuppression()
    end)
end

-- Detach ObjectiveTrackerFrame from Blizzard's Edit Mode and right-managed layout so neither shows a stray selection box under ours nor re-anchors it away from our box. Idempotent; runs on a clean stack (no protected ops — Edit Mode is OOC-only).
function Plugin:DetachNativeSystems(tracker)
    -- Blizzard's own "hidden system" flag: OnEditModeEnter skips HighlightSystem, so the .Selection overlay never anchors/shows.
    tracker.defaultHideSelection = true
    if tracker.ClearHighlight and (tracker.isHighlighted or tracker.isSelected) then tracker:ClearHighlight() end
    -- ManagedFrameMixin re-adds on every OnShow; this flag makes AddManagedFrame early-out. Pull it out now via its own container ref.
    tracker.ignoreFramePositionManager = true
    local rc = tracker.layoutParent
    if rc and rc.RemoveManagedFrame then rc:RemoveManagedFrame(tracker) end
end

-- Remove the quest modules (no POI buttons → no cache write → no map taint) and reparent the scenario/UIWidget-only container into the top of our box for its native cards + flyouts.
function Plugin:ApplyBlizzardSuppression()
    local tracker = ObjectiveTrackerFrame
    if not tracker or not tracker.RemoveModule then return end
    if InCombatLockdown() then
        Orbit.CombatManager:QueueUpdate(function() self:ApplyBlizzardSuppression() end)
        return
    end
    for _, name in ipairs(BLIZZARD_REMOVE) do
        local m = _G[name]
        if m then
            tracker:RemoveModule(m)
            -- RemoveModule stops future renders but leaves the already-drawn blocks visible; KeepAliveHidden hides the module and re-hides it if Blizzard shows it again.
            OrbitEngine.NativeFrame:KeepAliveHidden(m)
        end
    end
    self:DetachNativeSystems(tracker)
    -- Anchor only on the actual reparent; LayoutContent owns positioning thereafter. Re-anchoring here on every (repeated) call fights LayoutContent's section position → flicker on load.
    if tracker:GetParent() ~= self.scrollChild then
        tracker:SetParent(self.scrollChild)
        tracker:ClearAllPoints()
        tracker:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, 0)
        tracker:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, 0)
    end
    tracker:SetFrameLevel(self.scrollChild:GetFrameLevel())
    tracker:SetClampedToScreen(false)
    tracker:EnableMouse(false)
    if tracker.NineSlice then tracker.NineSlice:Hide() end
    if tracker.Header then OrbitEngine.NativeFrame:KeepAliveHidden(tracker.Header) end
    -- Hide the scenario module's own ornate header; we render our own collapsible section header for it in LayoutContent.
    if ScenarioObjectiveTracker and ScenarioObjectiveTracker.Header then
        OrbitEngine.NativeFrame:KeepAliveHidden(ScenarioObjectiveTracker.Header)
    end
    self:HookScenarioFlyouts()
    if not self._scenarioHooked then
        self._scenarioHooked = true
        -- Ignore size changes we cause ourselves while anchoring the block (avoids a resize->refresh->re-anchor rebuild loop).
        tracker:HookScript("OnSizeChanged", function()
            if self._inLayout then return end
            self:ScheduleRefresh()
        end)
        -- Reclaim the block if Blizzard reparented it out on show, and keep it hidden while our scenario section is collapsed.
        hooksecurefunc(tracker, "Show", function()
            if self:RehomeScenarioBlock() then self:ScheduleRefresh() end
            if self:IsSectionCollapsed("__SCENARIO__") then tracker:Hide() end
        end)
    end
end

-- Blizzard's managed/edit-mode anchor pass reclaims ObjectiveTrackerFrame (resets ignoreFramePositionManager and reparents it to the right-managed container). Re-assert our ownership; returns true if it had drifted out of our scroll child.
function Plugin:RehomeScenarioBlock()
    local tracker = ObjectiveTrackerFrame
    if not tracker or InCombatLockdown() then return false end
    tracker.ignoreFramePositionManager = true
    local rc = tracker.layoutParent
    if rc and rc.RemoveManagedFrame then rc:RemoveManagedFrame(tracker) end
    if tracker:GetParent() ~= self.scrollChild then
        tracker:SetParent(self.scrollChild)
        -- Blizzard cleared/replaced its points relative to the managed container; re-anchor to us so it isn't stranded until the relayout runs.
        tracker:ClearAllPoints()
        tracker:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, 0)
        tracker:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, 0)
        return true
    end
    return false
end

-- The Delve "Challenges" (TieredEntranceTraits) and MawBuffs flyouts open horizontally beyond our box; our vertical scroll clip would cut them off. Drop the clip while one is open, restore on close.
function Plugin:HookScenarioFlyouts()
    local so = ScenarioObjectiveTracker
    if not so then return end
    local containers = { so.TieredEntranceTraitsBlock, so.MawBuffsBlock }
    for _, block in ipairs(containers) do
        local list = block and block.Container and block.Container.List
        if list and not list._orbitClipHooked then
            list._orbitClipHooked = true
            list:HookScript("OnShow", function()
                self._flyoutOpen = true
                if self.scrollFrame then self.scrollFrame:SetClipsChildren(false) end
            end)
            list:HookScript("OnHide", function()
                self._flyoutOpen = false
                self:UpdateScrollClip()
            end)
        end
    end
end

-- Our scenario section-header title — read from Blizzard's (now hidden) module header text.
function Plugin:ScenarioTitle()
    local h = ScenarioObjectiveTracker and ScenarioObjectiveTracker.Header
    local t = h and h.Text and h.Text:GetText()
    if t and t ~= "" then return t end
    return TRACKER_HEADER_SCENARIO or "Scenario"
end

-- Height the reparented scenario/event block occupies, reserved below our scenario header.
function Plugin:ScenarioContentHeight()
    local c = ObjectiveTrackerFrame
    if not c or not c.modules or c:GetParent() ~= self.scrollChild then return 0 end
    -- When the StatusWidget orb owns the M+ block, exclude it (M+ IS the only scenario during a key) so we don't reserve a duplicate section; other scenario/widget modules still count.
    local dropMPlus = self._mplusOwned and ScenarioObjectiveTracker or nil
    local sum, count = 0, 0
    for _, m in ipairs(c.modules) do
        if m ~= dropMPlus then
            local h = m.GetContentsHeight and m:GetContentsHeight() or 0
            if h > 0 then sum = sum + h; count = count + 1 end
        end
    end
    if count == 0 then return 0 end
    return (c.topModulePadding or 0) + sum + (c.moduleSpacing or 0) * (count - 1) + (c.bottomModulePadding or 0)
end

-- [ REFRESH ]----------------------------------------------------------------------------------------
-- A plain boolean write — never taints. The clean OnUpdate poller (OnLoad) drains it into FullLayout out of combat.
function Plugin:ScheduleRefresh()
    self._refreshPending = true
end

-- Our frames are all UIParent-descended (insecure), so relayout is combat-safe — progress/collapse update live.
function Plugin:FullLayout()
    if not self.frame or not self.scrollChild then return end

    Orbit.ObjectivesSkin:RefreshCache(self)
    local model = Orbit.ObjectivesModel:BuildModel(self)

    -- scrollChild is widened for flyout overflow, so derive the content width from the frame and inset content back by padX.
    local inset = self:GetContentInset()
    local width = self.frame:GetWidth() - 2 * inset
    if width <= 1 then
        width = (self:GetSetting(SYSTEM_ID, "Width") or C.DEFAULT_WIDTH) - 2 * inset
    end
    local padX = C.HORIZONTAL_OVERFLOW + inset
    local scenarioH = self:ScenarioContentHeight()

    -- Skip the expensive layout half when nothing that affects the render changed (the common case at 10Hz — quest events fire constantly with identical results). Settings/theme changes set _forceRelayout.
    local fp = self:ComputeFingerprint(model, width, scenarioH)
    if fp == self._lastFingerprint and not self._forceRelayout then return end
    self._lastFingerprint, self._forceRelayout = fp, false

    -- Drop the stale item overlay OOC (its row is about to be recycled); re-hover re-attaches. Can't detach in combat (protected).
    if not InCombatLockdown() then self:DetachItemButton() end

    local totalH = self:LayoutContent(model, width, scenarioH, padX)
    self.scrollChild:SetHeight(math.max(totalH, C.MIN_TRACKER_HEIGHT))
    self._sectionCount = #model.sections
    self._hasContent = #model.sections > 0 or scenarioH > 0
    self:UpdateScrollClip()
    self:RefreshEmptyState()
    self:ApplyContainerHeight()
end

-- [ SCROLL ]-----------------------------------------------------------------------------------------
-- Derive the range from scroll-child vs viewport, NOT GetVerticalScrollRange (it balloons); clip only on real overflow.
function Plugin:UpdateScrollClip()
    local sf = self.scrollFrame
    if not sf or not self.scrollChild then return end
    -- A scenario flyout is open past our edge — never clip while it shows (HookScenarioFlyouts restores on close).
    if self._flyoutOpen then sf:SetClipsChildren(false); return end
    local range = math.max(0, self.scrollChild:GetHeight() - sf:GetHeight())
    sf:SetClipsChildren(range > 0)
    if sf:GetVerticalScroll() > range then sf:SetVerticalScroll(range) end
end

function Plugin:OnScroll(delta)
    local sf = self.scrollFrame
    if not sf or not self.scrollChild then return end
    local range = math.max(0, self.scrollChild:GetHeight() - sf:GetHeight())
    if range <= 0 then return end
    local v = sf:GetVerticalScroll() - delta * C.SCROLL_SPEED
    if v < 0 then v = 0 elseif v > range then v = range end
    sf:SetVerticalScroll(v)
end

-- [ COLLAPSE STATE ]---------------------------------------------------------------------------------
-- Persistent per-section collapse (AccountSettings) plus a transient, never-saved combat overlay for AutoCollapseCombat.
function Plugin:GetSavedCollapse(key)
    local state = Orbit.db and Orbit.db.AccountSettings and Orbit.db.AccountSettings.ObjectivesCollapseState
    return (state and state[key]) or false
end

function Plugin:IsSectionCollapsed(key)
    if self._combatCollapsed and self._combatCollapsed[key] then return true end
    return self:GetSavedCollapse(key)
end

function Plugin:SetSectionCollapsed(key, collapsed)
    if not Orbit.db or not Orbit.db.AccountSettings then return end
    local state = Orbit.db.AccountSettings.ObjectivesCollapseState
    if not state then state = {}; Orbit.db.AccountSettings.ObjectivesCollapseState = state end
    state[key] = collapsed or nil
end

-- [ APPLY SETTINGS ]---------------------------------------------------------------------------------
function Plugin:ApplySettings()
    local frame = self.frame
    if not frame then return end
    if InCombatLockdown() then
        Orbit.CombatManager:QueueUpdate(function() self:ApplySettings() end)
        return
    end

    -- Re-assert (idempotent): Blizzard's ObjectiveTrackerManager assigns its modules at PLAYER_ENTERING_WORLD, which can land after our first suppress.
    self:SuppressBlizzardTracker()

    local scale = self:GetSetting(SYSTEM_ID, "Scale") or C.DEFAULT_SCALE
    local width = self:GetSetting(SYSTEM_ID, "Width") or C.DEFAULT_WIDTH
    local height = self:GetSetting(SYSTEM_ID, "Height") or C.DEFAULT_HEIGHT
    frame:SetScale(scale / 100)
    frame:Show()

    -- Border first so borderPixelSize is available for the inset calc.
    self:ApplyBorder()
    self:ApplyBackdrop()

    local s = frame:GetEffectiveScale()
    local snappedHeight = OrbitEngine.Pixel:Snap(height, s)
    if IsWidthSynced(frame) then
        frame:SetHeight(snappedHeight)
    else
        frame:SetSize(OrbitEngine.Pixel:Snap(width, s), snappedHeight)
    end

    -- Viewport insets vertically (scroll clips top/bottom) but extends past the frame left/right so scenario/delve flyouts opening outward aren't clipped; FullLayout insets the content back via padX.
    local inset = self:GetContentInset()
    local ov = C.HORIZONTAL_OVERFLOW
    self.scrollFrame:ClearAllPoints()
    self.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -ov, -inset)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", ov, inset)

    Orbit.ObjectivesSkin:RefreshCache(self)

    if Orbit.OOCFadeMixin then Orbit.OOCFadeMixin:ApplyOOCFade(frame, self, SYSTEM_ID) end
    self:UpdateZoneFilters()

    self:ApplyContainerHeight()
    -- Settings/theme/geometry changed — force the next layout past the content-fingerprint early-out.
    self._forceRelayout = true
    self:ScheduleRefresh()
end

-- [ CONTAINER HEIGHT ]-------------------------------------------------------------------------------
-- Uncapped box height that wraps the rendered content with symmetric top/bottom inset.
function Plugin:DesiredContentHeight()
    local heightSetting = self:GetSetting(SYSTEM_ID, "Height") or C.DEFAULT_HEIGHT
    local content = (self.scrollChild and self.scrollChild:GetHeight()) or 0
    if content <= 0 then return heightSetting end
    return content + 2 * self:GetContentInset()
end

-- Box content-fits, capped at the Height setting; the ScrollFrame scrolls anything beyond. Edit Mode = full Height (grabbable).
function Plugin:ResolveContainerHeight()
    local heightSetting = self:GetSetting(SYSTEM_ID, "Height") or C.DEFAULT_HEIGHT
    if Orbit:IsEditMode() then return heightSetting end
    return math.min(heightSetting, self:DesiredContentHeight())
end

-- A stale saved position can restore a centered anchor; re-pin to the forced TOP point so SetHeight holds the top.
function Plugin:HoldTopAnchor()
    local frame = self.frame
    local forced = frame.orbitForceAnchorPoint
    if not forced or frame.orbitIsDragging then return end
    local point, relTo = frame:GetPoint(1)
    if point == forced or (relTo and relTo ~= UIParent) then return end
    local p, x, y = OrbitEngine.FrameSnap:NormalizePosition(frame)
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p, x, y)
    end
end

function Plugin:ApplyContainerHeight()
    local frame = self.frame
    if not frame then return end
    self:HoldTopAnchor()
    frame:SetHeight(OrbitEngine.Pixel:Snap(self:ResolveContainerHeight(), frame:GetEffectiveScale()))
end

-- Edit Mode toggle: reclaim the scenario block (Blizzard's exit anchor pass reparents it out of our frame), resize the box, and let the poll re-position it. Never a full ApplySettings — that visibly re-renders the block.
function Plugin:OnEditModeToggle()
    self:RehomeScenarioBlock()
    -- Re-anchor the (possibly reclaimed) block THIS frame, not via the 0.1s poll, so it never renders at Blizzard's native slot. EditMode.Exit is a clean OOC stack, so a direct FullLayout is safe here. _forceRelayout bypasses the fingerprint early-out; FullLayout also re-runs height + empty-state.
    self._forceRelayout = true
    self._refreshPending = false
    self:FullLayout()
end

-- Mount/dismount, pet battle, and vehicle toggles must NOT run the base PluginMixin path (a full ApplySettings that re-renders the reparented Blizzard tracker block — flicker). Alpha is owned by OOCFade; hard-hide for those cases, otherwise just re-assert fade.
function Plugin:UpdateVisibility()
    local frame = self.frame
    if not frame then return end
    if not Orbit:IsPluginEnabled(self.name) then frame:Hide(); return end
    local mountedHidden = Orbit.VisibilityEngine and Orbit.VisibilityEngine:IsFrameMountedHidden(self.name, frame.systemIndex or SYSTEM_ID)
    if (C_PetBattles and C_PetBattles.IsInBattle()) or (UnitHasVehicleUI and UnitHasVehicleUI("player")) or mountedHidden then
        frame:SetAlpha(0)
        return
    end
    frame:Show()
    if Orbit.OOCFadeMixin then
        Orbit.OOCFadeMixin:ApplyOOCFade(frame, self, SYSTEM_ID)
    else
        frame:SetAlpha((self:GetSetting(SYSTEM_ID, "Opacity") or C.OPACITY_DEFAULT) / 100)
    end
end

-- [ BORDER ]-----------------------------------------------------------------------------------------
function Plugin:ApplyBorder()
    local frame = self.frame
    local showBorder = self:GetSetting(SYSTEM_ID, "ShowBorder")
    -- Nothing tracked → never render a border, regardless of caller (ApplySettings re-applies unconditionally).
    if showBorder == false or self:IsTrackerEmpty() then
        if Orbit.Skin.ClearNineSliceBorder then Orbit.Skin:ClearNineSliceBorder(frame) end
        if frame._borderFrame then frame._borderFrame:Hide() end
        if frame._edgeBorderOverlay then frame._edgeBorderOverlay:Hide() end
        return
    end
    Orbit.Skin:SkinBorder(frame, frame, Orbit:GetTheme("BorderSize") or 1)
end

function Plugin:GetContentInset()
    local showBorder = self:GetSetting(SYSTEM_ID, "ShowBorder")
    local borderInset = 0
    if showBorder ~= false then
        borderInset = OrbitEngine.Pixel:BorderInset(self.frame, 1)
    end
    return borderInset + C.CONTENT_PADDING
end

-- [ BACKDROP ]---------------------------------------------------------------------------------------
function Plugin:ApplyBackdrop()
    local frame = self.frame
    local opacity = (self:GetSetting(SYSTEM_ID, "BackgroundOpacity") or C.BG_OPACITY_DEFAULT) / 100
    if not frame._backdrop then
        frame._backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._backdrop:SetAllPoints(frame)
    end
    -- Nothing tracked → never render the backdrop, regardless of caller.
    if opacity > 0 and not self:IsTrackerEmpty() then
        local bgColor = Orbit.Skin:GetBackgroundColor()
        frame._backdrop:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, opacity)
        frame._backdrop:Show()
    else
        frame._backdrop:Hide()
    end
end

-- [ EMPTY STATE ]------------------------------------------------------------------------------------
function Plugin:IsTrackerEmpty()
    if Orbit:IsEditMode() then return false end
    return not self._hasContent
end

function Plugin:ApplyEmptyVisibility(empty)
    local frame = self.frame
    if not frame then return end
    if empty then
        if frame._backdrop then frame._backdrop:Hide() end
        if frame._borderFrame then frame._borderFrame:Hide() end
        if frame._edgeBorderOverlay then frame._edgeBorderOverlay:Hide() end
    else
        self:ApplyBorder()
        self:ApplyBackdrop()
    end
end

function Plugin:RefreshEmptyState()
    local empty = self:IsTrackerEmpty()
    if empty == self._isEmpty then return end
    self._isEmpty = empty
    self:ApplyEmptyVisibility(empty)
end

-- [ BLIZZARD HIDER ]---------------------------------------------------------------------------------
-- Runs only when the plugin is DISABLED but the user toggled the Blizzard tracker hidden in the VE; when enabled we park it in OnLoad instead.
Orbit:RegisterBlizzardHider("Objectives", function()
    if ObjectiveTrackerFrame then OrbitEngine.NativeFrame:SecureHide(ObjectiveTrackerFrame) end
end)
