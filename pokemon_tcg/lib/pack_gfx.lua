-- Decode pret booster-pack face art via compressed tilemap + *1Gfx tiles.
local V = ...
local Cache = V.require("cache")
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local PackGfx = {}

PackGfx.TILES_W = 8
PackGfx.TILES_H = 12
PackGfx.WIDTH = PackGfx.TILES_W * 8  -- 64
PackGfx.HEIGHT = PackGfx.TILES_H * 8 -- 96
PackGfx.VRAM_BASE = 0x80

-- bank:offset from poketcg.sym
local SETS = {
  COLOSSEUM = {
    gfxBank = 0x24, gfxOffset = 0x5876,
    mapBank = 0x21, mapOffset = 0x6647, -- ColosseumTilemap (DMG)
    palBank = 0x2D, palOffset = 0x7FC3,
  },
  EVOLUTION = {
    gfxBank = 0x24, gfxOffset = 0x63DA,
    mapBank = 0x21, mapOffset = 0x673E,
    palBank = 0x2E, palOffset = 0x4042,
  },
  MYSTERY = {
    gfxBank = 0x24, gfxOffset = 0x6F3E,
    mapBank = 0x21, mapOffset = 0x6833,
    palBank = 0x2E, palOffset = 0x407C,
  },
  LABORATORY = {
    gfxBank = 0x25, gfxOffset = 0x4000,
    mapBank = 0x21, mapOffset = 0x6925,
    palBank = 0x2E, palOffset = 0x40B6,
  },
}

local images = {}
local romData = nil

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

function PackGfx.clear()
  images = {}
  romData = nil
end

local function rgb555(word)
  local r = band(word, 0x1F) / 31
  local g = band(rshift(word, 5), 0x1F) / 31
  local b = band(rshift(word, 10), 0x1F) / 31
  return r, g, b
end

-- pret InitDataDecompression + DecompressData (src/home/decompress.asm)
local function decompress(rom, srcOff, length)
  local pos = srcOff
  local numCmdBits = 1
  local cmdByte = 0
  local carry = 0
  local repeatToggle = false
  local repeatLengths = 0
  local numToRepeat = 0
  local secondary = {}
  for i = 0, 255 do secondary[i] = 0 end
  local secLow = 0xEF -- LOW(wDecompressionSecondaryBufferStart)
  local repeatOff = 0
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

-- ColosseumBoosterPal:: db 0 / db 7 / then rgb quads. Use first BGP.
local function loadPalette(rom, bank, offset)
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
  return tiles
end

local function decodeImage(rom, set)
  local info = SETS[set]
  if not info then return nil end

  local mapOff = bankFileOffset(info.mapBank, info.mapOffset)
  local tw, th = u8(rom, mapOff), u8(rom, mapOff + 1)
  if tw ~= PackGfx.TILES_W or th ~= PackGfx.TILES_H then return nil end
  -- header: w, h, dw NULL, db cgb → compressed payload at +5
  local tmap = decompress(rom, mapOff + 5, tw * th)
  local tiles = loadTiles(rom, info.gfxBank, info.gfxOffset)
  local pal = loadPalette(rom, info.palBank, info.palOffset)

  local w, h = PackGfx.WIDTH, PackGfx.HEIGHT
  local imageData = love.image.newImageData(w, h)
  for row = 0, th - 1 do
    for col = 0, tw - 1 do
      local tid = tmap[row * tw + col + 1]
      local tileIndex = tid - PackGfx.VRAM_BASE
      local tile = tiles[tileIndex]
      if tile then
        for y = 0, 7 do
          local lo = tile[y * 2]
          local hi = tile[y * 2 + 1]
          for x = 0, 7 do
            local bitn = 7 - x
            local shade = band(rshift(hi, bitn), 1) * 2 + band(rshift(lo, bitn), 1)
            local c = pal[shade + 1] or { 0, 0, 0, 1 }
            imageData:setPixel(col * 8 + x, row * 8 + y, c[1], c[2], c[3], 1)
          end
        end
      end
    end
  end
  local img = love.graphics.newImage(imageData)
  img:setFilter("nearest", "nearest")
  return img
end

function PackGfx.forget(setName)
  images[(setName or ""):upper()] = nil
end

function PackGfx.imageFromBytes(bytes)
  if type(bytes) ~= "string" or bytes == "" then return nil end
  if not (love and love.graphics and love.image) then return nil end
  local fs = love.filesystem
  local okFs, SaveData = pcall(require, "src.core.SaveData")
  if okFs and SaveData and SaveData.persistenceFs then
    local real = SaveData.persistenceFs()
    if real and real.newFileData then fs = real end
  end
  if not (fs and fs.newFileData) then return nil end
  local okFd, fd = pcall(fs.newFileData, bytes, "pack.png")
  if not okFd or not fd then return nil end
  local okImg, data = pcall(love.image.newImageData, fd)
  if not okImg or not data then return nil end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

local function loadCustomPack(setName)
  local ok, Custom = pcall(function() return V.require("custom") end)
  if not ok or not Custom then return nil end
  return PackGfx.imageFromBytes(Custom.installedPackPic(setName))
end

function PackGfx.drawBytes(bytes, x, y, scale)
  scale = math.floor((scale or 1) + 0.5)
  if scale < 1 then scale = 1 end
  x, y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
  local img = PackGfx.imageFromBytes(bytes)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y, 0, scale, scale)
  local P = require("src.render.PaletteFX")
  if P.markTrueColor then
    P.markTrueColor(x, y, PackGfx.WIDTH * scale, PackGfx.HEIGHT * scale)
  end
  return true
end

function PackGfx.image(setName)
  setName = (setName or "COLOSSEUM"):upper()
  if setName == "PREMIUM" then setName = "MYSTERY" end
  if images[setName] ~= nil then
    return images[setName] or nil
  end
  local custom = loadCustomPack(setName)
  if custom then
    images[setName] = custom
    return custom
  end
  -- ENERGY / PROMOTIONAL have no dedicated pack face art in the ROM.
  if not SETS[setName] then return nil end
  if not ensureRom() then return nil end
  local ok, img = pcall(decodeImage, romData, setName)
  if not ok then
    images[setName] = false
    return nil
  end
  images[setName] = img or false
  return img
end

function PackGfx.draw(setName, x, y, scale)
  scale = math.floor((scale or 1) + 0.5)
  if scale < 1 then scale = 1 end
  x, y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
  local img = PackGfx.image(setName)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y, 0, scale, scale)
  local P = require("src.render.PaletteFX")
  if P.markTrueColor then
    P.markTrueColor(x, y, PackGfx.WIDTH * scale, PackGfx.HEIGHT * scale)
  end
  return true
end

return PackGfx
