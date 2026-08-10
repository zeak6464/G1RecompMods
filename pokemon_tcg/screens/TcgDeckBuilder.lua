local V = ...
local Cache = V.require("cache")
local Save = V.require("save")
local Deck = V.require("deck")
local CardGfx = V.require("card_gfx")

local function Font()
  return require("src.render.Font")
end

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

-- GBC deck editor type tabs (left → right).
local TABS = {
  { key = "GRASS",      kind = "pokemon", label = "G" },
  { key = "FIRE",       kind = "pokemon", label = "R" },
  { key = "WATER",      kind = "pokemon", label = "W" },
  { key = "LIGHTNING",  kind = "pokemon", label = "L" },
  { key = "FIGHTING",   kind = "pokemon", label = "F" },
  { key = "PSYCHIC",    kind = "pokemon", label = "P" },
  { key = "COLORLESS",  kind = "pokemon", label = "C" },

  { key = "TRAINER",    kind = "trainer", label = "T" },
  { key = "ENERGY",     kind = "energy",  label = "E" },
}

local LIST_ROWS = 6
local LIST_TOP = 48

local function typeKey(card)
  if not card then return "COLORLESS" end
  if card.kind == "trainer" then return "TRAINER" end
  if card.kind == "energy" then return "ENERGY" end
  return card.type or "COLORLESS"
end

local function matchesTab(card, tab)
  if not card or not tab then return false end
  if tab.kind == "trainer" then return card.kind == "trainer" end
  if tab.kind == "energy" then return card.kind == "energy" end
  return card.kind == "pokemon" and (card.type or "COLORLESS") == tab.key
end

local function countByType(deck)
  local t = {}
  for _, tab in ipairs(TABS) do t[tab.key] = 0 end
  for _, id in ipairs(deck) do
    local key = typeKey(Cache.card(id))
    t[key] = (t[key] or 0) + 1
  end
  return t
end

function Screen:sgbPalettes(game)
  -- Keep list selection (black/white) out of SGB shade remap.
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, 19, 17) }
end


function Screen.new(game, mod)
  mod = mod or V.mod
  local self = setmetatable({}, Screen)
  self.game = game
  self.mod = mod
  self.tab = 1
  self.focus = "list" -- "tabs" | "list"
  self.index = 1
  self.scroll = 0
  self.message = nil
  self:rebuild()
  return self
end

function Screen.open(game, mod)
  return Screen.new(game, mod)
end

function Screen:rebuild()
  Save.init(self.mod)
  local collection = Save.collection(self.mod)
  local deck = Save.deck(self.mod)
  self.deckCount = #deck
  self.typeCounts = countByType(deck)

  local inDeck = {}
  for _, id in ipairs(deck) do
    local nid = tonumber(id) or id
    inDeck[nid] = (inDeck[nid] or 0) + 1
  end

  local tab = TABS[self.tab]
  local ids, seen = {}, {}
  for key, owned in pairs(collection) do
    local id = tonumber(key)
    if id and owned and owned > 0 then
      local card = Cache.card(id)
      if matchesTab(card, tab) then
        ids[#ids + 1] = id
        seen[id] = true
      end
    end
  end
  -- Also list cards that are in the deck for this tab (in case counts drifted).
  for id, n in pairs(inDeck) do
    if n > 0 and not seen[id] then
      local card = Cache.card(id)
      if matchesTab(card, tab) then
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids, function(a, b)
    local ca, cb = Cache.card(a), Cache.card(b)
    local na = ca and ca.name or ""
    local nb = cb and cb.name or ""
    if na == nb then return a < b end
    return na < nb
  end)

  local rows = {}
  for _, id in ipairs(ids) do
    local card = Cache.card(id)
    local owned = Save.countOwned(self.mod, id)
    local label
    if card and card.kind == "pokemon" then
      local lv = card.level or 0
      if lv > 0 then
        label = ("%s LV%d"):format(card.name or "?", lv)
      else
        label = card.name or "?"
      end
    else
      label = card and card.name or ("#" .. id)
    end

    rows[#rows + 1] = {
      id = id,
      label = label,
      inDeck = inDeck[id] or 0,
      owned = owned,
    }
  end
  self.rows = rows
  if self.index > #rows then self.index = math.max(1, #rows) end
  self:clampScroll()
end

function Screen:clampScroll()
  local n = #self.rows
  if n == 0 then
    self.scroll = 0
    self.index = 1
    return
  end
  if self.index < 1 then self.index = 1 end
  if self.index > n then self.index = n end
  if self.index - self.scroll > LIST_ROWS then
    self.scroll = self.index - LIST_ROWS
  end
  if self.index - self.scroll < 1 then
    self.scroll = self.index - 1
  end
  if self.scroll < 0 then self.scroll = 0 end
end

function Screen:addSelected()
  local row = self.rows[self.index]
  if not row then
    self.message = "No cards here"
    return
  end
  local ok, err = Deck.tryAdd(self.mod, row.id)
  self.message = ok and "ADDED" or (err or "CANT ADD")
  self:rebuild()
end

function Screen:removeSelected()
  local row = self.rows[self.index]
  if not row then return end
  local ok, err = Deck.tryRemove(self.mod, row.id)
  self.message = ok and "REMOVED" or (err or "CANT REMOVE")
  self:rebuild()
end


function Screen:resetStarter()
  Save.ensureStarterDeck(self.mod, Cache.get().practiceDeck, true)
  self.message = "Starter deck loaded"
  self:rebuild()
end

function Screen:changeTab(delta)
  self.tab = self.tab + delta
  if self.tab < 1 then self.tab = #TABS end
  if self.tab > #TABS then self.tab = 1 end
  self.index = 1
  self.scroll = 0
  self:rebuild()
end

function Screen:update()
  local input = self.game.input
  if input:wasPressed("b") then
    local ok, err = Deck.validate(self.mod)
    if not ok then
      self.message = err or "Deck incomplete"
      -- Still allow leaving; duel uses whatever is saved.

    end
    self.game.stack:pop()
    return
  end

  if self.focus == "tabs" then
    if input:wasPressed("left") then
      self:changeTab(-1)
    elseif input:wasPressed("right") then
      self:changeTab(1)
    elseif input:wasPressed("down") or input:wasPressed("a") then
      self.focus = "list"
      self:clampScroll()
    elseif input:wasPressed("select") then
      self:resetStarter()
    end
    return
  end

  -- list focus
  if input:wasPressed("up") then
    if self.index <= 1 then
      self.focus = "tabs"
    else
      self.index = self.index - 1
      self:clampScroll()
    end
  elseif input:wasPressed("down") then
    if #self.rows > 0 then
      self.index = math.min(#self.rows, self.index + 1)
      self:clampScroll()
    end
  elseif input:wasPressed("left") then
    -- Decrease copies of selected card
    self:removeSelected()
  elseif input:wasPressed("right") then
    -- Increase copies of selected card
    self:addSelected()
  elseif input:wasPressed("a") then
    self:addSelected()
  elseif input:wasPressed("start") or input:wasPressed("select") then
    self:removeSelected()
  end
end

local function drawTypeIcon(x, y, tab, selected)
  local r, g, b = CardGfx.typeColor({
    kind = tab.kind == "trainer" and "trainer"
      or tab.kind == "energy" and "energy"
      or "pokemon",
    type = tab.key,
    energyType = tab.key,
  })
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", x, y, 14, 12)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x, y, 14, 12)
  local F = Font()
  F.draw(tab.label, x + 3, y + 2)
  if selected then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.polygon("fill", x + 5, y - 5, x + 9, y - 5, x + 7, y - 1)
  end
end

function Screen:draw()
  local F = Font()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  love.graphics.setColor(0, 0, 0, 1)
  local count = ("%d/%d"):format(self.deckCount or 0, Deck.SIZE)
  F.draw(count, 160 - (#count * 8) - 4, 4)

  local tabY = 16
  for i, tab in ipairs(TABS) do
    local x = 4 + (i - 1) * 17
    drawTypeIcon(x, tabY, tab, i == self.tab and self.focus == "tabs")
    local n = tostring(self.typeCounts[tab.key] or 0)
    F.draw(n, x + math.floor((14 - #n * 8) / 2), tabY + 14)
  end
  if self.focus == "tabs" then
    local x = 4 + (self.tab - 1) * 17
    love.graphics.setColor(0.80, 0.18, 0.12, 1)
    love.graphics.rectangle("fill", x, tabY + 12, 14, 2)
  end

  love.graphics.setColor(0.80, 0.18, 0.12, 1)
  love.graphics.rectangle("fill", 0, 42, 160, 2)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 45, 160, 1)

  local n = #self.rows
  if n == 0 then
    love.graphics.setColor(0, 0, 0, 1)
    F.draw("(none owned)", 16, LIST_TOP + 16)
    F.draw("UP: types", 16, LIST_TOP + 28)
  else
    for row = 1, LIST_ROWS do
      local i = self.scroll + row
      local item = self.rows[i]
      if item then
        local y = LIST_TOP + (row - 1) * 12
        local selected = self.focus == "list" and i == self.index
        local name = item.label
        if #name > 12 then name = name:sub(1, 12) end
        local frac = ("%d/%d"):format(item.inDeck, item.owned)
        if selected then
          -- Red underline + filled cursor (readable under true-color).
          love.graphics.setColor(0.85, 0.15, 0.12, 1)
          love.graphics.rectangle("fill", 0, y + 8, 160, 2)
          love.graphics.setColor(0.95, 0.82, 0.25, 1)
          love.graphics.polygon("fill",
            2, y + 1, 8, y + 4, 2, y + 7)
        end
        love.graphics.setColor(0, 0, 0, 1)
        F.draw(name, 12, y)
        F.draw(frac, 160 - (#frac * 8) - 8, y)
      end
    end

    love.graphics.setColor(0, 0, 0, 1)
    if self.scroll > 0 then
      love.graphics.polygon("fill", 152, LIST_TOP - 2, 156, LIST_TOP - 2, 154, LIST_TOP - 6)
    end
    if self.scroll + LIST_ROWS < n then
      local by = LIST_TOP + LIST_ROWS * 12 - 2
      love.graphics.polygon("fill", 152, by, 156, by, 154, by + 4)
    end
  end


  love.graphics.setColor(0, 0, 0, 1)
  if self.message then
    local msg = self.message
    if #msg > 19 then msg = msg:sub(1, 19) end
    F.draw(msg, 4, 128)
  else
    F.draw("A:ADD START:DEL", 4, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Screen
