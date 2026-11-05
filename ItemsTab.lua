-- sacks: ItemsTab.lua
local _, ns = ...
local AddSack, AllGroups, BUTTON_HEIGHT, BitAnd, CHOICE_WIDTH, CONTENT_TOP = ns.AddSack, ns.AllGroups, ns.BUTTON_HEIGHT, ns.BitAnd, ns.CHOICE_WIDTH, ns.CONTENT_TOP
local ClassOptions, DROPDOWN_HEIGHT, Describe, FindGroup, HINT_HEIGHT, ItemClassInfo = ns.ClassOptions, ns.DROPDOWN_HEIGHT, ns.Describe, ns.FindGroup, ns.HINT_HEIGHT, ns.ItemClassInfo
local ItemSubClassInfo, LINE_HEIGHT, LastBag, MARGIN, MakeButton, MakeChoice = ns.ItemSubClassInfo, ns.LINE_HEIGHT, ns.LastBag, ns.MARGIN, ns.MakeButton, ns.MakeChoice
local MakeText, Matches, NativeFrame, OperatorOptions, PADDING, PatternError = ns.MakeText, ns.Matches, ns.NativeFrame, ns.OperatorOptions, ns.PADDING, ns.PatternError
local QualityName, QualityOptions, Refresh, STATS, Say, Stat = ns.QualityName, ns.QualityOptions, ns.Refresh, ns.STATS, ns.Say, ns.Stat
local SubClassOptions, TABLE_ROW_HEIGHT, TextMatches, ValueText, WHEEL_STEP, WINDOW_WIDTH = ns.SubClassOptions, ns.TABLE_ROW_HEIGHT, ns.TextMatches, ns.ValueText, ns.WHEEL_STEP, ns.WINDOW_WIDTH
local state = ns.state

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
    local page = ns.settings.items
    local selected = SelectedRows(BuildItemRows())
    -- While changing an existing sack the lines are the sack's own; a selected item is only there for "Exact item".
    -- Lines made from an earlier click ("auto") are replaced; lines that belong to the sack are not.
    local manual = false
    for _, line in ipairs(page.draft) do
        if not line.auto then manual = true end
    end
    if page.target and manual then return ns.RefreshSettings() end
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
    ns.RefreshSettings()
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
        ns.RefreshSettings()
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
    local page = ns.settings.items
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
    ns.settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
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
        ns.RefreshSettings()
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
            ns.RefreshSettings()
        end
    end)
    page.searchSack = MakeButton(page, "Sack from search", 140, function()
        local text = page.search:GetText() or ""
        if text == "" then return Say("type something in the search box first") end
        if #page.draft >= MAX_LINES then return Say("that is as many lines as a sack can have") end
        page.draft[#page.draft + 1] = { field = "name", op = PatternError(text) and "contains" or "matches", value = text }
        ns.RefreshSettings()
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
            ns.RefreshSettings()
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
        ns.RefreshSettings()
    end)

    page.tableTop = top
    page.scroll = MakeScrollbar(page, WINDOW_WIDTH - MARGIN * 2 + 3, top, function(offset)
        page.offset = offset
        ns.RefreshSettings()
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
        ns.RefreshSettings()
    end, CHOICE_WIDTH + 30)
    page.sackHint = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 56 + CHOICE_WIDTH + 30 + 40, -(y + (DROPDOWN_HEIGHT - 10) / 2))
    page.sackHint:SetText("pick an existing sack to change what it takes")
    y = y + DROPDOWN_HEIGHT

    -- The lines that say what the sack takes. RefreshItems places them, and everything below them, as they come and go.
    page.lineTop = y
    page.addButton = MakeButton(page, "Add a line", 110, function()
        if #page.draft >= MAX_LINES then return Say("that is as many lines as a sack can have") end
        page.draft[#page.draft + 1] = NewCondition("class")
        ns.RefreshSettings()
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
        ns.RefreshSettings()
    end)
    page.forget:SetPoint("LEFT", page.createButton, "RIGHT", 110, 0)
    y = y + BUTTON_HEIGHT

    page.height = y
    page:SetHeight(y)
    return page
end

-- shared with the files after this one
ns.BuildItemRows = BuildItemRows
ns.BuildItems = BuildItems
ns.ListRoom = ListRoom
ns.LoadSack = LoadSack
ns.MakeScrollbar = MakeScrollbar
ns.RefreshItems = RefreshItems
ns.sort = sort
