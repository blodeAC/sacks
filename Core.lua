-- sacks: Core.lua
local _, ns = ...
local UpgradeSort = ns.UpgradeSort
local DefaultGroups, EnsureFallback, HideOwnBags, HookOwnBags, IsOldRule, MakeIcon = ns.DefaultGroups, ns.EnsureFallback, ns.HideOwnBags, ns.HookOwnBags, ns.IsOldRule, ns.MakeIcon
local Refresh, ToConditions, WrapUserBagToggles, state = ns.Refresh, ns.ToConditions, ns.WrapUserBagToggles, ns.state

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Error log: errors raised by this add-on are remembered (also across reloads), for /sacks errors
---------------------------------------------------------------------------------------------------

local MAX_ERRORS = 20
local function RecordError(message)
    if not SacksDB then return end
    SacksDB.errors = SacksDB.errors or {}
    local list = SacksDB.errors
    local text = tostring(message):sub(1, 700)
    local last = list[#list]
    if last and last.text == text then
        last.count = (last.count or 1) + 1
        return
    end
    list[#list + 1] = { text = text, count = 1, time = date and date("%H:%M:%S") or "", combat = InCombatLockdown and InCombatLockdown() and true or false,
        stack = debugstack and tostring(debugstack(3, 10, 0)):sub(1, 900) or "" }
    while #list > MAX_ERRORS do table.remove(list, 1) end
end
if geterrorhandler and seterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(message)
        if type(message) == "string" and message:find("AddOns[/\\]sacks[/\\]") then pcall(RecordError, message) end
        if previous then return previous(message) end
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_COOLDOWN", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, addon, action)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- The game's "blocked from an action only available to the Blizzard UI" popup: remember which function it was
        -- and what was open, for /sacks errors.
        if addon == "sacks" then
            pcall(RecordError, string.format("%s: %s (bank=%s vendor=%s combat=%s)", event, tostring(action), tostring(state.bank),
                tostring(state.vendor), tostring(InCombatLockdown and InCombatLockdown() or false)))
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        SacksDB = SacksDB or {}
        SacksDB.groups = SacksDB.groups or DefaultGroups()
        for _, group in ipairs(SacksDB.groups) do
            group.rule = group.rule or {}
            if IsOldRule(group.rule) then group.rule = ToConditions(group.rule) end
            UpgradeSort(group)
        end
        EnsureFallback()
        UpgradeSort(SacksDB.fallback)
        MakeIcon()
        HookOwnBags()
        WrapUserBagToggles()
        HideOwnBags()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        ns.UpdateCooldowns()
        return
    elseif event == "BANKFRAME_OPENED" then
        state.bank = true
        -- The bank's tabs are not laid out yet when this event arrives; place the sacks once more right after.
        if C_Timer and C_Timer.After then C_Timer.After(0, function() if state.bank then Refresh() end end) end
    elseif event == "BANKFRAME_CLOSED" then
        state.bank = false
    elseif event == "MERCHANT_SHOW" then
        state.vendor = true
    elseif event == "MERCHANT_CLOSED" then
        state.vendor = false
    elseif event == "PLAYER_REGEN_ENABLED" and not state.pending then
        return
    end
    Refresh()
end)
