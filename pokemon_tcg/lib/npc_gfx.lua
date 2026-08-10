-- pret/poketcg NPC placement + OW sprite frames for TCG map screens.
local V = ...
local Cache = V.require("cache")
local TcgText = V.require("tcg_text")
local NpcScript = V.require("npc_script")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local NpcGfx = {}

-- MapScripts @ 04:562a (16 bytes/map; slot 0 = NPC list)
local MAP_SCRIPTS_BANK = 0x04
local MAP_SCRIPTS_OFFSET = 0x562a
local MAP_SCRIPT_SIZE = 16
-- NPCHeaderPointers @ 04:58f5
local NPC_HEADERS_BANK = 0x04
local NPC_HEADERS_OFFSET = 0x58f5
-- Sprites @ 20:516b (ptr_lo, ptr_hi, bankRel, tileCount)
local SPRITES_BANK = 0x20
local SPRITES_OFFSET = 0x516b

local DIR_FACING = { [0] = "north", [1] = "east", [2] = "south", [3] = "west" }

local OW_PAL = {
  { 1, 1, 1, 0 },
  { 0.95, 0.75, 0.55, 1 },
  { 0.25, 0.45, 0.85, 1 },
  { 0.1, 0.1, 0.1, 1 },
}

-- AnimFrameTable0 stand frames (20-tile OW sprites)
local OAM_20 = {
  north = {
    { 0, 0, 8, false }, { 0, 8, 9, false },
    { 8, 0, 10, false }, { 8, 8, 11, false },
  },
  south = {
    { 0, 0, 2, false }, { 0, 8, 3, false },
    { 8, 0, 4, false }, { 8, 8, 5, false },
  },
  east = {
    { 0, 0, 12, false }, { 0, 8, 13, false },
    { 8, 0, 14, false }, { 8, 8, 15, false },
  },
}

-- AnimFrameTable3 stand frames (8-tile clerks)
local OAM_8 = {
  north = {
    { 0, 0, 6, false }, { 8, 0, 7, false },
    { 0, 8, 6, true }, { 8, 8, 7, true },
  },
  south = {
    { 0, 0, 0, false }, { 8, 0, 1, false },
    { 0, 8, 0, true }, { 8, 8, 1, true },
  },
  east = {
    { 0, 0, 2, false }, { 0, 8, 3, false },
    { 8, 0, 4, false }, { 8, 8, 5, false },
  },
}

local romData = nil
local spriteCache = {} -- spriteId -> { north=, south=, east= }

local function bankFileOffset(bank, offsetInBank)
  if bank == 0 then return offsetInBank end
  return bank * 0x4000 + (offsetInBank - 0x4000)
end

local function u8(rom, off)
  return rom:byte(off + 1)
end

local function u16le(rom, off)
  return u8(rom, off) + u8(rom, off + 1) * 256
end

local function ensureRom()
  if romData then return true end
  local catalog = Cache.get()
  local path = catalog and catalog.path
  if not path then return false end
  local RomImport = V.require("rom_import")
  local data = RomImport.readFile(path)
  if not data then return false end
  romData = data
  return true
end

function NpcGfx.clear()
  romData = nil
  spriteCache = {}
end

local function decodeTilePixels(tile, pal)
  local pix = {}
  for y = 0, 7 do
    local low = tile[y * 2] or 0
    local high = tile[y * 2 + 1] or 0
    for x = 0, 7 do
      local bitn = 7 - x
      local shade = band(rshift(high, bitn), 1) * 2 + band(rshift(low, bitn), 1)
      pix[y * 8 + x + 1] = pal[shade + 1] or pal[1]
    end
  end
  return pix
end

local function frameFromOam(tiles, parts)
  local img = love.image.newImageData(16, 16)
  for py = 0, 15 do
    for px = 0, 15 do
      img:setPixel(px, py, 0, 0, 0, 0)
    end
  end
  for _, part in ipairs(parts) do
    local oy, ox, tid, xflip = part[1], part[2], part[3], part[4]
    local pix = tiles[tid]
    if pix then
      for ty = 0, 7 do
        for tx = 0, 7 do
          local sx = xflip and (7 - tx) or tx
          local c = pix[ty * 8 + sx + 1]
          local a = c[4] or 1
          if a > 0 and not (c[1] == 1 and c[2] == 1 and c[3] == 1) then
            img:setPixel(ox + tx, oy + ty, c[1], c[2], c[3], a)
          end
        end
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  return image
end

local function loadSpriteFrames(spriteId)
  if spriteCache[spriteId] then return spriteCache[spriteId] end
  if not ensureRom() then return nil end
  local entry = bankFileOffset(SPRITES_BANK, SPRITES_OFFSET) + spriteId * 4
  local ptr = u16le(romData, entry)
  local bankRel = u8(romData, entry + 2)
  local tileCount = u8(romData, entry + 3)
  local gfxBank = SPRITES_BANK + bankRel
  local goff = bankFileOffset(gfxBank, ptr)
  local count = u16le(romData, goff)
  if count < 1 then count = tileCount end
  local base = goff + 2
  local tiles = {}
  for t = 0, count - 1 do
    local tile = {}
    for i = 0, 15 do tile[i] = u8(romData, base + t * 16 + i) end
    tiles[t] = decodeTilePixels(tile, OW_PAL)
  end

  local oam = (count >= 20) and OAM_20 or OAM_8
  local frames = {
    north = frameFromOam(tiles, oam.north),
    south = frameFromOam(tiles, oam.south),
    east = frameFromOam(tiles, oam.east),
  }
  spriteCache[spriteId] = frames
  return frames
end

local function readHeader(npcId)
  local tableOff = bankFileOffset(NPC_HEADERS_BANK, NPC_HEADERS_OFFSET)
  local ptr = u16le(romData, tableOff + npcId * 2)
  if ptr == 0 then return nil end
  local off = bankFileOffset(NPC_HEADERS_BANK, ptr)
  local spriteId = u8(romData, off + 1)
  local scriptPtr = u16le(romData, off + 5)
  local nameTx = u16le(romData, off + 7)
  local pic = u8(romData, off + 9)
  local deckId = u8(romData, off + 10)
  local name = TcgText.decode(romData, nameTx, { upper = true }) or ("NPC " .. tostring(npcId))
  local dialog = NpcScript.firstDialogText(romData, scriptPtr)
  return {
    spriteId = spriteId,
    scriptPtr = scriptPtr,
    nameTx = nameTx,
    name = name,
    dialog = dialog,
    pic = pic,
    deckId = deckId,
  }
end

function NpcGfx.loadForMap(mapId)
  if not mapId or mapId < 1 then return {} end
  if not ensureRom() then return {} end
  local scripts = bankFileOffset(MAP_SCRIPTS_BANK, MAP_SCRIPTS_OFFSET) + mapId * MAP_SCRIPT_SIZE
  local listPtr = u16le(romData, scripts)
  if listPtr == 0 then return {} end
  local off = bankFileOffset(MAP_SCRIPTS_BANK, listPtr)
  local npcs = {}
  while true do
    local npcId = u8(romData, off)
    if npcId == 0 then break end
    local x = u8(romData, off + 1)
    local y = u8(romData, off + 2)
    local dir = u8(romData, off + 3)
    -- skip off-map placeholders ($fe/$ff) used by event Ronalds etc.
    if x < 0xF0 and y < 0xF0 then
      local header = readHeader(npcId)
      if header then
        local facing = DIR_FACING[dir] or "south"
        npcs[#npcs + 1] = {
          id = npcId,
          x = x,
          y = y,
          dir = dir,
          facing = facing,
          name = header.name,
          dialog = header.dialog,
          scriptPtr = header.scriptPtr,
          spriteId = header.spriteId,
          deckId = header.deckId,
          pic = header.pic,
        }
        loadSpriteFrames(header.spriteId)
      end
    end
    off = off + 6
  end
  return npcs
end

function NpcGfx.image(npc)
  if not npc then return nil, false end
  local frames = loadSpriteFrames(npc.spriteId)
  if not frames then return nil, false end
  local facing = npc.facing or "south"
  if facing == "west" then
    return frames.east, true
  elseif facing == "north" then
    return frames.north, false
  elseif facing == "east" then
    return frames.east, false
  end
  return frames.south, false
end

function NpcGfx.at(npcs, tx, ty)
  if not npcs then return nil end
  for _, n in ipairs(npcs) do
    if n.x == tx and n.y == ty then return n end
  end
  return nil
end

function NpcGfx.facingTile(tx, ty, facing)
  if facing == "north" then return tx, ty - 1 end
  if facing == "south" then return tx, ty + 1 end
  if facing == "west" then return tx - 1, ty end
  if facing == "east" then return tx + 1, ty end
  return tx, ty
end

-- pret *_DECK_ID = DeckPointers index - 2
function NpcGfx.deckCards(deckId)
  if not deckId or deckId == 0 then return nil, nil end
  local cat = Cache.get()
  if not cat or not cat.decks then return nil, nil end
  local idx = deckId + 2
  for _, d in ipairs(cat.decks) do
    if d.index == idx and type(d.cards) == "table" and #d.cards >= 60 then
      return d.cards, d.label
    end
  end
  -- Aliased / skipped pointer slots: match DeckPointers[idx] to a loaded deck.
  if not ensureRom() then return nil, nil end
  local Layout = V.require("data.import_layout")
  local base = bankFileOffset(Layout.DECK_POINTERS_BANK, Layout.DECK_POINTERS_OFFSET)
  local ptr = u16le(romData, base + idx * 2)
  if ptr == 0 then return nil, nil end
  for _, d in ipairs(cat.decks) do
    if d.ptr == ptr and type(d.cards) == "table" and #d.cards >= 60 then
      return d.cards, d.label or ("DECK " .. tostring(idx))
    end
  end
  return nil, nil
end

function NpcGfx.dialogText(npc)
  if not npc then return nil end
  if npc.dialog and npc.dialog ~= "" then return npc.dialog end
  return npc.name or "..."
end

return NpcGfx

