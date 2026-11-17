-- Item stats tab (Journalator_Statistics' idea): the Sales / Buys log (ns.db.sales) summed per item: units sold and bought,
-- mean unit prices, the last sale's unit price and date, the money received. Nothing new is recorded.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

-- one record per item name: sold / bought units and money, last sale { unit, t }
function ns.ItemStats()
    local by, list = {}, {}
    for _, r in ipairs(ns.db.sales) do
        local s = by[r.item]
        if not s then s = { item = r.item, sold = 0, soldM = 0, net = 0, bought = 0, boughtM = 0 }; by[r.item] = s; list[#list + 1] = s end
        local n = r.count or 1
        if r.kind == "Sold" then
            s.sold, s.soldM, s.net = s.sold + n, s.soldM + (r.money or 0), s.net + (r.net or 0)
            if r.money and (not s.lastT or r.t >= s.lastT) then s.last, s.lastT = r.money / n, r.t end
        elseif r.money then    -- a buy logged from the subject alone has no price: left out of the mean
            s.bought, s.boughtM = s.bought + n, s.boughtM + r.money
        end
    end
    for _, s in ipairs(list) do
        s.meanSold = s.sold > 0 and s.soldM / s.sold or nil
        s.meanBought = s.bought > 0 and s.boughtM / s.bought or nil
    end
    return list
end

table.insert(ns.tabs, { name = "Item stats", build = function(page)
    local function M(k) return function(r) return ns.Money(r[k]) end end
    local function V(k) return function(r) return r[k] end end
    local cols = {
        { title = "Item", width = 220, value = V("item") },
        { title = "Sold", width = 60, right = true, desc = true, value = V("sold") },
        { title = "Mean sold", width = 120, right = true, desc = true, value = V("meanSold"), text = M("meanSold") },
        { title = "Last sold", width = 120, right = true, desc = true, value = V("last"), text = M("last") },
        { title = "On", width = 96, desc = true, value = V("lastT"), text = function(r) return r.lastT and date("%Y-%m-%d", r.lastT) or "" end },
        { title = "Received", width = 120, right = true, desc = true, value = V("net"), text = M("net") },
        { title = "Bought", width = 60, right = true, desc = true, value = V("bought") },
        { title = "Mean paid", width = 120, right = true, desc = true, value = V("meanBought"), text = M("meanBought") },
    }
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 8, -12)
    note:SetText("Per unit, from the Sales / Buys log. |cff808080(no sale rate: expired auctions are not logged)  Right-click: delete.|r")
    local t = ns.Table(page, cols, 29, nil, 6, true, { click = ns.DeleteClick(page,
        function(r) return "every sale and buy of " .. r.item end,
        function(r) for i = #ns.db.sales, 1, -1 do if ns.db.sales[i].item == r.item then table.remove(ns.db.sales, i) end end end) })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t
    page.Refresh = function() t:SetRows(ns.ItemStats()) end
end })

end)
