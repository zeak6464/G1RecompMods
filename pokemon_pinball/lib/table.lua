-- Custom pinball table: one tall world (TOP+BOTTOM art stacked), camera follows ball.
-- ROM graphics only — mechanics are ours (pret LUTs are not ported).
local V = ...
local Physics = V.require("physics")

local Table = {}

Table.WORLD_W = 160
Table.WORLD_H = 288 -- 144 top + 144 bottom
Table.VIEW_H = 144
Table.BOTTOM_Y = 144 -- world Y where bottom field art starts

local function offsetY(list, dy)
  local out = {}
  for i, w in ipairs(list) do
    if w.x then
      out[i] = { x = w.x, y = w.y + dy, r = w.r, score = w.score, w = w.w, h = w.h, tag = w.tag }
    else
      out[i] = { w[1], w[2] + dy, w[3], w[4] + dy }
    end
  end
  return out
end

-- Closed rails matching the white playfield (inside the painted red border).
-- Digletts sit in the border — ball must not enter that art.
local function wallsWorld()
  local by = Table.BOTTOM_Y
  local W = {}
  local function add(x1, y1, x2, y2)
    W[#W + 1] = { x1, y1, x2, y2 }
  end

  -- continuous left rail (full table)
  add(16, 20, 16, by + 118)
  -- continuous right rail for TOP + upper BOTTOM (main field, not plunger)
  add(144, 20, 144, by + 16)
  -- top ceiling
  add(16, 20, 144, 20)

  -- bottom main-field right rail (stops before Diglett / plunger)
  add(132, by + 16, 132, by + 118)
  -- bridge from top-right rail into bottom main rail
  add(144, by + 16, 132, by + 16)

  -- plunger alley (separate channel on the far right)
  add(140, by + 16, 140, by + 128) -- alley left wall
  add(154, by + 16, 154, by + 128) -- alley outer wall
  add(140, by + 16, 154, by + 16) -- alley roof (exit is forced left in step)

  -- bottom apron / drain rails (gap between flippers stays open)
  add(16, by + 118, 48, by + 138)
  add(132, by + 118, 112, by + 138)

  -- inner lane guides (approx red-field arrows / side posts)
  add(28, by + 30, 28, by + 70)
  add(120, by + 30, 120, by + 70)
  add(40, 50, 40, 100)
  add(120, 50, 120, 100)

  return W
end

-- Solid circles for border Digletts / posts the ball must bounce off.
local function solidsWorld()
  local by = Table.BOTTOM_Y
  return {
    -- bottom Diglett mounds (yellow circles in the red border)
    { x = 22, y = by + 52, r = 11 },
    { x = 138, y = by + 52, r = 11 },
    { x = 22, y = by + 78, r = 9 },
    { x = 138, y = by + 78, r = 9 },
    -- upper side posts
    { x = 24, y = 70, r = 8 },
    { x = 136, y = 70, r = 8 },
    -- mid posts near secondary flipper art
    { x = 36, y = by + 95, r = 6 },
    { x = 124, y = by + 95, r = 6 },
  }
end

local function bumpersWorld(red)
  local top, bot
  if red then
    top = {
      { x = 40, y = 50, r = 7, score = 100 },
      { x = 80, y = 40, r = 8, score = 120 },
      { x = 120, y = 50, r = 7, score = 100 },
      { x = 60, y = 85, r = 6, score = 150 },
      { x = 100, y = 85, r = 6, score = 150 },
    }
    bot = {
      { x = 50, y = 40, r = 7, score = 100 },
      { x = 80, y = 28, r = 7, score = 100 },
      { x = 110, y = 40, r = 7, score = 100 },
      { x = 65, y = 68, r = 6, score = 150 },
      { x = 95, y = 68, r = 6, score = 150 },
    }
  else
    top = {
      { x = 36, y = 48, r = 7, score = 100 },
      { x = 80, y = 36, r = 8, score = 120 },
      { x = 124, y = 48, r = 7, score = 100 },
      { x = 55, y = 85, r = 6, score = 160 },
      { x = 105, y = 85, r = 6, score = 160 },
    }
    bot = {
      { x = 45, y = 36, r = 7, score = 100 },
      { x = 80, y = 24, r = 8, score = 120 },
      { x = 115, y = 36, r = 7, score = 100 },
      { x = 55, y = 70, r = 6, score = 160 },
      { x = 105, y = 70, r = 6, score = 160 },
    }
  end
  local out = {}
  for _, b in ipairs(top) do out[#out + 1] = b end
  for _, b in ipairs(offsetY(bot, Table.BOTTOM_Y)) do out[#out + 1] = b end
  return out
end

function Table.layout(field)
  field = field or "RED"
  local red = field == "RED"
  local by = Table.BOTTOM_Y
  return {
    field = field,
    bg = red and { 0.72, 0.22, 0.20 } or { 0.18, 0.28, 0.70 },
    accent = red and { 0.95, 0.75, 0.25 } or { 0.45, 0.85, 0.95 },
    walls = wallsWorld(),
    solids = solidsWorld(),
    bumpers = bumpersWorld(red),
    -- slots live on bottom art
    catchSlot = { x = 78, y = by + 18, w = 16, h = 10 },
    mapSlot = { x = 36, y = by + 50, w = 12, h = 12 },
    evoSlot = { x = 112, y = by + 50, w = 12, h = 12 },
    bonusSlot = { x = 72, y = by + 90, w = 16, h = 10 },
    monZone = { x = 80, y = by + 48, r = 10 },
    flippers = {
      { x = 52, y = by + 119, len = 28, rest = 0.65, swing = -1.15, side = "L" },
      { x = 108, y = by + 119, len = 28, rest = math.pi - 0.65, swing = 1.15, side = "R" },
    },
    flipperSprite = {
      L = { x = 48, y = by + 107 },
      R = { x = 96, y = by + 107 },
    },
    drainY = by + 142,
    launch = { x = 146, y = by + 124 },
    launchAlley = { x = 140, yMin = by + 16, yMax = by + 140 },
    -- hard box for main field (alley handled separately)
    fieldBox = { minX = 16, minY = 20, maxX = 132, maxY = by + 140 },
    alleyBox = { minX = 140, minY = by + 16, maxX = 154, maxY = by + 140 },
  }
end

function Table.newGame(field)
  return {
    layout = Table.layout(field),
    camY = Table.BOTTOM_Y, -- start looking at bottom (plunger)
    score = 0,
    balls = 3,
    ball = nil,
    leftUp = false,
    rightUp = false,
    prevLeftUp = false,
    prevRightUp = false,
    multiplier = 1,
    ballSaver = 0,
    launched = false,
    plunger = 0,
    flash = 0,
    message = nil,
    messageT = 0,
  }
end

function Table.spawnBall(game)
  local L = game.layout
  game.ball = Physics.newBall(L.launch.x, L.launch.y)
  game.launched = false
  game.plunger = 0
  game.ballSaver = 120
  game.camY = Table.BOTTOM_Y
end

local function armPlunger(game, msg)
  local L = game.layout
  local ball = game.ball
  if not ball then return end
  ball.x, ball.y = L.launch.x, L.launch.y
  ball.vx, ball.vy = 0, 0
  ball.alive = true
  game.launched = false
  game.plunger = 0
  game.camY = Table.BOTTOM_Y
  if msg then Table.setMessage(game, msg, 50) end
end

function Table.addScore(game, n)
  game.score = game.score + math.floor(n * (game.multiplier or 1))
  game.flash = 8
end

function Table.setMessage(game, msg, frames)
  game.message = msg
  game.messageT = frames or 70
end

function Table.updateCamera(game)
  local ball = game.ball
  local target = Table.BOTTOM_Y
  if ball and ball.alive then
    target = ball.y - Table.VIEW_H * 0.45
  end
  target = Physics.clamp(target, 0, Table.WORLD_H - Table.VIEW_H)
  -- smooth follow
  game.camY = game.camY + (target - game.camY) * 0.18
end

local function containBall(L, ball)
  local alley = L.launchAlley
  if alley and ball.x >= alley.x - 1 then
    local b = L.alleyBox
    Physics.containBox(ball, b.minX, b.minY, b.maxX, b.maxY, 0.75)
  else
    local b = L.fieldBox
    Physics.containBox(ball, b.minX, b.minY, b.maxX, b.maxY, 0.75)
  end
end

local function collideAll(game, ball, events, leftRising, rightRising)
  local L = game.layout
  for _, w in ipairs(L.walls) do
    Physics.collideSegment(ball, w[1], w[2], w[3], w[4], 0.92)
  end
  for _, s in ipairs(L.solids) do
    Physics.collideCircle(ball, s.x, s.y, s.r, 0.4, 0.95)
  end
  for _, f in ipairs(L.flippers) do
    local up = (f.side == "L" and game.leftUp) or (f.side == "R" and game.rightUp)
    local rising = (f.side == "L" and leftRising) or (f.side == "R" and rightRising)
    if Physics.collideFlipper(ball, f, up, rising) then
      Table.addScore(game, 10)
    end
  end
  for _, b in ipairs(L.bumpers) do
    if Physics.collideCircle(ball, b.x, b.y, b.r, 1.7, 1.05) then
      Table.addScore(game, b.score)
      events.bumper = (events.bumper or 0) + 1
    end
  end
  containBall(L, ball)
end

function Table.step(game, events)
  events = events or {}
  local L = game.layout
  local ball = game.ball
  if not ball or not ball.alive then
    Table.updateCamera(game)
    return events
  end

  if game.messageT > 0 then
    game.messageT = game.messageT - 1
    if game.messageT <= 0 then game.message = nil end
  end
  if game.flash > 0 then game.flash = game.flash - 1 end
  if game.ballSaver > 0 then game.ballSaver = game.ballSaver - 1 end

  if not game.launched then
    if events.plungeHold then
      game.plunger = math.min(1, game.plunger + 0.03)
    elseif game.plunger > 0.04 and events.plungeRelease then
      local power = math.max(game.plunger, 0.55)
      ball.vy = -5.0 - power * 3.5
      ball.vx = -0.15
      game.launched = true
      game.plunger = 0
      game.ballSaver = 120
    end
    game.prevLeftUp = game.leftUp
    game.prevRightUp = game.rightUp
    Table.updateCamera(game)
    return events
  end

  local leftRising = game.leftUp and not game.prevLeftUp
  local rightRising = game.rightUp and not game.prevRightUp
  Physics.applyGravity(ball)
  ball.vx = ball.vx * Physics.FRICTION
  ball.vy = ball.vy * Physics.FRICTION
  Physics.limitSpeed(ball)
  -- more substeps = less tunneling through rails
  local steps = 4
  for step = 1, steps do
    Physics.move(ball, 1 / steps)
    collideAll(game, ball, events,
      step == 1 and leftRising,
      step == 1 and rightRising)
  end

  -- exit plunger lane into the field at the alley top
  local alley = L.launchAlley
  if alley and ball.x > alley.x and ball.y <= alley.yMin + 6 and ball.vy < 0 then
    ball.vx = math.min(ball.vx, -2.0)
    ball.x = alley.x - ball.r - 1
  end

  local function slot(s)
    if Physics.inRect(ball, s.x, s.y, s.w, s.h) then
      ball.vy = math.min(ball.vy, -2.2)
      return true
    end
    return false
  end
  if slot(L.catchSlot) then Table.addScore(game, 500); events.catchSlot = true end
  if slot(L.mapSlot) then Table.addScore(game, 300); events.mapSlot = true end
  if slot(L.evoSlot) then Table.addScore(game, 300); events.evoSlot = true end
  if slot(L.bonusSlot) then Table.addScore(game, 1000); events.bonusSlot = true end

  if events.modeTarget and L.monZone then
    local z = L.monZone
    if Physics.collideCircle(ball, z.x, z.y, z.r, 1.2, 1.0) then
      events.hitModeTarget = true
      Table.addScore(game, 800)
    end
  end

  -- failed plunge: settle back in alley → re-arm
  if alley and ball.x > alley.x + 1 and ball.y > alley.yMin + 40 and ball.y < alley.yMax then
    if Physics.len(ball.vx, ball.vy) < 1.0 then
      armPlunger(game, "AGAIN")
      game.prevLeftUp = game.leftUp
      game.prevRightUp = game.rightUp
      Table.updateCamera(game)
      return events
    end
  end

  if ball.y > L.drainY then
    if game.ballSaver > 0 then
      ball.x, ball.y = 80, Table.BOTTOM_Y + 90
      ball.vy = -3.8
      ball.vx = 0
      Table.setMessage(game, "BALL SAVE!", 50)
    else
      ball.alive = false
      events.drain = true
    end
  end

  containBall(L, ball)

  game.prevLeftUp = game.leftUp
  game.prevRightUp = game.rightUp
  Table.updateCamera(game)
  return events
end

return Table
