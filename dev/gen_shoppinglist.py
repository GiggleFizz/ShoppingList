#!/usr/bin/env python3
"""Shopping List data generator — every craftable item on the realm and what
it is made of, read from the server's own Spell.dbc (never from memory).

Output: ../ShoppingListData.lua
  ShoppingListData = {
    [resultItemID] = { spellID, skillLineID, numMade, reagentID, count, reagentID, count, ... },
  }
  ShoppingListProfessions = { [skillLineID] = openingSpellID }
    -- the first-rank spell that opens each profession's window (effect 47
    -- TRADE_SKILL, named as the skill; Mining's window is "Smelting"), so the
    -- addon can "/cast" it by its localised name (GetSpellInfo at runtime)
  Item NAMES are deliberately absent: the client resolves them at runtime
  (GetItemInfo), so the addon works in any locale and names never go stale.

Scope: create-item spells (effect 24, SPELL_EFFECT_CREATE_ITEM) that belong
to a profession skill line (SkillLineAbility -> SkillLine category 11
"Profession" or the secondary lines Cooking 185 / First Aid 129) and have at
least one reagent. numMade = the create effect's minimum yield
(EffectBasePoints + 1). When several spells create the same item, the lowest
spell ID wins; the alternates are listed in the manifest.

Modes:
  generate - write ../ShoppingListData.lua + shoppinglist-manifest.tsv
  verify   - re-derive from the live DBCs/DB and diff both files

Developer paths (this machine only) live in the constants below; the addon
itself carries no paths.
"""
import os
import re
import subprocess
import sys

DEV_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.dirname(DEV_DIR)
LUA_OUT = os.path.join(OUT_DIR, "ShoppingListData.lua")
MANIFEST = os.path.join(DEV_DIR, "shoppinglist-manifest.tsv")
DBC_DIR = "/media/linuxdata/WOW_Private/playerbots_server/data/dbc"
WORLDSERVER_CONF = "/media/linuxdata/WOW_Private/playerbots_server/etc/worldserver.conf"
sys.path.insert(0, "/home/wizzfizz/workspaces/WoW/dbc-tools")
from wdbc import DBC  # noqa: E402

# Spell.dbc (3.3.5, SpellEntry layout as the core reads it)
F_EFFECT = (71, 72, 73)
F_BASEPOINTS = (80, 81, 82)
F_ITEMTYPE = (107, 108, 109)
F_REAGENT = range(52, 60)
F_REAGENT_COUNT = range(60, 68)
F_NAME = 136
EFFECT_CREATE_ITEM = 24
SKILL_CATEGORY_PROFESSION = 11
SECONDARY = {185, 129}          # Cooking, First Aid (category 9, but crafts)


def db_conn_info():
    with open(WORLDSERVER_CONF) as f:
        m = re.search(r'^WorldDatabaseInfo\s*=\s*"([^"]+)"', f.read(), re.M)
    return m.group(1).split(";")


def mysql(query):
    host, port, user, pw, db = db_conn_info()
    env = dict(os.environ, MYSQL_PWD=pw)
    out = subprocess.run(["mysql", "-h", host, "-P", port, "-u", user, "-N", "--batch", db],
                         input=query, capture_output=True, text=True, env=env, check=True).stdout
    return [line.split("\t") for line in out.splitlines()]


EFFECT_TRADE_SKILL = 47
WINDOW_NAME = {186: "Smelting"}        # Mining's craft window is the Smelting spell


def derive():
    sl = DBC(f"{DBC_DIR}/SkillLine.dbc")
    craft_skills = {r[0] for r in sl.records if r[1] == SKILL_CATEGORY_PROFESSION} | SECONDARY
    skill_name = {r[0]: sl.get_string(r[3]) for r in sl.records}
    sla = DBC(f"{DBC_DIR}/SkillLineAbility.dbc")
    spell_skill = {}
    for r in sla.records:
        if r[1] in craft_skills:
            spell_skill.setdefault(r[2], r[1])
    sp = DBC(f"{DBC_DIR}/Spell.dbc")
    recipes = {}          # result item -> dict
    alternates = {}       # result item -> [other spell ids]
    openers = {}          # skill line -> lowest-id window-opening spell
    for r in sp.records:
        sid = r[0]
        if sid not in spell_skill:
            continue
        skill = spell_skill[sid]
        if EFFECT_TRADE_SKILL in (r[F_EFFECT[0]], r[F_EFFECT[1]], r[F_EFFECT[2]]) \
                and sp.get_string(r[F_NAME]) == WINDOW_NAME.get(skill, skill_name[skill]):
            if skill not in openers or sid < openers[skill]:
                openers[skill] = sid
        for k in range(3):
            if r[F_EFFECT[k]] == EFFECT_CREATE_ITEM and r[F_ITEMTYPE[k]]:
                item = r[F_ITEMTYPE[k]]
                base = r[F_BASEPOINTS[k]]
                if base >= 2 ** 31:
                    base -= 2 ** 32
                num_made = max(1, base + 1)
                reagents = [(r[i], r[j]) for i, j in zip(F_REAGENT, F_REAGENT_COUNT) if r[i] and r[j]]
                if not reagents:
                    continue
                rec = {"spell": sid, "skill": spell_skill[sid], "numMade": num_made, "reagents": reagents,
                       "name": sp.get_string(r[F_NAME])}
                if item in recipes:
                    if sid < recipes[item]["spell"]:
                        alternates.setdefault(item, []).append(recipes[item]["spell"])
                        recipes[item] = rec
                    else:
                        alternates.setdefault(item, []).append(sid)
                else:
                    recipes[item] = rec
                break
    # names for the manifest only (review artefact), from item_template
    ids = set(recipes) | {rid for rec in recipes.values() for rid, _ in rec["reagents"]}
    rows = mysql(f"SELECT entry, name FROM item_template WHERE entry IN ({','.join(map(str, sorted(ids)))})")
    item_name = {int(e): n for e, n in rows}
    missing = sorted(i for i in ids if i not in item_name)
    if missing:
        sys.exit(f"items referenced by Spell.dbc but absent from item_template: {missing[:10]} ({len(missing)})")
    used = {rec["skill"] for rec in recipes.values()}
    missing_open = sorted(k for k in used if k not in openers)
    if missing_open:
        sys.exit(f"no window-opening spell found for skill lines {missing_open}")
    return recipes, alternates, skill_name, item_name, openers


def render(recipes, alternates, skill_name, item_name, openers):
    lines = ["-- ShoppingListData.lua: every craftable item and its reagents, generated by",
             "-- dev/gen_shoppinglist.py from the server's Spell.dbc (3.3.5). Do not hand-edit.",
             "-- [resultItemID] = { spellID, skillLineID, numMade, reagentID, count, ... }",
             f"-- {len(recipes)} recipes. Names are resolved by the client at runtime.",
             "ShoppingListData = {"]
    for item in sorted(recipes):
        rec = recipes[item]
        flat = [rec["spell"], rec["skill"], rec["numMade"]] + [x for pair in rec["reagents"] for x in pair]
        lines.append(f"  [{item}] = {{{', '.join(map(str, flat))}}},")
    lines.append("}")
    lines.append("-- [skillLineID] = the first-rank spell that opens that profession's window")
    lines.append("ShoppingListProfessions = {")
    for k in sorted(openers):
        lines.append(f"  [{k}] = {openers[k]},  -- {skill_name[k]}")
    lines.append("}")
    lua = "\n".join(lines) + "\n"
    man = ["result\tresult_name\tspell\tspell_name\tskill\tskill_name\tnumMade\treagents\talternate_spells"]
    for item in sorted(recipes):
        rec = recipes[item]
        reag = "; ".join(f"{c}x {item_name[i]} ({i})" for i, c in rec["reagents"])
        alts = ",".join(map(str, sorted(alternates.get(item, []))))
        man.append(f"{item}\t{item_name[item]}\t{rec['spell']}\t{rec['name']}\t{rec['skill']}\t{skill_name[rec['skill']]}\t{rec['numMade']}\t{reag}\t{alts}")
    man.append("")
    man.append("# window-opening spells")
    for k in sorted(openers):
        man.append(f"# {k}\t{skill_name[k]}\t{openers[k]}")
    return lua, "\n".join(man) + "\n"


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    lua, man = render(*derive())
    if mode == "generate":
        open(LUA_OUT, "w").write(lua)
        open(MANIFEST, "w").write(man)
        n = lua.split("ShoppingListProfessions")[0].count("\n  [")
        print(f"wrote {LUA_OUT} ({n} recipes)\nwrote {MANIFEST}")
    elif mode == "verify":
        bad = [p for p, want in ((LUA_OUT, lua), (MANIFEST, man)) if not os.path.exists(p) or open(p).read() != want]
        if bad:
            print("VERIFY FAILED — drift in: " + ", ".join(os.path.basename(b) for b in bad))
            sys.exit(1)
        print(f"VERIFY OK: {lua.split('ShoppingListProfessions')[0].count(chr(10) + '  [')} recipes match the live Spell.dbc / item_template.")
    else:
        sys.exit("usage: gen_shoppinglist.py generate|verify")


if __name__ == "__main__":
    main()
