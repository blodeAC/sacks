-- sacks: bag items shown as small groups ("sacks") that you pin wherever you like.
-- Each sack takes the items that match its rule and always keeps one blank slot, labelled with how many
-- real bag slots are free. While a vendor window is open the sacks stack beside it, keeping their own layout.

local _, ns = ...


local SLOT_GAP = 3
local PADDING = 6
local TITLE_HEIGHT = 14
local DEFAULT_COLUMNS = 6
local SCAN_LIMIT = 30 -- how many item class / subclass ids to scan when looking names up
local OTHER_NAME = "Other"
local DEFAULT_ANCHOR = "TOPLEFT"
local DEFAULT_FLOW = "ROWS"
local DEFAULT_TITLE = "TOP"
local DEFAULT_SORT = { { key = "name" } }
local WINDOW_WIDTH = 760
local ROW_HEIGHT = 28
local BUTTON_HEIGHT = 22
local MARGIN = 14
local HEADER = 28
local LABEL_HEIGHT = 14
local DROPDOWN_HEIGHT = 32
local LINE_HEIGHT = 34
local LAYOUT_WIDTH = 140
local SORT_LABEL_WIDTH = 70
local ORDER_ROW_HEIGHT = BUTTON_HEIGHT + 2
local PIN_WIDTH = 70
local MOVE_WIDTH = 50
local HINT_HEIGHT = 26
local SECTION_HEIGHT = LABEL_HEIGHT + BUTTON_HEIGHT + 30
local CONTENT_TOP = HEADER + 38
local TABLE_ROW_HEIGHT = 20
local WHEEL_STEP = 3
local CHOICE_WIDTH = 120
local DROPDOWN_INSET = 16
local CHECK_SIZE = 24
local ICON_SIZE = 31

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

-- RefreshSettings and ToggleSettings are defined with the settings window (Window.lua) and called through ns

local state = { frames = {}, counts = {}, titles = {}, vendor = false, pending = false, items = {}, selected = {} }

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
ns.SORT_LABEL_WIDTH = SORT_LABEL_WIDTH
ns.Say = Say
ns.SlotSize = SlotSize
ns.TABLE_ROW_HEIGHT = TABLE_ROW_HEIGHT
ns.TITLE_HEIGHT = TITLE_HEIGHT
ns.WHEEL_STEP = WHEEL_STEP
ns.WINDOW_WIDTH = WINDOW_WIDTH
ns.state = state
