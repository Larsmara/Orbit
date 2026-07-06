-- [ OBJECTIVES ACHIEVEMENT PROVIDER ]----------------------------------------------------------------
-- Tracked achievements + their incomplete criteria via C_ContentTracking + the achievement API.
---@type Orbit
local Orbit = Orbit
local C = Orbit.ObjectivesConstants
local Model = Orbit.ObjectivesModel

local CAT = C.CATEGORY
local MAX_CRITERIA = 8

local function TrackedAchievementIDs()
    local ids
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        ids = C_ContentTracking.GetTrackedIDs(Enum.ContentTrackingType.Achievement)
    end
    if (not ids or #ids == 0) and GetTrackedAchievements then
        ids = { GetTrackedAchievements() }
    end
    return ids
end

Model:RegisterProvider(function()
    local entries = {}
    local ids = TrackedAchievementIDs()
    if not ids then return entries end

    for _, id in ipairs(ids) do
        local _, name, _, completed, _, _, _, _, _, icon = GetAchievementInfo(id)
        if name then
            local lines = {}
            for i = 1, GetAchievementNumCriteria(id) do
                local cName, _, cDone, _, reqQty, _, _, _, qtyStr = GetAchievementCriteriaInfo(id, i)
                if cName and cName ~= "" and not cDone then
                    lines[#lines + 1] = { text = Model:FormatCriterion(cName, reqQty, qtyStr), finished = false }
                    if #lines >= MAX_CRITERIA then break end
                end
            end
            entries[#entries + 1] = {
                key = "ach:" .. id,
                achievementID = id,
                category = CAT.ACHIEVEMENT,
                title = name,
                iconTexture = icon,
                isComplete = completed and true or false,
                objectives = lines,
            }
        end
    end
    return entries
end)
