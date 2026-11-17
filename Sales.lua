-- Sales/Buys tab: auction house sales and purchases, logged from the auction mails as they are taken
-- ("Auction successful: X" pays the sale, "Auction won: X" delivers the buy). Taking the money or item deletes the
-- mail, so each is logged once; the invoice (GetInboxInvoiceInfo) gives item, count and price, the subject is the
-- fallback (no price for a buy then). Hooks the globals, so Blizzard's "Open All" and mail addons calling them count.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local function Pattern(fmt, fallback)
    return "^" .. (fmt or fallback):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
end
local SOLD = Pattern(AUCTION_SOLD_MAIL_SUBJECT, "Auction successful: %s")
local WON = Pattern(AUCTION_WON_MAIL_SUBJECT, "Auction won: %s")
local seen = {}   -- this session's logged mails (Open All may call two of our hooks on one mail)
local CAP = 2000   -- ns.db.sales entries kept, oldest dropped (as Vendor.lua)

function ns.LogMail(i)
    if not GetInboxHeaderInfo then return end
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
    if not subject then return end
    local key = subject .. ":" .. (money or 0) .. ":" .. math.floor((daysLeft or 0) * 1440)
    if seen[key] then return end
    local kind, item, count, price
    local inv, itemName, _, bid, _, _, _, _, _, _, n = GetInboxInvoiceInfo(i)
    if inv == "seller" or inv == "buyer" then
        kind, item, count, price = inv == "seller" and "Sold" or "Bought", itemName, n, bid
    elseif subject:match(SOLD) then
        kind, item, price = "Sold", subject:match(SOLD), money
    elseif subject:match(WON) then
        kind, item = "Bought", subject:match(WON)
    else
        return
    end
    seen[key] = true
    table.insert(ns.db.sales, { t = time(), char = ns.CharKey(), kind = kind, item = item, count = count or 1,
        money = price, net = kind == "Sold" and money or nil })
    while #ns.db.sales > CAP do table.remove(ns.db.sales, 1) end
end
for _, fn in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem" }) do
    if _G[fn] then hooksecurefunc(fn, function(i) ns.LogMail(i) end) end
end

table.insert(ns.tabs, { name = "Sales / Buys", build = function(page)
    local cols = {
        { title = "Date", width = 144, desc = true, value = function(r) return r.t end, text = function(r) return date("%Y-%m-%d %H:%M", r.t) end },
        { title = "Character", width = 150, value = function(r) return r.char end, text = function(r) return ns.CharName(r.char, ns.db.chars[r.char]) end },
        { title = "Type", width = 80, value = function(r) return r.kind end,
          text = function(r) return r.kind == "Sold" and "|cff40ff40Sold|r" or "|cffff8040Bought|r" end },
        { title = "Item", width = 220, value = function(r) return r.item end },
        { title = "Qty", width = 60, right = true, desc = true, value = function(r) return r.count end },
        { title = "Price", width = 150, right = true, desc = true, value = function(r) return r.money end, text = function(r) return ns.Money(r.money) end },
        { title = "Received", width = 150, right = true, desc = true, value = function(r) return r.net end,
          text = function(r) return r.net and ns.Money(r.net) or "" end },
    }
    local total = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    total:SetPoint("TOPLEFT", 8, -12)
    local t = ns.Table(page, cols, 29, nil, 1, true, { click = ns.DeleteClick(page,
        function(r) return r.kind:lower() .. " " .. r.item end, function(r) ns.Remove(ns.db.sales, r) end) })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t
    page.Refresh = function()
        local sold, bought, ns1, nb = 0, 0, 0, 0
        for _, r in ipairs(ns.db.sales) do
            if r.kind == "Sold" then sold, ns1 = sold + (r.net or r.money or 0), ns1 + 1
            else bought, nb = bought + (r.money or 0), nb + 1 end
        end
        t:SetRows(ns.db.sales)
        total:SetText(("Sold %d: %s received    Bought %d: %s spent    |cff808080(logged when you take the auction mail)|r")
            :format(ns1, ns.Money(sold), nb, ns.Money(bought)))
    end
end })

end)
