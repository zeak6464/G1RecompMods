-- Flag-based attack effects + Trainer approximations (not full pret scripts).
local V = ...
local Cache = V.require("cache")
local bit = require("bit")
local band = bit.band

local Effects = {}

Effects.BENCH_MAX = 5

Effects.F1 = {
  POISON = 0x01,
  SLEEP = 0x02,
  PARALYSIS = 0x04,
  CONFUSION = 0x08,
  LOW_RECOIL = 0x10,
  BENCH_DAMAGE = 0x20,
  HIGH_RECOIL = 0x40,
  DRAW = 0x80,
}
Effects.F2 = {
  SWITCH_OPP = 0x01,
  HEAL_USER = 0x02,
  NULLIFY_WEAKEN = 0x04,
  DISCARD_ENERGY = 0x08,
  ENERGY_BOOST = 0x10,
}

Effects.CAT = {
  NORMAL = 0,
  PLUS = 1,
  MINUS = 2,
  X = 3,
  POWER = 4,
}

local function coin()
  if love and love.math and love.math.random then
    return love.math.random(2) == 1
  end
  return math.random(2) == 1
end

function Effects.coin()
  return coin()
end

function Effects.category(atk)
  return band(atk.category or 0, 0x7F)
end

function Effects.isPokemonPower(atk)
  return Effects.category(atk) == Effects.CAT.POWER
end

function Effects.totalEnergy(mon)
  local n = 0
  if not mon or not mon.energy then return 0 end
  for _, v in pairs(mon.energy) do n = n + v end
  return n
end

function Effects.discardEnergy(mon, n, preferType)
  n = n or 1
  local order = { "FIRE", "GRASS", "LIGHTNING", "WATER", "FIGHTING", "PSYCHIC", "COLORLESS" }
  if preferType then
    local pref = { preferType }
    for _, t in ipairs(order) do
      if t ~= preferType then pref[#pref + 1] = t end
    end
    order = pref
  end
  local discarded = 0
  for _ = 1, n do
    local found = false
    for _, typ in ipairs(order) do
      if (mon.energy[typ] or 0) > 0 then
        mon.energy[typ] = mon.energy[typ] - 1
        discarded = discarded + 1
        found = true
        break
      end
    end
    if not found then break end
  end
  return discarded
end

function Effects.clearStatus(mon)
  if not mon then return end
  mon.poisoned = false
  mon.asleep = false
  mon.paralyzed = false
  mon.confused = false
end

function Effects.applyStatusFlags(def, flags1, log)
  if band(flags1, Effects.F1.POISON) ~= 0 then
    def.poisoned = true
    log("Poisoned!")
  end
  if band(flags1, Effects.F1.SLEEP) ~= 0 then
    def.asleep = true
    def.paralyzed = false
    log("Asleep!")
  end
  if band(flags1, Effects.F1.PARALYSIS) ~= 0 then
    def.paralyzed = true
    def.asleep = false
    log("Paralyzed!")
  end
  if band(flags1, Effects.F1.CONFUSION) ~= 0 then
    def.confused = true
    log("Confused!")
  end
end

function Effects.baseDamage(atk, mon)
  local dmg = atk.damage or 0
  local cat = Effects.category(atk)
  local f2 = atk.flags2 or 0
  local param = atk.effectParam or 0
  local energy = Effects.totalEnergy(mon)

  if band(f2, Effects.F2.ENERGY_BOOST) ~= 0 then
    local boost = energy * 10
    if param == 2 then boost = math.min(boost, 20) end
    if cat == Effects.CAT.X then
      dmg = (atk.damage or 10) * math.max(1, energy)
    else
      dmg = dmg + boost
    end
  elseif cat == Effects.CAT.PLUS then
    if coin() then dmg = dmg + 10 end
  elseif cat == Effects.CAT.X then
    dmg = dmg * (coin() and 2 or 1)
  elseif cat == Effects.CAT.MINUS then
    if coin() then dmg = math.max(0, dmg - 10) end
  end
  return dmg
end

function Effects.healAmount(atk, damageDealt)
  local param = atk.effectParam or 1
  if param == 2 then return math.floor((damageDealt or 0) / 2) end
  if param == 3 then return damageDealt or 0 end
  return 10
end

function Effects.applyAfterDamage(battle, side, foe, mon, def, atk, damageDealt)
  local f1 = atk.flags1 or 0
  local f2 = atk.flags2 or 0
  local param = atk.effectParam or 0
  local function log(msg) battle:logMsg(msg) end

  if band(f2, Effects.F2.HEAL_USER) ~= 0 then
    local heal = Effects.healAmount(atk, damageDealt)
    mon.damage = math.max(0, mon.damage - heal)
    if heal > 0 then log(("Healed %d!"):format(heal)) end
  end

  Effects.applyStatusFlags(def, f1, log)

  if band(f1, Effects.F1.LOW_RECOIL) ~= 0 then
    local recoil = param > 0 and param or 10
    mon.damage = mon.damage + recoil
    log(("Recoil %d!"):format(recoil))
  end
  if band(f1, Effects.F1.HIGH_RECOIL) ~= 0 then
    local recoil = param > 0 and param or 20
    mon.damage = mon.damage + recoil
    log(("Recoil %d!"):format(recoil))
  end

  if band(f1, Effects.F1.BENCH_DAMAGE) ~= 0 then
    local bd = param > 0 and param or 10
    for _, bmon in ipairs(foe.bench) do
      bmon.damage = bmon.damage + bd
    end
    if #foe.bench > 0 then log(("Bench takes %d!"):format(bd)) end
  end

  if band(f1, Effects.F1.DRAW) ~= 0 then
    if #side.deck > 0 then
      side.hand[#side.hand + 1] = table.remove(side.deck, 1)
      log("Drew a card!")
    end
  end

  if band(f2, Effects.F2.DISCARD_ENERGY) ~= 0 then
    local n = Effects.discardEnergy(mon, 1, mon.card and mon.card.type)
    if n > 0 then log("Discarded Energy!") end
  end

  if band(f2, Effects.F2.SWITCH_OPP) ~= 0 and #foe.bench > 0 then
    local idx = (love and love.math and love.math.random(#foe.bench)) or math.random(#foe.bench)
    local old = foe.active
    foe.active = foe.bench[idx]
    foe.bench[idx] = old
    Effects.clearStatus(foe.active)
    log("Switched defending Pokemon!")
  end

  if band(f2, Effects.F2.NULLIFY_WEAKEN) ~= 0 then
    mon.weakenOppNext = param > 0 and param or 20
    log("Next attack weakened!")
  end
end

local function drawN(side, n)
  local got = 0
  for _ = 1, n do
    if #side.deck == 0 then break end
    side.hand[#side.hand + 1] = table.remove(side.deck, 1)
    got = got + 1
  end
  return got
end

local function shuffleIntoDeck(side, id)
  side.deck[#side.deck + 1] = id
  -- light shuffle
  for i = #side.deck, 2, -1 do
    local j = (love and love.math and love.math.random(i)) or math.random(i)
    side.deck[i], side.deck[j] = side.deck[j], side.deck[i]
  end
end

local function takeFromDiscard(side, pred, maxN)
  maxN = maxN or 1
  local got = {}
  for i = #side.discard, 1, -1 do
    if #got >= maxN then break end
    local id = side.discard[i]
    local c = Cache.card(id)
    if pred(c, id) then
      table.remove(side.discard, i)
      got[#got + 1] = id
    end
  end
  return got
end

local function searchDeck(side, pred)
  for i, id in ipairs(side.deck) do
    local c = Cache.card(id)
    if pred(c, id) then
      table.remove(side.deck, i)
      return id
    end
  end
  return nil
end

local function emptyEnergy()
  return { FIRE=0, GRASS=0, LIGHTNING=0, WATER=0, FIGHTING=0, PSYCHIC=0, COLORLESS=0 }
end

local function makeDoll(cardId)
  local card = Cache.card(cardId)
  return {
    cardId = cardId,
    card = card,
    hp = 10,
    maxHp = 10,
    damage = 0,
    energy = emptyEnergy(),
    justPlayed = true,
    evolvedThisTurn = false,
    isDoll = true,
    noPrize = true,
  }
end

local function canBreedOnto(stage2Card, mon)
  if not stage2Card or not mon or not mon.card then return false end
  if stage2Card.stage ~= "STAGE2" then return false end
  if (mon.card.stage or "BASIC") ~= "BASIC" then return false end
  if mon.justPlayed or mon.evolvedThisTurn then return false end
  local mid = stage2Card.preEvoName
  if not mid then return false end
  if mid:upper() == (mon.card.name or ""):upper() then return true end
  for _, c in ipairs(Cache.allCards()) do
    if c.kind == "pokemon" and c.name and c.name:upper() == mid:upper() then
      if c.preEvoName and c.preEvoName:upper() == (mon.card.name or ""):upper() then
        return true
      end
    end
  end
  return false
end

-- Trainers with no picker.
Effects.TRAINER = {
  BILL = function(_, side)
    drawN(side, 2)
    return true, "Drew 2 cards!"
  end,

  PROFESSOR_OAK = function(_, side)
    for _, id in ipairs(side.hand) do
      side.discard[#side.discard + 1] = id
    end
    side.hand = {}
    drawN(side, 7)
    return true, "Oak: drew 7!"
  end,

  IMPOSTER_PROFESSOR_OAK = function(_, side, foe)
    for _, id in ipairs(foe.hand) do
      foe.discard[#foe.discard + 1] = id
    end
    foe.hand = {}
    drawN(foe, 7)
    return true, "Imposter Oak!"
  end,

  LASS = function(_, side, foe)
    local function stripTrainers(s)
      local kept = {}
      for _, id in ipairs(s.hand) do
        local c = Cache.card(id)
        if c and c.kind == "trainer" then
          shuffleIntoDeck(s, id)
        else
          kept[#kept + 1] = id
        end
      end
      s.hand = kept
    end
    stripTrainers(side)
    stripTrainers(foe)
    return true, "Lass!"
  end,

  IMAKUNI_CARD = function(_, side)
    if not side.active then return false, "No Active" end
    side.active.confused = true
    return true, "Confused yourself!"
  end,

  ENERGY_RETRIEVAL = function(_, side)
    local got = takeFromDiscard(side, function(c) return c and c.kind == "energy" end, 2)
    if #got == 0 then return false, "No Energy in discard" end
    for _, id in ipairs(got) do side.hand[#side.hand + 1] = id end
    return true, ("Got %d Energy!"):format(#got)
  end,

  SUPER_ENERGY_RETRIEVAL = function(_, side)
    if #side.hand < 2 then return false, "Need 2 cards" end
    for _ = 1, 2 do
      side.discard[#side.discard + 1] = table.remove(side.hand, 1)
    end
    local got = takeFromDiscard(side, function(c) return c and c.kind == "energy" end, 4)
    for _, id in ipairs(got) do side.hand[#side.hand + 1] = id end
    return true, ("Got %d Energy!"):format(#got)
  end,

  ENERGY_SEARCH = function(_, side)
    local id = searchDeck(side, function(c) return c and c.kind == "energy" end)
    if not id then return false, "No Energy in deck" end
    side.hand[#side.hand + 1] = id
    return true, "Found Energy!"
  end,

  ENERGY_REMOVAL = function(_, side, foe)
    if not foe.active or Effects.totalEnergy(foe.active) < 1 then
      return false, "No Energy on foe"
    end
    Effects.discardEnergy(foe.active, 1)
    return true, "Removed Energy!"
  end,

  SUPER_ENERGY_REMOVAL = function(_, side, foe)
    if not side.active or Effects.totalEnergy(side.active) < 1 then
      return false, "Need your Energy"
    end
    if not foe.active or Effects.totalEnergy(foe.active) < 1 then
      return false, "No Energy on foe"
    end
    Effects.discardEnergy(side.active, 1)
    Effects.discardEnergy(foe.active, 2)
    return true, "Super Energy Removal!"
  end,

  POKEMON_CENTER = function(_, side)
    if side.active then
      side.active.damage = 0
      Effects.discardEnergy(side.active, Effects.totalEnergy(side.active))
    end
    for _, m in ipairs(side.bench) do
      m.damage = 0
      Effects.discardEnergy(m, Effects.totalEnergy(m))
    end
    return true, "Pokemon Center!"
  end,

  POKE_BALL = function(_, side)
    local id = searchDeck(side, function(c)
      return c and c.kind == "pokemon" and (c.stage == "BASIC" or c.stage == "STAGE2_WITHOUT_STAGE1")
    end)
    if not id then return false, "No Basic in deck" end
    side.hand[#side.hand + 1] = id
    return true, "Found a Basic!"
  end,

  COMPUTER_SEARCH = function(_, side)
    if #side.hand < 1 then return false, "Need a card" end
    side.discard[#side.discard + 1] = table.remove(side.hand, 1)
    if #side.deck == 0 then return false, "Deck empty" end
    -- Lite: take top card of deck as "any card"
    side.hand[#side.hand + 1] = table.remove(side.deck, 1)
    return true, "Computer Search!"
  end,

  POKEDEX = function(_, side)
    -- Lite: rearrange is skipped; just confirm look.
    if #side.deck == 0 then return false, "Deck empty" end
    return true, "Checked top of deck!"
  end,

  PLUSPOWER = function(_, side)
    side.plusPower = (side.plusPower or 0) + 10
    return true, "PlusPower!"
  end,

  DEFENDER = function(_, side)
    if not side.active then return false, "No Active" end
    side.active.defender = (side.active.defender or 0) + 20
    return true, "Defender!"
  end,

  ITEM_FINDER = function(_, side)
    if #side.hand < 2 then return false, "Need 2 cards" end
    for _ = 1, 2 do
      side.discard[#side.discard + 1] = table.remove(side.hand, 1)
    end
    local got = takeFromDiscard(side, function(c) return c and c.kind == "trainer" end, 1)
    if #got == 0 then return false, "No Trainer in discard" end
    side.hand[#side.hand + 1] = got[1]
    return true, "Item Finder!"
  end,

  POTION = function(_, side)
    if not side.active then return false, "No Active" end
    side.active.damage = math.max(0, side.active.damage - 20)
    return true, "Potion!"
  end,

  SUPER_POTION = function(_, side)
    if not side.active then return false, "No Active" end
    if Effects.totalEnergy(side.active) < 1 then return false, "Need Energy" end
    Effects.discardEnergy(side.active, 1)
    side.active.damage = math.max(0, side.active.damage - 40)
    return true, "Super Potion!"
  end,

  FULL_HEAL = function(_, side)
    if not side.active then return false, "No Active" end
    Effects.clearStatus(side.active)
    return true, "Full Heal!"
  end,

  MAINTENANCE = function(_, side)
    if #side.hand < 2 then return false, "Need 2 cards" end
    for _ = 1, 2 do
      if #side.hand == 0 then break end
      side.discard[#side.discard + 1] = table.remove(side.hand, 1)
    end
    drawN(side, 1)
    return true, "Maintenance!"
  end,

  GAMBLER = function(_, side)
    for _, id in ipairs(side.hand) do
      shuffleIntoDeck(side, id)
    end
    side.hand = {}
    if coin() then
      drawN(side, 8)
      return true, "Gambler: drew 8!"
    end
    drawN(side, 1)
    return true, "Gambler: drew 1!"
  end,

  RECYCLE = function(_, side)
    if #side.discard == 0 then return false, "Discard empty" end
    local id = table.remove(side.discard)
    table.insert(side.deck, 1, id)
    return true, "Recycle!"
  end,

  CLEFAIRY_DOLL = function(_, side)
    if #side.bench >= Effects.BENCH_MAX then return false, "Bench full" end
    -- card already moved to discard by caller; pull it back as a doll on bench
    local id = side.discard[#side.discard]
    table.remove(side.discard)
    side.bench[#side.bench + 1] = makeDoll(id)
    return true, "Clefairy Doll!"
  end,

  MYSTERIOUS_FOSSIL = function(_, side)
    if #side.bench >= Effects.BENCH_MAX then return false, "Bench full" end
    local id = side.discard[#side.discard]
    table.remove(side.discard)
    side.bench[#side.bench + 1] = makeDoll(id)
    return true, "Mysterious Fossil!"
  end,
}

-- Target kinds for UI pickers.
Effects.TRAINER_TARGET = {
  SWITCH = "own_bench",
  GUST_OF_WIND = "opp_bench",
  SCOOP_UP = "own_any",
  MR_FUJI = "own_any",
  POKEMON_TRADER = "own_hand",
  POKEMON_BREEDER = "breed",
  DEVOLUTION_SPRAY = "own_any",
  REVIVE = "own_discard_basic",
  POKEMON_FLUTE = "opp_discard_basic",
}

function Effects.trainerNeedsTarget(key)
  return Effects.TRAINER_TARGET[key]
end

function Effects.isTrainerPlayable(key)
  return Effects.TRAINER[key] ~= nil or Effects.TRAINER_TARGET[key] ~= nil
end

function Effects.playTrainerTargeted(key, battle, side, foe, target)
  if key == "SWITCH" then
    local idx = target
    if not side.active or not side.bench[idx] then return false, "Bad target" end
    local old = side.active
    side.active = side.bench[idx]
    side.bench[idx] = old
    Effects.clearStatus(side.active)
    return true, "Switched!"
  elseif key == "GUST_OF_WIND" then
    local idx = target
    if not foe.active or not foe.bench[idx] then return false, "Bad target" end
    local old = foe.active
    foe.active = foe.bench[idx]
    foe.bench[idx] = old
    Effects.clearStatus(foe.active)
    return true, "Gust of Wind!"
  elseif key == "SCOOP_UP" then
    if target == "active" then
      if not side.active or #side.bench == 0 then return false, "Need Bench" end
      if side.active.isDoll then return false, "Cant scoop doll" end
      side.hand[#side.hand + 1] = side.active.cardId
      side.active = table.remove(side.bench, 1)
    else
      local mon = side.bench[target]
      if not mon then return false, "Bad target" end
      side.hand[#side.hand + 1] = mon.cardId
      table.remove(side.bench, target)
    end
    return true, "Scooped up!"
  elseif key == "MR_FUJI" then
    local mon = target == "active" and side.active or side.bench[target]
    if not mon then return false, "Bad target" end
    if target == "active" then
      if #side.bench == 0 then return false, "Need Bench" end
      shuffleIntoDeck(side, mon.cardId)
      side.active = table.remove(side.bench, 1)
    else
      shuffleIntoDeck(side, mon.cardId)
      table.remove(side.bench, target)
    end
    return true, "Mr Fuji!"
  elseif key == "POKEMON_TRADER" then
    -- target = hand index (among remaining hand after trainer removed)
    local hi = target
    if not side.hand[hi] then return false, "Bad card" end
    local give = table.remove(side.hand, hi)
    local id = searchDeck(side, function(c) return c and c.kind == "pokemon" end)
    if not id then
      table.insert(side.hand, hi, give)
      return false, "No Pokemon in deck"
    end
    shuffleIntoDeck(side, give)
    side.hand[#side.hand + 1] = id
    return true, "Pokemon Trader!"

  elseif key == "POKEMON_BREEDER" then
    -- target = { monTarget = "active"|idx, handIndex = stage2 in hand }
    local monTarget = target and target.monTarget
    local handIndex = target and target.handIndex
    local mon = monTarget == "active" and side.active or side.bench[monTarget]
    local evoId = side.hand[handIndex]
    local evo = Cache.card(evoId)
    if not mon or not evo then return false, "Bad target" end
    if not canBreedOnto(evo, mon) then return false, "Cant breed" end
    table.remove(side.hand, handIndex)
    side.discard[#side.discard + 1] = mon.cardId
    mon.cardId = evoId
    mon.card = evo
    mon.maxHp = evo.hp or mon.maxHp
    if mon.damage >= mon.maxHp then mon.damage = math.max(0, mon.maxHp - 10) end
    mon.evolvedThisTurn = true
    mon.justPlayed = false
    return true, "Pokemon Breeder!"
  elseif key == "DEVOLUTION_SPRAY" then
    local mon = target == "active" and side.active or side.bench[target]
    if not mon or not mon.card then return false, "Bad target" end
    local stage = mon.card.stage or "BASIC"
    if stage == "BASIC" or stage == "STAGE2_WITHOUT_STAGE1" then
      return false, "Already Basic"
    end
    local pre = mon.card.preEvoName
    if not pre then return false, "No prevo" end
    local preId = nil
    for _, c in ipairs(Cache.allCards()) do
      if c.kind == "pokemon" and c.name and c.name:upper() == pre:upper() then
        preId = c.id
        break
      end
    end
    if not preId then return false, "No prevo card" end
    side.discard[#side.discard + 1] = mon.cardId
    mon.cardId = preId
    mon.card = Cache.card(preId)
    mon.maxHp = mon.card.hp or mon.maxHp
    if mon.damage >= mon.maxHp then mon.damage = math.max(0, mon.maxHp - 10) end
    Effects.clearStatus(mon)
    return true, "Devolution Spray!"
  elseif key == "REVIVE" then
    -- target = discard index or card id
    local id = target
    local found = nil
    for i = #side.discard, 1, -1 do
      if side.discard[i] == id then
        found = i
        break
      end
    end
    if not found then return false, "Not in discard" end
    local c = Cache.card(id)
    if not c or c.kind ~= "pokemon" or (c.stage ~= "BASIC" and c.stage ~= "STAGE2_WITHOUT_STAGE1") then
      return false, "Not a Basic"
    end
    if #side.bench >= Effects.BENCH_MAX then return false, "Bench full" end
    table.remove(side.discard, found)
    local mon = {
      cardId = id,
      card = c,
      hp = c.hp or 10,
      maxHp = c.hp or 10,
      damage = math.floor((c.hp or 10) / 2),
      energy = emptyEnergy(),
      justPlayed = true,
      evolvedThisTurn = false,
    }
    side.bench[#side.bench + 1] = mon
    return true, "Revive!"
  elseif key == "POKEMON_FLUTE" then
    local id = target
    local found = nil
    for i = #foe.discard, 1, -1 do
      if foe.discard[i] == id then
        found = i
        break
      end
    end
    if not found then return false, "Not in discard" end
    local c = Cache.card(id)
    if not c or c.kind ~= "pokemon" or (c.stage ~= "BASIC" and c.stage ~= "STAGE2_WITHOUT_STAGE1") then
      return false, "Not a Basic"
    end
    if #foe.bench >= Effects.BENCH_MAX then return false, "Foe bench full" end
    table.remove(foe.discard, found)
    foe.bench[#foe.bench + 1] = {
      cardId = id,
      card = c,
      hp = c.hp or 10,
      maxHp = c.hp or 10,
      damage = 0,
      energy = emptyEnergy(),
      justPlayed = true,
      evolvedThisTurn = false,
    }
    return true, "Pokemon Flute!"
  end
  return false, "Unknown trainer"
end

return Effects
