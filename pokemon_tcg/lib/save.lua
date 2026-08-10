-- Collection / packs / deck persistence via mod.save.
local Save = {}

Save.PACK_SETS = {
  "COLOSSEUM", "EVOLUTION", "MYSTERY", "LABORATORY", "ENERGY", "PROMOTIONAL",
}

local function ensure(mod)
  if mod.save:get("initialized") then return end
  mod.save:set("collection", {})
  mod.save:set("packs", 0)
  mod.save:set("pack_inv", {})
  mod.save:set("deck", {})
  mod.save:set("wins", 0)
  mod.save:set("losses", 0)
  mod.save:set("trades", 0)
  mod.save:set("initialized", true)
end

local function packInv(mod)
  ensure(mod)
  local inv = mod.save:get("pack_inv", nil)
  if type(inv) ~= "table" then
    inv = {}
    local n = mod.save:get("packs", 0) or 0
    if n > 0 then
      if mod.save:get("next_pack_premium", false) then
        inv.MYSTERY = n
        mod.save:set("next_pack_premium", false)
      else
        inv.COLOSSEUM = n
      end
      mod.save:set("packs", 0)
    end
    mod.save:set("pack_inv", inv)
  end
  return inv
end

local function denseDeck(list)
  local out = {}
  if type(list) ~= "table" then return out end
  local maxn = 0
  for k, v in pairs(list) do
    local i = tonumber(k)
    local id = tonumber(v)
    if i and i >= 1 and id then
      out[i] = id
      if i > maxn then maxn = i end
    end
  end
  local dense = {}
  for i = 1, maxn do
    if out[i] ~= nil then dense[#dense + 1] = out[i] end
  end
  return dense
end

function Save.init(mod)
  ensure(mod)
  packInv(mod)
  -- Normalize deck once so #deck works after save reload.
  local d = denseDeck(mod.save:get("deck", {}))
  mod.save:set("deck", d)
end

function Save.collection(mod)
  ensure(mod)
  local c = mod.save:get("collection", {})
  if type(c) ~= "table" then c = {}; mod.save:set("collection", c) end
  return c
end

function Save.addCards(mod, ids)
  local c = Save.collection(mod)
  for _, id in ipairs(ids) do
    local key = tostring(tonumber(id) or id)
    c[key] = (c[key] or 0) + 1
  end
  mod.save:set("collection", c)
end

function Save.countOwned(mod, id)
  local c = Save.collection(mod)
  local key = tostring(tonumber(id) or id)
  return c[key] or 0
end

function Save.packs(mod)
  local inv = packInv(mod)
  local n = 0
  for _, set in ipairs(Save.PACK_SETS) do
    n = n + (inv[set] or 0)
  end
  return n
end

function Save.packCounts(mod)
  local inv = packInv(mod)
  local out = {}
  for _, set in ipairs(Save.PACK_SETS) do
    out[set] = inv[set] or 0
  end
  return out
end

function Save.addPack(mod, setName, n)
  ensure(mod)
  setName = (setName or "COLOSSEUM"):upper()
  local inv = packInv(mod)
  inv[setName] = (inv[setName] or 0) + (n or 1)
  mod.save:set("pack_inv", inv)
end

function Save.consumePack(mod, setName)
  local inv = packInv(mod)
  setName = (setName or "COLOSSEUM"):upper()
  local n = inv[setName] or 0
  if n < 1 then return false end
  inv[setName] = n - 1
  mod.save:set("pack_inv", inv)
  return true
end

function Save.deck(mod)
  ensure(mod)
  local d = denseDeck(mod.save:get("deck", {}))
  -- Keep save bucket in sync if it was sparse/string-keyed.
  mod.save:set("deck", d)
  return d
end

function Save.setDeck(mod, deck)
  ensure(mod)
  mod.save:set("deck", denseDeck(deck))
end

function Save.ensureStarterDeck(mod, practiceIds, force)
  local d = Save.deck(mod)
  if not force and #d >= 60 then return d end
  if type(practiceIds) == "table" and #practiceIds >= 40 then
    local copy = {}
    for i, id in ipairs(practiceIds) do
      copy[i] = tonumber(id) or id
    end
    Save.setDeck(mod, copy)
    Save.addCards(mod, copy)
    return copy
  end
  return d
end

function Save.recordWin(mod)
  ensure(mod)
  mod.save:set("wins", (mod.save:get("wins", 0) or 0) + 1)
end

function Save.recordLoss(mod)
  ensure(mod)
  mod.save:set("losses", (mod.save:get("losses", 0) or 0) + 1)
end

return Save
