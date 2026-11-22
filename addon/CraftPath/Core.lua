-- CraftPath core: data model, skill detection, pricing, saved variables, events and slash commands.

local ADDON, ns = ...
local R = ns.RAW

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format, tinsert = string.format, table.insert

ns.VERSION = "2.0.0"
ns.MAX_SKILL = 300

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------

-- Step: {from, to, name, itemID, yield, learn, yellow, green, grey, source, pattern, crafts,
--        mats, sale, saleType, soldPerDay, vendorPerCraft, reagents, thin, ahValue, listed, ahUsable}
local function ParseRoute(raw)
  local out = {}
  for i, r in ipairs(raw or {}) do
    out[i] = {
      index = i, from = r[1], to = r[2], name = r[3], item = (r[4] and r[4] ~= 0) and r[4] or nil, yield = r[5] or 1,
      learn = r[6], y = r[7], g = r[8], gr = r[9],
      src = r[10], pat = r[11] or 0, crafts = r[12],
      mats = r[13], sale = r[14], how = r[15], sold = r[16], vend = r[17] or 0,
      reag = r[18] or {}, thin = r[19] == 1, ahVal = r[20], listed = r[21], ahOk = r[22] == 1,
    }
  end
  return out
end

-- Gold: {name, itemID, yield, learn, source, mats, sale, soldPerDay, flag, reputation, pattern, reagents}
local function ParseGold(raw)
  local out = {}
  for i, r in ipairs(raw or {}) do
    out[i] = {
      name = r[1], item = r[2], yield = r[3] or 1, learn = r[4], src = r[5], mats = r[6], sale = r[7],
      sold = r[8], flag = r[9] ~= "" and r[9] or nil, rep = r[10] ~= "" and r[10] or nil, pat = r[11] or 0, reag = r[12] or {},
    }
  end
  return out
end

local PROF_DEFS = {
  { key = "alchemy", name = "Alchemy", skillLines = { 171 }, icon = "Interface\\Icons\\Trade_Alchemy", color = { 0.30, 0.86, 0.66 },
    match = { "alchemy", "alchimie", "alquimia", "alchimia" } },
  { key = "blacksmithing", name = "Blacksmithing", skillLines = { 164 }, icon = "Interface\\Icons\\Trade_BlackSmithing", color = { 0.52, 0.68, 0.92 },
    match = { "blacksmithing", "schmiedekunst", "forge", "herrería", "herreria", "forgiatura", "ferraria" } },
  { key = "enchanting", name = "Enchanting", skillLines = { 333 }, icon = "Interface\\Icons\\Trade_Engraving", color = { 0.68, 0.55, 1.00 },
    match = { "enchanting", "verzauberkunst", "enchantement", "encantamiento", "incantamento", "encantamento" } },
  { key = "engineering", name = "Engineering", skillLines = { 202 }, icon = "Interface\\Icons\\Trade_Engineering", color = { 0.98, 0.76, 0.26 },
    match = { "engineering", "ingenieurskunst", "ingénierie", "ingenierie", "ingeniería", "ingenieria", "ingegneria", "engenharia" } },
  { key = "leatherworking", name = "Leatherworking", skillLines = { 165 }, icon = "Interface\\Icons\\Trade_LeatherWorking", color = { 0.86, 0.60, 0.36 },
    match = { "leatherworking", "lederverarbeitung", "travail du cuir", "peletería", "peleteria", "conciatura", "couraria" } },
  { key = "tailoring", name = "Tailoring", skillLines = { 197 }, icon = "Interface\\Icons\\Trade_Tailoring", color = { 0.93, 0.45, 0.72 },
    match = { "tailoring", "schneiderei", "couture", "sastrería", "sastreria", "sartoria", "alfaiataria" } },
  { key = "cooking", name = "Cooking", skillLines = { 185 }, icon = "Interface\\Icons\\INV_Misc_Food_15", color = { 1.00, 0.52, 0.32 },
    match = { "cooking", "kochkunst", "cuisine", "cocina", "cucina", "culinária", "culinaria" } },
  { key = "first-aid", name = "First Aid", skillLines = { 129 }, icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", color = { 0.98, 0.42, 0.42 },
    match = { "first aid", "erste hilfe", "secourisme", "primeros auxilios", "primo soccorso", "primeiros socorros" } },
}

ns.PROFS = {}
ns.PROF_BY_KEY = {}
for _, d in ipairs(PROF_DEFS) do
  local data = R.profs and R.profs[d.key]
  if data then
    d.routes = { best = ParseRoute(data.best), trainer = ParseRoute(data.trainer) }
    d.gold = ParseGold(data.gold)
    d.alts = {}
    for i, r in ipairs(data.alts or {}) do d.alts[i] = ParseRoute(r) end
    d.fam = data.fam
    if #d.routes.trainer == 0 then d.routes.trainer = d.routes.best end
    ns.PROFS[#ns.PROFS + 1] = d
    ns.PROF_BY_KEY[d.key] = d
  end
end

ns.SOURCE = {
  T = { label = "TRAINER", long = "Trainer", color = { 0.45, 0.66, 1.00 } },
  V = { label = "VENDOR", long = "Vendor recipe", color = { 1.00, 0.70, 0.32 } },
  D = { label = "DROP", long = "Drop pattern", color = { 0.92, 0.50, 0.92 } },
  Q = { label = "QUEST", long = "Quest reward", color = { 0.95, 0.85, 0.40 } },
  P = { label = "PATTERN", long = "Pattern from the AH", color = { 0.40, 0.85, 0.85 } },
  R = { label = "REP", long = "Reputation recipe", color = { 0.95, 0.45, 0.62 } },
  U = { label = "UNKNOWN", long = "Unknown source", color = { 0.60, 0.62, 0.66 } },
  ["?"] = { label = "PATTERN", long = "Pattern", color = { 0.40, 0.85, 0.85 } },
}
setmetatable(ns.SOURCE, { __index = function(t) return t.U end })

---------------------------------------------------------------------------
-- API compatibility (Forever runs on the modern client, but stay defensive)
---------------------------------------------------------------------------

local issecret = issecretvalue or function() return false end

function ns.ItemIcon(id)
  local icon
  if C_Item and C_Item.GetItemIconByID then
    local ok, v = pcall(C_Item.GetItemIconByID, id)
    if ok then icon = v end
  end
  if not icon and GetItemIcon then
    local ok, v = pcall(GetItemIcon, id)
    if ok then icon = v end
  end
  return icon or 134400
end

-- steps without an item (enchants) use their recipe name and the profession icon
function ns.StepIcon(st, key)
  if st.item then return ns.ItemIcon(st.item) end
  local p = key and ns.PROF_BY_KEY[key]
  return p and p.icon or 134400
end
function ns.StepName(st)
  if st.item then return ns.ItemName(st.item) end
  return st.name or "?"
end

function ns.ItemInfo(id)
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(id) end
  if GetItemInfo then return GetItemInfo(id) end
end

function ns.ItemLink(id)
  local _, link = ns.ItemInfo(id)
  return link
end

function ns.ItemCount(id)
  local n
  if C_Item and C_Item.GetItemCount then
    local ok, v = pcall(C_Item.GetItemCount, id, true)
    if ok then n = v end
  elseif GetItemCount then
    local ok, v = pcall(GetItemCount, id, true)
    if ok then n = v end
  end
  if type(n) ~= "number" or issecret(n) then return 0 end
  return n
end

function ns.RequestItem(id)
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- display name: the route uses recipe names for results; reagents use the client's (localised) name when known
function ns.ItemName(id, preferClient)
  if preferClient then
    local name = ns.ItemInfo(id)
    if type(name) == "string" and name ~= "" then return name end
  end
  if not id then return "?" end
  return R.names[id] or ("item:" .. tostring(id))
end

function ns.InsertLink(id)
  if not id then return false end
  local link = ns.ItemLink(id)
  if not link then return false end
  local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
  if insert then
    local ok, res = pcall(insert, link)
    return ok and res ~= false
  end
  return false
end

---------------------------------------------------------------------------
-- Skill math
---------------------------------------------------------------------------

-- chance of a skill-up at skill s (orange = 100%, then linear down to grey)
function ns.Chance(st, s)
  if not s or s < st.learn or s >= st.gr then return 0 end
  if s < st.y then return 1 end
  return (st.gr - s) / (st.gr - st.y)
end

-- expected number of crafts to go from skill a to skill b with this recipe
function ns.Crafts(st, a, b)
  local n = 0
  for s = a, b - 1 do
    local p = ns.Chance(st, s)
    if p > 0 then n = n + 1 / p end
  end
  return n
end

function ns.Difficulty(st, s)
  if not s then return "none" end
  if s < st.learn then return "red" end
  if s < st.y then return "orange" end
  if s < st.g then return "yellow" end
  if s < st.gr then return "green" end
  return "grey"
end

ns.DIFF_LABEL = { red = "Skill too low", orange = "Orange", yellow = "Yellow", green = "Green", grey = "Grey", none = "Unknown" }

function ns.CurrentIndex(route, skill)
  if not skill then return nil end
  for i, st in ipairs(route) do
    if skill < st.to then return i end
  end
  return #route + 1
end

---------------------------------------------------------------------------
-- Prices (snapshot, optionally live from Auctionator)
---------------------------------------------------------------------------

local function LivePrice(id)
  if not id or not (ns.db and ns.db.livePrices) then return nil end
  -- Auctionator prices only count while they are fresh (seen today or yesterday); older ones lose to the website data
  if ns.AtrPrice then
    local p, age = ns.AtrPrice(id)
    if p and (age == nil or age <= 1) then return p end
    return nil
  end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID) then return nil end
  local ok, v = pcall(api.GetAuctionPriceByItemID, ADDON, id)
  if ok and type(v) == "number" and v > 0 and not issecret(v) then return v end
  return nil
end
ns.LivePrice = LivePrice

function ns.HasLivePrices()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  return (ns.db and ns.db.livePrices and api and api.GetAuctionPriceByItemID) and true or false
end

-- price for one unit, and whether it came from live data
function ns.UnitPrice(id)
  local snap = R.price[id]
  if snap and snap[2] == "V" then return snap[1], false end -- vendor items: fixed price
  local live = LivePrice(id)
  local bolt = R.bolts and R.bolts[id]
  if bolt then
    local clothLive = LivePrice(bolt[1])
    local clothSnap = R.price[bolt[1]] and R.price[bolt[1]][1]
    local viaCloth = (clothLive or clothSnap) and (clothLive or clothSnap) * bolt[2]
    local direct = live or (snap and snap[2] ~= "craft" and snap[1]) or nil
    local best = direct and viaCloth and min(direct, viaCloth) or direct or viaCloth or (snap and snap[1]) or 0
    return best, (live or clothLive) and true or false
  end
  if live then return live, true end
  return snap and snap[1] or 0, false
end

function ns.MatsCost(entry)
  local total, live = 0, false
  for _, r in ipairs(entry.reag) do
    local p, isLive = ns.UnitPrice(r[1])
    total = total + p * r[2]
    live = live or isLive
  end
  return total, live
end

-- the AH's cut of a sale (5% on the faction AH, 15% on the neutral AH; set on the website)
function ns.Cut()
  local f = R.filters
  return ((f and f.cut) or 5) / 100
end

-- value of one craft after the AH cut, or the vendor price when that is better
function ns.SaleValue(entry)
  local yield = entry.yield or 1
  local live = LivePrice(entry.item)
  if live and (entry.ahOk ~= false or entry.ahVal == nil) then
    local v = live * yield * (1 - ns.Cut())
    if entry.vend and entry.vend > v then return entry.vend, false end
    return v, true
  end
  return entry.sale or 0, false
end

-- age of the price data in seconds (based on the AH scan time)
function ns.Now()
  if GetServerTime then local ok, v = pcall(GetServerTime); if ok and type(v) == "number" then return v end end
  return time and time() or 0
end
function ns.DataAge()
  local ts = R.scannedTs or R.generatedTs
  local now = ns.Now()
  if not ts or ts == 0 or not now or now == 0 then return nil end
  return max(0, now - ts)
end
function ns.AgeText(sec)
  if not sec then return "unknown" end
  if sec < 90 then return "just now" end
  local m = floor(sec / 60 + 0.5)
  if m < 60 then return m .. " min ago" end
  local h = floor(sec / 3600)
  if h < 48 then return h .. " h ago" end
  return floor(h / 24) .. " days ago"
end
function ns.WebURL(key, skill)
  local base = R.url or ""
  if key then
    base = base .. "/#" .. key
    if skill then base = base .. "/" .. skill end
  end
  return base
end

function ns.Profit(entry)
  local cost, l1 = ns.MatsCost(entry)
  local sale, l2 = ns.SaleValue(entry)
  return sale - cost, cost, sale, (l1 or l2)
end

-- compact money string with coloured unit letters, e.g. "2g 06s".
-- digitColor (optional "|cffrrggbb") colours the numbers; every segment is closed on its own,
-- so the string can be embedded in other text without nesting colour codes.
local GOLD, SILVER, COPPER = "|cffffd24a", "|cffc9ced8", "|cffe3a46b"
function ns.Money(c, signed, digitColor)
  c = c or 0
  local neg = c < 0
  c = floor(abs(c) + 0.5)
  local g, s, cc = floor(c / 10000), floor(c / 100) % 100, c % 100
  local function D(txt) return digitColor and (digitColor .. txt .. "|r") or txt end
  local txt
  if g >= 100 then
    txt = D(format("%d", g)) .. GOLD .. "g|r"
  elseif g > 0 then
    txt = D(format("%d", g)) .. GOLD .. "g|r " .. D(format("%02d", s)) .. SILVER .. "s|r"
  elseif s >= 10 then
    txt = D(format("%d", s)) .. SILVER .. "s|r"
  elseif s > 0 then
    txt = D(format("%d", s)) .. SILVER .. "s|r " .. D(format("%02d", cc)) .. COPPER .. "c|r"
  else
    txt = D(format("%d", cc)) .. COPPER .. "c|r"
  end
  if neg then return D("-") .. txt end
  if signed then return D("+") .. txt end
  return txt
end

function ns.Num(n)
  if n >= 10 then return format("%d", floor(n + 0.5)) end
  return (format("%.1f", n):gsub("%.0$", ""))
end

---------------------------------------------------------------------------
-- Skill detection
---------------------------------------------------------------------------

local function MatchProf(skillLine, name)
  for _, p in ipairs(ns.PROFS) do
    if skillLine then
      for _, id in ipairs(p.skillLines) do
        if id == skillLine then return p.key end
      end
    end
  end
  if type(name) == "string" and not issecret(name) then
    local lower = name:lower()
    for _, p in ipairs(ns.PROFS) do
      for _, m in ipairs(p.match) do
        if lower:find(m, 1, true) then return p.key end
      end
    end
  end
  return nil
end
ns.MatchProf = MatchProf

local function SetSkill(key, rank, maxRank, source)
  if type(rank) ~= "number" or issecret(rank) or rank <= 0 then return false end
  local cur = ns.char.skills[key]
  local changed = not cur or cur.rank ~= rank
  ns.char.skills[key] = { rank = rank, max = (type(maxRank) == "number" and not issecret(maxRank)) and maxRank or (cur and cur.max) or ns.MAX_SKILL, src = source }
  if changed and cur and rank > cur.rank then ns.char.lastProf = key end
  return changed
end

function ns.ScanSkills()
  if not ns.char then return false end
  local changed = false
  local found = {}

  if GetProfessions and GetProfessionInfo then
    local ok, a, b, c, d, e = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ a, b, c, d, e }) do
        local ok2, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
        if ok2 and name then
          local key = MatchProf(skillLine, name)
          if key and not found[key] then
            found[key] = true
            changed = SetSkill(key, rank, maxRank, "api") or changed
          end
        end
      end
    end
  end

  if GetNumSkillLines and GetSkillLineInfo then
    local ok, n = pcall(GetNumSkillLines)
    if ok and type(n) == "number" then
      for i = 1, n do
        local ok2, name, isHeader, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
        if ok2 and name and not isHeader then
          local key = MatchProf(nil, name)
          if key and not found[key] then
            found[key] = true
            changed = SetSkill(key, rank, maxRank, "api") or changed
          end
        end
      end
    end
  end

  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    for _, p in ipairs(ns.PROFS) do
      if not found[p.key] then
        for _, id in ipairs(p.skillLines) do
          local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
          if ok and type(info) == "table" and type(info.skillLevel) == "number" and info.skillLevel > 0 then
            found[p.key] = true
            changed = SetSkill(p.key, info.skillLevel, info.maxSkillLevel, "api") or changed
            break
          end
        end
      end
    end
  end

  return changed
end

-- read the profession window that is open right now (modern and classic APIs)
function ns.ScanTradeSkill()
  if not ns.char then return nil end
  local key
  if C_TradeSkillUI then
    for _, fn in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
      local f = C_TradeSkillUI[fn]
      if f then
        local ok, info = pcall(f)
        if ok and type(info) == "table" then
          local k = MatchProf(info.profession or info.professionID, info.professionName or info.parentProfessionName)
          if k then
            key = k
            SetSkill(k, info.skillLevel, info.maxSkillLevel, "api")
            break
          end
        end
      end
    end
  end
  if not key and GetTradeSkillLine then
    local ok, name, rank, maxRank = pcall(GetTradeSkillLine)
    if ok then
      local k = MatchProf(nil, name)
      if k then
        key = k
        SetSkill(k, rank, maxRank, "api")
      end
    end
  end
  if key then ns.char.lastProf = key end
  return key
end

-- "Your skill in %s has increased to %d." -> Lua pattern
local function BuildPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local s = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
  s = s:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  s = s:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
  return "^" .. s .. "$"
end
ns.BuildPattern = BuildPattern

local SKILL_UP_PATTERN
function ns.ParseSkillMessage(msg)
  if type(msg) ~= "string" or issecret(msg) then return false end
  SKILL_UP_PATTERN = SKILL_UP_PATTERN or BuildPattern(SKILL_RANK_UP or "Your skill in %s has increased to %d.")
  if not SKILL_UP_PATTERN then return false end
  local name, rank = msg:match(SKILL_UP_PATTERN)
  if not name then return false end
  local key = MatchProf(nil, name)
  if not key then return false end
  local changed = SetSkill(key, tonumber(rank), nil, "chat")
  ns.char.lastProf = key
  return changed
end

function ns.GetSkill(key)
  local s = ns.char and ns.char.skills[key]
  if s then return s.rank, s.max, s.src end
  return nil
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local DEFAULTS = {
  point = { "CENTER", "CENTER", 0, 40 },
  scale = 1.0,
  tab = "tailoring",
  mode = "route",
  variant = {},
  budget = { mode = "off", gold = 0, ahSales = false },
  livePrices = true,
  tooltip = true,
  mini = { shown = true, point = { "TOP", "TOP", 0, -140 }, prof = "auto" },
  minimap = { hide = false, angle = 200 },
}

local CHAR_DEFAULTS = {
  skills = {},
  expanded = {},
  lastProf = nil,
}

local function CopyDefaults(src, dst)
  if type(dst) ~= "table" then dst = {} end
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = CopyDefaults(v, dst[k])
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end
ns.CopyDefaults = CopyDefaults

-- gold you want to plan with (copper), or nil when the budget is off
function ns.Budget()
  local b = ns.db and ns.db.budget
  if not b or b.mode == "off" then return nil end
  if b.mode == "manual" then return b.gold or 0 end
  if GetMoney then
    local ok, v = pcall(GetMoney)
    if ok and type(v) == "number" and not issecret(v) then return v end
  end
  return nil
end

-- what the rest of a route costs from this skill: peak gold needed and net result
-- (buy mats for ~5 crafts at a time; crafted items count at vendor price right away, or with ahSales at their AH value,
-- capped at a day's volume like the rest of the addon)
-- reach: the skill you get to before `budget` runs out (end of the route if it never does)
function ns.RestCalc(route, skill, ahSales, budget)
  skill = skill or 1
  local learned, c, peak, net, reach = {}, 0, 0, 0, nil
  for _, st in ipairs(route) do if st.from < skill then learned[st.name] = true end end
  for _, st in ipairs(route) do
    if skill < st.to then
      local a = max(skill, st.from)
      local full = ns.Crafts(st, st.from, st.to)
      local n = full > 0 and (st.crafts or full) * ns.Crafts(st, a, st.to) / full or 0
      local mats = n * (st.mats or 0)
      local pat = (not learned[st.name]) and (st.pat or 0) or 0
      learned[st.name] = true
      local val = 0
      if st.how == "AH" then
        local n1 = min(n, st.sold or 0)
        val = n1 * (st.sale or 0) + (n - n1) * (st.vend or 0)
      elseif st.how == "vendor" then
        val = n * (st.sale or 0)
      end
      -- buy mats for ~5 crafts at a time; sell them before buying more (AH beyond a day's volume at vendor price)
      local left, soldAH, first, cap = n, 0, true, (st.how == "AH") and (st.sold or 0) or 0
      local pos, span = a, st.to - a
      while left > 1e-9 do
        local b = min(5, left)
        c = c + b * (st.mats or 0) + (first and pat or 0)
        first = false
        if c > peak then peak = c end
        if not reach and budget and c > budget then reach = floor(pos) end
        local v = 0
        if st.how == "none" then
          v = 0
        elseif ahSales and st.how == "AH" then
          local a2 = max(0, min(b, cap - soldAH))
          v = a2 * (st.sale or 0) + (b - a2) * (st.vend or 0)
          soldAH = soldAH + a2
        else
          v = b * (st.vend or 0)
        end
        c = c - v
        left = left - b
        if n > 0 then pos = pos + span * b / n end
      end
      net = net + val - mats - pat
    end
  end
  if not reach then reach = (#route > 0) and route[#route].to or 300 end
  return peak, net, max(skill, reach)
end

-- the route to show: the normal one, or the best one from the budget family that fits your gold
function ns.Route(key)
  local p = ns.PROF_BY_KEY[key]
  local v = (ns.db and ns.db.variant[key]) or "best"
  local base = p.routes[v] or p.routes.best
  local budget = ns.Budget()
  if not budget or not (p.fam and p.fam[v]) then return base, v, nil end
  local skill = ns.GetSkill(key) or 1
  local sales = ns.db.budget.ahSales == true
  local ck = table.concat({ v, skill, budget, tostring(sales) }, "|")
  if p.bcache and p.bcache.key == ck then return p.bcache.route, v, p.bcache.info end
  local seen, best, bestPeak, bestNet, farR, farPeak, farNet, farReach = {}, nil, nil, nil, nil, nil, nil, nil
  for _, idx in ipairs(p.fam[v]) do
    local r = (idx == 0) and base or p.alts[idx]
    if r and not seen[r] then
      seen[r] = true
      local peak, net, reach = ns.RestCalc(r, skill, sales, budget)
      if peak <= budget and (not best or net > bestNet) then best, bestPeak, bestNet = r, peak, net end
      -- nothing fits: the route that gets you furthest on the gold you have (then the one needing the least)
      if not farR or reach > farReach or (reach == farReach and peak < farPeak) then
        farR, farPeak, farNet, farReach = r, peak, net, reach
      end
    end
  end
  local defPeak, defNet = ns.RestCalc(base, skill, sales)
  -- the normal route wins whenever it fits, so a big budget never changes anything
  if defPeak <= budget then best, bestPeak, bestNet = base, defPeak, defNet end
  local info = { budget = budget, fits = best ~= nil, defPeak = defPeak, defNet = defNet }
  if not best then best, bestPeak, bestNet, info.reach = farR, farPeak, farNet, farReach end
  info.peak, info.net, info.default = bestPeak, bestNet, best == base
  p.bcache = { key = ck, route = best, info = info }
  return best, v, info
end

-- the profession the mini tracker should follow
function ns.TrackedProf()
  local pref = ns.db.mini.prof
  if pref and ns.PROF_BY_KEY[pref] then return pref end
  if ns.char.lastProf and ns.PROF_BY_KEY[ns.char.lastProf] then return ns.char.lastProf end
  local tab = ns.db.tab
  if ns.PROF_BY_KEY[tab] then return tab end
  for _, p in ipairs(ns.PROFS) do if ns.GetSkill(p.key) then return p.key end end
  return ns.PROFS[1] and ns.PROFS[1].key or "tailoring"
end

---------------------------------------------------------------------------
-- Refresh scheduling
---------------------------------------------------------------------------

local pending = false
function ns.RequestRefresh(scan)
  if scan then ns.needScan = true end
  if pending then return end
  pending = true
  local function run()
    pending = false
    if ns.needScan then
      ns.needScan = false
      ns.ScanSkills()
    end
    if ns.UI and ns.UI.Refresh then ns.UI:Refresh() end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.15, run) else run() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ns.eventFrame = ev

local function SafeRegister(event)
  pcall(ev.RegisterEvent, ev, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end
    CraftPathDB = CopyDefaults(DEFAULTS, CraftPathDB)
    CraftPathCharDB = CopyDefaults(CHAR_DEFAULTS, CraftPathCharDB)
    ns.db, ns.char = CraftPathDB, CraftPathCharDB
    if ns.db.tab == "gold" then ns.db.tab = ns.db.goldProf or "tailoring"; ns.db.mode = "gold" end
    ns.db.goldProf = nil
    if ns.db.mode ~= "gold" then ns.db.mode = "route" end
    if not ns.PROF_BY_KEY[ns.db.tab] then ns.db.tab = ns.PROF_BY_KEY.tailoring and "tailoring" or (ns.PROFS[1] and ns.PROFS[1].key) end
  elseif event == "PLAYER_LOGIN" then
    for _, e in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "CHAT_MSG_SKILL",
                          "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "LEARNED_SPELL_IN_TAB", "PLAYER_MONEY" }) do
      SafeRegister(e)
    end
    ns.ScanSkills()
    if ns.InitTooltips then pcall(ns.InitTooltips) end
    if ns.InitAuctionator then pcall(ns.InitAuctionator) end
    if ns.UI and ns.UI.Init then ns.UI:Init() end
    ns.RequestRefresh(true)
  elseif event == "CHAT_MSG_SKILL" then
    local msg = ...
    if ns.ParseSkillMessage(msg) then ns.RequestRefresh(false) end
    ns.RequestRefresh(true)
  elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" or event == "PLAYER_MONEY" then
    ns.RequestRefresh(false)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
    local key = ns.ScanTradeSkill()
    if key and event == "TRADE_SKILL_SHOW" and ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then
      ns.UI:SelectTab(key, true)
    end
    ns.RequestRefresh(true)
  else
    ns.RequestRefresh(true)
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Print(msg)
  local frame = DEFAULT_CHAT_FRAME
  if frame then frame:AddMessage("|cffb48effCraftPath|r " .. msg) end
end
ns.Print = Print

local HELP = {
  "/cpath - show or hide the window",
  "/cpath mini - show or hide the mini tracker",
  "/cpath minimap - show or hide the minimap button",
  "/cpath skill tailoring 152 - set a skill by hand if it is not read automatically",
  "/cpath live - turn live Auctionator prices on or off",
  "/cpath scan - at the AH: search every item your route needs or makes in Auctionator, for exact prices",
  "/cpath list or /cpath list 225 - put the mats you still need (to that skill) in an Auctionator shopping list",
  "/cpath data - how old the price data is and how to update it",
  "/cpath gold auto, /cpath gold 150 or /cpath gold off - plan the route for your gold (auto = what you carry)",
  "/cpath sales - also count AH sales as you go when planning for your gold (on/off)",
  "/cpath tooltip - AH price and AH-or-vendor advice on item tooltips (on/off)",
  "/cpath web - link to this route on the website",
  "/cpath scale 1.1 - change the size (0.7 to 1.5)",
  "/cpath reset - move the windows back to the middle",
}

local ALIAS = { alch = "alchemy", bs = "blacksmithing", smith = "blacksmithing", ench = "enchanting", eng = "engineering", engi = "engineering",
  lw = "leatherworking", leather = "leatherworking", tailor = "tailoring", cook = "cooking", fa = "first-aid", firstaid = "first-aid",
  ["first-aid"] = "first-aid", ["first aid"] = "first-aid" }
local function ProfFromText(txt)
  txt = (txt or ""):lower()
  if ALIAS[txt] and ns.PROF_BY_KEY[ALIAS[txt]] then return ALIAS[txt] end
  if ns.PROF_BY_KEY[txt] then return txt end
  return MatchProf(nil, txt)
end
ns.ProfFromText = ProfFromText

local function Slash(input)
  input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = input:match("^(%S*)%s*(.-)$")
  local UI = ns.UI
  if cmd == "" then
    UI:Toggle()
  elseif cmd == "mini" then
    ns.db.mini.shown = not ns.db.mini.shown
    UI:Refresh()
  elseif cmd == "minimap" then
    ns.db.minimap.hide = not ns.db.minimap.hide
    UI:UpdateMinimapButton()
  elseif cmd == "live" then
    ns.db.livePrices = not ns.db.livePrices
    Print(ns.db.livePrices and "Live Auctionator prices are on." or "Using the prices from the website data.")
    UI:Refresh()
  elseif cmd == "scale" then
    local v = tonumber(rest)
    if v then
      ns.db.scale = max(0.7, min(1.5, v))
      UI:ApplyScale()
    else
      Print("Usage: /cpath scale 1.1")
    end
  elseif cmd == "skill" then
    local which, val = rest:match("^(.-)%s+(%d+)$")
    local key = which and ProfFromText(which)
    if key and tonumber(val) then
      SetSkill(key, tonumber(val), nil, "manual")
      ns.char.lastProf = key
      Print(format("%s set to %d.", ns.PROF_BY_KEY[key].name, tonumber(val)))
      UI:Refresh()
    else
      Print("Usage: /cpath skill tailoring 152  or  /cpath skill first aid 120")
    end
  elseif cmd == "data" then
    Print(format("Prices: %s, %s – AH scan %s%s.", R.source or "AHledger", R.market or "?", ns.AgeText(ns.DataAge()), R.asOf and R.asOf ~= "" and (" (" .. R.asOf .. ")") or ""))
    Print("New data every " .. (R.refreshMinutes or 30) .. " min on the website. With the updater running, type /reload to load it. Without it, download the addon again from:")
    Print(R.url or "?")
  elseif cmd == "web" then
    UI:ShowLink()
  elseif cmd == "scan" then
    if ns.ScanRoute then ns.ScanRoute() end
  elseif cmd == "list" or cmd == "shop" then
    if ns.ShoppingList then ns.ShoppingList(nil, tonumber(rest)) end
  elseif cmd == "tooltip" or cmd == "tooltips" then
    ns.db.tooltip = not (ns.db.tooltip ~= false)
    Print(ns.db.tooltip and "AH prices on item tooltips are on." or "AH prices on item tooltips are off.")
  elseif cmd == "gold" or cmd == "budget" then
    local b = ns.db.budget
    if rest == "off" then b.mode = "off"
    elseif rest == "" or rest == "auto" then b.mode = "auto"
    elseif tonumber(rest) then b.mode = "manual"; b.gold = floor(tonumber(rest) * 10000)
    else b.mode = "off" end
    Print(b.mode == "off" and "Budget off - showing the normal route." or (b.mode == "auto" and "Planning the route for the gold you carry." or ("Planning the route for " .. ns.Money(b.gold) .. ".")))
    UI:Refresh(true)
  elseif cmd == "sales" then
    ns.db.budget.ahSales = not ns.db.budget.ahSales
    Print(ns.db.budget.ahSales and "Gold planning counts AH sales as you go." or "Gold planning counts crafted items at vendor price (the safe way).")
    UI:Refresh()
  elseif cmd == "reset" then
    ns.db.point = { "CENTER", "CENTER", 0, 40 }
    ns.db.mini.point = { "TOP", "TOP", 0, -140 }
    ns.db.scale = 1.0
    UI:ResetPositions()
    Print("The windows are back in the middle.")
  else
    for _, line in ipairs(HELP) do Print(line) end
  end
end

SLASH_CRAFTPATH1 = "/cpath"
SLASH_CRAFTPATH2 = "/craftpath"
SlashCmdList["CRAFTPATH"] = Slash

-- Addon compartment (the addon menu next to the minimap)
function CraftPath_OnAddonCompartmentClick(_, button)
  if not ns.UI then return end
  if button == "RightButton" then
    ns.db.mini.shown = not ns.db.mini.shown
    ns.UI:Refresh()
  else
    ns.UI:Toggle()
  end
end

function CraftPath_OnAddonCompartmentEnter(_, frame)
  if not GameTooltip then return end
  GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
  GameTooltip:AddLine("CraftPath")
  GameTooltip:AddLine("Left-click: show the route", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("Right-click: mini tracker", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

function CraftPath_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
