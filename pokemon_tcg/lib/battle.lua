-- GBC-lite duel engine using imported card stats + flag-based effects.
local V = ...
local Cache = V.require("cache")
local Effects = V.require("effects")

local Battle = {}


Battle.DECK_SIZE = 60
Battle.PRIZES = 6
Battle.BENCH_MAX = 5 -- active is separate; at most 5 on each bench

local function shuffle(t, rng)
  rng = rng or math.random
  for i = #t, 2, -1 do
    local j = rng(i)
    t[i], t[j] = t[j], t[i]
  end
end

local function copyList(src)
  local t = {}
  for i, v in ipairs(src) do t[i] = v end
  return t
end

local function emptyEnergy()
  return { FIRE=0, GRASS=0, LIGHTNING=0, WATER=0, FIGHTING=0, PSYCHIC=0, COLORLESS=0 }
end

local function makeMon(cardId)
  local card = Cache.card(cardId)
  return {
    cardId = cardId,
    card = card,
    hp = card and card.hp or 10,
    maxHp = card and card.hp or 10,
    damage = 0,
    energy = emptyEnergy(),
    justPlayed = true,
    evolvedThisTurn = false,
    poisoned = false,
    asleep = false,
    paralyzed = false,
    confused = false,
  }
end

local function draw(side, n)
  n = n or 1
  for _ = 1, n do
    if #side.deck == 0 then return false end
    side.hand[#side.hand + 1] = table.remove(side.deck, 1)
  end
  return true
end

local function totalEnergy(mon)
  return Effects.totalEnergy(mon)
end

local function canPay(mon, cost)
  if not cost then return true end
  local have = {}
  for k, v in pairs(mon.energy) do have[k] = v end
  local colorlessNeed = cost.COLORLESS or 0
  for typ, need in pairs(cost) do
    if typ ~= "COLORLESS" then
      if (have[typ] or 0) < need then return false end
      have[typ] = have[typ] - need
    end
  end
  local leftover = 0
  for _, v in pairs(have) do leftover = leftover + v end
  return leftover >= colorlessNeed
end

local function discardEnergy(mon, n)
  return Effects.discardEnergy(mon, n)
end

function Battle.weaknessMultiplier(atkType, defMon)
  local w = defMon.card and defMon.card.weakness
  if w and atkType == w then return 2 end
  return 1
end

function Battle.resistanceReduce(atkType, defMon)
  local r = defMon.card and defMon.card.resistance
  if r and atkType == r then return 20 end
  return 0
end

local function sideFromDeck(deckIds, name)
  local deck = copyList(deckIds)
  shuffle(deck)
  return {
    name = name or "PLAYER",
    deck = deck,
    hand = {},
    discard = {},
    prizes = {},
    active = nil,
    bench = {},
    attachedEnergyThisTurn = false,
    plusPower = 0,
  }
end

local function isBenchable(card)
  if not card or card.kind ~= "pokemon" then return false end
  local stage = card.stage or "BASIC"
  return stage == "BASIC" or stage == "STAGE2_WITHOUT_STAGE1"
end

local function namesMatch(a, b)
  if not a or not b then return false end
  return a:upper() == b:upper()
end

local function canEvolveOnto(evoCard, mon)
  if not evoCard or not mon or not mon.card then return false end
  if evoCard.kind ~= "pokemon" then return false end
  local stage = evoCard.stage or "BASIC"
  if stage ~= "STAGE1" and stage ~= "STAGE2" then return false end
  if mon.justPlayed or mon.evolvedThisTurn then return false end
  return evoCard.preEvoName and namesMatch(evoCard.preEvoName, mon.card.name)
end


local function placeBasics(side)
  local kept = {}
  for _, id in ipairs(side.hand) do
    local card = Cache.card(id)
    if not side.active and isBenchable(card) then
      side.active = makeMon(id)
    else
      kept[#kept + 1] = id
    end
  end
  side.hand = kept
end

function Battle.isBenchable(card)
  return isBenchable(card)
end

function Battle.canEvolveOnto(evoCard, mon)
  return canEvolveOnto(evoCard, mon)
end

function Battle.new(playerDeck, oppDeck, opts)
  opts = opts or {}
  local self = {
    player = sideFromDeck(playerDeck, opts.playerName or "YOU"),
    opp = sideFromDeck(oppDeck, opts.oppName or "OPPONENT"),
    turn = "player",
    turnCount = 0,
    log = {},
    result = nil,
  }
  for _, side in ipairs({ self.player, self.opp }) do
    for _ = 1, 8 do
      side.hand = {}
      shuffle(side.deck)
      draw(side, 7)
      local hasBasic = false
      for _, id in ipairs(side.hand) do
        local c = Cache.card(id)
        if c and c.kind == "pokemon" and c.stage == "BASIC" then
          hasBasic = true; break
        end
      end
      if hasBasic then break end
      for _, id in ipairs(side.hand) do side.deck[#side.deck + 1] = id end
      side.hand = {}
    end
    placeBasics(side)
    if not side.active then
      for i, id in ipairs(side.deck) do
        local c = Cache.card(id)
        if c and c.kind == "pokemon" and c.stage == "BASIC" then
          side.active = makeMon(id)
          table.remove(side.deck, i)
          break
        end
      end
    end
    for _ = 1, Battle.PRIZES do
      if #side.deck > 0 then
        side.prizes[#side.prizes + 1] = table.remove(side.deck, 1)
      end
    end
  end
  self.turnCount = 1
  return setmetatable(self, { __index = Battle })
end

function Battle:logMsg(msg)
  self.log[#self.log + 1] = msg
end

function Battle:current()
  return self.turn == "player" and self.player or self.opp
end

function Battle:other()
  return self.turn == "player" and self.opp or self.player
end

local function isKnockedOut(mon)
  return mon and mon.damage >= mon.maxHp
end

function Battle:takePrize(side)
  if #side.prizes > 0 then
    local prize = table.remove(side.prizes, 1)
    side.hand[#side.hand + 1] = prize
    self:logMsg(side.name .. " takes a Prize card!")
  end
  if #side.prizes == 0 then
    self.result = (side == self.player) and "win" or "lose"
    return true
  end
  return false
end

-- Knock out mon on `foe` side; `side` is the player who gets the prize.
function Battle:knockOut(side, foe, mon, where)
  if not mon then return false end
  local noPrize = mon.noPrize
  self:logMsg((mon.card and mon.card.name or "?") .. " is Knocked Out!")
  foe.discard[#foe.discard + 1] = mon.cardId
  if where == "active" then
    foe.active = nil
  else
    table.remove(foe.bench, where)
  end
  if not noPrize then
    if self:takePrize(side) then return true end
  else
    self:logMsg("No Prize (doll).")
  end
  if where == "active" then
    if #foe.bench == 0 then
      self.result = (side == self.player) and "win" or "lose"
      self:logMsg(foe.name .. " has no Benched Pokémon!")
      return true
    end
    foe.active = table.remove(foe.bench, 1)
    Effects.clearStatus(foe.active)
  end
  return self.result ~= nil
end

function Battle:checkBenchKos(side, foe)
  -- Remove KO'd bench (prize each). Iterate backwards.
  for i = #foe.bench, 1, -1 do
    if isKnockedOut(foe.bench[i]) then
      if self:knockOut(side, foe, foe.bench[i], i) then return true end
    end
  end
  return false
end

function Battle:beginTurn()
  local side = self:current()
  local foe = self:other()
  side.attachedEnergyThisTurn = false
  side.plusPower = 0

  local mon = side.active
  if mon then
    mon.justPlayed = false
    mon.evolvedThisTurn = false
    -- Poison between turns
    if mon.poisoned then
      mon.damage = mon.damage + 10
      self:logMsg(side.name .. "'s Active is hurt by Poison!")
      if isKnockedOut(mon) then
        if self:knockOut(foe, side, mon, "active") then return end
      end
    end
    -- Sleep: try to wake
    if mon and mon.asleep then
      if Effects.coin() then
        mon.asleep = false
        self:logMsg("Woke up!")
      else
        self:logMsg("Still asleep...")
      end
    end
  end
  for _, m in ipairs(side.bench) do
    m.justPlayed = false
    m.evolvedThisTurn = false
  end
  if not draw(side, 1) then
    self.result = self.turn == "player" and "lose" or "win"
    self:logMsg(side.name .. " cannot draw - deck out!")

  end
end

function Battle:playBasic(handIndex, side)
  side = side or self:current()
  local id = side.hand[handIndex]
  local card = Cache.card(id)
  if not card or card.kind ~= "pokemon" then
    return false, "Not a Pokémon"
  end
  if not isBenchable(card) then
    return false, "Only Basics can bench"
  end
  if #side.bench >= Battle.BENCH_MAX then return false, "Bench full" end
  table.remove(side.hand, handIndex)
  side.bench[#side.bench + 1] = makeMon(id)
  self:logMsg(side.name .. " plays " .. card.name .. " to Bench")
  return true
end

function Battle:evolve(handIndex, target)
  local side = self:current()
  local id = side.hand[handIndex]
  local card = Cache.card(id)
  if not card or card.kind ~= "pokemon" then return false, "Not a Pokémon" end
  local mon = target == "active" and side.active or side.bench[target]
  if not mon then return false, "No target" end
  if not canEvolveOnto(card, mon) then return false, "Can't evolve" end
  table.remove(side.hand, handIndex)
  side.discard[#side.discard + 1] = mon.cardId
  mon.cardId = id
  mon.card = card
  mon.maxHp = card.hp or mon.maxHp
  mon.hp = mon.maxHp
  -- Keep damage counters; clamp if over new HP
  if mon.damage >= mon.maxHp then mon.damage = mon.maxHp - 10 end
  if mon.damage < 0 then mon.damage = 0 end
  mon.evolvedThisTurn = true
  mon.justPlayed = false
  self:logMsg(side.name .. " evolves into " .. card.name)
  return true
end

function Battle:attachEnergy(handIndex, target)
  local side = self:current()
  if side.attachedEnergyThisTurn then return false, "Already attached Energy" end
  local id = side.hand[handIndex]
  local card = Cache.card(id)
  if not card or card.kind ~= "energy" then return false, "Not an Energy card" end
  local mon = target == "active" and side.active or side.bench[target]
  if not mon then return false, "No target" end
  local et = card.energyType or "COLORLESS"
  if et == "DOUBLE_COLORLESS" then
    mon.energy.COLORLESS = mon.energy.COLORLESS + 2
  else
    mon.energy[et] = (mon.energy[et] or 0) + 1
  end
  table.remove(side.hand, handIndex)
  side.attachedEnergyThisTurn = true
  self:logMsg(side.name .. " attaches " .. card.name)
  return true
end

function Battle:retreat(benchIndex)
  local side = self:current()
  if not side.active or not side.bench[benchIndex] then return false, "Bad retreat" end
  if side.active.asleep or side.active.paralyzed then
    return false, "Can't retreat"
  end
  local cost = side.active.card and side.active.card.retreat or 0
  if cost >= 100 then return false, "Can't retreat" end
  if totalEnergy(side.active) < cost then return false, "Not enough Energy to retreat" end
  discardEnergy(side.active, cost)
  local old = side.active
  side.active = side.bench[benchIndex]
  side.bench[benchIndex] = old
  Effects.clearStatus(side.active)
  self:logMsg(side.name .. " retreats")
  return true
end

function Battle:playTrainer(handIndex, target)
  local side = self:current()
  local foe = self:other()
  local id = side.hand[handIndex]
  local card = Cache.card(id)
  if not card or card.kind ~= "trainer" then return false, "Not a Trainer" end
  local key = card.key
  local need = Effects.trainerNeedsTarget(key)
  if need and target == nil then
    return false, "Need target"
  end
  -- Remove from hand first
  table.remove(side.hand, handIndex)
  side.discard[#side.discard + 1] = id

  local ok, msg
  if need then
    ok, msg = Effects.playTrainerTargeted(key, self, side, foe, target)
  else
    local fn = Effects.TRAINER[key]
    if not fn then
      -- put back if unsupported
      table.remove(side.discard)
      table.insert(side.hand, handIndex, id)
      return false, "Trainer not supported"
    end
    ok, msg = fn(self, side, foe)
  end
  if not ok then
    table.remove(side.discard)
    table.insert(side.hand, handIndex, id)
    return false, msg
  end
  self:logMsg(side.name .. " plays " .. (card.name or key))
  if msg then self:logMsg(msg) end
  return true, msg
end

function Battle:canAttack(mon)
  if not mon then return false, "No Active" end
  if mon.asleep then return false, "Asleep!" end
  if mon.paralyzed then return false, "Paralyzed!" end
  return true
end

function Battle:attack(attackIndex)
  local side = self:current()
  local foe = self:other()
  local mon = side.active
  local def = foe.active
  if not mon or not def then return false, "No Active Pokémon" end
  local okAtk, why = self:canAttack(mon)
  if not okAtk then return false, why end
  local atk = mon.card and mon.card.attacks and mon.card.attacks[attackIndex]
  if not atk then return false, "No attack" end
  if Effects.isPokemonPower(atk) then return false, "That's a PokéPOWER" end
  if not canPay(mon, atk.cost) then return false, "Not enough Energy" end

  local fromSide = self.turn

  -- Confusion: tails → 20 to self, attack fails
  if mon.confused then
    if not Effects.coin() then
      mon.damage = mon.damage + 20
      self:logMsg("Confusion: hurt itself!")
      self.lastAttack = {
        from = fromSide,
        animId = 1,
        damage = 20,
        name = "CONFUSION",
        pkmnType = mon.card.type or "COLORLESS",
        selfHit = true,
      }
      if isKnockedOut(mon) then
        self:knockOut(foe, side, mon, "active")
      end
      self:endTurn()
      return true
    end
    self:logMsg("Confusion: attack OK")
  end

  local atkType = mon.card.type
  local dmg = Effects.baseDamage(atk, mon)
  dmg = dmg + (side.plusPower or 0)
  side.plusPower = 0
  dmg = dmg * Battle.weaknessMultiplier(atkType, def)
  dmg = math.max(0, dmg - Battle.resistanceReduce(atkType, def))
  if def.defender and def.defender > 0 then
    dmg = math.max(0, dmg - def.defender)
    def.defender = 0
  end
  if def.weakenOppNext and def.weakenOppNext > 0 then
    dmg = math.max(0, dmg - def.weakenOppNext)
    def.weakenOppNext = 0
  end


  def.damage = def.damage + dmg
  self:logMsg(("%s uses %s for %d!"):format(
    side.name, atk.name or "attack", dmg))
  self.lastAttack = {
    from = fromSide,
    animId = atk.animId or 1,
    damage = dmg,
    name = atk.name or "ATTACK",
    pkmnType = atkType or "COLORLESS",
  }

  Effects.applyAfterDamage(self, side, foe, mon, def, atk, dmg)

  -- KO checks: defending first, then attacker (recoil), then benches
  if isKnockedOut(def) then
    if self:knockOut(side, foe, def, "active") then return true end
  end
  if isKnockedOut(mon) then
    if self:knockOut(foe, side, mon, "active") then return true end
  end
  if self:checkBenchKos(side, foe) then return true end
  if self:checkBenchKos(foe, side) then return true end

  self:endTurn()
  return true
end

function Battle:endTurn()
  if self.result then return end
  local side = self:current()
  -- Paralysis wears off at end of turn
  if side.active and side.active.paralyzed then
    side.active.paralyzed = false
  end
  self.turn = self.turn == "player" and "opp" or "player"
  if self.turn == "player" then self.turnCount = self.turnCount + 1 end
  self:beginTurn()
end

function Battle:handBasics(side)
  local idxs = {}
  for i, id in ipairs(side.hand) do
    local c = Cache.card(id)
    if c and c.kind == "pokemon" and c.stage == "BASIC" then
      idxs[#idxs + 1] = i
    end
  end
  return idxs
end

function Battle:handEnergy(side)
  local idxs = {}
  for i, id in ipairs(side.hand) do
    local c = Cache.card(id)
    if c and c.kind == "energy" then idxs[#idxs + 1] = i end
  end
  return idxs
end

function Battle:evolveTargets(handIndex)
  local side = self:current()
  local card = Cache.card(side.hand[handIndex])
  local out = {}
  if not card then return out end
  if side.active and canEvolveOnto(card, side.active) then
    out[#out + 1] = { target = "active", mon = side.active }
  end
  for i, mon in ipairs(side.bench) do
    if canEvolveOnto(card, mon) then
      out[#out + 1] = { target = i, mon = mon }
    end
  end
  return out
end

return Battle
