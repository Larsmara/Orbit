---@type Orbit
local Orbit = Orbit
local OrbitEngine = Orbit.Engine

-- [ CONSTANTS ]-------------------------------------------------------------------------------------

local SYSTEM_ID = "Orbit_Minimap"
local DEFAULT_SIZE = 200

-- [ SETTINGS UI ]-----------------------------------------------------------------------------------

local Plugin = Orbit:GetPlugin(SYSTEM_ID)

function Plugin:AddSettings(dialog, systemFrame)
    local systemIndex = systemFrame.systemIndex or SYSTEM_ID
    local SB = OrbitEngine.SchemaBuilder

    local schema = {
        hideNativeSettings = true,
        controls = {},
    }

    -- Scale
    SB:AddSizeSettings(self, schema, systemIndex, systemFrame, nil, nil, {
        key = "Scale",
        label = "Scale",
        default = 100,
        min = 50,
        max = 200,
    })

    -- Opacity
    SB:AddOpacitySettings(self, schema, systemIndex, systemFrame)

    -- Size (diameter)
    table.insert(schema.controls, {
        type = "slider",
        key = "Size",
        label = "Size",
        min = 100,
        max = 400,
        step = 1,
        default = DEFAULT_SIZE,
    })

    -- Zone Text Size
    table.insert(schema.controls, {
        type = "slider",
        key = "ZoneTextSize",
        label = "Zone Text Size",
        min = 8,
        max = 24,
        step = 1,
        default = 12,
    })

    OrbitEngine.Config:Render(dialog, systemFrame, self, schema)
end
