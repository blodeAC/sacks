-- sacks: Placement.lua
local _, ns = ...
local AllGroups, BlankMode, DEFAULT_ANCHOR, DEFAULT_COLUMNS = ns.AllGroups, ns.BlankMode, ns.DEFAULT_ANCHOR, ns.DEFAULT_COLUMNS
local DEFAULT_FLOW, DEFAULT_TITLE, FindGroup, PADDING = ns.DEFAULT_FLOW, ns.DEFAULT_TITLE, ns.FindGroup, ns.PADDING
local SLOT_GAP, state = ns.SLOT_GAP, ns.state

-- The window the sacks line up beside while it is open, and which place it is: the vendor's, or the bank's; with the Town
-- sacks showing, also the mailbox's and the auction house's.
local function DockFrame()
    if state.vendor and MerchantFrame then return MerchantFrame, "vendor" end
    if state.bank and BankFrame then return BankFrame, "bank" end
    if SacksDB and SacksDB.layout == "town" and state.open then
        local mail, auction = rawget(_G, "MailFrame"), rawget(_G, "AuctionHouseFrame")
        if state.open.mail and mail then return mail, "mail" end
        if state.open.auction and auction then return auction, "auction" end
    end
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

-- How far right of the window the sacks start: past what sticks out of it (Overhang), and past any other window lying
-- over that spot, such as an addon's panel hung off the professions window (Blackthornes' craft queue). A window there is
-- a frame on the screen, shown, taking the mouse, narrower than most of the screen, beside at least half the window's
-- height (a window or panel; not a row of buff icons, the minimap or a lone button) and
-- starting before the sacks would (or so close after that not one slot fits between); the sacks then start after it, and after whatever lies past that, and so on. Each such
-- window is watched: when it hides or shows again, the sacks move back or out of its way. Frames the game keeps from
-- addons (forbidden: some of its dialogs) are skipped, since even asking whether they are shown is an error.
local watchedCovers = {}
local function Recheck() if ns.RecheckCover then C_Timer.After(0, ns.RecheckCover) end end

-- Watches a frame that can lie over the sacks: when it, or a part of it (a panel that opens out of it), shows, hides or
-- changes size, the sacks are placed again.
local function WatchCover(frame)
    if watchedCovers[frame] or not frame.HookScript then return end
    watchedCovers[frame] = true
    frame:HookScript("OnShow", Recheck)
    frame:HookScript("OnHide", Recheck)
    frame:HookScript("OnSizeChanged", Recheck)
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" and child.HookScript and not (child.IsForbidden and child:IsForbidden()) then
            child:HookScript("OnShow", Recheck)
            child:HookScript("OnHide", Recheck)
        end
    end
end

-- Addon panels known to open beside the professions window, watched from the start: they can show up later than the
-- window itself (Blackthornes' craft queue does), when nothing else would place the sacks again.
local KNOWN_COVERS = { "BlackthornesTSCraftPanel" }
local function WatchKnownCovers()
    for _, name in ipairs(KNOWN_COVERS) do
        local frame = rawget(_G, name)
        if type(frame) == "table" then WatchCover(frame) end
    end
end
ns.OnEvent("ADDON_LOADED", WatchKnownCovers)
ns.OnEvent("PLAYER_LOGIN", WatchKnownCovers)

-- How far right a frame reaches, with whatever of it is shown sticking out past its own edge (a second panel that opens
-- beside it, as Blackthornes' queued crafts do), in this scale.
local function Reach(frame, scale)
    local widest = 0
    local function scan(each, depth)
        local measured, edge = pcall(each.GetRight, each) -- the game refuses to measure some frames (the ping pin)
        if not measured then edge = nil end
        local own = each:GetEffectiveScale()
        if type(edge) == "number" and type(own) == "number" then widest = math.max(widest, edge * own / scale) end
        if depth < 3 then
            for _, child in ipairs({ each:GetChildren() }) do
                if type(child) == "table" and not (child.IsForbidden and child:IsForbidden()) and child.IsShown
                    and child:IsShown() and child.GetRight then
                    scan(child, depth + 1)
                end
            end
        end
    end
    scan(frame, 1)
    return widest
end

local function Rect(frame) return frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom() end

local function TakesMouse(frame)
    if frame.IsMouseEnabled and frame:IsMouseEnabled() then return true end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" and not (child.IsForbidden and child:IsForbidden()) and child.IsMouseEnabled and child:IsMouseEnabled() then return true end
    end
    return false
end

local function Covering(window)
    local overhang = Overhang(window)
    local right, top, bottom = window:GetRight(), window:GetTop(), window:GetBottom()
    local scale = window.GetEffectiveScale and window:GetEffectiveScale()
    if type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" or type(scale) ~= "number" or scale == 0 then
        return overhang
    end
    local screen = (UIParent:GetWidth() or 0) * UIParent:GetEffectiveScale() / scale
    local ours = {}
    for _, frame in pairs(state.frames or {}) do ours[frame] = true end
    -- a gap too narrow for even one slot of a sack counts as covered too
    local gap = ns.SlotSize() + 2 * PADDING
    local reach, moved, rounds = right + overhang, true, 0
    while moved and rounds < 10 do
        moved, rounds = false, rounds + 1
        for _, child in ipairs({ UIParent:GetChildren() }) do
            if type(child) == "table" and child ~= window and not ours[child] and not (child.IsForbidden and child:IsForbidden()) and child.IsVisible and child:IsVisible()
                and child.GetLeft then
                local childScale = child:GetEffectiveScale()
                local measured, left, edge, childTop, childBottom = pcall(Rect, child) -- some frames can not be measured
                if not measured then left = nil end
                if type(left) == "number" and type(edge) == "number" and type(childTop) == "number"
                    and type(childBottom) == "number" and type(childScale) == "number" then
                    local k = childScale / scale
                    left, edge, childTop, childBottom = left * k, edge * k, childTop * k, childBottom * k
                    local wide = edge - left
                    local overlap = math.min(childTop, top) - math.max(childBottom, bottom)
                    if wide > 0 and wide < screen * 0.6 and overlap >= (top - bottom) / 2
                        and left < reach + gap and edge > reach and TakesMouse(child) then
                        reach, moved = math.max(edge, Reach(child, scale)), true
                        WatchCover(child)
                    end
                end
            end
        end
    end
    return reach - right
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

-- How a sack is laid out: its own settings, also while a vendor window is open. Town sacks packed beside a window
-- (PackTown) take the width the packing gave them, filled like a page.
local function LayoutOf(group)
    local Default = ns.Default
    local packed = state.pack and state.pack.cols[group]
    if packed then
        return { anchor = "TOPLEFT", flow = "ROWS", title = group.title or Default("title", DEFAULT_TITLE), wrap = packed }
    end
    return { anchor = group.anchor or DEFAULT_ANCHOR, flow = group.flow or Default("flow", DEFAULT_FLOW),
        title = group.title or Default("title", DEFAULT_TITLE),
        wrap = group.cols or Default("cols", SacksDB.columns or DEFAULT_COLUMNS) }
end

local BeginSackDrag, EndSackDrag
-- Dragging a sack snaps its edges to the screen edges and to other sacks (hold Alt to drag freely), so sacks
-- can be tucked against each other and moved aside without gaps or overlap.
local SNAP_DISTANCE = 14
local SNAP_GAP = 2

-- A sack, or the free-slots box, by name.
local function FindDockable(name)
    local widget, money = SacksDB.widget, SacksDB.money
    return FindGroup(name) or (widget and widget.name == name and widget or nil) or (money and money.name == name and money or nil)
end

-- The frames that move with this sack: those docked to it, docked to one of those, and so on. While it is dragged they
-- come along, so they are always right against it; it must not snap or dock to them, or the two would be docked to
-- each other and neither dock could hold.
local function FollowerFrames(group)
    local followers = {}
    for other, otherFrame in pairs(state.frames) do
        local walk, steps = other, 0
        while walk and walk.dock and steps < 20 do
            walk = FindDockable(walk.dock.to)
            if walk == group then
                followers[otherFrame] = true
                break
            end
            steps = steps + 1
        end
    end
    return followers
end

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

local function SnapPosition(frame, left, bottom, followers)
    local width, height = frame:GetWidth(), frame:GetHeight()
    local xs, ys = { { low = 0, high = UIParent:GetWidth() } }, { { low = 0, high = UIParent:GetHeight() } }
    for _, other in pairs(state.frames) do
        if other ~= frame and other:IsShown() and not (followers and followers[other]) then
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
-- A sack dropped against several (tucked into a corner) docks to the first; the others are remembered as touches: if one
-- of those grows into it later, this sack moves out of its way (see PushApart).

local function DockOf(group, frame)
    local left, bottom, width, height = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not (type(left) == "number" and type(bottom) == "number") then return nil end
    local anchor = group.anchor or DEFAULT_ANCHOR
    local fromRight = anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT"
    local fromBottom = anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT"
    local function near(a, b) return math.abs(a - b) <= 1.5 end
    local followers = FollowerFrames(group)
    local found, touches = nil, {}
    for other, otherFrame in pairs(state.frames) do
        if other ~= group and otherFrame:IsShown() and not followers[otherFrame] then
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
                if dock then
                    dock.to = other.name
                    if found then touches[#touches + 1] = { to = other.name, side = dock.side } else found = dock end
                end
            end
        end
    end
    return found, (#touches > 0 and touches or nil)
end

-- In combat the game freezes anything secure, and everything attached to it: a sack whose items left click uses has a
-- secure "use item" layer on its slots (Slots.lua), so it, and every sack docked to it or it to them, can't be moved,
-- resized or refilled until combat ends. The rest are the game's plain bag buttons and stay live. Out of combat, none.
local function HasSecure(frame)
    if frame.IsProtected and frame:IsProtected() then return true end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" and rawget(child, "isUseLayer") then return true end -- a "use item" layer (Slots.lua)
    end
    return false
end

local function ChainRoot(group)
    local walk, steps = group, 0
    while walk and walk.dock and steps < 20 do
        local up = FindDockable(walk.dock.to)
        if not up then break end
        walk, steps = up, steps + 1
    end
    return walk
end

local function FrozenGroups()
    local frozen = {}
    if not InCombatLockdown() then return frozen end
    local roots = {}
    for group, frame in pairs(state.frames) do
        if HasSecure(frame) then roots[ChainRoot(group)] = true end
    end
    for group in pairs(state.frames) do
        if roots[ChainRoot(group)] then frozen[group] = true end
    end
    return frozen
end
ns.FrozenGroups = FrozenGroups

function BeginSackDrag(frame)
    -- The game does not let a frozen sack be moved in combat (see FrozenGroups), and raises its "blocked from an
    -- action" popup if you try.
    if InCombatLockdown() then
        local frozen = FrozenGroups()
        for group, each in pairs(state.frames) do
            if each == frame and frozen[group] then
                frame.noDrag = true
                ns.Say("a sack whose items left click uses, and what is docked with it, can't be moved in combat (the game doesn't allow it)")
                return
            end
        end
    end
    local scale = frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not (scale and cx and left and bottom) then
        frame:StartMoving()
        return
    end
    local grabX, grabY = cx / scale - left, cy / scale - bottom
    local followers = {}
    for group, each in pairs(state.frames) do
        if each == frame then followers = FollowerFrames(group) end
    end
    frame.dragging = true
    frame:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local newLeft, newBottom = x / scale - grabX, y / scale - grabY
        if not (IsAltKeyDown and IsAltKeyDown()) then newLeft, newBottom = SnapPosition(self, newLeft, newBottom, followers) end
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
    group.dock, group.touches = DockOf(group, frame)
    local changed = (before and before.to) ~= (group.dock and group.dock.to)
        or (before and before.side) ~= (group.dock and group.dock.side)
    -- Boxes docked to this one are re-anchored to it, so they come along.
    if (group.dock or before or changed) and state.refresh then state.refresh() end
end

-- The sack this one is docked to, if that sack still exists and the docks don't loop back around to this one.

local function DockTarget(group)
    local dock = group.dock
    if not dock then return nil end
    local target = FindDockable(dock.to)
    if not target or target == group or not state.frames[target] then return nil end
    local walk, steps = target, 0
    while walk and walk.dock and steps < 20 do
        walk = FindDockable(walk.dock.to)
        if walk == group then
            -- Docks that loop (A to B and B to A) can't both hold, and while both are kept neither does. Saves from
            -- before this was prevented can have one: this sack lets go, so the other one's dock holds again.
            group.dock = nil
            return nil
        end
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

-- Where a frame is on screen, in its own units, or nil while it has no place yet.
local function Rect(frame)
    local left, bottom, width, height = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not (type(left) == "number" and type(bottom) == "number" and type(width) == "number" and type(height) == "number") then return nil end
    return { left = left, bottom = bottom, right = left + width, top = bottom + height }
end

-- Which side of `other` a sack keeps to, if it docked to it or was dropped touching it.
local function KeepsTo(group, other)
    if group.dock and group.dock.to == other.name then return group.dock.side end
    for _, touch in ipairs(group.touches or {}) do
        if touch.to == other.name then return touch.side end
    end
end

-- Whether `group` hangs from `other` through its docks.
local function HangsFrom(group, other)
    local walk, steps = group, 0
    while walk and walk.dock and steps < 20 do
        walk = FindDockable(walk.dock.to)
        if walk == other then return true end
        steps = steps + 1
    end
    return false
end

-- Sacks that grew into each other are pushed apart. Of two that overlap, the one that moves is the one that was dropped
-- against the other (it keeps to its side of it), else the one docked under the other, else the one lower in the list;
-- with what is docked to it. A sack that keeps to a side moves straight out that side; otherwise the shortest way out.
-- Nothing is saved: the push is worked out again at every placement from the saved spots and docks, so when a sack
-- shrinks again the one it pushed goes back.
local function PushApart(groups)
    state.pushedBy = {}
    local shown = {}
    for index, group in ipairs(groups) do
        local frame = state.frames[group]
        if frame and frame:IsShown() then shown[#shown + 1] = { group = group, frame = frame, index = index } end
    end
    local function overlap(a, b)
        return a and b and a.left < b.right and a.right > b.left and a.bottom < b.top and a.top > b.bottom
    end
    for _ = 1, 20 do -- a push can land a sack on another; a few rounds settle it
        local moved = false
        for i = 1, #shown do
            for j = i + 1, #shown do
                local a, b = shown[i], shown[j]
                local ra, rb = Rect(a.frame), Rect(b.frame)
                if overlap(ra, rb) then
                    local mover, still, side
                    local aSide, bSide = KeepsTo(a.group, b.group), KeepsTo(b.group, a.group)
                    if aSide then mover, still, side = a, b, aSide
                    elseif bSide then mover, still, side = b, a, bSide
                    elseif HangsFrom(a.group, b.group) then mover, still = a, b
                    elseif HangsFrom(b.group, a.group) then mover, still = b, a
                    else mover, still = (a.index > b.index) and a or b, (a.index > b.index) and b or a end
                    -- A sack that falls to the bottom is never pushed up or down. Hanging under one that doesn't fall,
                    -- the other one gives way instead: it is pushed up, on top.
                    local OPPOSITE = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }
                    if mover.group.gravity and not still.group.gravity and (side == "TOP" or side == "BOTTOM") then
                        mover, still, side = still, mover, OPPOSITE[side]
                    end
                    local mine, theirs = Rect(mover.frame), Rect(still.frame)
                    local ways = {
                        RIGHT = { theirs.right + SNAP_GAP - mine.left, 0 }, LEFT = { theirs.left - SNAP_GAP - mine.right, 0 },
                        TOP = { 0, theirs.top + SNAP_GAP - mine.bottom }, BOTTOM = { 0, theirs.bottom - SNAP_GAP - mine.top },
                    }
                    -- a sack that falls to the bottom is only ever pushed sideways
                    if mover.group.gravity then ways.TOP, ways.BOTTOM = nil, nil end
                    local way = side and ways[side]
                    if not way then
                        for _, each in pairs(ways) do
                            if not way or math.abs(each[1]) + math.abs(each[2]) < math.abs(way[1]) + math.abs(way[2]) then way = each end
                        end
                    end
                    local point, relativeTo, relativePoint, x, y = mover.frame:GetPoint(1)
                    if point then
                        mover.frame:ClearAllPoints()
                        mover.frame:SetPoint(point, relativeTo, relativePoint, (x or 0) + way[1], (y or 0) + way[2])
                        state.pushedBy[mover.group] = still.group
                        moved = true
                    end
                end
            end
        end
        if not moved then break end
    end
end

-- Sacks ticked "Falls to the bottom" drop straight down until they rest on the bottom of the screen or on a sack under
-- them (one that overlaps them left to right and is lower), like stacking blocks. Their dock still sets where they are
-- left to right; only the height is gravity's. The lowest settles first, and whatever is docked to a sack moves with it,
-- so a stack builds up from the bottom: nothing is ever pulled up off the bottom, and a sack under one that grows lifts
-- what rests on it. Nothing is saved.
local function ApplyGravity(all)
    local rects = {}
    for _, group in ipairs(all) do
        local frame = state.frames[group]
        local r = frame and frame:IsShown() and Rect(frame)
        if r then rects[group] = r end
    end
    local waiting, settled = {}, {}
    for _, group in ipairs(all) do if group.gravity and rects[group] then waiting[group] = true end end
    while next(waiting) do
        local lowest
        for group in pairs(waiting) do
            if not lowest or rects[group].bottom < rects[lowest].bottom then lowest = group end
        end
        waiting[lowest] = nil
        local me, frame = rects[lowest], state.frames[lowest]
        local middle, floor = (me.bottom + me.top) / 2, 0
        for other, r in pairs(rects) do
            if other ~= lowest and r.left < me.right - 1 and r.right > me.left + 1 and (r.bottom + r.top) / 2 < middle then
                floor = math.max(floor, r.top + SNAP_GAP)
            end
        end
        local dy = floor - me.bottom
        if math.abs(dy) > 0.5 then
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", me.left, floor)
            settled[lowest] = true
            -- It moved dy, and so did what hangs from it: the sacks docked to it (and to those), except one that has
            -- settled on its own already (it no longer follows, and neither does what hangs from it).
            local moved, grew = { [lowest] = true }, true
            while grew do
                grew = false
                for group in pairs(rects) do
                    if not moved[group] and not settled[group] then
                        local target = DockTarget(group)
                        if target and moved[target] then moved[group], grew = true, true end
                    end
                end
            end
            for group in pairs(moved) do
                local r = rects[group]
                r.bottom, r.top = r.bottom + dy, r.top + dy
            end
        end
    end
end

-- Whether a sack is left off the screen: one with nothing at all to show (no items, no empty slot, no title), and New,
-- which only shows while it holds something unless asked to stay. An empty sack otherwise stays (title and an empty box)
-- so you can still see and move it.
local function IsHidden(group)
    if state.pack and state.pack.hidden[group] then return true end
    local hidden = BlankMode(group) == "NONE" and group.title == "NONE" and (state.counts[group] or 0) == 0
    if group.builtin and not group.always then hidden = true end
    return hidden
end

---------------------------------------------------------------------------------------------------
-- Town beside a window: every sack's width is chosen, and the sacks are arranged, so all of them take the least room
-- across while no column of sacks is taller than the window. Worked out again at every rebuild, from what each sack holds.
---------------------------------------------------------------------------------------------------

-- The sack that goes first (top left, against the window) at each place: the one Butler fills for what you came to do.
local FIRST_VERDICT = { vendor = "sell", mail = "mail", auction = "auction", bank = "keep" }
-- More sacks than this with items in them are arranged in list order (trying every arrangement grows too fast).
local MOST_ARRANGED = 11

local function ButlerSackOf(group)
    local rule = group.rule
    if rule and #rule == 1 and rule[1].field == "butler" and rule[1].op == "=" then return rule[1].value end
end

-- The sack that goes first at a place: the one chosen in Settings (by name; "" for none), else the one Butler fills for
-- what you came to do there.
local function FirstSack(place, groups)
    local chosen = SacksDB.townFirst and SacksDB.townFirst[place]
    if chosen == "" then return nil end
    for _, group in ipairs(groups) do
        if chosen and group.name == chosen then return group end
    end
    -- nothing chosen, or the chosen sack is gone (renamed or deleted): the one Butler fills
    for _, group in ipairs(groups) do
        if ButlerSackOf(group) == FIRST_VERDICT[place] then return group end
    end
end
ns.TownFirstSack = FirstSack
ns.TOWN_FIRST_VERDICT = FIRST_VERDICT

-- How big a sack is with this many columns (fewer when it has fewer cells): the same sums SackGeometry makes.
local function Measure(group, cols)
    local cells = math.max(1, (state.counts[group] or 0) + (BlankMode(group) ~= "NONE" and 1 or 0))
    local columns = math.min(cols, cells)
    local title = group.title or ns.Default("title", DEFAULT_TITLE)
    local top = title == "TOP" and ns.TITLE_HEIGHT or PADDING
    local bottom = title == "BOTTOM" and ns.TITLE_HEIGHT or PADDING
    local width, height = ns.GridSize(columns, math.ceil(cells / columns), ns.SlotSize(), top, bottom)
    return width, height, cells
end

-- One column of sacks given one width: each sack as wide as that (or its cells), so as short as it can be. Its width
-- in pixels and its height.
local function StackSize(members, cols)
    local width, height = 0, -SLOT_GAP
    for _, group in ipairs(members) do
        local w, h = Measure(group, cols)
        width = math.max(width, w)
        height = height + h + SLOT_GAP
    end
    return width, height
end

-- The narrowest a column of these sacks can be and still fit in the height: its column count and width in pixels.
-- A lone sack too tall even at its widest still gets a column (at its widest); several that can't fit get none.
local function NarrowestStack(members, limit)
    local most = 1
    for _, group in ipairs(members) do
        local _, _, cells = Measure(group, 1)
        most = math.max(most, cells)
    end
    local low, high = 1, most
    if select(2, StackSize(members, high)) > limit then
        if #members > 1 then return nil end
        return high, (StackSize(members, high))
    end
    while low < high do -- heights only fall as the width grows
        local mid = math.floor((low + high) / 2)
        if select(2, StackSize(members, mid)) <= limit then high = mid else low = mid + 1 end
    end
    return low, (StackSize(members, low))
end

-- Columns of sacks in list order: the split of the list into runs that takes the least room across.
local function ArrangeInOrder(full, limit)
    local n = #full
    local best = { [0] = { width = 0, count = 0 } }
    for i = 1, n do
        for j = 1, i do
            local before = best[j - 1]
            if before then
                local members = {}
                for k = j, i do members[#members + 1] = full[k] end
                local cols, width = NarrowestStack(members, limit)
                if cols then
                    local total = before.width + width + (j > 1 and SLOT_GAP or 0)
                    local mine = best[i]
                    if not mine or total < mine.width or (total == mine.width and before.count + 1 < mine.count) then
                        best[i] = { width = total, count = before.count + 1, from = j, cols = cols, prev = j - 1 }
                    end
                end
            end
        end
    end
    local stacks, at = {}, n
    while at > 0 do
        local step = best[at]
        local members = {}
        for k = step.from, at do members[#members + 1] = full[k] end
        table.insert(stacks, 1, { members = members, cols = step.cols })
        at = step.prev
    end
    return stacks
end

-- Columns of sacks in any arrangement: every way of grouping them is tried (a sack's column is a set of sacks), the one
-- that takes the least room across wins, fewer columns breaking a tie.
local function ArrangeFreely(full, limit)
    local n = #full
    local band, bor = bit.band, bit.bor
    local all = 2 ^ n - 1
    local stackOf = {} -- [set] = { cols, width } or false
    local function Stack(set)
        local known = stackOf[set]
        if known ~= nil then return known end
        local members = {}
        for i = 1, n do
            if band(set, 2 ^ (i - 1)) ~= 0 then members[#members + 1] = full[i] end
        end
        local cols, width = NarrowestStack(members, limit)
        stackOf[set] = cols and { cols = cols, width = width } or false
        return stackOf[set]
    end
    local best = { [0] = { width = 0, count = 0 } }
    local function Solve(rest)
        if best[rest] then return best[rest] end
        local low = band(rest, -rest)
        local mine = { width = math.huge, count = math.huge }
        local set = rest
        while set > 0 do
            if band(set, low) ~= 0 then
                local stack = Stack(set)
                if stack then
                    local after = Solve(rest - set)
                    local total = stack.width + after.width + (after.count > 0 and SLOT_GAP or 0)
                    if total < mine.width or (total == mine.width and after.count + 1 < mine.count) then
                        mine = { width = total, count = after.count + 1, set = set, cols = stack.cols }
                    end
                end
            end
            set = band(set - 1, rest)
        end
        best[rest] = mine
        return mine
    end
    Solve(all)
    local stacks, rest = {}, all
    while rest > 0 do
        local step = best[rest]
        local members = {}
        for i = 1, n do
            if band(step.set, 2 ^ (i - 1)) ~= 0 then members[#members + 1] = full[i] end
        end
        stacks[#stacks + 1] = { members = members, cols = step.cols, first = members[1] and members[1].packIndex }
        rest = rest - step.set
    end
    return stacks
end

-- Works out state.pack for the rebuild: each sack's columns (LayoutOf reads them) and its spot beside the window
-- (PlaceGroups puts it there). Nil when the Town sacks are not beside a window.
local function PackTown(groups)
    state.pack = nil
    local window, place = DockFrame()
    if not (window and SacksDB.layout == "town") then return end
    -- How tall a column may be: the window's height, or (a setting) down to the bottom of the screen.
    local limit = tonumber(window:GetHeight()) or 0
    if SacksDB.townHeight == "screen" then
        local top, scale, screen = window:GetTop(), window:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if type(top) == "number" and type(scale) == "number" and screen and screen > 0 then limit = top * scale / screen end
    end
    if limit <= 0 then return end
    -- Empty sacks (a setting): fill the room left at the edges, are hidden, or are arranged like the rest.
    local emptyMode = SacksDB.townEmpty or "fill"
    local full, empty, hidden = {}, {}, {}
    for index, group in ipairs(groups) do
        if not IsHidden(group) then
            group.packIndex = index
            local cells = (state.counts[group] or 0) + (BlankMode(group) ~= "NONE" and 1 or 0)
            if cells > 0 or emptyMode == "pack" then
                full[#full + 1] = group
            elseif emptyMode == "hide" then
                hidden[group] = true
            else
                empty[#empty + 1] = group
            end
        end
    end
    -- the sack for what you came to do goes first: top of the first column
    local first = FirstSack(place, full)
    local stacks
    if SacksDB.townOrder == "list" or #full > MOST_ARRANGED then
        stacks = ArrangeInOrder(full, limit)
    else
        stacks = ArrangeFreely(full, limit)
        for _, stack in ipairs(stacks) do
            table.sort(stack.members, function(a, b)
                if a == first or b == first then return a == first end
                return a.packIndex < b.packIndex
            end)
            stack.lead = stack.members[1] == first and 0 or stack.members[1].packIndex
        end
        table.sort(stacks, function(a, b) return a.lead < b.lead end)
    end
    local pack = { cols = {}, spots = {}, hidden = hidden }
    local x, columns = 0, {}
    for _, stack in ipairs(stacks) do
        local y, width = 0, 0
        for _, group in ipairs(stack.members) do
            local w, h = Measure(group, stack.cols)
            pack.cols[group] = stack.cols
            pack.spots[group] = { x = x, y = y }
            y = y + h + SLOT_GAP
            width = math.max(width, w)
        end
        columns[#columns + 1] = { x = x, y = y, width = width }
        x = x + width + SLOT_GAP
    end
    -- Empty sacks fill the room left at the bottom of the columns, the outermost column first; what doesn't fit starts a
    -- column of its own at the far edge.
    for _, group in ipairs(empty) do
        local w, h = Measure(group, 1)
        pack.cols[group] = 1
        local spot
        for i = #columns, 1, -1 do
            local column = columns[i]
            if column.y + h <= limit then
                spot = column
                break
            end
        end
        if not spot then
            spot = { x = x, y = 0, width = w }
            columns[#columns + 1] = spot
            x = x + w + SLOT_GAP
        end
        pack.spots[group] = { x = spot.x, y = spot.y }
        spot.y = spot.y + h + SLOT_GAP
        spot.width = math.max(spot.width, w)
    end
    state.pack = pack
end
ns.PackTown = PackTown

local function PlaceGroups()
    local groups = AllGroups()
    -- Every anchor is dropped first. A sack that was stacked at a vendor is anchored to another sack, and putting
    -- it back while that stale anchor is still there can make two sacks depend on each other, which the game refuses.
    for _, group in ipairs(groups) do state.frames[group]:ClearAllPoints() end
    local vendor = DockFrame()
    local limit = vendor and tonumber(vendor:GetHeight()) or 0
    local overhang = vendor and Covering(vendor) or 0
    state.coverUsed = overhang
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
        local hidden = IsHidden(group)
        local packed = state.pack and state.pack.spots[group]
        if vendor and packed then
            if not hidden then frame:SetPoint("TOPLEFT", vendor, "TOPRIGHT", PADDING + overhang + packed.x, -packed.y) end
        elseif vendor then
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
    if vendor then ns.UpdateSeams(groups, true) end -- no seams while the sacks are stacked beside a vendor
end

-- Once everything is placed (the sacks, and the free-slots and gold boxes, which sacks can dock to as well): sacks that
-- fall to the bottom settle, sacks that grew into each other are pushed apart, and the seams are drawn. Not at a vendor
-- (the sacks are stacked beside it then). A drop or a setting settles even with the mouse on a sack; what changes
-- in the bags while the sacks hold still never gets here (see BagsChanged in Sacks.lua).
local function Settle()
    if DockFrame() then return end
    local groups = AllGroups()
    local all = {}
    for _, group in ipairs(groups) do all[#all + 1] = group end
    for _, box in ipairs({ SacksDB.widget, SacksDB.money }) do
        if box and state.frames[box] and state.frames[box]:IsShown() then all[#all + 1] = box end
    end
    ApplyGravity(all)
    PushApart(groups)
    ApplyGravity(all) -- a sideways push can leave one hanging, or over a new floor
    ns.UpdateSeams(groups, false)
end

-- In words, for the tooltip of a sack's title: what it is docked to, or what pushed it aside.
local SIDE_WORDS = { RIGHT = "to the right of", LEFT = "to the left of", TOP = "on top of", BOTTOM = "under" }
local function DockWords(group)
    local lines = {}
    local target = DockTarget(group)
    if target then
        lines[#lines + 1] = "Docked " .. (SIDE_WORDS[group.dock.side] or "to") .. " " .. target.name .. ": it follows that sack."
    else
        lines[#lines + 1] = "Not docked: it stays where you put it. Drop it flush against a sack to dock it there."
    end
    local pusher = state.pushedBy and state.pushedBy[group]
    if pusher then lines[#lines + 1] = "Pushed aside by " .. pusher.name .. ", which grew into it. It goes back when there is room." end
    if group.gravity then lines[#lines + 1] = "Falls to the bottom: it rests on the bottom of the screen or on the sack under it." end
    local docked = {}
    for _, other in ipairs(AllGroups()) do
        if other ~= group and DockTarget(other) == group then
            docked[#docked + 1] = other.name .. " (" .. (SIDE_WORDS[other.dock.side] or "beside") .. " it)"
        end
    end
    if #docked > 0 then lines[#lines + 1] = "Docked to it: " .. table.concat(docked, ", ") .. ". They move with it." end
    if target or #docked > 0 then lines[#lines + 1] = "Click the gold seam between two sacks to cut their dock." end
    return lines
end

-- While the mouse is on a sack's title, its docks show as gold lines in the gaps: the one to the sack it follows, and
-- those of the sacks docked to it.
local FACING = { RIGHT = "LEFT", LEFT = "RIGHT", TOP = "BOTTOM", BOTTOM = "TOP" }
local function DockLine(frame, side)
    local line = rawget(frame, "dockLine")
    if not line then
        line = frame:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(1, 0.82, 0, 0.9)
        frame.dockLine = line
    end
    local edge, half = FACING[side], SNAP_GAP / 2
    line:ClearAllPoints()
    if edge == "LEFT" or edge == "RIGHT" then
        local x = edge == "LEFT" and -half or half
        line:SetPoint("TOP", frame, "TOP" .. edge, x, 0)
        line:SetPoint("BOTTOM", frame, "BOTTOM" .. edge, x, 0)
        line:SetWidth(2)
    else
        local y = edge == "BOTTOM" and -half or half
        line:SetPoint("LEFT", frame, edge .. "LEFT", 0, y)
        line:SetPoint("RIGHT", frame, edge .. "RIGHT", 0, y)
        line:SetHeight(2)
    end
    line:Show()
end

local function HideDockLines()
    for _, frame in pairs(state.frames) do
        local line = rawget(frame, "dockLine")
        if line then line:Hide() end
    end
end

-- Each dock has a seam: the gap between the two sacks, which takes the mouse. Hovering it lights it up and says which
-- two sacks it joins; clicking it cuts the dock (the docked sack stays exactly where it is). It reaches a little into
-- both sacks' margins, never over their slots, so it is easy to hit.
local SEAM_REACH = PADDING - 1
local function Seam(frame)
    local seam = rawget(frame, "seam")
    if seam then return seam end
    seam = CreateFrame("Button", nil, frame)
    seam:RegisterForClicks("LeftButtonUp")
    seam.line = seam:CreateTexture(nil, "OVERLAY")
    seam.line:SetColorTexture(1, 0.82, 0, 0.9)
    seam.line:Hide()
    -- a seam whose dock is gone (cut some other way since it was drawn) just goes away
    local function stale(self)
        if self.group and self.group.dock and DockTarget(self.group) == self.target then return false end
        self:Hide()
        GameTooltip:Hide()
        return true
    end
    seam:SetScript("OnEnter", function(self)
        if stale(self) then return end
        self.line:Show()
        local group, target = self.group, self.target
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(group.name .. " is docked " .. (SIDE_WORDS[group.dock.side] or "to") .. " " .. target.name, 1, 0.82, 0)
        GameTooltip:AddLine("It moves with " .. target.name .. ".", 1, 1, 1, true)
        GameTooltip:AddLine("Click to cut: " .. group.name .. " stays exactly where it is.", 0.5, 0.8, 1, true)
        GameTooltip:Show()
    end)
    seam:SetScript("OnLeave", function(self)
        self.line:Hide()
        GameTooltip:Hide()
    end)
    seam:SetScript("OnClick", function(self)
        if stale(self) then return end
        GameTooltip:Hide()
        ns.Undock(self.group)
    end)
    frame.seam = seam
    return seam
end

local function UpdateSeams(groups, off)
    for _, group in ipairs(groups) do
        local frame = state.frames[group]
        local target = not off and DockTarget(group)
        local targetFrame = target and state.frames[target]
        if frame and frame:IsShown() and targetFrame and targetFrame:IsShown() then
            local seam = Seam(frame)
            seam.group, seam.target = group, target
            seam:SetFrameLevel(math.max(frame:GetFrameLevel(), targetFrame:GetFrameLevel()) + 10)
            local edge, half, reach = FACING[group.dock.side], SNAP_GAP / 2, SEAM_REACH + SNAP_GAP / 2
            seam:ClearAllPoints()
            seam.line:ClearAllPoints()
            if edge == "LEFT" or edge == "RIGHT" then
                local x = edge == "LEFT" and -half or half
                seam:SetPoint("TOP", frame, "TOP" .. edge, x, 0)
                seam:SetPoint("BOTTOM", frame, "BOTTOM" .. edge, x, 0)
                seam:SetWidth(2 * reach)
                seam.line:SetPoint("TOP"); seam.line:SetPoint("BOTTOM"); seam.line:SetWidth(2)
            else
                local y = edge == "BOTTOM" and -half or half
                seam:SetPoint("LEFT", frame, edge .. "LEFT", 0, y)
                seam:SetPoint("RIGHT", frame, edge .. "RIGHT", 0, y)
                seam:SetHeight(2 * reach)
                seam.line:SetPoint("LEFT"); seam.line:SetPoint("RIGHT"); seam.line:SetHeight(2)
            end
            seam:Show()
        elseif frame and rawget(frame, "seam") then
            frame.seam:Hide()
        end
    end
end

local function ShowDockLines(group)
    HideDockLines()
    for _, other in ipairs(AllGroups()) do
        local frame = state.frames[other]
        local target = DockTarget(other)
        if frame and frame:IsShown() and target and (other == group or target == group) then DockLine(frame, other.dock.side) end
    end
end


-- The game opens windows side by side: the newest at the left, the ones already open pushed to the right. A vendor opened
-- while the character or professions window is up therefore lands at the left, with that window between it and the free
-- screen. Packs the windows the other way round: the others slide left into the vendor's place, in the order they were in,
-- and the vendor goes after them, so the sacks beside it always have room. The game lays the windows out again whenever
-- one opens or closes; this runs again then.
-- The sacks beside a window move again when what lies over their spot changes (see Covering).
function ns.RecheckCover()
    local window = DockFrame()
    if not window or InCombatLockdown() then return end
    if math.abs(Covering(window) - (state.coverUsed or 0)) > 0.5 then ns.Refresh() end
end

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
ns.ShowDockLines = ShowDockLines
ns.UpdateSeams = UpdateSeams
ns.Settle = Settle

-- Lets a sack go: it stays exactly where it is on screen, now at a spot of its own.
function ns.Undock(group)
    local frame = state.frames[group]
    local box = frame and Rect(frame)
    if box then
        local corner = group.anchor or DEFAULT_ANCHOR
        local at = POINT_FRACTION[corner]
        group.point, group.relPoint, group.relativeTo = corner, "BOTTOMLEFT", nil
        group.x = box.left + at.x * (box.right - box.left)
        group.y = box.bottom + at.y * (box.top - box.bottom)
    end
    group.dock, group.touches = nil, nil
    if state.refresh then state.refresh() end
end
ns.HideDockLines = HideDockLines
ns.DockWords = DockWords
ns.PlaceOne = PlaceOne
