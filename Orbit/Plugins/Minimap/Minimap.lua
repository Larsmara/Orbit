---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine
local LSM = LibStub("LibSharedMedia-3.0")

-- [ PLUGIN REGISTRATION ]---------------------------------------------------------------------------
local SYSTEM_ID = "Orbit_Minimap"

local Plugin = Orbit:RegisterPlugin("Minimap", SYSTEM_ID, {
    liveToggle = true,
    canvasMode = true,
    defaults = {
        Scale = 100,
        Opacity = 100,
        Size = 200,
        ZoneTextSize = 12,
        ZoneTextColoring = false,
        DisabledComponents = {},
        ComponentPositions = {
            ZoneText = { anchorX = "CENTER", offsetX = 0, anchorY = "BOTTOM", offsetY = 4, justifyH = "CENTER" },
            Clock = { anchorX = "LEFT", offsetX = 4, anchorY = "BOTTOM", offsetY = 4, justifyH = "LEFT" },
            Compartment = { anchorX = "RIGHT", offsetX = 2, anchorY = "BOTTOM", offsetY = 2 },
            Calendar = { anchorX = "RIGHT", offsetX = 4, anchorY = "TOP", offsetY = 4 },
            Tracking = { anchorX = "LEFT", offsetX = 4, anchorY = "TOP", offsetY = 4 },
            Coords = { anchorX = "RIGHT", offsetX = 4, anchorY = "BOTTOM", offsetY = 4, justifyH = "RIGHT" },
        },
    },
})

-- Apply NativeBarMixin for mouseOver / scale helpers
Mixin(Plugin, Orbit.NativeBarMixin)

-- [ CONSTANTS ]-------------------------------------------------------------------------------------

local BORDER_COLOR = { r = 0, g = 0, b = 0, a = 1 }
local DEFAULT_SIZE = 200
local ZONE_TEXT_PADDING = 4
local CLOCK_UPDATE_INTERVAL = 1
local COORDS_UPDATE_INTERVAL = 0.1
local CALENDAR_BUTTON_SIZE = 20
local TRACKING_BUTTON_SIZE = 20
local CALENDAR_DAY_TEXT_OFFSET_Y = -1
local CALENDAR_TEXT_SIZE = 10
local DAY_FORMAT = "%d"

-- [ BLIZZARD FRAME REFERENCES ]---------------------------------------------------------------------

local function GetBlizzardMinimap() return Minimap end

local function GetBlizzardCluster() return MinimapCluster end

-- [ BLIZZARD ART STRIPPING ]------------------------------------------------------------------------

local function StripBlizzardArt()
    local cluster = GetBlizzardCluster()
    if not cluster then
        return
    end

    -- Hide the entire cluster frame (takes BorderTop, ZoneTextButton, Tracking, IndicatorFrame, InstanceDifficulty with it)
    OrbitEngine.NativeFrame:Hide(cluster, { unregisterEvents = false, clearScripts = false })

    -- Hide the compass frame / backdrop art that surrounds the minimap render
    if MinimapBackdrop then
        MinimapBackdrop:SetAlpha(0)
    end
    if MinimapCompassTexture then
        MinimapCompassTexture:Hide()
    end

    -- Hide the expansion landing page button (garrison/covenant button on the minimap edge)
    if ExpansionLandingPageMinimapButton then
        ExpansionLandingPageMinimapButton:Hide()
        ExpansionLandingPageMinimapButton:SetScript("OnShow", function(self) self:Hide() end)
    end

    -- Suppress Blizzard's edit mode selection on the minimap cluster
    if cluster.Selection then
        cluster.Selection:SetAlpha(0)
        cluster.Selection:EnableMouse(false)
    end
end

-- [ ZONE TEXT UPDATER ]-----------------------------------------------------------------------------

local ZONE_PVP_COLORS = {
    sanctuary = { r = 0.41, g = 0.80, b = 0.94 },
    friendly = { r = 0.10, g = 1.00, b = 0.10 },
    hostile = { r = 1.00, g = 0.10, b = 0.10 },
    contested = { r = 1.00, g = 0.70, b = 0.00 },
}

local function UpdateZoneText(fontString, coloring, overrides)
    fontString:SetText(GetMinimapZoneText())
    if coloring then
        local pvpType = GetZonePVPInfo()
        local color = ZONE_PVP_COLORS[pvpType]
        if color then
            fontString:SetTextColor(color.r, color.g, color.b, 1)
        else
            fontString:SetTextColor(1, 1, 1, 1)
        end
    elseif overrides and next(overrides) then
        OrbitEngine.OverrideUtils.ApplyTextColor(fontString, overrides)
    else
        fontString:SetTextColor(1, 1, 1, 1)
    end
end

-- [ LIFECYCLE ]-------------------------------------------------------------------------------------

function Plugin:OnLoad()
    -- Create orbit container
    self.frame = CreateFrame("Frame", "OrbitMinimapContainer", UIParent)
    self.frame:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    self.frame:SetClampedToScreen(true)
    self.frame.systemIndex = SYSTEM_ID
    self.frame.editModeName = "Minimap"

    -- Anchor options for edit mode drag
    self.frame.anchorOptions = {
        horizontal = true,
        vertical = true,
        syncScale = false,
        syncDimensions = false,
    }

    -- Default position (top right, similar to Blizzard default)
    self.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)

    -- Background
    self.frame.bg = self.frame:CreateTexture(nil, "BACKGROUND")
    self.frame.bg:SetAllPoints(self.frame)
    self.frame.bg:SetColorTexture(0, 0, 0, 1)

    -- Overlay for canvas components (sits above the minimap render but below DIALOG strata)
    self.frame.Overlay = CreateFrame("Frame", nil, self.frame)
    self.frame.Overlay:SetAllPoints()
    self.frame.Overlay:SetFrameLevel(self.frame:GetFrameLevel() + 10)

    -- [ Zone Text component ]
    self.frame.ZoneText = self.frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.frame.ZoneText:SetPoint("TOP", self.frame, "BOTTOM", 0, -ZONE_TEXT_PADDING)

    -- [ Clock component ]
    self.frame.Clock = self.frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.frame.Clock:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 4, 4)
    self._lastCalendarDay = date(DAY_FORMAT)

    -- [ Coords component ]
    self.frame.Coords = self.frame.Overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.frame.Coords:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -4, 4)
    self.frame.Coords:SetJustifyH("RIGHT")

    -- [ Calendar component ]
    self.frame.Calendar = CreateFrame("Button", "OrbitMinimapCalendar", self.frame.Overlay)
    self.frame.Calendar:SetSize(CALENDAR_BUTTON_SIZE, CALENDAR_BUTTON_SIZE)
    self.frame.Calendar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -4, -4)
    self.frame.Calendar.orbitOriginalWidth = CALENDAR_BUTTON_SIZE
    self.frame.Calendar.orbitOriginalHeight = CALENDAR_BUTTON_SIZE

    self.frame.Calendar.Icon = self.frame.Calendar:CreateTexture(nil, "ARTWORK")
    self.frame.Calendar.Icon:SetAllPoints()
    self.frame.Calendar.Icon:SetAtlas("ui-hud-minimap-calendar")

    self.frame.Calendar.DayText = self.frame.Calendar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.frame.Calendar.DayText:SetPoint("CENTER", 0, CALENDAR_DAY_TEXT_OFFSET_Y)
    self.frame.Calendar.DayText:SetText(date(DAY_FORMAT))

    -- Pending invites glow
    self.frame.Calendar.InviteGlow = self.frame.Calendar:CreateTexture(nil, "OVERLAY", nil, 1)
    self.frame.Calendar.InviteGlow:SetAllPoints()
    self.frame.Calendar.InviteGlow:SetColorTexture(1, 0.82, 0, 0.4)
    self.frame.Calendar.InviteGlow:Hide()

    self.frame.Calendar:SetScript("OnClick", function() ToggleCalendar() end)
    self.frame.Calendar:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText(GAMETIME_TOOLTIP_TOGGLE_CALENDAR or "Calendar", 1, 1, 1)
        local pending = C_Calendar.GetNumPendingInvites and C_Calendar.GetNumPendingInvites() or 0
        if pending > 0 then
            GameTooltip:AddLine(string.format(CALENDAR_PENDING_INVITES_TOOLTIP or "%d pending invites", pending), 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    self.frame.Calendar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Orbit.EventBus:On("CALENDAR_UPDATE_PENDING_INVITES", function() self:UpdateCalendarInvites() end, self)

    -- [ Tracking component ]
    self.frame.Tracking = CreateFrame("Button", "OrbitMinimapTracking", self.frame.Overlay)
    self.frame.Tracking:SetSize(TRACKING_BUTTON_SIZE, TRACKING_BUTTON_SIZE)
    self.frame.Tracking:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -4)
    self.frame.Tracking.orbitOriginalWidth = TRACKING_BUTTON_SIZE
    self.frame.Tracking.orbitOriginalHeight = TRACKING_BUTTON_SIZE

    self.frame.Tracking.Icon = self.frame.Tracking:CreateTexture(nil, "ARTWORK")
    self.frame.Tracking.Icon:SetAllPoints()
    self.frame.Tracking.Icon:SetAtlas("ui-hud-minimap-tracking-up")

    self.frame.Tracking:SetScript("OnClick", function(btn)
        -- Reuse the native Blizzard tracking menu generator but anchor it to our visible button
        local nativeButton = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
        if nativeButton and nativeButton.menuGenerator then
            MenuUtil.CreateContextMenu(btn, nativeButton.menuGenerator)
        end
    end)
    self.frame.Tracking:SetScript("OnEnter", function(btn)
        btn.Icon:SetAtlas("ui-hud-minimap-tracking-mouseover")
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText(TRACKING or "Tracking", 1, 1, 1)
        GameTooltip:AddLine(MINIMAP_TRACKING_TOOLTIP_NONE or "Click to set tracking", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    self.frame.Tracking:SetScript("OnLeave", function(btn)
        btn.Icon:SetAtlas("ui-hud-minimap-tracking-up")
        GameTooltip:Hide()
    end)

    -- [ Compartment component ]
    self:CreateCompartmentButton()

    -- Register all canvas components for drag
    local MPC = function(key) return OrbitEngine.ComponentDrag:MakePositionCallback(self, SYSTEM_ID, key) end
    OrbitEngine.ComponentDrag:Attach(self.frame.ZoneText, self.frame, { key = "ZoneText", onPositionChange = MPC("ZoneText") })
    OrbitEngine.ComponentDrag:Attach(self.frame.Clock, self.frame, { key = "Clock", onPositionChange = MPC("Clock") })
    OrbitEngine.ComponentDrag:Attach(self.frame.Calendar, self.frame, { key = "Calendar", onPositionChange = MPC("Calendar") })
    OrbitEngine.ComponentDrag:Attach(self.frame.Tracking, self.frame, { key = "Tracking", onPositionChange = MPC("Tracking") })
    OrbitEngine.ComponentDrag:Attach(self.frame.Coords, self.frame, { key = "Coords", onPositionChange = MPC("Coords") })
    OrbitEngine.ComponentDrag:Attach(self._compartmentButton, self.frame, { key = "Compartment", onPositionChange = MPC("Compartment") })

    -- Register with edit mode
    OrbitEngine.Frame:AttachSettingsListener(self.frame, self, SYSTEM_ID)
    OrbitEngine.Frame:RestorePosition(self.frame, self, SYSTEM_ID)

    self:RegisterStandardEvents()
    self:RegisterVisibilityEvents()

    -- Zone text update events
    local function OnZoneChanged()
        local positions = self:GetSetting(SYSTEM_ID, "ComponentPositions") or {}
        local zoneOverrides = (positions.ZoneText or {}).overrides or {}
        UpdateZoneText(self.frame.ZoneText, self:GetSetting(SYSTEM_ID, "ZoneTextColoring"), zoneOverrides)
    end
    Orbit.EventBus:On("ZONE_CHANGED", OnZoneChanged, self)
    Orbit.EventBus:On("ZONE_CHANGED_INDOORS", OnZoneChanged, self)
    Orbit.EventBus:On("ZONE_CHANGED_NEW_AREA", OnZoneChanged, self)

    -- Reparent Blizzard's minimap into our container
    self:CaptureBlizzardMinimap()

    -- Check for pending calendar invites at login
    self:UpdateCalendarInvites()
end

-- [ CLOCK UPDATER ]---------------------------------------------------------------------------------

function Plugin:UpdateClock()
    if not self.frame or not self.frame.Clock then
        return
    end
    if GetCVarBool("timeMgrUseLocalTime") then
        self.frame.Clock:SetText(GameTime_GetLocalTime(GetCVarBool("timeMgrUseMilitaryTime")))
    else
        self.frame.Clock:SetText(GameTime_GetGameTime(GetCVarBool("timeMgrUseMilitaryTime")))
    end

    -- Refresh calendar day text at midnight
    local today = date(DAY_FORMAT)
    if self._lastCalendarDay ~= today then
        self._lastCalendarDay = today
        self.frame.Calendar.DayText:SetText(today)
    end
end

function Plugin:StartClockTicker()
    if self._clockTicker then
        return
    end
    self._clockTicker = C_Timer.NewTicker(CLOCK_UPDATE_INTERVAL, function() self:UpdateClock() end)
end

function Plugin:StopClockTicker()
    if self._clockTicker then
        self._clockTicker:Cancel()
        self._clockTicker = nil
    end
end

-- [ COORDS UPDATER ]--------------------------------------------------------------------------------

function Plugin:UpdateCoords()
    if not self.frame or not self.frame.Coords then
        return
    end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then
        self.frame.Coords:SetText("")
        return
    end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then
        self.frame.Coords:SetText("")
        return
    end
    local x, y = pos:GetXY()
    self.frame.Coords:SetFormattedText("%.1f, %.1f", x * 100, y * 100)
end

function Plugin:StartCoordsTicker()
    if self._coordsTicker then
        return
    end
    self._coordsTicker = C_Timer.NewTicker(COORDS_UPDATE_INTERVAL, function() self:UpdateCoords() end)
end

function Plugin:StopCoordsTicker()
    if self._coordsTicker then
        self._coordsTicker:Cancel()
        self._coordsTicker = nil
    end
end

-- [ CAPTURE ]---------------------------------------------------------------------------------------

function Plugin:CaptureBlizzardMinimap()
    local minimap = GetBlizzardMinimap()
    if not minimap then
        return
    end

    -- Strip all default art/chrome
    StripBlizzardArt()

    -- Reparent the actual render surface into our container
    minimap:SetParent(self.frame)
    minimap:ClearAllPoints()
    minimap:SetAllPoints(self.frame)

    -- Ensure minimap stays interactive
    minimap:EnableMouse(true)
    minimap:SetArchBlobRingScalar(0)
    minimap:SetQuestBlobRingScalar(0)

    -- Apply mask for square clipping
    minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8x8")

    -- Protect against Blizzard trying to re-steal the minimap
    OrbitEngine.FrameGuard:Protect(minimap, self.frame)
    OrbitEngine.FrameGuard:UpdateProtection(minimap, self.frame, function() self:ApplySettings() end, { enforceShow = true })

    -- Hook SetPoint to prevent Blizzard from repositioning
    if not minimap._orbitSetPointHooked then
        hooksecurefunc(minimap, "SetPoint", function(f, ...)
            if f._orbitRestoringPoint then
                return
            end
            if f:GetParent() == self.frame then
                local point = ...
                if point ~= "TOPLEFT" or select(2, ...) ~= self.frame then
                    f._orbitRestoringPoint = true
                    local ok, err = pcall(function()
                        f:ClearAllPoints()
                        f:SetAllPoints(self.frame)
                    end)
                    f._orbitRestoringPoint = nil
                    if not ok then
                        print("|cffff0000Orbit Minimap SetPoint guard error:|r", err)
                    end
                end
            end
        end)
        minimap._orbitSetPointHooked = true
    end

    self._captured = true
end

-- [ APPLY SETTINGS ]--------------------------------------------------------------------------------

function Plugin:ApplySettings()
    local frame = self.frame
    if not frame then
        return
    end
    if InCombatLockdown() then
        Orbit.CombatManager:QueueUpdate(function() self:ApplySettings() end)
        return
    end

    local isEditMode = Orbit:IsEditMode()
    local scale = (self:GetSetting(SYSTEM_ID, "Scale") or 100) / 100
    local size = self:GetSetting(SYSTEM_ID, "Size") or DEFAULT_SIZE
    local zoneTextSize = self:GetSetting(SYSTEM_ID, "ZoneTextSize") or 12
    local borderSize = Orbit.db.GlobalSettings.BorderSize or 2

    -- Scale
    frame:SetScale(scale)

    -- Size (square minimap)
    frame:SetSize(size, size)

    -- Border
    local backdropColor = Orbit.db.GlobalSettings.BackdropColour or { r = 0.145, g = 0.145, b = 0.145, a = 0.7 }
    Orbit.Skin:SkinBorder(frame, frame, borderSize, BORDER_COLOR)

    -- Background
    if frame.bg then
        frame.bg:SetColorTexture(backdropColor.r, backdropColor.g, backdropColor.b, backdropColor.a)
    end

    local s = Orbit.db.GlobalSettings.TextScale
    local textMultiplier = s == "Small" and 0.85 or s == "Large" and 1.15 or s == "ExtraLarge" and 1.30 or 1

    local savedPositions = self:GetSetting(SYSTEM_ID, "ComponentPositions") or {}

    -- Zone Text (disabled via Canvas Mode dock)
    if not self:IsComponentDisabled("ZoneText") then
        frame.ZoneText:Show()
        local zoneOverrides = (savedPositions.ZoneText or {}).overrides or {}
        Orbit.Skin:SkinText(frame.ZoneText, {
            font = Orbit.db.GlobalSettings.Font,
            textSize = zoneTextSize * textMultiplier,
        })
        OrbitEngine.OverrideUtils.ApplyOverrides(frame.ZoneText, zoneOverrides, {
            fontSize = zoneTextSize * textMultiplier,
            fontPath = LSM:Fetch("font", Orbit.db.GlobalSettings.Font),
        })
        UpdateZoneText(frame.ZoneText, self:GetSetting(SYSTEM_ID, "ZoneTextColoring"), zoneOverrides)
    else
        frame.ZoneText:Hide()
    end

    -- Clock (disabled via Canvas Mode dock)
    if not self:IsComponentDisabled("Clock") then
        frame.Clock:Show()
        local clockOverrides = (savedPositions.Clock or {}).overrides or {}
        Orbit.Skin:SkinText(frame.Clock, {
            font = Orbit.db.GlobalSettings.Font,
            textSize = (zoneTextSize - 1) * textMultiplier,
        })
        OrbitEngine.OverrideUtils.ApplyOverrides(frame.Clock, clockOverrides, {
            fontSize = (zoneTextSize - 1) * textMultiplier,
            fontPath = LSM:Fetch("font", Orbit.db.GlobalSettings.Font),
        })
        self:StartClockTicker()
        self:UpdateClock()
    else
        self:StopClockTicker()
        frame.Clock:Hide()
    end

    -- Calendar (disabled via Canvas Mode dock)
    if not self:IsComponentDisabled("Calendar") then
        frame.Calendar:Show()
        frame.Calendar.DayText:SetText(date(DAY_FORMAT))
        Orbit.Skin:SkinText(frame.Calendar.DayText, {
            font = Orbit.db.GlobalSettings.Font,
            textSize = CALENDAR_TEXT_SIZE * textMultiplier,
        })
    else
        frame.Calendar:Hide()
    end

    -- Tracking (disabled via Canvas Mode dock)
    if not self:IsComponentDisabled("Tracking") then
        frame.Tracking:Show()
    else
        frame.Tracking:Hide()
    end

    -- Coords (disabled via Canvas Mode dock)
    if not self:IsComponentDisabled("Coords") then
        frame.Coords:Show()
        local coordsOverrides = (savedPositions.Coords or {}).overrides or {}
        Orbit.Skin:SkinText(frame.Coords, {
            font = Orbit.db.GlobalSettings.Font,
            textSize = (zoneTextSize - 1) * textMultiplier,
        })
        OrbitEngine.OverrideUtils.ApplyOverrides(frame.Coords, coordsOverrides, {
            fontSize = (zoneTextSize - 1) * textMultiplier,
            fontPath = LSM:Fetch("font", Orbit.db.GlobalSettings.Font),
        })
        self:StartCoordsTicker()
        self:UpdateCoords()
    else
        self:StopCoordsTicker()
        frame.Coords:Hide()
    end

    -- Restore component positions from saved variables
    local isInCanvasMode = OrbitEngine.CanvasMode:IsActive(frame)
    if not isInCanvasMode then
        if savedPositions then
            OrbitEngine.ComponentDrag:RestoreFramePositions(frame, savedPositions)
        end
    end

    -- Opacity / Mouse-over fade
    self:ApplyMouseOver(frame, SYSTEM_ID)

    -- Restore position from saved variables
    OrbitEngine.Frame:RestorePosition(frame, self, SYSTEM_ID)

    -- Ensure minimap is parented correctly (in case of reload)
    local minimap = GetBlizzardMinimap()
    if minimap and minimap:GetParent() ~= frame then
        self:CaptureBlizzardMinimap()
    end

    -- Show the container
    frame:Show()

    -- Addon compartment
    self:ApplyAddonCompartment()

    -- In edit mode, always full alpha
    if isEditMode then
        frame:SetAlpha(1)
    end
end

-- [ CALENDAR PENDING INVITES ]----------------------------------------------------------------------

function Plugin:UpdateCalendarInvites()
    if not self.frame or not self.frame.Calendar then
        return
    end
    local glow = self.frame.Calendar.InviteGlow
    if not glow then
        return
    end
    local pending = C_Calendar.GetNumPendingInvites and C_Calendar.GetNumPendingInvites() or 0
    if pending > 0 then
        glow:Show()
    else
        glow:Hide()
    end
end

-- [ TEARDOWN ]--------------------------------------------------------------------------------------
-- Called when the plugin is live-toggled off. Restores Blizzard state and cancels timers.

function Plugin:OnDisable()
    -- Stop tickers
    self:StopClockTicker()
    self:StopCoordsTicker()

    -- Restore collected addon buttons
    self._compartmentActive = false
    self:RestoreCollectedButtons()

    -- Hide our frames
    if self._compartmentFlyout then
        self._compartmentFlyout:Hide()
    end

    -- Restore Blizzard minimap to its original parent
    local minimap = GetBlizzardMinimap()
    local cluster = GetBlizzardCluster()
    if minimap and cluster then
        minimap:SetParent(cluster)
        minimap:ClearAllPoints()
        -- Default Blizzard minimap offset within MinimapCluster as of 12.0
        minimap:SetPoint("CENTER", cluster, "CENTER", 9, -1)
    end

    -- Re-show the Blizzard cluster
    if cluster then
        cluster:Show()
    end

    -- Re-show expansion landing page button
    if ExpansionLandingPageMinimapButton then
        ExpansionLandingPageMinimapButton:SetScript("OnShow", nil)
        ExpansionLandingPageMinimapButton:Show()
    end
end
