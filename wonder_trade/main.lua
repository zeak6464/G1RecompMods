-- Local Wonder Trade: an attendant in every Poké Center swaps one party
-- mon for a random species from whatever is loaded (vanilla + other mods).
-- Received mons are shiny with perfect DVs. Gen 1 uses map_scripts + the
-- PartyMenu facade; Gold intercepts talk on *_POKECENTER_1F maps.

local GameVersion = require("src.core.GameVersion")

local PERFECT_DVS = {
  attack = 15, defense = 15, speed = 15, special = 15,
}

local GEN1_CENTERS = {
  "VIRIDIAN_POKECENTER",
  "PEWTER_POKECENTER",
  "CERULEAN_POKECENTER",
  "LAVENDER_POKECENTER",
  "VERMILION_POKECENTER",
  "CELADON_POKECENTER",
  "FUCHSIA_POKECENTER",
  "CINNABAR_POKECENTER",
  "SAFFRON_POKECENTER",
  "MT_MOON_POKECENTER",
  "ROCK_TUNNEL_POKECENTER",
}

local GEN2_CENTERS = {
  "CHERRYGROVE_POKECENTER_1F",
  "VIOLET_POKECENTER_1F",
  "ROUTE_32_POKECENTER_1F",
  "AZALEA_POKECENTER_1F",
  "GOLDENROD_POKECENTER_1F",
  "ECRUTEAK_POKECENTER_1F",
  "OLIVINE_POKECENTER_1F",
  "CIANWOOD_POKECENTER_1F",
  "MAHOGANY_POKECENTER_1F",
  "BLACKTHORN_POKECENTER_1F",
  "SILVER_CAVE_POKECENTER_1F",
  "INDIGO_PLATEAU_POKECENTER_1F",
  "VIRIDIAN_POKECENTER_1F",
  "PEWTER_POKECENTER_1F",
  "CERULEAN_POKECENTER_1F",
  "ROUTE_10_POKECENTER_1F",
  "VERMILION_POKECENTER_1F",
  "LAVENDER_POKECENTER_1F",
  "CELADON_POKECENTER_1F",
  "SAFFRON_POKECENTER_1F",
  "FUCHSIA_POKECENTER_1F",
  "CINNABAR_POKECENTER_1F",
}

local TEXT = "TEXT_WONDER_TRADE"
local NPC_INDEX = 92
local TRADE_ANIM = { "TradeAnim", "Gen2TradeAnim" }

local OT_NAMES = {
  "ASH", "MISTY", "BROCK", "GARY", "JOY", "BILL", "LANCE", "ERIKA",
  "KOGA", "SABRINA", "BLAINE", "SURGE", "OAK", "DAISY", "RED", "BLUE",
  "LEAF", "GREEN", "JANINE", "WILL", "KAREN", "BRUNO", "AGATHA",
}

local function rand(lo, hi)
  local r = (love and love.math and love.math.random) or math.random
  return r(lo, hi)
end

local function pick(list)
  return list[rand(1, #list)]
end

local function isSpecies(id, def)
  if type(id) ~= "string" or type(def) ~= "table" then return false end
  if id == "EGG" then return false end
  return type(def.baseStats) == "table"
end

local function buildPool(data)
  local pool = {}
  for id, def in pairs(data.pokemon or {}) do
    if isSpecies(id, def) then
      pool[#pool + 1] = id
    end
  end
  table.sort(pool)
  return pool
end

local function speciesName(data, id)
  local def = data.pokemon[id]
  return (def and def.name) or id
end

local function say(game, text, onDone)
  if GameVersion.generation() == 2 then
    local world = game.world
    if world and world.showText then
      world:showText(text, onDone)
      return
    end
  end
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, onDone))
end

local function makeMon(data, species, level)
  if GameVersion.generation() == 2 then
    return require("src.battle.gen2.Mon").new(data, species, level, {
      dvs = {
        attack = PERFECT_DVS.attack,
        defense = PERFECT_DVS.defense,
        speed = PERFECT_DVS.speed,
        special = PERFECT_DVS.special,
      },
      shiny = true,
    })
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  local mon = Pokemon.new(data, species, level)
  local dvs = {
    attack = PERFECT_DVS.attack,
    defense = PERFECT_DVS.defense,
    speed = PERFECT_DVS.speed,
    special = PERFECT_DVS.special,
  }
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
    + (dvs.speed % 2) * 2 + (dvs.special % 2)
  mon.dvs = dvs
  mon.stats = Stats.calc(data.pokemon[species], level, dvs, mon.statExp)
  mon.hp = mon.stats.hp
  mon.shiny = true
  return mon
end

local function markDex(save, species)
  local dex = save.pokedex
  if not dex then return end
  if type(dex.seen) == "table" then dex.seen[species] = true end
  if type(dex.owned) == "table" then dex.owned[species] = true end
  if type(dex.caught) == "table" then dex.caught[species] = true end
end

local function tradeEvolve(game, mon, onDone)
  if GameVersion.generation() == 2 then
    local Evolution = require("src.core.gen2.Evolution")
    local entry = Evolution.checkMon(game.data, mon, { link = true })
    if not entry then
      if onDone then onDone() end
      return
    end
    require("src.ui.Screens").push(game, "Gen2EvolutionAnim", {
      mon = mon,
      entry = entry,
      save = game.save,
      onDone = function()
        if game.stack and game.stack:top() then game.stack:pop() end
        if onDone then onDone() end
      end,
    })
    return
  end
  local evoName = "src.pokemon.Evolution"
  local Evolution = require(evoName)
  local evolveTo = select(1, Evolution.pendingFor(game, mon, { kind = "trade" }))
  if not evolveTo then
    if onDone then onDone() end
    return
  end
  Evolution.evolve(game, mon, evolveTo, onDone, "TRADE")
end

return function(mod)
  local pool
  local gen2 = GameVersion.generation() == 2
  local centers = gen2 and GEN2_CENTERS or GEN1_CENTERS

  for _, mapId in ipairs(centers) do
    mod.content.maps:patch(mapId, {
      objects = {
        __append = {
          {
            index = NPC_INDEX,
            x = 7,
            y = 4,
            sprite = "SPRITE_SUPER_NERD",
            movement = gen2 and 6 or "STAY",
            range = "DOWN",
            text = TEXT,
            name = "WONDER_TRADE",
          },
        },
      },
    })
  end

  local function beginTrade(game)
    local Screens = require("src.ui.Screens")
    local PartyMenu = require("src.ui.PartyMenu")
    local Runtime = require("src.mods.Runtime")

    local party = game.save.party
    if not party or #party < 1 then
      say(game, "You need a POKéMON\nto WONDER TRADE!")
      return
    end

    local function afterPick(picked)
      if not picked then
        say(game, "Maybe next time!")
        return
      end

      local slot
      for i, mon in ipairs(party) do
        if mon == picked then
          slot = i
          break
        end
      end
      if not slot then return end

      if not pool or #pool == 0 then
        pool = buildPool(game.data)
      end
      if #pool == 0 then
        say(game, "The network is\ndown right now...")
        return
      end

      local getSpecies = pick(pool)
      local level = math.max(2, math.min(100, math.floor(picked.level or 5)))
      local sent = party[slot]
      local newMon = makeMon(game.data, getSpecies, level)
      if not newMon then
        say(game, "The network is\ndown right now...")
        return
      end
      newMon.traded = true
      newMon.ot = pick(OT_NAMES)
      newMon.otName = newMon.ot
      newMon.otId = rand(0, 65535)

      table.remove(party, slot)
      table.insert(party, newMon)
      markDex(game.save, getSpecies)

      Runtime.emit("pokemon.received", {
        mon = newMon,
        from = "wonder_trade",
        peerName = newMon.ot,
      })
      Runtime.emit("trade.completed", {
        sent = sent,
        received = newMon,
      })

      local function afterAnim()
        local sentName = sent.nickname or speciesName(game.data, sent.species)
        local recvName = newMon.nickname or speciesName(game.data, newMon.species)
        say(game, sentName .. " was\nswapped for\v" .. recvName .. "!", function()
          tradeEvolve(game, newMon, function()
            say(game, "Come back anytime\nfor another trade!")
            mod.save:set("trades", (mod.save:get("trades", 0) or 0) + 1)
          end)
        end)
      end

      Screens.push(game, TRADE_ANIM[GameVersion.generation()], {
        sent = sent,
        received = newMon,
        given = sent,
        enemyName = newMon.ot,
        playerOt = game.save.player.name,
        playerOtId = sent.otId or game.save.player.id,
        enemyOtId = newMon.otId,
        row = { otName = newMon.ot, otId = newMon.otId },
        save = game.save,
        onDone = function()
          if game.stack and game.stack:top() then
            local top = game.stack:top()
            if top and (top.screenId or ""):find("TradeAnim") then
              game.stack:pop()
            end
          end
          afterAnim()
        end,
      })
    end

    local menu = PartyMenu.new(game, {
      pickOnly = true,
      onCancel = function()
        afterPick(nil)
      end,
      onSwitch = function(mon)
        afterPick(mon)
      end,
    })
    game.stack:push(menu)
  end

  if not gen2 then
    for _, mapId in ipairs(centers) do
      mod.content.map_scripts:register(mapId, {
        talk = {
          [TEXT] = {
            { "face_player" },
            {
              "ask",
              "WONDER TRADE?\nSwap one POKéMON\vfor a surprise!",
            },
            { "jump_if_false", "no" },
            { "wonder_trade:run" },
            { "jump", "end" },
            { "label", "no" },
            {
              "show_text",
              "Come back if you\nchange your mind!",
            },
          },
        },
      })
    end

    mod.content.commands:register("wonder_trade:run", {
      foreground = true,
      fn = function(ctx)
        beginTrade(ctx.game)
      end,
    })
  else
    local function isWonderNpc(npc)
      local def = npc and npc.def
      return def and (def.name == "WONDER_TRADE" or def.text == TEXT)
    end

    mod.events:on("game.ready", function()
      local OW = require("src.world.OverworldController")
      local prev = OW.talkTo
      function OW.talkTo(world, npc)
        if isWonderNpc(npc) then
          beginTrade((world and world.game) or mod.game)
          return true
        end
        if prev then return prev(world, npc) end
        return false
      end
    end)
  end
end
