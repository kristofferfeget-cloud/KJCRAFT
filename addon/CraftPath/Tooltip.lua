-- CraftPath: AH price and "AH or vendor?" on item tooltips.
-- Prices come from the website data (AHledger's price table for your market), or straight from the
-- AHledger addon when it is installed and has fresher prices.
local ADDON, ns = ...
local floor, max, format = math.floor, math.max, string.format

local CREDIT = "Prices from AHledger (ahledger.com)"
local C_GOOD, C_WARN, C_MUTE, C_ACC = "|cff5fd38a", "|cffffb347", "|cff9aa0ab", "|cffb48eff"

local function R() return ns.RAW or {} end

-- AH data for one item: median (copper per unit), sold per day (or nil), listed (or nil), scan time (unix, or nil)
local function AHData(id)
  local api, apiP = AHledgerAPI, nil
  if api and type(api.GetPrice) == "function" then
    local ok, p = pcall(api.GetPrice, id)
    if ok and type(p) == "table" and type(p.median) == "number" and p.median > 0 then apiP = p end
  end
  local updated = function(p) return type(p.updated) == "number" and p.updated or nil end
  -- the AHledger addon's own live prices first (kept fresh by AHledger sync)
  if apiP and not apiP.snapshot then return apiP.median, apiP.soldPerDay, apiP.quantity, updated(apiP) end
  local d = R()
  local row = d.ah and d.ah[id]
  if row and row[1] then return row[1], row[2] and row[2] / 10 or nil, row[3], (d.ahTs and d.ahTs > 0) and d.ahTs or d.scannedTs end
  if apiP then return apiP.median, apiP.soldPerDay, apiP.quantity, updated(apiP) end
  local snap = d.price and d.price[id]
  if snap and snap[2] == "AH" then return snap[1], snap[4], snap[3], d.scannedTs end
  local live = ns.LivePrice and ns.LivePrice(id)
  if live then return live, nil, nil, nil end
  return nil
end
ns.AHData = AHData

-- the verdict for one unit: "ah" / "slow" / "vendor", AH value after the cut, vendor price
function ns.SellAdvice(id)
  local median, sold, listed, ts = AHData(id)
  local vendor, quality, bindType = 0, 1, 0
  if GetItemInfo then
    local _, _, q, _, _, _, _, _, _, _, sell, _, _, bind = GetItemInfo(id)
    vendor, quality, bindType = sell or 0, q or 1, bind or 0
  end
  if not median then return nil end
  if bindType == 1 or bindType == 4 then return nil end -- soulbound on pickup / quest items: not for the AH
  local net = median * (1 - ns.Cut())
  local minSold = (R().filters and R().filters.minSold) or 3
  local verdict
  if vendor > 0 and vendor >= net then verdict = "vendor"
  elseif sold and sold < minSold then verdict = "slow"
  else verdict = "ah" end
  return { verdict = verdict, median = median, net = net, vendor = vendor, sold = sold, listed = listed, ts = ts, quality = quality }
end

local function AgeSuffix(ts)
  if not ts or ts <= 0 then return "" end
  local age = max(0, ns.Now() - ts)
  if age < 3 * 3600 then return "" end
  return " · " .. C_WARN .. "scan " .. ns.AgeText(age) .. "|r"
end

local function VerdictText(a)
  if a.verdict == "vendor" then return C_WARN .. "Vendor it|r" .. C_MUTE .. " – pays more than the AH|r" end
  if a.verdict == "slow" then
    return C_WARN .. "AH, but slow|r" .. C_MUTE .. format(" – only ~%s sold a day", a.sold < 1 and format("%.1f", a.sold) or floor(a.sold + 0.5)) .. "|r"
  end
  local gain = a.net - (a.vendor or 0)
  return C_GOOD .. "Sell on the AH|r" .. C_MUTE .. ((a.vendor or 0) > 0 and (" – " .. ns.Money(gain) .. " more than vendor") or "") .. "|r"
end

local function ItemID(tt, data)
  if data and type(data.id) == "number" then return data.id end
  if not tt.GetItem then return nil end
  local _, link = tt:GetItem()
  local id = link and link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

local function OnItem(tt, data)
  if tt.cpDone or not ns.db or ns.db.tooltip == false then return end
  if tt.IsForbidden and tt:IsForbidden() then return end
  local id = ItemID(tt, data)
  if not id then return end
  local a = ns.SellAdvice(id)
  if not a or a.quality == 0 then return end -- grey items always go to the vendor
  tt.cpDone, tt.cpAdvice = true, a
  -- the AHledger addon already shows the price (with its credit): only add the verdict
  local ahl = AHledgerAPI and type(AHledgerAPI.IsTooltipOn) == "function" and select(2, pcall(AHledgerAPI.IsTooltipOn))
  if ahl ~= true then
    local market = {}
    if a.sold then market[#market + 1] = (a.sold < 10 and format("%.1f", a.sold) or format("%d", floor(a.sold + 0.5))) .. "/day" end
    if a.listed then market[#market + 1] = a.listed .. " listed" end
    tt:AddDoubleLine(C_ACC .. "AH|r " .. C_MUTE .. table.concat(market, " · ") .. "|r", ns.Money(a.median), 1, 1, 1, 1, 1, 1)
  end
  tt:AddDoubleLine(VerdictText(a), a.vendor > 0 and (C_MUTE .. "vendor |r" .. ns.Money(a.vendor)) or "", 1, 1, 1, 1, 1, 1)
  if ahl ~= true then tt:AddLine(C_MUTE .. CREDIT .. "|r" .. AgeSuffix(a.ts), 1, 1, 1) end
  tt:Show()
end

-- stacks in your bags: what the whole stack is worth (the count is only known after SetBagItem returns)
local function StackCount(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then return info.stackCount end
  end
  if GetContainerItemInfo then
    local ok, _, count = pcall(GetContainerItemInfo, bag, slot)
    if ok then return count end
  end
  return nil
end

local function OnBagItem(tt, bag, slot)
  local a = tt.cpAdvice
  if not (tt.cpDone and a) or tt.cpStack then return end
  local n = StackCount(bag, slot)
  if not n or n < 2 then return end
  tt.cpStack = true
  local best = a.verdict == "vendor" and a.vendor or a.net
  tt:AddDoubleLine(C_MUTE .. "Stack of " .. n .. (a.verdict == "vendor" and " at the vendor" or " on the AH, after the cut") .. "|r", ns.Money(best * n), 1, 1, 1, 1, 1, 1)
  tt:Show()
end

local function Clear(tt) tt.cpDone, tt.cpAdvice, tt.cpStack = nil, nil, nil end

local hooked = {}
local function Hook(tt)
  if not tt or hooked[tt] then return end
  hooked[tt] = true
  pcall(tt.HookScript, tt, "OnTooltipCleared", Clear)
  pcall(tt.HookScript, tt, "OnHide", Clear)
  -- older clients: OnTooltipSetItem; newer ones: TooltipDataProcessor below (both are safe together)
  pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) OnItem(self) end)
end

function ns.InitTooltips()
  Hook(GameTooltip)
  Hook(ItemRefTooltip)
  if GameTooltip and GameTooltip.SetBagItem and hooksecurefunc then
    pcall(hooksecurefunc, GameTooltip, "SetBagItem", OnBagItem)
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt, data)
      if hooked[tt] then OnItem(tt, data) end
    end)
  end
end
