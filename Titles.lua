-- sacks: Titles.lua
local _, ns = ...

-- Titles are a template: {name} {count} {items} {value} {free} {special} are filled in from what the sack holds.
local TITLE_DEFAULT = "{name} ({count})"
local TITLE_PIECES = {
    { token = "{name}", about = "the sack's name" },
    { token = "{count}", about = "kinds of item in it" },
    { token = "{items}", about = "total items, counting stacks" },
    { token = "{value}", about = "vendor sell value of all of it" },
    { token = "{free}", about = "free slots in normal bags" },
    { token = "{special}", about = "free slots in special bags" },
}

local function Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local text = ""
    if gold > 0 then text = text .. gold .. "|cffffd700g|r " end
    if silver > 0 or gold > 0 then text = text .. silver .. "|cffc7c7cfs|r " end
    return text .. rest .. "|cffeda55fc|r"
end

local function ExpandTitle(group, items, free, special)
    local stacks, value = 0, 0
    for _, item in ipairs(items) do
        local count = item.count or 1
        stacks = stacks + count
        value = value + (item.sellPrice or 0) * count
    end
    local pieces = { name = group.name, count = #items, items = stacks, value = Money(value), free = free, special = special }
    local template = group.titleText or TITLE_DEFAULT
    return (template:gsub("{(%w+)}", function(token)
        local found = pieces[token:lower()]
        if found ~= nil then return tostring(found) end
    end))
end


ns.ExpandTitle = ExpandTitle
ns.TITLE_DEFAULT = TITLE_DEFAULT
ns.TITLE_PIECES = TITLE_PIECES
