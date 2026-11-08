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

-- What clicking and dragging a slot does. Right click uses the item (and sells it at a vendor); the rest is in the
-- comments below. These are secure attributes and scripts, so a slot is set up once and never rebuilt in combat.
-- Shift-click (and the other modified clicks) on an item: link it into chat or preview it, like the game's bags do,
-- otherwise open the stack splitter. Returns true when the click was used up.
local DIM_ALPHA = 0.65 -- how dark an item that cannot be used on the waiting item is drawn

local function ModifiedClick(button)
    if not button.bag then return false end
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    local link = getLink and getLink(button.bag, button.slot)
    if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return true end
    if not (IsModifiedClick and IsModifiedClick("SPLITSTACK")) or (CursorHasItem and CursorHasItem()) then return false end
    local open = (StackSplitFrame and StackSplitFrame.OpenStackSplitFrame
        and function(...) return StackSplitFrame:OpenStackSplitFrame(...) end) or OpenStackSplitFrame
    local info = Container.GetContainerItemInfo and Container.GetContainerItemInfo(button.bag, button.slot)
    local count = type(info) == "table" and info.stackCount or 0
    if open and count > 1 and not info.isLocked then
        open(count, button, "BOTTOMRIGHT", "TOPRIGHT")
        return true
    end
    return false
end

-- Whether a window you would move items into is open, and whether a right click moves the item into it there (as the
-- game's own bags do: sell, put in the bank, attach to a letter, put in the trade). While one is open, a click never
-- uses or equips the item; where a right click would not move it (the mailbox's inbox, the auction house) it does nothing.
local function shown(name)
    local frame = _G[name]
    return frame and frame.IsShown and frame:IsShown() or false
end
local function MovingWindow()
    if shown("MerchantFrame") or shown("BankFrame") or shown("GuildBankFrame") or shown("TradeFrame") or shown("SendMailFrame") then
        return true, true
    end
    if shown("MailFrame") or shown("AuctionFrame") or shown("AuctionHouseFrame") then return true, false end
    return false, false
end
ns.MovingWindow = MovingWindow

local function SetUpSlotClicks(button)
    -- Right click uses the item; with a vendor, bank, mailbox, trade or auction window open it moves the item there
    -- instead, or does nothing (see MovingWindow). Left click and dragging pick it up, like the game's bags, unless the
    -- sack is set to use items on left click (then only dragging picks up).
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type2", "item")
    -- The secure action normally fires when the mouse goes DOWN, which would use an item the moment you start to drag
    -- it. Fire on release instead, so holding and moving picks the item up and a plain click uses it.
    button:SetAttribute("useOnKeyDown", false)
    button:SetScript("PreClick", function(self, mouse, down)
        local windowOpen, moves = MovingWindow()
        if state.debugClicks then ns.LogClick(self, mouse, down, windowOpen) end
        if mouse == "LeftButton" and self.clickUse and windowOpen and not (InCombatLockdown and InCombatLockdown()) then
            -- A sack set to use items on left click behaves like the game's bags with such a window open: no use, only
            -- pick up.
            self:SetAttribute("type1", nil)
            self.leftOff = true
        end
        -- An item waiting for a target (a crate to fill, for example): clicking a slot hands it that item, as the game's
        -- bags do. Picking the item up instead would cancel the targeting.
        if mouse == "LeftButton" and not down and self.bag and not (InCombatLockdown and InCombatLockdown())
            and SpellCanTargetItem and SpellCanTargetItem() then
            if self.clickUse then
                self:SetAttribute("type1", nil)
                self.leftOff = true
            end
            local use = (C_Container and C_Container.UseContainerItem) or UseContainerItem
            if use then use(self.bag, self.slot) end
            return
        end
        if mouse == "LeftButton" and not down and not (InCombatLockdown and InCombatLockdown()) and ModifiedClick(self) then
            if self.clickUse then   -- a modified click must not also use the item
                self:SetAttribute("type1", nil)
                self.leftOff = true
            end
            return
        end
        if mouse == "LeftButton" and not down and self.bag and (not self.clickUse or self.leftOff) then
            Container.PickupContainerItem(self.bag, self.slot)
        end
        -- The secure "use item" action would equip a bag or a piece of gear even with a vendor, bank or mailbox open. The
        -- game's own bags call UseContainerItem there, which sells, banks, attaches or trades it, so do that: the secure
        -- action is switched off for this click and the move is made once, when the button comes back up. Where a right
        -- click moves nothing (the inbox, the auction house) the click does nothing at all.
        if mouse == "RightButton" and self.bag and windowOpen and not (InCombatLockdown and InCombatLockdown()) then
            self:SetAttribute("type2", nil)
            self.selling = true
            if not down and moves then
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
    -- the stack splitter calls this with the amount chosen
    button.SplitStack = function(self, amount)
        local split = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem
        if split and self.bag then split(self.bag, self.slot, amount) end
    end
    button:SetScript("OnDragStart", function(self)
        if self.bag and not (CursorHasItem and CursorHasItem()) then Container.PickupContainerItem(self.bag, self.slot) end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        if self.bag then Container.PickupContainerItem(self.bag, self.slot) end
    end)
end

-- What a slot is made of, back to front: its colour, the item art, the quest marker, the cooldown sweep, the stack count,
-- the square for special bags, and the glow for a new item.
local function AddSlotLayers(button)
    button.back = button:CreateTexture(nil, "BACKGROUND")
    button.back:SetAllPoints()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.quest = button:CreateTexture(nil, "OVERLAY")
    button.quest:SetAllPoints()
    button.quest:Hide()
    -- The cooldown sweep (and, with a cooldown-text addon, its timer) draws over the icon; the stack count sits on a
    -- frame above it so the sweep does not dim the number.
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetPoint("TOPLEFT", 2, -2)
    button.cooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(false) end
    button.over = CreateFrame("Frame", nil, button)
    button.over:SetAllPoints()
    button.over:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    -- A plain frame laid over the slot ahead of time and kept hidden. In combat a slot whose item is gone cannot have
    -- its use action removed (it is secure), but showing this frame catches the click first, so the game is never
    -- asked to use an empty slot or another item that has moved into it.
    button.dead = CreateFrame("Frame", nil, button)
    button.dead:SetAllPoints()
    button.dead:SetFrameLevel(button.over:GetFrameLevel() + 1)
    button.dead:EnableMouse(true)
    button.dead:Hide()
    button.count = button.over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
    -- A small square in the top corner: green when the item is in a special bag, amber when it fits a special bag
    -- that has room but sits in a normal bag, grey when it fits one that is full.
    -- Over the item art while an item waits for a target (a crate to fill) and this item is not one it can take.
    button.dim = button:CreateTexture(nil, "OVERLAY")
    button.dim:SetAllPoints(button.icon)
    button.dim:SetColorTexture(0, 0, 0, DIM_ALPHA)
    button.dim:Hide()
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetSize(math.max(2, math.floor(ns.SlotSize() / 5)), math.max(2, math.floor(ns.SlotSize() / 5)))
    button.mark:SetPoint("TOPRIGHT", -2, -2)
    button.mark:Hide()
    -- The glow the game's own bags put on an item that arrived since you last looked at it: its art, its colour by
    -- quality, and a slow fade in and out. Hovering the item clears it.
    AddFreshGlow(button, button.over, button.icon)
end

-- The tooltip a slot shows, and the coin cursor at a vendor.
local function SetUpSlotTooltip(button)
    button:SetScript("OnEnter", function(self)
        if self.bag then
            if ns.IsFresh and ns.IsFresh(self.bag, self.slot) then
                ns.ClearFresh(self.bag, self.slot)
                ns.RefreshFresh()
            end
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
end

-- While an item waits for a target (a crate to fill), the game's bags dim what it cannot take. Same here, driven by the
-- game's own answer for each item.
local function TargetingItems()
    return (SpellIsTargeting and SpellIsTargeting() and SpellCanTargetItem and SpellCanTargetItem() and SpellCanTargetItemID) and true or false
end

local function ApplyTargetDim(button, targeting)
    if targeting == nil then targeting = TargetingItems() end
    local dim = false
    if targeting and button.bag and button.itemID then
        local ok, valid = pcall(SpellCanTargetItemID, button.itemID)
        dim = ok and not valid
    end
    if dim then button.dim:Show() else button.dim:Hide() end
end
ns.ApplyTargetDim = ApplyTargetDim

local function UpdateTargetDim()
    local targeting = TargetingItems()
    for _, frame in pairs(state.frames) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button:IsShown() then ApplyTargetDim(button, targeting) end
        end
    end
end
ns.UpdateTargetDim = UpdateTargetDim

local function MakeSlotButton(parent)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(SlotSize(), SlotSize())
    SetUpSlotClicks(button)
    AddSlotLayers(button)
    SetUpSlotTooltip(button)
    return button
end

-- An item is new when the game says so (C_NewItems), exactly as the default bags do, so the two stay in step:
-- hovering an item here clears it there, and hovering it there clears it here (the game tells us when its flags change).
local function IsFresh(bag, slot)
    return C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) and true or false
end
local function ClearFresh(bag, slot)
    if C_NewItems and C_NewItems.RemoveNewItem then pcall(C_NewItems.RemoveNewItem, bag, slot) end
end
ns.IsFresh, ns.ClearFresh = IsFresh, ClearFresh

local function AtlasExists(name)
    if C_Texture and C_Texture.GetAtlasInfo then return C_Texture.GetAtlasInfo(name) ~= nil end
    return false
end

local function RefreshFresh()
    for _, frame in pairs(state.frames or {}) do
        local all = {}
        for _, button in ipairs(rawget(frame, "buttons") or {}) do all[#all + 1] = button end
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
ns.QuestMarker = QuestMarker
ns.TintByQuality = TintByQuality
ns.UpdateCooldown = UpdateCooldown
