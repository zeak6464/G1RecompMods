local V = ...
local Cache = V.require("cache")
local Save = V.require("save")

local Deck = {}
Deck.SIZE = 60
Deck.MAX_COPIES = 4

local function normId(id)
  return tonumber(id) or id
end

local function sameId(a, b)
  return normId(a) == normId(b)
end

local function countIn(list, id)
  id = normId(id)
  local n = 0
  for _, x in ipairs(list) do
    if sameId(x, id) then n = n + 1 end
  end
  return n
end

-- Ensure deck is a dense numeric array of numeric ids (save round-trips).
function Deck.normalize(list)
  local out = {}
  if type(list) ~= "table" then return out end
  local maxn = 0
  for k, v in pairs(list) do
    local i = tonumber(k)
    if i and i >= 1 then
      local id = normId(v)
      if id then
        out[i] = id
        if i > maxn then maxn = i end
      end
    end
  end
  -- compact holes
  local dense = {}
  for i = 1, maxn do
    if out[i] ~= nil then dense[#dense + 1] = out[i] end
  end
  return dense
end

function Deck.validate(mod, list)
  list = Deck.normalize(list or Save.deck(mod))
  if #list ~= Deck.SIZE then
    return false, ("Deck must be %d cards (have %d)"):format(Deck.SIZE, #list)
  end
  local counts, basics = {}, 0
  for _, id in ipairs(list) do
    local card = Cache.card(id)
    if not card then return false, "Unknown card " .. tostring(id) end
    counts[id] = (counts[id] or 0) + 1
    if card.kind ~= "energy" and counts[id] > Deck.MAX_COPIES then
      return false, "Too many copies of " .. card.name
    end
    if card.kind == "pokemon" and card.stage == "BASIC" then
      basics = basics + 1
    end
  end
  if basics < 1 then return false, "Need at least one Basic Pokémon" end
  return true
end

function Deck.ownedCopies(mod, id)
  return Save.countOwned(mod, normId(id))
end

function Deck.countInDeck(mod, id)
  return countIn(Save.deck(mod), id)
end

function Deck.tryAdd(mod, id)
  id = normId(id)
  local deck = Deck.normalize(Save.deck(mod))
  if #deck >= Deck.SIZE then return false, "Deck full, remove one" end

  local owned = Save.countOwned(mod, id)
  local inDeck = countIn(deck, id)
  if inDeck >= owned then return false, "No spare copies" end
  local card = Cache.card(id)
  if not card then return false, "Unknown card" end
  if card.kind ~= "energy" and inDeck >= Deck.MAX_COPIES then
    return false, "Max 4 copies"
  end
  deck[#deck + 1] = id
  Save.setDeck(mod, deck)
  return true
end

function Deck.tryRemove(mod, id)
  id = normId(id)
  local deck = Deck.normalize(Save.deck(mod))
  for i = #deck, 1, -1 do
    if sameId(deck[i], id) then
      table.remove(deck, i)
      Save.setDeck(mod, deck)
      return true
    end
  end
  return false, "Not in deck"
end

return Deck
