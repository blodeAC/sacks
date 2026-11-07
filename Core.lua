-- sacks: Core.lua
local _, ns = ...
local UpgradeSort = ns.UpgradeSort
local DefaultGroups, EnsureFallback, HideOwnBags, HookOwnBags, IsOldRule, MakeIcon = ns.DefaultGroups, ns.EnsureFallback, ns.HideOwnBags, ns.HookOwnBags, ns.IsOldRule, ns.MakeIcon
local Refresh, ToConditions, WrapUserBagToggles, state = ns.Refresh, ns.ToConditions, ns.WrapUserBagToggles, ns.state

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
ns.RecordError = RecordError
if geterrorhandler and seterrorhandler then
    local previous = geterrorhandler()
    seterrorhandler(function(message)
        if type(message) == "string" and message:find("AddOns[/\\]sacks[/\\]") then pcall(RecordError, message) end
        if previous then return previous(message) end
    end)
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

-- The game's "blocked from an action only available to the Blizzard UI" popup: remember which function it was
-- and what was open, for /sacks errors.
local function RecordBlocked(event, addon, action)
    if addon ~= "sacks" then return end
    pcall(RecordError, string.format("%s: %s (bank=%s vendor=%s combat=%s)", event, tostring(action), tostring(state.bank),
        tostring(state.vendor), tostring(InCombatLockdown and InCombatLockdown() or false)))
end
ns.OnEvent("ADDON_ACTION_BLOCKED", RecordBlocked)
ns.OnEvent("ADDON_ACTION_FORBIDDEN", RecordBlocked)

ns.OnEvent("PLAYER_LOGIN", function()
    SacksDB = SacksDB or {}
    -- saved data of features that no longer exist
    SacksDB.fresh, SacksDB.snapshot, SacksDB.snapshot2, SacksDB.tray, SacksDB.trayAlways = nil, nil, nil, nil, nil
    SacksDB.groups = SacksDB.groups or DefaultGroups()
    for _, group in ipairs(SacksDB.groups) do
        group.rule = group.rule or {}
        if IsOldRule(group.rule) then group.rule = ToConditions(group.rule) end
        UpgradeSort(group)
    end
    ns.EnsureCombatSack()
    EnsureFallback()
    UpgradeSort(SacksDB.fallback)
    MakeIcon()
    HookOwnBags()
    WrapUserBagToggles()
    HideOwnBags()
    Refresh()
end)

ns.OnEvent("BAG_UPDATE_DELAYED", Refresh)
ns.OnEvent("BAG_UPDATE_COOLDOWN", function() ns.UpdateCooldowns() end)
-- An item waiting for a target (a crate to fill) starts or stops: dim or restore the slots that cannot take it.
ns.OnEvent("CURRENT_SPELL_CAST_CHANGED", function() ns.UpdateTargetDim() end)

ns.OnEvent("PLAYER_REGEN_ENABLED", function()
    if state.pending then Refresh() end
end)

ns.OnEvent("MERCHANT_SHOW", function() state.vendor = true; Refresh() end)

-- The game lays its windows out again whenever one opens or closes; right after, the vendor window goes back past the
-- others, so the sacks beside it are never covered by the character or professions window. It runs straight away, in the
-- same frame as the game's layout, so the default arrangement is never drawn; and once more a frame later, in case the
-- game had not finished (a second run changes nothing when the windows are already in order).
local function SettleVendor()
    if not state.vendor then return end
    ns.KeepVendorLast()
    if C_Timer and C_Timer.After then C_Timer.After(0, ns.KeepVendorLast) end
end
ns.OnEvent("MERCHANT_SHOW", SettleVendor)
if hooksecurefunc then
    for _, name in ipairs({ "ShowUIPanel", "HideUIPanel" }) do
        if _G[name] then hooksecurefunc(name, SettleVendor) end
    end
end
ns.OnEvent("MERCHANT_CLOSED", function() state.vendor = false; Refresh() end)

ns.OnEvent("BANKFRAME_OPENED", function()
    state.bank = true
    Refresh()
    -- The bank's tabs are not laid out yet when this event arrives; place the sacks once more right after.
    if C_Timer and C_Timer.After then C_Timer.After(0, function() if state.bank then Refresh() end end) end
end)
ns.OnEvent("BANKFRAME_CLOSED", function() state.bank = false; Refresh() end)

-- The game says when its new-item flags change (for example when you hover an item in the default bags), so the
-- green wash in the sacks follows it.
ns.OnEvent("BAG_NEW_ITEMS_UPDATED", function()
    if SacksDB then ns.Guarded("new-item glow", ns.RefreshFresh) end
end)

-- Accepting, finishing or dropping a quest changes which items carry the quest marker, but changes no bag.
local function QuestsChanged()
    if SacksDB then ns.Guarded("quest markers", ns.RefreshQuestMarks) end
end
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }) do
    ns.OnEvent(event, QuestsChanged)
end
