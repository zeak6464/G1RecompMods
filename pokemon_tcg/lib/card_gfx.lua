-- Decode pret/poketcg card pictures (64x48 2bpp + 4-color GBC palette).
-- gfx field = (offset from CardGraphics) / 8  (see pret `gfx` macro).
local V = ...
local Layout = V.require("data.import_layout")
local Cache = V.require("cache")
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local CardGfx = {}

CardGfx.WIDTH = 64
CardGfx.HEIGHT = 48
CardGfx.BPP_BYTES = 64 * 48 * 2 / 8 -- 768
CardGfx.PAL_BYTES = 8
CardGfx.ENTRY_BYTES = CardGfx.BPP_BYTES + CardGfx.PAL_BYTES -- 776

local images = {} -- cardId -> Image
local romData = nil

local function bankFileOffset(bank, offsetInBank)
  if bank == 0 then return offsetInBank end
  return bank * 0x4000 + (offsetInBank - 0x4000)
end

local function cardGraphicsBase()
  return bankFileOffset(Layout.CARD_GRAPHICS_BANK, Layout.CARD_GRAPHICS_OFFSET)
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

function CardGfx.clear()
  images = {}
  romData = nil
end

-- RGB555 LE word → 0..1 floats
local function rgb555(word)
  local r = band(word, 0x1F) / 31
  local g = band(rshift(word, 5), 0x1F) / 31
  local b = band(rshift(word, 10), 0x1F) / 31
  return r, g, b
end

function CardGfx.palette(raw, off)
  off = off or 0
  local colors = {}
  for i = 0, 3 do
    local lo = raw:byte(off + i * 2 + 1)
    local hi = raw:byte(off + i * 2 + 2)
    local word = bor(lo, lshift(hi, 8))
    local r, g, b = rgb555(word)
    colors[i + 1] = { r, g, b, 1 }
  end
  return colors
end

-- Cards use rgbgfx -Z (column tile order).
function CardGfx.decodePixels(bpp, pal)
  local colors = CardGfx.palette(pal)
  local w, h = CardGfx.WIDTH, CardGfx.HEIGHT
  local tilesW, tilesH = w / 8, h / 8
  local pixels = {}

  for col = 0, tilesW - 1 do
    for row = 0, tilesH - 1 do
      local tile = col * tilesH + row
      local base = tile * 16
      local tileX, tileY = col * 8, row * 8
      for y = 0, 7 do
        local low = bpp:byte(base + y * 2 + 1)
        local high = bpp:byte(base + y * 2 + 2)
        for x = 0, 7 do
          local bitn = 7 - x
          local shade = band(rshift(high, bitn), 1) * 2
            + band(rshift(low, bitn), 1)
          local c = colors[shade + 1] or { 0, 0, 0, 1 }
          pixels[(tileY + y) * w + (tileX + x) + 1] = c
        end
      end
    end
  end
  return pixels, w, h
end

function CardGfx.slice(rom, gfxIndex)
  if type(gfxIndex) ~= "number" then return nil end
  local off = cardGraphicsBase() + gfxIndex * 8
  if off + CardGfx.ENTRY_BYTES > #rom then return nil end
  local bpp = rom:sub(off + 1, off + CardGfx.BPP_BYTES)
  local pal = rom:sub(off + CardGfx.BPP_BYTES + 1, off + CardGfx.ENTRY_BYTES)
  return bpp, pal
end

function CardGfx.toImageData(bpp, pal)
  if not (love and love.image and love.image.newImageData) then
    return nil
  end
  local pixels, w, h = CardGfx.decodePixels(bpp, pal)
  local img = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local c = pixels[y * w + x + 1]
      img:setPixel(x, y, c[1], c[2], c[3], c[4] or 1)
    end
  end
  return img
end

function CardGfx.image(cardId)
  cardId = tonumber(cardId) or cardId
  if images[cardId] then return images[cardId] end
  if not (love and love.graphics) then return nil end
  if not ensureRom() then return nil end
  local card = Cache.card(cardId)
  if not card or not card.gfx then return nil end
  local bpp, pal = CardGfx.slice(romData, card.gfx)
  if not bpp then return nil end
  local data = CardGfx.toImageData(bpp, pal)
  if not data then return nil end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  images[cardId] = img
  return img
end

-- Keep scales that land on whole canvas pixels (1, 2, 0.5, …). Round others.
local function pixelScale(scale)
  scale = scale or 1
  local w = CardGfx.WIDTH * scale
  local h = CardGfx.HEIGHT * scale
  if math.abs(w - math.floor(w + 0.5)) < 1e-6
      and math.abs(h - math.floor(h + 0.5)) < 1e-6
      and w >= 1 and h >= 1 then
    return scale
  end
  scale = math.floor(scale + 0.5)
  if scale < 1 then scale = 1 end
  return scale
end

function CardGfx.draw(cardId, x, y, scale)
  scale = pixelScale(scale)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  local img = CardGfx.image(cardId)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y, 0, scale, scale)
  -- Keep ROM RGB555 palettes out of Gen1 SGB shade remap.
  local P = require("src.render.PaletteFX")
  if P.markTrueColor then
    P.markTrueColor(x, y, CardGfx.WIDTH * scale, CardGfx.HEIGHT * scale)
  end
  return true
end


CardGfx.TYPE_RGB = {
  FIRE = { 0.90, 0.25, 0.15 },
  GRASS = { 0.20, 0.70, 0.25 },
  LIGHTNING = { 0.95, 0.85, 0.15 },
  WATER = { 0.20, 0.40, 0.90 },
  FIGHTING = { 0.65, 0.40, 0.20 },
  PSYCHIC = { 0.70, 0.30, 0.75 },
  COLORLESS = { 0.75, 0.75, 0.70 },
  TRAINER = { 0.25, 0.45, 0.85 },
  ENERGY = { 0.30, 0.65, 0.40 },
}

function CardGfx.typeColor(card)
  if not card then return 0.5, 0.5, 0.5 end
  if card.kind == "trainer" then
    local c = CardGfx.TYPE_RGB.TRAINER
    return c[1], c[2], c[3]
  end
  if card.kind == "energy" then
    local key = card.energyType or "ENERGY"
    local c = CardGfx.TYPE_RGB[key] or CardGfx.TYPE_RGB.ENERGY
    return c[1], c[2], c[3]
  end
  local c = CardGfx.TYPE_RGB[card.type] or CardGfx.TYPE_RGB.COLORLESS
  return c[1], c[2], c[3]
end

function CardGfx.drawFrame(cardId, x, y, scale)
  scale = pixelScale(scale)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  local card = Cache.card(cardId)
  local w, h = CardGfx.WIDTH * scale, CardGfx.HEIGHT * scale
  local r, g, b = CardGfx.typeColor(card)
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
  love.graphics.setColor(0.95, 0.92, 0.82, 1)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
  local ok = CardGfx.draw(cardId, x, y, scale)
  love.graphics.setColor(1, 1, 1, 1)
  return ok
end

-- Thin black portrait frame used on the GBC duel board.
function CardGfx.drawPortrait(cardId, x, y, scale)
  scale = pixelScale(scale)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  local w, h = CardGfx.WIDTH * scale, CardGfx.HEIGHT * scale
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  local ok = CardGfx.draw(cardId, x, y, scale)
  love.graphics.setColor(1, 1, 1, 1)
  return ok
end

return CardGfx

