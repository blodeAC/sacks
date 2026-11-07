-- sacks: Debug.lua
-- Tools for finding out what the game does: /sacks clicks and /sacks counts. Nothing here runs unless you turn it on.
local _, ns = ...
local Say, state = ns.Say, ns.state

-- /sacks clicks: say what every click on a sack's item does.
function ns.LogClick(button, mouse, down, atVendor)
    Say(string.format("click %s %s: clickUse=%s type1=%s type2=%s onKeyDown=%s item=%s bag=%s slot=%s vendor=%s combat=%s", tostring(mouse),
        down and "down" or "up", tostring(button.clickUse), tostring(button:GetAttribute("type1")), tostring(button:GetAttribute("type2")),
        tostring(button:GetAttribute("useOnKeyDown")), tostring(button:GetAttribute("item")), tostring(button.bag), tostring(button.slot),
        tostring(atVendor and true or false), tostring(InCombatLockdown and InCombatLockdown() or false)))
end

function ns.commands.clicks()
    state.debugClicks = not state.debugClicks
    Say("click log " .. (state.debugClicks and "on: click an item and read the lines below" or "off"))
end

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
    while #log > 300 do table.remove(log, 1) end
end

local function WatchCounts(event, unit, ...)
    if not (state.debugCounts and SacksDB) then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and unit ~= "player" then return end
    SacksDB.countLog = SacksDB.countLog or {}
    pcall(RecordCounts, event, unit, ...)
end
for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SUCCEEDED", "ITEM_LOCK_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ns.OnEvent(event, WatchCounts)
end

-- Records bag and cast events with the counts the game reports, for finding out why a count lags in combat.
--   /sacks counts          turn recording on or off
--   /sacks counts show     print what was recorded (do this out of combat)
--   /sacks counts clear    forget it
function ns.commands.counts(args)
    SacksDB.countLog = SacksDB.countLog or {}
    local rest = (args[1] or ""):lower()
    if rest == "show" then
        for _, line in ipairs(SacksDB.countLog) do Say(line) end
        Say(#SacksDB.countLog .. " lines (also saved in SacksDB.countLog)")
    elseif rest == "clear" then
        SacksDB.countLog = {}
        Say("count log cleared")
    else
        state.debugCounts = not state.debugCounts
        Say("count log " .. (state.debugCounts and "on: drink a potion in combat, then /sacks counts show out of combat" or "off"))
    end
end
