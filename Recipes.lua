-- Recipes tab: every recipe of every profession (Data.lua, + recipes read live from an open trade skill), with craft
-- cost, AH sell price and margins from Auctionator. Recipe format: { skillLineID, name, outputItemID (0 = none),
-- outputCount, reagentID, count, reagentID, count, ... }. Rows show profession + item icons and the name in the item's
-- quality colour; clicking a row opens its reagents (icon, name, quantity and price for n crafts, Total) right under it, with
-- Crafts / Makes boxes (tooltips only), Craft and Shopping list (Auctionator) buttons. AH prices older than 3 days (Sell, reagent totals) carry an orange "!".
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local AH_CUT = 0.05      -- auction house cut on sales
local CALLER = "DoudUI"   -- Auctionator API caller id

local function API() return Auctionator and Auctionator.API and Auctionator.API.v1 end
function ns.AHPrice(id)
    local api = API()
    return api and api.GetAuctionPriceByItemID(CALLER, id) or nil
end
-- vendor unit price of a reagent (Auctionator's merchant cache, else our vendor list)
local function VendorPrice(id)
    local api = API()
    return api and api.GetVendorPriceByItemID(CALLER, id) or ns.VendorPrices[id]
end
-- a reagent's unit cost: vendor price, else the AH price
function ns.ReagentPrice(id) return VendorPrice(id) or ns.AHPrice(id) end
-- days since Auctionator saw the item on the AH (nil: never or over 21 days)
function ns.PriceAge(id)
    local api = API()
    local ok, d = pcall(function() return api and api.GetAuctionAgeByItemID(CALLER, id) end)
    return ok and d or nil
end
local STALE = " |cffff9900!|r"    -- after an AH price older than 3 days
local function Stale(id) return ns.AHPrice(id) and not ((ns.PriceAge(id) or 99) <= 3) end
local function AgeText(id)    -- "today" / "1 day old" / "N days old" / ">21 days old" (Auctionator's cutoff)
    local d = ns.PriceAge(id)
    d = d and math.floor(d)
    return not d and ">21 days old" or d < 1 and "today" or d == 1 and "1 day old" or d .. " days old"
end
-- merchant sell price of one item (nil until item info loads). Cached for the session: the client's item cache is small, so
-- re-asking for thousands of AH items (Flip tab) evicted and re-requested them in a loop, refreshing forever.
local sellCache = {}
ns.sellCache = sellCache    -- tests swap item info mocks
local function ItemSell(id)
    if sellCache[id] then return sellCache[id] end
    local ok, p = pcall(function() return select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)) end)
    p = ok and p or nil
    sellCache[id] = p
    return p
end
ns.ItemSell = ItemSell

-- cost (all reagents, nil if any is unpriced), sell (AH price x output count), margin = the better of sell after the AH cut
-- and the vendor sell price (x output count) - cost (the gold one craft makes), pct = margin / cost * 100
function ns.Calc(r)
    local cost = 0
    for i = 5, #r, 2 do
        local p = ns.ReagentPrice(r[i])
        if not p then cost = nil break end
        cost = cost + p * r[i + 1]
    end
    local sell = r[3] ~= 0 and ns.AHPrice(r[3])
    sell = sell and sell * r[4] or nil
    local v = r[3] ~= 0 and ItemSell(r[3])
    local best = sell and sell * (1 - AH_CUT)
    if v and (not best or v * r[4] > best) then best = v * r[4] end
    local margin = cost and best and best - cost
    return cost, sell, margin, margin and cost > 0 and margin / cost * 100 or nil
end

-- static data with live scans on top (the live client is the truth when it differs)
function ns.AllRecipes()
    local all = {}
    for id, r in pairs(ns.Recipes) do all[id] = r end
    for id, r in pairs(ns.db.scanned) do all[id] = r end
    return all
end
local function Recipe(id) return ns.db.scanned[id] or ns.Recipes[id] end   -- one entry of AllRecipes, no copy

-- Live scan of the open trade skill (retail-style C_TradeSkillUI: lists the profession's unlearned recipes too).
local function Scan()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeSchematic) then return end
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return end
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local sk = base and base.professionID
    sk = sk and (ns.SkillParent[sk] or sk)
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local c, learned, done = ns.Char(), {}, {}    -- learned: recipes this character knows; done: skills seen in this scan
    c.known, c.scannedSkills = c.known or {}, c.scannedSkills or {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local s = T.GetRecipeSchematic(id, false)
        local skill = sk or (ns.Recipes[id] and ns.Recipes[id][1])
        local info = T.GetRecipeInfo and T.GetRecipeInfo(id)
        local name = s and (s.name or info and info.name or ns.Recipes[id] and ns.Recipes[id][2])
        if name and skill and ns.Skills[skill] then
            local r = { skill, name, s.outputItemID or 0, s.outputItemID and math.max(1, s.quantityMin or 1) or 0 }
            for _, slot in ipairs(s.reagentSlotSchematics or {}) do
                local it = slot.reagents and slot.reagents[1] and slot.reagents[1].itemID
                if it and (basic == nil or slot.reagentType == basic) then
                    r[#r + 1] = it; r[#r + 1] = slot.quantityRequired or 1
                end
            end
            if #r > 4 then ns.db.scanned[id] = r end
            done[skill] = true
            if info and info.learned then learned[id] = true end
        end
    end
    local all = ns.AllRecipes()
    for id in pairs(c.known) do    -- re-record the scanned professions (unlearned recipes drop)
        local rr = all[id]
        if rr and done[rr[1]] then c.known[id] = nil end
    end
    for id in pairs(learned) do c.known[id] = true end
    for sk in pairs(done) do c.scannedSkills[sk] = true end
end
ns.ScanTradeSkill = Scan
local pending
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(1, function() pending = false; Scan() end)
end
ns.On("TRADE_SKILL_SHOW", Later)
ns.On("TRADE_SKILL_LIST_UPDATE", Later)

local function Pct(v) return v and ("%d%%"):format(math.floor(v + 0.5)) or "|cff808080?|r" end
local function Cell(key) return function(rec) return ns.Money(rec[key]) end end
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local function Val(key) return function(rec) return rec[key] end end
local GREEN, RED = "|cff40ff40", "|cffff4040"
local function Sign(v) return v and (v > 0 and GREEN or v < 0 and RED) or nil end
-- vendor sell of a row's output x count (header rows: r[3] = 0 -> nil)
local function VSell(rec)
    local id = rec.r[3]
    local p = id ~= 0 and ItemSell(id)
    return p and p * rec.r[4] or nil
end

local VMARK = "|TInterface\\GossipFrame\\VendorGossipIcon:12|t"
-- the Sell column's value: the vendor price when it beats the AH price after the cut (or there is no AH price), and true then
local function Shown(rec)
    local v = VSell(rec)
    if v and (not rec.sell or v > rec.sell * (1 - AH_CUT)) then return v, true end
    return rec.sell
end
-- this character's rank per profession skill line ID
local function MyRanks()
    local rk = {}
    for _, p in ipairs(ns.Char().profs or {}) do
        for sk, nm in pairs(ns.Skills) do if nm:lower() == tostring(p[1]):lower() then rk[sk] = p[2] end end
    end
    return rk
end
-- skill-up difficulty at a rank: 4 optimal (orange), 3 medium (yellow), 2 easy (green), 1 trivial; nil = not learnable yet / unknown
local function Diff(rank, u)
    if not (rank and u and rank >= u[1]) then return end
    return rank < u[2] and 4 or rank < (u[2] + u[3]) / 2 and 3 or rank < u[3] and 2 or 1
end
local DIFF = { [4] = { "Professions-Icon-Skill-High", 1, 0.5, 0.1 }, [3] = { "Professions-Icon-Skill-Medium", 1, 0.9, 0.1 },
    [2] = { "Professions-Icon-Skill-Low", 0.25, 0.8, 0.25 } }
-- Interface\\COMMON\\Indicator-Yellow / -Green tinted, when the client lacks the atlas
local function DiffIcon(d)
    local m = DIFF[d]
    if not m then return nil, 0, 0, 0, 0 end
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(m[1]) then return { atlas = m[1] } end
    return { tex = "Interface\\COMMON\\Indicator-" .. (d == 2 and "Green" or "Yellow"), color = { m[2], m[3], m[4] } }
end
-- nobody knows the recipe, and no character has its profession without having scanned it (can't tell then)
local function Unknown(id, skill)
    local name = tostring(ns.Skills[skill]):lower()
    for _, c in pairs(ns.db.chars) do
        if c.known and c.known[id] then return false end
        if not (c.scannedSkills and c.scannedSkills[skill]) then
            for _, p in ipairs(c.profs or {}) do if tostring(p[1]):lower() == name then return false end end
        end
    end
    return true
end
local function KnownBy(id)
    local l = {}
    for k, c in pairs(ns.db.chars) do if c.known and c.known[id] then l[#l + 1] = ns.CharName(k, c) end end
    table.sort(l)
    return table.concat(l, ", ")
end

-- where a recipe comes from (Data.lua ns.RecipeSource): lines coloured by kind; "Source unknown" grey when none
local SRC_COL = { Trainer = { 1, 0.82, 0 }, Vendor = { 0.4, 1, 0.4 }, Quest = { 1, 1, 0.3 } }
local function SourceLines(rec, prefix)
    local G, l = GameTooltip, ns.RecipeSource and ns.RecipeSource[rec.id]
    if not l then G:AddLine("Source unknown", 0.6, 0.6, 0.6) return end
    for _, s in ipairs(l) do
        local c = SRC_COL[s:match("^%a+")] or { 1, 1, 1 }
        G:AddLine((prefix or "") .. s, c[1], c[2], c[3], true)
    end
end
-- hover text of the "not known" tag
local function TagTip(rec)
    GameTooltip:SetText("Not known")
    local it = ns.RecipeItem and ns.RecipeItem[rec.id]
    if it then GameTooltip:AddLine((ns.ItemColor(it) or "|cffffffff") .. ns.ItemName(it) .. "|r", 1, 1, 1) end
    SourceLines(rec)
end

-- recipe tooltip: the game's own (recipe result item), else its output item, else the spell
local function BaseTip(rec)
    if rec.kind == "hdr" then return end
    if rec.kind == "mat" then GameTooltip:SetItemByID(rec.r[3]) return end
    if GameTooltip.SetRecipeResultItem and pcall(GameTooltip.SetRecipeResultItem, GameTooltip, rec.id)
        and (GameTooltip:NumLines() or 0) > 0 then return end    -- unlearned recipes can leave it empty
    if rec.r[3] ~= 0 then GameTooltip:SetItemByID(rec.r[3]) else GameTooltip:SetSpellByID(rec.id) end
end

-- + craft cost, AH / vendor sell, margin and who knows the recipe
local function Tip(rec)
    BaseTip(rec)
    if rec.kind then return end
    local r, G = rec.r, GameTooltip
    G:AddLine(" ")
    G:AddDoubleLine("Craft cost", ns.Money(rec.cost))
    if r[3] ~= 0 then
        G:AddDoubleLine("Sell (AH)", ns.Money(rec.sell) .. (rec.sell and (Stale(r[3]) and "  |cffff9900" or "  |cff909090") .. AgeText(r[3]) .. "|r" or ""))
        local v = VSell(rec)
        if v then G:AddDoubleLine("Sell (vendor)", ns.Money(v)) end
    end
    if rec.margin then G:AddDoubleLine("Margin", ns.Money(rec.margin, Sign(rec.margin))) end
    local k = KnownBy(rec.id)
    if k ~= "" then G:AddLine("Known by: " .. k, 1, 1, 1, true) end
    if Unknown(rec.id, r[1]) then SourceLines(rec, "Source: ") end
end

-- gathering professions -> the item subclass (class 7, Trade Goods) of their raw materials
local RAW = { [182] = 9, [186] = 7, [393] = 6 }
local rawCache = {}
-- ponytail: subclass-based heuristic, so it may include crafted items of that subclass (e.g. crafted leathers) that no
-- gathering recipe makes; upgrade = an explicit list generated by gen.py.
local function Raw(sk)
    if rawCache[sk] then return rawCache[sk] end
    local all, made, seen, list = ns.AllRecipes(), {}, {}, {}
    for _, r in pairs(all) do if r[1] == sk and r[3] ~= 0 then made[r[3]] = true end end
    local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    for _, r in pairs(all) do
        for i = 5, #r, 2 do
            local id = r[i]
            if not seen[id] and not made[id] then
                seen[id] = true
                local ok, cls, sub = pcall(function() return select(6, f(id)) end)
                if ok and cls == 7 and sub == RAW[sk] then list[#list + 1] = id end
            end
        end
    end
    rawCache[sk] = list
    return list
end
ns.RawMaterials = Raw

local ICONS = {
    [40] = "Trade_BrewPoison", [129] = "Spell_Holy_SealOfSacrifice", [164] = "Trade_BlackSmithing",
    [165] = "INV_Misc_ArmorKit_17", [171] = "Trade_Alchemy", [182] = "Spell_Nature_NatureTouchGrow",
    [185] = "INV_Misc_Food_15", [186] = "Trade_Mining", [197] = "Trade_Tailoring", [202] = "Trade_Engineering",
    [333] = "Trade_Engraving", [393] = "INV_Misc_Pelt_Wolf_01",
}
ns.SkillIcons = ICONS
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
-- filter button groups: crafting, gathering, other (unlisted skills join "other")
local GROUPS = { { 171, 164, 185, 333, 202, 165, 197 }, { 182, 186, 393 }, { 129, 40 } }
local SYNC = { "TimeOfLastBrowseScan", "TimeOfLastReplicateScan", "TimeOfLastGetAllScan" }
local function SpellIcon(id)
    local ok, ic = pcall(function() return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or GetSpellTexture and GetSpellTexture(id) end)
    return ok and ic or nil
end
-- "last sync 5 min" from Auctionator's newest scan time
local function SyncText()
    local v, best = AUCTIONATOR_SAVEDVARS, 0
    if type(v) == "table" then for _, k in ipairs(SYNC) do if type(v[k]) == "number" and v[k] > best then best = v[k] end end end
    if best == 0 then return "|cffff4040last sync never|r" end
    local d = math.max(0, time() - best)
    local col = d > 3600 and "|cffff4040" or d > 1800 and "|cffff9900" or "|cff909090"
    local n, u = math.max(1, math.floor(d / 60)), "min"
    if d >= 86400 then n, u = math.floor(d / 86400), "day" elseif d >= 3600 then n, u = math.floor(d / 3600), "hour" end
    return ("%slast sync %d %s%s|r"):format(col, n, u, u ~= "min" and n ~= 1 and "s" or "")
end
-- column widths (star, skill-up, Recipe, Craft cost, Sell, Margin, Margin %): the window is sized to fit the table
-- (+ 14 scrollbar) with the page's 12px inset and the table's 4px margin on both sides
local COLW = { 24, 22, 428, 130, 130, 130, 90 }
do local w = 14 + 2 * (12 + 4); for _, v in ipairs(COLW) do w = w + v end; ns.W = w end
local function Plain(v) return (tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

table.insert(ns.tabs, { name = "Recipes", build = function(page)
    local skills, search, showHidden, rawOpen = {}, "", false, false    -- skills: selected profession IDs (empty = all); rawOpen: raw materials section expanded
    local favOnly, vendorOnly = false, false
    local cols = {
        { title = "", width = COLW[1], value = function(rec) return ns.db.fav[rec.id] and 0 or 1 end,
            -- ReputationStar: filled star left half of the sheet, empty right half
            icon = function(rec)
                if rec.kind then return nil, 0, 0, 0, 0 end
                return "Interface\\Common\\ReputationStar", ns.db.fav[rec.id] and 0 or 0.5, ns.db.fav[rec.id] and 0.5 or 1, 0, 0.5
            end },
        { title = "", width = COLW[2], desc = true, value = function(rec) return rec.diff end,
            -- skill-up difficulty, like the profession window's: orange / yellow / green mark (nothing when trivial)
            icon = function(rec) return DiffIcon(rec.diff) end },
        { title = "Recipe", width = COLW[3], mat = true, value = function(rec) return rec.r[2] end,
            text = function(rec)
                if rec.kind == "hdr" then
                    return "|TInterface\\Buttons\\UI-" .. (rawOpen and "Minus" or "Plus") .. "Button-Up:14|t " .. rec.r[2]
                end
                local c = ns.ItemColor(rec.r[3])
                local n = rec.kind == "mat" and ns.ItemName(rec.r[3]) or rec.r[2]
                return c and c .. n .. "|r" or n
            end,
            tag = function(rec) return not rec.kind and Unknown(rec.id, rec.r[1]) and "not known" or nil end, tagTip = TagTip, nameTip = true,
            icons = function(rec)
                local r = rec.r
                if rec.kind == "hdr" then return {} end
                if rec.kind == "mat" then return { ns.ItemIcon(r[3]) or QMARK } end
                return { "Interface\\Icons\\" .. (ICONS[r[1]] or "INV_Misc_QuestionMark"),
                    (r[3] ~= 0 and ns.ItemIcon(r[3]) or r[3] == 0 and SpellIcon(rec.id)) or QMARK }
            end },
        { title = "Craft cost", width = COLW[4], right = true, desc = true, value = Val("cost"), text = Cell("cost") },
        { title = "Sell", width = COLW[5], right = true, desc = true, mat = true, value = function(rec) return (Shown(rec)) end,
            text = function(rec)    -- AH price (+ "!" when old), or the vendor's with a vendor mark (green: beats the craft cost)
                local v, vend = Shown(rec)
                if vend then return VMARK .. " " .. ns.Money(v, rec.cost and v > rec.cost and GREEN or nil) end
                return ns.Money(v) .. (v and Stale(rec.r[3]) and STALE or "")
            end },
        { title = "Margin", width = COLW[6], right = true, desc = true, value = Val("margin"),
            text = function(rec) return ns.Money(rec.margin, Sign(rec.margin)) end },
        { title = "Margin %", width = COLW[7], right = true, desc = true, value = Val("pct"),
            text = function(rec) local c = Sign(rec.pct); return c and c .. Pct(rec.pct) .. "|r" or Pct(rec.pct) end },
    }
    for k = 3, #cols do    -- hidden recipes (shown on request) are grey
        local c = cols[k]
        local f = c.text or c.value
        c.text = function(rec)
            if rec.kind and (rec.kind == "hdr" and k > 3 or not c.mat) then return "" end    -- header / material rows: blank cells
            local v = f(rec)
            return ns.db.hidden[rec.id] and v ~= nil and "|cff808080" .. Plain(v) .. "|r" or v
        end
    end
    local Refresh, Panel, sel, P, Layout
    local justHidden = {}    -- hidden this visit: still listed (grey) so a second right-click un-hides it; dropped on the next show
    local nCraft = 1    -- crafts of the selected recipe (Crafts box)
    -- rows that fill the page under the table's start: page = frame minus 30 top / 12 bottom insets (Core.lua), table starts at TOP,
    -- header + rows are 21px each; the last row is only dropped when a whole one doesn't fit
    local TOP = 68
    local nre = math.floor((ns.H - 42 - TOP) / 21) - 1
    local t = ns.Table(page, cols, nre, Tip, 6, true, {
        item = function(rec) return not rec.kind and rec.r and rec.r[3] end,
        pin = function(rec) return rec.kind == "hdr" and 0 or rec.kind == "mat" and 1 or ns.db.fav[rec.id] and 2 end,
        selected = function(rec) return rec.id == sel end,
        expand = function(rec) return rec.id == sel and P or nil end,
        click = function(rec, btn, col)
            if rec.kind == "hdr" then rawOpen = not rawOpen; Refresh() return end
            if rec.kind then return end
            local tbl = btn == "RightButton" and ns.db.hidden or col == 1 and ns.db.fav
            if tbl == ns.db.hidden then justHidden[rec.id] = true end
            if not tbl then sel = rec.id ~= sel and rec.id or nil; nCraft = 1; Panel(); page.table:Redraw() return end
            tbl[rec.id] = not tbl[rec.id] or nil
            Refresh()
        end })
    t:SetPoint("TOPLEFT", 4, -TOP)
    page.table = t

    -- the selected recipe's panel, opened under its row: one reagent per row (up to 12: icon, name, x quantity, total price for n
    -- crafts), a separator and the Total (page.total) under them; right of them: Crafts / Makes boxes (linked through the output
    -- count), Craft, Shopping list and "can make N"
    P = CreateFrame("Frame", nil, t)
    P:SetWidth(t.width - 14); P:Hide()
    local bg = P:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    for _, a in ipairs({ "TOP", "BOTTOM" }) do
        local ln = P:CreateTexture(nil, "ARTWORK"); ln:SetHeight(1); ln:SetColorTexture(0.8, 0.64, 0.36, 0.5)
        ln:SetPoint(a .. "LEFT"); ln:SetPoint(a .. "RIGHT")
    end
    -- reagent columns line up with the table's: icon under the recipe's item icon (2nd icon of the Recipe cell), name under its
    -- name, totals in the Craft cost cell; same formulas as ns.Table's Draw
    local cx = t.colX
    local iconX, nameX = cx[3] + 4 + 20, cx[3] + 4 + 2 * 20
    local rl = {}
    for i = 1, 12 do
        local b = CreateFrame("Button", nil, P)
        b:SetSize(cx[5], 18); b:SetPoint("TOPLEFT", 0, -4 - (i - 1) * 18)
        b:SetHighlightTexture(HIGHLIGHT, "ADD")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", iconX, 0)
        b.name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b.name:SetSize(cx[4] - nameX - 4, 18); b.name:SetPoint("LEFT", nameX, 0); b.name:SetJustifyH("LEFT"); b.name:SetWordWrap(false)
        b.total = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b.total:SetSize(cols[4].width - 8, 18); b.total:SetPoint("LEFT", cx[4] + 4, 0); b.total:SetJustifyH("RIGHT")
        function b:ItemTip()
            GameTooltip:SetItemByID(self.id)
            if not VendorPrice(self.id) and ns.AHPrice(self.id) then
                if Stale(self.id) then GameTooltip:AddLine("AH price " .. AgeText(self.id), 1, 0.6, 0) else GameTooltip:AddLine("AH price " .. AgeText(self.id), 0.6, 0.6, 0.6) end
            end
            GameTooltip:Show()
        end
        function b:UpdateTooltip()   -- Blizzard calls it every 0.2s: refill only when Shift flips, else the tooltip flashes
            local sh = IsShiftKeyDown()
            if sh ~= self.shift then self.shift = sh; self:ItemTip() end
        end
        b:SetScript("OnEnter", function(self)
            if not (self.id and GameTooltip.SetItemByID) then return end
            ns.TipOwner(self); self.shift = nil; self:UpdateTooltip()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        rl[i] = b
    end
    local sep = P:CreateTexture(nil, "ARTWORK"); sep:SetSize(cols[4].width - 8, 1); sep:SetColorTexture(0.8, 0.64, 0.36, 0.5)
    local totL, tot = P:CreateFontString(nil, "ARTWORK", "GameFontHighlight"), P:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tot:SetSize(cols[4].width - 8, 18); tot:SetJustifyH("RIGHT"); totL:SetText("Total")
    page.reagents, page.panel = rl, P

    -- the controls sit at the panel's right edge: buttons (130 wide, 10 in), a numeric box (tooltip names it) left of each
    local function Box(anchor, tip)
        local e = CreateFrame("EditBox", nil, P, "InputBoxTemplate")
        e:SetSize(44, 20); e:SetPoint("RIGHT", anchor, "LEFT", -8, 0); e:SetAutoFocus(false); e:SetNumeric(true); e:SetMaxLetters(5)
        e:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip); GameTooltip:Show() end)
        e:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return e
    end
    local craft = ns.Chip(P, 130, 24, "Craft"); craft:SetPoint("TOPRIGHT", P, "TOPRIGHT", -10, -9)
    local shop = ns.Chip(P, 130, 24, "Shopping list"); shop:SetPoint("TOPRIGHT", P, "TOPRIGHT", -10, -35)
    local cnt = Box(craft, "Number of crafts")
    local mk = Box(shop, "Number of items made")
    cnt:SetText("1")
    page.crafts, page.makes = cnt, mk
    -- typing (userInput only, no loops): Crafts -> Makes = n x output; Makes -> Crafts = ceil(m / output); the other box is left alone
    cnt:SetScript("OnTextChanged", function(_, user)
        local v = user and tonumber(cnt:GetText())
        if v and v >= 1 then nCraft = math.floor(v); Panel(cnt) end
    end)
    mk:SetScript("OnTextChanged", function(_, user)
        local v, r = user and tonumber(mk:GetText()), sel and Recipe(sel)
        if v and r and r[4] > 0 then nCraft = math.max(1, math.ceil(v / r[4])); Panel(mk) end
    end)
    for _, e in ipairs({ cnt, mk }) do    -- normalise both boxes
        e:SetScript("OnEditFocusLost", function() Panel() end)
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Panel() end)
    end
    -- craft the selected recipe through the open profession window: Craft button, "can make N"
    local can = P:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    can:SetPoint("RIGHT", cnt, "LEFT", -10, 0); can:SetJustifyH("RIGHT")
    page.craft, page.shop = craft, shop
    local function UpdateCraft()
        local r, T = sel and Recipe(sel), C_TradeSkillUI
        for _, w in ipairs({ cnt, craft, shop }) do w:SetShown(r ~= nil) end
        mk:SetShown(r ~= nil and r[3] ~= 0)
        can:SetText("")
        if not r then return end
        shop.why = not API() and "Auctionator not loaded" or nil
        shop:SetEnabled(not shop.why)
        local why, info
        local okB, base = pcall(function() return T and T.GetBaseProfessionInfo and T.GetBaseProfessionInfo() end)
        local pid = okB and base and base.professionID
        if not (T and T.CraftRecipe) then why = "Crafting is not available"
        elseif not (ProfessionsFrame and ProfessionsFrame:IsShown() and pid and (ns.SkillParent[pid] or pid) == r[1]) then
            why = "Open " .. (ns.Skills[r[1]] or "the profession") .. " to craft"
        else
            local ok, i = pcall(T.GetRecipeInfo, sel)
            info = ok and i or nil
            if not (info and info.learned) then why = "Recipe not learned" end
        end
        craft.why = why
        craft:SetEnabled(not why)
        if not why then can:SetText("can make " .. (info.numAvailable or 0)) end
    end
    craft:SetScript("OnClick", function()
        if craft.why then return end
        local ok, err = pcall(C_TradeSkillUI.CraftRecipe, sel, nCraft)
        if not ok then FT.Print("craft failed: " .. tostring(err)) end
    end)
    -- Auctionator shopping list of what the n crafts still need (bags + bank counted); vendor-bought reagents are only named
    shop:SetScript("OnClick", function()
        local r, api = sel and Recipe(sel), API()
        if not (r and api) then return end
        local ok, err = pcall(function()
            local terms, vend, unk = {}, {}, {}
            for i = 5, #r, 2 do
                local id = r[i]
                local okC, have = pcall(GetItemCount, id, true)
                local need = r[i + 1] * nCraft - (okC and tonumber(have) or 0)
                local nm = ns.ItemName(id)
                if need > 0 then
                    if VendorPrice(id) then vend[#vend + 1] = nm
                    elseif nm == "item " .. id then unk[#unk + 1] = nm
                    else terms[#terms + 1] = api.ConvertToSearchString(CALLER, { searchString = nm, isExact = true, quantity = need }) end
                end
            end
            if #vend > 0 then FT.Print("buy from a vendor: " .. table.concat(vend, ", ")) end
            if #unk > 0 then FT.Print("skipped (name not loaded yet, try again): " .. table.concat(unk, ", ")) end
            if #terms == 0 then FT.Print("shopping list: nothing to buy") return end
            local name = "Doud: " .. r[2] .. " x" .. nCraft
            api.CreateShoppingList(CALLER, name, terms)
            FT.Print("shopping list " .. name .. " created (" .. #terms .. " items)")
        end)
        if not ok then FT.Print("shopping list failed: " .. tostring(err)) end
    end)
    for _, b in ipairs({ craft, shop }) do
        b:HookScript("OnEnter", function(self)    -- Chip (shared skin) keeps its own hover look
            if not self.why then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.why); GameTooltip:Show()
        end)
    end
    for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "BAG_UPDATE_DELAYED" }) do
        ns.On(e, function() if page:IsShown() then UpdateCraft() end end)
    end
    -- fills the panel and sizes it; the table (Redraw / SetRows) places it under the selected row. skip: the box being typed in
    function Panel(skip)
        local r = sel and Recipe(sel)
        for _, b in ipairs(rl) do b:Hide(); b.id = nil end
        UpdateCraft()
        sep:Hide(); totL:SetText(""); tot:SetText(""); page.total = nil
        if not r then return end
        if skip ~= cnt then cnt:SetText(tostring(nCraft)) end
        if skip ~= mk then mk:SetText(tostring(nCraft * r[4])) end
        local n = 0
        for i, b in ipairs(rl) do
            local id, q = r[3 + i * 2], r[4 + i * 2]
            if not id then break end
            local col, p = ns.ItemColor(id), ns.ReagentPrice(id)
            n = i
            b.id = id
            b.icon:SetTexture(ns.ItemIcon(id) or QMARK)
            b.name:SetText((col or "") .. ns.ItemName(id) .. (col and "|r" or "") .. "  x" .. q * nCraft)
            b.total:SetText(ns.Money(p and p * q * nCraft) .. (p and not VendorPrice(id) and Stale(id) and STALE or ""))
            b:Show()
        end
        local cost = ns.Calc(r)
        page.total = cost and cost * nCraft
        local y = -4 - n * 18
        sep:ClearAllPoints(); sep:SetPoint("TOPLEFT", cx[4] + 4, y - 2); sep:Show()
        totL:ClearAllPoints(); totL:SetPoint("TOPLEFT", nameX, y - 6); totL:SetText("Total")
        tot:ClearAllPoints(); tot:SetPoint("TOPLEFT", cx[4] + 4, y - 4); tot:SetText(ns.Money(page.total))
        P:SetHeight(math.max(32 + n * 18, 66))
    end
    local queued    -- item data arrived: repaint once (icons, colours, names)
    local function Repaint()
        if queued or not page:IsShown() then return end
        queued = true
        C_Timer.After(0.5, function() queued = false; Panel(); t:Redraw() end)
    end
    ns.On("GET_ITEM_INFO_RECEIVED", Repaint)
    ns.On("ITEM_DATA_LOAD_RESULT", Repaint)

    function Refresh()
        if Layout then Layout() end
        local list, q, rk = {}, search:lower(), MyRanks()
        for id, r in pairs(ns.AllRecipes()) do
            if (next(skills) == nil or skills[r[1]]) and (q == "" or r[2]:lower():find(q, 1, true))
                and (showHidden or not ns.db.hidden[id] or justHidden[id]) and (not favOnly or ns.db.fav[id])
                and not (ns.db.hideUnknown and Unknown(id, r[1])) then
                local cost, sell, margin, pct = ns.Calc(r)
                if not vendorOnly or (VSell({ r = r }) or 0) > (cost or math.huge) then list[#list + 1] = { id = id, r = r, cost = cost, sell = sell, margin = margin, pct = pct, diff = Diff(rk[r[1]], ns.SkillUp[id]) } end
            end
        end
        local first, seen, mats = nil, {}, {}
        for sk in pairs(skills) do if RAW[sk] and (not first or sk < first) then first = sk end end
        if first then    -- gathering profession(s) selected: one collapsible raw materials section (merged, deduped)
            for sk in pairs(skills) do
                for _, id in ipairs(RAW[sk] and Raw(sk) or {}) do
                    if not seen[id] and (q == "" or ns.ItemName(id):lower():find(q, 1, true)) then
                        seen[id] = true
                        mats[#mats + 1] = { kind = "mat", id = "m" .. id, r = { sk, "", id, 1 }, sell = ns.AHPrice(id) }
                    end
                end
            end
            list[#list + 1] = { kind = "hdr", id = "hdr", r = { first, "Raw materials (" .. #mats .. ")", 0, 0 } }
            if rawOpen then for _, m in ipairs(mats) do list[#list + 1] = m end end
        end
        Panel()
        t:SetRows(list)
        page.count:SetText(SyncText() .. (API() and "" or "  |cffff6060(Auctionator not loaded: no prices)|r"))
    end
    page.Refresh = function() justHidden = {}; Refresh() end

    -- profession filter: a row of icon buttons (All + each profession), a gold ring on each selected one (multi-select)
    local groups, listed, extra = { { false } }, {}, {}
    for _, g in ipairs(GROUPS) do
        local l = {}
        for _, id in ipairs(g) do listed[id] = true; if ns.Skills[id] then l[#l + 1] = id end end
        groups[#groups + 1] = l
    end
    for id in pairs(ns.Skills) do if not listed[id] then extra[#extra + 1] = id end end
    table.sort(extra, function(a, b) return ns.Skills[a] < ns.Skills[b] end)
    for _, id in ipairs(extra) do table.insert(groups[#groups], id) end
    local ids, gap, grp = {}, {}, {}    -- flat list; gap[n] = first button of a group; grp[n] = its group number
    for gi, g in ipairs(groups) do
        for j, id in ipairs(g) do ids[#ids + 1] = id; gap[#ids] = j == 1; grp[#ids] = gi end
    end
    local buttons = {}
    page.buttons = buttons
    local bx = 4
    local function Mark(b, on)
        b.sel:SetShown(on)
        b.icon:SetDesaturated(not on); b.icon:SetVertexColor(on and 1 or 0.7, on and 1 or 0.7, on and 1 or 0.7)
    end
    local function Place(b, x) b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -4); b.x = x end
    local mineBtn
    for n, id in ipairs(ids) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(32, 32)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexture("Interface\\Icons\\" .. (id and (ICONS[id] or "INV_Misc_QuestionMark") or "INV_Misc_Book_09"))
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.sel:SetBlendMode("ADD")
        b.sel:SetSize(68, 68); b.sel:SetPoint("CENTER")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function()
            ns.db.mine = nil    -- custom selection
            if id then skills[id] = not skills[id] or nil else wipe(skills) end
            Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(id and ns.Skills[id] or "All professions"); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.id = id
        Mark(b, not id)
        buttons[#buttons + 1] = b
    end
    -- lay the buttons out left to right (gap before each group's first button), all always visible; ring = selected;
    -- "My professions" on -> the selection is this character's learned professions
    function Layout()
        if ns.db.mine then
            wipe(skills)
            for sk in pairs(MyRanks()) do skills[sk] = true end
        end
        local x, lastG = 4, nil
        for n, b in ipairs(buttons) do
            if lastG and grp[n] ~= lastG then x = x + 10 end
            lastG = grp[n]
            Place(b, x); x = x + 36
            Mark(b, b.id and skills[b.id] or not b.id and next(skills) == nil)
        end
        if mineBtn then Mark(mineBtn, ns.db.mine and true or false) end
    end
    -- "My professions" toggle at the far right end of the full row
    do
        local x = 4
        for n = 1, #buttons do if gap[n] and n > 1 then x = x + 10 end; x = x + 36 end
        mineBtn = CreateFrame("Button", nil, page)
        mineBtn:SetSize(32, 32); Place(mineBtn, x + 10)
        mineBtn.icon = mineBtn:CreateTexture(nil, "ARTWORK"); mineBtn.icon:SetAllPoints()
        mineBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
        if SetPortraitTexture then pcall(SetPortraitTexture, mineBtn.icon, "player") end
        mineBtn.sel = mineBtn:CreateTexture(nil, "OVERLAY")
        mineBtn.sel:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); mineBtn.sel:SetBlendMode("ADD")
        mineBtn.sel:SetSize(68, 68); mineBtn.sel:SetPoint("CENTER")
        mineBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        mineBtn:SetScript("OnClick", function()
            if ns.db.mine then ns.db.mine = nil; wipe(skills) else ns.db.mine = true end
            Refresh()
        end)
        mineBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Select this character's professions"); GameTooltip:Show()
        end)
        mineBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        page.mineBtn = mineBtn
        Mark(mineBtn, ns.db.mine and true or false)
    end

    local ok, box = pcall(CreateFrame, "EditBox", nil, page, "SearchBoxTemplate")
    if not ok or not box then box = CreateFrame("EditBox", nil, page, "InputBoxTemplate") end
    box:SetSize(240, 20); box:SetPoint("TOPRIGHT", -10, -10); box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function(self) search = self:GetText() or ""; Refresh() end)
    page.search = box
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 6, -40)
    cb:SetScript("OnClick", function(self) showHidden = self:GetChecked() and true or false; Refresh() end)
    local cbl = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbl:SetPoint("LEFT", cb, "RIGHT", 0, 1); cbl:SetText("Show hidden")
    page.showBox = cb
    local fb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    fb:SetSize(24, 24); fb:SetPoint("LEFT", cbl, "RIGHT", 12, -1)
    fb:SetScript("OnClick", function(self) favOnly = self:GetChecked() and true or false; Refresh() end)
    local fbl = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fbl:SetPoint("LEFT", fb, "RIGHT", 0, 1); fbl:SetText("Favorites only")
    page.favBox = fb
    local vb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    vb:SetSize(24, 24); vb:SetPoint("LEFT", fbl, "RIGHT", 12, -1)
    vb:SetScript("OnClick", function(self) vendorOnly = self:GetChecked() and true or false; Refresh() end)
    local vbl = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    vbl:SetPoint("LEFT", vb, "RIGHT", 0, 1); vbl:SetText("Vendor profit only")
    page.vendorBox = vb
    local db = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    db:SetSize(24, 24); db:SetPoint("LEFT", vbl, "RIGHT", 12, -1); db:SetChecked(ns.db.hideUnknown and true or false)
    db:SetScript("OnClick", function(self) ns.db.hideUnknown = self:GetChecked() and true or nil; Refresh() end)
    local dbl = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dbl:SetPoint("LEFT", db, "RIGHT", 0, 1); dbl:SetText("Hide unknown")
    page.dimBox = db
    page.count = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    page.count:SetPoint("RIGHT", page, "TOPRIGHT", -10, -52)
end })

end)
