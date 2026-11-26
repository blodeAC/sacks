-- sacks: Sacks.lua
local _, ns = ...
local AllGroups, BACKDROP_ALPHA, BeginSackDrag, BlankMode = ns.AllGroups, ns.BACKDROP_ALPHA, ns.BeginSackDrag, ns.BlankMode
local COLOR, Container, DockFrame, ExpandTitle = ns.COLOR, ns.Container, ns.DockFrame, ns.ExpandTitle
local FindGroup, FinishDrag, GridCell, GridDimensions = ns.FindGroup, ns.FinishDrag, ns.GridCell, ns.GridDimensions
local GridSize, LastBag, LayoutOf, MakeSlotButton = ns.GridSize, ns.LastBag, ns.LayoutOf, ns.MakeSlotButton
local MarkStale, Matches, PADDING, PlaceGroups = ns.MarkStale, ns.Matches, ns.PADDING, ns.PlaceGroups
local PlaceInGrid, PlaceOne, QuestMarker, ReadBags = ns.PlaceInGrid, ns.PlaceOne, ns.QuestMarker, ns.ReadBags
local RefreshFresh, Rgb, SlotSize, SortItems = ns.RefreshFresh, ns.Rgb, ns.SlotSize, ns.SortItems
local ReadingOrder = ns.ReadingOrder
local TITLE_HEIGHT, TintByQuality, UpdateCooldown, state = ns.TITLE_HEIGHT, ns.TintByQuality, ns.UpdateCooldown, ns.state

-- Dropping an item on a free-slots box puts it in the first free slot of a normal bag.
-- Whatever is on the cursor (an item, or one being bought from a vendor) goes into a free bag slot: a special bag that
-- takes it first, then a normal bag. Nothing is swapped: a sack's slots are views of bag slots, and the sacks sort it
-- anyway. With no room it goes back where it came from and the game's "Inventory is full" shows.
local function DropIntoFreeSlot()
    local kind, itemID
    if GetCursorInfo then kind, itemID = GetCursorInfo() end -- not "GetCursorInfo and GetCursorInfo()": that keeps only the first value
    if not (CursorHasItem and CursorHasItem()) and kind ~= "merchant" then return end
    local familyOf = GetItemFamily or (C_Item and C_Item.GetItemFamily)
    local family = (kind == "item" and itemID and familyOf and familyOf(itemID)) or 0
    local function FirstFree(bag)
        for slot = 1, Container.GetContainerNumSlots(bag) or 0 do
            if Container.GetContainerItemInfo(bag, slot) == nil then return slot end
        end
    end
    for _, special in ipairs({ true, false }) do
        for bag = 0, LastBag() do
            local free, bagType = Container.GetContainerNumFreeSlots(bag)
            bagType = bagType or 0
            local fits = special and bagType ~= 0 and bit and bit.band(family, bagType) ~= 0 or (not special and bagType == 0)
            if fits and (free or 0) > 0 then
                local slot = FirstFree(bag)
                if slot then
                    Container.PickupContainerItem(bag, slot)
                    return
                end
            end
        end
    end
    if ClearCursor then ClearCursor() end
    if UIErrorsFrame and ERR_INV_FULL then UIErrorsFrame:AddMessage(ERR_INV_FULL, 1, 0.1, 0.1) end
end

-- Hovering a free-slots box lists every bag, so the free slots in special bags are never hidden from you.
local function ShowFreeTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Free slots")
    for _, bag in ipairs(state.bags or {}) do
        GameTooltip:AddDoubleLine(bag.name .. (bag.special and " (special)" or ""),
            bag.free .. " / " .. bag.total, 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine("The number counts normal bags. A +number counts special bags, which only take some items.",
        COLOR.GREY[1], COLOR.GREY[2], COLOR.GREY[3], true)
    GameTooltip:Show()
end

-- How a sack that uses its items on left click is marked (its title and a thin border), chosen on the Settings page.
local CLICK_COLORS = {
    { label = "Green", value = "green", r = 0.3, g = 1, b = 0.3 },
    { label = "Blue", value = "blue", r = 0.4, g = 0.7, b = 1 },
    { label = "Purple", value = "purple", r = 0.8, g = 0.5, b = 1 },
    { label = "Red", value = "red", r = 1, g = 0.35, b = 0.35 },
    { label = "White", value = "white", r = 1, g = 1, b = 1 },
    { label = "No marking", value = "none", color = { 0.6, 0.6, 0.6 } },
}
-- each choice is written in its own colour in the menu and in the box
for _, choice in ipairs(CLICK_COLORS) do
    if choice.r then choice.color = { choice.r, choice.g, choice.b } end
end
local function ClickColor()
    local wanted = SacksDB.clickColor or "green"
    for _, color in ipairs(CLICK_COLORS) do
        if color.value == wanted then return color.r, color.g, color.b end
    end
    return 0.3, 1, 0.3
end
ns.CLICK_COLORS = CLICK_COLORS
ns.ClickColor = ClickColor

local function MakeGroupFrame(group)
    local frame = CreateFrame("Frame", nil, UIParent)
    -- Where the game's own bags are drawn, under the settings window (DIALOG): a big sack must not cover the window you
    -- set it up in. Set before the slots are made so they follow.
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints()
    frame.back:SetColorTexture(0, 0, 0, BACKDROP_ALPHA)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Says "this sack is out of date" during combat. Made here, ahead of time, because text can change in combat
    -- but a new frame cannot be anchored to a sack then.
    frame.stale = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.stale:SetTextColor(1, 0.5, 0)
    -- the border of a sack set to use items on left click
    frame.edges = {}
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        local thin = (PixelUtil and PixelUtil.GetNearestPixelSize and UIParent.GetEffectiveScale)
            and PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1) or 1
        if edge[3] then line:SetHeight(thin) else line:SetWidth(thin) end
        line:Hide()
        frame.edges[#frame.edges + 1] = line
    end
    -- The whole sack takes the mouse, so moving off it always says so: that is when a held-still layout catches up.
    frame.isSack = true
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function() ns.HoldStill() end)
    frame:SetScript("OnLeave", function() ns.LetGo() end)
    frame:SetScript("OnHide", function() ns.LetGo() end)
    frame.handle = CreateFrame("Frame", nil, frame)
    frame.handle:EnableMouse(true)
    frame.handle:RegisterForDrag("LeftButton")
    frame.handle:SetScript("OnDragStart", function()
        if DockFrame() then return end
        -- Without a title the whole sack is the handle, and it takes shift to avoid dragging one by accident.
        if group.title == "NONE" and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        if ns.LogSackDrag then ns.LogSackDrag("sack drag start", group) end
        BeginSackDrag(frame)
    end)
    frame.handle:SetScript("OnDragStop", function()
        FinishDrag(group, frame)
        if ns.LogSackDrag then ns.LogSackDrag("sack drag stop", group) end
    end)
    -- Right-click the title (or a sack with no title) opens the settings window on this sack.
    frame.handle:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" and ns.EditSack then ns.EditSack(group) end
    end)
    -- Hovering the title shows it whole (a long one ends in "..."), what the sack is docked to, and what changed in combat.
    frame.handle:SetScript("OnEnter", function(self)
        local stale = state.stale[group]
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(state.titles[group] or group.name)
        if ns.DockWords then
            for _, line in ipairs(ns.DockWords(group)) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        end
        if stale then
            GameTooltip:AddLine("Changed during combat. This sack is rebuilt when combat ends:", 1, 0.5, 0, true)
            for _, line in ipairs(stale) do GameTooltip:AddLine(line, 1, 1, 1) end
        end
        GameTooltip:AddLine("Right-click: this sack's settings", 0.5, 0.8, 1)
        GameTooltip:Show()
        if ns.ShowDockLines then ns.ShowDockLines(group) end -- its docks, as gold lines in the gaps
    end)
    frame.handle:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ns.HideDockLines then ns.HideDockLines() end
        ns.LetGo()
    end)
    frame.handle:HookScript("OnEnter", function() ns.HoldStill() end)
    frame.blank = CreateFrame("Frame", nil, frame)
    frame.blank:SetSize(SlotSize(), SlotSize())
    frame.blank.back = frame.blank:CreateTexture(nil, "BACKGROUND")
    frame.blank.back:SetAllPoints()
    frame.blank.back:SetColorTexture(1, 1, 1, 0.08)
    frame.blank.text = frame.blank:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.blank.text:SetPoint("CENTER")
    frame.blank.extra = frame.blank:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.blank.extra:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.blank:EnableMouse(true)
    frame.blank:SetScript("OnMouseUp", DropIntoFreeSlot)
    frame.blank:SetScript("OnReceiveDrag", DropIntoFreeSlot)
    frame.blank:SetScript("OnEnter", ShowFreeTooltip)
    frame.blank:SetScript("OnLeave", function() GameTooltip:Hide(); ns.LetGo() end)
    frame.blank:HookScript("OnEnter", function() ns.HoldStill() end)
    frame.buttons = {}
    return frame
end

-- The measurements of a sack: how many columns and rows its cells make, how big it is, and where the first cell is.
local function SackGeometry(group, itemCount)
    local layout = LayoutOf(group)
    local size = SlotSize()
    -- The blank slot (it counts the free bag slots) goes last, first, or nowhere, per sack.
    local blankMode = BlankMode(group)
    local shift = blankMode == "FIRST" and 1 or 0
    local cells = itemCount + (blankMode ~= "NONE" and 1 or 0)
    local columns, rows = GridDimensions(layout, cells)
    -- At a vendor or the bank every sack is laid out like a page. Afterwards it goes back to its own corner and flow.
    local reading
    if DockFrame() then
        reading = ReadingOrder(layout, columns, rows, cells)
        layout = { anchor = "TOPLEFT", flow = "ROWS", title = layout.title, wrap = columns }
        columns, rows = GridDimensions(layout, cells)
    end
    local topSpace = layout.title == "TOP" and TITLE_HEIGHT or PADDING
    local bottomSpace = layout.title == "BOTTOM" and TITLE_HEIGHT or PADDING
    local width, height = GridSize(columns, rows, size, topSpace, bottomSpace)

    -- The first cell is next to the corner the sack grows from; filled like a page, it is at the top left wherever the
    -- sack is pinned (the sack still grows away from its corner).
    local page = layout.flow == "PAGE"
    local fromRight = not page and (layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT")
    local fromBottom = not page and (layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT")
    return { width = width, height = height, size = size, layout = layout, topSpace = topSpace, bottomSpace = bottomSpace,
        fromRight = fromRight, fromBottom = fromBottom, count = itemCount, shift = shift, blankMode = blankMode, reading = reading }
end

-- The title along one edge (or none), the handle you drag by, and the orange mark that says what a combat left out.
local function PlaceTitle(group, frame, geom, items, free, special)
    local layout, width = geom.layout, geom.width
    frame.title:ClearAllPoints()
    frame.handle:ClearAllPoints()
    if layout.title == "NONE" then
        frame.title:Hide()
        frame.handle:SetAllPoints()
    else
        frame.title:Show()
        local titleText = ExpandTitle(group, items, free, special)
        state.titles[group] = titleText
        frame.title:SetWidth(math.max(12, width - PADDING * 2))
        if frame.title.SetWordWrap then frame.title:SetWordWrap(false) end
        if frame.title.SetJustifyH then frame.title:SetJustifyH("LEFT") end
        frame.title:SetText(titleText)
        local edge = layout.title == "TOP" and "TOP" or "BOTTOM"
        frame.title:SetPoint(edge .. "LEFT", PADDING, layout.title == "TOP" and -3 or 3)
        frame.handle:SetPoint(edge .. "LEFT")
        frame.handle:SetPoint(edge .. "RIGHT")
        frame.handle:SetHeight(TITLE_HEIGHT)
    end
    local staleEdge = layout.title == "BOTTOM" and "BOTTOM" or "TOP"
    frame.stale:ClearAllPoints()
    frame.stale:SetPoint(staleEdge .. "RIGHT", -PADDING, staleEdge == "TOP" and -3 or 3)
    frame.stale:SetText("")
    state.stale[group] = nil
end

-- Fills one slot with its item: points the game's slot button at the item's bag slot (it draws itself from there),
-- and adds where the item really is.
local function FillSlot(button, item, group, size)
    ns.SizeSlot(button, size)
    button:SetFrameLevel(button.sack:GetFrameLevel() + 2)
    button.group = group
    if item.placeholder then
        -- a pinned item you have none of: its cell stays, dark (see Placeholder); the cover keeps clicks off the slot
        button.bag, button.slot, button.itemID, button.quality = nil, nil, item.itemID, item.quality
        button.placeholder, button.gone = true, false
        ns.DrawPlaceholder(button, item)
        button.clickUse = group.useOnClick and true or false
        ns.SetUseLayer(button, button.clickUse)
        button.where = nil
        button.mark:Hide()
        return
    end
    button.placeholder = nil
    button.bag, button.slot, button.itemID, button.quality = item.bag, item.slot, item.itemID, item.quality
    button.gone = false
    button.dead:Hide()
    ns.DrawSlot(button)
    -- A sack can use its items on left click, like an action bar. Dragging still picks an item up.
    button.clickUse = group.useOnClick and true or false
    ns.SetUseLayer(button, button.clickUse)
    if item.inSpecial then
        button.where, button.whereColor = "In your " .. item.bagName .. " (special bag).", COLOR.GREEN
        button.mark:SetColorTexture(0.2, 1, 0.2, 1)
        button.mark:Show()
    elseif item.fitsBag then
        if (item.fitsFree or 0) > 0 then
            button.where = "In " .. item.bagName .. ", but it fits your " .. item.fitsBag .. ", which has "
                .. item.fitsFree .. " free slot" .. (item.fitsFree == 1 and "" or "s") .. ". Move it there."
            button.whereColor = COLOR.AMBER
            button.mark:SetColorTexture(1, 0.7, 0.1, 1)
        else
            button.where = "In " .. item.bagName .. ". It fits your " .. item.fitsBag .. ", but that is full."
            button.whereColor = COLOR.GREY
            button.mark:SetColorTexture(0.6, 0.6, 0.6, 1)
        end
        button.mark:Show()
    else
        button.where, button.whereColor = "In " .. item.bagName .. ".", COLOR.GREY
        button.mark:Hide()
    end
end

-- A tooltip belongs to the slot it was opened on. When that slot now holds another item (one was sold or the
-- list shifted) show the new item; when it is empty or gone, close the tooltip.
local function KeepHoveredTooltip(frame)
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    if owner then
        for _, button in ipairs(frame.buttons) do
            if owner == button then
                if button:IsShown() and button.bag then
                    button:GetScript("OnEnter")(button)
                else
                    GameTooltip:Hide()
                    if ResetCursor then ResetCursor() end
                end
            end
        end
    end
end

-- A sack that uses items on left click is drawn in the colour picked for that, on its title and its border.
local function MarkClickSack(group, frame)
    local markR, markG, markB = ClickColor()
    local marked = group.useOnClick and markR ~= nil
    for _, line in ipairs(frame.edges) do
        if marked then
            line:SetColorTexture(markR, markG, markB, 0.9)
            line:Show()
        else
            line:Hide()
        end
    end
    if marked then frame.title:SetTextColor(markR, markG, markB) else frame.title:SetTextColor(Rgb(COLOR.GOLD)) end
end

-- The empty slot that counts the free bag slots (and the special ones, in green).
local function FillBlankSlot(frame, geom, count, free, special)
    local size, blankMode = geom.size, geom.blankMode
    local hasBlank = blankMode ~= "NONE"
    frame.blank:SetSize(size, size)
    if hasBlank then
        PlaceInGrid(frame.blank, blankMode == "FIRST" and 1 or count + 1, geom)
        frame.blank:Show()
    else
        frame.blank:Hide()
    end
    frame.blank.text:SetText(free)
    if free > 0 then frame.blank.text:SetTextColor(Rgb(COLOR.GOLD)) else frame.blank.text:SetTextColor(Rgb(COLOR.RED)) end
    frame.blank.extra:SetText(special > 0 and ("+" .. special) or "")
    frame.blank.extra:SetTextColor(Rgb(COLOR.GREEN))
end

local function FillGroup(group, items, free, special)
    local frame = state.frames[group] or MakeGroupFrame(group)
    state.frames[group] = frame
    local geom = SackGeometry(group, #items)
    frame:SetSize(geom.width, geom.height)
    frame.geom = geom
    -- A button moved here or elsewhere in this same rebuild has this rebuild's mark (claimGen); the rest go back to
    -- the pool. A slot's button is the same button wherever its slot shows (see SlotButton in Slots.lua).
    local generation = state.generation
    for _, ghost in ipairs(rawget(frame, "ghosts") or {}) do
        if ghost.claimGen ~= generation then ns.ParkSlot(ghost) end -- a full rebuild has real slots for them
    end
    frame.ghosts = {}
    PlaceTitle(group, frame, geom, items, free, special)

    local old = frame.buttons
    frame.buttons = {}
    frame.placeholders = rawget(frame, "placeholders") or {}
    local placeholders = 0
    for index, item in ipairs(items) do
        local button
        if not item.placeholder then
            button = ns.SlotButton(item.bag, item.slot)
            -- in combat, a button still standing in a frozen sack stays there (see FrozenGroups)
            local frozen = state.frozenNow
            if button and frozen and button:IsShown() and button.sack ~= frame and frozen[button.group] then button = nil end
        end
        if button then
            ns.MoveSlot(button, frame)
        else
            -- a pinned item you have none of, or (in combat) a slot with no button yet: a plain picture of it
            placeholders = placeholders + 1
            button = frame.placeholders[placeholders] or MakeSlotButton(frame)
            frame.placeholders[placeholders] = button
            if not item.placeholder then
                item = { itemID = item.itemID, icon = item.icon, quality = item.quality, name = item.name, placeholder = true }
            end
        end
        button.claimGen = generation
        frame.buttons[index] = button
        FillSlot(button, item, group, geom.size)
        PlaceInGrid(button, index + geom.shift, geom)
        button:Show()
    end
    for _, button in ipairs(old or {}) do
        if button.claimGen ~= generation then ns.ParkSlot(button) end
    end
    for index = placeholders + 1, #frame.placeholders do
        local button = frame.placeholders[index]
        if button.claimGen ~= generation then ns.ParkSlot(button) end
    end
    KeepHoveredTooltip(frame)
    MarkClickSack(group, frame)
    FillBlankSlot(frame, geom, #items, free, special)
end

-- A box of its own that shows your gold with the game's coin icons, to put anywhere (or dock against a sack): the
-- game only shows gold at the bottom of its backpack. It follows the game's money event, not a timer.
local MONEY_START = { point = "CENTER", x = 0, y = -280 }
local function MoneyGroup()
    SacksDB.money = SacksDB.money or { name = "Gold", shown = false, point = MONEY_START.point, x = MONEY_START.x, y = MONEY_START.y }
    return SacksDB.money
end

local function MoneyText() return ns.CoinText((GetMoney and GetMoney()) or 0) end

local function MakeMoneyBox(group)
    local frame = CreateFrame("Frame", "SacksMoneyBox", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints()
    frame.back:SetColorTexture(0, 0, 0, BACKDROP_ALPHA)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("CENTER")
    frame:SetScript("OnDragStart", function()
        if not DockFrame() then BeginSackDrag(frame) end
    end)
    frame:SetScript("OnDragStop", function() FinishDrag(group, frame) end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Gold")
        if ns.DockWords then
            for _, line in ipairs(ns.DockWords(group)) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        end
        GameTooltip:AddLine("Drag to move it. Settings page: hide it or reset its position.", 0.5, 0.8, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

-- The coins and the box's size, which follows them. Placing it again only when asked (place): the sacks do that.
local function UpdateMoney(place)
    if not SacksDB then return end
    local group = MoneyGroup()
    local frame = state.frames[group]
    if not group.shown then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = MakeMoneyBox(group)
        state.frames[group] = frame
        place = true
    end
    frame.text:SetText(MoneyText())
    local width = frame.text:GetStringWidth()
    frame:SetSize(math.ceil(type(width) == "number" and width or 0) + PADDING * 2, ns.BUTTON_HEIGHT)
    if place and not DockFrame() then
        frame:ClearAllPoints()
        PlaceOne(group, frame)
        if not state.placing and not state.holding then ns.Settle() end -- what hangs from it may need settling again (not while the sacks hold still)
    end
    frame:Show()
end

-- An optional box of its own that shows the free slots, to put anywhere (or dock against a sack).
-- Where the free-slots box starts (and where its reset puts it): a little below the middle, clear of a new sack.
local WIDGET_START = { point = "CENTER", x = 0, y = -220 }
local function WidgetGroup()
    SacksDB.widget = SacksDB.widget or { name = "Free slots", shown = false, point = WIDGET_START.point, x = WIDGET_START.x, y = WIDGET_START.y }
    return SacksDB.widget
end

local function MakeWidget(group)
    local frame = CreateFrame("Frame", "SacksFreeWidget", UIParent)
    -- With the sacks, under the settings window.
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints()
    frame.back:SetColorTexture(0, 0, 0, BACKDROP_ALPHA)
    frame.slot = frame:CreateTexture(nil, "ARTWORK")
    frame.slot:SetColorTexture(1, 1, 1, 0.08)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER")
    frame.extra = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.extra:SetTextColor(Rgb(COLOR.GREEN))
    frame:SetScript("OnDragStart", function()
        if not DockFrame() then BeginSackDrag(frame) end
    end)
    frame:SetScript("OnDragStop", function() FinishDrag(group, frame) end)
    frame:SetScript("OnMouseUp", DropIntoFreeSlot)
    frame:SetScript("OnReceiveDrag", DropIntoFreeSlot)
    frame:SetScript("OnEnter", ShowFreeTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

local function UpdateWidget(free, special)
    local group = WidgetGroup()
    local frame = state.frames[group]
    if not group.shown then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = MakeWidget(group)
        state.frames[group] = frame
    end
    local size = SlotSize()
    frame:SetSize(size + PADDING * 2, size + PADDING * 2)
    frame.slot:ClearAllPoints()
    frame.slot:SetSize(size, size)
    frame.slot:SetPoint("CENTER")
    frame.extra:ClearAllPoints()
    frame.extra:SetPoint("BOTTOMRIGHT", frame.slot, "BOTTOMRIGHT", -2, 2)
    frame.text:SetText(free)
    if free > 0 then frame.text:SetTextColor(Rgb(COLOR.GOLD)) else frame.text:SetTextColor(Rgb(COLOR.RED)) end
    frame.extra:SetText(special > 0 and ("+" .. special) or "")
    if not DockFrame() and not state.holding then
        frame:ClearAllPoints()
        PlaceOne(group, frame)
        if not state.placing and not state.holding then ns.Settle() end -- what hangs from it may need settling again (not while the sacks hold still)
    end
    frame:Show()
end

-- In combat the slots cannot be moved or re-assigned, but their text can change. This re-reads the stack in each
-- slot that is on screen, so a count goes down as you use the item instead of at the end of the fight. A slot that
-- now holds a different item or nothing is dimmed and left where it is until the full refresh after combat.
local GONE_SHADE = ns.GONE_SHADE
local function RefreshCounts()
    for _, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button.bag and button:IsShown() then
                local ok, info = pcall(C_Container.GetContainerItemInfo, button.bag, button.slot)
                if ok and type(info) == "table" and info.itemID == button.itemID then
                    button.gone = false
                    button.dead:Hide()
                    ns.DrawSlot(button)
                    ns.SetUseLayer(button, button.clickUse) -- out of combat only (it is secure)
                else
                    -- The item left: the cover catches clicks until the slot is filled again (see MakeSlotButton). A slot
                    -- whose left click uses its item goes on using it from your other stacks, like an action bar: it shows
                    -- how many you have left, and goes dark at none.
                    ns.SetUseLayer(button, false) -- out of combat; in combat the layer stays, pointed at the item
                    button.gone = true
                    button.dead:Show()
                    local using = rawget(button, "use") and button.use:IsShown()
                    local left = using and C_Item.GetItemCount(button.itemID) or 0
                    if left > 0 then
                        SetItemButtonCount(button, left)
                        SetItemButtonDesaturated(button, false)
                        SetItemButtonTextureVertexColor(button, 1, 1, 1)
                    else
                        SetItemButtonCount(button, nil)
                        SetItemButtonDesaturated(button, true)
                        SetItemButtonTextureVertexColor(button, GONE_SHADE, GONE_SHADE, GONE_SHADE)
                    end
                end
            end
        end
    end
end
ns.RefreshCounts = RefreshCounts

-- Runs a step that must not stop the rest of a refresh. A failure is written to /sacks errors, never swallowed.
local function Guarded(label, step, ...)
    local ok, err = pcall(step, ...)
    if not ok and ns.RecordError then ns.RecordError(label .. ": " .. tostring(err)) end
    return ok
end
ns.Guarded = Guarded

-- With the Town sacks showing, where the Normal sacks would put each item: which Normal sack (its place in their list)
-- and where in it (that sack's own order). Town sacks order their items by this (a setting), so things sit in the order
-- you know from Normal. Nil when Normal is showing, or the setting says each Town sack keeps its own order.
local function NormalRanks(items)
    local away = SacksDB.otherLayout
    if SacksDB.layout ~= "town" or SacksDB.townSort == "own" or not (away and away.groups) then return nil end
    local normal = {}
    for _, group in ipairs(away.groups) do normal[#normal + 1] = group end
    if away.fallback then normal[#normal + 1] = away.fallback end
    local buckets = {}
    for index in ipairs(normal) do buckets[index] = {} end
    for _, item in ipairs(items) do
        for index, group in ipairs(normal) do
            if (group.fixed or #(group.rule or {}) > 0) and Matches(group.rule or {}, item) then
                table.insert(buckets[index], item)
                break
            end
        end
    end
    local ranks = {}
    for index, group in ipairs(normal) do
        SortItems(group, buckets[index])
        for position, item in ipairs(buckets[index]) do ranks[item] = index * 100000 + position end
    end
    return ranks
end

-- A pinned item you have none of keeps its cell, like an action bar: drawn dark, at its pin's place.
local function Placeholder(id, index)
    local seen = SacksDB.seen and SacksDB.seen[id] or {}
    local item = { itemID = id, placeholder = true, bag = 99, slot = index, count = 0 }
    for key, value in pairs(seen) do item[key] = value end
    item.name = item.name or ("item " .. id)
    return item
end

-- Which sack each item goes to (the first whose lines take it; the last sack takes the rest), each sack's items in its
-- order, and how many each has.
local function Assign(items)
    local groups = AllGroups()
    local sorted = {}
    local carried = {}
    for _, group in ipairs(groups) do sorted[group] = {} end
    for _, item in ipairs(items) do
        if item.itemID then carried[item.itemID] = true end
        for _, group in ipairs(groups) do
            if (group.fixed or #group.rule > 0) and Matches(group.rule, item) then
                table.insert(sorted[group], item)
                break
            end
        end
    end
    for _, group in ipairs(groups) do
        for index, id in ipairs(group.pins or {}) do
            if not carried[id] then table.insert(sorted[group], Placeholder(id, index)) end
        end
    end
    state.normalRank = nil -- the Normal sacks sort by their own steps while their order is worked out
    state.normalRank = NormalRanks(items)
    for _, group in ipairs(groups) do SortItems(group, sorted[group]) end
    return groups, sorted
end

-- In combat with frozen sacks on screen (a sack whose items left click uses, and what is docked with it: see
-- FrozenGroups): the other sacks are rebuilt as usual, where they are; a frozen one keeps its slots (a slot whose item
-- left is covered, see RefreshCounts) and shows what it gains in its next cells (ShowGhosts). Nothing is moved, so the
-- frozen ones are never touched; the full rebuild runs when combat ends.
local function CombatRebuild(frozen)
    local items, free, special = ReadBags()
    state.items = items
    local groups, sorted = Assign(items)
    state.stale = {}
    state.frozenNow = frozen -- FillGroup leaves the buttons in frozen sacks where they are
    for _, group in ipairs(groups) do
        local frame = state.frames[group]
        if frozen[group] and frame then
            local shown = {}
            local removed = {}
            for _, button in ipairs(rawget(frame, "buttons") or {}) do
                if button.bag and button:IsShown() then
                    if button.gone then
                        local seen = SacksDB.seen and SacksDB.seen[button.itemID]
                        removed[#removed + 1] = "- " .. tostring(seen and seen.name or button.itemID) .. " (used up or moved)"
                    else
                        shown[button.bag .. ":" .. button.slot .. ":" .. tostring(button.itemID)] = true
                    end
                end
            end
            local pending, lines = {}, {}
            for _, item in ipairs(sorted[group]) do
                if not item.placeholder and not shown[item.bag .. ":" .. item.slot .. ":" .. tostring(item.itemID)] then
                    pending[#pending + 1] = item
                    lines[#lines + 1] = "+ " .. tostring(item.name) .. (item.count and item.count > 1 and " x" .. item.count or "")
                end
            end
            ns.ShowGhosts(group, frame, pending)
            for _, line in ipairs(removed) do lines[#lines + 1] = line end
            if #lines > 0 then state.stale[group] = lines end
            if rawget(frame, "stale") then frame.stale:SetText(#removed > 0 and ("-" .. #removed) or "") end
        else
            state.counts[group] = #sorted[group]
            FillGroup(group, sorted[group], free, special)
        end
    end
    state.frozenNow = nil
    state.placing = true -- nothing moves: the frozen sacks and what hangs from them stay where they are
    UpdateWidget(free, special)
    state.placing = false
    RefreshFresh()
    ns.UpdatePins()
end

local function Refresh()
    if not SacksDB then return end
    state.generation = (state.generation or 0) + 1 -- what was worked out from the bags before this is out of date
    -- In combat the sacks are rebuilt like any other time, unless some are frozen (see FrozenGroups): then everything
    -- else is, and the rest waits for the end of combat.
    if InCombatLockdown() then
        local frozen = ns.FrozenGroups()
        if next(frozen) then
            state.pending = true
            Guarded("combat counts", RefreshCounts) -- what each frozen slot shows is brought up to date now
            Guarded("combat rebuild", CombatRebuild, frozen)
            if ns.RefreshSettings then Guarded("settings", ns.RefreshSettings) end
            return
        end
    end
    state.pending = false
    ns.MakeAllSlotButtons()
    local items, free, special = ReadBags()
    state.items = items
    SacksDB.seen = SacksDB.seen or {}
    for _, item in ipairs(items) do
        if item.itemID then
            SacksDB.seen[item.itemID] = { name = item.name, icon = item.icon, classID = item.classID,
                subClassID = item.subClassID, quality = item.quality, sellPrice = item.sellPrice,
                itemLevel = item.itemLevel, minLevel = item.minLevel, stackMax = item.stackMax, equip = item.equip,
                bindType = item.bindType, reagent = item.reagent, bound = item.bound, family = item.family, tip = item.tip }
        end
    end
    -- The last sack takes whatever no other sack wants, so every item in your bags is always on screen somewhere.
    local groups, sorted = Assign(items)
    state.placed = 0
    for _, group in ipairs(groups) do
        state.counts[group] = #sorted[group]
        for _, item in ipairs(sorted[group]) do
            if not item.placeholder then state.placed = state.placed + 1 end
        end
    end
    -- Town beside a window: every sack's width and spot, from what each holds, before the sacks are drawn at that width
    ns.PackTown(groups)
    for _, group in ipairs(groups) do FillGroup(group, sorted[group], free, special) end
    state.placing = true
    PlaceGroups()
    UpdateWidget(free, special)
    UpdateMoney(true)
    state.placing = false
    ns.Settle() -- after the boxes too: a chain of sacks can hang from the gold box
    RefreshFresh()
    ns.UpdatePins()
    if ns.RefreshSettings then Guarded("settings", ns.RefreshSettings) end
end
state.refresh = Refresh

-- While the mouse is on a sack, the sacks hold still: selling, banking or using items leaves their slots where they are
-- (dimmed, and inert) instead of closing the gap under your cursor, and new items wait. When the mouse leaves every
-- sack, everything catches up at once. Only bag changes are held; anything you change in the settings applies at once.
local function OverSacks()
    for _, frame in pairs(state.frames or {}) do
        if rawget(frame, "isSack") and frame:IsShown() and frame:IsMouseOver() then return true end
    end
    return false
end

local function HoldStill()
    state.holding = true
end

local function LetGo()
    if not state.holding or OverSacks() then return end
    state.holding = false
    if state.heldBack then
        state.heldBack = false
        Refresh()
    end
end

-- What the bags changing does: the whole refresh, or while held still, only what each slot shows.
local function BagsChanged()
    if not state.holding or not SacksDB then return Refresh() end
    state.heldBack = true
    state.generation = (state.generation or 0) + 1
    Guarded("held counts", RefreshCounts)
    Guarded("held extras", function()
        local items, free, special = ReadBags()
        state.items = items
        MarkStale(items) -- what arrived is drawn in New, without moving anything
        UpdateWidget(free, special)
        RefreshFresh()
        ns.UpdateTargetDim() -- what a waiting crate can take depends on what is left
    end)
    if ns.RefreshSettings then Guarded("settings", ns.RefreshSettings) end
end

local function HideRemoved(group)
    if state.frames[group] then state.frames[group]:Hide() end
end

-- shared with the files after this one
-- The one place a sack is made. A new sack starts at the middle of the screen. It returns the sack, or nil and why not.
-- Callers decide what to say and when to refresh.
local function CreateSack(name, rule)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then return nil, "type a name for the sack first" end
    if FindGroup(name) then return nil, "there is already a sack called " .. name end
    -- a new sack grows from the default corner, if one is set on the Defaults page
    local group = { name = name, rule = rule or {}, point = "CENTER", x = 0, y = 0, anchor = ns.Default("anchor", nil) }
    -- First in priority, but after New, which always stays first.
    local first = SacksDB.groups[1]
    table.insert(SacksDB.groups, (first and first.builtin) and 2 or 1, group)
    return group
end


-- Puts a sack (or the free-slots box) back where a new one starts: undocked, in the middle of the screen. The box starts
-- a little lower so it does not sit on top of a new sack.
local function ResetPosition(group)
    local start = (group == SacksDB.widget) and WIDGET_START or (group == SacksDB.money) and MONEY_START or { point = "CENTER", x = 0, y = 0 }
    group.point, group.relPoint, group.relativeTo, group.dock = start.point, nil, nil, nil
    group.x, group.y = start.x, start.y
    Refresh()
end
ns.ResetPosition = ResetPosition
ns.CreateSack = CreateSack
ns.HideRemoved = HideRemoved
ns.Refresh = Refresh
ns.HoldStill = HoldStill
ns.DropIntoFreeSlot = DropIntoFreeSlot
ns.LetGo = LetGo
ns.BagsChanged = BagsChanged
ns.WidgetGroup = WidgetGroup
ns.MoneyGroup = MoneyGroup
ns.UpdateMoney = UpdateMoney
