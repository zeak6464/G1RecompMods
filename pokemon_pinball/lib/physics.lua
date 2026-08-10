-- Custom pinball physics (not pret LUT ports).
local Physics = {}

Physics.GRAVITY = 0.085
Physics.FRICTION = 0.996
Physics.MAX_SPEED = 5.0
Physics.BALL_R = 3.5

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function len(x, y)
  return math.sqrt(x * x + y * y)
end

local function norm(x, y)
  local d = len(x, y)
  if d < 1e-6 then return 0, 0, 0 end
  return x / d, y / d, d
end

function Physics.newBall(x, y)
  return { x = x, y = y, vx = 0, vy = 0, r = Physics.BALL_R, alive = true }
end

function Physics.applyGravity(ball)
  ball.vy = ball.vy + Physics.GRAVITY
end

function Physics.limitSpeed(ball)
  local s = len(ball.vx, ball.vy)
  if s > Physics.MAX_SPEED then
    local k = Physics.MAX_SPEED / s
    ball.vx = ball.vx * k
    ball.vy = ball.vy * k
  end
end

function Physics.move(ball, scale)
  scale = scale or 1
  -- friction only on full steps; substeps pass scale < 1
  if scale >= 0.999 then
    ball.vx = ball.vx * Physics.FRICTION
    ball.vy = ball.vy * Physics.FRICTION
  end
  ball.x = ball.x + ball.vx * scale
  ball.y = ball.y + ball.vy * scale
end

function Physics.collideSegment(ball, x1, y1, x2, y2, rest)
  rest = rest or 0.85
  local dx, dy = x2 - x1, y2 - y1
  local lx, ly, llen = norm(dx, dy)
  if llen < 1e-6 then return false end
  local nx, ny = -ly, lx
  local px, py = ball.x - x1, ball.y - y1
  local along = px * lx + py * ly
  if along < 0 then
    return Physics.collideCircle(ball, x1, y1, 0, 0, rest)
  end
  if along > llen then
    return Physics.collideCircle(ball, x2, y2, 0, 0, rest)
  end
  local dist = px * nx + py * ny
  if dist < 0 then
    nx, ny, dist = -nx, -ny, -dist
  end
  if dist >= ball.r then return false end
  local pen = ball.r - dist
  ball.x = ball.x + nx * pen
  ball.y = ball.y + ny * pen
  local vn = ball.vx * nx + ball.vy * ny
  if vn < 0 then
    ball.vx = ball.vx - (1 + rest) * vn * nx
    ball.vy = ball.vy - (1 + rest) * vn * ny
  end
  return true
end

function Physics.collideCircle(ball, cx, cy, cr, boost, rest)
  rest = rest or 0.9
  boost = boost or 0
  local dx, dy = ball.x - cx, ball.y - cy
  local nx, ny, d = norm(dx, dy)
  local minD = ball.r + cr
  if d >= minD or d < 1e-6 then return false end
  local pen = minD - d
  ball.x = ball.x + nx * pen
  ball.y = ball.y + ny * pen
  local vn = ball.vx * nx + ball.vy * ny
  if vn < 0 then
    ball.vx = ball.vx - (1 + rest) * vn * nx
    ball.vy = ball.vy - (1 + rest) * vn * ny
  end
  if boost > 0 then
    ball.vx = ball.vx + nx * boost
    ball.vy = ball.vy + ny * boost
  end
  return true
end

-- Angles in screen space (y+ down). rest = down toward drain; swing raises tip.
function Physics.flipperAngle(f, raised)
  if raised then return f.rest + f.swing end
  return f.rest
end

function Physics.flipperTip(f, raised)
  local ang = Physics.flipperAngle(f, raised)
  return f.x + math.cos(ang) * f.len, f.y + math.sin(ang) * f.len
end

function Physics.collideFlipper(ball, f, raised, justPressed)
  local x2, y2 = Physics.flipperTip(f, raised)
  local hit = Physics.collideSegment(ball, f.x, f.y, x2, y2, 0.35)
  -- fatten with endpoint hubs
  if Physics.collideCircle(ball, f.x, f.y, 4, 0, 0.35) then hit = true end
  if Physics.collideCircle(ball, x2, y2, 3.5, 0, 0.35) then hit = true end
  if not hit then return false end

  if raised or justPressed then
    local power = justPressed and 5.0 or 2.4
    local inward = (f.side == "L") and 2.2 or -2.2
    ball.vx = ball.vx * 0.25 + inward
    ball.vy = math.min(ball.vy, 0) - power
  end
  return true
end

function Physics.inRect(ball, x, y, w, h)
  return ball.x >= x and ball.x <= x + w and ball.y >= y and ball.y <= y + h
end

-- Bounce off an axis-aligned inward box (keeps ball inside).
function Physics.containBox(ball, minX, minY, maxX, maxY, rest)
  rest = rest or 0.7
  local hit = false
  if ball.x - ball.r < minX then
    ball.x = minX + ball.r
    if ball.vx < 0 then ball.vx = -ball.vx * rest end
    hit = true
  elseif ball.x + ball.r > maxX then
    ball.x = maxX - ball.r
    if ball.vx > 0 then ball.vx = -ball.vx * rest end
    hit = true
  end
  if ball.y - ball.r < minY then
    ball.y = minY + ball.r
    if ball.vy < 0 then ball.vy = -ball.vy * rest end
    hit = true
  end
  return hit
end

Physics.clamp = clamp
Physics.len = len
Physics.norm = norm

return Physics
