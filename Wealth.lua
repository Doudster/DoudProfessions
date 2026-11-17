-- Wealth tab: each character's gold, recorded per day (the last amount seen that day, ~30 days kept), with the account total.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local function Today(offset) return date("%Y-%m-%d", time() - (offset or 0) * 86400) end

local function Record()
    local c = ns.Char()
    c.money = c.money or {}
    c.money[Today()] = GetMoney()
    -- the 7 / 30-day changes read back at most to the newest day >= 30 days old: older ones dropped
    local _, cut = ns.GoldOn(c, Today(30))
    if cut then for d in pairs(c.money) do if d < cut then c.money[d] = nil end end end
end
ns.On("PLAYER_ENTERING_WORLD", Record)
ns.On("PLAYER_MONEY", Record)

-- gold on the last recorded day <= day (default: latest), and that day
function ns.GoldOn(c, day)
    local best
    for d in pairs(c.money or {}) do
        if (not day or d <= day) and (not best or d > best) then best = d end
    end
    return best and c.money[best], best
end

table.insert(ns.tabs, { name = "Wealth", build = function(page)
    local cols = {
        { title = "Character", width = 240, value = function(r) return r.key end, text = function(r) return ns.CharName(r.key, r.c) end },
        { title = "Gold", width = 180, right = true, desc = true, value = function(r) return r.now end, text = function(r) return ns.Money(r.now) end },
        { title = "Change (7 days)", width = 180, right = true, desc = true, value = function(r) return r.week end, text = function(r) return ns.Money(r.week) end },
        { title = "Change (30 days)", width = 180, right = true, desc = true, value = function(r) return r.month end, text = function(r) return ns.Money(r.month) end },
        { title = "Last seen", width = 140, desc = true, value = function(r) return r.day end },
    }
    local total = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    total:SetPoint("TOPLEFT", 8, -10)
    local t = ns.Table(page, cols, 29, nil, 2, true, { click = ns.DeleteClick(page,
        function(r) return "the gold history of " .. ns.CharName(r.key, r.c) end, function(r) r.c.money = nil end) })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t
    page.Refresh = function()
        local list, sum, week, month = {}, 0, 0, 0
        for key, c in pairs(ns.db.chars) do
            local now, day = ns.GoldOn(c)
            if now then
                local w, m = ns.GoldOn(c, Today(7)), ns.GoldOn(c, Today(30))
                list[#list + 1] = { key = key, c = c, now = now, day = day, week = w and now - w, month = m and now - m }
                sum, week, month = sum + now, week + (w and now - w or 0), month + (m and now - m or 0)
            end
        end
        t:SetRows(list)
        total:SetText(("Account total: %s   |cffffffff7 days:|r %s   |cffffffff30 days:|r %s")
            :format(ns.Money(sum), ns.Money(week), ns.Money(month)))
    end
end })

end)
