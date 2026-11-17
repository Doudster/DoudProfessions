-- Vendor tab (Journalator's "Vendoring"): merchant purchases, buybacks and repair-all costs, logged by hooking the globals
-- (so Doud UI's own auto repair / buy stacks and other addons count). Merchant info is read in the post-hook: the merchant
-- list still holds the item then. Extended-cost items (currencies) are logged at cost 0 with a note. A repair-all hook runs
-- after the call, so the cost is the live GetRepairAllCost (the server has not answered yet) or the last snapshot taken at
-- MERCHANT_SHOW / durability updates. Cursor repairs of single items are not logged. Capped at CAP entries, oldest dropped.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local CAP = 2000
local repairSnap = 0

local function Log(kind, link, count, cost, note)
    local v = ns.db.vendor
    table.insert(v, { t = time(), char = ns.CharKey(), kind = kind, item = link, count = count, cost = cost,
        vendor = UnitName and UnitName("npc") or nil, note = note })
    while #v > CAP do table.remove(v, 1) end
end

if hooksecurefunc and BuyMerchantItem then
    hooksecurefunc("BuyMerchantItem", function(index, qty)
        -- the C_MerchantFrame table form is what this client has (General's merchant code, verified in game)
        local name, price, lot, extended
        local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(index)
        if info then
            name, price, lot, extended = info.name, info.price, info.stackCount, info.hasExtendedCost
        elseif GetMerchantItemInfo then
            local _
            name, _, price, lot, _, _, extended = GetMerchantItemInfo(index)
        end
        if not name then return end
        lot = (lot and lot > 0) and lot or 1
        local link = GetMerchantItemLink and GetMerchantItemLink(index) or name
        local lots = (qty or lot) / lot   -- no quantity = one lot
        Log("buy", link, qty or lot, extended and 0 or math.floor((price or 0) * lots + 0.5), extended and "extended cost" or nil)
    end)
end
if hooksecurefunc and BuybackItem then
    hooksecurefunc("BuybackItem", function(index)
        if not GetBuybackItemInfo then return end
        local name, _, price, count = GetBuybackItemInfo(index)
        if name then Log("buyback", GetBuybackItemLink and GetBuybackItemLink(index) or name, count or 1, price or 0) end
    end)
end
if hooksecurefunc and RepairAllItems then
    hooksecurefunc("RepairAllItems", function(guild)
        local cost = GetRepairAllCost and GetRepairAllCost() or 0
        if cost <= 0 then cost = repairSnap end
        if cost > 0 then Log("repair", "Repair all", 1, cost, guild and "guild funds" or nil) end
    end)
end
local function Snap() if GetRepairAllCost then repairSnap = GetRepairAllCost() or 0 end end
ns.On("MERCHANT_SHOW", Snap)
ns.On("UPDATE_INVENTORY_DURABILITY", Snap)

table.insert(ns.tabs, { name = "Vendor", build = function(page)
    local cols = {
        { title = "Date", width = 144, desc = true, value = function(r) return r.t end, text = function(r) return date("%Y-%m-%d %H:%M", r.t) end },
        { title = "Character", width = 130, value = function(r) return r.char end, text = function(r) return ns.CharName(r.char, ns.db.chars[r.char]) end },
        { title = "Type", width = 70, value = function(r) return r.kind end },
        { title = "Item", width = 240, value = function(r) return r.item end,
          text = function(r) return r.note and (r.item .. " |cff808080(" .. r.note .. ")|r") or r.item end },
        { title = "Qty", width = 50, right = true, desc = true, value = function(r) return r.count end },
        { title = "Cost", width = 150, right = true, desc = true, value = function(r) return r.cost end, text = function(r) return ns.Money(r.cost) end },
        { title = "Vendor", width = 130, value = function(r) return r.vendor or "" end },
    }
    local total = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    total:SetPoint("TOPLEFT", 8, -12)
    local t = ns.Table(page, cols, 29, nil, 1, true, { click = ns.DeleteClick(page,
        function(r) return r.kind .. " " .. r.item end, function(r) ns.Remove(ns.db.vendor, r) end) })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t
    page.Refresh = function()
        local month, items, repairs, mItems, mRepairs = date("%Y-%m"), 0, 0, 0, 0
        for _, r in ipairs(ns.db.vendor) do
            local c, m = r.cost or 0, date("%Y-%m", r.t) == month
            if r.kind == "repair" then repairs = repairs + c; if m then mRepairs = mRepairs + c end
            else items = items + c; if m then mItems = mItems + c end end
        end
        t:SetRows(ns.db.vendor)
        total:SetText(("Items %s (month %s)    Repairs %s (month %s)"):format(ns.Money(items), ns.Money(mItems), ns.Money(repairs), ns.Money(mRepairs)))
    end
end })

end)
