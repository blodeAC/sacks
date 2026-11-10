-- sacks: Debug.lua
-- Tools for finding out what the game does: /sacks clicks and /sacks counts. Nothing here runs unless you turn it on.
local _, ns = ...
local Say, state = ns.Say, ns.state

-- /sacks clicks also says every time anything picks up a bag item (sacks or the game), with the line of code that did
-- it: to find what leaves an item on the cursor after moving a sack.
if hooksecurefunc and C_Container and C_Container.PickupContainerItem then
    hooksecurefunc(C_Container, "PickupContainerItem", function(bag, slot)
        if not state.debugClicks then return end
        local from = debugstack and debugstack(3, 1, 0) or "?"
        Say(string.format("pickup bag=%s slot=%s cursorAfter=%s from %s", tostring(bag), tostring(slot),
            tostring(GetCursorInfo and GetCursorInfo()), (from:gsub("\n", " "))))
    end)
end
-- and when a sack starts and stops being moved
function ns.LogSackDrag(what, group)
    if state.debugClicks then Say(what .. " " .. tostring(group and group.name) .. " cursor=" .. tostring(GetCursorInfo and GetCursorInfo())) end
end

-- /sacks clicks: say what every click on a sack's item does.
function ns.LogClick(button, mouse, down, atVendor)
    Say(string.format("click %s %s: clickUse=%s type1=%s type2=%s onKeyDown=%s item=%s bag=%s slot=%s vendor=%s combat=%s", tostring(mouse),
        down and "down" or "up", tostring(button.clickUse), tostring(button:GetAttribute("type1")), tostring(button:GetAttribute("type2")),
        tostring(button:GetAttribute("useOnKeyDown")), tostring(button:GetAttribute("item")), tostring(button.bag), tostring(button.slot),
        tostring(atVendor and true or false), tostring(InCombatLockdown and InCombatLockdown() or false)))
    -- what the game says about an item-targeting cursor (a crate waiting for an item to fill it) and about the cursor
    local function Ask(name, fn, ...)
        if not fn then return name .. "=missing" end
        local ok, value = pcall(fn, ...)
        return name .. "=" .. (ok and tostring(value) or "err")
    end
    Say("  item " .. tostring(button.itemID) .. ": " .. Ask("SpellCanTargetItemID", SpellCanTargetItemID, button.itemID))
    local cursor = GetCursorInfo and { GetCursorInfo() } or {}
    Say(string.format("  cursor: %s %s %s %s %s | modifiers: shift=%s split=%s | stacksplit=%s", Ask("SpellIsTargeting", SpellIsTargeting),
        Ask("SpellCanTargetItem", SpellCanTargetItem), Ask("CursorHasItem", CursorHasItem), "type=" .. tostring(cursor[1]),
        "id=" .. tostring(cursor[2]), tostring(IsShiftKeyDown and IsShiftKeyDown()),
        tostring(IsModifiedClick and IsModifiedClick("SPLITSTACK")), tostring(StackSplitFrame and StackSplitFrame.OpenStackSplitFrame and "method"
        or OpenStackSplitFrame and "global" or "none")))
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
