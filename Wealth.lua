-- Wealth tab: each character's gold, recorded per day (the last amount seen that day, kept forever: ~20 bytes a day),
-- with the account total, and a smoothed graph of that total over a chosen timeframe (7 days .. all time).
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local DAY = 86400
local function Today(offset) return date("%Y-%m-%d", time() - (offset or 0) * DAY) end
local function DayTime(d) local y, m, dd = d:match("(%d+)-(%d+)-(%d+)"); return time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 }) end

local function Record()
    local c = ns.Char()
    c.money = c.money or {}
    c.money[Today()] = GetMoney()
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

-- the account total on every day any character's gold was recorded (+ today), each character at its last amount:
-- { { t = time, day = "YYYY-MM-DD", v = copper } } oldest first
function ns.WealthSeries()
    local days, seen = {}, {}
    for _, c in pairs(ns.db.chars) do
        for d in pairs(c.money or {}) do if not seen[d] then seen[d] = true; days[#days + 1] = d end end
    end
    if #days == 0 then return {} end
    if not seen[Today()] then days[#days + 1] = Today() end
    table.sort(days)
    local last, pts = {}, {}
    for _, d in ipairs(days) do
        local sum = 0
        for key, c in pairs(ns.db.chars) do
            local v = c.money and c.money[d]
            if v then last[key] = v end
            sum = sum + (last[key] or 0)
        end
        pts[#pts + 1] = { t = DayTime(d), day = d, v = sum }
    end
    return pts
end

-- monotone cubic through the points (Fritsch-Carlson): smooth, never overshoots past a day's real amount.
-- Returns f(x) for x within [xs[1], xs[n]].
function ns.Smooth(xs, ys)
    local n, d, m = #xs, {}, {}
    for i = 1, n - 1 do d[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) end
    m[1], m[n] = d[1] or 0, d[n - 1] or 0
    for i = 2, n - 1 do m[i] = d[i - 1] * d[i] <= 0 and 0 or (d[i - 1] + d[i]) / 2 end
    for i = 1, n - 1 do
        if d[i] == 0 then m[i], m[i + 1] = 0, 0
        else
            local a, b = m[i] / d[i], m[i + 1] / d[i]
            local s = a * a + b * b
            if s > 9 then local k = 3 / math.sqrt(s); m[i], m[i + 1] = k * a * d[i], k * b * d[i] end
        end
    end
    local seg = 1
    return function(x)
        if n == 1 then return ys[1] end
        if x < xs[seg] then seg = 1 end
        while seg < n - 1 and x > xs[seg + 1] do seg = seg + 1 end
        local h = xs[seg + 1] - xs[seg]
        local t = (x - xs[seg]) / h
        local t2, t3 = t * t, t * t * t
        return (2 * t3 - 3 * t2 + 1) * ys[seg] + (t3 - 2 * t2 + t) * h * m[seg]
            + (-2 * t3 + 3 * t2) * ys[seg + 1] + (t3 - t2) * h * m[seg + 1]
    end
end

-- 1 / 2 / 5 x 10^k copper, the tick step for about n ticks over range
local function NiceStep(range, n)
    local raw = math.max(range / n, 1)
    local p = 10 ^ math.floor(math.log10(raw))
    for _, k in ipairs({ 1, 2, 5, 10 }) do if raw <= k * p then return k * p end end
end

local GOLD = { 1, 0.82, 0 }
local RANGES = { { "7 days", 7 }, { "30 days", 30 }, { "90 days", 90 }, { "1 year", 365 }, { "All", nil } }

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
    local t = ns.Table(page, cols, 9, nil, 2, true, { click = ns.DeleteClick(page,
        function(r) return "the gold history of " .. ns.CharName(r.key, r.c) end, function(r) r.c.money = nil end) })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t

    -- graph: title + timeframe chips on one line, then the plot (left margin for the gold axis, bottom for dates)
    local head = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    head:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 4, -18)
    local g = CreateFrame("Frame", nil, page); page.graph = g
    g:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 74, -56); g:SetPoint("BOTTOMRIGHT", -24, 30)
    local chips, Graph = {}, nil
    for i = #RANGES, 1, -1 do
        local r = RANGES[i]
        local c = ns.Chip(page, 78, 22, r[1], function() ns.db.wealthDays = r[2] or false; Graph() end)
        c:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", -(#RANGES - i) * 82, 14)
        c.mark = c:CreateTexture(nil, "OVERLAY"); c.mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
        c.mark:SetHeight(2); c.mark:SetPoint("BOTTOMLEFT", 8, -3); c.mark:SetPoint("BOTTOMRIGHT", -8, -3)
        c.days = r[2]
        chips[i] = c
    end

    local function Pool(make)
        local list = {}
        return function(i) local o = list[i] or make(); list[i] = o; o:Show(); return o end,
            function(from) for i = from, #list do list[i]:Hide() end end
    end
    local GridLine, HideGrid = Pool(function() local x = g:CreateTexture(nil, "BACKGROUND"); x:SetHeight(1); return x end)
    local YLabel, HideY = Pool(function() local x = g:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); x:SetTextColor(0.7, 0.7, 0.7); return x end)
    local XLabel, HideX = Pool(function() local x = g:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); x:SetTextColor(0.7, 0.7, 0.7); return x end)
    local Seg, HideSeg = Pool(function()
        local l = g:CreateLine(nil, "ARTWORK"); l:SetThickness(2); l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1); return l end)
    local Fill, HideFill = Pool(function()
        local x = g:CreateTexture(nil, "BORDER"); x:SetColorTexture(1, 1, 1, 1)
        if CreateColor then x:SetGradient("VERTICAL", CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.02), CreateColor(GOLD[1], GOLD[2], GOLD[3], 0.22))
        else x:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12) end
        return x end)
    local empty = g:CreateFontString(nil, "ARTWORK", "GameFontDisable"); empty:SetPoint("CENTER")

    -- hover: a guide line, a dot on the curve and the day's total in the tooltip
    local guide = g:CreateTexture(nil, "OVERLAY"); guide:SetWidth(1); guide:SetColorTexture(1, 1, 1, 0.25); guide:Hide()
    local dot = g:CreateTexture(nil, "OVERLAY"); dot:SetSize(6, 6); dot:SetColorTexture(1, 1, 1, 1); dot:Hide()
    local view    -- what Graph() drew: pts, x0, x1 (times), lo, hi, w, h
    local function Hover()
        if not view or not g:IsMouseOver() then return end
        local x = GetCursorPosition() / g:GetEffectiveScale() - g:GetLeft()
        local tm, best = view.x0 + x / view.w * (view.x1 - view.x0), nil
        for _, p in ipairs(view.pts) do if not best or math.abs(p.t - tm) < math.abs(best.t - tm) then best = p end end
        local px = (best.t - view.x0) / (view.x1 - view.x0) * view.w
        local py = (best.v - view.lo) / (view.hi - view.lo) * view.h
        guide:ClearAllPoints(); guide:SetPoint("TOP", g, "TOPLEFT", px, 0); guide:SetPoint("BOTTOM", g, "BOTTOMLEFT", px, 0); guide:Show()
        dot:ClearAllPoints(); dot:SetPoint("CENTER", g, "BOTTOMLEFT", px, py); dot:Show()
        GameTooltip:SetOwner(g, "ANCHOR_CURSOR")
        GameTooltip:SetText(best.day, 1, 1, 1)
        GameTooltip:AddLine(ns.Money(best.v), GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:Show()
    end
    g:EnableMouse(true)
    g:SetScript("OnUpdate", function() if g:IsMouseOver() then Hover() elseif guide:IsShown() then guide:Hide(); dot:Hide(); GameTooltip:Hide() end end)

    Graph = function()
        local days = ns.db.wealthDays or nil
        for _, c in ipairs(chips) do c.mark:SetShown(c.days == days) end
        head:SetText("Account total, " .. (days and ("last " .. (days == 365 and "year" or days .. " days")) or "all time"))
        local all, w, h = ns.WealthSeries(), g:GetWidth() or 0, g:GetHeight() or 0
        view = nil
        HideGrid(1); HideY(1); HideX(1); HideSeg(1); HideFill(1)
        empty:SetText(#all == 0 and "No gold recorded yet" or "")
        if #all == 0 or w <= 0 or h <= 0 then return end

        -- points in range; the amount carried in from before the range starts it, a lone day is drawn flat
        local x1 = all[#all].t
        local x0 = days and x1 - (days - 1) * DAY or all[1].t
        local pts, before = {}, nil
        for _, p in ipairs(all) do
            if p.t < x0 then before = p else pts[#pts + 1] = p end
        end
        if before and (not pts[1] or pts[1].t > x0) then table.insert(pts, 1, { t = x0, day = date("%Y-%m-%d", x0), v = before.v }) end
        if not days then x0 = pts[1].t end
        if x1 == x0 then x0 = x1 - DAY end
        if #pts == 1 then pts[2] = { t = x1, day = pts[1].day, v = pts[1].v }; pts[1] = { t = x0, day = pts[1].day, v = pts[1].v } end

        -- gold axis: round steps, about 4 gridlines
        local lo, hi = math.huge, -math.huge
        for _, p in ipairs(pts) do lo, hi = math.min(lo, p.v), math.max(hi, p.v) end
        local step = NiceStep(math.max(hi - lo, math.max(hi, 1) * 0.1), 4)
        lo, hi = math.max(math.floor(lo / step) * step, 0), math.ceil(hi / step) * step
        if hi <= lo then hi = lo + step end
        local i = 0
        for v = lo, hi + step / 2, step do
            i = i + 1
            local y = (v - lo) / (hi - lo) * h
            local gl = GridLine(i); gl:ClearAllPoints()
            gl:SetPoint("LEFT", g, "BOTTOMLEFT", 0, y); gl:SetPoint("RIGHT", g, "BOTTOMRIGHT", 0, y)
            gl:SetColorTexture(1, 1, 1, v == lo and 0.25 or 0.07)
            local lb = YLabel(i); lb:ClearAllPoints(); lb:SetPoint("RIGHT", g, "BOTTOMLEFT", -8, y)
            lb:SetText(v >= 10000 and v % 10000 == 0 and ns.Money(v):gsub(" 00|T.-|t", "") or ns.Money(v))
        end

        -- dates: about 5, short form within a year
        local span, fmt = x1 - x0, (x1 - x0) > 300 * DAY and "%b %Y" or "%d %b"
        local n = math.max(math.min(5, math.floor(span / DAY) + 1), 2)
        for k = 1, n do
            local tm = x0 + (k - 1) / (n - 1) * span
            local lb = XLabel(k); lb:ClearAllPoints()
            lb:SetPoint(k == 1 and "TOPLEFT" or k == n and "TOPRIGHT" or "TOP", g, "BOTTOMLEFT", (k - 1) / (n - 1) * w, -6)
            lb:SetText(date(fmt, tm))
        end

        -- the curve, sampled every 3 px, with a soft fill under it
        local xs, ys = {}, {}
        for k, p in ipairs(pts) do xs[k], ys[k] = (p.t - x0) / span * w, (p.v - lo) / (hi - lo) * h end
        local f, STEP, px, py, k = ns.Smooth(xs, ys), 3, nil, nil, 0
        for sx = xs[1], w + STEP - 0.01, STEP do
            local x = math.min(sx, w)
            local y = math.max(math.min(f(x), h), 0)
            k = k + 1
            if px then local l = Seg(k - 1); l:SetStartPoint("BOTTOMLEFT", g, px, py); l:SetEndPoint("BOTTOMLEFT", g, x, y) end
            local fl = Fill(k); fl:ClearAllPoints()
            fl:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", x, 0); fl:SetSize(math.min(STEP, w - x + 0.01), math.max(y, 0.01))
            px, py = x, y
        end
        view = { pts = pts, x0 = x0, x1 = x1, lo = lo, hi = hi, w = w, h = h }
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
