-- sacks: SacksTab.lua
local _, ns = ...
local CreateSack = ns.CreateSack
local AllGroups, BUTTON_HEIGHT, CHECK_SIZE, CHOICE_WIDTH, CONTENT_TOP, DEFAULT_COLUMNS = ns.AllGroups, ns.BUTTON_HEIGHT, ns.CHECK_SIZE, ns.CHOICE_WIDTH, ns.CONTENT_TOP, ns.DEFAULT_COLUMNS
local DefaultGroups, Describe, FindGroup, HideOwnBags, HideRemoved, LABEL_HEIGHT = ns.DefaultGroups, ns.Describe, ns.FindGroup, ns.HideOwnBags, ns.HideRemoved, ns.LABEL_HEIGHT
local ListRoom, LoadSack, MARGIN, MakeButton, MakeCheck, MakeScrollbar = ns.ListRoom, ns.LoadSack, ns.MARGIN, ns.MakeButton, ns.MakeCheck, ns.MakeScrollbar
local HINT_HEIGHT, ORDER_ROW_HEIGHT = ns.HINT_HEIGHT, ns.ORDER_ROW_HEIGHT
local MakeChoice, MOVE_WIDTH = ns.MakeChoice, ns.MOVE_WIDTH
local MakeText, NativeFrame, PADDING, ROW_HEIGHT, Refresh, SECTION_HEIGHT = ns.MakeText, ns.NativeFrame, ns.PADDING, ns.ROW_HEIGHT, ns.Refresh, ns.SECTION_HEIGHT
local SLOT_GAP, Say, WHEEL_STEP, WINDOW_WIDTH, WidgetGroup, state = ns.SLOT_GAP, ns.Say, ns.WHEEL_STEP, ns.WINDOW_WIDTH, ns.WidgetGroup, ns.state
local ButtonWidth, TextWidth = ns.ButtonWidth, ns.TextWidth

-- The list's columns. Every width is the measured width of the header or button that sits in it; the two text
-- columns split whatever room is left.
local COL
local function Columns()
    if COL then return COL end
    local full = WINDOW_WIDTH - MARGIN * 2
    local right = ButtonWidth("Remove") + MOVE_WIDTH * 3 + SLOT_GAP * 7
    local count, use = ButtonWidth("Items"), ButtonWidth("Left-click use")
    local text = math.floor((full - right - PADDING - count - use - PADDING * 3) / 2)
    COL = { sack = 0, sackW = text, count = text + PADDING, countW = count }
    COL.desc = COL.count + count + PADDING
    COL.descW = text
    COL.use = COL.desc + text + PADDING
    COL.useW = use
    return COL
end

---------------------------------------------------------------------------------------------------
-- Sacks: your sacks, with a quick way to start a new one
---------------------------------------------------------------------------------------------------

local function ShowTab(name)
    ns.settings.active = name
    for key, page in pairs({ sacks = ns.settings.sacks, items = ns.settings.items, layout = ns.settings.layout }) do
        if key == name then page:Show() else page:Hide() end
        if key == name then ns.settings.tabs[key]:Disable() else ns.settings.tabs[key]:Enable() end
    end
    ns.RefreshSettings()
end

local function MakeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WINDOW_WIDTH - MARGIN * 2, ROW_HEIGHT)
    row:EnableMouse(true)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0)
    local col = Columns()
    row.name = MakeText(row, "GameFontHighlight", "LEFT", col.sack, 0)
    row.name:SetWidth(col.sackW)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.count = MakeText(row, "GameFontHighlight", "LEFT", col.count, 0)
    row.count:SetWidth(col.countW - SLOT_GAP)
    if row.count.SetJustifyH then row.count:SetJustifyH("RIGHT") end
    row.desc = MakeText(row, "GameFontDisableSmall", "LEFT", col.desc, 0)
    row.desc:SetWidth(col.descW)
    if row.desc.SetWordWrap then row.desc:SetWordWrap(false) end
    -- Left-click uses the items of this sack, like an action bar.
    row.use = MakeCheck(row, "", function(self)
        row.group.useOnClick = self:GetChecked() and true or nil
        Refresh()
    end)
    row.use:SetPoint("LEFT", col.use + (col.useW - CHECK_SIZE) / 2, 0)
    row:SetScript("OnEnter", function(self)
        if not self.group or (not self.group.fixed and #self.group.rule == 0) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(self.group.name)
        GameTooltip:AddLine("Takes: " .. Describe(self.group.rule), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.remove = MakeButton(row, "Remove", nil, function()
        local group, index = FindGroup(row.group.name)
        if not group then return end
        table.remove(SacksDB.groups, index)
        HideRemoved(group)
        Refresh()
    end)
    row.remove:SetPoint("TOPRIGHT", 0, -3)
    row.edit = MakeButton(row, "Edit", MOVE_WIDTH, function()
        state.editing = row.group
        LoadSack(ns.settings.items, row.group)
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
    row.down = MakeButton(row, "Down", MOVE_WIDTH, function() move(1) end)
    row.down:SetPoint("RIGHT", row.edit, "LEFT", -SLOT_GAP * 2, 0)
    row.up = MakeButton(row, "Up", MOVE_WIDTH, function() move(-1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -SLOT_GAP, 0)
    return row
end

local function BuildSacks(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", MARGIN, -CONTENT_TOP)
    page:SetSize(WINDOW_WIDTH - MARGIN * 2, 100)

    page.rows = {}
    page.rowOffset = 0
    page.scroll = MakeScrollbar(page, WINDOW_WIDTH - MARGIN * 2 + SLOT_GAP, 0, function(offset)
        page.rowOffset = offset
        ns.RefreshSettings()
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
    local col = Columns()
    for _, head in ipairs({ { "Sack", col.sack, col.sackW }, { "Items", col.count, col.countW },
                            { "Takes", col.desc, col.descW }, { "Left-click use", col.use, col.useW } }) do
        local button = MakeButton(page, head[1], head[3], function() end)
        button:Disable()
        page.heads[#page.heads + 1] = { button = button, x = head[2] }
    end
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(self, delta)
        self.rowOffset = math.max(0, (self.rowOffset or 0) - delta * WHEEL_STEP)
        ns.RefreshSettings()
    end)

    page.hideCheck = MakeCheck(page, "Stop the game opening its own bags by itself (vendors etc.); B and the bag buttons still work", function(self)
        SacksDB.hideBags = self:GetChecked() and true or false
        HideOwnBags()
    end)
    page.hideCheck:SetPoint("TOPLEFT", -SLOT_GAP, -SLOT_GAP)
    page.widgetCheck = MakeCheck(page, "Show a free-slots box I can place anywhere", function(self)
        WidgetGroup().shown = self:GetChecked() and true or false
        Refresh()
    end)
    page.widgetCheck:SetPoint("TOPLEFT", -SLOT_GAP, -(SLOT_GAP + CHECK_SIZE + PADDING))
    -- Sacks that use items on left click are marked in this colour (title and border), so they stand out.
    local markY = SLOT_GAP + CHECK_SIZE + PADDING
    page.clickColor = MakeChoice(page, nil, 0, -markY, function() return ns.CLICK_COLORS end, function()
        SacksDB.clickColor = page.clickColor.value()
        Refresh()
    end)
    -- right-aligned: the box is as wide as its widest colour name, the label sits just left of it
    local markWidth = page.clickColor.fit()
    local markText = "Mark left-click sacks:"
    local markLeft = WINDOW_WIDTH - MARGIN * 2 - markWidth - ns.DROPDOWN_RIGHT
    page.clickColor.moveTo(markLeft, -markY)
    MakeText(page, "GameFontHighlight", "TOPLEFT", markLeft - PADDING - math.ceil(TextWidth(markText, "GameFontHighlight")),
        -(markY + (CHECK_SIZE - LABEL_HEIGHT) / 2)):SetText(markText)
    page.bagInfo = MakeText(page, "GameFontHighlightSmall", "TOPLEFT", 0, -(SLOT_GAP + 2 * (CHECK_SIZE + PADDING)))
    page.bagInfo:SetWidth(WINDOW_WIDTH - MARGIN * 2)

    local section = CreateFrame("Frame", nil, page)
    section:SetSize(WINDOW_WIDTH - MARGIN * 2, SECTION_HEIGHT)
    page.newSection = section
    local newTitle = MakeText(section, "GameFontNormal", "TOPLEFT", 0, 0)
    newTitle:SetText("New sack")
    local newHint = MakeText(section, "GameFontDisableSmall", "TOPLEFT", math.ceil(TextWidth("New sack", "GameFontNormal")) + PADDING, 0)
    newHint:SetText("give it a name; its lines are set on the Items tab")
    local newRule = section:CreateTexture(nil, "ARTWORK")
    newRule:SetColorTexture(1, 1, 1, 0.18)
    newRule:SetPoint("TOPLEFT", 0, -(LABEL_HEIGHT + SLOT_GAP))
    newRule:SetSize(WINDOW_WIDTH - MARGIN * 2, 1)
    page.nameEdit = NativeFrame("EditBox", section, "InputBoxTemplate")
    page.nameEdit:SetSize(ns.NAME_WIDTH, BUTTON_HEIGHT)
    page.nameEdit:SetPoint("TOPLEFT", PADDING, -(LABEL_HEIGHT + 2 * PADDING))
    page.nameEdit:SetAutoFocus(false)
    page.nameEdit:SetMaxLetters(32)
    page.nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.createButton = MakeButton(section, "New sack", nil, function()
        -- It starts with no lines, and a sack with no lines takes nothing, so it can't swallow items before it is set up.
        local group, problem = CreateSack(page.nameEdit:GetText(), {})
        if not group then return Say(problem) end
        page.nameEdit:SetText("")
        state.editing = group
        Refresh()
        LoadSack(ns.settings.items, group)
        ShowTab("items")
    end)
    page.createButton:SetPoint("LEFT", page.nameEdit, "RIGHT", PADDING, 0)
    page.resetButton = MakeButton(section, "Reset to starting sacks", nil, function()
        for _, group in ipairs(SacksDB.groups) do HideRemoved(group) end
        SacksDB.groups = DefaultGroups()
        Refresh()
    end)
    page.resetButton:SetPoint("LEFT", page.createButton, "RIGHT", PADDING, 0)

    -- Defaults that every sack falls back on, in a tinted box of their own.
    local defaults = CreateFrame("Frame", nil, page)
    local slotsY = LABEL_HEIGHT + SLOT_GAP + PADDING
    defaults:SetSize(WINDOW_WIDTH - MARGIN * 2, slotsY + BUTTON_HEIGHT + PADDING)
    page.defaults = defaults
    page.defaultsHeight = slotsY + BUTTON_HEIGHT + PADDING
    local rule = defaults:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.18)
    rule:SetPoint("TOPLEFT", 0, -(LABEL_HEIGHT + SLOT_GAP))
    rule:SetSize(WINDOW_WIDTH - MARGIN * 2, 1)
    MakeText(defaults, "GameFontNormal", "TOPLEFT", 0, 0):SetText("Defaults for all sacks")
    MakeText(defaults, "GameFontDisableSmall", "TOPLEFT", math.ceil(TextWidth("Defaults for all sacks", "GameFontNormal")) + PADDING, 0)
        :SetText("used by any sack that has no number of its own")
    local slotsLabel = "Slots per row"
    MakeText(defaults, "GameFontHighlight", "TOPLEFT", 0, -(slotsY + (BUTTON_HEIGHT - LABEL_HEIGHT) / 2)):SetText(slotsLabel)
    local minus = MakeButton(defaults, "-", nil, function()
        SacksDB.columns = math.max(1, (SacksDB.columns or DEFAULT_COLUMNS) - 1)
        Refresh()
    end)
    minus:SetPoint("TOPLEFT", math.ceil(TextWidth(slotsLabel, "GameFontHighlight")) + PADDING, -slotsY)
    page.defaultMinus = minus
    page.defaultCount = defaults:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.defaultCount:SetWidth(math.ceil(TextWidth("000", "GameFontHighlight")))
    page.defaultCount:SetJustifyH("CENTER")
    page.defaultCount:SetPoint("LEFT", minus, "RIGHT", SLOT_GAP, 0)
    local plus = MakeButton(defaults, "+", nil, function()
        SacksDB.columns = (SacksDB.columns or DEFAULT_COLUMNS) + 1
        Refresh()
    end)
    plus:SetPoint("LEFT", page.defaultCount, "RIGHT", SLOT_GAP, 0)
    return page
end

local function RefreshSacks()
    local page = ns.settings.sacks
    page.hideCheck:SetChecked(SacksDB.hideBags ~= false)
    page.widgetCheck:SetChecked(WidgetGroup().shown and true or false)
    page.clickColor.select(SacksDB.clickColor or "green")

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

    local top = 4 + 2 * (CHECK_SIZE + PADDING) + #lines * LABEL_HEIGHT + PADDING + SLOT_GAP * 3
    page.listHeader:ClearAllPoints()
    page.listHeader:SetPoint("TOPLEFT", 0, -top)
    page.listRule:ClearAllPoints()
    page.listRule:SetPoint("TOPLEFT", 0, -(top + LABEL_HEIGHT + SLOT_GAP))
    top = top + LABEL_HEIGHT + PADDING + 4
    page.priorityHint:ClearAllPoints()
    page.priorityHint:SetPoint("TOPLEFT", 0, -top)
    top = top + HINT_HEIGHT
    for _, head in ipairs(page.heads) do
        head.button:ClearAllPoints()
        head.button:SetPoint("TOPLEFT", head.x, -top)
    end
    top = top + ORDER_ROW_HEIGHT
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
        row.use:SetChecked(group.useOnClick and true or false)
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
    page.height = below + SECTION_HEIGHT + PADDING * 2 + page.defaultsHeight
    page:SetHeight(page.height)
    ns.settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
end

-- shared with the files after this one
ns.BuildSacks = BuildSacks
ns.RefreshSacks = RefreshSacks
ns.ShowTab = ShowTab
