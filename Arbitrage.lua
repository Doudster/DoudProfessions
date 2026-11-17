-- Arbitrage tab: recipes (every profession, Data.lua + live scans) making uncommon to epic weapons / armour whose average
-- disenchant value (Disenchant.lua: table odds, or yours once seen enough; AH price of each result, else vendor) beats the
-- reagent cost (ns.Calc). Outputs not cached yet are asked for and show up once loaded. Orange value = some result unpriced.
-- Filters: profession buttons (multi-select, none = all) and "Known only" (ns.db.arbKnown: recipes one of your characters
-- has learned, as recorded when their trade skill window was opened).
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local SKIP = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true }
local SKILLS = { false, 164, 165, 197, 202, 333 }   -- false = "All"; ponytail: the professions that craft gear, add one here if it starts to

local function Known(id)
    for _, c in pairs(ns.db.chars) do if c.known and c.known[id] then return true end end
end

-- { id (recipe), item, skill, cost, ah (AH price of the output, nil = unpriced), de, all, profit } per recipe whose output disenchants for more than it costs
function ns.ArbitrageItems()
    local list = {}
    local info = C_Item and C_Item.GetItemInfo or GetItemInfo
    for id, r in pairs(ns.AllRecipes()) do
        local out = r[3]
        if out ~= 0 then
            local ok, _, _, q, ilvl, _, _, _, _, loc, _, _, class = pcall(info, out)
            if ok and q and q >= 2 and q <= 4 and (class == 2 or class == 4) and not SKIP[loc or ""] then
                local cost, ah = ns.Calc(r)
                local de, all = ns.DisenchantValue(q, ilvl)
                de = de * r[4]
                if cost and de > cost then
                    list[#list + 1] = { id = id, item = out, skill = r[1], cost = cost, ah = ah, de = math.floor(de), all = all, profit = math.floor(de - cost) }
                end
            end
        end
    end
    return list
end

table.insert(ns.tabs, { name = "Arbitrage", build = function(page)
    local function M(k) return function(r) return ns.Money(r[k]) end end
    local function V(k) return function(r) return r[k] end end
    local cols = {
        { title = "Item", width = 300, value = function(r) return ns.ItemName(r.item) end,
          text = function(r) local c, n = ns.ItemColor(r.item), ns.ItemName(r.item); return c and c .. n .. "|r" or n end,
          icons = function(r) return { ns.ItemIcon(r.item) } end, nameTip = true },
        { title = "Profession", width = 120, value = function(r) return ns.Skills[r.skill] or "?" end },
        { title = "Crafting cost", width = 130, right = true, desc = true, value = V("cost"), text = M("cost") },
        { title = "Auction", width = 130, right = true, desc = true, value = V("ah"), text = M("ah") },
        { title = "Disenchant", width = 130, right = true, desc = true, value = V("de"),
          text = function(r) return ns.Money(r.de, not r.all and "|cffff9900" or nil) end },
        { title = "Profit", width = 130, right = true, desc = true, value = V("profit"), text = M("profit") },
    }
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 8, -12)
    local t = ns.Table(page, cols, 29, function(r)
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(r.item) end
    end, 5, true, { item = function(r) return r.item end })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t

    -- profession buttons (gold ring = selected; none selected = all), then the "Known only" box
    local skills, buttons = {}, {}
    page.buttons = buttons
    local function Mark(b, on)
        b.sel:SetShown(on)
        b.icon:SetDesaturated(not on); b.icon:SetVertexColor(on and 1 or 0.7, on and 1 or 0.7, on and 1 or 0.7)
    end
    for n, id in ipairs(SKILLS) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(32, 32); b:SetPoint("TOPLEFT", 4 + (n - 1) * 36 + (n > 1 and 10 or 0), -4)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
        b.icon:SetTexture("Interface\\Icons\\" .. (id and (ns.SkillIcons[id] or "INV_Misc_QuestionMark") or "INV_Misc_Book_09"))
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.sel:SetBlendMode("ADD")
        b.sel:SetSize(68, 68); b.sel:SetPoint("CENTER")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function()
            if id then skills[id] = not skills[id] or nil else wipe(skills) end
            page.Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(id and ns.Skills[id] or "All professions"); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.id = id
        buttons[n] = b
    end
    local kb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    kb:SetSize(24, 24); kb:SetPoint("LEFT", buttons[#buttons], "RIGHT", 16, 0); kb:SetChecked(ns.db.arbKnown and true or false)
    kb:SetScript("OnClick", function(self) ns.db.arbKnown = self:GetChecked() and true or nil; page.Refresh() end)
    local kl = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    kl:SetPoint("LEFT", kb, "RIGHT", 0, 1); kl:SetText("Known only")
    page.knownBox = kb
    note:ClearAllPoints(); note:SetPoint("RIGHT", page, "TOPRIGHT", -10, -20)

    page.Refresh = function()
        local list = {}
        for _, r in ipairs(ns.ArbitrageItems()) do
            if (next(skills) == nil or skills[r.skill]) and (not ns.db.arbKnown or Known(r.id)) then list[#list + 1] = r end
        end
        for _, b in ipairs(buttons) do Mark(b, b.id and skills[b.id] or not b.id and next(skills) == nil) end
        t:SetRows(list)
        note:SetText(("%d crafts disenchant for more than they cost |cff808080(odds approximate; orange = some results unpriced)|r"):format(#list))
    end
    local queued    -- item info arriving in bursts: one refresh a second
    ns.On("GET_ITEM_INFO_RECEIVED", function()
        if queued or not page:IsVisible() then return end
        queued = true
        C_Timer.After(1, function() queued = false; if page:IsVisible() then page.Refresh() end end)
    end)
end })

end)
