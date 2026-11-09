# sacks

A bag addon for WoW Forever. Instead of one big bag, your items are shown as small groups called **sacks**. Each sack takes the items that match its rules, sizes itself to its contents, and sits wherever you drag it.

Every item you carry is always in exactly one sack. The first sack (from the top of the list) whose rules match an item takes it, and the permanent fallback sack, **Other**, takes everything nothing else wants, so no item or slot ever goes unaccounted for.

## Install

With [instawow](https://github.com/layday/instawow):

```
instawow install github:blodeAC/sacks
```

or copy this folder to `World of Warcraft/_forever_/Interface/AddOns/sacks`.

## Using it

- Click the bag icon on the minimap edge, or type `/sacks`, to open the settings window.
- Right-click an item to use it. With a vendor, bank, guild bank, trade window or the mailbox's send tab open, it is sold, banked, traded or attached instead, like the game's own bags; with the mailbox's inbox or the auction house open, right-click does nothing. An item is never used or equipped while one of those windows is open.
- Right-click a sack's title to open it in the settings window. Hovering the title says what the sack is docked to.
- Drag a sack by its title bar to move it. Dropped flush against another sack, it docks to it and follows it; dropped against two (in a corner), it docks to one and keeps to its side of the other. A sack that grows into one beside it pushes that one aside, and it comes back when there is room. Edges snap to the screen and to other sacks (hold Alt for a free drag). A sack dropped against another one stays docked to it when either changes size.
- `B` and the bag buttons still open the game's own bags. The option on the Settings page stops the game opening them by itself (vendors and so on).
- At a vendor or the bank, the sacks stack beside that window and fill gaps beside narrower sacks. Each is laid out like a page from the top left, with the items in the same reading order as normal, then goes back to its own corner and flow afterwards. Right-click sells there, as in the game's bags.
- A sack can use its items on left click, like an action bar (the "Left-click uses the items" box at the top of the sack's page). Hold and drag to move an item. At a vendor left click just picks the item up. Such sacks are marked with a coloured title and border, and their name in the list is in that colour; the colour (or no marking) is chosen on the Settings page.
- On a sack's page, "Copy layout from" (Looks) copies another sack's corner, fill direction, title position, slots per row, title text, and "Copy order from" (Order) copies its sort steps. Neither copies the rule, pins or position.

## Settings window

At the left is the list: **All items**, **Settings**, then your sacks in priority order (the first sack whose lines an item fits gets it). Drag a sack up or down to change its place; Combat loot stays first and Other last. A sack's number is how many slots it shows now. **+ New sack** makes one with no lines (it takes nothing until you give it some) and puts its name ready to type over.

**A sack's page** - everything about that sack in one place:
- its name (Enter or click away to rename), "Left-click uses its items", Move to the middle of the screen, Delete sack;
- **Takes**: the table of items, then its lines under it. Drag a line by its dots to move it (each and/or stays where it is). Changes apply as you make them; **Undo changes** goes back to what it took when you opened it. In the table, green rows are in this sack and amber rows fit its lines but a sack above it in the list takes them. Click a row to add it as an "Exact item" line (again to take it out); an "Exact item" line also takes a typed name, or any part of a name only one item you have carried has;
- **Looks**: a picture of the screen with the sack in it, drawn with one more item than fits in a row and numbered in the order it fills. Click a quarter to pin the sack to that corner. Fill: Like a page (top left, across then down, wherever it is pinned; the starting fill, with the title above), or Across or Down from the pinned corner. Title, slots per row, the empty slot (Other), title text;
- **Order**: sort steps, then the items as icons, laid out like the sack. Click an icon to pin it to the front (gold frame) or unpin it; drag a pinned icon onto another pinned one to move it there. Hover an icon for its name, how many you have, and whether a sack above takes it now.

Sacks whose items left-click uses have their name in the list in the marking colour, the same colour as the "Left-click uses its items" box on their page.

**All items**, **Settings**, then your sacks in priority order (the first sack whose lines an item fits gets it). Drag a sack up or down to change its place; Combat loot stays first and Other last. A sack's number is how many slots it shows now. **+ New sack** makes one with no lines (it takes nothing until you give it some) and puts its name ready to type over.

**A sack's page** - everything about that sack in one place:
- its name (Enter or click away to rename), Move to the middle of the screen, Delete sack, and the left-click box;
- **Takes**: its lines. Changes apply as you make them; **Undo changes** goes back to what it took when you opened it. An "Exact item" line takes the item you type the name of (or any part of the name only one item you have carried has);
- **Looks**: corner, fill direction, title position, slots per row, the empty slot (Other), title text;
- **Order**: sort steps, and the items in the order shown, with pins.

**Defaults** - the same Looks and Order as a sack's page, for every sack that has no setting of its own. On a sack's page, **Use defaults** (Looks, Order) drops that sack's own settings; on the Defaults page, **Apply to every sack** does it for all of them (Undo last reset or import brings them back). The corner is only given to new sacks.

**All items** - every kind of item you carry or have carried, with what the game says about it and the sack it goes to. Select items (Ctrl-click for more) and **New sack from selection** makes a sack whose lines come from what they share; **Sack from search** makes one from the search text. Right-click an item to open its sack.

**Settings** - the game's own bags, the free-slots box, the gold box (your gold with the game's coin icons, placed and docked like a sack), the left-click marking colour, bag space, export/import/undo, and reset to the starting sacks.

### Sorting

A sack's order is a list of up to 10 steps, one row each. A step is either a **rule** ("Items where tooltip contains mana": the items that match come first) or a **sort field** (any field a rule can test, plus number carried and bag position, ascending or descending). A step only decides between two items when every step above it ties. Pinned items always come first. **+ And** adds another condition to a rule step. Drag a step by its dots to move it. For example, one rule step `tooltip contains mana` followed by one `tooltip contains heals` puts mana drinks first, then bandages, then everything else.

## Holding still

While the mouse is on a sack, the sacks hold still. Selling, banking or using items leaves their slots where they are, dimmed and inert, so the next item under your cursor stays put. New items wait. Counts still update. When the mouse leaves the sacks, everything catches up at once.

## Rules

A rule is a list of lines. Each line is `field operator value`, joined with AND (or OR where a line says so; AND binds first). A sack with no lines takes nothing.

Every text box (name, tooltip, exact item, and the search above the item table) takes Lua patterns, any case: `.*` any run of characters, `^` start, `$` end, `[abc]` one of, `%d` a digit, and `|` between alternatives. Text typed as is always finds itself word for word too, so a name with a `-` or `(` in it needs no escaping.

| Field | Meaning |
| --- | --- |
| class, sub | item class and subclass |
| quality | item quality (comparisons like "above Poor" work) |
| name | text in the item's name |
| tooltip | text in the item's tooltip, such as "mana" or "health" |
| item | one exact item |
| ilvl, level | item level, required level |
| stack | stack size |
| price | sell price |
| equip | equip slot |
| bind | bind type |
| reagent | crafting reagent |
| bound | soulbound |
| family | special bag type (mining, herbs, ...); "=" means it fits that bag |

## Titles

A sack's title can use `{name} {count} {items} {value} {free} {special}`. The free-slots number can also be shown in its own box.

## Commands

```
/sacks                       open the settings window
/sacks list                  every sack and what it takes
/sacks new <name> class=.. sub=.. quality=.. minq=.. maxq=.. id=..
/sacks remove <name>
/sacks cols <name or all> <number>
/sacks anchor <name> <frame>
/sacks classes               item classes and subclasses
/sacks fields [item link]    everything the game reports for an item
/sacks probe                 every item in your bags
/sacks bags                  open or close the game's own bags
/sacks reset                 back to the starting sacks
```

## Layout of the code

Files load in the order listed in `sacks.toc`; each shares one table (`ns`) with the ones after it.

| File | What it holds |
| --- | --- |
| Shared.lua | constants, the shared state table, small helpers |
| Bags.lua | reading the bags |
| Rules.lua | rule matching, the fields a rule can test, default sacks |
| Sacks.lua | drawing sacks, placement, docking and snapping, vendor layout, sack creation |
| GameBags.lua | hiding and showing the game's own bags |
| Commands.lua | the probe window and slash commands |
| Widgets.lua | shared settings-window widgets and option lists |
| ItemsTab.lua | the All items page, and the rule lines used by Takes and the sort steps |
| SackTab.lua | a sack's page: name and buttons, Takes, Looks, Order |
| SettingsTab.lua | the Settings page |
| Nav.lua | the list of sacks at the left of the window, with drag to reorder |
| Window.lua | the settings window, switching pages, and the minimap icon |
| Core.lua | events |

Saved settings are in the `SacksDB` saved variable.
