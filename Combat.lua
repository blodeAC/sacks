-- sacks: Combat.lua
local _, ns = ...
local AddFreshGlow, AllGroups, COLOR, ExpandTitle = ns.AddFreshGlow, ns.AllGroups, ns.COLOR, ns.ExpandTitle
local GridDimensions, GridSize, Matches, PADDING = ns.GridDimensions, ns.GridSize, ns.Matches, ns.PADDING
local PlaceInGrid, QuestMarker, ReadBags, TintByQuality = ns.PlaceInGrid, ns.QuestMarker, ns.ReadBags, ns.TintByQuality
local state = ns.state

-- While the sacks hold still under the mouse (nothing may move), or in combat in a sack that is frozen (see
-- FrozenGroups in Placement.lua), a new item has no slot of its own yet. It gets one of the game's bag buttons in the next
-- cell of its sack's grid, where its slot will be: nothing already on screen moves, and right click uses it at once. The
-- cells go on in the direction the sack grows; the free-slots box (a plain frame) steps aside.
local function MakeGhost(frame)
    return ns.MakeSlotButton(frame)
end

local function ShowGhosts(group, frame, pending)
    local geom = rawget(frame, "geom")
    frame.ghosts = rawget(frame, "ghosts") or {}
    for _, ghost in ipairs(frame.ghosts) do ns.ParkSlot(ghost) end -- pending items show nowhere else
    frame.ghosts = {}
    if not geom or geom.reading then return end -- docked at a vendor or bank: the title marker says it
    local size = geom.size
    if group.builtin then
        -- New has no real slots, so unlike the other sacks it can be resized right now to fit what it holds.
        local columns, rows = GridDimensions(geom.layout, #pending)
        geom.width, geom.height = GridSize(columns, rows, size, geom.topSpace, geom.bottomSpace)
        frame:SetSize(geom.width, geom.height)
        frame.title:SetWidth(math.max(12, geom.width - PADDING * 2))
        local ok, text = pcall(ExpandTitle, group, pending, 0, 0)
        if ok and text and geom.layout.title ~= "NONE" then frame.title:SetText(text) end
        if #pending > 0 then frame:Show() elseif not group.always then frame:Hide() end
    end
    local why = InCombatLockdown() and "Arrived during combat: it takes its place in the sack (and left click uses it, in a sack set to) once combat ends."
        or "New: it takes its place in its sack once the mouse leaves the sacks."
    -- The new item's own slot button (see SlotButton in Slots.lua). In combat it stays where it is (the frozen sack
    -- can't take it in) and is only pinned over the sack's next cell; otherwise it moves into the sack.
    local shown, pictures = 0, 0
    frame.ghostPictures = rawget(frame, "ghostPictures") or {}
    for _, picture in ipairs(frame.ghostPictures) do picture:Hide() end
    for _, item in ipairs(pending) do
        local ghost = ns.SlotButton(item.bag, item.slot)
        if ghost and ghost:IsShown() and ghost.sack ~= ns.SlotPool and ghost.sack ~= frame then
            -- its slot's button still stands in another sack, covering what left that slot (it can't be in two places):
            -- a picture of the item, covered, until the sacks catch up
            pictures = pictures + 1
            local picture = frame.ghostPictures[pictures] or ns.MakeSlotButton(frame)
            frame.ghostPictures[pictures] = picture
            shown = shown + 1
            ns.SizeSlot(picture, size)
            picture:SetFrameLevel(frame:GetFrameLevel() + 2)
            picture.itemID, picture.group = item.itemID, group
            ns.DrawPlaceholder(picture, item)
            picture.placeholder = true
            PlaceInGrid(picture, geom.shift + geom.count + shown, geom)
            picture:Show()
        elseif ghost then
            shown = shown + 1
            frame.ghosts[shown] = ghost
            local inside = not InCombatLockdown()
            if inside then ns.MoveSlot(ghost, frame) end
            ns.SizeSlot(ghost, size)
            ghost:SetFrameStrata(frame:GetFrameStrata())
            ghost:SetFrameLevel(frame:GetFrameLevel() + 2)
            ghost.claimGen = state.generation
            ghost.bag, ghost.slot, ghost.itemID, ghost.quality = item.bag, item.slot, item.itemID, item.quality
            ghost.placeholder, ghost.gone, ghost.group = nil, false, group
            ghost.dead:Hide()
            ns.DrawSlot(ghost)
            ghost.where, ghost.whereColor = why, COLOR.GREY
            PlaceInGrid(ghost, geom.shift + geom.count + shown, geom, not inside and frame or nil)
            ghost:Show()
        end
    end
    if geom.blankMode == "LAST" then PlaceInGrid(frame.blank, geom.count + #pending + 1, geom) end
end

-- In combat the sacks cannot be rebuilt, so tell the truth about what they are missing: each sack that would
-- gain or lose a slot gets an orange "+N -M" at its title, and its title tooltip lists the items.
local function MarkStale(items)
    local shown = {}
    for _, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button.bag and button:IsShown() and not button.gone then
                shown[button.bag .. ":" .. button.slot .. ":" .. tostring(button.itemID)] = true
            end
        end
    end
    local news, gone, pend = {}, {}, {}
    for _, item in ipairs(items or (ReadBags())) do
        if not shown[item.bag .. ":" .. item.slot .. ":" .. tostring(item.itemID)] then
            for _, group in ipairs(AllGroups()) do
                if group.builtin or ((group.fixed or #group.rule > 0) and Matches(group.rule, item)) then
                    news[group] = news[group] or {}
                    pend[group] = pend[group] or {}
                    table.insert(pend[group], item)
                    table.insert(news[group], "+ " .. tostring(item.name) .. (item.count and item.count > 1 and " x" .. item.count or ""))
                    break
                end
            end
        end
    end
    for group, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button.bag and button:IsShown() and button.gone then
                gone[group] = gone[group] or {}
                local seen = SacksDB.seen and SacksDB.seen[button.itemID]
                table.insert(gone[group], "- " .. tostring(seen and seen.name or button.itemID) .. " (used up or moved)")
            end
        end
    end
    state.stale = {}
    for group, frame in pairs(state.frames or {}) do
        local mark = rawget(frame, "stale") -- the free-slots widget is in this list too and has none
        local added, removed = news[group] or {}, gone[group] or {}
        if rawget(frame, "stale") then ShowGhosts(group, frame, pend[group] or {}) end -- the new ones are drawn, so they need no count
        if not mark then
            -- nothing to write on
        elseif #added + #removed > 0 then
            local lines = {}
            for _, line in ipairs(added) do lines[#lines + 1] = line end
            for _, line in ipairs(removed) do lines[#lines + 1] = line end
            state.stale[group] = lines
            mark:SetText(#removed > 0 and ("-" .. #removed) or "")
        else
            mark:SetText("")
        end
    end
end
ns.MarkStale = MarkStale
ns.ShowGhosts = ShowGhosts

---------------------------------------------------------------------------------------------------
-- New items
---------------------------------------------------------------------------------------------------
