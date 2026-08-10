-- Simple greedy AI guided by pret scoring ideas (not a full port).
local V = ...
local Cache = V.require("cache")
local Effects = V.require("effects")

local AI = {}

local function canPay(mon, cost)
  if not cost then return true end
  local have = {}
  for k, v in pairs(mon.energy) do have[k] = v end
  for typ, need in pairs(cost) do
    if typ ~= "COLORLESS" then
      if (have[typ] or 0) < need then return false end
      have[typ] = have[typ] - need
    end
  end
  local leftover = 0
  for _, v in pairs(have) do leftover = leftover + v end
  return leftover >= (cost.COLORLESS or 0)
end

function AI.takeTurn(battle)
  local side = battle:current()
  local Battle = V.require("battle")

  -- Play Bill / Potion if useful.
  for i, id in ipairs(side.hand) do
    local c = Cache.card(id)
    if c and c.kind == "trainer" then
      if c.key == "BILL" and #side.deck >= 2 then
        battle:playTrainer(i)
        break
      elseif c.key == "POTION" and side.active and side.active.damage >= 20 then
        battle:playTrainer(i)
        break
      elseif c.key == "FULL_HEAL" and side.active
        and (side.active.poisoned or side.active.asleep
          or side.active.paralyzed or side.active.confused) then
        battle:playTrainer(i)
        break
      end
    end
  end

  -- Evolve if possible.
  for i, id in ipairs(side.hand) do
    local targets = battle:evolveTargets(i)
    if #targets > 0 then
      battle:evolve(i, targets[1].target)
      break
    end
  end

  -- Play one Basic to bench if space (max 5).
  if #side.bench < Battle.BENCH_MAX then
    for i, id in ipairs(side.hand) do
      local c = Cache.card(id)
      if Battle.isBenchable(c) then
        battle:playBasic(i, side)
        break
      end
    end
  end

  -- Attach energy: prefer Active if it can't attack yet, else bench.
  if not side.attachedEnergyThisTurn then
    for i, id in ipairs(side.hand) do
      local c = Cache.card(id)
      if c and c.kind == "energy" then
        local target = "active"
        if side.active then
          local needs = true
          if side.active.card and side.active.card.attacks then
            for _, atk in ipairs(side.active.card.attacks) do
              if not Effects.isPokemonPower(atk) and canPay(side.active, atk.cost) then
                needs = false
                break
              end
            end
          end
          if not needs and #side.bench > 0 then
            target = 1
          end
        elseif #side.bench > 0 then
          target = 1
        end
        battle:attachEnergy(i, target)
        break
      end
    end
  end

  -- Attack with strongest affordable move.
  local okAtk = battle:canAttack(side.active)
  if okAtk and side.active and battle:other().active and side.active.card and side.active.card.attacks then
    local best, bestDmg = nil, -1
    for ai, atk in ipairs(side.active.card.attacks) do
      if not Effects.isPokemonPower(atk)
        and canPay(side.active, atk.cost)
        and (atk.damage or 0) > bestDmg then
        best, bestDmg = ai, atk.damage or 0
      end
    end
    if best then
      battle:attack(best)
      return
    end
  end
  battle:endTurn()
end

return AI
