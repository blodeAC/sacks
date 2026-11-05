-- sacks: SacksTab.lua
local _, ns = ...
local CreateSack = ns.CreateSack
local AllGroups, BUTTON_HEIGHT, CHECK_SIZE, CHOICE_WIDTH, CONTENT_TOP, DEFAULT_COLUMNS = ns.AllGroups, ns.BUTTON_HEIGHT, ns.CHECK_SIZE, ns.CHOICE_WIDTH, ns.CONTENT_TOP, ns.DEFAULT_COLUMNS
local DefaultGroups, Describe, FindGroup, HideOwnBags, HideRemoved, LABEL_HEIGHT = ns.DefaultGroups, ns.Describe, ns.FindGroup, ns.HideOwnBags, ns.HideRemoved, ns.LABEL_HEIGHT
local ListRoom, LoadSack, MARGIN, MakeButton, MakeCheck, MakeScrollbar = ns.ListRoom, ns.LoadSack, ns.MARGIN, ns.MakeButton, ns.MakeCheck, ns.MakeScrollbar
local MakeText, NativeFrame, PADDING, ROW_HEIGHT, Refresh, SECTION_HEIGHT = ns.MakeText, ns.NativeFrame, ns.PADDING, ns.ROW_HEIGHT, ns.Refresh, ns.SECTION_HEIGHT
local SLOT_GAP, Say, WHEEL_STEP, WINDOW_WIDTH, WidgetGroup, state = ns.SLOT_GAP, ns.Say, ns.WHEEL_STEP, ns.WINDOW_WIDTH, ns.WidgetGroup, ns.state

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
    for _, head in ipairs({ { "Sack", 0, 172 }, { "Items", 174, 48 }, { "Takes", 224, 252 } }) do
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
        -- It starts with no lines, and a sack with no lines takes nothing, so it can't swallow items before it is set up.
        local group, problem = CreateSack(page.nameEdit:GetText(), {})
        if not group then return Say(problem) end
        page.nameEdit:SetText("")
        state.editing = group
        Refresh()
        LoadSack(ns.settings.items, group)
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
    local page = ns.settings.sacks
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
    ns.settings:SetHeight(CONTENT_TOP + page.height + MARGIN)
end

-- shared with the files after this one
ns.BuildSacks = BuildSacks
ns.RefreshSacks = RefreshSacks
ns.ShowTab = ShowTab
