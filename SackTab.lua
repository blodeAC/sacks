-- sacks: SackTab.lua
-- The sack page: everything about one sack, picked in the list at the left of the window. Its name and buttons at the
-- top; the item table that shows what the sack's lines take, then Takes, the lines (applied as you change them); Looks, a small
-- picture of the sack on the screen with how it grows and fills; and Order.
local _, ns = ...
local Describe, FillLine, MAX_LINES, MakeLine, NewCondition = ns.Describe, ns.FillLine, ns.MAX_LINES, ns.MakeLine, ns.NewCondition
local Say, CopyCondition, DraftRule, FindGroup, HideRemoved, NAME_WIDTH = ns.Say, ns.CopyCondition, ns.DraftRule, ns.FindGroup, ns.HideRemoved, ns.NAME_WIDTH
local AllGroups, BUTTON_HEIGHT, BuildItemRows, CHECK_SIZE, CHOICE_WIDTH, CONTENT_TOP = ns.AllGroups, ns.BUTTON_HEIGHT, ns.BuildItemRows, ns.CHECK_SIZE, ns.CHOICE_WIDTH, ns.CONTENT_TOP
local DEFAULT_COLUMNS, DEFAULT_SORT, DROPDOWN_HEIGHT = ns.DEFAULT_COLUMNS, ns.DEFAULT_SORT, ns.DROPDOWN_HEIGHT
local LABEL_HEIGHT, LAYOUT_WIDTH, LINE_HEIGHT, MARGIN = ns.LABEL_HEIGHT, ns.LAYOUT_WIDTH, ns.LINE_HEIGHT, ns.MARGIN
local ButtonWidth, TextWidth, DROPDOWN_INSET, MakeTextBox = ns.ButtonWidth, ns.TextWidth, ns.DROPDOWN_INSET, ns.MakeTextBox
local GRIP_WIDTH, MakeButton, MakeCheck, MakeChoice, MakeScrollbar, MakeText = ns.GRIP_WIDTH, ns.MakeButton, ns.MakeCheck, ns.MakeChoice, ns.MakeScrollbar, ns.MakeText
local ORDER_ROW_HEIGHT, PADDING, PIN_WIDTH, Refresh, SLOT_GAP = ns.ORDER_ROW_HEIGHT, ns.PADDING, ns.PIN_WIDTH, ns.Refresh, ns.SLOT_GAP
local SORT_KEYS, SORT_KEY_ORDER, SortItems, TITLE_DEFAULT, TITLE_PIECES = ns.SORT_KEYS, ns.SORT_KEY_ORDER, ns.SortItems, ns.TITLE_DEFAULT, ns.TITLE_PIECES
local TABLE_ROW_HEIGHT, WHEEL_STEP, WINDOW_WIDTH, state = ns.TABLE_ROW_HEIGHT, ns.WHEEL_STEP, ns.WINDOW_WIDTH, ns.state
local BlankMode, GridCell, GridDimensions, LayoutOf, Matches = ns.BlankMode, ns.GridCell, ns.GridDimensions, ns.LayoutOf, ns.Matches
local FULL = WINDOW_WIDTH - MARGIN * 2
local MakeZoneTop, ZONE_HEIGHT, ZoneTitleMiddle = ns.MakeZoneTop, ns.ZONE_HEIGHT, ns.ZoneTitleMiddle
local UseDefaults, ApplyToEverySack, RefreshDefaultsButtons -- defined with the Looks and Order part
local RefreshOrderList -- defined after the Order part, which scrolls it
local TEXT_DROP = (BUTTON_HEIGHT - LABEL_HEIGHT) / 2 -- puts a label level with a button

---------------------------------------------------------------------------------------------------
-- The sack being edited
---------------------------------------------------------------------------------------------------

-- The sack the sack page shows. If there is none yet (or it was deleted), the first sack you made, else the first one.
local function EditedGroup()
    -- the Defaults page is this page showing the defaults, which are kept like a sack
    if ns.settings and ns.settings.active == "defaults" then return ns.DefaultsGroup() end
    local groups = AllGroups()
    for _, group in ipairs(groups) do
        if group == state.editing then return group end
    end
    state.editing = groups[1]
    for _, group in ipairs(groups) do
        if not group.builtin and not group.fixed then
            state.editing = group
            break
        end
    end
    return state.editing
end

-- A tooltip for any frame: a title and lines of help, shown while the mouse is over it.
local function SetTip(frame, title, ...)
    local lines = { ... }
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetText(title, 1, 0.82, 0)
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        ns.ShowTipBeside(self) -- beside the window, not over the controls
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- How many pixels the screen leaves for the page below `above` (the window's title bar and margins taken off).
local function ScreenRoom(above)
    local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    if type(screen) ~= "number" then screen = 1080 end
    return screen - 70 - CONTENT_TOP - MARGIN - above
end

---------------------------------------------------------------------------------------------------
-- Buttons in a row where one is picked, each as wide as its words
---------------------------------------------------------------------------------------------------

-- options: { label, value, tip }. onPick(value) runs when one is clicked. place(x, y) puts the row; select(value)
-- marks the picked one (gold); show(on) shows or hides the row.
local function MakeSegments(parent, options, onPick)
    local seg = { buttons = {} }
    local x = 0
    for _, option in ipairs(options) do
        local button = CreateFrame("Button", nil, parent)
        local width = ButtonWidth(option.label)
        button:SetSize(width, BUTTON_HEIGHT)
        button.back = button:CreateTexture(nil, "BACKGROUND")
        button.back:SetAllPoints()
        button.back:SetColorTexture(1, 1, 1, 0.07)
        button.picked = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        button.picked:SetAllPoints()
        button.picked:SetColorTexture(1, 0.82, 0, 0.3)
        button.picked:Hide()
        button.hover = button:CreateTexture(nil, "BACKGROUND", nil, 2)
        button.hover:SetAllPoints()
        button.hover:SetColorTexture(1, 1, 1, 0.08)
        button.hover:Hide()
        -- a thin frame round each choice; neighbours share their edge, and the picked one's is gold, on top
        button.edges = {}
        for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local edge = button:CreateTexture(nil, "BORDER")
            edge:SetPoint(side[1])
            edge:SetPoint(side[2])
            if side[1] == "TOPLEFT" and side[2] == "BOTTOMLEFT" or side[1] == "TOPRIGHT" then edge:SetWidth(1) else edge:SetHeight(1) end
            button.edges[#button.edges + 1] = edge
        end
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("CENTER", 0, 0)
        button.text:SetText(option.label)
        button.value = option.value
        button.offset = x
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnClick", function() onPick(option.value) end)
        button:SetScript("OnEnter", function(self)
            self.hover:Show()
            if option.tip then
                GameTooltip:SetOwner(self, "ANCHOR_NONE")
                GameTooltip:SetText(option.label, 1, 0.82, 0)
                GameTooltip:AddLine(option.tip, 1, 1, 1, true)
                ns.ShowTipBeside(self)
            end
        end)
        button:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        seg.buttons[#seg.buttons + 1] = button
        x = x + width - 1
    end
    seg.width = x + 1
    function seg.place(left, top)
        for _, button in ipairs(seg.buttons) do
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", parent, "TOPLEFT", left + button.offset, -top)
        end
    end
    function seg.select(value)
        for _, button in ipairs(seg.buttons) do
            local picked = button.value == value
            for _, edge in ipairs(button.edges) do
                if picked then edge:SetColorTexture(1, 0.82, 0, 0.9) else edge:SetColorTexture(1, 1, 1, 0.3) end
            end
            button:SetFrameLevel(button:GetParent():GetFrameLevel() + (picked and 2 or 1))
            if picked then
                button.picked:Show()
                button.text:SetTextColor(1, 0.82, 0)
            else
                button.picked:Hide()
                button.text:SetTextColor(1, 1, 1)
            end
        end
    end
    function seg.show(on)
        for _, button in ipairs(seg.buttons) do
            if on then button:Show() else button:Hide() end
        end
    end
    return seg
end

---------------------------------------------------------------------------------------------------
-- Looks and Order: how a sack grows, how it is sorted, and which items are pinned to the front
---------------------------------------------------------------------------------------------------

local DIRECTION_OPTIONS = { { label = "Ascending", value = false }, { label = "Descending", value = true } }
local MAX_SORT = 10 -- how many steps one sack's order can have

local function SortKeyOptions()
    local options = {}
    for _, key in ipairs(SORT_KEY_ORDER) do options[#options + 1] = { label = SORT_KEYS[key].label, value = key } end
    return options
end

-- The sack's items as the sack draws them: icons laid out by its own fill and slots per row, pinned ones first.
-- Click an icon to pin or unpin it; drag a pinned icon onto another to move it there. The name, how many, and where an
-- item goes now are in its tooltip.
local CELL_GAP = 2
local CELL_LEAST = 16 -- the smallest an icon is drawn when the sack is too tall for the room there is

-- Moves pin `from` to the place of pin `to` (or to the end of the pins, when dropped on an item that is not pinned).
local function MovePin(group, from, to)
    local pins = group.pins
    local id = table.remove(pins, from)
    if not to or to > #pins + 1 then to = #pins + 1 end
    table.insert(pins, to, id)
    Refresh()
end

local function ShowCellTooltip(cell)
    local entry = cell.data
    if not entry then return end
    GameTooltip:SetOwner(cell, "ANCHOR_NONE")
    if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. entry.id) then GameTooltip:SetText(entry.name) end
    GameTooltip:AddLine(" ")
    if entry.count == 0 then
        GameTooltip:AddLine("None in your bags right now", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(entry.count .. " in your bags", 1, 1, 1)
    end
    if entry.elsewhere then GameTooltip:AddLine("Goes to " .. entry.elsewhere .. " now: a sack above this one takes it", 1, 0.6, 0, true) end
    GameTooltip:AddLine(entry.pinned and "Click: unpin. Drag onto another pinned item to move it there." or "Click: pin it to the front", 0.5, 0.8, 1, true)
    ns.ShowTipBeside(cell)
end

local function MakeOrderCell(page)
    local cell = CreateFrame("Button", nil, page)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.edge = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = cell:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(1, 0.82, 0, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", 0, 0)
            edge:SetHeight(2)
        else
            edge:SetPoint("TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, 0, 0)
            edge:SetWidth(2)
        end
        cell.edge[#cell.edge + 1] = edge
    end
    -- the pin: a gold corner at the top left, on top of the gold frame
    cell.pin = cell:CreateTexture(nil, "OVERLAY", nil, 1)
    cell.pin:SetPoint("TOPLEFT", 0, 0)
    cell.pin:SetColorTexture(1, 0.82, 0, 1)
    cell.count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    cell.count:SetPoint("BOTTOMRIGHT", -1, 2)
    cell.hover = cell:CreateTexture(nil, "HIGHLIGHT")
    cell.hover:SetAllPoints()
    cell.hover:SetColorTexture(1, 1, 1, 0.2)
    cell:RegisterForClicks("LeftButtonUp")
    cell:RegisterForDrag("LeftButton")
    cell:SetScript("OnClick", function(self)
        if self.dragged then
            self.dragged = false
            return
        end
        local entry, group = self.data, EditedGroup()
        if not entry then return end
        group.pins = group.pins or {}
        if entry.pinned then
            table.remove(group.pins, entry.pinIndex)
        else
            group.pins[#group.pins + 1] = entry.id
        end
        Refresh()
    end)
    -- dragging a pinned icon: where it is let go decides; nothing runs while it is held
    cell:SetScript("OnDragStart", function(self)
        if not (self.data and self.data.pinned) then return end
        self.dragged = true
        self:SetAlpha(0.4)
        GameTooltip:Hide()
    end)
    cell:SetScript("OnDragStop", function(self)
        self:SetAlpha(1)
        if not (self.dragged and self.data) then return end
        for _, other in ipairs(page.orderCells) do
            if other ~= self and other:IsShown() and other.data and other:IsMouseOver() then
                MovePin(EditedGroup(), self.data.pinIndex, other.data.pinned and other.data.pinIndex or nil)
                return
            end
        end
    end)
    cell:SetScript("OnEnter", ShowCellTooltip)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cell
end

-- What Use defaults and Apply to every sack drop from a sack, per section. The corner is never dropped: it decides where
-- the sack sits and how the sacks docked to it hang, so a default corner is only given to new sacks.
local LOOK_FIELDS = { "flow", "title", "cols", "titleText" }
local ORDER_FIELDS = { "sort" }

local function HasOwn(group, fields)
    for _, field in ipairs(fields) do
        if group[field] ~= nil then return true end
    end
    return false
end

-- The sack shown drops its own settings for one section.
function UseDefaults(fields)
    local group = EditedGroup()
    for _, field in ipairs(fields) do group[field] = nil end
    Refresh()
end

-- Every sack drops its own settings for one section, after asking. Undo last reset or import (Settings) brings them back.
function ApplyToEverySack(fields, what)
    ns.Confirm("Make every sack use the default " .. what .. "?", "Each sack's own " .. what .. " settings are dropped. Undo last reset or import (Settings) brings them back.",
        "Apply", function()
            ns.BackupSacks()
            for _, group in ipairs(AllGroups()) do
                for _, field in ipairs(fields) do group[field] = nil end
            end
            Refresh()
        end)
end

-- On a sack's page: Use defaults, usable when the sack has settings of its own. On the Defaults page: Apply to every sack.
function RefreshDefaultsButtons(page, group)
    for _, pair in ipairs(page.defaultsButtons or {}) do
        if group.isDefaults then
            pair.use:Hide()
            pair.apply:Show()
        else
            pair.apply:Hide()
            pair.use:Show()
            if HasOwn(group, pair.fields) then pair.use:Enable() else pair.use:Disable() end
        end
    end
end

-- What the sections of the Looks and Order part share: where the next row goes (y), the column widths, the header.
local function LayoutContext(page)
    local L = { y = 0 }
    L.stride = LAYOUT_WIDTH + ns.DROPDOWN_RIGHT + PADDING -- from one drop-down of a row to the next
    L.WIDE = CHOICE_WIDTH + 2 * DROPDOWN_INSET
    L.FULL = FULL
    function L.mid(height) return (height - LABEL_HEIGHT) / 2 end -- drops a label to the middle of a control
    -- A part's top (the crease and the title), and at the right of the title a "Copy ... from" choice.
    function L.header(text, copyText, copy, what, fields)
        local top = L.y
        MakeZoneTop(page, top, text, L.FULL)
        local middle = top + ZoneTitleMiddle() -- the controls at the right sit level with the title
        local choiceX = L.FULL - L.WIDE - ns.DROPDOWN_RIGHT
        local labelX = choiceX - PADDING - math.ceil(TextWidth(copyText, "GameFontHighlight"))
        -- Use defaults (a sack's page) or Apply to every sack (the Defaults page), left of the copy choice
        local buttonRight = labelX - 2 * PADDING
        local use = MakeButton(page, "Use defaults", nil, function() UseDefaults(fields) end)
        use:SetPoint("TOPRIGHT", page, "TOPLEFT", buttonRight, -(middle - BUTTON_HEIGHT / 2))
        SetTip(use, "Use defaults", "Drop this sack's own " .. what .. " settings, so it follows the Defaults page.")
        local apply = MakeButton(page, "Apply to every sack", nil, function() ApplyToEverySack(fields, what) end)
        apply:SetPoint("TOPRIGHT", page, "TOPLEFT", buttonRight, -(middle - BUTTON_HEIGHT / 2))
        SetTip(apply, "Apply to every sack", "Every sack drops its own " .. what .. " settings and follows these.")
        page.defaultsButtons = page.defaultsButtons or {}
        page.defaultsButtons[#page.defaultsButtons + 1] = { use = use, apply = apply, fields = fields }
        local choiceTop = middle - BUTTON_HEIGHT / 2
        MakeText(page, "GameFontHighlight", "TOPLEFT", labelX, -(middle - LABEL_HEIGHT / 2)):SetText(copyText)
        local choice
        choice = MakeChoice(page, nil, choiceX, -choiceTop, function()
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
        end, L.WIDE)
        L.y = top + ZONE_HEIGHT
        return choice
    end
    return L
end

local function CopyLayout(source, target)
    for _, field in ipairs({ "anchor", "flow", "title", "cols", "titleText" }) do target[field] = source[field] end
end

local function CopySortOrder(source, target)
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
end

local function SortList()
    local group = EditedGroup()
    if not group.sort then
        -- a sack following the default order starts its own from a copy of it (the Defaults page, from the built-in one)
        local source = ns.Default("sort", DEFAULT_SORT)
        group.sort = {}
        for _, spec in ipairs(source) do
            local copy = { key = spec.key, descending = spec.descending }
            if spec.rule then
                copy.rule = {}
                for index, clause in ipairs(spec.rule) do copy.rule[index] = CopyCondition(clause) end
            end
            group.sort[#group.sort + 1] = copy
        end
    end
    return group.sort
end
local function MoveStep(from, to)
    local list = SortList()
    table.insert(list, to, table.remove(list, from))
    Refresh()
end

local function AddStep(spec)
    local list = SortList()
    if #list >= MAX_SORT then return Say("that is as many sort steps as a sack can have") end
    list[#list + 1] = spec
    Refresh()
end


-- The measurements of the sort steps: the number column, and the label column ("Then where", "Then sort by"), each as
-- wide as its widest text, and how far a control drops to sit in the middle of a row.
local function SortGeometry(L)
    local geom = { lift = ns.LINE_LIFT, labelLift = ns.LINE_LIFT + TEXT_DROP }
    geom.NUM = GRIP_WIDTH -- a step starts past the dots you drag it by
    -- the first box of every step starts past the widest label, and past the and/or box of a rule step's later lines
    geom.SLOT = ns.GateSeen() + PADDING
    for _, text in ipairs({ "First, where", "Then where", "Sort by", "Then sort by" }) do
        geom.SLOT = math.max(geom.SLOT, math.ceil(TextWidth(text, "GameFontHighlight")) + PADDING)
    end
    return geom
end

-- One row for each step the order can have. A row holds the controls of both kinds of step; placing decides which show.
local function MakeSortRows(page, L, geom)
    local NUM, SLOT, stride, FULL = geom.NUM, geom.SLOT, L.stride, L.FULL
    local ruleFields = ns.RuleFields
    -- room kept at the right of a row for its buttons: the widest set a row can have, and the gaps between them
    local CLUSTER = PADDING + ButtonWidth("+ And") + PADDING + ButtonWidth("x")
    for level = 1, MAX_SORT do
        local row = {}
        row.sortLabel = MakeText(page, "GameFontHighlight", "TOPLEFT", 0, 0)
        row.key = MakeChoice(page, nil, NUM + SLOT, 0, SortKeyOptions, function()
            SortList()[level].key = row.key.value()
            SortList()[level].descending = false
            Refresh()
        end, LAYOUT_WIDTH)
        row.direction = MakeChoice(page, nil, NUM + SLOT + stride, 0, function() return DIRECTION_OPTIONS end, function()
            SortList()[level].descending = row.direction.value()
            Refresh()
        end, CHOICE_WIDTH)
        row.andButton = MakeButton(page, "+ And", nil, function()
            local spec = SortList()[level]
            if #spec.rule >= MAX_LINES then return Say("that is as many conditions as a rule can have") end
            local condition = NewCondition("tooltip")
            condition.join = "AND"
            spec.rule[#spec.rule + 1] = condition
            Refresh()
        end)
        -- the step's place on the page (set when it is placed), for dragging it by its dots
        row.band = CreateFrame("Frame", nil, page)
        row.band:SetSize(FULL, LINE_HEIGHT)
        row.grip = ns.MakeGrip(row.band, BUTTON_HEIGHT)
        row.grip:SetPoint("TOPLEFT", 0, -ns.LINE_LIFT) -- level with the buttons
        ns.Reorderable(row.grip, page, function()
            local bands = {}
            for index = 1, #SortList() do bands[index] = page.sortRows[index].band end
            return bands
        end, function() return level end, MoveStep)
        row.remove = MakeButton(page, "x", nil, function()
            table.remove(SortList(), level)
            Refresh()
        end)
        ns.MarkWhatGoes(row.remove, row.band) -- the whole step, tinted while the mouse is on its x
        -- The conditions of a rule step: the same lines as a sack's rule, in one compact block.
        row.host = CreateFrame("Frame", nil, page)
        row.host:SetSize(FULL - NUM, LINE_HEIGHT)
        row.host.draft = {}
        row.host.lines = {}
        row.host.fieldOptions = ruleFields
        row.host.compact = true
        row.host.lineWidth = FULL - NUM -- ends where the step's own buttons end
        row.host.lineStart = 0
        row.host.lineReserve = CLUSTER
        row.host.onChange = function() Refresh() end
        page.sortRows[level] = row
    end
end


-- Add rule and Add sort field, on one row under the steps.
local function MakeSortButtons(page, geom)
    page.sortNone = MakeText(page, "GameFontDisableSmall", "TOPLEFT", geom.NUM, -(page.sortTop + geom.labelLift))
    page.sortNone:SetText("No steps: items stay in bag order.")
    page.sortAddMatch = MakeButton(page, "Add rule", nil, function()
        AddStep({ key = "match", rule = { NewCondition("tooltip") } })
    end)
    SetTip(page.sortAddMatch, "Add rule", "A step that puts the items its lines fit before the rest.")
    page.sortAdd = MakeButton(page, "Add sort field", nil, function()
        local used = {}
        for _, spec in ipairs(SortList()) do used[spec.key] = true end
        local key = "name"
        for _, candidate in ipairs(SORT_KEY_ORDER) do
            if not used[candidate] then key = candidate break end
        end
        AddStep({ key = key })
    end)
    SetTip(page.sortAdd, "Add sort field", "A step that sorts by a field. Each step only orders items the steps above it treated the same.")
end

-- Puts every step in place and returns how tall the list is.
local function PlaceSteps(page, L, geom, sort)
    local NUM, SLOT, lift, labelLift, stride, FULL = geom.NUM, geom.SLOT, geom.lift, geom.labelLift, L.stride, L.FULL
    local top = page.sortTop
    for level, row in ipairs(page.sortRows) do
        local spec = sort[level]
        if spec then
            local stepTop = top
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
                buttons = { row.andButton, row.remove }
            else
                row.host:Hide()
                row.sortLabel:ClearAllPoints()
                row.sortLabel:SetPoint("TOPLEFT", NUM, -(top + labelLift))
                row.key.moveTo(NUM + SLOT, -top)
                row.direction.moveTo(NUM + SLOT + stride, -top)
                top = top + LINE_HEIGHT
                buttons = { row.remove }
            end
            row.band:ClearAllPoints()
            row.band:SetPoint("TOPLEFT", 0, -stepTop)
            row.band:SetHeight(top - stepTop)
            -- the buttons sit at the right edge, on the first row of the step
            local rowTop = top - (spec.key == "match" and #spec.rule * LINE_HEIGHT or LINE_HEIGHT)
            local right = FULL
            for index = #buttons, 1, -1 do
                local button = buttons[index]
                button:ClearAllPoints()
                right = right - button:GetWidth()
                button:SetPoint("TOPLEFT", right, -(rowTop + lift))
                right = right - PADDING
            end
        end
    end
    return top - page.sortTop
end


-- Places what is under the steps: the buttons, then the item list.
local function PlaceBelow(page, height)
    local top = page.sortTop + math.max(height, LINE_HEIGHT)
    page.sortAddMatch:ClearAllPoints()
    page.sortAddMatch:SetPoint("TOPLEFT", 0, -top) -- at the left edge, under the dots
    page.sortAdd:ClearAllPoints()
    page.sortAdd:SetPoint("LEFT", page.sortAddMatch, "RIGHT", PADDING, 0)
    top = top + BUTTON_HEIGHT + PADDING
    page.orderTop = top
end

---------------------------------------------------------------------------------------------------
-- Looks: a small picture of the screen with the sack in it, and how it grows, fills and is titled
---------------------------------------------------------------------------------------------------

local LOOK_ROWS = 4 -- Fill, Title, Slots per row, Title text
local PREVIEW_HEIGHT = LOOK_ROWS * BUTTON_HEIGHT + (LOOK_ROWS - 1) * PADDING
local PREVIEW_WIDTH = math.ceil(PREVIEW_HEIGHT * 16 / 9) -- the shape of a wide screen
local PREVIEW_CELLS = 120 -- more than any bags hold
local CORNERS = {
    { value = "TOPLEFT", words = "top left", x = 0, y = 0 },
    { value = "TOPRIGHT", words = "top right", x = 1, y = 0 },
    { value = "BOTTOMLEFT", words = "bottom left", x = 0, y = 1 },
    { value = "BOTTOMRIGHT", words = "bottom right", x = 1, y = 1 },
}
local FILL_OPTIONS = {
    { label = "Like a page", value = "PAGE", tip = "Item 1 at the top left, across then down, wherever the sack is pinned. It still grows away from its corner." },
    { label = "Across", value = "ROWS", tip = "Item 1 in the pinned corner, then across, then the next row." },
    { label = "Down", value = "COLUMNS", tip = "Item 1 in the pinned corner, then down, then the next column." },
}
local TITLE_OPTIONS = {
    { label = "Above", value = "TOP" }, { label = "Below", value = "BOTTOM" },
    { label = "Hidden", value = "NONE", tip = "With no title, shift-drag the sack itself to move it." },
}
local BLANK_OPTIONS = {
    { label = "Last", value = "LAST", tip = "The empty slot (it shows the free bag slots) after the items." },
    { label = "First", value = "FIRST", tip = "The empty slot (it shows the free bag slots) before the items." },
    { label = "None", value = "NONE", tip = "No empty slot." },
}

local function Line(parent, layer, alpha)
    local texture = parent:CreateTexture(nil, layer or "BORDER")
    texture:SetColorTexture(1, 1, 1, alpha or 0.2)
    return texture
end

-- A 1-pixel frame around a frame.
local function Outline(frame, alpha)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = Line(frame, "BORDER", alpha)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", 0, 0)
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, 0, 0)
            edge:SetWidth(1)
        end
        edges[#edges + 1] = edge
    end
    return edges
end

-- The picture: the screen, split in four. Click a quarter to pin the sack to that corner. The sack is drawn there
-- with the items it holds now, numbered in the order they fill.
local function BuildPreview(page, top)
    local box = CreateFrame("Frame", nil, page)
    box:SetSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
    box:SetPoint("TOPLEFT", 0, -top)
    -- A sack too long to fit even at the smallest cells (very many slots per row or column) is cut off at the edge of
    -- the picture instead of drawing over the controls beside it.
    if box.SetClipsChildren then box:SetClipsChildren(true) end
    local back = box:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.45)
    Outline(box, 0.25)
    local across = Line(box, "BORDER", 0.08)
    across:SetPoint("LEFT", 0, 0)
    across:SetPoint("RIGHT", 0, 0)
    across:SetHeight(1)
    local down = Line(box, "BORDER", 0.08)
    down:SetPoint("TOP", 0, 0)
    down:SetPoint("BOTTOM", 0, 0)
    down:SetWidth(1)
    box.quarters = {}
    for _, corner in ipairs(CORNERS) do
        local quarter = CreateFrame("Button", nil, box)
        quarter:SetSize(PREVIEW_WIDTH / 2, PREVIEW_HEIGHT / 2)
        quarter:SetPoint("TOPLEFT", corner.x * PREVIEW_WIDTH / 2, -corner.y * PREVIEW_HEIGHT / 2)
        quarter.picked = quarter:CreateTexture(nil, "BACKGROUND")
        quarter.picked:SetAllPoints()
        quarter.picked:SetColorTexture(1, 0.82, 0, 0.08)
        quarter.hover = quarter:CreateTexture(nil, "BACKGROUND", nil, 1)
        quarter.hover:SetAllPoints()
        quarter.hover:SetColorTexture(1, 1, 1, 0.06)
        quarter.hover:Hide()
        quarter.value = corner.value
        quarter:RegisterForClicks("LeftButtonUp")
        quarter:SetScript("OnClick", function()
            EditedGroup().anchor = corner.value
            Refresh()
        end)
        quarter:SetScript("OnEnter", function(self)
            self.hover:Show()
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            if EditedGroup().isDefaults then
                GameTooltip:SetText("Pin new sacks to the " .. corner.words, 1, 0.82, 0)
                GameTooltip:AddLine("Sacks you already have keep their corner.", 1, 1, 1, true)
            else
                GameTooltip:SetText("Pin it to the " .. corner.words, 1, 0.82, 0)
                GameTooltip:AddLine("That corner stays put on screen. The sack grows away from it.", 1, 1, 1, true)
            end
            ns.ShowTipBeside(self)
        end)
        quarter:SetScript("OnLeave", function(self)
            self.hover:Hide()
            GameTooltip:Hide()
        end)
        box.quarters[#box.quarters + 1] = quarter
    end
    -- the sack: drawn above the quarters, letting clicks through to them
    local sack = CreateFrame("Frame", nil, box)
    sack:SetFrameLevel(box:GetFrameLevel() + 5)
    sack.back = sack:CreateTexture(nil, "BACKGROUND")
    sack.back:SetAllPoints()
    sack.back:SetColorTexture(0.12, 0.1, 0.08, 0.95)
    Outline(sack, 0.35)
    sack.title = sack:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sack.title:SetJustifyH("LEFT")
    if sack.title.SetWordWrap then sack.title:SetWordWrap(false) end
    sack.cells = {}
    box.sack = sack
    -- Above the sack: faint lines between the quarters and a bracket in each corner (the picked one filled in), so all
    -- four places to click show however big the sack is drawn. None of it takes the mouse; clicks reach the quarters.
    local over = CreateFrame("Frame", nil, box)
    over:SetAllPoints()
    over:SetFrameLevel(sack:GetFrameLevel() + 5)
    local across2 = Line(over, "OVERLAY", 0.15)
    across2:SetPoint("LEFT", 0, 0)
    across2:SetPoint("RIGHT", 0, 0)
    across2:SetHeight(1)
    local down2 = Line(over, "OVERLAY", 0.15)
    down2:SetPoint("TOP", 0, 0)
    down2:SetPoint("BOTTOM", 0, 0)
    down2:SetWidth(1)
    box.brackets = {}
    local arm, thick = 3 * SLOT_GAP, 2
    for _, corner in ipairs(CORNERS) do
        local bracket = { value = corner.value, parts = {} }
        local h = corner.x == 1 and "RIGHT" or "LEFT"
        local v = corner.y == 1 and "BOTTOM" or "TOP"
        local along = over:CreateTexture(nil, "OVERLAY")
        along:SetSize(arm, thick)
        along:SetPoint(v .. h, 0, 0)
        local upright = over:CreateTexture(nil, "OVERLAY")
        upright:SetSize(thick, arm)
        upright:SetPoint(v .. h, 0, 0)
        local fill = over:CreateTexture(nil, "OVERLAY")
        fill:SetSize(arm - thick, arm - thick)
        fill:SetPoint(v .. h, h == "LEFT" and thick or -thick, v == "TOP" and -thick or thick)
        bracket.parts = { along, upright }
        bracket.fill = fill
        box.brackets[#box.brackets + 1] = bracket
    end
    page.preview = box
end

local function PreviewCell(sack, index)
    local cell = sack.cells[index]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, sack)
    cell.back = cell:CreateTexture(nil, "ARTWORK")
    cell.back:SetAllPoints()
    cell.number = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.number:SetPoint("CENTER", 0, 0)
    sack.cells[index] = cell
    return cell
end

-- Draws the sack in the picture with one more item than fits in a row (the fewest that show how it fills and wraps),
-- and the empty slot if it has one, laid out by its own corner, fill and slots per row.
local function RefreshPreview(page, group)
    local box, sack = page.preview, page.preview.sack
    local layout = LayoutOf(group)
    local blankMode = BlankMode(group)
    local items = layout.wrap + 1
    local cells = math.min(PREVIEW_CELLS, items + (blankMode ~= "NONE" and 1 or 0))
    local empty = false
    local columns, rows = GridDimensions(layout, cells)
    local titleHeight = layout.title ~= "NONE" and LABEL_HEIGHT or 0
    local edge, pad, gap = SLOT_GAP, 2, 1
    local size = math.floor(math.min(
        (PREVIEW_WIDTH - 2 * edge - 2 * pad + gap) / columns,
        (PREVIEW_HEIGHT - 2 * edge - 2 * pad - titleHeight + gap) / rows)) - gap
    size = math.max(2, math.min(size, BUTTON_HEIGHT))
    local width = 2 * pad + columns * size + (columns - 1) * gap
    local height = 2 * pad + titleHeight + rows * size + (rows - 1) * gap
    local right = layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT"
    local bottom = layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT"
    sack:ClearAllPoints()
    sack:SetSize(width, height)
    sack:SetPoint(layout.anchor, box, layout.anchor, right and -edge or edge, bottom and edge or -edge)
    -- the title, as the sack shows it
    if titleHeight > 0 then
        sack.title:ClearAllPoints()
        sack.title:SetPoint(layout.title == "TOP" and "TOPLEFT" or "BOTTOMLEFT", pad, layout.title == "TOP" and -1 or 1)
        sack.title:SetWidth(width - 2 * pad)
        sack.title:SetText(state.titles[group] or group.name)
        sack.title:Show()
    else
        sack.title:Hide()
    end
    local fromRight = layout.flow ~= "PAGE" and right
    local fromBottom = layout.flow ~= "PAGE" and bottom
    local top = pad + (layout.title == "TOP" and titleHeight or 0)
    local blankCell = blankMode == "FIRST" and 1 or (blankMode == "LAST" and cells or nil)
    local numbered = size >= math.ceil(TextWidth("00", "GameFontHighlightSmall")) + 2
    for index = 1, cells do
        local cell = PreviewCell(sack, index)
        local column, row = GridCell(index, layout)
        if fromRight then column = columns - 1 - column end
        if fromBottom then row = rows - 1 - row end
        cell:ClearAllPoints()
        cell:SetSize(size, size)
        cell:SetPoint("TOPLEFT", pad + column * (size + gap), -(top + row * (size + gap)))
        if empty or index == blankCell then
            cell.back:SetColorTexture(1, 1, 1, 0.08)
            cell.number:SetText("")
        else
            cell.back:SetColorTexture(0.35, 0.28, 0.18, 1)
            local number = blankMode == "FIRST" and index - 1 or index
            cell.number:SetText(numbered and tostring(number) or "")
        end
        cell:Show()
    end
    for index = cells + 1, #sack.cells do sack.cells[index]:Hide() end
    for _, quarter in ipairs(box.quarters) do
        if quarter.value == layout.anchor then quarter.picked:Show() else quarter.picked:Hide() end
    end
    for _, bracket in ipairs(box.brackets) do
        local picked = bracket.value == layout.anchor
        for _, part in ipairs(bracket.parts) do
            if picked then part:SetColorTexture(1, 0.82, 0, 1) else part:SetColorTexture(1, 1, 1, 0.5) end
        end
        bracket.fill:SetColorTexture(1, 0.82, 0, 0.6)
        if picked then bracket.fill:Show() else bracket.fill:Hide() end
    end
end

-- Fill, Title, Slots per row (with the empty slot, or Always show for New) and Title text, beside the picture.
local function BuildLooks(page, L)
    page.copyLayout = L.header("Looks", "Copy layout from:", CopyLayout, "layout", LOOK_FIELDS)
    local top = L.y
    BuildPreview(page, top)
    local left = PREVIEW_WIDTH + 2 * PADDING
    local labelWidth = 0
    for _, text in ipairs({ "Fill", "Title", "Slots per row", "Title text" }) do
        labelWidth = math.max(labelWidth, math.ceil(TextWidth(text, "GameFontHighlight")))
    end
    local controls = left + labelWidth + PADDING
    local rowTop = function(index) return top + (index - 1) * (BUTTON_HEIGHT + PADDING) end
    local function label(text, index)
        MakeText(page, "GameFontHighlight", "TOPLEFT", left, -(rowTop(index) + TEXT_DROP)):SetText(text)
    end
    label("Fill", 1)
    page.fill = MakeSegments(page, FILL_OPTIONS, function(value)
        EditedGroup().flow = value
        Refresh()
    end)
    page.fill.place(controls, rowTop(1))
    label("Title", 2)
    page.titlePick = MakeSegments(page, TITLE_OPTIONS, function(value)
        EditedGroup().title = value
        Refresh()
    end)
    page.titlePick.place(controls, rowTop(2))
    -- slots per row: - n + and Use default; then the empty slot (Other) or Always show it (New)
    label("Slots per row", 3)
    local function perRow() return LayoutOf(EditedGroup()).wrap end
    page.perRowMinus = MakeButton(page, "-", nil, function()
        EditedGroup().cols = math.max(1, perRow() - 1)
        Refresh()
    end)
    page.perRowMinus:SetPoint("TOPLEFT", controls, -rowTop(3))
    page.perRowCount = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.perRowCount:SetWidth(math.ceil(TextWidth("000", "GameFontHighlight")))
    page.perRowCount:SetJustifyH("CENTER")
    page.perRowCount:SetPoint("LEFT", page.perRowMinus, "RIGHT", SLOT_GAP, 0)
    page.perRowPlus = MakeButton(page, "+", nil, function()
        EditedGroup().cols = perRow() + 1
        Refresh()
    end)
    page.perRowPlus:SetPoint("LEFT", page.perRowCount, "RIGHT", SLOT_GAP, 0)
    page.useDefault = MakeButton(page, "Use default", nil, function()
        EditedGroup().cols = nil
        Refresh()
    end)
    page.useDefault:SetPoint("LEFT", page.perRowPlus, "RIGHT", PADDING, 0)
    SetTip(page.useDefault, "Use default", "Go back to the slots per row on the Defaults page.")
    local afterDefault = controls + ButtonWidth("-") + ButtonWidth("+") + 2 * SLOT_GAP
        + math.ceil(TextWidth("000", "GameFontHighlight")) + PADDING + ButtonWidth("Use default") + 3 * PADDING
    page.blankLabel = MakeText(page, "GameFontHighlight", "TOPLEFT", afterDefault, -(rowTop(3) + TEXT_DROP))
    page.blankLabel:SetText("Empty slot")
    page.blank = MakeSegments(page, BLANK_OPTIONS, function(value)
        EditedGroup().blank = value
        Refresh()
    end)
    page.blank.place(afterDefault + math.ceil(TextWidth("Empty slot", "GameFontHighlight")) + PADDING, rowTop(3))
    page.alwaysCheck = MakeCheck(page, "Always show it", function(self)
        EditedGroup().always = self:GetChecked() and true or nil
        Refresh()
    end)
    page.alwaysCheck:SetPoint("TOPLEFT", afterDefault - SLOT_GAP, -(rowTop(3) + (BUTTON_HEIGHT - CHECK_SIZE) / 2))
    SetTip(page.alwaysCheck, "Always show it", "New is only on screen while it holds something. Tick this to see it now, to place it.")
    -- title text: the box, the token picker and Default
    label("Title text", 4)
    page.titleEdit = MakeTextBox(page, nil, function(self, typed)
        if not typed then return end
        EditedGroup().titleText = self:GetText()
        Refresh()
    end)
    page.titleEdit:SetPoint("TOPLEFT", controls + ns.TEXTBOX_ART_LEFT, -rowTop(4))
    SetTip(page.titleEdit, "Title text", "Tokens: {name} {count} {items} {value} {free} {special}. Longer than the sack: cut short with ..., the whole text on hover.")
    local tokenTop = rowTop(4) -- a drop-down's box is at the top of its frame
    page.insert = MakeChoice(page, nil, 0, -tokenTop, function()
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
    end, math.ceil(TextWidth("Insert token...")) + 2 * DROPDOWN_INSET)
    -- right to left: Default, the token picker (as wide as its own words; its menu is wider), and the box takes the
    -- room left of them
    local insertWidth = math.ceil(TextWidth("Insert token...")) + 2 * DROPDOWN_INSET
    page.titleDefault = MakeButton(page, "Default", nil, function()
        EditedGroup().titleText = nil
        Refresh()
    end)
    local defaultLeft = FULL - page.titleDefault:GetWidth()
    local insertLeft = defaultLeft - PADDING - insertWidth - ns.DROPDOWN_RIGHT
    page.insert.moveTo(insertLeft, -tokenTop)
    page.titleDefault:SetPoint("TOPLEFT", defaultLeft, -rowTop(4))
    -- its art reaches past its frame on both sides
    page.titleEdit:SetSize(insertLeft - PADDING - controls - 2 * ns.TEXTBOX_ART_LEFT, BUTTON_HEIGHT)
    L.y = top + PREVIEW_HEIGHT + 2 * PADDING
end

-- The order of the items: a numbered list of steps, each a rule or a field to sort by, then the items in that order.
local function BuildOrder(page, L)
    page.copySort = L.header("Order", "Copy order from:", CopySortOrder, "sort order", ORDER_FIELDS)
    local geom = SortGeometry(L)
    page.sortTop = L.y
    page.sortRows = {}
    MakeSortRows(page, L, geom)
    MakeSortButtons(page, geom)
    page.placeSteps = function(sort) return PlaceSteps(page, L, geom, sort) end
    page.placeBelow = function(height) PlaceBelow(page, height) end
    page.orderCells = {}
    page.orderEmpty = MakeText(page, "GameFontDisableSmall", "TOPLEFT", 0, 0)
    page.orderEmpty:SetText("Nothing in this sack right now.")
end

local function BuildLayout(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetSize(FULL, 100)
    local L = LayoutContext(page)
    BuildLooks(page, L)
    BuildOrder(page, L)
    return page
end

-- The picture and the controls beside it, set to what the sack has.
local function RefreshLooks(page, group)
    RefreshPreview(page, group)
    local layout = LayoutOf(group)
    page.fill.select(layout.flow)
    page.titlePick.select(layout.title)
    page.perRowCount:SetText(layout.wrap)
    if group.cols then page.useDefault:Enable() else page.useDefault:Disable() end
    -- only Other has the empty slot; only New needs Always show
    page.blank.show(group.fixed and true or false)
    page.blank.select(group.blank or "LAST")
    if group.fixed then page.blankLabel:Show() else page.blankLabel:Hide() end
    if group.builtin then page.alwaysCheck:Show() else page.alwaysCheck:Hide() end
    page.alwaysCheck:SetChecked(group.always and true or false)
    local titleText = group.titleText or ns.Default("titleText", TITLE_DEFAULT)
    if not page.titleEdit:HasFocus() and page.titleEdit:GetText() ~= titleText then page.titleEdit:SetText(titleText) end
    RefreshDefaultsButtons(page, group)
end

-- One step of the order: what it shows, and whether its dots show.
local function RefreshSortRow(row, spec, level, sort)
    local isRule = spec.key == "match"
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
    -- the dots are greyed out when there is nowhere to drag the step to
    row.band:Show()
    row.grip.SetUsable(#sort > 1) -- greyed out when there is nowhere to drag it to
    row.remove:Show()
end

-- A row with no step in it hides everything it holds.
local function HideSortRow(row)
    row.sortLabel:Hide()
    row.key.show(false)
    row.direction.show(false)
    row.andButton:Hide()
    row.band:Hide()
    row.remove:Hide()
    row.host:Hide()
end

local function RefreshSortSteps(page, group)
    local sort = group.sort or ns.Default("sort", DEFAULT_SORT)
    for level, row in ipairs(page.sortRows) do
        local spec = sort[level]
        if spec then
            RefreshSortRow(row, spec, level, sort)
        else
            HideSortRow(row)
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
end

-- Pinned items first, in the order you pinned them, then everything else sorted by the keys above. Changing
-- anything on this tab changes this list straight away.
local function OrderDisplay(group)
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
    return display
end


-- How tall the icons are drawn at full size: the rows the sack's items take, at the sack's own slot size.
local function OrderGridHeight(group, count)
    if count == 0 then return LABEL_HEIGHT end
    local _, rows = GridDimensions(LayoutOf(group), count)
    return rows * (ns.SlotSize() + CELL_GAP)
end

-- The icons under the steps, in no more than `room` pixels of height: at the sack's own slot size when they fit, else
-- smaller (down to CELL_LEAST).
function RefreshOrderList(page, group, display, room)
    local count = #display
    for index = count + 1, #page.orderCells do page.orderCells[index]:Hide() end
    if count == 0 then
        page.orderEmpty:ClearAllPoints()
        page.orderEmpty:SetPoint("TOPLEFT", 0, -page.orderTop)
        page.orderEmpty:Show()
        page.height = page.orderTop + LABEL_HEIGHT + PADDING
        page:SetHeight(page.height)
        return
    end
    page.orderEmpty:Hide()
    local layout = LayoutOf(group)
    local columns, rows = GridDimensions(layout, count)
    local size = math.min(ns.SlotSize(), math.floor((room or 0) / rows) - CELL_GAP, math.floor((FULL + CELL_GAP) / columns) - CELL_GAP)
    size = math.max(CELL_LEAST, size)
    local right = layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT"
    local bottom = layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT"
    local fromRight = layout.flow ~= "PAGE" and right
    local fromBottom = layout.flow ~= "PAGE" and bottom
    local showCount = size >= ns.SlotSize() * 0.6
    for index, entry in ipairs(display) do
        local cell = page.orderCells[index] or MakeOrderCell(page)
        page.orderCells[index] = cell
        cell.data = entry
        local column, row = GridCell(index, layout)
        if fromRight then column = columns - 1 - column end
        if fromBottom then row = rows - 1 - row end
        cell:ClearAllPoints()
        cell:SetSize(size, size)
        cell:SetPoint("TOPLEFT", column * (size + CELL_GAP), -(page.orderTop + row * (size + CELL_GAP)))
        cell.icon:SetTexture(entry.icon)
        cell.icon:SetDesaturated(entry.count == 0)
        cell.icon:SetAlpha(entry.count == 0 and 0.5 or 1)
        cell.count:SetText((showCount and entry.count > 1) and entry.count or "")
        local pinSize = math.max(4, math.floor(size / 4))
        cell.pin:SetSize(pinSize, pinSize)
        for _, edge in ipairs(cell.edge) do
            if entry.pinned then edge:Show() else edge:Hide() end
        end
        if entry.pinned then cell.pin:Show() else cell.pin:Hide() end
        cell:Show()
    end
    page.height = page.orderTop + rows * (size + CELL_GAP) + PADDING
    page:SetHeight(page.height)
end

---------------------------------------------------------------------------------------------------
-- The top of the page: the sack's name and the buttons that act on the whole sack
---------------------------------------------------------------------------------------------------

-- Gives the sack a new name. Sacks docked to it follow the new name. Says why not if it can't.
local function Rename(group, typed)
    local name = tostring(typed or ""):match("^%s*(.-)%s*$")
    if name == group.name then return end
    if name == "" then return Say("a sack needs a name") end
    local other = FindGroup(name)
    if other and other ~= group then return Say("there is already a sack called " .. name) end
    local oldName = group.name
    group.name = name
    for _, each in ipairs(AllGroups()) do
        if each.dock and each.dock.to == oldName then each.dock.to = name end
        for _, touch in ipairs(each.touches or {}) do
            if touch.to == oldName then touch.to = name end
        end
    end
    Refresh()
end

-- Deletes the sack after asking. Its items go to the next sack that takes them. The page moves to the sack below it.
local function DeleteSack(group)
    ns.Confirm("Delete the sack " .. group.name .. "?", "Its items go to the next sack in the list that takes them. This can't be undone.",
        "Delete", function()
            for index, each in ipairs(SacksDB.groups) do
                if each == group then
                    table.remove(SacksDB.groups, index)
                    HideRemoved(group)
                    state.editing = SacksDB.groups[index] or SacksDB.fallback
                    break
                end
            end
            Refresh()
        end)
end


-- Name, left-click, Move to the middle of the screen and Delete, on one row. New and Other keep their names,
-- so theirs is plain text with a word on what they take.
local function BuildHead(page)
    local head = CreateFrame("Frame", nil, page)
    head:SetSize(FULL, BUTTON_HEIGHT)
    head:SetPoint("TOPLEFT", 0, 0)
    page.head = head
    local label = "Name"
    MakeText(head, "GameFontHighlight", "TOPLEFT", 0, -TEXT_DROP):SetText(label)
    local nameX = math.ceil(TextWidth(label, "GameFontHighlight")) + 2 * PADDING
    -- The new name is taken when you press Enter or the box loses the keyboard; Escape puts the old one back. The box
    -- remembers which sack it is naming, so a name typed for one sack never lands on another.
    head.name = MakeTextBox(head, NAME_WIDTH)
    head.name:SetPoint("TOPLEFT", nameX, 0)
    head.name:SetMaxLetters(32)
    head.name:SetScript("OnEditFocusGained", function(self) self.group = EditedGroup() end)
    head.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    head.name:SetScript("OnEscapePressed", function(self)
        if self.group then self:SetText(self.group.name) end
        self:ClearFocus()
    end)
    head.name:SetScript("OnEditFocusLost", function(self)
        local group = self.group
        if not group then return end
        Rename(group, self:GetText())
        if group == EditedGroup() and self:GetText() ~= group.name then self:SetText(group.name) end
    end)
    head.fixedName = MakeText(head, "GameFontNormalLarge", "TOPLEFT", nameX, -TEXT_DROP)
    head.about = MakeText(head, "GameFontDisable", "TOPLEFT", 0, 0)
    head.use = MakeCheck(head, "Left-click uses its items", function(self)
        EditedGroup().useOnClick = self:GetChecked() and true or nil
        Refresh()
    end)
    head.use:SetPoint("TOPLEFT", nameX + NAME_WIDTH + 2 * PADDING, -(BUTTON_HEIGHT - CHECK_SIZE) / 2)
    SetTip(head.use, "Left-click uses its items", "Left-click an item in this sack to use it, like an action bar. Hold and drag to move it.",
        "The sack gets a title, border and name in the list in this colour. The colour is set on the Settings page.")
    head.delete = MakeButton(head, "Delete sack", nil, function() DeleteSack(EditedGroup()) end)
    head.delete:SetPoint("TOPRIGHT", 0, 0)
    head.middle = MakeButton(head, "Move to the middle of the screen", nil, function() ns.ResetPosition(EditedGroup()) end)
    head.middle:SetPoint("TOPRIGHT", head.delete, "TOPLEFT", -PADDING, 0)
end

-- Sets the top row for this sack and returns how tall it is.
local function RefreshHead(page, group)
    local head = page.head
    if group.builtin or group.fixed or group.isDefaults then
        head.name:Hide()
        head.fixedName:SetText(group.name)
        head.fixedName:Show()
        head.about:SetText(group.isDefaults and "for every sack that has no setting of its own"
            or group.builtin and "what arrives in combat, or while the mouse is on the sacks, until they can sort it" or "everything the other sacks don't take")
        head.about:ClearAllPoints()
        head.about:SetPoint("LEFT", head.fixedName, "RIGHT", 2 * PADDING, 0)
        head.about:Show()
        head.delete:Hide()
    else
        head.fixedName:Hide()
        head.about:Hide()
        head.name:Show()
        -- still typing a name for a sack that is no longer the one shown: that name is taken now
        if head.name:HasFocus() and head.name.group ~= group then head.name:ClearFocus() end
        if not head.name:HasFocus() then
            head.name.group = group
            if head.name:GetText() ~= group.name then head.name:SetText(group.name) end
        end
        head.delete:Show()
    end
    if group.isDefaults then head.middle:Hide() else head.middle:Show() end
    -- nothing in New can be used, and the words about it sit where the box would be
    if group.builtin or group.isDefaults then
        head.use:Hide()
    else
        head.use:ClearAllPoints()
        if group.fixed then
            head.use:SetPoint("LEFT", head.about, "RIGHT", 3 * PADDING, 0)
        else
            head.use:SetPoint("LEFT", head.name, "RIGHT", 2 * PADDING, 0)
        end
        head.use:SetChecked(group.useOnClick and true or false)
        -- its words in the colour that marks such sacks (title, border, name in the list), so the colour explains itself
        local markR, markG, markB = ns.ClickColor()
        if markR then head.use.label:SetTextColor(markR, markG, markB) else head.use.label:SetTextColor(1, 1, 1) end
        head.use:Show()
    end
    return BUTTON_HEIGHT + PADDING
end

---------------------------------------------------------------------------------------------------
-- Takes: the sack's lines, applied as you change them, over the table of items that shows what they take. Undo
-- changes goes back to what the sack took when you opened it here.
---------------------------------------------------------------------------------------------------

local function CopyRule(rule)
    local copy = {}
    for index, condition in ipairs(rule or {}) do copy[index] = CopyCondition(condition) end
    return copy
end

-- The lines on the page are a draft of the rule: they may hold a line that says nothing yet (an empty text, an item
-- you are still typing). The sack gets the lines that say something.
local function ApplyDraft(page)
    local group = EditedGroup()
    group.rule = DraftRule(page.takes.host.draft)
    page.appliedRule = group.rule
    Refresh()
end

-- Takes the sack's own lines as the draft: when another sack is opened, or its rule was changed somewhere else
-- (an import, an undo).
local function LoadDraft(page, group)
    page.takes.host.draft = CopyRule(group.rule)
    page.appliedRule = group.rule
    if page.draftFor ~= group then
        page.draftFor = group
        page.savedRule = CopyRule(group.rule)
    end
end


-- A click on a row of the table: an "Exact item" line for it, or, if there is one already, that line taken out.
local function ToggleItemLine(page, id)
    local draft = page.takes.host.draft
    for index, clause in ipairs(draft) do
        if clause.field == "item" and clause.value == id then
            table.remove(draft, index)
            if draft[1] then draft[1].join = nil end
            return ApplyDraft(page)
        end
    end
    if #draft >= MAX_LINES then return Say("that is as many lines as a sack can have") end
    draft[#draft + 1] = { field = "item", op = "=", value = id, join = #draft > 0 and "OR" or nil }
    ApplyDraft(page)
end

-- A small coloured square and its words, for the key to the table's colours.
local function KeyEntry(parent, color, text)
    local swatch = parent:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(LABEL_HEIGHT - 2, LABEL_HEIGHT - 2)
    swatch:SetColorTexture(color[1], color[2], color[3], math.min(1, color[4] * 2.5))
    local words = MakeText(parent, "GameFontHighlightSmall", "TOPLEFT", 0, 0)
    words:SetText(text)
    return swatch, words, LABEL_HEIGHT + math.ceil(TextWidth(text, "GameFontHighlightSmall"))
end

local function BuildTakes(page)
    local takes = CreateFrame("Frame", nil, page)
    takes:SetSize(FULL, 10)
    page.takes = takes
    -- The item table with its Show and Search on top, then the key to the table's colours, then the part's top (the crease
    -- and Takes), then the lines, then Add a line and Undo changes. The key and the part's top are one frame, placed under
    -- the table.
    local header = CreateFrame("Frame", nil, takes)
    local keyHeight = LABEL_HEIGHT + PADDING
    header:SetSize(FULL, keyHeight + ZONE_HEIGHT)
    takes.header = header
    local inSwatch, inWords, inWidth = KeyEntry(header, ns.MARK_IN, "in this sack")
    local takenSwatch, takenWords, takenWidth = KeyEntry(header, ns.MARK_TAKEN, "fits, but a sack above it in the list takes it")
    local x = FULL - takenWidth
    takenSwatch:SetPoint("TOPLEFT", x, -1)
    takenWords:SetPoint("TOPLEFT", x + LABEL_HEIGHT, 0)
    x = x - 3 * PADDING - inWidth
    inSwatch:SetPoint("TOPLEFT", x, -1)
    inWords:SetPoint("TOPLEFT", x + LABEL_HEIGHT, 0)
    local titleText = MakeZoneTop(header, keyHeight, "Takes", FULL)
    -- the title takes the mouse for its tooltip
    local title = CreateFrame("Frame", nil, header)
    title:SetSize(math.ceil(TextWidth("Takes", "SacksZoneFont")), ns.ZONE_TITLE_HEIGHT)
    title:SetPoint("TOPLEFT", titleText, "TOPLEFT", 0, 0)
    title:EnableMouse(true)
    SetTip(title, "Takes", "An item goes to the first sack in the list at the left whose lines it fits.",
        "A or B and C means A or (B and C): and is stronger than or.", "Hover a text box to see what you can type in it.")
    takes.top = keyHeight + ZONE_HEIGHT -- the height of the key and the part's top
    -- The lines are drawn by the same code as everywhere else; this frame is their page.
    local host = CreateFrame("Frame", nil, takes)
    host:SetSize(FULL, LINE_HEIGHT)
    host.draft, host.lines = {}, {}
    host.onChange = function() ApplyDraft(page) end
    takes.host = host
    takes.add = MakeButton(takes, "Add a line", nil, function()
        if #host.draft >= MAX_LINES then return Say("that is as many lines as a sack can have") end
        host.draft[#host.draft + 1] = NewCondition("name") -- empty: says nothing until you fill it in
        ns.RefreshSettings()
    end)
    takes.undo = MakeButton(takes, "Undo changes", nil, function()
        local group = EditedGroup()
        group.rule = CopyRule(page.savedRule)
        LoadDraft(page, group)
        Refresh()
    end)
    takes.undo:SetPoint("LEFT", takes.add, "RIGHT", PADDING, 0)
    SetTip(takes.undo, "Undo changes", "Back to the lines this sack had when you opened it here.")
    -- the table, its Show and Search row on top of it
    local items = ns.BuildItemTable(takes, 0, 12)
    items.clickHint = "Click: add it as an Exact item line (click again to take it out)"
    items.markOf = function(row)
        local group = EditedGroup()
        if row.sack == group.name then return "in" end
        if #group.rule > 0 and Matches(group.rule, row) then return "taken" end
    end
    items.fits = function(row) return items.markOf(row) ~= nil end
    items.onRowClick = function(row) ToggleItemLine(page, row.itemID) end
    takes.table = items
    -- New and Other have no lines; Takes is not shown for them.
end

-- The draft for this sack, loaded from its rule when another sack is opened or its rule changed elsewhere.
local function LoadedDraft(page, group)
    if page.draftFor ~= group or page.appliedRule ~= group.rule then LoadDraft(page, group) end
    return page.takes.host.draft
end

-- Places the key, the crease and title, the lines and their buttons from `top` down, and returns where they end.
local function PlaceLines(page, group, top)
    local takes, host = page.takes, page.takes.host
    if page.draftFor ~= group or page.appliedRule ~= group.rule then LoadDraft(page, group) end
    takes.header:ClearAllPoints()
    takes.header:SetPoint("TOPLEFT", 0, -top)
    local y = top + takes.top
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", 0, -y)
    for index, clause in ipairs(host.draft) do
        local line = host.lines[index] or MakeLine(host)
        host.lines[index] = line
        FillLine(line, clause, index, #host.draft)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 0, -(index - 1) * LINE_HEIGHT)
        line:Show()
    end
    for index = #host.draft + 1, #host.lines do host.lines[index]:Hide() end
    host:SetHeight(math.max(1, #host.draft * LINE_HEIGHT))
    y = y + #host.draft * LINE_HEIGHT
    takes.add:ClearAllPoints()
    takes.add:SetPoint("TOPLEFT", 0, -y) -- at the left edge, under the dots
    if Describe(group.rule) ~= Describe(page.savedRule) then takes.undo:Enable() else takes.undo:Disable() end
    return y + BUTTON_HEIGHT + PADDING
end

---------------------------------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------------------------------

local function BuildSack(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetSize(FULL, 100)
    BuildHead(page)
    BuildTakes(page)
    page.layout = BuildLayout(page)
    page.height = 100
    return page
end

-- How many rows the item table and the order list get: as many as they have, while the screen has room for both,
-- else shared out, each keeping a few.
local function ShareRows(room, tableWant, orderWant)
    local TABLE_LEAST, ORDER_LEAST = 5, 3
    local tableRows = math.min(tableWant, math.max(TABLE_LEAST,
        math.floor((room - math.min(orderWant, ORDER_LEAST) * ORDER_ROW_HEIGHT) / TABLE_ROW_HEIGHT)))
    local orderRows = math.min(orderWant, math.max(ORDER_LEAST,
        math.floor((room - tableRows * TABLE_ROW_HEIGHT) / ORDER_ROW_HEIGHT)))
    return tableRows, orderRows
end

local function RefreshSack()
    local page = ns.settings.sack
    local group = EditedGroup()
    if not group then return end
    local layout, takes = page.layout, page.takes
    local y = RefreshHead(page, group)
    -- Looks and Order first: their height above the item list does not depend on anything else
    RefreshLooks(layout, group)
    RefreshSortSteps(layout, group)
    local display = OrderDisplay(group)
    local special = group.builtin or group.fixed or group.isDefaults
    local tableWant, linesHeight, all, filtered = 0, 0, nil, nil
    if special then
        takes:Hide()
    else
        takes:Show()
        takes:ClearAllPoints()
        takes:SetPoint("TOPLEFT", 0, -y)
        -- the title, lines and buttons don't depend on the table's height: measured first, placed once it is known
        linesHeight = takes.top + #(LoadedDraft(page, group)) * LINE_HEIGHT + BUTTON_HEIGHT + PADDING
        all = BuildItemRows()
        takes.table.draft = takes.host.draft
        filtered = ns.FilteredRows(all, takes.table)
        tableWant = math.max(#filtered, 1)
    end
    -- the fixed parts of the page, then the rows the screen has room for
    local fixed = y + layout.orderTop + (special and 0 or (ns.TABLE_TOP + PADDING + linesHeight))
    -- the icons' room is counted in order rows, so the table and the icons can share the screen the same way
    local orderWant = math.ceil(OrderGridHeight(group, #display) / ORDER_ROW_HEIGHT)
    local tableRows, orderRows = ShareRows(ScreenRoom(fixed), math.min(tableWant, 12), orderWant)
    if not special then
        takes.table:ClearAllPoints()
        takes.table:SetPoint("TOPLEFT", 0, 0)
        ns.ShowTable(takes.table, all, tableRows, filtered)
        local tableHeight = ns.TABLE_TOP + tableRows * TABLE_ROW_HEIGHT + PADDING
        takes.table:SetHeight(tableHeight)
        local height = PlaceLines(page, group, tableHeight)
        takes:SetHeight(height)
        y = y + height
    end
    layout:ClearAllPoints()
    layout:SetPoint("TOPLEFT", 0, -y)
    RefreshOrderList(layout, group, display, orderRows * ORDER_ROW_HEIGHT)
    page.height = y + layout.height
    page:SetHeight(page.height)
    ns.FitWindow(page.height)
end

-- shared with the files after this one
ns.BuildSack = BuildSack
ns.RefreshSack = RefreshSack
ns.EditedGroup = EditedGroup
