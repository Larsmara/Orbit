-- [ OBJECTIVES INTERACTIONS ]------------------------------------------------------------------------
-- Row hover/click + one shared secure quest-item overlay; protected ops are OOC-only, frozen in combat.
---@type Orbit
local Orbit = Orbit
local C = Orbit.ObjectivesConstants
local Skin = Orbit.ObjectivesSkin
local L = Orbit.L

local Plugin = Orbit:GetPlugin("Objectives")

-- Addons can't touch the OS clipboard; this read-only popup pre-selects the URL so the user can Ctrl+C. data = the URL.
StaticPopupDialogs["ORBIT_OBJECTIVES_COPY_URL"] = {
    text = L.PLU_OBJ_COPY_WOWHEAD,
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 260,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(dialog)
        local eb = dialog.EditBox or dialog.editBox
        if not eb then return end
        eb:SetText(dialog.data or "")
        eb:HighlightText()
        eb:SetFocus()
    end,
    EditBoxOnTextChanged = function(editBox)
        local url = editBox:GetParent().data
        if url and editBox:GetText() ~= url then editBox:SetText(url); editBox:HighlightText() end
    end,
    EditBoxOnEnterPressed = function(editBox) editBox:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
}

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

-- [ WAYPOINT ]---------------------------------------------------------------------------------------
-- Drop a map waypoint on the quest's next objective and navigate to it. Every API is AllowedWhenUntainted (combat-safe). Falls back to super-tracking the quest when it has no map waypoint (account/meta quests).
function Plugin:SetQuestWaypoint(entry)
    local qid = entry.questID
    if not qid then return end
    local mapID, x, y = C_QuestLog.GetNextWaypoint(qid)
    if mapID and x and y then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    else
        C_SuperTrack.SetSuperTrackedQuestID(qid)
    end
end

function Plugin:ShowWowheadLink(questID)
    if not questID then return end
    StaticPopup_Show("ORBIT_OBJECTIVES_COPY_URL", nil, nil, C.WOWHEAD_QUEST_URL:format(questID))
end

-- [ CONTEXT MENU ]-----------------------------------------------------------------------------------
-- Right-click menu built on the modern MenuUtil system, mirroring Blizzard's native quest-tracker menu and reusing its localized globals. Quest-only actions guard on questID; Stop Tracking works for every trackable via DismissEntry.
function Plugin:ShowContextMenu(row)
    local entry = row.entry
    if not entry then return end
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(entry.title or "")
        local qid = entry.questID
        if qid then
            if C_SuperTrack.GetSuperTrackedQuestID() == qid then
                root:CreateButton(STOP_SUPER_TRACK_QUEST, function() C_SuperTrack.SetSuperTrackedQuestID(0) end)
            else
                root:CreateButton(SUPER_TRACK_QUEST, function() C_SuperTrack.SetSuperTrackedQuestID(qid) end)
            end
            root:CreateButton(OBJECTIVES_SHOW_QUEST_MAP, function()
                if not InCombatLockdown() and QuestMapFrame_OpenToQuestDetails then QuestMapFrame_OpenToQuestDetails(qid) end
            end)
            if C_QuestLog.IsPushableQuest(qid) and IsInGroup() then
                root:CreateButton(SHARE_QUEST, function() QuestUtil.ShareQuest(qid) end)
            end
            root:CreateButton(L.PLU_OBJ_COPY_WOWHEAD, function() self:ShowWowheadLink(qid) end)
        end
        root:CreateButton(OBJECTIVES_STOP_TRACKING, function() self:DismissEntry(entry) end)
        if qid then
            root:CreateButton(ABANDON_QUEST_ABBREV, function()
                if not InCombatLockdown() and QuestMapQuestOptions_AbandonQuest then QuestMapQuestOptions_AbandonQuest(qid) end
            end)
        end
    end)
end

-- [ CLICK ]------------------------------------------------------------------------------------------
-- Title/body: right-click opens the context menu, shift-left dismisses, plain-left waypoints the quest's next objective.
function Plugin:OnRowClick(row, button)
    local entry = row.entry
    if not entry then return end
    if button == "RightButton" then
        self:ShowContextMenu(row)
    elseif button == "LeftButton" then
        if IsShiftKeyDown() then
            self:DismissEntry(entry)
        else
            self:SetQuestWaypoint(entry)
        end
    end
end

-- Icon: plain-left focuses (super-tracks) the quest, shift-left dismisses, right-click opens the context menu.
function Plugin:OnIconClick(row, button)
    local entry = row.entry
    if not entry then return end
    if button == "RightButton" then
        self:ShowContextMenu(row)
    elseif IsShiftKeyDown() then
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
