-- Day Care ranch.  Gen 1 expands the Route 5 house.  Gen 2 keeps Route 34
-- clean: talking to the man or lady warps you to a private ranch map
-- where boxed Pokémon wander.

local GameVersion = require("src.core.GameVersion")
local TextBox = require("src.render.TextBox")

local GEN1_MAP = "DAYCARE"
local RANCH_MAP = "POKEMON_RANCH"
local FLOOR, WALL = 15, 10
local SRC_W = 4
local WIDTH, HEIGHT = 16, 14
local HOUSE_BY = 10
local HOUSE_BLOCKS = {
  4, 14, 5, 9,
  15, 1, 2, 15,
  15, 12, 13, 15,
  6, 11, 15, 7,
}

local GEN2_W, GEN2_H = 18, 14
local spawned = {}
local ranchMod

local function ranchBlocks()
  local blocks = {}
  for by = 0, HEIGHT - 1 do
    for bx = 0, WIDTH - 1 do
      local block
      local inHouse = bx < SRC_W and by >= HOUSE_BY
      if inHouse then
        local sx, sy = bx, by - HOUSE_BY
        block = HOUSE_BLOCKS[sy * SRC_W + sx + 1]
        if sy == 0 then block = FLOOR end
      elseif bx == 0 or bx == WIDTH - 1
          or by == 0 or by == HEIGHT - 1 then
        block = WALL
      else
        block = FLOOR
      end
      blocks[#blocks + 1] = block
    end
  end
  return blocks
end

local function boxedMons(save)
  local list = {}
  local boxes = save.boxes or {}
  for box = 1, 14 do
    for slot, mon in ipairs(boxes[box] or {}) do
      if mon and mon.species then
        list[#list + 1] = { mon = mon, box = box, slot = slot }
      end
    end
  end
  local dc = save.daycare or save.dayCare
  if dc and dc.mon and dc.mon.species then
    list[#list + 1] = { mon = dc.mon, box = 0, slot = 0, daycare = true }
  end
  if dc and dc.man and dc.man.mon and dc.man.mon.species then
    list[#list + 1] = { mon = dc.man.mon, box = 0, slot = 0, daycare = true }
  end
  if dc and dc.lady and dc.lady.mon and dc.lady.mon.species then
    list[#list + 1] = { mon = dc.lady.mon, box = 0, slot = 0, daycare = true }
  end
  return list
end

local function monName(data, mon)
  local def = data.pokemon and data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or mon.species
end

local function talkText(data, entry)
  local mon = entry and entry.mon
  if not mon then return nil end
  if mon.isEgg then return "It's an EGG!" end
  local name = monName(data, mon)
  if entry.daycare then
    return name .. " is being\nraised here."
  end
  local def = data.pokemon and data.pokemon[mon.species]
  local species = def and def.name or mon.species
  local level = mon.level or 1
  if name ~= species then
    return name .. "\n" .. species .. " L" .. level
  end
  return name .. " L" .. level
end

local OW_SIZE = 16

local function spriteTable(data)
  return data.gen2Sprites or data.sprites
end

local function iconImage(data, species)
  local icons = data.gen2Icons or data.icons
  if not icons then return nil end
  if icons.species and icons.icons then
    local iconId = icons.species[species]
    local entry = iconId and icons.icons[iconId]
    if type(entry) == "table" and entry.image then return entry.image end
    if type(entry) == "string" then return entry end
  end
  local bySpecies = icons.bySpecies and icons.bySpecies[species]
  if type(bySpecies) == "string" then
    return icons.icons and icons.icons[bySpecies] or bySpecies
  end
  return nil
end

local function eggIcon(data)
  local icons = data.gen2Icons or data.icons
  local entry = icons and icons.icons and icons.icons.ICON_EGG
  if type(entry) == "table" then return entry.image end
  if type(entry) == "string" then return entry end
  return nil
end

local function speciesDex(data, species)
  if not species then return nil end
  local n = tonumber(species)
  if n and n >= 1 then return math.floor(n) end
  local poke = data and data.pokemon and data.pokemon[species]
  local dex = poke and poke.dex
  if type(dex) == "number" and dex >= 1 then return math.floor(dex) end
  local dexDb = data and (data.gen2Pokedex or data.pokedex)
  local entry = dexDb and dexDb.entries and dexDb.entries[species]
  dex = entry and entry.dex
  if type(dex) == "number" and dex >= 1 then return math.floor(dex) end
  return nil
end

local function owSpritePath(data, mon)
  if not (ranchMod and mon and mon.species) then return nil end
  local dex = speciesDex(data, mon.species)
  if not dex then return nil end
  local kind = mon.shiny and "shiny" or "normal"
  local rel = string.format("sprites/%03d_%s.png", dex, kind)
  if not (ranchMod.info and ranchMod:info(rel)) then
    rel = string.format("sprites/%03d_normal.png", dex)
    if not (ranchMod.info and ranchMod:info(rel)) then return nil end
  end
  return ranchMod.assets:path(rel)
end

local function ensureSprite(data, mon)
  if type(mon) ~= "table" or not mon.species then return nil end
  local id = mon.isEgg and "SPRITE_RANCH_EGG"
    or ("SPRITE_RANCH_" .. mon.species .. (mon.shiny and "_S" or ""))
  local sprites = spriteTable(data)
  if not sprites then return nil end
  if sprites[id] then return id end
  if data.sprites and data.sprites[id] then return id end
  local poke = data.pokemon and data.pokemon[mon.species]
  local walk = not mon.isEgg and owSpritePath(data, mon)
  local path = (mon.isEgg and eggIcon(data))
    or walk or iconImage(data, mon.species) or (poke and poke.spriteFront)
  if not path then return nil end
  local def = {
    id = id,
    image = path,
    frames = walk and 6 or 1,
    walker = walk and true or false,
    frameWidth = OW_SIZE,
    frameHeight = OW_SIZE,
    anchorX = OW_SIZE / 2,
    anchorY = OW_SIZE,
    trueColor = walk and true or nil,
  }
  sprites[id] = def
  if data.sprites and data.sprites ~= sprites then
    data.sprites[id] = def
  end
  return id
end

local scaledCache = {}

local function monColors(data, mon)
  if GameVersion.generation() ~= 2 then return nil end
  if not (data and mon and mon.species) then return nil end
  local Palettes = require("src.world.gen2.Palettes")
  local pals = data.gen2Palettes or data.palettes
  return Palettes.monColors(pals, mon.species, mon.shiny)
end

local function paintShades(src, colors)
  local w, h = src:getWidth(), src:getHeight()
  local dst = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = src:getPixel(x, y)
      if a <= 0 then
        dst:setPixel(x, y, 0, 0, 0, 0)
      else
        local light = (r + g + b) / 3
        local c = light > 0.83 and colors[1]
          or light > 0.5 and colors[2]
          or light > 0.17 and colors[3] or colors[4]
        dst:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, a)
      end
    end
  end
  return dst
end

local function shrinkToOverworld(npc, data)
  local sprite = npc and npc.sprite
  if sprite and sprite.def and sprite.def.walker then
    return
  end
  if not (sprite and sprite.image and love and love.image and love.graphics) then
    return
  end
  local path = sprite.def and sprite.def.image
  if not path then return end
  local mon = npc.def and npc.def.ranchMon and npc.def.ranchMon.mon
  local key = path .. "|" .. tostring(mon and mon.species) .. "|"
    .. tostring(mon and mon.shiny)
  local cached = scaledCache[key]
  if not cached then
    local Assets = require("src.render.Assets")
    local ok, src = pcall(Assets.imageData, path)
    if not ok or not src or not src.getWidth then return end
    local colors = monColors(data, mon)
    if colors then src = paintShades(src, colors) end
    local sw, sh = src:getWidth(), src:getHeight()
    local dst = src
    if sw > OW_SIZE or sh > OW_SIZE then
      dst = love.image.newImageData(OW_SIZE, OW_SIZE)
      for y = 0, OW_SIZE - 1 do
        for x = 0, OW_SIZE - 1 do
          dst:setPixel(x, y, src:getPixel(
            math.min(sw - 1, math.floor(x * sw / OW_SIZE)),
            math.min(sh - 1, math.floor(y * sh / OW_SIZE))))
        end
      end
    end
    cached = { image = love.graphics.newImage(dst), colored = colors ~= nil }
    scaledCache[key] = cached
  end
  sprite.image = cached.image
  sprite.frameWidth = OW_SIZE
  sprite.frameHeight = OW_SIZE
  sprite.anchorX = OW_SIZE / 2
  sprite.anchorY = OW_SIZE
  sprite.frames[0] = love.graphics.newQuad(0, 0, OW_SIZE, OW_SIZE, OW_SIZE, OW_SIZE)
  if sprite.def and cached.colored then sprite.def.trueColor = true end
end

local function padFromOverview(snap, taken)
  if not snap or not snap.rows then return {} end
  local reserved = {}
  for _, marker in ipairs(snap.markers or {}) do
    if marker.kind == "warp" then
      reserved[(marker.y or 0) * 1000 + (marker.x or 0)] = true
    end
  end
  for key in pairs(taken or {}) do reserved[key] = true end
  local cells = {}
  for y = 1, snap.height - 3 do
    local row = snap.rows[y + 1]
    if row then
      for x = 1, snap.width - 2 do
        if row:sub(x + 1, x + 1) == "."
            and not reserved[y * 1000 + x]
            and (x + y) % 2 == 0 then
          cells[#cells + 1] = { x = x, y = y }
        end
      end
    end
  end
  return cells
end

local function clear(mod)
  for i = #spawned, 1, -1 do
    mod.world:removeNpc(spawned[i])
    spawned[i] = nil
  end
end

local function markPassable(ow, npcId, data)
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.id == npcId then
      npc.passable = true
      shrinkToOverworld(npc, data)
      return
    end
  end
end

local function ranchMap(gen)
  return gen == 2 and RANCH_MAP or GEN1_MAP
end

local function occupiedCells(ow)
  local taken = {}
  for _, npc in ipairs(ow and ow.npcs or {}) do
    if npc.cellX and npc.cellY then
      taken[npc.cellY * 1000 + npc.cellX] = true
    end
  end
  return taken
end

local function clusterKey(data, mon)
  if not mon or mon.isEgg then return "ZZ_EGG" end
  if GameVersion.generation() ~= 2 then return tostring(mon.species) end
  local Breeding = require("src.core.gen2.Breeding")
  local def = data.pokemon and data.pokemon[mon.species]
  if Breeding.isNoEggs(def) then return "ZZ_NONE" end
  local a, b = Breeding.eggGroups(def)
  if a and b and b < a then a, b = b, a end
  return tostring(a or "") .. "/" .. tostring(b or "")
end

local function populate(mod, game, ow, gen)
  clear(mod)
  local mapId = ranchMap(gen)
  local mons = boxedMons(game.save)
  table.sort(mons, function(a, b)
    local ka, kb = clusterKey(game.data, a.mon), clusterKey(game.data, b.mon)
    if ka == kb then return tostring(a.mon.species) < tostring(b.mon.species) end
    return ka < kb
  end)
  local cells = padFromOverview(mod.world:mapOverview(), occupiedCells(ow))
  if #cells == 0 then return end
  for i, entry in ipairs(mons) do
    local sprite = ensureSprite(game.data, entry.mon)
    if sprite then
      local cell = cells[((i - 1) % #cells) + 1]
      local objDef = {
        name = "RANCH_MON_" .. i,
        sprite = sprite,
        x = cell.x,
        y = cell.y,
        text = "TEXT_RANCH_MON",
        ranchMon = entry,
        passable = true,
      }
      if gen == 2 then
        objDef.movement = 2
        objDef.radius = { x = 4, y = 4 }
      else
        objDef.movement = "WALK"
        objDef.range = "ANY_DIR"
      end
      local npcId = mod.world:spawnNpc(mapId, objDef)
      if npcId then
        spawned[#spawned + 1] = npcId
        markPassable(ow, npcId, game.data)
      end
    end
  end
end

local PARTY_MAX = 6

local function say(game, text, onDone)
  if not text then
    if onDone then onDone() end
    return
  end
  game.stack:push(TextBox.new(game, text, onDone))
end

local function askYesNo(game, text, onYes, onNo)
  game.stack:push(TextBox.new(game, text, nil, {
    choice = function(yes)
      if yes then
        if onYes then onYes() end
      elseif onNo then
        onNo()
      end
    end,
  }))
end

local function boxedStillThere(save, entry)
  if not (save and entry and entry.mon) or entry.daycare then return false end
  local box = save.boxes and save.boxes[entry.box]
  return box and box[entry.slot] == entry.mon
end

local function ensureStats(game, mon)
  local def = game.data.pokemon and game.data.pokemon[mon.species]
  if not def then return end
  pcall(function()
    require("src.pokemon.Stats").ensure(def, mon)
  end)
end

local function playCry(game, species)
  pcall(function()
    require("src.core.Sound").playCry(game.data, species)
  end)
end

local function refreshRanch(mod, game)
  local ow = mod.world:overworld()
  if game and ow then populate(mod, game, ow, GameVersion.generation()) end
end

local STEP = {
  left = { -1, 0 }, right = { 1, 0 },
  up = { 0, -1 }, down = { 0, 1 },
}

local function ranchHerd(ow)
  local list = {}
  for _, npc in ipairs(ow and ow.npcs or {}) do
    local entry = npc.def and npc.def.ranchMon
    if entry and entry.mon and not entry.daycare then
      list[#list + 1] = npc
    end
  end
  return list
end

local function sharesEggGroup(data, a, b)
  if not (a and b) or a.isEgg or b.isEgg then return false end
  local Breeding = require("src.core.gen2.Breeding")
  return Breeding.groupsCompatible(data, a.species, b.species)
end

local function tryStepToward(ow, npc, dest)
  if npc.moving or not dest then return end
  local dx, dy = dest.cellX - npc.cellX, dest.cellY - npc.cellY
  if dx == 0 and dy == 0 then return end
  local dir = math.abs(dx) >= math.abs(dy)
    and (dx > 0 and "right" or "left")
    or (dy > 0 and "down" or "up")
  local d = STEP[dir]
  local tx, ty = npc.cellX + d[1], npc.cellY + d[2]
  local map = ow.map
  if map and map.isWalkable and not map:isWalkable(tx, ty) then return end
  if map and map.warpAt and map:warpAt(tx, ty) then return end
  npc.facing = dir
  npc.targetX, npc.targetY = tx, ty
  npc.moving = true
  npc.progress = 0
end

local function attractHerd(data, ow)
  local herd = ranchHerd(ow)
  for _, npc in ipairs(herd) do
    local mon = npc.def.ranchMon.mon
    if mon.isEgg then
      npc.radiusX, npc.radiusY = 0, 0
    else
      local best, bestD
      for _, other in ipairs(herd) do
        if other ~= npc and sharesEggGroup(data, mon, other.def.ranchMon.mon) then
          local d = math.abs(other.cellX - npc.cellX)
            + math.abs(other.cellY - npc.cellY)
          if not bestD or d < bestD then best, bestD = other, d end
        end
      end
      if best then
        npc.homeX, npc.homeY = best.cellX, best.cellY
        npc.radiusX, npc.radiusY = 1, 1
        if bestD > 1 then tryStepToward(ow, npc, best) end
      end
    end
  end
end

local function ranchBreed(save)
  save.ranchBreed = save.ranchBreed or { steps = 80, key = "", cool = 0 }
  return save.ranchBreed
end

local function pairKey(a, b)
  local ka, kb = tostring(a), tostring(b)
  if ka > kb then ka, kb = kb, ka end
  return ka .. "+" .. kb
end

local function storeEgg(save, egg)
  local Boxes = require("src.core.gen2.Boxes")
  for i = 1, Boxes.NUM_BOXES do
    if not Boxes.isFull(save, i) then
      local box = Boxes.box(save, i)
      box[#box + 1] = egg
      return true
    end
  end
  return false
end

local function tryRanchEgg(mod, game, ow)
  local Breeding = require("src.core.gen2.Breeding")
  local herd = ranchHerd(ow)
  local bestA, bestB, bestD
  for i = 1, #herd do
    local a = herd[i].def.ranchMon.mon
    if not a.isEgg then
      for j = i + 1, #herd do
        local b = herd[j].def.ranchMon.mon
        if not b.isEgg then
          local value = Breeding.compatibility(game.data, a, b)
          if value > 0 and value < 255 then
            local d = math.abs(herd[j].cellX - herd[i].cellX)
              + math.abs(herd[j].cellY - herd[i].cellY)
            if d <= 1 and (not bestD or d < bestD) then
              bestA, bestB, bestD = a, b, d
            end
          end
        end
      end
    end
  end
  local st = ranchBreed(game.save)
  if st.cool > 0 then
    st.cool = st.cool - 1
    return
  end
  if not bestA then
    st.key = ""
    return
  end
  local key = pairKey(bestA, bestB)
  if st.key ~= key then
    st.key, st.steps = key, 80
    return
  end
  st.steps = (st.steps or 80) - 1
  if st.steps > 0 then return end
  st.steps = 80
  local value = Breeding.compatibility(game.data, bestA, bestB)
  if love.math.random(0, 255) >= Breeding.eggChance(value) then return end
  local egg = Breeding.makeEgg(game.data, bestA, bestB, {
    playerName = game.save.player and game.save.player.name,
    playerId = game.save.player and game.save.player.id,
  })
  if not egg or not storeEgg(game.save, egg) then return end
  st.cool = 128
  refreshRanch(mod, game)
  if not (game.stack and game.stack.top and game.stack:top()) then
    say(game, "The POKéMON laid\nan EGG!")
  end
end

local function withdrawBoxed(game, entry)
  if not boxedStillThere(game.save, entry) then return false end
  table.remove(game.save.boxes[entry.box], entry.slot)
  game.save.party = game.save.party or {}
  game.save.party[#game.save.party + 1] = entry.mon
  ensureStats(game, entry.mon)
  return true
end

local function swapBoxed(game, entry, partyIndex)
  if not boxedStillThere(game.save, entry) then return false, "gone" end
  local party = game.save.party
  local other = party and party[partyIndex]
  if not other then return false, "gone" end
  if GameVersion.generation() == 2 then
    local Mail = require("src.core.gen2.Mail")
    if Mail.monHoldsMail(other) then return false, "mail" end
  end
  party[partyIndex] = entry.mon
  game.save.boxes[entry.box][entry.slot] = other
  ensureStats(game, entry.mon)
  return true, other
end

local function pickParty(game, onPick, onCancel)
  local Screens = require("src.ui.Screens")
  if GameVersion.generation() == 2 then
    Screens.push(game, "Gen2PartyMenu", {
      party = game.save.party,
      prompt = "choose",
      onChoose = function(index)
        game.stack:pop()
        if onPick then onPick(index) end
      end,
      onCancel = function()
        game.stack:pop()
        if onCancel then onCancel() end
      end,
    })
    return
  end
  Screens.push(game, "PartyMenu", {
    pickOnly = true,
    onSwitch = function(mon)
      for i, p in ipairs(game.save.party or {}) do
        if p == mon then
          if onPick then onPick(i) end
          return
        end
      end
      if onCancel then onCancel() end
    end,
    onCancel = onCancel,
  })
end

local function talkRanchMon(mod, game, entry, done)
  local finish = done or function() end
  local text = talkText(game.data, entry)
  if not text then
    finish()
    return
  end
  if entry.daycare then
    say(game, text, finish)
    return
  end
  local name = monName(game.data, entry.mon)
  local isEgg = entry.mon.isEgg == true
  local function joined(other)
    if not isEgg then playCry(game, entry.mon.species) end
    refreshRanch(mod, game)
    if isEgg then
      say(game, other and "Got the EGG!\v"
        .. monName(game.data, other) .. " is staying\nat the ranch."
        or "Got the EGG!", finish)
    elseif other then
      say(game, name .. " joined\nyour party!\v"
        .. monName(game.data, other) .. " is staying\nat the ranch.", finish)
    else
      say(game, name .. " joined\nyour party!", finish)
    end
  end
  local function askSwap()
    askYesNo(game, "Your party is full.\vSwap with one of\nyour POKéMON?",
      function()
        pickParty(game, function(index)
          local ok, extra = swapBoxed(game, entry, index)
          if not ok then
            if extra == "mail" then
              say(game, "Remove MAIL first.", finish)
            else
              finish()
            end
            return
          end
          joined(extra)
        end, finish)
      end, finish)
  end
  local prompt = isEgg and (text .. "\vTake it with you?")
    or (text .. "\vWant it to join\nyour party?")
  askYesNo(game, prompt, function()
    if not boxedStillThere(game.save, entry) then
      finish()
      return
    end
    if #(game.save.party or {}) < PARTY_MAX then
      if withdrawBoxed(game, entry) then
        joined(nil)
      else
        finish()
      end
    else
      askSwap()
    end
  end, finish)
end

local STAFF_MAPS = { DAY_CARE = true, ROUTE_34 = true }
local STAFF_SPRITES = { SPRITE_GRAMPS = true, SPRITE_GRANNY = true }

local function isDaycareStaff(npc, mapId)
  local d = npc and npc.def
  if not d then return false end
  local sprite = tostring(d.sprite or "")
  if STAFF_MAPS[mapId] and STAFF_SPRITES[sprite] then return true end
  local name = tostring(d.name or "")
  if name:find("MON", 1, true) then return false end
  if name:find("DAYCARE", 1, true) or name:find("DAY_CARE", 1, true) then
    return true
  end
  if name == "ROUTE34_GRAMPS" then return true end
  return false
end

local function hasPendingEgg(save)
  local dc = save and (save.dayCare or save.daycare)
  return dc and dc.hasEgg == true
end

-- Static ranch map (same record the content editor lists as POKEMON_RANCH).
local RANCH_LAND_X, RANCH_LAND_Y = 17, 24

local function ranchMapDef()
  return {
    id = RANCH_MAP,
    label = "Pokemon Ranch",
    index = 1000,
    generation = 2,
    tileset = "TILESET_HOUSE",
    width = GEN2_W,
    height = GEN2_H,
    borderBlock = 10,
    environment = "INDOOR",
    music = 37,
    palette = "PALETTE_DAY",
    landmark = 15,
    phoneService = true,
    blocks = {
      10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 10,
      10, 10, 10, 10, 10, 10, 10, 10, 11, 11, 10, 10, 10, 10, 10, 10, 10, 10,
    },
    objects = {
      {
        index = 1, name = "DAYCARE_GRAMPS", sprite = "SPRITE_GRAMPS",
        movement = 9, x = 15, y = 24, type = 0,
        hours = { -1, -1 }, radius = { x = 0, y = 0 },
        scriptKey = "57:7199",
      },
      {
        index = 2, name = "DAYCARE_GRANNY", sprite = "SPRITE_GRANNY",
        movement = 8, x = 19, y = 24, type = 0,
        hours = { -1, -1 }, radius = { x = 0, y = 0 },
        scriptKey = "57:71a1",
      },
    },
    warps = {
      { x = 16, y = 27, destMap = "DAY_CARE", destWarp = 3, destGroup = 11, destMapNum = 22 },
      { x = 17, y = 27, destMap = "DAY_CARE", destWarp = 3, destGroup = 11, destMapNum = 22 },
      { x = 18, y = 27, destMap = "DAY_CARE", destWarp = 3, destGroup = 11, destMapNum = 22 },
      { x = 19, y = 27, destMap = "DAY_CARE", destWarp = 3, destGroup = 11, destMapNum = 22 },
    },
  }
end

local function stripEditorKeys(src)
  local out = {}
  for k, v in pairs(src) do
    if type(k) ~= "string" or k:sub(1, 1) ~= "_" then
      out[k] = v
    end
  end
  return out
end

-- Hand-written main.lua is not regenerated, so editor encounter edits live
-- only in editor_project.lua. Gold reads data.gen2Encounters.grass[mapId],
-- not map.encounters.
local function applyEditorEncounters(mod, project)
  if not (mod and project) then return end
  local grass, water = {}, {}
  for id, map in pairs(project.maps or {}) do
    local enc = type(map) == "table" and map.encounters
    if type(enc) == "table" then
      if enc.grass then grass[id] = enc.grass end
      if enc.water then water[id] = enc.water end
    end
  end
  local function patchKind(kind, payload)
    if type(payload) == "table" and next(payload) then
      pcall(function()
        mod.content.encounters:patch(kind, payload)
      end)
    end
  end
  patchKind("grass", grass)
  patchKind("water", water)
  patchKind("fishGroups", project.fishGroups)
  patchKind("treeSets", project.treeSets)
  patchKind("trees", project.trees)
  patchKind("rocks", project.rocks)
end

local function gameTilesets(mod)
  local data = mod.game and mod.game.data
  return data and (data.gen2Tilesets or data.tilesets)
end

local function runtimeMicroTile(tileset, cellTile, micro)
  local blockId = math.floor(cellTile / 4)
  local quadrant = cellTile % 4
  local block = tileset.blocks and tileset.blocks[blockId + 1]
  if not block then return nil end
  local qx, qy = quadrant % 2, math.floor(quadrant / 2)
  local mx, my = micro % 2, math.floor(micro / 2)
  return block[(qy * 2 + my) * 4 + qx * 2 + mx + 1]
end

-- Gold only colorizes a tileset that has tilePalettes. The editor's layered
-- atlas is grayscale 4-shade pixels meant for that remap.
local function tilePalettesFor(mod, project)
  local pals = {}
  for i = 1, 96 do pals[i] = 1 end
  local tilesets = gameTilesets(mod)
  local src = project and project.layeredMaps and project.layeredMaps[RANCH_MAP]
  local layer = src and src.layers and src.layers[1]
  if not (tilesets and layer and layer.cells) then return pals end
  local seen, nextId = {}, 0
  local w = src.cellWidth or 0
  local h = src.cellHeight or 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local cell = layer.cells[y * w + x + 1]
      if type(cell) == "table" then
        local tsId = tostring(cell.source or ""):gsub("^@runtime:", "")
        local base = tilesets[tsId]
        local srcPals = base and base.tilePalettes
        if base and srcPals then
          for micro = 0, 3 do
            local microTile = runtimeMicroTile(base, cell.tile, micro)
            local key = tsId .. ":" .. tostring(microTile)
            if microTile ~= nil and seen[key] == nil then
              seen[key] = nextId
              pals[nextId + 1] = srcPals[microTile + 1] or 1
              nextId = nextId + 1
            end
          end
        end
      end
    end
  end
  return pals
end

local function loadLuaFile(mod, name)
  local path = mod and mod.path and (mod.path .. "/" .. name)
  if not path then return nil end
  local chunk
  if love and love.filesystem and love.filesystem.load then
    chunk = love.filesystem.load(path)
  end
  if not chunk and io and io.open then
    local f = io.open(path, "rb")
    if f then
      local body = f:read("*a")
      f:close()
      chunk = load(body, path)
    end
  end
  return chunk
end

local function loadEditorProject(mod)
  local chunk = loadLuaFile(mod, "editor_project.lua")
  if not chunk then return nil end
  local ok, project = pcall(chunk)
  if ok and type(project) == "table" then return project end
  return nil
end

-- Content-editor Save writes this when main.lua is hand-written. Same payload
-- as a generated main.lua: maps, tilesets, encounters, pokemon, items, text.
local function applyEditorGenerated(mod)
  local chunk = loadLuaFile(mod, "editor_apply.lua")
  if not chunk then return false end
  local ok, apply = pcall(chunk)
  if not (ok and type(apply) == "function") then return false end
  local ran, err = pcall(apply, mod)
  if not ran then
    print("editor_apply.lua failed: " .. tostring(err))
    return false
  end
  return true
end

local function registerGen2Ranch(mod)
  local project = loadEditorProject(mod)
  local fallback = ranchMapDef()
  local def = project and project.maps and project.maps[RANCH_MAP]
  def = def and stripEditorKeys(def) or fallback
  if project and project.tilesets then
    for id, tileset in pairs(project.tilesets) do
      if type(tileset) == "table" then
        local rec = stripEditorKeys(tileset)
        -- A trueColor atlas is already GBC-baked. Attaching tilePalettes makes
        -- Gold remap those pixels again with the map environment (INDOOR on
        -- Johto grass looks wrong).
        if not rec.tilePalettes and not rec.trueColor then
          rec.tilePalettes = tilePalettesFor(mod, project)
        end
        local ok = pcall(function()
          mod.content.tilesets:register(id, rec)
        end)
        if not ok then
          pcall(function() mod.content.tilesets:override(id, rec) end)
        end
      end
    end
  end
  local srcLayer = project and project.layeredMaps and project.layeredMaps[RANCH_MAP]
  if def.environment == "INDOOR" and srcLayer
      and srcLayer.baseTileset == "TILESET_JOHTO" then
    def.environment = "TOWN"
  end
  local bySprite = {}
  for _, obj in ipairs(fallback.objects or {}) do
    bySprite[tostring(obj.sprite or "")] = obj
  end
  for i, obj in ipairs(def.objects or {}) do
    local srcObj = bySprite[obj.sprite]
    obj.movement = tonumber(obj.movement) or obj.movement
    if srcObj then
      obj.index = tonumber(obj.index) or srcObj.index or i
      obj.name = obj.name or srcObj.name
      obj.type = obj.type or srcObj.type
      obj.hours = obj.hours or srcObj.hours
      obj.radius = obj.radius or srcObj.radius
      obj.scriptKey = obj.scriptKey or srcObj.scriptKey
    elseif not obj.index then
      obj.index = i
    end
  end
  local fbWarp = {}
  for _, warp in ipairs(fallback.warps or {}) do
    fbWarp[(warp.x or 0) .. "," .. (warp.y or 0)] = warp
  end
  for _, warp in ipairs(def.warps or {}) do
    if not warp.destMap or warp.destMap == RANCH_MAP then
      local src = fbWarp[(warp.x or 0) .. "," .. (warp.y or 0)]
        or fallback.warps[1]
      if src then
        warp.destMap = src.destMap
        warp.destWarp = src.destWarp
        warp.destGroup = src.destGroup
        warp.destMapNum = src.destMapNum
      end
    end
  end
  local data = mod.game and mod.game.data
  local maps = data and (data.gen2Maps or data.maps)
  local src = maps and maps.DAY_CARE
  if src then
    local dayCareBySprite = {}
    for _, obj in ipairs(src.objects or {}) do
      dayCareBySprite[tostring(obj.sprite or "")] = obj
    end
    for _, obj in ipairs(def.objects or {}) do
      local srcObj = dayCareBySprite[obj.sprite]
      if srcObj then
        obj.scriptKey = srcObj.scriptKey or srcObj.script or obj.scriptKey
        obj.script = srcObj.script
      end
    end
  end
  local ok = pcall(function()
    mod.content.maps:register(RANCH_MAP, def)
  end)
  if not ok then
    pcall(function() mod.content.maps:override(RANCH_MAP, def) end)
  end
  applyEditorEncounters(mod, project)
  return true, RANCH_LAND_X, RANCH_LAND_Y
end

return function(mod)
  ranchMod = mod
  local gen = GameVersion.generation()
  local applied = applyEditorGenerated(mod)

  if gen == 1 then
    local dy = HOUSE_BY * 2
    mod.content.maps:patch(GEN1_MAP, {
      width = WIDTH,
      height = HEIGHT,
      blocks = ranchBlocks(),
      objects = {
        {
          index = 1,
          movement = "STAY",
          name = "DAYCARE_GENTLEMAN",
          range = "RIGHT",
          sprite = "SPRITE_GENTLEMAN",
          text = "TEXT_DAYCARE_GENTLEMAN",
          x = 2,
          y = 3 + dy,
        },
      },
      warps = {
        { destMap = "LAST_MAP", destWarp = 5, x = 2, y = 7 + dy },
        { destMap = "LAST_MAP", destWarp = 5, x = 3, y = 7 + dy },
      },
    })
    mod.content.text:override("_DaycareGentlemanIntroText",
      "I run a POKéMON RANCH.\nYour boxed POKéMON\nlive here with me.\vWant me to raise\none of yours too?")
    mod.content.map_scripts:register(GEN1_MAP, {
      talk = {
        TEXT_RANCH_MON = function(game, ow, npc, done)
          talkRanchMon(mod, game, npc and npc.def and npc.def.ranchMon, done)
        end,
      },
    })
  end

  local ranchReady, landX, landY = false, 17, 24
  if gen == 2 then
    if applied then
      ranchReady, landX, landY = true, RANCH_LAND_X, RANCH_LAND_Y
    else
      local ok, x, y = registerGen2Ranch(mod)
      if ok then ranchReady, landX, landY = true, x, y end
    end
    local OW = require("src.world.OverworldController")
    local prev = OW.talkTo
    function OW.talkTo(world, npc)
      local entry = npc and npc.def and npc.def.ranchMon
      if entry then
        talkRanchMon(mod, mod.game, entry)
        return true
      end
      local mapId = world and world.map and world.map.id
      local save = world and world.game and world.game.save
        or (mod.game and mod.game.save)
      if ranchReady and mapId ~= RANCH_MAP and isDaycareStaff(npc, mapId)
          and not hasPendingEgg(save) then
        mod.world:warpTo(RANCH_MAP, landX, landY, "up")
        return true
      end
      if type(prev) == "function" then return prev(world, npc) end
      return false
    end
  end

  mod.events:on("map.entered", function(ev)
    if ev.mapId ~= ranchMap(gen) then return end
    local game = mod.game
    local ow = mod.world:overworld()
    if game and ow then populate(mod, game, ow, gen) end
  end)

  mod.events:on("map.exited", function(ev)
    if ev.mapId == ranchMap(gen) then clear(mod) end
  end)

  if gen == 2 then
    mod.events:on("world.interacted", function(ev)
      local npc = ev.target
      local entry = npc and npc.def and npc.def.ranchMon
      if ev.kind ~= "npc" or not entry then return end
      talkRanchMon(mod, mod.game, entry)
    end)
    mod.events:on("world.stepped", function(ev)
      if ev.mapId ~= RANCH_MAP then return end
      local game = mod.game
      local ow = mod.world:overworld()
      if not (game and ow) then return end
      attractHerd(game.data, ow)
      tryRanchEgg(mod, game, ow)
    end)
  end
end
