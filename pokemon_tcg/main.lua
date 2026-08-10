-- Pokémon TCG mod: BYO Pokémon TCG (U) ROM → packs, binder, decks, duels, trades.
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
    assert(chunk, ("pokemon_tcg require failed: %s (%s)"):format(name, tostring(err)))
    local result = chunk(V)
    loaded[name] = result
    return result
  end


  local Cache = V.require("cache")
  local Save = V.require("save")

  local function screen(name)
    return V.require("screens." .. name)
  end

  local function openHub(game)
    return screen("TcgHub").open(game, mod)
  end

  mod.content.screens:register("TcgImport", {
    new = function(game, args)
      return screen("TcgImport").new(game, args)
    end,
  })
  mod.content.screens:register("TcgHub", {
    new = function(game)
      return openHub(game)
    end,
  })
  mod.content.screens:register("TcgShop", {
    new = function(game)
      return screen("TcgShop").open(game, mod)
    end,
  })
  mod.content.screens:register("TcgPackOpen", {
    new = function(game, args)
      return screen("TcgPackOpen").new(game, args)
    end,
  })

  mod.content.screens:register("TcgCollection", {
    new = function(game)
      return screen("TcgCollection").open(game, mod)
    end,
  })
  mod.content.screens:register("TcgDeckBuilder", {
    new = function(game)
      return screen("TcgDeckBuilder").new(game, mod)
    end,
  })

  mod.content.screens:register("TcgBattle", {
    new = function(game, args)
      return screen("TcgBattle").new(game, args)
    end,
  })
  mod.content.screens:register("TcgTrade", {
    new = function(game)
      return screen("TcgTrade").open(game, mod)
    end,
  })
  mod.content.screens:register("TcgCardView", {
    new = function(game, args)
      return screen("TcgCardView").new(game, args)
    end,
  })
  mod.content.screens:register("TcgMap", {
    new = function(game, args)
      return screen("TcgMap").new(game, args)
    end,
  })


  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    items = next(game, items) or items
    mod.ui.insertBefore(items, "QUIT", {
      label = "TCG",
      onSelect = function()
        mod.ui.push(game, "TcgHub")
      end,
    })
    return items
  end)

  -- Celadon Mart 3F Game Boy kid opens the TCG hub.
  mod.content.map_scripts:register("CELADON_MART_3F", {
    talk = {
      TEXT_CELADONMART3F_GAMEBOY_KID1 = function(game, _ow, _npc, onDone)
        mod.ui.push(game, "TcgHub")
        if onDone then onDone() end
      end,
    },
  })

  mod.options:define({
    {
      key = "rom_path",
      type = "string",
      default = "roms/PokemonTCG.gbc",
      label = "TCG ROM path",
    },
  })

  -- Warm cache when possible (non-fatal if ROM missing).
  local ok, err = Cache.ensure(mod)
  if ok then
    Save.init(mod)
    Save.ensureStarterDeck(mod, Cache.get().practiceDeck)
    mod.log:info("TCG catalog ready (%d cards)", #Cache.allCards())
  else
    mod.log:warn("TCG ROM not imported yet: %s", tostring(err))
  end
end
