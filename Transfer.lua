-- sacks: Transfer.lua
local _, ns = ...
local COLOR, Rgb, Say = ns.COLOR, ns.Rgb, ns.Say

---------------------------------------------------------------------------------------------------
-- Export and import: your sacks as one block of text, to keep as a backup or to share.
-- An add-on cannot read or write files, so the text is shown in a box to copy, and a box to paste into.
---------------------------------------------------------------------------------------------------

local PREFIX = "SACKS1:" -- says what the text is, and which version of the format it is

---------------------------------------------------------------------------------------------------
-- Text <-> tables: a small JSON. Pasted text is only ever read by this, never run as code.
---------------------------------------------------------------------------------------------------

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local MAX_DEPTH = 12 -- a sack goes sack > sort step > rule > condition; nothing legitimate is deeper than this

local function EncodeString(text)
    return '"' .. text:gsub('[%c"\\]', function(char) return ESCAPES[char] or string.format("\\u%04x", char:byte()) end) .. '"'
end

local function IsList(value)
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count > 0 and count == #value
end

local function Encode(value, depth)
    local kind = type(value)
    if kind == "string" then return EncodeString(value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind ~= "table" then return "null" end
    if depth > MAX_DEPTH then error("too deep to save") end
    if next(value) == nil then return "[]" end
    local parts = {}
    if IsList(value) then
        for index = 1, #value do parts[index] = Encode(value[index], depth + 1) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do
        if type(key) == "string" and type(value[key]) ~= "function" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for index, key in ipairs(keys) do parts[index] = EncodeString(key) .. ":" .. Encode(value[key], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local UNESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

-- Returns the value, or nil and a sentence that says what is wrong with the text.
local function Decode(text)
    local position = 1
    local function fail(what) error({ what = what .. " (character " .. position .. ")" }, 0) end
    local function skip() position = text:find("[^ \t\r\n]", position) or #text + 1 end
    local read
    local function readString()
        position = position + 1 -- the opening quote
        local out = {}
        while true do
            local stop = text:find('["\\]', position)
            if not stop then fail("a quote is never closed") end
            out[#out + 1] = text:sub(position, stop - 1)
            if text:sub(stop, stop) == '"' then
                position = stop + 1
                return table.concat(out)
            end
            local code = text:sub(stop + 1, stop + 1)
            if code == "u" then
                local hex = text:match("^%x%x%x%x", stop + 2)
                if not hex then fail("a broken \\u in a quote") end
                out[#out + 1] = string.char(tonumber(hex, 16) % 256)
                position = stop + 6
            elseif UNESCAPES[code] then
                out[#out + 1] = UNESCAPES[code]
                position = stop + 2
            else
                fail("an unknown backslash in a quote")
            end
        end
    end
    local function readList(depth)
        position = position + 1
        local list = {}
        skip()
        if text:sub(position, position) == "]" then position = position + 1 return list end
        while true do
            list[#list + 1] = read(depth + 1)
            skip()
            local char = text:sub(position, position)
            position = position + 1
            if char == "]" then return list end
            if char ~= "," then position = position - 1 fail("expected , or ]") end
        end
    end
    local function readObject(depth)
        position = position + 1
        local object = {}
        skip()
        if text:sub(position, position) == "}" then position = position + 1 return object end
        while true do
            skip()
            if text:sub(position, position) ~= '"' then fail("expected a name in quotes") end
            local key = readString()
            skip()
            if text:sub(position, position) ~= ":" then fail("expected :") end
            position = position + 1
            object[key] = read(depth + 1)
            skip()
            local char = text:sub(position, position)
            position = position + 1
            if char == "}" then return object end
            if char ~= "," then position = position - 1 fail("expected , or }") end
        end
    end
    function read(depth)
        if depth > MAX_DEPTH then fail("nested too deeply") end
        skip()
        local char = text:sub(position, position)
        if char == '"' then return readString() end
        if char == "{" then return readObject(depth) end
        if char == "[" then return readList(depth) end
        local word = text:match("^[%a]+", position)
        if word == "true" or word == "false" or word == "null" then
            position = position + #word
            if word == "null" then return nil end
            return word == "true"
        end
        local number = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", position)
        if number and number ~= "" and tonumber(number) then
            position = position + #number
            return tonumber(number)
        end
        fail("unexpected text")
    end
    local ok, value = pcall(function()
        local result = read(1)
        skip()
        if position <= #text then fail("extra text after the end") end
        return result
    end)
    if ok then return value end
    if type(value) == "table" and value.what then return nil, value.what end
    return nil, "that is not a sacks export"
end

---------------------------------------------------------------------------------------------------
-- What gets exported, and checking what comes in
---------------------------------------------------------------------------------------------------

local MAX_SACKS, MAX_LINES_PER_RULE, MAX_PINS = 100, 50, 500
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local CORNERS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local FLOWS = { ROWS = true, COLUMNS = true }
local TITLES = { TOP = true, BOTTOM = true, NONE = true }
local SIDES = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true }

-- The settings that are kept: the sacks, Other, the free-slots box, and the global choices. Not what you have carried,
-- not the error log, not where the minimap icon sits.
local function Payload()
    return { groups = SacksDB.groups, fallback = SacksDB.fallback, widget = ns.WidgetGroup(), columns = SacksDB.columns,
        clickColor = SacksDB.clickColor, hideBags = SacksDB.hideBags }
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, inner in pairs(value) do copy[key] = DeepCopy(inner) end
    return copy
end

local function Export() return PREFIX .. Encode(Payload(), 1) end

-- Each Clean function returns a fresh table holding only what it knows, or nil and what is wrong.

local function Typed(source, key, kind, what)
    local value = source[key]
    if value ~= nil and type(value) ~= kind then return false, what .. ": " .. key .. " should be a " .. kind end
    return true
end

local function CleanRule(rule, what)
    if rule == nil then return {} end
    if type(rule) ~= "table" or #rule > MAX_LINES_PER_RULE then return nil, what .. ": the rule is not a list of lines" end
    local fields = { item = true }
    for _, option in ipairs(ns.RuleFields()) do fields[option.value] = true end
    local clean = {}
    for index, line in ipairs(rule) do
        if type(line) ~= "table" or not fields[line.field] or not ns.OP_TEXT[line.op] then
            return nil, what .. ": line " .. index .. " of the rule is not one this version knows"
        end
        local value = line.value
        if value ~= nil and type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean" then
            return nil, what .. ": line " .. index .. " has a value it cannot read"
        end
        if line.join ~= nil and line.join ~= "AND" and line.join ~= "OR" then return nil, what .. ": line " .. index .. " has a bad and/or" end
        if line.class ~= nil and type(line.class) ~= "number" then return nil, what .. ": line " .. index .. " has a bad class" end
        clean[index] = { field = line.field, op = line.op, value = value, join = line.join, class = line.class, auto = line.auto and true or nil }
    end
    return clean
end

local function CleanSort(sort, what)
    if sort == nil then return nil end
    if type(sort) ~= "table" or #sort > 20 then return nil, what .. ": the sort order is not a list of steps" end
    local clean = {}
    for index, step in ipairs(sort) do
        if type(step) ~= "table" or (step.key ~= "match" and not ns.SORT_KEYS[step.key]) then
            return nil, what .. ": step " .. index .. " of the sort order is not one this version knows"
        end
        local rule, problem = CleanRule(step.rule, what)
        if not rule then return nil, problem end
        clean[index] = { key = step.key, descending = step.descending and true or nil, rule = step.key == "match" and rule or nil }
    end
    return clean
end

local TYPES = { name = "string", point = "string", relPoint = "string", x = "number", y = "number", anchor = "string", flow = "string",
    title = "string", titleText = "string", cols = "number", blank = "string", reverse = "boolean", useOnClick = "boolean",
    always = "boolean", hideEmpty = "boolean", shown = "boolean" }

-- A sack (or Other, or the free-slots box). Never copied across: fixed, builtin and relativeTo, which the add-on decides itself.
local function CleanGroup(source, what)
    if type(source) ~= "table" then return nil, what .. " is not a sack" end
    local clean = {}
    for key, kind in pairs(TYPES) do
        local ok, problem = Typed(source, key, kind, what)
        if not ok then return nil, problem end
        clean[key] = source[key]
    end
    if type(clean.name) ~= "string" or clean.name == "" then return nil, what .. " has no name" end
    what = '"' .. clean.name .. '"'
    if (clean.point and not POINTS[clean.point]) or (clean.relPoint and not POINTS[clean.relPoint]) then return nil, what .. ": a bad screen position" end
    if clean.anchor and not CORNERS[clean.anchor] then return nil, what .. ": a bad corner" end
    if clean.flow and not FLOWS[clean.flow] then return nil, what .. ": a bad fill direction" end
    if clean.title and not TITLES[clean.title] then return nil, what .. ": a bad title place" end
    if clean.blank and clean.blank ~= "LAST" and clean.blank ~= "FIRST" and clean.blank ~= "NONE" then return nil, what .. ": a bad empty slot place" end
    if clean.cols and (clean.cols < 1 or clean.cols > 50 or clean.cols ~= math.floor(clean.cols)) then return nil, what .. ": a bad slots per row" end
    local problem
    clean.rule, problem = CleanRule(source.rule, what)
    if not clean.rule then return nil, problem end
    if source.sort ~= nil then
        clean.sort, problem = CleanSort(source.sort, what)
        if problem then return nil, problem end
    end
    if source.pins ~= nil then
        if type(source.pins) ~= "table" or #source.pins > MAX_PINS then return nil, what .. ": the pinned items are not a list" end
        clean.pins = {}
        for index, id in ipairs(source.pins) do
            if type(id) ~= "number" then return nil, what .. ": a pinned item is not a number" end
            clean.pins[index] = id
        end
    end
    local dock = source.dock
    if dock ~= nil then
        if type(dock) ~= "table" or type(dock.to) ~= "string" or (dock.side ~= nil and not SIDES[dock.side])
            or (dock.edge ~= nil and not SIDES[dock.edge]) or (dock.offset ~= nil and type(dock.offset) ~= "number") then
            return nil, what .. ": it is docked to something this version cannot read"
        end
        clean.dock = { to = dock.to, side = dock.side, edge = dock.edge, offset = dock.offset }
    end
    return clean
end

-- Checks the whole of what was pasted. Returns the clean data, or nil and what is wrong.
local function Validate(data)
    if type(data) ~= "table" or type(data.groups) ~= "table" or type(data.fallback) ~= "table" then
        return nil, "that is not a sacks export"
    end
    if #data.groups > MAX_SACKS then return nil, "more than " .. MAX_SACKS .. " sacks" end
    local clean, names = { groups = {} }, {}
    local function unique(group)
        if names[group.name:lower()] then return nil, 'two sacks are called "' .. group.name .. '"' end
        names[group.name:lower()] = true
        return true
    end
    for index, source in ipairs(data.groups) do
        local group, problem = CleanGroup(source, "sack " .. index)
        if not group then return nil, problem end
        local ok, duplicate = unique(group)
        if not ok then return nil, duplicate end
        clean.groups[index] = group
    end
    local fallback, problem = CleanGroup(data.fallback, "the Other sack")
    if not fallback then return nil, problem end
    local ok, duplicate = unique(fallback)
    if not ok then return nil, duplicate end
    clean.fallback = fallback
    if data.widget ~= nil then
        clean.widget, problem = CleanGroup(data.widget, "the free-slots box")
        if not clean.widget then return nil, problem end
    end
    if data.columns ~= nil then
        if type(data.columns) ~= "number" or data.columns < 1 or data.columns > 50 or data.columns ~= math.floor(data.columns) then
            return nil, "a bad number of slots per row"
        end
        clean.columns = data.columns
    end
    if data.clickColor ~= nil then
        if type(data.clickColor) ~= "string" then return nil, "a bad click colour" end
        clean.clickColor = data.clickColor
    end
    if data.hideBags ~= nil then
        if type(data.hideBags) ~= "boolean" then return nil, "a bad choice about the game's bags" end
        clean.hideBags = data.hideBags
    end
    return clean
end

-- Reads pasted text. Returns the clean data, or nil and what is wrong.
local function Parse(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" then return nil, "paste the text first" end
    if text:sub(1, #PREFIX) ~= PREFIX then
        if text:sub(1, 5):upper() == "SACKS" then return nil, "this text is from a different version of sacks" end
        return nil, "that is not a sacks export (it should start with " .. PREFIX .. ")"
    end
    local value, problem = Decode(text:sub(#PREFIX + 1))
    if value == nil then return nil, problem end
    return Validate(value)
end

---------------------------------------------------------------------------------------------------
-- Putting settings in place, and keeping the ones they replaced so one undo is possible
---------------------------------------------------------------------------------------------------

-- Replaces the settings with clean data. Other and the free-slots box keep their own table (their boxes on screen are
-- tied to it), so they are emptied and refilled.
local function Install(data)
    for _, group in ipairs(SacksDB.groups) do ns.HideRemoved(group) end
    SacksDB.groups = data.groups
    for _, group in ipairs(SacksDB.groups) do ns.UpgradeSort(group) end
    ns.EnsureCombatSack()
    local function refill(target, source)
        for key in pairs(target) do target[key] = nil end
        for key, value in pairs(source) do target[key] = value end
    end
    refill(SacksDB.fallback, data.fallback)
    ns.EnsureFallback()
    ns.UpgradeSort(SacksDB.fallback)
    if data.widget then refill(ns.WidgetGroup(), data.widget) end
    SacksDB.columns, SacksDB.clickColor = data.columns, data.clickColor
    if data.hideBags ~= nil then SacksDB.hideBags = data.hideBags end
    ns.HideOwnBags()
    ns.Refresh()
end

-- Keeps a copy of everything that Reset, Import and Undo change, for Undo to put back.
local function Backup() SacksDB.backup = DeepCopy(Payload()) end

-- Swaps in new settings, keeping the old ones for Undo. If anything goes wrong the old ones are put back.
local function Replace(data)
    local old = DeepCopy(Payload())
    local ok, problem = pcall(Install, data)
    if ok then
        SacksDB.backup = old
        return true
    end
    pcall(Install, old)
    Say("that could not be used: " .. tostring(problem))
    return false
end

local function Undo()
    local data = SacksDB.backup
    if not data then return Say("there is nothing to undo") end
    if pcall(Install, data) then
        SacksDB.backup = nil
        Say("put your sacks back as they were before the last reset or import")
    else
        Say("the saved copy could not be put back")
    end
end

---------------------------------------------------------------------------------------------------
-- The box that shows the text (export) or takes it (import)
---------------------------------------------------------------------------------------------------

local function BuildDialog()
    local dialog = ns.MakeModal("SacksTransfer")
    local box = dialog.box
    dialog.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.help = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dialog.edit = ns.MakeTextBox(box, nil, function(self, typed)
        if dialog.fixedText and typed then -- an export is for copying, not editing
            self:SetText(dialog.fixedText)
            self:HighlightText()
        end
    end)
    dialog.edit:SetMaxLetters(0)
    dialog.edit:SetMaxBytes(0) -- no limit: a whole setup is thousands of letters
    dialog.problem = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.problem:SetTextColor(Rgb(COLOR.RED))
    dialog.close = ns.MakeButton(box, "Close", nil, function() dialog:Hide() end)
    dialog.go = ns.MakeButton(box, "Import", nil, function() end)
    return dialog
end

local function ShowDialog(mode)
    local dialog = ns.transferDialog or BuildDialog()
    ns.transferDialog = dialog
    local pad = ns.PADDING
    local exporting = mode == "export"
    local text = exporting and Export() or ""
    dialog.fixedText = exporting and text or nil
    dialog.title:SetText(exporting and "Export your sacks" or "Import sacks")
    local help = exporting and "Press Ctrl+C to copy it. Paste it into the Import box to restore it or give it to someone else."
        or "Paste an export here (Ctrl+V), then press Import. To return to your old sacks, press Undo."
    dialog.help:SetText(help)
    dialog.problem:SetText("")
    dialog.close:SetText(exporting and "Close" or "Cancel")
    local closeWidth = ns.ButtonWidth(exporting and "Close" or "Cancel")
    dialog.close:SetWidth(closeWidth)
    local goWidth = ns.ButtonWidth("Import")
    -- as wide as the longer of the two help lines, so the box does not change size between the two
    local width = math.ceil(math.max(ns.TextWidth("Press Ctrl+C to copy it. Paste it into the Import box to restore it or give it to someone else.", "GameFontHighlight"),
        ns.TextWidth("Paste an export here (Ctrl+V), then press Import. To return to your old sacks, press Undo.", "GameFontHighlight"))) + 4 * pad
    local editHeight = ns.BUTTON_HEIGHT
    local top = 2 * pad
    dialog.box:SetSize(width, top + ns.LABEL_HEIGHT + pad + ns.LABEL_HEIGHT + pad + editHeight + pad + ns.LABEL_HEIGHT + pad + ns.BUTTON_HEIGHT + 2 * pad)
    dialog.title:ClearAllPoints()
    dialog.title:SetPoint("TOPLEFT", 2 * pad, -top)
    dialog.help:ClearAllPoints()
    dialog.help:SetPoint("TOPLEFT", 2 * pad, -(top + ns.LABEL_HEIGHT + pad))
    local editTop = top + ns.LABEL_HEIGHT + pad + ns.LABEL_HEIGHT + pad
    dialog.edit:ClearAllPoints()
    dialog.edit:SetPoint("TOPLEFT", 2 * pad, -editTop)
    dialog.edit:SetSize(width - 4 * pad, editHeight)
    dialog.problem:ClearAllPoints()
    dialog.problem:SetPoint("TOPLEFT", 2 * pad, -(editTop + editHeight + pad))
    local buttonTop = -(editTop + editHeight + pad + ns.LABEL_HEIGHT + pad)
    dialog.close:ClearAllPoints()
    dialog.close:SetPoint("TOPRIGHT", -2 * pad, buttonTop)
    dialog.go:ClearAllPoints()
    dialog.go:SetWidth(goWidth)
    dialog.go:SetPoint("RIGHT", dialog.close, "LEFT", -pad, 0)
    if exporting then dialog.go:Hide() else dialog.go:Show() end
    dialog.go:SetScript("OnClick", function()
        local data, problem = Parse(dialog.edit:GetText())
        if not data then
            dialog.problem:SetText(problem)
            return
        end
        local count = #data.groups
        dialog:Hide()
        ns.Confirm("Replace your sacks with these?",
            count .. " sack" .. (count == 1 and "" or "s") .. " plus Other. To return to your old sacks, press Undo.", "Replace", function()
                if Replace(data) then Say("imported " .. count .. " sack" .. (count == 1 and "" or "s")) end
            end)
    end)
    dialog.edit:SetText(text)
    dialog:Show()
    dialog.edit:SetFocus()
    if exporting then dialog.edit:HighlightText() end
end

ns.ExportSacks = Export
ns.ParseSacks = Parse
ns.ReplaceSacks = Replace
ns.BackupSacks = Backup
ns.UndoSacks = Undo
ns.ShowTransfer = ShowDialog
