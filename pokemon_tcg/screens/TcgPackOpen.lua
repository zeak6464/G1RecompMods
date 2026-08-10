local V = ...
local Cache = V.require("cache")
local Save = V.require("save")
local Pack = V.require("pack")
local CardGfx = V.require("card_gfx")

local function Font()
  return require("src.render.Font")
end

local Open = {}
Open.__index = Open
Open.isOpaque = true

function Open:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  return P.wholeNamed(game.data, "MEWMON")
end

local function beginOpen(self, setName)
  if not Save.consumePack(self.mod, setName) then
    self.error = "No packs to open!"
    return
  end
  self.setName = setName
  self.cards = Pack.open(setName)
  Save.addCards(self.mod, self.cards)
  self.index = 1
end

-- Picker when OPEN PACK is chosen with no set selected yet.
function Open.pick(game, mod)
  Save.init(mod)
  local counts = Save.packCounts(mod)
  local items = {}
  for _, set in ipairs(Save.PACK_SETS) do
    local n = counts[set] or 0
    if n > 0 then
      items[#items + 1] = {
        label = set,
        value = set,
        right = "x" .. tostring(n),
      }
    end
  end
  if #items == 0 then
    return Open.new(game, { error = "No packs to open!" })
  end
  return mod.ui.ListMenu.new(game, "OPEN PACK", items, {
    footer = "Choose a pack.",
    onChoose = function(item, menu)
      menu:close()
      mod.ui.push(game, "TcgPackOpen", { setName = item.value })
    end,
  })
end

function Open.new(game, args)
  args = args or {}
  local self = setmetatable({}, Open)
  self.game = game
  self.mod = V.mod
  self.cards = nil
  self.index = 1
  self.error = args.error
  self.setName = args.setName
  if self.error then
    return self
  end
  if not self.setName then
    -- Should go through Open.pick; consume nothing.
    self.error = "No pack selected!"
    return self
  end
  beginOpen(self, self.setName)
  return self
end

function Open:update()
  if self.game.input:wasPressed("a") or self.game.input:wasPressed("b") then
    if self.error or not self.cards then
      self.game.stack:pop()
      return
    end
    if self.index < #self.cards then
      self.index = self.index + 1
    else
      self.game.stack:pop()
    end
  end
end

function Open:draw()
  local F = Font()
  love.graphics.setColor(0.95, 0.92, 0.82, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  if self.error then
    love.graphics.setColor(0, 0, 0, 1)
    F.draw(self.error, 8, 56)
    F.draw("A/B: back", 8, 120)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local id = self.cards[self.index]
  local card = Cache.card(id)
  -- 2× fits above the text box; fractional scales shred nearest-neighbor pixels.
  local scale = 2
  local aw = CardGfx.WIDTH * scale
  local ax = math.floor((160 - aw) / 2)
  local ay = 2
  CardGfx.drawFrame(id, ax, ay, scale)

  love.graphics.setColor(0.98, 0.95, 0.88, 1)
  love.graphics.rectangle("fill", 0, 100, 160, 44)
  love.graphics.setColor(0.75, 0.15, 0.15, 1)
  love.graphics.rectangle("line", 1, 101, 158, 42)
  love.graphics.setColor(0, 0, 0, 1)
  F.draw(("%d / %d"):format(self.index, #self.cards), 8, 104)
  F.draw(card and card.name or "?", 8, 114)
  if card and card.kind == "pokemon" then
    F.draw(("HP%d %s"):format(card.hp or 0, card.type or ""), 8, 124)
  else
    F.draw(card and (card.kind or ""):upper() or "", 8, 124)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Open
