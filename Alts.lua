-- Alts tab: every character's professions and skill levels, recorded at login, on skill changes and when a trade
-- skill opens. One row per character and profession, so sorting by Profession then Skill finds the best crafter.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

function ns.RecordProfessions()
    if not GetProfessions then return end
    local profs = {}
    for i = 1, 6 do       -- prof1, prof2, archaeology, fishing, cooking, first aid (nil = none)
        local idx = select(i, GetProfessions())
        if idx then
            local name, _, rank, max = GetProfessionInfo(idx)
            if name then profs[#profs + 1] = { name, rank or 0, max or 0 } end
        end
    end
    local c = ns.Char()
    c.profs, c.profsAt = profs, time()
end
ns.On("PLAYER_ENTERING_WORLD", ns.RecordProfessions)
ns.On("SKILL_LINES_CHANGED", ns.RecordProfessions)
ns.On("TRADE_SKILL_SHOW", ns.RecordProfessions)

table.insert(ns.tabs, { name = "Alts' professions", build = function(page)
    local cols = {
        { title = "Character", width = 220, value = function(r) return r.key end, text = function(r) return ns.CharName(r.key, r.c) end },
        { title = "Profession", width = 220, value = function(r) return r.p[1] end },
        { title = "Skill", width = 90, right = true, desc = true, value = function(r) return r.p[2] end },
        { title = "Max", width = 90, right = true, desc = true, value = function(r) return r.p[3] end },
        { title = "Recorded", width = 180, desc = true, value = function(r) return r.c.profsAt end,
          text = function(r) return r.c.profsAt and date("%Y-%m-%d %H:%M", r.c.profsAt) or "" end },
    }
    local t = ns.Table(page, cols, 29, nil, 1, false, { click = ns.DeleteClick(page,
        function(r) return ns.CharName(r.key, r.c) .. "'s " .. r.p[1] end, function(r) ns.Remove(r.c.profs, r.p) end) })
    t:SetPoint("TOPLEFT", 4, -40)
    page.table = t
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 8, -12)
    note:SetText("Recorded when each character logs in. Log in on an alt once to add it. Right-click a row to delete it.")
    page.Refresh = function()
        local list = {}
        for key, c in pairs(ns.db.chars) do
            for _, p in ipairs(c.profs or {}) do list[#list + 1] = { key = key, c = c, p = p } end
        end
        t:SetRows(list)
    end
end })

end)
