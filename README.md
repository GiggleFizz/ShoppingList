# Shopping List

A crafting shopping list for World of Warcraft 3.3.5a (Wrath of the Lich King).

Queue the things you want to make; see every reagent they add up to, how many
you already have, and how many you are short. Any reagent that is itself
craftable can be drilled down to its own inputs — bars to ore, cloth to bolts,
as deep as the recipe tree goes — whether or not your character knows that
recipe.

Built for the profession specialisation quests ("The Way of the Weaponsmith"
wants four Moonsteel Broadswords, four Massive Iron Axes, two Heavy Mithril
Axes and two Big Black Maces — that is a lot of bars to count), but it works
for anything.

## Using it

- Open any trade-skill window and **shift-click a recipe** to add it to the
  list. (If a chat box is open the shift-click pastes the link into chat, as
  it always has; the list only takes the click when nothing else would.)
- **+ / −** change the quantity of a craft; **x** removes it; **Clear** empties
  the list.
- **Click a craft's name** to open its profession window at that recipe, with
  the count box set to what you still need. (It casts the profession for you,
  so it can't happen in combat; and if this character doesn't know the
  profession the line is dimmed — hold Shift to see which of your other
  characters can make it, when DataStore_Crafts is installed.)
- Below the rule, the **materials**: `32 x Mithril Bar   have 10, short 22`.
  Red means you are short; green means you have enough.
- A `>` after a material means it is craftable — **click it** to drill down.
  The material is then shown dimmed and its own inputs take its place in the
  totals — only for the part you don't already hold: `32 x Mithril Bar   have
  10, make 22` asks for 22 ore. Click the dimmed line to collapse it again.
- **Each craft you complete counts its line down.** At zero the line stays as
  "(done)" until you remove it, so you can see what you finished.
- **Hold Shift** over any line for its item tooltip (and how many your other
  characters hold, when DataStore_Containers is installed; the bank you last
  visited counts towards "have").
- A **List** button sits on the trade-skill window's title row; `/shop` (or
  `/shoppinglist`) toggles the window too; `/shop clear` empties it.
- A **minimap button**: left-click opens or closes the list, right-click clears
  it, drag it round the rim to move it.
- The list, drill-downs, window position and minimap-button position are saved
  per character.

## What it knows

`ShoppingListData.lua` is generated from the game's own `Spell.dbc` (3.3.5):
every craftable item in the game — 3,149 recipes across all professions,
including smelting, cooking and first aid — with its reagents and yield, and
the spell that opens each profession's window. Item
names are resolved by your client at runtime, so the addon works in any
locale. If you shift-click a recipe the data does not know, nothing happens.

## Installing

Copy the `ShoppingList` folder into `Interface/AddOns/`. New addon folders are
picked up on a full client start, not on `/reload`.

## Development

`dev/` holds the maintainer tooling and is not needed to run the addon:

- `dev/gen_shoppinglist.py generate|verify` — regenerates `ShoppingListData.lua`
  (and `dev/shoppinglist-manifest.tsv`, a human-readable review copy with
  item names) from a server's `Spell.dbc`, `SkillLine.dbc`,
  `SkillLineAbility.dbc` and `item_template`. Paths at the top of the script.
- `dev/test_harness.lua` — offline test suite (`lua5.1 dev/test_harness.lua`
  from the addon root); stubs the client, loads the real data, and re-derives
  every expected total independently.

## Credits

Written by GiggleFizz with Claude (Anthropic) as pair programmer — the design
rulings are the human's, the code was written together, and every claim about
the client or the game data was read from the files rather than remembered.
MIT licensed.
