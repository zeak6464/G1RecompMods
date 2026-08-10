-- Simplified bonus stage layouts.
local Bonus = {}

local SPECS = {
  GENGAR = {
    label = "GENGAR",
    time = 60 * 20,
    goal = 5,
    color = { 0.45, 0.20, 0.55 },
    targets = {
      { x = 40, y = 50, r = 8 },
      { x = 80, y = 40, r = 8 },
      { x = 120, y = 50, r = 8 },
      { x = 60, y = 80, r = 7 },
      { x = 100, y = 80, r = 7 },
    },
  },
  MEWTWO = {
    label = "MEWTWO",
    time = 60 * 22,
    goal = 6,
    color = { 0.70, 0.55, 0.80 },
    targets = {
      { x = 80, y = 36, r = 10 },
      { x = 50, y = 70, r = 7 },
      { x = 110, y = 70, r = 7 },
      { x = 80, y = 95, r = 7 },
    },
  },
  MEOWTH = {
    label = "MEOWTH",
    time = 60 * 18,
    goal = 8,
    color = { 0.85, 0.75, 0.35 },
    targets = {
      { x = 45, y = 55, r = 6 },
      { x = 80, y = 45, r = 6 },
      { x = 115, y = 55, r = 6 },
      { x = 55, y = 90, r = 6 },
      { x = 105, y = 90, r = 6 },
    },
  },
  DIGLETT = {
    label = "DIGLETT",
    time = 60 * 16,
    goal = 7,
    color = { 0.55, 0.35, 0.25 },
    targets = {
      { x = 35, y = 60, r = 6 },
      { x = 55, y = 50, r = 6 },
      { x = 80, y = 45, r = 6 },
      { x = 105, y = 50, r = 6 },
      { x = 125, y = 60, r = 6 },
    },
  },
  SEEL = {
    label = "SEEL",
    time = 60 * 18,
    goal = 5,
    color = { 0.55, 0.70, 0.85 },
    targets = {
      { x = 50, y = 55, r = 8 },
      { x = 80, y = 40, r = 8 },
      { x = 110, y = 55, r = 8 },
      { x = 80, y = 85, r = 8 },
    },
  },
}

Bonus.ORDER = { "GENGAR", "MEWTWO", "MEOWTH", "DIGLETT", "SEEL" }

function Bonus.spec(id)
  return SPECS[id]
end

function Bonus.new(id)
  local s = SPECS[id]
  if not s then return nil end
  local targets = {}
  for i, t in ipairs(s.targets) do
    targets[i] = { x = t.x, y = t.y, r = t.r, hit = false }
  end
  return {
    id = id,
    label = s.label,
    color = s.color,
    timer = s.time,
    goal = s.goal,
    hits = 0,
    targets = targets,
    done = false,
    score = 0,
  }
end

-- Phys = physics module with collideCircle
function Bonus.tick(state, ball, Phys)
  if state.done then return "idle" end
  state.timer = state.timer - 1
  for _, t in ipairs(state.targets) do
    if not t.hit and Phys.collideCircle(ball, t.x, t.y, t.r, 1.5, 1.0) then
      t.hit = true
      state.hits = state.hits + 1
      state.score = state.score + 5000
    end
  end
  if state.hits > 0 and state.hits % #state.targets == 0 then
    for _, t in ipairs(state.targets) do t.hit = false end
  end
  if state.hits >= state.goal then
    state.done = true
    state.score = state.score + 25000
    return "win"
  end
  if state.timer <= 0 then
    state.done = true
    return "timeout"
  end
  return nil
end

return Bonus
