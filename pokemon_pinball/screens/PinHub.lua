local V = ...
local Cache = V.require("cache")
local Save = V.require("save")
local Species = V.require("data.species")
local Stages = V.require("data.stages")

local Hub = {}

local function openPlay(game, mod, field)
  Save.setField(mod, field)
  mod.ui.push(game, "PinPlay", { field = field })
end

function Hub.open(game, mod)
  local ok, err = Cache.ensure(mod)
  if not ok then
    return V.require("screens.PinImport").new(game, { error = err })
  end
  Save.init(mod)

  local field = Save.lastField(mod)
  local items = {
    { label = "PLAY", value = "play", right = field },
    { label = "FIELD", value = "field", right = field },
    { label = "POKEDEX", value = "dex",
      right = ("%d/151"):format(Save.caughtCount(mod)) },
    { label = "SCORES", value = "scores" },
    { label = "EXIT", value = "exit" },
  }

  return mod.ui.ListMenu.new(game, "POKeMON PINBALL", items, {
    onChoose = function(item, menu)
      if item.value == "exit" then
        menu:close()
        return
      end
      if item.value == "play" then
        menu:close()
        openPlay(game, mod, Save.lastField(mod))
      elseif item.value == "field" then
        local fields = {
          { label = "RED FIELD", value = Stages.RED },
          { label = "BLUE FIELD", value = Stages.BLUE },
        }
        game.stack:push(mod.ui.ListMenu.new(game, "SELECT FIELD", fields, {
          onChoose = function(f, m2)
            Save.setField(mod, f.value)
            m2:close()
            menu.footer = "Field: " .. f.value
            -- refresh right label
            for _, it in ipairs(menu.items) do
              if it.value == "play" or it.value == "field" then
                it.right = f.value
              end
            end
          end,
        }))
      elseif item.value == "dex" then
        local caught = Save.caught(mod)
        local dexItems = {}
        for id = 1, 151 do
          local n = caught[tostring(id)] or 0
          if n > 0 then
            dexItems[#dexItems + 1] = {
              label = string.format("%03d %s", id, Species.name(id)),
              right = "x" .. tostring(n),
            }
          end
        end
        if #dexItems == 0 then
          dexItems[1] = { label = "NO CATCHES", right = "" }
        end
        game.stack:push(mod.ui.ListMenu.new(game, "PINBALL DEX", dexItems, {
          footer = "Caught in Catch Em.",
        }))
      elseif item.value == "scores" then
        local hs = Save.highScores(mod)
        local scoreItems = {}
        for _, fld in ipairs({ "RED", "BLUE" }) do
          local list = hs[fld] or {}
          if #list == 0 then
            scoreItems[#scoreItems + 1] = { label = fld .. " ---", right = "" }
          else
            for i, sc in ipairs(list) do
              scoreItems[#scoreItems + 1] = {
                label = string.format("%s #%d", fld, i),
                right = tostring(sc),
              }
            end
          end
        end
        game.stack:push(mod.ui.ListMenu.new(game, "HIGH SCORES", scoreItems, {}))
      end
    end,
  })
end

return Hub
