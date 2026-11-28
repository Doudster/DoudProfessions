-- Professions: a "Professions" tab on Blizzard's profession window (Blizzard_Professions, lazy-loaded) + a minimap button
-- opens a wide window (the full journal's size) with its own tabs, one file each: Recipes, Alts, Wealth, Sales, Item stats, Disenchant, Vendor, Flip, Arbitrage, Crates, Writs, Cooldowns.
-- Right-click a row of Alts / Wealth / Sales / Item stats / Vendor: delete it (asks first).
-- Tab files add { name, build = fn(page), shown = fn() (optional: false hides the tab) } to ns.tabs and listen through ns.On;
-- page.Refresh (if set) runs on show.
-- Settings (ProfessionsDB, account-wide): chars["Name-Realm"] = { class, profs = { {name, rank, max} }, profsAt,
-- money = { ["YYYY-MM-DD"] = copper (last seen that day) } }, sales = { {t, char, kind, item, count, money} },
-- vendor = { {t, char, kind = buy/buyback/repair, item (link), count, cost, vendor, note} } (Vendor tab),
-- fav[recipeID] / hidden[recipeID] = true (Recipes tab), mine = true (Recipes tab "My professions" filter on), hideUnknown = true (Recipes tab "Hide unknown": recipes nobody knows left out), scanned[recipeID] = recipe read from an open trade skill (Data.lua format), pos = window position,
-- deIgnore[itemID] = true / deBound / deAuto / deObs["quality:ilvl/5"] = { n, [itemID] = times } (Disenchant tab).
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

local NAME = "DoudProfessionsFrame"
local W, H = 1000, 720      -- W: Recipes.lua sets ns.W from its table width (used at build time); H = the full Journal's (ForeverJournal/UI.lua)
local TAB_LABEL = "Professions"
ns.W, ns.H = W, H
ns.tabs = {}

local handlers, ev = {}, CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, e, ...) for _, fn in ipairs(handlers[e]) do fn(...) end end)
function ns.On(e, fn)
    if not handlers[e] then handlers[e] = {}; ev:RegisterEvent(e) end
    table.insert(handlers[e], fn)
end

function ns.CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
function ns.Char()
    local k = ns.CharKey()
    local c = ns.db.chars[k] or {}
    ns.db.chars[k] = c
    if not ns.merged then   -- same name on another realm = same character: fold it into this one (this one wins)
        ns.merged = true
        local n = k:match("^(.-)%-")
        for k2, o in pairs(ns.db.chars) do
            if k2 ~= k and k2:match("^(.-)%-") == n then
                for f, v in pairs(o) do
                    local mine = c[f]
                    if mine == nil then c[f] = v
                    elseif type(mine) == "table" and type(v) == "table" and mine[1] == nil then
                        for kk, vv in pairs(v) do if mine[kk] == nil then mine[kk] = vv end end
                    end
                end
                ns.db.chars[k2] = nil
            end
        end
    end
    c.class = select(2, UnitClass("player"))
    return c
end
-- "Name" in its class colour
function ns.CharName(key, c)
    local col = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local n = key:match("^(.-)%-") or key
    return col and ("|c%s%s|r"):format(col.colorStr or "ffffffff", n) or n
end

-- copper -> "12 03 07" with gold/silver/copper coin icons after each part (copper omitted above 1 gold; negative in red), nil -> grey "?"; color ("|cffRRGGBB", optional) tints the digits
function ns.Money(c, col)
    if not c then return "|cff808080?|r" end
    local neg = c < 0
    c = math.floor(math.abs(c) + 0.5)
    local function D(v) return col and col .. v .. "|r" or v end
    local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local function I(k) return "|TInterface\\MoneyFrame\\UI-" .. k .. "Icon:0:0:2:0|t" end
    local t = g > 0 and (D(g) .. I("Gold") .. " " .. D(("%02d"):format(s)) .. I("Silver"))
        or s > 0 and (D(s) .. I("Silver") .. " " .. D(("%02d"):format(cu)) .. I("Copper")) or (D(cu) .. I("Copper"))
    return neg and "|cffff4040-|r" .. t or t
end

function ns.ItemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n then    -- the classic-style API may know it when the by-ID lookup doesn't yet
        local ok, v = pcall(function() return (C_Item and C_Item.GetItemInfo or GetItemInfo)(id) end)
        n = ok and type(v) == "string" and v or nil
    end
    if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return n or ("item " .. id)
end

-- an item's icon texture (nil until known)
function ns.ItemIcon(id)
    local ok, ic = pcall(function()
        return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or GetItemIcon and GetItemIcon(id)
    end)
    return ok and ic or nil
end
-- "|cffRRGGBB" of an item's quality colour (nil until known; asks the client to load it)
function ns.ItemColor(id)
    if not id or id == 0 then return end
    local ok, q = pcall(function()
        return C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) or GetItemInfo and select(3, GetItemInfo(id))
    end)
    if not (ok and q) then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and c.hex
end

-- A sortable, scrolling list. cols = { { title, width, value = fn(rec) -> sort key (nil sorts last),
-- text = fn(rec) -> string (default: value), right = true,
-- icon = fn(rec) -> texture, l, r, t, b (a 14px texture instead of text; or a table { atlas = name } / { tex = path, color = { r, g, b } }
-- for an atlas / a tinted texture), icons = fn(rec) -> { texture, ... }
-- (18px textures before the text), tag = fn(rec) -> string|nil (a small grey right-aligned label in the cell; the text is
-- shortened to clear it), tagTip = fn(rec) (with tag: hovering the tag fills GameTooltip; the tag's hover region ignores clicks, so
-- they still reach the row) } }. t:SetRows(recs) redraws; a header click sorts by that column, a second
-- click reverses. tip(rec) (optional) fills GameTooltip while hovering the text of a column marked nameTip (not the rest of the row). opts (optional): rowTip(rec) fills GameTooltip (at the cursor) while hovering anywhere on the row, click(rec, button, colIndex)
-- on row click, item(rec) -> itemID (Shift+left click searches it on an open AH, via Auctionator), pin(rec) -> number (lower sorts first, true = 1, nil/false = last) whatever the sort column, selected(rec) -> true highlights the
-- row, dim(rec) -> true draws the row at alpha 0.45; expand(rec) -> frame or nil: that frame (sized by the caller) is shown right under the row, pushing the following
-- rows down (rows that no longer fit are hidden; the frame is hidden when its row isn't shown); t.Redraw() repaints without re-sorting; t.colX[k] = column k's left x in the table, t.width = its width (scrollbar included).
local ROW = 21
-- Shift+click on a row with the AH open: Auctionator searches that item (exact name). true when it searched
function ns.AHSearch(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local open = AuctionHouseFrame and AuctionHouseFrame:IsShown() or AuctionFrame and AuctionFrame:IsShown()
    local name = id and id ~= 0 and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not (api and api.MultiSearchExact and open and name) then return end
    pcall(api.MultiSearchExact, "DoudUI", { name })
    return true
end
-- tooltip owner: the user's global tooltip anchor (TooltipTweaks re-anchors GameTooltip_SetDefaultAnchor) when present
function ns.TipOwner(f)
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, f) else GameTooltip:SetOwner(f, "ANCHOR_RIGHT") end
end
-- hover region on a row at (point, x): motion only, clicks fall through to the row; OnEnter fills GameTooltip via fn(rec)
local function Hover(r, point, x, fn)
    local h = CreateFrame("Frame", nil, r)
    h:SetHeight(ROW); h:SetPoint(point, r, "LEFT", x, 0); h:EnableMouse(true)
    if not pcall(h.SetMouseClickEnabled, h, false) then
        h:SetScript("OnMouseUp", function(_, b) local f = r:GetScript("OnClick"); if f then f(r, b) end end)
    end
    h:SetScript("OnEnter", function(self)
        if not r.rec then return end
        r:LockHighlight(); ns.TipOwner(self)
        -- Blizzard's OnUpdate calls this every 0.2s: refill only when Shift flips (Shift-compare), else the tooltip flashes
        self.UpdateTooltip = function(s)
            local sh = IsShiftKeyDown()
            if sh ~= s.shift and r.rec then s.shift = sh; fn(r.rec); GameTooltip:Show() end
        end
        self.shift = nil; self:UpdateTooltip()
    end)
    h:SetScript("OnLeave", function(self) self.UpdateTooltip = nil; r:UnlockHighlight(); GameTooltip:Hide() end)
    return h
end
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
function ns.Table(parent, cols, nRows, tip, sortCol, desc, opts)
    opts = opts or {}
    local t = CreateFrame("Frame", nil, parent)
    local width = 14
    for _, c in ipairs(cols) do width = width + c.width end
    t:SetSize(width, (nRows + 1) * ROW)
    local recs, sorted, offset = {}, {}, 0
    local rows, heads = {}, {}
    local sb, open = nil, {}
    if t.SetClipsChildren then t:SetClipsChildren(true) end

    local function Draw()
        local used, y = {}, 0
        for i, r in ipairs(rows) do
            local rec = sorted[offset + i]
            if rec and y + ROW > nRows * ROW then rec = nil end
            r.rec = rec
            r:SetAlpha(rec and opts.dim and opts.dim(rec) and 0.45 or 1)
            r:SetShown(rec ~= nil)
            if rec then
                r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -ROW - y); y = y + ROW
                r.selTex:SetShown(opts.selected and opts.selected(rec) or false)
                for k, c in ipairs(cols) do
                    if c.icon then
                        local v, l, rr, tp, b = c.icon(rec)
                        local cell = r.cells[k]
                        if type(v) == "table" then
                            if v.atlas then cell:SetAtlas(v.atlas) else cell:SetTexture(v.tex); cell:SetTexCoord(0, 1, 0, 1) end
                            local col = v.color or { 1, 1, 1 }; cell:SetVertexColor(col[1], col[2], col[3])
                        else
                            cell:SetTexture(v); cell:SetTexCoord(l, rr, tp, b); cell:SetVertexColor(1, 1, 1)
                        end
                    else
                        local v = c.text and c.text(rec) or c.value(rec)
                        local fs, list = r.cells[k], c.icons and c.icons(rec) or {}
                        local tg, tf = c.tag and c.tag(rec), r.tags[k]
                        if tf then tf:SetText(tg or "") end
                        if r.tagHit[k] then r.tagHit[k]:SetWidth(tf:GetStringWidth() + 2); r.tagHit[k]:SetShown(tg ~= nil) end
                        fs:SetPoint("LEFT", r.x[k] + 4 + #list * 20, 0); fs:SetWidth(c.width - 8 - #list * 20 - (tg and tf:GetStringWidth() + 6 or 0))
                        fs:SetText(v ~= nil and tostring(v) or "")
                        if r.nameK == k then r.nameHit:SetWidth(math.max(math.min(fs:GetStringWidth(), fs:GetWidth()), 1) + 2); r.nameHit:ClearAllPoints(); r.nameHit:SetPoint("LEFT", fs, "LEFT") end
                        for j, tx in ipairs(list) do
                            local ic = r.icons[k * 10 + j]
                            if not ic then
                                ic = r:CreateTexture(nil, "ARTWORK"); ic:SetSize(18, 18)
                                ic:SetPoint("LEFT", r.x[k] + 4 + (j - 1) * 20, 0); r.icons[k * 10 + j] = ic
                            end
                            ic:SetTexture(tx); ic:Show()
                        end
                        for j = #list + 1, 2 do if r.icons[k * 10 + j] then r.icons[k * 10 + j]:Hide() end end
                    end
                end
                local f = opts.expand and opts.expand(rec)
                if f then
                    f:ClearAllPoints(); f:SetPoint("TOPLEFT", r, "BOTTOMLEFT"); f:Show()
                    used[f] = true; y = y + f:GetHeight()
                end
            end
        end
        for f in pairs(open) do if not used[f] then f:Hide() end end
        open = used
    end
    local function Sort()
        local c = cols[sortCol]
        for i, h in ipairs(heads) do
            h.arrow:SetShown(i == sortCol)
            h.arrow:SetTexCoord(0, 0.5625, desc and 1 or 0, desc and 0 or 1)
        end
        local pin = opts.pin
        local function P(r) local v = pin(r); return v == true and 1 or v or math.huge end
        table.sort(sorted, function(a, b)
            if pin then
                local pa, pb = P(a), P(b)
                if pa ~= pb then return pa < pb end
            end
            local x, y = c.value(a), c.value(b)
            if x == nil or y == nil then if x ~= y then return x ~= nil end
            elseif x ~= y then if desc then return x > y end return x < y end
            return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)   -- ties by id: same order every refresh (pairs order varies)
        end)
        Draw()
    end

    local x = 0
    t.colX = {}
    for i, c in ipairs(cols) do
        t.colX[i] = x
        local h = CreateFrame("Button", nil, t)
        h:SetSize(c.width, ROW); h:SetPoint("TOPLEFT", x, 0)
        h.label = h:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h.label:SetPoint(c.right and "RIGHT" or "LEFT", c.right and -4 or 4, 0); h.label:SetText(c.title)    -- same inset as the cells
        h.arrow = h:CreateTexture(nil, "ARTWORK")
        h.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow"); h.arrow:SetSize(9, 8)
        h.arrow:SetPoint(c.right and "RIGHT" or "LEFT", h.label, c.right and "LEFT" or "RIGHT", c.right and -3 or 3, 0)
        h:SetHighlightTexture(HIGHLIGHT, "ADD")
        h:SetScript("OnClick", function()
            if sortCol == i then desc = not desc else sortCol, desc = i, c.desc or false end
            Sort()
        end)
        heads[i] = h
        x = x + c.width
    end
    local line = t:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.8, 0.64, 0.36, 0.5); line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -ROW); line:SetPoint("TOPRIGHT", 0, -ROW)

    for i = 1, nRows do
        local r = CreateFrame("Button", nil, t)
        r:SetSize(width - 14, ROW); r:SetPoint("TOPLEFT", 0, -i * ROW)
        r:SetHighlightTexture(HIGHLIGHT, "ADD")
        if i % 2 == 0 then
            local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.04)
        end
        r.selTex = r:CreateTexture(nil, "BACKGROUND"); r.selTex:SetAllPoints()
        r.selTex:SetColorTexture(1, 0.82, 0, 0.18); r.selTex:Hide()
        r.cells, r.icons, r.x, r.tags, r.tagHit = {}, {}, {}, {}, {}
        x = 0
        for k, c in ipairs(cols) do
            local fs
            if c.icon then
                fs = r:CreateTexture(nil, "ARTWORK"); fs:SetSize(14, 14); fs:SetPoint("CENTER", r, "LEFT", x + c.width / 2, 0)
            else
                fs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                fs:SetSize(c.width - 8, ROW); fs:SetPoint("LEFT", x + 4, 0)
                fs:SetJustifyH(c.right and "RIGHT" or "LEFT"); fs:SetWordWrap(false)
            end
            if c.tag then
                local tf = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                tf:SetPoint("RIGHT", r, "LEFT", x + c.width - 4, 0); tf:SetJustifyH("RIGHT"); r.tags[k] = tf
                if c.tagTip then r.tagHit[k] = Hover(r, "RIGHT", x + c.width - 4, c.tagTip) end
            end
            if c.nameTip and tip and not c.icon then r.nameHit, r.nameK = Hover(r, "LEFT", x + 4, tip), k end
            r.cells[k], r.x[k] = fs, x
            x = x + c.width
        end
        if opts.click or opts.item then
            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r:SetScript("OnClick", function(self, btn)
                if not self.rec then return end
                if btn == "LeftButton" and IsShiftKeyDown() and opts.item and ns.AHSearch(opts.item(self.rec)) then return end
                if not opts.click then return end
                local col, left = 1, self:GetLeft()
                if left and GetCursorPosition then    -- column under the cursor
                    local cx = GetCursorPosition() / self:GetEffectiveScale() - left
                    local w = 0
                    for k, c in ipairs(cols) do w = w + c.width; col = k; if cx < w then break end end
                end
                opts.click(self.rec, btn, col)
            end)
        end
        if opts.rowTip then    -- whole-row tooltip (hover regions of tag/nameTip columns keep their own)
            r:SetScript("OnEnter", function(self)
                if self.rec then GameTooltip:SetOwner(self, "ANCHOR_CURSOR"); opts.rowTip(self.rec); GameTooltip:Show() end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        rows[i] = r
    end

    sb = CreateFrame("Slider", nil, t)
    sb:SetOrientation("VERTICAL"); sb:SetWidth(12)
    sb:SetPoint("TOPRIGHT", 0, -ROW - 2); sb:SetPoint("BOTTOMRIGHT")
    local track = sb:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.35)
    sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    sb:SetValueStep(1); sb:SetMinMaxValues(0, 0); sb:SetValue(0)
    sb:SetScript("OnValueChanged", function(_, v) offset = math.floor(v + 0.5); Draw() end)
    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(_, d) sb:SetValue(math.max(0, offset - d * 3)) end)

    function t:SetRows(list)
        recs = list
        sorted = {}
        for i, r in ipairs(recs) do sorted[i] = r end
        local max = math.max(0, #sorted - nRows)
        sb:SetMinMaxValues(0, max)
        if offset > max then offset = max end
        sb:SetValue(offset)
        Sort()
    end
    t.sorted = function() return sorted end    -- for tests
    t.Redraw = Draw
    t.rows, t.cols, t.width = rows, cols, width
    sortCol = sortCol or 1
    return t
end

-- Journal-style button: the shared dark look (FT.SkinButton, Core.lua: tertiary atlases, Cinzel label in capitals).
-- :SetEnabled(false) greys it out (tooltips still fire: the button stays mouse-enabled).
function ns.Chip(parent, w, h, label, onClick)
    local c = CreateFrame("Button", nil, parent); c:SetSize(w, h)
    c.enabled = true
    local paint = FT.SkinButton(c, function() return c.enabled end)
    c.text = c:GetFontString()
    c:SetText(label)
    local setEnabled = c.SetEnabled
    function c:SetEnabled(v) self.enabled = v and true or false; setEnabled(self, v); if paint then paint() end end
    c:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if onClick then c:SetScript("OnClick", onClick) end
    return c
end

-- remove every x from list (by identity)
function ns.Remove(list, x) for i = #list, 1, -1 do if list[i] == x then table.remove(list, i) end end end
-- a ns.Table click handler deleting the right-clicked row after a Yes/No popup: what(rec) names it, del(rec) removes it,
-- then the page refreshes
function ns.DeleteClick(page, what, del)
    return function(rec, btn)
        if btn ~= "RightButton" then return end
        if StaticPopupDialogs and not StaticPopupDialogs.DOUDUI_PROF_DELETE then
            StaticPopupDialogs.DOUDUI_PROF_DELETE = { text = "Delete %s?", button1 = YES or "Yes", button2 = NO or "No",
                timeout = 0, whileDead = true, hideOnEscape = true, OnAccept = function(_, go) go() end }
        end
        local function go() del(rec); page.Refresh() end
        if StaticPopup_Show then StaticPopup_Show("DOUDUI_PROF_DELETE", what(rec), nil, go) else go() end
    end
end

-- Window -----------------------------------------------------------------------------------
local frame, current
local pages, tabButtons = {}, {}

-- Escape: while Blizzard's profession window is open it owns Escape and takes ours down with it (one press closes both);
-- on its own, ours is a UISpecialFrames entry
local function SyncEscape()
    if not frame then return end
    local name, pf = frame:GetName(), ProfessionsFrame
    for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end end
    if not (type(pf) == "table" and pf:IsShown()) then tinsert(UISpecialFrames, name) end
end

local function Select(i)
    current = i
    if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, frame, i) end
    local page = pages[i]
    if not page then
        page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 12, -30); page:SetPoint("BOTTOMRIGHT", -12, 12)
        page:Hide()
        pages[i] = page
        ns.tabs[i].build(page)
    end
    for k, p in pairs(pages) do p:SetShown(k == i) end
    if page.Refresh then page.Refresh() end
end

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", NAME, UIParent, "PortraitFrameTemplate")
    if ok and f and type(f.NineSlice) == "table" then
        if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
    else
        if ok and f then f:Hide() end
        f = CreateFrame("Frame", NAME .. "Plain", UIParent)
        local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.05, 0.04, 0.95)
        ok = false
    end
    if ok then    -- the journal's dark stone over the template background, dimmed (as CharacterSheet)
        local bg = f:CreateTexture(nil, "BACKGROUND", nil, -4)
        if type(f.Bg) == "table" then bg:SetAllPoints(f.Bg) else bg:SetPoint("TOPLEFT", 2, -21); bg:SetPoint("BOTTOMRIGHT", -2, 2) end
        if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Legacy-Rewards-Tracker-background")
            and bg:SetAtlas("Legacy-Rewards-Tracker-background")) then bg:SetColorTexture(0.04, 0.04, 0.04, 1) end
        local dim = f:CreateTexture(nil, "BACKGROUND", nil, -3)
        dim:SetAllPoints(bg); dim:SetColorTexture(0, 0, 0, 0.3)
    end
    frame = f
    f:SetSize(ns.W, H)
    local pos = ns.db.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
    f:SetFrameStrata("MEDIUM"); f:SetToplevel(true)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true); f:SetClampRectInsets(-16, 16, 16, -16)   -- 16px edge padding
    f:Hide()
    SyncEscape()
    local title = _G[f:GetName() .. "TitleText"]
    if type(title) ~= "table" then title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOP", 0, -6) end
    title:SetText(TAB_LABEL)
    local tb = CreateFrame("Frame", nil, f)
    tb:SetPoint("TOPLEFT"); tb:SetPoint("TOPRIGHT", -28, 0); tb:SetHeight(22)
    tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        ns.db.pos = { p, rp, x, y }
    end)

    -- tabs under the frame, like the character window's
    f.Tabs = tabButtons
    for i, tab in ipairs(ns.tabs) do
        local okT, b = pcall(CreateFrame, "Button", f:GetName() .. "Tab" .. i, f, "PanelTabButtonTemplate")
        if not okT or not b then b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); b:SetSize(110, 24) end
        b:SetID(i); b:SetText(tab.name)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
        b:SetScript("OnClick", function() Select(i) end)
        tabButtons[i] = b
    end
    if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, f, #ns.tabs) end
    -- a tab's shown() (optional) is asked on every show: hidden tabs drop out of the row, a hidden current tab falls back to the first
    f:SetScript("OnShow", function()
        local prev
        for i, tab in ipairs(ns.tabs) do
            local b, on = tabButtons[i], not tab.shown or tab.shown() and true or false
            b:SetShown(on and not tab.nobar); b:ClearAllPoints()
            if prev then b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 3, 0) else b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2) end
            if on then if not tab.nobar then prev = b end elseif current == i then current = 1 end
        end
        Select(current or 1)
    end)
end

function ns.Toggle()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end
FT.OpenProfessions = function(name) return ns.Open(name) end
-- show the window on the tab named name
function ns.Open(name)
    if not frame then Build() end
    for i, tab in ipairs(ns.tabs) do if tab.name == name then current = i end end
    if frame:IsShown() then Select(current) else frame:Show() end
end

-- The button on Blizzard's profession window: below its profession side tabs (ProfessionsFrame.Professions<i>Tab,
-- each 2 px under the previous), same size and art. No side tabs (another client): right of .TabSystem / under the
-- frame, spellbook skill-line-tab look. Not part of any Blizzard tab system: it only opens our window.
local function LastSideTab(pf)
    local last
    for i = 1, 20 do
        local t = pf["Professions" .. i .. "Tab"]
        if type(t) ~= "table" then break end
        if t:IsShown() then last = t end
    end
    if not last and type(pf.rightProfessionTabs) == "table" then   -- newer client: the list Naowh Forever docks
        for _, t in ipairs(pf.rightProfessionTabs) do if type(t) == "table" and t:IsShown() then last = t end end
    end
    return last
end
-- copy a side tab texture's art and size onto ours (centered: never round-trip GetPoint on this client)
local function CopyArt(dst, src)
    if type(src) ~= "table" then return end
    local atlas = src.GetAtlas and src:GetAtlas()
    if atlas then dst:SetAtlas(atlas) elseif src.GetTexture and src:GetTexture() then
        dst:SetTexture(src:GetTexture())
        if src.GetTexCoord then dst:SetTexCoord(src:GetTexCoord()) end
    else return end
    dst:ClearAllPoints(); dst:SetPoint("CENTER"); dst:SetSize(src:GetWidth(), src:GetHeight())
    return true
end
local function PlaceBzTab()
    local b, pf = ns.bzTab, ProfessionsFrame
    if not b then return end
    b:ClearAllPoints()
    if ns.bzDE then
        ns.bzDE:ClearAllPoints(); ns.bzDE:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
        ns.bzDE:SetShown(ns.KnowsDisenchant and ns.KnowsDisenchant() or false)
    end
    local last = LastSideTab(pf)
    ns.bzTabAnchor = last    -- for debugging
    if last then
        b:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
        if b.native then return end    -- Blizzard's template: its own size and art
        local w, h = last:GetWidth() or 0, last:GetHeight() or 0
        if w > 10 and h > 10 then b:SetSize(w, h) end
        if CopyArt(b.bg, last.Background) then
            if type(last.Icon) == "table" then
                b.icon:ClearAllPoints(); b.icon:SetPoint("CENTER"); b.icon:SetSize(last.Icon:GetWidth(), last.Icon:GetHeight())
            end
            return
        end
    else
        local sys = type(pf.TabSystem) == "table" and pf.TabSystem or nil
        if sys then b:SetPoint("TOPLEFT", sys, "TOPRIGHT", 3, 0) else b:SetPoint("TOPLEFT", pf, "BOTTOMLEFT", 12, 2) end
        if b.native then return end    -- no side tab shown yet (re-placed a frame later); template keeps its own art
        b:SetSize(32, 32)
    end
    local s = (b:GetWidth() or 32) / 32
    b.bg:SetSize(64 * s, 64 * s); b.bg:ClearAllPoints(); b.bg:SetPoint("TOPLEFT", -3 * s, 11 * s)
end
local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local function AddBlizzardTab()
    local pf = ProfessionsFrame
    if ns.bzTab or type(pf) ~= "table" then return end
    -- Blizzard's own side tab template (as Professions<i>Tab): its art, cropped + masked icon, hover, press offset
    local okT, t = pcall(CreateFrame, "Frame", nil, pf, "LargeSideTabButtonTemplate")
    if okT and t and type(t.Icon) == "table" and t.SetCustomOnMouseUpHandler then
        t.native, t.tooltipText, t.fillToInterior = true, TAB_LABEL, true
        t.Icon:SetTexture(ICON); t:SetChecked(false)
        t:SetCustomOnMouseUpHandler(function(_, btn, inside) if btn == "LeftButton" and inside ~= false then ns.Toggle() end end)
        ns.bzTab = t
    else
        local b = CreateFrame("Button", nil, pf)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(); b.icon:SetTexture(ICON)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() ns.Toggle() end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(TAB_LABEL); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ns.bzTab = b
    end
    -- a second side tab under it: the Disenchant list (only for characters who know Disenchant)
    if ns.bzTab.native then
        local d = CreateFrame("Frame", nil, pf, "LargeSideTabButtonTemplate")
        d.native, d.tooltipText, d.fillToInterior = true, "Disenchant", true
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(13262) or GetSpellTexture and GetSpellTexture(13262)
        d.Icon:SetTexture(tex or ICON); d:SetChecked(false)
        d:SetCustomOnMouseUpHandler(function(_, btn, inside) if btn == "LeftButton" and inside ~= false then ns.Open("Disenchant") end end)
        ns.bzDE = d
    end
    -- Naowh Forever fades ProfessionsFrame to alpha 0 under its own window and keeps Blizzard's side tabs drawn with
    -- SetIgnoreParentAlpha: ours (anchored under the last side tab) do the same, or they vanish with the frame
    for _, t in ipairs({ ns.bzTab, ns.bzDE }) do if t.SetIgnoreParentAlpha then t:SetIgnoreParentAlpha(true) end end
    PlaceBzTab()
    -- side tabs may appear late or change count: place again on show (and a frame later, once laid out)
    pf:HookScript("OnShow", function() PlaceBzTab(); C_Timer.After(0, PlaceBzTab) end)
    pf:HookScript("OnShow", SyncEscape)
    pf:HookScript("OnHide", function() if frame then frame:Hide() end; SyncEscape() end)
end
ns.On("ADDON_LOADED", function(name) if name == "Blizzard_Professions" then AddBlizzardTab() end end)

-- the Doud's UI page: this module has no settings, only a way in without a profession window
function ns.Panel(page)
    local y = FT.Section(page, -32, "Professions")
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(220, 26); b:SetPoint("TOPLEFT", 18, y); b:SetText("Open " .. TAB_LABEL)
    b:SetScript("OnClick", function() ns.Toggle() end)
    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")   -- help text, like the other pages
    fs:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -12); fs:SetWidth(460); fs:SetJustifyH("LEFT")
    fs:SetText("Also a tab on the profession window. Prices: Auctionator.")
end

-- minimap button (named *Button* child of Minimap, so MinimapTweaks' button collector picks it up): click toggles the
-- window, drag moves it round the minimap edge (ProfessionsDB.mmAngle, degrees)
local function MinimapButton()
    if not Minimap or _G.DoudProfessionsMinimapButton then return end
    local b = CreateFrame("Button", "DoudProfessionsMinimapButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local ic = b:CreateTexture(nil, "BACKGROUND")
    ic:SetSize(20, 20); ic:SetPoint("TOPLEFT", 7, -5); ic:SetTexture(ICON); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local bd = b:CreateTexture(nil, "OVERLAY")
    bd:SetSize(53, 53); bd:SetPoint("TOPLEFT"); bd:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local function Place()
        local a = math.rad(ns.db.mmAngle or 200)
        local r = (Minimap:GetWidth() or 140) / 2 + 5
        b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            ns.db.mmAngle = math.deg(math.atan2(cy / sc - my, cx / sc - mx)); Place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function() ns.Toggle() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText(TAB_LABEL)
        GameTooltip:AddLine("Click: open / close. Drag: move.", 1, 1, 1); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
end

function ns.OnLoad()
    ns.db = FT.InitDB("ProfessionsDB", { chars = {}, sales = {}, vendor = {}, scanned = {}, fav = {}, hidden = {}, deIgnore = {}, deObs = {} })
    AddBlizzardTab()     -- already loaded (another addon opened it first)
    MinimapButton()
end

end)
