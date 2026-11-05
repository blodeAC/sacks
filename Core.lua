-- sacks: Core.lua
local _, ns = ...
local DefaultGroups, EnsureFallback, HideOwnBags, HookOwnBags, IsOldRule, MakeIcon = ns.DefaultGroups, ns.EnsureFallback, ns.HideOwnBags, ns.HookOwnBags, ns.IsOldRule, ns.MakeIcon
local Refresh, ToConditions, WrapUserBagToggles, state = ns.Refresh, ns.ToConditions, ns.WrapUserBagToggles, ns.state

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        SacksDB = SacksDB or {}
        SacksDB.groups = SacksDB.groups or DefaultGroups()
        for _, group in ipairs(SacksDB.groups) do
            group.rule = group.rule or {}
            if IsOldRule(group.rule) then group.rule = ToConditions(group.rule) end
        end
        EnsureFallback()
        MakeIcon()
        HookOwnBags()
        WrapUserBagToggles()
        HideOwnBags()
    elseif event == "BANKFRAME_OPENED" then
        state.bank = true
        return
    elseif event == "BANKFRAME_CLOSED" then
        state.bank = false
        return
    elseif event == "MERCHANT_SHOW" then
        state.vendor = true
    elseif event == "MERCHANT_CLOSED" then
        state.vendor = false
    elseif event == "PLAYER_REGEN_ENABLED" and not state.pending then
        return
    end
    Refresh()
end)
