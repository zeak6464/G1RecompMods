-- Decode Pokémon TCG (U) ROM into a plain Lua card catalog.
-- Layout: pret/poketcg symbols for the matching SHA1.

local V = ...
local Layout = V.require("data.import_layout")
local CardIds = V.require("data.card_ids")
local TcgText = V.require("tcg_text")
local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol


local RomImport = {}

RomImport.EXPECTED_SHA1 = Layout.SHA1

local function bankFileOffset(bank, offsetInBank)
  if bank == 0 then return offsetInBank end
  return bank * 0x4000 + (offsetInBank - 0x4000)
end

local function u8(data, off)
  return data:byte(off + 1)
end

local function u16le(data, off)
  local lo, hi = data:byte(off + 1, off + 2)
  return lo + hi * 256
end

-- Pure-Lua SHA1 for headless tests. LOVE uses love.data.hash instead.
-- LuaJIT bit ops are signed; normalize to unsigned before %08x / length math.
local function u32(n)
  n = band(n, 0xffffffff)
  if n < 0 then n = n + 4294967296 end
  return n
end

local function sha1Pure(msg)
  local function tohex(n)
    return string.format("%08x", u32(n))
  end
  local h0, h1, h2, h3, h4 =
    0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local ml = #msg * 8
  msg = msg .. "\128"
  while (#msg % 64) ~= 56 do msg = msg .. "\0" end
  -- append 64-bit big-endian length (ml fits in low 32 for our ROM sizes)
  msg = msg .. string.char(0, 0, 0, 0)
  msg = msg .. string.char(
    band(rshift(ml, 24), 0xff),
    band(rshift(ml, 16), 0xff),
    band(rshift(ml, 8), 0xff),
    band(ml, 0xff))
  for chunk = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do
      local j = chunk + i * 4
      w[i] = u32(bor(
        lshift(msg:byte(j), 24),
        lshift(msg:byte(j + 1), 16),
        lshift(msg:byte(j + 2), 8),
        msg:byte(j + 3)))
    end
    for i = 16, 79 do
      w[i] = u32(rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1))
    end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then
        f = bor(band(b, c), band(bnot(b), d)); k = 0x5A827999
      elseif i < 40 then
        f = bxor(b, c, d); k = 0x6ED9EBA1
      elseif i < 60 then
        f = bor(band(b, c), band(b, d), band(c, d)); k = 0x8F1BBCDC
      else
        f = bxor(b, c, d); k = 0xCA62C1D6
      end
      local temp = u32(u32(rol(a, 5)) + u32(f) + u32(e) + u32(k) + w[i])
      e, d, c, b, a = d, c, u32(rol(b, 30)), a, temp
    end
    h0 = u32(h0 + a)
    h1 = u32(h1 + b)
    h2 = u32(h2 + c)
    h3 = u32(h3 + d)
    h4 = u32(h4 + e)
  end
  return tohex(h0) .. tohex(h1) .. tohex(h2) .. tohex(h3) .. tohex(h4)
end


function RomImport.sha1(data)
  if love and love.data and love.data.hash then
    local digest = love.data.hash("sha1", data)
    if type(digest) == "userdata" and digest.getString then
      digest = digest:getString()
    end
    if love.data.encode then
      return love.data.encode("string", "hex", digest)
    end
  end
  return sha1Pure(data)
end

function RomImport.readFile(path)
  -- First try LÖVE's virtual filesystem.
  -- This is required for files under the game's AppData/save directory.
  if love and love.filesystem and love.filesystem.read then
    local data = love.filesystem.read(path)
    if data and type(data) == "string" and #data > 0 then
      return data
    end
  end

  -- Fall back to the normal OS filesystem for absolute/external paths.
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  if type(data) ~= "string" or #data == 0 then
    return nil, "empty ROM"
  end
  return data
end

function RomImport.candidatePaths(mod)
  local paths = {}
  local function add(p)
    if type(p) == "string" and p ~= "" then paths[#paths + 1] = p end
  end
  if mod and mod.options and mod.options.get then
    add(mod.options:get("rom_path"))
  end
  if mod and mod.save then
    add(mod.save:get("rom_path"))
  end
  if mod and mod.path then
    add(mod.path .. "/baseroms/PokemonTCG.gbc")
    -- mods/pokemon_tcg → project root roms/
    add(mod.path .. "/../../roms/PokemonTCG.gbc")
    add(mod.path .. "/../roms/PokemonTCG.gbc")
    add(mod.path .. "/roms/PokemonTCG.gbc")
  end
  add("roms/PokemonTCG.gbc")
  add("./roms/PokemonTCG.gbc")
  -- LOVE save/identity cwd variants
  if love and love.filesystem and love.filesystem.getSource then
    local src = love.filesystem.getSource()
    if type(src) == "string" then
      add(src .. "/roms/PokemonTCG.gbc")
    end
  end
  return paths
end

function RomImport.findRom(mod)
  -- Launcher required_imports copies the dump here; prefer that over host paths.
  if mod and type(mod.read) == "function" then
    local data = mod:read("baseroms/PokemonTCG.gbc")
    if type(data) == "string" and #data > 0 then
      return "baseroms/PokemonTCG.gbc", data
    end
  end
  for _, path in ipairs(RomImport.candidatePaths(mod)) do
    local data = RomImport.readFile(path)
    if data then
      return path, data
    end
  end
  return nil, nil, "Pokémon TCG ROM not found (expected launcher import)"
end

local function decodeEnergyCost(data, off)
  -- 4 bytes packing energy counts for FIRE..COLORLESS (see pret energy macro)
  local bytes = { data:byte(off + 1, off + 4) }
  local counts = { 0, 0, 0, 0, 0, 0, 0, 0 } -- FIRE..UNUSED
  for t = 0, 7 do
    -- pret: even types use high nibble, odd use low nibble of each byte
    local byteIndex = math.floor(t / 2)
    local nibble = (t % 2 == 0)
      and band(rshift(bytes[byteIndex + 1], 4), 0xF)
      or band(bytes[byteIndex + 1], 0xF)
    counts[t + 1] = nibble
  end
  local cost = {}
  local names = { "FIRE", "GRASS", "LIGHTNING", "WATER", "FIGHTING", "PSYCHIC", "COLORLESS" }
  for i = 1, 7 do
    if counts[i] > 0 then cost[names[i]] = counts[i] end
  end
  return cost
end


local function decodeAttack(data, off)
  local nameId = u16le(data, off + 4)
  local damage = u8(data, off + 0x0A)
  local category = u8(data, off + 0x0B)
  if nameId == 0 and damage == 0 then return nil end
  local name = TcgText.decode(data, nameId, { upper = true })
  return {
    cost = decodeEnergyCost(data, off),
    nameId = nameId,
    name = name or "ATTACK",
    damage = damage,
    category = category,
    flags1 = u8(data, off + 0x0E),
    flags2 = u8(data, off + 0x0F),
    flags3 = u8(data, off + 0x10),
    effectParam = u8(data, off + 0x11),
    -- pret CARD_DATA_ATTACK*_ANIMATION (relative +$12)
    animId = u8(data, off + 0x12),
  }
end


local function wrName(byte)
  return Layout.WR[byte]
end

local function prettyName(idKey)
  if not idKey then return "?" end
  return (idKey:gsub("_", " "))
end

function RomImport.decodeCards(data)
  local cards, byId = {}, {}
  local cp = bankFileOffset(Layout.CARD_POINTERS_BANK, Layout.CARD_POINTERS_OFFSET)
  -- CardPointers: [0]=NULL, [1..NUM_CARDS]=cards, [NUM_CARDS+1]=NULL
  for id = 1, Layout.NUM_CARDS do
    local ptr = u16le(data, cp + id * 2)
    if ptr ~= 0 then
      local off = bankFileOffset(Layout.CARD_POINTERS_BANK, ptr)
      local typeByte = u8(data, off)
      local label = CardIds[id] or ("CARD_" .. id)
      local nameId = u16le(data, off + 3)
      local romName = TcgText.decode(data, nameId, { upper = true })
      local card = {
        id = id,
        key = label,
        name = romName or prettyName(label),
        nameId = nameId,
        typeByte = typeByte,
        rarity = Layout.RARITY[u8(data, off + 5)] or "CIRCLE",
        set = Layout.SET_HI[rshift(u8(data, off + 6), 4)] or "COLOSSEUM",
        gfx = u16le(data, off + 1),
      }
      if typeByte < Layout.TYPE_ENERGY then
        card.kind = "pokemon"
        card.type = Layout.TYPE_NAME[typeByte] or "COLORLESS"
        card.hp = u8(data, off + 8)
        card.stage = Layout.STAGE[u8(data, off + 9)] or "BASIC"
        card.preEvoNameId = u16le(data, off + 0x0A)
        if card.preEvoNameId ~= 0 then
          card.preEvoName = TcgText.decode(data, card.preEvoNameId, { upper = true })
        end
        card.attacks = {}
        local a1 = decodeAttack(data, off + 0x0C)
        local a2 = decodeAttack(data, off + 0x1F)
        if a1 then card.attacks[#card.attacks + 1] = a1 end
        if a2 then card.attacks[#card.attacks + 1] = a2 end
        card.retreat = u8(data, off + 0x32)
        card.weakness = wrName(u8(data, off + 0x33))
        card.resistance = wrName(u8(data, off + 0x34))
        card.dex = u8(data, off + 0x37)
        card.level = u8(data, off + 0x39)


      elseif typeByte >= Layout.TYPE_TRAINER then
        card.kind = "trainer"
        card.type = "TRAINER"
      else
        card.kind = "energy"
        card.type = Layout.TYPE_NAME[typeByte] or "ENERGY"
        card.energyType = card.type:gsub("^ENERGY_", "")
      end
      cards[#cards + 1] = card
      byId[id] = card
    end
  end
  return cards, byId
end

-- pret card_item expands to: db count, db card_id. List ends with db 0.
function RomImport.decodeDeckAt(data, fileOff)
  local deck = {}
  local i = fileOff
  while true do
    local count = u8(data, i)
    if count == 0 then break end
    local cid = u8(data, i + 1)
    if cid == 0 or cid > Layout.NUM_CARDS or count > 60 then break end
    for _ = 1, count do
      deck[#deck + 1] = cid
      if #deck >= 60 then break end
    end
    i = i + 2
    if #deck >= 60 or (i - fileOff) > 200 then break end
  end
  return deck
end

function RomImport.decodePracticeDeck(data)
  local off = bankFileOffset(
    Layout.PRACTICE_PLAYER_DECK_BANK, Layout.PRACTICE_PLAYER_DECK_OFFSET)
  return RomImport.decodeDeckAt(data, off)
end

function RomImport.decodeAllDecks(data)
  local DeckNames = V.require("data.deck_names")
  local base = bankFileOffset(Layout.DECK_POINTERS_BANK, Layout.DECK_POINTERS_OFFSET)
  local decks = {}
  local seenPtr = {}
  for idx = 0, 80 do
    local ptr = u16le(data, base + idx * 2)
    if ptr == 0 then break end
    local meta = DeckNames[idx] or {
      key = "DECK_" .. idx,
      label = ("DECK %d"):format(idx),
      skip = false,
    }
    local fileOff = bankFileOffset(Layout.DECK_POINTERS_BANK, ptr)
    local cards = RomImport.decodeDeckAt(data, fileOff)
    local entry = {
      index = idx,
      key = meta.key,
      label = meta.label,
      skip = meta.skip or false,
      ptr = ptr,
      cards = cards,
    }
    -- Prefer first occurrence when ROM aliases the same pointer.
    if not seenPtr[ptr] then
      seenPtr[ptr] = true
      decks[#decks + 1] = entry
    elseif not meta.skip then
      -- Keep alias only if first was skipped and this one is fightable.
      for _, d in ipairs(decks) do
        if d.ptr == ptr and d.skip and not meta.skip then
          d.key, d.label, d.skip, d.index = meta.key, meta.label, false, idx
          break
        end
      end
    end
  end
  return decks
end

function RomImport.duelOpponents(decks)
  local out = {}
  for _, d in ipairs(decks or {}) do
    if not d.skip and type(d.cards) == "table" and #d.cards >= 60 then
      out[#out + 1] = d
    end
  end
  return out
end

function RomImport.import(mod, path)
  path = path or select(1, RomImport.findRom(mod))
  if not path then
    return nil, "Pokémon TCG ROM not found"
  end
  local data, err = RomImport.readFile(path)
  if not data then return nil, err end
  local hash = RomImport.sha1(data)
  if hash ~= RomImport.EXPECTED_SHA1 then
    return nil, ("ROM SHA1 mismatch (got %s, want %s)"):format(hash, RomImport.EXPECTED_SHA1)
  end
  local cards, byId = RomImport.decodeCards(data)
  local practice = RomImport.decodePracticeDeck(data)
  local allDecks = RomImport.decodeAllDecks(data)
  local catalog = {
    sha1 = hash,
    path = path,
    cards = cards,
    byId = byId,
    practiceDeck = practice,
    decks = allDecks,
    duelOpponents = RomImport.duelOpponents(allDecks),
    importedAt = os.time(),
  }
  return catalog
end

return RomImport
