-- [ OBJECTIVES ZONE FILTER ]-------------------------------------------------------------------------
-- Auto-tracks quests in the player's current zone and untracks quests from other zones by managing the watch list — the tracker only shows watched quests, and there is no taint-safe way to override Blizzard's ShouldDisplayQuest. Quest data is non-secret and the watch APIs are AllowedWhenUntainted, so this is taint-light and combat-safe. Manual pins, the super-tracked quest, complete/turn-in-ready quests, and zoneless/account quests always stay visible.
---@type Orbit
local Orbit = Orbit

local C = Orbit.ObjectivesConstants
local SYSTEM_ID = C.SYSTEM_ID

local Plugin = Orbit:GetPlugin("Objectives")

local C_QuestLog = C_QuestLog
local C_Map = C_Map
local C_SuperTrack = C_SuperTrack
local C_TaskQuest = C_TaskQuest
local GetQuestUiMapID = GetQuestUiMapID
local ipairs, pairs, next, wipe = ipairs, pairs, next, wipe
local WATCH_AUTOMATIC = Enum.QuestWatchType and Enum.QuestWatchType.Automatic
local WATCH_MANUAL = Enum.QuestWatchType and Enum.QuestWatchType.Manual
local CONTINENT = Enum.UIMapType and Enum.UIMapType.Continent
local ZONE = Enum.UIMapType and Enum.UIMapType.Zone
local MAX_WQ_WATCHES_MANUAL = Constants.QuestWatchConsts.MAX_WORLD_QUEST_WATCHES_MANUAL

-- Zone change can fire ZONE_CHANGED (sub-area) without ZONE_CHANGED_NEW_AREA, so listen to both; quest events re-assert after accept/turn-in/abandon and after any watch change (autoQuestWatch re-adds out-of-zone quests, which we then drop). QUEST_LOG_UPDATE catches world-quest POI data streaming in after a zone-in/reload (GetQuestsOnMap is empty until then).
local ZONE_FILTER_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "QUEST_ACCEPTED",
    "QUEST_TURNED_IN",
    "QUEST_REMOVED",
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_LOG_UPDATE",
}

-- The player's current map plus its ancestors up to (and including) stopType: Continent for the quest filter (continent-wide quests show across the continent), Zone for world quests (tight — only the current zone, so an adjacent/child area like Zul'Aman never bleeds into Eversong Woods). A quest matches when its GetQuestUiMapID is in this set; sibling zones are always excluded.
local function BuildZoneMapSet(stopType)
    local set = {}
    local mapID = C_Map.GetBestMapForUnit("player")
    while mapID and mapID ~= 0 do
        set[mapID] = true
        local info = C_Map.GetMapInfo(mapID)
        if not info then break end
        if stopType and info.mapType and info.mapType <= stopType then break end
        mapID = info.parentMapID
    end
    return set
end

-- Zone-level map ID for the player's position — walks past micro-dungeons/orphan maps to the enclosing zone so entering a building doesn't count as leaving. Scopes the untrack-suppression set.
local function GetZoneKey()
    local mapID = C_Map.GetBestMapForUnit("player")
    while mapID and mapID ~= 0 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then return mapID end
        if info.mapType and info.mapType <= ZONE then return mapID end
        mapID = info.parentMapID
    end
    return mapID
end

-- [ EVALUATE ]---------------------------------------------------------------------------------------
-- Walk the quest log once: track current-zone quests, untrack other-zone quests. `AddQuestWatch` can't set the watch type (only the World-Quest variant takes one), so quests we add read back as Manual and are indistinguishable from real pins by type alone — we instead flag every quest we manage in `_zoneAutoTracked`, and only ever untrack those (plus engine-Automatic watches). Genuine manual pins, the super-tracked quest, complete/turn-in-ready quests, and zoneless/account quests are never removed.
function Plugin:EvaluateZoneFilter()
    if not self._zoneFilterEnabled then return end
    if self._zoneFilterUpdating then return end

    local zoneMaps = BuildZoneMapSet(CONTINENT)
    if not next(zoneMaps) then return end

    local tracked = self._zoneAutoTracked
    local removed = self._zoneAutoRemoved
    local suppressed = self._zoneAutoSuppressed
    local seenPrev = self._zoneSeenWatched
    local seenNow = {}
    local superID = C_SuperTrack.GetSuperTrackedQuestID()

    -- Suppression is scoped to the current zone: leaving and returning re-tracks what the user untracked here. seenPrev (last pass's in-zone watched quests) resets with it, so a fresh zone auto-tracks from scratch.
    local zoneKey = GetZoneKey()
    if self._zoneFilterState.suppressKey ~= zoneKey then
        wipe(suppressed)
        seenPrev = nil
        self._zoneFilterState.suppressKey = zoneKey
    end

    -- Guard our own AddQuestWatch/RemoveQuestWatch — each fires QUEST_WATCH_LIST_CHANGED, which would otherwise re-enter.
    self._zoneFilterUpdating = true

    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and not info.isTask and not info.isBounty then
            local questID = info.questID
            if questID then
                local questMap = GetQuestUiMapID(questID) or 0
                local inZone = questMap ~= 0 and zoneMaps[questMap]
                local watchType = C_QuestLog.GetQuestWatchType(questID)
                local watched = watchType ~= nil

                if inZone then
                    if watched then
                        if watchType == WATCH_AUTOMATIC then tracked[questID] = true end
                        suppressed[questID] = nil
                        seenNow[questID] = true
                    elseif suppressed[questID] then
                        -- user untracked it here; stay off until they leave and return to the zone
                    elseif seenPrev and seenPrev[questID] then
                        -- watched last pass, now unwatched, and we never untrack in-zone — so the user did. Suppress the re-add (covers both auto-tracked quests and the user's own manual pins).
                        suppressed[questID] = true
                        tracked[questID] = nil
                    elseif C_QuestLog.AddQuestWatch(questID) then
                        tracked[questID] = true
                        seenNow[questID] = true
                    end
                    removed[questID] = nil
                elseif watched and (tracked[questID] or watchType == WATCH_AUTOMATIC)
                    and questMap ~= 0 and questID ~= superID
                    and not C_QuestLog.IsComplete(questID) and not C_QuestLog.ReadyForTurnIn(questID) then
                    C_QuestLog.RemoveQuestWatch(questID)
                    tracked[questID] = nil
                    removed[questID] = true
                end
            end
        end
    end

    -- The sets persist across sessions, so drop quests that left the log (turned in / abandoned) or they grow forever.
    for questID in pairs(tracked) do
        if not C_QuestLog.GetLogIndexForQuestID(questID) then tracked[questID] = nil end
    end
    for questID in pairs(removed) do
        if not C_QuestLog.GetLogIndexForQuestID(questID) then removed[questID] = nil end
    end
    for questID in pairs(suppressed) do
        if not C_QuestLog.GetLogIndexForQuestID(questID) then suppressed[questID] = nil end
    end

    self._zoneSeenWatched = seenNow
    self._zoneFilterUpdating = false
end

-- [ WORLD QUESTS ]-----------------------------------------------------------------------------------
-- GetNumWorldQuestWatches spans both watch types; the client's eviction cap applies to Manual watches only.
local function CountManualWorldQuestWatches()
    local count = 0
    for i = 1, C_QuestLog.GetNumWorldQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
        if questID and C_QuestLog.GetQuestWatchType(questID) == WATCH_MANUAL then count = count + 1 end
    end
    return count
end

-- Auto-track in-area world quests as Manual watches (Automatic is engine-capped), flagging ours in _zoneAutoTrackedWQ; user pins (watched, never flagged) are left alone, and adds stop at the 5-slot Manual cap so a 6th never evicts a pin. A WQ the player untracks in-area is suppressed per-zone — detected by a Manual watch going away between passes (Automatic proximity expiry is ignored) — and not re-added until they leave/return or re-track it.
function Plugin:EvaluateWorldQuestZone()
    if not self._zoneWQEnabled then return end
    if self._zoneFilterUpdating then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end

    -- GetQuestsOnMap can return world quests from adjacent/child areas (e.g. Zul'Aman bleeding into Eversong Woods), so confirm each WQ's own zone is the current zone. Use C_TaskQuest.GetQuestZoneID — GetQuestUiMapID returns 0 for world quests, which rejected every one. Zone-level set, never the continent.
    local zoneMaps = BuildZoneMapSet(ZONE)
    local trackedWQ = self._zoneAutoTrackedWQ
    local suppressedWQ = self._zoneAutoSuppressedWQ

    -- Dismiss-suppression scoped to the current zone: a WQ the player untracks stays off until they leave and return (or manually re-track it). seenPrevWQ (in-area Manual watches last pass) resets with it.
    local zoneKey = GetZoneKey()
    if zoneKey and zoneKey ~= 0 and self._zoneFilterState.suppressKeyWQ ~= zoneKey then
        wipe(suppressedWQ)
        self._zoneSeenWatchedWQ = nil
        self._zoneFilterState.suppressKeyWQ = zoneKey
    end

    self._zoneFilterUpdating = true

    local inArea = {}
    local tasks = C_TaskQuest.GetQuestsOnMap(mapID)
    if tasks then
        for _, poi in ipairs(tasks) do
            local questID = poi.questID
            if questID and C_QuestLog.IsWorldQuest(questID) and zoneMaps[C_TaskQuest.GetQuestZoneID(questID) or 0] then
                inArea[questID] = true
            end
        end
    end

    -- Only reconcile when we actually have task data: GetQuestsOnMap returns nil transiently (post-login/zone-in before POIs stream), and treating that as "area is empty" would un-watch every tracked WQ. QUEST_LOG_UPDATE re-drives once data arrives.
    if tasks then
        for questID in pairs(trackedWQ) do
            if not inArea[questID] then
                C_QuestLog.RemoveWorldQuestWatch(questID)
                trackedWQ[questID] = nil
            end
        end

        local seenPrevWQ = self._zoneSeenWatchedWQ
        local seenNowWQ = {}
        local manualCount = CountManualWorldQuestWatches()
        for questID in pairs(inArea) do
            local watchType = C_QuestLog.GetQuestWatchType(questID)
            if watchType == WATCH_MANUAL then
                -- Manually watched (our add or the player's own pin) — record it so a later un-watch reads as a dismiss.
                suppressedWQ[questID] = nil
                seenNowWQ[questID] = true
            elseif watchType ~= nil then
                -- Blizzard's Automatic proximity watch manages its own show/hide; leave it be (and don't treat its expiry as a dismiss).
            elseif suppressedWQ[questID] then
                -- dismissed here; stay off until zone change or manual re-track
            elseif seenPrevWQ and seenPrevWQ[questID] then
                -- Manually watched last pass, now unwatched, and we never untrack in-area — so the player dismissed it.
                suppressedWQ[questID] = true
                trackedWQ[questID] = nil
            elseif manualCount < MAX_WQ_WATCHES_MANUAL and C_QuestLog.AddWorldQuestWatch(questID, WATCH_MANUAL) then
                trackedWQ[questID] = true
                seenNowWQ[questID] = true
                manualCount = manualCount + 1
            end
        end
        self._zoneSeenWatchedWQ = seenNowWQ
    end

    self._zoneFilterUpdating = false
end

-- Coalesce a burst of events into one next-frame pass. The pass clears _zoneFilterUpdating up front (a fresh frame is never nested in a pass), so an error mid-pass can't strand the guard true and permanently block the filter — it self-heals on the next event. Self-generated watch events just schedule one more idempotent pass, which converges.
function Plugin:ScheduleZoneFilterUpdate()
    if self._zoneFilterPending then return end
    self._zoneFilterPending = true
    RunNextFrame(function()
        self._zoneFilterPending = false
        self._zoneFilterUpdating = false
        self:EvaluateZoneFilter()
        self:EvaluateWorldQuestZone()
    end)
end

-- Re-watch the quests the filter removed (that still exist and aren't already watched) — the sets persist, so this restores across /reload too — then wipe both so turning the filter off forgets everything it managed.
function Plugin:RestoreZoneFilter()
    local removed = self._zoneAutoRemoved
    self._zoneFilterUpdating = true
    for questID in pairs(removed) do
        if C_QuestLog.GetLogIndexForQuestID(questID) and not C_QuestLog.GetQuestWatchType(questID) then
            C_QuestLog.AddQuestWatch(questID)
        end
    end
    wipe(removed)
    wipe(self._zoneAutoTracked)
    wipe(self._zoneAutoSuppressed)
    self._zoneFilterState.suppressKey = nil
    self._zoneSeenWatched = nil
    self._zoneFilterUpdating = false
end

-- Untrack the world quests the tracker added — the set persists, so prior sessions' adds are cleaned up too (the WQ tracker is additive; turning it off removes what it added).
function Plugin:RemoveAutoTrackedWorldQuests()
    self._zoneFilterUpdating = true
    for questID in pairs(self._zoneAutoTrackedWQ) do
        C_QuestLog.RemoveWorldQuestWatch(questID)
    end
    wipe(self._zoneAutoTrackedWQ)
    wipe(self._zoneAutoSuppressedWQ)
    self._zoneFilterState.suppressKeyWQ = nil
    self._zoneSeenWatchedWQ = nil
    self._zoneFilterUpdating = false
end

-- [ ENABLE / DISABLE ]-------------------------------------------------------------------------------
-- The current-zone quest filter and the area world-quest tracker are independent toggles that share one event frame and the current-map math. Idempotent: ApplySettings calls this every pass; each feature only acts on its own enabled-state transition (filter restores removed quests on off; WQ tracker untracks its adds on off).
function Plugin:UpdateZoneFilters()
    if not self._zoneFilterFrame then
        -- The shadow sets are char-persisted (rooted in OrbitDB, mutated in place): across /reload the filter must still know which watches it removed and which Manual WQ watches are its own — those read back identically to user pins.
        local state = self:GetCharData("ZoneFilterState")
        if not state then
            state = { tracked = {}, removed = {}, trackedWQ = {}, suppressed = {}, suppressedWQ = {} }
            self:SetCharData("ZoneFilterState", state)
        end
        -- Backfill any field a state persisted by an older version predates, so the pairs() loops never hit nil.
        state.tracked = state.tracked or {}
        state.removed = state.removed or {}
        state.trackedWQ = state.trackedWQ or {}
        state.suppressed = state.suppressed or {}
        state.suppressedWQ = state.suppressedWQ or {}
        self._zoneAutoTracked = state.tracked
        self._zoneAutoRemoved = state.removed
        self._zoneAutoTrackedWQ = state.trackedWQ
        self._zoneAutoSuppressed = state.suppressed
        self._zoneAutoSuppressedWQ = state.suppressedWQ
        self._zoneFilterState = state
        self._zoneFilterFrame = CreateFrame("Frame")
        self._zoneFilterFrame:SetScript("OnEvent", function() self:ScheduleZoneFilterUpdate() end)
    end

    local filter = self:GetSetting(SYSTEM_ID, "ZoneFilter") and true or false
    local worldQuests = self:GetSetting(SYSTEM_ID, "ZoneWorldQuests") and true or false
    local filterTurnedOn = filter and not self._zoneFilterEnabled
    local wqTurnedOn = worldQuests and not self._zoneWQEnabled

    if filter ~= self._zoneFilterEnabled then
        self._zoneFilterEnabled = filter
        if not filter then self:RestoreZoneFilter() end
    end
    if worldQuests ~= self._zoneWQEnabled then
        self._zoneWQEnabled = worldQuests
        if not worldQuests then self:RemoveAutoTrackedWorldQuests() end
    end

    local frame = self._zoneFilterFrame
    if filter or worldQuests then
        for _, event in ipairs(ZONE_FILTER_EVENTS) do frame:RegisterEvent(event) end
    else
        frame:UnregisterAllEvents()
    end

    -- Route the turn-on evaluation through the scheduler (deferred one frame) so it shares the self-healing guard reset; a direct call here could strand _zoneFilterUpdating if it errored.
    if filterTurnedOn or wqTurnedOn then self:ScheduleZoneFilterUpdate() end
end
