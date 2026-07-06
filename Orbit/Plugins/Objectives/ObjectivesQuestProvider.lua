-- [ OBJECTIVES QUEST PROVIDER ]----------------------------------------------------------------------
-- Quest-family entries (quests, campaign, world quests, bonus) from the watch lists + current-map tasks.
---@type Orbit
local Orbit = Orbit
local C = Orbit.ObjectivesConstants
local Model = Orbit.ObjectivesModel

local CAT = C.CATEGORY
local WorldQuest = Enum.QuestClassification.WorldQuest
local BonusObjective = Enum.QuestClassification.BonusObjective

-- Compact "1h 20m" / "8m" / "45s" for a world-quest time-left, rendered as a trailing objective line.
local function FormatTimeLeft(seconds)
    if seconds >= 3600 then
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    end
    return string.format("%ds", math.floor(seconds))
end

-- Build one normalized entry from a quest ID. Returns nil when its title isn't available yet (data still streaming).
local function BuildEntry(questID, ctx, forceWorldQuest)
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if not title or title == "" then return nil end

    local isWorldQuest = forceWorldQuest or C_QuestLog.IsWorldQuest(questID)
    local classification = C_QuestInfoSystem.GetQuestClassification(questID)
    local isCampaign = C_CampaignInfo.IsCampaignQuest(questID)
    local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
    local tagID = tagInfo and tagInfo.tagID

    local isComplete = C_QuestLog.ReadyForTurnIn(questID) or C_QuestLog.IsComplete(questID)
    local category
    if isComplete then
        category = CAT.COMPLETED
    elseif isWorldQuest or classification == WorldQuest then
        category = CAT.WORLDQUEST
    elseif classification == BonusObjective then
        category = CAT.BONUS
    elseif isCampaign then
        category = CAT.CAMPAIGN
    else
        category = CAT.QUEST
    end

    local objs = Model:GetObjectives(questID, isWorldQuest)
    local lines, progress = {}, nil
    for _, o in ipairs(objs) do
        if o.type == "progressbar" then
            -- Guard the streaming percent: it can be nil right after zone-in before data arrives.
            local pct = GetQuestProgressBarPercent(questID)
            if pct then progress = { cur = pct, max = 100 } end
        elseif o.text and o.text ~= "" then
            lines[#lines + 1] = { text = o.text, finished = o.finished }
        end
    end

    local timeLeft
    if isWorldQuest then
        local secs = C_TaskQuest.GetQuestTimeLeftSeconds(questID)
        if secs and secs > 0 then timeLeft = FormatTimeLeft(secs) end
    end

    local link, texture
    local logIdx = C_QuestLog.GetLogIndexForQuestID(questID)
    if logIdx then
        link, texture = GetQuestLogSpecialItemInfo(logIdx)
    end

    return {
        key = "quest:" .. questID,
        questID = questID,
        category = category,
        title = title,
        isComplete = isComplete,
        isSuperTracked = questID == ctx.superID,
        isCampaign = isCampaign,
        classification = classification,
        tagID = tagID,
        objectives = lines,
        progress = progress,
        timeLeft = timeLeft,
        itemLink = link,
        itemTexture = texture,
    }
end

Model:RegisterProvider(function(ctx)
    local entries, seen = {}, {}

    local function add(questID, forceWQ)
        if not questID or seen[questID] then return end
        seen[questID] = true
        local entry = BuildEntry(questID, ctx, forceWQ)
        if entry then entries[#entries + 1] = entry end
    end

    for i = 1, C_QuestLog.GetNumQuestWatches() do
        add(C_QuestLog.GetQuestIDForQuestWatchIndex(i))
    end
    for i = 1, C_QuestLog.GetNumWorldQuestWatches() do
        add(C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i), true)
    end

    -- Active bonus objectives / tasks the player is engaged in on the current map (Blizzard shows these without a watch).
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        local tasks = C_TaskQuest.GetQuestsOnMap(mapID)
        if tasks then
            for _, poi in ipairs(tasks) do
                local qid = poi.questID
                if qid and not seen[qid] and not C_QuestLog.IsWorldQuest(qid) and C_QuestLog.IsOnQuest(qid) then
                    add(qid)
                end
            end
        end
    end

    return entries
end)
