-- Pokémon Pinball mod: BYO Pinball ROM → Red/Blue fields, Catch 'Em, Evolution, Map Move, bonuses.
local GameVersion = require("src.core.GameVersion")

return function(mod)
  local loaded = {}
  local V = { mod = mod }

  function V.require(name)
    if loaded[name] ~= nil then return loaded[name] end
    local rel
    if name:match("^data%.") then
      rel = name:gsub("%.", "/") .. ".lua"
    elseif name:match("^screens%.") then
      rel = name:gsub("%.", "/") .. ".lua"
    else
      rel = "lib/" .. name .. ".lua"
    end
    local path = mod.path .. "/" .. rel
    local chunk, err
    if love and love.filesystem and love.filesystem.load then
      chunk, err = love.filesystem.load(path)
    end
    if not chunk then
      local f = io.open(path, "rb")
      if f then
        local src = f:read("*a")
        f:close()
        local loader = loadstring or load
        chunk, err = loader(src, "@" .. path)
      end
    end
    assert(chunk, ("pokemon_pinball require failed: %s (%s)"):format(name, tostring(err)))
    local result = chunk(V)
    loaded[name] = result
    return result
  end

  local Cache = V.require("cache")
  local Save = V.require("save")

  local function screen(name)
    return V.require("screens." .. name)
  end

  mod.content.screens:register("PinImport", {
    new = function(game, args)
      return screen("PinImport").new(game, args)
    end,
  })
  mod.content.screens:register("PinHub", {
    new = function(game)
      return screen("PinHub").open(game, mod)
    end,
  })
  mod.content.screens:register("PinPlay", {
    new = function(game, args)
      return screen("PinPlay").new(game, args)
    end,
  })

  mod.options:define({
    {
      key = "rom_path",
      type = "string",
      default = "roms/PokemonPinball.gbc",
      label = "Pinball ROM path (under mod folder)",
    },
  })

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    items = next(game, items) or items
    mod.ui.insertBefore(items, "QUIT", {
      label = "PINBALL",
      onSelect = function()
        mod.ui.push(game, "PinHub")
      end,
    })
    return items
  end)

  local TEXT = "TEXT_PINBALL_NPC"
  local function openPinball(game)
    mod.ui.push(game, "PinHub")
  end

  -- Celadon Game Corner attendant on Gen 1. Gold has no map_scripts home, so
  -- a clerk is patched onto both Game Corners and talk is intercepted.
  if GameVersion.generation() == 1 then
    local pinballNpcId = nil
    mod.events:on("map.entered", function(ev)
      if ev.mapId ~= "GAME_CORNER" then return end
      if pinballNpcId then
        mod.world:removeNpc(pinballNpcId)
        pinballNpcId = nil
      end
      pinballNpcId = mod.world:spawnNpc("GAME_CORNER", {
        index = 90,
        x = 9,
        y = 4,
        sprite = "SPRITE_GAMBLER",
        movement = "STAY",
        range = "NONE",
        text = TEXT,
      })
    end)

    mod.content.map_scripts:register("GAME_CORNER", {
      talk = {
        TEXT_PINBALL_NPC = {
          { "face_player" },
          { "ask", "Play POKeMON\nPINBALL?" },
          { "jump_if_false", "no" },
          { "push_screen", "PinHub" },
          { "jump", "end" },
          { "label", "no" },
          { "show_text", "Maybe later!" },
          { "label", "end" },
        },
      },
    })
  else
    local function addClerk(mapId, x, y, index)
      mod.content.maps:patch(mapId, {
        objects = {
          __append = {
            {
              index = index,
              x = x,
              y = y,
              sprite = "SPRITE_CLERK",
              movement = 6,
              name = "PINBALL_ATTENDANT",
              text = TEXT,
            },
          },
        },
      })
    end
    addClerk("GOLDENROD_GAME_CORNER", 10, 4, 90)
    addClerk("CELADON_GAME_CORNER", 10, 4, 90)
    local function isPinNpc(npc)
      local def = npc and npc.def
      return def and (def.name == "PINBALL_ATTENDANT" or def.text == TEXT)
    end
    mod.events:on("game.ready", function()
      local OW = require("src.world.OverworldController")
      local prev = OW.talkTo
      function OW.talkTo(world, npc)
        if isPinNpc(npc) then
          openPinball((world and world.game) or mod.game)
          return true
        end
        if prev then return prev(world, npc) end
        return false
      end
    end)
  end

  local ok, err = Cache.ensure(mod)
  if ok then
    Save.init(mod)
    mod.log:info("Pinball ROM ready (%s)", Cache.get().path)
  else
    mod.log:warn("Pinball ROM not imported yet: %s", tostring(err))
  end
end
