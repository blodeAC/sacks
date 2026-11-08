-- sacks: ItemsTab.lua
local _, ns = ...
local AllGroups, BUTTON_HEIGHT, BitAnd, CONTENT_TOP = ns.AllGroups, ns.BUTTON_HEIGHT, ns.BitAnd, ns.CONTENT_TOP
local ClassOptions, DROPDOWN_HEIGHT, Describe, FindGroup, ItemClassInfo = ns.ClassOptions, ns.DROPDOWN_HEIGHT, ns.Describe, ns.FindGroup, ns.ItemClassInfo
local ItemSubClassInfo, LINE_HEIGHT, LastBag, MARGIN, MakeButton, MakeChoice = ns.ItemSubClassInfo, ns.LINE_HEIGHT, ns.LastBag, ns.MARGIN, ns.MakeButton, ns.MakeChoice
local MakeText, Matches, OperatorOptions, PADDING, PatternError = ns.MakeText, ns.Matches, ns.OperatorOptions, ns.PADDING, ns.PatternError
local QualityName, QualityOptions, Refresh, STATS, Say, Stat = ns.QualityName, ns.QualityOptions, ns.Refresh, ns.STATS, ns.Say, ns.Stat
local SubClassOptions, TABLE_ROW_HEIGHT, TextMatches, ValueText, WHEEL_STEP, WINDOW_WIDTH = ns.SubClassOptions, ns.TABLE_ROW_HEIGHT, ns.TextMatches, ns.ValueText, ns.WHEEL_STEP, ns.WINDOW_WIDTH
local state = ns.state
local ButtonWidth, SLOT_GAP, TextWidth, DROPDOWN_INSET, LABEL_HEIGHT = ns.ButtonWidth, ns.SLOT_GAP, ns.TextWidth, ns.DROPDOWN_INSET, ns.LABEL_HEIGHT
local NAME_WIDTH, MakeTextBox, ItemInfo, CreateSack = ns.NAME_WIDTH, ns.MakeTextBox, ns.ItemInfo, ns.CreateSack
local NUMBER_WIDTH = math.ceil(TextWidth(string.rep("0", 8))) + 2 * PADDING
local TEXT_MIN = math.ceil(TextWidth(string.rep("M", 6))) + 2 * PADDING -- the least a pattern box may shrink to
local WARN_WIDTH = math.ceil(TextWidth("bad pattern", "GameFontNormalSmall")) + PADDING
local TEXT_DROP = (BUTTON_HEIGHT - LABEL_HEIGHT) / 2 -- puts a label level with a button
local INFO_HEIGHT = LABEL_HEIGHT + SLOT_GAP
local SUMMARY_HEIGHT = 2 * LABEL_HEIGHT + PADDING

---------------------------------------------------------------------------------------------------
-- All items: every kind of item you carry (or have carried), with what the game says about it and the sack it goes
-- to. Select items to make a sack from what they share. This file also holds the rule lines (what a sack takes), which
-- the sack page and the sort steps use.
---------------------------------------------------------------------------------------------------

local sort = { key = "class", descending = false }

local function Num(value) return value or -1 end
-- Sample texts for sizing a column: the widest thing the game can put in it.
local function Widest(lookup)
    local names = {}
    for _, name in ns.ScanNames(lookup) do names[#names + 1] = name end
    return names
end
local function ClassNames() return Widest(ItemClassInfo) end
local function SubNames()
    local names = {}
    for class in ns.ScanNames(ItemClassInfo) do
        for _, name in ipairs(Widest(function(sub) return ItemSubClassInfo(class, sub) end)) do names[#names + 1] = name end
    end
    return names
end
local function QualityNames()
    local names = {}
    for _, value in pairs(Enum.ItemQuality) do names[#names + 1] = QualityName(value) end
    return names
end
local function EquipNames()
    local names = {}
    for _, option in ipairs(Stat.Options and Stat.Options("equip") or {}) do names[#names + 1] = option.label end
    return names
end
local function BindNames() return Stat.bindShort end
local function FamilyNames()
    local names = {}
    for _, entry in ipairs(Stat.families or {}) do names[#names + 1] = entry[2] end
    return names
end

local COLUMNS = {
    { key = "name", title = "Item", samples = function() return { "Greater Mana Restoration Potion" } end, order = function(r) return r.name:lower() end,
        text = function(r) return r.name end },
    { key = "class", title = "Class", samples = function() return ClassNames() end, order = function(r) return r.classText end,
        text = function(r) return r.classText end },
    { key = "sub", title = "Subclass", samples = function() return SubNames() end, order = function(r) return r.subText end,
        text = function(r) return r.subText end },
    { key = "quality", title = "Quality", samples = function() return QualityNames() end, order = function(r) return r.quality end,
        text = function(r) return r.qualityText end },
    -- These come and go: a column for each fact your lines test, plus the reagent flag and the special bag type.
    { key = "ilvl", title = "iLvl", samples = function() return { "0000" } end, extra = true, order = function(r) return Num(r.itemLevel) end,
        text = function(r) return r.itemLevel and tostring(r.itemLevel) or "" end },
    { key = "level", title = "Req", samples = function() return { "000" } end, extra = true, order = function(r) return Num(r.minLevel) end,
        text = function(r) return r.minLevel and tostring(r.minLevel) or "" end },
    { key = "equip", title = "Slot", samples = function() return EquipNames() end, extra = true, order = function(r) return Stat.Format("equip", r.equip or "NONE") end,
        text = function(r) return (r.equip and r.equip ~= "NONE") and Stat.Format("equip", r.equip) or "" end },
    { key = "bind", title = "Binds", samples = function() return BindNames() end, extra = true, order = function(r) return Num(r.bindType) end,
        text = function(r) return Stat.bindShort[r.bindType or 0] or "" end },
    { key = "bound", title = "Bound", samples = function() return { "yes" } end, extra = true, order = function(r) return r.bound or 0 end,
        text = function(r) return r.bound == 1 and "yes" or "" end },
    { key = "reagent", title = "Reagent", samples = function() return { "yes" } end, extra = true, order = function(r) return r.reagent or 0 end,
        text = function(r) return r.reagent == 1 and "yes" or "" end },
    { key = "price", title = "Sells for", samples = function() return { "999g 99s 99c" } end, extra = true, order = function(r) return r.sellPrice or 0 end,
        text = function(r) return (r.sellPrice or 0) > 0 and Stat.MoneyText(r.sellPrice) or "" end },
    { key = "stack", title = "Stack", samples = function() return { "0000" } end, extra = true, order = function(r) return Num(r.stackMax) end,
        text = function(r) return r.stackMax and tostring(r.stackMax) or "" end },
    { key = "family", title = "Bag type", samples = function() return FamilyNames() end, extra = true, order = function(r) return Stat.FamilyText(r.family) end,
        text = function(r) return Stat.FamilyText(r.family) end },
    { key = "count", title = "Have", samples = function() return { "00000" } end, order = function(r) return r.count end,
        text = function(r) return tostring(r.count) end },
    { key = "sack", title = "In sack", order = function(r) return r.sack end, text = function(r) return r.sack end },
}

-- A fixed column is as wide as its header button or its widest sample, whichever is more (measured once).
local function Fixed(column)
    if not column.samples then return nil end
    if not column.fitted then
        local inset = (column.key == "name" and TABLE_ROW_HEIGHT + 3 or 4) + SLOT_GAP
        local widest = ButtonWidth(column.title)
        for _, text in pairs(column.samples()) do
            widest = math.max(widest, math.ceil(TextWidth(tostring(text))) + inset)
        end
        column.fitted = widest
    end
    return column.fitted
end

-- Which columns the table shows now: the fixed ones, then extras for every fact the lines test (on a sack's page) and
-- for the reagent flag and the special bag type, while there is room. The last column takes whatever width is left.
local function ActiveColumns(page)
    local base = 0
    for _, column in ipairs(COLUMNS) do
        if Fixed(column) and not column.extra then base = base + Fixed(column) end
    end
    local room = WINDOW_WIDTH - MARGIN * 2 - base - 2 * ButtonWidth("In sack")
    local show, wanted = {}, {}
    for _, clause in ipairs(page.draft or {}) do wanted[#wanted + 1] = clause.field end
    wanted[#wanted + 1] = "reagent"
    wanted[#wanted + 1] = "family"
    for _, key in ipairs(wanted) do
        for _, column in ipairs(COLUMNS) do
            if column.extra and column.key == key and not show[key] and room >= Fixed(column) then
                show[key] = true
                room = room - Fixed(column)
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
    if Fixed(column) then return Fixed(column) end
    local used = 0
    for _, other in ipairs(active or COLUMNS) do
        if Fixed(other) and (active or not other.extra) then used = used + Fixed(other) end
    end
    return WINDOW_WIDTH - MARGIN * 2 - used
end

-- One row per item kind: what is in your bags now, plus every kind you have seen before (shown with 0).
-- The rows are worked out once per refresh of the sacks (and again when the table is sorted another way), however many
-- times they are asked for in between: the pages, the line editor and typing an item's name all use the same rows.
local rowsCache, rowsKey
local function BuildItemRows()
    local key = tostring(state.generation or 0) .. ":" .. tostring(sort.key) .. ":" .. tostring(sort.descending)
    if rowsCache and rowsKey == key then return rowsCache end
    local rows, byId = {}, {}
    local function add(id, fields, count)
        local row = byId[id]
        if not row then
            row = { itemID = id, name = fields.name or ("item " .. id), icon = fields.icon, classID = fields.classID,
                subClassID = fields.subClassID, quality = fields.quality or 0, count = 0, sellPrice = fields.sellPrice,
                itemLevel = fields.itemLevel, minLevel = fields.minLevel, stackMax = fields.stackMax,
                equip = fields.equip, bindType = fields.bindType, reagent = fields.reagent, bound = fields.bound,
                family = fields.family, tip = fields.tip, bag = fields.bag or (LastBag() + 1), slot = fields.slot or 0 }
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
    rowsCache, rowsKey = rows, key
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

-- A sack's lines are edited as a draft: a list of lines you can add, remove and reorder. Lines that say nothing yet (an
-- empty text, an item not found) are left out of the rule the draft makes.
local MAX_LINES = 10
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
    return { field = field == "tooltip" and "tooltip" or "name", op = "contains", value = "" }
end

local function CopyCondition(condition)
    local copy = {}
    for key, value in pairs(condition) do copy[key] = value end
    return copy
end

-- What the lines currently say: lines that say nothing yet are left out, and the first line has no join.
local function DraftRule(draft)
    local rule = {}
    for _, condition in ipairs(draft) do
        local text = condition.field == "name" or condition.field == "tooltip"
        local empty = (text and (type(condition.value) ~= "string" or condition.value == ""))
            or (condition.field == "item" and not condition.value)
        if not empty then
            local copy = CopyCondition(condition)
            copy.auto, copy.typed = nil, nil
            if #rule == 0 then copy.join = nil end
            rule[#rule + 1] = copy
        end
    end
    return rule
end

-- An item's name, from what the game told us when you carried it, else from the game now.
local function ItemName(id)
    local seen = id and SacksDB.seen and SacksDB.seen[id]
    if seen and seen.name then return seen.name end
    return id and ItemInfo and ItemInfo(id) or nil
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
    if mode == "fits" and not (page.fits and page.fits(row)) then return false end
    local search = page.search and page.search:GetText() or ""
    if type(search) == "string" and search ~= "" then
        local op = PatternError(search) and "contains" or "matches"
        if not TextMatches(op, search, row.name) then return false end
    end
    return true
end

-- The lines for a sack that takes the selected items. Items sharing a bag type, or a class (and subclass), give those
-- lines; otherwise whatever else they share; otherwise the items themselves, each as an "Exact item" line joined with or.
local function RuleFromSelection(selected)
    local rule = {}
    local added = 0
    local function add(condition)
        if #rule < MAX_LINES then
            rule[#rule + 1] = condition
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
    return rule
end

-- Makes a sack that takes what the rule says, named from it, and opens it on the sack page.
local function SackFromRule(rule, itemName)
    local group, problem = CreateSack(UniqueName(SuggestName(rule, itemName)), rule)
    if not group then return Say(problem) end
    Say("made the sack " .. group.name .. ": " .. Describe(rule))
    state.selected = {}
    Refresh()
    ns.EditSack(group)
end

-- A line starts with the dots you drag it by, then "Take if" (or its and/or box); its x is at the right edge. The boxes
-- flow left to right, each as wide as its widest text, one PADDING apart.
local LINE_START = ns.GRIP_WIDTH
local REMOVE_ROOM = ButtonWidth("x") + PADDING -- the x at the right edge, and the gap before it

local function FieldOptions()
    local options = ns.RuleFields()
    options[#options + 1] = { label = "Exact item", value = "item" } -- only a rule line can name one item
    return options
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
    bar:SetWidth(SLOT_GAP * 2)
    bar:EnableMouse(true)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, 0.5)
    bar.thumb = CreateFrame("Button", nil, bar)
    bar.thumb:SetWidth(SLOT_GAP * 2)
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
    function bar.set(total, visible, offset, height, newTop, newX)
        if newTop then top = newTop end
        if newX then x = newX end
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
    -- While the thumb is held (and only then) it follows the mouse each frame.
    local function follow()
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            bar.dragging = false
            bar:SetScript("OnUpdate", nil)
            return
        end
        if bar.travel > 0 then
            go(bar.startOffset + (bar.startCursor - cursor()) / bar.travel * (bar.total - bar.visible))
        end
    end
    bar.thumb:SetScript("OnMouseDown", function()
        bar.dragging, bar.startCursor, bar.startOffset = true, cursor(), bar.offset
        bar:SetScript("OnUpdate", follow)
    end)
    bar.thumb:SetScript("OnMouseUp", function()
        bar.dragging = false
        bar:SetScript("OnUpdate", nil)
    end)
    bar:SetScript("OnMouseDown", function()
        local thumbTop = bar:GetTop() - bar.travel * bar.offset / math.max(1, bar.total - bar.visible)
        go(bar.offset + (cursor() > thumbTop and -bar.visible or bar.visible))
    end)
    return bar
end

-- The field picker of a line changed: start a new condition for the field. An exact item starts as the one item
-- selected in the All items table, if there is one, else empty for you to type its name; a subclass starts in the
-- class of the first Class line there is.
local function ChangeField(line, page, changed)
    local field = line.field.value()
    if field == line.clause.field then return end
    local condition
    if field == "item" then
        condition = { field = "item", op = "=", value = Shared(SelectedRows(BuildItemRows())).id }
    else
        condition = NewCondition(field)
        if field == "sub" then
            -- a new subclass line starts in the class of the first Class line there is
            for _, other in ipairs(page.draft) do
                if other.field == "class" and other.op == "=" then
                    condition.class = other.value
                    local first = SubClassOptions(other.value, false)[1]
                    condition.value = first and first.value or 0
                    break
                end
            end
        end
    end
    condition.join = line.clause.join
    page.draft[line.index] = condition
    changed()
end

-- The class picker of a line changed. The subclass lines that were using this Class line follow it to the new class.
local function ChangeClass(line, changed)
    if line.clause.field == "sub" then
        line.clause.class = line.class.value()
        local sub = SubClassOptions(line.clause.class, false)[1]
        line.clause.value = sub and sub.value or 0
    else
        local before, now = line.clause.value, line.class.value()
        line.clause.value = now
        -- the subclass lines that were using this Class line follow it to the new class
        if line.clause.field == "class" and before ~= now then
            for _, other in ipairs(line.page.draft) do
                if other.field == "sub" and other.class == before then
                    other.class = now
                    local first = SubClassOptions(now, false)[1]
                    other.value = first and first.value or 0
                end
            end
        end
    end
    changed()
end

-- The dots you drag a line by, its x, and the words in front of the first line.
local function MakeLineButtons(line, page, changed, plainY)
    line.remove = MakeButton(line, "x", nil, function()
        table.remove(page.draft, line.index)
        changed()
    end)
    line.remove:SetPoint("TOPRIGHT", 0, plainY)
    -- the row it belongs to, tinted while the mouse is on it: the x is at the far end of a wide row
    line.removeArea = CreateFrame("Frame", nil, line)
    line.removeArea:SetPoint("TOPLEFT", 0, plainY)
    line.removeArea:SetPoint("TOPRIGHT", 0, plainY)
    line.removeArea:SetHeight(BUTTON_HEIGHT)
    ns.MarkWhatGoes(line.remove, line.removeArea)
    -- Dragging a line to a new place keeps each and/or where it is, so the first line never carries one.
    line.grip = ns.MakeGrip(line, BUTTON_HEIGHT)
    line.grip:SetPoint("TOPLEFT", 0, plainY) -- level with the buttons
    ns.Reorderable(line.grip, page, function()
        local shown = {}
        for index = 1, #page.draft do shown[index] = page.lines[index] end
        return shown
    end, function() return line.index end, function(from, to)
        local draft = page.draft
        local joins = {}
        for index, clause in ipairs(draft) do joins[index] = clause.join end
        table.insert(draft, to, table.remove(draft, from))
        for index, clause in ipairs(draft) do clause.join = joins[index] end
        changed()
    end, line)

    line.firstText = MakeText(line, "GameFontHighlight", "TOPLEFT", LINE_START, plainY - TEXT_DROP)
    line.firstText:SetText("Take if")
end

-- The pickers of a line. FillLine decides which of them show, for the field the line is about.
local function MakeLineChoices(line, page, changed)
    line.gate = MakeChoice(line, nil, LINE_START, 0, function() return GATE_OPTIONS end, function()
        line.clause.join = line.gate.value() == "OR" and "OR" or nil
        changed()
    end)
    line.field = MakeChoice(line, nil, LINE_START, 0, function() return (rawget(page, "fieldOptions") or FieldOptions)() end, function()
        ChangeField(line, page, changed)
    end)
    line.op = MakeChoice(line, nil, LINE_START, 0, function() return OperatorOptions(line.clause and line.clause.field or "class") end,
        function()
            line.clause.op = line.op.value()
            changed()
        end)
    line.class = MakeChoice(line, nil, LINE_START, 0, function() return ClassOptions(false) end, function()
        ChangeClass(line, changed)
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
end

-- The item you mean by a name you typed: the one whose name it is, or the only one whose name has it in it. Looks
-- through everything you carry or have carried. Returns the item (or nil) and how many items the text fits.
local function FindItem(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$"):lower()
    if text == "" then return nil, 0 end
    local found, count = nil, 0
    for _, row in ipairs(BuildItemRows()) do
        local name = row.name:lower()
        if name == text then return row.itemID, 1 end
        if name:find(text, 1, true) then found, count = row.itemID, count + 1 end
    end
    if count == 1 then return found, 1 end
    return nil, count
end

-- What you can type in a text box, shown when the mouse is over it. A "matches pattern" line takes the full set of symbols;
-- the other lines only split alternatives with |.
local PATTERN_SYMBOLS = {
    { ".", "any one character" },
    { ".*", "any run of characters" },
    { "^", "start of the text" },
    { "$", "end of the text" },
}

local function ShowTextHelp(box, clause)
    if clause and clause.field == "item" then
        GameTooltip:SetOwner(box, "ANCHOR_TOP")
        GameTooltip:SetText("Exact item", 1, 0.82, 0)
        GameTooltip:AddLine("Type its name, or any part of the name that only one item you carry or have carried has.", 1, 1, 1, true)
        GameTooltip:AddLine("Upper and lower case do not matter.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
        return
    end
    local pattern = clause and (clause.op == "matches" or clause.op == "!matches")
    GameTooltip:SetOwner(box, "ANCHOR_TOP")
    GameTooltip:SetText(pattern and "Pattern" or "Text", 1, 0.82, 0)
    if pattern then
        for _, symbol in ipairs(PATTERN_SYMBOLS) do
            GameTooltip:AddDoubleLine(symbol[1], symbol[2], 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    GameTooltip:AddDoubleLine("||", "either side, like fire||frost", 1, 1, 1, 0.8, 0.8, 0.8)
    if not pattern then
        -- the symbols only work in a pattern; say where they are rather than leave the list looking cut short
        GameTooltip:AddLine('For  .  .*  ^  $  pick "matches pattern".', 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine("Upper and lower case do not matter.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- The boxes you type into (a number, or text), the warning at the right, and the label for an exact item.
local function MakeLineEntry(line, changed, plainY)
    line.number = MakeTextBox(line, NUMBER_WIDTH, function(self, typed)
        if not typed or not line.clause then return end
        local value = Stat.Parse(line.clause.field, self:GetText())
        if value ~= nil and value ~= line.clause.value then
            line.clause.value = value
            changed()
        end
    end)

    line.text = MakeTextBox(line, NAME_WIDTH * 2, function(self, typed)
        if not typed or not line.clause then return end
        if line.clause.field == "item" then
            -- what you typed is kept (so the box is not rewritten under you); the item it names is the value
            line.clause.typed = self:GetText()
            line.clause.value = (FindItem(line.clause.typed))
        else
            line.clause.value = self:GetText()
        end
        changed()
    end)
    line.text:SetPoint("TOPLEFT", LINE_START, plainY)
    line.text:SetScript("OnEnter", function(self) ShowTextHelp(self, line.clause) end)
    line.text:SetScript("OnLeave", function() GameTooltip:Hide() end)
    line.warn = MakeText(line, "GameFontNormalSmall", "TOPRIGHT", 0, plainY - TEXT_DROP)
    line.warn:SetTextColor(1, 0.3, 0.3)
    line.itemLabel = MakeText(line, "GameFontHighlight", "TOPLEFT", LINE_START, plainY - TEXT_DROP)
end

local function MakeLine(page)
    local line = CreateFrame("Frame", nil, page)
    line.page = page
    line.clause = false -- set by FillLine; the pickers below read it when they are built
    line:SetSize(rawget(page, "lineWidth") or (WINDOW_WIDTH - MARGIN * 2), LINE_HEIGHT)
    local plainY = -ns.LINE_LIFT
    local function changed()
        if line.clause then line.clause.auto = nil end -- once you touch a line it is yours
        -- A list that is not a sack's own rule says what to redraw when one of its lines changes.
        local onChange = rawget(page, "onChange")
        if onChange then onChange() else ns.RefreshSettings() end
    end

    MakeLineButtons(line, page, changed, plainY)
    MakeLineChoices(line, page, changed)
    MakeLineEntry(line, changed, plainY)
    return line
end

-- The and/or box (or the words "Take if") in front of the line, and the line's own buttons.
local function ShowLineControls(line, clause, index, count)
    if index == 1 then
        line.gate.show(false)
        line.firstText:ClearAllPoints()
        line.firstText:SetPoint("TOPLEFT", rawget(line.page, "lineStart") or LINE_START, -(ns.LINE_LIFT + TEXT_DROP))
        line.firstText:Show()
    else
        line.firstText:Hide()
        line.gate.show(true)
        line.gate.select(clause.join or "AND")
    end
    local compact = rawget(line.page, "compact")
    if compact then
        -- the step owns the dots; extra lines only get an x
        line.grip:Hide()
        if index == 1 then line.remove:Hide() else line.remove:Show() end
    else
        line.grip:Show()
        line.grip.SetUsable(count > 1) -- greyed out when there is nowhere to drag it to
    end
end

-- Hides what a line only shows for some fields; FillLine shows what the field needs.
local function HideValueControls(line)
    line.class.show(false)
    line.sub.show(false)
    line.quality.show(false)
    line.pick.show(false)
    line.itemLabel:Hide()
    line.warn:SetText("")
    line.warn:SetTextColor(1, 0.3, 0.3)
end

-- The pickers this field needs, shown and set. Returns every box of the line, left to right.
local function ShowValuePickers(line, clause)
    local boxes = { line.gate, line.field, line.op }
    if clause.field == "class" then
        line.class.show(true)
        line.class.select(clause.value)
        boxes[#boxes + 1] = line.class
    elseif clause.field == "sub" then
        -- A Class line that says the same class already says it, so the subclass does not ask again. Otherwise it
        -- asks for its own class and nothing is changed behind your back. (When you change a Class line, the
        -- subclass lines that were using it follow; that happens when you change it, not when the lines are drawn.)
        local owner
        for _, other in ipairs(line.page.draft) do
            if other.field == "class" and other.op == "=" and other.value == clause.class then owner = other break end
        end
        if owner then
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
    return boxes
end

-- Puts the boxes in a row. Each is as wide as the longest text it can hold; if the row would run past the window, the gaps
-- between boxes shrink (down to a small minimum) until it fits. Returns where the row ends.
local function PlaceBoxes(line, clause, boxes)
    local start = rawget(line.page, "lineStart") or LINE_START
    local reserve = rawget(line.page, "lineReserve") or (WARN_WIDTH + REMOVE_ROOM)
    -- The first box of every line starts in the same column: past the widest of the words in front of the first line
    -- and the and/or box of the lines after it (which sits at the left edge, where the words are), and past the
    -- column a sort step asks for.
    line.gate.fit()
    line.gate.moveTo(start, 0)
    table.remove(boxes, 1)
    local words = math.ceil(TextWidth(line.firstText:GetText() or "", "GameFontHighlight"))
    local firstX = start + math.max(rawget(line.page, "lineLead") or 0, words + PADDING, line.gate.seen() + PADDING)
    local total = 0
    for _, box in ipairs(boxes) do
        box.fit()
        total = total + box.seen()
    end
    -- A typing box needs room too, so the gaps shrink (down to SLOT_GAP) to leave it at least TEXT_MIN.
    local needsBox = clause.field == "name" or clause.field == "tooltip" or clause.field == "item" or (STATS[clause.field] and STATS[clause.field].kind ~= "pick")
    local room = WINDOW_WIDTH - MARGIN * 2 - firstX - reserve - (needsBox and TEXT_MIN or 0)
    local gap = PADDING
    if #boxes > 0 and total + #boxes * gap > room then
        gap = math.max(SLOT_GAP, (room - total) / #boxes)
    end
    local x = firstX
    for _, box in ipairs(boxes) do
        box.moveTo(x, 0)
        x = x + box.seen() + gap
    end
    return x -- where whatever follows the boxes starts
end

-- The typing box (a number or text) or the item label that follows the pickers, and the warning at the right.
local function ShowValueEntry(line, clause, x)
    local compact = rawget(line.page, "compact")
    local reserve = rawget(line.page, "lineReserve") or (WARN_WIDTH + REMOVE_ROOM)
    local warnRight = compact and reserve or REMOVE_ROOM
    local ART = ns.TEXTBOX_ART_LEFT -- a typing box's frame sits this far right of where its art starts
    -- The two typing boxes are only hidden when this line no longer needs them. Hiding a box and showing it again
    -- would take the keyboard away from it after every letter you type.
    local wantNumber, wantText = false, false
    line.warn:ClearAllPoints()
    line.warn:SetPoint("TOPRIGHT", -warnRight, -(ns.LINE_LIFT + TEXT_DROP))
    if STATS[clause.field] and STATS[clause.field].kind ~= "pick" then
        wantNumber = true
        line.number:ClearAllPoints()
        line.number:SetPoint("TOPLEFT", x + ART, -ns.LINE_LIFT)
        if not line.number:IsShown() then line.number:Show() end
        if Stat.Parse(clause.field, line.number:GetText()) ~= clause.value then
            line.number:SetText(STATS[clause.field].kind == "money" and Stat.MoneyText(clause.value) or tostring(clause.value))
        end
        if STATS[clause.field].kind == "money" then
            line.warn:SetText("e.g. 1g 50s 25c  (a bare number is copper)")
            line.warn:SetTextColor(ns.Rgb(ns.COLOR.DIM))
        end
    elseif clause.field == "name" or clause.field == "tooltip" then
        line.text:ClearAllPoints()
        line.text:SetPoint("TOPLEFT", x + ART, -ns.LINE_LIFT)
        line.text:SetWidth(math.max(TEXT_MIN, WINDOW_WIDTH - MARGIN * 2 - x - ART - reserve))
        wantText = true
        if not line.text:IsShown() then line.text:Show() end
        if line.text:GetText() ~= clause.value then line.text:SetText(clause.value) end
        if clause.op == "matches" or clause.op == "!matches" then
            if PatternError(clause.value) then line.warn:SetText("bad pattern") end
        end
    elseif clause.field == "item" then
        -- a name box as wide as a long name, and what it found right after it
        line.text:ClearAllPoints()
        line.text:SetPoint("TOPLEFT", x + ART, -ns.LINE_LIFT)
        line.text:SetWidth(NAME_WIDTH)
        wantText = true
        if not line.text:IsShown() then line.text:Show() end
        local name = ItemName(clause.value)
        local shown = clause.typed or name or ""
        if line.text:GetText() ~= shown then line.text:SetText(shown) end
        line.warn:ClearAllPoints()
        line.warn:SetPoint("LEFT", line.text, "RIGHT", PADDING, 0)
        if clause.value then
            -- what a part of a name found; nothing when the box already says it
            if name and shown:lower() ~= name:lower() then
                line.warn:SetText(name)
                line.warn:SetTextColor(ns.Rgb(ns.COLOR.GREEN))
            end
        else
            local _, count = FindItem(clause.typed)
            if shown == "" then
                line.warn:SetText("type an item's name")
                line.warn:SetTextColor(ns.Rgb(ns.COLOR.DIM))
            elseif count == 0 then
                line.warn:SetText("no item you have carried is called that")
            else
                line.warn:SetText(count .. " items fit, type more of the name")
                line.warn:SetTextColor(ns.Rgb(ns.COLOR.AMBER))
            end
        end
    elseif clause.field ~= "class" and clause.field ~= "sub" and clause.field ~= "quality" and not STATS[clause.field] then
        line.itemLabel:ClearAllPoints()
        line.itemLabel:SetPoint("TOPLEFT", x, -(ns.LINE_LIFT + TEXT_DROP))
        line.itemLabel:SetText(ValueText(clause))
        line.itemLabel:Show()
    end
    if not wantNumber then line.number:Hide() end
    if not wantText then line.text:Hide() end
end

local function FillLine(line, clause, index, count)
    line.clause, line.index = clause, index
    line.field.select(clause.field)
    line.op.select(clause.op)
    ShowLineControls(line, clause, index, count)
    HideValueControls(line)
    local boxes = ShowValuePickers(line, clause)
    ShowValueEntry(line, clause, PlaceBoxes(line, clause, boxes))
end

-- Lays the table's columns out (only when the set changed), and falls back to Class if the sorted column went away.
local function LayoutColumns(page)
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
end

-- How many kinds of item a rule's lines fit, of all you carry or have carried, and how many of those you hold now.
-- (A sack higher in the list may take some of them first.)
local function RuleTakes(rule)
    local kinds, held = 0, 0
    if #rule == 0 then return kinds, held end
    for _, row in ipairs(BuildItemRows()) do
        if Matches(rule, row) then
            kinds = kinds + 1
            held = held + row.count
        end
    end
    return kinds, held
end

-- The table without the rows the Show and Search boxes leave out.
local function FilteredRows(all, page)
    local rows = {}
    for _, row in ipairs(all) do
        if PassesFilter(row, page) then rows[#rows + 1] = row end
    end
    return rows
end

-- Everything under the table follows its bottom edge.
local function PlaceBelowTable(page, visible)
    local y = page.tableTop + visible * TABLE_ROW_HEIGHT + PADDING
    page.info:ClearAllPoints()
    page.info:SetPoint("TOPLEFT", 0, -y)
    page.summary:ClearAllPoints()
    page.summary:SetPoint("TOPLEFT", 0, -(y + INFO_HEIGHT))
    y = y + INFO_HEIGHT + SUMMARY_HEIGHT
    page.fromSelection:ClearAllPoints()
    page.fromSelection:SetPoint("TOPLEFT", 0, -y)
    page.forget:ClearAllPoints()
    page.forget:SetPoint("LEFT", page.fromSelection, "RIGHT", 3 * MARGIN, 0)
    y = y + BUTTON_HEIGHT
    page.height = y
    page:SetHeight(y)
end

-- Fills the table's rows from the first one in view.
local function FillTable(page, rows, visible)
    for index, view in ipairs(page.view) do
        local row = index <= visible and rows[page.offset + index] or nil
        view.data = row
        if row then
            view.icon:SetTexture(row.icon)
            for _, column in ipairs(COLUMNS) do view.cells[column.key]:SetText(column.text(row)) end
            local dim = row.count == 0
            for _, cell in pairs(view.cells) do
                if dim then cell:SetTextColor(ns.Rgb(ns.COLOR.DIM)) else cell:SetTextColor(1, 1, 1) end
            end
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
            if color and not dim then view.cells.name:SetTextColor(color.r, color.g, color.b) end
            -- the sack is a place you can go to: drawn in gold, opened by right-clicking the row
            view.cells.sack:SetTextColor(ns.Rgb(ns.COLOR.GOLD))
            -- On a sack's page: green, the sack takes it; amber, its lines fit but a sack above it takes it first.
            local mark = page.markOf and page.markOf(row)
            if mark == "in" then view.inMark:Show() else view.inMark:Hide() end
            if mark == "taken" then view.takenMark:Show() else view.takenMark:Hide() end
            if not page.markOf and state.selected[row.itemID] then view.selected:Show() else view.selected:Hide() end
            view:Show()
        else
            view:Hide()
        end
    end
end

local function MarkSortedHeader(page)
    for _, column in ipairs(COLUMNS) do
        local mark = ""
        if sort.key == column.key then mark = sort.descending and "  v" or "  ^" end
        page.headers[column.key]:SetText(column.title .. mark)
    end
end


-- Which rows are in view, of how many (also after scrolling).
local function InfoLine(page, rows, all, visible)
    local last = math.min(#rows, page.offset + visible)
    page.info:SetText(string.format("%d-%d of %d kinds of item shown (%d known). Grey: none right now.",
        #rows == 0 and 0 or page.offset + 1, last, #rows, #all))
end

local function Summarize(page, rows, all, visible, selected)
    InfoLine(page, rows, all, visible)
    if #selected == 0 then
        page.summary:SetText("Click items to select them (Ctrl-click for more) to make a sack that takes items like them. Right-click an item to open its sack.")
    else
        local rule = RuleFromSelection(selected)
        page.summary:SetText(string.format("%d selected. A new sack would take: %s", #selected,
            #rule > 0 and Describe(rule) or "(nothing they share fits a line. Select ten or fewer to list them one by one.)"))
    end
end

-- Fills a table (this page's or a sack page's) with the rows that pass its filter, `visible` of them at a time.
local function ShowTable(page, all, visible, rows)
    LayoutColumns(page)
    rows = rows or FilteredRows(all, page)
    page.lastRows, page.lastVisible = rows, visible
    page.offset = math.min(page.offset or 0, math.max(0, #rows - visible))
    page.scroll.set(#rows, visible, page.offset, visible * TABLE_ROW_HEIGHT)
    FillTable(page, rows, visible)
    MarkSortedHeader(page)
    return rows
end

local function RefreshItems()
    local page = ns.settings.items
    local all = BuildItemRows()
    local selected = SelectedRows(all)
    -- The table is as tall as its rows need, up to what the screen leaves after the lines and buttons below it.
    local below = INFO_HEIGHT + SUMMARY_HEIGHT + BUTTON_HEIGHT
    local filtered = FilteredRows(all, page)
    local visible = math.max(math.min(#filtered, ListRoom(page.tableTop, below, TABLE_ROW_HEIGHT, 8, #page.view)), 8)
    local rows = ShowTable(page, all, visible, filtered)
    PlaceBelowTable(page, visible)
    Summarize(page, rows, all, visible, selected)
    if #selected > 0 then page.fromSelection:Enable() else page.fromSelection:Disable() end
    ns.FitWindow(page.height)
end

local FILTER_HEIGHT = BUTTON_HEIGHT + PADDING -- the Show and Search row above the table

-- The row above the table, starting at x0: Show, Search, and (on this page) the button that makes a sack from the
-- search. A sack's page shows "What its lines fit" instead of "Unsorted".
local function BuildFilterRow(page, x0, onSackPage)
    x0 = x0 or 0
    local labelY = -TEXT_DROP
    local showX = x0 + math.ceil(TextWidth("Show", "GameFontHighlight")) + PADDING
    MakeText(page, "GameFontHighlight", "TOPLEFT", x0, labelY):SetText("Show")
    page.show = MakeChoice(page, nil, showX, 0, function()
        local options = {
            { label = "In my bags now", value = "bags" },
            { label = "Everything I've carried", value = "all" },
        }
        if onSackPage then
            options[#options + 1] = { label = "What its lines fit", value = "fits" }
        else
            options[#options + 1] = { label = "Unsorted (in " .. SacksDB.fallback.name .. ")", value = "unsorted" }
        end
        return options
    end, function()
        page.offset = 0
        ns.RefreshSettings()
    end)
    -- the Show box is as wide as its longest choice; Search, its box and the button follow it left to right
    page.show.fit()
    local searchLabelX = showX + page.show.seen() + 3 * PADDING -- pairs of words and box are further apart than a word and its box
    MakeText(page, "GameFontHighlight", "TOPLEFT", searchLabelX, labelY):SetText("Search")
    local searchX = searchLabelX + math.ceil(TextWidth("Search", "GameFontHighlight")) + PADDING
    page.search = MakeTextBox(page, NAME_WIDTH, function(_, user)
        if user then
            page.offset = 0
            ns.RefreshSettings()
        end
    end)
    page.search:SetPoint("TOPLEFT", searchX + ns.TEXTBOX_ART_LEFT, 0)
    if onSackPage then return end
    -- a new sack that takes every item whose name fits the search, opened on the sack page
    page.searchSack = MakeButton(page, "Sack from search", nil, function()
        local text = page.search:GetText() or ""
        if text == "" then return Say("type something in the search box first") end
        SackFromRule({ { field = "name", op = PatternError(text) and "contains" or "matches", value = text } })
    end)
    page.searchSack:SetPoint("TOPLEFT", searchX + ns.TEXTBOX_ART_LEFT + NAME_WIDTH + PADDING, 0)
end

-- The column headers; a click sorts by that column, a second click flips it.
local function BuildHeaders(page)
    local x = 0
    for _, column in ipairs(COLUMNS) do
        local width = ColumnWidth(column)
        local header = MakeButton(page, column.title, width, function()
            if sort.key == column.key then
                sort.descending = not sort.descending
            else
                sort.key, sort.descending = column.key, false
            end
            ns.RefreshSettings()
        end)
        header:SetPoint("TOPLEFT", x, -FILTER_HEIGHT)
        page.headers[column.key] = header
        x = x + width
    end
    page.headerTop = FILTER_HEIGHT
end

-- One row of the table: its colours, its icon, a cell for each column, and what a click and the mouse do.
local function MakeTableRow(page, top, index)
    local view = CreateFrame("Button", nil, page)
    view:SetSize(WINDOW_WIDTH - MARGIN * 2, TABLE_ROW_HEIGHT)
    view:SetPoint("TOPLEFT", 0, -(top + (index - 1) * TABLE_ROW_HEIGHT))
    view:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    view.selected = view:CreateTexture(nil, "BACKGROUND")
    view.selected:SetAllPoints()
    view.selected:SetColorTexture(0.2, 0.45, 1, 0.4)
    view.hover = view:CreateTexture(nil, "BACKGROUND")
    view.hover:SetAllPoints()
    view.hover:SetColorTexture(1, 1, 1, 0.08)
    view.hover:Hide()
    view.inMark = view:CreateTexture(nil, "BACKGROUND")
    view.inMark:SetAllPoints()
    view.inMark:SetColorTexture(ns.MARK_IN[1], ns.MARK_IN[2], ns.MARK_IN[3], ns.MARK_IN[4])
    view.inMark:Hide()
    view.takenMark = view:CreateTexture(nil, "BACKGROUND")
    view.takenMark:SetAllPoints()
    view.takenMark:SetColorTexture(ns.MARK_TAKEN[1], ns.MARK_TAKEN[2], ns.MARK_TAKEN[3], ns.MARK_TAKEN[4])
    view.takenMark:Hide()
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
    view:SetScript("OnClick", function(self, mouse)
        local row = self.data
        if not row then return end
        if mouse == "RightButton" then
            -- open the sack this item goes to
            local group = FindGroup(row.sack)
            if group then ns.EditSack(group) end
            return
        end
        if page.onRowClick then return page.onRowClick(row) end
        if IsControlKeyDown and IsControlKeyDown() then
            state.selected[row.itemID] = not state.selected[row.itemID] or nil
        else
            local only = state.selected[row.itemID] and next(state.selected, next(state.selected)) == nil
            state.selected = {}
            if not only then state.selected[row.itemID] = true end
        end
        ns.RefreshSettings()
    end)
    view:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.data then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.data.itemID) then
                GameTooltip:SetText(self.data.name)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(page.clickHint or "Click: select it (Ctrl-click: add to the selection)", 0.5, 0.8, 1)
            GameTooltip:AddLine("Right-click: open " .. tostring(self.data.sack), 0.5, 0.8, 1)
            GameTooltip:Show()
        end
    end)
    view:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    return view
end

-- The table of items, its mouse wheel and its scrollbar.
local function BuildTable(page, top, most)
    for index = 1, most or 40 do
        page.view[index] = MakeTableRow(page, top, index)
    end

    -- Scrolling only refills the rows in view, from the rows the last refresh worked out.
    local function scrollTo(offset)
        local rows, visible = page.lastRows, page.lastVisible
        if not rows then
            page.offset = offset
            return ns.RefreshSettings()
        end
        page.offset = math.max(0, math.min(offset, #rows - visible))
        page.scroll.set(#rows, visible, page.offset, visible * TABLE_ROW_HEIGHT)
        FillTable(page, rows, visible)
        if page.afterScroll then page.afterScroll() end
    end
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(self, delta) scrollTo((self.offset or 0) - delta * WHEEL_STEP) end)

    page.tableTop = top
    page.scroll = MakeScrollbar(page, WINDOW_WIDTH - MARGIN * 2 + SLOT_GAP, top, scrollTo)
end

-- The item table on a sack's page: the same table, its Show and Search row starting at x0. The page sets markOf, fits,
-- onRowClick and draft on it.
local function BuildItemTable(parent, x0, most)
    local page = CreateFrame("Frame", nil, parent)
    page:SetSize(WINDOW_WIDTH - MARGIN * 2, 100)
    page.offset, page.headers, page.view = 0, {}, {}
    BuildFilterRow(page, x0, true)
    BuildHeaders(page)
    BuildTable(page, FILTER_HEIGHT + ns.ORDER_ROW_HEIGHT, most)
    return page
end

-- Drops what the game was told about items you no longer carry (pinned ones stay).
local function ForgetUnseenItems()
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
    rowsCache = nil
    Say(string.format("forgot %d kinds of item you no longer carry (pinned ones are kept)", #doomed))
    ns.RefreshSettings()
end

local function BuildItems(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetSize(WINDOW_WIDTH - MARGIN * 2, 100)
    page.offset, page.headers, page.view = 0, {}, {}

    BuildFilterRow(page)
    BuildHeaders(page)
    BuildTable(page, FILTER_HEIGHT + ns.ORDER_ROW_HEIGHT)
    page.info = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, 0)
    page.summary = MakeText(page, "GameFontNormal", "TOPLEFT", 0, 0)
    page.summary:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    page.fromSelection = MakeButton(page, "New sack from selection", nil, function()
        local selected = SelectedRows(BuildItemRows())
        if #selected == 0 then return Say("select items in the table first") end
        local rule = RuleFromSelection(selected)
        if #rule == 0 then return Say("those items share nothing a line can say. Select ten or fewer to list them one by one.") end
        SackFromRule(rule, selected[1].name)
    end)
    page.forget = MakeButton(page, "Forget items I don't have", nil, ForgetUnseenItems)
    page.afterScroll = function() InfoLine(page, page.lastRows, BuildItemRows(), page.lastVisible) end
    page.height = 100
    return page
end

-- shared with the files after this one
ns.BuildItemRows = BuildItemRows
ns.BuildItemTable = BuildItemTable
ns.ShowTable = ShowTable
ns.FilteredRows = FilteredRows
ns.ItemName = ItemName
ns.TABLE_TOP = FILTER_HEIGHT + ns.ORDER_ROW_HEIGHT
-- How wide the and/or box at the start of a line looks: sort steps line their own columns up with it.
ns.GateSeen = function()
    local widest = 0
    for _, option in ipairs(GATE_OPTIONS) do widest = math.max(widest, TextWidth(option.label)) end
    return math.ceil(widest) + 2 * DROPDOWN_INSET + ns.DROPDOWN_RIGHT
end
ns.BuildItems = BuildItems
ns.CopyCondition = CopyCondition
ns.DraftRule = DraftRule
ns.FillLine = FillLine
ns.ListRoom = ListRoom
ns.MAX_LINES = MAX_LINES
ns.MakeLine = MakeLine
ns.NewCondition = NewCondition
ns.MakeScrollbar = MakeScrollbar
ns.RefreshItems = RefreshItems
ns.RuleTakes = RuleTakes
ns.UniqueName = UniqueName
ns.sort = sort
