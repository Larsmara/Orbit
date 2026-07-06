-- [ OBJECTIVES EVENTS ]------------------------------------------------------------------------------
-- Every content event only flips the ScheduleRefresh boolean (never taints); the clean poller drains it.
---@type Orbit
local Orbit = Orbit
local C = Orbit.ObjectivesConstants
local SYSTEM_ID = C.SYSTEM_ID
local Model = Orbit.ObjectivesModel

local Plugin = Orbit:GetPlugin("Objectives")

-- Any of these means the tracked content may have changed — a boolean flip is all we do (never taints).
local REFRESH_EVENTS = {
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_ACCEPTED",
    "UNIT_QUEST_LOG_CHANGED",
    "SUPER_TRACKING_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "TASK_PROGRESS_UPDATE",
    "AREA_POIS_UPDATED",
    "QUEST_POI_UPDATE",
    "TRACKED_ACHIEVEMENT_UPDATE",
    "TRACKED_ACHIEVEMENT_LIST_CHANGED",
    "CRITERIA_UPDATE",
    "ACHIEVEMENT_EARNED",
    "CONTENT_TRACKING_UPDATE",
    "SCENARIO_UPDATE",
    "SCENARIO_CRITERIA_UPDATE",
    "SCENARIO_POI_UPDATE",
    "CRITERIA_COMPLETE",
    "PERKS_ACTIVITIES_UPDATED",
    "TRADE_SKILL_LIST_UPDATE",
}

-- Force every section (including the scenario) collapsed while in combat when AutoCollapseCombat is on (transient, never saved).
function Plugin:SetCombatCollapse(entering)
    if entering then
        if not self:GetSetting(SYSTEM_ID, "AutoCollapseCombat") then return end
        self._combatCollapsed = self._combatCollapsed or {}
        for _, sec in ipairs(C.SECTIONS) do self._combatCollapsed[sec.key] = true end
        self._combatCollapsed["__SCENARIO__"] = true
        self:ScheduleRefresh()
    elseif self._combatCollapsed then
        self._combatCollapsed = nil
        self:ScheduleRefresh()
    end
end

function Plugin:InstallEventHandlers()
    if self._eventsInstalled then return end
    self._eventsInstalled = true

    local frame = CreateFrame("Frame")
    for _, event in ipairs(REFRESH_EVENTS) do frame:RegisterEvent(event) end
    frame:RegisterEvent("QUEST_TURNED_IN")
    frame:RegisterEvent("QUEST_REMOVED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
            if arg1 then Model:OnQuestGone(arg1) end
            self:ScheduleRefresh()
        elseif event == "PLAYER_REGEN_DISABLED" then
            self:SetCombatCollapse(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:SetCombatCollapse(false)
            self:DetachItemButton()
        else
            self:ScheduleRefresh()
        end
    end)
end
