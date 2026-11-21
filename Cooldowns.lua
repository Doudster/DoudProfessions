-- Cooldowns tab + alerts: long crafting cooldowns (1h+: transmutes, Mooncloth, the Salt Shaker item...) of every character.
-- Read from this character's known recipes (ns.Recipes) and its Salt Shaker at each loading screen, after each craft and on
-- item cooldown changes; spells sharing a cooldown merge ("Transmute: Arcanite" -> "Transmute"). A cooldown is listed once
-- it has been used (a ready one never used can't be told apart from a recipe without cooldown).
-- Alerts (pop-up in the raid warning frame + sound + chat line), each once per session: "Ready" (stays on every login until
-- the cooldown is used again) and "Soon" (15 min before). Alts' cooldowns count too, with their name.
-- On-screen list (drag to move, ProfessionsDB.cdPos) of every cooldown ready or under 3h, with its profession icon.
-- ProfessionsDB: chars[key].cds["Name|duration"] = end (time()); cdOff = true turns alerts off. Right-click a row: delete it.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local LONG, SOON, SHOW, SALT = 3600, 900, 3 * 3600, 15846
local said, ticker, page, bar, skillOf = {}, nil, nil, nil, nil

local function Label(name) return name:match("^(.-):") or name end

local function SpellCD(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(id)
        if cd then return cd.startTime, cd.duration end
    elseif GetSpellCooldown then return GetSpellCooldown(id) end
end
local function ItemCD(id)
    local f = C_Item and C_Item.GetItemCooldown or C_Container and C_Container.GetItemCooldown or GetItemCooldown
    if f then return f(id) end
end
local function Count(id)
    local f = C_Item and C_Item.GetItemCount or GetItemCount
    return f and f(id) or 0
end

local function Put(label, start, dur)
    if not (start and dur and start > 0 and dur >= LONG) then return end
    local c = ns.Char()
    c.cds = c.cds or {}
    c.cds[label .. "|" .. math.floor(dur + 0.5)] = math.floor(time() + start + dur - GetTime() + 0.5)
end
local function Save(id)
    local r = ns.Recipes[id]
    if r and IsPlayerSpell(id) then Put(Label(r[2]), SpellCD(id)) end
end
local function SaveSalt()
    if not InCombatLockdown() and Count(SALT) > 0 then Put("Salt Shaker", ItemCD(SALT)) end
end

function ns.ScanCooldowns()
    if InCombatLockdown() then return end
    for id in pairs(ns.Recipes) do Save(id) end
    SaveSalt()
end

-- this character's long-cooldown crafts (for the Test button): transmutes, Mooncloth, any recipe with a 1h+ base
-- cooldown (if the client has GetSpellBaseCooldown), the Salt Shaker in bags, and anything already tracked
function ns.CooldownCrafts()
    local set, out = {}, {}
    for id, r in pairs(ns.Recipes) do
        if IsPlayerSpell(id) and (r[2]:find("^Transmute") or r[2] == "Mooncloth"
            or GetSpellBaseCooldown and (GetSpellBaseCooldown(id) or 0) >= LONG * 1000) then set[Label(r[2])] = true end
    end
    if Count(SALT) > 0 then set["Salt Shaker"] = true end
    for k in pairs(ns.Char().cds or {}) do set[k:match("^(.-)|")] = true end
    for n in pairs(set) do out[#out + 1] = n end
    table.sort(out)
    return out
end

local function Alert(text)
    FT.Print(text)
    local col = ChatTypeInfo and ChatTypeInfo.RAID_WARNING
    if RaidWarningUtil and RaidWarningUtil.AddMessage then RaidWarningUtil.AddMessage(text, col)
    elseif RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, text, col) end
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
end

local function Skill(label)    -- a cooldown's profession, from the first recipe with that label
    if label == "Salt Shaker" then return 165 end    -- the item is used by leatherworkers (the recipe making it is Engineering)
    if not skillOf then
        skillOf = {}
        for _, r in pairs(ns.Recipes) do local l = Label(r[2]); skillOf[l] = skillOf[l] or r[1] end
    end
    return skillOf[label]
end
local function Icon(label) return "Interface\\Icons\\" .. (ns.SkillIcons[Skill(label)] or "INV_Misc_QuestionMark") end

local function Left(t)
    local s = t - time()
    if s <= 0 then return "|cff40ff40Ready|r" end
    local d, h, m = math.floor(s / 86400), math.floor(s / 3600) % 24, math.floor(s / 60) % 60
    return d > 0 and ("%dd %dh"):format(d, h) or h > 0 and ("%dh %02dm"):format(h, m) or ("%d min"):format(math.ceil(s / 60))
end

-- on-screen list of cooldowns ready or under 3h (every character), shown while there is one; drag to move (ProfessionsDB.cdPos)
local function Tracker(rows)
    if not bar then
        if #rows == 0 then return end
        bar = CreateFrame("Frame", "DoudProfessionsCooldowns", UIParent)
        bar:SetSize(240, 20); bar:SetClampedToScreen(true); bar:SetMovable(true); bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", bar.StartMoving)
        bar:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local p, _, rp, x, y = self:GetPoint(); ns.db.cdPos = { p, rp, x, y }
        end)
        bar:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("Crafting cooldowns")
            GameTooltip:AddLine("Drag: move. Turn off: Professions > Cooldowns.", 1, 1, 1); GameTooltip:Show()
        end)
        bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
        local pos = ns.db.cdPos or { "TOP", "TOP", 0, -200 }
        bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        bar.lines = {}
    end
    for i, r in ipairs(rows) do
        local l = bar.lines[i]
        if not l then
            l = { icon = bar:CreateTexture(nil, "ARTWORK"), name = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
                left = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall") }
            l.icon:SetSize(16, 16); l.icon:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
            l.name:SetPoint("LEFT", l.icon, "RIGHT", 4, 0)
            l.left:SetPoint("RIGHT", bar, "TOPRIGHT", -6, -12 - (i - 1) * 18)
            bar.lines[i] = l
        end
        l.icon:SetTexture(Icon(r.label)); l.name:SetText(r.name); l.left:SetText(Left(r.t))
        l.icon:Show(); l.name:Show(); l.left:Show()
    end
    for i = #rows + 1, #bar.lines do local l = bar.lines[i]; l.icon:Hide(); l.name:Hide(); l.left:Hide() end
    bar:SetHeight(#rows * 18 + 8)
    bar:SetShown(#rows > 0)
end

function ns.CheckCooldowns()
    if page and page:IsVisible() then page.Refresh() end
    local now, me, ready, soon, near = time(), ns.CharKey(), {}, {}, {}
    for key, c in pairs(ns.db.cdOff and {} or ns.db.chars) do
        for k, t in pairs(c.cds or {}) do
            local label = k:match("^(.-)|")
            local name = label .. (key ~= me and " (" .. ns.CharName(key, c) .. ")" or "")
            if t - now < SHOW then near[#near + 1] = { label = label, name = name, t = t } end
            local stage = t <= now and "r" or t - now <= SOON and "s"
            local id = key .. k .. t .. tostring(stage)
            if stage and not said[id] then
                said[id] = true
                name = "|T" .. Icon(label) .. ":0|t " .. name
                if stage == "r" then ready[#ready + 1] = name
                else soon[#soon + 1] = ("%s in %d min"):format(name, math.ceil((t - now) / 60)) end
            end
        end
    end
    table.sort(near, function(a, b) return a.t < b.t end)
    Tracker(near)
    table.sort(ready); table.sort(soon)
    if #ready > 0 then Alert("Ready: " .. table.concat(ready, ", ")) end
    if #soon > 0 then Alert("Soon: " .. table.concat(soon, ", ")) end
end

ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(5, function() ns.ScanCooldowns(); ns.CheckCooldowns() end)
    ticker = ticker or C_Timer.NewTicker(30, ns.CheckCooldowns)
end)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, id)
    if unit == "player" and not InCombatLockdown() and ns.Recipes[id] then C_Timer.After(1, function() Save(id); ns.CheckCooldowns() end) end
end)
ns.On("BAG_UPDATE_COOLDOWN", SaveSalt)

table.insert(ns.tabs, { name = "Cooldowns", build = function(p)
    page = p
    local cols = {
        { title = "Character", width = 220, value = function(r) return r.key end, text = function(r) return ns.CharName(r.key, r.c) end },
        { title = "Cooldown", width = 260, value = function(r) return r.name end, icons = function(r) return { Icon(r.name) } end },
        { title = "Ready in", width = 140, value = function(r) return r.t end, text = function(r) return Left(r.t) end },
        { title = "Ready at", width = 180, value = function(r) return r.t end, text = function(r) return date("%a %H:%M", r.t) end },
    }
    local t = ns.Table(p, cols, 29, nil, 3, false, { click = ns.DeleteClick(p,
        function(r) return ns.CharName(r.key, r.c) .. "'s " .. r.name end, function(r) r.c.cds[r.k] = nil end) })
    t:SetPoint("TOPLEFT", 4, -44)
    p.table = t
    local kb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    kb:SetSize(24, 24); kb:SetPoint("TOPLEFT", 6, -10)
    kb:SetScript("OnClick", function(self) ns.db.cdOff = not self:GetChecked() or nil; ns.CheckCooldowns() end)
    local kl = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    kl:SetPoint("LEFT", kb, "RIGHT", 0, 1); kl:SetText("Reminders (pop-up + sound when ready and 15 min before)")
    p.alertBox = kb
    local test = ns.Chip(p, 110, 22, "Test", function()
        local list = ns.CooldownCrafts()
        if #list == 0 then FT.Print("no long crafting cooldown on this character") return end
        local rows, names = {}, {}
        for i, n in ipairs(list) do rows[i] = { label = n, name = n, t = time() }; names[i] = "|T" .. Icon(n) .. ":0|t " .. n end
        Tracker(rows)    -- preview until the next check (30s)
        Alert("Test - Ready: " .. table.concat(names, ", "))
    end)
    test:SetPoint("LEFT", kl, "RIGHT", 12, -1)
    local note = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("RIGHT", p, "TOPRIGHT", -10, -20)
    note:SetText("Listed once used. Log in on an alt to update it. Right-click a row to delete it.")
    p.Refresh = function()
        kb:SetChecked(not ns.db.cdOff)
        local list = {}
        for key, c in pairs(ns.db.chars) do
            for k, v in pairs(c.cds or {}) do list[#list + 1] = { key = key, c = c, k = k, name = k:match("^(.-)|"), t = v } end
        end
        t:SetRows(list)
    end
end })

end)
