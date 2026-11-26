-- sacks: Slots.lua
local _, ns = ...
local Container, EMPTY_TINT_ALPHA, SLOT_TINT_ALPHA, SlotSize = ns.Container, ns.EMPTY_TINT_ALPHA, ns.SLOT_TINT_ALPHA, ns.SlotSize
local state = ns.state

-- Shows the item's cooldown (potions, hearthstone, trinkets) on its slot, as the game's own bags do.
-- The coloured box behind an item: its quality colour, or a plain dark one when it has none.
local function TintByQuality(texture, quality)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        texture:SetColorTexture(color.r, color.g, color.b, SLOT_TINT_ALPHA)
    else
        texture:SetColorTexture(0, 0, 0, EMPTY_TINT_ALPHA)
    end
end

-- The slow fade in and out of the glow on a new item (see RefreshFresh for what it shows).
local FRESH_PULSE_SECONDS, FRESH_PULSE_LOW = 0.9, 0.25
local function AddFreshGlow(target, parent, icon)
    target.fresh = parent:CreateTexture(nil, "OVERLAY")
    target.fresh:SetPoint("CENTER", icon, "CENTER")
    target.fresh:SetBlendMode("ADD")
    target.fresh:Hide()
    local ok, group = pcall(target.fresh.CreateAnimationGroup, target.fresh)
    if ok and type(group) == "table" then
        local fade = group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(FRESH_PULSE_LOW)
        fade:SetDuration(FRESH_PULSE_SECONDS)
        group:SetLooping("BOUNCE")
        target.freshPulse = group
    end
end

-- The quest marker the game's bags draw over a quest item: a "!" when it starts a quest, a border when a quest wants it.
local function QuestMarker(texture, item)
    local path
    if item.questBang then
        path = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang"
    elseif item.questItem then
        path = TEXTURE_ITEM_QUEST_BORDER or "Interface\\ContainerFrame\\UI-Icon-QuestBorder"
    end
    if path then
        texture:SetTexture(path)
        texture:Show()
    else
        texture:Hide()
    end
end

-- Redraws just the quest markers (no rebuild), for when the quest log changes: accepting a quest makes its "!" go away
-- without touching a bag.
local function RefreshQuestMarks()
    for _, frame in pairs(state.frames or {}) do
        for _, list in ipairs({ rawget(frame, "buttons") or {}, rawget(frame, "ghosts") or {} }) do
            for _, slot in ipairs(list) do
                if rawget(slot, "bag") and slot:IsShown() then
                    local bang, wanted = ns.QuestInfo(slot.bag, slot.slot)
                    QuestMarker(slot.quest, { questBang = bang, questItem = wanted })
                end
            end
        end
    end
end
ns.RefreshQuestMarks = RefreshQuestMarks

-- The spell an item casts when used (remembered once known: it never changes for an item; not remembered while the
-- game has not loaded the item's data yet).
local itemSpell = {}
local function ItemSpellID(itemID)
    if not itemSpell[itemID] then
        local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
        local spellID
        if get then spellID = select(2, get(itemID)) end
        itemSpell[itemID] = spellID
    end
    return itemSpell[itemID]
end

-- The cooldown of the spell an item casts, when it is running and is not just the global cooldown. Its start and
-- duration can be secret values (when the game restricts cooldowns): never compared or added here, so only the
-- never-secret flags decide anything.
local function SpellCooldownOf(itemID)
    local spellID = itemID and ItemSpellID(itemID)
    if not (spellID and C_Spell and C_Spell.GetSpellCooldown) then return end
    local info = C_Spell.GetSpellCooldown(spellID)
    if info and info.isActive and not info.isOnGCD then return info end
end


---------------------------------------------------------------------------------------------------
-- The slots are the game's own bag item buttons (ContainerFrameItemButtonTemplate, the squares in the default bags),
-- each pointed at one bag slot. Everything a click, a drag, a hover or a modified click does is the game's own code:
-- using, selling, banking, attaching to a letter, posting at the auction house, giving an item to a waiting crate,
-- splitting and merging stacks, linking. What a slot shows is drawn by the game's own functions too (quality border,
-- count, quest marker, junk coin, new-item glow, the grey for what a waiting crate can't take, cooldown, locked).
--
-- Which bag and slot a button stands for must be values the game itself wrote: anything sacks writes carries sacks'
-- taint, and the game's click code then refuses to use the item. Two in-game taint logs showed it (Nov 26 2026): the
-- button's own SetBagID from sacks left "Execution tainted by sacks while reading field bagID", and an ID set with
-- SetID from sacks made the slot number tainted ("reading field slotIndex", the slot the game's click built from
-- GetID). So each bag slot gets one button of its own for good (SlotButton), and its bag and slot are set once, by a
-- secure snippet with the numbers written into the snippet itself, the game's own way of running addon code untainted
-- (SecureHandlerExecute). Sacks never changes them again: it only moves the button into whichever sack shows that slot.
-- Sacks must never write a value the game's click code reads; it only adds its own parts on top: the special-bag square,
-- the cover over a slot whose item left, the line in the tooltip saying where the item is, and for sacks that use items
-- on left click, a secure "use item" layer (see UseLayer).
---------------------------------------------------------------------------------------------------

local function IsItemButton(button) return rawget(button, "isItemButton") end

local function AtlasExists(name)
    if C_Texture and C_Texture.GetAtlasInfo then return C_Texture.GetAtlasInfo(name) ~= nil end
    return false
end

ns.GONE_SHADE = 0.4 -- how dark an item you can't use now is drawn: the game's own for an action you can't use (ActionButton.lua)
local GONE_SHADE = ns.GONE_SHADE

-- A slot's cooldown: the game's own (UpdateCooldown on the button, from the bag). On Forever the bag's cooldown can be
-- shorter than the real one: Student Fodder showed 5 minutes while the game's own tooltip and its spell (Trail Snack)
-- said 10 min 21 sec (the spell's cooldown is the 30 minutes the item really has). So while the item's spell has a
-- cooldown running (not just the global one), that is drawn instead. Its numbers can be secret (in a group, in combat):
-- the duration object the game provides for that is handed to the widget as is, never compared.
local function UpdateCooldown(button)
    local cooldown = rawget(button, "Cooldown") or rawget(button, "cooldown")
    if not cooldown then return end
    local hasItem = button.bag and C_Container.HasContainerItem(button.bag, button.slot)
    if IsItemButton(button) then button:UpdateCooldown(hasItem) end
    local spell = hasItem and SpellCooldownOf(button.itemID)
    local durationObject = spell and C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject
        and C_Spell.GetSpellCooldownDuration(ItemSpellID(button.itemID), true)
    local secret = spell and issecretvalue and (issecretvalue(spell.startTime) or issecretvalue(spell.duration))
    if spell and (durationObject or not secret) then
        cooldown:SetDrawEdge(false)
        if durationObject then
            cooldown:SetCooldownFromDurationObject(durationObject)
        else
            cooldown:SetCooldown(spell.startTime, spell.duration, spell.modRate)
        end
        -- as the game's bags do: an item whose cooldown has not started running yet (used this fight) is drawn dark
        local shade = spell.isEnabled and 1 or 0.4
        if IsItemButton(button) then SetItemButtonTextureVertexColor(button, shade, shade, shade) end
    end
end

local function EachSlot(visit)
    for _, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button.bag and button:IsShown() then visit(button) end
        end
    end
end

local function UpdateCooldowns() EachSlot(UpdateCooldown) end
ns.UpdateCooldowns = UpdateCooldowns

-- Draws a slot from what its bag slot holds, the way the game's bags draw theirs (ContainerFrameMixin:UpdateItems in
-- the forever branch of Blizzard's UI), with the game's own functions.
local function DrawSlot(button)
    local bag, slot = button.bag, button.slot
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local texture = info and info.iconFileID
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot) or {}
    ClearItemButtonOverlay(button)
    button:SetHasItem(texture)
    button:SetItemButtonTexture(texture)
    button:SyncAppearanceWithHasItem()
    SetItemButtonQuality(button, info and info.quality, info and info.hyperlink, false, info and info.isBound)
    SetItemButtonCount(button, info and info.stackCount)
    SetItemButtonDesaturated(button, info and info.isLocked)
    button:UpdateQuestItem(quest.isQuestItem, quest.questID, quest.isActive)
    button:UpdateNewItem(info and info.quality)
    button:UpdateJunkItem(info and info.quality, info and info.hasNoValue)
    button:UpdateItemContextMatching()
    button:SetReadable(info and info.isReadable)
    button:SetMatchesSearch(not (info and info.isFiltered))
    UpdateCooldown(button)
    return info
end
ns.DrawSlot = DrawSlot

-- What clicking a slot of a sack that uses items on left click does, on its secure "use item" layer. The right button
-- passes through to the game's slot underneath (sell, bank, letter, auction house, use). A left click uses the item,
-- like an action bar button, except where the game's bags would not use it: something on the cursor, a vendor, bank,
-- mailbox, trade or auction window open, or a modified click. Then the "use" is switched off for that click and the
-- game's slot underneath does what its own left click does. Switching it can only happen out of combat.
local function shown(name)
    local frame = _G[name]
    return frame and frame.IsVisible and frame:IsVisible() or false
end
local function MovingWindow()
    return shown("MerchantFrame") or shown("BankFrame") or shown("GuildBankFrame") or shown("TradeFrame") or shown("MailFrame")
        or shown("AuctionFrame") or shown("AuctionHouseFrame")
end
ns.MovingWindow = MovingWindow

local function UseLayer(button)
    local use = rawget(button, "use")
    if use then return use end
    -- in the sack, not in the button: a secure frame inside a button would freeze the button in combat wherever it goes
    use = CreateFrame("Button", nil, button.sack, "SecureActionButtonTemplate")
    use.isUseLayer = true
    use:SetAllPoints(button)
    use:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    use:RegisterForDrag("LeftButton")
    if use.SetPassThroughButtons then use:SetPassThroughButtons("RightButton") end
    use:SetAttribute("type1", "item")
    -- fire on release, so holding and moving picks the item up instead of using it
    use:SetAttribute("useOnKeyDown", false)
    use:SetScript("PreClick", function(self, mouse, down)
        if InCombatLockdown() then return end
        if state.debugClicks then ns.LogClick(button, mouse, down, MovingWindow()) end
        if SpellCanTargetItem() or SpellCanTargetItemID() then return end -- the "use" hands this item to what waits
        local handOver = GetCursorInfo() ~= nil or MovingWindow() or IsModifiedClick()
        if handOver then
            self:SetAttribute("type1", nil)
            self.handOver = true
        end
    end)
    use:SetScript("PostClick", function(self, mouse, down)
        if not self.handOver or down then return end
        self.handOver = nil
        self:SetAttribute("type1", "item")
        button:OnClick("LeftButton") -- the game's own left click on the slot underneath
    end)
    use:SetScript("OnDragStart", function() button:OnDragStart("LeftButton") end)
    use:SetScript("OnReceiveDrag", function() button:OnReceiveDrag() end)
    use:SetScript("OnEnter", function(self)
        if button.gone or button.placeholder then
            -- its own stack left (combat): the slot uses the item from wherever it is, so show that item
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(button.itemID)
            GameTooltip:Show()
            ns.HoldStill()
        else
            button:GetScript("OnEnter")(button)
        end
    end)
    use:SetScript("OnLeave", function() button:GetScript("OnLeave")(button) end)
    button.use = use
    return use
end

-- Points a slot's "use item" layer at its item (shown only for sacks that use items on left click). Out of combat only:
-- the layer is secure. It names the item, not the bag slot, as an action bar does: whichever stack of it you have is
-- used, so in combat (when the layer can't be changed) the slot keeps working after its own stack runs out.
local function SetUseLayer(button, wanted)
    if InCombatLockdown() then return end
    local use = wanted and UseLayer(button) or rawget(button, "use")
    if not use then return end
    if wanted and button.itemID then
        if use:GetParent() ~= button.sack then use:SetParent(button.sack) end
        use:ClearAllPoints()
        use:SetAllPoints(button)
        use:SetFrameLevel(button:GetFrameLevel() + 2)
        use:SetAttribute("item", "item:" .. button.itemID)
        use:Show()
    else
        use:SetAttribute("item", nil)
        use:Hide()
        -- out of the sack, so the sack holds nothing secure and stays free in combat (see FrozenGroups)
        if ns.SlotPool and use:GetParent() ~= ns.SlotPool then use:SetParent(ns.SlotPool) end
    end
end
ns.SetUseLayer = SetUseLayer

-- The line under the game's tooltip saying where the item really is (and the special-bag hint).
local function AddWhere(button)
    if button.where and GameTooltip:GetOwner() == button then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(button.where, button.whereColor[1], button.whereColor[2], button.whereColor[3], true)
        GameTooltip:Show()
    end
end

-- Pins: ctrl shows a pin on every item; clicking it pins or unpins (the sack's Order page does the same).
local PIN_ATLAS = "waypoint-mappin-minimap-tracked"
local PIN_SIZE = 18 -- on the game's 37 pixel slot (it scales with the slot): half its width
local PIN_FADED = 0.7 -- an unpinned item's pin while Ctrl is held: there to click, a little quieter than a real one

local function IsPinned(button)
    for _, id in ipairs(button.group and button.group.pins or {}) do
        if id == button.itemID then return true end
    end
    return false
end

local function TogglePin(button)
    local group = button.group
    if not (group and button.itemID) then return end
    group.pins = group.pins or {}
    for index, id in ipairs(group.pins) do
        if id == button.itemID then
            table.remove(group.pins, index)
            return ns.Refresh()
        end
    end
    group.pins[#group.pins + 1] = button.itemID
    ns.Refresh()
end

local function UpdatePins()
    local ctrl = IsControlKeyDown()
    for _, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            local pin = rawget(button, "pin")
            if pin then
                local live = button:IsShown() and button.group and button.itemID
                local pinned = live and IsPinned(button)
                if live and (pinned or ctrl) then
                    pin.icon:SetAlpha(pinned and 1 or PIN_FADED)
                    pin.shadow:SetAlpha(pinned and 1 or PIN_FADED)
                    pin:EnableMouse(ctrl)
                    pin:Show()
                else
                    pin:EnableMouse(false)
                    pin:Hide()
                end
            end
        end
    end
end
ns.UpdatePins = UpdatePins

-- A pinned item you have none of (see Placeholder in Sacks.lua): its picture, dark, no count, nothing else drawn.
local function DrawPlaceholder(button, item)
    ClearItemButtonOverlay(button)
    button:SetHasItem(item.icon)
    button:SetItemButtonTexture(item.icon)
    SetItemButtonQuality(button, item.quality)
    SetItemButtonCount(button, nil)
    SetItemButtonDesaturated(button, true)
    SetItemButtonTextureVertexColor(button, GONE_SHADE, GONE_SHADE, GONE_SHADE)
    button.Cooldown:Hide()
    if button.JunkIcon then button.JunkIcon:Hide() end
    if button.IconQuestTexture then button.IconQuestTexture:Hide() end
    if button.NewItemTexture then button.NewItemTexture:Hide() end
    if button.flashAnim then button.flashAnim:Stop() end
    if button.newitemglowAnim then button.newitemglowAnim:Stop() end
    button.dead:Show()
end
ns.DrawPlaceholder = DrawPlaceholder

local function MakeSlotButton(parent)
    local button = CreateFrame("ItemButton", nil, parent, "ContainerFrameItemButtonTemplate")
    button.isItemButton = true
    button.sack = parent -- the frame it is in: a sack, or the pool while no sack shows it
    button:ClearAllPoints() -- the template brings its own corner anchor
    button.baseSize = button:GetWidth() -- the game's slot size; sacks scale it to theirs
    button:SetFrameLevel(parent:GetFrameLevel() + 2)
    -- A small square in the top corner: green when the item is in a special bag, amber when it fits a special bag
    -- that has room but sits in a normal bag, grey when it fits one that is full.
    button.mark = button:CreateTexture(nil, "OVERLAY", nil, 7)
    local markSize = math.max(2, math.floor(button.baseSize / 5))
    button.mark:SetSize(markSize, markSize)
    button.mark:SetPoint("TOPRIGHT", -2, -2)
    button.mark:Hide()
    -- A plain frame over the slot, kept hidden: shown over a slot whose item left while it can't be redrawn (in combat,
    -- or while the sacks hold still), so a click there never reaches whatever its bag slot holds now.
    button.dead = CreateFrame("Frame", nil, button)
    button.dead:SetAllPoints()
    -- under the "use item" layer (see UseLayer), which keeps working by item: a left click still uses the item from
    -- another stack, a right click (which the layer passes through) stops here
    button.dead:SetFrameLevel(button:GetFrameLevel() + 1)
    button.dead:EnableMouse(true)
    button.dead:Hide()
    -- a pinned item you have none of shows its own tooltip on the cover
    button.dead:SetScript("OnEnter", function(self)
        if not button.placeholder then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(button.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Pinned: you have none, so its place waits for it.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
        ns.HoldStill()
    end)
    button.dead:SetScript("OnLeave", function() GameTooltip:Hide(); ns.LetGo() end)
    -- The pin: a mark in the top left corner of a pinned item, always; while Ctrl is held, on every item, to click
    -- (see UpdatePins).
    local pin = CreateFrame("Button", nil, button)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetPoint("TOPLEFT", -2, 2)
    pin:SetFrameLevel(button:GetFrameLevel() + 6)
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints()
    -- a black copy a pixel down and right, so it stands out on any icon
    pin.shadow = pin:CreateTexture(nil, "ARTWORK")
    pin.shadow:SetPoint("TOPLEFT", 1, -1)
    pin.shadow:SetPoint("BOTTOMRIGHT", 1, -1)
    if AtlasExists(PIN_ATLAS) then
        pin.icon:SetAtlas(PIN_ATLAS)
        pin.shadow:SetAtlas(PIN_ATLAS)
        pin.shadow:SetVertexColor(0, 0, 0, 1)
    else
        pin.icon:SetColorTexture(1, 0.82, 0, 1)
    end
    pin:EnableMouse(false)
    pin:Hide()
    pin:SetScript("OnClick", function() TogglePin(button) end)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(IsPinned(button) and "Unpin" or "Pin")
        GameTooltip:AddLine("A pinned item goes first in its sack and keeps its place, even when you have none.", 1, 1, 1, true)
        GameTooltip:Show()
        ns.HoldStill()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide(); ns.LetGo() end)
    button.pin = pin
    -- the tooltip: the game's own, plus where the item is; again whenever the game refreshes it
    button:HookScript("OnEnter", AddWhere)
    local refresh = button.UpdateTooltip
    button.UpdateTooltip = function(self)
        refresh(self)
        AddWhere(self)
    end
    -- the sacks hold still while the mouse is on them
    button:HookScript("OnEnter", function() ns.HoldStill() end)
    button:HookScript("OnLeave", function() ns.LetGo() end)
    -- /sacks clicks: what each click was (after the game's own click has run)
    button:HookScript("OnClick", function(self, mouse) if state.debugClicks then ns.LogClick(self, mouse, false, MovingWindow()) end end)
    return button
end

-- Sets the slot to a size: the game's button scaled, so all its parts keep their proportions.
local function SizeSlot(button, size)
    if IsItemButton(button) then
        button:SetScale(size / button.baseSize)
    else
        button:SetSize(size, size)
    end
end
ns.SizeSlot = SizeSlot

-- Redraws just the quest markers (no rebuild), for when the quest log changes: accepting a quest makes its "!" go away
-- without touching a bag.
local function RefreshQuestMarks()
    for _, frame in pairs(state.frames or {}) do
        for _, slot in ipairs(rawget(frame, "buttons") or {}) do
            if slot.bag and slot:IsShown() and not slot.gone then
                local quest = C_Container.GetContainerItemQuestInfo(slot.bag, slot.slot) or {}
                slot:UpdateQuestItem(quest.isQuestItem, quest.questID, quest.isActive)
            end
        end
        for _, ghost in ipairs(rawget(frame, "ghosts") or {}) do
            if rawget(ghost, "bag") and ghost:IsShown() then
                local quest = C_Container.GetContainerItemQuestInfo(ghost.bag, ghost.slot) or {}
                ghost:UpdateQuestItem(quest.isQuestItem, quest.questID, quest.isActive)
            end
        end
    end
end
ns.RefreshQuestMarks = RefreshQuestMarks

-- While something waits for an item target (a crate to fill, a whetstone, an enchant), the game's own question decides
-- which slots grey: the button asks it itself.
local function UpdateTargetDim()
    EachSlot(function(button) if not button.gone then button:UpdateItemContextMatching() end end)
end
ns.UpdateTargetDim = UpdateTargetDim

-- The game's bag search (its search box, C_Container.SetItemSearch) dims what doesn't match, here as in its bags.
local function UpdateSearch()
    EachSlot(function(button)
        local info = C_Container.GetContainerItemInfo(button.bag, button.slot)
        button:SetMatchesSearch(not (info and info.isFiltered))
    end)
end
ns.UpdateSearch = UpdateSearch

-- An item that is locked (on the cursor, in a trade, on a letter, being split) is drawn grey, as in the game's bags.
local function UpdateLocked(bag, slot)
    EachSlot(function(button)
        if not button.gone and (bag == nil or (button.bag == bag and button.slot == slot)) then
            local info = C_Container.GetContainerItemInfo(button.bag, button.slot)
            SetItemButtonDesaturated(button, info and info.isLocked)
        end
    end)
end
ns.UpdateLocked = UpdateLocked

-- An item is new when the game says so (C_NewItems), exactly as the default bags do, so the two stay in step:
-- hovering an item here clears it there, and hovering it there clears it here (the game tells us when its flags change).
local function IsFresh(bag, slot)
    return C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) and true or false
end
local function ClearFresh(bag, slot)
    if C_NewItems and C_NewItems.RemoveNewItem then pcall(C_NewItems.RemoveNewItem, bag, slot) end
end
ns.IsFresh, ns.ClearFresh = IsFresh, ClearFresh


local function RefreshFresh()
    for _, frame in pairs(state.frames or {}) do
        local all = {}
        -- the slots are the game's buttons, which draw the glow themselves
        for _, list in ipairs({ rawget(frame, "buttons") or {}, rawget(frame, "ghosts") or {} }) do
            for _, button in ipairs(list) do
                if button.bag and button:IsShown() and not button.gone then button:UpdateNewItem(button.quality) end
            end
        end
        for _, ghost in ipairs(rawget(frame, "ghosts") or {}) do if ghost:IsShown() then all[#all + 1] = ghost end end
        for _, button in ipairs(all) do
            local glow = rawget(button, "fresh")
            if glow then
                if rawget(button, "bag") and not rawget(button, "gone") and IsFresh(button.bag, button.slot) then
                    -- the same texture the default bags use for this quality, when this client has it
                    local named = NEW_ITEM_ATLAS_BY_QUALITY and NEW_ITEM_ATLAS_BY_QUALITY[button.quality]
                    local atlas = (named and AtlasExists(named) and named) or (AtlasExists("bags-glow-white") and "bags-glow-white") or nil
                    if atlas then
                        glow:SetAtlas(atlas, true)
                        glow:SetVertexColor(1, 1, 1)
                    else
                        -- no such art here: a plain white edge glow from a texture every client has
                        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                        glow:SetSize(SlotSize() * 1.8, SlotSize() * 1.8)
                    end
                    glow:Show()
                    if button.freshPulse and not button.freshPulse:IsPlaying() then button.freshPulse:Play() end
                else
                    glow:Hide()
                    if button.freshPulse then button.freshPulse:Stop() end
                end
            end
        end
    end
end
ns.RefreshFresh = RefreshFresh

ns.AddFreshGlow = AddFreshGlow
ns.MakeSlotButton = MakeSlotButton

-- Where a slot's button waits while no sack shows it.
local pool = CreateFrame("Frame", "SacksSlotPool", UIParent)
pool:SetSize(1, 1)
pool:SetPoint("TOPLEFT")
pool:Show()
ns.SlotPool = pool
-- The secure frame the snippets run on (SecureHandlerExecute needs one).
local header = CreateFrame("Frame", "SacksSlotHeader", UIParent, "SecureHandlerBaseTemplate")

-- The button of one bag slot: made once, out of combat, its bag and slot set by the game (see the top of this part).
-- In combat a slot that has none yet gets none (nil) until combat ends.
local slotButtons = {}
local function SlotButton(bag, slot)
    local key = bag .. ":" .. slot
    local button = slotButtons[key]
    if button then return button end
    if InCombatLockdown() then return nil end
    button = MakeSlotButton(pool)
    button:Hide()
    SecureHandlerSetFrameRef(header, "slot", button)
    SecureHandlerExecute(header, ("local b = self:GetFrameRef(\"slot\") b:SetAttribute(\"bagid\", %d) b:SetID(%d)"):format(bag, slot))
    button.slotKey = key
    slotButtons[key] = button
    return button
end
ns.SlotButton = SlotButton

-- Every slot of every bag gets its button ahead of time, out of combat: an item looted in combat into a slot never used
-- before still has its own button then (one can't be made in combat).
local function MakeAllSlotButtons()
    if InCombatLockdown() then return end
    for bag = 0, ns.LastBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do SlotButton(bag, slot) end
    end
end
ns.MakeAllSlotButtons = MakeAllSlotButtons

-- Moves a button into a sack (or back to the pool). Out of combat always; in combat too, unless it sits in a frozen sack.
local function MoveSlot(button, frame)
    if button:GetParent() ~= frame then button:SetParent(frame) end
    button.sack = frame
end
ns.MoveSlot = MoveSlot

-- A button no sack shows any more: hidden, back in the pool.
local function ParkSlot(button)
    button:Hide()
    button.dead:Hide()
    SetUseLayer(button, false)
    button.bag, button.placeholder = nil, nil
    if rawget(button, "slotKey") then MoveSlot(button, pool) end
end
ns.ParkSlot = ParkSlot
ns.QuestMarker = QuestMarker
ns.TintByQuality = TintByQuality
ns.UpdateCooldown = UpdateCooldown
