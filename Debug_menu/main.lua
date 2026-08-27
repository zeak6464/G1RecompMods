return function(mod)
  print("[DebugMenu] Essentials-style debug mode...")

  local GameVersion = require("src.core.GameVersion")
  local Menu = require("src.ui.Menu")
  local Font = require("src.render.Font")

  local overlayOn = true
  local noEncounters = false
  local patchedWorlds = {}

  local function isGen2()
    return GameVersion.generation() == 2
  end

  local function ctrlHeld()
    local kb = love and love.keyboard
    if not (kb and kb.isDown) then return false end
    return kb.isDown("lctrl") or kb.isDown("rctrl")
  end

  local function worldOf(game)
    return game and (game.world or game.overworld)
  end

  local function liveGame()
    return mod.game
  end

  local function skipFieldEncounters()
    return noEncounters or ctrlHeld()
  end

  local function clearUi(game)
    local stack = game and game.stack
    if not stack then return end
    for _ = 1, 16 do
      local top = stack:top()
      if not top or top.isOverworld then break end
      stack:pop()
    end
  end

  local function showMsg(game, text)
    if isGen2() then
      local world = worldOf(game)
      if world and world.showText then
        world:showText(text)
        return
      end
    end
    local ok, TextBox = pcall(require, "src.render.TextBox")
    if ok and TextBox and game and game.stack then
      game.stack:push(TextBox.new(game, text))
    end
  end

  local function safe(game, fn, failMsg)
    local ok, err = pcall(fn)
    if not ok then
      print("[DebugMenu]", tostring(err))
      showMsg(game, failMsg or "ACTION FAILED!")
    end
    return ok
  end

  ------------------------------------------------------------------
  -- Patch trainer sight so Ctrl skips overworld trainer engagements.
  ------------------------------------------------------------------
  local function patchWorld(game)
    local world = worldOf(game)
    if not world then return end
    if patchedWorlds[world] then return end
    patchedWorlds[world] = true
    if world.checkTrainerBattle then
      local orig = world.checkTrainerBattle
      world.checkTrainerBattle = function(self)
        if ctrlHeld() then return false end
        return orig(self)
      end
    end
    if world.checkTrainerSight then
      local orig = world.checkTrainerSight
      world.checkTrainerSight = function(self)
        if ctrlHeld() then return end
        return orig(self)
      end
    end
  end

  ------------------------------------------------------------------
  -- Data helpers
  ------------------------------------------------------------------
  local function mapsTable(game)
    local world = worldOf(game)
    if world and type(world.maps) == "table" then return world.maps end
    local data = game and game.data
    return data and (data.gen2Maps or data.maps)
  end

  local function sortedIds(tbl, keep)
    local ids = {}
    if type(tbl) ~= "table" then return ids end
    for id, val in pairs(tbl) do
      if type(id) == "string" and (not keep or keep(id, val)) then
        ids[#ids + 1] = id
      end
    end
    table.sort(ids)
    return ids
  end

  local function speciesList(game)
    local out = {}
    local poke = game.data and game.data.pokemon
    if type(poke) ~= "table" then return out end
    local byDex = {}
    local maxDex = 0
    for species, def in pairs(poke) do
      if type(def) == "table" and type(def.dex) == "number" and def.dex > 0
          and species ~= "EGG" and species ~= "UNUSED" then
        byDex[def.dex] = {
          id = def.id or species,
          name = def.name or def.id or species,
          dex = def.dex,
        }
        if def.dex > maxDex then maxDex = def.dex end
      end
    end
    for n = 1, maxDex do
      if byDex[n] then out[#out + 1] = byDex[n] end
    end
    return out
  end

  local function isJunkItem(id, def)
    if type(id) ~= "string" then return true end
    if id:match("^ITEM_[0-9A-F]+$") then return true end
    local name = type(def) == "table" and def.name or nil
    if name == "TERU-SAMA" or name == "" then return true end
    return false
  end

  local function itemList(game)
    local items = game.data and game.data.items
    local ids = sortedIds(items, function(id, def)
      return type(def) == "table" and not isJunkItem(id, def)
    end)
    local out = {}
    for _, id in ipairs(ids) do
      local def = items[id]
      out[#out + 1] = {
        id = id,
        name = (def and def.name) or id,
      }
    end
    return out
  end

  local function landingCell(def)
    if type(def) ~= "table" then return 4, 4 end
    local warps = def.warps
    if type(warps) == "table" then
      local w = warps[1]
      if type(w) == "table" then
        return tonumber(w.x) or 4, tonumber(w.y) or 4
      end
    end
    local bw = tonumber(def.width) or 5
    local bh = tonumber(def.height) or 5
    return math.max(1, math.floor(bw)), math.max(1, math.floor(bh))
  end

  ------------------------------------------------------------------
  -- UI: Gold Chrome list / Gen1 Menu / number picker
  ------------------------------------------------------------------
  local openDebugMenu

  -- Gold box is 20 tiles; border takes cols 0 and 19, cursor sits at 1,
  -- labels start at 2.  Sixteen glyphs fit inside without crossing the wall.
  local LABEL_TILES = 16

  local function clipLabel(text)
    text = tostring(text or "")
    local spans = Font.split(text)
    if #spans <= LABEL_TILES then return text end
    return text:sub(spans[1].from, spans[LABEL_TILES].to)
  end

  local function pushGoldList(game, items, opts)
    opts = opts or {}
    if not items or #items == 0 then
      showMsg(game, opts.emptyMsg or "NO ENTRIES.")
      return
    end
    local Chrome = require("src.ui.gen2.Chrome")
    local rows = math.min(opts.maxVisible or 8, #items, 8)
    local screen = {
      isOpaque = false,
      isDebugMenu = true,
      list = Chrome.List.new({
        items = items,
        x = 2, y = 2, spacing = 2,
        rows = rows,
        wrap = true,
        startAccepts = true,
        onChoose = function(_value, index)
          local item = items[index]
          if not item then return end
          if not item.keepOpen then game.stack:pop() end
          if item.onSelect then
            safe(game, item.onSelect, "ACTION FAILED!")
          end
        end,
        onCancel = function()
          game.stack:pop()
          if opts.onCancel then opts.onCancel() end
        end,
      }),
      update = function(self)
        self.list:update(game.input)
      end,
      draw = function(self)
        Chrome.box(0, 0, 20, rows * 2 + 2)
        local list = self.list
        for row = 1, list.rows do
          local i = row + list.scroll
          local item = list.items[i]
          if item then
            local ty = list.y + (row - 1) * list.spacing
            if i == list.index then Chrome.cursor(list.x - 1, ty) end
            Chrome.print(clipLabel(item.label), list.x, ty)
          end
        end
        if list.rows < #list.items and list.scroll + list.rows < #list.items then
          love.graphics.setColor(0, 0, 0, 1)
          Font.drawCode(Chrome.DOWN_ARROW, (list.x - 1) * 8,
            (list.y + list.rows * list.spacing - 1) * 8)
        end
      end,
    }
    game.stack:push(screen)
  end

  local function pushGen1Menu(game, items, opts)
    opts = opts or {}
    if not items or #items == 0 then
      showMsg(game, opts.emptyMsg or "NO ENTRIES.")
      return
    end
    game.stack:push(Menu.new(game, items, {
      tx = 0, ty = 0, tw = 20,
      maxVisible = opts.maxVisible or 8,
      startCloses = true,
      onCancel = opts.onCancel,
    }))
  end

  local function pushList(game, items, opts)
    if isGen2() then
      pushGoldList(game, items, opts)
    else
      pushGen1Menu(game, items, opts)
    end
  end

  local function toggleRow(labelFn, flipFn)
    local row = { keepOpen = true }
    local function sync() row.label = labelFn() end
    sync()
    row.onSelect = function()
      flipFn()
      sync()
    end
    return row
  end

  local function pushNumberPicker(game, opts)
    opts = opts or {}
    local minV = opts.min or 0
    local maxV = opts.max or 100
    local step = opts.step or 1
    local big = opts.bigStep or 10
    local value = math.max(minV, math.min(maxV, opts.value or minV))
    local title = opts.title or "VALUE"
    game.stack:push({
      isOpaque = false,
      update = function(self)
        local input = game.input
        if input:wasPressed("b") then
          game.stack:pop()
          if opts.onCancel then opts.onCancel() end
        elseif input:wasPressed("up") then
          value = math.min(maxV, value + step)
        elseif input:wasPressed("down") then
          value = math.max(minV, value - step)
        elseif input:wasPressed("right") then
          value = math.min(maxV, value + big)
        elseif input:wasPressed("left") then
          value = math.max(minV, value - big)
        elseif input:wasPressed("a") then
          game.stack:pop()
          if opts.onConfirm then opts.onConfirm(value) end
        end
      end,
      draw = function()
        Font.drawBox(1, 2, 18, 10)
        Font.draw(title, 24, 24)
        Font.draw(string.format("%d", value), 24, 48)
        Font.draw("UP/DN  L/R", 16, 72)
        Font.draw("A:OK  B:BACK", 16, 88)
      end,
    })
  end

  ------------------------------------------------------------------
  -- Actions
  ------------------------------------------------------------------
  local function warpToMap(game, mapId, x, y, spawnId)
    local world = worldOf(game)
    if not world then return end
    clearUi(game)
    safe(game, function()
      if isGen2() then
        if spawnId and world.flyTo and world:flyTo(spawnId) then return end
        if world.warpToMapId then
          world:warpToMapId(mapId, x, y, "down")
        elseif world.setMap then
          world:setMap(mapId, x, y, "down")
        end
      elseif world.setMap then
        world:setMap(mapId, x, y, "down")
      end
    end, "WARP FAILED!")
  end

  local function addMon(game, speciesId, level, quiet)
    local Party = require("src.pokemon.Party")
    local Boxes = require("src.pokemon.Boxes")
    local save = game.save
    save.party = save.party or {}
    local mon
    if isGen2() then
      local Mon = require("src.battle.gen2.Mon")
      mon = Mon.new(game.data, speciesId, level)
      if mon then Mon.stampOT(save, mon) end
    else
      local Pokemon = require("src.pokemon.Pokemon")
      mon = Pokemon.new(game.data, speciesId, level)
      pcall(function()
        require("src.battle.BattleState").stampOT(save, mon)
      end)
    end
    if not mon then
      if not quiet then showMsg(game, "COULD NOT CREATE\nPOKeMON!") end
      return
    end
    local name = mon.nickname or mon.name or speciesId
    if Party.add(save.party, mon) then
      if not quiet then
        showMsg(game, string.format("%s (LV.%d)\nTO PARTY!", name, level))
      end
    else
      local box = Boxes.deposit(save, mon)
      if not quiet then
        showMsg(game, string.format("%s (LV.%d)\nTO BOX %s!", name, level, tostring(box or "?")))
      end
    end
    local dex = save.pokedex
    if dex then
      dex.seen = dex.seen or {}
      dex.seen[speciesId] = true
      if isGen2() then
        dex.caught = dex.caught or {}
        dex.caught[speciesId] = true
      else
        dex.owned = dex.owned or {}
        dex.owned[speciesId] = true
      end
    end
  end

  local function healParty(game)
    local save = game.save
    if not (save and save.party) then return end
    if isGen2() then
      local world = worldOf(game)
      if world and world.healParty then
        world:healParty()
        return
      end
      for _, mon in ipairs(save.party) do
        mon.hp = mon.maxHp or mon.hp
        mon.status = nil
        for _, move in ipairs(mon.moves or {}) do
          if type(move) == "table" then move.pp = move.maxPp or move.pp end
        end
      end
    else
      local Pokemon = require("src.pokemon.Pokemon")
      for _, mon in ipairs(save.party) do Pokemon.heal(mon) end
    end
  end

  local function forceAddItem(game, itemId, count)
    local save = game.save
    save.inventory = save.inventory or {}
    local Bag = require("src.inventory.Bag")
    local have = save.inventory[itemId] or 0
    local want = math.min(99, math.max(0, count or 1))
    if want <= 0 then
      save.inventory[itemId] = nil
      Bag.order(save)
      return
    end
    save.inventory[itemId] = want
    if have == 0 then
      local order = Bag.order(save)
      local found = false
      for _, id in ipairs(order) do
        if id == itemId then found = true; break end
      end
      if not found then order[#order + 1] = itemId end
    end
  end

  local function fillBag(game, qty)
    for _, item in ipairs(itemList(game)) do
      forceAddItem(game, item.id, qty)
    end
  end

  local function emptyBag(game)
    local save = game.save
    save.inventory = save.inventory or {}
    local Bag = require("src.inventory.Bag")
    for id in pairs(save.inventory) do
      if not Bag.isBadge(id) then save.inventory[id] = nil end
    end
    save.bagOrder = {}
    Bag.order(save)
  end

  local function giveBadges(game, on)
    local save = game.save
    if isGen2() then
      local FieldMoves = require("src.world.gen2.FieldMoves")
      save.player = save.player or {}
      save.player.badges = save.player.badges or {}
      save.player.kantoBadges = save.player.kantoBadges or {}
      for _, name in ipairs(FieldMoves.JOHTO_BADGES or {}) do
        save.player.badges[name] = on or nil
      end
      for _, name in ipairs(FieldMoves.KANTO_BADGES or {}) do
        save.player.kantoBadges[name] = on or nil
      end
    else
      save.inventory = save.inventory or {}
      local badges = {
        "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
        "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
      }
      for _, b in ipairs(badges) do
        save.inventory[b] = on and 1 or nil
      end
    end
  end

  local function completeDex(game)
    local save = game.save
    save.pokedex = save.pokedex or {}
    save.pokedex.seen = save.pokedex.seen or {}
    if isGen2() then
      save.pokedex.caught = save.pokedex.caught or {}
    else
      save.pokedex.owned = save.pokedex.owned or {}
    end
    for _, sp in ipairs(speciesList(game)) do
      save.pokedex.seen[sp.id] = true
      if isGen2() then
        save.pokedex.caught[sp.id] = true
      else
        save.pokedex.owned[sp.id] = true
      end
    end
    if isGen2() then
      local world = worldOf(game)
      if world and world.setEngineFlag then
        world:setEngineFlag(11, true) -- ENGINE_POKEDEX
      end
    end
  end

  local function fillBoxes(game)
    local Boxes = require("src.pokemon.Boxes")
    local list = speciesList(game)
    local n = 0
    for _, sp in ipairs(list) do
      local mon
      if isGen2() then
        local Mon = require("src.battle.gen2.Mon")
        mon = Mon.new(game.data, sp.id, 50)
        if mon then Mon.stampOT(game.save, mon) end
      else
        local Pokemon = require("src.pokemon.Pokemon")
        mon = Pokemon.new(game.data, sp.id, 50)
      end
      if mon then
        if not Boxes.deposit(game.save, mon) then break end
        n = n + 1
      end
    end
    showMsg(game, string.format("FILLED BOXES\n%d MONS.", n))
  end

  local function clearBoxes(game)
    local save = game.save
    save.boxes = {}
    showMsg(game, "BOXES CLEARED.")
  end

  local function demoParty(game)
    local ids = isGen2()
      and { "CYNDAQUIL", "TOTODILE", "CHIKORITA", "PIKACHU", "EEVEE", "GYARADOS" }
      or { "CHARMANDER", "SQUIRTLE", "BULBASAUR", "PIKACHU", "EEVEE", "GYARADOS" }
    game.save.party = {}
    for _, id in ipairs(ids) do
      addMon(game, id, 50, true)
    end
  end

  local function testWildBattle(game, speciesId, level)
    local world = worldOf(game)
    clearUi(game)
    if isGen2() then
      if not world or not world.startBattle then
        showMsg(game, "NO BATTLE.")
        return
      end
      local Mon = require("src.battle.gen2.Mon")
      local mon = Mon.new(game.data, speciesId, level)
      if not mon then
        showMsg(game, "COULD NOT CREATE\nPOKeMON!")
        return
      end
      world:startBattle({ wild = mon })
    else
      local BattleState = require("src.battle.BattleState")
      local startWild = BattleState["new" .. "Wild"]
      local battle = startWild(game, speciesId, level)
      if world and world.pushBattle then
        world:pushBattle(battle)
      else
        game.stack:push(battle)
      end
    end
  end

  local function openPc(game)
    local world = worldOf(game)
    if isGen2() and world and world.openPc then
      world:openPc()
      return
    end
    local Screens = require("src.ui.Screens")
    pcall(Screens.push, game, isGen2() and "Gen2CenterPcMenu" or "BoxMenu")
  end

  local function renamePlayer(game)
    local Screens = require("src.ui.Screens")
    local save = game.save
    save.player = save.player or {}
    if isGen2() then
      -- Gen2NamingScreen:accept does not pop; World:renameMon / nameRival do.
      local finished = false
      local function finish(name)
        if finished then return end
        finished = true
        game.stack:pop()
        if name and name ~= "" then save.player.name = name end
      end
      Screens.push(game, "Gen2NamingScreen", {
        type = "player",
        initial = save.player.name or "",
        menuGfx = game.data and game.data.gen2MenuGfx,
        onDone = finish,
        onCancel = function() finish(nil) end,
      })
    else
      Screens.push(game, "NamingScreen", {
        title = "YOUR NAME?",
        default = save.player.name or "RED",
        onDone = function(name)
          if name and name ~= "" then save.player.name = name end
        end,
      })
    end
  end

  local function setMoney(game, n)
    local save = game.save
    if isGen2() then
      save.player = save.player or {}
      save.player.money = n
    else
      save.money = n
    end
  end

  local function currentMoney(game)
    local save = game.save
    if isGen2() then
      return (save.player and save.player.money) or 0
    end
    return save.money or 0
  end

  local function setCoins(game, n)
    local CoinCase = require("src.core.gen2.CoinCase")
    local save = game.save
    save.player = save.player or {}
    save.player.coins = math.max(0, math.min(CoinCase.MAX_COINS, n))
  end

  local function fillPocket(game, pocket, qty)
    local n = 0
    for _, it in ipairs(itemList(game)) do
      local def = game.data.items and game.data.items[it.id]
      if def and (def.pocket == pocket or tostring(it.id):find("^" .. pocket)) then
        forceAddItem(game, it.id, qty)
        n = n + 1
      end
    end
    return n
  end

  local function seenDex(game, caughtToo)
    completeDex(game)
    if caughtToo then return end
    local dex = game.save.pokedex
    if not dex then return end
    if isGen2() then dex.caught = {} else dex.owned = {} end
  end

  local function setEngineFlag(game, id, on)
    local world = worldOf(game)
    if world and world.setEngineFlag then
      world:setEngineFlag(id, on and true or false)
    end
    local save = game.save
    save.engineFlags = save.engineFlags or {}
    save.engineFlags[id] = on and true or nil
  end

  local function givePokedex(game)
    local save = game.save
    save.pokedex = save.pokedex or { seen = {}, caught = {}, owned = {} }
    if isGen2() then
      setEngineFlag(game, 11, true) -- ENGINE_POKEDEX
    else
      save.pokedexReceived = true
    end
  end

  -- ENGINE_RADIO/MAP/PHONE/EXPN_CARD (0-3) plus ENGINE_POKEGEAR (4).
  local function givePokegear(game)
    if not isGen2() then return end
    local save = game.save
    setEngineFlag(game, 0, true)
    setEngineFlag(game, 1, true)
    setEngineFlag(game, 2, true)
    setEngineFlag(game, 3, true)
    setEngineFlag(game, 4, true)
    save.pokegearFlags = {
      radio = true, map = true, phone = true, expn = true,
    }
    save.pokegearReceived = true
  end

  local function testTrainerBattle(game, classKey, member)
    local world = worldOf(game)
    clearUi(game)
    if isGen2() then
      if not (world and world.startScriptedBattle) then
        showMsg(game, "NO BATTLE.")
        return
      end
      local Trainers = require("src.world.gen2.Trainers")
      local record = Trainers.lookup(game.data.trainers, classKey, member)
      if not record then
        showMsg(game, "NO TRAINER.")
        return
      end
      world:startScriptedBattle(record)
      return
    end
    local BattleState = require("src.battle.BattleState")
    local startTrainer = BattleState["new" .. "Trainer"]
    local battle = startTrainer(game, classKey, member)
    if world and world.pushBattle then
      world:pushBattle(battle)
    else
      game.stack:push(battle)
    end
  end

  ------------------------------------------------------------------
  -- Live map editor (connections, warps, blocks)
  ------------------------------------------------------------------
  local function loadOwn(name)
    local path = (mod.path or "mods/Debug") .. "/" .. name
    local chunk
    if love and love.filesystem and love.filesystem.load then
      local ok, result = pcall(love.filesystem.load, path)
      if ok then chunk = result end
    end
    if not chunk then
      local ok, result = pcall(loadfile, path)
      if ok then chunk = result end
    end
    if not chunk then
      error("[DebugMenu] missing " .. path)
    end
    return chunk()
  end

  local editorHost = {
    mod = mod,
    isGen2 = isGen2,
    worldOf = worldOf,
    mapsTable = mapsTable,
    sortedIds = sortedIds,
    pushList = pushList,
    pushNumberPicker = pushNumberPicker,
    showMsg = showMsg,
    landingCell = landingCell,
    warpToMap = warpToMap,
    toggleRow = toggleRow,
    liveGame = liveGame,
    hudOn = function() return overlayOn end,
    setHudOn = function(on) overlayOn = on and true or false end,
  }
  local MapEdit = loadOwn("map_editor.lua")(editorHost)
  local BattleEdit = loadOwn("battle_editor.lua")(editorHost)

  ------------------------------------------------------------------
  -- Essentials-style nested debug menus
  ------------------------------------------------------------------
  local daytimeIndex = 1
  local daytimeOptions = {
    { label = "SYNC", hour = nil },
    { label = "MORN", hour = 8 },
    { label = "DAY", hour = 13 },
    { label = "NITE", hour = 21 },
  }

  local function applyTime(game, opt)
    if isGen2() then
      local world = worldOf(game)
      if world then world.clockHour = opt.hour end
      return
    end
    _G.YELLOW_CRYSTAL_TIME_OVERRIDE = opt.hour
  end

  local function openSpeciesThen(game, title, onPick)
    local items = {}
    for _, sp in ipairs(speciesList(game)) do
      items[#items + 1] = {
        label = string.format("%03d %s", sp.dex, sp.name),
        onSelect = function()
          pushNumberPicker(game, {
            title = title or "LEVEL",
            min = 1, max = 100, value = 50,
            onConfirm = function(level) onPick(sp.id, level, sp.name) end,
          })
        end,
      }
    end
    pushList(game, items, {
      maxVisible = 8,
      emptyMsg = "NO POKeMON DATA.",
    })
  end

  local function openItemThen(game)
    local items = {}
    for _, it in ipairs(itemList(game)) do
      items[#items + 1] = {
        label = it.name,
        onSelect = function()
          pushNumberPicker(game, {
            title = it.name,
            min = 1, max = 99, value = 1,
            onConfirm = function(qty)
              forceAddItem(game, it.id, qty)
              showMsg(game, string.format("GOT %s x%d", it.name, qty))
            end,
          })
        end,
      }
    end
    pushList(game, items, {
      maxVisible = 8,
      emptyMsg = "NO ITEMS.",
    })
  end

  local function resetMapTrainers(game)
    local world = worldOf(game)
    local n = 0
    if isGen2() and world and world.events then
      local def = world.map and world.map.def
      for _, obj in ipairs((def and def.objects) or {}) do
        local ev = obj.trainer and obj.trainer.event
        if ev then
          world.events:set(ev, false)
          n = n + 1
        end
      end
    end
    local save = game.save
    if save and save.defeatedTrainers then
      local mapId = world and world.map and world.map.id
      for key in pairs(save.defeatedTrainers) do
        if not mapId or tostring(key):find(mapId, 1, true) then
          save.defeatedTrainers[key] = nil
          n = n + 1
        end
      end
    end
    showMsg(game, string.format("RESET %d.", n))
  end

  local function category(game, label, rows)
    return {
      label = label,
      keepOpen = true,
      onSelect = function()
        pushList(game, rows, { emptyMsg = "NO ENTRIES." })
      end,
    }
  end

  local function openTrainerThen(game)
    local rows = {}
    if isGen2() then
      -- Class display names repeat (LEADER x16, ELITE FOUR x4). Group by
      -- that name so one "LEADER..." row lists every gym leader.
      local classes = game.data and game.data.trainers and game.data.trainers.classes
      local groups, titles = {}, {}
      for _, id in ipairs(sortedIds(classes, function(_, c)
        return type(c) == "table" and type(c.trainers) == "table"
      end)) do
        local class = classes[id]
        local title = class.name or id
        if not groups[title] then
          groups[title] = {}
          titles[#titles + 1] = title
        end
        for i, row in ipairs(class.trainers or {}) do
          groups[title][#groups[title] + 1] = {
            label = row.name or class.id or tostring(i),
            classIndex = class.index,
            member = i,
          }
        end
      end
      table.sort(titles)
      for _, title in ipairs(titles) do
        local members = groups[title]
        rows[#rows + 1] = {
          label = title .. "...",
          keepOpen = true,
          onSelect = function()
            local list, used = {}, {}
            for _, entry in ipairs(members) do
              local label = entry.label
              if used[label] then
                label = label .. " " .. tostring(entry.member)
              end
              used[label] = true
              local classIndex, member = entry.classIndex, entry.member
              list[#list + 1] = {
                label = label,
                onSelect = function()
                  testTrainerBattle(game, classIndex, member)
                end,
              }
            end
            table.sort(list, function(a, b) return a.label < b.label end)
            pushList(game, list, { emptyMsg = "NO TRAINERS." })
          end,
        }
      end
    else
      local trainers = game.data and game.data.trainers
      local ids = sortedIds(trainers, function(_, t)
        return type(t) == "table" and type(t.parties) == "table"
      end)
      for _, id in ipairs(ids) do
        local trainer = trainers[id]
        local classId = id
        rows[#rows + 1] = {
          label = (trainer.name or id) .. "...",
          keepOpen = true,
          onSelect = function()
            local parties = {}
            for i in ipairs(trainer.parties or {}) do
              local partyIndex = i
              parties[#parties + 1] = {
                label = "PARTY " .. tostring(i),
                onSelect = function()
                  testTrainerBattle(game, classId, partyIndex)
                end,
              }
            end
            pushList(game, parties, { emptyMsg = "NO PARTIES." })
          end,
        }
      end
    end
    pushList(game, rows, { emptyMsg = "NO TRAINERS." })
  end

  openDebugMenu = function(game)
    if not (game and game.stack and game.save) then return end
    patchWorld(game)
    local world = worldOf(game)
    local save = game.save

    local timeItem = {
      keepOpen = true,
      label = "Time: " .. daytimeOptions[daytimeIndex].label,
    }
    timeItem.onSelect = function()
      daytimeIndex = (daytimeIndex % #daytimeOptions) + 1
      local opt = daytimeOptions[daytimeIndex]
      timeItem.label = "Time: " .. opt.label
      applyTime(game, opt)
    end

    local field = {
      {
        label = "Warp to map...",
        keepOpen = true,
        onSelect = function()
          local maps = mapsTable(game)
          local rows = {}
          for _, id in ipairs(sortedIds(maps)) do
            rows[#rows + 1] = {
              label = id,
              onSelect = function()
                local x, y = landingCell(maps[id])
                warpToMap(game, id, x, y)
              end,
            }
          end
          pushList(game, rows, { emptyMsg = "NO MAPS." })
        end,
      },
      {
        label = "Use PC",
        onSelect = function() openPc(game) end,
      },
      {
        label = "Heal party",
        onSelect = function()
          healParty(game)
          showMsg(game, "PARTY HEALED.")
        end,
      },
      toggleRow(function()
        return overlayOn and "HUD: ON" or "HUD: OFF"
      end, function()
        overlayOn = not overlayOn
      end),
      toggleRow(function()
        return noEncounters and "Encounters: OFF" or "Encounters: ON"
      end, function()
        noEncounters = not noEncounters
      end),
      timeItem,
      {
        label = "Reset trainers",
        onSelect = function() resetMapTrainers(game) end,
      },
    }
    if isGen2() and world then
      field[#field + 1] = {
        label = "Map flags...",
        keepOpen = true,
        onSelect = function()
          local flags, seen = {}, {}
          local function addFlag(id, name)
            if id == nil or seen[id] then return end
            seen[id] = true
            flags[#flags + 1] = toggleRow(function()
              local on = world.events and world.events:get(id)
              return string.format("%s %s [%s]", on and "*" or " ", tostring(id), name)
            end, function()
              if world.events then
                world.events:set(id, not world.events:get(id))
              end
            end)
          end
          local def = world.map and world.map.def
          for _, obj in ipairs((def and def.objects) or {}) do
            if obj.eventFlag then addFlag(obj.eventFlag, obj.name or "obj") end
            if obj.trainer and obj.trainer.event then
              addFlag(obj.trainer.event, "trainer")
            end
          end
          pushList(game, flags, { emptyMsg = "NO FLAGS ON MAP." })
        end,
      }
      field[#field + 1] = {
        label = "Ready Day-Care egg",
        onSelect = function()
          local Breeding = require("src.core.gen2.Breeding")
          local dc = Breeding.dayCare(save)
          if not (dc.man.mon and dc.lady.mon) then
            showMsg(game, "DAY CARE EMPTY.")
            return
          end
          Breeding.initBreeding(game.data, save)
          dc.hasEgg = true
          showMsg(game, "EGG READY.")
        end,
      }
      field[#field + 1] = {
        label = "Hatch party eggs",
        onSelect = function()
          local n = 0
          for _, mon in ipairs(save.party or {}) do
            if mon.isEgg then
              mon.eggSteps = 1
              n = n + 1
            end
          end
          showMsg(game, n > 0 and string.format("%d EGG(S) READY.", n) or "NO EGGS.")
        end,
      }
    end

    local pokemon = {
      {
        label = "Heal party",
        onSelect = function()
          healParty(game)
          showMsg(game, "PARTY HEALED.")
        end,
      },
      {
        label = "Add Pokemon...",
        keepOpen = true,
        onSelect = function()
          openSpeciesThen(game, "LEVEL", function(id, level)
            addMon(game, id, level)
          end)
        end,
      },
      {
        label = "Demo party",
        onSelect = function()
          demoParty(game)
          showMsg(game, "DEMO PARTY SET.")
        end,
      },
      {
        label = "Fill boxes",
        onSelect = function() fillBoxes(game) end,
      },
      {
        label = "Clear boxes",
        onSelect = function() clearBoxes(game) end,
      },
    }

    local battle = {
      {
        label = "Pic positions...",
        keepOpen = true,
        onSelect = function() BattleEdit.openMenu(game) end,
      },
      {
        label = "Test wild battle...",
        keepOpen = true,
        onSelect = function()
          openSpeciesThen(game, "LEVEL", function(id, level)
            testWildBattle(game, id, level)
          end)
        end,
      },
      {
        label = "Test trainer battle...",
        keepOpen = true,
        onSelect = function() openTrainerThen(game) end,
      },
    }

    local itemsMenu = {
      {
        label = "Add item...",
        keepOpen = true,
        onSelect = function() openItemThen(game) end,
      },
      {
        label = "Fill bag",
        onSelect = function()
          fillBag(game, 99)
          showMsg(game, "BAG FILLED.")
        end,
      },
      {
        label = "Empty bag",
        onSelect = function()
          emptyBag(game)
          showMsg(game, "BAG EMPTIED.")
        end,
      },
      {
        label = "Give TMs/HMs",
        onSelect = function()
          local n = fillPocket(game, "TM_HM", 1)
          if n == 0 then n = fillPocket(game, "TM_", 1) end
          showMsg(game, string.format("GAVE %d TMs.", n))
        end,
      },
      {
        label = "Give key items",
        onSelect = function()
          local n = fillPocket(game, "KEY_ITEM", 1)
          showMsg(game, string.format("GAVE %d KEY ITEMS.", n))
        end,
      },
    }

    local player = {
      {
        label = "Set money...",
        keepOpen = true,
        onSelect = function()
          pushNumberPicker(game, {
            title = "MONEY",
            min = 0, max = 999999, value = currentMoney(game),
            step = 100, bigStep = 10000,
            onConfirm = function(n)
              setMoney(game, n)
              showMsg(game, "MONEY SET.")
            end,
          })
        end,
      },
      {
        label = "Give all badges",
        onSelect = function()
          giveBadges(game, true)
          showMsg(game, "ALL BADGES.")
        end,
      },
      {
        label = "Take all badges",
        onSelect = function()
          giveBadges(game, false)
          showMsg(game, "BADGES CLEARED.")
        end,
      },
      {
        label = "Give Pokedex",
        onSelect = function()
          givePokedex(game)
          showMsg(game, "GOT POKeDEX.")
        end,
      },
      {
        label = "Give Pokegear",
        onSelect = function()
          givePokegear(game)
          showMsg(game, "POKeGEAR UNLOCKED.")
        end,
      },
      {
        label = "Complete Pokedex",
        onSelect = function()
          givePokedex(game)
          completeDex(game)
          showMsg(game, "DEX COMPLETE.")
        end,
      },
      {
        label = "Seen all species",
        onSelect = function()
          givePokedex(game)
          seenDex(game, false)
          showMsg(game, "ALL SEEN.")
        end,
      },
      {
        label = "Rename player...",
        onSelect = function() renamePlayer(game) end,
      },
    }
    if isGen2() then
      player[#player + 1] = {
        label = "Set coins...",
        keepOpen = true,
        onSelect = function()
          local CoinCase = require("src.core.gen2.CoinCase")
          pushNumberPicker(game, {
            title = "COINS",
            min = 0, max = CoinCase.MAX_COINS,
            value = CoinCase.coins(save),
            step = 10, bigStep = 100,
            onConfirm = function(n)
              setCoins(game, n)
              showMsg(game, "COINS SET.")
            end,
          })
        end,
      }
      player[#player + 1] = {
        label = "Badges...",
        keepOpen = true,
        onSelect = function()
          local FieldMoves = require("src.world.gen2.FieldMoves")
          save.player = save.player or {}
          save.player.badges = save.player.badges or {}
          save.player.kantoBadges = save.player.kantoBadges or {}
          local rows = {}
          local function addStore(store, names)
            for _, name in ipairs(names) do
              rows[#rows + 1] = toggleRow(function()
                return (save.player[store][name] and "* " or "  ") .. name
              end, function()
                local bag = save.player[store]
                bag[name] = (not bag[name]) or nil
              end)
            end
          end
          addStore("badges", FieldMoves.JOHTO_BADGES)
          addStore("kantoBadges", FieldMoves.KANTO_BADGES)
          pushList(game, rows)
        end,
      }
      player[#player + 1] = {
        label = "Phone numbers...",
        keepOpen = true,
        onSelect = function()
          local Phone = require("src.core.gen2.Phone")
          local trainers = game.data and game.data.trainers
          local ids = {}
          for id = 1, Phone.NUM_PHONE_CONTACTS do
            local row = Phone.CONTACTS[id]
            if type(row) == "table" and (row.class or (row.number or 0) ~= 0) then
              ids[#ids + 1] = id
            end
          end
          local function putAll()
            local state = Phone.state(save)
            local list = {}
            for _, id in ipairs(ids) do
              list[#list + 1] = id
            end
            state.list = list
            Phone.mirror(save, state)
            return #list
          end
          local function toggle(id)
            local ok, why = Phone.addContact(save, id)
            if ok then return "added" end
            if why == "already" then
              Phone.removeContact(save, id)
              return "removed"
            end
            if why == "full" then
              local state = Phone.state(save)
              state.list[#state.list + 1] = id
              Phone.mirror(save, state)
              return "added"
            end
            return why or "failed"
          end
          local rows = {
            {
              label = "Fill phone list",
              onSelect = function()
                showMsg(game, string.format("ADDED %d.", putAll()))
              end,
            },
          }
          for _, id in ipairs(ids) do
            local name = Phone.contactName(id, trainers) or tostring(id)
            local contactId = id
            rows[#rows + 1] = {
              label = name,
              onSelect = function()
                local result = toggle(contactId)
                if result == "added" then
                  showMsg(game, "ADDED " .. name .. ".")
                elseif result == "removed" then
                  showMsg(game, "REMOVED " .. name .. ".")
                else
                  showMsg(game, "PHONE FAILED.")
                end
              end,
            }
          end
          pushList(game, rows)
        end,
      }
    end

    pushList(game, {
      category(game, "Field options...", field),
      {
        label = "Map options...",
        keepOpen = true,
        onSelect = function() MapEdit.openMenu(game) end,
      },
      category(game, "Pokemon options...", pokemon),
      category(game, "Battle options...", battle),
      category(game, "Item options...", itemsMenu),
      category(game, "Player options...", player),
    }, {
      onCancel = function()
        if isGen2() then return end
        pcall(function()
          require("src.ui.Screens").push(game, "StartMenu")
        end)
      end,
    })
  end

  ------------------------------------------------------------------
  -- Party Pokémon debug (field submenu DEBUG row)
  ------------------------------------------------------------------
  local function copyTable(t)
    if type(t) ~= "table" then return t end
    local n = {}
    for k, v in pairs(t) do n[k] = copyTable(v) end
    return n
  end

  local function monName(game, mon)
    if mon.nickname and mon.nickname ~= "" then return mon.nickname end
    if mon.name and mon.name ~= "" then return mon.name end
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
    return (def and def.name) or mon.species or "?"
  end

  local function dvHp(dvs)
    local function bit(v) return (v or 0) % 2 end
    return bit(dvs.attack) * 8 + bit(dvs.defense) * 4
      + bit(dvs.speed) * 2 + bit(dvs.special)
  end

  local function randomDvs()
    local rng = love.math.random
    return {
      attack = rng(0, 15), defense = rng(0, 15),
      speed = rng(0, 15), special = rng(0, 15),
    }
  end

  local function dvsAreShiny(dvs)
    if type(dvs) ~= "table" then return false end
    if (dvs.speed or 0) ~= 10 or (dvs.defense or 0) ~= 10
        or (dvs.special or 0) ~= 10 then
      return false
    end
    local attack = dvs.attack or 0
    return attack % 4 == 2 or attack % 4 == 3
  end

  local function goldGender(def, dvs)
    local ratio = def and def.genderRatio
    if not ratio then return "unknown" end
    if ratio == 0xff then return "unknown" end
    local threshold = math.floor(ratio / 16)
    return ((dvs and dvs.attack or 0) < threshold) and "female" or "male"
  end

  local function restat(game, mon)
    local data = game.data
    local def = data and data.pokemon and data.pokemon[mon.species]
    if not def then return end
    local level = tonumber(mon.level) or 1
    local statExp = type(mon.statExp) == "table" and mon.statExp or nil
    if isGen2() then
      local G2Mon = require("src.battle.gen2.Mon")
      if type(mon.dvs) ~= "table" then mon.dvs = randomDvs() end
      mon.dvs.hp = dvHp(mon.dvs)
      if def.baseStats and G2Mon.stats then
        mon.stats = G2Mon.stats(def.baseStats, mon.dvs, level, statExp)
        mon.maxHp = mon.stats.hp
        mon.hp = math.max(0, math.min(tonumber(mon.hp) or mon.maxHp, mon.maxHp))
      end
      pcall(function()
        local growth = G2Mon.growthFor(data, def.growthRate)
        if growth then
          mon.experience = G2Mon.experienceForLevel(growth, level)
        end
      end)
      mon.shiny = dvsAreShiny(mon.dvs)
      mon.gender = goldGender(def, mon.dvs)
      pcall(function()
        local Unown = require("src.core.gen2.Unown")
        if mon.species == Unown.SPECIES then
          mon.unownLetter = Unown.letterFromDVs(mon.dvs)
        end
      end)
    else
      local Stats = require("src.pokemon.Stats")
      local Growth = require("src.pokemon.Growth")
      if type(mon.dvs) ~= "table" then mon.dvs = Stats.randomDVs() end
      mon.stats = Stats.calc(def, level, mon.dvs, statExp)
      mon.hp = math.max(0, math.min(tonumber(mon.hp) or mon.stats.hp,
                                   mon.stats.hp))
      pcall(function()
        mon.exp = Growth.expForLevel(def.growthRate, level)
      end)
    end
  end

  local function healOne(game, mon)
    if isGen2() then
      mon.hp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
      mon.status = nil
      for _, move in ipairs(mon.moves or {}) do
        if type(move) == "table" then move.pp = move.maxPp or move.pp end
      end
    else
      require("src.pokemon.Pokemon").heal(mon)
    end
  end

  local function monIsShiny(mon)
    return type(mon) == "table"
      and (dvsAreShiny(mon.dvs) or mon.shiny == true)
  end

  -- Prefer the save.party row the party list is drawing, not a copy.
  local function partyMon(game, mon)
    local party = game and game.save and game.save.party
    if type(party) ~= "table" then return mon end
    for _, m in ipairs(party) do
      if m == mon then return m end
    end
    local slot = tonumber(game.partyMenuCursor)
    if slot and party[slot] then return party[slot] end
    return party[1] or mon
  end

  -- pret/pokegold CheckShininess + ATKDEFDV_SHINY $EA / SPDSPCDV_SHINY $AA.
  local function setShiny(game, mon, want)
    mon = partyMon(game, mon)
    if type(mon) ~= "table" then return end
    want = want and true or false
    if want then
      mon.dvs = {
        attack = 14, defense = 10, speed = 10, special = 10, hp = 0,
      }
    else
      local src = type(mon.dvs) == "table" and mon.dvs or randomDvs()
      mon.dvs = {
        attack = src.attack or 0,
        defense = (src.defense == 10) and 11 or (src.defense or 0),
        speed = src.speed or 0,
        special = src.special or 0,
      }
      if dvsAreShiny(mon.dvs) then mon.dvs.defense = 11 end
    end
    mon.dvs.hp = dvHp(mon.dvs)
    mon.shiny = want
    pcall(restat, game, mon)
    mon.shiny = want
    local cap = mon.maxHp or (mon.stats and mon.stats.hp)
    if cap then mon.hp = cap end
  end

  local function moveList(game)
    local moves = game.data and game.data.moves
    local ids = sortedIds(moves, function(_, def)
      return type(def) == "table"
    end)
    local out = {}
    for _, id in ipairs(ids) do
      local def = moves[id]
      out[#out + 1] = { id = id, name = (def and def.name) or id }
    end
    return out
  end

  local function knowsMove(mon, moveId)
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == moveId then return true end
    end
    return false
  end

  local function writeMove(game, mon, moveId, slot)
    local def = game.data and game.data.moves and game.data.moves[moveId]
    local pp = def and def.pp or 0
    local entry = { id = moveId, pp = pp, maxPp = pp }
    if slot then
      mon.moves[slot] = entry
    else
      mon.moves = mon.moves or {}
      mon.moves[#mon.moves + 1] = entry
    end
  end

  local function setSpecies(game, mon, speciesId)
    local def = game.data and game.data.pokemon and game.data.pokemon[speciesId]
    if not def then return end
    local oldName = mon.name or mon.species
    mon.species = speciesId
    mon.name = def.name or speciesId
    mon.types = def.types
    if not mon.nickname or mon.nickname == "" or mon.nickname == oldName then
      mon.nickname = mon.name
    end
    pcall(restat, game, mon)
  end

  local function setGender(game, mon, want)
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
    local ratio = def and def.genderRatio
    if not ratio or ratio == 0xff then
      showMsg(game, "NO GENDER.")
      return
    end
    local threshold = math.floor(ratio / 16)
    if type(mon.dvs) ~= "table" then mon.dvs = randomDvs() end
    if want == "female" then
      if threshold <= 0 then
        showMsg(game, "ALWAYS MALE.")
        return
      end
      mon.dvs.attack = math.max(0, threshold - 1)
    else
      mon.dvs.attack = math.min(15, math.max(threshold, 0))
    end
    mon.dvs.hp = dvHp(mon.dvs)
    pcall(restat, game, mon)
  end

  local function resetMoves(game, mon)
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
    mon.moves = {}
    if isGen2() then
      local G2Mon = require("src.battle.gen2.Mon")
      mon.moves = G2Mon.movesAtLevel(def, mon.level or 1, game.data.moves)
      return
    end
    local Pokemon = require("src.pokemon.Pokemon")
    for _, id in ipairs(Pokemon.movesAtLevel(def, mon.level or 1) or {}) do
      writeMove(game, mon, id)
    end
  end

  local function renameMon(game, mon)
    local world = worldOf(game)
    if isGen2() and world and world.renameMon then
      world:renameMon(mon, function(newName)
        if newName and newName ~= "" then mon.nickname = newName end
      end)
      return
    end
    local Screens = require("src.ui.Screens")
    Screens.push(game, "NamingScreen", {
      title = "NICKNAME?",
      default = mon.nickname or mon.name or "",
      onDone = function(newName)
        if newName and newName ~= "" then mon.nickname = newName end
      end,
    })
  end

  local function statusChoices()
    if isGen2() then
      return {
        { label = "OK", value = nil },
        { label = "SLP", value = "sleep" },
        { label = "PSN", value = "poison" },
        { label = "BRN", value = "burn" },
        { label = "FRZ", value = "freeze" },
        { label = "PAR", value = "paralyze" },
      }
    end
    return {
      { label = "OK", value = nil },
      { label = "SLP", value = "SLP" },
      { label = "PSN", value = "PSN" },
      { label = "BRN", value = "BRN" },
      { label = "FRZ", value = "FRZ" },
      { label = "PAR", value = "PAR" },
    }
  end

  local function statusLabel(mon)
    local cur = mon.status
    if not cur then return "OK" end
    for _, row in ipairs(statusChoices()) do
      if row.value == cur then return row.label end
    end
    return tostring(cur)
  end

  local function maxHpOf(mon)
    return mon.maxHp or (mon.stats and mon.stats.hp) or 1
  end

  local function openMonDebug(game, mon)
    if not (game and mon) then return end
    local name = monName(game, mon)
    local items = {}

    items[#items + 1] = {
      label = "Heal",
      onSelect = function()
        healOne(game, mon)
        showMsg(game, name .. "\nHEALED!")
      end,
    }
    items[#items + 1] = {
      label = string.format("Level: %d...", mon.level or 1),
      onSelect = function()
        pushNumberPicker(game, {
          title = "LEVEL",
          min = 1, max = 100, value = mon.level or 1,
          onConfirm = function(lv)
            mon.level = lv
            restat(game, mon)
            showMsg(game, string.format("%s\nIS NOW LV.%d!", name, lv))
          end,
        })
      end,
    }
    items[#items + 1] = toggleRow(
      function()
        local live = partyMon(game, mon)
        return "Shiny: " .. (monIsShiny(live) and "ON" or "OFF")
      end,
      function()
        local live = partyMon(game, mon)
        setShiny(game, live, not monIsShiny(live))
      end)
    items[#items + 1] = {
      label = "Species...",
      keepOpen = true,
      onSelect = function()
        local rows = {}
        for _, sp in ipairs(speciesList(game)) do
          rows[#rows + 1] = {
            label = string.format("%03d %s", sp.dex, sp.name),
            onSelect = function()
              setSpecies(game, mon, sp.id)
              showMsg(game, "NOW " .. sp.name .. "!")
            end,
          }
        end
        pushList(game, rows, { emptyMsg = "NO POKeMON DATA." })
      end,
    }
    if isGen2() then
      items[#items + 1] = {
        label = "Gender: " .. tostring(mon.gender or "?"):upper() .. "...",
        keepOpen = true,
        onSelect = function()
          pushList(game, {
            {
              label = "MALE",
              onSelect = function()
                setGender(game, mon, "male")
                showMsg(game, "MALE.")
              end,
            },
            {
              label = "FEMALE",
              onSelect = function()
                setGender(game, mon, "female")
                showMsg(game, "FEMALE.")
              end,
            },
          })
        end,
      }
      items[#items + 1] = {
        label = "Nickname...",
        onSelect = function() renameMon(game, mon) end,
      }
      items[#items + 1] = {
        label = string.format("Happiness: %d...", tonumber(mon.happiness) or 0),
        keepOpen = true,
        onSelect = function()
          pushNumberPicker(game, {
            title = "HAPPINESS",
            min = 0, max = 255, value = tonumber(mon.happiness) or 70,
            onConfirm = function(v)
              mon.happiness = v
              showMsg(game, "HAPPINESS SET.")
            end,
          })
        end,
      }
      items[#items + 1] = {
        label = "Pokerus...",
        keepOpen = true,
        onSelect = function()
          pushList(game, {
            {
              label = "NONE",
              onSelect = function()
                mon.pokerus = 0
                showMsg(game, "POKeRUS CLEARED.")
              end,
            },
            {
              label = "INFECTED",
              onSelect = function()
                mon.pokerus = 0x34
                showMsg(game, "POKeRUS ON.")
              end,
            },
            {
              label = "CURED",
              onSelect = function()
                mon.pokerus = 0x30
                showMsg(game, "POKeRUS CURED.")
              end,
            },
          })
        end,
      }
    else
      items[#items + 1] = {
        label = "Nickname...",
        onSelect = function() renameMon(game, mon) end,
      }
    end
    items[#items + 1] = {
      label = "DVs...",
      keepOpen = true,
      onSelect = function()
        if type(mon.dvs) ~= "table" then mon.dvs = randomDvs() end
        local rows = {}
        for _, stat in ipairs({ "attack", "defense", "speed", "special" }) do
          rows[#rows + 1] = {
            label = stat:upper() .. ": " .. tostring(mon.dvs[stat] or 0),
            keepOpen = true,
            onSelect = function()
              pushNumberPicker(game, {
                title = stat:upper(),
                min = 0, max = 15, value = mon.dvs[stat] or 0,
                onConfirm = function(v)
                  mon.dvs[stat] = v
                  mon.dvs.hp = dvHp(mon.dvs)
                  pcall(restat, game, mon)
                  showMsg(game, stat:upper() .. " SET.")
                end,
              })
            end,
          }
        end
        pushList(game, rows)
      end,
    }
    items[#items + 1] = {
      label = "Reset moves",
      onSelect = function()
        resetMoves(game, mon)
        showMsg(game, "MOVES RESET.")
      end,
    }
    if isGen2() and mon.species == "UNOWN" then
      items[#items + 1] = {
        label = "Unown letter...",
        keepOpen = true,
        onSelect = function()
          local Unown = require("src.core.gen2.Unown")
          local rows = {}
          for i = 1, Unown.NUM_UNOWN do
            rows[#rows + 1] = {
              label = Unown.name(i) or tostring(i),
              onSelect = function()
                mon.dvs = Unown.dvsForLetter(i)
                mon.dvs.hp = dvHp(mon.dvs)
                mon.unownLetter = i
                pcall(restat, game, mon)
                showMsg(game, "UNOWN " .. (Unown.name(i) or "?"))
              end,
            }
          end
          pushList(game, rows)
        end,
      }
    end
    items[#items + 1] = {
      label = string.format("HP: %d/%d...", tonumber(mon.hp) or 0, maxHpOf(mon)),
      onSelect = function()
        local cap = maxHpOf(mon)
        pushNumberPicker(game, {
          title = "HP",
          min = 0, max = cap, value = math.min(tonumber(mon.hp) or cap, cap),
          onConfirm = function(hp)
            mon.hp = hp
            showMsg(game, string.format("%s\nHP SET TO %d.", name, hp))
          end,
        })
      end,
    }
    items[#items + 1] = {
      label = "Status: " .. statusLabel(mon) .. "...",
      onSelect = function()
        local rows = {}
        for _, st in ipairs(statusChoices()) do
          rows[#rows + 1] = {
            label = st.label,
            onSelect = function()
              mon.status = st.value
              if st.value == "sleep" then mon.statusTurns = 3 end
              showMsg(game, name .. "\nSTATUS: " .. st.label)
            end,
          }
        end
        pushList(game, rows)
      end,
    }
    items[#items + 1] = {
      label = "Teach move...",
      onSelect = function()
        local rows = {}
        for _, mv in ipairs(moveList(game)) do
          rows[#rows + 1] = {
            label = mv.name,
            onSelect = function()
              if knowsMove(mon, mv.id) then
                showMsg(game, "ALREADY KNOWS\n" .. mv.name .. "!")
                return
              end
              mon.moves = mon.moves or {}
              if #mon.moves < 4 then
                writeMove(game, mon, mv.id)
                showMsg(game, name .. "\nLEARNED " .. mv.name .. "!")
                return
              end
              local forget = {}
              for i, known in ipairs(mon.moves) do
                local kdef = game.data.moves and game.data.moves[known.id]
                forget[#forget + 1] = {
                  label = (kdef and kdef.name) or known.id or "?",
                  onSelect = function()
                    writeMove(game, mon, mv.id, i)
                    showMsg(game, name .. "\nLEARNED " .. mv.name .. "!")
                  end,
                }
              end
              pushList(game, forget, { emptyMsg = "NO MOVES." })
            end,
          }
        end
        pushList(game, rows, { emptyMsg = "NO MOVES." })
      end,
    }
    items[#items + 1] = {
      label = "Forget move...",
      onSelect = function()
        if not mon.moves or #mon.moves <= 1 then
          showMsg(game, "CAN'T FORGET\nLAST MOVE!")
          return
        end
        local rows = {}
        for i, known in ipairs(mon.moves) do
          local kdef = game.data.moves and game.data.moves[known.id]
          rows[#rows + 1] = {
            label = (kdef and kdef.name) or known.id or "?",
            onSelect = function()
              table.remove(mon.moves, i)
              showMsg(game, "FORGOT " .. ((kdef and kdef.name) or known.id) .. "!")
            end,
          }
        end
        pushList(game, rows)
      end,
    }
    if isGen2() then
      local held = mon.item
      local heldName = "NONE"
      if held then
        local idef = game.data.items and game.data.items[held]
        heldName = (idef and idef.name) or held
      end
      items[#items + 1] = {
        label = "Item: " .. heldName .. "...",
        onSelect = function()
          local rows = {
            {
              label = "NONE",
              onSelect = function()
                mon.item = nil
                showMsg(game, name .. "\nITEM CLEARED.")
              end,
            },
          }
          for _, it in ipairs(itemList(game)) do
            rows[#rows + 1] = {
              label = it.name,
              onSelect = function()
                mon.item = it.id
                showMsg(game, name .. "\nGOT " .. it.name .. ".")
              end,
            }
          end
          pushList(game, rows)
        end,
      }
    end
    items[#items + 1] = {
      label = "Duplicate",
      onSelect = function()
        local Party = require("src.pokemon.Party")
        local Boxes = require("src.pokemon.Boxes")
        local copy = copyTable(mon)
        local save = game.save
        save.party = save.party or {}
        if Party.add(save.party, copy) then
          showMsg(game, name .. "\nCOPIED TO PARTY!")
        else
          local box = Boxes.deposit(save, copy)
          showMsg(game, name .. "\nCOPIED TO BOX " .. tostring(box or "?") .. "!")
        end
      end,
    }
    items[#items + 1] = {
      label = "Release",
      onSelect = function()
        local party = game.save and game.save.party
        if not party or #party <= 1 then
          showMsg(game, "CAN'T RELEASE\nLAST POKeMON!")
          return
        end
        for i, m in ipairs(party) do
          if m == mon then
            table.remove(party, i)
            local top = game.stack and game.stack:top()
            if top and not top.isOverworld then game.stack:pop() end
            showMsg(game, name .. "\nWAS RELEASED.")
            return
          end
        end
      end,
    }

    pushList(game, items)
  end

  ------------------------------------------------------------------
  -- Hooks: start menu, collision, encounters, HUD
  ------------------------------------------------------------------
  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local list = nextFn and nextFn(game, items) or items
    if type(list) ~= "table" then list = items end
    local row = {
      label = "DEBUG",
      desc = { "Debug mode", "Tools" },
      onSelect = function() openDebugMenu(game) end,
    }
    local inserted = false
    for i, item in ipairs(list) do
      local label = item and item.label and tostring(item.label) or ""
      if label:find("OPTION") or label:find("SAVE") then
        table.insert(list, i, row)
        inserted = true
        break
      end
    end
    if not inserted then table.insert(list, row) end
    return list
  end)

  mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    local list = nextFn and nextFn(game, items, mon, ctx) or items
    if type(list) ~= "table" then list = items or {} end
    if ctx and ctx.battle then return list end
    if mon and mon.isEgg then return list end
    for _, item in ipairs(list) do
      local label = item.label and tostring(item.label):upper() or ""
      if item.id == "DEBUG" or label == "DEBUG" then return list end
    end
    local row = {
      id = "DEBUG",
      label = "DEBUG",
      onSelect = function(m, g) openMonDebug(g or game, m or mon) end,
    }
    local insertAt = #list + 1
    for i, item in ipairs(list) do
      local id = item.id or item.action
      local label = item.label and tostring(item.label):upper() or ""
      if id == "CANCEL" or id == "cancel" or label == "CANCEL" then
        insertAt = i
        break
      end
    end
    table.insert(list, insertAt, row)
    if #list > 8 then
      for i = #list, 1, -1 do
        local item = list[i]
        if item.id == "CANCEL" or item.action == "cancel" then
          table.remove(list, i)
          break
        end
      end
    end
    while #list > 8 do
      local dropped = false
      for i, item in ipairs(list) do
        if item.id ~= "DEBUG" and (item.fieldMove or (item.action
            and item.action ~= "stats" and item.action ~= "switch")) then
          table.remove(list, i)
          dropped = true
          break
        end
      end
      if not dropped then break end
    end
    return list
  end)

  mod.hooks:wrap("movement.collision", function(nextFn, allowed, ctx)
    if ctrlHeld() then
      local game = liveGame()
      local world = worldOf(game)
      local mover = ctx and ctx.mover
      if world and mover and (mover == world.player or mover == (game and game.player)) then
        if ctx.reason ~= "bounds" then return true end
      end
    end
    return nextFn(allowed, ctx)
  end)

  mod.hooks:wrap("encounter.roll", function(nextFn, a, b)
    if skipFieldEncounters() then return nil end
    return nextFn(a, b)
  end)

  mod.hooks:wrap("render.hud", function(nextFn, game, vp)
    nextFn(game, vp)
    BattleEdit.setViewport(vp)
    if not overlayOn then return end
    -- STATS draws the shiny ⁂ on row 0; keep the coord overlay off opaque
    -- menus so that icon (and the rest of the header) stay visible.
    local top = game and game.stack and game.stack:top()
    if top and BattleEdit.isBattleScreen(top) then return end
    if top and (top.isOpaque or top.isDebugMenu) then return end
    local world = worldOf(game)
    local p = world and world.player
    if not p then return end
    local mapId = world.map and (world.map.id or "?") or "?"
    local line = string.format("%s  %d,%d", mapId, p.cellX or 0, p.cellY or 0)
    if ctrlHeld() then line = line .. "  CTRL" end
    if noEncounters then line = line .. "  NOENC" end
    local G = love.graphics
    G.push()
    if vp and vp.gameX then
      G.translate(vp.gameX, vp.gameY)
      G.scale(vp.scale or 1, vp.scale or 1)
    end
    Font.draw(line, 8, 0)
    local extra = MapEdit.hudExtra(game)
    if extra then
      for i, text in ipairs(extra) do
        Font.draw(text, 8, i * 8)
      end
    end
    MapEdit.drawHud(game)
    G.pop()
  end)

  mod.events:on("mods.loaded", function(ev)
    MapEdit.applySaved(ev and ev.data)
    BattleEdit.applySaved()
    BattleEdit.ensurePatched()
  end)

  mod.hooks:wrap("battle.overlay", function(nextFn, battle)
    nextFn(battle)
    if BattleEdit.drawOverlay then BattleEdit.drawOverlay(battle) end
  end)

  mod.events:on("map.entered", function()
    patchWorld(liveGame())
  end)

  -- Poll keys on the engine's input.step hook. Wrapping love.keypressed does
  -- not reliably see F-keys (F1 save, F2 load, F5 reload, F10 mods), and the
  -- sandbox assignment is the wrong seam.
  local keyWasDown = {}
  local function keyEdge(name)
    local kb = love and love.keyboard
    if not (kb and kb.isDown) then return false end
    local down = kb.isDown(name)
    local pressed = down and not keyWasDown[name]
    keyWasDown[name] = down
    return pressed
  end

  mod.hooks:wrap("input.step", function(nextFn, game, dt)
    if ctrlHeld() and keyEdge("z") then
      if not MapEdit.onKey("undo") then BattleEdit.onKey("undo") end
    end
    if keyEdge("p") then MapEdit.onKey("p") end
    if keyEdge("o") then MapEdit.onKey("o") end
    if keyEdge("q") then MapEdit.onKey("q") end
    if keyEdge("e") then MapEdit.onKey("e") end
    if keyEdge("[") or keyEdge(",") then MapEdit.onKey("[") end
    if keyEdge("]") or keyEdge(".") then MapEdit.onKey("]") end
    MapEdit.tick(game)
    return nextFn(game, dt)
  end)

  mod.hooks:wrap("input.pointer", function(nextFn, game, ev)
    if MapEdit.onPointer and MapEdit.onPointer(game, ev) then return true end
    if BattleEdit.onPointer and BattleEdit.onPointer(game, ev) then return true end
    return nextFn(game, ev)
  end)

  print("[DebugMenu] Ready. Start menu DEBUG / Map options, HUD toggle in menus, hold Ctrl to walk through walls.")
end
