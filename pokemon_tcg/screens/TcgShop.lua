local V = ...
local Save = V.require("save")
local Pack = V.require("pack")
local PackGfx = V.require("pack_gfx")

local function Font()
  return require("src.render.Font")
end

-- Simple "received a booster" beat matching GBC TCG flow.
local Received = {}
Received.__index = Received
Received.isOpaque = true

function Received:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, 19, 17) }
end

function Received.new(game, args)
  local self = setmetatable({}, Received)
  self.game = game
  self.setName = args and args.setName or "COLOSSEUM"
  self.player = (game.save.player and game.save.player.name) or "PLAYER"
  return self
end

function Received:update()
  if self.game.input:wasPressed("a") or self.game.input:wasPressed("b") then
    self.game.stack:pop()
  end
end

function Received:draw()
  local F = Font()
  love.graphics.setColor(0.95, 0.92, 0.82, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  local scale = 1
  local pw = PackGfx.WIDTH * scale
  local px = math.floor((160 - pw) / 2)
  local py = 2
  if not PackGfx.draw(self.setName, px, py, scale) then
    love.graphics.setColor(0.95, 0.75, 0.15, 1)
    love.graphics.rectangle("fill", 52, 12, 56, 80)
    love.graphics.setColor(0, 0, 0, 1)
    F.draw("PACK", 64, 16)
    F.draw(self.setName:sub(1, 8), 48, 82)
  end

  love.graphics.setColor(0.98, 0.95, 0.88, 1)
  love.graphics.rectangle("fill", 0, 100, 160, 44)
  love.graphics.setColor(0.75, 0.15, 0.15, 1)
  love.graphics.rectangle("line", 1, 101, 158, 42)
  love.graphics.setColor(0, 0, 0, 1)
  local name = self.player:sub(1, 7)
  F.draw(name .. " RECEIVED A", 8, 108)
  F.draw("BOOSTER PACK:", 8, 118)
  F.draw(self.setName .. ".", 8, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

local Shop = {}

local SHORT = {
  COLOSSEUM = "COLOSSEUM",
  EVOLUTION = "EVOLUTION",
  MYSTERY = "MYSTERY",
  LABORATORY = "LABORATORY",
  ENERGY = "ENERGY",
  PROMOTIONAL = "PROMO",
}

function Shop.open(game, mod)
  local items = {}
  for _, set in ipairs(Pack.shopSets()) do
    local price = Pack.price(set)
    items[#items + 1] = {
      label = (SHORT[set] or set):sub(1, 12),
      value = set,
      right = ("%d"):format(price),
    }
  end
  return mod.ui.ListMenu.new(game, "BUY PACKS", items, {
    dialogue = true,
    money = function() return game.save.money or 0 end,
    footer = "Choose a pack.",
    onChoose = function(item, menu)
      local price = Pack.price(item.value)
      local money = game.save.money or 0
      if money < price then
        menu.footer = "Not enough money!"
        return
      end
      game.save.money = money - price
      Save.addPack(mod, item.value, 1)
      menu:close()
      game.stack:push(Received.new(game, { setName = item.value }))
    end,
  })
end

return Shop
