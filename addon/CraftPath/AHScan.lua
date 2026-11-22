-- CraftPath + Auctionator:
--  * prices from your own Auctionator scans are used when they are from today (exact for your AH right now)
--  * "Scan" searches the AH (through Auctionator) for every item the rest of your route needs or makes
--  * "To list" puts the mats you still have to buy, minus what is in your bags and bank, in an Auctionator shopping list
local ADDON, ns = ...
local floor, ceil, max, min, format = math.floor, math.ceil, math.max, math.min, string.format
local issecret = issecretvalue or function() return false end

local function API() return Auctionator and Auctionator.API and Auctionator.API.v1 end
local function Print(msg) if ns.Print then ns.Print(msg) end end

function ns.HasAuctionator()
  local a = API()
  return (a and a.GetAuctionPriceByItemID) and true or false
end

-- Auctionator's price for one unit and how many days ago it was seen (0 = today), or nil
function ns.AtrPrice(id)
  local a = API()
  if not (id and a and a.GetAuctionPriceByItemID) then return nil end
  local ok, p = pcall(a.GetAuctionPriceByItemID, ADDON, id)
  if not ok or type(p) ~= "number" or issecret(p) or p <= 0 then return nil end
  local age
  if a.GetAuctionAgeByItemID then
    local ok2, v = pcall(a.GetAuctionAgeByItemID, ADDON, id)
    if ok2 and type(v) == "number" and not issecret(v) then age = v end
  end
  return p, age
end

---------------------------------------------------------------------------
-- What the rest of a route needs
---------------------------------------------------------------------------

-- crafted mats (bolts, …): what one craft makes and what it takes, from the website data
local function CraftOf(id)
  local R = ns.RAW or {}
  local c = R.crafts and R.crafts[id]
  if c then return c[1] or 1, c[2] end
  local b = R.bolts and R.bolts[id]
  if b then return 1, { { b[1], b[2] } } end
  return nil
end

-- skill the default shopping list goes to: the end of the current step and the two after it
function ns.ListTarget(route, skill)
  local cur = ns.CurrentIndex(route, skill) or 1
  local st = route[min(#route, cur + 2)]
  return st and st.to or 300
end

-- mats to buy from `skill` to `to` on a route: { [id] = qty }, mats to make yourself { [id] = qty }, and the steps' products
function ns.RouteNeeds(route, skill, to)
  local need, make, products = {}, {}, {}
  local function add(id, q, depth)
    local y, reag = CraftOf(id)
    if reag and depth < 3 then
      local n = ceil(q / y - 0.001)
      make[id] = (make[id] or 0) + n * y
      for _, r in ipairs(reag) do add(r[1], r[2] * n, depth + 1) end
    else
      need[id] = (need[id] or 0) + q
    end
  end
  for _, st in ipairs(route) do
    if st.to > skill and st.from < to then
      local crafts = ns.Crafts(st, max(skill, st.from), min(st.to, to))
      if crafts > 0 then
        for _, r in ipairs(st.reag) do add(r[1], ceil(crafts * r[2] - 0.001), 0) end
        if st.item and st.item > 0 then products[#products + 1] = st.item end
      end
    end
  end
  return need, make, products
end

---------------------------------------------------------------------------
-- Scan (search the AH for the route's items through Auctionator)
---------------------------------------------------------------------------

local function NameOf(id)
  local name = ns.ItemInfo and ns.ItemInfo(id)
  if type(name) == "string" and name ~= "" then return name end
  if ns.RequestItem then ns.RequestItem(id) end
  return nil
end

function ns.ScanRoute(key)
  local a = API()
  if not (a and (a.MultiSearchExact or a.MultiSearch)) then Print("Install Auctionator to scan prices from CraftPath."); return end
  if not ns.ahOpen then Print("Open the auction house first, then press Scan (or type /cpath scan)."); return end
  key = key or (ns.UI and ns.UI.tab) or (ns.db and ns.db.tab)
  if not (key and ns.PROF_BY_KEY[key]) then return end
  local route = ns.Route(key)
  local skill = ns.GetSkill(key) or 1
  local need, make, products = ns.RouteNeeds(route, skill, 300)
  local ids, seen = {}, {}
  local function push(id) if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  for id in pairs(need) do push(id) end
  for id in pairs(make) do push(id) end
  for _, id in ipairs(products) do push(id) end
  for _, g in ipairs(ns.PROF_BY_KEY[key].gold or {}) do
    push(g.item)
    for _, r in ipairs(g.reag) do push(r[1]) end
  end
  local names, missing = {}, 0
  for _, id in ipairs(ids) do
    local p = ns.RAW and ns.RAW.price and ns.RAW.price[id]
    if not (p and p[2] == "V") then -- vendor items have a fixed price
      local n = NameOf(id)
      if n then names[#names + 1] = n else missing = missing + 1 end
    end
    if #names >= 80 then break end
  end
  if #names == 0 then Print("Nothing to scan yet - try again in a second (item names are still loading)."); return end
  local fn = a.MultiSearchExact or a.MultiSearch
  local ok, err = pcall(fn, ADDON, names)
  if not ok then Print("Auctionator could not start the search: " .. tostring(err)); return end
  ns.lastScanAsk = ns.Now and ns.Now() or 0
  Print(format("Scanning %d items for %s in Auctionator's Shopping tab%s. Prices update in CraftPath as the results come in.",
    #names, ns.PROF_BY_KEY[key].name, missing > 0 and format(" (%d still loading - scan again for them)", missing) or ""))
end

---------------------------------------------------------------------------
-- Shopping list
---------------------------------------------------------------------------

local function SearchString(a, name, qty)
  if a.ConvertToSearchString then
    local ok, s = pcall(a.ConvertToSearchString, ADDON, { searchString = name, isExact = true, quantity = qty })
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  return '"' .. name .. '"'
end

function ns.ShoppingList(key, to)
  local a = API()
  if not (a and a.CreateShoppingList) then Print("Install Auctionator to make shopping lists from CraftPath."); return end
  key = key or (ns.UI and ns.UI.tab) or (ns.db and ns.db.tab)
  local p = key and ns.PROF_BY_KEY[key]
  if not p then return end
  local route = ns.Route(key)
  local skill = ns.GetSkill(key) or 1
  to = max(skill + 1, min(300, to or ns.ListTarget(route, skill)))
  local need = ns.RouteNeeds(route, skill, to)
  local rows, missing, total = {}, 0, 0
  for id, q in pairs(need) do
    local left = q - (ns.ItemCount and ns.ItemCount(id) or 0)
    if left > 0 then
      local name = NameOf(id)
      if name then
        rows[#rows + 1] = { name = name, qty = left }
        total = total + left * (ns.UnitPrice and ns.UnitPrice(id) or 0)
      else
        missing = missing + 1
      end
    end
  end
  if #rows == 0 and missing == 0 then Print(format("You already have every mat for %s %d-%d.", p.name, skill, to)); return end
  if #rows == 0 then Print("Item names are still loading - try again in a second."); return end
  table.sort(rows, function(x, y) return x.name < y.name end)
  local strings = {}
  for i, r in ipairs(rows) do strings[i] = SearchString(a, r.name, r.qty) end
  local listName = "CraftPath " .. p.name
  local ok, err = pcall(a.CreateShoppingList, ADDON, listName, strings)
  if not ok then Print("Auctionator could not make the list: " .. tostring(err)); return end
  Print(format("Auctionator list \"%s\": %d mats for skill %d-%d (about %s, after what you have in bags and bank)%s. Open Auctionator's Shopping tab to buy.",
    listName, #rows, skill, to, ns.Money(total), missing > 0 and format("; %d names still loading - make the list again", missing) or ""))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function ns.InitAuctionator()
  local a = API()
  if a and a.RegisterForDBUpdate then
    pcall(a.RegisterForDBUpdate, ADDON, function() if ns.RequestRefresh then ns.RequestRefresh(false) end end)
  end
end

local ev = CreateFrame("Frame")
ns.ahFrame = ev
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event)
  ns.ahOpen = (event == "AUCTION_HOUSE_SHOW")
  if ns.UI and ns.UI.Refresh and ns.UI.frame and ns.UI.frame:IsShown() then ns.UI:Refresh() end
end)
