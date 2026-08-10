-- Walk a pret/poketcg map decoded from the TCG ROM.
local V = ...
local Cache = V.require("cache")
local MapGfx = V.require("map_gfx")
local NpcGfx = V.require("npc_gfx")
local TcgText = V.require("tcg_text")

local function Font()
  return require("src.render.Font")
end

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true
Screen.letterboxWhite = true

local VIEW_W, VIEW_H = 160, 144

function Screen:uiSize()
  return VIEW_W, VIEW_H
end

function Screen:wantsFillScale()
  return true
end

function Screen:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, 19, 17) }
end

function Screen:enterMap(key, tx, ty)
  local map, err = MapGfx.load(key)
  if not map then
    self.error = err or "Map load failed"
    return false
  end
  self.error = nil
  self.map = map
  self.mapKey = key
  self.tx = tx or map.spawnX
  self.ty = ty or map.spawnY
  if not MapGfx.canWalk(map, self.tx, self.ty) then
    -- Prefer exact warp dest even if marked solid; else hunt.
    local ok = false
    for y = map.th - 1, 0, -1 do
      for x = 0, map.tw - 1 do
        if MapGfx.canWalk(map, x, y) then
          self.tx, self.ty = x, y
          ok = true
          break
        end
      end
      if ok then break end
    end
  end
  self.walkFrame = false
  self.toast = nil
  self.toastTimer = 0
  -- Ignore warp tiles briefly after a transition so doors don't bounce.
  self.warpIgnore = 12
  return true
end

function Screen.new(game, args)
  args = args or {}
  local self = setmetatable({}, Screen)
  self.game = game
  self.mod = V.mod
  self.error = nil
  self.facing = "south"
  self.moveCooldown = 0
  self.walkFrame = false
  self.toast = nil
  self.toastTimer = 0
  self.warpIgnore = 0

  local ok = Cache.ensure(self.mod)
  if not ok then
    self.error = "Import TCG ROM first"
    return self
  end

  self:enterMap(args.map or "MASON_LABORATORY", args.x, args.y)
  return self
end

local DIRS = {
  up = { 0, -1, "north" },
  down = { 0, 1, "south" },
  left = { -1, 0, "west" },
  right = { 1, 0, "east" },
}

function Screen:applyWarp(warp)
  if not warp then return end
  if self.warpIgnore and self.warpIgnore > 0 then return end
  -- OVERWORLD_MAP (0): leave to hub
  if warp.destId == 0 or not warp.destKey then
    if warp.destId == 0 then
      self.game.stack:pop()
      return
    end
    self.toast = "No map yet"
    self.toastTimer = 90
    return
  end
  self:enterMap(warp.destKey, warp.dx, warp.dy)
end

function Screen:tryMove(dx, dy, facing)
  local nx, ny = self.tx + dx, self.ty + dy
  self.facing = facing
  local warpHere = MapGfx.warpAt(self.map, self.tx, self.ty)
  if MapGfx.canWalk(self.map, nx, ny) then
    self.tx, self.ty = nx, ny
    self.walkFrame = not self.walkFrame
    local w = MapGfx.warpAt(self.map, self.tx, self.ty)
    if w then self:applyWarp(w) end
  elseif warpHere and (nx < 0 or ny < 0 or nx >= self.map.tw or ny >= self.map.th
      or not MapGfx.canWalk(self.map, nx, ny)) then
    self:applyWarp(warpHere)
  end
end

function Screen:finishTalk(npc)
  if not npc then return end
  local cards = NpcGfx.deckCards(npc.deckId)
  if not cards then return end
  self.mod.ui.push(self.game, "TcgBattle", {
    oppDeck = cards,
    oppName = npc.name,
  })
end

function Screen:tryTalk()
  local fx, fy = NpcGfx.facingTile(self.tx, self.ty, self.facing)
  local npc = MapGfx.npcAt(self.map, fx, fy)
  if not npc then return end

  local body = NpcGfx.dialogText(npc) or "..."
  local text = TcgText.toTextBox(body, npc.name or "NPC")
  local TextBox = require("src.render.TextBox")
  local cards = NpcGfx.deckCards(npc.deckId)

  self.game.stack:push(TextBox.new(self.game, text, function()
    if not cards then return end
    local prompt = "Duel with " .. (npc.name or "them") .. "?"
    self.game.stack:push(TextBox.new(self.game, prompt, nil, {
      choice = function(yes)
        if yes then self:finishTalk(npc) end
      end,
    }))
  end))
end

function Screen:update()
  local input = self.game.input
  if self.error then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
    end
    return
  end

  if self.warpIgnore and self.warpIgnore > 0 then
    self.warpIgnore = self.warpIgnore - 1
  end

  if self.toastTimer and self.toastTimer > 0 then
    self.toastTimer = self.toastTimer - 1
    if self.toastTimer <= 0 then self.toast = nil end
  end

  if input:wasPressed("b") then
    self.game.stack:pop()
    return
  end

  if input:wasPressed("a") then
    self:tryTalk()
    return
  end

  if self.moveCooldown > 0 then
    self.moveCooldown = self.moveCooldown - 1
    if self.moveCooldown == 0 then self.walkFrame = false end
    return
  end

  for key, d in pairs(DIRS) do
    if input:wasPressed(key) or input:isDown(key) then
      self:tryMove(d[1], d[2], d[3])
      self.moveCooldown = 8
      break
    end
  end
end

local function drawSprite(img, flip, sx, sy)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  if flip then
    love.graphics.draw(img, sx + 16, sy, 0, -1, 1)
  else
    love.graphics.draw(img, sx, sy)
  end
  return true
end

function Screen:draw()
  local F = Font()
  if self.error then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, VIEW_W, VIEW_H)
    love.graphics.setColor(0, 0, 0, 1)
    F.draw(self.error, 8, 56)
    F.draw("B: back", 8, 120)
    return
  end

  local map = self.map
  local px, py = self.tx * 8, self.ty * 8
  local camX = math.floor(px + 4 - VIEW_W / 2)
  local camY = math.floor(py + 4 - VIEW_H / 2)
  camX = math.max(0, math.min(camX, math.max(0, map.wpx - VIEW_W)))
  camY = math.max(0, math.min(camY, math.max(0, map.hpx - VIEW_H)))

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(map.image, -camX, -camY)

  if map.npcs then
    for _, npc in ipairs(map.npcs) do
      local img, flip = NpcGfx.image(npc)
      local sx = npc.x * 8 - camX
      local sy = npc.y * 8 - camY - 8
      if not drawSprite(img, flip, sx, sy) then
        love.graphics.setColor(0.2, 0.55, 0.9, 1)
        love.graphics.rectangle("fill", sx + 2, sy + 4, 12, 12)
      end
    end
  end

  local img, flip = MapGfx.playerImage(self.facing, self.walkFrame)
  local sx = px - camX
  local sy = py - camY - 8
  if not drawSprite(img, flip, sx, sy) then
    love.graphics.setColor(0.95, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", sx + 2, sy + 4, 12, 12)
  end

  local P = require("src.render.PaletteFX")
  if P.markTrueColor then
    P.markTrueColor(0, 0, VIEW_W, VIEW_H)
  end

  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, VIEW_W, 12)
  love.graphics.setColor(1, 1, 1, 1)
  local title = map.label or "MAP"
  if #title > 12 then title = title:sub(1, 12) end
  F.draw(title, 4, 2)
  F.draw("A/B", 128, 2)

  if self.toast then
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 8, 118, 144, 18)
    love.graphics.setColor(1, 1, 1, 1)
    local msg = self.toast
    if #msg > 18 then msg = msg:sub(1, 18) end
    F.draw(msg, 12, 123)
  end
end

return Screen
