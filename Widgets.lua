-- sacks: Widgets.lua
local _, ns = ...
local CreateSack = ns.CreateSack
local BUTTON_HEIGHT, CHECK_SIZE, CHOICE_WIDTH, DROPDOWN_INSET, Describe = ns.BUTTON_HEIGHT, ns.CHECK_SIZE, ns.CHOICE_WIDTH, ns.DROPDOWN_INSET, ns.Describe
local ItemClassInfo, ItemSubClassInfo, LABEL_HEIGHT, OP_TEXT, QualityName, Refresh = ns.ItemClassInfo, ns.ItemSubClassInfo, ns.LABEL_HEIGHT, ns.OP_TEXT, ns.QualityName, ns.Refresh
local Say, ScanNames, Stat, state = ns.Say, ns.ScanNames, ns.Stat, ns.state

---------------------------------------------------------------------------------------------------
-- Settings window, and the icon that opens it
---------------------------------------------------------------------------------------------------

-- ns.settings holds the settings window once it exists

-- Build a frame with one of the game's own templates; if this client lacks the template, fall back to a plain frame
-- so the window still opens.
local function NativeFrame(kind, parent, template)
    if template then
        local ok, frame = pcall(CreateFrame, kind, nil, parent, template)
        if ok and frame then return frame, true end
    end
    return CreateFrame(kind, nil, parent), false
end

local function MakeButton(parent, text, width, onClick)
    local button = NativeFrame("Button", parent, "UIPanelButtonTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetText(text)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", onClick)
    return button
end

local function MakeText(parent, template, point, x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetPoint(point, x, y)
    text:SetJustifyH("LEFT")
    return text
end

-- A tick box drawn with the game's own check textures, with its label to the right.
local function MakeCheck(parent, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(CHECK_SIZE, CHECK_SIZE)
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetText(label)
    check:SetScript("OnClick", onClick)
    return check
end

-- Choices for the pickers come from the game's own class, subclass and quality names.
-- The game still lists some retired categories ("Explosives (OBSOLETE)"). They are left out of the pick lists unless
-- an item you have carried is filed under one.
function Stat.InUse(class, sub)
    local function uses(entry)
        return entry.classID == class and (sub == nil or entry.subClassID == sub)
    end
    for _, item in ipairs(state.items or {}) do
        if uses(item) then return true end
    end
    for _, seen in pairs(SacksDB and SacksDB.seen or {}) do
        if uses(seen) then return true end
    end
    return false
end

local function ClassOptions(withAny)
    local options = withAny and { { label = "Any" } } or {}
    for id, name in ScanNames(ItemClassInfo) do
        local _, retired = ItemClassInfo(id)
        if not retired then
            options[#options + 1] = { label = name, value = id }
        elseif Stat.InUse(id) then
            options[#options + 1] = { label = name .. " (old)", value = id }
        end
    end
    return options
end

local function SubClassOptions(class, withAny)
    local options = withAny and { { label = "Any" } } or {}
    if class then
        for id, name in ScanNames(function(sub) return ItemSubClassInfo(class, sub) end) do
            local _, retired = ItemSubClassInfo(class, id)
            if not retired then
                options[#options + 1] = { label = name, value = id }
            elseif Stat.InUse(class, id) then
                options[#options + 1] = { label = name .. " (old)", value = id }
            end
        end
    end
    return options
end

-- Qualities are listed from lowest to highest and written in the colour the game uses for them.
local function ColouredQuality(quality)
    local colour = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not colour then return QualityName(quality) end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(colour.r * 255 + 0.5), math.floor(colour.g * 255 + 0.5),
        math.floor(colour.b * 255 + 0.5), QualityName(quality))
end

local function QualityOptions(withAny)
    local options, seen, values = withAny and { { label = "Any" } } or {}, {}, {}
    for _, value in pairs(Enum.ItemQuality) do
        if not seen[value] then
            seen[value] = true
            values[#values + 1] = value
        end
    end
    table.sort(values)
    for _, value in ipairs(values) do options[#options + 1] = { label = ColouredQuality(value), value = value } end
    return options
end

local FIELD_OPERATORS = {
    class = { "=", "~=" },
    sub = { "=", "~=", "<", "<=", ">", ">=" },
    quality = { "=", "~=", "<", "<=", ">", ">=" },
    name = { "contains", "!contains", "matches", "!matches" },
    item = { "=", "~=" },
    ilvl = { "=", "~=", "<", "<=", ">", ">=" }, level = { "=", "~=", "<", "<=", ">", ">=" },
    stack = { "=", "~=", "<", "<=", ">", ">=" }, price = { "=", "~=", "<", "<=", ">", ">=" },
    equip = { "=", "~=" }, bind = { "=", "~=" }, reagent = { "=" }, bound = { "=" }, family = { "=", "~=" },
}

local function OperatorOptions(field)
    local options = {}
    for _, op in ipairs(FIELD_OPERATORS[field]) do options[#options + 1] = { label = OP_TEXT[op], value = op } end
    return options
end

-- A drop-down list. It uses the game's own drop-down menu; if this client has none it becomes a button that steps
-- through the choices instead. With a title the label sits above it. x, y place it inside parent.
local dropdowns = 0
local measuring
local function TextWidth(text)
    measuring = measuring or UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measuring:SetText(text or "")
    local width = measuring:GetStringWidth()
    return type(width) == "number" and width or 0
end

local function MakeChoice(parent, title, x, y, getOptions, onChange, width)
    width = width or CHOICE_WIDTH
    local choice = { index = 1 }
    local function current()
        local options = getOptions()
        return options[choice.index] or options[1] or { label = "" }
    end

    local menu
    if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
        dropdowns = dropdowns + 1
        local ok, frame = pcall(CreateFrame, "Frame", "SacksDropdown" .. dropdowns, parent, "UIDropDownMenuTemplate")
        if ok and frame then menu = frame end
    end

    local below = 0
    if title then
        choice.title = MakeText(parent, "GameFontHighlightSmall", "TOPLEFT", x, y)
        choice.title:SetText(title)
        below = LABEL_HEIGHT
    end
    choice.width = width
    if menu then
        choice.frame = menu
        menu:SetPoint("TOPLEFT", parent, "TOPLEFT", x - DROPDOWN_INSET, y - below)
        UIDropDownMenu_SetWidth(menu, width)
        UIDropDownMenu_Initialize(menu, function(_, level)
            for index, option in ipairs(getOptions()) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.label
                info.checked = index == choice.index
                info.func = function()
                    choice.index = index
                    UIDropDownMenu_SetText(menu, option.label)
                    if onChange then onChange() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        function choice.update() UIDropDownMenu_SetText(menu, current().label) end
    else
        choice.frame = MakeButton(parent, title or "", width + DROPDOWN_INSET, function(_, mouse)
            local count = #getOptions()
            choice.index = (choice.index - 1 + (mouse == "RightButton" and -1 or 1)) % count + 1
            choice.update()
            if onChange then onChange() end
        end)
        choice.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - below)
        function choice.update() choice.frame:SetText(current().label) end
    end

    -- Sizes the box to the widest thing it can show (room for the arrow included) and returns that width.
    function choice.fit()
        local widest = 0
        for _, option in ipairs(getOptions()) do widest = math.max(widest, TextWidth(option.label)) end
        local fitted = math.ceil(widest) + 32 -- room for the dropdown arrow and a little air
        choice.width = fitted
        if menu then UIDropDownMenu_SetWidth(menu, fitted) else choice.frame:SetWidth(fitted + DROPDOWN_INSET) end
        return fitted
    end
    -- Moves the box so its visible left edge is at x.
    function choice.moveTo(left, top)
        choice.frame:ClearAllPoints()
        choice.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left - (menu and DROPDOWN_INSET or 0), (top or y) - below)
    end
    function choice.value() return current().value end
    function choice.reset()
        choice.index = 1
        choice.update()
    end
    function choice.select(value)
        choice.index = 1
        for index, option in ipairs(getOptions()) do
            if option.value == value then choice.index = index end
        end
        choice.update()
    end
    function choice.enable(enabled)
        if menu then
            local toggle = enabled and UIDropDownMenu_EnableDropDown or UIDropDownMenu_DisableDropDown
            if toggle then toggle(menu) end
        elseif enabled then
            choice.frame:Enable()
        else
            choice.frame:Disable()
        end
    end
    function choice.show(visible)
        if visible then choice.frame:Show() else choice.frame:Hide() end
        if choice.title then
            if visible then choice.title:Show() else choice.title:Hide() end
        end
    end
    choice.update()
    return choice
end

-- Adds a sack from a name and a rule, telling you why if it can't.
local function AddSack(name, rule)
    if #rule == 0 then return Say("pick at least one thing for the sack to take") end
    local group, problem = CreateSack(name, rule)
    if not group then return Say(problem) end
    Say("made the sack " .. group.name .. ": " .. Describe(rule))
    Refresh()
    return true
end

-- shared with the files after this one
ns.AddSack = AddSack
ns.ClassOptions = ClassOptions
ns.MakeButton = MakeButton
ns.MakeCheck = MakeCheck
ns.MakeChoice = MakeChoice
ns.MakeText = MakeText
ns.NativeFrame = NativeFrame
ns.OperatorOptions = OperatorOptions
ns.QualityOptions = QualityOptions
ns.SubClassOptions = SubClassOptions
