local V = ...

local function Font()
  return require("src.render.Font")
end

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

function Screen.new(game, args)
  local self = setmetatable({}, Screen)
  self.game = game
  self.error = args and args.error or "Import Pinball ROM"
  return self
end

function Screen:update()
  if self.game.input:wasPressed("a") or self.game.input:wasPressed("b")
    or self.game.input:wasPressed("start") then
    self.game.stack:pop()
  end
end

function Screen:draw()
  local F = Font()
  love.graphics.setColor(0.12, 0.12, 0.18, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 1, 1)
  F.draw("PINBALL ROM", 24, 24)
  love.graphics.setColor(0.95, 0.85, 0.4, 1)
  local msg = tostring(self.error or "")
  local y = 48
  while #msg > 0 do
    local line = msg:sub(1, 18)
    msg = msg:sub(19)
    F.draw(line, 8, y)
    y = y + 12
    if y > 110 then break end
  end
  love.graphics.setColor(0.8, 0.8, 0.8, 1)
  F.draw("Place ROM at:", 8, 116)
  F.draw("mod/roms/", 8, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

return Screen
