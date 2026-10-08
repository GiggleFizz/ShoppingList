# Shopping List — Statement (endorsed 2026-10-08)

**Requirement.** A per-character shopping list of things to craft: shift-click
a recipe in any trade-skill window to add it; +/- adjusts quantity; the window
shows the crafts and, below a rule, every reagent summed with need / have /
short; any reagent that is itself craftable can be drilled down on demand,
its own inputs then counting instead of it. Survives profession swaps,
logouts and reloads. Publishable standard.

**Rulings.** A-1 data generated from Spell.dbc (his switch after the window-only
limitation surfaced: "potentially valuable feature") · B shift-click adds,
+/- in our window · C drill-down on demand per line, nested · D-1 need/have/
short with DataStore bank + alts · E-1 standalone movable window · F "Shopping
List" · G quest integration out ("we can track craftables the same as every
other").

**Design.** dev/gen_shoppinglist.py -> ShoppingListData.lua (3,149 recipes:
[result] = {spell, skill, numMade, reagent, count, ...}; names resolved by the
client at runtime; manifest with names + alternate spells; verify_stack gate).
ShoppingList.lua: model (Add/SetCount/Remove/Clear/ToggleExpand/Materials —
expanded craftables replaced by ceil(qty/numMade) x their inputs, depth 8);
Lines (crafts, rule, drilled intermediates dimmed, leaves with have/short);
Have = GetItemCount(id, true) or DataStore's own bags+bank if larger, alts in
the tooltip; FauxScrollFrame window (18 rows x 20 px, rows 22 px narrower than
the frame for the bar), drag + persisted position, Escape closes; "List"
button on the trade-skill title row at the portrait (ARL's "TL" anchor,
sized like ARL's Scan: 20 high, label+10); shift-click = post-hook on
HandleModifiedItemClick, ours only when CHATLINK, an enchant: link, the
trade window visible and no chat box / BrowseName / MacroFrameText would
take the link (Blizzard's paste precedence re-derived); /shop, /shop clear.
Harness dev/test_harness.lua 54/54 against the real data file (every total
re-derived independently).

**Field rows (2026-10-08, Claude 1039).**

| Row | Test | Result |
|---|---|---|
| 1 | harness | PASS 54/54 |
| 2 | cold start, /shop | PASS |
| 3 | the Weaponsmith quest list via shift-click | PASS |
| 4 | +/-/x, Clear | PASS |
| 5 | chat box open: link pastes, list unchanged | PASS |
| 6 | profession swap: list intact | PASS |
| 7 | drill down Mithril Bar; collapse | PASS |
| 8 | drill down an uncraftable-by-me reagent; raw materials have no glyph | PASS |
| 9 | have / short, DataStore alts in tooltip | PASS |
| 10 | relog + /reload persistence | PASS |
| 11 | second character: own list | PASS |
| P1 | List button placement | FAIL x2 -> PASS: first overlapped ARL's Scan (default TR, same side as the link button); moved left of the title (sat high/right); then given ARL's exact TL anchor and sizing |
| P2 | geometry / scroll | FAIL -> PASS: rows ran under the FauxScrollFrame bar (the 22 px law, written in the statement, not applied); rows narrowed |
| P3 | drag + Escape | PASS |
| P4 | chrome | PASS |

**Lesson.** Enumerating a window's tenants is not reading where they draw —
ARL's button anchor was one grep away and I shipped without it. Twice on
this project now (Informant 2026-10-06, ARL 2026-10-08): the rule is
"read every tenant's anchor before claiming a pixel".

---

# Shopping List 0.2 — Statement (endorsed 2026-10-08, "let's see how testing goes")

**Requirement.** (1) Window tooltips only while Shift is held. (2) Clicking a
craft's name opens its profession window, expands and selects the recipe,
count box pre-filled with the remaining count; out of combat only; dimmed
when the character lacks the profession. (3) Each successful cast of a listed
recipe by this character counts it down; at 0 the line stays as "(done)";
drilled-down intermediates you hold offset their own inputs. Amendment
0.2.2 (F1-F3, found on Shinora): profession known but recipe not — marked
orange "(recipe unknown)" when DataStore_Crafts has this character's
profession scanned, click DISARMED with a status notice (his ruling F2-2),
and after any open where the recipe isn't found the status line says so.

**Rulings.** 1-1 Shift reveals tooltips · 2a secure attributes out of combat
only (the macro is "/cast [nocombat] <profession>" so combat clicks do
nothing) · 2b dim + tooltip names alts who can (DataStore_Crafts) · 2c count
box pre-filled · 3a done line stays · 3b held intermediates offset inputs ·
3c own casts only · F1 yes · F2-2 disarm · F3 yes.

**Design notes.** ShoppingListProfessions = skill line -> first-rank window
spell (generator, Spell.dbc effect 47; Mining's window is "Smelting"), name
via GetSpellInfo at runtime; profession KNOWN = spellbook walk by name
(GetSpellName(i, BOOKTYPE_SPELL), SpellClusters' technique) — IsSpellKnown()
is FALSE for a held Blacksmithing on 3.3.5 (field, row 3 first run); recipe
known = DataStore:IsCraftKnown(DataStore:GetProfession(me, prof), spell),
tri-state; countdown = UNIT_SPELLCAST_SUCCEEDED("player", name) matched by
recipe spell NAME (the client's own cast-sequence technique), count -=
numMade; Accumulate: expanded craftable walks inputs for max(0, need-have).
Harness 102/102.

**Field rows (Shinora 1033, live team, 2026-10-08).**

| Row | Result |
|---|---|
| 2 Shift tooltips | PASS |
| 3 click -> Blacksmithing at the recipe, count pre-filled | FAIL -> PASS (0.2.1: IsSpellKnown false for professions; spellbook scan by name) |
| 4 switch from another open profession | PASS |
| 5 profession known, recipe not (Primal Mooncloth on Shinora, Tailoring 9/75) | FAIL -> PASS (0.2.2: F1-F3; note: on this realm every character holds all 11 professions, so "profession unknown" is a publication-only case) |
| 6 combat: nothing, status says so, re-arms after | PASS |
| 7 one craft counts down, materials follow | PASS |
| 8 Create All to 0: line stays "(done)"; x removes; + revives | PASS |
| 9 drilled-down bar with 10 held: "have 10, make 22"; smelting moves it | PASS |
| 10 alternate-spell recipe counts down | PASS |
| 11 another character's cast ignored | PASS |
| P1 click area / dims distinct | PASS |
| P2 status line without layout shift | PASS |
| P3 Shift tooltip placement | PASS |

**Lessons.** (1) A FrameXML sighting proves an API exists, not that it answers
for your spell class — row 0 the exact call on the exact class. (2) A test
row that assumes "character lacks X" must be read against the realm's rules
first (11 professions each: nobody lacks anything).

**Published 2026-10-08 as 1.0.0** (GiggleFizz/ShoppingList, MIT; his standard: 1.0.0 = first publication). Runtime = 0.2.2 unchanged.
