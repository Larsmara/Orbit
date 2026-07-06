-- [ OBJECTIVES SCENARIO PROVIDER ]-------------------------------------------------------------------
-- No-op: scenarios/delves/events are rendered by Blizzard's own ScenarioObjectiveTracker, which SuppressBlizzardTracker keeps and reparents into the top of our box (native cards + flyouts).
---@type Orbit
local Orbit = Orbit

Orbit.ObjectivesModel:RegisterProvider(function() return nil end)
