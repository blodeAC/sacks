-- sacks: Window.lua
-- The settings window: the list of sacks at the left (Nav.lua), and beside it one page at a time: a sack (SackTab.lua),
-- All items (ItemsTab.lua) or Settings (SettingsTab.lua).
local _, ns = ...
local BuildItems, BuildNav, BuildSack, BuildSettingsPage, CONTENT_TOP = ns.BuildItems, ns.BuildNav, ns.BuildSack, ns.BuildSettingsPage, ns.CONTENT_TOP
local MARGIN, MakeText, NativeFrame = ns.MARGIN, ns.MakeText, ns.NativeFrame
local RefreshItems, RefreshNav, RefreshSack, RefreshSettingsPage = ns.RefreshItems, ns.RefreshNav, ns.RefreshSack, ns.RefreshSettingsPage
local Say, ToggleOwnBags, WINDOW_WIDTH, state = ns.Say, ns.ToggleOwnBags, ns.WINDOW_WIDTH, ns.state

---------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------

-- The pages, by the name the list uses for them, and where the window keeps each.
local PAGES = { sack = "sack", defaults = "sack", items = "items", settings = "general" }

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

    window.active = "sack"
    window.nav = BuildNav(window)
    window.sack = BuildSack(window)
    window.items = BuildItems(window)
    window.general = BuildSettingsPage(window)
    for _, key in pairs(PAGES) do
        local page = window[key]
        page:SetPoint("TOPLEFT", window.nav, "TOPRIGHT", MARGIN, 0)
        page:Hide()
    end
end

-- Sizes the window to the list and the page shown: as wide as both, as tall as the taller.
function ns.FitWindow(pageHeight)
    local window, nav = ns.settings, ns.settings.nav
    local height = math.max(pageHeight or 0, nav.height or 0)
    nav.edge:SetHeight(height)
    window:SetSize((nav.width or 0) + MARGIN + WINDOW_WIDTH, CONTENT_TOP + height + MARGIN)
end

function ns.RefreshSettings()
    local window = ns.settings
    if not window or not window:IsShown() or not window.general then return end
    RefreshNav()
    if window.active == "items" then
        RefreshItems()
    elseif window.active == "settings" then
        RefreshSettingsPage()
    else
        RefreshSack()
    end
end

-- Shows one page: "sack" (the sack picked in the list), "defaults" (the same page, for the defaults), "items" or
-- "settings".
function ns.ShowView(name)
    local window = ns.settings
    window.active = PAGES[name] and name or "sack"
    local shown = PAGES[window.active]
    for _, key in pairs(PAGES) do
        if key ~= shown then window[key]:Hide() end
    end
    window[shown]:Show()
    ns.RefreshSettings()
end

-- Anything that goes wrong while building or filling the window is printed, never swallowed.
local function Guard(step, ...)
    local ok, err = pcall(step, ...)
    if not ok then Say("settings window error: " .. tostring(err)) end
    return ok
end

-- Builds the window the first time it is needed. Returns whether it is there.
local function EnsureWindow()
    if not ns.settings then
        Guard(BuildSettings)
        if ns.settings and ns.settings.general then
            ns.settings:Show()
            Guard(ns.ShowView, "sack")
            ns.settings:Hide()
        end
    end
    return ns.settings and ns.settings.general and true or false
end

function ns.ToggleSettings()
    if not EnsureWindow() then return end
    if ns.settings:IsShown() then
        ns.settings:Hide()
    else
        ns.settings:Show()
        Guard(ns.RefreshSettings)
    end
end

-- Opens the window on one sack's page (right-click a sack, or a sack named in the All items table).
function ns.EditSack(group)
    if not EnsureWindow() then return end
    state.editing = group
    ns.settings:Show()
    Guard(ns.ShowView, "sack")
end

-- A small bag icon you can drag anywhere; clicking it opens the settings.
local function MakeIcon()
    SacksDB.icon = SacksDB.icon or {}
    local saved = SacksDB.icon
    saved.angle = saved.angle or 200
    local host = Minimap or UIParent
    -- Built like spelltips' button: the tracking-border art is drawn for a 31-pixel button with the icon in its middle,
    -- so the button is exactly that size and the ring sits centred on the edge of the minimap.
    local button = CreateFrame("Button", "SacksIcon", host)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.dragged = false
    button.texture = button:CreateTexture(nil, "BACKGROUND")
    button.texture:SetSize(20, 20)
    button.texture:SetPoint("CENTER", 0, 1)
    button.texture:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Sits on the edge of the minimap at an angle you choose by dragging it around.
    local function place()
        local radius = (Minimap and Minimap:GetWidth() or 140) / 2 + 5
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
