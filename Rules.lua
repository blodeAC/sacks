-- sacks: Rules.lua
local _, ns = ...
local BitAnd, ItemClassInfo, ItemSubClassInfo, OTHER_NAME, SCAN_LIMIT = ns.BitAnd, ns.ItemClassInfo, ns.ItemSubClassInfo, ns.OTHER_NAME, ns.SCAN_LIMIT

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

-- The fields a rule line can test, in the order the pickers list them (Items tab and Layout tab share this).
local function RuleFields()
    return { { label = "Class", value = "class" }, { label = "Subclass", value = "sub" },
        { label = "Quality", value = "quality" }, { label = "Name", value = "name" },
        { label = "Tooltip text", value = "tooltip" },
        { label = "Item level", value = "ilvl" }, { label = "Required level", value = "level" },
        { label = "Equip slot", value = "equip" }, { label = "Bind type", value = "bind" },
        { label = "Soulbound", value = "bound" }, { label = "Crafting reagent", value = "reagent" },
        { label = "Sell price", value = "price" }, { label = "Stack size", value = "stack" },
        { label = "Special bag type", value = "family" } }
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
    if field == "tooltip" then return TextMatches(condition.op, condition.value, item.tip) end
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
-- A text line with nothing typed in it yet says nothing, so it is left out wherever a rule is used.
local function IsBlankLine(condition)
    return (condition.field == "name" or condition.field == "tooltip") and (type(condition.value) ~= "string" or condition.value == "")
end

local function Matches(rule, item)
    local groupHolds = true
    for index, condition in ipairs(rule) do
        if not IsBlankLine(condition) then
            if index > 1 and condition.join == "OR" then
                if groupHolds then return true end
                groupHolds = true
            end
            if groupHolds and not ConditionMatches(condition, item) then groupHolds = false end
        end
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

local FIELD_TEXT = { class = "class", sub = "subclass", quality = "quality", name = "name", tooltip = "tooltip text", item = "item" }
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

-- A line of a rule in three pieces, as the Items tab shows it: what is tested, how, and against what.
local function ClauseParts(condition, rule)
    return FIELD_TEXT[condition.field] or STATS[condition.field].text, OP_TEXT[condition.op], ValueText(condition, rule)
end

local function Describe(rule)
    local text = ""
    for index, condition in ipairs(rule) do
        if index > 1 then text = text .. (condition.join == "OR" and "  OR  " or " and ") end
        local field, op, value = ClauseParts(condition, rule)
        text = text .. field .. " " .. op .. " " .. value
    end
    return text ~= "" and text or "everything else"
end

local SACK_COLUMN_X = -300 -- the starting sacks sit in one column this far left of the screen centre

-- Starting sacks, built from the game's own enums. The first sack that matches an item gets it.
local function DefaultGroups()
    local groups = {}
    local function add(name, rule, x, y)
        groups[#groups + 1] = { name = name, rule = rule, point = "CENTER", x = x, y = y }
    end
    add("Combat loot", {}, SACK_COLUMN_X, 300)
    groups[1].builtin = true
    add("Quest", { { field = "class", op = "=", value = Enum.ItemClass.Questitem } }, SACK_COLUMN_X, 200)
    add("Junk", { { field = "quality", op = "<=", value = Enum.ItemQuality.Poor } }, SACK_COLUMN_X, 100)
    add("Consumables", { { field = "class", op = "=", value = Enum.ItemClass.Consumable } }, SACK_COLUMN_X, 0)
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
    SacksDB.fallback = SacksDB.fallback or { name = OTHER_NAME, point = "CENTER", x = SACK_COLUMN_X, y = -100 }
    SacksDB.fallback.rule = {}
    SacksDB.fallback.fixed = true
end

-- The "Combat loot" sack is built in, like Other: it always exists and is first in the list. It has no rule: the sacks
-- cannot get new slots during combat, so it is where an item you loot in combat is shown until combat ends (then the
-- sacks are rebuilt and the item goes to its own sack). It is laid out like any sack and hidden outside combat unless
-- "always show" is on. Older saves had it as "New items" or not at all: that one is adopted, or one is made.
local COMBAT_NAME = "Combat loot"
local function EnsureCombatSack()
    local found
    for _, group in ipairs(SacksDB.groups) do
        if group.builtin then found = group end
    end
    if not found then
        for _, group in ipairs(SacksDB.groups) do
            if not found and (group.name == "New items" or group.name == COMBAT_NAME) then found = group end
        end
    end
    if found then
        for index, group in ipairs(SacksDB.groups) do
            if group == found then table.remove(SacksDB.groups, index) break end
        end
    else
        found = { point = "CENTER", x = SACK_COLUMN_X, y = 300 }
    end
    found.name = COMBAT_NAME
    found.builtin = true
    found.rule = {}
    found.hideEmpty = nil
    table.insert(SacksDB.groups, 1, found) -- first in the list: in combat it is what gets the new items
end

-- shared with the files after this one
ns.EnsureCombatSack = EnsureCombatSack
ns.RuleFields = RuleFields
ns.AllGroups = AllGroups
ns.DefaultGroups = DefaultGroups
ns.ClauseParts = ClauseParts
ns.Describe = Describe
ns.EnsureFallback = EnsureFallback
ns.FindGroup = FindGroup
ns.IsOldRule = IsOldRule
ns.Matches = Matches
ns.IsBlankLine = IsBlankLine
ns.OP_TEXT = OP_TEXT
ns.ParseRule = ParseRule
ns.PatternError = PatternError
ns.QualityName = QualityName
ns.STATS = STATS
ns.ScanNames = ScanNames
ns.Stat = Stat
ns.TextMatches = TextMatches
ns.ToConditions = ToConditions
ns.ValueText = ValueText
