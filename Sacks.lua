-- sacks: Sacks.lua
local _, ns = ...
local STATS, Stat = ns.STATS, ns.Stat
local AllGroups, Container, DEFAULT_ANCHOR, DEFAULT_COLUMNS, DEFAULT_FLOW, DEFAULT_SORT = ns.AllGroups, ns.Container, ns.DEFAULT_ANCHOR, ns.DEFAULT_COLUMNS, ns.DEFAULT_FLOW, ns.DEFAULT_SORT
local IsBlankLine = ns.IsBlankLine
local DEFAULT_TITLE, FindGroup, LastBag, Matches, PADDING, ReadBags = ns.DEFAULT_TITLE, ns.FindGroup, ns.LastBag, ns.Matches, ns.PADDING, ns.ReadBags
local SLOT_GAP, SlotSize, TITLE_HEIGHT, state = ns.SLOT_GAP, ns.SlotSize, ns.TITLE_HEIGHT, ns.state

---------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------

-- The window the sacks line up beside while it is open: the vendor's, or the bank's.
local function DockFrame()
    if state.vendor and MerchantFrame then return MerchantFrame end
    if state.bank and BankFrame then return BankFrame end
end

-- Some windows have tabs or buttons that stick out past their right edge (the bank's chest button). The sacks go
-- beyond whatever sticks out the furthest, so they never cover it. Looked up each time the sacks are placed.
local function Overhang(window)
    if not (window.GetRight and window.GetChildren) then return 0 end
    local right = window:GetRight()
    local scale = window.GetEffectiveScale and window:GetEffectiveScale()
    if type(right) ~= "number" or type(scale) ~= "number" or scale == 0 then return 0 end
    local widest = 0
    local function scan(parent, depth)
        for _, child in ipairs({ parent:GetChildren() }) do
            if type(child) == "table" and child.IsShown and child:IsShown() and child.GetRight then
                local edge = child:GetRight()
                local childScale = child.GetEffectiveScale and child:GetEffectiveScale()
                if type(edge) == "number" and type(childScale) == "number" then
                    local over = edge * childScale / scale - right
                    if over > widest then widest = over end
                end
                if depth < 3 and child.GetChildren then scan(child, depth + 1) end
            end
        end
    end
    scan(window, 1)
    -- nothing that is a tab or button sticks out further than the window is wide
    local width = window.GetWidth and window:GetWidth()
    return type(width) == "number" and width > 0 and math.min(widest, width) or widest
end

-- Shows the item's cooldown (potions, hearthstone, trinkets) on its slot, as the game's own bags do.
local function UpdateCooldown(button)
    local cooldown = button.cooldown
    if not cooldown then return end
    local get = (C_Container and C_Container.GetContainerItemCooldown) or GetContainerItemCooldown
    local start, duration, enable = 0, 0, 0
    if button.bag and get then start, duration, enable = get(button.bag, button.slot) end
    if CooldownFrame_Set then
        CooldownFrame_Set(cooldown, start or 0, duration or 0, enable)
    elseif (duration or 0) > 0 then
        cooldown:SetCooldown(start, duration)
    else
        cooldown:SetCooldown(0, 0)
    end
end

local function UpdateCooldowns()
    for _, frame in pairs(state.frames) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button.bag and button:IsShown() then UpdateCooldown(button) end
        end
    end
end
ns.UpdateCooldowns = UpdateCooldowns

local function MakeSlotButton(parent)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(SlotSize(), SlotSize())
    -- Right click uses the item (and sells it at a vendor). Left click and dragging pick it up, like the game's bags,
    -- unless the sack is set to use items on left click (then only dragging picks up).
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type2", "item")
    -- The secure action normally fires when the mouse goes DOWN, which would use an item the moment you start to drag
    -- it. Fire on release instead, so holding and moving picks the item up and a plain click uses it.
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(self, mouse, down)
        local atVendor = MerchantFrame and MerchantFrame:IsShown()
        if state.debugClicks then
            ns.Say(string.format("click %s %s: clickUse=%s type1=%s type2=%s onKeyDown=%s item=%s bag=%s slot=%s vendor=%s combat=%s", tostring(mouse),
                down and "down" or "up", tostring(self.clickUse), tostring(self:GetAttribute("type1")), tostring(self:GetAttribute("type2")), tostring(self:GetAttribute("useOnKeyDown")),
                tostring(self:GetAttribute("item")), tostring(self.bag), tostring(self.slot), tostring(atVendor and true or false),
                tostring(InCombatLockdown and InCombatLockdown() or false)))
        end
        if mouse == "LeftButton" and self.clickUse and atVendor and not (InCombatLockdown and InCombatLockdown()) then
            -- A sack set to use items on left click behaves like the game's bags at a vendor: no use, only pick up.
            self:SetAttribute("type1", nil)
            self.leftOff = true
        end
        if mouse == "LeftButton" and not down and self.bag and (not self.clickUse or self.leftOff) then
            Container.PickupContainerItem(self.bag, self.slot)
        end
        -- The secure "use item" action equips bags and gear at a vendor instead of selling them. At a vendor the game's
        -- own bags call UseContainerItem, which sells, so do that: the secure action is switched off for this click
        -- and the sale is made once, when the button comes back up.
        if mouse == "RightButton" and self.bag and MerchantFrame and MerchantFrame:IsShown()
            and not (InCombatLockdown and InCombatLockdown()) then
            self:SetAttribute("type2", nil)
            self.selling = true
            if not down then
                local use = (C_Container and C_Container.UseContainerItem) or UseContainerItem
                if use then use(self.bag, self.slot) end
            end
        end
    end)
    button:SetScript("PostClick", function(self)
        if self.leftOff then
            self.leftOff = nil
            self:SetAttribute("type1", "item")
        end
        if self.selling then
            self.selling = nil
            self:SetAttribute("type2", "item")
        end
    end)
    button:SetScript("OnDragStart", function(self)
        if self.bag and not (CursorHasItem and CursorHasItem()) then Container.PickupContainerItem(self.bag, self.slot) end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        if self.bag then Container.PickupContainerItem(self.bag, self.slot) end
    end)
    button.back = button:CreateTexture(nil, "BACKGROUND")
    button.back:SetAllPoints()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    -- The cooldown sweep (and, with a cooldown-text addon, its timer) draws over the icon; the stack count sits on a
    -- frame above it so the sweep does not dim the number.
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetPoint("TOPLEFT", 2, -2)
    button.cooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(false) end
    button.over = CreateFrame("Frame", nil, button)
    button.over:SetAllPoints()
    button.over:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    button.count = button.over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
    -- A small square in the top corner: green when the item is in a special bag, amber when it fits a special bag
    -- that has room but sits in a normal bag, grey when it fits one that is full.
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetSize(math.max(2, math.floor(ns.SlotSize() / 5)), math.max(2, math.floor(ns.SlotSize() / 5)))
    button.mark:SetPoint("TOPRIGHT", -2, -2)
    button.mark:Hide()
    button:SetScript("OnEnter", function(self)
        if self.bag then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetBagItem(self.bag, self.slot)
            if self.where then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.where, self.whereColor[1], self.whereColor[2], self.whereColor[3], true)
                GameTooltip:Show()
            end
            -- At a vendor the game shows a coin cursor over what you can sell; do the same.
            local showSell = (C_Container and C_Container.ShowContainerSellCursor) or ShowContainerSellCursor
            if showSell and MerchantFrame and MerchantFrame:IsShown() then showSell(self.bag, self.slot) end
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    end)
    return button
end

-- Where each of the nine anchor points sits on a frame, as a fraction of its width (x) and height (y, from the bottom).
local POINT_FRACTION = {
    TOPLEFT = { x = 0, y = 1 }, TOP = { x = 0.5, y = 1 }, TOPRIGHT = { x = 1, y = 1 },
    LEFT = { x = 0, y = 0.5 }, CENTER = { x = 0.5, y = 0.5 }, RIGHT = { x = 1, y = 0.5 },
    BOTTOMLEFT = { x = 0, y = 0 }, BOTTOM = { x = 0.5, y = 0 }, BOTTOMRIGHT = { x = 1, y = 0 },
}

-- Moves a saved position from the point it was saved against to the corner the sack grows from, so the corner
-- stays put when the sack gets bigger or smaller.
local function MoveToCorner(group, frame)
    local corner = group.anchor or DEFAULT_ANCHOR
    local from, to = POINT_FRACTION[group.point or "CENTER"], POINT_FRACTION[corner]
    group.x = (group.x or 0) + (to.x - from.x) * frame:GetWidth()
    group.y = (group.y or 0) + (to.y - from.y) * frame:GetHeight()
    group.point = corner
end

local function SavePosition(group, frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    group.point, group.relPoint, group.x, group.y, group.relativeTo = point, relPoint, x, y, nil
    MoveToCorner(group, frame)
end

-- How a sack is laid out: its own settings, also while a vendor window is open.
local function LayoutOf(group)
    return { anchor = group.anchor or DEFAULT_ANCHOR, flow = group.flow or DEFAULT_FLOW,
        title = group.title or DEFAULT_TITLE, wrap = group.cols or SacksDB.columns or DEFAULT_COLUMNS }
end

local BeginSackDrag, EndSackDrag
-- Dragging a sack snaps its edges to the screen edges and to other sacks (hold Alt to drag freely), so sacks
-- can be tucked against each other and moved aside without gaps or overlap.
local SNAP_DISTANCE = 14
local SNAP_GAP = 2

local function SnapAxis(low, size, targets)
    local best, bestDistance = 0, SNAP_DISTANCE + 1
    for _, target in ipairs(targets) do
        for _, shift in ipairs({ target.low - low, target.high - (low + size),
                                 target.high + SNAP_GAP - low, target.low - SNAP_GAP - (low + size) }) do
            if math.abs(shift) < bestDistance then best, bestDistance = shift, math.abs(shift) end
        end
    end
    if bestDistance <= SNAP_DISTANCE then return best end
    return 0
end

local function SnapPosition(frame, left, bottom)
    local width, height = frame:GetWidth(), frame:GetHeight()
    local xs, ys = { { low = 0, high = UIParent:GetWidth() } }, { { low = 0, high = UIParent:GetHeight() } }
    for _, other in pairs(state.frames) do
        if other ~= frame and other:IsShown() then
            local ol, ob, ow, oh = other:GetLeft(), other:GetBottom(), other:GetWidth(), other:GetHeight()
            if type(ol) == "number" and type(ob) == "number" and type(ow) == "number" and type(oh) == "number" then
                -- Only snap along an axis to sacks that are actually next to us on the other axis.
                local nearY = bottom < ob + oh + SNAP_DISTANCE and bottom + height > ob - SNAP_DISTANCE
                local nearX = left < ol + ow + SNAP_DISTANCE and left + width > ol - SNAP_DISTANCE
                if nearY then xs[#xs + 1] = { low = ol, high = ol + ow } end
                if nearX then ys[#ys + 1] = { low = ob, high = ob + oh } end
            end
        end
    end
    return left + SnapAxis(left, width, xs), bottom + SnapAxis(bottom, height, ys)
end

-- A sack dropped right against another one is docked to it: it stays against that sack when either changes size.
-- The saved dock says which sack, which side, and how far along that side, measured from the corner the sack grows from.

local function DockOf(group, frame)
    local left, bottom, width, height = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not (type(left) == "number" and type(bottom) == "number") then return nil end
    local anchor = group.anchor or DEFAULT_ANCHOR
    local fromRight = anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT"
    local fromBottom = anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT"
    local function near(a, b) return math.abs(a - b) <= 1.5 end
    for other, otherFrame in pairs(state.frames) do
        if other ~= group and otherFrame:IsShown() then
            local ol, ob, ow, oh = otherFrame:GetLeft(), otherFrame:GetBottom(), otherFrame:GetWidth(), otherFrame:GetHeight()
            if type(ol) == "number" and type(ob) == "number" and type(ow) == "number" and type(oh) == "number" then
                local overlapY = bottom < ob + oh and bottom + height > ob
                local overlapX = left < ol + ow and left + width > ol
                local alongY = fromBottom and (bottom - ob) or ((bottom + height) - (ob + oh))
                local alongX = fromRight and ((left + width) - (ol + ow)) or (left - ol)
                -- If the two edges along the shared side line up, the dock keeps THOSE edges lined up, whichever way
                -- the sack grows. Otherwise it keeps the corner the sack grows from.
                local function alongVertical()
                    if near(bottom, ob) then return { edge = "BOTTOM", offset = 0 } end
                    if near(bottom + height, ob + oh) then return { edge = "TOP", offset = 0 } end
                    return { offset = alongY }
                end
                local function alongHorizontal()
                    if near(left, ol) then return { edge = "LEFT", offset = 0 } end
                    if near(left + width, ol + ow) then return { edge = "RIGHT", offset = 0 } end
                    return { offset = alongX }
                end
                local dock
                if overlapY and near(left, ol + ow + SNAP_GAP) then dock = alongVertical(); dock.side = "RIGHT"
                elseif overlapY and near(left + width, ol - SNAP_GAP) then dock = alongVertical(); dock.side = "LEFT"
                elseif overlapX and near(bottom, ob + oh + SNAP_GAP) then dock = alongHorizontal(); dock.side = "TOP"
                elseif overlapX and near(bottom + height, ob - SNAP_GAP) then dock = alongHorizontal(); dock.side = "BOTTOM" end
                if dock then dock.to = other.name; return dock end
            end
        end
    end
end

function BeginSackDrag(frame)
    local scale = frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not (scale and cx and left and bottom) then
        frame:StartMoving()
        return
    end
    local grabX, grabY = cx / scale - left, cy / scale - bottom
    frame.dragging = true
    frame:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local newLeft, newBottom = x / scale - grabX, y / scale - grabY
        if not (IsAltKeyDown and IsAltKeyDown()) then newLeft, newBottom = SnapPosition(self, newLeft, newBottom) end
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
    end)
end

function EndSackDrag(frame)
    if frame.dragging then
        frame.dragging = nil
        frame:SetScript("OnUpdate", nil)
    else
        frame:StopMovingOrSizing()
    end
end

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
        0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

-- Where a sack's empty slot goes: its own setting, else the default for every sack, else after the items.
-- Only the Other sack has the empty slot (it is the one that always exists); the rest never show one.
local function BlankMode(group)
    if not group.fixed then return "NONE" end
    return group.blank or "LAST"
end

-- Titles are a template: {name} {count} {items} {value} {free} {special} are filled in from what the sack holds.
local TITLE_DEFAULT = "{name} ({count})"
local TITLE_PIECES = {
    { token = "{name}", about = "the sack's name" },
    { token = "{count}", about = "kinds of item in it" },
    { token = "{items}", about = "total items, counting stacks" },
    { token = "{value}", about = "vendor sell value of all of it" },
    { token = "{free}", about = "free slots in normal bags" },
    { token = "{special}", about = "free slots in special bags" },
}

local function Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local text = ""
    if gold > 0 then text = text .. gold .. "|cffffd700g|r " end
    if silver > 0 or gold > 0 then text = text .. silver .. "|cffc7c7cfs|r " end
    return text .. rest .. "|cffeda55fc|r"
end

local function ExpandTitle(group, items, free, special)
    local stacks, value = 0, 0
    for _, item in ipairs(items) do
        local count = item.count or 1
        stacks = stacks + count
        value = value + (item.sellPrice or 0) * count
    end
    local pieces = { name = group.name, count = #items, items = stacks, value = Money(value), free = free, special = special }
    local template = group.titleText or TITLE_DEFAULT
    return (template:gsub("{(%w+)}", function(token)
        local found = pieces[token:lower()]
        if found ~= nil then return tostring(found) end
    end))
end

-- Ends a drag: remembers where the box went and which box, if any, it is now docked against.
local function FinishDrag(group, frame)
    EndSackDrag(frame)
    if DockFrame() then return end
    SavePosition(group, frame)
    local before = group.dock
    group.dock = DockOf(group, frame)
    local changed = (before and before.to) ~= (group.dock and group.dock.to)
        or (before and before.side) ~= (group.dock and group.dock.side)
    -- Boxes docked to this one are re-anchored to it, so they come along.
    if (group.dock or before or changed) and state.refresh then state.refresh() end
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
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints()
    frame.back:SetColorTexture(0, 0, 0, 0.45)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
        if full and frame.title.IsTruncated and frame.title:IsTruncated() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(full)
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

-- Which cell of the grid an item goes in: filling across then wrapping, or down then wrapping.
local function GridCell(index, layout)
    if layout.flow == "COLUMNS" then
        return math.floor((index - 1) / layout.wrap), (index - 1) % layout.wrap
    end
    return (index - 1) % layout.wrap, math.floor((index - 1) / layout.wrap)
end

local function FillGroup(group, items, free, special)
    local frame = state.frames[group] or MakeGroupFrame(group)
    state.frames[group] = frame
    local layout = LayoutOf(group)
    local size = SlotSize()
    -- The blank slot (it counts the free bag slots) goes last, first, or nowhere, per sack.
    local blankMode = BlankMode(group)
    local hasBlank = blankMode ~= "NONE"
    local shift = blankMode == "FIRST" and 1 or 0
    local cells = math.max(1, #items + (hasBlank and 1 or 0))
    local function Dimensions(grid)
        if grid.flow == "COLUMNS" then
            return math.ceil(cells / grid.wrap), math.min(grid.wrap, cells)
        end
        return math.min(grid.wrap, cells), math.ceil(cells / grid.wrap)
    end
    local columns, rows = Dimensions(layout)
    -- At a vendor or the bank every sack is laid out like a page, from the top left, across then down. The cells keep the
    -- order you normally read them in (left to right, top to bottom), so a sack that grows up or left looks the
    -- same, just packed to the top left. Afterwards it goes back to its own corner and flow.
    local reading
    if DockFrame() then
        local fromRightNow = layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT"
        local fromBottomNow = layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT"
        local list = {}
        for index = 1, cells do
            local column, row = GridCell(index, layout)
            local visualColumn = fromRightNow and (columns - 1 - column) or column
            local visualRow = fromBottomNow and (rows - 1 - row) or row
            list[index] = { index = index, key = visualRow * columns + visualColumn }
        end
        table.sort(list, function(a, b) return a.key < b.key end)
        reading = {}
        for rank, entry in ipairs(list) do reading[entry.index] = rank end
        layout = { anchor = "TOPLEFT", flow = "ROWS", title = layout.title, wrap = columns }
        columns, rows = Dimensions(layout)
    end
    local topSpace = layout.title == "TOP" and TITLE_HEIGHT or PADDING
    local bottomSpace = layout.title == "BOTTOM" and TITLE_HEIGHT or PADDING
    local width = PADDING * 2 + columns * size + (columns - 1) * SLOT_GAP
    local height = topSpace + rows * size + (rows - 1) * SLOT_GAP + bottomSpace
    frame:SetSize(width, height)

    -- The first cell is next to the corner the sack grows from.
    local fromRight = layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT"
    local fromBottom = layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT"
    local function place(frameToPlace, index)
        if reading then index = reading[index] end
        local column, row = GridCell(index, layout)
        local x = column * (size + SLOT_GAP)
        local y = row * (size + SLOT_GAP)
        x = fromRight and (width - PADDING - size - x) or (PADDING + x)
        y = fromBottom and (height - bottomSpace - size - y) or (topSpace + y)
        frameToPlace:ClearAllPoints()
        frameToPlace:SetPoint("TOPLEFT", x, -y)
    end

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

    for index, item in ipairs(items) do
        local button = frame.buttons[index] or MakeSlotButton(frame)
        frame.buttons[index] = button
        button:SetSize(size, size)
        button.bag, button.slot = item.bag, item.slot
        button:SetAttribute("item", item.bag .. " " .. item.slot)
        -- A sack can use its items on left click, like an action bar. Dragging still picks an item up.
        button.clickUse = group.useOnClick and true or false
        if not (InCombatLockdown and InCombatLockdown()) then
            button:SetAttribute("type1", button.clickUse and "item" or nil)
        end
        button.icon:SetTexture(item.icon)
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
        if color then button.back:SetColorTexture(color.r, color.g, color.b, 0.45) else button.back:SetColorTexture(0, 0, 0, 0.3) end
        button.count:SetText((item.count or 1) > 1 and item.count or "")
        if item.inSpecial then
            button.where, button.whereColor = "In your " .. item.bagName .. " (special bag).", { 0.4, 1, 0.4 }
            button.mark:SetColorTexture(0.2, 1, 0.2, 1)
            button.mark:Show()
        elseif item.fitsBag then
            if (item.fitsFree or 0) > 0 then
                button.where = "In " .. item.bagName .. ", but it fits your " .. item.fitsBag .. ", which has "
                    .. item.fitsFree .. " free slot" .. (item.fitsFree == 1 and "" or "s") .. ". Move it there."
                button.whereColor = { 1, 0.7, 0.1 }
                button.mark:SetColorTexture(1, 0.7, 0.1, 1)
            else
                button.where = "In " .. item.bagName .. ". It fits your " .. item.fitsBag .. ", but that is full."
                button.whereColor = { 0.7, 0.7, 0.7 }
                button.mark:SetColorTexture(0.6, 0.6, 0.6, 1)
            end
            button.mark:Show()
        else
            button.where, button.whereColor = "In " .. item.bagName .. ".", { 0.7, 0.7, 0.7 }
            button.mark:Hide()
        end
        place(button, index + shift)
        button:Show()
        UpdateCooldown(button)
    end
    for index = #items + 1, #frame.buttons do
        frame.buttons[index].bag = nil
        frame.buttons[index]:Hide()
    end

    -- A tooltip belongs to the slot it was opened on. When that slot now holds another item (one was sold or the
    -- list shifted) show the new item; when it is empty or gone, close the tooltip.
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
    if marked then frame.title:SetTextColor(markR, markG, markB) else frame.title:SetTextColor(1, 0.82, 0) end

    frame.blank:SetSize(size, size)
    if hasBlank then
        place(frame.blank, blankMode == "FIRST" and 1 or #items + 1)
        frame.blank:Show()
    else
        frame.blank:Hide()
    end
    frame.blank.text:SetText(free)
    if free > 0 then frame.blank.text:SetTextColor(1, 0.82, 0) else frame.blank.text:SetTextColor(1, 0.2, 0.2) end
    frame.blank.extra:SetText(special > 0 and ("+" .. special) or "")
    frame.blank.extra:SetTextColor(0.4, 1, 0.4)
end

-- The sack this one is docked to, if that sack still exists and the docks don't loop back around to this one.
-- A sack, or the free-slots box, by name.
local function FindDockable(name)
    local widget = SacksDB.widget
    return FindGroup(name) or (widget and widget.name == name and widget or nil)
end

local function DockTarget(group)
    local dock = group.dock
    if not dock then return nil end
    local target = FindDockable(dock.to)
    if not target or target == group or not state.frames[target] then return nil end
    local walk, steps = target, 0
    while walk and walk.dock and steps < 20 do
        walk = FindDockable(walk.dock.to)
        if walk == group then return nil end
        steps = steps + 1
    end
    return target
end

-- Puts one box where it belongs: against the box it is docked to, or at its saved position.
local function PlaceOne(group, frame)
    if not group.relativeTo and group.point ~= (group.anchor or DEFAULT_ANCHOR) then MoveToCorner(group, frame) end
    local target = DockTarget(group)
    if target then
        local anchor = group.anchor or DEFAULT_ANCHOR
        local v = (anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT") and "BOTTOM" or "TOP"
        local h = (anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT") and "RIGHT" or "LEFT"
        local side, offset, gap = group.dock.side, group.dock.offset or 0, SNAP_GAP
        local edge = group.dock.edge
        if edge == "TOP" or edge == "BOTTOM" then v = edge elseif edge == "LEFT" or edge == "RIGHT" then h = edge end
        local mine, theirs, x, y
        if side == "RIGHT" then mine, theirs, x, y = v .. "LEFT", v .. "RIGHT", gap, offset
        elseif side == "LEFT" then mine, theirs, x, y = v .. "RIGHT", v .. "LEFT", -gap, offset
        elseif side == "TOP" then mine, theirs, x, y = "BOTTOM" .. h, "TOP" .. h, offset, gap
        else mine, theirs, x, y = "TOP" .. h, "BOTTOM" .. h, offset, -gap end
        frame:SetPoint(mine, state.frames[target], theirs, x, y)
    else
        local relativeTo = group.relativeTo and _G[group.relativeTo] or UIParent
        frame:SetPoint(group.point or DEFAULT_ANCHOR, relativeTo, group.relPoint or group.point or DEFAULT_ANCHOR,
            group.x or 0, group.y or 0)
    end
end

local function PlaceGroups()
    local groups = AllGroups()
    -- Every anchor is dropped first. A sack that was stacked at a vendor is anchored to another sack, and putting
    -- it back while that stale anchor is still there can make two sacks depend on each other, which the game refuses.
    for _, group in ipairs(groups) do state.frames[group]:ClearAllPoints() end
    local vendor = DockFrame()
    local limit = vendor and tonumber(vendor:GetHeight()) or 0
    local overhang = vendor and Overhang(vendor) or 0
    local placed = {}
    -- Finds the spot for a box of this size: as far left as it fits, and as high as it fits there. Candidate spots are
    -- the top corner, below each placed box, and beside each placed box, so a box slips into the gap beside narrow ones.
    local function FindSpot(width, height)
        local spots = { { 0, 0 } }
        for _, box in ipairs(placed) do
            spots[#spots + 1] = { box.x, box.y + box.height + SLOT_GAP }
            spots[#spots + 1] = { box.x + box.width + SLOT_GAP, box.y }
        end
        local bestX, bestY
        for _, spot in ipairs(spots) do
            local x, y, free = spot[1], spot[2], true
            if y > 0 and y + height > limit then free = false end
            for _, box in ipairs(placed) do
                if free and x < box.x + box.width + SLOT_GAP and x + width + SLOT_GAP > box.x
                    and y < box.y + box.height + SLOT_GAP and y + height + SLOT_GAP > box.y then free = false end
            end
            if free and (not bestX or x < bestX or (x == bestX and y < bestY)) then bestX, bestY = x, y end
        end
        if bestX then return bestX, bestY end
        -- Nothing fits inside the window's height: start a new column past everything placed so far.
        local right = 0
        for _, box in ipairs(placed) do right = math.max(right, box.x + box.width + SLOT_GAP) end
        return right, 0
    end
    for _, group in ipairs(groups) do
        local frame = state.frames[group]
        -- An empty sack stays on screen (title and an empty box) so you can still see and move it; only a sack with
        -- nothing at all to show (no items, no empty slot, no title) goes away.
        local hidden = BlankMode(group) == "NONE" and group.title == "NONE" and (state.counts[group] or 0) == 0
        if vendor then
            -- Beside the vendor (or bank) window, in sack-list order, filling downward to the window's height. A box that no
            -- longer fits below goes into free space beside the narrower boxes, or into a new column.
            if not hidden then
                local height, width = tonumber(frame:GetHeight()) or 0, tonumber(frame:GetWidth()) or 0
                local x, y = FindSpot(width, height)
                frame:SetPoint("TOPLEFT", vendor, "TOPRIGHT", PADDING + overhang + x, -y)
                placed[#placed + 1] = { x = x, y = y, width = width, height = height }
            end
        else
            PlaceOne(group, frame)
        end
        if hidden then frame:Hide() else frame:Show() end
    end
end

-- The order inside a sack: pinned items first (in the order they were pinned), then each sort key in turn, then the
-- bag position so the order never flickers.
local SORT_KEYS = {
    name = { label = "Name", value = function(item) return item.name:lower() end },
    class = { label = "Class", value = function(item) return item.classID or -1 end },
    sub = { label = "Subclass", value = function(item) return item.subClassID or -1 end },
    quality = { label = "Quality", value = function(item) return item.quality end },
    count = { label = "Number carried", value = function(item) return item.count or 1 end },
    position = { label = "Bag position", value = function(item) return item.bag end },
}
local SORT_KEY_ORDER = { "name", "class", "sub", "quality" }
-- Every other field a rule can test is a sort key too, read the same way the rules read it. An equip slot sorts in the
-- order the slots are listed in the rule editor; the rest sort by their number.
for _, field in ipairs({ "ilvl", "level", "price", "equip", "bind", "bound", "reagent", "family", "stack" }) do
    local stat = STATS[field]
    local label = field == "stack" and "Max stack size" or (stat.text:gsub("^%l", string.upper))
    if field == "equip" then
        local slotRank = {}
        for index, option in ipairs(Stat.Options("equip")) do slotRank[option.value] = index end
        SORT_KEYS[field] = { label = label, value = function(item) return slotRank[stat.get(item) or "NONE"] or 0 end }
    else
        SORT_KEYS[field] = { label = label, value = function(item) return tonumber(stat.get(item)) or -1 end }
    end
    SORT_KEY_ORDER[#SORT_KEY_ORDER + 1] = field
end
SORT_KEY_ORDER[#SORT_KEY_ORDER + 1] = "count"
SORT_KEY_ORDER[#SORT_KEY_ORDER + 1] = "position"

-- An "Items matching" step puts the items that match its rule first, or last when it is descending. A rule with no
-- lines matches nothing, so the step then changes nothing.
local function MatchRank(rule, item)
    if not rule then return 1 end
    for _, condition in ipairs(rule) do
        -- a rule with only empty text lines has nothing to match yet
        if not IsBlankLine(condition) then
            if Matches(rule, item) then return 0 end
            return 1
        end
    end
    return 1
end

-- Sorting steps saved by an earlier version as one "buckets" step become one "Items matching" step per bucket,
-- which sorts items exactly the same way.
-- Subclass ids are labels, not a scale, so only "is" and "is not" mean anything for them. A line saved with an
-- ordered comparison on one becomes "is".
local ORDERED = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }
local function FixRule(rule)
    for _, clause in ipairs(rule or {}) do
        if (clause.field == "sub" or clause.field == "class") and ORDERED[clause.op] then
            clause.op = "="
            ns.Say("a " .. clause.field .. " line used < or > (meaningless for ids); it now reads 'is'")
        end
    end
end

local function UpgradeSort(group)
    FixRule(group.rule)
    for _, spec in ipairs(group.sort or {}) do FixRule(spec.rule) end
    if not group.sort then return end
    local list = {}
    for _, spec in ipairs(group.sort) do
        if spec.buckets then
            for _, bucket in ipairs(spec.buckets) do
                list[#list + 1] = { key = "match", rule = bucket.rule or {} }
            end
        else
            if spec.key == "match" then spec.descending = nil end
            list[#list + 1] = spec
        end
    end
    group.sort = list
end

local function SortItems(group, items)
    local rank = {}
    for index, id in ipairs(group.pins or {}) do rank[id] = index end
    local keys = group.sort or DEFAULT_SORT
    table.sort(items, function(a, b)
        local rankA, rankB = rank[a.itemID] or math.huge, rank[b.itemID] or math.huge
        if rankA ~= rankB then return rankA < rankB end
        for _, spec in ipairs(keys) do
            local key = SORT_KEYS[spec.key]
            if spec.key == "match" then
                key = { value = function(item) return MatchRank(spec.rule, item) end }
            end
            if key then
                local left, right = key.value(a), key.value(b)
                if left ~= right then
                    if spec.descending then return left > right end
                    return left < right
                end
            end
        end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
end

-- An optional box of its own that shows the free slots, to put anywhere (or dock against a sack).
local function WidgetGroup()
    SacksDB.widget = SacksDB.widget or { name = "Free slots", shown = false, point = "CENTER", x = 0, y = -220 }
    return SacksDB.widget
end

local function MakeWidget(group)
    local frame = CreateFrame("Frame", "SacksFreeWidget", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.back = frame:CreateTexture(nil, "BACKGROUND")
    frame.back:SetAllPoints()
    frame.back:SetColorTexture(0, 0, 0, 0.45)
    frame.slot = frame:CreateTexture(nil, "ARTWORK")
    frame.slot:SetColorTexture(1, 1, 1, 0.08)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("CENTER")
    frame.extra = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.extra:SetTextColor(0.4, 1, 0.4)
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
    if free > 0 then frame.text:SetTextColor(1, 0.82, 0) else frame.text:SetTextColor(1, 0.2, 0.2) end
    frame.extra:SetText(special > 0 and ("+" .. special) or "")
    if not DockFrame() then
        frame:ClearAllPoints()
        PlaceOne(group, frame)
    end
    frame:Show()
end

local function Refresh()
    if not SacksDB then return end
    if InCombatLockdown() then
        state.pending = true -- secure buttons can't be changed in combat; redo it when combat ends
        if ns.RefreshSettings then pcall(ns.RefreshSettings) end
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
    state.shown = 0
    for _, group in ipairs(groups) do
        SortItems(group, sorted[group])
        if group.reverse then
            local list, count = sorted[group], #sorted[group]
            for index = 1, math.floor(count / 2) do list[index], list[count - index + 1] = list[count - index + 1], list[index] end
        end
        state.counts[group] = #sorted[group]
        state.shown = state.shown + #sorted[group]
        FillGroup(group, sorted[group], free, special)
    end
    PlaceGroups()
    UpdateWidget(free, special)
    if ns.RefreshSettings then pcall(ns.RefreshSettings) end
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

ns.CreateSack = CreateSack
ns.UpgradeSort = UpgradeSort
ns.HideRemoved = HideRemoved
ns.Refresh = Refresh
ns.SORT_KEYS = SORT_KEYS
ns.SORT_KEY_ORDER = SORT_KEY_ORDER
ns.SortItems = SortItems
ns.TITLE_DEFAULT = TITLE_DEFAULT
ns.TITLE_PIECES = TITLE_PIECES
ns.WidgetGroup = WidgetGroup
