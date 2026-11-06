-- sacks: Window.lua
local _, ns = ...
local BuildItems, BuildLayout, BuildSacks, HEADER, ICON_SIZE, MARGIN = ns.BuildItems, ns.BuildLayout, ns.BuildSacks, ns.HEADER, ns.ICON_SIZE, ns.MARGIN
local MakeButton, MakeText, NativeFrame, RefreshItems, RefreshLayout, RefreshSacks = ns.MakeButton, ns.MakeText, ns.NativeFrame, ns.RefreshItems, ns.RefreshLayout, ns.RefreshSacks
local SLOT_GAP, Say, ShowTab, ToggleOwnBags, WINDOW_WIDTH = ns.SLOT_GAP, ns.Say, ns.ShowTab, ns.ToggleOwnBags, ns.WINDOW_WIDTH

---------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------

local function BuildSettings()
    -- One window only: it is remembered the moment it exists, so a failure further down can never lead to a second one.
    local window = NativeFrame("Frame", UIParent, "BasicFrameTemplateWithInset")
    ns.settings = window
    window:SetSize(WINDOW_WIDTH, 300)
    window:SetPoint("TOP", UIParent, "TOP", 0, -30) -- the top edge stays put if the window ever has to grow
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- The game re-anchors a dragged frame by its own choice of point; pin the top left corner so the window
        -- always grows and shrinks downward from where you put it.
        local left, top = self:GetLeft(), self:GetTop()
        if type(left) == "number" and type(top) == "number" then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    window:Hide()
    if window.TitleText then
        window.TitleText:SetText("sacks")
    else
        MakeText(window, "GameFontNormalLarge", "TOP", 0, -8):SetText("sacks")
    end
    if not window.CloseButton then
        local close = NativeFrame("Button", window, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
    end
    tinsert(UISpecialFrames, "SacksSettings")
    _G.SacksSettings = window

    window.tabs = {}
    local previous
    for _, tab in ipairs({ { "sacks", "Sacks" }, { "items", "Items" }, { "layout", "Layout" } }) do
        local button = MakeButton(window, tab[2], nil, function() ShowTab(tab[1]) end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", SLOT_GAP, 0)
        else
            button:SetPoint("TOPLEFT", MARGIN, -(HEADER + 6))
        end
        window.tabs[tab[1]] = button
        previous = button
    end

    window.sacks = BuildSacks(window)
    window.items = BuildItems(window)
    window.layout = BuildLayout(window)
    window.active = "sacks"
end

function ns.RefreshSettings()
    if not ns.settings or not ns.settings:IsShown() or not ns.settings.layout then return end
    if ns.settings.active == "items" then
        RefreshItems()
    elseif ns.settings.active == "layout" then
        RefreshLayout()
    else
        RefreshSacks()
    end
end

-- Anything that goes wrong while building or filling the window is printed, never swallowed.
local function Guard(step, ...)
    local ok, err = pcall(step, ...)
    if not ok then Say("settings window error: " .. tostring(err)) end
    return ok
end

function ns.ToggleSettings()
    if not ns.settings then
        Guard(BuildSettings)
        if ns.settings and ns.settings.layout then Guard(ShowTab, "sacks") end
    end
    if not ns.settings then return end
    if ns.settings:IsShown() then
        ns.settings:Hide()
    else
        ns.settings:Show()
        Guard(ns.RefreshSettings)
    end
end

-- A small bag icon you can drag anywhere; clicking it opens the settings.
local function MakeIcon()
    SacksDB.icon = SacksDB.icon or {}
    local saved = SacksDB.icon
    saved.angle = saved.angle or 200
    local host = Minimap or UIParent
    local button = CreateFrame("Button", "SacksIcon", host)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.dragged = false
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(25, 25)
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetSize(20, 20)
    button.texture:SetPoint("TOPLEFT", 6, -5)
    button.texture:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    button.texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Sits on the edge of the minimap at an angle you choose by dragging it around.
    local function place()
        local radius = (Minimap and Minimap:GetWidth() or 140) / 2 + 10
        local angle = math.rad(saved.angle)
        button:ClearAllPoints()
        button:SetPoint("CENTER", host, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    place()
    local arc = math.atan2 or math.atan
    button:SetScript("OnDragStart", function(self)
        self.dragged = true
        if not Minimap then return end
        self:SetScript("OnUpdate", function()
            local centerX, centerY = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local x, y = GetCursorPosition()
            if type(centerX) ~= "number" or not x then return end
            saved.angle = math.deg(arc(y / scale - centerY, x / scale - centerX))
            place()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnClick", function(self, mouse)
        if self.dragged then
            self.dragged = false
            return
        end
        if mouse == "RightButton" then return ToggleOwnBags() end
        ns.ToggleSettings()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("sacks")
        GameTooltip:AddLine("Click for settings. Right click to open or close the game's own bags. Drag to move this icon around the minimap.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- shared with the files after this one
ns.MakeIcon = MakeIcon
