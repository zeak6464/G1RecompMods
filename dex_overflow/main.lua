-- Species past the 255 ROM-index byte, without changing the engine.
--
-- Recomp still validates pokemon.index as 0..255.  This mod never sets
-- index.  Party, box, and the #DEX already key mons by string id, so the
-- extras load, battle, and list.  Script bytes / .sav / link cable still
-- cannot name them (those paths are one byte).
--
-- Copy a row in EXTRAS to add more.  Reuse a vanilla pic so this pack
-- ships no ROM art.  Gen 1 donors are Kanto species (back pics use the
-- trailing "b"); Gen 2 donors can be Johto.

local GameVersion = require("src.core.GameVersion")

return function(mod)
  local gen2 = GameVersion.generation() == 2

  local EXTRAS = {
    { id = "OVERFLOW_252", name = "OVERFLW", dex = 252,
      donor1 = "pidgey", donor2 = "cyndaquil" },
    { id = "OVERFLOW_253", name = "OVERFLX", dex = 253,
      donor1 = "geodude", donor2 = "totodile" },
    { id = "OVERFLOW_254", name = "OVERFLY", dex = 254,
      donor1 = "meowth", donor2 = "chikorita" },
    { id = "OVERFLOW_255", name = "OVERFLZ", dex = 255,
      donor1 = "psyduck", donor2 = "sentret" },
    { id = "OVERFLOW_256", name = "OVER256", dex = 256,
      donor1 = "growlithe", donor2 = "pidgey" },
    { id = "OVERFLOW_257", name = "OVER257", dex = 257,
      donor1 = "poliwag", donor2 = "geodude" },
    { id = "OVERFLOW_258", name = "OVER258", dex = 258,
      donor1 = "abra", donor2 = "mareep" },
    { id = "OVERFLOW_259", name = "OVER259", dex = 259,
      donor1 = "machop", donor2 = "hoothoot" },
    { id = "OVERFLOW_260", name = "OVER260", dex = 260,
      donor1 = "bellsprout", donor2 = "wooper" },
    { id = "OVERFLOW_261", name = "OVER261", dex = 261,
      donor1 = "tentacool", donor2 = "slugma" },
  }

  local ids = {}
  for _, spec in ipairs(EXTRAS) do
    ids[#ids + 1] = spec.id
    -- No `index`.  That field is the 255-wide ROM byte; leaving it off is
    -- the bypass.  Do not set 253 here either — that byte is EGG.
    local donor = gen2 and spec.donor2 or spec.donor1
    local front = "assets/generated/battle/front/" .. donor .. ".png"
    local back = gen2
      and ("assets/generated/battle/back/" .. donor .. ".png")
      or ("assets/generated/battle/back/" .. donor .. "b.png")
    if gen2 then
      mod.content.pokemon:register(spec.id, {
        id = spec.id,
        name = spec.name,
        dex = spec.dex,
        types = { "NORMAL" },
        baseStats = {
          hp = 50, attack = 50, defense = 50, speed = 50,
          specialAttack = 50, specialDefense = 50,
        },
        catchRate = 45,
        baseExp = 64,
        growthRate = "GROWTH_MEDIUM_FAST",
        levelMoves = {
          { level = 1, move = "TACKLE" },
          { level = 5, move = "GROWL" },
        },
        evolutions = {},
        picSize = 5,
        spriteFront = front,
        spriteBack = back,
      })
      mod.content.icons:register(spec.id, "ICON_MONSTER")
    else
      mod.content.pokemon:register(spec.id, {
        id = spec.id,
        name = spec.name,
        dex = spec.dex,
        types = { "NORMAL" },
        baseStats = {
          hp = 50, attack = 50, defense = 50, speed = 50, special = 50,
        },
        catchRate = 45,
        baseExp = 64,
        growthRate = "MEDIUM_FAST",
        level1Moves = { "TACKLE" },
        learnset = {
          { level = 5, move = "GROWL" },
        },
        evolutions = {},
        frontSize = 5,
        spriteFront = front,
        spriteBack = back,
        dexEntry = {
          kind = "NORMAL",
          heightFt = 1,
          heightIn = 8,
          weight = 100,
          text = spec.name .. " was added past the 255 species byte.",
        },
      })
      mod.content.icons:register(spec.id, "QUADRUPED")
    end
  end

  mod.content.constants:patch("dexSize", 261)
  mod.content.constants:patch("dexDigits", 3)
  if gen2 then
    -- Append, do not replace: a bare list wipes the vanilla 251 names.
    mod.content.constants:patch("speciesOrder", { __append = ids })
  end

  if not gen2 then return end

  mod.events:on("mods.loaded", function(ev)
    local data = ev and ev.data
    if type(data) ~= "table" then return end

    local dex = data.gen2Pokedex or data.pokedex
    if type(dex) ~= "table" then
      dex = { entries = {} }
      data.gen2Pokedex = dex
      data.pokedex = dex
    end
    dex.entries = dex.entries or {}
    dex.newOrder = dex.newOrder or {}
    dex.alphabeticalOrder = dex.alphabeticalOrder or {}

    local inNew, inAZ = {}, {}
    for _, id in ipairs(dex.newOrder) do inNew[id] = true end
    for _, id in ipairs(dex.alphabeticalOrder) do inAZ[id] = true end

    for _, spec in ipairs(EXTRAS) do
      dex.entries[spec.id] = {
        id = spec.id,
        dex = spec.dex,
        kind = "NORMAL",
        height = 5,
        weight = 100,
        text = spec.name .. " was added past the 255 species byte.",
      }
      if not inNew[spec.id] then
        dex.newOrder[#dex.newOrder + 1] = spec.id
        inNew[spec.id] = true
      end
      if not inAZ[spec.id] then
        dex.alphabeticalOrder[#dex.alphabeticalOrder + 1] = spec.id
        inAZ[spec.id] = true
      end
    end
    table.sort(dex.alphabeticalOrder)
  end)
end
