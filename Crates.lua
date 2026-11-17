-- Crates tab: which Waylaid Crate gets Merchant's Favor cheapest. Per crate: its AH price + the cheapest of the material
-- bundles its quest accepts (vendor or AH unit price x count) - the gold the hand-in pays back = total, then total / Favor.
-- Prices from Auctionator. Favor and gold back per family / crate quality (1 white = raw materials, 2 green = refined) as
-- seen in game on Forever 1.60.1. Idea from WaylaidCost (Shakam, no license): own code, crate data read from the client's
-- ItemSparse (ids/quality) + the quest requirements. Writs not covered.
-- "Mats in bags first" (ProfessionsDB.crateBags): materials in your bags are free (a part-filled bundle costs only what's
-- missing), crates with a full bundle in bags sort first. List tooltips follow the cursor (styled by PrettyTooltip if loaded).
-- Hover a row, or any crate item (bags, AH...), for every bundle's cost and cost per Favor (the item tooltip leaves the
-- crate's price out: you hold it). Click a row with the AH open: Auctionator shopping list "Doud: <crate>" (crate + the
-- cheapest bundle's missing count), searched right away; does nothing with the AH closed. Shift+click: link the crate in chat.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local FAVOR = { Apprentice = { 5, 10 }, Journeyman = { 10, 20 }, Expert = { 15, 30 }, Artisan = { 20, 40 } }
local BACK = { Apprentice = { 250, 500 }, Journeyman = { 500, 1000 }, Expert = { 750, 1500 }, Artisan = { 1000, 2000 } }
-- { crate itemID, family, quality, { { material itemID, count }, ... } }
ns.CRATES = {
    { 248702, "Apprentice", 2, { { 4231, 2 }, { 2996, 20 } } },  -- Apprentice Fabrics
    { 248703, "Apprentice", 2, { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },  -- Apprentice Ingots
    { 248704, "Apprentice", 2, { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },  -- Apprentice Parts
    { 248685, "Apprentice", 1, { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },  -- Apprentice Curiosities
    { 248682, "Apprentice", 1, { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },  -- Apprentice Herbs
    { 248683, "Apprentice", 1, { { 2770, 20 }, { 2771, 20 } } },  -- Apprentice Ore
    { 248684, "Apprentice", 1, { { 2589, 40 }, { 2318, 20 } } },  -- Apprentice Textiles
    { 248705, "Journeyman", 2, { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },  -- Journeyman Fabrics
    { 248706, "Journeyman", 2, { { 2842, 10 }, { 3575, 20 } } },  -- Journeyman Ingots
    { 248707, "Journeyman", 2, { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } },  -- Journeyman Parts
    { 248689, "Journeyman", 1, { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },  -- Journeyman Curiosities
    { 248686, "Journeyman", 1, { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } },  -- Journeyman Herbs
    { 248687, "Journeyman", 1, { { 2775, 10 }, { 2772, 20 } } },  -- Journeyman Ore
    { 248688, "Journeyman", 1, { { 2592, 20 }, { 4306, 40 }, { 2319, 20 } } },  -- Journeyman Textiles
    { 248708, "Expert", 2, { { 4339, 8 }, { 4236, 2 } } },  -- Expert Fabrics
    { 248709, "Expert", 2, { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } },  -- Expert Ingots
    { 248710, "Expert", 2, { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } },  -- Expert Parts
    { 248694, "Expert", 1, { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },  -- Expert Curiosities
    { 248690, "Expert", 1, { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } },  -- Earthly Expert Herbs
    { 248691, "Expert", 1, { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } },  -- Flowering Expert Herbs
    { 248692, "Expert", 1, { { 2776, 10 }, { 3858, 20 } } },  -- Expert Ore
    { 248693, "Expert", 1, { { 4338, 40 }, { 4234, 20 } } },  -- Expert Textiles
    { 248711, "Artisan", 2, { { 14048, 8 }, { 8172, 2 } } },  -- Artisan Fabrics
    { 248712, "Artisan", 2, { { 11371, 2 }, { 6037, 10 }, { 12359, 20 } } },  -- Artisan Ingots
    { 248713, "Artisan", 2, { { 15994, 5 }, { 18631, 5 }, { 16000, 2 } } },  -- Artisan Parts
    { 248699, "Artisan", 1, { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } },  -- Artisan Curiosities
    { 248695, "Artisan", 1, { { 13464, 10 }, { 8838, 20 }, { 8839, 10 }, { 8845, 10 }, { 8846, 10 } } },  -- Earthly Artisan Herbs
    { 248696, "Artisan", 1, { { 13463, 20 }, { 13465, 20 }, { 13466, 20 }, { 13467, 20 } } },  -- Flowering Artisan Herbs
    { 248697, "Artisan", 1, { { 7911, 10 }, { 10620, 20 }, { 11370, 20 } } },  -- Artisan Ore
    { 248698, "Artisan", 1, { { 14047, 40 }, { 4304, 20 }, { 8170, 20 } } },  -- Artisan Textiles
}

-- one crate's row: { id, favor, back, crate (AH price), opts = { { id, n, have (in bags, max n), cost, owned } } (cheapest
-- first, unpriced last), best (cheapest priced bundle), owned (a bundle is in your bags), total, per (copper per Favor) };
-- with bags, only the missing count is priced. nil prices stay nil
local function Have(id) local ok, n = pcall(GetItemCount, id); return ok and tonumber(n) or 0 end
local function Row(c, bags)
    local r = { id = c[1], favor = FAVOR[c[2]][c[3]], back = BACK[c[2]][c[3]], crate = ns.AHPrice(c[1]), opts = {} }
    for _, m in ipairs(c[4]) do
        local u, have = ns.ReagentPrice(m[1]), math.min(Have(m[1]), m[2])
        local owned, buy = have == m[2], bags and m[2] - have or m[2]
        r.owned = r.owned or owned
        r.opts[#r.opts + 1] = { id = m[1], n = m[2], have = have, owned = owned, cost = buy == 0 and 0 or u and u * buy }
    end
    table.sort(r.opts, function(a, b) return (a.cost or math.huge) < (b.cost or math.huge) end)
    r.best = r.opts[1].cost and r.opts[1]
    if r.crate and r.best then r.total = r.crate + r.best.cost - r.back; r.per = r.total / r.favor end
    return r
end
function ns.CrateRows(bags)
    local list = {}
    for _, c in ipairs(ns.CRATES) do list[#list + 1] = Row(c, bags) end
    return list
end
local function Item(id) local c, n = ns.ItemColor(id), ns.ItemName(id); return c and c .. n .. "|r" or n end

-- every bundle: "20 Tin Bar (in bags)"   "10 00 - 5 50 / Favor"; the cheapest (name and prices) in green. crate = the crate's own price (0 when held)
function ns.CrateTip(tip, r, crate)
    tip:AddLine(("%d Merchant's Favor, %s back on hand-in"):format(r.favor, ns.Money(r.back)), 1, 0.82, 0)
    for _, o in ipairs(r.opts) do
        local per = crate and o.cost and (crate + o.cost - r.back) / r.favor
        local g = o == r.best and "|cff40ff40" or nil
        tip:AddDoubleLine((g and "|cff40ff40> |r" or "   ") .. o.n .. " " .. (g and g .. ns.ItemName(o.id) .. "|r" or Item(o.id)) .. (o.owned and " |cff40c0ff(in bags)|r" or o.have > 0 and (" |cff40c0ff(%d in bags)|r"):format(o.have) or ""),
            ns.Money(o.cost, g) .. "  |cff808080-|r  " .. ns.Money(per, g) .. " |cff808080/ Favor|r", 1, 1, 1, 1, 1, 1)
    end
end

-- click: shopping list of the crate + what the cheapest bundle still needs, searched; nothing while the AH is closed
function ns.CrateShop(r)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.CreateShoppingList) then FT.Print("Auctionator not loaded") return end
    local want = { { r.id, 1 } }
    local need = r.best and r.best.n - Have(r.best.id) or 0
    if need > 0 then want[2] = { r.best.id, need } end
    local terms, strs = {}, {}
    for _, w in ipairs(want) do
        local nm = ns.ItemName(w[1])
        if nm == "item " .. w[1] then FT.Print("item names still loading, try again") return end
        terms[#terms + 1] = { searchString = nm, isExact = true, quantity = w[2] }
        strs[#strs + 1] = api.ConvertToSearchString("DoudUI", terms[#terms])
    end
    local name = "Doud: " .. ns.ItemName(r.id):gsub("^Waylaid Crate: ", "")
    local ok, err = pcall(api.CreateShoppingList, "DoudUI", name, strs)
    if not ok then FT.Print("shopping list failed: " .. tostring(err)) return end
    if api.MultiSearchAdvanced then pcall(api.MultiSearchAdvanced, "DoudUI", terms) end
end

-- crate item tooltips (bags, AH, links)
local byID = {}
for _, c in ipairs(ns.CRATES) do byID[c[1]] = c end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
        local c = data and byID[data.id]
        if c and ns.db then pcall(ns.CrateTip, tip, Row(c, ns.db.crateBags), 0) end
    end)
end

table.insert(ns.tabs, { name = "Crates", build = function(page)
    local function M(k) return function(r) return ns.Money(r[k]) end end
    local function V(k) return function(r) return r[k] end end
    local cols = {
        { title = "Crate", width = 270, value = function(r) return ns.ItemName(r.id) end,
          text = function(r) return (Item(r.id):gsub("Waylaid Crate: ", "")) end, icons = function(r) return { ns.ItemIcon(r.id) } end },
        { title = "Favor", width = 60, right = true, desc = true, value = V("favor") },
        { title = "Crate price", width = 120, right = true, value = V("crate"), text = M("crate") },
        { title = "Cheapest materials", width = 220, value = function(r) return r.best and r.best.cost end,
          text = function(r) return r.best and (r.best.n .. " " .. Item(r.best.id)) or "|cff808080no price|r" end,
          icons = function(r) return { r.best and ns.ItemIcon(r.best.id) } end,
          tag = function(r)
              local b = r.best
              return b and ns.db.crateBags and (b.owned and "in bags" or b.have > 0 and b.have .. "/" .. b.n) or nil
          end },
        { title = "Materials", width = 110, right = true, value = function(r) return r.best and r.best.cost end,
          text = function(r) return ns.Money(r.best and r.best.cost) end },
        { title = "Gold back", width = 90, right = true, value = V("back"), text = M("back") },
        { title = "Per Favor", width = 110, right = true, value = V("per"), text = M("per") },
    }
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("RIGHT", page, "TOPRIGHT", -10, -20)
    local t = ns.Table(page, cols, 29, nil, 7, false, {
        rowTip = function(r)
            GameTooltip:AddLine(Item(r.id))
            ns.CrateTip(GameTooltip, r, r.crate)
            GameTooltip:AddLine("Total = crate + materials - gold back", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Click (AH open): Auctionator shopping list + search. Shift+click: link in chat", 0.6, 0.6, 0.6)
        end,
        click = function(r, btn)
            if btn ~= "LeftButton" then return end
            if not IsShiftKeyDown() then ns.CrateShop(r) return end
            local ok, _, link = pcall(C_Item and C_Item.GetItemInfo or GetItemInfo, r.id)
            if ok and link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end,
        pin = function(r) return ns.db.crateBags and r.owned or nil end })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t
    local kb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    kb:SetSize(24, 24); kb:SetPoint("TOPLEFT", 6, -10); kb:SetChecked(ns.db.crateBags and true or false)
    kb:SetScript("OnClick", function(self) ns.db.crateBags = self:GetChecked() and true or nil; page.Refresh() end)
    local kl = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    kl:SetPoint("LEFT", kb, "RIGHT", 0, 1); kl:SetText("Mats in bags first (count as free)")
    page.bagsBox = kb
    page.Refresh = function()
        t:SetRows(ns.CrateRows(ns.db.crateBags))
        note:SetText(Auctionator and Auctionator.API and "Cheapest Waylaid Crates per Merchant's Favor. Prices from Auctionator."
            or "|cffff6060Auctionator not loaded: no AH prices.|r")
    end
    local queued    -- item names arriving in bursts / bags changing: one refresh a second
    local function Later()
        if queued or not page:IsVisible() then return end
        queued = true
        C_Timer.After(1, function() queued = false; if page:IsVisible() then page.Refresh() end end)
    end
    ns.On("GET_ITEM_INFO_RECEIVED", function(_, ok) if ok then Later() end end)
    ns.On("BAG_UPDATE_DELAYED", Later)
end })

end)
