-- Safari Zone All: any wild roll inside the Safari Zone (Gen 1) or
-- National Park (Gold) becomes a random species from the merged pokemon
-- registry (vanilla + every loaded mod). Levels stay on the vanilla roll.

local SAFARI = {
  SAFARI_ZONE_CENTER = true,
  SAFARI_ZONE_EAST = true,
  SAFARI_ZONE_NORTH = true,
  SAFARI_ZONE_WEST = true,
  NATIONAL_PARK = true,
  NATIONAL_PARK_BUG_CONTEST = true,
}

return function(mod)
  local pool

  local function isSpecies(id, def)
    if type(id) ~= "string" or type(def) ~= "table" then return false end
    if id == "EGG" or id == "UNUSED" then return false end
    return type(def.baseStats) == "table"
  end

  -- game.data.pokemon is the live merge (ROM + every mod). This mod's
  -- content.pokemon overlay does not include those other sources.
  local function livePokemon(src)
    if type(src) == "table" and type(src.pokemon) == "table" then
      return src.pokemon
    end
    local game = (src and src.game) or mod.game
    local data = game and game.data
    if type(data) == "table" and type(data.pokemon) == "table" then
      return data.pokemon
    end
    return nil
  end

  local function rebuildPool(src)
    local rows = {}
    local poke = livePokemon(src)
    if poke then
      for id, def in pairs(poke) do
        if isSpecies(id, def) then
          rows[#rows + 1] = id
        end
      end
    else
      for id, def in mod.content.pokemon:each() do
        if isSpecies(id, def) then
          rows[#rows + 1] = id
        end
      end
    end
    table.sort(rows)
    pool = rows
    return pool
  end

  local function speciesPool(src)
    if livePokemon(src) then return rebuildPool(src) end
    if pool and #pool > 0 then return pool end
    return rebuildPool(src)
  end

  local function pickSpecies(rng, src)
    local rows = speciesPool(src)
    if #rows == 0 then return nil end
    local r = rng or ((love and love.math and love.math.random) or math.random)
    return rows[r(1, #rows)]
  end

  local function inSafari(mapId, ctx)
    if mapId and SAFARI[mapId] then return true end
    return ctx and ctx.kind == "contest"
  end

  mod.events:on("mods.loaded", function(ev)
    rebuildPool(ev and ev.data)
  end)

  mod.events:on("game.ready", function(ev)
    rebuildPool((ev and ev.game and ev.game.data) or (mod.game and mod.game.data))
    mod.log:info("Safari pool: %d species", #pool)
  end)

  -- Grass + surfing water both go through encounter.species after a roll.
  -- Gold adds ctx.kind / daytime; the mapId test is enough for both games.
  mod.hooks:wrap("encounter.species", function(next, enc, ctx)
    enc = next(enc, ctx)
    if not enc or not ctx or not inSafari(ctx.mapId, ctx) then
      return enc
    end
    local species = pickSpecies(ctx.rng, ctx)
    if not species then return enc end
    return { species = species, level = enc.level }
  end)

  -- Fishing keeps bite odds, but any hooked mon becomes a random species.
  mod.hooks:wrap("encounter.fishing", function(next, rod, mapId, candidates, ctx)
    local enc = next(rod, mapId, candidates, ctx)
    if not enc or not inSafari(mapId, ctx) then
      return enc
    end
    local species = pickSpecies(ctx and ctx.rng, ctx)
    if not species then return enc end
    return { species = species, level = enc.level }
  end)
end
