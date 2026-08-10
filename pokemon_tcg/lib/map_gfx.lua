-- Decode pret/poketcg overworld tilemaps + tilesets for TCG map screens.
local V = ...
local Cache = V.require("cache")
local Maps = V.require("data.maps")
local NpcGfx = V.require("npc_gfx")
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local MapGfx = {}

-- WarpDataPointers @ 07:4099 (pret)
local WARP_POINTERS_BANK = 0x07
local WARP_POINTERS_OFFSET = 0x4099
-- OWPlayerGfx @ 22:7E90
local PLAYER_GFX_BANK = 0x22
local PLAYER_GFX_OFFSET = 0x7E90

local romData = nil
local cache = {} -- key -> baked map
local playerFrames = nil -- facing -> Image
local byMapId = nil

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

function MapGfx.clear()
  cache = {}
  romData = nil
  playerFrames = nil
  NpcGfx.clear()
end

local function ensureById()
  if byMapId then return byMapId end
  byMapId = {}
  for key, info in pairs(Maps) do
    if info.mapId then byMapId[info.mapId] = key end
  end
  return byMapId
end

function MapGfx.keyForId(mapId)
  return ensureById()[mapId]
end

local function loadWarps(mapId)
  if not mapId or mapId < 1 then return {} end
  local tableOff = bankFileOffset(WARP_POINTERS_BANK, WARP_POINTERS_OFFSET)
  local ptr = u16le(romData, tableOff + mapId * 2)
  if ptr == 0 then return {} end
  local off = bankFileOffset(WARP_POINTERS_BANK, ptr)
  local warps = {}
  while true do
    local x = u8(romData, off)
    local y = u8(romData, off + 1)
    local destId = u8(romData, off + 2)
    local dx = u8(romData, off + 3)
    local dy = u8(romData, off + 4)
    off = off + 5
    if x == 0 and y == 0 then break end
    warps[#warps + 1] = {
      x = x, y = y,
      destId = destId,
      destKey = MapGfx.keyForId(destId),
      dx = dx, dy = dy,
    }
  end
  return warps
end

local function rgb555(word)
  local r = band(word, 0x1F) / 31
  local g = band(rshift(word, 5), 0x1F) / 31
  local b = band(rshift(word, 10), 0x1F) / 31
  return r, g, b
end

-- pret InitDataDecompression + DecompressData
local function decompress(rom, srcOff, length)
  local pos = srcOff
  local numCmdBits, cmdByte, carry = 1, 0, 0
  local repeatToggle, repeatLengths, numToRepeat = false, 0, 0
  local secondary = {}
  for i = 0, 255 do secondary[i] = 0 end
  local secLow, repeatOff = 0xEF, 0
  local out = {}

  local function get()
    local b = u8(rom, pos)
    pos = pos + 1
    return b
  end

  local function repeatByte()
    local a = secondary[band(repeatOff, 0xFF)]
    repeatOff = band(repeatOff + 1, 0xFF)
    secondary[secLow] = a
    secLow = band(secLow + 1, 0xFF)
    return a
  end

  for _ = 1, length do
    local a
    if numToRepeat ~= 0 then
      numToRepeat = numToRepeat - 1
      a = repeatByte()
    else
      numCmdBits = numCmdBits - 1
      if numCmdBits == 0 then
        numCmdBits = 8
        cmdByte = get()
      end
      local newCarry = band(rshift(cmdByte, 7), 1)
      cmdByte = band(lshift(cmdByte, 1) + carry, 0xFF)
      carry = newCarry
      a = get()
      if carry ~= 0 then
        secondary[secLow] = a
        secLow = band(secLow + 1, 0xFF)
      else
        repeatOff = a
        if not repeatToggle then
          repeatToggle = true
          repeatLengths = get()
          numToRepeat = band(rshift(repeatLengths, 4), 0xF) + 1
        else
          repeatToggle = false
          numToRepeat = band(repeatLengths, 0xF) + 1
        end
        a = repeatByte()
      end
    end
    out[#out + 1] = a
  end
  return out
end

local function loadPalette(rom, bank, offset)
  -- Palettes start with a short header; first BGP is 4×RGB555.
  local off = bankFileOffset(bank, offset) + 2
  local colors = {}
  for i = 0, 3 do
    local word = u16le(rom, off + i * 2)
    local r, g, b = rgb555(word)
    colors[i + 1] = { r, g, b, 1 }
  end
  return colors
end

local function loadTiles(rom, bank, offset)
  local goff = bankFileOffset(bank, offset)
  local tileCount = u16le(rom, goff)
  local tiles = {}
  local base = goff + 2
  for t = 0, tileCount - 1 do
    local tile = {}
    for i = 0, 15 do
      tile[i] = u8(rom, base + t * 16 + i)
    end
    tiles[t] = tile
  end
  return tiles, tileCount
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

function MapGfx.load(key)
  if cache[key] then return cache[key] end
  if not ensureRom() then return nil, "No ROM" end
  local info = Maps[key]
  if not info then return nil, "Unknown map" end

  local mapOff = bankFileOffset(info.mapBank, info.mapOffset)
  local tw, th = u8(romData, mapOff), u8(romData, mapOff + 1)
  if tw < 1 or th < 1 or tw > 64 or th > 64 then
    return nil, "Bad map size"
  end

  local tilemap = decompress(romData, mapOff + 5, tw * th)
  local pw, ph = math.floor(tw / 2), math.floor(th / 2)
  -- Header dw points at the compressed permission map (half W × half H).
  local permPtr = u16le(romData, mapOff + 2)
  local permOff = bankFileOffset(info.mapBank, permPtr)
  local perms = decompress(romData, permOff, pw * ph)

  local tiles, tileCount = loadTiles(romData, info.tilesBank, info.tilesOffset)
  local pal = loadPalette(romData, info.palBank, info.palOffset)

  local decoded = {}
  for t = 0, tileCount - 1 do
    decoded[t] = decodeTilePixels(tiles[t], pal)
  end

  local wpx, hpx = tw * 8, th * 8
  local img = love.image.newImageData(wpx, hpx)
  for ty = 0, th - 1 do
    for tx = 0, tw - 1 do
      local tid = tilemap[ty * tw + tx + 1] or 0
      -- VRAM base $80 for OW maps
      local idx = tid >= 0x80 and (tid - 0x80) or tid
      local pix = decoded[idx] or decoded[0]
      if pix then
        for py = 0, 7 do
          for px = 0, 7 do
            local c = pix[py * 8 + px + 1]
            img:setPixel(tx * 8 + px, ty * 8 + py, c[1], c[2], c[3], 1)
          end
        end
      end
    end
  end

  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")

  local map = {
    key = key,
    mapId = info.mapId,
    label = info.label or key,
    tw = tw,
    th = th,
    pw = pw,
    ph = ph,
    perms = perms,
    image = image,
    wpx = wpx,
    hpx = hpx,
    spawnX = info.spawnX or 2,
    spawnY = info.spawnY or 2,
    warps = loadWarps(info.mapId),
    npcs = NpcGfx.loadForMap(info.mapId),
  }
  cache[key] = map
  return map
end

function MapGfx.canWalk(map, tx, ty)
  if not map then return false end
  if tx < 0 or ty < 0 or tx >= map.tw or ty >= map.th then return false end
  if NpcGfx.at(map.npcs, tx, ty) then return false end
  local cx, cy = math.floor(tx / 2), math.floor(ty / 2)
  if cx < 0 or cy < 0 or cx >= map.pw or cy >= map.ph then return false end
  local p = map.perms[cy * map.pw + cx + 1] or 0xFF
  return p == 0
end

function MapGfx.npcAt(map, tx, ty)
  return map and NpcGfx.at(map.npcs, tx, ty) or nil
end

MapGfx.Npc = NpcGfx

function MapGfx.warpAt(map, tx, ty)
  if not map or not map.warps then return nil end
  for _, w in ipairs(map.warps) do
    if w.x == tx and w.y == ty then return w end
  end
  return nil
end

-- OW player tiles + AnimFrameTable0 OAM (pret anims1.asm).
-- Tile packing is not five linear 2×2 frames; down/up walk halves are mirrored.
local PLAYER_PAL = {
  { 1, 1, 1, 0 },          -- shade 0 → transparent
  { 0.95, 0.75, 0.55, 1 }, -- skin
  { 0.25, 0.45, 0.85, 1 }, -- shirt / hat
  { 0.1, 0.1, 0.1, 1 },    -- outline
}

-- { y, x, tileId, xflip } per OAM entry
local PLAYER_OAM = {
  north = {
    { 0, 0, 8, false }, { 0, 8, 9, false },
    { 8, 0, 10, false }, { 8, 8, 11, false },
  },
  north_walk = {
    { 0, 0, 6, false }, { 8, 0, 7, false },
    { 8, 8, 7, true }, { 0, 8, 6, true },
  },
  south = {
    { 0, 0, 2, false }, { 0, 8, 3, false },
    { 8, 0, 4, false }, { 8, 8, 5, false },
  },
  south_walk = {
    { 0, 0, 0, false }, { 8, 0, 1, false },
    { 0, 8, 0, true }, { 8, 8, 1, true },
  },
  east = {
    { 0, 0, 12, false }, { 0, 8, 13, false },
    { 8, 0, 14, false }, { 8, 8, 15, false },
  },
  east_walk = {
    { 0, 0, 16, false }, { 0, 8, 17, false },
    { 8, 0, 18, false }, { 8, 8, 19, false },
  },
}

local function buildPlayerFrames()
  if playerFrames then return playerFrames end
  if not ensureRom() then return nil end
  local goff = bankFileOffset(PLAYER_GFX_BANK, PLAYER_GFX_OFFSET)
  local tileCount = u16le(romData, goff)
  local base = goff + 2
  local tiles = {}
  for t = 0, tileCount - 1 do
    local tile = {}
    for i = 0, 15 do tile[i] = u8(romData, base + t * 16 + i) end
    tiles[t] = decodeTilePixels(tile, PLAYER_PAL)
  end

  local function frameFromOam(parts)
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

  playerFrames = {
    north = frameFromOam(PLAYER_OAM.north),
    north_walk = frameFromOam(PLAYER_OAM.north_walk),
    south = frameFromOam(PLAYER_OAM.south),
    south_walk = frameFromOam(PLAYER_OAM.south_walk),
    east = frameFromOam(PLAYER_OAM.east),
    east_walk = frameFromOam(PLAYER_OAM.east_walk),
  }
  return playerFrames
end

function MapGfx.playerImage(facing, walking)
  local frames = buildPlayerFrames()
  if not frames then return nil end
  if facing == "north" then
    return walking and frames.north_walk or frames.north, false
  elseif facing == "east" then
    return walking and frames.east_walk or frames.east, false
  elseif facing == "west" then
    -- AnimData3 = east frames with OAM_XFLIP
    return walking and frames.east_walk or frames.east, true
  end
  return walking and frames.south_walk or frames.south, false
end

MapGfx.MAPS = Maps

return MapGfx
