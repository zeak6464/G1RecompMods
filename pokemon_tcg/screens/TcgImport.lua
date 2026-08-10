local V = ...
local Cache = V.require("cache")

local function Font()
  return require("src.render.Font")
end

local Import = {}
Import.__index = Import
Import.isOpaque = true

function Import.new(game, args)
  args = args or {}
  local self = setmetatable({}, Import)
  self.game = game
  self.mod = V.mod
  self.error = args.error
  self.message = nil
  return self
end

function Import:tryImport()
  local ok, result = Cache.ensure(self.mod)
  if ok then
    self.message = ("Imported %d cards."):format(#result.cards)
    self.error = nil
  else
    self.error = result
  end
end

function Import:enter()
  self:tryImport()
end

function Import:update()
  local input = self.game.input
  if input:wasPressed("a") then
    if Cache.isReady() then
      self.game.stack:pop()
      self.mod.ui.push(self.game, "TcgHub")
    else
      self:tryImport()
    end
  elseif input:wasPressed("b") then
    self.game.stack:pop()
  end
end

function Import:draw()
  local F = Font()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  F.drawBox(0, 0, 20, 18)
  love.graphics.setColor(0, 0, 0, 1)
  F.draw("POKéMON TCG ROM", 8, 8)
  F.draw("Need TCG (U) ROM:", 8, 24)
  F.draw("roms/PokemonTCG.gbc", 8, 36)
  if self.error then
    local err = tostring(self.error)
    if #err > 18 then err = err:sub(1, 18) end
    F.draw(err, 8, 56)
    F.draw("A: retry  B: back", 8, 120)
  elseif self.message then
    F.draw(self.message, 8, 56)
    F.draw("A: open hub", 8, 120)
  else
    F.draw("Searching...", 8, 56)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Import
