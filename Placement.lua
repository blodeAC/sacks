-- sacks: Placement.lua
local _, ns = ...
local AllGroups, BlankMode, DEFAULT_ANCHOR, DEFAULT_COLUMNS = ns.AllGroups, ns.BlankMode, ns.DEFAULT_ANCHOR, ns.DEFAULT_COLUMNS
local DEFAULT_FLOW, DEFAULT_TITLE, FindGroup, PADDING = ns.DEFAULT_FLOW, ns.DEFAULT_TITLE, ns.FindGroup, ns.PADDING
local SLOT_GAP, state = ns.SLOT_GAP, ns.state

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
    -- A position with no screen point of its own (a new sack, a starting one) is measured from the middle of the screen.
    -- Without this it would be read from the screen corner it is moved to, and land at the top left.
    group.relPoint = group.relPoint or group.point or "CENTER"
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
    -- The game does not let a frame be moved in combat while item buttons are attached to it, and raises its
    -- "blocked from an action" popup if you try. A sack with no item buttons (Combat loot) can still be moved.
    if InCombatLockdown and InCombatLockdown() and #(rawget(frame, "buttons") or {}) > 0 then
        frame.noDrag = true
        ns.Say("sacks with items in them can't be moved in combat (the game doesn't allow it)")
        return
    end
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

-- Ends a drag: remembers where the box went and which box, if any, it is now docked against.
local function FinishDrag(group, frame)
    if rawget(frame, "noDrag") then frame.noDrag = nil return end -- the drag was refused in combat
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
        if group.builtin and not group.always then hidden = true end -- Combat loot: only in combat, unless asked to stay
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


-- The game opens windows side by side: the newest at the left, the ones already open pushed to the right. A vendor opened
-- while the character or professions window is up therefore lands at the left, with that window between it and the free
-- screen. Packs the windows the other way round: the others slide left into the vendor's place, in the order they were in,
-- and the vendor goes after them, so the sacks beside it always have room. The game lays the windows out again whenever
-- one opens or closes; this runs again then.
local function KeepVendorLast()
    local vendor = MerchantFrame
    if not (state.vendor and vendor and vendor.IsShown and vendor:IsShown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not (UIPanelWindows and UIParent and UIParent.GetEffectiveScale and vendor.GetEffectiveScale) then return end
    local uiScale = UIParent:GetEffectiveScale()
    if type(uiScale) ~= "number" or uiScale <= 0 then return end
    local pixel = 1 / uiScale -- one screen pixel in the screen's units: edges that close count as the same edge
    -- a window's left, right and bottom edge, in the screen's own units
    local function Edges(frame)
        local scale = frame.GetEffectiveScale and frame:GetEffectiveScale()
        local left, right = frame.GetLeft and frame:GetLeft(), frame.GetRight and frame:GetRight()
        local bottom = frame.GetBottom and frame:GetBottom()
        if not (type(scale) == "number" and scale > 0 and type(left) == "number" and type(right) == "number"
            and type(bottom) == "number") then return nil end
        local k = scale / uiScale
        return left * k, right * k, bottom * k
    end
    local function MoveTo(frame, left, bottom) -- in the screen's units
        local k = uiScale / frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * k, bottom * k)
    end
    local vLeft, vRight, vBottom = Edges(vendor)
    if not vLeft then return end
    -- the windows pushed to the right of the vendor
    local others, minLeft, farRight = {}, nil, nil
    for name, info in pairs(UIPanelWindows) do
        local frame = _G[name]
        if frame and frame ~= vendor and type(info) == "table" and info.area ~= "fullscreen"
            and frame.IsShown and frame:IsShown() then
            local left, right, bottom = Edges(frame)
            if left and left >= vLeft - pixel then
                -- the window's tabs stick out past its right edge; the vendor must go beyond them too
                local reach = right + Overhang(frame) * (frame:GetEffectiveScale() / uiScale)
                others[#others + 1] = { frame = frame, left = left, bottom = bottom }
                minLeft = math.min(minLeft or left, left)
                farRight = math.max(farRight or reach, reach)
            end
        end
    end
    if #others == 0 then return end
    -- the others slide left by this much; the vendor goes after them, the same distance from what sticks out as the sacks keep
    local shift = minLeft - vLeft
    local vendorLeft = farRight - shift + PADDING
    local screen = UIParent.GetWidth and UIParent:GetWidth()
    if type(screen) == "number" and vendorLeft + (vRight - vLeft) > screen then return end -- no room at the right
    for _, other in ipairs(others) do MoveTo(other.frame, other.left - shift, other.bottom) end
    MoveTo(vendor, vendorLeft, vBottom)
end
ns.KeepVendorLast = KeepVendorLast

ns.BeginSackDrag = BeginSackDrag
ns.DockFrame = DockFrame
ns.FinishDrag = FinishDrag
ns.LayoutOf = LayoutOf
ns.PlaceGroups = PlaceGroups
ns.PlaceOne = PlaceOne
