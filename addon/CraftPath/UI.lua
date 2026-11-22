-- CraftPath UI: main window (route and gold tips per profession), mini tracker, minimap button and website link.

local ADDON, ns = ...
local R = ns.RAW

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local format = string.format

local UI = {}
ns.UI = UI

---------------------------------------------------------------------------
-- Style
---------------------------------------------------------------------------

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONT_NUM = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

local C = {
  bg     = { 0.043, 0.047, 0.059, 0.97 },
  panel  = { 0.071, 0.077, 0.094, 1 },
  card   = { 0.094, 0.101, 0.122, 1 },
  line   = { 1, 1, 1, 0.07 },
  text   = { 0.93, 0.94, 0.96 },
  sub    = { 0.64, 0.67, 0.73 },
  mute   = { 0.44, 0.47, 0.53 },
  pos    = { 0.38, 0.87, 0.50 },
  neg    = { 0.97, 0.45, 0.45 },
  gold   = { 1.00, 0.82, 0.33 },
}

local DIFF = {
  red    = { 0.90, 0.28, 0.28 },
  orange = { 1.00, 0.53, 0.25 },
  yellow = { 1.00, 0.86, 0.15 },
  green  = { 0.33, 0.82, 0.33 },
  grey   = { 0.55, 0.56, 0.58 },
  none   = { 0.93, 0.94, 0.96 },
}

local W, H = 548, 700
local HEADER_H, TABS_H = 54, 36
local ROW_H, GOLD_ROW_H = 40, 48
local LIST_W = W - 24

local function Hex(c)
  return format("|cff%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

local function Tex(parent, layer, c, sub)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
  t:SetTexture(WHITE)
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  return t
end

local function Text(parent, size, color, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(font or FONT, size or 12, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.7)
  local c = color or C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

local function SetColor(fs, c, a)
  fs:SetTextColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function Border(f, c)
  local t = {}
  for i = 1, 4 do t[i] = Tex(f, "BORDER", c) end
  t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("TOPRIGHT"); t[1]:SetHeight(1)
  t[2]:SetPoint("BOTTOMLEFT"); t[2]:SetPoint("BOTTOMRIGHT"); t[2]:SetHeight(1)
  t[3]:SetPoint("TOPLEFT"); t[3]:SetPoint("BOTTOMLEFT"); t[3]:SetWidth(1)
  t[4]:SetPoint("TOPRIGHT"); t[4]:SetPoint("BOTTOMRIGHT"); t[4]:SetWidth(1)
  f.borderTex = t
  return t
end

local function SetBorderColor(f, c)
  for _, t in ipairs(f.borderTex or {}) do t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
end

local function Shadow(f, size)
  for i = 1, size or 6 do
    local s = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    s:SetTexture(WHITE)
    s:SetVertexColor(0, 0, 0, 0.055)
    s:SetPoint("TOPLEFT", -i, i)
    s:SetPoint("BOTTOMRIGHT", i, -i)
  end
end

local function Icon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.bg = Tex(f, "BACKGROUND", { 0, 0, 0, 0.6 })
  f.bg:SetAllPoints()
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("TOPLEFT", 1, -1)
  f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  Border(f, { 1, 1, 1, 0.12 })
  return f
end

local function MoneyText(fs, value, signed)
  fs:SetText(ns.Money(value, signed))
end

local function ProfitColor(v)
  if v > 50 then return C.pos elseif v < -50 then return C.neg end
  return C.sub
end

local function ShowItemTooltip(owner, id, lines, anchor, title)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  if id then
    local ok = false
    if GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, id) end
    if not ok then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id) end
  else
    GameTooltip:AddLine(title or "", 1, 1, 1)
  end
  if lines and #lines > 0 then
    GameTooltip:AddLine(" ")
    for _, l in ipairs(lines) do
      if l.right then
        GameTooltip:AddDoubleLine(l[1], l.right, 0.8, 0.8, 0.8, 1, 1, 1)
      else
        GameTooltip:AddLine(l[1], l[2] or 0.85, l[3] or 0.85, l[4] or 0.85, true)
      end
    end
  end
  GameTooltip:Show()
end

local function HideTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

-- small flat button with hover state
local function FlatButton(parent, w, h, label, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = Tex(b, "BACKGROUND", { 1, 1, 1, 0.05 })
  b.bg:SetAllPoints()
  b.text = Text(b, size or 11, C.sub, FONT, "CENTER")
  b.text:SetPoint("CENTER")
  b.text:SetText(label or "")
  b:SetScript("OnEnter", function(s)
    if not s.active then s.bg:SetVertexColor(1, 1, 1, 0.09) end
    if s.tip then
      GameTooltip:SetOwner(s, "ANCHOR_TOP")
      GameTooltip:AddLine(s.tip[1])
      for i = 2, #s.tip do GameTooltip:AddLine(s.tip[i], 0.8, 0.8, 0.8, true) end
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(s)
    if not s.active then s.bg:SetVertexColor(1, 1, 1, 0.05) end
    HideTooltip()
  end)
  function b:SetActive(on, accent)
    self.active = on
    if on then
      local a = accent or C.text
      self.bg:SetVertexColor(a[1], a[2], a[3], 0.22)
      SetColor(self.text, C.text)
    else
      self.bg:SetVertexColor(1, 1, 1, 0.05)
      SetColor(self.text, C.sub)
    end
  end
  return b
end

-- source badge: coloured label with tinted background
local function Badge(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(50, 15)
  f.bg = Tex(f, "BACKGROUND", { 1, 1, 1, 0.1 })
  f.bg:SetAllPoints()
  f.text = Text(f, 8.5, C.text, FONT, "CENTER")
  f.text:SetPoint("CENTER", 0, 0)
  function f:Set(label, c)
    self.text:SetText(label)
    SetColor(self.text, c)
    self.bg:SetVertexColor(c[1], c[2], c[3], 0.16)
    self:SetWidth(max(30, self.text:GetStringWidth() + 10))
  end
  return f
end

local function AccentOf(key)
  local p = ns.PROF_BY_KEY[key]
  return p and p.color or C.gold
end

---------------------------------------------------------------------------
-- Scroll list with a slim scrollbar
---------------------------------------------------------------------------

local function CreateScroll(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(LIST_W - 10, 1)
  scroll:SetScrollChild(child)
  scroll.child = child

  local track = CreateFrame("Frame", nil, parent)
  track:SetWidth(4)
  track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -2)
  track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 2)
  track.bg = Tex(track, "BACKGROUND", { 1, 1, 1, 0.04 })
  track.bg:SetAllPoints()
  scroll.track = track

  local thumb = CreateFrame("Button", nil, track)
  thumb:SetWidth(4)
  thumb.tex = Tex(thumb, "ARTWORK", { 1, 1, 1, 0.22 })
  thumb.tex:SetAllPoints()
  scroll.thumb = thumb

  function scroll:MaxScroll()
    return max(0, (self.child:GetHeight() or 0) - (self:GetHeight() or 0))
  end

  function scroll:UpdateThumb()
    local viewH = self:GetHeight() or 0
    local contentH = self.child:GetHeight() or 1
    local maxS = self:MaxScroll()
    if maxS <= 0 or viewH <= 0 then
      self.track:Hide()
      return
    end
    self.track:Show()
    local trackH = self.track:GetHeight() or viewH
    local thumbH = max(24, trackH * viewH / contentH)
    local pos = (self:GetVerticalScroll() or 0) / maxS
    self.thumb:SetHeight(thumbH)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOP", self.track, "TOP", 0, -pos * (trackH - thumbH))
  end

  function scroll:ScrollTo(v)
    v = max(0, min(self:MaxScroll(), v))
    self:SetVerticalScroll(v)
    self:UpdateThumb()
  end

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    self:ScrollTo((self:GetVerticalScroll() or 0) - delta * ROW_H * 1.5)
  end)
  scroll:SetScript("OnSizeChanged", function(self) self:UpdateThumb() end)

  thumb:SetScript("OnEnter", function(s) s.tex:SetVertexColor(1, 1, 1, 0.4) end)
  thumb:SetScript("OnLeave", function(s) if not s.dragging then s.tex:SetVertexColor(1, 1, 1, 0.22) end end)
  thumb:SetScript("OnMouseDown", function(s)
    local _, y = GetCursorPosition()
    s.dragging = true
    s.startY = y / s:GetEffectiveScale()
    s.startScroll = scroll:GetVerticalScroll() or 0
    s:SetScript("OnUpdate", function(self)
      local _, cy = GetCursorPosition()
      cy = cy / self:GetEffectiveScale()
      local trackH = scroll.track:GetHeight() or 1
      local thumbH = self:GetHeight() or 1
      local range = max(1, trackH - thumbH)
      scroll:ScrollTo(self.startScroll + (self.startY - cy) / range * scroll:MaxScroll())
    end)
  end)
  thumb:SetScript("OnMouseUp", function(s)
    s.dragging = false
    s:SetScript("OnUpdate", nil)
    s.tex:SetVertexColor(1, 1, 1, 0.22)
  end)

  return scroll
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------

function UI:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "CraftPathFrame", UIParent)
  self.frame = f
  f:SetSize(W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:Hide()
  Shadow(f, 7)
  f.bg = Tex(f, "BACKGROUND", C.bg)
  f.bg:SetAllPoints()
  Border(f, { 1, 1, 1, 0.09 })
  if UISpecialFrames then table.insert(UISpecialFrames, "CraftPathFrame") end

  -- header ---------------------------------------------------------------
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER_H)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() f:StartMoving() end)
  header:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    ns.db.point = { p, rp, x, y }
  end)
  self.accentLine = Tex(header, "ARTWORK", C.gold)
  self.accentLine:SetPoint("TOPLEFT", 1, -1)
  self.accentLine:SetPoint("TOPRIGHT", -1, -1)
  self.accentLine:SetHeight(2)

  self.headIcon = Icon(header, 30)
  self.headIcon:SetPoint("LEFT", 16, -2)
  self.title = Text(header, 15, C.text)
  self.title:SetPoint("TOPLEFT", self.headIcon, "TOPRIGHT", 11, 0)
  self.title:SetText("Craft" .. Hex(C.sub) .. "Path|r")
  self.subtitle = Text(header, 10.5, C.sub)
  self.subtitle:SetPoint("BOTTOMLEFT", self.headIcon, "BOTTOMRIGHT", 11, 0)

  local close = CreateFrame("Button", nil, header)
  close:SetSize(26, 26)
  close:SetPoint("RIGHT", -12, -2)
  close.lines = {}
  for i, deg in ipairs({ 45, -45 }) do
    local l = Tex(close, "ARTWORK", C.sub)
    l:SetSize(13, 1.6)
    l:SetPoint("CENTER")
    if l.SetRotation then l:SetRotation(math.rad(deg)) end
    close.lines[i] = l
  end
  if not close.lines[1].SetRotation then
    for _, l in ipairs(close.lines) do l:Hide() end
    local x = Text(close, 14, C.sub, FONT, "CENTER"); x:SetPoint("CENTER"); x:SetText("x")
  end
  close.bg = Tex(close, "BACKGROUND", { 1, 1, 1, 0 })
  close.bg:SetAllPoints()
  close:SetScript("OnEnter", function(s)
    s.bg:SetVertexColor(1, 1, 1, 0.08)
    for _, l in ipairs(s.lines) do l:SetVertexColor(1, 1, 1, 1) end
  end)
  close:SetScript("OnLeave", function(s)
    s.bg:SetVertexColor(1, 1, 1, 0)
    for _, l in ipairs(s.lines) do l:SetVertexColor(C.sub[1], C.sub[2], C.sub[3], 1) end
  end)
  close:SetScript("OnClick", function() f:Hide() end)

  -- tabs -------------------------------------------------------------------
  local tabs = CreateFrame("Frame", nil, f)
  tabs:SetPoint("TOPLEFT", 12, -HEADER_H)
  tabs:SetPoint("TOPRIGHT", -12, -HEADER_H)
  tabs:SetHeight(TABS_H)
  local div = Tex(f, "ARTWORK", C.line)
  div:SetPoint("TOPLEFT", 0, -(HEADER_H + TABS_H))
  div:SetPoint("TOPRIGHT", 0, -(HEADER_H + TABS_H))
  div:SetHeight(1)

  self.tabs = {}
  local tabDefs = {}
  for _, p in ipairs(ns.PROFS) do tabDefs[#tabDefs + 1] = { key = p.key, label = "", icon = p.icon, name = p.name } end
  local tabW = (W - 24) / #tabDefs
  for i, d in ipairs(tabDefs) do
    local b = CreateFrame("Button", nil, tabs)
    b:SetSize(tabW, TABS_H)
    b:SetPoint("LEFT", (i - 1) * tabW, 0)
    b.key = d.key
    b.bg = Tex(b, "BACKGROUND", { 1, 1, 1, 0 })
    b.bg:SetPoint("TOPLEFT", 2, -3)
    b.bg:SetPoint("BOTTOMRIGHT", -2, 3)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetTexture(d.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = Text(b, 12, C.sub)
    b.label:SetText(d.label)
    b.count = Text(b, 11, C.mute, FONT_NUM)
    b.under = Tex(b, "ARTWORK", C.gold)
    b.under:SetPoint("BOTTOMLEFT", 10, 0)
    b.under:SetPoint("BOTTOMRIGHT", -10, 0)
    b.under:SetHeight(2)
    b:SetScript("OnClick", function() UI:SelectTab(d.key) end)
    b:SetScript("OnEnter", function(s)
      if UI.tab ~= s.key then s.bg:SetVertexColor(1, 1, 1, 0.04) end
      if GameTooltip then
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(d.name)
        local sk = ns.GetSkill(d.key)
        GameTooltip:AddLine(sk and ("Your skill: " .. sk) or "Not found on this character (you can still look)", 0.8, 0.8, 0.8)
        GameTooltip:Show()
      end
    end)
    b:SetScript("OnLeave", function(s) if UI.tab ~= s.key then s.bg:SetVertexColor(1, 1, 1, 0) end; HideTooltip() end)
    self.tabs[d.key] = b
  end

  self:BuildProfPage()
  self:BuildGoldPage()

  -- footer -----------------------------------------------------------------
  local fl = Tex(f, "ARTWORK", C.line)
  fl:SetPoint("BOTTOMLEFT", 0, 30)
  fl:SetPoint("BOTTOMRIGHT", 0, 30)
  fl:SetHeight(1)
  self.footer = Text(f, 10, C.mute)
  self.footer:SetPoint("BOTTOMLEFT", 16, 10)
  if self.footer.SetWordWrap then self.footer:SetWordWrap(false) end
  self.liveBtn = FlatButton(f, 92, 18, "Live: off", 9.5)
  self.liveBtn:SetPoint("BOTTOMRIGHT", -12, 6)
  self.liveBtn:SetScript("OnClick", function()
    ns.db.livePrices = not ns.db.livePrices
    UI:Refresh()
  end)
  self.liveBtn.tip = { "Live prices", "Uses Auctionator's prices if it is installed and has scanned the AH. Otherwise the prices from the website data are used." }
  self.miniBtn = FlatButton(f, 70, 18, "Mini: on", 9.5)
  self.miniBtn:SetPoint("RIGHT", self.liveBtn, "LEFT", -6, 0)
  self.miniBtn:SetScript("OnClick", function()
    ns.db.mini.shown = not ns.db.mini.shown
    UI:Refresh()
  end)
  self.miniBtn.tip = { "Mini tracker", "A small window that shows the next step while you craft. Drag to move, click to open the route." }
  self.webBtn = FlatButton(f, 64, 18, "Website", 9.5)
  self.webBtn:SetPoint("RIGHT", self.miniBtn, "LEFT", -6, 0)
  self.webBtn:SetScript("OnClick", function() UI:ShowLink() end)
  self.webBtn.tip = { "Website", "Get a link to this route on the website, with live prices, filters and the shopping list." }
  self.footer:SetPoint("RIGHT", self.webBtn, "LEFT", -8, 0)
  -- Auctionator buttons (only at the auction house)
  self.listBtn = FlatButton(f, 52, 18, "To list", 9.5)
  self.listBtn:SetPoint("RIGHT", self.webBtn, "LEFT", -6, 0)
  self.listBtn:SetScript("OnClick", function() if ns.ShoppingList then ns.ShoppingList(UI.tab) end end)
  self.listBtn.tip = { "Shopping list", "Puts the mats for the current step and the two after it in an Auctionator shopping list, minus what you have in bags and bank. /cpath list 225 goes to a skill of your choice." }
  self.scanBtn = FlatButton(f, 46, 18, "Scan", 9.5)
  self.scanBtn:SetPoint("RIGHT", self.listBtn, "LEFT", -6, 0)
  self.scanBtn:SetScript("OnClick", function() if ns.ScanRoute then ns.ScanRoute(UI.tab) end end)
  self.scanBtn.tip = { "Scan prices", "Searches the AH in Auctionator for every mat and product left in this route (and the gold tips). CraftPath then uses those exact prices for today." }
  self.listBtn:Hide(); self.scanBtn:Hide()

  f:SetScript("OnShow", function() UI:Refresh(true) end)
  self:ApplyScale()
  self:ResetPositions(true)
end

---------------------------------------------------------------------------
-- Profession page
---------------------------------------------------------------------------

function UI:BuildProfPage()
  local f = self.frame
  local page = CreateFrame("Frame", nil, f)
  page:SetPoint("TOPLEFT", 0, -(HEADER_H + TABS_H))
  page:SetPoint("BOTTOMRIGHT", 0, 31)
  self.profPage = page

  -- summary
  self.skillText = Text(page, 30, C.text, FONT_NUM)
  self.skillText:SetPoint("TOPLEFT", 16, -14)
  self.skillMax = Text(page, 13, C.mute, FONT_NUM)
  self.skillMax:SetPoint("BOTTOMLEFT", self.skillText, "BOTTOMRIGHT", 3, 4)
  self.stepText = Text(page, 10.5, C.sub)
  self.stepText:SetPoint("TOPLEFT", self.skillText, "BOTTOMLEFT", 1, -3)

  self.varBest = FlatButton(page, 86, 22, "Best route", 10.5)
  self.varTrainer = FlatButton(page, 86, 22, "Trainer only", 10.5)
  self.goldBtn = FlatButton(page, 76, 22, "Gold tips", 10.5)
  self.varTrainer:SetPoint("TOPRIGHT", -16, -16)
  self.varBest:SetPoint("RIGHT", self.varTrainer, "LEFT", -4, 0)
  self.goldBtn:SetPoint("RIGHT", self.varBest, "LEFT", -10, 0)
  self.varBest.tip = { "Best route", "The cheapest way up, including vendor recipes and cheap patterns from the AH." }
  self.varTrainer.tip = { "Trainer only", "Trainer recipes as far as possible. Vendor or drop recipes only where the trainer has nothing that gives points." }
  self.goldBtn.tip = { "Gold tips", "What is worth crafting for gold in this profession right now." }
  self.goldBtn:SetScript("OnClick", function() UI:SetMode("gold") end)
  self.budgetBtn = FlatButton(page, 150, 18, "Budget: off", 9.5)
  self.budgetBtn:SetPoint("TOPRIGHT", -16, -44)
  self.budgetBtn:SetScript("OnClick", function()
    local b = ns.db.budget
    b.mode = (b.mode == "off") and "auto" or "off"
    UI:Refresh(true)
  end)
  self.budgetBtn.tip = { "Plan for your gold", "Picks the best route that never needs more gold than you have. Click: off / the gold you carry. Type /cpath gold 150 for a fixed amount. Crafted items count at vendor price; /cpath sales also counts AH sales." }
  self.varBest:SetScript("OnClick", function() UI:SetVariant("best") end)
  self.varTrainer:SetScript("OnClick", function() UI:SetVariant("trainer") end)

  -- progress bar with step ticks
  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", 16, -74)
  bar:SetPoint("TOPRIGHT", -16, -74)
  bar:SetHeight(6)
  bar.bg = Tex(bar, "BACKGROUND", { 1, 1, 1, 0.07 })
  bar.bg:SetAllPoints()
  bar.fill = Tex(bar, "ARTWORK", C.gold)
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")
  bar.fill:SetWidth(1)
  bar.ticks = {}
  self.bar = bar
  self.barLeft = Text(page, 9, C.mute, FONT_NUM)
  self.barLeft:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
  self.barLeft:SetText("1")
  self.barRight = Text(page, 9, C.mute, FONT_NUM, "RIGHT")
  self.barRight:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -4)
  self.barRight:SetText("300")
  self.barMid = Text(page, 9, C.sub, FONT_NUM, "CENTER")

  -- current step card
  local card = CreateFrame("Frame", nil, page)
  card:SetPoint("TOPLEFT", 12, -104)
  card:SetPoint("TOPRIGHT", -12, -104)
  card:SetHeight(156)
  card.bg = Tex(card, "BACKGROUND", C.card)
  card.bg:SetAllPoints()
  Border(card, { 1, 1, 1, 0.06 })
  card.accent = Tex(card, "ARTWORK", C.gold)
  card.accent:SetPoint("TOPLEFT")
  card.accent:SetPoint("BOTTOMLEFT")
  card.accent:SetWidth(3)
  card.glow = Tex(card, "BACKGROUND", { 1, 1, 1, 0.03 }, 1)
  card.glow:SetPoint("TOPLEFT")
  card.glow:SetPoint("BOTTOMLEFT")
  card.glow:SetWidth(120)
  if card.glow.SetGradient and CreateColor then
    pcall(card.glow.SetGradient, card.glow, "HORIZONTAL", CreateColor(1, 1, 1, 0.06), CreateColor(1, 1, 1, 0))
  end
  self.card = card

  card.label = Text(card, 9, C.gold)
  card.label:SetPoint("TOPLEFT", 16, -12)
  card.icon = Icon(card, 44)
  card.icon:SetPoint("TOPLEFT", 16, -28)
  card.icon:EnableMouse(true)
  card.icon:SetScript("OnLeave", HideTooltip)
  card.name = Text(card, 15, C.text)
  card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -1)
  card.name:SetWidth(300)
  card.badge = Badge(card)
  card.badge:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -7)
  card.meta = Text(card, 10.5, C.sub)
  card.meta:SetPoint("LEFT", card.badge, "RIGHT", 8, 0)
  card.crafts = Text(card, 24, C.text, FONT_NUM, "RIGHT")
  card.crafts:SetPoint("TOPRIGHT", -16, -24)
  card.craftsSub = Text(card, 9.5, C.mute, FONT, "RIGHT")
  card.craftsSub:SetPoint("TOPRIGHT", card.crafts, "BOTTOMRIGHT", 0, -1)
  card.stats = Text(card, 11, C.text)
  card.stats:SetPoint("TOPLEFT", 16, -84)
  card.stats:SetWidth(W - 56)
  card.chips = {}
  card.note = Text(card, 10, C.mute)
  card.note:SetPoint("BOTTOMLEFT", 16, 11)
  card.note:SetWidth(W - 56)

  -- list header
  self.listTitle = Text(page, 9, C.mute)
  self.listTitle:SetPoint("TOPLEFT", 16, -276)
  self.listTitle:SetText("THE WHOLE ROUTE")
  self.listInfo = Text(page, 10, C.sub, FONT, "RIGHT")
  self.listInfo:SetPoint("TOPRIGHT", -16, -275)

  local scroll = CreateScroll(page)
  scroll:SetPoint("TOPLEFT", 12, -292)
  scroll:SetPoint("BOTTOMRIGHT", -12, 6)
  self.routeScroll = scroll
  self.routeRows, self.routeDetails = {}, {}
end

local function MakeChip(parent)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(80, 20)
  c:EnableMouse(true)
  c.bg = Tex(c, "BACKGROUND", { 1, 1, 1, 0.04 })
  c.bg:SetAllPoints()
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(16, 16)
  c.icon:SetPoint("LEFT", 2, 0)
  c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  c.text = Text(c, 10.5, C.text, FONT_NUM)
  c.text:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
  c:SetScript("OnLeave", function(s) s.bg:SetVertexColor(1, 1, 1, 0.04); HideTooltip() end)
  return c
end

local function ReagentTooltipLines(id, qty, need, have)
  local lines = {}
  local price, live = ns.UnitPrice(id)
  if need then lines[#lines + 1] = { format("Need %d for the rest of the step", need), 1, 1, 1 } end
  if have then
    local c = (need and have >= need) and C.pos or C.text
    lines[#lines + 1] = { format("You have %d (bags and bank)", have), c[1], c[2], c[3] }
  end
  if qty then lines[#lines + 1] = { format("%d per craft", qty) } end
  local snap = R.price[id]
  local how = snap and snap[2]
  local where = live and "live" or (how == "V" and "vendor" or (how == "craft" and "cheapest to craft yourself" or "AH"))
  lines[#lines + 1] = { "Price each: " .. ns.Money(price) .. "  (" .. where .. ")" }
  if snap and how == "AH" and snap[3] then
    local short = need and snap[3] < need
    lines[#lines + 1] = { format("On the AH: %d listed%s", snap[3], snap[4] and format(", ~%s sold per day", ns.Num(snap[4])) or ""), short and 1 or 0.7, short and 0.5 or 0.7, short and 0.5 or 0.7 }
  end
  local bolt = R.bolts and R.bolts[id]
  if bolt then
    local n = (need or qty or 1) * bolt[2]
    lines[#lines + 1] = { format("Craft it: %d x %s", n, ns.ItemName(bolt[1], true)), 0.6, 0.8, 1 }
  end
  return lines
end

local function FillChips(card, st, remaining, accent)
  local x = 16
  local maxX = W - 40
  for i, r in ipairs(st.reag) do
    local chip = card.chips[i] or MakeChip(card)
    card.chips[i] = chip
    local id, qty = r[1], r[2]
    local need = ceil(remaining * qty - 0.001)
    local have = ns.ItemCount(id)
    chip.icon:SetTexture(ns.ItemIcon(id))
    if have >= need then chip.text:SetText(Hex(C.pos) .. have .. "/" .. need .. "|r") else chip.text:SetText(have .. Hex(C.mute) .. "/|r" .. need) end
    local w = 28 + chip.text:GetStringWidth()
    chip:SetWidth(w)
    chip:ClearAllPoints()
    if x + w > maxX then chip:Hide() else
      chip:SetPoint("TOPLEFT", card, "TOPLEFT", x, -104)
      chip:Show()
      x = x + w + 6
    end
    chip:SetScript("OnEnter", function(s)
      s.bg:SetVertexColor(1, 1, 1, 0.09)
      ShowItemTooltip(s, id, ReagentTooltipLines(id, qty, need, have))
    end)
  end
  for i = #st.reag + 1, #card.chips do card.chips[i]:Hide() end
end

function UI:RenderCard(key, route, cur, skill)
  local card = self.card
  local accent = AccentOf(key)
  card.accent:SetVertexColor(accent[1], accent[2], accent[3], 1)
  SetColor(card.label, accent)

  if not skill then
    card.label:SetText("SKILL NOT FOUND")
    card.icon.tex:SetTexture(ns.PROF_BY_KEY[key].icon)
    card.name:SetText("Open the profession window once")
    SetColor(card.name, C.text)
    card.badge:Hide()
    card.meta:SetText("")
    card.crafts:SetText("")
    card.craftsSub:SetText("")
    card.stats:SetText("Or type  /cpath skill " .. key .. " 152  with your skill. The route below applies either way.")
    card.note:SetText("")
    for _, c in ipairs(card.chips) do c:Hide() end
    card.icon:SetScript("OnEnter", nil)
    return
  end

  local st = route[cur]
  if not st then
    card.label:SetText("DONE")
    card.icon.tex:SetTexture(ns.PROF_BY_KEY[key].icon)
    card.name:SetText(format("%s is at %d. Well done!", ns.PROF_BY_KEY[key].name, skill))
    SetColor(card.name, C.text)
    card.badge:Hide()
    card.meta:SetText("")
    card.crafts:SetText("")
    card.craftsSub:SetText("")
    card.stats:SetText("Check Gold tips for what is worth crafting now.")
    card.note:SetText("")
    for _, c in ipairs(card.chips) do c:Hide() end
    card.icon:SetScript("OnEnter", nil)
    return
  end

  local from = max(skill, st.from)
  local remaining = ns.Crafts(st, from, st.to)
  local diff = ns.Difficulty(st, skill)
  local profit, cost, sale, live = ns.Profit(st)
  local src = ns.SOURCE[st.src] or ns.SOURCE["?"]

  card.label:SetText(format("NEXT STEP  %d-%d", st.from, st.to))
  card.icon.tex:SetTexture(ns.StepIcon(st, key))
  card.icon:SetScript("OnEnter", function(s)
    ShowItemTooltip(s, st.item, { { "Shift-click in the route to link it in chat.", 0.6, 0.6, 0.6 } }, nil, ns.StepName(st))
  end)
  card.name:SetText(ns.StepName(st))
  SetColor(card.name, DIFF[diff] or C.text)
  card.badge:Show()
  card.badge:Set(src.label, src.color)
  local meta = format("Learn at %d", st.learn)
  if st.pat and st.pat > 0 then meta = meta .. "  ·  pattern ~" .. ns.Money(st.pat) .. " on the AH" end
  meta = meta .. "  ·  " .. Hex(DIFF[diff] or C.text) .. ns.DIFF_LABEL[diff] .. "|r"
  card.meta:SetText(meta)
  card.crafts:SetText("~" .. ns.Num(remaining))
  card.craftsSub:SetText(format("crafts to %d", st.to))

  local pc = ProfitColor(profit)
  local L = Hex(C.mute)
  local stats = L .. "Mats|r " .. ns.Money(cost) .. "    " .. (st.how == "none" and (L .. "Not sellable|r") or (L .. (st.how == "vendor" and "Vendor|r " or "AH|r ") .. ns.Money(sale)))
    .. "    " .. L .. "Each|r " .. ns.Money(profit, true, Hex(pc))
    .. "    " .. L .. "Total|r " .. ns.Money(profit * remaining, true, Hex(ProfitColor(profit * remaining)))
  if live then stats = stats .. "  " .. Hex(C.pos) .. "live|r" end
  card.stats:SetText(stats)

  FillChips(card, st, remaining, accent)

  local note = (st.item and R.notes[st.item]) or ""
  if st.thin then note = "Some mats are barely on the AH – the price may not hold." end
  if st.sold and st.how == "AH" and remaining > st.sold then
    note = (note ~= "" and (note .. "  ") or "") .. format("~%s sell per day – spread your sales.", ns.Num(st.sold))
  end
  card.note:SetText(note)
end

-- progress bar ticks at every step boundary
function UI:RenderBar(key, route, skill)
  local bar = self.bar
  local accent = AccentOf(key)
  local width = W - 32
  bar.fill:SetVertexColor(accent[1], accent[2], accent[3], 1)
  local frac = skill and min(1, max(0, (skill - 1) / (ns.MAX_SKILL - 1))) or 0
  bar.fill:SetWidth(max(1, width * frac))
  if not skill then bar.fill:Hide() else bar.fill:Show() end
  for i, st in ipairs(route) do
    local t = bar.ticks[i]
    if not t then
      t = Tex(bar, "OVERLAY", { 0.03, 0.035, 0.045, 1 })
      t:SetSize(2, 6)
      bar.ticks[i] = t
    end
    if i < #route then
      t:ClearAllPoints()
      t:SetPoint("LEFT", bar, "LEFT", width * (st.to - 1) / (ns.MAX_SKILL - 1) - 1, 0)
      t:Show()
    else
      t:Hide()
    end
  end
  for i = #route + 1, #bar.ticks do bar.ticks[i]:Hide() end
  if skill then
    self.barMid:ClearAllPoints()
    self.barMid:SetPoint("TOP", bar, "BOTTOMLEFT", max(14, min(width - 14, width * frac)), -4)
    self.barMid:SetText(skill)
    self.barMid:Show()
  else
    self.barMid:Hide()
  end
end

local function MakeRouteRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.bg = Tex(row, "BACKGROUND", { 1, 1, 1, 0 })
  row.bg:SetAllPoints()
  row.sep = Tex(row, "BORDER", { 1, 1, 1, 0.04 })
  row.sep:SetPoint("BOTTOMLEFT", 8, 0)
  row.sep:SetPoint("BOTTOMRIGHT", -8, 0)
  row.sep:SetHeight(1)
  row.bar = Tex(row, "ARTWORK", C.gold)
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(2)
  row.check = row:CreateTexture(nil, "ARTWORK")
  row.check:SetSize(13, 13)
  row.check:SetPoint("LEFT", 9, 0)
  row.check:SetTexture(CHECK)
  row.dot = Tex(row, "ARTWORK", C.mute)
  row.dot:SetSize(6, 6)
  row.dot:SetPoint("CENTER", row, "LEFT", 15.5, 0)
  row.range = Text(row, 12, C.sub, FONT_NUM)
  row.range:SetPoint("LEFT", 28, 0)
  row.icon = Icon(row, 26)
  row.icon:SetPoint("LEFT", 84, 0)
  row.name = Text(row, 12.5, C.text)
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
  row.name:SetWidth(250)
  row.sub = Text(row, 9.5, C.mute)
  row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
  row.sub:SetWidth(260)
  row.profit = Text(row, 12, C.sub, FONT_NUM, "RIGHT")
  row.profit:SetPoint("TOPRIGHT", -12, -7)
  row.crafts = Text(row, 9.5, C.mute, FONT, "RIGHT")
  row.crafts:SetPoint("BOTTOMRIGHT", -12, 7)
  row:SetScript("OnEnter", function(s)
    if not s.current then s.bg:SetVertexColor(1, 1, 1, 0.035) end
    if s.step then
      local st = s.step
      local lines = {
        { format("Step %d-%d  ·  ~%s crafts", st.from, st.to, ns.Num(s.remaining or st.crafts)) },
        { format("Colours: %d / %d / %d / %d", st.learn, st.y, st.g, st.gr), 0.7, 0.7, 0.7 },
        { "Click for details. Shift-click to link.", 0.55, 0.55, 0.55 },
      }
      if st.item and R.notes[st.item] then table.insert(lines, 2, { R.notes[st.item], 1, 0.82, 0.4 }) end
      ShowItemTooltip(s, st.item, lines, nil, ns.StepName(st))
    end
  end)
  row:SetScript("OnLeave", function(s)
    if not s.current then s.bg:SetVertexColor(1, 1, 1, 0) end
    HideTooltip()
  end)
  return row
end

local function MakeDetail(parent)
  local d = CreateFrame("Frame", nil, parent)
  d.bg = Tex(d, "BACKGROUND", { 1, 1, 1, 0.025 })
  d.bg:SetAllPoints()
  -- colour band
  d.band = CreateFrame("Frame", nil, d)
  d.band:SetHeight(6)
  d.band:SetPoint("TOPLEFT", 28, -14)
  d.band:SetPoint("TOPRIGHT", -16, -14)
  d.seg = {}
  for i, k in ipairs({ "orange", "yellow", "green" }) do
    d.seg[i] = Tex(d.band, "ARTWORK", DIFF[k])
  end
  d.marker = Tex(d.band, "OVERLAY", { 1, 1, 1, 1 })
  d.marker:SetSize(2, 12)
  d.labels = {}
  for i = 1, 4 do d.labels[i] = Text(d, 9, C.mute, FONT_NUM, "CENTER") end
  d.lines = {}
  d.info = Text(d, 10, C.sub)
  if d.info.SetWordWrap then d.info:SetWordWrap(true) end
  d.info:SetJustifyV("TOP")
  return d
end

local function MakeReagLine(parent)
  local l = CreateFrame("Frame", nil, parent)
  l:SetHeight(20)
  l:EnableMouse(true)
  l.icon = l:CreateTexture(nil, "ARTWORK")
  l.icon:SetSize(16, 16)
  l.icon:SetPoint("LEFT", 0, 0)
  l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  l.name = Text(l, 11, C.text)
  l.name:SetPoint("LEFT", l.icon, "RIGHT", 7, 0)
  l.qty = Text(l, 10.5, C.mute, FONT_NUM)
  l.qty:SetPoint("LEFT", 210, 0)
  l.need = Text(l, 10.5, C.text, FONT_NUM)
  l.need:SetPoint("LEFT", 270, 0)
  l.price = Text(l, 10.5, C.sub, FONT_NUM, "RIGHT")
  l.price:SetPoint("RIGHT", 0, 0)
  l:SetScript("OnLeave", HideTooltip)
  return l
end

function UI:FillDetail(d, st, width, skill, remaining)
  local bandW = width - 44
  local span = max(1, st.gr - st.learn)
  local function X(v) return bandW * (v - st.learn) / span end
  local bounds = { st.learn, st.y, st.g, st.gr }
  for i = 1, 3 do
    local s = d.seg[i]
    local a, b = X(bounds[i]), X(bounds[i + 1])
    s:ClearAllPoints()
    if b - a < 0.5 then s:Hide() else
      s:SetPoint("TOPLEFT", d.band, "TOPLEFT", a, 0)
      s:SetSize(b - a, 6)
      s:SetAlpha(0.85)
      s:Show()
    end
  end
  local lastX = -100
  for i = 1, 4 do
    local lab = d.labels[i]
    local x = X(bounds[i])
    if x - lastX < 22 and i > 1 then lab:Hide() else
      lab:ClearAllPoints()
      lab:SetPoint("TOP", d.band, "BOTTOMLEFT", x, -3)
      lab:SetText(bounds[i])
      lab:Show()
      lastX = x
    end
  end
  if skill and skill >= st.learn and skill <= st.gr then
    d.marker:ClearAllPoints()
    d.marker:SetPoint("CENTER", d.band, "LEFT", X(skill), 0)
    d.marker:Show()
  else
    d.marker:Hide()
  end

  local y = 44
  for i, r in ipairs(st.reag) do
    local l = d.lines[i] or MakeReagLine(d)
    d.lines[i] = l
    local id, qty = r[1], r[2]
    local need = ceil(remaining * qty - 0.001)
    local have = ns.ItemCount(id)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", d, "TOPLEFT", 28, -y)
    l:SetPoint("TOPRIGHT", d, "TOPRIGHT", -16, -y)
    l.icon:SetTexture(ns.ItemIcon(id))
    l.name:SetText(ns.ItemName(id, true))
    l.qty:SetText(qty .. " each")
    if have >= need and need > 0 then
      l.need:SetText(Hex(C.pos) .. need .. " total|r")
    else
      l.need:SetText(need .. " total" .. (have > 0 and (Hex(C.mute) .. "  (have " .. have .. ")|r") or ""))
    end
    local price = ns.UnitPrice(id)
    l.price:SetText(ns.Money(price))
    l:SetScript("OnEnter", function(s) ShowItemTooltip(s, id, ReagentTooltipLines(id, qty, need, have)) end)
    l:Show()
    y = y + 20
  end
  for i = #st.reag + 1, #d.lines do d.lines[i]:Hide() end

  local src = ns.SOURCE[st.src] or ns.SOURCE["?"]
  local info = Hex(src.color) .. src.long .. "|r"
  if st.pat and st.pat > 0 then info = info .. "  ·  pattern ~" .. ns.Money(st.pat) .. " on the AH" end
  if st.how == "none" then info = info .. "  ·  cannot be sold"
  elseif st.ahVal then
    info = info .. "  ·  AH " .. ns.Money(st.ahVal) .. " after cut, vendor " .. ns.Money(st.vend or 0) .. " → " .. (st.how == "AH" and "AH" or "vendor")
  elseif st.how ~= "AH" then info = info .. "  ·  sells to a vendor" end
  if st.sold and st.how ~= "none" then info = info .. format("  ·  ~%s sold/day%s", ns.Num(st.sold), st.listed and format(", %d listed", st.listed) or "") end
  local note = st.thin and "Some mats are barely on the AH – the price may not hold." or (st.item and R.notes[st.item])
  if note then info = info .. "\n" .. note end
  d.info:ClearAllPoints()
  d.info:SetPoint("TOPLEFT", d, "TOPLEFT", 28, -(y + 6))
  d.info:SetWidth(width - 44)
  d.info:SetText(info)
  local infoH = note and 40 or 26
  local h = y + 6 + infoH + 12
  d:SetHeight(h)
  return h
end

function UI:RenderRoute(key, route, variant, cur, skill, scrollToCurrent)
  local scroll = self.routeScroll
  local child = scroll.child
  local width = LIST_W - 10
  child:SetWidth(width)
  local accent = AccentOf(key)
  local y = 0
  local totalCrafts, totalProfit = 0, 0
  local curY

  for i, st in ipairs(route) do
    local row = self.routeRows[i] or MakeRouteRow(child)
    self.routeRows[i] = row
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    row.item, row.step = st.item, st

    local done = cur and i < cur
    local isCur = cur and i == cur
    row.current = isCur
    local remaining = st.crafts
    if isCur then remaining = ns.Crafts(st, max(skill, st.from), st.to) end
    if done then remaining = 0 end
    row.remaining = remaining
    local profit = ns.Profit(st)
    if not done then
      totalCrafts = totalCrafts + remaining
      totalProfit = totalProfit + remaining * profit
    end

    row.range:SetText(st.from .. "-" .. st.to)
    row.icon.tex:SetTexture(ns.StepIcon(st, key))
    row.name:SetText(ns.StepName(st))
    local src = ns.SOURCE[st.src] or ns.SOURCE["?"]
    local sub = Hex(src.color) .. src.label .. "|r" .. Hex(C.mute) .. "  ·  learn " .. st.learn
    if st.thin then sub = sub .. "  ·  " .. Hex(C.neg) .. "thin market|r" .. Hex(C.mute) end
    if st.pat and st.pat > 0 then sub = sub .. "  ·  AH ~" .. ns.Money(st.pat) end
    row.sub:SetText(sub)
    MoneyText(row.profit, profit, true)
    local pc = ProfitColor(profit)
    row.crafts:SetText((isCur and ("~" .. ns.Num(remaining) .. " left") or ("~" .. ns.Num(st.crafts) .. " crafts")))

    if done then
      row.check:Show(); row.dot:Hide()
      SetColor(row.name, C.mute); SetColor(row.range, C.mute)
      row.icon:SetAlpha(0.45)
      row.profit:SetAlpha(0.5)
      row.bar:Hide()
      row.bg:SetVertexColor(1, 1, 1, 0)
    elseif isCur then
      row.check:Hide(); row.dot:Show()
      row.dot:SetVertexColor(accent[1], accent[2], accent[3], 1)
      SetColor(row.name, DIFF[ns.Difficulty(st, skill)] or C.text); SetColor(row.range, C.text)
      row.icon:SetAlpha(1)
      row.profit:SetAlpha(1)
      row.bar:Show(); row.bar:SetVertexColor(accent[1], accent[2], accent[3], 1)
      row.bg:SetVertexColor(accent[1], accent[2], accent[3], 0.09)
      curY = y
    else
      row.check:Hide(); row.dot:Show()
      row.dot:SetVertexColor(C.mute[1], C.mute[2], C.mute[3], 0.8)
      SetColor(row.name, C.text); SetColor(row.range, C.sub)
      row.icon:SetAlpha(1)
      row.profit:SetAlpha(1)
      row.bar:Hide()
      row.bg:SetVertexColor(1, 1, 1, 0)
    end
    if profit > 50 or profit < -50 then
      -- coloured sign is part of Money(); tint the whole string lightly
      row.profit:SetTextColor(pc[1], pc[2], pc[3], 1)
    else
      SetColor(row.profit, C.sub)
    end

    local ekey = key .. ":" .. variant .. ":" .. tostring(st.item or st.name) .. ":" .. st.from
    row:SetScript("OnClick", function(_, button)
      if IsShiftKeyDown and IsShiftKeyDown() then
        ns.InsertLink(st.item)
        return
      end
      ns.char.expanded[ekey] = not ns.char.expanded[ekey] or nil
      UI:Refresh()
    end)
    row:Show()
    y = y + ROW_H

    local d = self.routeDetails[i]
    if ns.char.expanded[ekey] then
      d = d or MakeDetail(child)
      self.routeDetails[i] = d
      d:ClearAllPoints()
      d:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
      d:SetWidth(width)
      local detailRemaining = done and 0 or (isCur and remaining or st.crafts)
      local h = self:FillDetail(d, st, width, skill, max(detailRemaining, 0))
      d:Show()
      y = y + h
    elseif d then
      d:Hide()
    end
  end
  for i = #route + 1, #self.routeRows do self.routeRows[i]:Hide() end
  for i = #route + 1, #self.routeDetails do if self.routeDetails[i] then self.routeDetails[i]:Hide() end end

  child:SetHeight(max(1, y))
  if scrollToCurrent then
    local target = (curY or 0) - ROW_H
    scroll:ScrollTo(target)
    -- the scroll frame may not have its final size on the first frame after showing
    if C_Timer and C_Timer.After then
      C_Timer.After(0.05, function() scroll:ScrollTo(target) end)
    end
  else
    scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
  end

  local prefix = cur and "Left" or "Total"
  self.listInfo:SetText(format("%s: ~%s crafts  ·  ", prefix, ns.Num(totalCrafts)) .. ns.Money(totalProfit, true, Hex(ProfitColor(totalProfit))))
end

---------------------------------------------------------------------------
-- Gold page
---------------------------------------------------------------------------

function UI:BuildGoldPage()
  local f = self.frame
  local page = CreateFrame("Frame", nil, f)
  page:SetPoint("TOPLEFT", 0, -(HEADER_H + TABS_H))
  page:SetPoint("BOTTOMRIGHT", 0, 31)
  page:Hide()
  self.goldPage = page

  self.goldTitle = Text(page, 14, C.text)
  self.goldTitle:SetPoint("TOPLEFT", 16, -16)
  self.goldTitle:SetText("What makes gold?")
  self.goldSub = Text(page, 10.5, C.sub)
  self.goldSub:SetPoint("TOPLEFT", self.goldTitle, "BOTTOMLEFT", 0, -5)
  self.goldSub:SetText("Profit per craft after the AH cut. What you can craft now is at the top.")

  self.goldBack = FlatButton(page, 76, 22, "Route", 10.5)
  self.goldBack:SetPoint("TOPRIGHT", -16, -16)
  self.goldBack:SetScript("OnClick", function() UI:SetMode("route") end)
  self.goldBack.tip = { "Route", "Back to the levelling route for this profession." }

  local hl = Text(page, 9, C.mute)
  hl:SetPoint("TOPLEFT", 16, -62)
  hl:SetText("CRAFT")
  local hr1 = Text(page, 9, C.mute, FONT, "RIGHT")
  hr1:SetPoint("TOPRIGHT", -24, -62)
  hr1:SetText("PROFIT  ·  SOLD/DAY")
  local line = Tex(page, "ARTWORK", C.line)
  line:SetPoint("TOPLEFT", 12, -76)
  line:SetPoint("TOPRIGHT", -12, -76)
  line:SetHeight(1)

  local scroll = CreateScroll(page)
  scroll:SetPoint("TOPLEFT", 12, -80)
  scroll:SetPoint("BOTTOMRIGHT", -12, 6)
  self.goldScroll = scroll
  self.goldRows = {}
end

local function MakeGoldRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(GOLD_ROW_H)
  row.bg = Tex(row, "BACKGROUND", { 1, 1, 1, 0 })
  row.bg:SetAllPoints()
  row.sep = Tex(row, "BORDER", { 1, 1, 1, 0.04 })
  row.sep:SetPoint("BOTTOMLEFT", 8, 0)
  row.sep:SetPoint("BOTTOMRIGHT", -8, 0)
  row.sep:SetHeight(1)
  row.icon = Icon(row, 32)
  row.icon:SetPoint("LEFT", 12, 0)
  row.name = Text(row, 12.5, C.text)
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 11, -2)
  row.name:SetWidth(270)
  row.badge = Badge(row)
  row.badge:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 11, 1)
  row.sub = Text(row, 9.5, C.mute)
  row.sub:SetPoint("LEFT", row.badge, "RIGHT", 7, 0)
  row.sub:SetWidth(300)
  row.profit = Text(row, 13, C.pos, FONT_NUM, "RIGHT")
  row.profit:SetPoint("TOPRIGHT", -14, -9)
  row.sold = Text(row, 9.5, C.mute, FONT, "RIGHT")
  row.sold:SetPoint("BOTTOMRIGHT", -14, 9)
  row.lock = Badge(row)
  row.lock:SetPoint("RIGHT", row.profit, "LEFT", -10, 0)
  row:SetScript("OnLeave", function(s) s.bg:SetVertexColor(1, 1, 1, 0); HideTooltip() end)
  return row
end

function UI:RenderGold(scrollTop)
  local key = self.tab
  if not ns.PROF_BY_KEY[key] then key = ns.PROFS[1].key end
  local p = ns.PROF_BY_KEY[key]
  local accent = p.color
  self.goldTitle:SetText("What makes gold in " .. p.name .. "?")
  self.goldSub:SetText(format("Profit per craft after the %d%% AH cut. What you can craft now is at the top.", floor(ns.Cut() * 100 + 0.5)))
  local skill = ns.GetSkill(key) or 0

  local list = {}
  for _, g in ipairs(p.gold) do
    local profit, cost, sale = ns.Profit(g)
    list[#list + 1] = { g = g, profit = profit, cost = cost, sale = sale, ok = skill >= g.learn }
  end
  table.sort(list, function(a, b)
    if a.ok ~= b.ok then return a.ok end
    if a.ok then return a.profit > b.profit end
    if a.g.learn ~= b.g.learn then return a.g.learn < b.g.learn end
    return a.profit > b.profit
  end)

  local child = self.goldScroll.child
  local width = LIST_W - 10
  child:SetWidth(width)
  local y = 0
  for i, e in ipairs(list) do
    local g = e.g
    local row = self.goldRows[i] or MakeGoldRow(child)
    self.goldRows[i] = row
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    row.icon.tex:SetTexture(ns.ItemIcon(g.item))
    row.name:SetText(g.name or ns.ItemName(g.item))
    local src = ns.SOURCE[g.src] or ns.SOURCE["?"]
    row.badge:Set(src.label, src.color)
    local sub = "learn " .. g.learn
    if R.cooldown and R.cooldown[g.item] then sub = sub .. "  ·  " .. Hex(C.gold) .. "cooldown|r" .. Hex(C.mute) end
    local note = R.notes[g.item]
    if note then sub = sub .. "  ·  " .. note end
    row.sub:SetText(sub)
    row.profit:SetText(ns.Money(e.profit, true))
    local pc = ProfitColor(e.profit)
    row.profit:SetTextColor(pc[1], pc[2], pc[3], 1)
    row.sold:SetText(g.sold and (ns.Num(g.sold) .. " / day") or "")
    if e.ok then
      row:SetAlpha(1)
      row.lock:Hide()
      SetColor(row.name, C.text)
    else
      row:SetAlpha(0.6)
      row.lock:Set("NEEDS " .. g.learn, C.sub)
      row.lock:Show()
      SetColor(row.name, C.sub)
    end
    row:SetScript("OnEnter", function(s)
      s.bg:SetVertexColor(accent[1], accent[2], accent[3], 0.07)
      local lines = {
        { "Mats per craft", right = ns.Money(e.cost) },
        { "Sale after the AH cut", right = ns.Money(e.sale) },
        { "Profit per craft", right = ns.Money(e.profit, true) },
      }
      for _, r in ipairs(g.reag) do
        lines[#lines + 1] = { "  " .. r[2] .. " x " .. ns.ItemName(r[1], true), right = ns.Money(ns.UnitPrice(r[1]) * r[2]) }
      end
      if (g.yield or 1) > 1 then lines[#lines + 1] = { format("Makes %d per craft.", g.yield), 0.6, 0.8, 1 } end
      if R.notes[g.item] then lines[#lines + 1] = { R.notes[g.item], 1, 0.82, 0.4 } end
      if not e.ok then lines[#lines + 1] = { format("Needs %s %d (you have %d).", p.name, g.learn, skill), 1, 0.5, 0.5 } end
      ShowItemTooltip(s, g.item, lines)
    end)
    row:SetScript("OnClick", function()
      if IsShiftKeyDown and IsShiftKeyDown() then ns.InsertLink(g.item) end
    end)
    row:Show()
    y = y + GOLD_ROW_H
  end
  for i = #list + 1, #self.goldRows do self.goldRows[i]:Hide() end
  child:SetHeight(max(1, y))
  if scrollTop then self.goldScroll:ScrollTo(0) else self.goldScroll:ScrollTo(self.goldScroll:GetVerticalScroll() or 0) end
end

---------------------------------------------------------------------------
-- Mini tracker
---------------------------------------------------------------------------

function UI:BuildMini()
  if self.mini then return end
  local m = CreateFrame("Button", "CraftPathMini", UIParent)
  self.mini = m
  m:SetSize(272, 58)
  m:SetFrameStrata("MEDIUM")
  m:SetClampedToScreen(true)
  m:SetMovable(true)
  m:EnableMouse(true)
  m:RegisterForDrag("LeftButton")
  m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  Shadow(m, 4)
  m.bg = Tex(m, "BACKGROUND", C.bg)
  m.bg:SetAllPoints()
  Border(m, { 1, 1, 1, 0.09 })
  m.accent = Tex(m, "ARTWORK", C.gold)
  m.accent:SetPoint("TOPLEFT")
  m.accent:SetPoint("BOTTOMLEFT")
  m.accent:SetWidth(3)
  m.icon = Icon(m, 34)
  m.icon:SetPoint("LEFT", 12, 1)
  m.top = Text(m, 9, C.sub)
  m.top:SetPoint("TOPLEFT", m.icon, "TOPRIGHT", 10, 1)
  m.step = Text(m, 9, C.mute, FONT, "RIGHT")
  m.step:SetPoint("TOPRIGHT", -10, -8)
  m.name = Text(m, 12.5, C.text)
  m.name:SetPoint("LEFT", m.icon, "RIGHT", 10, 0)
  m.name:SetWidth(210)
  m.info = Text(m, 9.5, C.mute)
  m.info:SetPoint("BOTTOMLEFT", m.icon, "BOTTOMRIGHT", 10, -1)
  m.info:SetWidth(215)
  m.prog = Tex(m, "OVERLAY", C.gold)
  m.prog:SetPoint("BOTTOMLEFT", 3, 1)
  m.prog:SetHeight(2)
  m.progBg = Tex(m, "ARTWORK", { 1, 1, 1, 0.05 })
  m.progBg:SetPoint("BOTTOMLEFT", 3, 1)
  m.progBg:SetPoint("BOTTOMRIGHT", -1, 1)
  m.progBg:SetHeight(2)

  m:SetScript("OnDragStart", function(s) s.moved = true; s:StartMoving() end)
  m:SetScript("OnDragStop", function(s)
    s:StopMovingOrSizing()
    local p, _, rp, x, y = s:GetPoint()
    ns.db.mini.point = { p, rp, x, y }
  end)
  m:SetScript("OnClick", function(s, button)
    if s.moved then s.moved = false; return end
    if button == "RightButton" then
      local list = {}
      for _, p in ipairs(ns.PROFS) do if ns.GetSkill(p.key) then list[#list + 1] = p.key end end
      if #list == 0 then for _, p in ipairs(ns.PROFS) do list[#list + 1] = p.key end end
      local cur, idx = ns.TrackedProf(), 0
      for i, k in ipairs(list) do if k == cur then idx = i end end
      ns.db.mini.prof = list[(idx % #list) + 1]
      UI:Refresh()
    else
      if UI.frame and not UI.frame:IsShown() then UI:SelectTab(ns.TrackedProf(), true) end
      UI:Toggle()
    end
  end)
  m:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("CraftPath")
    GameTooltip:AddLine("Click: open the route", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: next profession", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  m:SetScript("OnLeave", HideTooltip)
  local pt = ns.db.mini.point
  m:ClearAllPoints()
  m:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
end

function UI:RenderMini()
  if not self.mini then return end
  local m = self.mini
  if not ns.db.mini.shown then m:Hide() return end
  local key = ns.TrackedProf()
  local p = ns.PROF_BY_KEY[key]
  local route = ns.Route(key)
  local skill = ns.GetSkill(key)
  local accent = p.color
  m.accent:SetVertexColor(accent[1], accent[2], accent[3], 1)
  m.prog:SetVertexColor(accent[1], accent[2], accent[3], 1)
  m.top:SetText(p.name:upper() .. "  " .. Hex(C.text) .. (skill or "?") .. "|r" .. Hex(C.mute) .. "/" .. ns.MAX_SKILL .. "|r")
  local frac = skill and min(1, (skill - 1) / (ns.MAX_SKILL - 1)) or 0
  m.prog:SetWidth(max(1, (m:GetWidth() - 4) * frac))
  local cur = ns.CurrentIndex(route, skill)
  local st = cur and route[cur]
  if not skill then
    m.icon.tex:SetTexture(p.icon)
    m.name:SetText("Skill not found")
    SetColor(m.name, C.sub)
    m.info:SetText("Open the profession window or use /cpath skill")
    m.step:SetText("")
  elseif not st then
    m.icon.tex:SetTexture(p.icon)
    m.name:SetText("Done, " .. skill .. "!")
    SetColor(m.name, C.pos)
    m.info:SetText("Check Gold tips for what is worth crafting")
    m.step:SetText("")
  else
    local remaining = ns.Crafts(st, max(skill, st.from), st.to)
    local profit = ns.Profit(st)
    m.icon.tex:SetTexture(ns.StepIcon(st, key))
    m.name:SetText(ns.StepName(st))
    SetColor(m.name, DIFF[ns.Difficulty(st, skill)] or C.text)
    m.info:SetText(format("~%s crafts to %d  ·  ", ns.Num(remaining), st.to) .. ns.Money(profit, true, Hex(ProfitColor(profit))) .. Hex(C.mute) .. " each|r")
    m.step:SetText(format("%d/%d", cur, #route))
  end
  m:Show()
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

function UI:BuildMinimapButton()
  if self.mmb or not Minimap then return end
  local b = CreateFrame("Button", "CraftPathMinimapButton", Minimap)
  self.mmb = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetTexture(ns.PROF_BY_KEY.tailoring.icon)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetPoint("TOPLEFT", 7, -6)
  b.icon = icon
  local overlay = b:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local function Place()
    local a = math.rad(ns.db.minimap.angle or 200)
    local r = (Minimap:GetWidth() or 140) / 2 + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b.Place = Place
  local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
  b:SetScript("OnDragStart", function(s)
    s:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      px, py = px / sc, py / sc
      ns.db.minimap.angle = math.deg(atan2(py - my, px - mx))
      Place()
    end)
  end)
  b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.db.mini.shown = not ns.db.mini.shown
      UI:Refresh()
    else
      UI:Toggle()
    end
  end)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_LEFT")
    GameTooltip:AddLine("CraftPath")
    GameTooltip:AddLine("Left-click: show the route", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: mini tracker", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move the button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", HideTooltip)
  Place()
end

function UI:UpdateMinimapButton()
  if not self.mmb then return end
  if ns.db.minimap.hide then self.mmb:Hide() else self.mmb:Show(); self.mmb.Place() end
end

---------------------------------------------------------------------------
-- Control
---------------------------------------------------------------------------

function UI:Init()
  if self.ready then return end
  self.ready = true
  self.tab = ns.db.tab
  self:Build()
  self:BuildMini()
  self:BuildMinimapButton()
  self:UpdateMinimapButton()
end

function UI:ApplyScale()
  if self.frame then self.frame:SetScale(ns.db.scale or 1) end
end

function UI:ResetPositions(silent)
  if self.frame then
    local p = ns.db.point
    self.frame:ClearAllPoints()
    self.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    self:ApplyScale()
  end
  if self.mini then
    local p = ns.db.mini.point
    self.mini:ClearAllPoints()
    self.mini:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  end
end

function UI:Toggle()
  if not self.frame then self:Init() end
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function UI:SelectTab(key, silent)
  self.tab = key
  ns.db.tab = key
  if not silent then self:Refresh(true) end
end

function UI:SetMode(m)
  ns.db.mode = (m == "gold") and "gold" or "route"
  self:Refresh(true)
end

-- small popup with a copyable link to the current route on the website
function UI:ShowLink()
  if not self.frame then self:Init() end
  local key = ns.PROF_BY_KEY[self.tab] and self.tab or nil
  local url = ns.WebURL(key, key and ns.GetSkill(key) or nil)
  if not self.linkBox then
    local p = CreateFrame("Frame", "CraftPathLink", UIParent)
    p:SetSize(440, 104)
    p:SetFrameStrata("DIALOG")
    p:SetToplevel(true)
    p:SetPoint("CENTER", 0, 140)
    p:EnableMouse(true)
    Shadow(p, 7)
    p.bg = Tex(p, "BACKGROUND", C.panel)
    p.bg:SetAllPoints()
    Border(p, { 1, 1, 1, 0.12 })
    p.title = Text(p, 12.5, C.text)
    p.title:SetPoint("TOPLEFT", 14, -12)
    p.title:SetText("Open this route on the website")
    local eb = CreateFrame("EditBox", nil, p)
    eb:SetPoint("TOPLEFT", 14, -36)
    eb:SetPoint("TOPRIGHT", -14, -36)
    eb:SetHeight(24)
    eb:SetFont(FONT, 11, "")
    eb:SetTextColor(1, 1, 1)
    eb:SetAutoFocus(true)
    if eb.SetTextInsets then eb:SetTextInsets(7, 7, 0, 0) end
    eb.bg = Tex(eb, "BACKGROUND", { 0, 0, 0, 0.4 })
    eb.bg:SetAllPoints()
    eb:SetScript("OnEscapePressed", function() p:Hide() end)
    eb:SetScript("OnEnterPressed", function() p:Hide() end)
    eb:SetScript("OnTextChanged", function(s, user) if user then s:SetText(p.url or ""); s:HighlightText() end end)
    p.eb = eb
    p.hint = Text(p, 10, C.mute)
    p.hint:SetPoint("BOTTOMLEFT", 14, 13)
    p.hint:SetText("Press Ctrl+C to copy, then paste it in your browser.")
    local close = FlatButton(p, 56, 18, "Close", 9.5)
    close:SetPoint("BOTTOMRIGHT", -12, 10)
    close:SetScript("OnClick", function() p:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "CraftPathLink") end
    self.linkBox = p
  end
  local p = self.linkBox
  p.url = url
  p.eb:SetText(url)
  p:Show()
  p.eb:SetFocus()
  p.eb:HighlightText()
end

function UI:SetVariant(v)
  local key = self.tab
  if not ns.PROF_BY_KEY[key] then return end
  ns.db.variant[key] = v
  self:Refresh(true)
end

function UI:Refresh(scrollToCurrent)
  if not self.ready then return end
  self:RenderMini()
  local f = self.frame
  if not (f and f:IsShown()) then return end

  local key = ns.PROF_BY_KEY[self.tab] and self.tab or ns.PROFS[1].key
  self.tab = key
  local isGold = (ns.db.mode == "gold")
  local accent = AccentOf(key)

  self.accentLine:SetVertexColor(accent[1], accent[2], accent[3], 1)
  for k, b in pairs(self.tabs) do
    local sel = (k == key)
    local a = (k == "gold") and C.gold or AccentOf(k)
    b.under:SetVertexColor(a[1], a[2], a[3], 1)
    if sel then b.under:Show() else b.under:Hide() end
    b.bg:SetVertexColor(1, 1, 1, sel and 0.045 or 0)
    SetColor(b.label, sel and C.text or C.sub)
    local s = ns.PROF_BY_KEY[k] and ns.GetSkill(k)
    b.count:SetText(s and tostring(s) or "")
    b.icon:SetAlpha((s or sel) and 1 or 0.45)
    -- centre icon + label + count together
    local lw = b.label:GetStringWidth() + (s and (b.count:GetStringWidth() + 6) or 0)
    local total = 16 + 7 + lw
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", b, "CENTER", -total / 2, 0)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
    b.count:ClearAllPoints()
    b.count:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
  end

  local live = ns.HasLivePrices()
  self.liveBtn.text:SetText(ns.db.livePrices and (live and "Live: on" or "Live: none") or "Live: off")
  self.liveBtn:SetActive(ns.db.livePrices and live, C.pos)
  self.miniBtn.text:SetText(ns.db.mini.shown and "Mini: on" or "Mini: off")
  self.miniBtn:SetActive(ns.db.mini.shown, accent)
  local age = ns.DataAge()
  local ageCol = (age and age > 3 * 3600) and Hex({ 1, 0.62, 0.3 }) or ""
  self.footer:SetText(format("%s  ·  %s  ·  %sAH scan %s%s", R.source or "AHledger", R.market or "", ageCol, ns.AgeText(age), ageCol ~= "" and "|r" or "") .. (live and "  ·  + Auctionator" or ""))
  self.webBtn:SetActive(false, accent)
  local atAH = ns.ahOpen and ns.HasAuctionator and ns.HasAuctionator()
  if atAH then self.scanBtn:Show(); self.listBtn:Show() else self.scanBtn:Hide(); self.listBtn:Hide() end
  self.footer:SetPoint("RIGHT", atAH and self.scanBtn or self.webBtn, "LEFT", -8, 0)
  if atAH then self.scanBtn:SetActive(true, C.pos) end

  if isGold then
    self.profPage:Hide()
    self.goldPage:Show()
    self.headIcon.tex:SetTexture(ns.PROF_BY_KEY[key].icon)
    self.subtitle:SetText(ns.PROF_BY_KEY[key].name .. "  ·  Gold tips")
    self.goldBack:SetActive(false, accent)
    self:RenderGold(scrollToCurrent)
    return
  end

  self.goldPage:Hide()
  self.profPage:Show()
  local p = ns.PROF_BY_KEY[key]
  local route, variant, binfo = ns.Route(key)
  local skill = ns.GetSkill(key)
  local cur = ns.CurrentIndex(route, skill)
  local bmode = ns.db.budget.mode
  self.budgetBtn.text:SetText(bmode == "off" and "Budget: off" or (bmode == "auto" and "Budget: your gold" or ("Budget: " .. ns.Money(ns.db.budget.gold))))
  self.budgetBtn:SetActive(bmode ~= "off", accent)

  self.headIcon.tex:SetTexture(p.icon)
  self.subtitle:SetText(format("%s  ·  %s  ·  1-%d", p.name, variant == "trainer" and "Trainer only" or "Best route", ns.MAX_SKILL))
  self.goldBtn:SetActive(false, accent)
  self.varBest:SetActive(variant == "best", accent)
  self.varTrainer:SetActive(variant == "trainer", accent)

  self.skillText:SetText(skill and tostring(skill) or "?")
  self.skillMax:SetText("/ " .. ns.MAX_SKILL)
  if not skill then
    self.stepText:SetText("Skill not found yet")
  elseif cur > #route then
    self.stepText:SetText("Route complete")
  else
    self.stepText:SetText(format("Step %d of %d", cur, #route))
  end
  if binfo and skill then
    local col = binfo.fits and (binfo.default and C.pos or C.gold) or C.neg
    local base = (self.stepText.GetText and self.stepText:GetText() or "") .. "  ·  "
    if binfo.fits then
      local txt = binfo.default and "fits " or "adjusted to "
      self.stepText:SetText(base .. Hex(col) .. txt .. "|r" .. ns.Money(binfo.budget)
        .. Hex(C.mute) .. "  (needs |r" .. ns.Money(binfo.peak) .. Hex(C.mute) .. ")|r")
    else
      self.stepText:SetText(base .. ns.Money(binfo.budget) .. Hex(col) .. " lasts to " .. (binfo.reach or "?") .. "|r"
        .. Hex(C.mute) .. "  (all the way: |r" .. ns.Money(binfo.peak) .. Hex(C.mute) .. ")|r")
    end
  end

  self:RenderBar(key, route, skill)
  self:RenderCard(key, route, cur, skill)
  self:RenderRoute(key, route, variant, cur, skill, scrollToCurrent)
end
