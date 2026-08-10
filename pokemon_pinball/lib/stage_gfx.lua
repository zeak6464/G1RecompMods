-- Decode pret stage backgrounds (2bpp tiles + GBC tilemap/attr + palettes).
local V = ...
local Layout = V.require("data.import_layout")
local RomImport = V.require("rom_import")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local StageGfx = {}

local images = {} -- key -> Image
local romData = nil

local function stages()
  return {
    RED_BOTTOM = {
      kind = "bottom",
      gfx0 = Layout.RED_BOTTOM_GFX0,
      gfx1 = Layout.RED_BOTTOM_GFX1,
      tilemap = Layout.RED_BOTTOM_TILEMAP,
      attr = Layout.RED_BOTTOM_ATTR,
      pal = Layout.RED_BOTTOM_PAL,
    },
    BLUE_BOTTOM = {
      kind = "bottom",
      gfx0 = Layout.BLUE_BOTTOM_GFX0,
      gfx1 = Layout.BLUE_BOTTOM_GFX1,
      tilemap = Layout.BLUE_BOTTOM_TILEMAP,
      attr = Layout.BLUE_BOTTOM_ATTR,
      pal = Layout.BLUE_BOTTOM_PAL,
    },
    RED_TOP = {
      kind = "top",
      status = Layout.RED_TOP_STATUS,
      gfx3 = Layout.RED_TOP_GFX3,
      base = Layout.RED_TOP_BASE,
      gfx1 = Layout.RED_TOP_GFX4,
      tilemap = Layout.RED_TOP_TILEMAP,
      attr = Layout.RED_TOP_ATTR,
      pal = Layout.RED_TOP_PAL,
    },
    BLUE_TOP = {
      kind = "top",
      status = Layout.BLUE_TOP_STATUS,
      gfx3 = Layout.BLUE_TOP_GFX3,
      base = Layout.BLUE_TOP_BASE,
      gfx1 = Layout.BLUE_TOP_GFX4,
      tilemap = Layout.BLUE_TOP_TILEMAP,
      attr = Layout.BLUE_TOP_ATTR,
      pal = Layout.BLUE_TOP_PAL,
    },
  }
end

local function stageKey(field, half)
  field = (field or "RED"):upper()
  if field ~= "BLUE" then field = "RED" end
  half = (half or "BOTTOM"):upper()
  if half ~= "TOP" then half = "BOTTOM" end
  return field .. "_" .. half
end

local function ensureRom(mod)
  if romData then return true end
  local path = RomImport.findRom(mod)
  if not path then return false end
  local data, err = RomImport.readFile(path)
  if not data then return false, err end
  romData = data
  return true
end

local function u8(data, off)
  return data:byte(off + 1)
end

local function rgb555(data, off)
  local lo, hi = u8(data, off), u8(data, off + 1)
  local v = lo + hi * 256
  local r = band(v, 31) * 255 / 31
  local g = band(rshift(v, 5), 31) * 255 / 31
  local b = band(rshift(v, 10), 31) * 255 / 31
  return r / 255, g / 255, b / 255, 1
end

local function decodeTile(data, off)
  local pix = {}
  for y = 0, 7 do
    local b0 = u8(data, off + y * 2)
    local b1 = u8(data, off + y * 2 + 1)
    local row = {}
    for x = 0, 7 do
      local bitn = 7 - x
      local lo = band(rshift(b0, bitn), 1)
      local hi = band(rshift(b1, bitn), 1)
      row[x + 1] = lo + hi * 2
    end
    pix[y + 1] = row
  end
  return pix
end

-- pret loads Stage*BottomBase* into vTilesSH ($8800) for $1000 bytes, which
-- fills $8800-$97FF. BG uses signed ($8800) addressing:
--   tile 0-127  -> $9000 + id*16  = gfx offset $800 + id*16
--   tile 128-255 -> $8800 + (id-128)*16 = gfx offset (id-128)*16
local function signedTileOffset(tid)
  if tid < 128 then
    return 0x800 + tid * 16
  end
  return (tid - 128) * 16
end

local function loadTiles(data, off)
  local tiles = {}
  for tid = 0, 255 do
    tiles[tid] = decodeTile(data, off + signedTileOffset(tid))
  end
  return tiles
end

-- Top field bank0 is assembled into vTilesSH: status($100)+gfx3($1a0)+base($d60).
local function topBank0RomOffset(info, vramOff)
  if vramOff < 0x100 then
    return info.status + vramOff
  end
  if vramOff < 0x2a0 then
    return info.gfx3 + (vramOff - 0x100)
  end
  return info.base + (vramOff - 0x2a0)
end

local function loadTopBank0Tiles(data, info)
  local tiles = {}
  for tid = 0, 255 do
    local voff = signedTileOffset(tid)
    tiles[tid] = decodeTile(data, topBank0RomOffset(info, voff))
  end
  return tiles
end

local function loadPals(data, off)
  local pals = {}
  for p = 0, 7 do
    local cols = {}
    for c = 0, 3 do
      local r, g, b = rgb555(data, off + p * 8 + c * 2)
      cols[c] = { r, g, b, 1 }
    end
    pals[p] = cols
  end
  return pals
end

function StageGfx.decodeBackground(data, key)
  local info = stages()[key]
  if not info then return nil end
  local t0, t1
  if info.kind == "top" then
    t0 = loadTopBank0Tiles(data, info)
    t1 = loadTiles(data, info.gfx1)
  else
    t0 = loadTiles(data, info.gfx0)
    t1 = loadTiles(data, info.gfx1)
  end
  local pals = loadPals(data, info.pal)
  local w, h = 160, 144
  local imageData = love.image.newImageData(w, h)
  for ty = 0, 17 do
    for tx = 0, 19 do
      local i = ty * 32 + tx
      local tid = u8(data, info.tilemap + i)
      local a = u8(data, info.attr + i)
      local pal = band(a, 7)
      local bank = band(rshift(a, 3), 1)
      local xflip = band(rshift(a, 5), 1) ~= 0
      local yflip = band(rshift(a, 6), 1) ~= 0
      local tile = (bank == 1) and t1[tid] or t0[tid]
      if tile then
        for py = 0, 7 do
          for px = 0, 7 do
            local sx = xflip and (7 - px) or px
            local sy = yflip and (7 - py) or py
            local ci = tile[sy + 1][sx + 1]
            local col = pals[pal][ci]
            imageData:setPixel(tx * 8 + px, ty * 8 + py, col[1], col[2], col[3], 1)
          end
        end
      end
    end
  end
  local img = love.graphics.newImage(imageData)
  img:setFilter("nearest", "nearest")
  return img
end

-- Reverse pret tools/gfx --interleave (width in tiles).
local function deinterleaveTiles(tiles, n, widthTiles)
  local linear = {}
  for i = 0, n - 1 do
    local tile = i * 2
    local row = math.floor(i / widthTiles)
    tile = tile - widthTiles * row
    if row % 2 ~= 0 then
      tile = tile - widthTiles + 1
    end
    linear[i] = tiles[tile]
  end
  return linear
end

local function signed8(v)
  if v >= 128 then return v - 256 end
  return v
end

local function loadObjPals(data, field)
  local info = stages()[stageKey(field, "BOTTOM")]
  return loadPals(data, info.pal + 0x40)
end

-- PinballPokeballGfx: w32.interleave.2bpp, 32 tiles → 8× 16x16 spin frames.
-- BallSpin0 uses OBJ tiles $40/$42 (8x16 pair) = linear sheet tiles 0,1 / 4,5.
function StageGfx.decodeBall(data)
  local off = Layout.BALL_GFX
  local pals = loadObjPals(data, "RED")
  local pal = pals[0]
  local raw = {}
  for i = 0, 31 do
    raw[i] = decodeTile(data, off + i * 16)
  end
  local tiles = deinterleaveTiles(raw, 32, 4)
  local idxs = { 0, 1, 4, 5 }
  local imageData = love.image.newImageData(16, 16)
  for qi = 0, 3 do
    local tx = qi % 2
    local ty = math.floor(qi / 2)
    local tile = tiles[idxs[qi + 1]]
    for py = 0, 7 do
      for px = 0, 7 do
        local ci = tile[py + 1][px + 1]
        local col = pal[ci]
        local a = (ci == 0) and 0 or 1
        imageData:setPixel(tx * 8 + px, ty * 8 + py, col[1], col[2], col[3], a)
      end
    end
  end
  local img = love.graphics.newImage(imageData)
  img:setFilter("nearest", "nearest")
  return img
end

-- FlipperGfx at vTilesOB $60; 8x16 OBJ mode. Sprite OAM from pret sprite_frames.asm.
-- Attrs: left = xflip + pal 2, right = pal 2.
local FLIPPER_OAM = {
  L_down = { { 0x0c, 0x03, 0x64 }, { 0x0a, 0x0b, 0x62 }, { 0x14, 0x13, 0x60 }, xflip = true },
  L_horiz = { { 0x0c, 0x03, 0x6a }, { 0x04, 0x0b, 0x68 }, { 0x0c, 0x13, 0x66 }, xflip = true },
  L_up = { { 0x0a, 0x03, 0x70 }, { 0x03, 0x0b, 0x6e }, { 0xfd, 0x13, 0x6c }, xflip = true },
  R_down = { { 0x0c, 0x05, 0x64 }, { 0x0a, 0xfd, 0x62 }, { 0x14, 0xf5, 0x60 }, xflip = false },
  R_horiz = { { 0x0c, 0x05, 0x6a }, { 0x04, 0xfd, 0x68 }, { 0x0c, 0xf5, 0x66 }, xflip = false },
  R_up = { { 0x0a, 0x05, 0x70 }, { 0x03, 0xfd, 0x6e }, { 0xfd, 0xf5, 0x6c }, xflip = false },
}

-- pret FlippersSpritePixelOffsetData ($7b38 / $7b68) are OAM coords;
-- convert to screen pixels (OAM x-8, OAM y-16).
StageGfx.FLIPPER_ANCHOR = {
  L = { x = 0x38 - 8, y = 0x7b - 16 }, -- 48, 107
  R = { x = 0x68 - 8, y = 0x7b - 16 }, -- 96, 107
}

function StageGfx.decodeFlipperPose(data, poseKey, stageKey)
  local parts = FLIPPER_OAM[poseKey]
  if not parts then return nil end
  local pals = loadObjPals(data, stageKey)
  local pal = pals[2]
  local flipOff = Layout.FLIPPER_GFX
  local xflip = parts.xflip
  local minx, miny, maxx, maxy = 999, 999, -999, -999
  for i = 1, 3 do
    local yoff, xoff = signed8(parts[i][1]), signed8(parts[i][2])
    if xoff < minx then minx = xoff end
    if yoff < miny then miny = yoff end
    if xoff + 8 > maxx then maxx = xoff + 8 end
    if yoff + 16 > maxy then maxy = yoff + 16 end
  end
  local w, h = maxx - minx, maxy - miny
  local imageData = love.image.newImageData(w, h)
  for i = 1, 3 do
    local yoff, xoff, tid = signed8(parts[i][1]), signed8(parts[i][2]), parts[i][3]
    local baseTid = tid - 0x60
    local x0, y0 = xoff - minx, yoff - miny
    for half = 0, 1 do
      local tile = decodeTile(data, flipOff + (baseTid + half) * 16)
      for py = 0, 7 do
        for px = 0, 7 do
          local sx = xflip and (7 - px) or px
          local ci = tile[py + 1][sx + 1]
          if ci ~= 0 then
            local col = pal[ci]
            imageData:setPixel(x0 + px, y0 + half * 8 + py, col[1], col[2], col[3], 1)
          end
        end
      end
    end
  end
  local img = love.graphics.newImage(imageData)
  img:setFilter("nearest", "nearest")
  return { image = img, ox = -minx, oy = -miny }
end

function StageGfx.decodeFlippers(data, stageKey)
  local out = {}
  for key in pairs(FLIPPER_OAM) do
    out[key] = StageGfx.decodeFlipperPose(data, key, stageKey)
  end
  return out
end

function StageGfx.background(mod, field, half)
  local key = "bg_" .. stageKey(field, half)
  if images[key] ~= nil then return images[key] or nil end
  if not ensureRom(mod) then
    images[key] = false
    return nil
  end
  local ok, img = pcall(StageGfx.decodeBackground, romData, stageKey(field, half))
  if not ok or not img then
    images[key] = false
    return nil
  end
  images[key] = img
  return img
end

function StageGfx.ball(mod)
  if images.ball ~= nil then return images.ball or nil end
  if not ensureRom(mod) then
    images.ball = false
    return nil
  end
  local ok, img = pcall(StageGfx.decodeBall, romData)
  if not ok or not img then
    images.ball = false
    return nil
  end
  images.ball = img
  return img
end

function StageGfx.flippers(mod, field)
  field = (field or "RED"):upper()
  if field ~= "BLUE" then field = "RED" end
  local key = "flip_" .. field
  if images[key] ~= nil then return images[key] or nil end
  if not ensureRom(mod) then
    images[key] = false
    return nil
  end
  local ok, set = pcall(StageGfx.decodeFlippers, romData, field)
  if not ok or not set then
    images[key] = false
    return nil
  end
  images[key] = set
  return set
end

function StageGfx.clear()
  images = {}
  romData = nil
end

return StageGfx
