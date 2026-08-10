-- Local Wonder Trade: an attendant in every Poké Center swaps one party
-- mon for a random non-legendary. Mirrors the engine's in-game trade flow
-- (PartyMenu pick -> TradeAnim -> optional trade evolution).

local LEGENDARY = {
  ARTICUNO = true,
  ZAPDOS = true,
  MOLTRES = true,
  MEWTWO = true,
  MEW = true,
}

local CENTERS = {
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

-- Shared talk key on every center map.
local TEXT = "TEXT_WONDER_TRADE"

-- High object index so we never collide with vanilla _obj_ save keys.
local NPC_INDEX = 92

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

local function buildPool(data)
  local pool = {}
  for id, def in pairs(data.pokemon or {}) do
    if type(id) == "string" and def and not LEGENDARY[id] then
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

return function(mod)
  local pool

  -- ------- NPC on every Poké Center (same interior layout)

  for _, mapId in ipairs(CENTERS) do
    mod.content.maps:patch(mapId, {
      objects = {
        __append = {
          {
            index = NPC_INDEX,
            x = 7,
            y = 4,
            sprite = "SPRITE_SUPER_NERD",
            movement = "STAY",
            range = "DOWN",
            text = TEXT,
            name = "WONDER_TRADE",
          },
        },
      },
    })

    mod.content.map_scripts:register(mapId, {
      talk = {
        [TEXT] = {
          { "face_player" },
          {
            "ask",
            "WONDER TRADE?\nSwap one POKéMON\nfor a surprise!",
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

  -- ------- the trade verb (same PartyMenu / TradeAnim path as Commands.trade)

  mod.content.commands:register("wonder_trade:run", {
    foreground = true,
    fn = function(ctx)
      local Screens = require("src.ui.Screens")
      local Pokemon = require("src.pokemon.Pokemon")
      local Evolution = require("src.pokemon.Evolution")
      local Runtime = require("src.mods.Runtime")
      local Sound = require("src.core.Sound")

      local party = ctx.save.party
      if not party or #party < 1 then
        require("src.script.Commands").show_text(ctx,
          "You need a POKéMON\nto WONDER TRADE!")
        return
      end

      local runner = ctx.runner
      local picked
      Screens.push(ctx.game, "PartyMenu", {
        pickOnly = true,
        onCancel = function()
          runner:resume()
        end,
        onSwitch = function(mon)
          picked = mon
          runner:resume()
        end,
      })
      runner:yield()

      if not picked then
        require("src.script.Commands").show_text(ctx,
          "Maybe next time!")
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
        pool = buildPool(ctx.game.data)
      end
      if #pool == 0 then
        require("src.script.Commands").show_text(ctx,
          "The network is\ndown right now...")
        return
      end

      local getSpecies = pick(pool)
      local level = math.max(2, math.min(100, math.floor(picked.level or 5)))
      local sent = party[slot]
      local newMon = Pokemon.new(ctx.game.data, getSpecies, level)
      newMon.traded = true
      newMon.ot = pick(OT_NAMES)
      newMon.otId = rand(0, 65535)

      table.remove(party, slot)
      table.insert(party, newMon)

      local dex = ctx.save.pokedex
      if dex then
        dex.seen[getSpecies] = true
        dex.owned[getSpecies] = true
      end

      pcall(function()
        require("src.world.PikachuFollower")
          .modifyHappiness(ctx.save, "TRADE", sent)
      end)

      Runtime.emit("pokemon.received", {
        mon = newMon,
        from = "wonder_trade",
        peerName = newMon.ot,
      })

      local evolveTo = select(1, Evolution.pendingFor(ctx.game, newMon, {
        kind = "trade",
      }))
      Runtime.emit("trade.completed", {
        sent = sent,
        received = newMon,
        evolveTo = evolveTo,
      })

      require("src.script.Commands").show_text(ctx,
        "Connecting to the\nWONDER TRADE net...")

      Screens.push(ctx.game, "TradeAnim", {
        sent = sent,
        received = newMon,
        enemyName = newMon.ot,
        playerOt = ctx.save.player.name,
        playerOtId = sent.otId or ctx.save.player.id,
        enemyOtId = newMon.otId,
        onDone = function()
          runner:resume()
        end,
      })
      runner:yield()

      Sound.play(ctx.game.data, "Get_Key_Item")

      local sentName = sent.nickname or speciesName(ctx.game.data, sent.species)
      local recvName = newMon.nickname or speciesName(ctx.game.data, newMon.species)
      require("src.script.Commands").show_text(ctx,
        sentName .. " was\nswapped for\n" .. recvName .. "!")

      if evolveTo then
        Evolution.evolve(ctx.game, newMon, evolveTo, function()
          runner:resume()
        end, "TRADE")
        runner:yield()
      end

      require("src.script.Commands").show_text(ctx,
        "Come back anytime\nfor another trade!")

      mod.save:set("trades", (mod.save:get("trades", 0) or 0) + 1)
    end,
  })
end
