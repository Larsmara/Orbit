-- [ OBJECTIVES INTERACTIONS ]------------------------------------------------------------------------
-- Row hover/click + one shared secure quest-item overlay; protected ops are OOC-only, frozen in combat.
---@type Orbit
local Orbit = Orbit
local C = Orbit.ObjectivesConstants
local Skin = Orbit.ObjectivesSkin

local Plugin = Orbit:GetPlugin("Objectives")

-- [ SECURE QUEST-ITEM OVERLAY ]----------------------------------------------------------------------
-- One invisible SecureActionButton (type=item) parented to UIParent and anchored (never reparented) over the hovered row's item hit-frame, OOC only. Anchoring — not parenting — keeps rows insecure so they can relayout in combat; row.itemIcon draws the visible icon.
local itemBtn = CreateFrame("Button", "OrbitObjectivesItemButton", UIParent, "SecureActionButtonTemplate")
itemBtn:Hide()
itemBtn:SetSize(C.ITEM_BUTTON_SIZE, C.ITEM_BUTTON_SIZE)
itemBtn:SetFrameStrata("HIGH")
itemBtn:RegisterForClicks("LeftButtonUp")
itemBtn:SetAttribute("type", "item")

function Plugin:AttachItemButton(row, entry)
    if InCombatLockdown() then return end
    if not (entry and entry.itemLink and row.itemHit) then itemBtn:Hide(); return end
    itemBtn:ClearAllPoints()
    itemBtn:SetAllPoints(row.itemHit)
    -- SecureCmdItemParse resolves "item:ID" most reliably; fall back to the raw link.
    local id = entry.itemLink:match("item:(%d+)")
    itemBtn:SetAttribute("item", id and ("item:" .. id) or entry.itemLink)
    itemBtn:Show()
end

function Plugin:DetachItemButton()
    if InCombatLockdown() then return end
    itemBtn:Hide()
end

-- [ ROW HOVER ]--------------------------------------------------------------------------------------
function Plugin:OnRowEnter(row)
    local entry = row.entry
    if not entry then return end
    if row.title then Skin:ApplyTitleColor(row.title, entry, true) end

    if entry.questID or (entry.objectives and #entry.objectives > 0) then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.title or "", 1, 0.82, 0, nil, true)
        for _, obj in ipairs(entry.objectives or {}) do
            if obj.finished then
                GameTooltip:AddLine(obj.text, 0.5, 1.0, 0.5, true)
            else
                GameTooltip:AddLine(obj.text, 0.8, 0.8, 0.8, true)
            end
        end
        if entry.timeLeft then GameTooltip:AddLine(entry.timeLeft, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
        row._tooltip = true
    end

    if not InCombatLockdown() then
        if entry.itemLink then self:AttachItemButton(row, entry) else self:DetachItemButton() end
    end
end

function Plugin:OnRowLeave(row)
    local entry = row.entry
    if entry and row.title then Skin:ApplyTitleColor(row.title, entry, false) end
    if row._tooltip then GameTooltip:Hide(); row._tooltip = false end
end

-- Icon hover adds a type-coloured glow (signals click-to-focus) on top of the row's normal hover behaviour.
function Plugin:OnIconEnter(row)
    local entry = row.entry
    if entry and entry.questID and row.iconGlow then
        local col = Skin:GetPOIColor(entry)
        row.iconGlow:SetVertexColor(col.r, col.g, col.b)
        row.iconGlow:Show()
    end
    self:OnRowEnter(row)
end

function Plugin:OnIconLeave(row)
    if row.iconGlow then row.iconGlow:Hide() end
    self:OnRowLeave(row)
end

-- [ DISMISS ]----------------------------------------------------------------------------------------
-- Untrack an entry regardless of category. Every API here is AllowedWhenUntainted (combat-safe).
function Plugin:DismissEntry(entry)
    if entry.questID then
        -- A quest may be in either watch list and its classification need not match, so clear both (each no-ops if not applicable).
        C_QuestLog.RemoveQuestWatch(entry.questID)
        C_QuestLog.RemoveWorldQuestWatch(entry.questID)
    elseif entry.achievementID then
        C_ContentTracking.StopTracking(Enum.ContentTrackingType.Achievement, entry.achievementID, Enum.ContentTrackingStopType.Manual)
    elseif entry.recipeID then
        C_TradeSkillUI.SetRecipeTracked(entry.recipeID, false, entry.isRecraft)
    elseif entry.perkID then
        C_PerksActivities.RemoveTrackedPerksActivity(entry.perkID)
    end
end

-- [ CLICK ]------------------------------------------------------------------------------------------
-- Title/body: shift-left dismisses, plain-left opens the quest in the map/log (combat-gated). Right does nothing.
function Plugin:OnRowClick(row, button)
    local entry = row.entry
    if not entry or button ~= "LeftButton" then return end
    if IsShiftKeyDown() then
        self:DismissEntry(entry)
    elseif entry.questID and not InCombatLockdown() and QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(entry.questID)
    end
end

-- Icon: plain-left focuses (super-tracks) the quest, shift-left dismisses.
function Plugin:OnIconClick(row)
    local entry = row.entry
    if not entry then return end
    if IsShiftKeyDown() then
        self:DismissEntry(entry)
    elseif entry.questID then
        if C_SuperTrack.GetSuperTrackedQuestID() == entry.questID then
            C_SuperTrack.SetSuperTrackedQuestID(0)
        else
            C_SuperTrack.SetSuperTrackedQuestID(entry.questID)
        end
    end
end

-- [ SECTION COLLAPSE ]-------------------------------------------------------------------------------
function Plugin:ToggleSectionCollapse(key)
    if not key then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    -- Flip the DISPLAYED state (includes any transient combat override), then clear the override so a single click always matches the chevron mid-combat and never corrupts the saved preference.
    local collapsed = not self:IsSectionCollapsed(key)
    if self._combatCollapsed then self._combatCollapsed[key] = nil end
    self:SetSectionCollapsed(key, collapsed)
    self:ScheduleRefresh()
end
