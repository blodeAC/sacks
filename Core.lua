-- sacks: bag items shown as small groups ("sacks") that you pin wherever you like.
-- Each sack takes the items that match its rule and always keeps one blank slot, labelled with how many
-- real bag slots are free. While a vendor window is open the sacks stack beside it, keeping their own layout.

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

local RefreshSettings, ToggleSettings -- defined with the settings window below

local state = { frames = {}, counts = {}, titles = {}, vendor = false, pending = false, items = {}, selected = {} }

---------------------------------------------------------------------------------------------------
-- Reading the bags
---------------------------------------------------------------------------------------------------

-- One entry per occupied slot: where it is, what it is, and what class the game files it under.
local function BitAnd(a, b)
    if bit and bit.band then return bit.band(a, b) end
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

local function ReadSlot(bag, slot)
    local info = Container.GetContainerItemInfo(bag, slot)
    if info == nil then return nil end
    local entry = { bag = bag, slot = slot }
    local _
    if type(info) == "table" then
        entry.link, entry.count, entry.quality, entry.itemID, entry.icon =
            info.hyperlink, info.stackCount, info.quality, info.itemID, info.iconFileID
        entry.bound = info.isBound and 1 or 0
    else
        entry.icon, entry.count, _, entry.quality, _, _, entry.link = Container.GetContainerItemInfo(bag, slot)
    end
    local id, _, _, _, icon, classID, subClassID = ItemInstant(entry.link or entry.itemID)
    entry.itemID = entry.itemID or id
    entry.icon = entry.icon or icon
    entry.classID, entry.subClassID = classID, subClassID
    local info = { ItemInfo(entry.link or entry.itemID) }
    entry.name = info[1] or entry.link or tostring(entry.itemID)
    entry.sellPrice = tonumber(info[11]) or 0
    entry.itemLevel, entry.minLevel, entry.stackMax = tonumber(info[4]), tonumber(info[5]), tonumber(info[8])
    entry.equip = (info[9] and info[9] ~= "" and info[9] ~= "INVTYPE_NON_EQUIP_IGNORE") and info[9] or "NONE"
    entry.bindType, entry.reagent = tonumber(info[14]), info[17] and 1 or 0
    entry.bound = entry.bound or 0
    entry.quality = entry.quality or 0
    local family = GetItemFamily or (C_Item and C_Item.GetItemFamily)
    entry.family = family and tonumber(family(entry.link or entry.itemID)) or 0
    return entry
end

-- The last bag index: the backpack, the bag slots, and the reagent bag where the client has one.
local function LastBag()
    return (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
end

local function BagName(bag)
    local lookup = Container.GetBagName or GetBagName
    local name = lookup and lookup(bag)
    if name and name ~= "" then return name end
    return bag == 0 and "Backpack" or ("Bag " .. bag)
end

-- Reads every item in every bag. Also returns the free slots in normal bags and in special bags (a mining bag, say),
-- and keeps a per-bag list for the tooltip and the settings window.
local function ReadBags()
    local items, free, special = {}, 0, 0
    state.bags, state.slots, state.freeAll = {}, 0, 0
    local families = {}
    for bag = 0, LastBag() do
        local slots = Container.GetContainerNumSlots(bag) or 0
        local bagFree, bagType = Container.GetContainerNumFreeSlots(bag)
        bagFree = bagFree or 0
        if slots > 0 then
            local isSpecial = (bagType or 0) ~= 0
            state.bags[#state.bags + 1] = { bag = bag, name = BagName(bag), total = slots, free = bagFree, special = isSpecial,
                family = bagType or 0 }
            families[bag] = bagType or 0
            state.slots = state.slots + slots
            state.freeAll = state.freeAll + bagFree
            if isSpecial then special = special + bagFree else free = free + bagFree end
        end
        for slot = 1, slots do
            local entry = ReadSlot(bag, slot)
            if entry then items[#items + 1] = entry end
        end
    end
    -- Where each item really lives. An item that fits a special bag (a mining bag, say) but sits in a normal bag is
    -- flagged, because that wastes a normal slot; "full" means the special bag has no room, so it can't move.
    for _, item in ipairs(items) do
        item.bagName = BagName(item.bag)
        item.inSpecial = (families[item.bag] or 0) ~= 0
        if not item.inSpecial and (item.family or 0) ~= 0 then
            for _, bag in ipairs(state.bags) do
                if bag.special and BitAnd(item.family, bag.family) ~= 0 then
                    item.fitsBag, item.fitsFree = bag.name, bag.free
                    break
                end
            end
        end
    end
    return items, free, special
end

---------------------------------------------------------------------------------------------------
-- Rules: a sack takes every item that matches all the criteria it lists
---------------------------------------------------------------------------------------------------

-- A rule is a list of conditions and an item has to meet all of them. A condition looks like
--     { field = "quality", op = ">=", value = 3 }
-- Fields: class, sub (a subclass, which carries its own class), quality, name, and item (an exact item id).
local COMPARE = {
    ["="] = function(a, b) return a == b end,
    ["~="] = function(a, b) return a ~= b end,
    ["<"] = function(a, b) return a < b end,
    ["<="] = function(a, b) return a <= b end,
    [">"] = function(a, b) return a > b end,
    [">="] = function(a, b) return a >= b end,
}

local function Compare(op, actual, wanted)
    if actual == nil or wanted == nil then return op == "~=" end
    return COMPARE[op](actual, wanted)
end

-- Patterns ignore case. Lowercasing a whole pattern would turn %S into %s, so letters after a % are left alone.
local function LowerPattern(pattern)
    return (pattern:gsub("(%%?)(.)", function(escape, char)
        if escape == "" then return char:lower() end
        return escape .. char
    end))
end

-- A name condition holds one or more alternatives separated by |.
local function Alternatives(text)
    local list = {}
    for piece in (text or ""):gmatch("[^|]+") do
        local alternative = piece:match("^%s*(.-)%s*$")
        if alternative ~= "" then list[#list + 1] = alternative end
    end
    return list
end

local function PatternError(text)
    for _, alternative in ipairs(Alternatives(text)) do
        local ok, err = pcall(string.find, "", LowerPattern(alternative))
        if not ok then return err end
    end
end

local function TextMatches(op, value, name)
    name = (name or ""):lower()
    local plain = op == "contains" or op == "!contains"
    local found = false
    for _, alternative in ipairs(Alternatives(value)) do
        if plain then
            found = found or name:find(alternative:lower(), 1, true) ~= nil
        else
            local ok, position = pcall(string.find, name, LowerPattern(alternative))
            found = found or (ok and position ~= nil)
        end
    end
    if op:sub(1, 1) == "!" then return not found end
    return found
end

-- Item facts beyond class, subclass and quality that a sack line can test. The game gives these in its item info:
-- number fields compare with = < > and so on, pick fields choose from a list.
local EQUIP_SLOTS = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_ROBE",
    "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
    "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT",
    "INVTYPE_THROWN", "INVTYPE_RELIC", "INVTYPE_AMMO", "INVTYPE_BAG", "INVTYPE_QUIVER" }
local BIND_TYPES = { { 0, "Doesn't bind" }, { 1, "Bind on pickup" }, { 2, "Bind on equip" }, { 3, "Bind on use" },
    { 4, "Quest item" } }
local STATS = {
    ilvl = { text = "item level", kind = "number", get = function(item) return item.itemLevel end },
    level = { text = "required level", kind = "number", get = function(item) return item.minLevel end },
    stack = { text = "stack size", kind = "number", get = function(item) return item.stackMax end },
    price = { text = "sell price", kind = "money", get = function(item) return item.sellPrice end },
    equip = { text = "equip slot", kind = "pick", get = function(item) return item.equip end },
    bind = { text = "bind type", kind = "pick", get = function(item) return item.bindType end },
    reagent = { text = "crafting reagent", kind = "pick", get = function(item) return item.reagent end },
    bound = { text = "soulbound", kind = "pick", get = function(item) return item.bound end },
    family = { text = "special bag type", kind = "pick", get = function(item) return item.family end },
}
local Stat = {}
-- Which special bags take an item: the game's bag family bits (an item can fit more than one).
Stat.families = { { 1, "Arrows" }, { 2, "Bullets" }, { 4, "Soul shards" }, { 8, "Leatherworking" }, { 16, "Inscription" },
    { 32, "Herbs" }, { 64, "Enchanting" }, { 128, "Engineering" }, { 256, "Keys" }, { 512, "Gems" }, { 1024, "Mining" } }
Stat.bindShort = { [0] = "", "BoP", "BoE", "BoU", "Quest" }

function Stat.FamilyText(mask)
    local names = {}
    for _, entry in ipairs(Stat.families) do
        if BitAnd(mask or 0, entry[1]) ~= 0 then names[#names + 1] = entry[2] end
    end
    return table.concat(names, ", ")
end

function Stat.MoneyText(copper)
    copper = math.floor(tonumber(copper) or 0)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

-- "1g 50s", "75c", or a bare number (copper). Anything else is not a price.
function Stat.ParseMoney(text)
    text = (text or ""):lower():gsub("%s", "")
    if text == "" or text:gsub("%d+[gsc]?", "") ~= "" then return nil end
    local total = 0
    for amount, unit in text:gmatch("(%d+)([gsc]?)") do
        total = total + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    return total
end

function Stat.Parse(field, text)
    if STATS[field].kind == "money" then return Stat.ParseMoney(text) end
    return tonumber(text)
end

function Stat.Format(field, value)
    local stat = STATS[field]
    if stat.kind == "money" then return Stat.MoneyText(value) end
    if stat.kind == "number" then return tostring(value) end
    for _, option in ipairs(Stat.Options(field)) do
        if option.value == value then return option.label end
    end
    return tostring(value)
end

function Stat.Options(field)
    local options = {}
    if field == "equip" then
        options[1] = { label = "Not equippable", value = "NONE" }
        for _, token in ipairs(EQUIP_SLOTS) do
            options[#options + 1] = { label = _G[token] or token:sub(9):lower():gsub("^%l", string.upper), value = token }
        end
    elseif field == "bind" then
        for _, entry in ipairs(BIND_TYPES) do options[#options + 1] = { label = entry[2], value = entry[1] } end
    elseif field == "family" then
        for _, entry in ipairs(Stat.families) do options[#options + 1] = { label = entry[2], value = entry[1] } end
    else
        options = { { label = "Yes", value = 1 }, { label = "No", value = 0 } }
    end
    return options
end

local function ConditionMatches(condition, item)
    local field = condition.field
    if field == "class" then return Compare(condition.op, item.classID, condition.value) end
    if field == "sub" then
        if item.classID ~= condition.class then return condition.op == "~=" end
        return Compare(condition.op, item.subClassID, condition.value)
    end
    if field == "quality" then return Compare(condition.op, item.quality or 0, condition.value) end
    if field == "name" then return TextMatches(condition.op, condition.value, item.name) end
    if field == "item" then return Compare(condition.op, item.itemID, condition.value) end
    if field == "family" then
        local fits = BitAnd(item.family or 0, condition.value or 0) ~= 0
        if condition.op == "~=" then return not fits end
        return fits
    end
    if STATS[field] then return Compare(condition.op, STATS[field].get(item), condition.value) end
    return false
end

-- Conditions are joined by AND unless one says join = "OR". AND is applied first, so "A and B or C" means (A and B) or C.
local function Matches(rule, item)
    local groupHolds = true
    for index, condition in ipairs(rule) do
        if index > 1 and condition.join == "OR" then
            if groupHolds then return true end
            groupHolds = true
        end
        if groupHolds and not ConditionMatches(condition, item) then groupHolds = false end
    end
    return groupHolds
end

-- Rules saved by the first versions were a table of class=, sub=, minq=, maxq=, id=. This turns one into a list.
local function IsOldRule(rule)
    return rule.class ~= nil or rule.sub ~= nil or rule.minq ~= nil or rule.maxq ~= nil or rule.id ~= nil
end

local function ToConditions(old)
    local list = {}
    if old.class then list[#list + 1] = { field = "class", op = "=", value = old.class } end
    if old.sub then list[#list + 1] = { field = "sub", op = "=", class = old.class, value = old.sub } end
    if old.minq and old.minq == old.maxq then
        list[#list + 1] = { field = "quality", op = "=", value = old.minq }
    else
        if old.minq then list[#list + 1] = { field = "quality", op = ">=", value = old.minq } end
        if old.maxq then list[#list + 1] = { field = "quality", op = "<=", value = old.maxq } end
    end
    if old.id then list[#list + 1] = { field = "item", op = "=", value = old.id } end
    return list
end

-- Finds an id by name: an exact match wins, otherwise the first name that starts with the text.
-- Underscores stand for spaces, so sub=food_&_drink works, and so does just sub=food.
local function FindByName(text, names)
    text = text:lower():gsub("_", " ")
    local prefix
    for id, name in names do
        local lower = name:lower()
        if lower == text then return id end
        if not prefix and lower:sub(1, #text) == text then prefix = id end
    end
    return prefix
end

local function ScanNames(lookup)
    local id = -1
    return function()
        while id < SCAN_LIMIT do
            id = id + 1
            local name = lookup(id)
            if name and name ~= "" then return id, name end
        end
    end
end

local function ClassByName(text)
    return FindByName(text, ScanNames(ItemClassInfo))
end

local function SubClassByName(class, text)
    return FindByName(text, ScanNames(function(id) return ItemSubClassInfo(class, id) end))
end

local function QualityByName(text)
    local qualities = {}
    for name, value in pairs(Enum.ItemQuality) do qualities[value] = name end
    return FindByName(text, ScanNames(function(id) return qualities[id] end))
end

-- "class=Consumable sub=Potion quality=poor" -> rule table, or nil and a reason.
local function ParseRule(words)
    local rule = {}
    for _, word in ipairs(words) do
        local key, value = word:match("^(%w+)=(.+)$")
        if not key then return nil, "expected key=value, got '" .. word .. "'" end
        key = key:lower()
        if key == "class" then
            rule.class = tonumber(value) or ClassByName(value)
            if not rule.class then return nil, "no item class called '" .. value .. "' (see /sacks classes)" end
        elseif key == "sub" then
            if not rule.class then return nil, "give class= before sub=" end
            rule.sub = tonumber(value) or SubClassByName(rule.class, value)
            if not rule.sub then return nil, "no subclass called '" .. value .. "' (see /sacks classes)" end
        elseif key == "quality" or key == "minq" or key == "maxq" then
            local quality = tonumber(value) or QualityByName(value)
            if not quality then return nil, "no quality called '" .. value .. "'" end
            if key ~= "maxq" then rule.minq = quality end
            if key ~= "minq" then rule.maxq = quality end
        elseif key == "id" then
            rule.id = tonumber(value)
            if not rule.id then return nil, "id must be a number" end
        else
            return nil, "unknown criterion '" .. key .. "' (class, sub, quality, minq, maxq, id)"
        end
    end
    return rule
end

local function QualityName(quality)
    return _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
end

local FIELD_TEXT = { class = "class", sub = "subclass", quality = "quality", name = "name", item = "item" }
local OP_TEXT = {
    ["="] = "is", ["~="] = "is not", ["<"] = "is below", ["<="] = "is at most", [">"] = "is above",
    [">="] = "is at least", contains = "contains", ["!contains"] = "doesn't contain", matches = "matches pattern",
    ["!matches"] = "doesn't match",
}

local function ValueText(condition, rule)
    local field = condition.field
    if field == "class" then return tostring(ItemClassInfo(condition.value) or condition.value) end
    if field == "sub" then
        local text = tostring(ItemSubClassInfo(condition.class, condition.value) or condition.value)
        -- The class is only spelled out when no condition of this rule already names it.
        for _, other in ipairs(rule or {}) do
            if other.field == "class" and other.op == "=" and other.value == condition.class then return text end
        end
        return text .. " (" .. tostring(ItemClassInfo(condition.class) or condition.class) .. ")"
    end
    if field == "quality" then return QualityName(condition.value) end
    if field == "item" then
        local seen = SacksDB and SacksDB.seen and SacksDB.seen[condition.value]
        return seen and seen.name or ("item " .. tostring(condition.value))
    end
    if STATS[field] then return Stat.Format(field, condition.value) end
    return tostring(condition.value)
end

local function Describe(rule)
    local text = ""
    for index, condition in ipairs(rule) do
        if index > 1 then text = text .. (condition.join == "OR" and "  OR  " or " and ") end
        text = text .. (FIELD_TEXT[condition.field] or STATS[condition.field].text) .. " " .. OP_TEXT[condition.op] .. " " .. ValueText(condition, rule)
    end
    return text ~= "" and text or "everything else"
end

-- Starting sacks, built from the game's own enums. The first sack that matches an item gets it.
local function DefaultGroups()
    local groups = {}
    local function add(name, rule, x, y)
        groups[#groups + 1] = { name = name, rule = rule, point = "CENTER", x = x, y = y }
    end
    add("Quest", { { field = "class", op = "=", value = Enum.ItemClass.Questitem } }, -300, 200)
    add("Junk", { { field = "quality", op = "<=", value = Enum.ItemQuality.Poor } }, -300, 100)
    add("Consumables", { { field = "class", op = "=", value = Enum.ItemClass.Consumable } }, -300, 0)
    return groups
end

-- The last sack ("Other") is always there and has no conditions: it takes whatever no other sack wants. Because of it
-- every item in your bags is always shown somewhere. It can be laid out like any sack but not edited or removed.
local function AllGroups()
    local list = {}
    for _, group in ipairs(SacksDB.groups) do list[#list + 1] = group end
    list[#list + 1] = SacksDB.fallback
    return list
end

local function FindGroup(name)
    for index, group in ipairs(AllGroups()) do
        if group.name:lower() == (name or ""):lower() then return group, index end
    end
end

-- Older saves had "Other" as an ordinary sack with no conditions; it becomes the permanent last sack.
local function EnsureFallback()
    if not SacksDB.fallback then
        for index, group in ipairs(SacksDB.groups) do
            if #group.rule == 0 and group.name == OTHER_NAME then
                SacksDB.fallback = table.remove(SacksDB.groups, index)
                break
            end
        end
    end
    SacksDB.fallback = SacksDB.fallback or { name = OTHER_NAME, point = "CENTER", x = -300, y = -100 }
    SacksDB.fallback.rule = {}
    SacksDB.fallback.fixed = true
end

---------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------

local function MakeSlotButton(parent)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(SlotSize(), SlotSize())
    -- Right click uses the item (and sells it at a vendor). Left click and dragging pick it up, like the game's bags.
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type2", "item")
    button:SetScript("PreClick", function(self, mouse, down)
        if mouse == "LeftButton" and not down and self.bag then Container.PickupContainerItem(self.bag, self.slot) end
    end)
    button:SetScript("OnDragStart", function(self)
        if self.bag and not (CursorHasItem and CursorHasItem()) then Container.PickupContainerItem(self.bag, self.slot) end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        if self.bag then Container.PickupContainerItem(self.bag, self.slot) end
    end)
    button.back = button:CreateTexture(nil, "BACKGROUND")
    button.back:SetAllPoints()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
    -- A small square in the top corner: green when the item is in a special bag, amber when it fits a special bag
    -- that has room but sits in a normal bag, grey when it fits one that is full.
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetSize(7, 7)
    button.mark:SetPoint("TOPRIGHT", -2, -2)
    button.mark:Hide()
    button:SetScript("OnEnter", function(self)
        if self.bag then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(self.bag, self.slot)
            if self.where then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.where, self.whereColor[1], self.whereColor[2], self.whereColor[3], true)
                GameTooltip:Show()
            end
            -- At a vendor the game shows a coin cursor over what you can sell; do the same.
            local showSell = (C_Container and C_Container.ShowContainerSellCursor) or ShowContainerSellCursor
            if showSell and MerchantFrame and MerchantFrame:IsShown() then showSell(self.bag, self.slot) end
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    end)
    return button
end

-- Where each of the nine anchor points sits on a frame, as a fraction of its width (x) and height (y, from the bottom).
local POINT_FRACTION = {
    TOPLEFT = { x = 0, y = 1 }, TOP = { x = 0.5, y = 1 }, TOPRIGHT = { x = 1, y = 1 },
    LEFT = { x = 0, y = 0.5 }, CENTER = { x = 0.5, y = 0.5 }, RIGHT = { x = 1, y = 0.5 },
    BOTTOMLEFT = { x = 0, y = 0 }, BOTTOM = { x = 0.5, y = 0 }, BOTTOMRIGHT = { x = 1, y = 0 },
}

-- Moves a saved position from the point it was saved against to the corner the sack grows from, so the corner
-- stays put when the sack gets bigger or smaller.
local function MoveToCorner(group, frame)
    local corner = group.anchor or DEFAULT_ANCHOR
    local from, to = POINT_FRACTION[group.point or "CENTER"], POINT_FRACTION[corner]
    group.x = (group.x or 0) + (to.x - from.x) * frame:GetWidth()
    group.y = (group.y or 0) + (to.y - from.y) * frame:GetHeight()
    group.point = corner
end

local function SavePosition(group, frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    group.point, group.relPoint, group.x, group.y, group.relativeTo = point, relPoint, x, y, nil
    MoveToCorner(group, frame)
end

-- How a sack is laid out: its own settings, also while a vendor window is open.
local function LayoutOf(group)
    return { anchor = group.anchor or DEFAULT_ANCHOR, flow = group.flow or DEFAULT_FLOW,
        title = group.title or DEFAULT_TITLE, wrap = group.cols or SacksDB.columns or DEFAULT_COLUMNS }
end

local BeginSackDrag, EndSackDrag
-- Dragging a sack snaps its edges to the screen edges and to other sacks (hold Alt to drag freely), so sacks
-- can be tucked against each other and moved aside without gaps or overlap.
local SNAP_DISTANCE = 14
local SNAP_GAP = 2

local function SnapAxis(low, size, targets)
    local best, bestDistance = 0, SNAP_DISTANCE + 1
    for _, target in ipairs(targets) do
        for _, shift in ipairs({ target.low - low, target.high - (low + size),
                                 target.high + SNAP_GAP - low, target.low - SNAP_GAP - (low + size) }) do
            if math.abs(shift) < bestDistance then best, bestDistance = shift, math.abs(shift) end
        end
    end
    if bestDistance <= SNAP_DISTANCE then return best end
    return 0
end

local function SnapPosition(frame, left, bottom)
    local width, height = frame:GetWidth(), frame:GetHeight()
    local xs, ys = { { low = 0, high = UIParent:GetWidth() } }, { { low = 0, high = UIParent:GetHeight() } }
    for _, other in pairs(state.frames) do
        if other ~= frame and other:IsShown() then
            local ol, ob, ow, oh = other:GetLeft(), other:GetBottom(), other:GetWidth(), other:GetHeight()
            if type(ol) == "number" and type(ob) == "number" and type(ow) == "number" and type(oh) == "number" then
                -- Only snap along an axis to sacks that are actually next to us on the other axis.
                local nearY = bottom < ob + oh + SNAP_DISTANCE and bottom + height > ob - SNAP_DISTANCE
                local nearX = left < ol + ow + SNAP_DISTANCE and left + width > ol - SNAP_DISTANCE
                if nearY then xs[#xs + 1] = { low = ol, high = ol + ow } end
                if nearX then ys[#ys + 1] = { low = ob, high = ob + oh } end
            end
        end
    end
    return left + SnapAxis(left, width, xs), bottom + SnapAxis(bottom, height, ys)
end

-- A sack dropped right against another one is docked to it: it stays against that sack when either changes size.
-- The saved dock says which sack, which side, and how far along that side, measured from the corner the sack grows from.

local function DockOf(group, frame)
    local left, bottom, width, height = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not (type(left) == "number" and type(bottom) == "number") then return nil end
    local anchor = group.anchor or DEFAULT_ANCHOR
    local fromRight = anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT"
    local fromBottom = anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT"
    local function near(a, b) return math.abs(a - b) <= 1.5 end
    for other, otherFrame in pairs(state.frames) do
        if other ~= group and otherFrame:IsShown() then
            local ol, ob, ow, oh = otherFrame:GetLeft(), otherFrame:GetBottom(), otherFrame:GetWidth(), otherFrame:GetHeight()
            if type(ol) == "number" and type(ob) == "number" and type(ow) == "number" and type(oh) == "number" then
                local overlapY = bottom < ob + oh and bottom + height > ob
                local overlapX = left < ol + ow and left + width > ol
                local alongY = fromBottom and (bottom - ob) or ((bottom + height) - (ob + oh))
                local alongX = fromRight and ((left + width) - (ol + ow)) or (left - ol)
                -- If the two edges along the shared side line up, the dock keeps THOSE edges lined up, whichever way
                -- the sack grows. Otherwise it keeps the corner the sack grows from.
                local function alongVertical()
                    if near(bottom, ob) then return { edge = "BOTTOM", offset = 0 } end
                    if near(bottom + height, ob + oh) then return { edge = "TOP", offset = 0 } end
                    return { offset = alongY }
                end
                local function alongHorizontal()
                    if near(left, ol) then return { edge = "LEFT", offset = 0 } end
                    if near(left + width, ol + ow) then return { edge = "RIGHT", offset = 0 } end
                    return { offset = alongX }
                end
                local dock
                if overlapY and near(left, ol + ow + SNAP_GAP) then dock = alongVertical(); dock.side = "RIGHT"
                elseif overlapY and near(left + width, ol - SNAP_GAP) then dock = alongVertical(); dock.side = "LEFT"
                elseif overlapX and near(bottom, ob + oh + SNAP_GAP) then dock = alongHorizontal(); dock.side = "TOP"
                elseif overlapX and near(bottom + height, ob - SNAP_GAP) then dock = alongHorizontal(); dock.side = "BOTTOM" end
                if dock then dock.to = other.name; return dock end
            end
        end
    end
end

function BeginSackDrag(frame)
    local scale = frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not (scale and cx and left and bottom) then
        frame:StartMoving()
        return
    end
    local grabX, grabY = cx / scale - left, cy / scale - bottom
    frame.dragging = true
    frame:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local newLeft, newBottom = x / scale - grabX, y / scale - grabY
        if not (IsAltKeyDown and IsAltKeyDown()) then newLeft, newBottom = SnapPosition(self, newLeft, newBottom) end
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
    end)
end

function EndSackDrag(frame)
    if frame.dragging then
        frame.dragging = nil
        frame:SetScript("OnUpdate", nil)
    else
        frame:StopMovingOrSizing()
    end
end

-- Dropping an item on a free-slots box puts it in the first free slot of a normal bag.
local function DropIntoFreeSlot()
    if not (CursorHasItem and CursorHasItem()) then return end
    for bag = 0, LastBag() do
        local free, bagType = Container.GetContainerNumFreeSlots(bag)
        if (bagType or 0) == 0 and (free or 0) > 0 then
            for slot = 1, Container.GetContainerNumSlots(bag) do
                if Container.GetContainerItemInfo(bag, slot) == nil then
                    Container.PickupContainerItem(bag, slot)
                    return
                end
            end
        end
    end
end

-- Hovering a free-slots box lists every bag, so the free slots in special bags are never hidden from you.
local function ShowFreeTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Free slots")
    for _, bag in ipairs(state.bags or {}) do
        GameTooltip:AddDoubleLine(bag.name .. (bag.special and " (special)" or ""),
            bag.free .. " / " .. bag.total, 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine("The number counts normal bags. A +number counts special bags, which only take some items.",
        0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

-- Where a sack's empty slot goes: its own setting, else the default for every sack, else after the items.
-- Only the Other sack has the empty slot (it is the one that always exists); the rest never show one.
local function BlankMode(group)
    if not group.fixed then return "NONE" end
    return group.blank or "LAST"
end

-- Titles are a template: {name} {count} {items} {value} {free} {special} are filled in from what the sack holds.
local TITLE_DEFAULT = "{name} ({count})"
local TITLE_PIECES = {
    { token = "{name}", about = "the sack's name" },
    { token = "{count}", about = "kinds of item in it" },
    { token = "{items}", about = "total items, counting stacks" },
    { token = "{value}", about = "vendor sell value of all of it" },
    { token = "{free}", about = "free slots in normal bags" },
    { token = "{special}", about = "free slots in special bags" },
}

local function Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local text = ""
    if gold > 0 then text = text .. gold .. "|cffffd700g|r " end
    if silver > 0 or gold > 0 then text = text .. silver .. "|cffc7c7cfs|r " end
    return text .. rest .. "|cffeda55fc|r"
end

local function ExpandTitle(group, items, free, special)
    local stacks, value = 0, 0
    for _, item in ipairs(items) do
        local count = item.count or 1
        stacks = stacks + count
        value = value + (item.sellPrice or 0) * count
    end
    local pieces = { name = group.name, count = #items, items = stacks, value = Money(value), free = free, special = special }
    local template = group.titleText or TITLE_DEFAULT
    return (template:gsub("{(%w+)}", function(token)
        local found = pieces[token:lower()]
        if found ~= nil then return tostring(found) end
    end))
end

-- Ends a drag: remembers where the box went and which box, if any, it is now docked against.
local function FinishDrag(group, frame)
    EndSackDrag(frame)
    if state.vendor then return end
    SavePosition(group, frame)
    local before = group.dock
    group.dock = DockOf(group, frame)
    local changed = (before and before.to) ~= (group.dock and group.dock.to)
        or (before and before.side) ~= (group.dock and group.dock.side)
    -- Boxes docked to this one are re-anchored to it, so they come along.
    if (group.dock or before or changed) and state.refresh then state.refresh() end
end

local function MakeGroupFrame(group)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints()
    frame.back:SetColorTexture(0, 0, 0, 0.45)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.handle = CreateFrame("Frame", nil, frame)
    frame.handle:EnableMouse(true)
    frame.handle:RegisterForDrag("LeftButton")
    frame.handle:SetScript("OnDragStart", function()
        if state.vendor then return end
        -- Without a title the whole sack is the handle, and it takes shift to avoid dragging one by accident.
        if group.title == "NONE" and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        BeginSackDrag(frame)
    end)
    frame.handle:SetScript("OnDragStop", function() FinishDrag(group, frame) end)
    -- A title too long for the sack ends in "..."; hovering it shows the whole thing.
    frame.handle:SetScript("OnEnter", function(self)
        local full = state.titles[group]
        if full and frame.title.IsTruncated and frame.title:IsTruncated() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(full)
            GameTooltip:Show()
        end
    end)
    frame.handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.blank = CreateFrame("Frame", nil, frame)
    frame.blank:SetSize(SlotSize(), SlotSize())
    frame.blank.back = frame.blank:CreateTexture(nil, "BACKGROUND")
    frame.blank.back:SetAllPoints()
    frame.blank.back:SetColorTexture(1, 1, 1, 0.08)
    frame.blank.text = frame.blank:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.blank.text:SetPoint("CENTER")
    frame.blank.extra = frame.blank:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.blank.extra:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.blank:EnableMouse(true)
    frame.blank:SetScript("OnMouseUp", DropIntoFreeSlot)
    frame.blank:SetScript("OnReceiveDrag", DropIntoFreeSlot)
    frame.blank:SetScript("OnEnter", ShowFreeTooltip)
    frame.blank:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.buttons = {}
    return frame
end

-- Which cell of the grid an item goes in: filling across then wrapping, or down then wrapping.
local function GridCell(index, layout)
    if layout.flow == "COLUMNS" then
        return math.floor((index - 1) / layout.wrap), (index - 1) % layout.wrap
    end
    return (index - 1) % layout.wrap, math.floor((index - 1) / layout.wrap)
end

local function FillGroup(group, items, free, special)
    local frame = state.frames[group] or MakeGroupFrame(group)
    state.frames[group] = frame
    local layout = LayoutOf(group)
    local size = SlotSize()
    -- The blank slot (it counts the free bag slots) goes last, first, or nowhere, per sack.
    local blankMode = BlankMode(group)
    local hasBlank = blankMode ~= "NONE"
    local shift = blankMode == "FIRST" and 1 or 0
    local cells = math.max(1, #items + (hasBlank and 1 or 0))
    local columns, rows
    if layout.flow == "COLUMNS" then
        rows = math.min(layout.wrap, cells)
        columns = math.ceil(cells / layout.wrap)
    else
        columns = math.min(layout.wrap, cells)
        rows = math.ceil(cells / layout.wrap)
    end
    local topSpace = layout.title == "TOP" and TITLE_HEIGHT or PADDING
    local bottomSpace = layout.title == "BOTTOM" and TITLE_HEIGHT or PADDING
    local width = PADDING * 2 + columns * size + (columns - 1) * SLOT_GAP
    local height = topSpace + rows * size + (rows - 1) * SLOT_GAP + bottomSpace
    frame:SetSize(width, height)

    -- The first cell is next to the corner the sack grows from.
    local fromRight = layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT"
    local fromBottom = layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT"
    local function place(frameToPlace, index)
        local column, row = GridCell(index, layout)
        local x = column * (size + SLOT_GAP)
        local y = row * (size + SLOT_GAP)
        x = fromRight and (width - PADDING - size - x) or (PADDING + x)
        y = fromBottom and (height - bottomSpace - size - y) or (topSpace + y)
        frameToPlace:ClearAllPoints()
        frameToPlace:SetPoint("TOPLEFT", x, -y)
    end

    frame.title:ClearAllPoints()
    frame.handle:ClearAllPoints()
    if layout.title == "NONE" then
        frame.title:Hide()
        frame.handle:SetAllPoints()
    else
        frame.title:Show()
        local titleText = ExpandTitle(group, items, free, special)
        state.titles[group] = titleText
        frame.title:SetWidth(math.max(12, width - PADDING * 2))
        if frame.title.SetWordWrap then frame.title:SetWordWrap(false) end
        if frame.title.SetJustifyH then frame.title:SetJustifyH("LEFT") end
        frame.title:SetText(titleText)
        local edge = layout.title == "TOP" and "TOP" or "BOTTOM"
        frame.title:SetPoint(edge .. "LEFT", PADDING, layout.title == "TOP" and -3 or 3)
        frame.handle:SetPoint(edge .. "LEFT")
        frame.handle:SetPoint(edge .. "RIGHT")
        frame.handle:SetHeight(TITLE_HEIGHT)
    end

    for index, item in ipairs(items) do
        local button = frame.buttons[index] or MakeSlotButton(frame)
        frame.buttons[index] = button
        button:SetSize(size, size)
        button.bag, button.slot = item.bag, item.slot
        button:SetAttribute("item", item.bag .. " " .. item.slot)
        button.icon:SetTexture(item.icon)
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
        if color then button.back:SetColorTexture(color.r, color.g, color.b, 0.45) else button.back:SetColorTexture(0, 0, 0, 0.3) end
        button.count:SetText((item.count or 1) > 1 and item.count or "")
        if item.inSpecial then
            button.where, button.whereColor = "In your " .. item.bagName .. " (special bag).", { 0.4, 1, 0.4 }
            button.mark:SetColorTexture(0.2, 1, 0.2, 1)
            button.mark:Show()
        elseif item.fitsBag then
            if (item.fitsFree or 0) > 0 then
                button.where = "In " .. item.bagName .. ", but it fits your " .. item.fitsBag .. ", which has "
                    .. item.fitsFree .. " free slot" .. (item.fitsFree == 1 and "" or "s") .. ". Move it there."
                button.whereColor = { 1, 0.7, 0.1 }
                button.mark:SetColorTexture(1, 0.7, 0.1, 1)
            else
                button.where = "In " .. item.bagName .. ". It fits your " .. item.fitsBag .. ", but that is full."
                button.whereColor = { 0.7, 0.7, 0.7 }
                button.mark:SetColorTexture(0.6, 0.6, 0.6, 1)
            end
            button.mark:Show()
        else
            button.where, button.whereColor = "In " .. item.bagName .. ".", { 0.7, 0.7, 0.7 }
            button.mark:Hide()
        end
        place(button, index + shift)
        button:Show()
    end
    for index = #items + 1, #frame.buttons do
        frame.buttons[index].bag = nil
        frame.buttons[index]:Hide()
    end

    frame.blank:SetSize(size, size)
    if hasBlank then
        place(frame.blank, blankMode == "FIRST" and 1 or #items + 1)
        frame.blank:Show()
    else
        frame.blank:Hide()
    end
    frame.blank.text:SetText(free)
    if free > 0 then frame.blank.text:SetTextColor(1, 0.82, 0) else frame.blank.text:SetTextColor(1, 0.2, 0.2) end
    frame.blank.extra:SetText(special > 0 and ("+" .. special) or "")
    frame.blank.extra:SetTextColor(0.4, 1, 0.4)
end

-- The sack this one is docked to, if that sack still exists and the docks don't loop back around to this one.
-- A sack, or the free-slots box, by name.
local function FindDockable(name)
    local widget = SacksDB.widget
    return FindGroup(name) or (widget and widget.name == name and widget or nil)
end

local function DockTarget(group)
    local dock = group.dock
    if not dock then return nil end
    local target = FindDockable(dock.to)
    if not target or target == group or not state.frames[target] then return nil end
    local walk, steps = target, 0
    while walk and walk.dock and steps < 20 do
        walk = FindDockable(walk.dock.to)
        if walk == group then return nil end
        steps = steps + 1
    end
    return target
end

-- Puts one box where it belongs: against the box it is docked to, or at its saved position.
local function PlaceOne(group, frame)
    if not group.relativeTo and group.point ~= (group.anchor or DEFAULT_ANCHOR) then MoveToCorner(group, frame) end
    local target = DockTarget(group)
    if target then
        local anchor = group.anchor or DEFAULT_ANCHOR
        local v = (anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT") and "BOTTOM" or "TOP"
        local h = (anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT") and "RIGHT" or "LEFT"
        local side, offset, gap = group.dock.side, group.dock.offset or 0, SNAP_GAP
        local edge = group.dock.edge
        if edge == "TOP" or edge == "BOTTOM" then v = edge elseif edge == "LEFT" or edge == "RIGHT" then h = edge end
        local mine, theirs, x, y
        if side == "RIGHT" then mine, theirs, x, y = v .. "LEFT", v .. "RIGHT", gap, offset
        elseif side == "LEFT" then mine, theirs, x, y = v .. "RIGHT", v .. "LEFT", -gap, offset
        elseif side == "TOP" then mine, theirs, x, y = "BOTTOM" .. h, "TOP" .. h, offset, gap
        else mine, theirs, x, y = "TOP" .. h, "BOTTOM" .. h, offset, -gap end
        frame:SetPoint(mine, state.frames[target], theirs, x, y)
    else
        local relativeTo = group.relativeTo and _G[group.relativeTo] or UIParent
        frame:SetPoint(group.point or DEFAULT_ANCHOR, relativeTo, group.relPoint or group.point or DEFAULT_ANCHOR,
            group.x or 0, group.y or 0)
    end
end

local function PlaceGroups()
    local groups = AllGroups()
    -- Every anchor is dropped first. A sack that was stacked at a vendor is anchored to another sack, and putting
    -- it back while that stale anchor is still there can make two sacks depend on each other, which the game refuses.
    for _, group in ipairs(groups) do state.frames[group]:ClearAllPoints() end
    local vendor = state.vendor and MerchantFrame
    local limit = vendor and tonumber(MerchantFrame:GetHeight()) or 0
    local placed = {}
    -- Finds the spot for a box of this size: as far left as it fits, and as high as it fits there. Candidate spots are
    -- the top corner, below each placed box, and beside each placed box, so a box slips into the gap beside narrow ones.
    local function FindSpot(width, height)
        local spots = { { 0, 0 } }
        for _, box in ipairs(placed) do
            spots[#spots + 1] = { box.x, box.y + box.height + SLOT_GAP }
            spots[#spots + 1] = { box.x + box.width + SLOT_GAP, box.y }
        end
        local bestX, bestY
        for _, spot in ipairs(spots) do
            local x, y, free = spot[1], spot[2], true
            if y > 0 and y + height > limit then free = false end
            for _, box in ipairs(placed) do
                if free and x < box.x + box.width + SLOT_GAP and x + width + SLOT_GAP > box.x
                    and y < box.y + box.height + SLOT_GAP and y + height + SLOT_GAP > box.y then free = false end
            end
            if free and (not bestX or x < bestX or (x == bestX and y < bestY)) then bestX, bestY = x, y end
        end
        if bestX then return bestX, bestY end
        -- Nothing fits inside the window's height: start a new column past everything placed so far.
        local right = 0
        for _, box in ipairs(placed) do right = math.max(right, box.x + box.width + SLOT_GAP) end
        return right, 0
    end
    for _, group in ipairs(groups) do
        local frame = state.frames[group]
        -- An empty sack stays on screen (title and an empty box) so you can still see and move it; only a sack with
        -- nothing at all to show (no items, no empty slot, no title) goes away.
        local hidden = BlankMode(group) == "NONE" and group.title == "NONE" and (state.counts[group] or 0) == 0
        if vendor then
            -- Beside the vendor window, in sack-list order, filling downward to the window's height. A box that no
            -- longer fits below goes into free space beside the narrower boxes, or into a new column.
            if not hidden then
                local height, width = tonumber(frame:GetHeight()) or 0, tonumber(frame:GetWidth()) or 0
                local x, y = FindSpot(width, height)
                frame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", PADDING + x, -y)
                placed[#placed + 1] = { x = x, y = y, width = width, height = height }
            end
        else
            PlaceOne(group, frame)
        end
        if hidden then frame:Hide() else frame:Show() end
    end
end

-- The order inside a sack: pinned items first (in the order they were pinned), then each sort key in turn, then the
-- bag position so the order never flickers.
local SORT_KEYS = {
    name = { label = "Name", value = function(item) return item.name:lower() end },
    class = { label = "Class", value = function(item) return item.classID or -1 end },
    sub = { label = "Subclass", value = function(item) return item.subClassID or -1 end },
    quality = { label = "Quality", value = function(item) return item.quality end },
    count = { label = "Stack size", value = function(item) return item.count or 1 end },
    position = { label = "Bag position", value = function(item) return item.bag end },
}
local SORT_KEY_ORDER = { "name", "class", "sub", "quality", "count", "position" }

local function SortItems(group, items)
    local rank = {}
    for index, id in ipairs(group.pins or {}) do rank[id] = index end
    local keys = group.sort or DEFAULT_SORT
    table.sort(items, function(a, b)
        local rankA, rankB = rank[a.itemID] or math.huge, rank[b.itemID] or math.huge
        if rankA ~= rankB then return rankA < rankB end
        for _, spec in ipairs(keys) do
            local key = SORT_KEYS[spec.key]
            if key then
                local left, right = key.value(a), key.value(b)
                if left ~= right then
                    if spec.descending then return left > right end
                    return left < right
                end
            end
        end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
end

-- An optional box of its own that shows the free slots, to put anywhere (or dock against a sack).
local function WidgetGroup()
    SacksDB.widget = SacksDB.widget or { name = "Free slots", shown = false, point = "CENTER", x = 0, y = -220 }
    return SacksDB.widget
end

local function MakeWidget(group)
    local frame = CreateFrame("Frame", "SacksFreeWidget", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints()
    frame.back:SetColorTexture(0, 0, 0, 0.45)
    frame.slot = frame:CreateTexture(nil, "ARTWORK")
    frame.slot:SetColorTexture(1, 1, 1, 0.08)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER")
    frame.extra = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.extra:SetTextColor(0.4, 1, 0.4)
    frame:SetScript("OnDragStart", function()
        if not state.vendor then BeginSackDrag(frame) end
    end)
    frame:SetScript("OnDragStop", function() FinishDrag(group, frame) end)
    frame:SetScript("OnMouseUp", DropIntoFreeSlot)
    frame:SetScript("OnReceiveDrag", DropIntoFreeSlot)
    frame:SetScript("OnEnter", ShowFreeTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

local function UpdateWidget(free, special)
    local group = WidgetGroup()
    local frame = state.frames[group]
    if not group.shown then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = MakeWidget(group)
        state.frames[group] = frame
    end
    local size = SlotSize()
    frame:SetSize(size + PADDING * 2, size + PADDING * 2)
    frame.slot:ClearAllPoints()
    frame.slot:SetSize(size, size)
    frame.slot:SetPoint("CENTER")
    frame.extra:ClearAllPoints()
    frame.extra:SetPoint("BOTTOMRIGHT", frame.slot, "BOTTOMRIGHT", -2, 2)
    frame.text:SetText(free)
    if free > 0 then frame.text:SetTextColor(1, 0.82, 0) else frame.text:SetTextColor(1, 0.2, 0.2) end
    frame.extra:SetText(special > 0 and ("+" .. special) or "")
    if not state.vendor then
        frame:ClearAllPoints()
        PlaceOne(group, frame)
    end
    frame:Show()
end

local function Refresh()
    if not SacksDB then return end
    if InCombatLockdown() then
        state.pending = true -- secure buttons can't be changed in combat; redo it when combat ends
        if RefreshSettings then pcall(RefreshSettings) end
        return
    end
    state.pending = false
    local items, free, special = ReadBags()
    state.items = items
    SacksDB.seen = SacksDB.seen or {}
    for _, item in ipairs(items) do
        if item.itemID then
            SacksDB.seen[item.itemID] = { name = item.name, icon = item.icon, classID = item.classID,
                subClassID = item.subClassID, quality = item.quality, sellPrice = item.sellPrice,
                itemLevel = item.itemLevel, minLevel = item.minLevel, stackMax = item.stackMax, equip = item.equip,
                bindType = item.bindType, reagent = item.reagent, bound = item.bound, family = item.family }
        end
    end
    -- The last sack takes whatever no other sack wants, so every item in your bags is always on screen somewhere.
    local groups = AllGroups()
    local sorted = {}
    for _, group in ipairs(groups) do sorted[group] = {} end
    for _, item in ipairs(items) do
        for _, group in ipairs(groups) do
            if (group.fixed or #group.rule > 0) and Matches(group.rule, item) then
                table.insert(sorted[group], item)
                break
            end
        end
    end
    state.shown = 0
    for _, group in ipairs(groups) do
        SortItems(group, sorted[group])
        if group.reverse then
            local list, count = sorted[group], #sorted[group]
            for index = 1, math.floor(count / 2) do list[index], list[count - index + 1] = list[count - index + 1], list[index] end
        end
        state.counts[group] = #sorted[group]
        state.shown = state.shown + #sorted[group]
        FillGroup(group, sorted[group], free, special)
    end
    PlaceGroups()
    UpdateWidget(free, special)
    if RefreshSettings then pcall(RefreshSettings) end
end
state.refresh = Refresh

local function HideRemoved(group)
    if state.frames[group] then state.frames[group]:Hide() end
end

---------------------------------------------------------------------------------------------------
-- The game's own bags: hidden whenever they open, unless you turn that off in the settings
---------------------------------------------------------------------------------------------------

local function OwnBagFrames()
    local frames = { ContainerFrameCombinedBags }
    local index = 1
    while _G["ContainerFrame" .. index] do
        frames[#frames + 1] = _G["ContainerFrame" .. index]
        index = index + 1
    end
    return frames
end

local function OwnBagsShown()
    for _, frame in ipairs(OwnBagFrames()) do
        if frame:IsShown() then return true end
    end
    return false
end

-- They stay open when you opened them yourself (see ToggleOwnBags) and while the bank is open, since the bank's
-- own bags use the same windows.
local function HideOwnBags()
    if SacksDB.hideBags == false or InCombatLockdown() or state.ownBagsAllowed or state.userBags then return end
    if state.bank or (BankFrame and BankFrame:IsShown()) then return end
    for _, frame in ipairs(OwnBagFrames()) do
        if frame:IsShown() then pcall(frame.Hide, frame) end
    end
end

-- Opens or closes the game's own bags on purpose, so you can check them against the sacks.
local function ToggleOwnBags()
    if OwnBagsShown() then
        state.ownBagsAllowed = false
        if CloseAllBags then
            pcall(CloseAllBags)
        else
            for _, frame in ipairs(OwnBagFrames()) do pcall(frame.Hide, frame) end
        end
    else
        state.ownBagsAllowed = true
        local open = OpenAllBags or ToggleAllBags
        if open then pcall(open) end
    end
end

local hooked = {}
local function HookOwnBags()
    for _, frame in ipairs(OwnBagFrames()) do
        if not hooked[frame] then
            hooked[frame] = true
            frame:HookScript("OnShow", HideOwnBags)
            frame:HookScript("OnHide", function()
                if not OwnBagsShown() then state.ownBagsAllowed = false end
            end)
        end
    end
end

-- The game opens its own bags by itself at vendors, mail and so on. Those are blocked; B and the bag buttons go
-- through these three functions, so anything they open is the player's own doing and is left open.
local function WrapUserBagToggles()
    for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
        local original = _G[name]
        if type(original) == "function" and not state.wrapped then
            _G[name] = function(...)
                state.userBags = true
                local results = { pcall(original, ...) }
                state.userBags = false
                if OwnBagsShown() then state.ownBagsAllowed = true end
                if not results[1] then error(results[2], 0) end
                return unpack(results, 2)
            end
        end
    end
    state.wrapped = true
end

---------------------------------------------------------------------------------------------------
-- Probe window (kept so you can see exactly what the client reports for your bags)
---------------------------------------------------------------------------------------------------

local textWindow
local function ShowText(text)
    if not textWindow then
        textWindow = CreateFrame("Frame", "SacksTextWindow", UIParent)
        textWindow:SetSize(640, 420)
        textWindow:SetPoint("CENTER")
        textWindow:SetFrameStrata("DIALOG")
        textWindow:EnableMouse(true)
        textWindow:SetMovable(true)
        textWindow:RegisterForDrag("LeftButton")
        textWindow:SetScript("OnDragStart", textWindow.StartMoving)
        textWindow:SetScript("OnDragStop", textWindow.StopMovingOrSizing)
        local back = textWindow:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0, 0, 0, 0.85)
        local scroll = CreateFrame("ScrollFrame", "SacksTextScroll", textWindow, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -12)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(590)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() textWindow:Hide() end)
        scroll:SetScrollChild(edit)
        textWindow.edit = edit
    end
    textWindow.edit:SetText(text)
    textWindow.edit:HighlightText()
    textWindow:Show()
    textWindow.edit:SetFocus()
end

local function ShowLines(lines)
    if not pcall(ShowText, table.concat(lines, "\n")) then
        for _, line in ipairs(lines) do print(line) end
    end
end

local function ProbeLines()
    local lines = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = Container.GetContainerNumSlots(bag) or 0
        if slots > 0 then
            local free, bagType = Container.GetContainerNumFreeSlots(bag)
            lines[#lines + 1] = string.format("bag %d  slots %d  free %s  bagType %s", bag, slots, tostring(free),
                tostring(bagType))
            for slot = 1, slots do
                local e = ReadSlot(bag, slot)
                if e then
                    lines[#lines + 1] = string.format("  %d.%-2d  id %-7s class %-4s sub %-4s q %-2s x%-3s %s",
                        bag, slot, tostring(e.itemID), tostring(e.classID), tostring(e.subClassID),
                        tostring(e.quality), tostring(e.count), tostring(e.name))
                end
            end
        end
    end
    return lines
end

local function ClassLines()
    local lines = {}
    for id = 0, SCAN_LIMIT do
        local name = ItemClassInfo(id)
        if name then
            local subs = {}
            for sub = 0, SCAN_LIMIT do
                local subName = ItemSubClassInfo(id, sub)
                if subName and subName ~= "" then subs[#subs + 1] = subName end
            end
            lines[#lines + 1] = string.format("%d %s: %s", id, name, table.concat(subs, ", "))
        end
    end
    return lines
end

---------------------------------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------------------------------

local HELP = {
    "/sacks - open the settings window (or click the bag icon)",
    "/sacks list - show every sack and what it takes",
    "/sacks new <name> class=.. sub=.. quality=.. minq=.. maxq=.. id=.. - make a sack; the newest sack is checked first",
    "/sacks remove <name>",
    "/sacks cols <name or all> <number> - how many slots per row; all sets the default for every sack",
    "/sacks anchor <name> <frame> - pin a sack to a named frame (e.g. MinimapCluster); drag its title bar to unpin",
    "/sacks classes - the item classes and subclasses you can use",
    "/sacks fields - every detail the game gives for the item under the mouse (or /sacks fields [item link])",
    "/sacks probe - list every item in your bags with its class, subclass and quality",
    "/sacks bags - open or close the game's own bags",
    "/sacks reset - back to the starting sacks",
    "Drag a sack by its title bar to move it.",
}

local function Words(text)
    local words = {}
    for word in (text or ""):gmatch("%S+") do words[#words + 1] = word end
    return words
end

local commands = {}

function commands.list()
    for _, group in ipairs(AllGroups()) do
        Say(string.format("%s (%d items): %s", group.name, state.counts[group] or 0, Describe(group.rule)))
    end
end

function commands.new(args)
    local name = table.remove(args, 1)
    if not name then return Say("give the sack a name: /sacks new <name> class=.. ...") end
    if FindGroup(name) then return Say("there is already a sack called " .. name) end
    local rule, reason = ParseRule(args)
    if not rule then return Say(reason) end
    rule = ToConditions(rule)
    table.insert(SacksDB.groups, 1, { name = name, rule = rule, point = "CENTER", x = 0, y = 0 })
    Say("made " .. name .. ": " .. Describe(rule))
    Refresh()
end

function commands.remove(args)
    local group, index = FindGroup(args[1])
    if not group then return Say("no sack called " .. tostring(args[1])) end
    if group.fixed then return Say(group.name .. " can't be removed: it keeps every item in your bags on screen") end
    table.remove(SacksDB.groups, index)
    HideRemoved(group)
    Refresh()
end

function commands.cols(args)
    local columns = tonumber(args[2])
    if not args[1] or not columns or columns < 1 then
        return Say("usage: /sacks cols <name or all> <number>")
    end
    columns = math.floor(columns)
    if args[1]:lower() == "all" then
        SacksDB.columns = columns -- the default for every sack without its own number
    else
        local group = FindGroup(args[1])
        if not group then return Say("no sack called " .. args[1]) end
        group.cols = columns
    end
    Refresh()
end

function commands.anchor(args)
    local group = FindGroup(args[1])
    if not group or not args[2] then return Say("usage: /sacks anchor <name> <frame>") end
    if not _G[args[2]] then return Say("no frame called " .. args[2]) end
    group.relativeTo, group.point, group.relPoint, group.x, group.y = args[2], "TOPLEFT", "BOTTOMLEFT", 0, -SLOT_GAP
    Refresh()
end

function commands.classes() ShowLines(ClassLines()) end

function commands.bags() ToggleOwnBags() end

function commands.probe()
    local ok, lines = pcall(ProbeLines)
    if ok then ShowLines(lines) else Say("probe failed: " .. tostring(lines)) end
end

function commands.reset()
    for _, group in ipairs(SacksDB.groups) do HideRemoved(group) end
    SacksDB.groups = DefaultGroups()
    Refresh()
end

local ITEM_FIELD_NAMES = { "name", "link", "quality", "itemLevel", "minLevel", "type", "subType", "stackCount", "equipLoc",
    "texture", "sellPrice", "classID", "subclassID", "bindType", "expansionID", "setID", "isCraftingReagent", "description" }

-- Prints everything this client says about one item, so we can see which fields exist and are filled in.
function commands.fields(args)
    local target = #args > 0 and table.concat(args, " ") or nil
    if not target and GetCursorInfo then
        local kind, id, link = GetCursorInfo()
        if kind == "item" then target = link or id end
    end
    if not target and GameTooltip and GameTooltip.GetItem then
        local _, link = GameTooltip:GetItem()
        target = link
    end
    local id = target and (tonumber(target) or tonumber(tostring(target):match("item:(%d+)")))
    if not id then
        Say("hover an item (or hold it on the cursor) and type /sacks fields, or: /sacks fields [shift-click an item]")
        return
    end
    local ref = "item:" .. id
    local values = { ItemInfo(ref) }
    local count = select("#", ItemInfo(ref))
    Say(string.format("item %d: GetItemInfo returned %d values", id, count))
    for index = 1, math.max(count, #values) do
        local value = values[index]
        if index == 2 and value then value = "(link)" end
        Say(string.format("  %d %s = %s", index, ITEM_FIELD_NAMES[index] or "(unknown)", tostring(value)))
    end
    local instant = Item.GetItemInfoInstant or GetItemInfoInstant
    if instant then
        local list = { instant(ref) }
        for index = 1, #list do list[index] = tostring(list[index]) end
        Say("GetItemInfoInstant: " .. table.concat(list, ", "))
    end
    local family = GetItemFamily or (C_Item and C_Item.GetItemFamily)
    if family then Say("GetItemFamily: " .. tostring(family(ref))) end
    local found
    for bag = 0, 4 do
        for slot = 1, (C_Container and C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id and not found then
                found = true
                local keys = {}
                for key, value in pairs(info) do
                    if key ~= "hyperlink" and key ~= "iconFileID" then keys[#keys + 1] = key .. "=" .. tostring(value) end
                end
                table.sort(keys)
                Say("bag slot info: " .. table.concat(keys, ", "))
            end
        end
    end
    if not found then Say("bag slot info: that item is not in your bags right now") end
end

SLASH_SACKS1 = "/sacks"
SlashCmdList["SACKS"] = function(message)
    local args = Words(message)
    local name = (table.remove(args, 1) or ""):lower()
    if name == "" then
        ToggleSettings()
    elseif commands[name] then
        commands[name](args)
    else
        for _, line in ipairs(HELP) do Say(line) end
    end
end

---------------------------------------------------------------------------------------------------
-- Settings window, and the icon that opens it
---------------------------------------------------------------------------------------------------

local settings

-- Build a frame with one of the game's own templates; if this client lacks the template, fall back to a plain frame
-- so the window still opens.
local function NativeFrame(kind, parent, template)
    if template then
        local ok, frame = pcall(CreateFrame, kind, nil, parent, template)
        if ok and frame then return frame, true end
    end
    return CreateFrame(kind, nil, parent), false
end

local function MakeButton(parent, text, width, onClick)
    local button = NativeFrame("Button", parent, "UIPanelButtonTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetText(text)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", onClick)
    return button
end

local function MakeText(parent, template, point, x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint(point, x, y)
    text:SetJustifyH("LEFT")
    return text
end

-- A tick box drawn with the game's own check textures, with its label to the right.
local function MakeCheck(parent, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(CHECK_SIZE, CHECK_SIZE)
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetText(label)
    check:SetScript("OnClick", onClick)
    return check
end

-- Choices for the pickers come from the game's own class, subclass and quality names.
-- The game still lists some retired categories ("Explosives (OBSOLETE)"). They are left out of the pick lists unless
-- an item you have carried is filed under one.
function Stat.InUse(class, sub)
    local function uses(entry)
        return entry.classID == class and (sub == nil or entry.subClassID == sub)
    end
    for _, item in ipairs(state.items or {}) do
        if uses(item) then return true end
    end
    for _, seen in pairs(SacksDB and SacksDB.seen or {}) do
        if uses(seen) then return true end
    end
    return false
end

local function ClassOptions(withAny)
    local options = withAny and { { label = "Any" } } or {}
    for id, name in ScanNames(ItemClassInfo) do
        local _, retired = ItemClassInfo(id)
        if not retired then
            options[#options + 1] = { label = name, value = id }
        elseif Stat.InUse(id) then
            options[#options + 1] = { label = name .. " (old)", value = id }
        end
    end
    return options
end

local function SubClassOptions(class, withAny)
    local options = withAny and { { label = "Any" } } or {}
    if class then
        for id, name in ScanNames(function(sub) return ItemSubClassInfo(class, sub) end) do
            local _, retired = ItemSubClassInfo(class, id)
            if not retired then
                options[#options + 1] = { label = name, value = id }
            elseif Stat.InUse(class, id) then
                options[#options + 1] = { label = name .. " (old)", value = id }
            end
        end
    end
    return options
end

-- Qualities are listed from lowest to highest and written in the colour the game uses for them.
local function ColouredQuality(quality)
    local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not colour then return QualityName(quality) end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(colour.r * 255 + 0.5), math.floor(colour.g * 255 + 0.5),
        math.floor(colour.b * 255 + 0.5), QualityName(quality))
end

local function QualityOptions(withAny)
    local options, seen, values = withAny and { { label = "Any" } } or {}, {}, {}
    for _, value in pairs(Enum.ItemQuality) do
        if not seen[value] then
            seen[value] = true
            values[#values + 1] = value
        end
    end
    table.sort(values)
    for _, value in ipairs(values) do options[#options + 1] = { label = ColouredQuality(value), value = value } end
    return options
end

local FIELD_OPERATORS = {
    class = { "=", "~=" },
    sub = { "=", "~=", "<", "<=", ">", ">=" },
    quality = { "=", "~=", "<", "<=", ">", ">=" },
    name = { "contains", "!contains", "matches", "!matches" },
    item = { "=", "~=" },
    ilvl = { "=", "~=", "<", "<=", ">", ">=" }, level = { "=", "~=", "<", "<=", ">", ">=" },
    stack = { "=", "~=", "<", "<=", ">", ">=" }, price = { "=", "~=", "<", "<=", ">", ">=" },
    equip = { "=", "~=" }, bind = { "=", "~=" }, reagent = { "=" }, bound = { "=" }, family = { "=", "~=" },
}

local function OperatorOptions(field)
    local options = {}
    for _, op in ipairs(FIELD_OPERATORS[field]) do options[#options + 1] = { label = OP_TEXT[op], value = op } end
    return options
end

-- A drop-down list. It uses the game's own drop-down menu; if this client has none it becomes a button that steps
-- through the choices instead. With a title the label sits above it. x, y place it inside parent.
local dropdowns = 0
local measuring
local function TextWidth(text)
    measuring = measuring or UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measuring:SetText(text or "")
    local width = measuring:GetStringWidth()
    return type(width) == "number" and width or 0
end

local function MakeChoice(parent, title, x, y, getOptions, onChange, width)
    width = width or CHOICE_WIDTH
    local choice = { index = 1 }
    local function current()
        local options = getOptions()
        return options[choice.index] or options[1] or { label = "" }
    end

    local menu
    if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
        dropdowns = dropdowns + 1
        local ok, frame = pcall(CreateFrame, "Frame", "SacksDropdown" .. dropdowns, parent, "UIDropDownMenuTemplate")
        if ok and frame then menu = frame end
    end

    local below = 0
    if title then
        choice.title = MakeText(parent, "GameFontHighlightSmall", "TOPLEFT", x, y)
        choice.title:SetText(title)
        below = LABEL_HEIGHT
    end
    choice.width = width
    if menu then
        choice.frame = menu
        menu:SetPoint("TOPLEFT", parent, "TOPLEFT", x - DROPDOWN_INSET, y - below)
        UIDropDownMenu_SetWidth(menu, width)
        UIDropDownMenu_Initialize(menu, function(_, level)
            for index, option in ipairs(getOptions()) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.label
                info.checked = index == choice.index
                info.func = function()
                    choice.index = index
                    UIDropDownMenu_SetText(menu, option.label)
                    if onChange then onChange() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        function choice.update() UIDropDownMenu_SetText(menu, current().label) end
    else
        choice.frame = MakeButton(parent, title or "", width + DROPDOWN_INSET, function(_, mouse)
            local count = #getOptions()
            choice.index = (choice.index - 1 + (mouse == "RightButton" and -1 or 1)) % count + 1
            choice.update()
            if onChange then onChange() end
        end)
        choice.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - below)
        function choice.update() choice.frame:SetText(current().label) end
    end

    -- Sizes the box to the widest thing it can show (room for the arrow included) and returns that width.
    function choice.fit()
        local widest = 0
        for _, option in ipairs(getOptions()) do widest = math.max(widest, TextWidth(option.label)) end
        local fitted = math.ceil(widest) + 32 -- room for the dropdown arrow and a little air
        choice.width = fitted
        if menu then UIDropDownMenu_SetWidth(menu, fitted) else choice.frame:SetWidth(fitted + DROPDOWN_INSET) end
        return fitted
    end
    -- Moves the box so its visible left edge is at x.
    function choice.moveTo(left, top)
        choice.frame:ClearAllPoints()
        choice.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left - (menu and DROPDOWN_INSET or 0), (top or y) - below)
    end
    function choice.value() return current().value end
    function choice.reset()
        choice.index = 1
        choice.update()
    end
    function choice.select(value)
        choice.index = 1
        for index, option in ipairs(getOptions()) do
            if option.value == value then choice.index = index end
        end
        choice.update()
    end
    function choice.enable(enabled)
        if menu then
            local toggle = enabled and UIDropDownMenu_EnableDropDown or UIDropDownMenu_DisableDropDown
            if toggle then toggle(menu) end
        elseif enabled then
            choice.frame:Enable()
        else
            choice.frame:Disable()
        end
    end
    function choice.show(visible)
        if visible then choice.frame:Show() else choice.frame:Hide() end
        if choice.title then
            if visible then choice.title:Show() else choice.title:Hide() end
        end
    end
    choice.update()
    return choice
end

-- Adds a sack from a name and a rule, telling you why if it can't.
local function AddSack(name, rule)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then return Say("type a name for the sack first") end
    if FindGroup(name) then return Say("there is already a sack called " .. name) end
    if #rule == 0 then return Say("pick at least one thing for the sack to take") end
    table.insert(SacksDB.groups, 1, { name = name, rule = rule, point = "CENTER", x = 0, y = 0 })
    Say("made the sack " .. name .. ": " .. Describe(rule))
    Refresh()
    return true
end

---------------------------------------------------------------------------------------------------
-- Items: every kind of item you carry (or have carried), with what the game says about it
---------------------------------------------------------------------------------------------------

local sort = { key = "class", descending = false }

local function Num(value) return value or -1 end
local COLUMNS = {
    { key = "name", title = "Item", width = 170, order = function(r) return r.name:lower() end,
        text = function(r) return r.name end },
    { key = "class", title = "Class", width = 88, order = function(r) return r.classText end,
        text = function(r) return r.classText end },
    { key = "sub", title = "Subclass", width = 100, order = function(r) return r.subText end,
        text = function(r) return r.subText end },
    { key = "quality", title = "Quality", width = 68, order = function(r) return r.quality end,
        text = function(r) return r.qualityText end },
    -- These come and go: a column for each fact your lines test, plus the reagent flag and the special bag type.
    { key = "ilvl", title = "iLvl", width = 44, extra = true, order = function(r) return Num(r.itemLevel) end,
        text = function(r) return r.itemLevel and tostring(r.itemLevel) or "" end },
    { key = "level", title = "Req", width = 40, extra = true, order = function(r) return Num(r.minLevel) end,
        text = function(r) return r.minLevel and tostring(r.minLevel) or "" end },
    { key = "equip", title = "Slot", width = 78, extra = true, order = function(r) return Stat.Format("equip", r.equip or "NONE") end,
        text = function(r) return (r.equip and r.equip ~= "NONE") and Stat.Format("equip", r.equip) or "" end },
    { key = "bind", title = "Binds", width = 48, extra = true, order = function(r) return Num(r.bindType) end,
        text = function(r) return Stat.bindShort[r.bindType or 0] or "" end },
    { key = "bound", title = "Bound", width = 50, extra = true, order = function(r) return r.bound or 0 end,
        text = function(r) return r.bound == 1 and "yes" or "" end },
    { key = "reagent", title = "Reagent", width = 58, extra = true, order = function(r) return r.reagent or 0 end,
        text = function(r) return r.reagent == 1 and "yes" or "" end },
    { key = "price", title = "Sells for", width = 78, extra = true, order = function(r) return r.sellPrice or 0 end,
        text = function(r) return (r.sellPrice or 0) > 0 and Stat.MoneyText(r.sellPrice) or "" end },
    { key = "stack", title = "Stack", width = 44, extra = true, order = function(r) return Num(r.stackMax) end,
        text = function(r) return r.stackMax and tostring(r.stackMax) or "" end },
    { key = "family", title = "Bag type", width = 84, extra = true, order = function(r) return Stat.FamilyText(r.family) end,
        text = function(r) return Stat.FamilyText(r.family) end },
    { key = "count", title = "Have", width = 44, order = function(r) return r.count end,
        text = function(r) return tostring(r.count) end },
    { key = "sack", title = "In sack", order = function(r) return r.sack end, text = function(r) return r.sack end },
}

-- Which columns the table shows now: the fixed ones, then extras for every fact the lines test and for the defaults
-- (reagent flag, special bag type) while there is room. The last column takes whatever width is left.
local function ActiveColumns(page)
    local base = 0
    for _, column in ipairs(COLUMNS) do
        if column.width and not column.extra then base = base + column.width end
    end
    local room = WINDOW_WIDTH - MARGIN * 2 - base - 100
    local show, wanted = {}, {}
    for _, clause in ipairs(page.draft or {}) do wanted[#wanted + 1] = clause.field end
    wanted[#wanted + 1] = "reagent"
    wanted[#wanted + 1] = "family"
    for _, key in ipairs(wanted) do
        for _, column in ipairs(COLUMNS) do
            if column.extra and column.key == key and not show[key] and room >= column.width then
                show[key] = true
                room = room - column.width
            end
        end
    end
    local list = {}
    for _, column in ipairs(COLUMNS) do
        if not column.extra or show[column.key] then list[#list + 1] = column end
    end
    return list
end

local function ColumnWidth(column, active)
    if column.width then return column.width end
    local used = 0
    for _, other in ipairs(active or COLUMNS) do
        if other.width and (active or not other.extra) then used = used + other.width end
    end
    return WINDOW_WIDTH - MARGIN * 2 - used
end

-- One row per item kind: what is in your bags now, plus every kind you have seen before (shown with 0).
local function BuildItemRows()
    local rows, byId = {}, {}
    local function add(id, fields, count)
        local row = byId[id]
        if not row then
            row = { itemID = id, name = fields.name or ("item " .. id), icon = fields.icon, classID = fields.classID,
                subClassID = fields.subClassID, quality = fields.quality or 0, count = 0, sellPrice = fields.sellPrice,
                itemLevel = fields.itemLevel, minLevel = fields.minLevel, stackMax = fields.stackMax,
                equip = fields.equip, bindType = fields.bindType, reagent = fields.reagent, bound = fields.bound,
                family = fields.family, bag = fields.bag or (LastBag() + 1), slot = fields.slot or 0 }
            byId[id] = row
            rows[#rows + 1] = row
        end
        row.count = row.count + count
        if fields.bound == 1 then row.bound = 1 end -- any bound stack counts
    end
    for _, item in ipairs(state.items or {}) do
        if item.itemID then add(item.itemID, item, item.count or 1) end
    end
    for id, seen in pairs(SacksDB.seen or {}) do
        if not byId[id] then add(id, seen, 0) end
    end
    for _, row in ipairs(rows) do
        row.classText = row.classID and ItemClassInfo(row.classID) or "?"
        row.subText = row.classID and row.subClassID and ItemSubClassInfo(row.classID, row.subClassID) or ""
        row.qualityText = QualityName(row.quality)
        row.sack = ""
        for _, group in ipairs(AllGroups()) do
            if (group.fixed or #group.rule > 0) and Matches(group.rule, row) then
                row.sack = group.name
                break
            end
        end
    end
    local column
    for _, candidate in ipairs(COLUMNS) do
        if candidate.key == sort.key then column = candidate end
    end
    table.sort(rows, function(a, b)
        local left, right = column.order(a), column.order(b)
        if left ~= right then
            if sort.descending then return left > right end
            return left < right
        end
        return a.name:lower() < b.name:lower()
    end)
    return rows
end

local function SelectedRows(rows)
    local selected = {}
    for _, row in ipairs(rows) do
        if state.selected[row.itemID] then selected[#selected + 1] = row end
    end
    return selected
end

-- What every selected item has in common. A field that differs between them is nil: it can't be used.
local function Shared(selected)
    local shared = {}
    if #selected == 0 then return shared end
    local first = selected[1]
    shared.class, shared.sub, shared.quality = first.classID, first.subClassID, first.quality
    for _, row in ipairs(selected) do
        if row.classID ~= shared.class then shared.class = nil end
        if row.subClassID ~= shared.sub then shared.sub = nil end
        if row.quality ~= shared.quality then shared.quality = nil end
    end
    if not shared.class then shared.sub = nil end
    -- Special bag types: a bit every selected item has (the lowest one, so the line names a single bag type).
    local common = first.family or 0
    shared.equip, shared.reagent = first.equip, first.reagent
    for _, row in ipairs(selected) do
        common = BitAnd(common, row.family or 0)
        if row.equip ~= shared.equip then shared.equip = nil end
        if row.reagent ~= shared.reagent then shared.reagent = nil end
    end
    for _, entry in ipairs(Stat.families) do
        if BitAnd(common, entry[1]) ~= 0 then
            shared.family = entry[1]
            break
        end
    end
    if shared.equip == "NONE" then shared.equip = nil end
    if shared.reagent ~= 1 then shared.reagent = nil end
    if #selected == 1 then shared.id = first.itemID end
    return shared
end

-- The sack being built or changed on the Items tab is a draft: a list of lines you can add, remove and reorder.
local MAX_LINES = 10
local NEW_SACK = { name = "New sack" }
local GATE_OPTIONS = { { label = "and", value = "AND" }, { label = "or", value = "OR" } }

local function NewCondition(field)
    local class = (ClassOptions(false)[1] or {}).value
    if field == "class" then return { field = field, op = "=", value = class } end
    if field == "sub" then
        local sub = SubClassOptions(class, false)[1]
        return { field = field, op = "=", class = class, value = sub and sub.value or 0 }
    end
    if field == "quality" then return { field = field, op = "=", value = QualityOptions(false)[1].value } end
    local stat = STATS[field]
    if stat and stat.kind == "pick" then return { field = field, op = "=", value = Stat.Options(field)[1].value } end
    if stat then return { field = field, op = ">=", value = 0 } end
    return { field = "name", op = "contains", value = "" }
end

local function CopyCondition(condition)
    local copy = {}
    for key, value in pairs(condition) do copy[key] = value end
    return copy
end

-- What the lines currently say: empty name lines are left out, and the first line has no join.
local function DraftRule(page)
    local rule = {}
    for _, condition in ipairs(page.draft) do
        local empty = condition.field == "name" and (type(condition.value) ~= "string" or condition.value == "")
        if not empty then
            local copy = CopyCondition(condition)
            copy.auto = nil
            if #rule == 0 then copy.join = nil end
            rule[#rule + 1] = copy
        end
    end
    return rule
end

local function SackPickOptions()
    local options = { { label = "New sack", value = NEW_SACK } }
    for _, group in ipairs(AllGroups()) do
        if not group.fixed then options[#options + 1] = { label = group.name, value = group } end
    end
    return options
end

local function LoadSack(page, group)
    page.target = group or false
    page.draft = {}
    if group then
        for _, condition in ipairs(group.rule) do page.draft[#page.draft + 1] = CopyCondition(condition) end
    end
    state.selected = {}
    page.sackPick.select(group or NEW_SACK)
    page.suggested = nil
    page.nameEdit:SetText(group and group.name or "")
end

-- Descriptive CamelCase names for a new sack, built from what it takes: LeatherArmor, Junk, EpicCloth...
local function CamelCase(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%w+") do out[#out + 1] = word:sub(1, 1):upper() .. word:sub(2) end
    return table.concat(out)
end

local function SuggestName(rule, itemName)
    local class, sub, quality, name, item
    for _, condition in ipairs(rule) do
        if condition.field == "class" then class = condition
        elseif condition.field == "sub" then sub = condition
        elseif condition.field == "quality" then quality = condition
        elseif condition.field == "name" then name = condition
        elseif condition.field == "item" then item = condition end
    end
    if item then
        local seen = SacksDB and SacksDB.seen and SacksDB.seen[item.value]
        local label = (seen and seen.name) or itemName
        if label then return CamelCase(label):sub(1, 32) end
    end
    local poor = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
    if quality and quality.value == poor and (quality.op == "=" or quality.op == "<=") and not (class or sub or name) then
        return "Junk"
    end
    local base = ""
    if sub and sub.op == "=" and sub.class then
        base = CamelCase(ItemSubClassInfo(sub.class, sub.value))
        local armor, weapon = Enum and Enum.ItemClass and Enum.ItemClass.Armor, Enum and Enum.ItemClass and Enum.ItemClass.Weapon
        if sub.class == armor or sub.class == weapon then
            local extra = CamelCase(ItemClassInfo(sub.class))
            if not base:find(extra, 1, true) then base = base .. extra end
        end
    elseif class and class.op == "=" then
        base = CamelCase(ItemClassInfo(class.value))
    end
    if name then
        local word = CamelCase(name.value)
        if name.op == "!contains" or name.op == "!matches" then word = "Not" .. word end
        base = base .. word
    end
    if quality then
        local label = CamelCase(QualityName(quality.value))
        if quality.value == poor and quality.op == "=" then label = "Junk" end
        local op = quality.op
        if op == "=" then base = label .. base
        elseif op == ">=" then base = base .. label .. "Plus"
        elseif op == ">" then base = "Above" .. label .. base
        elseif op == "<" then base = "Below" .. label .. base
        elseif op == "<=" then base = "UpTo" .. label .. base
        else base = "Not" .. label .. base end
    end
    if base == "" then base = "Sack" end
    return base:sub(1, 32)
end

local function UniqueName(base)
    if base == "" or not FindGroup(base) then return base end
    local number = 2
    while FindGroup(base:sub(1, 30) .. number) do number = number + 1 end
    return base:sub(1, 30) .. number
end

-- The table can be narrowed: kinds you have now, kinds nothing of yours takes, and a name search.
local function PassesFilter(row, page)
    local mode = page.show and page.show.value() or "bags"
    if mode == "bags" and row.count == 0 then return false end
    if mode == "unsorted" and (row.count == 0 or row.sack ~= SacksDB.fallback.name) then return false end
    local search = page.search and page.search:GetText() or ""
    if type(search) == "string" and search ~= "" then
        local op = PatternError(search) and "contains" or "matches"
        if not TextMatches(op, search, row.name) then return false end
    end
    return true
end

local function SelectionChanged()
    local page = settings.items
    local selected = SelectedRows(BuildItemRows())
    -- While changing an existing sack the lines are the sack's own; a selected item is only there for "Exact item".
    -- Lines made from an earlier click ("auto") are replaced; lines that belong to the sack are not.
    local manual = false
    for _, line in ipairs(page.draft) do
        if not line.auto then manual = true end
    end
    if page.target and manual then return RefreshSettings() end
    -- For a new sack, the lines made from a selection are replaced each time the selection changes (lines you
    -- edited by hand are yours and stay). Items sharing a class (and subclass) give those lines; otherwise a
    -- shared quality; otherwise the items themselves, each as an "Exact item" line joined with or.
    for index = #page.draft, 1, -1 do
        if page.draft[index].auto then table.remove(page.draft, index) end
    end
    local added = 0
    local function add(condition)
        condition.auto = true
        if #page.draft < MAX_LINES then
            page.draft[#page.draft + 1] = condition
            added = added + 1
        end
    end
    if #selected > 0 then
        local shared = Shared(selected)
        if shared.family then add({ field = "family", op = "=", value = shared.family }) end
        if shared.class then
            add({ field = "class", op = "=", value = shared.class })
            if shared.sub then add({ field = "sub", op = "=", class = shared.class, value = shared.sub }) end
        end
        if added == 0 then
            -- No class or bag type in common: whatever else they share, and failing that the items themselves.
            if shared.equip then add({ field = "equip", op = "=", value = shared.equip }) end
            if shared.reagent then add({ field = "reagent", op = "=", value = 1 }) end
            if shared.quality then add({ field = "quality", op = "=", value = shared.quality }) end
            if added == 0 and #selected <= MAX_LINES then
                for index, row in ipairs(selected) do
                    add({ field = "item", op = "=", value = row.itemID, join = index > 1 and "OR" or nil })
                end
            end
        end
    end
    RefreshSettings()
end

local LINE_START = 124 -- the lines flow left to right from here, each box as wide as its widest text

local function FieldOptions()
    return { { label = "Class", value = "class" }, { label = "Subclass", value = "sub" },
        { label = "Quality", value = "quality" }, { label = "Name", value = "name" },
        { label = "Item level", value = "ilvl" }, { label = "Required level", value = "level" },
        { label = "Equip slot", value = "equip" }, { label = "Bind type", value = "bind" },
        { label = "Soulbound", value = "bound" }, { label = "Crafting reagent", value = "reagent" },
        { label = "Sell price", value = "price" }, { label = "Stack size", value = "stack" },
        { label = "Special bag type", value = "family" },
        { label = "Exact item", value = "item" } }
end

-- How many rows of a list fit on screen: what is left of the screen height after everything else in the window.
local function ListRoom(above, below, rowHeight, least, most)
    local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(screen) ~= "number" then screen = 1080 end
    local fits = math.floor((screen - 70 - CONTENT_TOP - above - below - MARGIN) / rowHeight)
    return math.max(least, math.min(most, fits))
end

-- A scroll bar for a list: a track with a thumb you can drag. Click the track to move a page. set() sizes it.
local function MakeScrollbar(parent, x, top, onScroll)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(10)
    bar:EnableMouse(true)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, 0.5)
    bar.thumb = CreateFrame("Button", nil, bar)
    bar.thumb:SetWidth(10)
    bar.thumb.tex = bar.thumb:CreateTexture(nil, "OVERLAY")
    bar.thumb.tex:SetAllPoints()
    bar.thumb.tex:SetColorTexture(1, 0.82, 0, 0.6)
    bar.total, bar.visible, bar.offset, bar.travel = 0, 0, 0, 0
    bar.dragging = false
    local function cursor()
        if not GetCursorPosition then return 0 end
        local _, cy = GetCursorPosition()
        return cy / bar:GetEffectiveScale()
    end
    local function go(offset)
        offset = math.max(0, math.min(bar.total - bar.visible, math.floor(offset + 0.5)))
        if offset ~= bar.offset then onScroll(offset) end
    end
    function bar.set(total, visible, offset, height, newTop)
        if newTop then top = newTop end
        bar.total, bar.visible, bar.offset = total, visible, offset
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", x, -top)
        bar:SetHeight(height)
        if total <= visible then
            bar:Hide()
            return
        end
        bar:Show()
        local size = math.max(18, height * visible / total)
        bar.travel = height - size
        bar.thumb:SetHeight(size)
        bar.thumb:ClearAllPoints()
        bar.thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(bar.travel * offset / (total - visible)))
    end
    bar.thumb:SetScript("OnMouseDown", function()
        bar.dragging, bar.startCursor, bar.startOffset = true, cursor(), bar.offset
    end)
    bar.thumb:SetScript("OnMouseUp", function() bar.dragging = false end)
    bar:SetScript("OnMouseDown", function()
        local thumbTop = bar:GetTop() - bar.travel * bar.offset / math.max(1, bar.total - bar.visible)
        go(bar.offset + (cursor() > thumbTop and -bar.visible or bar.visible))
    end)
    bar:SetScript("OnUpdate", function()
        if not bar.dragging then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            bar.dragging = false
            return
        end
        if bar.travel > 0 then
            go(bar.startOffset + (bar.startCursor - cursor()) / bar.travel * (bar.total - bar.visible))
        end
    end)
    return bar
end

local function MakeLine(page)
    local line = CreateFrame("Frame", nil, page)
    line.page = page
    line.clause = false -- set by FillLine; the pickers below read it when they are built
    line:SetSize(WINDOW_WIDTH - MARGIN * 2, LINE_HEIGHT)
    local plainY = -(LINE_HEIGHT - BUTTON_HEIGHT) / 2
    local function changed()
        if line.clause then line.clause.auto = nil end -- once you touch a line it is yours
        RefreshSettings()
    end

    -- Reordering keeps each and/or where it is, so the first line never carries one.
    local function move(by)
        local draft, from, to = page.draft, line.index, line.index + by
        if not draft[to] then return end
        draft[from], draft[to] = draft[to], draft[from]
        draft[from].join, draft[to].join = draft[to].join, draft[from].join
        changed()
    end
    line.remove = MakeButton(line, "x", 22, function()
        table.remove(page.draft, line.index)
        changed()
    end)
    line.remove:SetPoint("TOPLEFT", 0, plainY)
    line.up = MakeButton(line, "Up", 44, function() move(-1) end)
    line.up:SetPoint("TOPLEFT", 25, plainY)
    line.down = MakeButton(line, "Down", 44, function() move(1) end)
    line.down:SetPoint("TOPLEFT", 72, plainY)

    line.firstText = MakeText(line, "GameFontHighlight", "TOPLEFT", LINE_START, plainY - 4)
    line.firstText:SetText("Take if")
    line.gate = MakeChoice(line, nil, LINE_START, 0, function() return GATE_OPTIONS end, function()
        line.clause.join = line.gate.value() == "OR" and "OR" or nil
        changed()
    end)
    line.field = MakeChoice(line, nil, LINE_START, 0, FieldOptions, function()
        local field = line.field.value()
        if field == line.clause.field then return end
        local condition
        if field == "item" then
            local id = Shared(SelectedRows(BuildItemRows())).id
            if not id then
                Say("select exactly one item in the table first, then choose Exact item")
                line.field.select(line.clause.field)
                return
            end
            condition = { field = "item", op = "=", value = id }
        else
            condition = NewCondition(field)
        end
        condition.join = line.clause.join
        page.draft[line.index] = condition
        changed()
    end)
    line.op = MakeChoice(line, nil, LINE_START, 0, function() return OperatorOptions(line.clause and line.clause.field or "class") end,
        function()
            line.clause.op = line.op.value()
            changed()
        end)
    line.class = MakeChoice(line, nil, LINE_START, 0, function() return ClassOptions(false) end, function()
        if line.clause.field == "sub" then
            line.clause.class = line.class.value()
            local sub = SubClassOptions(line.clause.class, false)[1]
            line.clause.value = sub and sub.value or 0
        else
            line.clause.value = line.class.value()
        end
        changed()
    end)
    line.sub = MakeChoice(line, nil, LINE_START, 0, function() return SubClassOptions(line.clause and line.clause.class, false) end,
        function()
            line.clause.value = line.sub.value()
            changed()
        end)
    line.quality = MakeChoice(line, nil, LINE_START, 0, function() return QualityOptions(false) end, function()
        line.clause.value = line.quality.value()
        changed()
    end)

    line.pick = MakeChoice(line, nil, LINE_START, 0, function()
        return Stat.Options(line.clause and line.clause.field or "bound")
    end, function()
        line.clause.value = line.pick.value()
        changed()
    end)
    line.number = NativeFrame("EditBox", line, "InputBoxTemplate")
    line.number:SetSize(90, BUTTON_HEIGHT)
    line.number:SetAutoFocus(false)
    line.number:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    line.number:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    line.number:SetScript("OnTextChanged", function(self, typed)
        if not typed or not line.clause then return end
        local value = Stat.Parse(line.clause.field, self:GetText())
        if value ~= nil and value ~= line.clause.value then
            line.clause.value = value
            changed()
        end
    end)

    line.text = NativeFrame("EditBox", line, "InputBoxTemplate")
    line.text:SetSize(200, BUTTON_HEIGHT)
    line.text:SetPoint("TOPLEFT", LINE_START, plainY)
    line.text:SetAutoFocus(false)
    line.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    line.text:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    line.text:SetScript("OnTextChanged", function(self, typed)
        if not typed then return end
        line.clause.value = self:GetText()
        changed()
    end)
    line.warn = MakeText(line, "GameFontNormalSmall", "TOPRIGHT", 0, plainY - 4)
    line.warn:SetTextColor(1, 0.3, 0.3)
    line.itemLabel = MakeText(line, "GameFontHighlight", "TOPLEFT", LINE_START, plainY - 4)
    return line
end

local function FillLine(line, clause, index, count)
    line.clause, line.index = clause, index
    line.field.select(clause.field)
    line.op.select(clause.op)
    if index == 1 then
        line.gate.show(false)
        line.firstText:Show()
    else
        line.firstText:Hide()
        line.gate.show(true)
        line.gate.select(clause.join or "AND")
    end
    if index == 1 then line.up:Disable() else line.up:Enable() end
    if index == count then line.down:Disable() else line.down:Enable() end
    line.class.show(false)
    line.sub.show(false)
    line.quality.show(false)
    line.pick.show(false)
    line.number:Hide()
    line.text:Hide()
    line.itemLabel:Hide()
    line.warn:SetText("")
    line.warn:SetTextColor(1, 0.3, 0.3)

    -- Each box is as wide as the longest text it can hold. If the row would run past the window, the gaps
    -- between boxes shrink (down to a small minimum) until it fits.
    local boxes = { line.gate, line.field, line.op }
    if clause.field == "class" then
        line.class.show(true)
        line.class.select(clause.value)
        boxes[#boxes + 1] = line.class
    elseif clause.field == "sub" then
        -- A Class line above or below already says which class; the subclass follows it instead of asking again.
        local owner
        for _, other in ipairs(line.page.draft) do
            if other.field == "class" and other.op == "=" and not owner then owner = other end
        end
        if owner then
            if clause.class ~= owner.value then
                clause.class = owner.value
                local first = SubClassOptions(owner.value, false)[1]
                clause.value = first and first.value or 0
            end
            line.class.show(false)
        else
            line.class.show(true)
            line.class.select(clause.class)
            boxes[#boxes + 1] = line.class
        end
        line.sub.show(true)
        line.sub.select(clause.value)
        boxes[#boxes + 1] = line.sub
    elseif clause.field == "quality" then
        line.quality.show(true)
        line.quality.select(clause.value)
        boxes[#boxes + 1] = line.quality
    elseif STATS[clause.field] and STATS[clause.field].kind == "pick" then
        line.pick.show(true)
        line.pick.select(clause.value)
        boxes[#boxes + 1] = line.pick
    end
    local total = 0
    for _, box in ipairs(boxes) do total = total + box.fit() end
    local room = WINDOW_WIDTH - MARGIN * 2 - LINE_START - 50
    local gap = 40 -- from one fitted box to the next (the box frame is wider than its text area)
    if #boxes > 1 and total + (#boxes - 1) * gap > room then
        gap = math.max(12, (room - total) / (#boxes - 1))
    end
    local x = LINE_START
    for _, box in ipairs(boxes) do
        box.moveTo(x, 0)
        x = x + box.width + gap
    end
    if STATS[clause.field] and STATS[clause.field].kind ~= "pick" then
        line.number:ClearAllPoints()
        line.number:SetPoint("TOPLEFT", x + 6, -(LINE_HEIGHT - BUTTON_HEIGHT) / 2)
        line.number:Show()
        if Stat.Parse(clause.field, line.number:GetText()) ~= clause.value then
            line.number:SetText(STATS[clause.field].kind == "money" and Stat.MoneyText(clause.value) or tostring(clause.value))
        end
        if STATS[clause.field].kind == "money" then
            line.warn:SetText("e.g. 1g 50s 25c  (a bare number is copper)")
            line.warn:SetTextColor(0.6, 0.6, 0.6)
        end
    elseif clause.field == "name" then
        line.text:ClearAllPoints()
        line.text:SetPoint("TOPLEFT", x + 6, -(LINE_HEIGHT - BUTTON_HEIGHT) / 2)
        line.text:SetWidth(math.max(120, WINDOW_WIDTH - MARGIN * 2 - x - 70))
        line.text:Show()
        if line.text:GetText() ~= clause.value then line.text:SetText(clause.value) end
        if clause.op == "matches" or clause.op == "!matches" then
            if PatternError(clause.value) then line.warn:SetText("bad pattern") end
        end
    elseif clause.field ~= "class" and clause.field ~= "sub" and clause.field ~= "quality" and not STATS[clause.field] then
        line.itemLabel:ClearAllPoints()
        line.itemLabel:SetPoint("TOPLEFT", x, -(LINE_HEIGHT - BUTTON_HEIGHT) / 2 - 4)
        line.itemLabel:SetText(ValueText(clause))
        line.itemLabel:Show()
    end
end

local function RefreshItems()
    local page = settings.items
    -- Lay the columns out (only when the set changed), and fall back to Class if the sorted column went away.
    local active = ActiveColumns(page)
    local signature = {}
    local shownKey = {}
    for _, column in ipairs(active) do
        signature[#signature + 1] = column.key
        shownKey[column.key] = true
    end
    signature = table.concat(signature, ",")
    if not shownKey[sort.key] then sort.key, sort.descending = "class", false end
    if page.columnSignature ~= signature then
        page.columnSignature = signature
        local x = 0
        for _, column in ipairs(COLUMNS) do
            local header = page.headers[column.key]
            if shownKey[column.key] then
                local width = ColumnWidth(column, active)
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", x, -page.headerTop)
                header:SetWidth(width)
                header:Show()
                local inset = column.key == "name" and TABLE_ROW_HEIGHT + 3 or 4
                for _, view in ipairs(page.view) do
                    local cell = view.cells[column.key]
                    cell:ClearAllPoints()
                    cell:SetPoint("LEFT", x + inset, 0)
                    cell:SetWidth(width - inset - 2)
                    cell:Show()
                end
                x = x + width
            else
                header:Hide()
                for _, view in ipairs(page.view) do view.cells[column.key]:Hide() end
            end
        end
    end
    if page.target then
        local found
        for _, group in ipairs(AllGroups()) do
            if group == page.target then found = true end
        end
        if not found then LoadSack(page, nil) end
    end
    page.sackPick.select(page.target or NEW_SACK)
    page.createButton:SetText(page.target and "Save changes" or "Make sack")
    local rows = BuildItemRows()
    local selected = SelectedRows(rows)
    local rule = DraftRule(page)
    local previewing = #rule > 0

    local matches, held = 0, 0
    for _, row in ipairs(rows) do
        row.matched = previewing and Matches(rule, row)
        if row.matched then
            matches = matches + 1
            held = held + row.count
        end
    end

    if not page.target then
        local suggestion = previewing and UniqueName(SuggestName(rule, selected[1] and selected[1].name)) or ""
        local typed = page.nameEdit:GetText() or ""
        if typed == "" or typed == page.suggested then page.nameEdit:SetText(suggestion) end
        page.suggested = suggestion
    end

    local all = rows
    rows = {}
    for _, row in ipairs(all) do
        if PassesFilter(row, page) then rows[#rows + 1] = row end
    end
    -- The table is as tall as its rows need, up to what the screen leaves after the lines and buttons below it.
    local below = 16 + 34 + DROPDOWN_HEIGHT + #page.draft * LINE_HEIGHT + BUTTON_HEIGHT + PADDING + HINT_HEIGHT + BUTTON_HEIGHT
    local visible = math.max(math.min(#rows, ListRoom(page.tableTop, below, TABLE_ROW_HEIGHT, 8, 16)), 8)
    local most = math.max(0, #rows - visible)
    page.offset = math.min(page.offset or 0, most)
    page.scroll.set(#rows, visible, page.offset, visible * TABLE_ROW_HEIGHT)

    -- Everything under the table follows its bottom edge; the lines come and go below that.
    local y = page.tableTop + visible * TABLE_ROW_HEIGHT + PADDING
    page.info:ClearAllPoints()
    page.info:SetPoint("TOPLEFT", 0, -y)
    page.summary:ClearAllPoints()
    page.summary:SetPoint("TOPLEFT", 0, -(y + 16))
    y = y + 16 + 34
    page.sackLabel:ClearAllPoints()
    page.sackLabel:SetPoint("TOPLEFT", 0, -(y + (DROPDOWN_HEIGHT - 12) / 2))
    page.sackPick.moveTo(56, -y)
    page.sackHint:ClearAllPoints()
    page.sackHint:SetPoint("TOPLEFT", 56 + CHOICE_WIDTH + 30 + 40, -(y + (DROPDOWN_HEIGHT - 10) / 2))
    y = y + DROPDOWN_HEIGHT
    for index, clause in ipairs(page.draft) do
        local line = page.lines[index] or MakeLine(page)
        page.lines[index] = line
        FillLine(line, clause, index, #page.draft)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 0, -y)
        line:Show()
        y = y + LINE_HEIGHT
    end
    for index = #page.draft + 1, #page.lines do page.lines[index]:Hide() end
    page.addButton:ClearAllPoints()
    page.addButton:SetPoint("TOPLEFT", 0, -y)
    y = y + BUTTON_HEIGHT + PADDING
    page.hint:ClearAllPoints()
    page.hint:SetPoint("TOPLEFT", 0, -y)
    y = y + HINT_HEIGHT
    page.nameEdit:ClearAllPoints()
    page.nameEdit:SetPoint("TOPLEFT", 6, -y)
    y = y + BUTTON_HEIGHT
    page.height = y
    page:SetHeight(y)

    for index, view in ipairs(page.view) do
        local row = index <= visible and rows[page.offset + index] or nil
        view.data = row
        if row then
            view.icon:SetTexture(row.icon)
            for _, column in ipairs(COLUMNS) do view.cells[column.key]:SetText(column.text(row)) end
            local dim = row.count == 0
            for _, cell in pairs(view.cells) do
                if dim then cell:SetTextColor(0.6, 0.6, 0.6) else cell:SetTextColor(1, 1, 1) end
            end
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
            if color and not dim then view.cells.name:SetTextColor(color.r, color.g, color.b) end
            if state.selected[row.itemID] then view.selected:Show() else view.selected:Hide() end
            if row.matched and not state.selected[row.itemID] then view.matched:Show() else view.matched:Hide() end
            view:Show()
        else
            view:Hide()
        end
    end
    for _, column in ipairs(COLUMNS) do
        local mark = ""
        if sort.key == column.key then mark = sort.descending and "  v" or "  ^" end
        page.headers[column.key]:SetText(column.title .. mark)
    end

    local last = math.min(#rows, page.offset + visible)
    page.info:SetText(string.format("%d-%d of %d kinds of item shown (%d known). Mouse wheel scrolls. Grey: none right now.",
        #rows == 0 and 0 or page.offset + 1, last, #rows, #all))
    if previewing then
        page.summary:SetText(string.format("Takes %d kinds of item, %d in your bags now (green rows).", matches, held))
    elseif #selected == 0 then
        page.summary:SetText("Select items in the table to fill in the lines below, or press Add a line to set them by hand.")
    else
        page.summary:SetText("Add a line below to say what the sack takes.")
    end
    settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
end

local function BuildItems(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", MARGIN, -CONTENT_TOP)
    page:SetSize(WINDOW_WIDTH - MARGIN * 2, 100)
    page.offset, page.headers, page.view = 0, {}, {}
    page.target, page.draft, page.lines = false, {}, {}

    local filterHeight = DROPDOWN_HEIGHT + PADDING
    MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -((DROPDOWN_HEIGHT - 12) / 2)):SetText("Show")
    page.show = MakeChoice(page, nil, 36, 0, function()
        return {
            { label = "In my bags now", value = "bags" },
            { label = "Everything I've carried", value = "all" },
            { label = "Unsorted (in " .. SacksDB.fallback.name .. ")", value = "unsorted" },
        }
    end, function()
        page.offset = 0
        RefreshSettings()
    end, 150)
    MakeText(page, "GameFontHighlight", "TOPLEFT", 250, -((DROPDOWN_HEIGHT - 12) / 2)):SetText("Search")
    page.search = NativeFrame("EditBox", page, "InputBoxTemplate")
    page.search:SetSize(120, BUTTON_HEIGHT)
    page.search:SetPoint("TOPLEFT", 304, -((DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2))
    page.search:SetAutoFocus(false)
    page.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.search:SetScript("OnTextChanged", function(_, user)
        if user then
            page.offset = 0
            RefreshSettings()
        end
    end)
    page.searchSack = MakeButton(page, "Sack from search", 140, function()
        local text = page.search:GetText() or ""
        if text == "" then return Say("type something in the search box first") end
        if #page.draft >= MAX_LINES then return Say("that is as many lines as a sack can have") end
        page.draft[#page.draft + 1] = { field = "name", op = PatternError(text) and "contains" or "matches", value = text }
        RefreshSettings()
    end)
    page.searchSack:SetPoint("TOPLEFT", 440, -((DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2))

    local x = 0
    for _, column in ipairs(COLUMNS) do
        local width = ColumnWidth(column)
        local header = MakeButton(page, column.title, width, function()
            if sort.key == column.key then
                sort.descending = not sort.descending
            else
                sort.key, sort.descending = column.key, false
            end
            RefreshSettings()
        end)
        header:SetPoint("TOPLEFT", x, -filterHeight)
        page.headers[column.key] = header
        x = x + width
    end
    page.headerTop = filterHeight

    local top = filterHeight + BUTTON_HEIGHT + 2
    for index = 1, 40 do
        local view = CreateFrame("Button", nil, page)
        view:SetSize(WINDOW_WIDTH - MARGIN * 2, TABLE_ROW_HEIGHT)
        view:SetPoint("TOPLEFT", 0, -(top + (index - 1) * TABLE_ROW_HEIGHT))
        view:RegisterForClicks("LeftButtonUp")
        view.matched = view:CreateTexture(nil, "BACKGROUND")
        view.matched:SetAllPoints()
        view.matched:SetColorTexture(0.1, 0.8, 0.2, 0.18)
        view.selected = view:CreateTexture(nil, "BACKGROUND")
        view.selected:SetAllPoints()
        view.selected:SetColorTexture(0.2, 0.45, 1, 0.4)
        view.hover = view:CreateTexture(nil, "BACKGROUND")
        view.hover:SetAllPoints()
        view.hover:SetColorTexture(1, 1, 1, 0.08)
        view.hover:Hide()
        view.icon = view:CreateTexture(nil, "ARTWORK")
        view.icon:SetSize(TABLE_ROW_HEIGHT - 2, TABLE_ROW_HEIGHT - 2)
        view.icon:SetPoint("LEFT", 1, 0)
        view.cells = {}
        local cellX = 0
        for _, column in ipairs(COLUMNS) do
            local cell = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            local width = ColumnWidth(column)
            local inset = column.key == "name" and TABLE_ROW_HEIGHT + 3 or 4
            cell:SetPoint("LEFT", cellX + inset, 0)
            cell:SetWidth(width - inset - 2)
            cell:SetJustifyH("LEFT")
            if cell.SetWordWrap then cell:SetWordWrap(false) end
            view.cells[column.key] = cell
            cellX = cellX + width
        end
        view:SetScript("OnClick", function(self)
            local row = self.data
            if not row then return end
            if IsControlKeyDown and IsControlKeyDown() then
                state.selected[row.itemID] = not state.selected[row.itemID] or nil
            else
                local only = state.selected[row.itemID] and next(state.selected, next(state.selected)) == nil
                state.selected = {}
                if not only then state.selected[row.itemID] = true end
            end
            SelectionChanged()
        end)
        view:SetScript("OnEnter", function(self)
            self.hover:Show()
            if self.data then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.data.itemID) then
                    GameTooltip:SetText(self.data.name)
                end
                GameTooltip:Show()
            end
        end)
        view:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        page.view[index] = view
    end

    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, (self.offset or 0) - delta * WHEEL_STEP)
        RefreshSettings()
    end)

    page.tableTop = top
    page.scroll = MakeScrollbar(page, WINDOW_WIDTH - MARGIN * 2 + 3, top, function(offset)
        page.offset = offset
        RefreshSettings()
    end)
    local y = top + 12 * TABLE_ROW_HEIGHT + PADDING
    page.info = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    y = y + 16
    page.summary = MakeText(page, "GameFontNormal", "TOPLEFT", 0, -y)
    page.summary:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    y = y + 34

    page.sackLabel = MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -(y + (DROPDOWN_HEIGHT - 12) / 2))
    page.sackLabel:SetText("Sack")
    page.sackPick = MakeChoice(page, nil, 56, -y, SackPickOptions, function()
        local value = page.sackPick.value()
        LoadSack(page, value ~= NEW_SACK and value or nil)
        RefreshSettings()
    end, CHOICE_WIDTH + 30)
    page.sackHint = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 56 + CHOICE_WIDTH + 30 + 40, -(y + (DROPDOWN_HEIGHT - 10) / 2))
    page.sackHint:SetText("pick an existing sack to change what it takes")
    y = y + DROPDOWN_HEIGHT

    -- The lines that say what the sack takes. RefreshItems places them, and everything below them, as they come and go.
    page.lineTop = y
    page.addButton = MakeButton(page, "Add a line", 110, function()
        if #page.draft >= MAX_LINES then return Say("that is as many lines as a sack can have") end
        page.draft[#page.draft + 1] = NewCondition("class")
        RefreshSettings()
    end)
    page.hint = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    page.hint:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    page.hint:SetText("Lines evaluated top to bottom; and binds tighter than or: A and B or C = (A and B) or C. Name matches: case-insensitive; . any char, .* any run, ^ start, $ end, | alternatives.")

    page.nameEdit = NativeFrame("EditBox", page, "InputBoxTemplate")
    page.nameEdit:SetSize(CHOICE_WIDTH + 30, BUTTON_HEIGHT)
    page.nameEdit:SetPoint("TOPLEFT", 6, -y)
    page.nameEdit:SetAutoFocus(false)
    page.nameEdit:SetMaxLetters(32)
    page.nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.createButton = MakeButton(page, "Make sack", 120, function()
        local rule = DraftRule(page)
        local target = page.target
        if target then
            local name = (page.nameEdit:GetText() or ""):match("^%s*(.-)%s*$")
            if name == "" then return Say("a sack needs a name") end
            local other = FindGroup(name)
            if other and other ~= target then return Say("there is already a sack called " .. name) end
            if #rule == 0 then return Say("add at least one line for the sack to take") end
            local oldName = target.name
            target.rule, target.name = rule, name
            for _, group in ipairs(AllGroups()) do
                if group.dock and group.dock.to == oldName then group.dock.to = name end
            end
            Say("saved " .. name .. ": " .. Describe(rule))
            Refresh()
            return
        end
        if AddSack(page.nameEdit:GetText(), rule) then
            page.nameEdit:SetText("")
            page.suggested = nil
        end
    end)
    page.createButton:SetPoint("LEFT", page.nameEdit, "RIGHT", 10, 0)
    page.forget = MakeButton(page, "Forget items I don't have", 170, function()
        local keep = {}
        for _, group in ipairs(AllGroups()) do
            for _, id in ipairs(group.pins or {}) do keep[id] = true end
        end
        for _, item in ipairs(state.items or {}) do
            if item.itemID then keep[item.itemID] = true end
        end
        local doomed = {}
        for id in pairs(SacksDB.seen or {}) do
            if not keep[id] then doomed[#doomed + 1] = id end
        end
        for _, id in ipairs(doomed) do SacksDB.seen[id] = nil end
        Say(string.format("forgot %d kinds of item you no longer carry (pinned ones are kept)", #doomed))
        RefreshSettings()
    end)
    page.forget:SetPoint("LEFT", page.createButton, "RIGHT", 110, 0)
    y = y + BUTTON_HEIGHT

    page.height = y
    page:SetHeight(y)
    return page
end

---------------------------------------------------------------------------------------------------
-- Helpers shared by the Items, Layout and Sacks tabs
---------------------------------------------------------------------------------------------------

local function EditedGroup()
    local groups = AllGroups()
    for _, group in ipairs(groups) do
        if group == state.editing then return group end
    end
    state.editing = groups[1]
    return state.editing
end

local function SackOptions()
    local options = {}
    for _, group in ipairs(AllGroups()) do options[#options + 1] = { label = group.name, value = group } end
    return options
end

---------------------------------------------------------------------------------------------------
-- Layout: how a sack grows, how it is sorted, and which items are pinned to the front
---------------------------------------------------------------------------------------------------

local ANCHOR_OPTIONS = {
    { label = "Top left", value = "TOPLEFT" }, { label = "Top right", value = "TOPRIGHT" },
    { label = "Bottom left", value = "BOTTOMLEFT" }, { label = "Bottom right", value = "BOTTOMRIGHT" },
}
local FLOW_OPTIONS = { { label = "Across, then wrap", value = "ROWS" }, { label = "Down, then wrap", value = "COLUMNS" } }
local TITLE_OPTIONS = { { label = "Above", value = "TOP" }, { label = "Below", value = "BOTTOM" },
    { label = "Hidden", value = "NONE" } }
local BLANK_OPTIONS = { { label = "After the items", value = "LAST" }, { label = "Before the items", value = "FIRST" },
    { label = "Not shown", value = "NONE" } }
local DIRECTION_OPTIONS = { { label = "Ascending", value = false }, { label = "Descending", value = true } }

local function SortKeyOptions(withNone)
    local options = withNone and { { label = "(none)" } } or {}
    for _, key in ipairs(SORT_KEY_ORDER) do options[#options + 1] = { label = SORT_KEYS[key].label, value = key } end
    return options
end

-- One row of the list of a sack's items, in the order they are shown. Pinned ones can be moved; any can be pinned.
local function MakeOrderRow(page)
    local row = CreateFrame("Frame", nil, page)
    local width = WINDOW_WIDTH - MARGIN * 2
    row:SetSize(width, ORDER_ROW_HEIGHT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ORDER_ROW_HEIGHT - 2, ORDER_ROW_HEIGHT - 2)
    row.icon:SetPoint("LEFT", 1, 0)
    row.name = MakeText(row, "GameFontHighlight", "LEFT", ORDER_ROW_HEIGHT + 4, 0)
    row.name:SetWidth(width - ORDER_ROW_HEIGHT - PIN_WIDTH - MOVE_WIDTH * 2 - SLOT_GAP * 4)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    local function move(by)
        local pins = EditedGroup().pins
        local target = row.data.pinIndex + by
        if not pins[target] then return end
        pins[row.data.pinIndex], pins[target] = pins[target], pins[row.data.pinIndex]
        Refresh()
    end
    row.pin = MakeButton(row, "Pin", PIN_WIDTH, function()
        local group = EditedGroup()
        group.pins = group.pins or {}
        if row.data.pinned then
            table.remove(group.pins, row.data.pinIndex)
        else
            group.pins[#group.pins + 1] = row.data.id
        end
        Refresh()
    end)
    row.pin:SetPoint("RIGHT", 0, 0)
    row.down = MakeButton(row, "Down", MOVE_WIDTH, function() move(1) end)
    row.down:SetPoint("RIGHT", row.pin, "LEFT", -SLOT_GAP, 0)
    row.up = MakeButton(row, "Up", MOVE_WIDTH, function() move(-1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -SLOT_GAP, 0)
    return row
end

local function BuildLayout(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", MARGIN, -CONTENT_TOP)
    page:SetSize(WINDOW_WIDTH - MARGIN * 2, 100)
    page.pinLines = {}

    local y = 0
    local stride = LAYOUT_WIDTH + 40
    local function setting(field, title, column, options)
        local choice
        choice = MakeChoice(page, title, column * stride, -y, function() return options end, function()
            EditedGroup()[field] = choice.value()
            Refresh()
        end, LAYOUT_WIDTH)
        return choice
    end
    local STEPPER_X = 170
    local function stepper(label, at, get, set)
        MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -(at + 4)):SetText(label)
        local box = {}
        box.minus = MakeButton(page, "-", BUTTON_HEIGHT + 4, function()
            set(math.max(1, get() - 1))
            Refresh()
        end)
        box.minus:SetPoint("TOPLEFT", STEPPER_X, -at)
        box.count = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        box.count:SetWidth(30)
        box.count:SetJustifyH("CENTER")
        box.count:SetPoint("LEFT", box.minus, "RIGHT", SLOT_GAP, 0)
        box.plus = MakeButton(page, "+", BUTTON_HEIGHT + 4, function()
            set(get() + 1)
            Refresh()
        end)
        box.plus:SetPoint("LEFT", box.count, "RIGHT", SLOT_GAP, 0)
        return box
    end
    local function header(text)
        local label = MakeText(page, "GameFontNormal", "TOPLEFT", 0, -y)
        label:SetText(text)
        local rule = page:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.18)
        rule:SetPoint("TOPLEFT", 0, -(y + LABEL_HEIGHT + 3))
        rule:SetSize(WINDOW_WIDTH - MARGIN * 2, 1)
        y = y + LABEL_HEIGHT + PADDING + 4
    end
    local DROP_LIFT = (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2
    local function dropdownRow(label, options, get, set)
        local text = MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -(y + DROP_LIFT + 4))
        text:SetText(label)
        local choice
        choice = MakeChoice(page, nil, STEPPER_X, -y, function() return options end, function() set(choice.value()) end, LAYOUT_WIDTH)
        return choice, text
    end
    local afterDropdown = STEPPER_X + LAYOUT_WIDTH + 50

    header("This sack")
    MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -(y + (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2 + 4)):SetText("Editing sack:")
    page.sackChoice = MakeChoice(page, nil, 110, -y, SackOptions, function()
        state.editing = page.sackChoice.value()
        RefreshSettings()
    end, CHOICE_WIDTH + 30)
    y = y + DROPDOWN_HEIGHT + PADDING
    page.anchor = setting("anchor", "Grows from this corner", 0, ANCHOR_OPTIONS)
    page.flow = setting("flow", "Fills", 1, FLOW_OPTIONS)
    page.title = setting("title", "Title", 2, TITLE_OPTIONS)
    y = y + LABEL_HEIGHT + DROPDOWN_HEIGHT + PADDING
    page.layoutHint = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    page.layoutHint:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    y = y + HINT_HEIGHT

    -- This sack: how many per row and the empty slot, each next to the button that goes back to the default.
    page.perRow = stepper("Slots per row", y, function() return EditedGroup().cols or SacksDB.columns or DEFAULT_COLUMNS end,
        function(value) EditedGroup().cols = value end)
    page.useDefault = MakeButton(page, "Use default", 100, function()
        EditedGroup().cols = nil
        Refresh()
    end)
    page.useDefault:SetPoint("LEFT", page.perRow.plus, "RIGHT", 12, 0)
    y = y + LINE_HEIGHT
    page.blank, page.blankLabel = dropdownRow("Empty slot", BLANK_OPTIONS, nil, function(value)
        EditedGroup().blank = value
        Refresh()
    end)
    y = y + DROPDOWN_HEIGHT + 2
    page.blankHint = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    page.blankHint:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    y = y + 2 * LABEL_HEIGHT + 4

    MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -y):SetText("Title text")
    MakeText(page, "GameFontDisableSmall", "TOPLEFT", 80, -(y + 2)):SetText("tokens: {name} {count} {items} {value} {free} {special}")
    y = y + LABEL_HEIGHT + 2
    page.titleEdit = NativeFrame("EditBox", page, "InputBoxTemplate")
    page.titleEdit:SetSize(300, BUTTON_HEIGHT)
    page.titleEdit:SetPoint("TOPLEFT", 6, -(y + (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2))
    page.titleEdit:SetAutoFocus(false)
    page.titleEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.titleEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.titleEdit:SetScript("OnTextChanged", function(self, typed)
        if not typed then return end
        EditedGroup().titleText = self:GetText()
        Refresh()
    end)
    page.insert = MakeChoice(page, nil, 330, -y, function()
        local options = { { label = "Insert token..." } }
        for _, piece in ipairs(TITLE_PIECES) do
            options[#options + 1] = { label = piece.token .. "  " .. piece.about, value = piece.token }
        end
        return options
    end, function()
        local token = page.insert.value()
        if token then
            local text = (page.titleEdit:GetText() or "") .. token
            page.titleEdit:SetText(text)
            EditedGroup().titleText = text
            Refresh()
        end
        page.insert.reset()
    end)
    local insertWidth = page.insert.fit()
    page.insert.moveTo(330, -y)
    page.titleDefault = MakeButton(page, "Default", 80, function()
        EditedGroup().titleText = nil
        Refresh()
    end)
    page.titleDefault:SetPoint("TOPLEFT", 330 + insertWidth + 40, -(y + (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2))
    y = y + DROPDOWN_HEIGHT
    page.titlePreview = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    page.titlePreview:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    y = y + 18 + PADDING


    header("Order of the items in this sack")
    page.sortRows = {}
    local function sortChanged()
        local list = {}
        for _, row in ipairs(page.sortRows) do
            local key = row.key.value()
            if key then list[#list + 1] = { key = key, descending = row.direction.value() } end
        end
        EditedGroup().sort = list
        Refresh()
    end
    for level = 1, 3 do
        local row = {}
        MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -(y + (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2 + 3)):SetText(level == 1 and "Sort by" or "then by")
        row.key = MakeChoice(page, nil, SORT_LABEL_WIDTH, -y, function() return SortKeyOptions(level > 1) end, sortChanged,
            LAYOUT_WIDTH)
        row.direction = MakeChoice(page, nil, SORT_LABEL_WIDTH + stride, -y, function() return DIRECTION_OPTIONS end,
            sortChanged, CHOICE_WIDTH)
        page.sortRows[level] = row
        y = y + LINE_HEIGHT
    end
    page.reverseCheck = MakeCheck(page, "Reverse the whole order (pins and sorting, flipped end to end)", function(self)
        EditedGroup().reverse = self:GetChecked() and true or false
        Refresh()
    end)
    page.reverseCheck:SetPoint("TOPLEFT", -4, -y)
    y = y + CHECK_SIZE + PADDING

    page.orderTitle = MakeText(page, "GameFontNormal", "TOPLEFT", 0, -y)
    page.orderTitle:SetText("Items in this sack, in the order they are shown")
    y = y + LABEL_HEIGHT + PADDING
    page.orderTop = y
    page.orderRows = {}
    page.orderScroll = MakeScrollbar(page, WINDOW_WIDTH - MARGIN * 2 + 3, y, function(offset)
        page.orderOffset = offset
        RefreshSettings()
    end)
    for index = 1, 30 do
        local row = MakeOrderRow(page)
        row:SetPoint("TOPLEFT", 0, -(y + (index - 1) * ORDER_ROW_HEIGHT))
        page.orderRows[index] = row
    end
    y = y + 8 * ORDER_ROW_HEIGHT + PADDING
    page.orderInfo = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    y = y + LABEL_HEIGHT
    page.height = y
    page:SetHeight(y)
    page.orderOffset = 0
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(self, delta)
        self.orderOffset = math.max(0, (self.orderOffset or 0) - delta * WHEEL_STEP)
        RefreshSettings()
    end)
    return page
end

local function RefreshLayout()
    local page = settings.layout
    local group = EditedGroup()
    if not group then return end
    page.sackChoice.select(group)
    page.anchor.select(group.anchor or DEFAULT_ANCHOR)
    page.flow.select(group.flow or DEFAULT_FLOW)
    page.title.select(group.title or DEFAULT_TITLE)
    page.perRow.count:SetText(group.cols or SacksDB.columns or DEFAULT_COLUMNS)
    page.reverseCheck:SetChecked(group.reverse and true or false)
    -- Only the Other sack has the empty slot, so the choice is only there while editing it.
    page.blank.show(group.fixed and true or false)
    if group.fixed then page.blankLabel:Show() else page.blankLabel:Hide() end
    page.blank.select(group.blank or "LAST")
    page.blankHint:SetText(group.fixed and "Empty slot: an extra cell showing free normal-bag slots (red at 0) and +N free special-bag slots. Dropping an item on it puts the item in the first free bag slot."
        or "Empty slot: only the Other sack has one. Pick Other in Editing sack to change it.")
    local titleText = group.titleText or TITLE_DEFAULT
    if page.titleEdit:GetText() ~= titleText then page.titleEdit:SetText(titleText) end
    page.titlePreview:SetText("Preview: " .. ((group.title ~= "NONE" and state.titles[group]) or "(title hidden)") .. "   (longer than the sack: clipped with ..., full text on hover)")
    page.orderTitle:SetText(group.reverse and "Items in this sack, in this order (the sack shows the list backwards)"
        or "Items in this sack, in the order they are shown")
    if group.cols then page.useDefault:Enable() else page.useDefault:Disable() end
    page.layoutHint:SetText(group.title == "NONE" and "Title hidden: shift-drag the sack body to move it." or
        "Corner = the fixed point; the sack grows away from it. At a vendor the sacks keep these settings and stack beside the vendor window.")

    local sort = group.sort or DEFAULT_SORT
    for level, row in ipairs(page.sortRows) do
        local spec = sort[level]
        row.key.select(spec and spec.key)
        row.direction.select(spec and spec.descending or false)
    end

    -- Pinned items first, in the order you pinned them, then everything else sorted by the keys above. Changing
    -- anything on this tab changes this list straight away.
    local rows = BuildItemRows()
    local byId = {}
    for _, row in ipairs(rows) do byId[row.itemID] = row end
    local display, isPinned = {}, {}
    for index, id in ipairs(group.pins or {}) do
        isPinned[id] = true
        local row = byId[id]
        local seen = SacksDB.seen and SacksDB.seen[id]
        display[#display + 1] = { id = id, pinned = true, pinIndex = index,
            name = row and row.name or (seen and seen.name) or ("item " .. id),
            icon = row and row.icon or (seen and seen.icon), count = row and row.count or 0,
            elsewhere = row and row.sack ~= group.name and row.sack or nil }
    end
    local rest = {}
    for _, row in ipairs(rows) do
        if row.sack == group.name and row.count > 0 and not isPinned[row.itemID] then rest[#rest + 1] = row end
    end
    SortItems({ sort = group.sort }, rest)
    for _, row in ipairs(rest) do
        display[#display + 1] = { id = row.itemID, pinned = false, name = row.name, icon = row.icon, count = row.count }
    end

    local visible = math.max(math.min(#display, ListRoom(page.orderTop, PADDING + LABEL_HEIGHT, ORDER_ROW_HEIGHT, 4, 12)), 4)
    page.orderOffset = math.min(page.orderOffset or 0, math.max(0, #display - visible))
    page.orderScroll.set(#display, visible, page.orderOffset, visible * ORDER_ROW_HEIGHT)
    page.orderInfo:ClearAllPoints()
    page.orderInfo:SetPoint("TOPLEFT", 0, -(page.orderTop + visible * ORDER_ROW_HEIGHT + PADDING))
    page.height = page.orderTop + visible * ORDER_ROW_HEIGHT + PADDING + LABEL_HEIGHT
    page:SetHeight(page.height)
    for index, row in ipairs(page.orderRows) do
        local entry = index <= visible and display[page.orderOffset + index] or nil
        row.data = entry
        if entry then
            row.icon:SetTexture(entry.icon)
            local suffix = entry.count == 0 and "  (none right now)" or ("  x" .. entry.count)
            if entry.elsewhere then suffix = suffix .. "  (goes to " .. entry.elsewhere .. " now)" end
            row.name:SetText(entry.name .. suffix)
            if entry.count == 0 then row.name:SetTextColor(0.6, 0.6, 0.6) else row.name:SetTextColor(1, 1, 1) end
            row.pin:SetText(entry.pinned and "Unpin" or "Pin")
            if entry.pinned then
                row.up:Show()
                row.down:Show()
                if entry.pinIndex == 1 then row.up:Disable() else row.up:Enable() end
                if entry.pinIndex == #group.pins then row.down:Disable() else row.down:Enable() end
            else
                row.up:Hide()
                row.down:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    local last = math.min(#display, page.orderOffset + visible)
    page.orderInfo:SetText(string.format("%d-%d of %d. Wheel scrolls. Pinned items first, then the sort order; Reverse flips the whole list.",
        #display == 0 and 0 or page.orderOffset + 1, last, #display))
    settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
end

---------------------------------------------------------------------------------------------------
-- Sacks: your sacks, with a quick way to start a new one
---------------------------------------------------------------------------------------------------

local function ShowTab(name)
    settings.active = name
    for key, page in pairs({ sacks = settings.sacks, items = settings.items, layout = settings.layout }) do
        if key == name then page:Show() else page:Hide() end
        if key == name then settings.tabs[key]:Disable() else settings.tabs[key]:Enable() end
    end
    RefreshSettings()
end

local function MakeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WINDOW_WIDTH - MARGIN * 2, ROW_HEIGHT)
    row:EnableMouse(true)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0)
    row.name = MakeText(row, "GameFontHighlight", "TOPLEFT", 0, -7)
    row.name:SetWidth(170)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.count = MakeText(row, "GameFontHighlight", "TOPLEFT", 176, -7)
    row.count:SetWidth(36)
    if row.count.SetJustifyH then row.count:SetJustifyH("RIGHT") end
    row.desc = MakeText(row, "GameFontDisableSmall", "TOPLEFT", 226, -9)
    row.desc:SetWidth(250)
    if row.desc.SetWordWrap then row.desc:SetWordWrap(false) end
    row:SetScript("OnEnter", function(self)
        if not self.group or (not self.group.fixed and #self.group.rule == 0) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(self.group.name)
        GameTooltip:AddLine("Takes: " .. Describe(self.group.rule), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.remove = MakeButton(row, "Remove", 70, function()
        local group, index = FindGroup(row.group.name)
        if not group then return end
        table.remove(SacksDB.groups, index)
        HideRemoved(group)
        Refresh()
    end)
    row.remove:SetPoint("TOPRIGHT", 0, -3)
    row.edit = MakeButton(row, "Edit", 50, function()
        state.editing = row.group
        LoadSack(settings.items, row.group)
        ShowTab("items")
    end)
    row.edit:SetPoint("RIGHT", row.remove, "LEFT", -SLOT_GAP * 2, 0)
    -- Order is priority: an item goes to the first sack in the list whose lines it matches.
    local function move(by)
        local _, index = FindGroup(row.group.name)
        local other = SacksDB.groups[index + by]
        if not other then return end
        SacksDB.groups[index], SacksDB.groups[index + by] = other, SacksDB.groups[index]
        Refresh()
    end
    row.down = MakeButton(row, "Down", 50, function() move(1) end)
    row.down:SetPoint("RIGHT", row.edit, "LEFT", -SLOT_GAP * 2, 0)
    row.up = MakeButton(row, "Up", 50, function() move(-1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -SLOT_GAP, 0)
    return row
end

local function BuildSacks(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", MARGIN, -CONTENT_TOP)
    page:SetSize(WINDOW_WIDTH - MARGIN * 2, 100)

    page.rows = {}
    page.rowOffset = 0
    page.scroll = MakeScrollbar(page, WINDOW_WIDTH - MARGIN * 2 + 3, 0, function(offset)
        page.rowOffset = offset
        RefreshSettings()
    end)
    page.priorityHint = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, 0)
    page.priorityHint:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    page.priorityHint:SetText("Order is priority: an item goes to the first sack below whose lines it matches. Up and Down change the order. A sack with no lines takes nothing.")
    -- A header strip like the Items table's. These are labels, so they are greyed out and do nothing.
    page.listHeader = MakeText(page, "GameFontNormal", "TOPLEFT", 0, 0)
    page.listHeader:SetText("Sacks")
    page.listRule = page:CreateTexture(nil, "ARTWORK")
    page.listRule:SetColorTexture(1, 1, 1, 0.18)
    page.listRule:SetSize(WINDOW_WIDTH - MARGIN * 2, 1)
    page.heads = {}
    for _, head in ipairs({ { "Sack", 0, 172 }, { "Items", 174, 48 }, { "Takes", 224, 252 } }) do
        local button = MakeButton(page, head[1], head[3], function() end)
        button:Disable()
        page.heads[#page.heads + 1] = { button = button, x = head[2] }
    end
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(self, delta)
        self.rowOffset = math.max(0, (self.rowOffset or 0) - delta * WHEEL_STEP)
        RefreshSettings()
    end)

    page.hideCheck = MakeCheck(page, "Stop the game opening its own bags by itself (vendors etc.); B and the bag buttons still work", function(self)
        SacksDB.hideBags = self:GetChecked() and true or false
        HideOwnBags()
    end)
    page.hideCheck:SetPoint("TOPLEFT", -4, -4)
    page.widgetCheck = MakeCheck(page, "Show a free-slots box I can place anywhere", function(self)
        WidgetGroup().shown = self:GetChecked() and true or false
        Refresh()
    end)
    page.widgetCheck:SetPoint("TOPLEFT", -4, -(4 + CHECK_SIZE + PADDING))
    page.bagInfo = MakeText(page, "GameFontHighlightSmall", "TOPLEFT", 0, -(4 + 2 * (CHECK_SIZE + PADDING)))
    page.bagInfo:SetWidth(WINDOW_WIDTH - MARGIN * 2)

    local section = CreateFrame("Frame", nil, page)
    section:SetSize(WINDOW_WIDTH - MARGIN * 2, SECTION_HEIGHT)
    page.newSection = section
    MakeText(section, "GameFontNormal", "TOPLEFT", 0, 0):SetText("New sack")
    MakeText(section, "GameFontDisableSmall", "TOPLEFT", 80, -2):SetText("give it a name; its lines are set on the Items tab")
    local newRule = section:CreateTexture(nil, "ARTWORK")
    newRule:SetColorTexture(1, 1, 1, 0.18)
    newRule:SetPoint("TOPLEFT", 0, -(LABEL_HEIGHT + 3))
    newRule:SetSize(WINDOW_WIDTH - MARGIN * 2, 1)
    page.nameEdit = NativeFrame("EditBox", section, "InputBoxTemplate")
    page.nameEdit:SetSize(CHOICE_WIDTH + 30, BUTTON_HEIGHT)
    page.nameEdit:SetPoint("TOPLEFT", 6, -LABEL_HEIGHT - 12)
    page.nameEdit:SetAutoFocus(false)
    page.nameEdit:SetMaxLetters(32)
    page.nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.createButton = MakeButton(section, "New sack", 90, function()
        local name = (page.nameEdit:GetText() or ""):match("^%s*(.-)%s*$")
        if name == "" then return Say("type a name for the sack first") end
        if FindGroup(name) then return Say("there is already a sack called " .. name) end
        -- It starts with no lines, and a sack with no lines takes nothing, so it can't swallow items before it is set up.
        local group = { name = name, rule = {}, point = "CENTER", x = 0, y = 0 }
        table.insert(SacksDB.groups, 1, group)
        page.nameEdit:SetText("")
        state.editing = group
        Refresh()
        LoadSack(settings.items, group)
        ShowTab("items")
    end)
    page.createButton:SetPoint("LEFT", page.nameEdit, "RIGHT", 10, 0)
    page.resetButton = MakeButton(section, "Reset to starting sacks", 160, function()
        for _, group in ipairs(SacksDB.groups) do HideRemoved(group) end
        SacksDB.groups = DefaultGroups()
        Refresh()
    end)
    page.resetButton:SetPoint("LEFT", page.createButton, "RIGHT", 10, 0)

    -- Defaults that every sack falls back on, in a tinted box of their own.
    local defaults = CreateFrame("Frame", nil, page)
    defaults:SetSize(WINDOW_WIDTH - MARGIN * 2, 70)
    page.defaults = defaults
    local rule = defaults:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.18)
    rule:SetPoint("TOPLEFT", 0, -(LABEL_HEIGHT + 3))
    rule:SetSize(WINDOW_WIDTH - MARGIN * 2, 1)
    MakeText(defaults, "GameFontNormal", "TOPLEFT", 0, 0):SetText("Defaults for all sacks")
    MakeText(defaults, "GameFontDisableSmall", "TOPLEFT", 160, -2):SetText("used by any sack that has no number of its own")
    MakeText(defaults, "GameFontHighlight", "TOPLEFT", 0, -46):SetText("Slots per row")
    local minus = MakeButton(defaults, "-", BUTTON_HEIGHT + 4, function()
        SacksDB.columns = math.max(1, (SacksDB.columns or DEFAULT_COLUMNS) - 1)
        Refresh()
    end)
    minus:SetPoint("TOPLEFT", 170, -42)
    page.defaultMinus = minus
    page.defaultCount = defaults:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.defaultCount:SetWidth(30)
    page.defaultCount:SetJustifyH("CENTER")
    page.defaultCount:SetPoint("LEFT", minus, "RIGHT", SLOT_GAP, 0)
    local plus = MakeButton(defaults, "+", BUTTON_HEIGHT + 4, function()
        SacksDB.columns = (SacksDB.columns or DEFAULT_COLUMNS) + 1
        Refresh()
    end)
    plus:SetPoint("LEFT", page.defaultCount, "RIGHT", SLOT_GAP, 0)
    return page
end

local function RefreshSacks()
    local page = settings.sacks
    page.hideCheck:SetChecked(SacksDB.hideBags ~= false)
    page.widgetCheck:SetChecked(WidgetGroup().shown and true or false)

    -- One quiet line about space; anything else only appears when something is actually wrong.
    local free = 0
    for _, bag in ipairs(state.bags or {}) do free = free + bag.free end
    local used = (state.slots or 0) - (state.freeAll or 0)
    local count = #(state.items or {})
    local lines = { string.format("Bag space: %d of %d slots used, %d free", used, state.slots or 0, free) }
    for _, bag in ipairs(state.bags or {}) do
        if bag.special then lines[#lines + 1] = string.format("   %s: %d of %d used", bag.name, bag.total - bag.free, bag.total) end
    end
    if (state.shown or 0) ~= count or used ~= count then
        lines[#lines + 1] = string.format("|cffff5555Showing %d of the %d items read (the game counts %d slots in use).|r",
            state.shown or 0, count, used)
    end
    local misfits, misfitNames = 0, {}
    for _, item in ipairs(state.items or {}) do
        if item.fitsBag and (item.fitsFree or 0) > 0 then
            misfits = misfits + 1
            if #misfitNames < 4 then misfitNames[#misfitNames + 1] = item.name end
        end
    end
    if misfits > 0 then
        lines[#lines + 1] = string.format("|cffffb31a%d item%s in normal bags would fit a special bag with room: %s%s|r",
            misfits, misfits == 1 and "" or "s", table.concat(misfitNames, ", "), misfits > #misfitNames and ", ..." or "")
    end
    page.bagInfo:SetText(table.concat(lines, "\n"))

    local top = 4 + 2 * (CHECK_SIZE + PADDING) + #lines * 13 + PADDING + 8
    page.listHeader:ClearAllPoints()
    page.listHeader:SetPoint("TOPLEFT", 0, -top)
    page.listRule:ClearAllPoints()
    page.listRule:SetPoint("TOPLEFT", 0, -(top + LABEL_HEIGHT + 3))
    top = top + LABEL_HEIGHT + PADDING + 4
    page.priorityHint:ClearAllPoints()
    page.priorityHint:SetPoint("TOPLEFT", 0, -top)
    top = top + 26
    for _, head in ipairs(page.heads) do
        head.button:ClearAllPoints()
        head.button:SetPoint("TOPLEFT", head.x, -top)
    end
    top = top + BUTTON_HEIGHT + 2
    local groups = AllGroups()
    local visible = math.min(#groups, ListRoom(top, PADDING + SECTION_HEIGHT, ROW_HEIGHT, 4, 10))
    page.rowOffset = math.max(0, math.min(page.rowOffset or 0, #groups - visible))
    page.scroll.set(#groups, visible, page.rowOffset, visible * ROW_HEIGHT, top)
    local real = #SacksDB.groups
    for index = 1, visible do
        local position = page.rowOffset + index
        local group = groups[position]
        local row = page.rows[index] or MakeRow(page)
        page.rows[index] = row
        row.group = group
        local held = state.counts[group] or 0
        row.name:SetText(group.name)
        row.stripe:SetColorTexture(1, 1, 1, position % 2 == 0 and 0.05 or 0)
        row.count:SetText(tostring(held))
        if held == 0 then row.count:SetTextColor(0.6, 0.6, 0.6) else row.count:SetTextColor(1, 1, 1) end
        row.desc:SetText((not group.fixed and #group.rule == 0) and "takes nothing yet: add lines on the Items tab" or Describe(group.rule))
        -- The last sack can't be edited, removed or moved: it is what keeps every item on screen.
        if group.fixed then
            row.edit:Hide()
            row.remove:Hide()
            row.up:Hide()
            row.down:Hide()
        else
            row.edit:Show()
            row.remove:Show()
            row.up:Show()
            row.down:Show()
            if position == 1 then row.up:Disable() else row.up:Enable() end
            if position == real then row.down:Disable() else row.down:Enable() end
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(top + (index - 1) * ROW_HEIGHT))
        row:Show()
    end
    for index = visible + 1, #page.rows do page.rows[index]:Hide() end
    local below = top + visible * ROW_HEIGHT + PADDING * 2
    page.newSection:ClearAllPoints()
    page.newSection:SetPoint("TOPLEFT", 0, -below)
    page.defaults:ClearAllPoints()
    page.defaults:SetPoint("TOPLEFT", 0, -(below + SECTION_HEIGHT + PADDING * 2))
    page.defaultCount:SetText(SacksDB.columns or DEFAULT_COLUMNS)
    page.height = below + SECTION_HEIGHT + PADDING * 2 + 76
    page:SetHeight(page.height)
    settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
end

---------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------

local function BuildSettings()
    -- One window only: it is remembered the moment it exists, so a failure further down can never lead to a second one.
    local window = NativeFrame("Frame", UIParent, "BasicFrameTemplateWithInset")
    settings = window
    window:SetSize(WINDOW_WIDTH, 300)
    window:SetPoint("TOP", UIParent, "TOP", 0, -30) -- the top edge stays put if the window ever has to grow
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- The game re-anchors a dragged frame by its own choice of point; pin the top left corner so the window
        -- always grows and shrinks downward from where you put it.
        local left, top = self:GetLeft(), self:GetTop()
        if type(left) == "number" and type(top) == "number" then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    window:Hide()
    if window.TitleText then
        window.TitleText:SetText("sacks")
    else
        MakeText(window, "GameFontNormalLarge", "TOP", 0, -8):SetText("sacks")
    end
    if not window.CloseButton then
        local close = NativeFrame("Button", window, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
    end
    tinsert(UISpecialFrames, "SacksSettings")
    _G.SacksSettings = window

    window.tabs = {}
    local previous
    for _, tab in ipairs({ { "sacks", "Sacks" }, { "items", "Items" }, { "layout", "Layout" } }) do
        local button = MakeButton(window, tab[2], 90, function() ShowTab(tab[1]) end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", SLOT_GAP, 0)
        else
            button:SetPoint("TOPLEFT", MARGIN, -(HEADER + 6))
        end
        window.tabs[tab[1]] = button
        previous = button
    end

    window.sacks = BuildSacks(window)
    window.items = BuildItems(window)
    window.layout = BuildLayout(window)
    window.active = "sacks"
end

function RefreshSettings()
    if not settings or not settings:IsShown() or not settings.layout then return end
    if settings.active == "items" then
        RefreshItems()
    elseif settings.active == "layout" then
        RefreshLayout()
    else
        RefreshSacks()
    end
end

-- Anything that goes wrong while building or filling the window is printed, never swallowed.
local function Guard(step, ...)
    local ok, err = pcall(step, ...)
    if not ok then Say("settings window error: " .. tostring(err)) end
    return ok
end

function ToggleSettings()
    if not settings then
        Guard(BuildSettings)
        if settings and settings.layout then Guard(ShowTab, "sacks") end
    end
    if not settings then return end
    if settings:IsShown() then
        settings:Hide()
    else
        settings:Show()
        Guard(RefreshSettings)
    end
end

-- A small bag icon you can drag anywhere; clicking it opens the settings.
local function MakeIcon()
    SacksDB.icon = SacksDB.icon or {}
    local saved = SacksDB.icon
    saved.angle = saved.angle or 200
    local host = Minimap or UIParent
    local button = CreateFrame("Button", "SacksIcon", host)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.dragged = false
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(25, 25)
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetSize(20, 20)
    button.texture:SetPoint("TOPLEFT", 6, -5)
    button.texture:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    button.texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Sits on the edge of the minimap at an angle you choose by dragging it around.
    local function place()
        local radius = (Minimap and Minimap:GetWidth() or 140) / 2 + 10
        local angle = math.rad(saved.angle)
        button:ClearAllPoints()
        button:SetPoint("CENTER", host, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    place()
    local arc = math.atan2 or math.atan
    button:SetScript("OnDragStart", function(self)
        self.dragged = true
        if not Minimap then return end
        self:SetScript("OnUpdate", function()
            local centerX, centerY = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local x, y = GetCursorPosition()
            if type(centerX) ~= "number" or not x then return end
            saved.angle = math.deg(arc(y / scale - centerY, x / scale - centerX))
            place()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnClick", function(self, mouse)
        if self.dragged then
            self.dragged = false
            return
        end
        if mouse == "RightButton" then return ToggleOwnBags() end
        ToggleSettings()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("sacks")
        GameTooltip:AddLine("Click for settings. Right click to open or close the game's own bags. Drag to move this icon around the minimap.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        SacksDB = SacksDB or {}
        SacksDB.groups = SacksDB.groups or DefaultGroups()
        for _, group in ipairs(SacksDB.groups) do
            group.rule = group.rule or {}
            if IsOldRule(group.rule) then group.rule = ToConditions(group.rule) end
        end
        EnsureFallback()
        MakeIcon()
        HookOwnBags()
        WrapUserBagToggles()
        HideOwnBags()
    elseif event == "BANKFRAME_OPENED" then
        state.bank = true
        return
    elseif event == "BANKFRAME_CLOSED" then
        state.bank = false
        return
    elseif event == "MERCHANT_SHOW" then
        state.vendor = true
    elseif event == "MERCHANT_CLOSED" then
        state.vendor = false
    elseif event == "PLAYER_REGEN_ENABLED" and not state.pending then
        return
    end
    Refresh()
end)
