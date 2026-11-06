-- sacks: bag items shown as small groups ("sacks") that you pin wherever you like.
-- Each sack takes the items that match its rule and always keeps one blank slot, labelled with how many
-- real bag slots are free. While a vendor window is open the sacks stack beside it, keeping their own layout.

local _, ns = ...


-- Measurements come from the game: the height of its fonts, the real size of its button template, the width of text as
-- drawn. Every number below that is not measured is a ratio of one that is; a fallback is used only when this client
-- reports nothing usable.
local function Positive(value, fallback)
    return (type(value) == "number" and value > 0) and value or fallback
end

local function FontHeight(font, fallback)
    local ok, text = pcall(UIParent.CreateFontString, UIParent, nil, "OVERLAY", font)
    if not ok or not text then return fallback end
    text:SetText("Ag")
    local height = Positive(text.GetStringHeight and text:GetStringHeight(), nil) or Positive(select(2, text:GetFont()), nil)
    return Positive(height, fallback)
end

-- The height the game's own template gives a frame of this kind (a probe frame, hidden at once).
local function MeasuredHeight(kind, name, template, fallback)
    local ok, probe = pcall(CreateFrame, kind, name, UIParent, template)
    if not ok or not probe then return fallback end
    local height = Positive(probe.GetHeight and probe:GetHeight(), nil)
    if probe.Hide then probe:Hide() end
    return height or fallback
end

-- Width of text as the game draws it in a font (the small highlight font unless another is named).
local measuring = {}
local function TextWidth(text, font)
    font = font or "GameFontHighlightSmall"
    measuring[font] = measuring[font] or UIParent:CreateFontString(nil, "OVERLAY", font)
    measuring[font]:SetText(text or "")
    local width = measuring[font]:GetStringWidth()
    return type(width) == "number" and width or 0
end

local LABEL_HEIGHT = math.ceil(FontHeight("GameFontHighlightSmall", 10)) + 2
local TITLE_HEIGHT = math.ceil(FontHeight("GameFontNormalSmall", 10)) + 2
local PADDING = math.ceil(LABEL_HEIGHT / 2)
local SLOT_GAP = math.ceil(PADDING / 2)
local BUTTON_HEIGHT = math.ceil(MeasuredHeight("Button", nil, "UIPanelButtonTemplate", 22))
local MARGIN = 2 * PADDING
local CHECK_SIZE = BUTTON_HEIGHT + SLOT_GAP
local DROPDOWN_HEIGHT = math.ceil(MeasuredHeight("Frame", "SacksDropdownProbe", "UIDropDownMenuTemplate", BUTTON_HEIGHT + 2 * PADDING))
local LINE_HEIGHT = DROPDOWN_HEIGHT + SLOT_GAP
local ROW_HEIGHT = BUTTON_HEIGHT + PADDING
local ORDER_ROW_HEIGHT = BUTTON_HEIGHT + SLOT_GAP
local HEADER = ROW_HEIGHT
local HINT_HEIGHT = 2 * LABEL_HEIGHT - 2
local SECTION_HEIGHT = LABEL_HEIGHT + BUTTON_HEIGHT + 5 * PADDING
local CONTENT_TOP = HEADER + BUTTON_HEIGHT + 2 * PADDING
local TABLE_ROW_HEIGHT = BUTTON_HEIGHT - SLOT_GAP + 1
local DROPDOWN_INSET = 2 * PADDING + SLOT_GAP -- the template's left cap
local CHOICE_WIDTH = math.ceil(TextWidth("Weapon (old)")) + 2 * DROPDOWN_INSET
local LAYOUT_WIDTH = math.ceil(TextWidth("Bottom right")) + 2 * DROPDOWN_INSET + 2 * PADDING
local SORT_LABEL_WIDTH = math.ceil(TextWidth("Then by")) + 2 * PADDING
local NAME_WIDTH = math.ceil(TextWidth(string.rep("M", 16))) + 2 * PADDING -- a typing box for a name: room for 16 wide letters
local DROPDOWN_RIGHT = DROPDOWN_INSET + PADDING -- how far a drop-down's art reaches past the width it is given
local WHEEL_STEP = 3 -- rows per mouse wheel notch
local WINDOW_WIDTH = 760 -- how wide the settings window is drawn
local DEFAULT_COLUMNS = 6
local SCAN_LIMIT = 30 -- how many item class / subclass ids to scan when looking names up
local OTHER_NAME = "Other"
local DEFAULT_ANCHOR = "TOPLEFT"
local DEFAULT_FLOW = "ROWS"
local DEFAULT_TITLE = "TOP"
local DEFAULT_SORT = { { key = "name" } }
local ICON_SIZE -- set below, once SlotSize exists
local PIN_WIDTH, MOVE_WIDTH

-- A button wide enough for its own text. Pass several texts to fit the widest.
local function ButtonWidth(text)
    local widest = 0
    if type(text) == "table" then
        for _, each in ipairs(text) do widest = math.max(widest, TextWidth(each)) end
    else
        widest = TextWidth(text)
    end
    return math.max(BUTTON_HEIGHT, math.ceil(widest) + 3 * PADDING)
end
PIN_WIDTH = ButtonWidth({ "Pin", "Unpin" })
MOVE_WIDTH = ButtonWidth({ "Up", "Down" })

local function Say(text)
    print("|cff66ccffsacks|r " .. tostring(text))
end

-- This client has no global GetItemClassInfo: use the C_Item version, and the Enum names as a last resort.
-- The game files some old items under retired categories and names them "Explosives (OBSOLETE)". The tag is dropped
-- from every name shown; the second return value says it was there.
local function Untagged(name)
    if type(name) ~= "string" then return name, false end
    local clean, found = name:gsub("%s*%(OBSOLETE%)", "")
    return clean, found > 0
end

local function ItemClassInfo(id)
    local lookup = GetItemClassInfo or (C_Item and C_Item.GetItemClassInfo)
    if lookup then return Untagged(lookup(id)) end
    for name, value in pairs(Enum.ItemClass) do
        if value == id then return name end
    end
end

local function ItemSubClassInfo(class, sub)
    local lookup = GetItemSubClassInfo or (C_Item and C_Item.GetItemSubClassInfo)
    if lookup then return Untagged(lookup(class, sub)) end
end

-- Retail-style C_Container / C_Item if the client has them, the old globals otherwise.
local Container = C_Container or {
    GetContainerNumSlots = GetContainerNumSlots,
    GetContainerNumFreeSlots = GetContainerNumFreeSlots,
    GetContainerItemInfo = GetContainerItemInfo,
    PickupContainerItem = PickupContainerItem,
}
local Item = C_Item or {}
local ItemInstant = Item.GetItemInfoInstant or GetItemInfoInstant
local ItemInfo = Item.GetItemInfo or GetItemInfo

-- Slots are drawn the same size as your action bar buttons.
local function SlotSize()
    local width = ActionButton1 and ActionButton1.GetWidth and ActionButton1:GetWidth()
    return (type(width) == "number" and width > 0) and width or 34
end
ICON_SIZE = SlotSize() - 3

-- RefreshSettings and ToggleSettings are defined with the settings window (Window.lua) and called through ns

local state = { frames = {}, counts = {}, titles = {}, stale = {}, vendor = false, pending = false, items = {}, selected = {} }

-- shared with the files after this one
ns.BUTTON_HEIGHT = BUTTON_HEIGHT
ns.CHECK_SIZE = CHECK_SIZE
ns.CHOICE_WIDTH = CHOICE_WIDTH
ns.CONTENT_TOP = CONTENT_TOP
ns.Container = Container
ns.DEFAULT_ANCHOR = DEFAULT_ANCHOR
ns.DEFAULT_COLUMNS = DEFAULT_COLUMNS
ns.DEFAULT_FLOW = DEFAULT_FLOW
ns.DEFAULT_SORT = DEFAULT_SORT
ns.DEFAULT_TITLE = DEFAULT_TITLE
ns.DROPDOWN_HEIGHT = DROPDOWN_HEIGHT
ns.DROPDOWN_INSET = DROPDOWN_INSET
ns.HEADER = HEADER
ns.HINT_HEIGHT = HINT_HEIGHT
ns.ICON_SIZE = ICON_SIZE
ns.Item = Item
ns.ItemClassInfo = ItemClassInfo
ns.ItemInfo = ItemInfo
ns.ItemInstant = ItemInstant
ns.ItemSubClassInfo = ItemSubClassInfo
ns.LABEL_HEIGHT = LABEL_HEIGHT
ns.LAYOUT_WIDTH = LAYOUT_WIDTH
ns.LINE_HEIGHT = LINE_HEIGHT
ns.MARGIN = MARGIN
ns.MOVE_WIDTH = MOVE_WIDTH
ns.ORDER_ROW_HEIGHT = ORDER_ROW_HEIGHT
ns.OTHER_NAME = OTHER_NAME
ns.PADDING = PADDING
ns.PIN_WIDTH = PIN_WIDTH
ns.ROW_HEIGHT = ROW_HEIGHT
ns.SCAN_LIMIT = SCAN_LIMIT
ns.SECTION_HEIGHT = SECTION_HEIGHT
ns.SLOT_GAP = SLOT_GAP
ns.DROPDOWN_RIGHT = DROPDOWN_RIGHT
ns.NAME_WIDTH = NAME_WIDTH
ns.ButtonWidth = ButtonWidth
ns.TextWidth = TextWidth
ns.SORT_LABEL_WIDTH = SORT_LABEL_WIDTH
ns.Say = Say
ns.SlotSize = SlotSize
ns.TABLE_ROW_HEIGHT = TABLE_ROW_HEIGHT
ns.TITLE_HEIGHT = TITLE_HEIGHT
ns.WHEEL_STEP = WHEEL_STEP
ns.WINDOW_WIDTH = WINDOW_WIDTH
ns.state = state
