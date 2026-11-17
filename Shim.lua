-- Doud's Professions: the Doud's UI Professions module (Modules/Professions/*, copied verbatim by build.sh) on its own.
-- Stands in for what DoudUI's Core.lua / Panel.lua give the module: FT.Module collects its chunks, our ADDON_LOADED
-- runs them with ("Professions", ns) then ns.OnLoad. No options page: /dprof toggles the window.
local ADDON, FT = ...
FT.BRAND = "Doud's Professions"
FT.FONT_CINZEL = "Interface\\AddOns\\" .. ADDON .. "\\fonts\\Cinzel-Medium.ttf"
local ns = { PATH = "Interface\\AddOns\\" .. ADDON .. "\\" }
local chunks = {}
function FT.Module(_, chunk) chunks[#chunks + 1] = chunk end
function FT.Print(msg) print("|cffffd100" .. FT.BRAND .. "|r: " .. msg) end
-- ponytail: copies of DoudUI Core.lua's ns.InitDB / Panel.lua's ns.Section / Core.lua's ns.SkinButton, keep in step
function FT.InitDB(name, DEFAULTS)
    local db = _G[name] or {}
    _G[name] = db
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    return db
end
function FT.Section(page, y, text)
    local fs = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y); fs:SetText(text)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25); line:SetHeight(1)
    line:SetPoint("TOPLEFT", 16, y - 16); line:SetPoint("TOPRIGHT", -16, y - 16)
    return y - 24
end
local function Tertiary(n)
    n = "common-button-tertiary-" .. n
    local ok, info = pcall(function() return C_Texture.GetAtlasInfo(n) end)
    return ok and info and n or nil
end
local SIZES, faces = { 12 }, {}
local function Face(size)
    if not faces[size] then
        local on, off = CreateFont("DoudProfChipFont" .. size), CreateFont("DoudProfChipFontDisabled" .. size)
        for f, c in pairs({ [on] = { 1, 0.82, 0 }, [off] = { 0.35, 0.34, 0.33 } }) do
            f:SetFont(FT.FONT_CINZEL, size, ""); f:SetTextColor(c[1], c[2], c[3])
            f:SetShadowColor(0, 0, 0, 1); f:SetShadowOffset(0, -1)
        end
        faces[size] = { on, off }
    end
    return faces[size][1], faces[size][2]
end
local skinned = setmetatable({}, { __mode = "k" })
function FT.SkinButton(b, isOn, off)
    local s, normal = skinned[b], Tertiary("normal")
    if s then s.set(not off) return s.paint end
    if off or not normal then return end
    local hoverA, downA = Tertiary("hover") or normal, Tertiary("depressed-normal") or normal
    local skin = b:CreateTexture(nil, "BACKGROUND", nil, 1); skin:SetAllPoints()
    local faded = { b.Left, b.Middle, b.Right, b:GetHighlightTexture() }
    for _, t in pairs(faded) do t:SetAlpha(0) end   -- pairs: Chips have no Left / Middle / Right
    local fonts = { b:GetNormalFontObject(), b:GetHighlightFontObject(), b:GetDisabledFontObject() }   -- Blizzard's, for off
    local hover, down
    local function paint()
        if s.off then return end
        local on; if isOn then on = isOn() else on = b:IsEnabled() end
        skin:SetAtlas(on and (down and downA or hover and hoverA) or normal)
        skin:SetAlpha(on and 1 or 0.35); skin:SetDesaturated(not on)
        local fs = b:GetFontString()
        if fs then if on then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.35, 0.34, 0.33) end end
    end
    s = { paint = paint }
    skinned[b] = s
    local function fit()   -- widest size whose capitals fit with 4px a side (pcall: sizes may be secret)
        pcall(function()
            local fs, w = b:GetFontString(), b:GetWidth() - 8
            for _, size in ipairs(SIZES) do
                local on, off = Face(size)
                b:SetNormalFontObject(on); b:SetHighlightFontObject(on); b:SetDisabledFontObject(off)
                if not (fs and w > 0) or fs:GetStringWidth() <= w then break end
            end
        end)
        paint()
    end
    local busy
    hooksecurefunc(b, "SetText", function(self, t)
        if busy or s.off then return end
        if type(t) == "string" and not t:find("|", 1, true) and t:upper() ~= t then s.text = t; busy = true; self:SetText(t:upper()); busy = false end
        fit()
    end)
    fit()
    local t = b:GetText(); if t then b:SetText(t) end
    b:HookScript("OnEnter", function() hover = true; paint() end)
    b:HookScript("OnLeave", function() hover, down = false, false; paint() end)
    b:HookScript("OnMouseDown", function() down = true; paint() end)
    b:HookScript("OnMouseUp", function() down = false; paint() end)
    for _, e in ipairs({ "OnEnable", "OnDisable", "OnShow" }) do b:HookScript(e, paint) end
    function s.set(on)
        if (not s.off) == on then return end
        s.off = not on or nil
        skin:SetShown(on)
        for _, t in pairs(faded) do t:SetAlpha(on and 0 or 1) end
        if on then local t = b:GetText(); if t then b:SetText(t) else fit() end return end   -- the SetText hook re-caps, fits, paints
        for i, m in ipairs({ "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject" }) do if fonts[i] then b[m](b, fonts[i]) end end
        local fs, f = b:GetFontString(), b:IsEnabled() and fonts[1] or fonts[3]
        if fs and f then fs:SetTextColor(f:GetTextColor()) end
        if s.text and b:GetText() == s.text:upper() then b:SetText(s.text) end
    end
    paint()
    return paint
end

local function Toggle() if ns.Toggle then ns.Toggle() end end
DoudProfessions_Toggle = Toggle
SLASH_DOUDPROFESSIONS1, SLASH_DOUDPROFESSIONS2 = "/dprof", "/doudprofessions"
SlashCmdList.DOUDPROFESSIONS = Toggle

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    local ok, err = true, nil
    for _, chunk in ipairs(chunks) do
        ok, err = pcall(chunk, "Professions", ns)
        if not ok then break end
    end
    if ok and ns.OnLoad then ok, err = pcall(ns.OnLoad) end
    if not ok then geterrorhandler()(err) end
    chunks = nil
end)
