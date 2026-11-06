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
ns.RecordError = RecordError
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
        SacksDB.fresh, SacksDB.snapshot, SacksDB.snapshot2 = nil, nil, nil -- an earlier version tracked new items itself
        SacksDB.tray, SacksDB.trayAlways = nil, nil -- the new-items tray is gone
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

-- /sacks counts: while on, every bag/cast event is written to SacksDB.countLog along with any slot whose shown count
-- differs from what the game reports right now, so a potion drunk in combat can be read back afterwards.
local function Now() return GetTime and string.format("%.2f", GetTime()) or "?" end
local function Safe(call, ...)
    local ok, value = pcall(call, ...)
    if not ok then return "err" end
    local shown, text = pcall(tostring, value)
    return shown and text or "secret"
end
local function RecordCounts(event, ...)
    local log = SacksDB.countLog
    local parts = {}
    for index = 1, select("#", ...) do parts[#parts + 1] = Safe(function(...) return (select(index, ...)) end, ...) end
    local line = string.format("%s %s(%s) combat=%s", Now(), event, table.concat(parts, ","), tostring(InCombatLockdown and InCombatLockdown() or false))
    log[#log + 1] = line
    local seen = 0
    for _, frame in pairs(state.frames or {}) do
        for _, button in ipairs(frame.buttons or {}) do
            if button.bag and button:IsShown() and seen < 30 then
                local info = Safe(function() return C_Container.GetContainerItemInfo(button.bag, button.slot).stackCount end)
                local id = Safe(function() return C_Container.GetContainerItemID(button.bag, button.slot) end)
                local total = Safe(function(item) return (C_Item and C_Item.GetItemCount or GetItemCount)(item) end, tonumber(id) or 0)
                local shown = button.count:GetText() or ""
                if shown == "" then shown = "1" end
                if shown ~= info then
                    seen = seen + 1
                    log[#log + 1] = string.format("    item %s shown=%s slotStack=%s total=%s", id, shown, info, total)
                end
            end
        end
    end
    -- cooldowns: what the game reports for each slot against what its spin shows
    local cds = 0
    for _, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if button.bag and button:IsShown() and cds < 10 then
                local get = (C_Container and C_Container.GetContainerItemCooldown) or GetContainerItemCooldown
                local a = Safe(function() return (select(1, get(button.bag, button.slot))) end)
                local b = Safe(function() return (select(2, get(button.bag, button.slot))) end)
                local c = Safe(function() return (select(3, get(button.bag, button.slot))) end)
                local spin = Safe(function() return button.cooldown:IsShown() end)
                local from = Safe(function() return (select(1, button.cooldown:GetCooldownTimes())) end)
                local length = Safe(function() return (select(2, button.cooldown:GetCooldownTimes())) end)
                if (tonumber(b) or 0) > 0 or spin == "true" then
                    cds = cds + 1
                    log[#log + 1] = string.format("    cooldown item %s api=%s,%s,%s spinShown=%s spin=%s,%s", Safe(function() return C_Container.GetContainerItemID(button.bag, button.slot) end), a, b, c, spin, from, length)
                end
            end
        end
    end
    if cds == 0 then log[#log + 1] = "    cooldown: no slot reports one and no spin is shown" end
    -- the global cooldown itself (the shared spell 61304), which is what the action bars spin for
    local gstart = Safe(function() local f = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown; local a = f(61304); if type(a) == "table" then return a.startTime end return a end)
    local gdur = Safe(function() local f = C_Spell and C_Spell.GetSpellCooldown or GetSpellCooldown; local a, b = f(61304); if type(a) == "table" then return a.duration end return b end)
    log[#log + 1] = string.format("    global cooldown: start=%s duration=%s now=%s", gstart, gdur, Now())
    while #log > 300 do table.remove(log, 1) end
end
-- The game says when its new-item flags change (for example when you hover an item in the default bags), so the
-- green wash in the sacks follows it.
local flags = CreateFrame("Frame")
if pcall(flags.RegisterEvent, flags, "BAG_NEW_ITEMS_UPDATED") then
    flags:SetScript("OnEvent", function()
        if not SacksDB then return end
        if ns.RefreshFresh then pcall(ns.RefreshFresh) end
    end)
end

-- Accepting, finishing or dropping a quest changes which items carry the quest marker, but changes no bag.
local quests = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }) do
    pcall(quests.RegisterEvent, quests, event)
end
quests:SetScript("OnEvent", function()
    if SacksDB and ns.RefreshQuestMarks then pcall(ns.RefreshQuestMarks) end
end)

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SUCCEEDED", "ITEM_LOCK_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", function(_, event, unit, ...)
    if not (state.debugCounts and SacksDB) then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and unit ~= "player" then return end
    SacksDB.countLog = SacksDB.countLog or {}
    pcall(RecordCounts, event, unit, ...)
end)

