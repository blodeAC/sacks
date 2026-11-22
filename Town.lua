-- sacks: Town.lua
-- Two layouts of sacks: Normal, and Town for selling, posting and muling. Each has its own sacks, order, places and
-- looks, and its own New and Other. Whichever is showing is the one in SacksDB.groups and SacksDB.fallback, so every page
-- of the settings window edits the layout on screen; the other waits in SacksDB.otherLayout.
--
-- Town comes on by itself while a vendor, mailbox, auction house or bank window is open (each can be turned off in
-- Settings), and with the Town button or /sacks town.
--
-- Town's starting sacks sort by what Blackthornes Butler says to do with each item: the "Butler says" rule line. That
-- line asks Butler the same way Butler's own tooltip line does, for the exact bag slot, fresh at every rebuild, and the
-- sacks are rebuilt whenever Butler's verdicts change (a hook on its redraw, no polling).
local _, ns = ...
local state = ns.state

---------------------------------------------------------------------------------------------------
-- What Butler says
---------------------------------------------------------------------------------------------------

local function Butler()
    local butler = rawget(_G, "BlackthornesButler")
    if type(butler) == "table" and type(butler.Verdicts) == "table" and type(butler.Bags) == "table" then return butler end
    return nil
end

-- Butler's verdict for the item in a bag slot, as its tooltip line works it out (UI/VerdictTip.lua: Fresh, KeptRow,
-- VerdictTip:Line): Butler's kept record of the slot when nothing in it changed, else a fresh read; the row of Butler's
-- own grouping when that is up to date (it knows which copies an alt's upgrade takes), else Verdicts:Judge. Kept on the
-- item for the rest of this rebuild. Nil when Butler is not loaded, the item is not in a bag, or Butler has no answer.
local function Verdict(item)
    if item.butler ~= nil then return item.butler or nil end
    local verdict
    local butler = Butler()
    if butler and item.bag and item.slot and item.itemID then
        local ok, result = pcall(function()
            local Bags, Verdicts = butler.Bags, butler.Verdicts
            local entry = Bags.ReadSlot(item.bag, item.slot)
            if not (entry and entry.itemID == item.itemID) then return nil end
            local kept = Bags.slots[item.bag .. ":" .. item.slot]
            if kept and kept.key == entry.key then
                entry = kept
            else
                entry.quest = Bags.ReadQuest(item.bag, item.slot, item.itemID)
            end
            Verdicts:ForgetIfOld()
            local cache = Verdicts.groupCache
            if cache and cache.bags == Bags.version and cache.verdicts == Verdicts.version then
                for _, group in ipairs(cache.groups or {}) do
                    for _, row in ipairs(group.rows or {}) do
                        for _, slot in ipairs(row.slots or {}) do
                            if slot == entry then return row.verdict end
                        end
                    end
                end
            end
            return (Verdicts:Judge(entry))
        end)
        if ok and type(result) == "string" then verdict = result end
    end
    item.butler = verdict or false
    return verdict
end
ns.ButlerVerdict = Verdict

-- Butler's verdicts in Butler's own order, with its own names. Used for the rule line's choices.
local VERDICTS = { "craft", "sell", "auction", "disenchant", "mail", "bank", "look", "wait", "keep" }
local function VerdictLabel(verdict)
    local butler = Butler()
    local label = butler and butler.Verdicts.LABELS and butler.Verdicts.LABELS[verdict]
    return type(label) == "string" and label or (verdict:gsub("^%l", string.upper))
end

function ns.ButlerOptions()
    local butler = Butler()
    local order = butler and type(butler.Verdicts.ORDER) == "table" and butler.Verdicts.ORDER or VERDICTS
    local options = {}
    for _, verdict in ipairs(order) do options[#options + 1] = { label = VerdictLabel(verdict), value = verdict } end
    return options
end

-- Whether any sack of the layout showing tests what Butler says (its Takes lines, or a sort step's lines).
local function UsesButler()
    if not SacksDB then return false end
    local function has(rule)
        for _, clause in ipairs(rule or {}) do
            if clause.field == "butler" then return true end
        end
        return false
    end
    for _, group in ipairs(ns.AllGroups()) do
        if has(group.rule) then return true end
        for _, step in ipairs(group.sort or {}) do
            if has(step.rule) then return true end
        end
    end
    return false
end

-- Butler redraws whenever a verdict could have changed (a choice, an item loaded, its bags read again). The sacks follow
-- once that frame is over, however many redraws it held, and only when a sack showing asks Butler anything.
local function ButlerChanged()
    if state.butlerQueued or not UsesButler() then return end
    state.butlerQueued = true
    C_Timer.After(0, function()
        state.butlerQueued = false
        ns.BagsChanged() -- held like any bag change while the mouse is on a sack
    end)
end

local hooked = false
local function HookButler()
    local butler = Butler()
    if hooked or not butler or type(butler.Verdicts.Redraw) ~= "function" then return end
    hooksecurefunc(butler.Verdicts, "Redraw", ButlerChanged)
    hooked = true
end

---------------------------------------------------------------------------------------------------
-- The Town layout
---------------------------------------------------------------------------------------------------

-- Town's starting sacks: one per thing Butler can tell you to do in town, in this order (the first sack an item fits
-- takes it). Look at it and Wait for a price go to Other. Two columns left of the middle of the screen.
local TOWN_VERDICTS = { "sell", "auction", "mail", "disenchant", "bank", "craft", "keep" }
local TOWN_LEFT, TOWN_RIGHT, TOWN_TOP, TOWN_STEP = -450, -200, 300, 120

function ns.TownGroups()
    local groups = { { name = "New", rule = {}, builtin = true, point = "CENTER", x = TOWN_LEFT, y = TOWN_TOP } }
    for index, verdict in ipairs(TOWN_VERDICTS) do
        local column = index % 2 == 1 and TOWN_RIGHT or TOWN_LEFT
        local row = math.floor(index / 2)
        groups[#groups + 1] = { name = VerdictLabel(verdict), rule = { { field = "butler", op = "=", value = verdict } },
            point = "CENTER", x = column, y = TOWN_TOP - row * TOWN_STEP }
    end
    return groups
end

-- What a saved layout needs before it is used: the same upgrades the login gives the one showing (Core.lua).
local function Prepare()
    for _, group in ipairs(SacksDB.groups) do
        group.rule = group.rule or {}
        if ns.IsOldRule(group.rule) then group.rule = ns.ToConditions(group.rule) end
        ns.UpgradeSort(group)
        ns.UpgradeTextOps(group)
    end
    ns.EnsureCombatSack()
    ns.EnsureFallback()
    ns.UpgradeSort(SacksDB.fallback)
    ns.UpgradeTextOps(SacksDB.fallback)
end

local function Showing()
    return SacksDB.layout == "town" and "town" or "normal"
end

-- Puts a layout on screen: the sacks showing are hidden and put away, the other comes out (made from Town's starting
-- sacks the first time).
local function SwapTo(layout)
    if Showing() == layout then return end
    for _, group in ipairs(ns.AllGroups()) do
        ns.HideRemoved(group)
        -- its slots stop counting as items on screen (Combat.lua looks at every sack frame, hidden or not)
        local frame = state.frames[group]
        for _, slot in ipairs(frame and rawget(frame, "buttons") or {}) do slot.bag = nil end
    end
    local away = { groups = SacksDB.groups, fallback = SacksDB.fallback }
    local stored = SacksDB.otherLayout
    SacksDB.layout = layout
    if stored and stored.groups then
        SacksDB.groups, SacksDB.fallback = stored.groups, stored.fallback
    else
        SacksDB.groups = ns.DefaultGroups() -- Town's, now that the layout says town
        -- Other under the left column, below the last starting sack there
        SacksDB.fallback = { name = ns.OTHER_NAME, point = "CENTER", x = TOWN_LEFT, y = TOWN_TOP - 4 * TOWN_STEP }
    end
    SacksDB.otherLayout = away
    Prepare()
end

---------------------------------------------------------------------------------------------------
-- When Town shows
---------------------------------------------------------------------------------------------------

-- The windows that bring Town out, each one a setting (all on unless turned off).
local PLACES = {
    { key = "vendor", label = "a vendor", open = "MERCHANT_SHOW", close = "MERCHANT_CLOSED", frame = "MerchantFrame" },
    { key = "mail", label = "a mailbox", open = "MAIL_SHOW", close = "MAIL_CLOSED", frame = "MailFrame" },
    { key = "auction", label = "the auction house", open = "AUCTION_HOUSE_SHOW", close = "AUCTION_HOUSE_CLOSED",
        frame = "AuctionHouseFrame" },
    { key = "bank", label = "the bank", open = "BANKFRAME_OPENED", close = "BANKFRAME_CLOSED", frame = "BankFrame" },
}
ns.TOWN_PLACES = PLACES

function ns.TownAt(key)
    return not (SacksDB.townAt and SacksDB.townAt[key] == false)
end

function ns.SetTownAt(key, on)
    SacksDB.townAt = SacksDB.townAt or {}
    SacksDB.townAt[key] = on and true or false
    ns.ApplyLayout()
end

state.open = {}       -- [place key] = true while its window is open
state.override = nil  -- "town" or "normal" from the button or /sacks town, else nil

-- The layout that should show: the button's choice, else Town while a window it is on for is open.
local function Wanted()
    if state.override then return state.override end
    for _, place in ipairs(PLACES) do
        if state.open[place.key] and ns.TownAt(place.key) then return "town" end
    end
    return "normal"
end

local UpdateButton -- below

-- Shows the layout that should show. The sacks are hidden and shown as a whole, which the game does not allow in combat:
-- then it happens when combat ends.
function ns.ApplyLayout()
    if not (SacksDB and SacksDB.groups) then return end
    if InCombatLockdown() then
        state.layoutPending = true
        return
    end
    state.layoutPending = false
    local layout = Wanted()
    if Showing() ~= layout then
        SwapTo(layout)
        ns.Refresh()
    end
    UpdateButton()
end

-- The button and /sacks town: show the other layout. Town chosen this way stays until you choose Normal. Normal chosen
-- while a window has Town out lasts until that window closes.
function ns.ToggleTown()
    if not SacksDB then return end
    ns.ForceLayout(Showing() == "town" and "normal" or "town")
end

function ns.ForceLayout(layout)
    if not SacksDB then return end
    state.override = layout
    ns.ApplyLayout()
    if InCombatLockdown() then ns.Say("the sacks change to " .. (layout == "town" and "Town" or "Normal") .. " when combat ends") end
end

-- The Town sacks line up beside the mailbox and auction house windows too (Placement.lua: DockFrame), so those windows
-- opening or closing rebuild the sacks even when the layout stays the same. Once the frame is over: the auction house
-- window is only made when it first opens.
local function Rearrange(place)
    if place.key ~= "mail" and place.key ~= "auction" then return end -- the vendor and bank rebuild on their own (Core.lua)
    C_Timer.After(0, function()
        if Showing() == "town" and not InCombatLockdown() then ns.Refresh() end
    end)
end

-- A place closing: its close event, or its window going away. Some ways of leaving don't send the close event (the
-- mailbox closed by opening the game's settings), so the window hiding counts too; whichever comes first does it.
local function Closed(place)
    if not state.open[place.key] then return end -- already closed (the event and the window both say so)
    state.open[place.key] = nil
    -- the vendor and bank flags the sacks line up by (Core.lua) go with it, if their close event never came
    local stale = (place.key == "vendor" and state.vendor) or (place.key == "bank" and state.bank)
    if place.key == "vendor" then state.vendor = false end
    if place.key == "bank" then state.bank = false end
    if state.override == "normal" then state.override = nil end
    local before = Showing()
    ns.ApplyLayout()
    if stale and Showing() == before and not InCombatLockdown() then ns.Refresh() end
    Rearrange(place)
end

-- Watches a place's window for going away. Only the window itself being hidden counts: hiding the whole interface
-- (Alt+Z) hides it from view but leaves it shown, and the place is still open. The auction house window is only made
-- when it first opens, so this runs again whenever a place opens.
local watched = {}
local function Watch(place)
    local window = rawget(_G, place.frame)
    if watched[place.key] or type(window) ~= "table" or not window.HookScript then return end
    watched[place.key] = true
    window:HookScript("OnHide", function(self)
        if not self:IsShown() then Closed(place) end
    end)
end

for _, place in ipairs(PLACES) do
    ns.OnEvent(place.open, function()
        state.open[place.key] = true
        ns.ApplyLayout()
        Rearrange(place)
        Watch(place)
        C_Timer.After(0, function() Watch(place) end)
    end)
    ns.OnEvent(place.close, function() Closed(place) end)
end

ns.OnEvent("PLAYER_REGEN_ENABLED", function()
    if state.layoutPending then ns.ApplyLayout() end
end)

-- After the login has set the saved sacks up (Core.lua): back to Normal if the last session ended in Town, and the hook
-- on Butler.
ns.OnEvent("PLAYER_ENTERING_WORLD", function()
    HookButler()
    ns.ApplyLayout()
end)

---------------------------------------------------------------------------------------------------
-- The Town button: a small button of its own to put anywhere. Click: the other layout. Drag: move it.
---------------------------------------------------------------------------------------------------

local BUTTON_START = { point = "CENTER", x = 0, y = -340 }
local ON_TEXT, OFF_TEXT = "Town: on", "Town: off"

local function ButtonPlace()
    SacksDB.townButton = SacksDB.townButton or { shown = true, point = BUTTON_START.point, x = BUTTON_START.x, y = BUTTON_START.y }
    return SacksDB.townButton
end
ns.TownButtonPlace = ButtonPlace

local button
local function MakeButton()
    local frame = CreateFrame("Button", "SacksTownButton", UIParent, "UIPanelButtonTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    frame:SetSize(ns.ButtonWidth({ ON_TEXT, OFF_TEXT }), ns.BUTTON_HEIGHT)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnClick", function() ns.ToggleTown() end)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local place = ButtonPlace()
        local point, _, _, x, y = self:GetPoint()
        place.point, place.x, place.y = point, x, y
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Showing() == "town" and "Town sacks are showing" or "Normal sacks are showing")
        GameTooltip:AddLine("Click for the other layout. Town chosen here stays until you click again; Normal chosen while a "
            .. "vendor, mailbox, auction house or bank has Town out lasts until that window closes.", 1, 1, 1, true)
        GameTooltip:AddLine("Drag to move it. Settings page: which windows bring Town out, hide this button.", 0.5, 0.8, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

UpdateButton = function()
    if not SacksDB then return end
    local place = ButtonPlace()
    if not place.shown then
        if button then button:Hide() end
        return
    end
    if not button then
        button = MakeButton()
        button:SetPoint(place.point, UIParent, place.point, place.x, place.y)
    end
    local town = Showing() == "town"
    button:SetText(town and ON_TEXT or OFF_TEXT)
    if town then button:LockHighlight() else button:UnlockHighlight() end
    button:Show()
end
ns.UpdateTownButton = UpdateButton

function ns.ResetTownButton()
    local place = ButtonPlace()
    place.point, place.x, place.y = BUTTON_START.point, BUTTON_START.x, BUTTON_START.y
    if button then
        button:ClearAllPoints()
        button:SetPoint(place.point, UIParent, place.point, place.x, place.y)
    end
end

function ns.ShowingLayout() return Showing() end
