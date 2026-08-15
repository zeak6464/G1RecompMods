-- Delta Type Pokémon — rare wilds anywhere, type-colored, extra type moves
-- added to the species' normal level-up pool (not a full moveset replace).
--
-- Other mods register a type (any load order — from entry if you load after
-- this mod, otherwise from game.ready):
--   local delta = mod.find("delta_type")
--   if delta then
--     delta.exports.registerType("STEEL", {
--       moves = { "METAL_CLAW", "STEEL_WING", "IRON_TAIL", "SLASH" },
--       shades = { {232,232,240}, {168,168,184}, {88,88,112}, {24,24,40} },
--       -- or learnset = { {level=1, move="METAL_CLAW"}, ... }
--     })
--   end

local GameVersion = require("src.core.GameVersion")

local BUILTIN_TYPES = {
  "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG",
  "GHOST", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE",
  "DRAGON",
}

local DEFAULT_LEVELS = { 1, 15, 30, 50 }

-- Four shades, lightest → darkest (same contract as AssetTransform.recolor).
local TYPE_SHADES = {
  NORMAL       = { { 248, 248, 248 }, { 200, 200, 184 }, { 120, 120, 104 }, { 40, 40, 32 } },
  FIGHTING     = { { 248, 216, 200 }, { 216, 96, 64 }, { 144, 40, 32 }, { 48, 8, 8 } },
  FLYING       = { { 232, 240, 248 }, { 160, 192, 232 }, { 72, 112, 176 }, { 16, 32, 64 } },
  POISON       = { { 240, 216, 248 }, { 176, 96, 200 }, { 96, 32, 128 }, { 32, 0, 48 } },
  GROUND       = { { 248, 232, 184 }, { 200, 152, 72 }, { 128, 80, 24 }, { 48, 24, 8 } },
  ROCK         = { { 232, 224, 200 }, { 168, 152, 112 }, { 96, 80, 48 }, { 32, 24, 16 } },
  BUG          = { { 232, 248, 184 }, { 152, 200, 64 }, { 72, 120, 24 }, { 24, 40, 8 } },
  GHOST        = { { 216, 200, 232 }, { 120, 88, 160 }, { 64, 32, 96 }, { 16, 0, 32 } },
  FIRE         = { { 248, 232, 184 }, { 248, 128, 40 }, { 184, 40, 16 }, { 48, 8, 0 } },
  WATER        = { { 216, 240, 248 }, { 64, 160, 232 }, { 24, 72, 176 }, { 0, 16, 48 } },
  GRASS        = { { 216, 248, 200 }, { 88, 192, 72 }, { 24, 112, 32 }, { 0, 32, 8 } },
  ELECTRIC     = { { 248, 248, 200 }, { 248, 216, 32 }, { 184, 136, 0 }, { 56, 40, 0 } },
  PSYCHIC_TYPE = { { 248, 216, 232 }, { 232, 96, 160 }, { 152, 32, 96 }, { 48, 0, 32 } },
  ICE          = { { 232, 248, 248 }, { 144, 216, 232 }, { 56, 144, 184 }, { 8, 40, 64 } },
  DRAGON       = { { 216, 200, 248 }, { 112, 80, 200 }, { 64, 32, 144 }, { 16, 0, 48 } },
  STEEL        = { { 232, 232, 240 }, { 168, 168, 184 }, { 88, 88, 112 }, { 24, 24, 40 } },
  DARK         = { { 184, 168, 160 }, { 96, 80, 80 }, { 48, 32, 40 }, { 16, 8, 16 } },
}

local TYPE_MOVES = {
  NORMAL       = { "TACKLE", "BODY_SLAM", "QUICK_ATTACK", "HYPER_BEAM" },
  FIGHTING     = { "KARATE_CHOP", "LOW_KICK", "SUBMISSION", "SEISMIC_TOSS" },
  FLYING       = { "GUST", "WING_ATTACK", "DRILL_PECK", "SKY_ATTACK" },
  POISON       = { "POISON_STING", "ACID", "SLUDGE", "TOXIC" },
  GROUND       = { "BONE_CLUB", "DIG", "EARTHQUAKE", "FISSURE" },
  ROCK         = { "ROCK_THROW", "ROCK_SLIDE", "HARDEN", "SELFDESTRUCT" },
  BUG          = { "PIN_MISSILE", "TWINEEDLE", "LEECH_LIFE", "STRING_SHOT" },
  GHOST        = { "LICK", "NIGHT_SHADE", "CONFUSE_RAY", "HYPNOSIS" },
  FIRE         = { "EMBER", "FLAMETHROWER", "FIRE_SPIN", "FIRE_BLAST" },
  WATER        = { "WATER_GUN", "BUBBLEBEAM", "CLAMP", "HYDRO_PUMP" },
  GRASS        = { "ABSORB", "MEGA_DRAIN", "RAZOR_LEAF", "SOLARBEAM" },
  ELECTRIC     = { "THUNDERSHOCK", "THUNDER_WAVE", "THUNDERBOLT", "THUNDER" },
  PSYCHIC_TYPE = { "CONFUSION", "PSYBEAM", "PSYCHIC", "HYPNOSIS" },
  ICE          = { "ICE_BEAM", "AURORA_BEAM", "BLIZZARD", "MIST" },
  DRAGON       = { "DRAGON_RAGE", "LEER", "WRAP", "HYPER_BEAM" },
  STEEL        = { "METAL_CLAW", "STEEL_WING", "IRON_TAIL", "SLASH" },
  DARK         = { "BITE", "FAINT_ATTACK", "PURSUIT", "CRUNCH" },
}

local function rand(lo, hi)
  local r = (love and love.math and love.math.random) or math.random
  return r(lo, hi)
end

local function deltaOf(mon)
  return mon and mon.extra and mon.extra.delta
end

local function shadeIndex(r)
  if r > 0.83 then return 1 end
  if r > 0.5 then return 2 end
  if r > 0.17 then return 3 end
  return 4
end

local function recolor(imageData, shades)
  local out = love.image.newImageData(imageData:getDimensions())
  out:paste(imageData, 0, 0, 0, 0, imageData:getDimensions())
  out:mapPixel(function(_, _, r, g, b, a)
    if a == 0 then return r, g, b, a end
    local c = shades[shadeIndex(r)]
    return c[1] / 255, c[2] / 255, c[3] / 255, a
  end)
  return out
end

local function copyShades(src)
  if type(src) ~= "table" then return nil end
  local out = {}
  for i = 1, 4 do
    local row = src[i]
    if type(row) ~= "table" then return nil end
    out[i] = { row[1] or 0, row[2] or 0, row[3] or 0 }
  end
  return out
end

local function assignLevels(moveIds, levels)
  local out = {}
  levels = levels or DEFAULT_LEVELS
  for i, id in ipairs(moveIds or {}) do
    if type(id) == "string" and id ~= "" then
      out[#out + 1] = { level = levels[i] or (i * 15), move = id }
    end
  end
  return out
end

local function parseLearnset(spec)
  spec = spec or {}
  if type(spec.learnset) == "table" and spec.learnset[1] then
    if type(spec.learnset[1]) == "table" and spec.learnset[1].move then
      local out = {}
      for _, e in ipairs(spec.learnset) do
        if e.move then
          out[#out + 1] = {
            level = math.max(1, math.floor(tonumber(e.level) or 1)),
            move = e.move,
          }
        end
      end
      return out
    end
    return assignLevels(spec.learnset, spec.levels)
  end
  if type(spec.moves) == "table" then
    return assignLevels(spec.moves, spec.levels)
  end
  return {}
end

return function(mod)
  local registry = {}
  local typePool = {}

  local function learnsetFor(typeId)
    local row = registry[typeId]
    return row and row.learnset or {}
  end

  local function shadesFor(typeId)
    local row = registry[typeId]
    return row and row.shades or TYPE_SHADES[typeId]
  end

  local function registerType(typeId, spec)
    if type(typeId) ~= "string" or typeId == "" then return false end
    typeId = typeId:upper()
    if typeId == "PSYCHIC" then typeId = "PSYCHIC_TYPE" end
    spec = spec or {}
    local learnset = parseLearnset(spec)
    if #learnset == 0 and TYPE_MOVES[typeId] then
      learnset = assignLevels(TYPE_MOVES[typeId], spec.levels)
    end
    table.sort(learnset, function(a, b)
      return (a.level or 1) < (b.level or 1)
    end)
    registry[typeId] = {
      learnset = learnset,
      shades = copyShades(spec.shades) or copyShades(TYPE_SHADES[typeId])
        or copyShades(TYPE_SHADES.STEEL),
    }
    local found = false
    for _, t in ipairs(typePool) do
      if t == typeId then found = true break end
    end
    if not found then typePool[#typePool + 1] = typeId end
    return true
  end

  for _, t in ipairs(BUILTIN_TYPES) do
    registerType(t, { moves = TYPE_MOVES[t], shades = TYPE_SHADES[t] })
  end
  if GameVersion.generation() == 2 then
    registerType("STEEL", { moves = TYPE_MOVES.STEEL, shades = TYPE_SHADES.STEEL })
    registerType("DARK", { moves = TYPE_MOVES.DARK, shades = TYPE_SHADES.DARK })
  end

  mod.exports.registerType = registerType
  mod.exports.types = function()
    local out = {}
    for i, t in ipairs(typePool) do out[i] = t end
    return out
  end
  mod.exports.learnsetFor = function(typeId)
    local out = {}
    for i, e in ipairs(learnsetFor(typeId)) do
      out[i] = { level = e.level, move = e.move }
    end
    return out
  end

  local function pickType(data, species)
    local def = data.pokemon[species]
    local primary = def and def.types and def.types[1]
    local choices = {}
    for _, t in ipairs(typePool) do
      if t ~= primary then choices[#choices + 1] = t end
    end
    if #choices == 0 then return "NORMAL" end
    return choices[rand(1, #choices)]
  end

  local function knownMove(data, id)
    return id and data and data.moves and data.moves[id]
  end

  -- Vanilla rows plus this type's extra rows, in level order, last four kept.
  local function mergeMoveIds(data, species, level, typeId)
    local def = data and data.pokemon and data.pokemon[species]
    local rows = {}
    if def then
      if type(def.level1Moves) == "table" then
        for _, id in ipairs(def.level1Moves) do
          rows[#rows + 1] = { level = 1, move = id }
        end
      end
      for _, entry in ipairs(def.learnset or def.levelMoves or {}) do
        rows[#rows + 1] = { level = entry.level or 1, move = entry.move }
      end
    end
    for _, entry in ipairs(learnsetFor(typeId)) do
      rows[#rows + 1] = { level = entry.level or 1, move = entry.move, extra = true }
    end
    table.sort(rows, function(a, b)
      if a.level ~= b.level then return a.level < b.level end
      if a.extra ~= b.extra then return not a.extra end
      return false
    end)
    local ids, seen = {}, {}
    for _, entry in ipairs(rows) do
      local id = entry.move
      if (entry.level or 0) <= level and knownMove(data, id) and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
        if #ids > 4 then table.remove(ids, 1) end
      end
    end
    return ids
  end

  local function slotsFromIds(data, ids)
    local moves = {}
    for _, id in ipairs(ids) do
      local mdef = data.moves[id]
      if mdef then
        moves[#moves + 1] = { id = id, pp = mdef.pp or 0, maxPp = mdef.pp or 0 }
      end
    end
    if #moves == 0 then
      local fallback = data.moves.TACKLE
      moves[1] = { id = "TACKLE", pp = fallback and fallback.pp or 35 }
    end
    return moves
  end

  local function deltaMovesAt(typeId, level)
    local out = {}
    for _, entry in ipairs(learnsetFor(typeId)) do
      if entry.level == level and entry.move then
        out[#out + 1] = entry.move
      end
    end
    return out
  end

  local function stampDelta(data, mon)
    if not mon or deltaOf(mon) then return deltaOf(mon) end
    local typeId = pickType(data, mon.species)
    mon.extra = mon.extra or {}
    mon.extra.delta = { type = typeId }
    mon.moves = slotsFromIds(data, mergeMoveIds(data, mon.species, mon.level or 1, typeId))
    mon.types = { typeId }
    return mon.extra.delta
  end

  local function applyDeltaTypes(battler, mon)
    local d = deltaOf(mon)
    if not d or not d.type then return end
    mon.types = { d.type }
    if battler and battler.curTypes then
      battler.curTypes = { d.type }
    end
    if battler and battler ~= mon then
      local base = mon.nickname
        or (battler.def and battler.def.name)
        or mon.species
      if type(battler.name) == "string" and not battler.name:match("^D%.") then
        battler.name = "D." .. base
      end
    end
  end

  local function ensureTint(srcPath, species, side, typeId)
    local shades = shadesFor(typeId)
    if not shades or not srcPath or not love or not love.filesystem then
      return nil
    end
    local rel = ("delta/%s/%s/%s.png"):format(typeId, side, species)
    local outPath = "save/mod-derived/" .. mod.id .. "/" .. rel
    if love.filesystem.getInfo(outPath) then
      return outPath
    end
    local Assets = require("src.render.Assets")
    local ok, src = pcall(Assets.imageData, srcPath)
    if not ok or not src then return nil end
    local tinted = recolor(src, shades)
    local dir = outPath:match("^(.*)/[^/]+$")
    if dir then love.filesystem.createDirectory(dir) end
    local encoded = tinted:encode("png")
    local written = love.filesystem.write(outPath, encoded)
    if not written then return nil end
    return outPath
  end

  local function odds()
    local n = tonumber(mod.options:get("odds")) or 64
    if n < 1 then n = 1 end
    return math.floor(n)
  end

  local function isWildBattle(ev, battle)
    local kind = ev and ev.kind
    if kind == "trainer" or kind == "gym" or kind == "final"
        or kind == "ghost" or kind == "oldman" then
      return false
    end
    if kind == "wild" or kind == "safari" then return true end
    if battle and (battle.wild or battle.safari or battle.kind == "wild") then
      return true
    end
    return false
  end

  local function appendUnique(list, ids, data)
    local seen = {}
    for _, id in ipairs(list) do seen[id] = true end
    for _, id in ipairs(ids) do
      if id and not seen[id] and (not data or knownMove(data, id)) then
        seen[id] = true
        list[#list + 1] = id
      end
    end
  end

  -- Recolored art when a mon carries extra.delta. Same hook on both games.
  mod.hooks:wrap("pokemon.sprite", function(next, path, ctx)
    path = next(path, ctx)
    local d = ctx.mon and deltaOf(ctx.mon)
    if not d or not d.type or not path then return path end
    local tinted = ensureTint(path, ctx.species, ctx.side, d.type)
    if tinted then
      ctx.trueColor = true
      return tinted
    end
    return path
  end)

  -- Rare wilds anywhere (grass, water, fishing, safari). Default 1/64.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local data = (mod.game and mod.game.data) or battle.data
    local enemy = battle.enemy
    local mon = enemy and (enemy.mon or enemy)
    if isWildBattle(ev, battle) and mon and not deltaOf(mon) then
      if rand(1, odds()) == 1 then
        stampDelta(data, mon)
      end
    end
    if enemy then applyDeltaTypes(enemy, mon) end
    local player = battle.player
    if player then applyDeltaTypes(player, player.mon or player) end
  end)

  local wrapCandy
  if GameVersion.generation() == 2 then
    local Battle = require("src.battle.gen2.Battle")
    local vanillaDef = Battle.speciesDef
    function Battle.speciesDef(self, mon)
      local def = vanillaDef(self, mon)
      local d = deltaOf(mon)
      if not (d and d.type and def) then return def end
      return setmetatable({ types = { d.type } }, { __index = def })
    end

    local Mon = require("src.battle.gen2.Mon")
    local vanillaGain = Mon.gainExperience
    function Mon.gainExperience(mon, amount, data)
      local result = vanillaGain(mon, amount, data)
      local d = deltaOf(mon)
      if d and d.type and result and result.learned then
        local from = result.from or 0
        local to = result.to or mon.level
        for _, entry in ipairs(learnsetFor(d.type)) do
          if entry.level > from and entry.level <= to then
            appendUnique(result.learned, { entry.move }, data)
          end
        end
      end
      return result
    end

    local Evolution = require("src.core.gen2.Evolution")
    local vanillaEvo = Evolution.learnedOnEvolve
    function Evolution.learnedOnEvolve(data, species, level, mon)
      local out = vanillaEvo(data, species, level, mon)
      local d = deltaOf(mon)
      if d and d.type then
        appendUnique(out, deltaMovesAt(d.type, level), data)
      end
      return out
    end

    local Breeding = require("src.core.gen2.Breeding")
    local vanillaBreed = Breeding.learnMovesFromDayCare
    function Breeding.learnMovesFromDayCare(data, mon, fromLevel, toLevel)
      vanillaBreed(data, mon, fromLevel, toLevel)
      local d = deltaOf(mon)
      if not (d and d.type) then return mon.moves end
      mon.moves = mon.moves or {}
      for _, row in ipairs(learnsetFor(d.type)) do
        if row.level > fromLevel and row.level <= toLevel
            and knownMove(data, row.move) then
          local known = false
          for _, entry in ipairs(mon.moves) do
            if entry.id == row.move then known = true break end
          end
          if not known then
            Breeding.loadEggMove(mon.moves, row.move, data)
          end
        end
      end
      return mon.moves
    end

    wrapCandy = function(rec)
      if not rec or not rec.use or rec._deltaWrapped then return end
      local vanillaCandy = rec.use
      rec.use = function(ctx)
        local result = vanillaCandy(ctx)
        local d = ctx and deltaOf(ctx.mon)
        if result and result.learned and d and d.type then
          appendUnique(result.learned, deltaMovesAt(d.type, result.level), ctx.data)
        end
        return result
      end
      rec._deltaWrapped = true
    end
    wrapCandy(require("src.core.gen2.ItemEffects").RECORDS.RARE_CANDY)
  else
    local Experience = require("src.battle.Experience")
    local vanillaApply = Experience.apply
    local vanillaAt = Experience.movesLearnedAt
    local lastMon

    function Experience.apply(data, mon, ...)
      lastMon = mon
      return vanillaApply(data, mon, ...)
    end

    local function monForDef(speciesDef, level)
      if lastMon and deltaOf(lastMon) then
        local data = mod.game and mod.game.data
        if data and data.pokemon[lastMon.species] == speciesDef then
          return lastMon
        end
      end
      local game = mod.game
      local party = game and game.save and game.save.party
      if type(party) ~= "table" then return nil end
      for _, mon in ipairs(party) do
        local data = game.data
        if mon and deltaOf(mon) and data.pokemon[mon.species] == speciesDef
            and (not level or mon.level == level) then
          return mon
        end
      end
      return nil
    end

    function Experience.movesLearnedAt(speciesDef, level)
      local out = vanillaAt(speciesDef, level)
      local mon = monForDef(speciesDef, level)
      local d = deltaOf(mon)
      if d and d.type then
        appendUnique(out, deltaMovesAt(d.type, level),
          mod.game and mod.game.data)
      end
      return out
    end

    local Pokemon = require("src.pokemon.Pokemon")
    local vanillaDay = Pokemon.learnMovesFromDayCare
    function Pokemon.learnMovesFromDayCare(data, mon, speciesDef, startLevel, newLevel)
      vanillaDay(data, mon, speciesDef, startLevel, newLevel)
      local d = deltaOf(mon)
      if d and d.type then
        vanillaDay(data, mon, { learnset = learnsetFor(d.type) }, startLevel, newLevel)
      end
    end

    local summaryName = "src.ui.SummaryMenu"
    local SummaryMenu = require(summaryName)
    local vanillaDraw = SummaryMenu.draw
    function SummaryMenu.draw(self)
      local mon = self.mon
      local def = mon and self.game.data.pokemon[mon.species]
      local d = deltaOf(mon)
      local saved
      if def and d and d.type then
        saved = def.types
        def.types = { d.type }
      end
      vanillaDraw(self)
      if def and saved then def.types = saved end
    end
  end

  -- Types a later mod added to the chart join the pool (moves/shades still
  -- come from registerType when that mod supplies them).
  mod.events:on("game.ready", function(ev)
    local data = (ev and ev.game and ev.game.data) or (mod.game and mod.game.data)
    local types = data and data.type_chart and data.type_chart.types
    if type(types) == "table" then
      for id in pairs(types) do
        if type(id) == "string" and id ~= "CURSE_TYPE" and id ~= "CURSE"
            and not registry[id] then
          registerType(id, {})
        end
      end
    end
    if wrapCandy then
      wrapCandy(data and data.gen2ItemEffects and data.gen2ItemEffects.RARE_CANDY)
    end
  end)

  mod.events:on("pokemon.caught", function(ev)
    if ev.mon and deltaOf(ev.mon) then
      mod.save:set("caught", (mod.save:get("caught", 0) or 0) + 1)
    end
  end)

  mod.options:define({
    {
      key = "odds",
      type = "number",
      default = 64,
      min = 1,
      max = 256,
      step = 1,
      label = "Delta odds (1 in N)",
    },
  })
end
