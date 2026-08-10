-- Delta Type Pokémon — Safari Zone exclusive.
-- Wild Safari encounters get a new type (not their vanilla primary), a
-- type-themed moveset, and a recolored battle/summary sprite. The delta
-- stamp lives on mon.extra.delta so catches keep it.

local TYPES = {
  "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG",
  "GHOST", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE",
  "DRAGON",
}

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
}

-- Prefer non-HM damaging / utility moves of that type (Gen 1 ids).
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

return function(mod)
  local function pickType(data, species)
    local def = data.pokemon[species]
    local primary = def and def.types and def.types[1]
    local choices = {}
    for _, t in ipairs(TYPES) do
      if t ~= primary then choices[#choices + 1] = t end
    end
    if #choices == 0 then return "NORMAL" end
    return choices[rand(1, #choices)]
  end

  local function buildMoves(data, typeId)
    local want = TYPE_MOVES[typeId] or TYPE_MOVES.NORMAL
    local moves = {}
    for _, id in ipairs(want) do
      local mdef = data.moves[id]
      if mdef then
        moves[#moves + 1] = { id = id, pp = mdef.pp or 0 }
      end
    end
    if #moves == 0 then
      local fallback = data.moves.TACKLE
      moves[1] = { id = "TACKLE", pp = fallback and fallback.pp or 35 }
    end
    return moves
  end

  local function stampDelta(data, mon)
    if not mon or deltaOf(mon) then return deltaOf(mon) end
    local typeId = pickType(data, mon.species)
    mon.extra = mon.extra or {}
    mon.extra.delta = { type = typeId }
    mon.moves = buildMoves(data, typeId)
    return mon.extra.delta
  end

  local function ensureTint(srcPath, species, side, typeId)
    local shades = TYPE_SHADES[typeId]
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

  -- Recolored art when a mon carries extra.delta.
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

  mod.events:on("game.ready", function()
    local BattleState = require("src.battle.BattleState")
    local SummaryMenu = require("src.ui.SummaryMenu")

    -- Safari wilds only: stamp delta, then rebuild the battler so types
    -- and the hue'd sprite both land before the intro cry.
    local vanillaSafari = BattleState.makeSafari
    BattleState.makeSafari = function(self, state)
      if self.enemy and self.enemy.mon then
        stampDelta(self.game.data, self.enemy.mon)
        self.enemy = BattleState.makeBattler(
          self.game.data, self.enemy.mon, false, nil)
        local d = deltaOf(self.enemy.mon)
        if d and d.type then
          local base = self.enemy.mon.nickname
            or (self.enemy.def and self.enemy.def.name)
            or self.enemy.mon.species
          self.enemy.name = "D." .. base
        end
      end
      return vanillaSafari(self, state)
    end

    -- Caught / traded Deltas keep correct STAB & matchups in every battle.
    local vanillaMake = BattleState.makeBattler
    BattleState.makeBattler = function(data, mon, isPlayer, save)
      local battler = vanillaMake(data, mon, isPlayer, save)
      local d = deltaOf(mon)
      if d and d.type then
        battler.curTypes = { d.type }
      end
      return battler
    end

    -- Status screen TYPE1/TYPE2 rows follow the delta type.
    local vanillaDraw = SummaryMenu.draw
    SummaryMenu.draw = function(self)
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
  end)

  mod.events:on("pokemon.caught", function(ev)
    -- Catch copies the live enemy mon; delta is already stamped. Track count.
    if ev.mon and deltaOf(ev.mon) then
      mod.save:set("caught", (mod.save:get("caught", 0) or 0) + 1)
    end
  end)
end
