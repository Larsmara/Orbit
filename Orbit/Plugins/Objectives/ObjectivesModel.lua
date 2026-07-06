-- [ OBJECTIVES MODEL ]-------------------------------------------------------------------------------
-- Runs the provider registry each layout and buckets entries into an ordered {sections} render model.
---@type Orbit
local Orbit = Orbit
local C = Orbit.ObjectivesConstants

Orbit.ObjectivesModel = { providers = {} }
local Model = Orbit.ObjectivesModel

local EMPTY = {}
local WQ_CACHE_CAP = 50

-- World quests report empty objectives once you leave their zone, so keep the last non-empty copy. Bounded FIFO (_wqOrder) so a WQ that expires without a clean removal event can't grow the cache without limit.
Model.wqObjCache = {}
Model._wqOrder = {}

-- Providers register a function(ctx) -> array of entries, each tagged with a CATEGORY.
function Model:RegisterProvider(fn)
    self.providers[#self.providers + 1] = fn
end

-- Drop a quest's cached objectives when it leaves the log (turn-in / abandon); called from Events. Also drop its FIFO slot so a recurring WQ ID can't accumulate stale duplicates in _wqOrder and evict a live entry early.
function Model:OnQuestGone(questID)
    if self.wqObjCache[questID] == nil then return end
    self.wqObjCache[questID] = nil
    local order = self._wqOrder
    for i = #order, 1, -1 do
        if order[i] == questID then table.remove(order, i); break end
    end
end

-- Shared "Name (3/10)" criterion formatting for the achievement + scenario providers.
function Model:FormatCriterion(name, total, qtyStr)
    if total and total > 1 and qtyStr and qtyStr ~= "" then
        return name .. " (" .. qtyStr .. ")"
    end
    return name
end

-- Objectives with the world-quest fallback: cache the latest non-empty read, reuse it when out-of-zone reads come back empty.
function Model:GetObjectives(questID, isWorldQuest)
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if isWorldQuest then
        if objs and #objs > 0 then
            if self.wqObjCache[questID] == nil then
                local order = self._wqOrder
                order[#order + 1] = questID
                if #order > WQ_CACHE_CAP then
                    local old = table.remove(order, 1)
                    if old ~= questID then self.wqObjCache[old] = nil end
                end
            end
            self.wqObjCache[questID] = objs
        else
            objs = self.wqObjCache[questID]
        end
    end
    return objs or EMPTY
end

function Model:BuildModel(plugin)
    local ctx = { superID = C_SuperTrack.GetSuperTrackedQuestID() }
    local byCat = {}
    for _, fn in ipairs(self.providers) do
        -- Isolate a failing provider (many version-varying Blizzard C APIs) so it can't blank the whole tracker, but log the bug to the error ring buffer rather than swallow it.
        local ok, entries = pcall(fn, ctx)
        if not ok then
            Orbit.ErrorHandler:LogError("Objectives", "Provider", entries)
        elseif entries then
            for _, e in ipairs(entries) do
                local cat = e.category
                if cat then
                    local list = byCat[cat]
                    if not list then list = {}; byCat[cat] = list end
                    list[#list + 1] = e
                end
            end
        end
    end

    local sections = {}
    for _, sec in ipairs(C.SECTIONS) do
        local list = byCat[sec.key]
        if list and #list > 0 then
            local collapsed = plugin:IsSectionCollapsed(sec.key)
            sections[#sections + 1] = {
                key = sec.key,
                title = sec.title or _G[sec.titleGlobal] or sec.titleGlobal,
                collapsed = collapsed,
                count = #list,
                entries = collapsed and EMPTY or list,
            }
        end
    end
    return { sections = sections }
end
