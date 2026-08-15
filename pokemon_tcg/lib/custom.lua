-- Player-made cards and booster packs, stored on mod.save.
local V = ...

local Custom = {}

Custom.FIRST_ID = 10000

local installedPacks = {}
local installedList = {}
local installedPics = {}
local installedPackPics = {}

local function decodeB64(b64)
  if type(b64) ~= "string" or b64 == "" then return nil end
  if not (love and love.data and love.data.decode) then return nil end
  local ok, data = pcall(love.data.decode, "string", "base64", b64)
  if ok and type(data) == "string" then return data end
  return nil
end

local TYPES = {
  "FIRE", "GRASS", "LIGHTNING", "WATER", "FIGHTING", "PSYCHIC", "COLORLESS",
}

local WR_TYPES = {
  "FIRE", "GRASS", "LIGHTNING", "WATER", "FIGHTING", "PSYCHIC",
}

function Custom.types()
  return TYPES
end

function Custom.wrTypes()
  return WR_TYPES
end

local function wrType(value)
  if value == nil or value == "" or value == "NONE" then return nil end
  value = tostring(value):upper()
  for _, t in ipairs(WR_TYPES) do
    if t == value then return value end
  end
  return nil
end

local function copyCost(cost)
  local out = {}
  if type(cost) ~= "table" then return out end
  for _, typ in ipairs(TYPES) do
    local n = tonumber(cost[typ]) or 0
    if n > 0 then out[typ] = math.min(4, math.floor(n)) end
  end
  return out
end

local function copyAttacks(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, atk in ipairs(list) do
    if type(atk) == "table" and (atk.name or atk.damage) then
      out[#out + 1] = {
        name = tostring(atk.name or "ATTACK"):upper():sub(1, 12),
        damage = math.max(0, math.floor(tonumber(atk.damage) or 0)),
        cost = copyCost(atk.cost),
      }
    end
  end
  return out
end

local function copyIds(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, id in ipairs(list) do
    local n = tonumber(id)
    if n then out[#out + 1] = n end
  end
  return out
end

local function sanitizeCard(raw)
  if type(raw) ~= "table" then return nil end
  local id = tonumber(raw.id)
  if not id or id < Custom.FIRST_ID then return nil end
  local kind = raw.kind
  if kind ~= "pokemon" and kind ~= "energy" and kind ~= "trainer" then
    return nil
  end
  local name = tostring(raw.name or ""):upper()
  if name == "" then return nil end
  name = name:sub(1, 12)
  local card = {
    id = id,
    key = "CUSTOM_" .. tostring(id),
    name = name,
    kind = kind,
    rarity = raw.rarity == "DIAMOND" and "DIAMOND"
      or (raw.rarity == "STAR" and "STAR" or "CIRCLE"),
    set = "CUSTOM",
    custom = true,
  }
  if kind == "pokemon" then
    local typ = tostring(raw.type or "COLORLESS"):upper()
    local ok = false
    for _, t in ipairs(TYPES) do
      if t == typ then ok = true break end
    end
    if not ok then typ = "COLORLESS" end
    card.type = typ
    card.hp = math.max(10, math.min(250, math.floor(tonumber(raw.hp) or 50)))
    card.level = math.max(1, math.min(99, math.floor(tonumber(raw.level) or 10)))
    card.stage = raw.stage == "STAGE1" and "STAGE1"
      or (raw.stage == "STAGE2" and "STAGE2" or "BASIC")
    card.retreat = math.max(0, math.min(4, math.floor(tonumber(raw.retreat) or 1)))
    card.weakness = wrType(raw.weakness)
    card.resistance = wrType(raw.resistance)
    card.attacks = copyAttacks(raw.attacks)
    if #card.attacks == 0 then
      card.attacks[1] = { name = "TACKLE", damage = 10, cost = { COLORLESS = 1 } }
    end
  elseif kind == "energy" then
    local typ = tostring(raw.energyType or raw.type or "COLORLESS"):upper()
    local ok = false
    for _, t in ipairs(TYPES) do
      if t == typ then ok = true break end
    end
    if not ok then typ = "COLORLESS" end
    card.energyType = typ
    card.type = "ENERGY_" .. typ
    if name == "NEW CARD" or name == "" then
      card.name = typ .. " ENERGY"
    end
  else
    card.type = "TRAINER"
  end
  return card
end

local function sanitizePack(raw)
  if type(raw) ~= "table" then return nil end
  local set = tostring(raw.set or raw.name or ""):upper()
  set = set:gsub("[^A-Z0-9 ]", "")
  set = set:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if set == "" then return nil end
  local cards = copyIds(raw.cards)
  if #cards == 0 then return nil end
  return {
    set = set,
    name = tostring(raw.name or set):upper():sub(1, 12),
    cards = cards,
    price = math.max(100, math.min(9999, math.floor(tonumber(raw.price) or 500))),
    custom = true,
  }
end

function Custom.cards(mod)
  if not mod or not mod.save then return {} end
  local raw = mod.save:get("custom_cards", {})
  if type(raw) ~= "table" then return {} end
  local out = {}
  for _, c in ipairs(raw) do
    local card = sanitizeCard(c)
    if card then out[#out + 1] = card end
  end
  return out
end

function Custom.packs(mod)
  if not mod or not mod.save then return {} end
  local raw = mod.save:get("custom_packs", {})
  if type(raw) ~= "table" then return {} end
  local out = {}
  for _, p in ipairs(raw) do
    local pack = sanitizePack(p)
    if pack then out[#out + 1] = pack end
  end
  return out
end

function Custom.nextId(mod)
  local n = tonumber(mod.save:get("custom_next_id", Custom.FIRST_ID)) or Custom.FIRST_ID
  if n < Custom.FIRST_ID then n = Custom.FIRST_ID end
  for _, c in ipairs(Custom.cards(mod)) do
    if c.id >= n then n = c.id + 1 end
  end
  return n
end

function Custom.install(mod, cache)
  cache = cache or V.require("cache")
  local catalog = cache.catalog
  if catalog and catalog.cards and catalog.byId then
    local kept = {}
    for _, c in ipairs(catalog.cards) do
      if not c.custom then kept[#kept + 1] = c end
    end
    catalog.cards = kept
    local drop = {}
    for id, c in pairs(catalog.byId) do
      if c and c.custom then drop[#drop + 1] = id end
    end
    for _, id in ipairs(drop) do catalog.byId[id] = nil end
    for _, card in ipairs(Custom.cards(mod)) do
      catalog.cards[#catalog.cards + 1] = card
      catalog.byId[card.id] = card
    end
  end
  installedPacks = {}
  installedList = {}
  installedPics = {}
  installedPackPics = {}
  for _, p in ipairs(Custom.packs(mod)) do
    installedPacks[p.set] = p
    installedList[#installedList + 1] = p
  end
  local pics = mod and mod.save and mod.save:get("custom_pics", {}) or {}
  if type(pics) == "table" then
    for key, b64 in pairs(pics) do
      local id = tonumber(key)
      if id then installedPics[id] = decodeB64(b64) end
    end
  end
  local packPics = mod and mod.save and mod.save:get("custom_pack_pics", {}) or {}
  if type(packPics) == "table" then
    for key, b64 in pairs(packPics) do
      if type(key) == "string" then
        installedPackPics[key:upper()] = decodeB64(b64)
      end
    end
  end
end

function Custom.picB64(mod, id)
  if not (mod and mod.save) then return nil end
  local pics = mod.save:get("custom_pics", {})
  if type(pics) ~= "table" then return nil end
  local b64 = pics[tostring(tonumber(id) or id)]
  if type(b64) == "string" and b64 ~= "" then return b64 end
  return nil
end

function Custom.installedPic(id)
  return installedPics[tonumber(id)]
end

function Custom.setPic(mod, id, b64)
  id = tonumber(id)
  if not id then return false end
  local pics = mod.save:get("custom_pics", {})
  if type(pics) ~= "table" then pics = {} end
  if type(b64) == "string" and b64 ~= "" then
    pics[tostring(id)] = b64
  else
    pics[tostring(id)] = nil
  end
  mod.save:set("custom_pics", pics)
  Custom.install(mod)
  local ok, CardGfx = pcall(function() return V.require("card_gfx") end)
  if ok and CardGfx and CardGfx.forget then CardGfx.forget(id) end
  return true
end

function Custom.packPicB64(mod, setName)
  if not (mod and mod.save) then return nil end
  local pics = mod.save:get("custom_pack_pics", {})
  if type(pics) ~= "table" then return nil end
  local b64 = pics[(setName or ""):upper()]
  if type(b64) == "string" and b64 ~= "" then return b64 end
  return nil
end

function Custom.installedPackPic(setName)
  return installedPackPics[(setName or ""):upper()]
end

function Custom.setPackPic(mod, setName, b64)
  setName = (setName or ""):upper()
  if setName == "" then return false end
  local pics = mod.save:get("custom_pack_pics", {})
  if type(pics) ~= "table" then pics = {} end
  if type(b64) == "string" and b64 ~= "" then
    pics[setName] = b64
  else
    pics[setName] = nil
  end
  mod.save:set("custom_pack_pics", pics)
  Custom.install(mod)
  local ok, PackGfx = pcall(function() return V.require("pack_gfx") end)
  if ok and PackGfx and PackGfx.forget then PackGfx.forget(setName) end
  return true
end

function Custom.installedPack(setName)
  return installedPacks[(setName or ""):upper()]
end

function Custom.installedPacks()
  return installedList
end

local function writeCards(mod, cards)
  local raw = {}
  for _, c in ipairs(cards) do
    raw[#raw + 1] = sanitizeCard(c)
  end
  mod.save:set("custom_cards", raw)
  Custom.install(mod)
end

local function writePacks(mod, packs)
  local raw = {}
  for _, p in ipairs(packs) do
    raw[#raw + 1] = sanitizePack(p)
  end
  mod.save:set("custom_packs", raw)
  Custom.install(mod)
end

function Custom.saveCard(mod, draft)
  local cards = Custom.cards(mod)
  local id = tonumber(draft and draft.id)
  if not id then
    id = Custom.nextId(mod)
    mod.save:set("custom_next_id", id + 1)
  end
  draft = draft or {}
  draft.id = id
  local card = sanitizeCard(draft)
  if not card then return nil, "Invalid card" end
  local replaced = false
  for i, c in ipairs(cards) do
    if c.id == id then
      cards[i] = card
      replaced = true
      break
    end
  end
  if not replaced then cards[#cards + 1] = card end
  writeCards(mod, cards)
  if draft.picB64 ~= nil then
    Custom.setPic(mod, card.id, draft.picB64 ~= "" and draft.picB64 or nil)
  end
  return card
end

function Custom.deleteCard(mod, id)
  id = tonumber(id)
  if not id then return false end
  local cards = {}
  for _, c in ipairs(Custom.cards(mod)) do
    if c.id ~= id then cards[#cards + 1] = c end
  end
  writeCards(mod, cards)
  Custom.setPic(mod, id, nil)
  local packs = Custom.packs(mod)
  for _, p in ipairs(packs) do
    local keep = {}
    for _, cid in ipairs(p.cards) do
      if cid ~= id then keep[#keep + 1] = cid end
    end
    p.cards = keep
  end
  writePacks(mod, packs)
  local Save = V.require("save")
  local col = Save.collection(mod)
  col[tostring(id)] = nil
  mod.save:set("collection", col)
  local deck = Save.deck(mod)
  local kept = {}
  for _, cid in ipairs(deck) do
    if tonumber(cid) ~= id then kept[#kept + 1] = cid end
  end
  Save.setDeck(mod, kept)
  return true
end

local VANILLA = {
  COLOSSEUM = true, EVOLUTION = true, MYSTERY = true,
  LABORATORY = true, ENERGY = true, PROMOTIONAL = true, PREMIUM = true,
}

function Custom.uniqueSet(mod, name, keepSet)
  local set = tostring(name or "CUSTOM"):upper()
  set = set:gsub("[^A-Z0-9 ]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if set == "" then set = "CUSTOM" end
  if VANILLA[set] then set = "C " .. set end
  local used = {}
  for _, p in ipairs(Custom.packs(mod)) do
    if p.set ~= keepSet then used[p.set] = true end
  end
  if not used[set] then return set end
  local n = 2
  while used[set .. " " .. tostring(n)] do n = n + 1 end
  return set .. " " .. tostring(n)
end

function Custom.savePack(mod, draft)
  draft = draft or {}
  local keep = draft.set
  local set = Custom.uniqueSet(mod, draft.name or draft.set, keep)
  if keep and keep ~= "" then set = keep end
  draft.set = set
  local pack = sanitizePack(draft)
  if not pack then return nil, "Add at least one card" end
  local packs = Custom.packs(mod)
  local replaced = false
  for i, p in ipairs(packs) do
    if p.set == pack.set then
      packs[i] = pack
      replaced = true
      break
    end
  end
  if not replaced then packs[#packs + 1] = pack end
  writePacks(mod, packs)
  if draft.picB64 ~= nil then
    Custom.setPackPic(mod, pack.set, draft.picB64 ~= "" and draft.picB64 or nil)
  end
  return pack
end

function Custom.deletePack(mod, setName)
  setName = (setName or ""):upper()
  local packs = {}
  for _, p in ipairs(Custom.packs(mod)) do
    if p.set ~= setName then packs[#packs + 1] = p end
  end
  writePacks(mod, packs)
  Custom.setPackPic(mod, setName, nil)
  local Save = V.require("save")
  local inv = mod.save:get("pack_inv", {})
  if type(inv) == "table" then
    inv[setName] = nil
    mod.save:set("pack_inv", inv)
  end
  return true
end

return Custom
