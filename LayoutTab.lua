-- sacks: LayoutTab.lua
local _, ns = ...
local Describe, FillLine, MAX_LINES, MakeLine, NewCondition = ns.Describe, ns.FillLine, ns.MAX_LINES, ns.MakeLine, ns.NewCondition
local Say = ns.Say
local AllGroups, BUTTON_HEIGHT, BuildItemRows, CHECK_SIZE, CHOICE_WIDTH, CONTENT_TOP = ns.AllGroups, ns.BUTTON_HEIGHT, ns.BuildItemRows, ns.CHECK_SIZE, ns.CHOICE_WIDTH, ns.CONTENT_TOP
local DEFAULT_ANCHOR, DEFAULT_COLUMNS, DEFAULT_FLOW, DEFAULT_SORT, DEFAULT_TITLE, DROPDOWN_HEIGHT = ns.DEFAULT_ANCHOR, ns.DEFAULT_COLUMNS, ns.DEFAULT_FLOW, ns.DEFAULT_SORT, ns.DEFAULT_TITLE, ns.DROPDOWN_HEIGHT
local HINT_HEIGHT, LABEL_HEIGHT, LAYOUT_WIDTH, LINE_HEIGHT, ListRoom, MARGIN = ns.HINT_HEIGHT, ns.LABEL_HEIGHT, ns.LAYOUT_WIDTH, ns.LINE_HEIGHT, ns.ListRoom, ns.MARGIN
local ButtonWidth, TextWidth, DROPDOWN_INSET = ns.ButtonWidth, ns.TextWidth, ns.DROPDOWN_INSET
local MOVE_WIDTH, MakeButton, MakeCheck, MakeChoice, MakeScrollbar, MakeText = ns.MOVE_WIDTH, ns.MakeButton, ns.MakeCheck, ns.MakeChoice, ns.MakeScrollbar, ns.MakeText
local NativeFrame, ORDER_ROW_HEIGHT, PADDING, PIN_WIDTH, Refresh, SLOT_GAP = ns.NativeFrame, ns.ORDER_ROW_HEIGHT, ns.PADDING, ns.PIN_WIDTH, ns.Refresh, ns.SLOT_GAP
local SORT_KEYS, SORT_KEY_ORDER, SORT_LABEL_WIDTH, SortItems, TITLE_DEFAULT, TITLE_PIECES = ns.SORT_KEYS, ns.SORT_KEY_ORDER, ns.SORT_LABEL_WIDTH, ns.SortItems, ns.TITLE_DEFAULT, ns.TITLE_PIECES
local WHEEL_STEP, WINDOW_WIDTH, sort, state = ns.WHEEL_STEP, ns.WINDOW_WIDTH, ns.sort, ns.state

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

local MAX_SORT = 10 -- how many steps one sack's order can have

local function SortKeyOptions()
    local options = {}
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
    local stride = LAYOUT_WIDTH + 2 * DROPDOWN_INSET + PADDING
    local WIDE = CHOICE_WIDTH + 2 * DROPDOWN_INSET
    local FULL = WINDOW_WIDTH - MARGIN * 2
    local function mid(height) return (height - LABEL_HEIGHT) / 2 end -- drops a label to the middle of a control
    local function setting(field, title, column, options)
        local choice
        choice = MakeChoice(page, title, column * stride, -y, function() return options end, function()
            EditedGroup()[field] = choice.value()
            Refresh()
        end, LAYOUT_WIDTH)
        return choice
    end
    local STEPPER_X = math.ceil(TextWidth("Slots per row", "GameFontHighlight")) + PADDING
    local function stepper(label, at, get, set)
        MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -(at + mid(BUTTON_HEIGHT))):SetText(label)
        local box = {}
        box.minus = MakeButton(page, "-", nil, function()
            set(math.max(1, get() - 1))
            Refresh()
        end)
        box.minus:SetPoint("TOPLEFT", STEPPER_X, -at)
        box.count = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        box.count:SetWidth(math.ceil(TextWidth("000", "GameFontHighlight")))
        box.count:SetJustifyH("CENTER")
        box.count:SetPoint("LEFT", box.minus, "RIGHT", SLOT_GAP, 0)
        box.plus = MakeButton(page, "+", nil, function()
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
        rule:SetPoint("TOPLEFT", 0, -(y + LABEL_HEIGHT + SLOT_GAP))
        rule:SetSize(FULL, 1)
        y = y + LABEL_HEIGHT + PADDING + SLOT_GAP
    end
    header("This sack")
    MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -(y + mid(DROPDOWN_HEIGHT))):SetText("Editing sack:")
    page.sackChoice = MakeChoice(page, nil, math.ceil(TextWidth("Editing sack:", "GameFontHighlight")) + PADDING, -y, SackOptions, function()
        state.editing = page.sackChoice.value()
        ns.RefreshSettings()
    end, WIDE)
    -- Copy another sack's settings onto this one, a section at a time (not its rule, items, pins or position).
    -- Both sit at the right edge: the box is as wide as the others, its label just to the left of it.
    local function copyChoice(label, top, copy, what)
        local x = FULL - WIDE - ns.DROPDOWN_RIGHT
        MakeText(page, "GameFontHighlight", "TOPLEFT", x - PADDING - math.ceil(TextWidth(label, "GameFontHighlight")),
            -(top + mid(DROPDOWN_HEIGHT))):SetText(label)
        local choice
        choice = MakeChoice(page, nil, x, -top, function()
            local options = { { label = "Choose a sack..." } }
            for _, group in ipairs(AllGroups()) do
                if group ~= state.editing then options[#options + 1] = { label = group.name, value = group } end
            end
            return options
        end, function()
            local source = choice.value()
            choice.reset()
            local target = EditedGroup()
            if not source or source == target then return end
            copy(source, target)
            Say("copied the " .. what .. " of " .. source.name .. " onto " .. target.name)
            Refresh()
        end, WIDE)
        return choice
    end
    local function copyLayout(source, target)
        for _, field in ipairs({ "anchor", "flow", "title", "cols", "titleText" }) do target[field] = source[field] end
    end
    page.copyLayout = copyChoice("Copy layout from:", y, copyLayout, "layout")
    page.copySortChoice = function(top)
        page.copySort = copyChoice("Copy order from:", top, function(source, target)
            target.reverse = source.reverse
            target.sort = nil
            if not source.sort then return end
            target.sort = {}
            for index, spec in ipairs(source.sort) do
                local copy = { key = spec.key, descending = spec.descending }
                if spec.rule then
                    copy.rule = {}
                    for lineIndex, clause in ipairs(spec.rule) do
                        local line = {}
                        for k, v in pairs(clause) do line[k] = v end
                        copy.rule[lineIndex] = line
                    end
                end
                target.sort[index] = copy
            end
        end, "sort order")
    end
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
    page.useDefault = MakeButton(page, "Use default", nil, function()
        EditedGroup().cols = nil
        Refresh()
    end)
    page.useDefault:SetPoint("LEFT", page.perRow.plus, "RIGHT", PADDING, 0)
    y = y + LINE_HEIGHT
    -- Only the Other sack has an empty slot, so its choice sits beside the slots per row, and only while editing Other.
    local blankX = FULL - LAYOUT_WIDTH - ns.DROPDOWN_RIGHT
    page.blankLabel = MakeText(page, "GameFontHighlight", "TOPLEFT",
        blankX - PADDING - math.ceil(TextWidth("Empty slot", "GameFontHighlight")), -(y + mid(DROPDOWN_HEIGHT)))
    page.blankLabel:SetText("Empty slot")
    page.blank = MakeChoice(page, nil, blankX, -y, function() return BLANK_OPTIONS end, function()
        EditedGroup().blank = page.blank.value()
        Refresh()
    end, LAYOUT_WIDTH)
    y = y + math.max(LINE_HEIGHT, DROPDOWN_HEIGHT) + PADDING

    MakeText(page, "GameFontHighlight", "TOPLEFT", 0, -y):SetText("Title text")
    MakeText(page, "GameFontDisableSmall", "TOPLEFT", math.ceil(TextWidth("Title text", "GameFontHighlight")) + PADDING, -y):SetText("tokens: {name} {count} {items} {value} {free} {special}")
    y = y + LABEL_HEIGHT + SLOT_GAP
    page.titleEdit = NativeFrame("EditBox", page, "InputBoxTemplate")
    page.titleEdit:SetPoint("TOPLEFT", PADDING, -(y + (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2))
    page.titleEdit:SetAutoFocus(false)
    page.titleEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.titleEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.titleEdit:SetScript("OnTextChanged", function(self, typed)
        if not typed then return end
        EditedGroup().titleText = self:GetText()
        Refresh()
    end)
    page.insert = MakeChoice(page, nil, 0, -y, function()
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
    -- right to left: the Default button, the token picker, and the box takes everything left of them
    local insertWidth = page.insert.fit()
    page.titleDefault = MakeButton(page, "Default", nil, function()
        EditedGroup().titleText = nil
        Refresh()
    end)
    local defaultLeft = FULL - page.titleDefault:GetWidth()
    local insertLeft = defaultLeft - PADDING - insertWidth - ns.DROPDOWN_RIGHT
    page.insert.moveTo(insertLeft, -y)
    page.titleDefault:SetPoint("TOPLEFT", defaultLeft, -(y + (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2))
    page.titleEdit:SetSize(insertLeft - DROPDOWN_INSET - PADDING, BUTTON_HEIGHT)
    y = y + DROPDOWN_HEIGHT
    page.titlePreview = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    page.titlePreview:SetWidth(WINDOW_WIDTH - MARGIN * 2)
    y = y + LABEL_HEIGHT + 2 * PADDING


    header("Order of the items in this sack")
    page.copySortChoice(y - 2)
    y = y + DROPDOWN_HEIGHT + 2
    -- The order is a numbered list read top to bottom; a step only decides between two items when every step above
    -- it ties. A step is either a rule ("Where tooltip contains heals": the items that match go first) or a field to
    -- sort by. Each step is one row; a rule gets extra rows only if you add more conditions to it.
    local lift = (DROPDOWN_HEIGHT - BUTTON_HEIGHT) / 2
    local labelLift = mid(DROPDOWN_HEIGHT)
    -- the number column, and the label column ("Then where", "Then sort by"), each as wide as its widest text
    local NUM = math.ceil(TextWidth(MAX_SORT .. ".", "GameFontHighlight")) + PADDING
    local SLOT = 0
    for _, text in ipairs({ "First, where", "Then where", "Sort by", "Then sort by" }) do
        SLOT = math.max(SLOT, math.ceil(TextWidth(text, "GameFontHighlight")) + PADDING)
    end
    page.sortHint = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -y)
    page.sortHint:SetText("Items are sorted by step 1. Step 2 only orders items step 1 treated the same, and so on down.")
    y = y + LABEL_HEIGHT + SLOT_GAP
    page.sortTop = y
    page.sortRows = {}
    local function sortList()
        local group = EditedGroup()
        if not group.sort then
            group.sort = {}
            for _, spec in ipairs(DEFAULT_SORT) do group.sort[#group.sort + 1] = { key = spec.key, descending = spec.descending } end
        end
        return group.sort
    end
    local function swapSteps(a, b)
        local list = sortList()
        if not list[b] then return end
        list[a], list[b] = list[b], list[a]
        Refresh()
    end
    local function ruleFields()
        return { { label = "Class", value = "class" }, { label = "Subclass", value = "sub" },
            { label = "Quality", value = "quality" }, { label = "Name", value = "name" },
            { label = "Tooltip text", value = "tooltip" },
            { label = "Item level", value = "ilvl" }, { label = "Required level", value = "level" },
            { label = "Equip slot", value = "equip" }, { label = "Bind type", value = "bind" },
            { label = "Soulbound", value = "bound" }, { label = "Crafting reagent", value = "reagent" },
            { label = "Sell price", value = "price" }, { label = "Stack size", value = "stack" },
            { label = "Special bag type", value = "family" } }
    end
    -- room kept at the right of a row for its buttons: the widest set a row can have, and the gaps between them
    local CLUSTER = ButtonWidth("+ And") + MOVE_WIDTH * 2 + ButtonWidth("x") + SLOT_GAP * 4
    for level = 1, MAX_SORT do
        local row = {}
        row.label = MakeText(page, "GameFontHighlight", "TOPLEFT", 0, 0)
        row.sortLabel = MakeText(page, "GameFontHighlight", "TOPLEFT", 0, 0)
                row.key = MakeChoice(page, nil, NUM + SLOT, 0, SortKeyOptions, function()
            sortList()[level].key = row.key.value()
            sortList()[level].descending = false
            Refresh()
        end, LAYOUT_WIDTH)
        row.direction = MakeChoice(page, nil, NUM + SLOT + stride, 0, function() return DIRECTION_OPTIONS end, function()
            sortList()[level].descending = row.direction.value()
            Refresh()
        end, CHOICE_WIDTH)
        row.andButton = MakeButton(page, "+ And", nil, function()
            local spec = sortList()[level]
            if #spec.rule >= MAX_LINES then return Say("that is as many conditions as a rule can have") end
            local condition = NewCondition("tooltip")
            condition.join = "AND"
            spec.rule[#spec.rule + 1] = condition
            Refresh()
        end)
        row.up = MakeButton(page, "Up", MOVE_WIDTH, function() swapSteps(level, level - 1) end)
        row.down = MakeButton(page, "Down", MOVE_WIDTH, function() swapSteps(level, level + 1) end)
        row.remove = MakeButton(page, "x", nil, function()
            table.remove(sortList(), level)
            Refresh()
        end)
        -- The conditions of a rule step: the same lines as a sack's rule, in one compact block.
        row.host = CreateFrame("Frame", nil, page)
        row.host:SetSize(FULL - NUM, LINE_HEIGHT)
        row.host.draft = {}
        row.host.lines = {}
        row.host.fieldOptions = ruleFields
        row.host.compact = true
        row.host.lineWidth = FULL - NUM - SLOT_GAP -- ends where the step's own buttons end
        row.host.lineStart = 0
        row.host.lineReserve = CLUSTER + NUM
        row.host.onChange = function() Refresh() end
        page.sortRows[level] = row
    end
    page.sortNone = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, -(page.sortTop + labelLift))
    page.sortNone:SetText("No steps: items stay in bag order.")
    local function addStep(spec)
        local list = sortList()
        if #list >= MAX_SORT then return Say("that is as many sort steps as a sack can have") end
        list[#list + 1] = spec
        Refresh()
    end
    page.sortAddMatch = MakeButton(page, "Add rule", nil, function()
        addStep({ key = "match", rule = { NewCondition("tooltip") } })
    end)
    page.sortAdd = MakeButton(page, "Add sort field", nil, function()
        local used = {}
        for _, spec in ipairs(sortList()) do used[spec.key] = true end
        local key = "name"
        for _, candidate in ipairs(SORT_KEY_ORDER) do
            if not used[candidate] then key = candidate break end
        end
        addStep({ key = key })
    end)
    page.reverseCheck = MakeCheck(page, "Reverse the whole order (pins and sorting, flipped end to end)", function(self)
        EditedGroup().reverse = self:GetChecked() and true or false
        Refresh()
    end)
    page.orderTitle = MakeText(page, "GameFontNormal", "TOPLEFT", 0, 0)

    -- Puts every step in place and returns how tall the list is.
    function page.placeSteps(sort)
        local top = page.sortTop
        for level, row in ipairs(page.sortRows) do
            local spec = sort[level]
            if spec then
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", 0, -(top + labelLift))
                local buttons
                if spec.key == "match" then
                    spec.rule = spec.rule or {}
                    if #spec.rule == 0 then spec.rule[1] = NewCondition("tooltip") end
                    local host = row.host
                    host.draft = spec.rule
                    host.lineLead = SLOT
                    host:ClearAllPoints()
                    host:SetPoint("TOPLEFT", page, "TOPLEFT", NUM, -top)
                    host:Show()
                    local inner = 0
                    for lineIndex, clause in ipairs(spec.rule) do
                        local line = host.lines[lineIndex]
                        if not line then
                            line = MakeLine(host)
                            line.firstText:SetText("Items where")
                            host.lines[lineIndex] = line
                        end
                        line.firstText:SetText(level == 1 and "First, where" or "Then where")
                        FillLine(line, clause, lineIndex, #spec.rule)
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -inner)
                        line:Show()
                        inner = inner + LINE_HEIGHT
                    end
                    for lineIndex = #spec.rule + 1, #host.lines do host.lines[lineIndex]:Hide() end
                    host:SetHeight(inner)
                    top = top + inner
                    buttons = { row.andButton, row.up, row.down, row.remove }
                else
                    row.host:Hide()
                    row.sortLabel:ClearAllPoints()
                    row.sortLabel:SetPoint("TOPLEFT", NUM, -(top + labelLift))
                    row.key.moveTo(NUM + SLOT, -top)
                    row.direction.moveTo(NUM + SLOT + stride, -top)
                    top = top + LINE_HEIGHT
                    buttons = { row.up, row.down, row.remove }
                end
                -- the buttons sit at the right edge, on the first row of the step
                local rowTop = top - (spec.key == "match" and #spec.rule * LINE_HEIGHT or LINE_HEIGHT)
                local right = FULL - SLOT_GAP
                for index = #buttons, 1, -1 do
                    local button = buttons[index]
                    button:ClearAllPoints()
                    right = right - button:GetWidth()
                    button:SetPoint("TOPLEFT", right, -(rowTop + lift))
                    right = right - SLOT_GAP
                end
            end
        end
        return top - page.sortTop
    end

    -- Places everything under the steps; called whenever the steps change.
    function page.placeBelow(height)
        local top = page.sortTop + math.max(height, LINE_HEIGHT)
        page.sortAddMatch:ClearAllPoints()
        page.sortAddMatch:SetPoint("TOPLEFT", 0, -top)
        page.sortAdd:ClearAllPoints()
        page.sortAdd:SetPoint("LEFT", page.sortAddMatch, "RIGHT", PADDING, 0)
        top = top + BUTTON_HEIGHT + PADDING + SLOT_GAP
        page.reverseCheck:ClearAllPoints()
        page.reverseCheck:SetPoint("TOPLEFT", -SLOT_GAP, -top)
        top = top + CHECK_SIZE + PADDING
        page.orderTitle:ClearAllPoints()
        page.orderTitle:SetPoint("TOPLEFT", 0, -top)
        top = top + LABEL_HEIGHT + PADDING
        page.orderTop = top
        for index, row in ipairs(page.orderRows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(top + (index - 1) * ORDER_ROW_HEIGHT))
        end
    end
    y = y + LINE_HEIGHT + BUTTON_HEIGHT + PADDING + 4 + CHECK_SIZE + PADDING

    page.orderTitle:SetText("Items in this sack, in the order they are shown")
    y = y + LABEL_HEIGHT + PADDING
    page.orderTop = y
    page.orderRows = {}
    page.orderScroll = MakeScrollbar(page, WINDOW_WIDTH - MARGIN * 2 + SLOT_GAP, y, function(offset)
        page.orderOffset = offset
        ns.RefreshSettings()
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
        ns.RefreshSettings()
    end)
    return page
end

local function RefreshLayout()
    local page = ns.settings.layout
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
        if spec then
            local isRule = spec.key == "match"
            row.label:SetText(level .. ".")
            row.label:Show()
            if isRule then
                row.sortLabel:Hide()
                row.key.show(false)
                row.direction.show(false)
                row.andButton:Show()
            else
                row.sortLabel:SetText(level == 1 and "Sort by" or "Then sort by")
                row.sortLabel:Show()
                row.key.show(true)
                row.key.select(spec.key)
                row.direction.show(true)
                row.direction.select(spec.descending or false)
                row.andButton:Hide()
                row.host:Hide()
            end
            -- Up and Down only appear when there is somewhere to move to.
            if #sort > 1 then
                row.up:Show()
                row.down:Show()
                if level == 1 then row.up:Disable() else row.up:Enable() end
                if level == #sort then row.down:Disable() else row.down:Enable() end
            else
                row.up:Hide()
                row.down:Hide()
            end
            row.remove:Show()
        else
            row.label:Hide()
            row.sortLabel:Hide()
            row.key.show(false)
            row.direction.show(false)
            row.andButton:Hide()
            row.up:Hide()
            row.down:Hide()
            row.remove:Hide()
            row.host:Hide()
        end
    end
    if #sort == 0 then page.sortNone:Show() else page.sortNone:Hide() end
    if #sort >= MAX_SORT then
        page.sortAdd:Disable()
        page.sortAddMatch:Disable()
    else
        page.sortAdd:Enable()
        page.sortAddMatch:Enable()
    end
    page.placeBelow(page.placeSteps(sort))

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
    page.orderScroll.set(#display, visible, page.orderOffset, visible * ORDER_ROW_HEIGHT, page.orderTop)
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
    ns.settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
end

-- shared with the files after this one
ns.BuildLayout = BuildLayout
ns.RefreshLayout = RefreshLayout
