-- Disenchant tab (only shown to characters who know Disenchant): the uncommon to epic weapons and armour in the bags
-- (bags 0-4: equipped gear never listed). The Disenchant button casts on the first listed, not ignored item through a
-- secure action button (type "spell", target-bag / target-slot): its attributes are only set out of combat (re-armed on
-- PLAYER_REGEN_ENABLED) and follow the list on every bag change. The button hangs off UIParent, not the window (a
-- secure child would make the whole window protected: no Hide / Escape in combat); it is anchored to the page and
-- shown only out of combat, hidden and unanchored when combat starts. Right-click a row: ignore it / take it back
-- (ns.db.deIgnore[itemID], account-wide). Options: soulbound only (ns.db.deBound), open this tab with Enchanting (ns.db.deAuto).
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local SPELL, ENCHANTING = 13262, 333
local TAB = "Disenchant"
local SKIP = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true }

function ns.KnowsDisenchant()
    if IsPlayerSpell and IsPlayerSpell(SPELL) then return true end
    if IsSpellKnown and IsSpellKnown(SPELL) then return true end
    return C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(SPELL) or false
end
local function SpellName()
    local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(SPELL)
    return type(i) == "table" and i.name or GetSpellInfo and GetSpellInfo(SPELL) or SPELL
end

-- Classic-style disenchant table, approximate (the client exposes no loot tables): { quality, minIlvl, maxIlvl, { {itemID, %} } }.
-- Real results are recorded per quality / 5-ilvl bracket in ns.db.deObs ("q:bracket" = { n = disenchants, [itemID] = times seen })
-- and shown next to it; once a bracket has OBS_MIN disenchants the observed odds replace the table's in the expected value.
local OBS_MIN = 10
local DE = {
    { 2, 1, 15, { { 10940, 80 }, { 10938, 20 } } },
    { 2, 16, 20, { { 10940, 75 }, { 10939, 20 }, { 10978, 5 } } },
    { 2, 21, 25, { { 10940, 15 }, { 11083, 75 }, { 10998, 10 } } },
    { 2, 26, 30, { { 11083, 75 }, { 11082, 20 }, { 11084, 5 } } },
    { 2, 31, 35, { { 11137, 75 }, { 11134, 20 }, { 11138, 5 } } },
    { 2, 36, 40, { { 11137, 75 }, { 11135, 20 }, { 11139, 5 } } },
    { 2, 41, 45, { { 11176, 75 }, { 11174, 20 }, { 11177, 5 } } },
    { 2, 46, 50, { { 11176, 75 }, { 11175, 20 }, { 11178, 5 } } },
    { 2, 51, 55, { { 16204, 75 }, { 16202, 20 }, { 14343, 5 } } },
    { 2, 56, 999, { { 16204, 75 }, { 16203, 20 }, { 14344, 5 } } },
    { 3, 1, 25, { { 10978, 100 } } }, { 3, 26, 30, { { 11084, 100 } } }, { 3, 31, 35, { { 11138, 100 } } },
    { 3, 36, 40, { { 11139, 100 } } }, { 3, 41, 45, { { 11177, 100 } } }, { 3, 46, 50, { { 11178, 100 } } },
    { 3, 51, 55, { { 14343, 100 } } }, { 3, 56, 999, { { 14344, 100 } } },
    { 4, 1, 50, { { 11178, 100 } } }, { 4, 51, 55, { { 14344, 100 } } }, { 4, 56, 999, { { 20725, 100 } } },
}
local function Bracket(q, ilvl) return q .. ":" .. math.floor((ilvl or 0) / 5) end

-- { id, pct (table), n, c (observed: c of n disenchants), price (AH, nil unknown), p (the odds used for the value) } per possible result
function ns.DisenchantOutcomes(q, ilvl)
    local out, at = {}, {}
    for _, e in ipairs(DE) do
        if e[1] == q and ilvl and ilvl >= e[2] and ilvl <= e[3] then
            for _, d in ipairs(e[4]) do at[d[1]] = #out + 1; out[#out + 1] = { id = d[1], pct = d[2] } end
        end
    end
    local o = ns.db.deObs[Bracket(q, ilvl)]
    local n = o and o.n or 0
    for id, c in pairs(o or {}) do
        if id ~= "n" and not at[id] then at[id] = #out + 1; out[#out + 1] = { id = id } end
    end
    for _, r in ipairs(out) do
        r.n, r.c, r.price = n, o and o[r.id] or 0, ns.AHPrice(r.id)
        r.p = n >= OBS_MIN and r.c / n * 100 or r.pct or 0
    end
    return out
end

-- watch the cast: the item the button targeted is remembered at click, the loot messages right after a successful cast count
local pending
local function LootPattern(f) return "^" .. f:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$" end
local LOOT = {}
for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
    if _G[g] then LOOT[#LOOT + 1] = LootPattern(_G[g]) end
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, id)
    if unit == "player" and id == SPELL and pending then pending.t = GetTime() end
end)
ns.On("CHAT_MSG_LOOT", function(msg)
    if not (pending and pending.t and GetTime() - pending.t < 5 and type(msg) == "string") then return end
    for _, pat in ipairs(LOOT) do
        local link = msg:match(pat)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local o = ns.db.deObs[pending.key]
            if not o then o = { n = 0 }; ns.db.deObs[pending.key] = o end
            if not pending.counted then pending.counted = true; o.n = o.n + 1 end
            o[id] = (o[id] or 0) + 1
            return
        end
    end
end)

-- a bag slot as C_Container's info table (legacy GetContainerItemInfo returns mapped), nil when empty
local function SlotInfo(bag, slot)
    local C = C_Container
    if C and C.GetContainerItemInfo then return C.GetContainerItemInfo(bag, slot) end
    if not GetContainerItemInfo then return end
    local tex, count, locked, q, _, _, link, _, _, id, bound = GetContainerItemInfo(bag, slot)
    return id and { iconFileID = tex, stackCount = count, isLocked = locked, quality = q, hyperlink = link, itemID = id, isBound = bound }
end
local function NumSlots(bag)
    local fn = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    return fn and fn(bag) or 0
end

-- quality of an item the bag info doesn't know yet (not cached at the first open): asks the client to load it, the tab lists again when it arrives
local function ItemQuality(id)
    local ok, q = pcall(function() return C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) end)
    if ok and q then return q end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- { bag, slot, id, link, name, icon, q, ilvl, bound } per disenchantable bag item (ignored ones included); locked items
-- (being moved or disenchanted) skipped
function ns.DisenchantItems()
    local list = {}
    local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local level = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
    if not instant then return list end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, NumSlots(bag) do
            local i = SlotInfo(bag, slot)
            local q = i and i.itemID and not i.isLocked and (i.quality or ItemQuality(i.itemID))
            if q and q >= 2 and q <= 4 and (i.isBound or not ns.db.deBound) then
                local _, _, _, loc, icon, class = instant(i.itemID)
                if (class == 2 or class == 4) and not SKIP[loc or ""] then
                    local link = i.hyperlink
                    list[#list + 1] = { bag = bag, slot = slot, id = i.itemID, link = link, q = q, bound = i.isBound,
                        name = link and link:match("%[(.-)%]") or ns.ItemName(i.itemID), icon = i.iconFileID or icon,
                        ilvl = link and level and level(link) or nil }
                end
            end
        end
    end
    return list
end

-- an item's own auction price (by link first: gear is priced per item level), nil unknown
local function ItemAH(r)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and r.link and api.GetAuctionPriceByItemLink then
        local ok, p = pcall(api.GetAuctionPriceByItemLink, "DoudUI", r.link)
        if ok and p then return p end
    end
    return ns.AHPrice(r.id)
end
-- average value of one disenchant (AH price of each result, else its vendor price, times its odds) and whether every result was priced
local function Expected(outs)
    local ev, all = 0, #outs > 0
    for _, o in ipairs(outs) do
        o.vendor = ns.ItemSell(o.id)
        o.best = o.price or o.vendor
        if o.best then o.val = o.p / 100 * o.best; ev = ev + o.val else all = false end
    end
    return ev, all
end
-- value of disenchanting an item of quality q / item level ilvl: average copper, all results priced
function ns.DisenchantValue(q, ilvl) return Expected(ns.DisenchantOutcomes(q, ilvl)) end

table.insert(ns.tabs, { name = TAB, nobar = true, shown = ns.KnowsDisenchant, build = function(page)
    local showIgnored, btn, paint, sel, P
    local cols = {
        { title = "Item", width = 300, value = function(r) return r.name end,
          text = function(r) local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.q]; return c and c.hex and c.hex .. r.name .. "|r" or r.name end,
          icons = function(r) return { r.icon } end, nameTip = true,
          tag = function(r) return ns.db.deIgnore[r.id] and "ignored" or nil end },
        { title = "iLvl", width = 60, right = true, desc = true, value = function(r) return r.ilvl end },
        { title = "Bound", width = 70, value = function(r) return r.bound and "yes" or "no" end },
        { title = "Disenchant", width = 110, right = true, desc = true, value = function(r) return r.ev end,
          text = function(r) return ns.Money(r.ev and math.floor(r.ev), r.evAll and nil or "|cffff9900") end },
        { title = "Vendor", width = 110, right = true, desc = true, value = function(r) return r.vendor end, text = function(r) return ns.Money(r.vendor) end },
        { title = "Auction", width = 110, right = true, desc = true, value = function(r) return r.ah end, text = function(r) return ns.Money(r.ah) end },
    }
    local function Tip(r)
        if r.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(r.link) elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.id) end
        GameTooltip:AddLine("Click: show what it disenchants into; right-click: " .. (ns.db.deIgnore[r.id] and "stop ignoring" or "ignore"), 0.6, 0.6, 0.6)
    end
    local t
    local function IsSel(r) return sel and r.bag == sel.bag and r.slot == sel.slot and r.id == sel.id end
    local function Next()    -- the selected item, else the first listed one not ignored (the table's order)
        for _, r in ipairs(t.sorted()) do if IsSel(r) and not ns.db.deIgnore[r.id] then return r end end
        for _, r in ipairs(t.sorted()) do if not ns.db.deIgnore[r.id] then return r end end
    end
    -- point the secure button at the next item (out of combat only: attributes are protected)
    local function Arm()
        if InCombatLockdown and InCombatLockdown() then return end
        local r = Next()
        btn.item = r
        btn:SetAttribute("type", r and "spell" or nil)
        btn:SetAttribute("spell", r and SpellName() or nil)
        btn:SetAttribute("target-bag", r and r.bag or nil)
        btn:SetAttribute("target-slot", r and r.slot or nil)
        btn:SetText(r and "Disenchant" or "Nothing to disenchant")
        btn:SetEnabled(r ~= nil); if paint then paint() end
        t:Redraw()
    end
    local Refresh
    t = ns.Table(page, cols, 29, Tip, 1, false, {
        item = function(r) return r.id end,
        dim = function(r) return ns.db.deIgnore[r.id] end,
        selected = function(r) return btn and btn.item == r end,
        expand = function(r) return IsSel(r) and P or nil end,
        click = function(r, b)
            if b == "RightButton" then ns.db.deIgnore[r.id] = not ns.db.deIgnore[r.id] or nil
            else sel = not IsSel(r) and { bag = r.bag, slot = r.slot, id = r.id } or nil end
            Refresh()
        end })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t

    -- the selected item's panel, opened under its row (like a recipe's): one line per result, aligned with the table's columns
    P = CreateFrame("Frame", nil, t)
    P:SetWidth(t.width - 14); P:Hide()
    local bg = P:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    for _, a in ipairs({ "TOP", "BOTTOM" }) do
        local ln = P:CreateTexture(nil, "ARTWORK"); ln:SetHeight(1); ln:SetColorTexture(0.8, 0.64, 0.36, 0.5)
        ln:SetPoint(a .. "LEFT"); ln:SetPoint(a .. "RIGHT")
    end
    local cx, LH = t.colX, 18
    local function FS(parent, x, w, font, right, y)
        local f = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
        f:SetSize(w - 8, LH); f:SetPoint("TOPLEFT", P, "TOPLEFT", x + 4, y); f:SetJustifyH(right and "RIGHT" or "LEFT"); f:SetWordWrap(false)
        return f
    end
    local heads = { "Disenchants into", "Chance", "Seen", "Value", "Vendor", "Auction" }
    for k, h in ipairs(heads) do
        local f = FS(P, cx[k] + (k == 1 and 24 or 0), cols[k].width - (k == 1 and 24 or 0), "GameFontDisableSmall", k > 1, -4)
        f:SetText(h)
    end
    local lines = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, P)
        b:SetSize((t.width - 14), LH); b:SetPoint("TOPLEFT", 0, -4 - i * LH)
        b:SetHighlightTexture(HIGHLIGHT or "Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 8, 0)
        local function F(k, left) local f = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            f:SetSize(cols[k].width - 8 - (left or 0), LH); f:SetPoint("LEFT", cx[k] + 4 + (left or 0), 0)
            f:SetJustifyH(k > 1 and "RIGHT" or "LEFT"); f:SetWordWrap(false); return f end
        b.f = { F(1, 24), F(2), F(3), F(4), F(5), F(6) }
        b:SetScript("OnEnter", function(self)
            if self.id and GameTooltip.SetItemByID then ns.TipOwner(self); GameTooltip:SetItemByID(self.id); GameTooltip:Show() end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lines[i] = b
    end
    local foot = FS(P, 0, (t.width - 14) - 8, "GameFontHighlightSmall", false, 0)
    foot:SetWidth((t.width - 14) - 16)
    page.panel = P

    local function Panel(r)
        if not r then P:Hide(); return end
        local outs = r.outs
        for i, b in ipairs(lines) do
            local o = outs[i]
            b:SetShown(o ~= nil)
            if o then
                b.id = o.id
                b.icon:SetTexture(ns.ItemIcon(o.id))
                local f = b.f
                f[1]:SetText((ns.ItemColor(o.id) or "") .. ns.ItemName(o.id) .. "|r")
                f[2]:SetText(o.pct and ("%d%%"):format(o.pct) or "?")
                f[3]:SetText(o.n > 0 and ("%d/%d"):format(o.c, o.n) or "-")
                f[4]:SetText(ns.Money(o.val and math.floor(o.val)))
                f[5]:SetText(ns.Money(o.vendor)); f[6]:SetText(ns.Money(o.price))
            end
        end
        local n = math.min(#outs, #lines)
        local n0 = outs[1] and outs[1].n or 0
        foot:ClearAllPoints(); foot:SetPoint("TOPLEFT", P, "TOPLEFT", 8, -4 - (n + 1) * LH - 2)
        foot:SetText(n == 0 and "No known results for this item."
            or ("Average %s per disenchant%s  |cff808080(%s)|r"):format(ns.Money(math.floor(r.ev or 0)), r.evAll and "" or " |cffff9900+ unpriced results|r",
                n0 >= OBS_MIN and ("odds from your " .. n0 .. " disenchants") or "table odds are approximate; yours are recorded as you disenchant"))
        P:SetHeight(4 + (n + 1) * LH + 24)
    end

    -- the journal-look button, secure: the click itself casts (LeftButton only; key-down CVar decides the edge)
    btn = CreateFrame("Button", "DoudProfessionsDisenchantButton", UIParent, "SecureActionButtonTemplate")
    btn:SetSize(220, 26); btn:SetFrameStrata("HIGH"); btn:Hide()   -- HIGH: stays above the (toplevel, MEDIUM) window
    local function Place()   -- out of combat only: the button is protected
        if InCombatLockdown and InCombatLockdown() then return end
        btn:ClearAllPoints()
        if page:IsVisible() then btn:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, -8); btn:Show() else btn:Hide() end
    end
    page:HookScript("OnShow", Place); page:HookScript("OnHide", Place)
    ns.On("PLAYER_REGEN_ENABLED", Place)
    ns.On("PLAYER_REGEN_DISABLED", function() btn:Hide(); btn:ClearAllPoints() end)   -- fires before the lockdown
    if btn.RegisterForClicks then btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown") end
    paint = FT.SkinButton and FT.SkinButton(btn)
    btn:HookScript("OnEnter", function(self)
        if not self.item then return end
        ns.TipOwner(self); GameTooltip:SetText("Disenchant " .. self.item.name); GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    btn:HookScript("PreClick", function(self)
        local r = self.item
        pending = r and { key = Bracket(r.q, r.ilvl) } or nil
    end)
    page.button = btn

    -- checkboxes left to right on the top line (anchor: the previous label; none = the page's corner)
    local function Check(label, anchor, get, set)
        local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        if anchor then cb:SetPoint("LEFT", anchor, "RIGHT", 12, -1) else cb:SetPoint("TOPLEFT", 6, -10) end
        cb:SetChecked(get() and true or false)
        cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or nil); page.Refresh() end)
        local l = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", cb, "RIGHT", 0, 1); l:SetText(label)
        return cb, l
    end
    local l
    page.boundBox, l = Check("Soulbound only", nil, function() return ns.db.deBound end, function(v) ns.db.deBound = v end)
    page.ignoredBox, l = Check("Show ignored", l, function() return showIgnored end, function(v) showIgnored = v end)
    page.autoBox = Check("Open with Enchanting", l, function() return ns.db.deAuto end, function(v) ns.db.deAuto = v end)

    Refresh = function()
        local list, selRow = {}, nil
        for _, r in ipairs(ns.DisenchantItems()) do
            if showIgnored or not ns.db.deIgnore[r.id] then
                r.outs = ns.DisenchantOutcomes(r.q, r.ilvl)
                r.ev, r.evAll = Expected(r.outs)
                r.vendor, r.ah = ns.ItemSell(r.id), ItemAH(r)
                list[#list + 1] = r
                if IsSel(r) then selRow = r end
            end
        end
        if not selRow then sel = nil end
        Panel(selRow)
        t:SetRows(list)
        Arm()
    end
    page.Refresh = Refresh
    page.Arm = Arm
    -- bags change (an item disenchanted, looted, moved) -> list again; combat over -> arm what changed meanwhile; item data
    -- arriving (names, prices, qualities of items not cached at the first open) -> list again, batched
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do
        ns.On(e, function() if page:IsVisible() then Refresh() end end)
    end
    local queued
    ns.On("GET_ITEM_INFO_RECEIVED", function()
        if queued or not page:IsVisible() then return end
        queued = true
        C_Timer.After(0.3, function() queued = nil; if page:IsVisible() then Refresh() end end)
    end)
end })

-- "Open with Enchanting": the Enchanting window brings this tab up beside it
ns.On("TRADE_SKILL_SHOW", function()
    local T = C_TradeSkillUI
    if not (ns.db.deAuto and ns.KnowsDisenchant() and T and T.GetBaseProfessionInfo) then return end
    local ok, base = pcall(T.GetBaseProfessionInfo)
    local pid = ok and base and base.professionID
    if pid and (ns.SkillParent[pid] or pid) == ENCHANTING then ns.Open(TAB) end
end)

end)
