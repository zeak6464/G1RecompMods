local V = ...
local Cache = V.require("cache")
local Save = V.require("save")
local Table = V.require("table")
local Physics = V.require("physics")
local Modes = V.require("modes")
local Bonus = V.require("bonus")
local Species = V.require("data.species")
local Maps = V.require("data.maps")
local StageGfx = V.require("stage_gfx")

local function Font()
  return require("src.render.Font")
end

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

function Screen:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, 19, 17) }
end

function Screen.new(game, args)
  args = args or {}
  local self = setmetatable({}, Screen)
  self.game = game
  self.mod = V.mod
  self.field = args.field or Save.lastField(self.mod) or "RED"
  self.paused = false
  self.gameOver = false
  self.bonusIdx = 1
  self.plungeHeld = false

  local ok = Cache.ensure(self.mod)
  if not ok then
    self.error = "ROM missing"
    return self
  end
  Save.init(self.mod)
  self.catalog = Cache.get()

  local mapList = Maps.forField(self.field)
  local mapIndex = Save.mapIndex(self.mod)
  if mapIndex < 1 or mapIndex > #mapList then mapIndex = 1 end

  self.table = Table.newGame(self.field)
  self.session = Modes.newSession(self.field, mapList, mapIndex)
  self.bonus = nil
  self.bgBottom = StageGfx.background(self.mod, self.field, "BOTTOM")
  self.bgTop = StageGfx.background(self.mod, self.field, "TOP")
  self.ballImage = StageGfx.ball(self.mod)
  self.flipperImages = StageGfx.flippers(self.mod, self.field)
  Table.spawnBall(self.table)
  Table.setMessage(self.table, self.field .. " FIELD", 70)
  return self
end

function Screen:endGame()
  if self.gameOver then return end
  self.gameOver = true
  local best = Save.submitScore(self.mod, self.field, self.table.score)
  Save.setMapIndex(self.mod, self.session.mapIndex)
  Table.setMessage(self.table, best and "NEW RECORD!" or "GAME OVER", 180)
end

function Screen:enterBonus()
  local id = Bonus.ORDER[self.bonusIdx]
  self.bonusIdx = self.bonusIdx % #Bonus.ORDER + 1
  self.bonus = Bonus.new(id)
  -- bonus uses a flat local 160x144 field
  self.bonusFlippers = {
    { x = 52, y = 120, len = 28, rest = 0.65, swing = -1.15, side = "L" },
    { x = 108, y = 120, len = 28, rest = math.pi - 0.65, swing = 1.15, side = "R" },
  }
  Table.setMessage(self.table, "BONUS!", 60)
  local g = self.table
  if g.ball then
    g.ball.x, g.ball.y = 80, 100
    g.ball.vx, g.ball.vy = 0, -2
    g.launched = true
  end
  g.camY = 0
end

function Screen:leaveBonus(result)
  if self.bonus then
    Table.addScore(self.table, self.bonus.score)
    Table.setMessage(self.table,
      result == "win" and "BONUS CLEAR!" or "BONUS END", 70)
  end
  self.bonus = nil
  self.bonusFlippers = nil
  local g = self.table
  if g.ball and g.ball.alive then
    g.ball.x, g.ball.y = 80, Table.BOTTOM_Y + 90
    g.ball.vx, g.ball.vy = 0, -2.5
    g.launched = true
    g.camY = Table.BOTTOM_Y
  end
end

function Screen:update()
  local input = self.game.input
  if self.error then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
    end
    return
  end

  if input:wasPressed("start") then
    if self.gameOver then
      self.game.stack:pop()
      return
    end
    self.paused = not self.paused
  end
  if input:wasPressed("b") and self.paused then
    self.game.stack:pop()
    return
  end
  if self.paused or self.gameOver then
    if self.gameOver and (input:wasPressed("a") or input:wasPressed("b")) then
      self.game.stack:pop()
    end
    return
  end

  local g = self.table
  g.leftUp = input:isDown("a") or input:isDown("left")
  g.rightUp = input:isDown("b") or input:isDown("right")

  local holding = input:isDown("down") or input:isDown("select")
  local plungeRelease = (self.plungeHeld and not holding) or input:wasPressed("up")
  self.plungeHeld = holding
  local events = {
    plungeHold = holding,
    plungeRelease = plungeRelease,
    modeTarget = self.session.mode ~= "idle",
  }

  if self.bonus then
    local ball = g.ball
    if ball and ball.alive then
      Physics.applyGravity(ball)
      Physics.limitSpeed(ball)
      Physics.move(ball)
      Physics.collideSegment(ball, 12, 16, 12, 130, 0.9)
      Physics.collideSegment(ball, 148, 16, 148, 130, 0.9)
      Physics.collideSegment(ball, 12, 16, 148, 16, 0.9)
      for _, f in ipairs(self.bonusFlippers) do
        local up = (f.side == "L" and g.leftUp) or (f.side == "R" and g.rightUp)
        Physics.collideFlipper(ball, f, up, false)
      end
      local result = Bonus.tick(self.bonus, ball, Physics)
      if result == "win" or result == "timeout" then
        self:leaveBonus(result)
      end
      if ball.y > 148 then
        self:leaveBonus("timeout")
        g.balls = g.balls - 1
        if g.balls <= 0 then
          self:endGame()
        else
          Table.spawnBall(g)
        end
      end
    end
    g.camY = 0
    return
  end

  Table.step(g, events)

  if events.bumper then
    local act = Modes.bumpCatchMeter(self.session, events.bumper)
    if act == "start_catch" then
      local id = Modes.startCatch(self.session, self.catalog)
      Table.setMessage(g, "CATCH " .. Species.name(id), 70)
    end
  end
  if events.catchSlot and self.session.mode == "idle" then
    local id = Modes.startCatch(self.session, self.catalog)
    Table.setMessage(g, "CATCH " .. Species.name(id), 70)
  end
  if events.mapSlot and self.session.mode == "idle" then
    Modes.bumpMapMeter(self.session, 2)
    Modes.startMapMove(self.session)
    Table.setMessage(g, "MAP MOVE!", 70)
  end
  if events.evoSlot and self.session.mode == "idle" then
    Modes.startEvo(self.session, Save.caught(self.mod))
    Table.setMessage(g, "EVOLUTION!", 70)
  end
  if events.bonusSlot and self.session.mode == "idle" then
    self:enterBonus()
  end

  if events.hitModeTarget then
    local done = Modes.hitTarget(self.session)
    if done == "complete" then
      local payload = Modes.complete(self.session)
      if payload.mode == "catch" and payload.targetId then
        Save.catch(self.mod, payload.targetId)
        Table.addScore(g, 20000)
        Table.setMessage(g, "GOT " .. Species.name(payload.targetId) .. "!", 100)
      elseif payload.mode == "mapmove" then
        Save.setMapIndex(self.mod, payload.mapIndex)
        Table.addScore(g, 5000)
        Table.setMessage(g, "MAP " .. Modes.mapLabel(self.session), 70)
      elseif payload.mode == "evo" and payload.evoTo then
        Save.catch(self.mod, payload.evoTo)
        Table.addScore(g, 30000)
        Table.setMessage(g,
          Species.name(payload.evoFrom) .. ">" .. Species.name(payload.evoTo),
          100)
      end
    end
  end

  if Modes.tick(self.session) == "timeout" then
    Table.setMessage(g, "TIME UP", 50)
  end

  if events.drain then
    g.balls = g.balls - 1
    if g.balls <= 0 then
      self:endGame()
    else
      Table.spawnBall(g)
      Table.setMessage(g, ("BALL %d"):format(g.balls), 50)
    end
  end
end

local function drawFlipperFallback(f, up, camY, color)
  local x2, y2 = Physics.flipperTip(f, up)
  love.graphics.setColor(color[1], color[2], color[3], 1)
  love.graphics.setLineWidth(6)
  love.graphics.line(f.x, f.y - camY, x2, y2 - camY)
  love.graphics.setLineWidth(1)
  love.graphics.circle("fill", f.x, f.y - camY, 3.5)
end

local function drawFlipperSprite(set, side, up, worldAnchor, camY)
  if not set or not worldAnchor then return false end
  local pose = up and (side .. "_up") or (side .. "_down")
  local spr = set[pose]
  if not spr then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(spr.image, worldAnchor.x, worldAnchor.y - camY, 0, 1, 1, spr.ox, spr.oy)
  return true
end

function Screen:draw()
  local F = Font()
  if self.error then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    F.draw(self.error, 24, 64)
    return
  end

  local g = self.table
  local L = g.layout
  local camY = g.camY or 0

  if self.bonus then
    local c = self.bonus.color
    love.graphics.setColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    for _, t in ipairs(self.bonus.targets) do
      if not t.hit then
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.circle("fill", t.x, t.y, t.r)
      end
    end
    for _, f in ipairs(self.bonusFlippers) do
      local up = (f.side == "L" and g.leftUp) or (f.side == "R" and g.rightUp)
      drawFlipperFallback(f, up, 0, { 0.75, 0.8, 1 })
    end
  else
    -- tall world: TOP art at 0, BOTTOM art at 144, view follows camY
    love.graphics.setColor(1, 1, 1, 1)
    if self.bgTop then
      love.graphics.draw(self.bgTop, 0, 0 - camY)
    else
      love.graphics.setColor(L.bg[1] * 0.7, L.bg[2] * 0.7, L.bg[3] * 0.7, 1)
      love.graphics.rectangle("fill", 0, 0 - camY, 160, 144)
    end
    if self.bgBottom then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self.bgBottom, 0, Table.BOTTOM_Y - camY)
    else
      love.graphics.setColor(L.bg[1], L.bg[2], L.bg[3], 1)
      love.graphics.rectangle("fill", 0, Table.BOTTOM_Y - camY, 160, 144)
    end

    -- flippers (ROM sprite + physics-aligned fallback)
    local flipSet = self.flipperImages
    local anchors = L.flipperSprite
    if not drawFlipperSprite(flipSet, "L", g.leftUp, anchors.L, camY) then
      drawFlipperFallback(L.flippers[1], g.leftUp, camY, { 0.7, 0.75, 0.95 })
    end
    if not drawFlipperSprite(flipSet, "R", g.rightUp, anchors.R, camY) then
      drawFlipperFallback(L.flippers[2], g.rightUp, camY, { 0.7, 0.75, 0.95 })
    end

    -- mode target ring (world → view)
    if self.session.mode ~= "idle" then
      local z = L.monZone
      love.graphics.setColor(1, 1, 0.25, 0.7)
      love.graphics.circle("line", z.x, z.y - camY, z.r + 2)
    end
  end

  -- ball
  if g.ball and g.ball.alive then
    local bx, by = g.ball.x, g.ball.y - (self.bonus and 0 or camY)
    if self.ballImage then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self.ballImage, bx - 8, by - 8)
    else
      love.graphics.setColor(0.9, 0.15, 0.15, 1)
      love.graphics.circle("fill", bx, by, g.ball.r + 1)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.circle("fill", bx, by + 1, g.ball.r - 0.5)
    end
  end

  -- plunger charge (screen-fixed on the right)
  if not g.launched and not self.bonus then
    if g.plunger > 0 then
      love.graphics.setColor(1, 1, 0.2, 1)
      love.graphics.rectangle("fill", 152, 100 - g.plunger * 50, 5, g.plunger * 50)
    end
  end

  -- HUD (screen-fixed, keep short so labels don't overlap)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, 160, 12)
  love.graphics.setColor(1, 1, 1, 1)
  F.draw(tostring(g.score), 2, 2)
  F.draw("x" .. tostring(math.max(0, g.balls)), 70, 2)
  local map = Modes.mapLabel(self.session)
  if #map > 5 then map = map:sub(1, 5) end
  F.draw(map, 100, 2)

  if self.session.mode ~= "idle" and not self.bonus then
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 12, 160, 10)
    love.graphics.setColor(1, 1, 0.45, 1)
    local prog
    if self.session.mode == "evo" then
      prog = ("%d/%d"):format(self.session.evoProgress, self.session.evoNeed)
    else
      prog = ("%d/%d"):format(self.session.hits, self.session.needHits)
    end
    local name = Species.name(self.session.targetId or 25)
    if #name > 7 then name = name:sub(1, 7) end
    F.draw(self.session.mode:upper() .. " " .. name .. " " .. prog, 2, 13)
  end

  if self.bonus then
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 12, 160, 10)
    love.graphics.setColor(1, 0.9, 0.4, 1)
    F.draw(("%s %d/%d"):format(self.bonus.label, self.bonus.hits, self.bonus.goal), 2, 13)
  end

  -- toast under HUD (does not block the table center)
  if g.message then
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 20, 24, 120, 12)
    love.graphics.setColor(1, 1, 1, 1)
    F.draw(g.message:sub(1, 14), 24, 26)
  elseif not g.launched and not self.bonus then
    love.graphics.setColor(1, 1, 1, 0.8)
    F.draw("HOLD DOWN", 52, 26)
  end

  if self.paused then
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    F.draw("PAUSE", 60, 60)
    F.draw("B:QUIT", 56, 80)
  end

  if self.gameOver then
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    F.draw("GAME OVER", 44, 56)
    F.draw(tostring(g.score), 52, 72)
    F.draw("A:EXIT", 56, 96)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return Screen
