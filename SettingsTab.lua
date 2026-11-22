-- sacks: SettingsTab.lua
-- The Settings page: the game's own bags, the free-slots box, how left-click sacks are marked, backup and sharing, and
-- going back to the starting sacks. (The defaults every sack falls back on have their own page, Defaults.)
local _, ns = ...
local BUTTON_HEIGHT, CHECK_SIZE, DEFAULT_COLUMNS, DefaultGroups = ns.BUTTON_HEIGHT, ns.CHECK_SIZE, ns.DEFAULT_COLUMNS, ns.DefaultGroups
local HideOwnBags, HideRemoved, LABEL_HEIGHT, MARGIN = ns.HideOwnBags, ns.HideRemoved, ns.LABEL_HEIGHT, ns.MARGIN
local MakeButton, MakeCheck, MakeChoice, MakeText = ns.MakeButton, ns.MakeCheck, ns.MakeChoice, ns.MakeText
local PADDING, Refresh, SLOT_GAP, TextWidth = ns.PADDING, ns.Refresh, ns.SLOT_GAP, ns.TextWidth
local WINDOW_WIDTH, WidgetGroup, state = ns.WINDOW_WIDTH, ns.WidgetGroup, ns.state
local FULL = WINDOW_WIDTH - MARGIN * 2

-- A section's top (the crease and its title, as on a sack's page) and the grey note beside the title. Returns where the
-- section's content starts.
local function SectionTitle(parent, title, note)
    local text = ns.MakeZoneTop(parent, 0, title, FULL)
    if note then
        local words = MakeText(parent, "GameFontDisableSmall", "BOTTOMLEFT", 0, 0)
        words:ClearAllPoints()
        words:SetPoint("BOTTOMLEFT", text, "BOTTOMRIGHT", PADDING, 0)
        words:SetText(note)
    end
    return ns.ZONE_HEIGHT
end

-- The game's own bags, the free-slots box, the colour that marks left-click sacks, and how full the bags are.
local function BuildBagOptions(page)
    local box = CreateFrame("Frame", nil, page)
    box:SetSize(FULL, 10)
    box:SetPoint("TOPLEFT", 0, 0)
    page.bags = box
    local y = SectionTitle(box, "Bags")
    page.hideCheck = MakeCheck(box, "Stop the game opening its own bags by itself (vendors etc.). B and the bag buttons still work.", function(self)
        SacksDB.hideBags = self:GetChecked() and true or false
        HideOwnBags()
    end)
    page.hideCheck:SetPoint("TOPLEFT", -SLOT_GAP, -y)
    y = y + CHECK_SIZE + SLOT_GAP
    page.widgetCheck = MakeCheck(box, "Show a free-slots box I can place anywhere", function(self)
        WidgetGroup().shown = self:GetChecked() and true or false
        Refresh()
    end)
    page.widgetCheck:SetPoint("TOPLEFT", -SLOT_GAP, -y)
    -- brings the box back to a place you can see, if you lose it
    page.widgetReset = MakeButton(box, "Reset its position", nil, function() ns.ResetPosition(WidgetGroup()) end)
    page.widgetReset:SetPoint("LEFT", page.widgetCheck.label, "RIGHT", PADDING * 2, 0)
    y = y + CHECK_SIZE + SLOT_GAP
    page.moneyCheck = MakeCheck(box, "Show a gold box I can place anywhere", function(self)
        ns.MoneyGroup().shown = self:GetChecked() and true or false
        Refresh()
    end)
    page.moneyCheck:SetPoint("TOPLEFT", -SLOT_GAP, -y)
    page.moneyReset = MakeButton(box, "Reset its position", nil, function() ns.ResetPosition(ns.MoneyGroup()) end)
    page.moneyReset:SetPoint("LEFT", page.moneyCheck.label, "RIGHT", PADDING * 2, 0)
    y = y + CHECK_SIZE + SLOT_GAP
    -- Sacks that use items on left click are marked in this colour (title and border), so they stand out.
    local markText = "Mark sacks whose items left-click uses:"
    MakeText(box, "GameFontHighlight", "TOPLEFT", 0, -(y + (BUTTON_HEIGHT - LABEL_HEIGHT) / 2)):SetText(markText)
    page.clickColor = MakeChoice(box, nil, math.ceil(TextWidth(markText, "GameFontHighlight")) + PADDING, -y,
        function() return ns.CLICK_COLORS end, function()
            SacksDB.clickColor = page.clickColor.value()
            Refresh()
        end)
    page.clickColor.fit()
    y = y + BUTTON_HEIGHT + PADDING
    page.bagInfo = MakeText(box, "GameFontHighlightSmall", "TOPLEFT", 0, -y)
    page.bagInfo:SetWidth(FULL)
    page.bagInfoTop = y
end

-- How the Town sacks line up beside a vendor, mailbox, auction house or bank window: each choice where there is more
-- than one sensible way, as a labelled row.
local TOWN_ARRANGE = {
    { label = "Narrowest, the first sack top left", value = "narrow" },
    { label = "In my sack-list order", value = "list" },
}
local TOWN_HEIGHT = {
    { label = "The window", value = "window" },
    { label = "Down to the bottom of the screen", value = "screen" },
}
local TOWN_EMPTY = {
    { label = "Fill the room left at the edges", value = "fill" },
    { label = "Hidden", value = "hide" },
    { label = "Arranged like the rest", value = "pack" },
}
local TOWN_SORT = {
    { label = "The order the Normal sacks put them in", value = "normal" },
    { label = "Each sack's own order", value = "own" },
}
local BUTLER_FIRST = "\0butler" -- the first sack choice that means "the one Butler fills for this place"

-- The Town sacks, whichever layout is showing (for the first-sack choices).
local function TownSacks()
    local groups, fallback
    if ns.ShowingLayout() == "town" then
        groups, fallback = SacksDB.groups, SacksDB.fallback
    elseif SacksDB.otherLayout and SacksDB.otherLayout.groups then
        groups, fallback = SacksDB.otherLayout.groups, SacksDB.otherLayout.fallback
    else
        groups = ns.TownGroups()
    end
    local list = {}
    for _, group in ipairs(groups or {}) do list[#list + 1] = group end
    if fallback then list[#list + 1] = fallback end
    return list
end

local function FirstOptions(place)
    local verdict = ns.TOWN_FIRST_VERDICT[place]
    local label = verdict
    for _, option in ipairs(ns.ButlerOptions()) do
        if option.value == verdict then label = option.label end
    end
    local options = { { label = "The sack Butler fills with " .. label, value = BUTLER_FIRST } }
    for _, group in ipairs(TownSacks()) do
        if group.name and group.name ~= "" then options[#options + 1] = { label = group.name, value = group.name } end
    end
    options[#options + 1] = { label = "None", value = "" }
    return options
end

local function BuildTownBeside(page, box, y)
    local rows = {
        { text = "Beside a window, arrange them:", options = function() return TOWN_ARRANGE end, key = "townOrder" },
        { text = "Columns as tall as:", options = function() return TOWN_HEIGHT end, key = "townHeight" },
        { text = "Empty sacks:", options = function() return TOWN_EMPTY end, key = "townEmpty" },
        { text = "Items inside each sack:", options = function() return TOWN_SORT end, key = "townSort" },
    }
    for _, place in ipairs(ns.TOWN_PLACES) do
        rows[#rows + 1] = { text = "First sack at " .. place.label .. ":", options = function() return FirstOptions(place.key) end,
            place = place.key }
    end
    local labelWidth = 0
    for _, row in ipairs(rows) do labelWidth = math.max(labelWidth, math.ceil(TextWidth(row.text, "GameFontHighlight"))) end
    page.townRows = {}
    for _, row in ipairs(rows) do
        MakeText(box, "GameFontHighlight", "TOPLEFT", 0, -(y + (BUTTON_HEIGHT - LABEL_HEIGHT) / 2)):SetText(row.text)
        local choice
        choice = MakeChoice(box, nil, labelWidth + PADDING, -y, row.options, function()
            local value = choice.value()
            if row.place then
                SacksDB.townFirst = SacksDB.townFirst or {}
                if value == BUTLER_FIRST then value = nil end
                SacksDB.townFirst[row.place] = value
            else
                SacksDB[row.key] = value
            end
            Refresh()
        end)
        choice.fit()
        choice.row = row
        page.townRows[#page.townRows + 1] = choice
        y = y + BUTTON_HEIGHT + SLOT_GAP
    end
    return y + PADDING
end

-- Shows the saved Town choices in their rows (the first-sack lists also follow renamed and new sacks).
local function RefreshTownRows(page)
    for _, choice in ipairs(page.townRows or {}) do
        local row = choice.row
        if row.place then
            local chosen = SacksDB.townFirst and SacksDB.townFirst[row.place]
            choice.fit()
            choice.select(chosen == nil and BUTLER_FIRST or chosen)
        else
            choice.select(SacksDB[row.key] or row.options()[1].value)
        end
    end
end

-- The Town layout: switching to it here, its button, and which windows bring it out by themselves.
local TOWN_SHOW, NORMAL_SHOW = "Show Town sacks", "Show Normal sacks"
local function BuildTown(page)
    local box = CreateFrame("Frame", nil, page)
    page.town = box
    local y = SectionTitle(box, "Town", "a second layout of sacks, for selling, posting and muling")
    page.townToggle = MakeButton(box, TOWN_SHOW, ns.ButtonWidth({ TOWN_SHOW, NORMAL_SHOW }), function() ns.ToggleTown() end)
    page.townToggle:SetPoint("TOPLEFT", 0, -y)
    page.townShowing = MakeText(box, "GameFontHighlight", "TOPLEFT", 0, 0)
    page.townShowing:ClearAllPoints()
    page.townShowing:SetPoint("LEFT", page.townToggle, "RIGHT", PADDING * 2, 0)
    y = y + BUTTON_HEIGHT + PADDING
    page.townButtonCheck = MakeCheck(box, "Show the Town button I can place anywhere", function(self)
        ns.TownButtonPlace().shown = self:GetChecked() and true or false
        ns.UpdateTownButton()
    end)
    page.townButtonCheck:SetPoint("TOPLEFT", -SLOT_GAP, -y)
    local reset = MakeButton(box, "Reset its position", nil, function() ns.ResetTownButton() end)
    reset:SetPoint("LEFT", page.townButtonCheck.label, "RIGHT", PADDING * 2, 0)
    y = y + CHECK_SIZE + SLOT_GAP
    local lead = "Show Town by itself while open:"
    MakeText(box, "GameFontHighlight", "TOPLEFT", 0, -(y + (CHECK_SIZE - LABEL_HEIGHT) / 2)):SetText(lead)
    page.townChecks = {}
    local x = math.ceil(TextWidth(lead, "GameFontHighlight")) + PADDING
    for _, place in ipairs(ns.TOWN_PLACES) do
        local label = place.label:gsub("^%l", string.upper)
        local check = MakeCheck(box, label, function(self) ns.SetTownAt(place.key, self:GetChecked()) end)
        check:SetPoint("TOPLEFT", x, -y)
        check.key = place.key
        page.townChecks[#page.townChecks + 1] = check
        x = x + CHECK_SIZE + 2 + math.ceil(TextWidth(label, "GameFontHighlight")) + PADDING * 2
    end
    y = y + CHECK_SIZE + SLOT_GAP
    y = BuildTownBeside(page, box, y)
    MakeText(box, "GameFontDisableSmall", "TOPLEFT", 0, -y):SetText(
        "The sack list and every sack's page edit the layout that is showing: show Town to set up its sacks.")
    y = y + LABEL_HEIGHT + PADDING
    page.townHeight = y
    box:SetSize(FULL, y)
end

-- Your sacks as text to keep or share, a way back from the last reset or import, and the reset itself.
local function BuildBackup(page)
    local box = CreateFrame("Frame", nil, page)
    page.backup = box
    local y = SectionTitle(box, "Backup and sharing", "your sacks as text: keep it, or give it to someone")
    local export = MakeButton(box, "Export", nil, function() ns.ShowTransfer("export") end)
    export:SetPoint("TOPLEFT", 0, -y)
    local import = MakeButton(box, "Import", nil, function() ns.ShowTransfer("import") end)
    import:SetPoint("LEFT", export, "RIGHT", PADDING, 0)
    page.undoButton = MakeButton(box, "Undo last reset or import", nil, function() ns.UndoSacks() end)
    page.undoButton:SetPoint("LEFT", import, "RIGHT", PADDING, 0)
    -- at the far right, away from the everyday buttons; it asks before it does anything
    page.resetButton = MakeButton(box, "Reset to starting sacks", nil, function()
        local which = ns.ShowingLayout() == "town" and "Town" or "Normal"
        ns.Confirm("Reset the " .. which .. " sacks to their starting sacks?", "Every " .. which .. " sack you made, and its layout, pins and order, is thrown away. Undo last reset or import brings them back.",
            "Reset", function()
                ns.BackupSacks()
                for _, group in ipairs(SacksDB.groups) do HideRemoved(group) end
                SacksDB.groups = DefaultGroups()
                Refresh()
            end)
    end)
    page.resetButton:SetPoint("TOPRIGHT", 0, -y)
    page.backupHeight = y + BUTTON_HEIGHT + PADDING
    box:SetSize(FULL, page.backupHeight)
end

local function BuildSettingsPage(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetSize(FULL, 100)
    BuildBagOptions(page)
    BuildTown(page)
    BuildBackup(page)
    page.height = 100
    return page
end

-- One quiet line about space; anything else only appears when something is actually wrong.
local function SpaceLines()
    local free = 0
    for _, bag in ipairs(state.bags or {}) do free = free + bag.free end
    local used = (state.slots or 0) - (state.freeAll or 0)
    local count = #(state.items or {})
    local lines = { string.format("Bag space: %d of %d slots used, %d free", used, state.slots or 0, free) }
    for _, bag in ipairs(state.bags or {}) do
        if bag.special then lines[#lines + 1] = string.format("   %s: %d of %d used", bag.name, bag.total - bag.free, bag.total) end
    end
    if (state.placed or 0) ~= count or used ~= count then
        lines[#lines + 1] = string.format("|cffff5555Showing %d of the %d items read (the game counts %d slots in use).|r",
            state.placed or 0, count, used)
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
    return lines
end

local function RefreshSettingsPage()
    local page = ns.settings.general
    page.hideCheck:SetChecked(SacksDB.hideBags ~= false)
    page.widgetCheck:SetChecked(WidgetGroup().shown and true or false)
    page.moneyCheck:SetChecked(ns.MoneyGroup().shown and true or false)
    page.clickColor.select(SacksDB.clickColor or "green")
    local lines = SpaceLines()
    page.bagInfo:SetText(table.concat(lines, "\n"))
    local y = page.bagInfoTop + #lines * LABEL_HEIGHT + 2 * PADDING
    page.bags:SetHeight(y)
    local town = ns.ShowingLayout() == "town"
    page.townToggle:SetText(town and NORMAL_SHOW or TOWN_SHOW)
    page.townShowing:SetText(town and "Town sacks are showing" or "Normal sacks are showing")
    page.townButtonCheck:SetChecked(ns.TownButtonPlace().shown and true or false)
    for _, check in ipairs(page.townChecks) do check:SetChecked(ns.TownAt(check.key)) end
    RefreshTownRows(page)
    page.town:ClearAllPoints()
    page.town:SetPoint("TOPLEFT", 0, -y)
    y = y + page.townHeight
    page.backup:ClearAllPoints()
    page.backup:SetPoint("TOPLEFT", 0, -y)
    if SacksDB.backup then page.undoButton:Enable() else page.undoButton:Disable() end
    y = y + page.backupHeight
    page.height = y
    page:SetHeight(y)
    ns.FitWindow(y)
end

-- shared with the files after this one
ns.BuildSettingsPage = BuildSettingsPage
ns.RefreshSettingsPage = RefreshSettingsPage
