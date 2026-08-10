local V = ...
local Cache = V.require("cache")
local Trade = V.require("trade")

local TradeScreen = {}

function TradeScreen.open(game, mod)
  local offer = Trade.nextOffer(mod)
  if not offer then
    return mod.ui.ListMenu.new(game, "TRADE", {
      { label = "(no cards)", value = nil },
    }, {
      onChoose = function(_, menu) menu:close() end,
    })
  end

  local items = {
    { label = ("Give: %s"):format(offer.wantName), value = "info" },
    { label = ("Get: %s"):format(offer.giveName), value = "info" },
    { label = "ACCEPT", value = "accept" },
    { label = "DECLINE", value = "decline" },
  }

  return mod.ui.ListMenu.new(game, "NPC TRADE", items, {
    footer = offer.blurb or "Trade?",
    onChoose = function(item, menu)
      if item.value == "info" then return end
      if item.value == "decline" then
        Trade.skip(mod)
        menu:close()
        return
      end
      local ok, err = Trade.accept(mod, offer)
      menu.footer = ok and "Traded!" or (err or "Failed")
      if ok then menu:close() end
    end,
  })
end

return TradeScreen
