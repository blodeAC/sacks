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
            pcall(CloseAllBags)
        else
            for _, frame in ipairs(OwnBagFrames()) do pcall(frame.Hide, frame) end
        end
    else
        state.ownBagsAllowed = true
        local open = OpenAllBags or ToggleAllBags
        if open then pcall(open) end
    end
end

local hooked = {}
local function HookOwnBags()
    for _, frame in ipairs(OwnBagFrames()) do
        if not hooked[frame] then
            hooked[frame] = true
            frame:HookScript("OnShow", HideOwnBags)
            frame:HookScript("OnHide", function()
                if not OwnBagsShown() then state.ownBagsAllowed = false end
            end)
        end
    end
end

-- The game opens its own bags by itself at vendors, mail and so on. Those are blocked; B and the bag buttons go
-- through these three functions, so anything they open is the player's own doing and is left open.
local function WrapUserBagToggles()
    for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
        local original = _G[name]
        if type(original) == "function" and not state.wrapped then
            _G[name] = function(...)
                state.userBags = true
                local results = { pcall(original, ...) }
                state.userBags = false
                if OwnBagsShown() then state.ownBagsAllowed = true end
                if not results[1] then error(results[2], 0) end
                return unpack(results, 2)
            end
        end
    end
    state.wrapped = true
end

-- shared with the files after this one
ns.HideOwnBags = HideOwnBags
ns.HookOwnBags = HookOwnBags
ns.ToggleOwnBags = ToggleOwnBags
ns.WrapUserBagToggles = WrapUserBagToggles
