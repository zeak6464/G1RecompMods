-- In-memory + filesystem cache for the imported TCG catalog.
local V = ...
local RomImport = V.require("rom_import")

local Cache = {
  catalog = nil,
}

local function cacheDir()
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    return "pokemon_tcg_cache"
  end
  return nil
end

function Cache.isReady()
  return Cache.catalog ~= nil and Cache.catalog.byId ~= nil
end

function Cache.get()
  return Cache.catalog
end

function Cache.card(id)
  local c = Cache.catalog
  if not c or not c.byId then return nil end
  return c.byId[id] or c.byId[tonumber(id)]
end


function Cache.allCards()
  local c = Cache.catalog
  return c and c.cards or {}
end

function Cache.ensure(mod)
  if Cache.isReady() then return true, Cache.catalog end
  local catalog, err = RomImport.import(mod)
  if not catalog then return false, err end
  Cache.catalog = catalog
  if mod and mod.save then
    mod.save:set("rom_path", catalog.path)
    mod.save:set("rom_sha1", catalog.sha1)
  end
  -- Persist a lightweight JSON-less summary for debugging (card count only).
  local dir = cacheDir()
  if dir and love and love.filesystem then
    love.filesystem.createDirectory(dir)
    love.filesystem.write(dir .. "/meta.txt",
      ("sha1=%s\npath=%s\ncards=%d\n"):format(
        catalog.sha1, catalog.path, #catalog.cards))
  end
  return true, catalog
end

function Cache.clear()
  Cache.catalog = nil
  local ok, CardGfx = pcall(function() return V.require("card_gfx") end)
  if ok and CardGfx and CardGfx.clear then CardGfx.clear() end
  local ok2, PackGfx = pcall(function() return V.require("pack_gfx") end)
  if ok2 and PackGfx and PackGfx.clear then PackGfx.clear() end
  local ok3, MapGfx = pcall(function() return V.require("map_gfx") end)
  if ok3 and MapGfx and MapGfx.clear then MapGfx.clear() end
end


return Cache

