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
        ns.Confirm("Reset to the starting sacks?", "Every sack you made, and its layout, pins and order, is thrown away. Undo last reset or import brings them back.",
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
