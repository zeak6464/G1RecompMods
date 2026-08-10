local V = ...
local Cache = V.require("cache")
local Save = V.require("save")
local CardGfx = V.require("card_gfx")

local Collection = {}

function Collection.open(game, mod)
  local collection = Save.collection(mod)
  local items = {}
  local ids = {}
  for key, count in pairs(collection) do
    local id = tonumber(key)
    if id and count and count > 0 then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local card = Cache.card(id)
    local label = card and card.name or ("#" .. tostring(id))
    if card and card.kind == "pokemon" and card.level then
      label = ("%s LV%d"):format(card.name, card.level)
    end
    items[#items + 1] = {
      label = label:sub(1, 14),
      value = id,
      right = "x" .. tostring(collection[tostring(id)] or collection[id]),
    }
  end
  if #items == 0 then
    items[1] = { label = "(empty)", value = nil }
  end

  local menu
  menu = mod.ui.ListMenu.new(game, "COLLECTION", items, {
    onChoose = function(item, m)
      if not item.value then
        m:close()
        return
      end
      mod.ui.push(game, "TcgCardView", {
        cardId = item.value,
        count = collection[tostring(item.value)] or collection[item.value],
      })
    end,
  })

  -- draw selected card preview beside the list
  local baseDraw = menu.draw
  menu.draw = function(self)
    baseDraw(self)
    local item = self.items[self.index]
    if item and item.value then
      -- Integer scale only — fractional scales shred nearest-neighbor pixels.
      CardGfx.drawFrame(item.value, 94, 24, 1)
    end
  end
  return menu
end

return Collection
