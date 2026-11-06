-- sacks: Commands.lua
local _, ns = ...
local CreateSack = ns.CreateSack
local AllGroups, Container, DefaultGroups, Describe, FindGroup, HideRemoved = ns.AllGroups, ns.Container, ns.DefaultGroups, ns.Describe, ns.FindGroup, ns.HideRemoved
local Item, ItemClassInfo, ItemInfo, ItemSubClassInfo, ParseRule, ReadSlot = ns.Item, ns.ItemClassInfo, ns.ItemInfo, ns.ItemSubClassInfo, ns.ParseRule, ns.ReadSlot
local Refresh, SCAN_LIMIT, SLOT_GAP, Say, ToConditions, ToggleOwnBags = ns.Refresh, ns.SCAN_LIMIT, ns.SLOT_GAP, ns.Say, ns.ToConditions, ns.ToggleOwnBags
local state = ns.state

---------------------------------------------------------------------------------------------------
-- Probe window (kept so you can see exactly what the client reports for your bags)
---------------------------------------------------------------------------------------------------

local textWindow
local function ShowText(text)
    if not textWindow then
        textWindow = CreateFrame("Frame", "SacksTextWindow", UIParent)
        textWindow:SetSize(640, 420)
        textWindow:SetPoint("CENTER")
        textWindow:SetFrameStrata("DIALOG")
        textWindow:EnableMouse(true)
        textWindow:SetMovable(true)
        textWindow:RegisterForDrag("LeftButton")
        textWindow:SetScript("OnDragStart", textWindow.StartMoving)
        textWindow:SetScript("OnDragStop", textWindow.StopMovingOrSizing)
        local back = textWindow:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0, 0, 0, 0.85)
        local scroll = CreateFrame("ScrollFrame", "SacksTextScroll", textWindow, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -12)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(590)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() textWindow:Hide() end)
        scroll:SetScrollChild(edit)
        textWindow.edit = edit
    end
    textWindow.edit:SetText(text)
    textWindow.edit:HighlightText()
    textWindow:Show()
    textWindow.edit:SetFocus()
end

local function ShowLines(lines)
    if not pcall(ShowText, table.concat(lines, "\n")) then
        for _, line in ipairs(lines) do print(line) end
    end
end

local function ProbeLines()
    local lines = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = Container.GetContainerNumSlots(bag) or 0
        if slots > 0 then
            local free, bagType = Container.GetContainerNumFreeSlots(bag)
            lines[#lines + 1] = string.format("bag %d  slots %d  free %s  bagType %s", bag, slots, tostring(free),
                tostring(bagType))
            for slot = 1, slots do
                local e = ReadSlot(bag, slot)
                if e then
                    lines[#lines + 1] = string.format("  %d.%-2d  id %-7s class %-4s sub %-4s q %-2s x%-3s %s",
                        bag, slot, tostring(e.itemID), tostring(e.classID), tostring(e.subClassID),
                        tostring(e.quality), tostring(e.count), tostring(e.name))
                end
            end
        end
    end
    return lines
end

local function ClassLines()
    local lines = {}
    for id = 0, SCAN_LIMIT do
        local name = ItemClassInfo(id)
        if name then
            local subs = {}
            for sub = 0, SCAN_LIMIT do
                local subName = ItemSubClassInfo(id, sub)
                if subName and subName ~= "" then subs[#subs + 1] = subName end
            end
            lines[#lines + 1] = string.format("%d %s: %s", id, name, table.concat(subs, ", "))
        end
    end
    return lines
end

---------------------------------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------------------------------

local HELP = {
    "/sacks - open the settings window (or click the bag icon)",
    "/sacks list - show every sack and what it takes",
    "/sacks new <name> class=.. sub=.. quality=.. minq=.. maxq=.. id=.. - make a sack; the newest sack is checked first",
    "/sacks remove <name>",
    "/sacks cols <name or all> <number> - how many slots per row; all sets the default for every sack",
    "/sacks anchor <name> <frame> - pin a sack to a named frame (e.g. MinimapCluster); drag its title bar to unpin",
    "/sacks classes - the item classes and subclasses you can use",
    "/sacks fields - every detail the game gives for the item under the mouse (or /sacks fields [item link])",
    "/sacks probe - list every item in your bags with its class, subclass and quality",
    "/sacks bags - open or close the game's own bags",
    "/sacks errors - the last errors this add-on raised (kept across reloads); /sacks errors clear empties it",
    "/sacks counts - record bag/cast events and the counts the game reports (show, clear); for finding out why a count lags in combat",
    "/sacks deadtest [bare] - point the first slot at an empty bag slot to test clicks on used-up items (see its notes)",
    "/sacks ghosttest - what a plain frame may do beside a sack in combat (run once out of combat, once in)",
    "/sacks reset - back to the starting sacks",
    "Drag a sack by its title bar to move it.",
}

local function Words(text)
    local words = {}
    for word in (text or ""):gmatch("%S+") do words[#words + 1] = word end
    return words
end

local commands = {}

function commands.list()
    for _, group in ipairs(AllGroups()) do
        Say(string.format("%s (%d items): %s", group.name, state.counts[group] or 0, Describe(group.rule)))
    end
end

function commands.new(args)
    local name = table.remove(args, 1)
    if not name then return Say("give the sack a name: /sacks new <name> class=.. ...") end
    local rule, reason = ParseRule(args)
    if not rule then return Say(reason) end
    rule = ToConditions(rule)
    local group, problem = CreateSack(name, rule)
    if not group then return Say(problem) end
    Say("made " .. name .. ": " .. Describe(rule))
    Refresh()
end

function commands.remove(args)
    local group, index = FindGroup(args[1])
    if not group then return Say("no sack called " .. tostring(args[1])) end
    if group.builtin then return Say(group.name .. " can't be removed: it is where items looted in combat show") end
    if group.fixed then return Say(group.name .. " can't be removed: it keeps every item in your bags on screen") end
    table.remove(SacksDB.groups, index)
    HideRemoved(group)
    Refresh()
end

function commands.cols(args)
    local columns = tonumber(args[2])
    if not args[1] or not columns or columns < 1 then
        return Say("usage: /sacks cols <name or all> <number>")
    end
    columns = math.floor(columns)
    if args[1]:lower() == "all" then
        SacksDB.columns = columns -- the default for every sack without its own number
    else
        local group = FindGroup(args[1])
        if not group then return Say("no sack called " .. args[1]) end
        group.cols = columns
    end
    Refresh()
end

function commands.anchor(args)
    local group = FindGroup(args[1])
    if not group or not args[2] then return Say("usage: /sacks anchor <name> <frame>") end
    if not _G[args[2]] then return Say("no frame called " .. args[2]) end
    group.relativeTo, group.point, group.relPoint, group.x, group.y = args[2], "TOPLEFT", "BOTTOMLEFT", 0, -SLOT_GAP
    Refresh()
end

function commands.classes() ShowLines(ClassLines()) end

-- The errors this add-on has raised, newest last (kept across reloads). "/sacks errors clear" empties the list.
function commands.errors(args)
    local list = SacksDB and SacksDB.errors or {}
    if args[1] == "clear" then
        if SacksDB then SacksDB.errors = nil end
        return Say("error log cleared")
    end
    if #list == 0 then return Say("no errors recorded") end
    for index = math.max(1, #list - 4), #list do
        local entry = list[index]
        Say(string.format("[%s%s%s] %s", entry.time or "", entry.combat and " combat" or "", (entry.count or 1) > 1 and (" x" .. entry.count) or "", entry.text))
        if entry.stack and entry.stack ~= "" then Say(entry.stack) end
    end
end

-- Prints what every click on a sack's item does (for finding out why a click does nothing).
function commands.clicks()
    state.debugClicks = not state.debugClicks
    Say("click log " .. (state.debugClicks and "on: click an item and read the lines below" or "off"))
end

-- Records bag and cast events with the counts the game reports, for finding out why a count lags in combat.
--   /sacks counts          turn recording on or off
--   /sacks counts show     print what was recorded (do this out of combat)
--   /sacks counts clear    forget it
function commands.counts(args)
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

-- Reproduces "click a slot whose item is gone" without needing to use up an item. The first slot on screen is pointed
-- at an empty bag slot (what a used-up item leaves behind). With "bare" nothing covers it, so a right-click should
-- raise the game's own error; without it the click-blocking cover is on, so a right-click should do nothing.
-- Any bag change puts the slot back to normal.
function commands.deadtest(args)
    if InCombatLockdown() then return Say("do this out of combat") end
    local target, sack
    for group, frame in pairs(state.frames or {}) do
        for _, button in ipairs(rawget(frame, "buttons") or {}) do
            if not target and button.bag and button:IsShown() then target, sack = button, group end
        end
    end
    if not target then return Say("no slot on screen to test with") end
    local emptyBag, emptySlot
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            if not emptyBag and not C_Container.GetContainerItemInfo(bag, slot) then emptyBag, emptySlot = bag, slot end
        end
    end
    if not emptyBag then return Say("no empty bag slot to point at") end
    target:SetAttribute("item", emptyBag .. " " .. emptySlot)
    if (args[1] or "") == "bare" then target.dead:Hide() else target.dead:Show() end
    local name = target.itemID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(target.itemID) or tostring(target.itemID)
    target.icon:SetDesaturated(true) -- the test slot is greyed so you can see which one it is
    Say(string.format("TEST SLOT: the greyed %s, in the sack \"%s\". It now points at an empty bag slot; cover %s.",
        tostring(name), tostring(sack and sack.name or "?"), (args[1] or "") == "bare" and "OFF" or "ON"))
    Say((args[1] or "") == "bare" and "Right-click that greyed slot now. The game should show its error; then /sacks errors."
        or "Right-click that greyed slot now. Nothing should happen; then /sacks errors should show nothing new.")
end

-- Finds out what a plain (non-secure) frame is allowed to do next to a sack in combat: be created, be anchored to
-- a sack, be moved, be shown, be a child of a sack. Run it once out of combat and once in combat and compare.
function commands.ghosttest()
    local sack
    for _, frame in pairs(state.frames or {}) do
        if not sack and frame:IsShown() then sack = frame end
    end
    if not sack then return Say("no sack on screen") end
    local combat = InCombatLockdown() and "IN combat" or "out of combat"
    local function Step(label, call)
        local ok, problem = pcall(call)
        Say(string.format("%s, %s: %s", combat, label, ok and "ok" or ("BLOCKED " .. tostring(problem))))
    end
    local ghost = state.ghost
    Step("create a frame", function()
        if not ghost then
            ghost = CreateFrame("Frame", nil, UIParent)
            ghost:SetSize(24, 24)
            ghost.back = ghost:CreateTexture(nil, "BACKGROUND")
            ghost.back:SetAllPoints()
            ghost.back:SetColorTexture(1, 0.5, 0, 1)
            state.ghost = ghost
        end
    end)
    if not ghost then return end
    Step("anchor it under the sack", function() ghost:ClearAllPoints(); ghost:SetPoint("TOPLEFT", sack, "BOTTOMLEFT", 0, -2) end)
    Step("show it", function() ghost:Show() end)
    Step("move it (anchor again, further right)", function() ghost:ClearAllPoints(); ghost:SetPoint("TOPLEFT", sack, "BOTTOMLEFT", 40, -2) end)
    Step("hide, then show it", function() ghost:Hide(); ghost:Show() end)
    Step("make a frame as a child of the sack", function()
        state.child = state.child or CreateFrame("Frame", nil, sack)
        state.child:SetSize(8, 8)
        state.child:SetPoint("TOPRIGHT", sack, "BOTTOMRIGHT", 0, -2)
        state.child.back = state.child.back or state.child:CreateTexture(nil, "BACKGROUND")
        state.child.back:SetAllPoints()
        state.child.back:SetColorTexture(0, 1, 1, 1)
        state.child:Show()
    end)
    Say("An orange square should sit under the sack, and a small cyan one at its right. /reload removes them.")
end

function commands.bags() ToggleOwnBags() end

function commands.probe()
    local ok, lines = pcall(ProbeLines)
    if ok then ShowLines(lines) else Say("probe failed: " .. tostring(lines)) end
end

function commands.reset()
    for _, group in ipairs(SacksDB.groups) do HideRemoved(group) end
    SacksDB.groups = DefaultGroups()
    Refresh()
end

local ITEM_FIELD_NAMES = { "name", "link", "quality", "itemLevel", "minLevel", "type", "subType", "stackCount", "equipLoc",
    "texture", "sellPrice", "classID", "subclassID", "bindType", "expansionID", "setID", "isCraftingReagent", "description" }

-- Prints everything this client says about one item, so we can see which fields exist and are filled in.
function commands.fields(args)
    local target = #args > 0 and table.concat(args, " ") or nil
    if not target and GetCursorInfo then
        local kind, id, link = GetCursorInfo()
        if kind == "item" then target = link or id end
    end
    if not target and GameTooltip and GameTooltip.GetItem then
        local _, link = GameTooltip:GetItem()
        target = link
    end
    local id = target and (tonumber(target) or tonumber(tostring(target):match("item:(%d+)")))
    if not id then
        Say("hover an item (or hold it on the cursor) and type /sacks fields, or: /sacks fields [shift-click an item]")
        return
    end
    local ref = "item:" .. id
    local values = { ItemInfo(ref) }
    local count = select("#", ItemInfo(ref))
    Say(string.format("item %d: GetItemInfo returned %d values", id, count))
    for index = 1, math.max(count, #values) do
        local value = values[index]
        if index == 2 and value then value = "(link)" end
        Say(string.format("  %d %s = %s", index, ITEM_FIELD_NAMES[index] or "(unknown)", tostring(value)))
    end
    local instant = Item.GetItemInfoInstant or GetItemInfoInstant
    if instant then
        local list = { instant(ref) }
        for index = 1, #list do list[index] = tostring(list[index]) end
        Say("GetItemInfoInstant: " .. table.concat(list, ", "))
    end
    local family = GetItemFamily or (C_Item and C_Item.GetItemFamily)
    if family then Say("GetItemFamily: " .. tostring(family(ref))) end
    local found
    for bag = 0, 4 do
        for slot = 1, (C_Container and C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id and not found then
                found = true
                local keys = {}
                for key, value in pairs(info) do
                    if key ~= "hyperlink" and key ~= "iconFileID" then keys[#keys + 1] = key .. "=" .. tostring(value) end
                end
                table.sort(keys)
                Say("bag slot info: " .. table.concat(keys, ", "))
            end
        end
    end
    if not found then Say("bag slot info: that item is not in your bags right now") end
end

SLASH_SACKS1 = "/sacks"
SlashCmdList["SACKS"] = function(message)
    local args = Words(message)
    local name = (table.remove(args, 1) or ""):lower()
    if name == "" then
        ns.ToggleSettings()
    elseif commands[name] then
        commands[name](args)
    else
        for _, line in ipairs(HELP) do Say(line) end
    end
end
