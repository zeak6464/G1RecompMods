local V = ...
local Cache = V.require("cache")

local Pack = {}

Pack.PRICE = 500
Pack.PRICE_BY_SET = {
  COLOSSEUM = 500,
  EVOLUTION = 500,
  MYSTERY = 700,
  LABORATORY = 700,
  ENERGY = 300,
  PROMOTIONAL = 1000,
}

-- All pret SET_HI booster kinds (buyable in shop).
Pack.SETS = {
  "COLOSSEUM",
  "EVOLUTION",
  "MYSTERY",
  "LABORATORY",
  "ENERGY",
  "PROMOTIONAL",
}

Pack.SIZE = 10

local WEIGHT = {
  CIRCLE = 70,
  DIAMOND = 25,
  STAR = 5,
}

-- Mystery / Laboratory skew a bit rarer (GBC “better” packs).
local WEIGHT_RARE = {
  CIRCLE = 55,
  DIAMOND = 30,
  STAR = 15,
}

local function rng(a, b)
  if love and love.math and love.math.random then
    return love.math.random(a, b)
  end
  return math.random(a, b)
end

function Pack.price(setName)
  setName = (setName or "COLOSSEUM"):upper()
  if Pack.PRICE_BY_SET[setName] then return Pack.PRICE_BY_SET[setName] end
  local custom = V.require("custom").installedPack(setName)
  if custom and custom.price then return custom.price end
  return Pack.PRICE
end

function Pack.shopSets()
  local out = {}
  for _, set in ipairs(Pack.SETS) do out[#out + 1] = set end
  for _, pack in ipairs(V.require("custom").installedPacks()) do
    out[#out + 1] = pack.set
  end
  return out
end

local function poolByRarity(setName)
  local pools = { CIRCLE = {}, DIAMOND = {}, STAR = {} }
  if setName == "ENERGY" then
    for _, card in ipairs(Cache.allCards()) do
      if card.kind == "energy" and not card.custom then
        pools.CIRCLE[#pools.CIRCLE + 1] = card.id
      end
    end
    return pools
  end

  for _, card in ipairs(Cache.allCards()) do
    if not card.custom then
      if card.kind == "energy" and setName ~= "PROMOTIONAL" then
        pools.CIRCLE[#pools.CIRCLE + 1] = card.id
      elseif pools[card.rarity] and card.set == setName then
        pools[card.rarity][#pools[card.rarity] + 1] = card.id
      end
    end
  end
  -- Thin set pools fall back to any card of that rarity.
  for rarity, pool in pairs(pools) do
    if #pool < 5 and setName ~= "PROMOTIONAL" then
      for _, card in ipairs(Cache.allCards()) do
        if not card.custom and card.kind ~= "energy" and card.rarity == rarity then
          pool[#pool + 1] = card.id
        end
      end
    elseif #pool < 1 and setName == "PROMOTIONAL" then
      for _, card in ipairs(Cache.allCards()) do
        if not card.custom and card.kind ~= "energy"
            and (card.rarity == "PROMOSTAR" or card.rarity == rarity) then
          pool[#pool + 1] = card.id
        end
      end
    end
  end
  return pools
end

local function pickRarity(setName)
  if setName == "ENERGY" then return "CIRCLE" end
  local w = (setName == "MYSTERY" or setName == "LABORATORY" or setName == "PROMOTIONAL")
    and WEIGHT_RARE or WEIGHT
  local total = w.CIRCLE + w.DIAMOND + w.STAR
  local roll = rng(1, total)
  if roll <= w.CIRCLE then return "CIRCLE" end
  if roll <= w.CIRCLE + w.DIAMOND then return "DIAMOND" end
  return "STAR"
end

local function openCustom(pack)
  local pool = pack.cards or {}
  local out = {}
  if #pool == 0 then return out end
  for _ = 1, Pack.SIZE do
    out[#out + 1] = pool[rng(1, #pool)]
  end
  return out
end

function Pack.open(setName)
  setName = (setName or "COLOSSEUM"):upper()
  if setName == "PREMIUM" then setName = "MYSTERY" end
  local custom = V.require("custom").installedPack(setName)
  if custom then return openCustom(custom) end
  local pools = poolByRarity(setName)
  local out = {}
  for _ = 1, Pack.SIZE do
    local rarity = pickRarity(setName)
    local pool = pools[rarity]
    if not pool or #pool == 0 then pool = pools.CIRCLE end
    if (not pool or #pool == 0) and setName == "PROMOTIONAL" then
      pool = pools.DIAMOND
    end
    if (not pool or #pool == 0) and setName == "PROMOTIONAL" then
      pool = pools.STAR
    end
    if pool and #pool > 0 then
      out[#out + 1] = pool[rng(1, #pool)]
    end
  end
  return out
end

return Pack
