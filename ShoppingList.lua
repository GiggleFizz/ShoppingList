-- Shopping List: a per-character queue of things to craft and the reagents
-- they add up to.
--
--   * shift-click a recipe in any trade-skill window -> it joins the list
--     (only when no chat box / auction search / macro editor would take the
--     link instead — Blizzard's own paste precedence is respected)
--   * + / - / x on each craft; Clear for the lot
--   * click a craft's name -> its profession window opens at that recipe,
--     count box pre-filled (a secure "/cast [nocombat] <profession>" — the
--     click is yours, the cast is the client's; nothing happens in combat)
--   * Materials: every reagent summed across the list with need / have / short
--   * any reagent that is itself craftable can be drilled down (click) — its
--     own inputs then count instead of it, as deep as you like; bars you
--     already hold reduce what their inputs must cover
--   * each craft you complete counts its line down; at 0 it stays as "done"
--   * hold Shift over a line for its tooltip
--
-- Recipe data (ShoppingListData.lua) is generated from the 3.3.5 Spell.dbc:
-- every craftable item on the realm, keyed by result item id, names resolved
-- by the client at runtime so any locale works.
--
-- Globals: ShoppingList (addon table), ShoppingListDB (per-character saved
-- variables), ShoppingListFrame (the window), ShoppingListData /
-- ShoppingListProfessions (the data).

ShoppingList = ShoppingList or {}
local SL = ShoppingList
local DATA, PROF = ShoppingListData, ShoppingListProfessions

local ROWS, ROW_H = 18, 20          -- visible rows, row height
local WIDTH = 380
local NAME_W = 220                  -- the clickable icon + name span of a craft row

-- ---------------------------------------------------------------- data --
local bySpell = {}                   -- spellID -> result item id
for item, rec in pairs(DATA) do bySpell[rec[1]] = item end

local function Recipe(item)          -- -> numMade, { {id, count}, ... } or nil
    local rec = DATA[item]
    if not rec then return nil end
    local reagents = {}
    for i = 4, #rec, 2 do reagents[#reagents + 1] = { rec[i], rec[i + 1] } end
    return rec[3], reagents
end
SL.Recipe = Recipe
function SL.IsCraftable(item) return DATA[item] ~= nil end
function SL.ItemForSpell(spell) return bySpell[spell] end

-- the spells this character knows, by name (so any rank counts): a walk of
-- the spellbook, the way SpellClusters does it — IsSpellKnown() is NOT
-- reliable for profession spells on 3.3.5 (field, 2026-10-08: false for a
-- held Blacksmithing)
local BOOK = BOOKTYPE_SPELL or "spell"
local book            -- name -> true; nil = rescan
local function KnownByName(name)
    if not book then
        book = {}
        local i = 1
        while true do
            local n = GetSpellName(i, BOOK)
            if not n then break end
            book[n] = true
            i = i + 1
        end
    end
    return book[name] == true
end
function SL.InvalidateBook() book = nil end

-- the profession that makes an item: its window-opening spell and that
-- spell's (localised) name; whether this character knows the profession
local function Profession(item)
    local rec = DATA[item]
    if not rec then return nil end
    local opener = PROF[rec[2]]
    local name = opener and GetSpellInfo(opener)
    return opener, name, (name and KnownByName(name)) or false
end
SL.Profession = Profession

-- --------------------------------------------------------------- model --
local function DB()
    ShoppingListDB = ShoppingListDB or {}
    local db = ShoppingListDB
    db.items = db.items or {}        -- ordered: { {id=, count=, done=}, ... }
    db.expanded = db.expanded or {}  -- reagent id -> true (drilled down)
    return db
end
SL.DB = DB

local function Find(id)
    for i, e in ipairs(DB().items) do if e.id == id then return i, e end end
end

function SL.Add(id, n)
    if not DATA[id] then return false end
    n = n or 1
    local _, e = Find(id)
    if e then e.count = e.count + n; e.done = nil
    else table.insert(DB().items, { id = id, count = n }) end
    SL.Refresh()
    return true
end

function SL.SetCount(id, n)          -- the +/- buttons: below 1 removes
    local i, e = Find(id)
    if not e then return end
    if n <= 0 then table.remove(DB().items, i) else e.count = n; e.done = nil end
    SL.Refresh()
end

function SL.Remove(id) SL.SetCount(id, 0) end

function SL.Clear()
    DB().items = {}
    SL.Refresh()
end

function SL.ToggleExpand(id)
    if not DATA[id] then return end
    local x = DB().expanded
    x[id] = (not x[id]) or nil
    SL.Refresh()
end

-- A craft you just completed: count down by what one cast makes; at 0 the
-- line stays as "done" until removed.
function SL.Crafted(spellName)
    local changed = false
    for _, e in ipairs(DB().items) do
        if e.count > 0 then
            local rec = DATA[e.id]
            if rec and GetSpellInfo(rec[1]) == spellName then
                e.count = math.max(0, e.count - rec[3])
                if e.count == 0 then e.done = true end
                changed = true
            end
        end
    end
    if changed then SL.Refresh() end
    return changed
end

-- ------------------------------------------------------------- have --
-- bags live (GetItemCount with bank when the client knows it); DataStore,
-- when present, adds the bank it remembers and what the alts hold.
local function Have(id)
    local mine = GetItemCount(id, true) or 0
    local alts = 0
    if DataStore and DataStore.GetContainerItemCount and DataStore.GetCharacter then
        local me = DataStore:GetCharacter()
        if me then
            local bags, bank = DataStore:GetContainerItemCount(me, id)
            local stored = (bags or 0) + (bank or 0)
            if stored > mine then mine = stored end
        end
        if DataStore.GetCharacters then
            local myName = UnitName("player")
            for name, char in pairs(DataStore:GetCharacters()) do
                if name ~= myName then
                    local bags, bank = DataStore:GetContainerItemCount(char, id)
                    alts = alts + (bags or 0) + (bank or 0)
                end
            end
        end
    end
    return mine, alts
end
SL.Have = Have

-- Does THIS character know a recipe? DataStore_Crafts remembers every
-- profession window it has seen: true / false when it has this profession
-- scanned, nil when it cannot say (no DataStore, profession never opened).
local function RecipeKnown(item, profName)
    local rec = DATA[item]
    if not (rec and profName and DataStore and DataStore.GetCharacter and DataStore.GetProfession and DataStore.IsCraftKnown) then return nil end
    local me = DataStore:GetCharacter()
    local prof = me and DataStore:GetProfession(me, profName)
    if type(prof) ~= "table" then return nil end
    return DataStore:IsCraftKnown(prof, rec[1]) == true
end
SL.RecipeKnown = RecipeKnown

-- other characters who know a recipe (DataStore_Crafts), for the tooltip
local function WhoCanCraft(item)
    local rec = DATA[item]
    if not (rec and DataStore and DataStore.GetCharacters and DataStore.GetProfessions and DataStore.IsCraftKnown) then return {} end
    local names, myName = {}, UnitName("player")
    for name, char in pairs(DataStore:GetCharacters()) do
        if name ~= myName then
            local profs = DataStore:GetProfessions(char)
            if type(profs) == "table" then
                for _, prof in pairs(profs) do
                    if type(prof) == "table" and DataStore:IsCraftKnown(prof, rec[1]) then
                        names[#names + 1] = name
                        break
                    end
                end
            end
        end
    end
    table.sort(names)
    return names
end
SL.WhoCanCraft = WhoCanCraft

-- Materials: walk every craft; an expanded craftable reagent contributes its
-- own inputs — for the crafts still needed after what you already hold —
-- instead of itself. Returns leaves (merged totals you must gather) and the
-- intermediates drilled past ({need, have, make}).
local function Accumulate(id, qty, leaves, inter, expanded, depth)
    if expanded[id] and DATA[id] and depth < 8 then
        local have = Have(id)
        local x = inter[id]
        if not x then x = { need = 0, have = have, make = 0 }; inter[id] = x end
        x.need = x.need + qty
        local make = math.max(0, x.need - have)
        local add = make - x.make          -- the part of the make not yet walked
        x.make = make
        if add > 0 then
            local numMade, reagents = Recipe(id)
            local crafts = math.ceil(add / numMade)
            for _, r in ipairs(reagents) do
                Accumulate(r[1], crafts * r[2], leaves, inter, expanded, depth + 1)
            end
        end
    else
        leaves[id] = (leaves[id] or 0) + qty
    end
end

function SL.Materials()
    local leaves, inter = {}, {}
    local db = DB()
    for _, e in ipairs(db.items) do
        if e.count > 0 then
            local numMade, reagents = Recipe(e.id)
            local crafts = math.ceil(e.count / numMade)
            for _, r in ipairs(reagents) do
                Accumulate(r[1], crafts * r[2], leaves, inter, db.expanded, 0)
            end
        end
    end
    return leaves, inter
end

-- ---------------------------------------------------------------- names --
local nameTip
local function ItemName(id)
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
    if name then
        local r, g, b = GetItemQualityColor(quality or 1)
        return name, icon, r, g, b
    end
    -- unknown to the client yet: ask once (the reply arrives shortly) and show a placeholder
    if not nameTip then
        nameTip = CreateFrame("GameTooltip", "ShoppingListNameTip", UIParent, "GameTooltipTemplate")
        nameTip:Hide()
    end
    nameTip:SetOwner(UIParent, "ANCHOR_NONE")
    nameTip:SetHyperlink("item:" .. id)
    nameTip:Hide()
    return "item " .. id, "Interface\\Icons\\INV_Misc_QuestionMark", 0.6, 0.6, 0.6
end

-- ------------------------------------------------------------ the lines --
-- One flat list the window draws: crafts, a rule, then materials.
--   { kind = "craft", id, count, done, known, prof, recipe (true/false/nil) }
--   { kind = "rule" }
--   { kind = "inter", id, need, have, make }              (drilled past, dimmed)
--   { kind = "leaf",  id, need, have, alts, craftable }   (gather these)
local function SortedIds(t)
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local na, nb = GetItemInfo(a) or ("~" .. a), GetItemInfo(b) or ("~" .. b)
        return na < nb
    end)
    return ids
end

function SL.Lines()
    local lines = {}
    local db = DB()
    for _, e in ipairs(db.items) do
        local _, prof, known = Profession(e.id)
        local recipe = nil                          -- (not "known and X or nil": X may be false)
        if known then recipe = RecipeKnown(e.id, prof) end
        lines[#lines + 1] = { kind = "craft", id = e.id, count = e.count, done = e.done, known = known, prof = prof,
                              recipe = recipe }
    end
    if #db.items == 0 then return lines end
    lines[#lines + 1] = { kind = "rule" }
    local leaves, inter = SL.Materials()
    for _, id in ipairs(SortedIds(inter)) do
        local x = inter[id]
        lines[#lines + 1] = { kind = "inter", id = id, need = x.need, have = x.have, make = x.make }
    end
    for _, id in ipairs(SortedIds(leaves)) do
        local have, alts = Have(id)
        lines[#lines + 1] = { kind = "leaf", id = id, need = leaves[id], have = have, alts = alts,
                              craftable = DATA[id] ~= nil }
    end
    return lines
end

-- --------------------------------------------------------------- window --
local frame, rows, scroll, status
local GREEN, RED, DIM, GOLD = "|cff1eff00", "|cffff4040", "|cff808080", "|cffffd100"
local hovered          -- the row under the mouse, for the Shift tooltip
local notice, noticeAt -- a short-lived status message (e.g. "recipe not known")
local function Notice(text)
    notice, noticeAt = text, GetTime()
    SL.Refresh()
end
SL.Notice = Notice
local pending          -- { item, count, prof }: a craft clicked, waiting for its window

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    DB().pos = { point, relPoint, x, y }
end

local function RestorePosition()
    local p = DB().pos
    frame:ClearAllPoints()
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

local function ShowTip(r)
    if not r.id then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. r.id)
    if r.kind == "craft" then
        if r.known == false and r.prof then
            GameTooltip:AddLine(RED .. "Needs " .. r.prof .. "|r")
            local who = WhoCanCraft(r.id)
            if #who > 0 then GameTooltip:AddLine(DIM .. "Can be made by: " .. table.concat(who, ", ") .. "|r") end
        elseif r.recipe == false then
            GameTooltip:AddLine("|cffff8000You don't know this recipe|r")
            local who = WhoCanCraft(r.id)
            if #who > 0 then GameTooltip:AddLine(DIM .. "Can be made by: " .. table.concat(who, ", ") .. "|r") end
        elseif r.known then
            GameTooltip:AddLine(DIM .. "Click to open " .. (r.prof or "the profession") .. " at this recipe|r")
        end
    elseif r.kind == "leaf" then
        if r.alts and r.alts > 0 then
            GameTooltip:AddLine(DIM .. "Also on your other characters: " .. r.alts .. "|r")
        end
        if r.craftable then GameTooltip:AddLine(DIM .. "Click to drill down into its reagents|r") end
    elseif r.kind == "inter" then
        GameTooltip:AddLine(DIM .. "Click to collapse|r")
    end
    GameTooltip:Show()
end

local function NewRow(i)
    local r = CreateFrame("Button", "ShoppingListRow" .. i, frame)
    r:SetSize(WIDTH - 40 - 22, ROW_H)   -- the FauxScrollFrame bar hangs 22 px past its frame
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -40 - (i - 1) * ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWidth(NAME_W - 20)
    r.right = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.right:SetJustifyH("RIGHT")
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetTexture(1, 1, 1, 0.25)
    r.rule:SetHeight(1)
    r.rule:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.rule:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    -- craft controls
    r.plus = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.plus:SetSize(18, 18); r.plus:SetText("+")
    r.plus:SetPoint("RIGHT", r, "RIGHT", -44, 0)
    r.minus = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.minus:SetSize(18, 18); r.minus:SetText("-")
    r.minus:SetPoint("RIGHT", r.plus, "LEFT", -2, 0)
    r.del = CreateFrame("Button", nil, r, "UIPanelCloseButton")
    r.del:SetSize(22, 22)
    r.del:SetPoint("RIGHT", r, "RIGHT", -18, 0)
    r.plus:SetScript("OnClick", function() SL.SetCount(r.id, r.count + 1) end)
    r.minus:SetScript("OnClick", function() SL.SetCount(r.id, r.count - 1) end)
    r.del:SetScript("OnClick", function() SL.Remove(r.id) end)
    -- the secure click layer over icon + name: "/cast [nocombat] <profession>"
    r.cast = CreateFrame("Button", "ShoppingListRow" .. i .. "Cast", r, "SecureActionButtonTemplate")
    r.cast:SetSize(NAME_W, ROW_H)
    r.cast:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.cast:RegisterForClicks("LeftButtonUp")
    r.cast:SetAttribute("type", "macro")
    r.cast:SetAttribute("macrotext", "")
    r.cast:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        pending = nil
        if r.kind ~= "craft" or not r.known or (r.count or 0) <= 0 then
            self:SetAttribute("macrotext", "")
            return
        end
        if r.recipe == false then                 -- F2 (ruling): disarmed, and say why
            self:SetAttribute("macrotext", "")
            Notice("You don't know this recipe (" .. r.prof .. ").")
            return
        end
        pending = { item = r.id, count = r.count, prof = r.prof }
        -- the right window is already open: select directly, no cast needed
        if TradeSkillFrame and TradeSkillFrame:IsVisible() and GetTradeSkillLine and GetTradeSkillLine() == r.prof then
            self:SetAttribute("macrotext", "")
            SL.SelectPending()
        elseif UnitCastingInfo("player") then
            self:SetAttribute("macrotext", "")   -- mid-cast: the /cast would fail silently
            pending = nil
        else
            self:SetAttribute("macrotext", "/cast [nocombat] " .. r.prof)
        end
    end)
    r.cast:SetScript("OnEnter", function() hovered = r; if IsShiftKeyDown() then ShowTip(r) end end)
    r.cast:SetScript("OnLeave", function() hovered = nil; GameTooltip:Hide() end)
    r:SetScript("OnClick", function()
        if r.kind == "leaf" and r.craftable then SL.ToggleExpand(r.id)
        elseif r.kind == "inter" then SL.ToggleExpand(r.id) end
    end)
    r:SetScript("OnEnter", function() hovered = r; if IsShiftKeyDown() then ShowTip(r) end end)
    r:SetScript("OnLeave", function() hovered = nil; GameTooltip:Hide() end)
    return r
end

local function Draw()
    if not frame or not frame:IsShown() then return end
    local lines = SL.Lines()
    local combat = InCombatLockdown()
    FauxScrollFrame_Update(scroll, #lines, ROWS, ROW_H)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, ROWS do
        local r, l = rows[i], lines[i + offset]
        r.id, r.kind, r.count, r.craftable, r.alts, r.done, r.known, r.prof, r.recipe = nil, nil, nil, nil, nil, nil, nil, nil, nil
        r.plus:Hide(); r.minus:Hide(); r.del:Hide(); r.rule:Hide(); r.icon:Hide()
        r.text:SetText(""); r.right:SetText("")
        if not combat then r.cast:SetAttribute("macrotext", "") end
        if not l then r:Hide()
        else
            r:Show()
            r.kind, r.id = l.kind, l.id
            if l.kind == "rule" then
                r.rule:Show()
            else
                local name, icon, cr, cg, cb = ItemName(l.id)
                r.icon:Show(); r.icon:SetTexture(icon)
                if l.kind == "craft" then
                    r.count, r.done, r.known, r.prof, r.recipe = l.count, l.done, l.known, l.prof, l.recipe
                    if l.done then
                        r.text:SetFormattedText(DIM .. "%s  (done)|r", name)
                    elseif not l.known then
                        r.text:SetFormattedText(DIM .. "%d x %s|r", l.count, name)
                    elseif l.recipe == false then
                        r.text:SetFormattedText("%d x |cff%02x%02x%02x%s|r |cffff8000(recipe unknown)|r", l.count, cr * 255, cg * 255, cb * 255, name)
                    else
                        r.text:SetFormattedText("%d x |cff%02x%02x%02x%s|r", l.count, cr * 255, cg * 255, cb * 255, name)
                    end
                    r.plus:Show(); r.minus:Show(); r.del:Show()
                elseif l.kind == "inter" then
                    if l.make > 0 then
                        r.text:SetFormattedText(DIM .. "%d x %s|r", l.need, name)
                        r.right:SetFormattedText(DIM .. "have %d, make %d|r", l.have, l.make)
                    else
                        r.text:SetFormattedText(DIM .. "%d x %s|r", l.need, name)
                        r.right:SetFormattedText(GREEN .. "have %d|r", l.have)
                    end
                elseif l.kind == "leaf" then
                    r.craftable, r.alts = l.craftable, l.alts
                    local glyph = l.craftable and (" " .. GOLD .. ">|r") or ""
                    r.text:SetFormattedText("%d x |cff%02x%02x%02x%s|r%s", l.need, cr * 255, cg * 255, cb * 255, name, glyph)
                    local short = l.need - l.have
                    if short > 0 then
                        r.right:SetFormattedText("%shave %d, short %d|r", RED, l.have, short)
                    else
                        r.right:SetFormattedText("%shave %d|r", GREEN, l.have)
                    end
                end
            end
        end
    end
    local db = DB()
    if notice and GetTime() - noticeAt < 6 then
        status:SetText("|cffff8000" .. notice .. "|r")
    elseif combat then
        status:SetText(RED .. "In combat: crafts can't be opened until it ends.|r")
    elseif #db.items == 0 then
        status:SetText(DIM .. "Shift-click a recipe in a trade-skill window to add it.|r")
    else
        status:SetFormattedText(DIM .. "%d craft%s|r", #db.items, #db.items == 1 and "" or "s")
    end
end

function SL.Refresh()
    if frame and frame:IsShown() then Draw() end
end
function SL.StatusText() return status and status:GetText() end   -- for the harness

-- After a craft row's click opened (or found) its profession window: expand
-- any collapsed header, find the recipe by its result item, select it and
-- pre-fill the count box with what the list still wants.
function SL.SelectPending()
    if not pending then return end
    if not (TradeSkillFrame and TradeSkillFrame:IsVisible()) then return end
    if GetTradeSkillLine() ~= pending.prof then return end
    local n = GetNumTradeSkills()
    for i = n, 1, -1 do
        local _, kind, _, isExpanded = GetTradeSkillInfo(i)
        if kind == "header" and not isExpanded then
            ExpandTradeSkillSubClass(i)      -- fires TRADE_SKILL_UPDATE; we come back
            return
        end
    end
    local want, found = "item:" .. pending.item .. ":", false
    for i = 1, n do
        local link = GetTradeSkillItemLink(i)
        if link and link:find(want, 1, true) then
            TradeSkillFrame_SetSelection(i)
            TradeSkillFrame_Update()
            if TradeSkillInputBox then TradeSkillInputBox:SetNumber(pending.count) end
            found = true
            break
        end
    end
    local prof = pending.prof
    pending = nil
    if not found then Notice("Recipe not found in " .. prof .. " (not known, or filtered out).") end
end

local function BuildFrame()
    frame = CreateFrame("Frame", "ShoppingListFrame", UIParent)
    frame:SetSize(WIDTH, 40 + ROWS * ROW_H + 36)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32,
                        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    frame:SetScript("OnShow", Draw)
    frame:SetScript("OnHide", function() DB().shown = nil end)
    frame:Hide()
    tinsert(UISpecialFrames, "ShoppingListFrame")        -- Escape closes it

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("Shopping List")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    scroll = CreateFrame("ScrollFrame", "ShoppingListScroll", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -40)
    scroll:SetSize(WIDTH - 40 - 22, ROWS * ROW_H)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Draw)
    end)
    rows = {}
    for i = 1, ROWS do rows[i] = NewRow(i) end

    status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(60, 20); clear:SetText("Clear")
    clear:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
    clear:SetScript("OnClick", SL.Clear)
    RestorePosition()
end

function SL.Toggle()
    if frame:IsShown() then frame:Hide() else frame:Show(); DB().shown = true end
end

-- ------------------------------------------------- trade-skill window --
-- A "List" button on the title row, beside the portrait — the spot Ackis
-- Recipe List uses for its scan button when set to "TL" (core.lua:831); its
-- default is "TR", at the close button, so the two never meet. The right of
-- the title is Blizzard's link button's.
local function AttachToTradeSkill()
    if not TradeSkillFrame or ShoppingListTradeButton then return end
    local b = CreateFrame("Button", "ShoppingListTradeButton", TradeSkillFrame, "UIPanelButtonTemplate")
    b:SetText("List")
    b:SetHeight(20)                                 -- ARL's own sizing: 20 high,
    b:SetWidth(b:GetTextWidth() + 10)               -- label width + 10
    b:SetPoint("LEFT", TradeSkillFramePortrait, "RIGHT", 2, 12)
    b:SetScript("OnClick", SL.Toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Shopping List")
        GameTooltip:AddLine(DIM .. "Shift-click a recipe to add it.|r")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Where would a shift-clicked link go? Blizzard's ChatEdit_InsertLink takes
-- it if a chat box is active, else the auction search box if visible, else
-- the macro editor. Only when none of those would, the click is ours.
local function LinkHasATaker()
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return true end
    if BrowseName and BrowseName:IsVisible() then return true end
    if MacroFrameText and MacroFrameText:IsVisible() then return true end
    return false
end
SL.LinkHasATaker = LinkHasATaker

function SL.OnModifiedItemClick(link)
    if type(link) ~= "string" then return end
    if not IsModifiedClick("CHATLINK") then return end
    if not (TradeSkillFrame and TradeSkillFrame:IsVisible()) then return end
    if LinkHasATaker() then return end
    local spell = tonumber(link:match("|Henchant:(%d+)"))
    local item = spell and bySpell[spell]
    if not item then return end
    SL.Add(item, 1)
    if frame and not frame:IsShown() then frame:Show(); DB().shown = true end
end

-- --------------------------------------------------------------- wiring --
local ev = CreateFrame("Frame", "ShoppingListEvents")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("MODIFIER_STATE_CHANGED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == "ShoppingList" then
            DB()
            BuildFrame()
            hooksecurefunc("HandleModifiedItemClick", SL.OnModifiedItemClick)
            if IsAddOnLoaded("Blizzard_TradeSkillUI") then AttachToTradeSkill() end
        elseif arg1 == "Blizzard_TradeSkillUI" then
            AttachToTradeSkill()
        end
    elseif event == "PLAYER_LOGIN" then
        if DB().shown then frame:Show() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" and arg2 then SL.Crafted(arg2) end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        SL.SelectPending()
        SL.Refresh()
    elseif event == "SPELLS_CHANGED" then
        SL.InvalidateBook()
        SL.Refresh()
    elseif event == "MODIFIER_STATE_CHANGED" then
        if hovered then
            if IsShiftKeyDown() then ShowTip(hovered) else GameTooltip:Hide() end
        end
    else
        SL.Refresh()
    end
end)

SLASH_SHOPPINGLIST1 = "/shop"
SLASH_SHOPPINGLIST2 = "/shoppinglist"
SlashCmdList.SHOPPINGLIST = function(msg)
    msg = (msg or ""):lower()
    if msg == "clear" then SL.Clear() else SL.Toggle() end
end
