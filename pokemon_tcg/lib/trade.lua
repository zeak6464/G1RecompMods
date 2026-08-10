local V = ...
local Cache = V.require("cache")
local Save = V.require("save")

local Trade = {}

local function rng(a, b)
  if love and love.math then return love.math.random(a, b) end
  return math.random(a, b)
end

function Trade.offerFor(mod, giveId)
  local give = Cache.card(giveId)
  if not give then return nil, "Unknown card" end
  if Save.countOwned(mod, giveId) < 1 then return nil, "You don't own that card" end
  local candidates = {}
  for _, card in ipairs(Cache.allCards()) do
    if card.id ~= giveId and card.kind ~= "energy"
       and card.rarity == give.rarity and Save.countOwned(mod, card.id) == 0 then
      candidates[#candidates + 1] = card.id
    end
  end
  if #candidates == 0 then
    for _, card in ipairs(Cache.allCards()) do
      if card.id ~= giveId and card.kind ~= "energy" then
        candidates[#candidates + 1] = card.id
      end
    end
  end
  if #candidates == 0 then return nil, "No trade available" end
  return candidates[rng(1, #candidates)]
end

function Trade.nextOffer(mod)
  local collection = Save.collection(mod)
  local owned = {}
  for key, count in pairs(collection) do
    local id = tonumber(key)
    if id and count and count > 0 then
      local card = Cache.card(id)
      if card and card.kind ~= "energy" then
        owned[#owned + 1] = id
      end
    end
  end
  if #owned == 0 then return nil end
  local giveId = owned[rng(1, #owned)]
  local recvId, err = Trade.offerFor(mod, giveId)
  if not recvId then return nil, err end
  local give = Cache.card(giveId)
  local recv = Cache.card(recvId)
  return {
    want = giveId, -- player gives
    give = recvId, -- NPC gives
    blurb = ("Trade your %s?"):format(give and give.name or "?"),
    wantName = give and give.name or "?",
    giveName = recv and recv.name or "?",
  }
end

function Trade.skip(mod)
  mod.save:set("trade_skips", (mod.save:get("trade_skips", 0) or 0) + 1)
end

function Trade.accept(mod, a, b)
  local giveId, recvId
  if type(a) == "table" then
    giveId, recvId = a.want, a.give
  else
    giveId, recvId = a, b
  end
  local c = Save.collection(mod)
  local gk, rk = tostring(giveId), tostring(recvId)
  if (c[gk] or 0) < 1 then return false, "Missing card" end
  c[gk] = c[gk] - 1
  if c[gk] <= 0 then c[gk] = nil end
  c[rk] = (c[rk] or 0) + 1
  mod.save:set("collection", c)
  mod.save:set("trades", (mod.save:get("trades", 0) or 0) + 1)
  return true
end

return Trade
