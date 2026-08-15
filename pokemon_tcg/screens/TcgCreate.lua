local V = ...
local Cache = V.require("cache")
local Save = V.require("save")
local Custom = V.require("custom")
local CardGfx = V.require("card_gfx")
local Share = V.require("share")

local Create = {}

local TYPES = Custom.types()
local WR_OPTS = { "NONE" }
for _, t in ipairs(Custom.wrTypes()) do WR_OPTS[#WR_OPTS + 1] = t end
local HP_OPTS = { 30, 40, 50, 60, 70, 80, 90, 100, 120, 150, 200 }
local LV_OPTS = { 8, 10, 12, 15, 20, 25, 30, 40, 50, 60 }
local DMG_OPTS = { 0, 10, 20, 30, 40, 50, 60, 70, 80, 100 }
local RARITIES = { "CIRCLE", "DIAMOND", "STAR" }
local STAGES = { "BASIC", "STAGE1", "STAGE2" }
local RETREAT_OPTS = { 0, 1, 2, 3, 4 }
local PRICES = { 300, 500, 700, 1000 }
local COST_N = { 1, 2, 3, 4 }

local function askName(game, title, current, onDone)
  local GameVersion = require("src.core.GameVersion")
  local Screens = require("src.ui.Screens")
  if GameVersion.generation() == 2 then
    local finished = false
    local function finish(name)
      if finished then return end
      finished = true
      game.stack:pop()
      if name and name ~= "" then onDone(name:upper()) end
    end
    Screens.push(game, "Gen2NamingScreen", {
      type = "nickname",
      prompt = title or "NAME?",
      maxLength = 10,
      initial = current or "",
      onDone = finish,
      onCancel = function() finish(nil) end,
    })
    return
  end
  Screens.push(game, "Naming" .. "Screen", {
    title = title or "NAME?",
    maxLen = 10,
    default = current or "",
    onDone = function(name)
      if name and name ~= "" then onDone(name:upper()) end
    end,
  })
end

local function pickList(game, mod, title, values, onPick)
  local items = {}
  for _, v in ipairs(values) do
    items[#items + 1] = { label = tostring(v), value = v }
  end
  game.stack:push(mod.ui.ListMenu.new(game, title, items, {
    footer = "A: choose  B: back",
    onChoose = function(item, menu)
      menu:close()
      onPick(item.value)
    end,
  }))
end

local function confirm(game, mod, title, onYes)
  game.stack:push(mod.ui.ListMenu.new(game, title, {
    { label = "YES", value = true },
    { label = "NO", value = false },
  }, {
    onChoose = function(item, menu)
      menu:close()
      if item.value then onYes() end
    end,
  }))
end

local function showPath(game, mod, title, path)
  local items = {}
  local s = tostring(path or "")
  if s == "" then
    items[1] = { label = "(unknown)", value = true }
  else
    while #s > 0 do
      items[#items + 1] = { label = s:sub(1, 16), value = true }
      s = s:sub(17)
    end
  end
  game.stack:push(mod.ui.ListMenu.new(game, title, items, {
    footer = "Put .tcg and art here.",
    onChoose = function(_, menu) menu:close() end,
  }))
end

local function showPackPreview(game, title, setName, picB64)
  local PackGfx = V.require("pack_gfx")
  local Preview = {}
  Preview.__index = Preview
  Preview.isOpaque = true
  function Preview:sgbPalettes(g)
    local P = require("src.render.PaletteFX")
    return { P.trueColorZone(0, 0, 19, 17) }
  end
  function Preview:update()
    if game.input:wasPressed("a") or game.input:wasPressed("b") then
      game.stack:pop()
    end
  end
  function Preview:draw()
    local F = require("src.render.Font")
    love.graphics.setColor(0.95, 0.92, 0.82, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    local px = math.floor((160 - PackGfx.WIDTH) / 2)
    local py = 4
    local bytes = picB64 and picB64 ~= "" and Share.b64dec(picB64) or nil
    local ok = false
    if bytes then
      ok = PackGfx.drawBytes(bytes, px, py, 1)
    end
    if not ok and setName then
      ok = PackGfx.draw(setName, px, py, 1)
    end
    if not ok then
      love.graphics.setColor(0.95, 0.75, 0.15, 1)
      love.graphics.rectangle("fill", px, py, PackGfx.WIDTH, PackGfx.HEIGHT)
      love.graphics.setColor(0, 0, 0, 1)
      F.draw("PACK", px + 16, py + 40)
    end
    love.graphics.setColor(0.98, 0.95, 0.88, 1)
    love.graphics.rectangle("fill", 0, 104, 160, 40)
    love.graphics.setColor(0.75, 0.15, 0.15, 1)
    love.graphics.rectangle("line", 1, 105, 158, 38)
    love.graphics.setColor(0, 0, 0, 1)
    F.draw((title or "PACK"):sub(1, 16), 8, 112)
    F.draw("A/B: back", 8, 124)
    love.graphics.setColor(1, 1, 1, 1)
  end
  game.stack:push(setmetatable({}, Preview))
end

local function pickPicture(game, mod, draft, onDone, w, h)
  Share.ensureDirs()
  local files = Share.listArt(mod)
  local items = {
    { label = "CLEAR", value = "clear" },
    { label = "FOLDER", value = "folder" },
  }
  for _, name in ipairs(files) do
    items[#items + 1] = { label = name:sub(1, 14), value = name }
  end
  game.stack:push(mod.ui.ListMenu.new(game, "PICTURE", items, {
    footer = #files == 0 and "Drop PNG in share/art" or "A: use picture",
    onChoose = function(item, menu)
      if item.value == "folder" then
        showPath(game, mod, "ART FOLDER", Share.folderPath() .. "/art")
        return
      end
      if item.value == "clear" then
        draft.picB64 = ""
        menu:close()
        onDone()
        return
      end
      local bytes = Share.readArt(mod, item.value)
      local b64, err = Share.encodePicture(bytes, item.value, w, h)
      if not b64 then
        menu.footer = err or "Bad image"
        return
      end
      draft.picB64 = b64
      menu:close()
      onDone()
    end,
  }))
end

local function openImport(game, mod)
  Share.ensureDirs()
  local files = Share.listExports(mod)
  local items = {}
  for _, name in ipairs(files) do
    items[#items + 1] = { label = name:sub(1, 14), value = name }
  end
  if #items == 0 then
    items[1] = { label = "(no .tcg files)", value = nil }
  end
  game.stack:push(mod.ui.ListMenu.new(game, "IMPORT", items, {
    footer = "Drop .tcg in share folder.",
    onChoose = function(item, menu)
      if not item.value then
        menu:close()
        return
      end
      local result, err = Share.importFile(mod, item.value)
      if not result then
        menu.footer = err or "Import failed"
        return
      end
      menu:close()
      game.stack:push(mod.ui.ListMenu.new(game, "IMPORTED", {
        { label = (result.name or "?"):sub(1, 14), value = true },
      }, {
        footer = result.kind == "pack"
          and (tostring(result.count) .. " cards + pack")
          or "Added to collection.",
        onChoose = function(_, m) m:close() end,
      }))
    end,
  }))
end

local function costText(cost)
  if type(cost) ~= "table" then return "-" end
  local parts = {}
  for _, typ in ipairs(TYPES) do
    local n = cost[typ] or 0
    if n > 0 then
      parts[#parts + 1] = tostring(n) .. typ:sub(1, 1)
    end
  end
  if #parts == 0 then return "-" end
  return table.concat(parts, " ")
end

local function atkText(atk)
  if not atk then return "(NONE)" end
  return ("%s %d"):format(atk.name or "ATK", atk.damage or 0)
end

local function newDraft(kind)
  if kind == "energy" then
    return {
      kind = "energy",
      name = "FIRE ENERGY",
      energyType = "FIRE",
      type = "FIRE",
      rarity = "CIRCLE",
    }
  end
  if kind == "trainer" then
    return {
      kind = "trainer",
      name = "TRAINER",
      type = "TRAINER",
      rarity = "CIRCLE",
    }
  end
  return {
    kind = "pokemon",
    name = "NEW CARD",
    type = "COLORLESS",
    hp = 50,
    level = 10,
    stage = "BASIC",
    retreat = 1,
    weakness = nil,
    resistance = nil,
    rarity = "CIRCLE",
    attacks = {
      { name = "TACKLE", damage = 20, cost = { COLORLESS = 1 } },
    },
  }
end

local function cardFromExisting(mod, card)
  local draft = {
    id = card.id,
    kind = card.kind,
    name = card.name,
    type = card.type,
    energyType = card.energyType,
    hp = card.hp,
    level = card.level,
    stage = card.stage,
    retreat = card.retreat,
    weakness = card.weakness,
    resistance = card.resistance,
    rarity = card.rarity,
    picB64 = Custom.picB64(mod, card.id),
    attacks = {},
  }
  for _, atk in ipairs(card.attacks or {}) do
    local cost = {}
    for k, v in pairs(atk.cost or {}) do cost[k] = v end
    draft.attacks[#draft.attacks + 1] = {
      name = atk.name,
      damage = atk.damage,
      cost = cost,
    }
  end
  return draft
end

local function rebuild(menu, items)
  menu.items = items
  if menu.index > #items then menu.index = #items end
  if menu.index < 1 then menu.index = 1 end
end

local function editCost(game, mod, atk, onDone)
  atk.cost = atk.cost or {}
  local function open()
    local items = {
      { label = "NOW", right = costText(atk.cost), value = "now" },
    }
    for _, typ in ipairs(TYPES) do
      items[#items + 1] = { label = "ADD " .. typ, value = typ }
    end
    items[#items + 1] = { label = "CLEAR", value = "clear" }
    items[#items + 1] = { label = "DONE", value = "done" }
    game.stack:push(mod.ui.ListMenu.new(game, "ATK COST", items, {
      footer = "Add energy pips.",
      onChoose = function(item, menu)
        if item.value == "now" then return end
        if item.value == "done" then
          menu:close()
          onDone()
          return
        end
        if item.value == "clear" then
          atk.cost = {}
          menu:close()
          open()
          return
        end
        pickList(game, mod, item.value, COST_N, function(n)
          atk.cost[item.value] = n
          menu:close()
          open()
        end)
      end,
    }))
  end
  open()
end

local function editAttack(game, mod, atk, title, onDone)
  local function items()
    return {
      { label = "NAME", right = atk.name or "ATK", value = "name" },
      { label = "DAMAGE", right = tostring(atk.damage or 0), value = "dmg" },
      { label = "COST", right = costText(atk.cost), value = "cost" },
      { label = "DONE", value = "done" },
    }
  end
  local menu
  menu = mod.ui.ListMenu.new(game, title, items(), {
    footer = "A: edit  B: back",
    onChoose = function(item)
      if item.value == "done" then
        menu:close()
        onDone()
      elseif item.value == "name" then
        askName(game, "ATTACK?", atk.name, function(name)
          atk.name = name
          rebuild(menu, items())
        end)
      elseif item.value == "dmg" then
        pickList(game, mod, "DAMAGE", DMG_OPTS, function(n)
          atk.damage = n
          rebuild(menu, items())
        end)
      elseif item.value == "cost" then
        editCost(game, mod, atk, function()
          rebuild(menu, items())
        end)
      end
    end,
  })
  game.stack:push(menu)
end

local function openCardEditor(game, mod, draft, isNew)
  local function items()
    local list = {
      { label = "NAME", right = (draft.name or "?"):sub(1, 8), value = "name" },
      { label = "KIND", right = (draft.kind or ""):upper(), value = "kind" },
    }
    if draft.kind == "pokemon" then
      list[#list + 1] = { label = "TYPE", right = draft.type or "?", value = "type" }
      list[#list + 1] = { label = "HP", right = tostring(draft.hp or 0), value = "hp" }
      list[#list + 1] = { label = "LEVEL", right = tostring(draft.level or 0), value = "level" }
      list[#list + 1] = { label = "STAGE", right = draft.stage or "BASIC", value = "stage" }
      list[#list + 1] = { label = "WEAK", right = draft.weakness or "NONE", value = "weak" }
      list[#list + 1] = { label = "RESIST", right = draft.resistance or "NONE", value = "resist" }
      list[#list + 1] = { label = "RETREAT", right = tostring(draft.retreat or 0), value = "retreat" }
      list[#list + 1] = {
        label = "ATK1",
        right = atkText(draft.attacks and draft.attacks[1]),
        value = "atk1",
      }
      list[#list + 1] = {
        label = "ATK2",
        right = atkText(draft.attacks and draft.attacks[2]),
        value = "atk2",
      }
    elseif draft.kind == "energy" then
      list[#list + 1] = {
        label = "TYPE",
        right = draft.energyType or draft.type or "?",
        value = "etype",
      }
    end
    list[#list + 1] = { label = "RARITY", right = draft.rarity or "CIRCLE", value = "rarity" }
    list[#list + 1] = {
      label = "PICTURE",
      right = (draft.picB64 and draft.picB64 ~= "") and "SET" or "NONE",
      value = "pic",
    }
    list[#list + 1] = { label = "SAVE", value = "save" }
    return list
  end

  local menu
  menu = mod.ui.ListMenu.new(game, isNew and "NEW CARD" or "EDIT CARD", items(), {
    footer = "A: edit  B: back",
    onChoose = function(item)
      if item.value == "name" then
        askName(game, "CARD NAME?", draft.name, function(name)
          draft.name = name
          rebuild(menu, items())
        end)
      elseif item.value == "kind" then
        pickList(game, mod, "KIND", { "pokemon", "energy", "trainer" }, function(kind)
          local keepName, keepId, keepPic = draft.name, draft.id, draft.picB64
          draft = newDraft(kind)
          draft.id = keepId
          draft.picB64 = keepPic
          if keepName and keepName ~= "NEW CARD" then draft.name = keepName end
          rebuild(menu, items())
        end)
      elseif item.value == "type" then
        pickList(game, mod, "TYPE", TYPES, function(typ)
          draft.type = typ
          rebuild(menu, items())
        end)
      elseif item.value == "etype" then
        pickList(game, mod, "ENERGY", TYPES, function(typ)
          draft.energyType = typ
          draft.type = typ
          if not draft.name or draft.name:match("ENERGY$") then
            draft.name = typ .. " ENERGY"
          end
          rebuild(menu, items())
        end)
      elseif item.value == "hp" then
        pickList(game, mod, "HP", HP_OPTS, function(n)
          draft.hp = n
          rebuild(menu, items())
        end)
      elseif item.value == "level" then
        pickList(game, mod, "LEVEL", LV_OPTS, function(n)
          draft.level = n
          rebuild(menu, items())
        end)
      elseif item.value == "stage" then
        pickList(game, mod, "STAGE", STAGES, function(s)
          draft.stage = s
          rebuild(menu, items())
        end)
      elseif item.value == "weak" then
        pickList(game, mod, "WEAK", WR_OPTS, function(v)
          draft.weakness = (v == "NONE") and nil or v
          rebuild(menu, items())
        end)
      elseif item.value == "resist" then
        pickList(game, mod, "RESIST", WR_OPTS, function(v)
          draft.resistance = (v == "NONE") and nil or v
          rebuild(menu, items())
        end)
      elseif item.value == "retreat" then
        pickList(game, mod, "RETREAT", RETREAT_OPTS, function(n)
          draft.retreat = n
          rebuild(menu, items())
        end)
      elseif item.value == "pic" then
        pickPicture(game, mod, draft, function()
          rebuild(menu, items())
        end)
      elseif item.value == "atk1" then
        draft.attacks = draft.attacks or {}
        draft.attacks[1] = draft.attacks[1]
          or { name = "TACKLE", damage = 20, cost = { COLORLESS = 1 } }
        editAttack(game, mod, draft.attacks[1], "ATTACK 1", function()
          rebuild(menu, items())
        end)
      elseif item.value == "atk2" then
        draft.attacks = draft.attacks or {}
        if not draft.attacks[2] then
          draft.attacks[2] = { name = "ATTACK", damage = 30, cost = { COLORLESS = 2 } }
        end
        editAttack(game, mod, draft.attacks[2], "ATTACK 2", function()
          rebuild(menu, items())
        end)
      elseif item.value == "rarity" then
        pickList(game, mod, "RARITY", RARITIES, function(r)
          draft.rarity = r
          rebuild(menu, items())
        end)
      elseif item.value == "save" then
        local card, err = Custom.saveCard(mod, draft)
        if not card then
          menu.footer = err or "Could not save"
          return
        end
        if isNew then Save.addCards(mod, { card.id }) end
        menu:close()
        game.stack:push(mod.ui.ListMenu.new(game, "SAVED", {
          { label = card.name, value = card.id },
        }, {
          footer = isNew and "Added to collection." or "Card updated.",
          onChoose = function(_, m)
            m:close()
            if card then
              mod.ui.push(game, "TcgCardView", { cardId = card.id })
            end
          end,
        }))
      end
    end,
  })
  game.stack:push(menu)
end

local function cardLabel(id)
  local card = Cache.card(id)
  if not card then return "#" .. tostring(id) end
  return (card.name or "?"):sub(1, 12)
end

local function openPackEditor(game, mod, draft, isNew)
  draft.cards = draft.cards or {}
  local function items()
    local list = {
      { label = "NAME", right = (draft.name or "?"):sub(1, 8), value = "name" },
      { label = "PRICE", right = tostring(draft.price or 500), value = "price" },
      {
        label = "PICTURE",
        right = (draft.picB64 and draft.picB64 ~= "") and "SET" or "NONE",
        value = "pic",
      },
      { label = "VIEW", value = "view" },
      { label = "ADD CARD", right = tostring(#draft.cards), value = "add" },
    }
    for i, id in ipairs(draft.cards) do
      list[#list + 1] = {
        label = cardLabel(id),
        value = "rm",
        rm = i,
        right = "DEL",
      }
    end
    list[#list + 1] = { label = "SAVE", value = "save" }
    return list
  end

  local function addCard()
    local cards = Cache.allCards()
    local picks = {}
    for _, c in ipairs(cards) do
      if c.custom then
        picks[#picks + 1] = {
          label = (c.name or "?"):sub(1, 12),
          value = c.id,
          right = "NEW",
        }
      end
    end
    for _, c in ipairs(cards) do
      if not c.custom then
        picks[#picks + 1] = {
          label = (c.name or "?"):sub(1, 12),
          value = c.id,
        }
      end
    end
    if #picks == 0 then return end
    local picker
    picker = mod.ui.ListMenu.new(game, "ADD CARD", picks, {
      footer = "A: add  B: done",
      onChoose = function(item)
        draft.cards[#draft.cards + 1] = item.value
        picker.footer = "Added " .. (item.label or "")
      end,
    })
    local baseDraw = picker.draw
    picker.draw = function(self)
      baseDraw(self)
      local item = self.items[self.index]
      if item and item.value then
        CardGfx.drawFrame(item.value, 94, 24, 1)
      end
    end
    game.stack:push(picker)
  end

  local menu
  local function refresh()
    rebuild(menu, items())
  end

  menu = mod.ui.ListMenu.new(game, isNew and "NEW PACK" or "EDIT PACK", items(), {
    footer = "A: edit  B: back",
    onChoose = function(item)
      if item.value == "name" then
        askName(game, "PACK NAME?", draft.name, function(name)
          draft.name = name
          refresh()
        end)
      elseif item.value == "price" then
        pickList(game, mod, "PRICE", PRICES, function(n)
          draft.price = n
          refresh()
        end)
      elseif item.value == "pic" then
        local PackGfx = V.require("pack_gfx")
        pickPicture(game, mod, draft, function()
          refresh()
          showPackPreview(game, draft.name, draft.set, draft.picB64)
        end, PackGfx.WIDTH, PackGfx.HEIGHT)
      elseif item.value == "view" then
        showPackPreview(game, draft.name, draft.set, draft.picB64)
      elseif item.value == "add" then
        addCard()
      elseif item.value == "rm" then
        table.remove(draft.cards, item.rm)
        refresh()
      elseif item.value == "save" then
        if not draft.set then
          draft.set = Custom.uniqueSet(mod, draft.name)
        end
        local pack, err = Custom.savePack(mod, draft)
        if not pack then
          menu.footer = err or "Add a card first"
          return
        end
        if isNew then Save.addPack(mod, pack.set, 1) end
        menu:close()
        showPackPreview(game, pack.name or pack.set, pack.set, draft.picB64)
      end
    end,
  })

  -- Refresh card count when returning from ADD CARD.
  local baseUpdate = menu.update
  menu._packCount = #draft.cards
  menu.update = function(self, dt)
    if #draft.cards ~= self._packCount then
      self._packCount = #draft.cards
      refresh()
    end
    return baseUpdate(self, dt)
  end
  game.stack:push(menu)
end

local function myCards(game, mod)
  local cards = Custom.cards(mod)
  local items = {}
  for _, c in ipairs(cards) do
    items[#items + 1] = {
      label = (c.name or "?"):sub(1, 12),
      value = c.id,
      right = (c.kind or ""):sub(1, 3):upper(),
    }
  end
  if #items == 0 then
    items[1] = { label = "(none yet)", value = nil }
  end
  local menu
  menu = mod.ui.ListMenu.new(game, "MY CARDS", items, {
    footer = "A: options  B: back",
    onChoose = function(item)
      if not item.value then
        menu:close()
        return
      end
      game.stack:push(mod.ui.ListMenu.new(game, item.label, {
        { label = "VIEW", value = "view" },
        { label = "EDIT", value = "edit" },
        { label = "EXPORT", value = "export" },
        { label = "GIVE 1", value = "give" },
        { label = "DELETE", value = "del" },
      }, {
        onChoose = function(act, m)
          m:close()
          if act.value == "view" then
            mod.ui.push(game, "TcgCardView", { cardId = item.value })
          elseif act.value == "edit" then
            local card = Cache.card(item.value)
            if card then openCardEditor(game, mod, cardFromExisting(mod, card), false) end
          elseif act.value == "export" then
            local file, err = Share.exportCard(mod, item.value)
            menu.footer = file and ("Wrote " .. file) or (err or "Export failed")
          elseif act.value == "give" then
            Save.addCards(mod, { item.value })
            menu.footer = "Added 1 copy."
          elseif act.value == "del" then
            confirm(game, mod, "DELETE?", function()
              Custom.deleteCard(mod, item.value)
              menu:close()
              myCards(game, mod)
            end)
          end
        end,
      }))
    end,
  })
  local baseDraw = menu.draw
  menu.draw = function(self)
    baseDraw(self)
    local item = self.items[self.index]
    if item and item.value then
      CardGfx.drawFrame(item.value, 94, 24, 1)
    end
  end
  game.stack:push(menu)
end

local function myPacks(game, mod)
  local packs = Custom.packs(mod)
  local items = {}
  for _, p in ipairs(packs) do
    items[#items + 1] = {
      label = (p.name or p.set):sub(1, 12),
      value = p.set,
      right = tostring(#(p.cards or {})),
    }
  end
  if #items == 0 then
    items[1] = { label = "(none yet)", value = nil }
  end
  game.stack:push(mod.ui.ListMenu.new(game, "MY PACKS", items, {
    footer = "A: options  B: back",
    onChoose = function(item, menu)
      if not item.value then
        menu:close()
        return
      end
      game.stack:push(mod.ui.ListMenu.new(game, item.label, {
        { label = "VIEW", value = "view" },
        { label = "EDIT", value = "edit" },
        { label = "EXPORT", value = "export" },
        { label = "GIVE 1", value = "give" },
        { label = "DELETE", value = "del" },
      }, {
        onChoose = function(act, m)
          m:close()
          if act.value == "view" then
            showPackPreview(game, item.label, item.value, Custom.packPicB64(mod, item.value))
          elseif act.value == "edit" then
            local found
            for _, p in ipairs(Custom.packs(mod)) do
              if p.set == item.value then found = p break end
            end
            if found then
              local draft = {
                set = found.set,
                name = found.name,
                price = found.price,
                picB64 = Custom.packPicB64(mod, found.set),
                cards = {},
              }
              for _, id in ipairs(found.cards or {}) do
                draft.cards[#draft.cards + 1] = id
              end
              openPackEditor(game, mod, draft, false)
            end
          elseif act.value == "export" then
            local file, err = Share.exportPack(mod, item.value)
            menu.footer = file and ("Wrote " .. file) or (err or "Export failed")
          elseif act.value == "give" then
            Save.addPack(mod, item.value, 1)
            menu.footer = "Gave 1 pack."
          elseif act.value == "del" then
            confirm(game, mod, "DELETE?", function()
              Custom.deletePack(mod, item.value)
              menu:close()
              myPacks(game, mod)
            end)
          end
        end,
      }))
    end,
  }))
end

function Create.open(game, mod)
  Cache.ensure(mod)
  Save.init(mod)
  Share.ensureDirs()
  return mod.ui.ListMenu.new(game, "CREATE", {
    { label = "NEW CARD", value = "card" },
    { label = "NEW PACK", value = "pack" },
    { label = "MY CARDS", value = "mycards" },
    { label = "MY PACKS", value = "mypacks" },
    { label = "IMPORT", value = "import" },
    { label = "SHARE FOLDER", value = "folder" },
  }, {
    footer = "Make and share cards.",
    onChoose = function(item)
      if item.value == "card" then
        openCardEditor(game, mod, newDraft("pokemon"), true)
      elseif item.value == "pack" then
        openPackEditor(game, mod, { name = "MY PACK", price = 500, cards = {} }, true)
      elseif item.value == "mycards" then
        myCards(game, mod)
      elseif item.value == "mypacks" then
        myPacks(game, mod)
      elseif item.value == "import" then
        openImport(game, mod)
      elseif item.value == "folder" then
        showPath(game, mod, "SHARE FOLDER", Share.folderPath())
      end
    end,
  })
end

return Create
