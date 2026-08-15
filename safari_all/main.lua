-- Safari Zone All: any wild roll inside the Safari Zone (Gen 1) or
-- National Park (Gold) becomes a random species from the merged pokemon
-- registry. Levels stay on the vanilla roll.

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

  local function rebuildPool()
    local rows = {}
    for id, def in mod.content.pokemon:each() do
      if type(id) == "string" and def then
        rows[#rows + 1] = id
      end
    end
    table.sort(rows)
    pool = rows
    return pool
  end

  local function speciesPool()
    if pool and #pool > 0 then return pool end
    return rebuildPool()
  end

  local function pickSpecies(rng)
    local rows = speciesPool()
    if #rows == 0 then return nil end
    local r = rng or ((love and love.math and love.math.random) or math.random)
    return rows[r(1, #rows)]
  end

  local function inSafari(mapId, ctx)
    if mapId and SAFARI[mapId] then return true end
    return ctx and ctx.kind == "contest"
  end

  -- Content can settle after other mods load; rebuild once the game is live.
  mod.events:on("game.ready", function()
    rebuildPool()
    mod.log:info("Safari pool: %d species", #pool)
  end)

  -- Grass + surfing water both go through encounter.species after a roll.
  -- Gold adds ctx.kind / daytime; the mapId test is enough for both games.
  mod.hooks:wrap("encounter.species", function(next, enc, ctx)
    enc = next(enc, ctx)
    if not enc or not ctx or not inSafari(ctx.mapId, ctx) then
      return enc
    end
    local species = pickSpecies(ctx.rng)
    if not species then return enc end
    return { species = species, level = enc.level }
  end)

  -- Fishing keeps bite odds, but any hooked mon becomes a random species.
  mod.hooks:wrap("encounter.fishing", function(next, rod, mapId, candidates, ctx)
    local enc = next(rod, mapId, candidates, ctx)
    if not enc or not inSafari(mapId, ctx) then
      return enc
    end
    local species = pickSpecies()
    if not species then return enc end
    return { species = species, level = enc.level }
  end)
end
