-- Auctionator's "To Craft / Profit" under a recipe (Professions window): its Profit line is swapped for what the crafted
-- item fetches at a vendor, on the AH (after the 5% cut) and disenchanted (Disenchant.lua odds), each with its gain / loss
-- against the craft cost. Enchants (no output item) keep Auctionator's own Profit line.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local SKIP = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true }

local function Line(label, v, cost, col)
    if not v then return label .. " " .. ns.Money(nil) end
    local d = math.floor(v - cost + 0.5)
    return label .. " " .. ns.Money(v, col or "|cffffffff") .. "  (" .. (d >= 0 and "|cff40ff40+|r" .. ns.Money(d, "|cff40ff40") or ns.Money(d, "|cffff4040")) .. ")"
end

-- the three lines for this recipe, nil for enchants / anything without an output item
function ns.CraftValueLines(form)
    local ci, api = Auctionator.CraftingInfo, Auctionator.API.v1
    local info = form:GetRecipeInfo()
    if not info or info.isEnchantingRecipe then return end
    local tx = form:GetTransaction()
    local out = C_TradeSkillUI.GetRecipeOutputItemData(info.recipeID, tx:CreateCraftingReagentInfoTbl(), tx:GetAllocationItemGUID())
    local link = out and out.hyperlink
    if not link then return end
    local _, _, q, ilvl, _, _, _, _, loc, _, sell, class = C_Item.GetItemInfo(link)
    local id = out.itemID or C_Item.GetItemInfoInstant(link)
    local count = form.recipeSchematic and form.recipeSchematic.quantityMin or 1
    local cost = ci.CalculateCraftCost(C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false, form:GetCurrentRecipeLevel()), tx)
    local ah = api.GetAuctionPriceByItemLink(AUCTIONATOR_L_REAGENT_SEARCH, link)
    sell = sell or ns.ItemSell(id)
    local t = {
        Line("Vendor:", sell and sell * count, cost),
        Line("Auction:", ah and ah * count * Auctionator.Constants.AfterAHCut, cost),
    }
    if q and q >= 2 and q <= 4 and (class == 2 or class == 4) and not SKIP[loc or ""] then
        local de, all = ns.DisenchantValue(q, ilvl)
        t[3] = Line("Disenchant:", de * count, cost, not all and "|cffff9900" or nil)   -- orange = some result unpriced
    end
    return t
end

local function Hook()
    local ci = Auctionator and Auctionator.CraftingInfo
    if not (ci and ci.GetInfoText and ci.CalculateCraftCost) or ci.doudValues then return end
    ci.doudValues = true
    local orig = ci.GetInfoText
    ci.GetInfoText = function(form, showProfit, ...)
        local text, lines = orig(form, showProfit, ...)
        local ok, extra = pcall(ns.CraftValueLines, form)
        if not (showProfit and ok and extra) then return text, lines end
        local keep = {}
        for l in (text .. "\n"):gmatch("(.-)\n") do
            if l ~= "" and not l:find(AUCTIONATOR_L_PROFIT_COLON, 1, true) then keep[#keep + 1] = l end
        end
        for _, l in ipairs(extra) do keep[#keep + 1] = l end
        return table.concat(keep, "\n"), #keep
    end
end
ns.On("PLAYER_LOGIN", Hook)
ns.On("TRADE_SKILL_SHOW", Hook)

end)
