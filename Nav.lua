-- sacks: Nav.lua
-- The list at the left of the settings window: All items and Settings, then every sack in priority order. Click a sack
-- to open it; drag it up or down to change which sack gets an item first. Combat loot stays first and Other last.
local _, ns = ...
local AllGroups, BUTTON_HEIGHT, CreateSack, Describe = ns.AllGroups, ns.BUTTON_HEIGHT, ns.CreateSack, ns.Describe
local LABEL_HEIGHT, ListRoom, MakeButton, MakeScrollbar, MakeText = ns.LABEL_HEIGHT, ns.ListRoom, ns.MakeButton, ns.MakeScrollbar, ns.MakeText
local NAME_WIDTH, PADDING, Refresh, SLOT_GAP, Say = ns.NAME_WIDTH, ns.PADDING, ns.Refresh, ns.SLOT_GAP, ns.Say
local TextWidth, WHEEL_STEP, state = ns.TextWidth, ns.WHEEL_STEP, ns.state

local ROW_HEIGHT = BUTTON_HEIGHT
local GRIP_WIDTH = 2 * PADDING -- the dots you drag a sack by
local COUNT_WIDTH = math.ceil(TextWidth("000", "GameFontHighlight"))
local BAR_ROOM = 3 * SLOT_GAP -- kept at the right of the rows for the scrollbar
local LIST_HINT = "drag to reorder"
local NEW_TEXT = "+ New sack"
local MOST_ROWS = 40

-- Closes whatever text box has the keyboard, so what was typed there is taken before the page changes.
local function DropKeyboard()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.ClearFocus then focus:ClearFocus() end
end

local function OpenView(name)
    DropKeyboard()
    ns.ShowView(name)
end

local function OpenSack(group)
    DropKeyboard()
    state.editing = group
    ns.ShowView("sack")
end

-- How wide the list is: room for the longest sack name (up to a limit, longer ones end in ...), its count and the grip,
-- and never narrower than the list's own words.
local function NavWidth()
    local name = 0
    for _, group in ipairs(AllGroups()) do name = math.max(name, math.ceil(TextWidth(group.name, "GameFontHighlight"))) end
    name = math.min(name, NAME_WIDTH)
    local width = GRIP_WIDTH + name + PADDING + COUNT_WIDTH + SLOT_GAP + BAR_ROOM
    local header = math.ceil(TextWidth("Sacks", "GameFontNormal") + PADDING + TextWidth(LIST_HINT, "GameFontDisableSmall"))
    for _, text in ipairs({ "All items", "Defaults", "Settings" }) do
        width = math.max(width, PADDING + math.ceil(TextWidth(text, "GameFontHighlight")) + PADDING)
    end
    return math.max(width, header, ns.ButtonWidth(NEW_TEXT))
end

-- A row of the list: a light patch when the mouse is over it, a gold one when it is the page shown.
local function MakeRowLook(row)
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.08)
    row.hover:Hide()
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.2)
    row.selected:Hide()
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
end

-- All items, Defaults and Settings: the pages that are not a sack.
local function MakeViewRow(nav, label, view)
    local row = CreateFrame("Button", nil, nav)
    row:SetHeight(ROW_HEIGHT)
    MakeRowLook(row)
    row.name:SetPoint("LEFT", PADDING, 0)
    row.name:SetText(label)
    row.view = view
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function() OpenView(view) end)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    return row
end

---------------------------------------------------------------------------------------------------
-- Dragging a sack to a new place in the list. While a drag is on, the list follows the mouse each frame (and only then),
-- drawing a gold line where the sack would go.
---------------------------------------------------------------------------------------------------

-- Where in the list a sack may go: after Combat loot (always first) and before Other (always last, not in the list
-- of sacks you made). Returns the first and last place a sack can be put before.
local function DropRange()
    local first = (SacksDB.groups[1] and SacksDB.groups[1].builtin) and 2 or 1
    return first, #SacksDB.groups + 1
end

local function GroupIndex(group)
    for index, each in ipairs(SacksDB.groups) do
        if each == group then return index end
    end
    return #SacksDB.groups + 1 -- Other
end

-- The place under the mouse: the sack the dragged one would be put before, and the row whose top edge marks it.
local function DropTarget(nav)
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / nav:GetEffectiveScale()
    local first, last = DropRange()
    local before, mark = last, nil
    for _, row in ipairs(nav.rows) do
        if row:IsShown() and row.group then
            local top, bottom = row:GetTop(), row:GetBottom()
            if type(top) == "number" and type(bottom) == "number" and cursorY > (top + bottom) / 2 then
                before = GroupIndex(row.group)
                break
            end
        end
    end
    before = math.max(first, math.min(last, before))
    for _, row in ipairs(nav.rows) do
        if row:IsShown() and row.group and GroupIndex(row.group) == before then mark = row end
    end
    return before, mark
end

local function TrackDrag(nav)
    local before, mark = DropTarget(nav)
    nav.dropBefore = before
    if mark then
        nav.dropLine:ClearAllPoints()
        nav.dropLine:SetPoint("BOTTOMLEFT", mark, "TOPLEFT", 0, -1)
        nav.dropLine:SetPoint("BOTTOMRIGHT", mark, "TOPRIGHT", 0, -1)
        nav.dropLine:Show()
    else
        nav.dropLine:Hide()
    end
end

local function BeginDrag(nav, row)
    if not row.group or row.group.builtin or row.group.fixed then return end
    nav.dragging = row.group
    nav.dropBefore = nil
    row.dragged = true
    row:SetAlpha(0.5)
    nav:SetScript("OnUpdate", TrackDrag)
end

local function EndDrag(nav, row)
    nav:SetScript("OnUpdate", nil)
    nav.dropLine:Hide()
    row:SetAlpha(1)
    local group, before = nav.dragging, nav.dropBefore
    nav.dragging, nav.dropBefore = nil, nil
    if not group or not before then return end
    local from = GroupIndex(group)
    if before == from or before == from + 1 then return end -- dropped where it already was
    table.remove(SacksDB.groups, from)
    if before > from then before = before - 1 end
    table.insert(SacksDB.groups, before, group)
    Refresh()
end

---------------------------------------------------------------------------------------------------
-- The sack rows
---------------------------------------------------------------------------------------------------

local function MakeGrip(row)
    row.grip = {}
    local dot = math.max(2, math.floor(SLOT_GAP / 2))
    for column = 0, 1 do
        for line = -1, 1 do
            local texture = row:CreateTexture(nil, "ARTWORK")
            texture:SetSize(dot, dot)
            texture:SetColorTexture(1, 1, 1, 0.35)
            texture:SetPoint("CENTER", row, "LEFT", GRIP_WIDTH / 2 + (column - 0.5) * 2 * dot, line * 2 * dot)
            row.grip[#row.grip + 1] = texture
        end
    end
end

-- The whole rule of the sack under the mouse, and what you can do with the row.
local function ShowRowTooltip(row)
    local group = row.group
    if not group then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(group.name, 1, 0.82, 0)
    local lines = (group.builtin or group.fixed) and {} or ns.ClauseLines(group.rule)
    if group.builtin then
        GameTooltip:AddLine("What you loot in combat, until combat ends. Always first.", 1, 1, 1, true)
    elseif group.fixed then
        GameTooltip:AddLine("Everything no sack above it takes. Always last.", 1, 1, 1, true)
    elseif #lines == 0 then
        GameTooltip:AddLine("No lines yet: takes nothing.", 0.7, 0.7, 0.7, true)
    else
        for _, line in ipairs(lines) do GameTooltip:AddLine((line:gsub("|", "||")), 1, 1, 1, true) end
    end
    if group.useOnClick then GameTooltip:AddLine("Left-click uses its items (its name is in that colour).", 0.5, 0.8, 1, true) end
    if not (group.builtin or group.fixed) then GameTooltip:AddLine("Drag to change its place in the list.", 0.5, 0.5, 0.5) end
    GameTooltip:Show()
end

local function MakeSackRow(nav)
    local row = CreateFrame("Button", nil, nav)
    row:SetHeight(ROW_HEIGHT)
    MakeRowLook(row)
    MakeGrip(row)
    row.name:SetPoint("LEFT", GRIP_WIDTH, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.count:SetJustifyH("RIGHT")
    row.count:SetWidth(COUNT_WIDTH)
    row.count:SetPoint("RIGHT", -SLOT_GAP, 0)
    row:RegisterForClicks("LeftButtonUp")
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnClick", function(self)
        -- the click that ends a drag is not a click on the row
        if self.dragged then
            self.dragged = false
            return
        end
        if self.group then OpenSack(self.group) end
    end)
    row:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        BeginDrag(nav, self)
    end)
    row:SetScript("OnDragStop", function(self) EndDrag(nav, self) end)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not nav.dragging then ShowRowTooltip(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    return row
end

-- One sack's row: its name (in the left-click colour when left-click uses its items, the same colour as the "Left-click
-- uses its items" box on its page), how many slots it shows, and the grip only when it can be moved.
local function FillSackRow(nav, row, group, width)
    row.group = group
    row:SetWidth(width)
    row.name:SetWidth(width - GRIP_WIDTH - COUNT_WIDTH - PADDING - SLOT_GAP)
    row.name:SetText(group.name)
    local markR, markG, markB = ns.ClickColor()
    if group.useOnClick and markR then row.name:SetTextColor(markR, markG, markB) else row.name:SetTextColor(1, 1, 1) end
    local held = state.counts[group] or 0
    row.count:SetText(tostring(held))
    if held == 0 then row.count:SetTextColor(ns.Rgb(ns.COLOR.DIM)) else row.count:SetTextColor(1, 1, 1) end
    local movable = not (group.builtin or group.fixed)
    for _, dot in ipairs(row.grip) do
        if movable then dot:Show() else dot:Hide() end
    end
    local shown = ns.settings.active == "sack" and group == ns.EditedGroup()
    if shown then row.selected:Show() else row.selected:Hide() end
    row:Show()
end

---------------------------------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------------------------------

-- A new sack with no lines (so it takes nothing yet), opened on its page with its name ready to type over.
local function NewSack()
    local group, problem = CreateSack(ns.UniqueName("NewSack"), {})
    if not group then return Say(problem) end
    Refresh()
    OpenSack(group)
    local box = ns.settings.sack.head.name
    if box:IsShown() then
        box:SetFocus()
        box:HighlightText()
    end
end

local function BuildNav(window)
    local nav = CreateFrame("Frame", nil, window)
    nav:SetPoint("TOPLEFT", ns.MARGIN, -ns.CONTENT_TOP)
    nav:SetSize(100, 100)
    nav.views = { MakeViewRow(nav, "All items", "items"), MakeViewRow(nav, "Defaults", "defaults"), MakeViewRow(nav, "Settings", "settings") }
    nav.title = MakeText(nav, "GameFontNormal", "TOPLEFT", 0, 0)
    nav.title:SetText("Sacks")
    nav.hint = MakeText(nav, "GameFontDisableSmall", "TOPLEFT", 0, 0)
    nav.hint:SetText(LIST_HINT)
    nav.rows = {}
    nav.offset = 0
    nav.dropLine = nav:CreateTexture(nil, "OVERLAY")
    nav.dropLine:SetHeight(2)
    nav.dropLine:SetColorTexture(1, 0.82, 0, 1)
    nav.dropLine:Hide()
    -- scrolling the list redraws only the list
    nav.scroll = MakeScrollbar(nav, 0, 0, function(offset)
        nav.offset = offset
        ns.RefreshNav()
    end)
    nav:EnableMouseWheel(true)
    nav:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, (self.offset or 0) - delta * WHEEL_STEP)
        ns.RefreshNav()
    end)
    nav.newButton = MakeButton(nav, NEW_TEXT, nil, NewSack)
    -- a line between the list and the page beside it
    nav.edge = window:CreateTexture(nil, "ARTWORK")
    nav.edge:SetColorTexture(1, 1, 1, 0.12)
    nav.edge:SetWidth(1)
    nav.edge:SetPoint("TOPLEFT", nav, "TOPRIGHT", ns.MARGIN / 2, 0) -- as tall as the window's content: see FitWindow
    return nav
end

local function RefreshNav()
    local nav = ns.settings.nav
    local width = NavWidth()
    nav.width = width
    nav:SetWidth(width)
    local y = 0
    for _, row in ipairs(nav.views) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetWidth(width - BAR_ROOM)
        if ns.settings.active == row.view then row.selected:Show() else row.selected:Hide() end
        y = y + ROW_HEIGHT
    end
    y = y + PADDING
    nav.title:ClearAllPoints()
    nav.title:SetPoint("TOPLEFT", 0, -y)
    nav.hint:ClearAllPoints()
    nav.hint:SetPoint("BOTTOMLEFT", nav.title, "BOTTOMRIGHT", PADDING, 0)
    y = y + LABEL_HEIGHT + PADDING
    local groups = AllGroups()
    local visible = math.min(#groups, ListRoom(y, PADDING + BUTTON_HEIGHT, ROW_HEIGHT, 6, MOST_ROWS))
    nav.offset = math.max(0, math.min(nav.offset or 0, #groups - visible))
    nav.scroll.set(#groups, visible, nav.offset, visible * ROW_HEIGHT, y, width - 2 * SLOT_GAP)
    for index = 1, visible do
        local row = nav.rows[index] or MakeSackRow(nav)
        nav.rows[index] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(y + (index - 1) * ROW_HEIGHT))
        FillSackRow(nav, row, groups[nav.offset + index], width - BAR_ROOM)
    end
    for index = visible + 1, #nav.rows do
        nav.rows[index].group = nil
        nav.rows[index]:Hide()
    end
    y = y + visible * ROW_HEIGHT + PADDING
    nav.newButton:ClearAllPoints()
    nav.newButton:SetPoint("TOPLEFT", 0, -y)
    y = y + BUTTON_HEIGHT
    nav.height = y
    nav:SetHeight(y)
end

-- shared with the files after this one
ns.BuildNav = BuildNav
ns.RefreshNav = RefreshNav
