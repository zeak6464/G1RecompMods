local V = ...
local Cache = V.require("cache")
local CardGfx = V.require("card_gfx")

local function Font()
  return require("src.render.Font")
end

local View = {}
View.__index = View
View.isOpaque = true

local COST_ORDER = {
  "FIRE", "GRASS", "LIGHTNING", "WATER", "FIGHTING", "PSYCHIC", "COLORLESS",
}

local function expandCost(cost)
  local out = {}
  if not cost then return out end
  for _, typ in ipairs(COST_ORDER) do
    local n = cost[typ] or 0
    for _ = 1, n do out[#out + 1] = typ end
  end
  return out
end

local function drawTypePip(x, y, typ)
  local r, g, b = CardGfx.typeColor({ kind = "pokemon", type = typ or "COLORLESS" })
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", x, y, 7, 7)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x, y, 7, 7)
end

function View:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  return P.wholeNamed(game.data, "MEWMON")
end

function View.new(game, args)
  args = args or {}
  local self = setmetatable({}, View)
  self.game = game
  self.cardId = args.cardId
  self.count = args.count
  self.damage = args.damage
  self.maxHp = args.maxHp
  self.title = args.title
  return self
end

function View:update()
  if self.game.input:wasPressed("a") or self.game.input:wasPressed("b") then
    self.game.stack:pop()
  end
end

function View:drawPokemon(card)
  local F = Font()

  -- red double border like GBC card page
  love.graphics.setColor(0.80, 0.18, 0.12, 1)
  love.graphics.rectangle("line", 2, 2, 156, 140)
  love.graphics.rectangle("line", 4, 4, 152, 136)

  -- header: type pip + name + Lv + HP
  drawTypePip(8, 8, card.type)
  love.graphics.setColor(0, 0, 0, 1)
  local name = card.name or "?"
  if #name > 10 then name = name:sub(1, 10) end
  F.draw(name, 18, 8)
  F.draw(("Lv%d"):format(card.level or 0), 104, 8)
  if self.maxHp ~= nil and self.damage ~= nil then
    local cur = math.max(0, self.maxHp - self.damage)
    F.draw(("HP%d"):format(cur), 128, 8)
  else
    F.draw(("HP%d"):format(card.hp or 0), 128, 8)
  end

  -- art
  CardGfx.drawFrame(self.cardId, 48, 20, 1)

  -- attacks
  local y = 74
  local attacks = card.attacks or {}
  if #attacks == 0 then
    love.graphics.setColor(0, 0, 0, 1)
    F.draw("(no attacks)", 8, y)
    y = y + 12
  else
    for _, atk in ipairs(attacks) do
      local costs = expandCost(atk.cost)
      local x = 8
      if #costs == 0 then
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.rectangle("fill", x, y + 1, 7, 7)
        x = x + 10
      else
        for i, typ in ipairs(costs) do
          if i > 4 then break end
          drawTypePip(x, y + 1, typ)
          x = x + 9
        end
      end
      love.graphics.setColor(0, 0, 0, 1)
      local aname = atk.name or "ATTACK"
      if #aname > 10 then aname = aname:sub(1, 10) end
      F.draw(aname, math.max(x, 48), y)
      if (atk.damage or 0) > 0 then
        F.draw(tostring(atk.damage), 140, y)
      end
      y = y + 12
      if y > 108 then break end
    end
  end

  -- footer stats
  love.graphics.setColor(0, 0, 0, 1)
  F.draw("RETREAT", 8, 112)
  local rx = 64
  local retreat = card.retreat or 0
  if retreat <= 0 then
    F.draw("-", rx, 112)
  else
    for i = 1, math.min(retreat, 4) do
      drawTypePip(rx + (i - 1) * 9, 113, "COLORLESS")
    end
  end

  F.draw("WEAK", 8, 124)
  if card.weakness then
    drawTypePip(48, 125, card.weakness)
  else
    F.draw("-", 48, 124)
  end

  F.draw("RESIST", 72, 124)
  if card.resistance then
    drawTypePip(120, 125, card.resistance)
  else
    F.draw("-", 120, 124)
  end

  F.draw(("No.%03d"):format(card.dex or 0), 8, 134)
end

function View:drawSimple(card)
  local F = Font()
  CardGfx.drawFrame(self.cardId, 48, 16, 1)
  love.graphics.setColor(0, 0, 0, 1)
  F.draw(card and card.name or "?", 8, 80)
  F.draw(card and (card.kind or ""):upper() or "", 8, 92)
  if card and card.kind == "energy" then
    F.draw(card.energyType or card.type or "", 8, 104)
  end
  F.draw("A/B: back", 8, 128)
end

function View:draw()
  love.graphics.setColor(0.98, 0.96, 0.92, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  local card = Cache.card(self.cardId)
  if card and card.kind == "pokemon" then
    self:drawPokemon(card)
  else
    self:drawSimple(card)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return View
