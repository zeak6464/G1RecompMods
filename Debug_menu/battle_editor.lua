-- Live in-game battle pic placement for DebugMenu.
-- Drag the player/enemy sprites; offsets are stored per species.

return function(H)
  local SAVE_FILE = "debug_battle_edits.lua"
  local liveEdit = false
  local pos = {} -- [species] = { frontX, frontY, backX, backY }
  local lastVp = nil
  local drag = nil
  local undoStack = {}
  local UNDO_MAX = 50
  local patched = {}

  local function isBattleScreen(s)
    return s and (s.isBattle or s.drawPic or s.drawPicsLayer) or false
  end

  local function battleOf(game)
    local stack = game and game.stack
    if not (stack and stack.top) then return nil end
    local top = stack:top()
    if isBattleScreen(top) then return top end
    return nil
  end

  local function speciesOf(battle, side)
    if not battle then return nil end
    local mon
    if side == "player" then
      mon = (battle.battle and battle.battle.player) or battle.player
    else
      mon = (battle.battle and battle.battle.enemy) or battle.enemy
    end
    if not mon then return nil end
    return mon.species or (mon.mon and mon.mon.species)
  end

  local function getXY(species, side)
    local row = species and pos[species]
    if not row then return 0, 0 end
    if side == "player" then
      return row.backX or 0, row.backY or 0
    end
    return row.frontX or 0, row.frontY or 0
  end

  local function setXY(species, side, x, y)
    if not species then return end
    pos[species] = pos[species] or {}
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    if side == "player" then
      pos[species].backX, pos[species].backY = x, y
    else
      pos[species].frontX, pos[species].frontY = x, y
    end
  end

  local function pushUndo(entry)
    undoStack[#undoStack + 1] = entry
    while #undoStack > UNDO_MAX do
      table.remove(undoStack, 1)
    end
  end

  local function quote(s)
    return string.format("%q", tostring(s or ""))
  end

  local function dumpValue(v, indent)
    indent = indent or ""
    local ty = type(v)
    if ty == "string" then return quote(v) end
    if ty == "number" or ty == "boolean" then return tostring(v) end
    if ty ~= "table" then return "nil" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "{" }
    for _, k in ipairs(keys) do
      local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k
        or ("[" .. quote(k) .. "]")
      parts[#parts + 1] = "\n" .. indent .. "  " .. key .. " = "
        .. dumpValue(v[k], indent .. "  ") .. ","
    end
    parts[#parts + 1] = "\n" .. indent .. "}"
    return table.concat(parts)
  end

  local function writeSaved()
    local payload = {}
    for id, row in pairs(pos) do
      if type(id) == "string" and type(row) == "table" then
        if (row.frontX or 0) ~= 0 or (row.frontY or 0) ~= 0
           or (row.backX or 0) ~= 0 or (row.backY or 0) ~= 0 then
          payload[id] = {
            frontX = row.frontX or 0, frontY = row.frontY or 0,
            backX = row.backX or 0, backY = row.backY or 0,
          }
        end
      end
    end
    local body = "-- DebugMenu live battle pic positions\nreturn "
      .. dumpValue(payload) .. "\n"
    if love and love.filesystem and love.filesystem.write then
      love.filesystem.write(SAVE_FILE, body)
    end
    if love and love.system and love.system.setClipboardText then
      pcall(love.system.setClipboardText, body)
    end
    print("[DebugMenu] battle pic edits:\n" .. body)
    return true, body
  end

  local function applySaved()
    if not (love and love.filesystem and love.filesystem.read) then return end
    if not love.filesystem.getInfo(SAVE_FILE) then return end
    local body = love.filesystem.read(SAVE_FILE)
    if type(body) ~= "string" or body == "" then return end
    local chunk, err = load(body, SAVE_FILE)
    if not chunk then
      print("[DebugMenu] battle edits load failed: " .. tostring(err))
      return
    end
    local ok, payload = pcall(chunk)
    if not (ok and type(payload) == "table") then return end
    for id, row in pairs(payload) do
      if type(id) == "string" and type(row) == "table" then
        pos[id] = {
          frontX = math.floor(tonumber(row.frontX) or 0),
          frontY = math.floor(tonumber(row.frontY) or 0),
          backX = math.floor(tonumber(row.backX) or 0),
          backY = math.floor(tonumber(row.backY) or 0),
        }
      end
    end
    print("[DebugMenu] reapplied live battle pic edits.")
  end

  local function defaultBox(side)
    if H.isGen2() then
      if side == "player" then return 16, 48, 48, 48 end
      return 96, 0, 56, 56
    end
    if side == "player" then return 8, 32, 64, 64 end
    return 96, 0, 56, 56
  end

  local function boxFor(battle, side)
    local x, y, w, h = defaultBox(side)
    local sp = speciesOf(battle, side)
    local ox, oy = getXY(sp, side)
    return { x = x + ox, y = y + oy, w = w, h = h, species = sp, side = side }
  end

  local function hitSide(battle, gx, gy)
    for _, side in ipairs({ "player", "enemy" }) do
      local b = boxFor(battle, side)
      if b.species and gx >= b.x and gy >= b.y
         and gx < b.x + b.w and gy < b.y + b.h then
        return b
      end
    end
    return nil
  end

  local function windowToGame(x, y)
    if lastVp and lastVp.gameX then
      local s = lastVp.scale or 1
      if s == 0 then s = 1 end
      return (x - lastVp.gameX) / s, (y - lastVp.gameY) / s
    end
    local ww, wh = love.graphics.getDimensions()
    local s = math.max(1, math.floor(math.min(ww / 160, wh / 144)))
    local ox = math.floor((ww - 160 * s) / 2)
    local oy = math.floor((wh - 144 * s) / 2)
    return (x - ox) / s, (y - oy) / s
  end

  local function patchGen2(BS)
    if not (BS and BS.drawPic) or patched[BS] then return end
    patched[BS] = true
    local orig = BS.drawPic
    BS.drawPic = function(self, mon, back)
      local species = mon and mon.species
      local ox, oy = getXY(species, back and "player" or "enemy")
      if ox == 0 and oy == 0 then
        return orig(self, mon, back)
      end
      love.graphics.push()
      love.graphics.translate(ox, oy)
      orig(self, mon, back)
      love.graphics.pop()
    end
  end

  local function patchGen1(BS)
    if not (BS and BS.drawPicsLayer) or patched[BS] then return end
    patched[BS] = true
    local orig = BS.drawPicsLayer
    BS.drawPicsLayer = function(self, slide, sx, sy, onlySide, skipMenuClip)
      local function run(side)
        local mon = side == "player" and self.player or self.enemy
        local species = mon and ((mon.mon and mon.mon.species) or mon.species)
        local ox, oy = getXY(species, side)
        if ox ~= 0 or oy ~= 0 then
          love.graphics.push()
          love.graphics.translate(ox, oy)
        end
        orig(self, slide, sx, sy, side, skipMenuClip)
        if ox ~= 0 or oy ~= 0 then love.graphics.pop() end
      end
      if onlySide == "player" or onlySide == "enemy" then
        run(onlySide)
      else
        run("enemy")
        run("player")
      end
    end
  end

  local function ensurePatched()
    if H.isGen2() then
      local ok, BS = pcall(require, "src.ui.gen2.BattleState")
      if ok then patchGen2(BS) end
    else
      local ok, BS = pcall(require, "src.battle.BattleState")
      if ok then patchGen1(BS) end
    end
  end

  local function undoPaint(game)
    if drag then
      setXY(drag.species, drag.side, drag.origX, drag.origY)
      drag = nil
      return true
    end
    if #undoStack == 0 then return false, "NOTHING TO UNDO." end
    local e = undoStack[#undoStack]
    undoStack[#undoStack] = nil
    setXY(e.species, e.side, e.x, e.y)
    return true
  end

  local function nudge(game, side, dx, dy)
    local battle = battleOf(game)
    local sp = speciesOf(battle, side)
    if not sp then return false, "NO BATTLE." end
    local x, y = getXY(sp, side)
    pushUndo({ species = sp, side = side, x = x, y = y })
    setXY(sp, side, x + dx, y + dy)
    return true
  end

  local function resetSide(game, side)
    local battle = battleOf(game)
    local sp = speciesOf(battle, side)
    if not sp then return false, "NO BATTLE." end
    local x, y = getXY(sp, side)
    pushUndo({ species = sp, side = side, x = x, y = y })
    setXY(sp, side, 0, 0)
    return true
  end

  local function openMenu(game)
    ensurePatched()
    local battle = battleOf(game)
    local pSp = speciesOf(battle, "player") or "--"
    local eSp = speciesOf(battle, "enemy") or "--"
    local px, py = getXY(speciesOf(battle, "player"), "player")
    local ex, ey = getXY(speciesOf(battle, "enemy"), "enemy")
    H.pushList(game, {
      H.toggleRow(function()
        return liveEdit and "PIC EDIT: ON" or "PIC EDIT: OFF"
      end, function()
        liveEdit = not liveEdit
        if liveEdit then ensurePatched() end
      end),
      {
        label = string.format("Player %s %d,%d", pSp, px, py),
        keepOpen = true,
        onSelect = function()
          H.pushNumberPicker(game, {
            title = "PLAYER X",
            min = -64, max = 64, value = px,
            onConfirm = function(vx)
              H.pushNumberPicker(game, {
                title = "PLAYER Y",
                min = -64, max = 64, value = py,
                onConfirm = function(vy)
                  local sp = speciesOf(battleOf(game), "player")
                    or speciesOf(battle, "player")
                  if not sp then return end
                  local ox, oy = getXY(sp, "player")
                  pushUndo({ species = sp, side = "player", x = ox, y = oy })
                  setXY(sp, "player", vx, vy)
                  H.showMsg(game, string.format("PLAYER %d,%d", vx, vy))
                end,
              })
            end,
          })
        end,
      },
      {
        label = string.format("Enemy %s %d,%d", eSp, ex, ey),
        keepOpen = true,
        onSelect = function()
          H.pushNumberPicker(game, {
            title = "ENEMY X",
            min = -64, max = 64, value = ex,
            onConfirm = function(vx)
              H.pushNumberPicker(game, {
                title = "ENEMY Y",
                min = -64, max = 64, value = ey,
                onConfirm = function(vy)
                  local sp = speciesOf(battleOf(game), "enemy")
                    or speciesOf(battle, "enemy")
                  if not sp then return end
                  local ox, oy = getXY(sp, "enemy")
                  pushUndo({ species = sp, side = "enemy", x = ox, y = oy })
                  setXY(sp, "enemy", vx, vy)
                  H.showMsg(game, string.format("ENEMY %d,%d", vx, vy))
                end,
              })
            end,
          })
        end,
      },
      {
        label = "Reset player",
        keepOpen = true,
        onSelect = function()
          local ok, err = resetSide(game, "player")
          H.showMsg(game, ok and "PLAYER RESET." or (err or "FAIL."))
        end,
      },
      {
        label = "Reset enemy",
        keepOpen = true,
        onSelect = function()
          local ok, err = resetSide(game, "enemy")
          H.showMsg(game, ok and "ENEMY RESET." or (err or "FAIL."))
        end,
      },
      {
        label = "Undo (Ctrl+Z)",
        keepOpen = true,
        onSelect = function()
          local ok, err = undoPaint(game)
          H.showMsg(game, ok and "UNDONE." or (err or "FAIL."))
        end,
      },
      {
        label = "Dump Lua",
        onSelect = function()
          local ok = writeSaved()
          H.showMsg(game, ok and "DUMPED BATTLE EDITS." or "DUMP FAILED.")
        end,
      },
    })
  end

  local function drawOverlay(battle)
    if not liveEdit or not H.hudOn or not H.hudOn() then return end
    ensurePatched()
    local Font = require("src.render.Font")
    local px, py = getXY(speciesOf(battle, "player"), "player")
    local ex, ey = getXY(speciesOf(battle, "enemy"), "enemy")
    Font.draw(string.format("PICS P %d,%d  E %d,%d", px, py, ex, ey), 8, 80)
    Font.draw("DRAG  CTRL+Z", 8, 88)
  end

  local function onPointer(game, ev)
    if not liveEdit or not game or not ev then return false end
    local battle = battleOf(game)
    if not battle then
      drag = nil
      return false
    end
    ensurePatched()
    if ev.phase == "cancelled" then
      if drag then
        setXY(drag.species, drag.side, drag.origX, drag.origY)
        drag = nil
      end
      return false
    end
    local gx, gy = windowToGame(ev.x, ev.y)
    if ev.phase == "pressed" then
      if ev.button ~= nil and ev.button ~= 1 then return false end
      local hit = hitSide(battle, gx, gy)
      if not hit then return false end
      local ox, oy = getXY(hit.species, hit.side)
      drag = {
        species = hit.species, side = hit.side,
        origX = ox, origY = oy,
        grabX = gx - ox, grabY = gy - oy,
      }
      return true
    elseif ev.phase == "moved" then
      if not drag then return false end
      setXY(drag.species, drag.side, gx - drag.grabX, gy - drag.grabY)
      return true
    elseif ev.phase == "released" then
      if not drag then return false end
      local nx, ny = getXY(drag.species, drag.side)
      if nx ~= drag.origX or ny ~= drag.origY then
        pushUndo({
          species = drag.species, side = drag.side,
          x = drag.origX, y = drag.origY,
        })
      end
      drag = nil
      return true
    end
    return false
  end

  local function onKey(key)
    local game = H.liveGame()
    if not liveEdit or not game or not battleOf(game) then return false end
    if key == "undo" then
      local ok, err = undoPaint(game)
      if not ok and err then H.showMsg(game, err) end
      return true
    end
    return false
  end

  return {
    openMenu = openMenu,
    drawOverlay = drawOverlay,
    onPointer = onPointer,
    onKey = onKey,
    setViewport = function(vp) lastVp = vp end,
    applySaved = applySaved,
    ensurePatched = ensurePatched,
    isBattleScreen = isBattleScreen,
  }
end
