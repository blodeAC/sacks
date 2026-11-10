-- sacks: Bags.lua
local _, ns = ...
local Container, ItemInfo, ItemInstant, state = ns.Container, ns.ItemInfo, ns.ItemInstant, ns.state

---------------------------------------------------------------------------------------------------
-- Reading the bags
---------------------------------------------------------------------------------------------------

-- One entry per occupied slot: where it is, what it is, and what class the game files it under.
local function BitAnd(a, b)
    if bit and bit.band then return bit.band(a, b) end
    local result, place = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end

-- What the game's own bags mark quest items with: a "!" for one that starts a quest you are not on, a border for one a
-- quest wants. Asked again when the quest log changes, since accepting a quest changes no bag.
local function QuestInfo(bag, slot)
    local questInfo = C_Container and C_Container.GetContainerItemQuestInfo
    if not questInfo then return false, false end
    local ok, quest = pcall(questInfo, bag, slot)
    if not (ok and type(quest) == "table") then return false, false end
    return quest.questID and not quest.isActive and true or false, (quest.isQuestItem or quest.questID) and true or false
end
ns.QuestInfo = QuestInfo

-- The text of an item's tooltip, as one string: what the game's item info leaves out (a drink restores mana, a bandage
-- heals, and so on). Read from the game's tooltip data where it has it, otherwise from a hidden tooltip.
local scanTip
local function ReadTooltip(bag, slot)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and type(data) == "table" then
            for _, line in ipairs(data.lines or {}) do
                if type(line.leftText) == "string" then lines[#lines + 1] = line.leftText end
                if type(line.rightText) == "string" then lines[#lines + 1] = line.rightText end
            end
        end
    elseif CreateFrame then
        pcall(function()
            scanTip = scanTip or CreateFrame("GameTooltip", "SacksScanTooltip", nil, "GameTooltipTemplate")
            scanTip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTip:ClearLines()
            scanTip:SetBagItem(bag, slot)
            local count = scanTip:NumLines()
            if type(count) ~= "number" then return end
            for index = 1, count do
                for _, side in ipairs({ "Left", "Right" }) do
                    local text = _G["SacksScanTooltipText" .. side .. index]
                    local value = text and text:GetText()
                    if type(value) == "string" then lines[#lines + 1] = value end
                end
            end
        end)
    end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

local function ReadSlot(bag, slot)
    local info = Container.GetContainerItemInfo(bag, slot)
    if info == nil then return nil end
    local entry = { bag = bag, slot = slot }
    local _
    if type(info) == "table" then
        entry.link, entry.count, entry.quality, entry.itemID, entry.icon =
            info.hyperlink, info.stackCount, info.quality, info.itemID, info.iconFileID
        entry.bound = info.isBound and 1 or 0
        entry.locked, entry.noValue = info.isLocked and true or false, info.hasNoValue and true or false
    else
        entry.icon, entry.count, _, entry.quality, _, _, entry.link = Container.GetContainerItemInfo(bag, slot)
    end
    local id, _, _, _, icon, classID, subClassID = ItemInstant(entry.link or entry.itemID)
    entry.itemID = entry.itemID or id
    entry.icon = entry.icon or icon
    entry.classID, entry.subClassID = classID, subClassID
    local info = { ItemInfo(entry.link or entry.itemID) }
    entry.name = info[1] or entry.link or tostring(entry.itemID)
    entry.sellPrice = tonumber(info[11]) or 0
    entry.itemLevel, entry.minLevel, entry.stackMax = tonumber(info[4]), tonumber(info[5]), tonumber(info[8])
    entry.equip = (info[9] and info[9] ~= "" and info[9] ~= "INVTYPE_NON_EQUIP_IGNORE") and info[9] or "NONE"
    entry.bindType, entry.reagent = tonumber(info[14]), info[17] and 1 or 0
    entry.bound = entry.bound or 0
    entry.questBang, entry.questItem = ns.QuestInfo(bag, slot)
    entry.quality = entry.quality or 0
    local family = GetItemFamily or (C_Item and C_Item.GetItemFamily)
    entry.family = family and tonumber(family(entry.link or entry.itemID)) or 0
    -- Tooltip text is read once per kind of item and kept (also in the saved list of items seen). If the game hasn't
    -- got the text yet it stays empty and is tried again the next time the bags are read.
    state.tips = state.tips or {}
    local seen = SacksDB and SacksDB.seen and SacksDB.seen[entry.itemID]
    entry.tip = state.tips[entry.itemID] or (seen and seen.tip)
    if not entry.tip then
        entry.tip = ReadTooltip(bag, slot)
        if entry.tip then state.tips[entry.itemID] = entry.tip end
    end
    return entry
end

-- The last bag index: the backpack, the bag slots, and the reagent bag where the client has one.
local function LastBag()
    return (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
end

local function BagName(bag)
    local lookup = Container.GetBagName or GetBagName
    local name = lookup and lookup(bag)
    if name and name ~= "" then return name end
    return bag == 0 and "Backpack" or ("Bag " .. bag)
end

-- Reads every item in every bag. Also returns the free slots in normal bags and in special bags (a mining bag, say),
-- and keeps a per-bag list for the tooltip and the settings window.
local function ReadBags()
    local items, free, special = {}, 0, 0
    state.bags, state.slots, state.freeAll = {}, 0, 0
    local families = {}
    for bag = 0, LastBag() do
        local slots = Container.GetContainerNumSlots(bag) or 0
        local bagFree, bagType = Container.GetContainerNumFreeSlots(bag)
        bagFree = bagFree or 0
        if slots > 0 then
            local isSpecial = (bagType or 0) ~= 0
            state.bags[#state.bags + 1] = { bag = bag, name = BagName(bag), total = slots, free = bagFree, special = isSpecial,
                family = bagType or 0 }
            families[bag] = bagType or 0
            state.slots = state.slots + slots
            state.freeAll = state.freeAll + bagFree
            if isSpecial then special = special + bagFree else free = free + bagFree end
        end
        for slot = 1, slots do
            local entry = ReadSlot(bag, slot)
            if entry then items[#items + 1] = entry end
        end
    end
    -- Where each item really lives. An item that fits a special bag (a mining bag, say) but sits in a normal bag is
    -- flagged, because that wastes a normal slot; "full" means the special bag has no room, so it can't move.
    for _, item in ipairs(items) do
        item.bagName = BagName(item.bag)
        item.inSpecial = (families[item.bag] or 0) ~= 0
        if not item.inSpecial and (item.family or 0) ~= 0 then
            for _, bag in ipairs(state.bags) do
                if bag.special and BitAnd(item.family, bag.family) ~= 0 then
                    item.fitsBag, item.fitsFree = bag.name, bag.free
                    break
                end
            end
        end
    end
    return items, free, special
end

-- shared with the files after this one
ns.BitAnd = BitAnd
ns.LastBag = LastBag
ns.ReadBags = ReadBags
ns.ReadSlot = ReadSlot
