-- sacks: LayoutTab.lua
local _, ns = ...
local AllGroups, BUTTON_HEIGHT, BuildItemRows, CHECK_SIZE, CHOICE_WIDTH, CONTENT_TOP = ns.AllGroups, ns.BUTTON_HEIGHT, ns.BuildItemRows, ns.CHECK_SIZE, ns.CHOICE_WIDTH, ns.CONTENT_TOP
local DEFAULT_ANCHOR, DEFAULT_COLUMNS, DEFAULT_FLOW, DEFAULT_SORT, DEFAULT_TITLE, DROPDOWN_HEIGHT = ns.DEFAULT_ANCHOR, ns.DEFAULT_COLUMNS, ns.DEFAULT_FLOW, ns.DEFAULT_SORT, ns.DEFAULT_TITLE, ns.DROPDOWN_HEIGHT
local HINT_HEIGHT, LABEL_HEIGHT, LAYOUT_WIDTH, LINE_HEIGHT, ListRoom, MARGIN = ns.HINT_HEIGHT, ns.LABEL_HEIGHT, ns.LAYOUT_WIDTH, ns.LINE_HEIGHT, ns.ListRoom, ns.MARGIN
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
        ns.RefreshSettings()
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
    ns.settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
end

-- shared with the files after this one
ns.BuildLayout = BuildLayout
ns.RefreshLayout = RefreshLayout
