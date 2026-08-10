local V = ...
local RomImport = V.require("rom_import")

local Cache = { catalog = nil }

function Cache.isReady()
  return Cache.catalog ~= nil and Cache.catalog.wild ~= nil
end

function Cache.get()
  return Cache.catalog
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
  return true, catalog
end

function Cache.clear()
  Cache.catalog = nil
  local ok, StageGfx = pcall(function() return V.require("stage_gfx") end)
  if ok and StageGfx and StageGfx.clear then StageGfx.clear() end
end

return Cache
