-- [ QOL CONTENT ]------------------------------------------------------------------------------------
-- Expandable accordion sections for Quality of Life features.
local _, Orbit = ...
local L = Orbit.L
local Layout = Orbit.Engine.Layout
local Pixel = Orbit.Engine.Pixel
local A = Layout.Advanced
local math_floor = math.floor

-- [ CONSTANTS ]--------------------------------------------------------------------------------------
local STACK_GAP = 6
local SEARCH_WIDTH = 200
local SEARCH_HEIGHT = 30
local SEARCH_RIGHT_INSET = 34
local UI_PADDING = 10
local UI_TOP_OFFSET = -8
local UI_DESC_HEIGHT = 28
local UI_ROW_HEIGHT = 32
local UI_GAP = 8
local UI_PP_BUTTON_WIDTH = 110
local UI_APPLY_BUTTON_WIDTH = 80
local UI_BUTTON_HEIGHT = 22
local UI_BOTTOM_PAD = 8
local UI_SCALE_PERCENT = 100

-- [ HELPERS ]----------------------------------------------------------------------------------------
local function FmtDecimal(v) return string.format("%.2f", v) end

local function SetAccountSetting(key, val)
    if not Orbit.db.AccountSettings then Orbit.db.AccountSettings = {} end
    Orbit.db.AccountSettings[key] = val
end

local function GetAccountSetting(key, default)
    -- Explicit nil check — `... or default` silently replaces a saved `false`, breaking unchecked-box persistence.
    local v = Orbit.db.AccountSettings[key]
    if v == nil then return default end
    return v
end

-- [ GROUPED LAYOUT ]---------------------------------------------------------------------------------
-- Group = optional header + gold divider, then full-width rows, then per-type grids (checkboxes 3-col, sliders/dropdowns 2-col) reflowed on resize.
local HOMO_PAD = 8
local HOMO_COL_GAP = 10
local HOMO_HEADER_H = 28
local HOMO_FULL_ROW_H = 32
local HOMO_FULL_GAP = 6
local HOMO_GROUP_GAP = 12
local HOMO_TOP = -6
local CHECK_COLS, CHECK_ROW_H = 3, 26
local SLIDER_COLS, SLIDER_ROW_H = 2, 46
local DROPDOWN_COLS, DROPDOWN_ROW_H = 2, 40

-- Canonical QoL section header (GameFontNormal label + gold divider) — the one header style every panel shares. Returns the y after the header.
local function AddGroupHeader(body, text, y)
    local hdr = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", body, "TOPLEFT", HOMO_PAD, y)
    hdr:SetJustifyH("LEFT")
    hdr:SetText(text)
    local divider = body:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 0.82, 0, 0.3)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", body, "TOPLEFT", HOMO_PAD, y - 18)
    divider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -HOMO_PAD, y - 18)
    return y - HOMO_HEADER_H
end

-- `full` entries are a frame or { frame, h }; `dropdowns`/`sliders` render 2-col, `checks` 3-col — each a width-reflowed grid. Async descriptions must pass explicit h.
local function BuildGrouped(body, groups)
    local grids = {}
    local yPos = HOMO_TOP

    local function addGrid(items, cols, rowH)
        if not items or #items == 0 then return end
        for _, w in ipairs(items) do Layout:AddControl(body, w) end
        grids[#grids + 1] = { items = items, gridY = yPos, cols = cols, rowH = rowH }
        yPos = yPos - math.ceil(#items / cols) * rowH
    end

    for _, group in ipairs(groups) do
        if group.header then yPos = AddGroupHeader(body, group.header, yPos) end
        for _, entry in ipairs(group.full or {}) do
            local frame = entry.frame or entry
            Layout:AddControl(body, frame)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", body, "TOPLEFT", HOMO_PAD, yPos)
            frame:SetPoint("TOPRIGHT", body, "TOPRIGHT", -HOMO_PAD, yPos)
            local h = entry.h or frame:GetHeight()
            if not h or h < 1 then h = HOMO_FULL_ROW_H end
            yPos = yPos - h - HOMO_FULL_GAP
        end
        addGrid(group.dropdowns, DROPDOWN_COLS, DROPDOWN_ROW_H)
        addGrid(group.sliders, SLIDER_COLS, SLIDER_ROW_H)
        addGrid(group.checks, CHECK_COLS, CHECK_ROW_H)
        yPos = yPos - HOMO_GROUP_GAP
    end

    -- colWidth is width-dependent; reflow on resize since the accordion body may be 0-wide at build. Dual-anchor (not SetWidth) so sliders/dropdowns lay out their label + value correctly.
    local function Reflow()
        local width = body:GetWidth()
        if width < 1 then return end
        for _, g in ipairs(grids) do
            local colWidth = (width - HOMO_PAD * 2) / g.cols
            for i, w in ipairs(g.items) do
                local col = (i - 1) % g.cols
                local left = HOMO_PAD + col * colWidth
                local y = g.gridY - math_floor((i - 1) / g.cols) * g.rowH
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", body, "TOPLEFT", left, y)
                w:SetPoint("TOPRIGHT", body, "TOPLEFT", left + colWidth - HOMO_COL_GAP, y)
            end
        end
    end
    body:SetScript("OnSizeChanged", Reflow)
    Reflow()
    return math.abs(yPos)
end

-- [ SECTION BUILDERS ]-------------------------------------------------------------------------------
-- Each builder receives the body frame and returns the computed content height.

local function BuildMoveMore(body)
    local desc = Layout:CreateDescription(body, GetAccountSetting("MoveMoreSavePositions", false) and L.PLU_MM_DESC_SAVE or L.PLU_MM_DESC_RESET, A.MUTED)

    local enableCb = Layout:CreateCheckbox(body, L.PLU_MM_ENABLE, nil, GetAccountSetting("MoveMore", false), function(checked)
        SetAccountSetting("MoveMore", checked)
        if checked then Orbit.MoveMore:Enable() else Orbit.MoveMore:Disable() end
    end, { compact = true })

    local saveCb = Layout:CreateCheckbox(body, L.PLU_MM_SAVE_POSITIONS, nil, GetAccountSetting("MoveMoreSavePositions", false), function(checked)
        SetAccountSetting("MoveMoreSavePositions", checked)
        if desc and desc.text then desc.text:SetText(checked and L.PLU_MM_DESC_SAVE or L.PLU_MM_DESC_RESET) end
    end, { compact = true })

    local resetBtn = Layout:CreateButton(body, L.PLU_MM_RESET_ALL, function()
        Orbit.MoveMore:ClearSavedPositions()
    end)

    return BuildGrouped(body, {
        { full = { { frame = desc, h = 40 } }, checks = { enableCb, saveCb } },
        { full = { { frame = resetBtn, h = 24 } } },
    })
end

local function BuildUserInterface(body)
    local desc = Layout:CreateDescription(body, L.PLU_UI_DESC, A.MUTED)
    Layout:AddControl(body, desc)
    desc:ClearAllPoints()
    desc:SetPoint("TOPLEFT", body, "TOPLEFT", UI_PADDING, UI_TOP_OFFSET)
    desc:SetPoint("TOPRIGHT", body, "TOPRIGHT", -UI_PADDING, UI_TOP_OFFSET)

    local rowY = UI_TOP_OFFSET - UI_DESC_HEIGHT
    local UIScale = Orbit.UserInterface
    local minScale, maxScale, stepScale = UIScale:ScaleRange()
    local steps = (maxScale - minScale) / stepScale
    local stagedScale = UIScale:GetScale()

    local slider, ppBtn, applyBtn
    slider = Layout:CreateSlider(body, L.PLU_UI_SCALE, minScale, maxScale, stepScale,
        function(v) return string.format("%d%%", math_floor(v * UI_SCALE_PERCENT + 0.5)) end,
        stagedScale,
        function(val) stagedScale = val end,
        { updateOnRelease = true })
    Layout:AddControl(body, slider)
    slider:ClearAllPoints()
    slider:SetPoint("TOPLEFT", body, "TOPLEFT", UI_PADDING, rowY)
    slider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -UI_PADDING - UI_PP_BUTTON_WIDTH - UI_APPLY_BUTTON_WIDTH - UI_GAP * 2, rowY)

    ppBtn = Layout:CreateButton(body, L.PLU_UI_PIXEL_PERFECT, function()
        local pp = UIScale:GetPixelPerfectScale()
        stagedScale = pp
        slider._isInitializing = true
        slider.Slider:Init(pp, minScale, maxScale, steps, {})
        slider._isInitializing = false
    end, UI_PP_BUTTON_WIDTH)
    Layout:AddControl(body, ppBtn)
    ppBtn:ClearAllPoints()
    ppBtn:SetSize(UI_PP_BUTTON_WIDTH, UI_BUTTON_HEIGHT)
    ppBtn:SetPoint("LEFT", slider, "RIGHT", UI_GAP, 0)
    ppBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.PLU_UI_PIXEL_PERFECT)
        GameTooltip:AddLine(L.PLU_UI_TT_DETECTED_F:format(UIScale:GetResolution()), 1, 1, 1)
        GameTooltip:AddLine(L.PLU_UI_TT_SCALE_F:format(Pixel:GetScale() * UI_SCALE_PERCENT), 1, 1, 1)
        GameTooltip:Show()
    end)
    ppBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    applyBtn = Layout:CreateButton(body, L.PLU_UI_APPLY, function()
        UIScale:SetScale(stagedScale)
    end, UI_APPLY_BUTTON_WIDTH)
    Layout:AddControl(body, applyBtn)
    applyBtn:ClearAllPoints()
    applyBtn:SetSize(UI_APPLY_BUTTON_WIDTH, UI_BUTTON_HEIGHT)
    applyBtn:SetPoint("LEFT", ppBtn, "RIGHT", UI_GAP, 0)

    return math.abs(rowY - UI_ROW_HEIGHT - UI_BOTTOM_PAD)
end

local function BuildMouse(body)
    local enableCb = Layout:CreateCheckbox(body, L.PLU_MOUSE_ENABLE, nil, GetAccountSetting("CustomCursor", false), function(checked)
        SetAccountSetting("CustomCursor", checked)
        if checked then Orbit.Mouse:Enable() else Orbit.Mouse:Disable() end
    end)
    local desc = Layout:CreateDescription(body, L.PLU_MOUSE_DESC, A.MUTED)
    -- RefreshSnapshot after each write — CVAR_UPDATE doesn't fire for SavedVariables, and the per-frame OnUpdate reads cached fields.
    local s1 = Layout:CreateSlider(body, L.PLU_MOUSE_SCALE, 0.1, 2.0, 0.01, FmtDecimal, GetAccountSetting("CustomCursorScale", 0.55), function(val)
        SetAccountSetting("CustomCursorScale", val)
        Orbit.Mouse:RefreshSnapshot()
    end)
    local s2 = Layout:CreateSlider(body, L.PLU_MOUSE_X_OFFSET, -5, 5, 0.1, FmtDecimal, GetAccountSetting("CustomCursorX", 2.10), function(val)
        SetAccountSetting("CustomCursorX", val)
        Orbit.Mouse:RefreshSnapshot()
    end)
    local s3 = Layout:CreateSlider(body, L.PLU_MOUSE_Y_OFFSET, -5, 5, 0.1, FmtDecimal, GetAccountSetting("CustomCursorY", 1.40), function(val)
        SetAccountSetting("CustomCursorY", val)
        Orbit.Mouse:RefreshSnapshot()
    end)
    local cursorMap = { [0] = "32px", [1] = "48px", [2] = "64px", [3] = "96px", [4] = "128px" }
    local startCursor = tonumber(C_CVar.GetCVar("cursorSizePreferred")) or 0
    if startCursor < 0 then startCursor = 0 end
    local s4 = Layout:CreateSlider(body, L.PLU_MOUSE_OS_SIZE, 0, 4, 1, function(v)
        return cursorMap[math_floor(v + 0.5)] or tostring(v)
    end, startCursor, function(val)
        C_CVar.SetCVar("cursorSizePreferred", tostring(math_floor(val + 0.5)))
    end)
    return BuildGrouped(body, {
        { full = { enableCb, { frame = desc, h = 32 } } },
        { header = L.PLU_MOUSE_ADJUST, sliders = { s1, s2, s3, s4 } },
    })
end

local function BuildTooltips(body, section, requestRelayout)
    local setEnabled

    local desc = Layout:CreateDescription(body, L.PLU_TIP_DESC, A.MUTED)
    local enableCb = Layout:CreateCheckbox(body, L.PLU_TIP_ENABLE, nil, GetAccountSetting("Tooltips", true), function(checked)
        SetAccountSetting("Tooltips", checked)
        if checked then Orbit.Tooltips:Enable() else Orbit.Tooltips:Disable() end
        setEnabled(checked)
    end)

    local yTop = HOMO_TOP
    local function placeFull(frame, h)
        Layout:AddControl(body, frame)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", body, "TOPLEFT", HOMO_PAD, yTop)
        frame:SetPoint("TOPRIGHT", body, "TOPRIGHT", -HOMO_PAD, yTop)
        yTop = yTop - h - HOMO_FULL_GAP
    end
    placeFull(desc, 32)
    placeFull(enableCb, HOMO_FULL_ROW_H)
    local topH = math.abs(yTop)

    -- Sub-options live in their own frame so the master toggle can hide them all at once.
    local options = CreateFrame("Frame", nil, body)
    options:SetPoint("TOPLEFT", body, "TOPLEFT", 0, yTop)
    options:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, yTop)

    local styleDD = Layout:CreateDropdown(options, L.PLU_TIP_STYLE, {
        { value = 1, label = L.PLU_TIP_STYLE_BLIZZARD },
        { value = 2, label = L.PLU_TIP_STYLE_ORBIT },
    }, GetAccountSetting("TooltipStyle", 2), function(value)
        SetAccountSetting("TooltipStyle", value)
        Orbit.Tooltips:ApplyStyle()
    end)

    local anchorDD = Layout:CreateDropdown(options, L.PLU_TIP_ANCHOR, {
        { value = 1, label = L.PLU_TIP_ANCHOR_DEFAULT },
        { value = 2, label = L.PLU_TIP_ANCHOR_CURSOR },
        { value = 3, label = L.PLU_TIP_ANCHOR_CURSOR_LEFT },
        { value = 4, label = L.PLU_TIP_ANCHOR_CURSOR_RIGHT },
    }, GetAccountSetting("TooltipAnchor", 4), function(value)
        SetAccountSetting("TooltipAnchor", value)
    end)

    local scaleSlider = Layout:CreateSlider(options, L.PLU_TIP_SCALE, 0.5, 1.5, 0.05, function(v)
        return string.format("%d%%", math_floor(v * UI_SCALE_PERCENT + 0.5))
    end, GetAccountSetting("TooltipScale", 1.0), function(val)
        SetAccountSetting("TooltipScale", math_floor(val * 20 + 0.5) / 20)
        Orbit.Tooltips:ApplyScale()
    end)

    local function toggle(key, label, tip, default)
        return Layout:CreateCheckbox(options, label, tip, GetAccountSetting(key, default), function(checked)
            SetAccountSetting(key, checked)
        end, { compact = true })
    end

    local optionsH = BuildGrouped(options, {
        { header = L.PLU_TIP_GRP_APPEARANCE, dropdowns = { styleDD, anchorDD }, sliders = { scaleSlider } },
        { header = L.PLU_TIP_GRP_ENHANCE, checks = {
            toggle("TooltipHideCombat",      L.PLU_TIP_HIDE_COMBAT,      L.PLU_TIP_HIDE_COMBAT_TT,      true),
            toggle("TooltipHideHealthBar",   L.PLU_TIP_HIDE_HEALTHBAR,   L.PLU_TIP_HIDE_HEALTHBAR_TT,   true),
            toggle("TooltipHideInstruction", L.PLU_TIP_HIDE_INSTRUCTION, L.PLU_TIP_HIDE_INSTRUCTION_TT, true),
            toggle("TooltipShowTarget",      L.PLU_TIP_SHOW_TARGET,      L.PLU_TIP_SHOW_TARGET_TT,      false),
            toggle("TooltipGuildRank",       L.PLU_TIP_GUILD_RANK,       L.PLU_TIP_GUILD_RANK_TT,       true),
            toggle("TooltipAllegiance",      L.PLU_TIP_ALLEGIANCE,       L.PLU_TIP_ALLEGIANCE_TT,       false),
            toggle("TooltipShowIDs",         L.PLU_TIP_SHOW_IDS,         L.PLU_TIP_SHOW_IDS_TT,         false),
        } },
    })
    options:SetHeight(optionsH)

    -- Mirror the sub-option controls into the body's control list so search still indexes them.
    local bodyList = Layout.containerControls[body]
    if bodyList then
        for _, c in ipairs(Layout.containerControls[options] or {}) do
            bodyList[#bodyList + 1] = c
        end
    end

    setEnabled = function(enabled)
        options:SetShown(enabled)
        if section then section:SetContentHeight(enabled and (topH + optionsH) or topH) end
        if requestRelayout then requestRelayout() end
    end

    local enabled = GetAccountSetting("Tooltips", true)
    options:SetShown(enabled)
    return enabled and (topH + optionsH) or topH
end

local SPOTLIGHT_BINDING = "ORBIT_SPOTLIGHT_TOGGLE"
local SPOTLIGHT_COL_X_LEFT = 10
local SPOTLIGHT_COL_X_RIGHT_FRAC = 0.5
local SPOTLIGHT_COL_GAP = 15
local SPOTLIGHT_ROW_GAP = 6
local SPOTLIGHT_HEADER_GAP = 12
local SPOTLIGHT_SECTION_GAP = 14
local SPOTLIGHT_ROW_H = 26
local SPOTLIGHT_HOTKEY_BTN_W = 140
local SPOTLIGHT_HOTKEY_BTN_H = 22
-- Bind capture matching Orbit's Welcome dialog / Blizzard keybinds: same button skin + keyboard, mouse, wheel.
local function CreateHotkeyCapture(parent, bindingName)
    local btn = CreateFrame("Button", nil, parent, "UIMenuButtonStretchTemplate")
    btn:SetSize(SPOTLIGHT_HOTKEY_BTN_W, SPOTLIGHT_HOTKEY_BTN_H)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.SelectedHighlight = btn:CreateTexture(nil, "OVERLAY")
    btn.SelectedHighlight:SetTexture("Interface\\Buttons\\UI-Silver-Button-Select")
    btn.SelectedHighlight:SetBlendMode("ADD")
    btn.SelectedHighlight:SetPoint("CENTER", 0, -3)
    btn.SelectedHighlight:SetSize(SPOTLIGHT_HOTKEY_BTN_W, SPOTLIGHT_HOTKEY_BTN_H)
    btn.SelectedHighlight:Hide()

    local function Refresh()
        local key = GetBindingKey(bindingName)
        local text = key and GetBindingText(key)
        btn:SetText(text and text ~= "" and text or GRAY_FONT_COLOR:WrapTextInColorCode(L.PLU_SPT_UNBOUND))
    end

    local function StopListening()
        btn._listening = false
        btn.SelectedHighlight:Hide()
        btn:EnableKeyboard(false)
        btn:EnableMouseWheel(false)
        btn:SetPropagateKeyboardInput(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnKeyDown", nil)
        btn:SetScript("OnMouseWheel", nil)
        Refresh()
    end

    local function Process(input)
        local key = GetConvertedKeyOrButton(input)
        if key == "ESCAPE" then StopListening(); return end
        if IsKeyPressIgnoredForBinding(key) then return end
        local existing = GetBindingKey(bindingName)
        if existing then SetBinding(existing) end
        SetBinding(CreateKeyChordStringUsingMetaKeyState(key), bindingName)
        SaveBindings(GetCurrentBindingSet())
        StopListening()
    end

    btn:SetScript("OnClick", function(self, mouseButton, isDown)
        if self._listening then
            if isDown then Process(mouseButton) end
            return
        end
        if mouseButton == "RightButton" then
            local existing = GetBindingKey(bindingName)
            if existing then SetBinding(existing); SaveBindings(GetCurrentBindingSet()) end
            Refresh()
            return
        end
        self._listening = true
        self.SelectedHighlight:Show()
        self:RegisterForClicks("AnyDown", "AnyUp")
        self:EnableMouseWheel(true)
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(false)
        self:SetScript("OnKeyDown", function(s, k) Process(k) end)
        self:SetScript("OnMouseWheel", function(s, d) Process(d > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
        self:SetText(L.PLU_SPT_PRESS_KEY)
    end)

    Refresh()
    return btn
end

local SPOTLIGHT_DESC_HEIGHT = 36

local function BuildSpotlight(body)
    local yPos = -10
    local startX = SPOTLIGHT_COL_X_LEFT

    local desc = Layout:CreateDescription(body, L.PLU_SPT_DESC, A.MUTED)
    Layout:AddControl(body, desc)
    desc:ClearAllPoints()
    desc:SetPoint("TOPLEFT", body, "TOPLEFT", startX, yPos)
    desc:SetPoint("TOPRIGHT", body, "TOPRIGHT", -startX, yPos)
    yPos = yPos - SPOTLIGHT_DESC_HEIGHT

    -- Hotkey row: static "Hotkey:" label with the capture button to its right.
    local hotkeyLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hotkeyLabel:SetText(L.PLU_SPT_HOTKEY .. ":")
    hotkeyLabel:SetPoint("TOPLEFT", body, "TOPLEFT", startX, yPos - 4)

    local hotkeyBtn = CreateHotkeyCapture(body, SPOTLIGHT_BINDING)
    hotkeyBtn:SetPoint("LEFT", hotkeyLabel, "RIGHT", 8, 0)
    yPos = yPos - SPOTLIGHT_ROW_H

    -- Fuzzy (left column) + Hide Passives (right column).
    yPos = yPos - SPOTLIGHT_SECTION_GAP
    local fuzzyCb = Layout:CreateCheckbox(body, L.PLU_SPT_FUZZY, L.PLU_SPT_FUZZY_TT, GetAccountSetting("Spotlight_Fuzzy", true), function(checked)
        SetAccountSetting("Spotlight_Fuzzy", checked)
    end, { compact = true })
    Layout:AddControl(body, fuzzyCb)
    fuzzyCb:ClearAllPoints()
    fuzzyCb:SetPoint("TOPLEFT", body, "TOPLEFT", startX, yPos)
    fuzzyCb:SetPoint("TOPRIGHT", body, "TOP", 0, yPos)

    local passiveCb = Layout:CreateCheckbox(body, L.PLU_SPT_HIDE_PASSIVES, L.PLU_SPT_HIDE_PASSIVES_TT, GetAccountSetting("Spotlight_HidePassives", true), function(checked)
        SetAccountSetting("Spotlight_HidePassives", checked)
    end, { compact = true })
    Layout:AddControl(body, passiveCb)
    passiveCb:ClearAllPoints()
    passiveCb:SetPoint("TOPLEFT", body, "TOP", 0, yPos)
    passiveCb:SetPoint("TOPRIGHT", body, "TOPRIGHT", -startX, yPos)
    yPos = yPos - SPOTLIGHT_ROW_H - SPOTLIGHT_ROW_GAP

    -- Scale (left half) + Max Results (right half) — slider template needs both anchors for label + value text.
    local scaleSlider = Layout:CreateSlider(body, L.PLU_SPT_SCALE, 0.70, 1.30, 0.05, function(v)
        return string.format("%d%%", math_floor(v * 100 + 0.5))
    end, GetAccountSetting("Spotlight_Scale", 1.0), function(val)
        SetAccountSetting("Spotlight_Scale", math_floor(val * 20 + 0.5) / 20)
    end)
    Layout:AddControl(body, scaleSlider)
    scaleSlider:ClearAllPoints()
    scaleSlider:SetPoint("TOPLEFT", body, "TOPLEFT", startX, yPos)
    scaleSlider:SetPoint("TOPRIGHT", body, "TOP", -Pixel:Snap(SPOTLIGHT_COL_GAP / 2, body:GetEffectiveScale()), yPos)

    local maxSlider = Layout:CreateSlider(body, L.PLU_SPT_MAX_RESULTS, 10, 100, 1, tostring, GetAccountSetting("Spotlight_MaxResults", 100), function(val)
        SetAccountSetting("Spotlight_MaxResults", math_floor(val + 0.5))
    end)
    Layout:AddControl(body, maxSlider)
    maxSlider:ClearAllPoints()
    maxSlider:SetPoint("TOPLEFT", body, "TOP", Pixel:Snap(SPOTLIGHT_COL_GAP / 2, body:GetEffectiveScale()), yPos)
    maxSlider:SetPoint("TOPRIGHT", body, "TOPRIGHT", -startX, yPos)
    yPos = yPos - 40 - SPOTLIGHT_ROW_GAP

    yPos = yPos - SPOTLIGHT_SECTION_GAP
    yPos = AddGroupHeader(body, L.PLU_SPT_CATEGORIES, yPos)

    -- Source checkboxes in a 3-column grid; prefixOnly kinds (help) are always on and get no toggle.
    local kinds = {}
    for _, src in ipairs(Orbit.Spotlight.Kinds) do
        if not src.prefixOnly then kinds[#kinds + 1] = src end
    end
    local sourceBoxes = {}
    for i, src in ipairs(kinds) do
        local settingKey = "Spotlight_Src_" .. src.settingKey
        local initial = GetAccountSetting(settingKey, true)
        sourceBoxes[i] = Layout:CreateCheckbox(body, L[src.labelKey], nil, initial, function(checked)
            SetAccountSetting(settingKey, checked)
            Orbit.Spotlight.Index.IndexManager:InvalidateAll()
        end, { compact = true })
        Layout:AddControl(body, sourceBoxes[i])
    end
    local SOURCE_COLS = 3
    local sourceGridY = yPos
    yPos = yPos - math.ceil(#kinds / SOURCE_COLS) * SPOTLIGHT_ROW_H

    -- 3-column reflow: no built-in third anchor, so position from the body's live width on resize.
    local function ReflowSources()
        local width = body:GetWidth()
        if width < 1 then return end
        local colWidth = (width - startX * 2) / SOURCE_COLS
        for i, cb in ipairs(sourceBoxes) do
            local col = (i - 1) % SOURCE_COLS
            local left = startX + col * colWidth
            local rowY = sourceGridY - math.floor((i - 1) / SOURCE_COLS) * SPOTLIGHT_ROW_H
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", body, "TOPLEFT", left, rowY)
            cb:SetPoint("TOPRIGHT", body, "TOPLEFT", left + colWidth - 10, rowY)
        end
    end
    body:SetScript("OnSizeChanged", ReflowSources)
    ReflowSources()

    return math.abs(yPos)
end

local AUTO_PADDING = 8
local AUTO_ROW_H = 26
local AUTO_HEADER_H = 28
local AUTO_TOP = -6
local AUTO_COLUMNS = 3
local AUTO_GROUP_GAP = 14

local AUTO_GROUPS = {
    { header = "PLU_AUTO_QUESTING", entries = {
        { "PLU_AUTO_ACCEPT",               nil,                                "AutoAcceptQuests",       false },
        { "PLU_AUTO_TURNIN",               nil,                                "AutoTurnInQuests",       false },
        { "PLU_AUTO_TURNIN_HOLD_SHIFT",    "PLU_AUTO_TURNIN_HOLD_SHIFT_TT",    "AutoTurnInHoldShift",    true  },
        { "PLU_AUTO_ACCEPT_PREVENT_MULTI", "PLU_AUTO_ACCEPT_PREVENT_MULTI_TT", "AutoAcceptPreventMulti", true  },
    } },
    { header = "PLU_NPC_HEADER", entries = {
        { "PLU_AUTO_GOSSIP",    "PLU_AUTO_GOSSIP_TT",    "AutomateGossip", false },
        { "PLU_AUTO_SELL_JUNK", "PLU_AUTO_SELL_JUNK_TT", "AutoSellJunk",   false },
        { "PLU_AUTO_REPAIR",    "PLU_AUTO_REPAIR_TT",    "AutoRepair",     false },
    } },
}

local function BuildAutomation(body)
    local layout = {}
    local yPos = AUTO_TOP
    for _, group in ipairs(AUTO_GROUPS) do
        local gridY = AddGroupHeader(body, L[group.header], yPos)
        local boxes = {}
        for i, entry in ipairs(group.entries) do
            local key = entry[3]
            local cb = Layout:CreateCheckbox(body, L[entry[1]], entry[2] and L[entry[2]] or nil, GetAccountSetting(key, entry[4]), function(checked)
                SetAccountSetting(key, checked)
            end, { compact = true })
            Layout:AddControl(body, cb)
            boxes[i] = cb
        end
        layout[#layout + 1] = { boxes = boxes, gridY = gridY }
        yPos = gridY - math.ceil(#group.entries / AUTO_COLUMNS) * AUTO_ROW_H - AUTO_GROUP_GAP
    end

    -- colWidth is width-dependent; reflow on resize since the accordion body may be 0-wide at build.
    local function Reflow()
        local width = body:GetWidth()
        if width < 1 then return end
        local colWidth = (width - AUTO_PADDING * 2) / AUTO_COLUMNS
        for _, g in ipairs(layout) do
            for i, cb in ipairs(g.boxes) do
                local col = (i - 1) % AUTO_COLUMNS
                local row = math_floor((i - 1) / AUTO_COLUMNS)
                cb:ClearAllPoints()
                cb:SetPoint("TOPLEFT", body, "TOPLEFT", AUTO_PADDING + col * colWidth, g.gridY - row * AUTO_ROW_H)
                cb:SetWidth(colWidth)
            end
        end
    end
    body:SetScript("OnSizeChanged", Reflow)
    Reflow()

    return math.abs(yPos)
end

local function BuildColors(body)
    local desc = Layout:CreateDescription(body, L.PLU_COLORS_DESC, A.MUTED)
    Layout:AddControl(body, desc)
    desc:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -8)
    desc:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -8)

    local yPos = -40 -- Fixed estimate since desc:GetHeight() is asynchronous
    local allPickers = {}

    yPos = AddGroupHeader(body, L.PLU_COLORS_CLASS, yPos)

    local classes = {
        "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", 
        "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", 
        "DRUID", "DEMONHUNTER", "EVOKER"
    }

    local startX = 10
    local limitsPerLine = 4
    local colWidth = 115
    local rowHeight = 35
    local padding = 5

    -- Build Classes Grid
    local CC = Orbit.Engine.ClassColor
    for i, classFile in ipairs(classes) do
        local colorData = CC:GetOverrides(classFile)
        local locClass = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or (classFile:sub(1,1) .. classFile:sub(2):lower())

        local picker
        picker = Layout:CreateColorPicker(body, locClass, colorData, function(c)
            CC:SetOverride(classFile, c)
            if not c then
                local res = CC:GetOverrides(classFile)
                picker:SetColorQuiet(res.r, res.g, res.b, res.a)
            end
        end, { compact = true, allowClear = true })

        local dx, dy = Layout:ComputeGridPosition(i, limitsPerLine, 0, colWidth, rowHeight, padding)
        Layout:AddControl(body, picker)
        picker:SetPoint("TOPLEFT", body, "TOPLEFT", startX + dx, yPos + dy)
        allPickers[#allPickers + 1] = { type = "class", key = classFile, picker = picker }
    end

    local _, gridH = Layout:ComputeGridContainerSize(#classes, limitsPerLine, 0, colWidth, rowHeight, padding)
    yPos = yPos - gridH - 20

    yPos = AddGroupHeader(body, L.PLU_COLORS_REACTION, yPos)

    local RC = Orbit.Engine.ReactionColor
    local reactions = { "HOSTILE", "NEUTRAL", "FRIENDLY" }
    local reactionLabels = { HOSTILE = L.PLU_COLORS_HOSTILE, NEUTRAL = L.PLU_COLORS_NEUTRAL, FRIENDLY = L.PLU_COLORS_FRIENDLY }
    for i, reaction in ipairs(reactions) do
        local colorData = RC:GetOverride(reaction)
        local picker
        picker = Layout:CreateColorPicker(body, reactionLabels[reaction], colorData, function(c)
            RC:SetOverride(reaction, c)
            if not c then
                local res = RC:GetOverride(reaction)
                picker:SetColorQuiet(res.r, res.g, res.b, res.a)
            end
        end, { compact = true, allowClear = true })

        local dx, dy = Layout:ComputeGridPosition(i, limitsPerLine, 0, colWidth, rowHeight, padding)
        Layout:AddControl(body, picker)
        picker:SetPoint("TOPLEFT", body, "TOPLEFT", startX + dx, yPos + dy)
        allPickers[#allPickers + 1] = { type = "reaction", key = reaction, picker = picker }
    end

    local _, gridH2 = Layout:ComputeGridContainerSize(#reactions, limitsPerLine, 0, colWidth, rowHeight, padding)
    yPos = yPos - gridH2 - 15

    yPos = AddGroupHeader(body, L.PLU_COLORS_REPUTATION, yPos)

    local repEntries = { "RENOWN", "PARAGON", "PARAGON_REWARD" }
    local repLabels = { RENOWN = L.PLU_COLORS_RENOWN, PARAGON = L.PLU_COLORS_PARAGON, PARAGON_REWARD = L.PLU_COLORS_PARAGON_REWARD }
    for i, key in ipairs(repEntries) do
        local colorData = RC:GetOverride(key)
        local picker
        picker = Layout:CreateColorPicker(body, repLabels[key], colorData, function(c)
            RC:SetOverride(key, c)
            if not c then
                local res = RC:GetOverride(key)
                picker:SetColorQuiet(res.r, res.g, res.b, res.a)
            end
        end, { compact = true, allowClear = true })

        local dx, dy = Layout:ComputeGridPosition(i, limitsPerLine, 0, colWidth, rowHeight, padding)
        Layout:AddControl(body, picker)
        picker:SetPoint("TOPLEFT", body, "TOPLEFT", startX + dx, yPos + dy)
        allPickers[#allPickers + 1] = { type = "reaction", key = key, picker = picker }
    end

    local _, gridH3 = Layout:ComputeGridContainerSize(#repEntries, limitsPerLine, 0, colWidth, rowHeight, padding)
    yPos = yPos - gridH3 - 15

    -- Reset to Defaults button
    local resetBtn = Layout:CreateButton(body, L.CMN_RESET_TO_DEFAULTS, function()
        local acct = Orbit.db and Orbit.db.AccountSettings
        if acct then
            for _, classFile in ipairs(classes) do acct["ClassColor_" .. classFile] = nil end
            for _, reaction in ipairs(reactions) do acct["ReactionColor_" .. reaction] = nil end
            for _, key in ipairs(repEntries) do acct["ReactionColor_" .. key] = nil end
        end
        for _, entry in ipairs(allPickers) do
            local c = entry.type == "class" and CC:GetOverrides(entry.key) or RC:GetOverride(entry.key)
            entry.picker:SetColorQuiet(c.r, c.g, c.b, c.a)
        end
        Orbit.EventBus:Fire("ORBIT_COLORS_CHANGED")
    end)
    Layout:AddControl(body, resetBtn)
    resetBtn:SetPoint("TOPLEFT", body, "TOPLEFT", startX, yPos)
    yPos = yPos - 30

    return math.abs(yPos)
end

-- [ BUILD ]------------------------------------------------------------------------------------------
function Orbit._AC.CreateQoLContent(parent)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()
    content:Hide()
    -- Title + subtitle (fixed, non-scrolling)
    local header = Layout:CreateSectionHeader(content, L.PLU_QOL_TITLE)
    header:SetPoint("TOPLEFT", A.PADDING, A.TITLE_Y)
    header:SetPoint("TOPRIGHT", -A.PADDING, A.TITLE_Y)
    local desc = Layout:CreateDescription(content, L.PLU_QOL_DESC, A.MUTED)
    desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)

    -- Search Box Container matches Orbit EditBox
    local searchContainer = CreateFrame("Frame", nil, content, "BackdropTemplate")
    searchContainer:SetSize(SEARCH_WIDTH, SEARCH_HEIGHT)
    searchContainer:SetPoint("TOPRIGHT", content, "TOPRIGHT", -A.PADDING - SEARCH_RIGHT_INSET, A.TITLE_Y + 4)
    searchContainer:SetBackdrop(Layout.ORBIT_INPUT_BACKDROP)
    searchContainer:SetBackdropColor(0, 0, 0, 0.5)
    searchContainer:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local searchBox = CreateFrame("EditBox", nil, searchContainer, "SearchBoxTemplate")
    searchBox:SetPoint("TOPLEFT", searchContainer, "TOPLEFT", 8, 0)
    searchBox:SetPoint("BOTTOMRIGHT", searchContainer, "BOTTOMRIGHT", -4, 0)
    searchBox:SetFontObject(ChatFontNormal)
    searchBox:SetAutoFocus(false)
    if searchBox.Left then searchBox.Left:Hide() end
    if searchBox.Middle then searchBox.Middle:Hide() end
    if searchBox.Right then searchBox.Right:Hide() end

    -- Scrollable area
    local scrollFrame, scrollChild = Layout:CreateScrollArea(content)
    local sectionDefs = {
        { L.PLU_QOL_SEC_UI, BuildUserInterface },
        { L.PLU_QOL_SEC_COLORS, BuildColors },
        { L.PLU_QOL_SEC_MOVEMORE, BuildMoveMore },
        { L.PLU_QOL_SEC_MOUSE, BuildMouse },
        { L.PLU_QOL_SEC_TOOLTIPS, BuildTooltips },
        { L.PLU_QOL_SEC_AUTOMATION, BuildAutomation },
        { L.PLU_SPT_SECTION_TITLE, BuildSpotlight },
    }
    -- Build accordion sections
    local sections = {}
    local LayoutSections
    for _, def in ipairs(sectionDefs) do
        local section = Layout:CreateAccordion(scrollChild, def[1])
        section.searchName = def[1]:lower()
        section:SetParent(scrollChild)
        local body = section:GetBody()
        if def[2] then
            section:SetContentHeight(def[2](body, section, function() LayoutSections() end))
            -- Index all visible text within the section for search
            local controls = Layout.containerControls and Layout.containerControls[body]
            if controls then
                local parts = { section.searchName }
                for _, c in ipairs(controls) do
                    if c.Label and c.Label.GetText then parts[#parts + 1] = (c.Label:GetText() or ""):lower() end
                    if c.text and c.text.GetText then parts[#parts + 1] = (c.text:GetText() or ""):lower() end
                    if c.Text and c.Text.GetText then parts[#parts + 1] = (c.Text:GetText() or ""):lower() end
                    -- Compact checkboxes (Automation, Spotlight) keep their label on the inner button, not the outer frame.
                    if c._cb and c._cb.text and c._cb.text.GetText then parts[#parts + 1] = (c._cb.text:GetText() or ""):lower() end
                end
                section.searchName = table.concat(parts, " ")
            end
        else
            local placeholder = Layout:CreateDescription(body, L.PLU_QOL_NO_SETTINGS, A.MUTED)
            Layout:AddControl(body, placeholder)
            section:SetContentHeight(Layout:Stack(body, 0, STACK_GAP))
        end
        table.insert(sections, section)
    end
    -- Layout + reflow
    LayoutSections = function()
        local y = 0
        for _, section in ipairs(sections) do
            if section:IsShown() then
                section:ClearAllPoints()
                section:SetPoint("TOPLEFT", 0, y)
                section:SetPoint("TOPRIGHT", 0, y)
                y = y - section:GetHeight() - A.SECTION_SPACING
            end
        end
        scrollFrame:UpdateContentHeight(math.abs(y) + 10)
    end
    for _, section in ipairs(sections) do section._onToggle = LayoutSections end
    LayoutSections()

    searchBox:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        local query = self:GetText():lower()
        local isSearching = query ~= ""

        for _, section in ipairs(sections) do
            if isSearching then
                if string.find(section.searchName, query, 1, true) then
                    section:Show()
                    section:SetExpanded(true)
                else
                    section:Hide()
                end
            else
                section:Show()
                section:SetExpanded(false)
            end
        end
        LayoutSections()
    end)
    return content
end
