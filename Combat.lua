-- sacks: Combat.lua
local _, ns = ...
local AddFreshGlow, AllGroups, COLOR, ExpandTitle = ns.AddFreshGlow, ns.AllGroups, ns.COLOR, ns.ExpandTitle
local GridDimensions, GridSize, Matches, PADDING = ns.GridDimensions, ns.GridSize, ns.Matches, ns.PADDING
local PlaceInGrid, QuestMarker, ReadBags, TintByQuality = ns.PlaceInGrid, ns.QuestMarker, ns.ReadBags, ns.TintByQuality
local state = ns.state

-- In combat, or while the sacks hold still under the mouse, a new item has no slot to go in (in combat the secure slots
-- cannot be added or moved; while held, nothing may move). It is drawn here as a plain,
-- non-secure icon in the next cell of its sack's grid, where its slot will be after combat. The cells go on in the
-- direction the sack grows, so nothing already on screen has to move; the free-slots box (a plain frame) steps aside.
local function MakeGhost(frame)
    local ghost = CreateFrame("Frame", nil, frame)
    ghost:EnableMouse(true)
    ghost.back = ghost:CreateTexture(nil, "BACKGROUND")
    ghost.back:SetAllPoints()
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetPoint("TOPLEFT", 2, -2)
    ghost.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    ghost.quest = ghost:CreateTexture(nil, "OVERLAY")
    ghost.quest:SetAllPoints()
    ghost.quest:Hide()
    ghost.over = CreateFrame("Frame", nil, ghost)
    ghost.over:SetAllPoints()
    ghost.over:SetFrameLevel(ghost:GetFrameLevel() + 2)
    ghost.count = ghost.over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ghost.count:SetPoint("BOTTOMRIGHT", -3, 3)
    AddFreshGlow(ghost, ghost.over, ghost.icon)
    ghost:SetScript("OnEnter", function(self)
        if not self.bag then return end
        if ns.IsFresh(self.bag, self.slot) then
            ns.ClearFresh(self.bag, self.slot)
            ns.RefreshFresh()
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.bag, self.slot)
        GameTooltip:AddLine(" ")
        local why = (InCombatLockdown and InCombatLockdown()) and "Arrived during combat: it can be used once combat ends."
            or "New: it goes to its sack, and can be used, once the mouse leaves the sacks."
        GameTooltip:AddLine(why, COLOR.GREY[1], COLOR.GREY[2], COLOR.GREY[3], true)
        GameTooltip:Show()
    end)
    ghost:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ns.LetGo()
    end)
    ghost:HookScript("OnEnter", function() ns.HoldStill() end)
    return ghost
end

local function ShowGhosts(group, frame, pending)
    local geom = rawget(frame, "geom")
    frame.ghosts = rawget(frame, "ghosts") or {}
    for _, ghost in ipairs(frame.ghosts) do ghost:Hide() end
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
    for index, item in ipairs(pending) do
        local ghost = frame.ghosts[index] or MakeGhost(frame)
        frame.ghosts[index] = ghost
        ghost:SetSize(size, size)
        ghost.bag, ghost.slot, ghost.itemID, ghost.quality = item.bag, item.slot, item.itemID, item.quality
        ghost.icon:SetTexture(item.icon)
        QuestMarker(ghost.quest, item)
        TintByQuality(ghost.back, item.quality)
        ghost.count:SetText((item.count or 1) > 1 and item.count or "")
        PlaceInGrid(ghost, geom.shift + geom.count + index, geom)
        ghost:Show()
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

---------------------------------------------------------------------------------------------------
-- New items
---------------------------------------------------------------------------------------------------
