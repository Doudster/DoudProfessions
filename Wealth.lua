-- Wealth tab: each character's gold, recorded per day (the last amount seen that day, ~30 days kept), with the account total
-- and a line graph of that total per day.
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
    local t = ns.Table(page, cols, 14, nil, 2, true, { click = ns.DeleteClick(page,
        function(r) return "the gold history of " .. ns.CharName(r.key, r.c) end, function(r) r.c.money = nil end) })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t

    -- account total per day over the kept ~30 days, each character counted at its last recorded amount
    local g = CreateFrame("Frame", nil, page)
    g:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 100, -24); g:SetPoint("BOTTOMRIGHT", -16, 28)
    local bg = g:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    local title = g:CreateFontString(nil, "ARTWORK", "GameFontNormal"); title:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 0, 4)
    title:SetText("Account total, last 30 days")
    local function Label(...) local fs = g:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); fs:SetPoint(...); return fs end
    local yTop, yBot = Label("TOPRIGHT", g, "TOPLEFT", -6, 0), Label("BOTTOMRIGHT", g, "BOTTOMLEFT", -6, 0)
    local xFirst, xLast = Label("TOPLEFT", g, "BOTTOMLEFT", 0, -4), Label("TOPRIGHT", g, "BOTTOMRIGHT", 0, -4)
    local lines = {}
    local function Graph()
        local pts = {}
        for i = 30, 0, -1 do
            local day, sum, any = Today(i), 0, false
            for _, c in pairs(ns.db.chars) do
                local v = ns.GoldOn(c, day)
                if v then sum, any = sum + v, true end
            end
            if any then pts[#pts + 1] = { day = day, v = sum } end
        end
        for _, l in ipairs(lines) do l:Hide() end
        local lo, hi = math.huge, -math.huge
        for _, p in ipairs(pts) do lo, hi = math.min(lo, p.v), math.max(hi, p.v) end
        if hi == lo then lo, hi = lo - 10000, hi + 10000 end
        yTop:SetText(#pts > 0 and ns.Money(hi) or ""); yBot:SetText(#pts > 0 and ns.Money(math.max(lo, 0)) or "")
        xFirst:SetText(pts[1] and pts[1].day or "No gold recorded yet"); xLast:SetText(#pts > 1 and pts[#pts].day or "")
        local w, h = g:GetWidth() or 0, g:GetHeight() or 0
        local function XY(i) return (i - 1) / math.max(#pts - 1, 1) * w, (pts[i].v - lo) / (hi - lo) * h end
        for i = 2, #pts do
            local l = lines[i - 1]
            if not l then l = g:CreateLine(nil, "ARTWORK"); l:SetThickness(2); l:SetColorTexture(1, 0.82, 0); lines[i - 1] = l end
            local x1, y1 = XY(i - 1); local x2, y2 = XY(i)
            l:SetStartPoint("BOTTOMLEFT", g, x1, y1); l:SetEndPoint("BOTTOMLEFT", g, x2, y2); l:Show()
        end
    end

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
        Graph()
    end
end })

end)
