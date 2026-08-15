local V = ...
local Cache = V.require("cache")
local Save = V.require("save")

local Hub = {}

function Hub.open(game, mod)
  local ok, err = Cache.ensure(mod)
  if not ok then
    return V.require("screens.TcgImport").new(game, { error = err })
  end
  Save.init(mod)
  Save.ensureStarterDeck(mod, Cache.get().practiceDeck)

  local items = {
    { label = "MAP", value = "map" },
    { label = "BUY PACKS", value = "shop" },
    { label = "OPEN PACK", value = "open",
      right = tostring(Save.packs(mod)) },
    { label = "COLLECTION", value = "collection" },
    { label = "DECK", value = "deck",
      right = ("%d/60"):format(#Save.deck(mod)) },
    { label = "DUEL", value = "duel" },
    { label = "TRADE", value = "trade" },
    { label = "CREATE", value = "create" },
    { label = "EXIT", value = "exit" },
  }

  local menu = mod.ui.ListMenu.new(game, "POKéMON TCG", items, {
    onChoose = function(item, menuSelf)
      menuSelf:close()
      if item.value == "exit" then return end
      if item.value == "map" then
        local MapGfx = V.require("map_gfx")
        local mapItems = {}
        for key, info in pairs(MapGfx.MAPS) do
          mapItems[#mapItems + 1] = {
            label = info.label or key,
            value = key,
            mapId = info.mapId or 999,
          }
        end
        table.sort(mapItems, function(a, b)
          if a.mapId ~= b.mapId then return a.mapId < b.mapId end
          return a.label < b.label
        end)
        game.stack:push(mod.ui.ListMenu.new(game, "TCG MAPS", mapItems, {
          footer = "Pick a room to walk.",
          onChoose = function(pick, m)
            m:close()
            mod.ui.push(game, "TcgMap", { map = pick.value })
          end,
        }))
      elseif item.value == "shop" then mod.ui.push(game, "TcgShop")
      elseif item.value == "open" then
        game.stack:push(V.require("screens.TcgPackOpen").pick(game, mod))
      elseif item.value == "collection" then mod.ui.push(game, "TcgCollection")

      elseif item.value == "deck" then mod.ui.push(game, "TcgDeckBuilder")
      elseif item.value == "duel" then
        local cat = Cache.get()
        local opps = (cat and cat.duelOpponents) or {}
        if #opps == 0 then
          mod.ui.push(game, "TcgBattle")
        else
          local duelItems = {}
          for _, d in ipairs(opps) do
            duelItems[#duelItems + 1] = {
              label = d.label or d.key,
              value = d,
            }
          end
          game.stack:push(mod.ui.ListMenu.new(game, "CHOOSE TRAINER", duelItems, {
            footer = "Pick an opponent.",
            onChoose = function(pick, m)
              m:close()
              mod.ui.push(game, "TcgBattle", { oppDeck = pick.value.cards, oppName = pick.value.label })
            end,
          }))
        end
      elseif item.value == "trade" then mod.ui.push(game, "TcgTrade")
      elseif item.value == "create" then mod.ui.push(game, "TcgCreate")
      end
    end,
  })
  return menu
end

return Hub
