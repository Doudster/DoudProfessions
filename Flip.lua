-- Flip tab: items whose AH price (Auctionator's scan database: the lowest buyout per unit last seen) is under what a vendor
-- pays for them (buy, sell to a vendor) or under their average disenchant value (gear, Disenchant.lua: AH price of each
-- result, else vendor; orange = some result unpriced). Each item shows its better use. Prices are from the last scan, so the
-- auction may be gone. Gear keys ("g:id:ilvl") count by item ID, the cheapest kept; pets ("p:") skipped. Items not cached
-- yet are asked for and show up once loaded.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local SKIP = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true }
-- id -> { q, ilvl } for disenchantable gear, false otherwise. Cached for the session (like ns.ItemSell): re-asking evicts items
-- from the client's small cache and loops
local gear = {}
local function Gear(id)
    if gear[id] ~= nil then return gear[id] end
    local ok, _, _, q, ilvl, _, _, _, _, loc, _, _, class = pcall(C_Item and C_Item.GetItemInfo or GetItemInfo, id)
    if not (ok and q) then return end     -- not loaded yet
    gear[id] = q >= 2 and q <= 4 and (class == 2 or class == 4) and not SKIP[loc or ""] and { q = q, ilvl = ilvl } or false
    return gear[id]
end
ns.flipGear = gear   -- tests swap item info mocks

-- { id, ah, kind ("Vendor" / "Disenchant"), value, all (every DE result priced), profit } per item worth flipping
function ns.FlipItems()
    local db = Auctionator and Auctionator.Database and Auctionator.Database.db
    local best, list, de = {}, {}, {}
    for key, d in pairs(type(db) == "table" and db or {}) do
        local id = tonumber(key) or tonumber(tostring(key):match("^gr?:(%d+)"))
        local m = type(d) == "table" and d.m
        if id and m and m > 0 and (not best[id] or m < best[id]) then best[id] = m end
    end
    for id, ah in pairs(best) do
        local r = { id = id, ah = ah, kind = "Vendor", value = ns.ItemSell(id) or 0, all = true }
        local g = Gear(id)
        if g then
            local k = g.q .. ":" .. (g.ilvl or 0)    -- one DE value per quality / item level per refresh
            de[k] = de[k] or { ns.DisenchantValue(g.q, g.ilvl) }
            if de[k][1] > r.value then r.kind, r.value, r.all = "Disenchant", math.floor(de[k][1]), de[k][2] end
        end
        if r.value > ah then r.profit = r.value - ah; list[#list + 1] = r end
    end
    return list
end

table.insert(ns.tabs, { name = "Flip", build = function(page)
    local function M(k) return function(r) return ns.Money(r[k]) end end
    local function V(k) return function(r) return r[k] end end
    local cols = {
        { title = "Item", width = 340, value = function(r) return ns.ItemName(r.id) end,
          text = function(r) local c, n = ns.ItemColor(r.id), ns.ItemName(r.id); return c and c .. n .. "|r" or n end,
          icons = function(r) return { ns.ItemIcon(r.id) } end, nameTip = true },
        { title = "AH price", width = 140, right = true, desc = true, value = V("ah"), text = M("ah") },
        { title = "Use", width = 110, value = V("kind") },
        { title = "Value", width = 140, right = true, desc = true, value = V("value"),
          text = function(r) return ns.Money(r.value, not r.all and "|cffff9900" or nil) end },
        { title = "Profit", width = 140, right = true, desc = true, value = V("profit"), text = M("profit") },
    }
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 8, -12)
    local t = ns.Table(page, cols, 29, function(r)
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.id) end
    end, 5, true, { item = function(r) return r.id end })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t
    page.Refresh = function()
        local list = ns.FlipItems()
        t:SetRows(list)
        note:SetText(Auctionator and Auctionator.Database
            and ("%d items on the AH under their vendor or disenchant value, from Auctionator's last scan. |cff808080(scan again to check they're still up)|r"):format(#list)
            or "|cffff6060Auctionator not loaded: no AH prices.|r")
    end
    local queued    -- item info arriving in bursts: one refresh a second
    ns.On("GET_ITEM_INFO_RECEIVED", function(_, ok)
        if not ok or queued or not page:IsVisible() then return end   -- failed loads (removed items) would retry forever
        queued = true
        C_Timer.After(1, function() queued = false; if page:IsVisible() then page.Refresh() end end)
    end)
end })

end)
