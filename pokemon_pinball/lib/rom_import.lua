-- Verify Pokémon Pinball (U) ROM and load wild tables from fixed offsets.
local V = ...
local Layout = V.require("data.import_layout")
local WildTables = V.require("data.wild_tables")
local Maps = V.require("data.maps")

local RomImport = {}
RomImport.EXPECTED_SHA1 = Layout.SHA1

function RomImport.sha1(data)
  if love and love.data and love.data.hash then
    local digest = love.data.hash("sha1", data)
    local hex = {}
    for i = 1, #digest do
      hex[#hex + 1] = string.format("%02x", digest:byte(i))
    end
    return table.concat(hex)
  end
  -- Fallback: shell out is unavailable in-game; require love.data.hash.
  error("love.data.hash required to verify Pinball ROM SHA1")
end

local function existsReadable(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  if love and love.filesystem and love.filesystem.getInfo then
    if love.filesystem.getInfo(path) then return true end
  end
  return false
end

function RomImport.findRom(mod)
  local opt = mod and mod.options and mod.options.get and mod.options:get("rom_path")
  local modRom = mod and mod.path and (mod.path .. "/roms/PokemonPinball.gbc") or nil
  local candidates = {
    -- Prefer ROM bundled next to the mod (mods/pokemon_pinball/roms/...).
    modRom,
    mod and mod.path and (mod.path .. "/roms/pokepinball.gbc") or nil,
    -- Absolute / project-relative option, then join under mod.path if relative.
    opt,
    opt and mod and mod.path and (mod.path .. "/" .. opt) or nil,
    "roms/PokemonPinball.gbc",
    "roms/pokepinball.gbc",
  }
  for _, p in ipairs(candidates) do
    if existsReadable(p) then return p end
  end
  return nil
end

function RomImport.readFile(path)
  local f = io.open(path, "rb")
  if f then
    local data = f:read("*a")
    f:close()
    return data
  end
  if love and love.filesystem and love.filesystem.read then
    local data = love.filesystem.read(path)
    if data then return data end
  end
  return nil, "Cannot read " .. tostring(path)
end

local function u8(data, off)
  return data:byte(off + 1)
end

local function readSlots(data, off)
  local t = {}
  for i = 0, Layout.WILD_SLOT_COUNT - 1 do
    t[#t + 1] = u8(data, off + i)
  end
  return t
end

-- Prefer embedded pret tables; optionally overlay from ROM when present.
function RomImport.decodeWildFromRom(data)
  local red = {}
  local order = {
    "PALLET_TOWN", "VIRIDIAN_FOREST", "PEWTER_CITY", "CERULEAN_CITY",
    "VERMILION_SEASIDE", "ROCK_MOUNTAIN", "LAVENDER_TOWN", "CYCLING_ROAD",
    "SAFARI_ZONE", "SEAFOAM_ISLANDS", "CINNABAR_ISLAND", "INDIGO_PLATEAU",
  }
  local off = Layout.RED_STAGE_WILD_MONS
  for _, key in ipairs(order) do
    red[key] = {
      common = readSlots(data, off),
      rare = readSlots(data, off + Layout.WILD_SLOT_COUNT),
    }
    off = off + Layout.WILD_SLOT_COUNT * 2
  end
  return red
end

function RomImport.import(mod, path)
  path = path or RomImport.findRom(mod)
  if not path then
    return nil, "Pinball ROM not found (mods/pokemon_pinball/roms/PokemonPinball.gbc)"
  end
  local data, err = RomImport.readFile(path)
  if not data then return nil, err end
  local hash = RomImport.sha1(data)
  if hash ~= RomImport.EXPECTED_SHA1 then
    return nil, ("ROM SHA1 mismatch (got %s, want %s)"):format(hash, RomImport.EXPECTED_SHA1)
  end
  local redRom = RomImport.decodeWildFromRom(data)
  local wild = {
    RED = redRom,
    BLUE = WildTables.BLUE, -- blue block layout varies; use pret tables
  }
  return {
    sha1 = hash,
    path = path,
    wild = wild,
    maps = Maps,
    importedAt = os.time(),
  }
end

return RomImport
