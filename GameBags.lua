-- sacks: GameBags.lua
local _, ns = ...
local state = ns.state

---------------------------------------------------------------------------------------------------
-- The game's own bags: hidden whenever they open, unless you turn that off in the settings
---------------------------------------------------------------------------------------------------

local function OwnBagFrames()
    local frames = { ContainerFrameCombinedBags }
    local index = 1
    while _G["ContainerFrame" .. index] do
        frames[#frames + 1] = _G["ContainerFrame" .. index]
        index = index + 1
    end
    return frames
end

local function OwnBagsShown()
    for _, frame in ipairs(OwnBagFrames()) do
        if frame:IsShown() then return true end
    end
    return false
end

-- They stay open when you opened them yourself (see ToggleOwnBags) and while the bank is open, since the bank's
-- own bags use the same windows.
local function HideOwnBags()
    if SacksDB.hideBags == false or InCombatLockdown() or state.ownBagsAllowed or state.userBags then return end
    if state.bank or (BankFrame and BankFrame:IsShown()) then return end
    for _, frame in ipairs(OwnBagFrames()) do
        if frame:IsShown() then pcall(frame.Hide, frame) end
    end
end

-- Opens or closes the game's own bags on purpose, so you can check them against the sacks.
local function ToggleOwnBags()
    if OwnBagsShown() then
        state.ownBagsAllowed = false
        if CloseAllBags then
            (securecall or pcall)(CloseAllBags)
        else
            for _, frame in ipairs(OwnBagFrames()) do pcall(frame.Hide, frame) end
        end
    else
        state.ownBagsAllowed = true
        local open = OpenAllBags or ToggleAllBags
        if open then (securecall or pcall)(open) end -- securecall: the game opens them without this add-on's taint
    end
end

local hooked = {}
local function HookOwnBags()
    for _, frame in ipairs(OwnBagFrames()) do
        if not hooked[frame] then
            hooked[frame] = true
            -- one frame later, so the post-hooks below can say it was the player's own toggle first
            frame:HookScript("OnShow", function()
                if C_Timer and C_Timer.After then C_Timer.After(0, HideOwnBags) else HideOwnBags() end
            end)
            frame:HookScript("OnHide", function()
                if not OwnBagsShown() then state.ownBagsAllowed = false end
            end)
        end
    end
end

-- The game opens its own bags by itself at vendors, mail and so on. Those are blocked; B and the bag buttons go
-- through these three functions, so anything they open is the player's own doing and is left open. They are only
-- hooked after the fact (hooksecurefunc), never replaced: replacing a game function makes everything it does
-- "tainted", and the game then refuses to use an item clicked in its own bags.
local function WrapUserBagToggles()
    if state.wrapped or not hooksecurefunc or not (C_Timer and C_Timer.After) then return end
    state.wrapped = true
    for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function()
                state.userBags = true -- seen by the bag-hiding check, which runs one frame after the bags appeared
                C_Timer.After(0, function()
                    state.userBags = false
                    if OwnBagsShown() then state.ownBagsAllowed = true end
                end)
            end)
        end
    end
end

-- shared with the files after this one
ns.HideOwnBags = HideOwnBags
ns.HookOwnBags = HookOwnBags
ns.ToggleOwnBags = ToggleOwnBags
ns.WrapUserBagToggles = WrapUserBagToggles
