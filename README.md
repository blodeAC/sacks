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
- Drag a sack by its title bar to move it. Edges snap to the screen and to other sacks (hold Alt for a free drag). A sack dropped against another one stays docked to it when either changes size.
- `B` and the bag buttons still open the game's own bags. The option on the Sacks tab stops the game opening them by itself (vendors and so on).
- At a vendor, the sacks stack beside the vendor window, each keeping its own layout, and fill gaps beside narrower sacks.

## Settings window

**Sacks** - your sacks in priority order (Up/Down to reorder, Edit, Remove), a quick way to start a new one, and defaults that apply to every sack.

**Items** - every kind of item you carry or have carried, with what the game says about it. Click items to select them and the sack's rule lines are filled in from what they share; edit the lines by hand any time. Columns follow the fields the lines use.

**Layout** - how the selected sack grows (corner, flow, slots per row), its title, which end shows the empty slot, its sort order, and the items pinned to the front.

## Rules

A rule is a list of lines. Each line is `field operator value`, joined with AND (or OR where a line says so; AND binds first). A sack with no lines takes nothing.

| Field | Meaning |
| --- | --- |
| class, sub | item class and subclass |
| quality | item quality (comparisons like "above Poor" work) |
| name | name pattern |
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
| ItemsTab.lua | the Items tab |
| LayoutTab.lua | the Layout tab |
| SacksTab.lua | the Sacks tab |
| Window.lua | the settings window and minimap icon |
| Core.lua | events |

Saved settings are in the `SacksDB` saved variable.
