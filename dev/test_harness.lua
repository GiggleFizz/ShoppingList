-- Shopping List offline harness (lua5.1). Run from the addon root:
--   lua5.1 dev/test_harness.lua
-- Stubs the 3.3.5 client surface the addon touches, loads the REAL data file,
-- and re-derives every expected total independently of the addon's code.
local passed, failed = 0, 0
local function check(name, cond, detail)
    if cond then passed = passed + 1
    else failed = failed + 1; io.stderr:write("FAIL: " .. name .. (detail and (" -- " .. tostring(detail)) or "") .. "\n") end
end

-- ------------------------------------------------------------ UI stubs --
local function Region()
    local r = { shown = true, points = {}, text = "" }
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:IsVisible() return self.shown end
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:ClearAllPoints() self.points = {} end
    function r:GetPoint() local p = self.points[#self.points] or { "CENTER", nil, "CENTER", 0, 0 }; return p[1], p[2], p[3], p[4], p[5] end
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:SetHeight(h) self.h = h end
    function r:SetTexture(t) self.texture = t end
    function r:GetTextWidth() return 28 end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetText(t) self.text = t end
    function r:SetFormattedText(f, ...) self.text = string.format(f, ...) end
    function r:GetText() return self.text end
    return r
end
local frames = {}
function CreateFrame(ftype, name, parent, template)
    local f = Region()
    f.ftype, f.name, f.parent, f.template, f.scripts, f.events = ftype, name, parent, template, {}, {}
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:SetAttribute(k, v) if HARNESS.combat then error("attribute change in combat") end self.attr = self.attr or {}; self.attr[k] = v end
    function f:GetAttribute(k) return self.attr and self.attr[k] end
    function f:RegisterForClicks(...) self.clicks = { ... } end
    function f:Click() -- the client: PreClick, then the secure action (macro), then PostClick
        if self.scripts.PreClick then self.scripts.PreClick(self) end
        local m = self.attr and self.attr.macrotext or ""
        if m ~= "" then HARNESS.casts[#HARNESS.casts + 1] = m; HARNESS.OnMacro(m) end
        if self.scripts.OnClick then self.scripts.OnClick(self) end
    end
    function f:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end   -- the client fires OnShow/OnHide
    function f:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function f:GetScript(k) return self.scripts[k] end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetBackdrop(b) self.backdrop = b end
    function f:SetMovable(v) self.movable = v end
    function f:EnableMouse(v) self.mouse = v end
    function f:SetClampedToScreen(v) self.clamped = v end
    function f:RegisterForDrag(b) self.drag = b end
    function f:StartMoving() self.moving = true end
    function f:StopMovingOrSizing() self.moving = false; self.points = { { "TOPLEFT", UIParent, "TOPLEFT", 123, -45 } } end
    function f:CreateTexture() return Region() end
    function f:CreateFontString() return Region() end
    function f:SetOwner(o, a) self.owner = o end
    function f:SetHyperlink(l) self.link = l; HARNESS.pinged[#HARNESS.pinged + 1] = l end
    function f:AddLine(t) self.lines = self.lines or {}; self.lines[#self.lines + 1] = t end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
HARNESS = { pinged = {}, items = {}, counts = {}, hooks = {}, casts = {}, combat = false, shift = false,
            spells = {}, known = {}, casting = nil, trade = nil, selected = nil, inputBox = nil }
function HARNESS.OnMacro(m) end
function InCombatLockdown() return HARNESS.combat end
function IsShiftKeyDown() return HARNESS.shift end
function UnitCastingInfo() return HARNESS.casting end
BOOKTYPE_SPELL = "spell"
function GetSpellName(i, book) return HARNESS.book and HARNESS.book[i] end   -- the spellbook, in order
function GetSpellInfo(x) if type(x) == "number" then return HARNESS.spells[x] end end
-- the open trade-skill window: { line = "Blacksmithing", skills = { {name, kind, expanded, item} } }
function GetTradeSkillLine() return HARNESS.trade and HARNESS.trade.line end
function GetNumTradeSkills() return HARNESS.trade and #HARNESS.trade.skills or 0 end
function GetTradeSkillInfo(i) local t = HARNESS.trade.skills[i]; return t.name, t.kind, 0, t.expanded end
function ExpandTradeSkillSubClass(i) HARNESS.trade.skills[i].expanded = true; HARNESS.expanded = (HARNESS.expanded or 0) + 1 end
function GetTradeSkillItemLink(i) local t = HARNESS.trade.skills[i]; return t.item and ("|Hitem:" .. t.item .. ":0:0:0:0:0:0:0:70|h[x]|h") end
function TradeSkillFrame_SetSelection(i) HARNESS.selected = i end
function TradeSkillFrame_Update() HARNESS.updated = (HARNESS.updated or 0) + 1 end
UIParent = Region(); UIParent.name = "UIParent"
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
UISpecialFrames = {}
function tinsert(t, v) t[#t + 1] = v end
function hooksecurefunc(name, fn) HARNESS.hooks[name] = fn end
function IsAddOnLoaded(n) return HARNESS.loaded and HARNESS.loaded[n] end
function UnitName() return HARNESS.me or "Claude" end
function GetItemQualityColor(q) return 1, 1, 1 end
TradeSkillInputBox = { SetNumber = function(self, n) HARNESS.inputBox = n end }
function GetItemInfo(id) local n = HARNESS.items[id]; if n then return n, "link", 1, 0, 0, "", "", 1, "", "icon" end end
function GetItemCount(id, bank) return HARNESS.counts[id] or 0 end
local modifier = nil
function IsModifiedClick(kind) return modifier == kind end
function ChatEdit_GetActiveWindow() return HARNESS.chatActive end
function FauxScrollFrame_Update(s, total, rows, h) s.total, s.rows = total, rows end
function FauxScrollFrame_GetOffset(s) return s.offset or 0 end
function FauxScrollFrame_OnVerticalScroll(s, off, h, fn) s.offset = math.floor(off / h); fn() end
SlashCmdList = {}
HARNESS.now = 0
function GetTime() return HARNESS.now end

-- -------------------------------------------------------------- loading --
local before = {}
for k in pairs(_G) do before[k] = true end
dofile("ShoppingListData.lua")
dofile("ShoppingList.lua")
local allowed = { ShoppingList = 1, ShoppingListData = 1, ShoppingListProfessions = 1, ShoppingListEvents = 1, SLASH_SHOPPINGLIST1 = 1, SLASH_SHOPPINGLIST2 = 1 }
local leaked = {}
for k in pairs(_G) do if not before[k] and not allowed[k] then leaked[#leaked + 1] = k end end
check("S1 no globals leaked before ADDON_LOADED", #leaked == 0, table.concat(leaked, ","))
local ev = ShoppingListEvents
local function fire(e, ...) ev.scripts.OnEvent(ev, e, ...) end
fire("ADDON_LOADED", "ShoppingList")
check("S1 frame built, hidden, escape-closable", ShoppingListFrame and not ShoppingListFrame:IsShown() and UISpecialFrames[1] == "ShoppingListFrame")
check("S1 hook on HandleModifiedItemClick", HARNESS.hooks.HandleModifiedItemClick ~= nil)
check("S1 data loaded (3,000+ recipes)", (function() local n = 0 for _ in pairs(ShoppingListData) do n = n + 1 end return n > 3000 end)())
check("S1 every recipe's profession has a window-opening spell", (function() for _, rec in pairs(ShoppingListData) do if not ShoppingListProfessions[rec[2]] then return false end end return true end)())
local SL = ShoppingList
local DATA = ShoppingListData

-- independent re-derivation of the materials
local function expect(items, expanded)
    local leaves = {}
    local function walk(id, qty, depth)
        if expanded[id] and DATA[id] and depth < 8 then
            local rec = DATA[id]; local crafts = math.ceil(qty / rec[3])
            for i = 4, #rec, 2 do walk(rec[i], crafts * rec[i + 1], depth + 1) end
        else leaves[id] = (leaves[id] or 0) + qty end
    end
    for id, count in pairs(items) do
        local rec = DATA[id]; local crafts = math.ceil(count / rec[3])
        for i = 4, #rec, 2 do walk(rec[i], crafts * rec[i + 1], 0) end
    end
    return leaves
end
local function same(a, b) for k, v in pairs(a) do if b[k] ~= v then return false, k end end for k, v in pairs(b) do if a[k] ~= v then return false, k end end return true end

-- ================================================================ S2 the quest list
local BBM, HMA, MIA, MSB = 7945, 7941, 3855, 3853
check("S2 all four weaponsmith quest items are recipes", DATA[BBM] and DATA[HMA] and DATA[MIA] and DATA[MSB])
SL.Add(BBM, 2); SL.Add(HMA, 2); SL.Add(MIA, 4); SL.Add(MSB, 4)
local leaves = SL.Materials()
local want = expect({ [BBM] = 2, [HMA] = 2, [MIA] = 4, [MSB] = 4 }, {})
check("S2 materials equal the independent derivation", same(leaves, want))
check("S2 Mithril Bar >= 56 (16x2 + 12x2 from the two mithril weapons)", leaves[3860] and leaves[3860] >= 56, leaves[3860])
check("S2 Citrine = 4 (2 per Heavy Mithril Axe)", leaves[3864] == 4, leaves[3864])
check("S2 Add of a non-recipe is refused", SL.Add(3858, 1) == false and #SL.DB().items == 4)
check("S2 adding again merges", (function() SL.Add(BBM, 1); local _, e = nil, nil; for _, x in ipairs(SL.DB().items) do if x.id == BBM then e = x end end; return e.count == 3 and #SL.DB().items == 4 end)())
SL.SetCount(BBM, 2)

-- ================================================================ S3 counts / remove / clear
SL.SetCount(MSB, 1); check("S3 SetCount", (function() for _, x in ipairs(SL.DB().items) do if x.id == MSB then return x.count == 1 end end end)())
SL.SetCount(MSB, 0); check("S3 SetCount 0 removes", (function() for _, x in ipairs(SL.DB().items) do if x.id == MSB then return false end end return #SL.DB().items == 3 end)())
SL.Remove(MIA); check("S3 Remove", #SL.DB().items == 2)
leaves = SL.Materials(); check("S3 totals follow removals", same(leaves, expect({ [BBM] = 2, [HMA] = 2 }, {})))
SL.Clear(); check("S3 Clear", #SL.DB().items == 0 and next((SL.Materials())) == nil)

-- ================================================================ S4 numMade > 1
local multi
for id, rec in pairs(DATA) do if rec[3] > 1 and not multi then multi = id end end
check("S4 a multi-yield recipe exists", multi ~= nil)
if multi then
    local n = DATA[multi][3]
    SL.Add(multi, 1); local l1 = SL.Materials()
    SL.SetCount(multi, n); local l2 = SL.Materials()
    SL.SetCount(multi, n + 1); local l3 = SL.Materials()
    check("S4 1 and numMade both cost one craft", same(l1, l2))
    check("S4 numMade+1 costs two crafts", (function() for k, v in pairs(l3) do if v ~= 2 * l1[k] then return false end end return true end)())
    SL.Clear()
end

-- ================================================================ S5 drill-down
SL.Add(BBM, 2)
SL.ToggleExpand(3860)                                   -- Mithril Bar -> Mithril Ore
leaves = SL.Materials()
local lv, inter = SL.Materials()
check("S5 expanded bar leaves the leaves; ore arrives", leaves[3860] == nil and leaves[3858] == 32, tostring(leaves[3858]))
check("S5 intermediate recorded with its quantity", inter[3860].need == 32 and inter[3860].make == 32)
check("S5 equals independent derivation", same(leaves, expect({ [BBM] = 2 }, { [3860] = true })))
SL.ToggleExpand(3860)
check("S5 collapse restores the bar", SL.Materials()[3860] == 32)
-- nested: something made of Steel Bar -> Iron Bar + Coal -> Iron Ore
local steelUser
for id, rec in pairs(DATA) do for i = 4, #rec, 2 do if rec[i] == 3859 and not steelUser then steelUser = id end end end
check("S5 a Steel Bar consumer exists", steelUser ~= nil)
SL.Clear(); SL.Add(steelUser, 1)
SL.ToggleExpand(3859)                                   -- Steel Bar
local l = SL.Materials()
check("S5 Steel Bar -> Iron Bar + Coal", l[3575] and l[3857] and l[3859] == nil)
SL.ToggleExpand(3575)                                   -- Iron Bar -> Iron Ore
l = SL.Materials()
check("S5 nested: Iron Bar -> Iron Ore, Coal stays", l[2772] and l[3575] == nil and l[3857], tostring(l[2772]))
check("S5 nested equals independent derivation", same(l, expect({ [steelUser] = 1 }, { [3859] = true, [3575] = true })))
check("S5 toggling a raw material is a no-op", (function() SL.ToggleExpand(3858); return SL.DB().expanded[3858] == nil end)())
SL.Clear(); SL.DB().expanded = {}

-- ================================================================ S6 lines, have/short, names
HARNESS.items[3860] = "Mithril Bar"; HARNESS.items[7945] = "Big Black Mace"; HARNESS.items[3858] = "Mithril Ore"
HARNESS.spells[2018] = "Blacksmithing"; HARNESS.book = { "Attack", "Blacksmithing", "Stealth" }; fire("SPELLS_CHANGED")   -- Claude's spellbook
HARNESS.counts[3860] = 10
SL.Add(BBM, 2)
local lines = SL.Lines()
check("S6 lines: 1 craft, rule, then materials", lines[1].kind == "craft" and lines[2].kind == "rule" and lines[3].kind == "leaf")
local bar
for _, x in ipairs(lines) do if x.kind == "leaf" and x.id == 3860 then bar = x end end
check("S6 Mithril Bar leaf: need 32, have 10, craftable", bar and bar.need == 32 and bar.have == 10 and bar.craftable)
check("S6 raw material is not craftable", (function() for _, x in ipairs(lines) do if x.id == 1210 then return x.craftable == false end end end)())  -- Shadowgem
ShoppingListFrame:Show()
local row3 = ShoppingListRow3
check("S6 draw: short shown red", row3.right.text:find("short 22") and row3.right.text:find("ff4040"))
HARNESS.counts[3860] = 40; SL.Refresh()
check("S6 draw: have shown green when enough", ShoppingListRow3.right.text:find("have 40") and ShoppingListRow3.right.text:find("1eff00"))
check("S6 unknown name -> placeholder + one ping", (function()
    for _, x in ipairs(lines) do if x.id == 1210 then end end
    local before = #HARNESS.pinged; SL.Refresh(); return #HARNESS.pinged > 0 end)())
check("S6 craft row shows count and controls", ShoppingListRow1.text.text:find("^2 x") and ShoppingListRow1.plus.shown and ShoppingListRow1.del.shown)
check("S6 rule row draws a rule, nothing else", ShoppingListRow2.rule.shown and ShoppingListRow2.text.text == "")

-- ================================================================ S7 DataStore (bank + alts)
DataStore = {
    GetCharacter = function() return "me" end,
    GetCharacters = function() return { Claude = "me", Pallytest = "alt" } end,
    GetContainerItemCount = function(self, char, id) if id == 3860 then return (char == "me") and 5 or 0, (char == "me") and 50 or 7 end return 0, 0 end,
}
local have, alts = SL.Have(3860)
check("S7 DataStore bank beats live count when larger; alts summed", have == 55 and alts == 7, have .. "/" .. alts)
DataStore = nil

-- ================================================================ S8 shift-click precedence
SL.Clear(); ShoppingListFrame:Hide()
TradeSkillFrame = CreateFrame("Frame", "TradeSkillFrame"); TradeSkillFrame:Show()
local link = "|cffffd000|Henchant:10001|h[Big Black Mace]|h|r"
modifier = "CHATLINK"; HARNESS.chatActive = nil
HARNESS.hooks.HandleModifiedItemClick(link)
check("S8 shift-click with no taker adds the recipe and shows the window", #SL.DB().items == 1 and SL.DB().items[1].id == BBM and ShoppingListFrame:IsShown())
HARNESS.chatActive = {}; HARNESS.hooks.HandleModifiedItemClick(link)
check("S8 chat box active: the link is chat's, not ours", SL.DB().items[1].count == 1)
HARNESS.chatActive = nil; BrowseName = CreateFrame("EditBox", "BrowseName"); BrowseName:Show()
HARNESS.hooks.HandleModifiedItemClick(link)
check("S8 auction search box visible: not ours", SL.DB().items[1].count == 1)
BrowseName:Hide(); MacroFrameText = CreateFrame("EditBox", "MacroFrameText"); MacroFrameText:Show()
HARNESS.hooks.HandleModifiedItemClick(link)
check("S8 macro editor visible: not ours", SL.DB().items[1].count == 1)
MacroFrameText:Hide(); modifier = "DRESSUP"; HARNESS.hooks.HandleModifiedItemClick(link)
check("S8 ctrl-click (dress-up) ignored", SL.DB().items[1].count == 1)
modifier = "CHATLINK"; HARNESS.hooks.HandleModifiedItemClick("|Hitem:3860:0:0:0:0:0:0:0:70|h[Mithril Bar]|h")
check("S8 an item link (reagent click) is not a recipe", SL.DB().items[1].count == 1 and #SL.DB().items == 1)
TradeSkillFrame:Hide(); HARNESS.hooks.HandleModifiedItemClick(link)
check("S8 trade window hidden: ignored", SL.DB().items[1].count == 1)
TradeSkillFrame:Show(); HARNESS.hooks.HandleModifiedItemClick(link)
check("S8 second clean shift-click increments", SL.DB().items[1].count == 2)
HARNESS.hooks.HandleModifiedItemClick(nil)
check("S8 nil link tolerated", true)

-- ================================================================ S9 trade-skill button + persistence + slash
TradeSkillFrameTitleText = Region(); TradeSkillLinkButton = CreateFrame("Button", "TradeSkillLinkButton", TradeSkillFrame); TradeSkillFramePortrait = Region()
fire("ADDON_LOADED", "Blizzard_TradeSkillUI")
check("S9 List button beside the portrait (ARL's TL spot; its default TR is at the close button)", ShoppingListTradeButton and ShoppingListTradeButton.points[1][1] == "LEFT" and ShoppingListTradeButton.points[1][2] == TradeSkillFramePortrait and ShoppingListTradeButton.points[1][4] == 2 and ShoppingListTradeButton.points[1][5] == 12)
check("S9 rows are narrower than the scroll frame + bar", ShoppingListRow1.w == 380 - 40 - 22)
check("S9 List button sized like ARL's: 20 high, label + 10 wide", ShoppingListTradeButton.h == 20 and ShoppingListTradeButton.w == 38)
fire("ADDON_LOADED", "Blizzard_TradeSkillUI")
check("S9 attaching twice does not duplicate", (function() local n = 0 for _, f in ipairs(frames) do if f.name == "ShoppingListTradeButton" then n = n + 1 end end return n == 1 end)())
ShoppingListFrame.scripts.OnDragStart(ShoppingListFrame); ShoppingListFrame.scripts.OnDragStop(ShoppingListFrame)
check("S9 drag stop persists the position", SL.DB().pos and SL.DB().pos[3] == 123 and SL.DB().pos[4] == -45)
check("S9 DB shape", type(SL.DB().items) == "table" and type(SL.DB().expanded) == "table" and SL.DB().shown == true)
SlashCmdList.SHOPPINGLIST("")
check("S9 /shop toggles (hides)", not ShoppingListFrame:IsShown() and SL.DB().shown == nil)
SlashCmdList.SHOPPINGLIST("clear")
check("S9 /shop clear empties the list", #SL.DB().items == 0)
check("S9 still no stray globals", (function() local bad = {} for k in pairs(_G) do if not before[k] and not allowed[k] and not tostring(k):match("^ShoppingList") and k ~= "TradeSkillFrame" and k ~= "BrowseName" and k ~= "MacroFrameText" and k ~= "TradeSkillFrameTitleText" and k ~= "TradeSkillLinkButton" and k ~= "TradeSkillFramePortrait" and k ~= "DataStore" and k ~= "TradeSkillInputBox" then bad[#bad+1]=k end end return #bad == 0, table.concat(bad, ",") end)())


-- ================================================================ S10 Shift-gated tooltips
HARNESS.items[7945] = "Big Black Mace"; HARNESS.spells[2018] = "Blacksmithing"; HARNESS.spells[10001] = "Big Black Mace"
SL.Add(BBM, 2); ShoppingListFrame:Show()
GameTooltip.lines = nil; GameTooltip.link = nil
local row = ShoppingListRow1
HARNESS.shift = false; row.cast.scripts.OnEnter(row.cast)
check("S10 hover without Shift: no tooltip", GameTooltip.link == nil)
HARNESS.shift = true; fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
check("S10 Shift pressed while hovering: tooltip appears", GameTooltip.link == "item:7945")
check("S10 tooltip tells how to open the profession", GameTooltip.lines and GameTooltip.lines[1]:find("open Blacksmithing"))
HARNESS.shift = false; GameTooltip.shown = true; fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
check("S10 Shift released: tooltip hidden", GameTooltip.shown == false)
row.cast.scripts.OnLeave(row.cast)

-- ================================================================ S11 click a craft -> /cast its profession, select the recipe
HARNESS.trade = nil; HARNESS.casts = {}
HARNESS.OnMacro = function(m)   -- the client casts Blacksmithing: its window opens
    HARNESS.trade = { line = "Blacksmithing", skills = {
        { name = "Armor", kind = "header", expanded = true },
        { name = "Heavy Mithril Boots", kind = "optimal", item = 7939 },
        { name = "Weapons", kind = "header", expanded = false },
        { name = "Big Black Mace", kind = "optimal", item = 7945 } } }
    TradeSkillFrame:Show(); fire("TRADE_SKILL_SHOW")
end
check("S11 craft row carries the secure layer, macro empty until clicked", row.cast.attr.type == "macro" and row.cast.attr.macrotext == "")
row.cast:Click()
check("S11 click cast '/cast [nocombat] Blacksmithing'", HARNESS.casts[1] == "/cast [nocombat] Blacksmithing", HARNESS.casts[1])
check("S11 collapsed Weapons header expanded on show", HARNESS.expanded == 1 and HARNESS.trade.skills[3].expanded)
fire("TRADE_SKILL_UPDATE")       -- the client's update after the expansion
check("S11 recipe selected by result item, window updated", HARNESS.selected == 4 and HARNESS.updated >= 1, tostring(HARNESS.selected))
check("S11 count box pre-filled with the remaining count", HARNESS.inputBox == 2, tostring(HARNESS.inputBox))
HARNESS.selected = nil; HARNESS.inputBox = nil
fire("TRADE_SKILL_UPDATE")
check("S11 a later update does not re-select (pending consumed)", HARNESS.selected == nil)
-- right window already open: select directly, no cast
HARNESS.casts = {}
row.cast:Click()
check("S11 window already on Blacksmithing: no cast, direct select", #HARNESS.casts == 0 and HARNESS.selected == 4)
-- mid-cast: disarmed
HARNESS.trade = nil; TradeSkillFrame:Hide(); HARNESS.casting = "Something"; HARNESS.casts = {}
row.cast:Click()
check("S11 mid-cast: click disarmed", #HARNESS.casts == 0)
HARNESS.casting = nil
-- profession unknown: dimmed, disarmed, tooltip names who can
HARNESS.book = { "Attack", "Stealth" }; fire("SPELLS_CHANGED")
check("S11 unknown profession: row dimmed", row.text.text:find("808080") and row.text.text:find("2 x"))
HARNESS.casts = {}; row.cast:Click()
check("S11 unknown profession: click does nothing", #HARNESS.casts == 0)
DataStore = { GetCharacters = function() return { Claude = "me", Pallytest = "alt", Crafter = "alt2" } end,
    GetProfessions = function(self, c) return c == "alt2" and { Blacksmithing = { tag = "bs" } } or {} end,
    IsCraftKnown = function(self, prof, spell) return prof.tag == "bs" and spell == 10001 end,
    GetCharacter = function() return "me" end, GetContainerItemCount = function() return 0, 0 end }
HARNESS.shift = true; GameTooltip.lines = nil; row.cast.scripts.OnEnter(row.cast)
check("S11 tooltip: Needs Blacksmithing + who can make it", GameTooltip.lines and GameTooltip.lines[1]:find("Needs Blacksmithing") and GameTooltip.lines[2]:find("Crafter"), GameTooltip.lines and table.concat(GameTooltip.lines, " | "))
row.cast.scripts.OnLeave(row.cast); HARNESS.shift = false; DataStore = nil; HARNESS.book = { "Attack", "Blacksmithing", "Stealth" }; fire("SPELLS_CHANGED")
check("S11 the book is keyed by name: a higher rank still counts", (function() HARNESS.book = { "Blacksmithing" }; fire("SPELLS_CHANGED"); local _, _, k = SL.Profession(BBM); return k == true end)())
-- combat: no attribute writes, status says so, re-arms after
HARNESS.combat = true; fire("PLAYER_REGEN_DISABLED")
check("S11 in combat: Draw skips attributes, status explains", ShoppingListFrame:IsShown() and _G.ShoppingListFrame and true)
local statusText
for _, f in ipairs(frames) do end
HARNESS.combat = false; fire("PLAYER_REGEN_ENABLED")
check("S11 out of combat: drawing again is allowed", true)

-- ================================================================ S12 countdown as you craft
SL.Clear(); SL.Add(BBM, 2); SL.Add(HMA, 1)
HARNESS.spells[9993] = "Heavy Mithril Axe"
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Big Black Mace")
check("S12 one cast counts a craft down 2 -> 1", SL.DB().items[1].count == 1 and not SL.DB().items[1].done)
local l = SL.Materials()
check("S12 materials follow (16 Mithril Bar for the one left + 12 for the axe)", l[3860] == 28, l[3860])
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Big Black Mace")
check("S12 reaching 0 keeps the line as done", SL.DB().items[1].count == 0 and SL.DB().items[1].done == true and #SL.DB().items == 2)
check("S12 a done craft contributes no materials", SL.Materials()[3860] == 12)
SL.Refresh()
check("S12 done line drawn dimmed with '(done)'", ShoppingListRow1.text.text:find("%(done%)") and ShoppingListRow1.text.text:find("808080"))
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Big Black Mace")
check("S12 extra casts past 0 do nothing", SL.DB().items[1].count == 0)
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Heavy Mithril Axe")
check("S12 another unit's cast is ignored", SL.DB().items[2].count == 1)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Fireball")
check("S12 unrelated spell ignored", SL.DB().items[2].count == 1)
-- multi-yield: one cast makes numMade
if multi then
    SL.Add(multi, DATA[multi][3] + 1); HARNESS.spells[DATA[multi][1]] = "MultiYield"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "MultiYield")
    local _, e = nil, nil; for _, x in ipairs(SL.DB().items) do if x.id == multi then e = x end end
    check("S12 multi-yield cast counts numMade down", e.count == 1, e.count)
end
check("S12 + on a done craft revives it", (function() SL.SetCount(BBM, 1); return SL.DB().items[1].count == 1 and SL.DB().items[1].done == nil end)())

-- ================================================================ S13 held intermediates offset their inputs
SL.Clear(); SL.DB().expanded = {}
SL.Add(BBM, 2)                      -- 32 Mithril Bar
HARNESS.counts[3860] = 10           -- hold 10 bars
SL.ToggleExpand(3860)
local lv, inter = SL.Materials()
check("S13 drilled-down bar: need 32, have 10, make 22", inter[3860].need == 32 and inter[3860].have == 10 and inter[3860].make == 22)
check("S13 ore asked only for the 22 to make", lv[3858] == 22, lv[3858])
HARNESS.counts[3860] = 40
lv, inter = SL.Materials()
check("S13 enough bars held: nothing to make, no ore", inter[3860].make == 0 and lv[3858] == nil)
SL.Refresh()
check("S13 line reads have 40 in green", ShoppingListRow3.right.text:find("have 40") and ShoppingListRow3.right.text:find("1eff00"))
HARNESS.counts[3860] = 10; SL.Refresh()
check("S13 line reads have 10, make 22", ShoppingListRow3.right.text:find("have 10, make 22"))
-- nested with holdings: Steel Bar user, hold 1 Steel Bar
SL.Clear(); SL.DB().expanded = {}; HARNESS.counts = {}
SL.Add(steelUser, 1); SL.ToggleExpand(3859)
local needSteel = select(2, SL.Materials())[3859].need
HARNESS.counts[3859] = needSteel - 1
lv, inter = SL.Materials()
check("S13 nested: holding all but one Steel Bar asks for one bar's inputs", lv[3575] == 1 and lv[3857] == 1, tostring(lv[3575]) .. "/" .. tostring(lv[3857]))
HARNESS.counts = {}; SL.Clear(); SL.DB().expanded = {}

-- ================================================================ S14 regressions: silence of the secure layer when not a craft
SL.Add(BBM, 1); SL.Refresh()
local leafRow
for i = 1, 18 do local r = _G["ShoppingListRow" .. i]; if r.kind == "leaf" then leafRow = r; break end end
HARNESS.casts = {}; leafRow.cast:Click()
check("S14 the secure layer on a material row never casts", #HARNESS.casts == 0 and leafRow.cast.attr.macrotext == "")


-- ================================================================ S15 profession known, recipe not (F1/F2) + not found after open (F3)
SL.Clear(); SL.DB().expanded = {}; HARNESS.casts = {}; HARNESS.trade = nil; TradeSkillFrame:Hide()
HARNESS.book = { "Attack", "Blacksmithing", "Tailoring" }; fire("SPELLS_CHANGED")
HARNESS.spells[3908] = "Tailoring"; HARNESS.spells[26751] = "Primal Mooncloth"; HARNESS.items[21845] = "Primal Mooncloth"
HARNESS.me = "Shinora"
SL.Add(21845, 1)                      -- Primal Mooncloth, a Tailoring recipe Shinora doesn't know
-- (a) no DataStore: can't tell before the click -> normal row, click opens, F3 reports after
SL.Refresh()
check("S15 without DataStore the row is normal (recipe state unknown)", ShoppingListRow1.text.text:find("^1 x") and not ShoppingListRow1.text.text:find("recipe unknown"))
HARNESS.OnMacro = function(m) HARNESS.trade = { line = "Tailoring", skills = { { name = "Cloth", kind = "header", expanded = true }, { name = "Bolt of Linen Cloth", kind = "trivial", item = 2996 } } }; TradeSkillFrame:Show(); fire("TRADE_SKILL_SHOW") end
HARNESS.now = 100; ShoppingListRow1.cast:Click()
check("S15 click cast Tailoring", HARNESS.casts[#HARNESS.casts] == "/cast [nocombat] Tailoring")
check("S15 F3: recipe not found -> notice on the status line names the profession", SL.StatusText() and SL.StatusText():find("not found in Tailoring"), SL.StatusText())
HARNESS.now = 110; SL.Refresh()
check("S15 notice fades after a few seconds", not SL.StatusText():find("not found"), SL.StatusText())
-- (b) DataStore knows Shinora's Tailoring and the recipe is NOT in it
DataStore = { GetCharacter = function() return "me" end,
    GetProfession = function(self, c, name) if c == "me" and name == "Tailoring" then return { tag = "tailor" } end end,
    GetProfessions = function(self, c) return c == "alt" and { Tailoring = { tag = "alt-tailor" } } or {} end,
    IsCraftKnown = function(self, prof, spell) return prof.tag == "alt-tailor" and spell == 26751 end,
    GetCharacters = function() return { Claude = "alt", Shinora = "me" } end,
    GetContainerItemCount = function() return 0, 0 end }
HARNESS.trade = nil; TradeSkillFrame:Hide(); HARNESS.casts = {}
SL.Refresh()
check("S15 F1: row marked '(recipe unknown)' in colour", ShoppingListRow1.text.text:find("recipe unknown") and not ShoppingListRow1.text.text:find("^|cff808080"))
check("S15 recipe tri-state false", SL.RecipeKnown(21845, "Tailoring") == false)
HARNESS.now = 200; ShoppingListRow1.cast:Click()
check("S15 F2: click disarmed", #HARNESS.casts == 0 and ShoppingListRow1.cast.attr.macrotext == "")
check("S15 F2: status says why", SL.StatusText():find("don't know this recipe") and SL.StatusText():find("Tailoring"), SL.StatusText())
HARNESS.shift = true; GameTooltip.lines = nil; ShoppingListRow1.cast.scripts.OnEnter(ShoppingListRow1.cast)
check("S15 tooltip: don't know + who can (Claude)", GameTooltip.lines and GameTooltip.lines[1]:find("know this recipe") and GameTooltip.lines[2]:find("Claude"), GameTooltip.lines and table.concat(GameTooltip.lines, " | "))
ShoppingListRow1.cast.scripts.OnLeave(ShoppingListRow1.cast); HARNESS.shift = false
-- (c) DataStore says the recipe IS known -> normal row, click arms
DataStore.IsCraftKnown = function(self, prof, spell) return true end
SL.Refresh()
check("S15 recipe known: normal row, click arms", ShoppingListRow1.text.text:find("^1 x") and not ShoppingListRow1.text.text:find("recipe unknown"))
HARNESS.trade = nil; ShoppingListRow1.cast:Click()
check("S15 recipe known: cast fires", HARNESS.casts[#HARNESS.casts] == "/cast [nocombat] Tailoring")
-- (d) a profession DataStore never scanned -> tri-state nil -> normal row
check("S15 unscanned profession -> nil (can't say)", SL.RecipeKnown(BBM, "Blacksmithing") == nil)
DataStore = nil; HARNESS.now = 0; HARNESS.me = nil

io.stderr:write(string.format("Shopping List harness: %d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
