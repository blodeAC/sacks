-- sacks: Sort.lua
local _, ns = ...
local DEFAULT_SORT, IsBlankLine, Matches, STATS = ns.DEFAULT_SORT, ns.IsBlankLine, ns.Matches, ns.STATS
local Stat = ns.Stat

-- The order inside a sack: pinned items first (in the order they were pinned), then each sort key in turn, then the
-- bag position so the order never flickers.
local SORT_KEYS = {
    name = { label = "Name", value = function(item) return item.name:lower() end },
    class = { label = "Class", value = function(item) return item.classID or -1 end },
    sub = { label = "Subclass", value = function(item) return item.subClassID or -1 end },
    quality = { label = "Quality", value = function(item) return item.quality end },
    count = { label = "Number carried", value = function(item) return item.count or 1 end },
    position = { label = "Bag position", value = function(item) return item.bag end },
}
local SORT_KEY_ORDER = { "name", "class", "sub", "quality" }
-- Every other field a rule can test is a sort key too, read the same way the rules read it. An equip slot sorts in the
-- order the slots are listed in the rule editor; the rest sort by their number.
for _, field in ipairs({ "ilvl", "level", "price", "equip", "bind", "bound", "reagent", "family", "stack" }) do
    local stat = STATS[field]
    local label = field == "stack" and "Max stack size" or (stat.text:gsub("^%l", string.upper))
    if field == "equip" then
        local slotRank = {}
        for index, option in ipairs(Stat.Options("equip")) do slotRank[option.value] = index end
        SORT_KEYS[field] = { label = label, value = function(item) return slotRank[stat.get(item) or "NONE"] or 0 end }
    else
        SORT_KEYS[field] = { label = label, value = function(item) return tonumber(stat.get(item)) or -1 end }
    end
    SORT_KEY_ORDER[#SORT_KEY_ORDER + 1] = field
end
SORT_KEY_ORDER[#SORT_KEY_ORDER + 1] = "count"
SORT_KEY_ORDER[#SORT_KEY_ORDER + 1] = "position"

-- An "Items matching" step puts the items that match its rule first, or last when it is descending. A rule with no
-- lines matches nothing, so the step then changes nothing.
local function MatchRank(rule, item)
    if not rule then return 1 end
    for _, condition in ipairs(rule) do
        -- a rule with only empty text lines has nothing to match yet
        if not IsBlankLine(condition) then
            if Matches(rule, item) then return 0 end
            return 1
        end
    end
    return 1
end

-- Sorting steps saved by an earlier version as one "buckets" step become one "Items matching" step per bucket,
-- which sorts items exactly the same way.
-- Subclass ids are labels, not a scale, so only "is" and "is not" mean anything for them. A line saved with an
-- ordered comparison on one becomes "is".
local ORDERED = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }
local function FixRule(rule)
    for _, clause in ipairs(rule or {}) do
        if (clause.field == "sub" or clause.field == "class") and ORDERED[clause.op] then
            clause.op = "="
            ns.Say("a " .. clause.field .. " line used < or > (meaningless for ids). It now reads 'is'.")
        end
    end
end

local function UpgradeSort(group)
    FixRule(group.rule)
    for _, spec in ipairs(group.sort or {}) do FixRule(spec.rule) end
    -- Reverse is gone. What it was for, the first items at the top left of a sack pinned at a bottom corner, is what
    -- "Like a page" does, and that keeps pins first.
    if group.reverse then
        local anchor = group.anchor or ns.DEFAULT_ANCHOR
        if (anchor == "BOTTOMLEFT" or anchor == "BOTTOMRIGHT") and group.flow ~= "COLUMNS" then group.flow = "PAGE" end
    end
    group.reverse = nil
    if not group.sort then return end
    local list = {}
    for _, spec in ipairs(group.sort) do
        if spec.buckets then
            for _, bucket in ipairs(spec.buckets) do
                list[#list + 1] = { key = "match", rule = bucket.rule or {} }
            end
        else
            if spec.key == "match" then spec.descending = nil end
            list[#list + 1] = spec
        end
    end
    group.sort = list
end

local function SortItems(group, items)
    local rank = {}
    for index, id in ipairs(group.pins or {}) do rank[id] = index end
    local keys = group.sort or ns.Default("sort", DEFAULT_SORT)
    -- Whatever the steps leave tied, stacks of the same item stay together (at the place of the first one in your bags),
    -- and only then does bag position decide, so the order is steady and identical stacks are never split up by chance.
    local first = {}
    for _, item in ipairs(items) do
        local place = item.bag * 1000 + item.slot
        local id = item.itemID or 0
        if not first[id] or place < first[id] then first[id] = place end
    end
    table.sort(items, function(a, b)
        local rankA, rankB = rank[a.itemID] or math.huge, rank[b.itemID] or math.huge
        if rankA ~= rankB then return rankA < rankB end
        for _, spec in ipairs(keys) do
            local key = SORT_KEYS[spec.key]
            if spec.key == "match" then
                key = { value = function(item) return MatchRank(spec.rule, item) end }
            end
            if key then
                local left, right = key.value(a), key.value(b)
                if left ~= right then
                    if spec.descending then return left > right end
                    return left < right
                end
            end
        end
        local firstA, firstB = first[a.itemID or 0], first[b.itemID or 0]
        if firstA ~= firstB then return firstA < firstB end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
end


ns.SORT_KEYS = SORT_KEYS
ns.SORT_KEY_ORDER = SORT_KEY_ORDER
ns.SortItems = SortItems
ns.UpgradeSort = UpgradeSort
