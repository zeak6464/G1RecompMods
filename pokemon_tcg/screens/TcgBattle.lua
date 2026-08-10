local V = ...
local Cache = V.require("cache")
local Save = V.require("save")
local Battle = V.require("battle")
local Ai = V.require("ai")
local CardGfx = V.require("card_gfx")
local AttackFx = V.require("attack_fx")

local function Font()
  return require("src.render.Font")
end

local Screen = {}
Screen.__index = Screen
Screen.isOpaque = true

-- GBC duel main menu (3x2). Native 8×8 font only — scaling shreds glyphs on the pixel canvas.
local MAIN = {
  { id = "hand",    label = "HAND",    x = 12,  y = 112 },
  { id = "check",   label = "CHECK",   x = 52,  y = 112 },
  { id = "retreat", label = "RETREAT", x = 100, y = 112 },
  { id = "attack",  label = "ATTACK",  x = 12,  y = 128 },
  { id = "power",   label = "PKMN",    label2 = "POWER", x = 72, y = 124 },
  { id = "done",    label = "DONE",    x = 120, y = 128 },
}





local function hpNow(mon)
  if not mon then return 0, 0 end
  return math.max(0, (mon.maxHp or 0) - (mon.damage or 0)), mon.maxHp or 0
end

local function energyList(mon)
  local out = {}
  if not mon or not mon.energy then return out end
  local order = { "FIRE", "GRASS", "LIGHTNING", "WATER", "FIGHTING", "PSYCHIC", "COLORLESS" }
  for _, typ in ipairs(order) do
    local n = mon.energy[typ] or 0
    for _ = 1, n do out[#out + 1] = typ end
  end
  return out
end

local function canPay(mon, cost)
  if not cost then return true end
  local have = {}
  for k, v in pairs(mon.energy) do have[k] = v end
  for typ, need in pairs(cost) do
    if typ ~= "COLORLESS" then
      if (have[typ] or 0) < need then return false end
      have[typ] = have[typ] - need
    end
  end
  local leftover = 0
  for _, v in pairs(have) do leftover = leftover + v end
  return leftover >= (cost.COLORLESS or 0)
end

local function nameLv(mon)
  if not mon then return "-" end
  local card = mon.card or Cache.card(mon.cardId)
  local name = card and card.name or "?"
  local lv = card and card.level
  if lv and lv > 0 then
    return ("%s LV%d"):format(name, lv)
  end
  return name
end

-- Keep GBC greens/reds/card art out of Gen1 SGB remap.
function Screen:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, 19, 17) }
end


function Screen.new(game, args)
  args = args or {}
  local self = setmetatable({}, Screen)
  self.game = game
  self.mod = V.mod
  self.done = false
  self.error = nil
  self.mode = "main"
  self.cursor = 4 -- ATTACK, like the reference screenshot
  self.subIndex = 1
  self.subItems = {}
  self.message = nil
  self.oppName = args.oppName

  local ok = Cache.ensure(self.mod)
  if not ok then
    self.error = "Import TCG ROM first"
    return self
  end

  local playerDeck = Save.deck(self.mod)
  if #playerDeck < 60 then
    self.error = "Deck needs 60 cards"
    return self
  end
  local npcDeck = args.oppDeck
  if type(npcDeck) ~= "table" or #npcDeck < 60 then
    local cat = Cache.get()
    npcDeck = cat and cat.practiceDeck
  end
  if type(npcDeck) ~= "table" or #npcDeck < 60 then
    npcDeck = playerDeck
  end
  self.battle = Battle.new(playerDeck, npcDeck, { oppName = self.oppName })
  self:enterMain()
  return self
end


function Screen:setMessage(msg)
  self.message = msg
end

function Screen:flushLog()
  local b = self.battle
  if not b then return end
  local last
  while #b.log > 0 do
    last = table.remove(b.log, 1)
  end
  if last then self.message = last end
end

function Screen:finishIfDone()
  local b = self.battle
  if not b or not b.result then return false end
  self.done = true
  self.mode = "done"
  if b.result == "win" then
    Save.recordWin(self.mod)
    self.message = "You win!"
  else
    Save.recordLoss(self.mod)
    self.message = "You lose..."
  end
  return true
end

function Screen:enterMain()
  if self:finishIfDone() then return end
  local b = self.battle
  if b.turn == "opp" then
    self.mode = "opp"
    self.message = "Opponent's turn"
    return
  end
  self.mode = "main"
end

function Screen:beginAttackAnim()
  local a = self.battle and self.battle.lastAttack
  if not a then return false end
  self.battle.lastAttack = nil
  self.atkFx = AttackFx.start(a)
  self.mode = "anim"
  return true
end

function Screen:afterAttackResolve()
  if self:beginAttackAnim() then return end
  self:enterMain()
end

function Screen:runOpponent()
  local b = self.battle
  if b.turn == "opp" and not b.result then
    Ai.takeTurn(b)
    self:flushLog()
  end
  self:afterAttackResolve()
end

function Screen:openHand()
  local Effects = V.require("effects")
  local hand = self.battle.player.hand
  self.subItems = {}
  for i, id in ipairs(hand) do
    local card = Cache.card(id)
    local right = ""
    if card then
      if card.kind == "pokemon" then
        if Battle.isBenchable(card) then
          right = "BENCH"
        elseif #(self.battle:evolveTargets(i)) > 0 then
          right = "EVO"
        else
          right = card.stage or "PKMN"
        end
      elseif card.kind == "energy" then
        right = "EN"
      else
        local key = card.key
        if Effects.isTrainerPlayable(key) then
          right = "USE"
        else
          right = "TR"
        end
      end
    end
    local label = card and card.name or ("#" .. id)
    if #label > 10 then label = label:sub(1, 10) end
    self.subItems[#self.subItems + 1] = {
      label = label,
      right = right,
      cardId = id,
      handIndex = i,
    }
  end
  if #self.subItems == 0 then
    self:setMessage("No cards in hand!")
    return
  end
  self.mode = "hand"
  self.subIndex = 1
end


function Screen:openAttack()
  local Effects = V.require("effects")
  local mon = self.battle.player.active
  local okAtk, why = self.battle:canAttack(mon)
  if not okAtk then
    self:setMessage(why or "Can't attack")
    return
  end
  local attacks = mon and mon.card and mon.card.attacks or {}
  self.subItems = {}
  for i, atk in ipairs(attacks) do
    if not Effects.isPokemonPower(atk) then
      self.subItems[#self.subItems + 1] = {
        label = string.format("%s %d", atk.name or ("ATK" .. i), atk.damage or 0),
        atkIndex = i,
        ok = canPay(mon, atk.cost),
      }
    end
  end
  if #self.subItems == 0 then
    self:setMessage("No attacks!")
    return
  end
  self.mode = "attack"
  self.subIndex = 1
end


function Screen:openRetreat()
  local side = self.battle.player
  self.subItems = {}
  for i, mon in ipairs(side.bench) do
    self.subItems[#self.subItems + 1] = {
      label = nameLv(mon),
      benchIndex = i,
      cardId = mon.cardId,
    }
  end
  if #self.subItems == 0 then
    self:setMessage("No Benched Pokémon!")
    return
  end
  self.mode = "retreat"
  self.subIndex = 1
end

function Screen:openEnergyTarget(handIndex)
  local side = self.battle.player
  self.subItems = {}
  if side.active then
    self.subItems[#self.subItems + 1] = {
      label = nameLv(side.active),
      right = "ACT",
      energyTarget = "active",
      handIndex = handIndex,
      cardId = side.active.cardId,
    }
  end
  for i, mon in ipairs(side.bench) do
    self.subItems[#self.subItems + 1] = {
      label = nameLv(mon),
      right = "BN" .. i,
      energyTarget = i,
      handIndex = handIndex,
      cardId = mon.cardId,
    }
  end
  if #self.subItems == 0 then
    self:setMessage("No Pokémon!")
    return
  end
  self.mode = "energy"
  self.subIndex = 1
end

function Screen:openEvolveTarget(handIndex)
  local targets = self.battle:evolveTargets(handIndex)
  self.subItems = {}
  for _, t in ipairs(targets) do
    self.subItems[#self.subItems + 1] = {
      label = nameLv(t.mon),
      right = t.target == "active" and "ACT" or ("BN" .. t.target),
      evoTarget = t.target,
      handIndex = handIndex,
      cardId = t.mon.cardId,
    }
  end
  if #self.subItems == 0 then
    self:setMessage("No evolve target!")
    return
  end
  self.mode = "evolve"
  self.subIndex = 1
end

local function isBasicPkmn(card)
  return card and card.kind == "pokemon"
    and (card.stage == "BASIC" or card.stage == "STAGE2_WITHOUT_STAGE1")
end

function Screen:openTrainerTarget(handIndex, need)
  local side = self.battle.player
  local foe = self.battle.opp
  self.subItems = {}
  if need == "own_bench" then
    for i, mon in ipairs(side.bench) do
      self.subItems[#self.subItems + 1] = {
        label = nameLv(mon),
        right = "BN" .. i,
        trainerTarget = i,
        handIndex = handIndex,
      }
    end
  elseif need == "opp_bench" then
    for i, mon in ipairs(foe.bench) do
      self.subItems[#self.subItems + 1] = {
        label = nameLv(mon),
        right = "BN" .. i,
        trainerTarget = i,
        handIndex = handIndex,
      }
    end
  elseif need == "own_any" then
    if side.active then
      self.subItems[#self.subItems + 1] = {
        label = nameLv(side.active),
        right = "ACT",
        trainerTarget = "active",
        handIndex = handIndex,
      }
    end
    for i, mon in ipairs(side.bench) do
      self.subItems[#self.subItems + 1] = {
        label = nameLv(mon),
        right = "BN" .. i,
        trainerTarget = i,
        handIndex = handIndex,
      }
    end
  elseif need == "own_hand" then
    -- Pokemon Trader: pick a Pokemon to put back (index after trainer leave).
    for i, id in ipairs(side.hand) do
      if i ~= handIndex then
        local c = Cache.card(id)
        if c and c.kind == "pokemon" then
          local adj = i > handIndex and (i - 1) or i
          local label = c.name or ("#" .. id)
          if #label > 10 then label = label:sub(1, 10) end
          self.subItems[#self.subItems + 1] = {
            label = label,
            right = "HND",
            trainerTarget = adj,
            handIndex = handIndex,
          }
        end
      end
    end
  elseif need == "own_discard_basic" then
    local seen = {}
    for _, id in ipairs(side.discard) do
      if not seen[id] then
        local c = Cache.card(id)
        if isBasicPkmn(c) then
          seen[id] = true
          local label = c.name or ("#" .. id)
          if #label > 10 then label = label:sub(1, 10) end
          self.subItems[#self.subItems + 1] = {
            label = label,
            right = "DSC",
            trainerTarget = id,
            handIndex = handIndex,
          }
        end
      end
    end
  elseif need == "opp_discard_basic" then
    local seen = {}
    for _, id in ipairs(foe.discard) do
      if not seen[id] then
        local c = Cache.card(id)
        if isBasicPkmn(c) then
          seen[id] = true
          local label = c.name or ("#" .. id)
          if #label > 10 then label = label:sub(1, 10) end
          self.subItems[#self.subItems + 1] = {
            label = label,
            right = "DSC",
            trainerTarget = id,
            handIndex = handIndex,
          }
        end
      end
    end
  elseif need == "breed" then
    -- Step 1: Stage 2 in hand (excluding trainer).
    for i, id in ipairs(side.hand) do
      if i ~= handIndex then
        local c = Cache.card(id)
        if c and c.kind == "pokemon" and c.stage == "STAGE2" then
          local adj = i > handIndex and (i - 1) or i
          local label = c.name or ("#" .. id)
          if #label > 10 then label = label:sub(1, 10) end
          self.subItems[#self.subItems + 1] = {
            label = label,
            right = "S2",
            breedHandAdj = adj,
            handIndex = handIndex,
          }
        end
      end
    end
  end
  if #self.subItems == 0 then
    self:setMessage("No target!")
    return
  end
  self.mode = need == "breed" and "breed_evo" or "trainer"
  self.subIndex = 1
end

function Screen:openBreedMonTarget(handIndex, breedHandAdj)
  local side = self.battle.player
  self.subItems = {}
  -- breedHandAdj is Stage2 index after the trainer card leaves the hand.
  local absEvo = breedHandAdj
  if breedHandAdj >= handIndex then
    absEvo = breedHandAdj + 1
  end
  local evo = Cache.card(side.hand[absEvo])
  local function tryAdd(mon, monTarget)
    if not mon or not mon.card or not evo then return end
    if (mon.card.stage or "BASIC") ~= "BASIC" then return end
    if mon.justPlayed or mon.evolvedThisTurn then return end
    self.subItems[#self.subItems + 1] = {
      label = nameLv(mon),
      right = monTarget == "active" and "ACT" or "BN",
      trainerTarget = { monTarget = monTarget, handIndex = breedHandAdj },
      handIndex = handIndex,
    }
  end
  tryAdd(side.active, "active")
  for i, mon in ipairs(side.bench) do
    tryAdd(mon, i)
  end
  if #self.subItems == 0 then
    self:setMessage("No breed target!")
    return
  end
  self.mode = "trainer"
  self.subIndex = 1
end



local function checkEntry(mon, right)
  local hp = math.max(0, (mon.maxHp or 0) - (mon.damage or 0))
  return {
    label = nameLv(mon),
    right = right,
    cardId = mon.cardId,
    damage = mon.damage or 0,
    maxHp = mon.maxHp or 0,
    hp = hp,
  }
end

function Screen:openCheck()
  local you = self.battle.player
  local opp = self.battle.opp
  self.subItems = {}
  if you.active then
    self.subItems[#self.subItems + 1] = checkEntry(you.active, "YOU")
  end
  for i, mon in ipairs(you.bench) do
    self.subItems[#self.subItems + 1] = checkEntry(mon, "YB" .. i)
  end
  if opp.active then
    self.subItems[#self.subItems + 1] = checkEntry(opp.active, "OPP")
  end
  for i, mon in ipairs(opp.bench) do
    self.subItems[#self.subItems + 1] = checkEntry(mon, "OB" .. i)
  end
  if #self.subItems == 0 then
    self:setMessage("No Pokémon!")
    return
  end
  self.mode = "check"
  self.subIndex = 1
end


function Screen:chooseMain()
  local item = MAIN[self.cursor]
  if not item then return end
  if item.id == "hand" then
    self:openHand()
  elseif item.id == "check" then
    self:openCheck()
  elseif item.id == "retreat" then
    self:openRetreat()
  elseif item.id == "attack" then
    self:openAttack()
  elseif item.id == "power" then
    self:setMessage("No PokéPOWER!")
  elseif item.id == "done" then
    self.battle:endTurn()
    self:flushLog()
    self:enterMain()
  end
end

function Screen:chooseSub()
  local item = self.subItems[self.subIndex]
  if not item then return end
  local b = self.battle

  if self.mode == "hand" then
    local Effects = V.require("effects")
    local card = Cache.card(item.cardId)
    if card and card.kind == "pokemon" then
      if Battle.isBenchable(card) then
        local ok, err = b:playBasic(item.handIndex, b.player)
        self:setMessage(ok and "To the Bench!" or (err or "Fail"))
        self:flushLog()
        self:enterMain()
      else
        self:openEvolveTarget(item.handIndex)
      end
    elseif card and card.kind == "energy" then
      self:openEnergyTarget(item.handIndex)
    elseif card and card.kind == "trainer" then
      local need = Effects.trainerNeedsTarget(card.key)
      if need then
        self:openTrainerTarget(item.handIndex, need)
      else
        local ok, err = b:playTrainer(item.handIndex)
        self:setMessage(ok and (err or "Played!") or (err or "Fail"))
        self:flushLog()
        self:enterMain()
      end
    else
      self:setMessage("Can't play")
    end
    return
  end

  if self.mode == "energy" then
    local ok, err = b:attachEnergy(item.handIndex, item.energyTarget)
    self:setMessage(ok and "Energy attached!" or (err or "Fail"))
    self:flushLog()
    self:enterMain()
    return
  end

  if self.mode == "evolve" then
    local ok, err = b:evolve(item.handIndex, item.evoTarget)
    self:setMessage(ok and "Evolved!" or (err or "Fail"))
    self:flushLog()
    self:enterMain()
    return
  end

  if self.mode == "breed_evo" then
    self:openBreedMonTarget(item.handIndex, item.breedHandAdj)
    return
  end

  if self.mode == "trainer" then
    local ok, err = b:playTrainer(item.handIndex, item.trainerTarget)
    self:setMessage(ok and (err or "Played!") or (err or "Fail"))
    self:flushLog()
    self:enterMain()
    return
  end

  if self.mode == "check" then
    self.mod.ui.push(self.game, "TcgCardView", {
      cardId = item.cardId,
      damage = item.damage,
      maxHp = item.maxHp,
      title = item.right,
    })
    return
  end


  if self.mode == "attack" then
    if not item.ok then
      self:setMessage("Not enough Energy!")
      return
    end
    local ok, err = b:attack(item.atkIndex)
    self:flushLog()
    if not ok then
      self:setMessage(err or "Can't attack")
      return
    end
    self:afterAttackResolve()
    return
  end

  if self.mode == "retreat" then
    local ok, err = b:retreat(item.benchIndex)
    self:flushLog()
    self:setMessage(ok and "Retreated!" or (err or "Fail"))
    self:enterMain()
  end
end

function Screen:update()
  local input = self.game.input
  if self.error or self.done then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
    end
    return
  end

  if self.mode == "anim" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.atkFx = nil
      self:enterMain()
      return
    end
    if AttackFx.update(self.atkFx) then
      self.atkFx = nil
      self:enterMain()
    end
    return
  end

  if self.mode == "opp" then
    if input:wasPressed("a") then
      self:runOpponent()
    elseif input:wasPressed("b") then
      self.game.stack:pop()
    end
    return
  end

  if self.mode == "main" then
    local col = ((self.cursor - 1) % 3)
    local row = math.floor((self.cursor - 1) / 3)
    if input:wasPressed("left") then
      col = (col + 2) % 3
    elseif input:wasPressed("right") then
      col = (col + 1) % 3
    elseif input:wasPressed("up") then
      row = (row + 1) % 2
    elseif input:wasPressed("down") then
      row = (row + 1) % 2
    elseif input:wasPressed("a") then
      self:chooseMain()
    elseif input:wasPressed("b") then
      self.game.stack:pop()
    end
    self.cursor = row * 3 + col + 1
    return
  end

  -- submenu
  if input:wasPressed("up") then
    self.subIndex = math.max(1, self.subIndex - 1)
  elseif input:wasPressed("down") then
    self.subIndex = math.min(#self.subItems, self.subIndex + 1)
  elseif input:wasPressed("a") then
    self:chooseSub()
  elseif input:wasPressed("b") then
    self:enterMain()
  end
end

-- --- drawing helpers -------------------------------------------------------

local function drawText(text, x, y)
  love.graphics.setColor(0, 0, 0, 1)
  Font().draw(text, math.floor(x + 0.5), math.floor(y + 0.5))
end

local function drawZigzag()
  love.graphics.setColor(0.18, 0.62, 0.28, 1)
  local y0 = 50
  for x = 0, 160, 8 do
    love.graphics.polygon("fill",
      x, y0 + 4,
      x + 4, y0 - 2,
      x + 8, y0 + 4,
      x + 8, y0 + 8,
      x + 4, y0 + 14,
      x, y0 + 8)
  end
end

local function drawHpOrbs(x, y, current, maxHp)
  local total = math.max(1, math.ceil((maxHp or 10) / 10))
  local filled = math.ceil((current or 0) / 10)
  total = math.min(total, 10)
  for i = 1, total do
    local ox = x + (i - 1) * 8
    love.graphics.setColor(0.05, 0.05, 0.05, 1)
    if i <= filled then
      love.graphics.circle("fill", ox + 3, y + 3, 3)
    else
      love.graphics.circle("line", ox + 3, y + 3, 3)
    end
  end
end

local function drawTypePip(x, y, typ)
  local r, g, b = CardGfx.typeColor({ kind = "pokemon", type = typ or "COLORLESS" })
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", x, y, 7, 7)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", x, y, 7, 7)
end

local function drawEnergyRow(x, y, mon)
  drawText("E", x, y)
  local list = energyList(mon)
  local ox = x + 10
  for i, typ in ipairs(list) do
    if i > 6 then break end
    drawTypePip(ox, y, typ)
    ox = ox + 9
  end
end

-- Bench (dark square) · Prizes (gold card backs) · Deck (purple)
local function drawBenchPrizeDeck(x, y, benchN, prizeN, deckN)
  love.graphics.setColor(0.15, 0.15, 0.15, 1)
  love.graphics.rectangle("fill", x, y, 6, 6)
  drawText(tostring(benchN or 0), x + 8, y - 1)

  local px = x + 24
  local n = math.min(prizeN or 0, 6)
  for i = 1, n do
    love.graphics.setColor(0.72, 0.55, 0.12, 1)
    love.graphics.rectangle("fill", px + (i - 1) * 2, y - (i - 1), 5, 7)
    love.graphics.setColor(0.2, 0.15, 0.05, 1)
    love.graphics.rectangle("line", px + (i - 1) * 2, y - (i - 1), 5, 7)
  end
  drawText(tostring(prizeN or 0), px + 14, y - 1)

  love.graphics.setColor(0.35, 0.25, 0.55, 1)
  love.graphics.rectangle("fill", x + 56, y, 5, 7)
  drawText(tostring(deckN or 0), x + 64, y - 1)
end


local function drawHandCursor(x, y)
  love.graphics.setColor(0.95, 0.82, 0.45, 1)
  love.graphics.polygon("fill",
    x, y + 1, x + 5, y + 1, x + 5, y + 5, x + 9, y + 5,
    x + 9, y + 10, x + 2, y + 10, x + 2, y + 7, x, y + 7)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.polygon("line",
    x, y + 1, x + 5, y + 1, x + 5, y + 5, x + 9, y + 5,
    x + 9, y + 10, x + 2, y + 10, x + 2, y + 7, x, y + 7)
end

local function monType(mon)
  local card = mon and (mon.card or Cache.card(mon.cardId))
  return card and card.type or "COLORLESS"
end

local function shortName(mon, maxLen)
  local label = nameLv(mon)
  if #label > maxLen then label = label:sub(1, maxLen) end
  return label
end

local function statusTag(mon)
  if not mon then return "" end
  if mon.asleep then return "SLP" end
  if mon.paralyzed then return "PAR" end
  if mon.confused then return "CNF" end
  if mon.poisoned then return "PSN" end
  return ""
end


function Screen:drawField()
  local b = self.battle
  local fx = self.atkFx
  local oxs, oys = AttackFx.shake(fx, "opp")
  local pxs, pys = AttackFx.shake(fx, "player")

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 104)
  drawZigzag()

  local opp, you = b.opp, b.player

  drawBenchPrizeDeck(4, 4, #opp.bench, #opp.prizes, #opp.deck)
  if opp.active then
    drawEnergyRow(4, 14, opp.active)
    drawTypePip(4, 26, monType(opp.active))
    drawText(shortName(opp.active, 10), 14, 26)
    local ot = statusTag(opp.active)
    if ot ~= "" then drawText(ot, 14, 34) end
    local ohp, omax = hpNow(opp.active)
    drawText("HP", 4, 42)
    drawHpOrbs(22, 42, ohp, omax)
    CardGfx.drawPortrait(opp.active.cardId, 92 + oxs, 6 + oys, 1)
  end

  if you.active then
    CardGfx.drawPortrait(you.active.cardId, 6 + pxs, 56 + pys, 1)
    drawEnergyRow(74, 56, you.active)
    drawTypePip(74, 68, monType(you.active))
    drawText(shortName(you.active, 9), 84, 68)
    local yt = statusTag(you.active)
    if yt ~= "" then drawText(yt, 84, 76) end
    local php, pmax = hpNow(you.active)
    drawText("HP", 74, 84)
    drawHpOrbs(92, 84, php, pmax)

    drawBenchPrizeDeck(74, 92, #you.bench, #you.prizes, #you.deck)
  end

  AttackFx.draw(fx)
end


function Screen:drawMenuBox()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 104, 160, 40)
  love.graphics.setColor(0.85, 0.15, 0.12, 1)
  love.graphics.rectangle("line", 1, 105, 158, 38)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", 3, 107, 154, 34)

  if self.mode == "main" then
    for i, item in ipairs(MAIN) do
      drawText(item.label, item.x, item.y)
      if item.label2 then
        drawText(item.label2, item.x, item.y + 8)
      end
      if i == self.cursor then
        drawHandCursor(item.x - 12, item.y + (item.label2 and 2 or 0))
      end
    end
  elseif self.mode == "anim" then
    local name = self.atkFx and self.atkFx.name or "ATTACK"
    if #name > 14 then name = name:sub(1, 14) end
    drawText(name, 8, 114)
    drawText("A: skip", 8, 128)
  elseif self.mode == "opp" then
    drawText(self.message or "Opponent's turn", 8, 114)
    drawText("A: continue", 8, 128)
  elseif self.mode == "done" then
    drawText(self.message or "Done", 8, 114)
    drawText("A: exit", 8, 128)
  else
    local modeLabel = self.mode:upper()
    if self.mode == "check" then modeLabel = "CHECK" end
    drawText(modeLabel, 8, 110)
    local item = self.subItems[self.subIndex]
    if item then
      local label = item.label or "?"
      if item.right then label = item.right .. " " .. label end
      if #label > 17 then label = label:sub(1, 17) end
      drawText(">" .. label, 8, 120)
      if item.ok == false then
        drawText("(need Energy)", 8, 130)
      elseif self.mode == "check" and item.hp then
        drawText(("HP%d %d/%d A:view"):format(item.hp, self.subIndex, #self.subItems), 8, 130)
      else
        drawText(("%d/%d A:ok B:back"):format(self.subIndex, #self.subItems), 8, 130)
      end
    end
  end
end

function Screen:draw()
  if self.error then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    drawText(self.error, 8, 56)
    drawText("B: back", 8, 120)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  self:drawField()
  self:drawMenuBox()

  if self.message and self.mode == "main" then
    local msg = self.message
    if #msg > 18 then msg = msg:sub(1, 18) end
    drawText(msg, 4, 96)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return Screen



