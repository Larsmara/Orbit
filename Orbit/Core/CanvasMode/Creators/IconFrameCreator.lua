-- [ CANVAS MODE - ICON FRAME CREATOR ]--------------------------------------------------------------

local _, addonTable = ...
local Orbit = addonTable
local OrbitEngine = Orbit.Engine
local CanvasMode = OrbitEngine.CanvasMode
local CC = CanvasMode.CreatorConstants
local GetSourceSize = CanvasMode.GetSourceSize

-- [ CREATOR ]---------------------------------------------------------------------------------------

local function Create(container, preview, key, source, data)
    local iconTexture = source.Icon
    local hasFlipbook = iconTexture and iconTexture.orbitPreviewTexCoord
    local visual

    -- Zoom component: render stacked zoom-in / zoom-out icons to match the real minimap
    if key == "Zoom" then
        local overrides = data and data.overrides
        local savedSize = overrides and overrides.IconSize
        local w, h = GetSourceSize(source, CC.DEFAULT_ICON_SIZE, CC.DEFAULT_ICON_SIZE)
        if savedSize and savedSize > 0 then
            local aspect = h / math.max(w, 1)
            w = savedSize
            h = savedSize * aspect
        end
        container:SetSize(w, h)

        local btnSize = w
        local gap = 2

        local zoomInTex = container:CreateTexture(nil, "ARTWORK")
        zoomInTex:SetSize(btnSize, btnSize)
        zoomInTex:SetPoint("TOP", container, "TOP", 0, 0)
        zoomInTex:SetAtlas("ui-hud-minimap-zoom-in", false)

        local zoomOutTex = container:CreateTexture(nil, "ARTWORK")
        zoomOutTex:SetSize(btnSize, btnSize)
        zoomOutTex:SetPoint("TOP", zoomInTex, "BOTTOM", 0, -gap)
        zoomOutTex:SetAtlas("ui-hud-minimap-zoom-out", false)

        visual = container
        container.isIconFrame = true
        return visual
    end

    if hasFlipbook then
        visual = container:CreateTexture(nil, "OVERLAY")
        visual:SetAllPoints(container)
        local atlasName = iconTexture.GetAtlas and iconTexture:GetAtlas()
        if atlasName then
            visual:SetAtlas(atlasName, false)
        elseif iconTexture:GetTexture() then
            visual:SetTexture(iconTexture:GetTexture())
        end
        local tc = iconTexture.orbitPreviewTexCoord
        visual:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetAllPoints(container)
        btn:EnableMouse(false)
        btn.Icon = btn:CreateTexture(nil, "ARTWORK")
        btn.Icon:SetAllPoints()
        btn.icon = btn.Icon

        local texturePath = iconTexture and iconTexture:GetTexture()
        local StatusMixin = Orbit.StatusIconMixin
        if texturePath then
            btn.Icon:SetTexture(texturePath)
        elseif StatusMixin and key == "DefensiveIcon" then
            btn.Icon:SetTexture(StatusMixin:GetDefensiveTexture())
        elseif StatusMixin and key == "CrowdControlIcon" then
            btn.Icon:SetTexture(StatusMixin:GetCrowdControlTexture())
        elseif StatusMixin and key == "PrivateAuraAnchor" then
            btn.Icon:SetTexture(StatusMixin:GetPrivateAuraTexture())
        else
            local previewAtlases = Orbit.IconPreviewAtlases or {}
            if previewAtlases[key] then
                btn.Icon:SetAtlas(previewAtlases[key], false)
            else
                btn.Icon:SetColorTexture(CC.FALLBACK_GRAY[1], CC.FALLBACK_GRAY[2], CC.FALLBACK_GRAY[3],
                    CC.FALLBACK_GRAY[4])
            end
        end

        local scale = btn:GetEffectiveScale() or 1
        local globalBorder = Orbit.db.GlobalSettings.BorderSize or Orbit.Engine.Pixel:DefaultBorderSize(scale)
        if Orbit.Skin and Orbit.Skin.Icons then
            Orbit.Skin.Icons:ApplyCustom(btn, { zoom = 0, borderStyle = 1, borderSize = globalBorder, showTimer = false })
            Orbit.Skin:SkinBorder(btn, btn, globalBorder)
        end

        visual = btn
        container.isIconFrame = true
    end

    local overrides = data and data.overrides
    local savedSize = overrides and overrides.IconSize
    local w, h = GetSourceSize(source, CC.DEFAULT_ICON_SIZE, CC.DEFAULT_ICON_SIZE)
    if savedSize and savedSize > 0 then w, h = savedSize, savedSize end
    container:SetSize(w, h)

    return visual
end

CanvasMode:RegisterCreator("IconFrame", Create)
