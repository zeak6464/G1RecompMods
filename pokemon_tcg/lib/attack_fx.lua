-- Lightweight duel attack FX (not a full pret DUEL_ANIM sprite port).
-- Uses ROM ATK_ANIM id + Pokémon type for style/color.
local V = ...
local CardGfx = V.require("card_gfx")

local AttackFx = {}

-- Portrait top-left (matches TcgBattle:drawField)
local PORTRAIT = {
  player = { x = 6, y = 56, w = 64, h = 48 },
  opp = { x = 92, y = 6, w = 64, h = 48 },
}

local function centerOf(side)
  local p = PORTRAIT[side]
  return p.x + p.w / 2, p.y + p.h / 2
end

-- Map pret ATK_ANIM_* ranges → FX family (see attack_animations.asm pointer table).
local function familyFor(animId)
  animId = animId or 1
  if animId == 0 then return "none" end
  if animId <= 5 then return "hit" end -- HIT / BIG_HIT / recoil
  if animId <= 13 then return "thunder" end
  if animId <= 16 then return "flame" end
  if animId == 17 then return "dive" end
  if animId <= 24 then return "water" end
  if animId <= 30 then return "psychic" end
  if animId <= 31 then return "beam" end
  if animId <= 40 then return "fight" end -- rock / punch / slash
  if animId <= 50 then return "gas" end
  if animId <= 55 then return "status" end -- protect / barrier / etc
  if animId <= 60 then return "heal" end
  return "hit"
end

function AttackFx.start(opts)
  opts = opts or {}
  local from = opts.from or "player"
  local to = opts.selfHit and from or (from == "player" and "opp" or "player")
  local typ = opts.pkmnType or "COLORLESS"
  local r, g, b = CardGfx.typeColor({ kind = "pokemon", type = typ })
  local family = familyFor(opts.animId)
  local ax, ay = centerOf(from)
  local dx, dy = centerOf(to)
  return {
    t = 0,
    from = from,
    to = to,
    family = family,
    damage = opts.damage or 0,
    name = opts.name or "ATTACK",
    color = { r, g, b },
    ax = ax, ay = ay,
    dx = dx, dy = dy,
    duration = 54,
    done = false,
  }
end

function AttackFx.update(fx)
  if not fx or fx.done then return true end
  fx.t = fx.t + 1
  if fx.t >= fx.duration then
    fx.done = true
    return true
  end
  return false
end

function AttackFx.shake(fx, side)
  if not fx or fx.done then return 0, 0 end
  local t = fx.t
  -- defender shake during hit window
  if side == fx.to and t >= 22 and t < 38 then
    local amp = (fx.family == "hit" and fx.damage >= 40) and 3 or 2
    return ((t % 2 == 0) and amp or -amp), ((t % 4 < 2) and 1 or -1)
  end
  -- attacker nudge on wind-up
  if side == fx.from and t < 12 then
    local toward = fx.to == "opp" and 1 or -1
    return toward, 0
  end
  return 0, 0
end

local function lerp(a, b, u)
  return a + (b - a) * u
end

function AttackFx.draw(fx)
  if not fx or fx.done then return end
  local t = fx.t
  local cr, cg, cb = fx.color[1], fx.color[2], fx.color[3]
  local Font = require("src.render.Font")

  -- Phase 1: attacker glow
  if t < 14 then
    local a = 0.25 + 0.35 * math.sin(t * 0.8)
    local p = PORTRAIT[fx.from]
    love.graphics.setColor(cr, cg, cb, a)
    love.graphics.rectangle("fill", p.x - 2, p.y - 2, p.w + 4, p.h + 4)
  end

  -- Phase 2: projectile / beam
  if t >= 10 and t < 28 then
    local u = (t - 10) / 18
    local x = lerp(fx.ax, fx.dx, u)
    local y = lerp(fx.ay, fx.dy, u)
    love.graphics.setColor(cr, cg, cb, 1)
    if fx.family == "beam" or fx.family == "psychic" or fx.family == "thunder" then
      love.graphics.setLineWidth(2)
      love.graphics.line(fx.ax, fx.ay, x, y)
      love.graphics.setLineWidth(1)
      love.graphics.circle("fill", x, y, 3 + (fx.family == "thunder" and (t % 3) or 0))
    elseif fx.family == "flame" then
      for i = 0, 2 do
        love.graphics.circle("fill", x - i * 4, y + math.sin((t + i) * 0.7) * 3, 4 - i)
      end
    elseif fx.family == "water" then
      for i = 0, 3 do
        love.graphics.circle("fill", x - i * 3, y + math.cos((t + i) * 0.9) * 2, 2)
      end
    elseif fx.family == "heal" or fx.family == "status" then
      love.graphics.circle("line", fx.ax, fx.ay, 8 + t % 6)
    else
      -- hit / fight / gas / dive: streaking orb
      love.graphics.circle("fill", x, y, 4)
      love.graphics.setColor(1, 1, 1, 0.8)
      love.graphics.circle("fill", x - 2, y - 1, 2)
    end
  end

  -- Phase 3: impact flash on defender
  if t >= 22 and t < 34 then
    local p = PORTRAIT[fx.to]
    local a = (34 - t) / 12
    love.graphics.setColor(1, 1, 1, a * 0.7)
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
    love.graphics.setColor(cr, cg, cb, a)
    love.graphics.circle("line", fx.dx, fx.dy, 6 + (t - 22))
    if (fx.damage or 0) >= 50 then
      love.graphics.circle("line", fx.dx, fx.dy, 12 + (t - 22))
    end
  end

  -- Phase 4: damage / name toast
  if t >= 28 and t < 52 then
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 24, 44, 112, 20)
    love.graphics.setColor(1, 1, 1, 1)
    local name = fx.name or "ATTACK"
    if #name > 12 then name = name:sub(1, 12) end
    Font.draw(name, 28, 46)
    if (fx.damage or 0) > 0 then
      love.graphics.setColor(cr, cg, cb, 1)
      Font.draw(tostring(fx.damage) .. "!", 100, 46)
    else
      love.graphics.setColor(0.7, 0.7, 0.7, 1)
      Font.draw("---", 108, 46)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

AttackFx.PORTRAIT = PORTRAIT

return AttackFx
