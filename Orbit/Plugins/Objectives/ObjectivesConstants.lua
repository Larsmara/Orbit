-- [ OBJECTIVES CONSTANTS ]---------------------------------------------------------------------------
local _, Orbit = ...

Orbit.ObjectivesConstants = {
    SYSTEM_ID = "Orbit_Objectives",
    DEFAULT_SCALE = 100,
    DEFAULT_WIDTH = 300,
    DEFAULT_HEIGHT = 334,
    DEFAULT_ANCHOR_X = -80,
    DEFAULT_ANCHOR_Y = -260,
    WIDTH_MIN = 260,
    WIDTH_MAX = 400,
    WIDTH_STEP = 2,
    HEIGHT_MIN = 200,
    HEIGHT_MAX = 1200,
    HEIGHT_STEP = 10,
    BG_OPACITY_MIN = 0,
    BG_OPACITY_MAX = 100,
    BG_OPACITY_STEP = 5,
    BG_OPACITY_DEFAULT = 0,
    CONTENT_PADDING = 6,
    HEADER_SEPARATOR_HEIGHT = 2,
    OPACITY_DEFAULT = 100,
    TITLE_FONT_SIZE_MIN = 8,
    TITLE_FONT_SIZE_MAX = 18,
    TITLE_FONT_SIZE_STEP = 1,
    TITLE_FONT_SIZE_DEFAULT = 12,
    OBJECTIVE_FONT_SIZE_MIN = 8,
    OBJECTIVE_FONT_SIZE_MAX = 16,
    OBJECTIVE_FONT_SIZE_STEP = 1,
    OBJECTIVE_FONT_SIZE_DEFAULT = 10,
    HEADER_FONT_SIZE_MIN = 8,
    HEADER_FONT_SIZE_MAX = 20,
    HEADER_FONT_SIZE_STEP = 1,
    HEADER_FONT_SIZE_DEFAULT = 14,
    HEADER_VPADDING = 3,
    HEADER_MIN_HEIGHT = 18,
    PROGRESS_BAR_FONT_SIZE = 12,
    PROGRESS_BAR_HEIGHT = 16,
    PROGRESS_BAR_LABEL_PADDING = 4,
    PROGRESS_BAR_SIDE_PADDING = 30,
    PROGRESS_BAR_LEFT_EXTRA = 10,
    BAR_BG_ALPHA = 0.85,
    -- Scrolling snaps to quest boundaries (one wheel tick = one quest) and eases there; higher = snappier. The ease runs a self-terminating OnUpdate only while animating.
    SCROLL_ANIM_SPEED = 14,
    -- Horizontal slack on the scroll viewport so scenario/delve flyouts opening past our edge aren't clipped (the ScrollFrame clips vertically to scroll, but this widens its rect so it never clips left/right).
    HORIZONTAL_OVERFLOW = 260,
    -- Breathing room added below the content ONLY when the bottom-most entry is a progress bar (its skinned border would otherwise sit flush against the frame's bottom border). Text-ending content hugs tight so the backdrop/border don't gain dead space.
    PROGRESS_BAR_BOTTOM_PAD = 6,
    -- When the bottom-most element is a header (a collapsed last section), its separator is drawn ~thickness BELOW the header, past the content height — this pad keeps it inside the content-fit box so it isn't clipped.
    HEADER_BOTTOM_PAD = 4,
    HIGHLIGHT_BRIGHTEN = 1.3,
    POI_SIZE = 18,

    -- Row/section layout geometry (our own widgets — no Blizzard block metrics). Inter-element gaps are Format-driven (FORMAT_SPACING).
    OBJECTIVE_INDENT    = 22,  -- objective text left indent (past the POI icon column)
    CHECK_SIZE          = 12,  -- completed-objective checkmark
    CHECK_TEXT_GAP      = 2,   -- gap between the checkmark column and objective text
    ITEM_BUTTON_SIZE    = 20,  -- quest-item hover target (right of title)
    ITEM_RESERVE_GAP    = 4,   -- gap reserved between title and the item button
    HEADER_TITLE_INDENT = 14,  -- section-header title left offset (past the chevron)
    HEADER_HIGHLIGHT_ALPHA = 0.06,  -- subtle white overlay on header mouseover
    CHEVRON_FONT_SIZE   = 14,  -- collapse chevron (+/-) glyph size
    ICON_GLOW_PAD       = 16,  -- how far the icon mouseover glow overshoots the icon
    ICON_CROP_MIN       = 0.08,  -- square-crop texcoord for file-texture icons (achievement/item)
    ICON_CROP_MAX       = 0.92,

    -- Density presets for the Format slider (1=Compact, 2=Standard, 3=Large): every inter-element gap.
    FORMAT_DEFAULT = 2,
    FORMAT_MIN = 1,
    FORMAT_MAX = 3,
    FORMAT_SPACING = {
        [1] = { sectionTop = 5,  sectionHeader = 7,  row = 9,  titleObj = 1, objLine = 1 },
        [2] = { sectionTop = 8,  sectionHeader = 9,  row = 11, titleObj = 2, objLine = 2 },
        [3] = { sectionTop = 13, sectionHeader = 12, row = 15, titleObj = 4, objLine = 4 },
    },

    -- The RegisterUpdate driver coalesces ScheduleRefresh() boolean writes into one FullLayout per this interval, always on a taint-free stack.
    REFRESH_POLL_INTERVAL = 0.1,

    -- Quest sort order within each section. "tracked" preserves the watch-list order (no sort); the rest re-sort our own model (taint-safe — we own the render). Proximity re-reads distance on a ticker so it stays live as you move.
    SORT_DEFAULT = "tracked",
    SORT_PROXIMITY_INTERVAL = 2.0,

    WOWHEAD_QUEST_URL = "https://www.wowhead.com/quest=%d",

    -- Light entry animations (Blizzard AnimationGroups + StatusBar interpolation; no manual OnUpdate).
    FADE_IN_DURATION    = 0.25,
    FLASH_PEAK_ALPHA    = 0.14,
    FLASH_UP_DURATION   = 0.15,
    FLASH_DOWN_DURATION = 0.35,

    TITLE_COLOR_DEFAULT     = { r = 1.00, g = 0.82, b = 0.00, a = 1 },
    COMPLETED_COLOR_DEFAULT = { r = 0.90, g = 0.80, b = 0.10, a = 1 },
    FOCUS_COLOR_DEFAULT     = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
    HEADER_COLOR_DEFAULT    = { r = 1.00, g = 1.00, b = 1.00, a = 1 },
    OBJECTIVE_COLOR_DEFAULT = { r = 0.80, g = 0.80, b = 0.80 },
    CHEVRON_COLOR           = { r = 0.80, g = 0.80, b = 0.80 },
    QUEST_COUNT_COLOR       = { r = 0.60, g = 0.60, b = 0.60 },
    SEPARATOR_ALPHA         = 0.18,
    SEPARATOR_ALPHA_CLASS   = 0.48,

    PROGRESS_FORMAT_DEFAULT = "%",
    PROGRESS_TOKENS = {
        { key = "%",        sample = "75%" },
        { key = "CurrentK", sample = "8K"  },
        { key = "Current",  sample = "150" },
        { key = "MaxK",     sample = "10K" },
        { key = "Max",      sample = "200" },
    },

    -- POI tag-specific title colours (overrides classification when tag matches)
    TAG_COLOR_GROUP   = { r = 0.40, g = 0.70, b = 1.00 },
    TAG_COLOR_RAID    = { r = 0.20, g = 0.58, b = 0.30 },
    TAG_COLOR_PVP     = { r = 0.90, g = 0.20, b = 0.20 },
    TAG_COLOR_ACCOUNT = { r = 0.40, g = 0.80, b = 0.95 },

    -- Titles reuse Blizzard's own localized header globals (all-locale, matching Blizzard's terms — like using Blizzard atlases).
    CATEGORY = {
        SCENARIO    = "SCENARIO",
        COMPLETED   = "COMPLETED",
        CAMPAIGN    = "CAMPAIGN",
        QUEST       = "QUEST",
        WORLDQUEST  = "WORLDQUEST",
        BONUS       = "BONUS",
        ACHIEVEMENT = "ACHIEVEMENT",
        PROFESSION  = "PROFESSION",
        MONTHLY     = "MONTHLY",
    },
    -- Render order. titleGlobal resolved lazily via _G (some header globals belong to Blizzard_ObjectiveTracker, which may load after this file); COMPLETED uses an Orbit string (no clean Blizzard "Completed" global).
    SECTIONS = {
        { key = "SCENARIO",    titleGlobal = "TRACKER_HEADER_SCENARIO" },
        { key = "COMPLETED",   title = Orbit.L.PLU_OBJ_SEC_COMPLETED },
        { key = "CAMPAIGN",    titleGlobal = "TRACKER_HEADER_CAMPAIGN_QUESTS" },
        { key = "QUEST",       titleGlobal = "TRACKER_HEADER_QUESTS" },
        { key = "WORLDQUEST",  titleGlobal = "TRACKER_HEADER_WORLD_QUESTS" },
        { key = "BONUS",       titleGlobal = "TRACKER_HEADER_BONUS_OBJECTIVES" },
        { key = "ACHIEVEMENT", titleGlobal = "TRACKER_HEADER_ACHIEVEMENTS" },
        { key = "PROFESSION",  titleGlobal = "PROFESSIONS_TRACKER_HEADER_PROFESSION" },
        { key = "MONTHLY",     titleGlobal = "TRACKER_HEADER_MONTHLY_ACTIVITIES" },
    },
}

-- Validate/recover a colour from plain {r,g,b} or legacy colour-curve {pins=...} format.
function Orbit.ObjectivesConstants.ValidateColor(c, fallback)
    if type(c) ~= "table" then return fallback end
    if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then return c end
    if c.pins and c.pins[1] and type(c.pins[1].color) == "table" then
        local pin = c.pins[1].color
        if type(pin.r) == "number" and type(pin.g) == "number" and type(pin.b) == "number" then
            return { r = pin.r, g = pin.g, b = pin.b, a = pin.a or 1 }
        end
    end
    return fallback
end
