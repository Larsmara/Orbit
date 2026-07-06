-- [ OBJECTIVES RENDER ]------------------------------------------------------------------------------
-- Pooled rows + section headers built from our own regions; LayoutContent stacks them and returns the content height.
---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine

local C = Orbit.ObjectivesConstants
local SYSTEM_ID = C.SYSTEM_ID
local Skin = Orbit.ObjectivesSkin
local cache = Skin.cache
local Pixel = OrbitEngine.Pixel

local Plugin = Orbit:GetPlugin("Objectives")

local OBJ_TEXT_INDENT = C.OBJECTIVE_INDENT + C.CHECK_SIZE + C.CHECK_TEXT_GAP
local BAR_INTERP = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

-- Signature of an entry's progress, used to flash on advance. Dim lines (WQ timer, scenario stage) are excluded so ticking clocks don't flash.
local function BuildSignature(entry)
    local parts = {}
    for _, obj in ipairs(entry.objectives or {}) do
        if not obj.dim then
            parts[#parts + 1] = obj.text or ""
            parts[#parts + 1] = obj.finished and "1" or "0"
        end
    end
    if entry.progress then parts[#parts + 1] = "p" .. entry.progress.cur end
    parts[#parts + 1] = entry.isComplete and "c" or ""
    return table.concat(parts, "|")
end

-- [ POOLS ]------------------------------------------------------------------------------------------
function Plugin:EnsurePools()
    if self._rowPool then return end
    self._rowPool = CreateFramePool("Frame", self.scrollChild)
    self._headerPool = CreateFramePool("Button", self.scrollChild)
end

-- [ ROW WIDGETS ]------------------------------------------------------------------------------------
local function EnsureRowWidgets(row)
    if row._built then return end
    row._built = true
    row.lines = {}

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(C.POI_SIZE, C.POI_SIZE)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    row.iconGlow = row:CreateTexture(nil, "OVERLAY")
    row.iconGlow:SetTexture("Interface\\AddOns\\Orbit\\Core\\assets\\Radial\\orbit-radial-glow")
    row.iconGlow:SetBlendMode("ADD")
    row.iconGlow:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.iconGlow:SetSize(C.POI_SIZE + C.ICON_GLOW_PAD, C.POI_SIZE + C.ICON_GLOW_PAD)
    row.iconGlow:Hide()

    -- The icon is its own click target (focus/super-track); enter/leave forward to the row (tooltip/scroll) plus a type-coloured glow.
    row.iconHit = CreateFrame("Button", nil, row)
    row.iconHit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.iconHit:SetSize(C.POI_SIZE, C.POI_SIZE)
    row.iconHit:RegisterForClicks("LeftButtonUp")
    row.iconHit:SetScript("OnClick", function() Plugin:OnIconClick(row) end)
    row.iconHit:SetScript("OnEnter", function() Plugin:OnIconEnter(row) end)
    row.iconHit:SetScript("OnLeave", function() Plugin:OnIconLeave(row) end)
    row.iconHit:EnableMouseWheel(true)
    row.iconHit:SetScript("OnMouseWheel", function(_, delta) Plugin:OnScroll(delta) end)

    row.title = row:CreateFontString(nil, "ARTWORK")
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(true)

    row.itemHit = CreateFrame("Frame", nil, row)
    row.itemHit:SetSize(C.ITEM_BUTTON_SIZE, C.ITEM_BUTTON_SIZE)
    row.itemHit:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.itemIcon = row.itemHit:CreateTexture(nil, "ARTWORK")
    row.itemIcon:SetAllPoints()
    row.itemIcon:SetTexCoord(C.ICON_CROP_MIN, C.ICON_CROP_MAX, C.ICON_CROP_MIN, C.ICON_CROP_MAX)

    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) Plugin:OnScroll(delta) end)
    row:SetScript("OnEnter", function(r) Plugin:OnRowEnter(r) end)
    row:SetScript("OnLeave", function(r) Plugin:OnRowLeave(r) end)
    row:SetScript("OnMouseUp", function(r, button) Plugin:OnRowClick(r, button) end)

    row.fadeIn = row:CreateAnimationGroup()
    local fa = row.fadeIn:CreateAnimation("Alpha")
    fa:SetFromAlpha(0); fa:SetToAlpha(1); fa:SetDuration(C.FADE_IN_DURATION); fa:SetSmoothing("OUT")
    row.fadeIn:SetToFinalAlpha(true)

    row.flash = row:CreateTexture(nil, "OVERLAY")
    row.flash:SetAllPoints(row)
    row.flash:SetColorTexture(1, 1, 1, 1)
    row.flash:SetBlendMode("ADD")
    row.flash:SetAlpha(0)
    row.flashAnim = row.flash:CreateAnimationGroup()
    local up = row.flashAnim:CreateAnimation("Alpha")
    up:SetFromAlpha(0); up:SetToAlpha(C.FLASH_PEAK_ALPHA); up:SetDuration(C.FLASH_UP_DURATION); up:SetOrder(1)
    local down = row.flashAnim:CreateAnimation("Alpha")
    down:SetFromAlpha(C.FLASH_PEAK_ALPHA); down:SetToAlpha(0); down:SetDuration(C.FLASH_DOWN_DURATION); down:SetOrder(2)
end

local function EnsureLine(row, i)
    local line = row.lines[i]
    if line then return line end
    line = {}
    line.fs = row:CreateFontString(nil, "ARTWORK")
    line.fs:SetJustifyH("LEFT")
    line.fs:SetWordWrap(true)
    line.check = row:CreateTexture(nil, "OVERLAY")
    line.check:SetSize(C.CHECK_SIZE, C.CHECK_SIZE)
    line.check:SetAtlas("checkmark-minimal")
    line.check:SetDesaturated(true)
    line.check:SetVertexColor(0, 1, 0)
    row.lines[i] = line
    return line
end

local function EnsureBar(row)
    if row.bar then return row.bar end
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetHeight(C.PROGRESS_BAR_HEIGHT)
    bar:SetMinMaxValues(0, 1)
    bar.Label = bar:CreateFontString(nil, "OVERLAY")
    bar.Label:SetPoint("LEFT", bar, "LEFT", C.PROGRESS_BAR_LABEL_PADDING, 0)
    bar.Label:SetPoint("RIGHT", bar, "RIGHT", -C.PROGRESS_BAR_LABEL_PADDING, 0)
    bar.Label:SetJustifyH("CENTER")
    row.bar = bar
    return bar
end

-- [ POPULATE ROW ]-----------------------------------------------------------------------------------
local function PopulateRow(row, entry, width, isNew, lastCur, flash, scale)
    EnsureRowWidgets(row)
    row.entry = entry
    local iconSz = Pixel:Snap(C.POI_SIZE, scale)
    row.icon:SetSize(iconSz, iconSz)
    row.iconHit:SetSize(iconSz, iconSz)

    if isNew then
        row:SetAlpha(0)
        row.fadeIn:Stop(); row.fadeIn:Play()
    else
        row.fadeIn:Stop(); row:SetAlpha(1)
    end
    if flash then
        row.flashAnim:Stop(); row.flash:SetAlpha(0); row.flashAnim:Play()
    end

    -- Icon: quest kinds resolve a POI atlas; providers may supply an explicit texture (achievement) or atlas.
    if entry.iconTexture then
        row.icon:SetTexCoord(C.ICON_CROP_MIN, C.ICON_CROP_MAX, C.ICON_CROP_MIN, C.ICON_CROP_MAX)
        row.icon:SetTexture(entry.iconTexture)
    elseif entry.iconAtlas then
        row.icon:SetAtlas(entry.iconAtlas)
    else
        row.icon:SetAtlas(Skin:GetPOIAtlas(entry))
    end

    local itemReserve = entry.itemTexture and (C.ITEM_BUTTON_SIZE + C.ITEM_RESERVE_GAP) or 0
    Skin:ApplyFont(row.title, cache.titleSize)
    row.title:SetWidth(math.max(1, width - C.OBJECTIVE_INDENT - itemReserve))
    row.title:SetText(entry.title or "")
    Skin:ApplyTitleColor(row.title, entry, false)
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", C.OBJECTIVE_INDENT, 0)

    if entry.itemTexture then
        local itemSz = Pixel:Snap(C.ITEM_BUTTON_SIZE, scale)
        row.itemHit:SetSize(itemSz, itemSz)
        row.itemIcon:SetTexture(entry.itemTexture)
        row.itemHit:Show()
    else
        row.itemHit:Hide()
    end

    local y = math.max(row.title:GetStringHeight(), C.POI_SIZE)

    local oc = cache.objectiveColor
    local cc = cache.completedColor
    local sp = cache.spacing
    local objs = entry.objectives or {}
    local checkSz = Pixel:Snap(C.CHECK_SIZE, scale)
    for i, obj in ipairs(objs) do
        y = y + (i == 1 and sp.titleObj or sp.objLine)
        local line = EnsureLine(row, i)
        Skin:ApplyFont(line.fs, cache.objectiveSize)
        line.fs:SetWidth(math.max(1, width - OBJ_TEXT_INDENT))
        line.fs:SetText(obj.text or "")
        if obj.finished then
            line.fs:SetTextColor(cc.r, cc.g, cc.b)
        elseif obj.dim then
            line.fs:SetTextColor(oc.r, oc.g, oc.b, 0.6)
        else
            line.fs:SetTextColor(oc.r, oc.g, oc.b)
        end
        line.check:SetSize(checkSz, checkSz)
        local snapY = Pixel:Snap(y, scale)
        line.fs:ClearAllPoints()
        line.fs:SetPoint("TOPLEFT", row, "TOPLEFT", OBJ_TEXT_INDENT, -snapY)
        line.fs:Show()
        line.check:ClearAllPoints()
        line.check:SetPoint("TOPLEFT", row, "TOPLEFT", C.OBJECTIVE_INDENT, -snapY)
        line.check:SetShown(obj.finished == true)
        y = y + line.fs:GetStringHeight()
    end
    for i = #objs + 1, #row.lines do
        row.lines[i].fs:Hide()
        row.lines[i].check:Hide()
    end

    if entry.progress then
        y = y + sp.titleObj
        local bar = EnsureBar(row)
        -- Re-skin only when the bar theme changed (or the bar is new), not every pass.
        if bar._styleEpoch ~= Skin._barStyleEpoch then
            Skin:ApplyBarStyle(bar)
            bar._styleEpoch = Skin._barStyleEpoch
        end
        bar:SetMinMaxValues(0, entry.progress.max)
        -- Seed from this quest's last value (pooled bars carry a stranger's value) then interpolate to the new one.
        if lastCur then bar:SetValue(lastCur) end
        if BAR_INTERP then bar:SetValue(entry.progress.cur, BAR_INTERP) else bar:SetValue(entry.progress.cur) end
        Skin:ApplyFont(bar.Label, C.PROGRESS_BAR_FONT_SIZE)
        bar.Label:SetText(Skin:FormatProgress(entry.progress.cur, entry.progress.max) or "")
        local barH = Pixel:Snap(C.PROGRESS_BAR_HEIGHT, scale)
        bar:SetHeight(barH)
        bar:ClearAllPoints()
        local leftPad = C.PROGRESS_BAR_SIDE_PADDING + C.PROGRESS_BAR_LEFT_EXTRA
        bar:SetPoint("TOPLEFT", row, "TOPLEFT", leftPad, -Pixel:Snap(y, scale))
        bar:SetWidth(Pixel:Snap(math.max(1, width - leftPad - C.PROGRESS_BAR_SIDE_PADDING), scale))
        bar:Show()
        y = y + barH
    elseif row.bar then
        row.bar:Hide()
    end

    row:SetSize(width, y)
    return y
end

-- [ HEADER WIDGETS ]---------------------------------------------------------------------------------
local function EnsureHeaderWidgets(header)
    if header._built then return end
    header._built = true

    header.chevron = header:CreateFontString(nil, "ARTWORK")
    header.chevron:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.title = header:CreateFontString(nil, "ARTWORK")
    header.title:SetPoint("LEFT", header, "LEFT", C.HEADER_TITLE_INDENT, 0)
    header.title:SetJustifyH("LEFT")
    header.counter = header:CreateFontString(nil, "ARTWORK")
    header.counter:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header.sep = header:CreateTexture(nil, "ARTWORK")

    header.highlight = header:CreateTexture(nil, "BACKGROUND")
    header.highlight:SetAllPoints(header)
    header.highlight:SetColorTexture(1, 1, 1, C.HEADER_HIGHLIGHT_ALPHA)
    header.highlight:Hide()

    header:RegisterForClicks("LeftButtonUp")
    header:SetScript("OnClick", function(h) Plugin:ToggleSectionCollapse(h.sectionKey) end)
    header:EnableMouseWheel(true)
    header:SetScript("OnMouseWheel", function(_, delta) Plugin:OnScroll(delta) end)
    header:SetScript("OnEnter", function(h) h.highlight:Show() end)
    header:SetScript("OnLeave", function(h) h.highlight:Hide() end)
end

local function PopulateHeader(header, section, width, showCount, sepOn)
    EnsureHeaderWidgets(header)
    header.sectionKey = section.key
    header.highlight:Hide()

    Skin:ApplyFont(header.title, cache.headerSize)
    header.title:SetText(section.title or "")
    local hc = cache.headerColor
    header.title:SetTextColor(hc.r, hc.g, hc.b)

    Skin:ApplyFont(header.chevron, C.CHEVRON_FONT_SIZE)
    header.chevron:SetText(section.collapsed and "+" or "-")
    local cv = C.CHEVRON_COLOR
    header.chevron:SetTextColor(cv.r, cv.g, cv.b)

    if showCount then
        Skin:ApplyFont(header.counter, cache.objectiveSize)
        header.counter:SetText(tostring(section.count))
        local qc = C.QUEST_COUNT_COLOR
        header.counter:SetTextColor(qc.r, qc.g, qc.b)
        header.counter:Show()
    else
        header.counter:Hide()
    end

    local hH = math.max(cache.headerSize + 2 * C.HEADER_VPADDING, C.HEADER_MIN_HEIGHT)
    hH = OrbitEngine.Pixel:Snap(hH, header:GetEffectiveScale())
    header:SetSize(width, hH)
    Skin:ApplyHeaderSeparator(header, header.sep, sepOn, cache.headerColor, cache.headerIsClass)
    return hH
end

-- [ LAYOUT ]-----------------------------------------------------------------------------------------
-- A COMPLETE content fingerprint over every render input, so FullLayout can skip the layout half when nothing visible changed. Must fold every field the render reads (deliberately more inclusive than BuildSignature, which is only a flash heuristic) or the render goes stale.
function Plugin:ComputeFingerprint(model, width, scenarioH)
    local p = self._fpParts
    if p then wipe(p) else p = {}; self._fpParts = p end
    local n = 0
    n = n + 1; p[n] = Skin._fontEpoch
    n = n + 1; p[n] = Skin._barStyleEpoch
    n = n + 1; p[n] = cache.titleSize
    n = n + 1; p[n] = cache.objectiveSize
    n = n + 1; p[n] = cache.headerSize
    n = n + 1; p[n] = cache.showCount and 1 or 0
    n = n + 1; p[n] = cache.sepOn and 1 or 0
    n = n + 1; p[n] = math.floor((width or 0) + 0.5)
    n = n + 1; p[n] = math.floor((scenarioH or 0) + 0.5)
    if scenarioH > 0 then
        n = n + 1; p[n] = self:ScenarioTitle()
        n = n + 1; p[n] = self:IsSectionCollapsed("__SCENARIO__") and "C" or "O"
        -- Fold the block's pull-up shift too — its Header height can shift independently of scenarioH.
        local sh = ScenarioObjectiveTracker and ScenarioObjectiveTracker.Header
        n = n + 1; p[n] = (ObjectiveTrackerFrame and ObjectiveTrackerFrame.topModulePadding or 0) + (sh and sh:GetHeight() or 0)
    end
    for _, section in ipairs(model.sections) do
        n = n + 1; p[n] = section.key
        n = n + 1; p[n] = section.collapsed and "C" or "O"
        n = n + 1; p[n] = section.count
        if not section.collapsed then
            for _, entry in ipairs(section.entries) do
                n = n + 1; p[n] = entry.key or "?"
                n = n + 1; p[n] = (entry.isComplete and 1 or 0) + (entry.isSuperTracked and 2 or 0) + (entry.isCampaign and 4 or 0)
                n = n + 1; p[n] = entry.classification or 0
                n = n + 1; p[n] = entry.tagID or 0
                n = n + 1; p[n] = entry.title or ""
                n = n + 1; p[n] = entry.iconTexture or entry.iconAtlas or ""
                n = n + 1; p[n] = entry.itemTexture or ""
                local objs = entry.objectives
                if objs then
                    for _, obj in ipairs(objs) do
                        n = n + 1; p[n] = obj.text or ""
                        n = n + 1; p[n] = (obj.finished and 1 or 0) + (obj.dim and 2 or 0)
                    end
                end
                local pg = entry.progress
                if pg then n = n + 1; p[n] = pg.cur; n = n + 1; p[n] = pg.max end
            end
        end
    end
    return table.concat(p, "\1", 1, n)
end

function Plugin:LayoutContent(model, width, scenarioH, padX)
    padX = padX or 0
    self:EnsurePools()
    self._rowPool:ReleaseAll()
    self._headerPool:ReleaseAll()

    -- Light animation diff: fade in keys not seen last pass, flash keys whose progress signature changed. First pass never animates (avoids a login-time mass fade).
    local prevKeys, prevProgress, prevSig = self._prevKeys, self._lastProgress, self._lastSig
    local firstPass = prevKeys == nil
    local newKeys, newProgress, newSig = {}, {}, {}

    local showCount = cache.showCount
    local sepOn = cache.sepOn

    local sp = cache.spacing
    local y = 0
    local bottomIsBar = false
    local scale = self.scrollChild:GetEffectiveScale()

    -- Our own collapsible section header for Blizzard's reparented scenario/event block. The block is pulled up under the header (shift = Blizzard's own hidden module header + top padding) so the first card starts right below it — no gap.
    local block = ObjectiveTrackerFrame
    local scenarioShown = scenarioH > 0 and block ~= nil
    if scenarioShown then
        local collapsed = self:IsSectionCollapsed("__SCENARIO__")
        local header = self._headerPool:Acquire()
        local desc = self._scenarioDesc
        if not desc then desc = { key = "__SCENARIO__" }; self._scenarioDesc = desc end
        desc.title, desc.collapsed = self:ScenarioTitle(), collapsed
        local hH = PopulateHeader(header, desc, width, false, sepOn)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", padX, -Pixel:Snap(y, scale))
        header:Show()
        y = y + hH
        if collapsed then
            block:Hide()
        else
            y = y + sp.sectionHeader
            local sh = ScenarioObjectiveTracker and ScenarioObjectiveTracker.Header
            local shift = (block.topModulePadding or 0) + (sh and sh:GetHeight() or 0)
            -- Guard our own resize from re-arming a refresh via the block's OnSizeChanged hook.
            self._inLayout = true
            block:ClearAllPoints()
            local blockY = Pixel:Snap(shift - y, scale)
            block:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", padX, blockY)
            block:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", -padX, blockY)
            block:Show()
            self._inLayout = false
            y = y + math.max(0, scenarioH - shift)
        end
    end

    for si, section in ipairs(model.sections) do
        if si > 1 or scenarioShown then y = y + sp.sectionTop end
        local header = self._headerPool:Acquire()
        local hH = PopulateHeader(header, section, width, showCount, sepOn)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", padX, -Pixel:Snap(y, scale))
        header:Show()
        y = y + hH
        bottomIsBar = false
        if not section.collapsed then
            for ei, entry in ipairs(section.entries) do
                y = y + (ei == 1 and sp.sectionHeader or sp.row)
                local key = entry.key
                local sig = BuildSignature(entry)
                local isNew = not firstPass and key and not prevKeys[key]
                local lastCur = key and prevProgress and prevProgress[key]
                local flash = not firstPass and not isNew and key and prevSig and prevSig[key] and prevSig[key] ~= sig
                if key then
                    newKeys[key] = true
                    newSig[key] = sig
                    if entry.progress then newProgress[key] = entry.progress.cur end
                end
                local row = self._rowPool:Acquire()
                local rH = PopulateRow(row, entry, width, isNew, lastCur, flash, scale)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", padX, -Pixel:Snap(y, scale))
                row:Show()
                y = y + rH
                bottomIsBar = entry.progress ~= nil
            end
        end
    end

    self._prevKeys, self._lastProgress, self._lastSig = newKeys, newProgress, newSig
    return y + (bottomIsBar and C.PROGRESS_BAR_BOTTOM_PAD or 0)
end
