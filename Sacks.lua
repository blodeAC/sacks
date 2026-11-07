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
local function DropIntoFreeSlot()
    if not (CursorHasItem and CursorHasItem()) then return end
    for bag = 0, LastBag() do
        local free, bagType = Container.GetContainerNumFreeSlots(bag)
        if (bagType or 0) == 0 and (free or 0) > 0 then
            for slot = 1, Container.GetContainerNumSlots(bag) do
                if Container.GetContainerItemInfo(bag, slot) == nil then
                    Container.PickupContainerItem(bag, slot)
                    return
                end
            end
        end
    end
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

-- How a sack that uses its items on left click is marked (its title and a thin border), chosen on the Sacks tab.
local CLICK_COLORS = {
    { label = "Green", value = "green", r = 0.3, g = 1, b = 0.3 },
    { label = "Blue", value = "blue", r = 0.4, g = 0.7, b = 1 },
    { label = "Purple", value = "purple", r = 0.8, g = 0.5, b = 1 },
    { label = "Red", value = "red", r = 1, g = 0.35, b = 0.35 },
    { label = "White", value = "white", r = 1, g = 1, b = 1 },
    { label = "No marking", value = "none" },
}
local function ClickColor()
    local wanted = SacksDB.clickColor or "green"
    for _, color in ipairs(CLICK_COLORS) do
        if color.value == wanted then return color.r, color.g, color.b end
    end
    return 0.3, 1, 0.3
end
ns.CLICK_COLORS = CLICK_COLORS

local function MakeGroupFrame(group)
    local frame = CreateFrame("Frame", nil, UIParent)
    -- Above the settings window (which is DIALOG), so a sack that starts in the middle of the screen is not hidden behind it.
    -- Set before the slots are made so they follow.
    frame:SetFrameStrata("DIALOG")
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
    frame.handle = CreateFrame("Frame", nil, frame)
    frame.handle:EnableMouse(true)
    frame.handle:RegisterForDrag("LeftButton")
    frame.handle:SetScript("OnDragStart", function()
        if DockFrame() then return end
        -- Without a title the whole sack is the handle, and it takes shift to avoid dragging one by accident.
        if group.title == "NONE" and not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        BeginSackDrag(frame)
    end)
    frame.handle:SetScript("OnDragStop", function() FinishDrag(group, frame) end)
    -- A title too long for the sack ends in "..."; hovering it shows the whole thing.
    frame.handle:SetScript("OnEnter", function(self)
        local full = state.titles[group]
        local stale = state.stale[group]
        local cut = full and frame.title.IsTruncated and frame.title:IsTruncated()
        if cut or stale then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(cut and full or (state.titles[group] or ""))
            if stale then
                GameTooltip:AddLine("Changed during combat; this sack is rebuilt when combat ends:", 1, 0.5, 0, true)
                for _, line in ipairs(stale) do GameTooltip:AddLine(line, 1, 1, 1) end
            end
            GameTooltip:Show()
        end
    end)
    frame.handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    frame.blank:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

    -- The first cell is next to the corner the sack grows from.
    local fromRight = layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT"
    local fromBottom = layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT"
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

-- Fills one slot with its item: the art, the count, the quest marker, and where the item really is.
local function FillSlot(button, item, group, size)
    button:SetSize(size, size)
    button.bag, button.slot, button.itemID, button.quality = item.bag, item.slot, item.itemID, item.quality
    button:SetAttribute("item", item.bag .. " " .. item.slot)
    -- A sack can use its items on left click, like an action bar. Dragging still picks an item up.
    button.clickUse = group.useOnClick and true or false
    if not (InCombatLockdown and InCombatLockdown()) then
        button:SetAttribute("type1", button.clickUse and "item" or nil)
    end
    button.icon:SetTexture(item.icon)
    QuestMarker(button.quest, item)
    button.icon:SetDesaturated(false)
    button.gone = false
    button.dead:Hide()
    ns.ApplyTargetDim(button)
    TintByQuality(button.back, item.quality)
    button.count:SetText((item.count or 1) > 1 and item.count or "")
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
    for _, ghost in ipairs(rawget(frame, "ghosts") or {}) do ghost:Hide() end -- a full rebuild has real slots for them
    PlaceTitle(group, frame, geom, items, free, special)

    for index, item in ipairs(items) do
        local button = frame.buttons[index] or MakeSlotButton(frame)
        frame.buttons[index] = button
        FillSlot(button, item, group, geom.size)
        PlaceInGrid(button, index + geom.shift, geom)
        button:Show()
        UpdateCooldown(button)
    end
    for index = #items + 1, #frame.buttons do
        frame.buttons[index].bag = nil
        frame.buttons[index].dead:Hide()
        frame.buttons[index]:Hide()
    end
    KeepHoveredTooltip(frame)
    MarkClickSack(group, frame)
    FillBlankSlot(frame, geom, #items, free, special)
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
    -- Above the settings window, so the box is not hidden behind it while you place it.
    frame:SetFrameStrata("DIALOG")
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
    if not DockFrame() then
        frame:ClearAllPoints()
        PlaceOne(group, frame)
    end
    frame:Show()
end

-- In combat the slots cannot be moved or re-assigned, but their text can change. This re-reads the stack in each
-- slot that is on screen, so a count goes down as you use the item instead of at the end of the fight. A slot that
-- now holds a different item or nothing is dimmed and left where it is until the full refresh after combat.
local function RefreshCounts()
    for _, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button.bag and button:IsShown() then
                local ok, info = pcall(C_Container.GetContainerItemInfo, button.bag, button.slot)
                if ok and type(info) == "table" and info.itemID == button.itemID then
                    local stack = info.stackCount or 1
                    button.count:SetText(stack > 1 and stack or "")
                    button.icon:SetDesaturated(false)
                    button.gone = false
                    button.dead:Hide()
                else
                    button.gone = true
                    button.dead:Show()
                    button.count:SetText("")
                    button.icon:SetDesaturated(true)
                end
                UpdateCooldown(button)
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

local function Refresh()
    if not SacksDB then return end
    if InCombatLockdown() then
        state.pending = true -- secure buttons can't be changed in combat; redo it when combat ends
        Guarded("combat counts", RefreshCounts) -- but what each slot shows can be brought up to date now
        Guarded("combat items", function()
            local items = ReadBags()
            MarkStale(items) -- what it cannot show yet is drawn in Combat loot
            RefreshFresh()
        end)
        if ns.RefreshSettings then Guarded("settings", ns.RefreshSettings) end
        return
    end
    state.pending = false
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
    local groups = AllGroups()
    local sorted = {}
    for _, group in ipairs(groups) do sorted[group] = {} end
    for _, item in ipairs(items) do
        for _, group in ipairs(groups) do
            if (group.fixed or #group.rule > 0) and Matches(group.rule, item) then
                table.insert(sorted[group], item)
                break
            end
        end
    end
    state.placed = 0
    for _, group in ipairs(groups) do
        SortItems(group, sorted[group])
        if group.reverse then
            local list, count = sorted[group], #sorted[group]
            for index = 1, math.floor(count / 2) do list[index], list[count - index + 1] = list[count - index + 1], list[index] end
        end
        state.counts[group] = #sorted[group]
        state.placed = state.placed + #sorted[group]
        FillGroup(group, sorted[group], free, special)
    end
    PlaceGroups()
    UpdateWidget(free, special)
    RefreshFresh()
    if ns.RefreshSettings then Guarded("settings", ns.RefreshSettings) end
end
state.refresh = Refresh

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
    local group = { name = name, rule = rule or {}, point = "CENTER", x = 0, y = 0 }
    table.insert(SacksDB.groups, 1, group)
    return group
end


-- Puts a sack (or the free-slots box) back where a new one starts: undocked, in the middle of the screen. The box starts
-- a little lower so it does not sit on top of a new sack.
local function ResetPosition(group)
    local start = (group == SacksDB.widget) and WIDGET_START or { point = "CENTER", x = 0, y = 0 }
    group.point, group.relPoint, group.relativeTo, group.dock = start.point, nil, nil, nil
    group.x, group.y = start.x, start.y
    Refresh()
end
ns.ResetPosition = ResetPosition
ns.CreateSack = CreateSack
ns.HideRemoved = HideRemoved
ns.Refresh = Refresh
ns.WidgetGroup = WidgetGroup
