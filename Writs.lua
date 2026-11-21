-- Writs tab: which Craftsman's Writ gets trade-faction reputation (Azeroth Commerce Authority / Durotar Supply and
-- Logistics, same amount both sides) cheapest. Per writ: its AH price + the requested item (the cheaper of its AH price and
-- its craft cost from the Recipes data) = total, then total / rep. Writs are dailies: done today = dimmed. Prices from Auctionator.
-- Writ ids, quest ids and requested items read from the client's ItemSparse (name match, lowest id); rep per writ as seen in
-- game. Idea from WaylaidCost (Shakam, no license): own code. Gold paid on hand-in unknown: not counted.
-- "Items in bags first" (ProfessionsDB.writBags): a writ or requested item in your bags is free, writs you can hand in sort first.
-- Click a row with the AH open: Auctionator shopping list "Doud: <item>" (writ + what's missing), searched. Shift+click: link the writ.
local _, FT = ...
FT.Module("Professions", function(...)
local ADDON, ns = ...

-- { writ itemID, quest ID, requested itemID, rep, count (default 1) }
ns.WRITS = {
    { 264049, 94249, 7048, 75 },  -- Azure Silk Hood
    { 264045, 94245, 4254, 75 },  -- Barbaric Gloves
    { 264036, 94236, 4380, 75 },  -- Big Bronze Bomb
    { 264027, 94227, 3848, 75 },  -- Big Bronze Knife
    { 264048, 94248, 6263, 75 },  -- Blue Overalls
    { 264053, 94253, 10048, 75 },  -- Colorful Kilt
    { 264037, 94237, 8069, 75, 200 },  -- Crafted Solid Shot
    { 264044, 94244, 4252, 75 },  -- Dark Leather Shoulders
    { 264041, 94241, 2317, 75 },  -- Dark Leather Tunic
    { 264019, 94219, 5996, 75 },  -- Draught of Water Breathing
    { 264018, 94218, 8951, 75 },  -- Elixir of Defense
    { 264016, 94216, 3390, 75 },  -- Elixir of Lesser Agility
    { 264011, 94004, 3391, 75 },  -- Elixir of Ogre's Strength
    { 264012, 94212, 3383, 75 },  -- Elixir of Wisdom
    { 264030, 94230, 4384, 75 },  -- Explosive Sheep
    { 264039, 94239, 5958, 75 },  -- Fine Leather Pants
    { 264015, 94215, 5634, 75 },  -- Free Action Potion
    { 264035, 94235, 7506, 75 },  -- Gnomish Universal Remote
    { 264021, 94221, 11128, 75 },  -- Golden Rod
    { 264054, 94254, 6264, 75 },  -- Greater Adept's Robe
    { 264028, 94228, 3484, 75 },  -- Green Iron Boots
    { 264026, 94226, 3485, 75 },  -- Green Iron Gauntlets
    { 264024, 94224, 3491, 75 },  -- Heavy Bronze Mace
    { 264038, 94238, 18662, 75 },  -- Heavy Leather Ball
    { 264043, 94243, 7371, 75 },  -- Heavy Quiver
    { 264040, 94240, 7349, 75 },  -- Herbalist's Gloves
    { 264022, 94222, 5541, 75 },  -- Iridescent Hammer
    { 264013, 94213, 3385, 75 },  -- Lesser Mana Potion
    { 264017, 94217, 3388, 75 },  -- Lesser Troll's Blood Elixir
    { 264047, 94247, 5766, 75 },  -- Lesser Wizard's Robe
    { 264032, 94232, 4381, 75 },  -- Minor Recombobulator
    { 264031, 94231, 4383, 75 },  -- Moonsight Rifle
    { 264029, 94229, 5507, 75 },  -- Ornate Spyglass
    { 264020, 94220, 5540, 75 },  -- Pearl-Handled Dagger
    { 264051, 94251, 4317, 75 },  -- Phoenix Pants
    { 264042, 94242, 7358, 75 },  -- Pilferer's Gloves
    { 264033, 94233, 6712, 75 },  -- Practice Lock
    { 264046, 94246, 7284, 75 },  -- Red Whelp Gloves
    { 264052, 94252, 4313, 75 },  -- Red Woolen Boots
    { 264025, 94225, 2865, 75 },  -- Rough Bronze Leggings
    { 264034, 94234, 4373, 75 },  -- Shadow Goggles
    { 264014, 94214, 6048, 75 },  -- Shadow Protection Potion
    { 264023, 94223, 15869, 75 },  -- Silver Skeleton Key
    { 264050, 94250, 4245, 75 },  -- Small Silk Pack
    { 264055, 94255, 4321, 75 },  -- Spider Silk Slippers
    { 264081, 94281, 4392, 125 },  -- Advanced Target Dummy
    { 264100, 94300, 8201, 125 },  -- Big Voodoo Mask
    { 264101, 94301, 8200, 125 },  -- Big Voodoo Robe
    { 264110, 94310, 9998, 125 },  -- Black Mageweave Vest
    { 264072, 94272, 7942, 125 },  -- Blue Glittering Axe
    { 264060, 94260, 10592, 125 },  -- Catseye Draught
    { 264084, 94284, 10501, 125 },  -- Catseye Ultra Goggles
    { 264114, 94314, 10042, 125 },  -- Cindercloth Robe
    { 264092, 94292, 8174, 125 },  -- Comfortable Leather Hat
    { 264082, 94282, 4393, 125 },  -- Craftsman's Monocle
    { 264106, 94306, 7063, 125 },  -- Crimson Silk Robe
    { 264091, 94291, 16005, 125 },  -- Dark Iron Bomb
    { 264094, 94294, 7378, 125 },  -- Dusky Bracers
    { 264115, 94315, 7061, 125 },  -- Earthen Silk Belt
    { 264066, 94266, 8949, 125 },  -- Elixir of Agility
    { 264108, 94308, 22246, 125 },  -- Enchanted Mageweave Pouch
    { 264087, 94287, 10500, 125 },  -- Fire Goggles
    { 264063, 94263, 6049, 125 },  -- Fire Protection Potion
    { 264086, 94286, 4852, 125 },  -- Flash Bomb
    { 264056, 94256, 6050, 125 },  -- Frost Protection Potion
    { 264083, 94283, 4395, 125 },  -- Goblin Land Mine
    { 264065, 94265, 9061, 125 },  -- Goblin Rocket Fuel
    { 264074, 94274, 3837, 125 },  -- Golden Scale Coif
    { 264078, 94278, 9366, 125 },  -- Golden Scale Gauntlets
    { 264061, 94261, 5633, 125 },  -- Great Rage Potion
    { 264093, 94293, 5965, 125 },  -- Guardian Cloak
    { 264089, 94289, 10498, 125 },  -- Gyromatic Micro-Adjuster
    { 264079, 94279, 7941, 125 },  -- Heavy Mithril Axe
    { 264069, 94269, 9060, 125 },  -- Inlaid Mithril Cylinder
    { 264057, 94257, 3823, 125 },  -- Lesser Invisibility Potion
    { 264058, 94258, 4623, 125 },  -- Lesser Stoneshield Potion
    { 264104, 94304, 10050, 125 },  -- Mageweave Bag
    { 264062, 94262, 3827, 125 },  -- Mana Potion
    { 264080, 94280, 4396, 125 },  -- Mechanical Dragonling
    { 264090, 94290, 11590, 125 },  -- Mechanical Repair Kit
    { 264088, 94288, 10514, 125 },  -- Mithril Frag Bomb
    { 264073, 94273, 3853, 125 },  -- Moonsteel Broadsword
    { 264059, 94259, 6052, 125 },  -- Nature Protection Potion
    { 264099, 94299, 8192, 125 },  -- Nightscape Shoulders
    { 264112, 94312, 10052, 125 },  -- Orange Martial Shirt
    { 264071, 94271, 7928, 125 },  -- Ornate Mithril Shoulders
    { 264097, 94297, 8217, 125 },  -- Quickdraw Quiver
    { 264111, 94311, 10009, 125 },  -- Red Mageweave Pants
    { 264064, 94264, 3824, 125 },  -- Shadow Oil
    { 264105, 94305, 10023, 125 },  -- Shadoweave Gloves
    { 264107, 94307, 10004, 125 },  -- Shadoweave Robe
    { 264075, 94275, 7964, 125 },  -- Solid Sharpening Stone
    { 264109, 94309, 4329, 125 },  -- Star Belt
    { 264068, 94268, 7922, 125 },  -- Steel Plate Helm
    { 264070, 94270, 6041, 125 },  -- Steel Weapon Chain
    { 264098, 94298, 7391, 125 },  -- Swift Boots
    { 264103, 94303, 8218, 125 },  -- Thick Leather Ammo Pouch
    { 264077, 94277, 11144, 125 },  -- Truesilver Rod
    { 264102, 94302, 8189, 125 },  -- Turtle Scale Breastplate
    { 264085, 94285, 10560, 125 },  -- Unstable Trigger
    { 264113, 94313, 10008, 125 },  -- White Bandit Mask
    { 264076, 94276, 7943, 125 },  -- Wicked Mithril Blade
    { 264095, 94295, 8214, 125 },  -- Wild Leather Helmet
    { 264096, 94296, 8210, 125 },  -- Wild Leather Shoulders
    { 264067, 94267, 9144, 125 },  -- Wildvine Potion
    { 264132, 94332, 15872, 200 },  -- Arcanite Skeleton Key
    { 264157, 94357, 22251, 200 },  -- Cenarion Herb Bag
    { 264148, 94348, 15075, 200 },  -- Chimeric Vest
    { 264130, 94330, 20549, 200 },  -- Darkrune Gauntlets
    { 264124, 94324, 246948, 200 },  -- Distilled Firewater
    { 264119, 94319, 9233, 200 },  -- Draught of Detect Demon
    { 264117, 94317, 12190, 200 },  -- Dreamless Sleep Potion
    { 264133, 94333, 7947, 200 },  -- Ebon Shiv
    { 264156, 94356, 14108, 200 },  -- Felcloth Boots
    { 264139, 94339, 18232, 200 },  -- Field Repair Bot 74A
    { 264121, 94321, 13513, 200 },  -- Flask of Chromatic Resistance
    { 264151, 94351, 15071, 200 },  -- Frostsaber Boots
    { 264159, 94359, 14141, 200 },  -- Ghostweave Vest
    { 264120, 94320, 9088, 200 },  -- Gift of Arthas
    { 264137, 94337, 18645, 200 },  -- Gnomish Alarm-O-Bot
    { 264138, 94338, 18587, 200 },  -- Goblin Jumper Cables XL
    { 264144, 94344, 18258, 200 },  -- Gordok Ogre Suit
    { 264118, 94318, 13457, 200 },  -- Greater Fire Protection Potion
    { 264135, 94335, 10504, 200 },  -- Green Lens
    { 264149, 94349, 15080, 200 },  -- Heavy Scorpid Helm
    { 264131, 94331, 12775, 200 },  -- Huge Thorium Battleaxe
    { 264129, 94329, 12422, 200 },  -- Imperial Plate Chest
    { 264136, 94336, 15996, 200 },  -- Lifelike Mechanical Toad
    { 264122, 94322, 3387, 200 },  -- Limited Invulnerability Potion
    { 264123, 94323, 18253, 200 },  -- Major Rejuvenation Potion
    { 264134, 94334, 16023, 200 },  -- Masterwork Target Dummy
    { 264128, 94328, 7969, 200 },  -- Mithril Spurs
    { 264127, 94327, 7929, 200 },  -- Orcish War Leggings
    { 264116, 94316, 9224, 200 },  -- Potion of Demonslaying
    { 264126, 94326, 12416, 200 },  -- Radiant Belt
    { 264125, 94325, 12417, 200 },  -- Radiant Circlet
    { 264153, 94353, 14046, 200 },  -- Runecloth Bag
    { 264154, 94354, 13864, 200 },  -- Runecloth Boots
    { 264150, 94350, 15092, 200 },  -- Runic Leather Bracers
    { 264146, 94346, 15094, 200 },  -- Runic Leather Headband
    { 264158, 94358, 10025, 200 },  -- Shadoweave Mask
    { 264141, 94341, 10548, 200 },  -- Sniper Scope
    { 264160, 94360, 21340, 200 },  -- Soul Pouch
    { 264142, 94342, 21277, 200 },  -- Tranquil Mechanical Yeti
    { 264140, 94340, 18631, 200 },  -- Truesilver Transformer
    { 264155, 94355, 10036, 200 },  -- Tuxedo Jacket
    { 264145, 94345, 15053, 200 },  -- Volcanic Breastplate
    { 264147, 94347, 15084, 200 },  -- Wicked Leather Bracers
    { 264143, 94343, 15087, 200 },  -- Wicked Leather Pants
    { 264152, 94352, 14130, 200 },  -- Wizardweave Turban
}

local function Have(id) local ok, n = pcall(GetItemCount, id); return ok and tonumber(n) or 0 end
local crafts    -- output itemID -> recipe (Recipes data + live scans), built on first use
local function CraftCost(id)
    if not crafts then
        crafts = {}
        for _, r in pairs(ns.AllRecipes()) do if r[3] ~= 0 then crafts[r[3]] = crafts[r[3]] or r end end
    end
    local r = crafts[id]
    local c = r and ns.Calc(r)
    return c and c / math.max(r[4], 1)
end
-- { id, quest, item, n, rep, writ (price, 0 held with bags), have, unit, crafted (unit is the craft cost), cost (item, missing
-- count only with bags), ah / craft (both prices for that count), total, per, ready (all in bags), done (today), active (in the quest log) }
local function Row(w, bags)
    local n = w[5] or 1
    local r = { id = w[1], quest = w[2], item = w[3], n = n, rep = w[4], have = math.min(Have(w[3]), n) }
    r.writ = bags and Have(w[1]) > 0 and 0 or ns.AHPrice(w[1])
    local ah, craft = ns.AHPrice(w[3]), CraftCost(w[3])
    r.unit, r.crafted = ah, nil
    if craft and (not ah or craft < ah) then r.unit, r.crafted = craft, true end
    local buy = bags and n - r.have or n
    r.cost = buy == 0 and 0 or r.unit and r.unit * buy
    r.ah, r.craft = ah and ah * buy, craft and craft * buy
    r.ready = r.have == n and Have(w[1]) > 0
    if r.writ and r.cost then r.total = r.writ + r.cost; r.per = r.total / r.rep end
    local Q = C_QuestLog
    r.done = Q and Q.IsQuestFlaggedCompleted and Q.IsQuestFlaggedCompleted(w[2]) or nil
    r.active = Q and Q.IsOnQuest and Q.IsOnQuest(w[2]) or nil
    return r
end
function ns.WritRows(bags)
    crafts = nil    -- recipes/scans may have changed
    local list = {}
    for _, w in ipairs(ns.WRITS) do list[#list + 1] = Row(w, bags) end
    return list
end
local function Item(id) local c, n = ns.ItemColor(id), ns.ItemName(id); return c and c .. n .. "|r" or n end
local function Name(id) return (ns.ItemName(id):gsub("^Craftsman's Writ: ", "")) end

-- click: shopping list of the writ + the requested item's missing count, searched; nothing while the AH is closed
function ns.WritShop(r)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.CreateShoppingList) then FT.Print("Auctionator not loaded") return end
    local want = {}
    if Have(r.id) == 0 then want[1] = { r.id, 1 } end
    if r.n - Have(r.item) > 0 then want[#want + 1] = { r.item, r.n - Have(r.item) } end
    if #want == 0 then FT.Print("all in bags") return end
    local terms, strs = {}, {}
    for _, w in ipairs(want) do
        local nm = ns.ItemName(w[1])
        if nm == "item " .. w[1] then FT.Print("item names still loading, try again") return end
        terms[#terms + 1] = { searchString = nm, isExact = true, quantity = w[2] }
        strs[#strs + 1] = api.ConvertToSearchString("DoudUI", terms[#terms])
    end
    local ok, err = pcall(api.CreateShoppingList, "DoudUI", "Doud: " .. Name(r.id), strs)
    if not ok then FT.Print("shopping list failed: " .. tostring(err)) return end
    if api.MultiSearchAdvanced then pcall(api.MultiSearchAdvanced, "DoudUI", terms) end
end

table.insert(ns.tabs, { name = "Writs", build = function(page)
    local function M(k) return function(r) return ns.Money(r[k]) end end
    local function V(k) return function(r) return r[k] end end
    local function Pick(k, crafted)    -- the price the total uses in green
        return function(r) return ns.Money(r[k], r[k] and r.cost ~= 0 and (r.crafted or false) == crafted and "|cff40ff40" or nil) end
    end
    local cols = {
        { title = "Writ", width = 0, value = function(r) return Name(r.id) end, text = function(r) return Name(r.id) end,
          icons = function(r) return { ns.ItemIcon(r.item) } end,
          tag = function(r)
              return r.done and "done today" or r.active and "in log"
                  or ns.db.writBags and (r.have == r.n and "in bags" or r.have > 0 and r.have .. "/" .. r.n) or nil
          end },
        { title = "Rep", width = 60, right = true, desc = true, value = V("rep") },
        { title = "Writ price", width = 120, right = true, value = V("writ"), text = M("writ") },
        { title = "AH price", width = 120, right = true, value = V("ah"), text = Pick("ah", false) },
        { title = "Crafted", width = 120, right = true, value = V("craft"), text = Pick("craft", true) },
        { title = "Total", width = 120, right = true, value = V("total"), text = M("total") },
        { title = "Per rep", width = 110, right = true, value = V("per"), text = M("per") },
    }
    local used = 46    -- the Writ column takes what's left of the window width (scrollbar 14 + margins 32)
    for i = 2, #cols do used = used + cols[i].width end
    cols[1].width = math.max(200, ns.W - used)
    local note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("RIGHT", page, "TOPRIGHT", -10, -20)
    local t = ns.Table(page, cols, 29, nil, 6, false, {
        rowTip = function(r)
            GameTooltip:AddLine(Item(r.id))
            GameTooltip:AddLine(("%d trade reputation"):format(r.rep), 1, 0.82, 0)
            GameTooltip:AddDoubleLine((r.n > 1 and r.n .. " " or "") .. Item(r.item), ns.Money(r.cost), 1, 1, 1, 1, 1, 1)
            local ah, craft = ns.AHPrice(r.item), CraftCost(r.item)
            GameTooltip:AddDoubleLine("   AH", ns.Money(ah and ah * r.n), 0.6, 0.6, 0.6, 1, 1, 1)
            GameTooltip:AddDoubleLine("   Craft (reagents)", ns.Money(craft and craft * r.n), 0.6, 0.6, 0.6, 1, 1, 1)
            if r.done then GameTooltip:AddLine("Done today", 0.5, 0.5, 0.5) end
            GameTooltip:AddLine("Total = writ + item (cheaper of AH and craft)", 0.6, 0.6, 0.6)
            GameTooltip:AddLine("Click (AH open): Auctionator shopping list + search. Shift+click: link in chat", 0.6, 0.6, 0.6)
        end,
        click = function(r, btn)
            if btn ~= "LeftButton" then return end
            if not IsShiftKeyDown() then ns.WritShop(r) return end
            local ok, _, link = pcall(C_Item and C_Item.GetItemInfo or GetItemInfo, r.id)
            if ok and link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end,
        dim = function(r) return r.done end,
        pin = function(r) return ns.db.writBags and r.ready and not r.done or nil end })
    t:SetPoint("TOPLEFT", 4, -44)
    page.table = t
    local kb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    kb:SetSize(24, 24); kb:SetPoint("TOPLEFT", 6, -10); kb:SetChecked(ns.db.writBags and true or false)
    kb:SetScript("OnClick", function(self) ns.db.writBags = self:GetChecked() and true or nil; page.Refresh() end)
    local kl = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    kl:SetPoint("LEFT", kb, "RIGHT", 0, 1); kl:SetText("Items in bags first (count as free)")
    page.bagsBox = kb
    page.Refresh = function()
        t:SetRows(ns.WritRows(ns.db.writBags))
        note:SetText(Auctionator and Auctionator.API and "Cheapest Craftsman's Writs per trade reputation. Prices from Auctionator."
            or "|cffff6060Auctionator not loaded: no AH prices.|r")
    end
    local queued
    local function Later()
        if queued or not page:IsVisible() then return end
        queued = true
        C_Timer.After(1, function() queued = false; if page:IsVisible() then page.Refresh() end end)
    end
    ns.On("GET_ITEM_INFO_RECEIVED", function(_, ok) if ok then Later() end end)
    ns.On("BAG_UPDATE_DELAYED", Later)
    ns.On("QUEST_TURNED_IN", Later)
end })

end)
