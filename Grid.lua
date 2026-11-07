-- sacks: Grid.lua
local _, ns = ...
local PADDING, SLOT_GAP = ns.PADDING, ns.SLOT_GAP

-- Where a sack's empty slot goes: its own setting, else the default for every sack, else after the items.
-- Only the Other sack has the empty slot (it is the one that always exists); the rest never show one.
local function BlankMode(group)
    if not group.fixed then return "NONE" end
    return group.blank or "LAST"
end

-- Which cell of the grid an item goes in: filling across then wrapping, or down then wrapping.
local function GridCell(index, layout)
    if layout.flow == "COLUMNS" then
        return math.floor((index - 1) / layout.wrap), (index - 1) % layout.wrap
    end
    return (index - 1) % layout.wrap, math.floor((index - 1) / layout.wrap)
end

-- How many columns and rows hold this many cells.
local function GridDimensions(layout, cells)
    cells = math.max(1, cells)
    if layout.flow == "COLUMNS" then
        return math.ceil(cells / layout.wrap), math.min(layout.wrap, cells)
    end
    return math.min(layout.wrap, cells), math.ceil(cells / layout.wrap)
end

-- How big a sack is, in pixels, with that many columns and rows.
local function GridSize(columns, rows, size, topSpace, bottomSpace)
    return PADDING * 2 + columns * size + (columns - 1) * SLOT_GAP, topSpace + rows * size + (rows - 1) * SLOT_GAP + bottomSpace
end

-- Put a slot (or a combat ghost) in the cell with this number. geom is the sack's measurements: width, height, size,
-- layout, topSpace, bottomSpace, and whether the first cell is at the right or bottom. The first cell is next to the
-- corner the sack grows from. A docked sack lists the cells in reading order (geom.reading).
local function PlaceInGrid(target, index, geom)
    if geom.reading then index = geom.reading[index] end
    local column, row = GridCell(index, geom.layout)
    local x = column * (geom.size + SLOT_GAP)
    local y = row * (geom.size + SLOT_GAP)
    x = geom.fromRight and (geom.width - PADDING - geom.size - x) or (PADDING + x)
    y = geom.fromBottom and (geom.height - geom.bottomSpace - geom.size - y) or (geom.topSpace + y)
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", x, -y)
end

-- At a vendor or the bank every sack is laid out like a page, from the top left, across then down. The cells keep the
-- order you normally read them in (left to right, top to bottom), so a sack that grows up or left looks the
-- same, just packed to the top left. This numbers them: reading[cell] is the place the cell takes on the page.
local function ReadingOrder(layout, columns, rows, cells)
    local fromRightNow = layout.anchor == "TOPRIGHT" or layout.anchor == "BOTTOMRIGHT"
    local fromBottomNow = layout.anchor == "BOTTOMLEFT" or layout.anchor == "BOTTOMRIGHT"
    local list = {}
    for index = 1, cells do
        local column, row = GridCell(index, layout)
        local visualColumn = fromRightNow and (columns - 1 - column) or column
        local visualRow = fromBottomNow and (rows - 1 - row) or row
        list[index] = { index = index, key = visualRow * columns + visualColumn }
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    local reading = {}
    for rank, entry in ipairs(list) do reading[entry.index] = rank end
    return reading
end

ns.GridDimensions = GridDimensions
ns.GridSize = GridSize
ns.ReadingOrder = ReadingOrder
ns.PlaceInGrid = PlaceInGrid
ns.BlankMode = BlankMode
ns.GridCell = GridCell
