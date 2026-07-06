-- [ OBJECTIVES TRACKABLE PROVIDER ]------------------------------------------------------------------
-- Long-tail trackables (profession recipes, monthly activities); every version-conditional API is existence-guarded.
---@type Orbit
local Orbit = Orbit
local C = Orbit.ObjectivesConstants
local Model = Orbit.ObjectivesModel

local CAT = C.CATEGORY

-- [ PROFESSION RECIPES ]-----------------------------------------------------------------------------
Model:RegisterProvider(function()
    local entries = {}
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked and C_TradeSkillUI.GetRecipeSchematic) then
        return entries
    end

    local function addRecipes(isRecraft)
        local ids = C_TradeSkillUI.GetRecipesTracked(isRecraft)
        if not ids then return end
        for _, recipeID in ipairs(ids) do
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
            local name = schematic and schematic.name
            if name and name ~= "" then
                entries[#entries + 1] = {
                    key = "recipe:" .. recipeID .. (isRecraft and "r" or ""),
                    recipeID = recipeID,
                    isRecraft = isRecraft,
                    category = CAT.PROFESSION,
                    title = name,
                    objectives = {},
                }
            end
        end
    end
    addRecipes(false)
    addRecipes(true)
    return entries
end)

-- [ MONTHLY ACTIVITIES / TRADING POST ]--------------------------------------------------------------
Model:RegisterProvider(function()
    local entries = {}
    if not (C_PerksActivities and C_PerksActivities.GetTrackedPerksActivities and C_PerksActivities.GetPerksActivityInfo) then
        return entries
    end

    local tracked = C_PerksActivities.GetTrackedPerksActivities()
    local ids = tracked and tracked.trackedIDs
    if not ids then return entries end

    for _, id in ipairs(ids) do
        local info = C_PerksActivities.GetPerksActivityInfo(id)
        if info and info.activityName and info.activityName ~= "" then
            local lines = {}
            if info.description and info.description ~= "" then
                lines[1] = { text = info.description, finished = info.completed == true }
            end
            entries[#entries + 1] = {
                key = "perk:" .. id,
                perkID = id,
                category = CAT.MONTHLY,
                title = info.activityName,
                isComplete = info.completed == true,
                objectives = lines,
            }
        end
    end
    return entries
end)
