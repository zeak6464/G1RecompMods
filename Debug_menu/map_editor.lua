-- Live in-game map editor for DebugMenu.
-- Mutates the loaded map records and rebuilds neighbor strips / warp
-- lookups so connections and doors can be tested while walking.

return function(H)
  local liveEdit = false
  local SAVE_FILE = "debug_map_edits.lua"
  local DIR_ORDER = { "north", "south", "east", "west" }
  local FACE_DIR = { up = "north", down = "south", left = "west", right = "east" }
  local OPP = { north = "south", south = "north", east = "west", west = "east" }
  local dirty = {} -- [mapId] = { connections = true, warps = true }
  local dirtyTilesets = {}

  local function mapsOf(game)
    return H.mapsTable(game)
  end

  local function currentMapId(game)
    local world = H.worldOf(game)
    return world and world.map and world.map.id
  end

  local function currentDef(game)
    local world = H.worldOf(game)
    if world and world.map and world.map.def then return world.map.def end
    local id = currentMapId(game)
    local maps = mapsOf(game)
    return id and maps and maps[id]
  end

  local function connDest(conn)
    if type(conn) ~= "table" then return nil end
    local function named(id)
      return type(id) == "string" and id ~= "" and tonumber(id) == nil and id or nil
    end
    return named(conn.mapId) or named(conn.map)
  end

  local function markDirty(mapId, kind)
    if not mapId then return end
    dirty[mapId] = dirty[mapId] or {}
    dirty[mapId][kind] = true
  end

  local function rebuildWarpLookup(map)
    if not map then return end
    local warps = map.warps or (map.def and map.def.warps) or {}
    if map.warpAt then
      local t = {}
      local wcells = map.widthCells or 1
      for i, w in ipairs(warps) do
        if type(w) == "table" then
          t[(tonumber(w.y) or 0) * wcells + (tonumber(w.x) or 0)] = { index = i, def = w }
        end
      end
      map.warpAt = t
    end
    if map._warpAt then
      local t = {}
      for i, w in ipairs(warps) do
        if type(w) == "table" then
          t[(tonumber(w.y) or 0) * 1024 + (tonumber(w.x) or 0)] = { index = i, def = w }
        end
      end
      map._warpAt = t
    end
  end

  local function refreshLive(game, mapId)
    local world = H.worldOf(game)
    if not world then return end
    if world.map then
      if world.map.def and world.map.def.connections then
        world.map.connections = world.map.def.connections
      end
      rebuildWarpLookup(world.map)
    end
    if world.rebuildNeighbors then
      pcall(function() world:rebuildNeighbors() end)
    end
    if H.isGen2() and world.dropMapImages and mapId then
      pcall(function() world:dropMapImages(mapId) end)
      pcall(function() world:refreshMapImages() end)
    end
  end

  local function makeConn(destDef, destId, offset, prev)
    local entry = { mapId = destId, offset = math.floor(tonumber(offset) or 0) }
    if type(prev) == "table" and connDest(prev) == destId then
      for _, key in ipairs({ "group", "map", "stripLength", "width", "xOffset", "yOffset" }) do
        entry[key] = prev[key]
      end
    elseif destDef then
      entry.group = destDef.group
      if type(destDef.map) == "number" then
        entry.map = destDef.map
      else
        entry.map = destId
      end
    else
      entry.map = destId
    end
    if entry.map == nil then entry.map = destId end
    return entry
  end

  local function setConnection(game, fromId, dir, destId, offset)
    local maps = mapsOf(game)
    local from = maps and maps[fromId]
    if not from then return false, "NO MAP." end
    from.connections = from.connections or {}
    local opp = OPP[dir]
    local prev = from.connections[dir]
    local prevDest = connDest(prev)

    local function clearBack(otherId)
      if not (otherId and opp) then return end
      local other = maps[otherId]
      if not other then return end
      other.connections = other.connections or {}
      local back = other.connections[opp]
      if connDest(back) == fromId then
        other.connections[opp] = nil
        markDirty(otherId, "connections")
      end
    end

    offset = math.floor(tonumber(offset) or 0)
    if not destId or destId == "" then
      if prevDest then clearBack(prevDest) end
      from.connections[dir] = nil
    else
      if prevDest and prevDest ~= destId then clearBack(prevDest) end
      from.connections[dir] = makeConn(maps[destId], destId, offset, prev)
      if opp and maps[destId] then
        local dest = maps[destId]
        dest.connections = dest.connections or {}
        dest.connections[opp] = makeConn(from, fromId, -offset, dest.connections[opp])
        markDirty(destId, "connections")
      end
    end
    markDirty(fromId, "connections")
    refreshLive(game, fromId)
    return true
  end

  local function facingDir(game)
    local world = H.worldOf(game)
    local facing = world and world.player and world.player.facing
    return FACE_DIR[facing or "down"] or "south"
  end

  local function nudgeFacingOffset(game, delta)
    local mapId = currentMapId(game)
    local def = currentDef(game)
    local dir = facingDir(game)
    if not (mapId and def and dir) then return false end
    def.connections = def.connections or {}
    local cur = def.connections[dir]
    local dest = connDest(cur)
    if not dest then return false, "NO " .. dir:upper() .. " LINK." end
    return setConnection(game, mapId, dir, dest, (cur.offset or 0) + delta)
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
    local keys, isArray = {}, true
    for k in pairs(v) do
      keys[#keys + 1] = k
      if type(k) ~= "number" then isArray = false end
    end
    if isArray then
      table.sort(keys)
      local parts = { "{" }
      for _, k in ipairs(keys) do
        parts[#parts + 1] = "\n" .. indent .. "  " .. dumpValue(v[k], indent .. "  ") .. ","
      end
      parts[#parts + 1] = "\n" .. indent .. "}"
      return table.concat(parts)
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "{" }
    for _, k in ipairs(keys) do
      local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. quote(k) .. "]")
      parts[#parts + 1] = "\n" .. indent .. "  " .. key .. " = " .. dumpValue(v[k], indent .. "  ") .. ","
    end
    parts[#parts + 1] = "\n" .. indent .. "}"
    return table.concat(parts)
  end

  local function snapshot(def)
    local out = {}
    if type(def.connections) == "table" then
      local c = {}
      for _, dir in ipairs(DIR_ORDER) do
        local conn = def.connections[dir]
        if conn then
          c[dir] = {
            map = conn.map, mapId = conn.mapId or connDest(conn),
            offset = conn.offset or 0, group = conn.group,
            stripLength = conn.stripLength, width = conn.width,
            xOffset = conn.xOffset, yOffset = conn.yOffset,
          }
        end
      end
      out.connections = c
    end
    if type(def.warps) == "table" then
      local w = {}
      for i, warp in ipairs(def.warps) do
        w[i] = {
          x = warp.x, y = warp.y,
          destMap = warp.destMap, destWarp = warp.destWarp,
          destGroup = warp.destGroup, destMapNum = warp.destMapNum,
        }
      end
      out.warps = w
    end
    if type(def.blocks) == "table" then
      local b = {}
      for i = 1, #def.blocks do b[i] = def.blocks[i] end
      out.blocks = b
    end
    return out
  end

  local function tilesetById(game, tsId)
    if not tsId then return nil end
    local data = game and game.data
    local world = H.worldOf(game)
    return (data and data.gen2Tilesets and data.gen2Tilesets[tsId])
      or (data and data.tilesets and data.tilesets[tsId])
      or (world and world.tilesets and world.tilesets[tsId])
  end

  local function snapshotTilesets(game)
    local out = {}
    for tsId in pairs(dirtyTilesets) do
      local ts = tilesetById(game, tsId)
      if type(ts) == "table" then
        local row = {}
        if type(ts.collision) == "table" then
          local coll = {}
          for i, quad in pairs(ts.collision) do
            if type(quad) == "table" then
              coll[tostring(i)] = { quad[1], quad[2], quad[3], quad[4] }
            end
          end
          row.collision = coll
        end
        if type(ts.walkable) == "table" then
          local w = {}
          for i = 1, #ts.walkable do w[i] = ts.walkable[i] end
          row.walkable = w
        end
        if type(ts.waterTiles) == "table" then
          local w = {}
          for i = 1, #ts.waterTiles do w[i] = ts.waterTiles[i] end
          row.waterTiles = w
        end
        if type(ts.shoreTiles) == "table" then
          local w = {}
          for i = 1, #ts.shoreTiles do w[i] = ts.shoreTiles[i] end
          row.shoreTiles = w
        end
        if ts.grassTile ~= nil then row.grassTile = ts.grassTile end
        out[tsId] = row
      end
    end
    local field = game and game.data and game.data.field
    if field and type(field.ledges) == "table" then
      local extra = {}
      for _, ledge in ipairs(field.ledges) do
        if type(ledge) == "table" and ledge._debug then
          extra[#extra + 1] = {
            tileset = ledge.tileset, facing = ledge.facing, input = ledge.input,
            standingTile = ledge.standingTile, ledgeTile = ledge.ledgeTile,
            _debug = true,
          }
        end
      end
      if extra[1] then out._ledges = extra end
    end
    return out
  end

  local function writeSaved(game)
    local maps = mapsOf(game)
    if not maps then return false end
    local payload = {}
    for mapId, flags in pairs(dirty) do
      local def = maps[mapId]
      if type(def) == "table" then
        local snap = snapshot(def)
        local row = {}
        if flags.connections then row.connections = snap.connections end
        if flags.warps then row.warps = snap.warps end
        if flags.blocks then row.blocks = snap.blocks end
        if next(row) then payload[mapId] = row end
      end
    end
    if next(dirtyTilesets) then
      payload._tilesets = snapshotTilesets(game)
    end
    local body = "-- DebugMenu live map edits\nreturn " .. dumpValue(payload) .. "\n"
    if love and love.filesystem and love.filesystem.write then
      love.filesystem.write(SAVE_FILE, body)
    end
    if love and love.system and love.system.setClipboardText then
      pcall(love.system.setClipboardText, body)
    end
    print("[DebugMenu] map edits:\n" .. body)
    return true, body
  end

  local function applyPatch(maps, mapId, patch)
    local def = maps[mapId]
    if not (def and type(patch) == "table") then return end
    if type(patch.connections) == "table" then
      def.connections = def.connections or {}
      for _, dir in ipairs(DIR_ORDER) do
        def.connections[dir] = patch.connections[dir]
      end
      markDirty(mapId, "connections")
    end
    if type(patch.warps) == "table" then
      def.warps = patch.warps
      markDirty(mapId, "warps")
    end
    if type(patch.blocks) == "table" then
      def.blocks = def.blocks or {}
      for i = 1, #patch.blocks do
        def.blocks[i] = patch.blocks[i]
      end
      markDirty(mapId, "blocks")
    end
  end

  local function applyTilesets(data, patch)
    if type(patch) ~= "table" or not data then return end
    local bags = { data.gen2Tilesets, data.tilesets }
    for tsId, row in pairs(patch) do
      if tsId ~= "_ledges" and type(tsId) == "string" and type(row) == "table" then
        local ts
        for _, bag in ipairs(bags) do
          if bag and bag[tsId] then ts = bag[tsId]; break end
        end
        if ts then
          if type(row.collision) == "table" then
            ts.collision = ts.collision or {}
            for key, quad in pairs(row.collision) do
              local i = tonumber(key)
              if i and type(quad) == "table" then
                ts.collision[i] = { quad[1], quad[2], quad[3], quad[4] }
              end
            end
          end
          if type(row.walkable) == "table" then ts.walkable = row.walkable end
          if type(row.waterTiles) == "table" then ts.waterTiles = row.waterTiles end
          if type(row.shoreTiles) == "table" then ts.shoreTiles = row.shoreTiles end
          if row.grassTile ~= nil then ts.grassTile = row.grassTile end
          dirtyTilesets[tsId] = true
        end
      end
    end
    if type(patch._ledges) == "table" then
      data.field = data.field or {}
      data.field.ledges = data.field.ledges or {}
      for _, ledge in ipairs(patch._ledges) do
        if type(ledge) == "table" then
          ledge._debug = true
          data.field.ledges[#data.field.ledges + 1] = ledge
        end
      end
    end
  end

  local function applySaved(data)
    if not (love and love.filesystem and love.filesystem.read) then return end
    if not love.filesystem.getInfo(SAVE_FILE) then return end
    local body = love.filesystem.read(SAVE_FILE)
    if type(body) ~= "string" or body == "" then return end
    local chunk, err = load(body, SAVE_FILE)
    if not chunk then
      print("[DebugMenu] map edits load failed: " .. tostring(err))
      return
    end
    local ok, payload = pcall(chunk)
    if not (ok and type(payload) == "table") then return end
    local maps = data and (data.gen2Maps or data.maps)
    if type(payload._tilesets) == "table" then
      applyTilesets(data, payload._tilesets)
    end
    if type(maps) ~= "table" then return end
    for mapId, patch in pairs(payload) do
      if type(mapId) == "string" and mapId ~= "_tilesets" then
        applyPatch(maps, mapId, patch)
      end
    end
    print("[DebugMenu] reapplied live map edits.")
  end

  local function pickMap(game, title, onPick)
    local maps = mapsOf(game)
    local rows = {}
    for _, id in ipairs(H.sortedIds(maps)) do
      rows[#rows + 1] = {
        label = id,
        onSelect = function() onPick(id) end,
      }
    end
    H.pushList(game, rows, { emptyMsg = "NO MAPS.", title = title })
  end

  local function connLabel(def, dir)
    local conn = def and def.connections and def.connections[dir]
    local dest = connDest(conn)
    if not dest then return dir:upper() .. ": --" end
    return string.format("%s: %s @ %d", dir:upper(), dest, conn.offset or 0)
  end

  local function openDirMenu(game, dir)
    local mapId = currentMapId(game)
    local def = currentDef(game)
    if not (mapId and def) then
      H.showMsg(game, "NO MAP.")
      return
    end
    def.connections = def.connections or {}
    local rows = {
      {
        label = "Set dest map...",
        keepOpen = true,
        onSelect = function()
          pickMap(game, dir:upper(), function(destId)
            local cur = def.connections[dir]
            setConnection(game, mapId, dir, destId, cur and cur.offset or 0)
            H.showMsg(game, dir:upper() .. " -> " .. destId)
          end)
        end,
      },
      {
        label = "Set offset...",
        keepOpen = true,
        onSelect = function()
          local cur = def.connections[dir]
          if not connDest(cur) then
            H.showMsg(game, "SET DEST FIRST.")
            return
          end
          H.pushNumberPicker(game, {
            title = dir:upper() .. " OFFSET",
            min = -64, max = 64, value = cur.offset or 0,
            onConfirm = function(off)
              setConnection(game, mapId, dir, connDest(cur), off)
              H.showMsg(game, string.format("%s OFFSET %d", dir:upper(), off))
            end,
          })
        end,
      },
      {
        label = "Nudge -1",
        keepOpen = true,
        onSelect = function()
          local cur = def.connections[dir]
          if not connDest(cur) then
            H.showMsg(game, "SET DEST FIRST.")
            return
          end
          setConnection(game, mapId, dir, connDest(cur), (cur.offset or 0) - 1)
        end,
      },
      {
        label = "Nudge +1",
        keepOpen = true,
        onSelect = function()
          local cur = def.connections[dir]
          if not connDest(cur) then
            H.showMsg(game, "SET DEST FIRST.")
            return
          end
          setConnection(game, mapId, dir, connDest(cur), (cur.offset or 0) + 1)
        end,
      },
      {
        label = "Clear",
        onSelect = function()
          setConnection(game, mapId, dir, nil, 0)
          H.showMsg(game, dir:upper() .. " CLEARED.")
        end,
      },
    }
    local dest = connDest(def.connections[dir])
    if dest then
      rows[#rows + 1] = {
        label = "Warp to dest",
        onSelect = function()
          local maps = mapsOf(game)
          local x, y = H.landingCell(maps and maps[dest])
          H.warpToMap(game, dest, x, y)
        end,
      }
    end
    H.pushList(game, rows)
  end

  local function openConnections(game)
    local def = currentDef(game)
    if not def then
      H.showMsg(game, "NO MAP.")
      return
    end
    local rows = {}
    for _, dir in ipairs(DIR_ORDER) do
      local d = dir
      rows[#rows + 1] = {
        label = connLabel(def, d),
        keepOpen = true,
        onSelect = function() openDirMenu(game, d) end,
      }
    end
    rows[#rows + 1] = {
      label = "Connect facing...",
      keepOpen = true,
      onSelect = function()
        openDirMenu(game, facingDir(game))
      end,
    }
    H.pushList(game, rows)
  end

  local function newWarp(game, destId)
    local world = H.worldOf(game)
    local p = world and world.player
    local maps = mapsOf(game)
    local dest = maps and maps[destId]
    local warp = {
      x = p and p.cellX or 0,
      y = p and p.cellY or 0,
      destMap = destId,
      destWarp = 1,
    }
    if dest then
      warp.destGroup = dest.group
      warp.destMapNum = dest.map
    end
    return warp
  end

  local function openWarpEdit(game, warp, index)
    local mapId = currentMapId(game)
    local def = currentDef(game)
    local rows = {
      {
        label = string.format("At %d,%d", warp.x or 0, warp.y or 0),
        keepOpen = true,
        onSelect = function()
          local world = H.worldOf(game)
          local p = world and world.player
          if not p then return end
          warp.x, warp.y = p.cellX, p.cellY
          markDirty(mapId, "warps")
          refreshLive(game, mapId)
          H.showMsg(game, string.format("WARP %d MOVED.", index))
        end,
      },
      {
        label = "Dest map: " .. tostring(warp.destMap or "?"),
        keepOpen = true,
        onSelect = function()
          pickMap(game, "WARP DEST", function(destId)
            warp.destMap = destId
            local dest = destId and mapsOf(game) and mapsOf(game)[destId]
            if dest then
              warp.destGroup = dest.group
              warp.destMapNum = dest.map
            end
            markDirty(mapId, "warps")
            H.showMsg(game, "DEST " .. destId)
          end)
        end,
      },
      {
        label = "Dest warp: " .. tostring(warp.destWarp or 1),
        keepOpen = true,
        onSelect = function()
          H.pushNumberPicker(game, {
            title = "DEST WARP #",
            min = 1, max = 64, value = tonumber(warp.destWarp) or 1,
            onConfirm = function(n)
              warp.destWarp = n
              markDirty(mapId, "warps")
              H.showMsg(game, "DEST WARP " .. n)
            end,
          })
        end,
      },
      {
        label = "Take warp",
        onSelect = function()
          local destId = warp.destMap
          local dest = destId and mapsOf(game)[destId]
          local dw = dest and dest.warps and dest.warps[tonumber(warp.destWarp) or 1]
          if dw then
            H.warpToMap(game, destId, dw.x, dw.y)
          elseif dest then
            local x, y = H.landingCell(dest)
            H.warpToMap(game, destId, x, y)
          else
            H.showMsg(game, "NO DEST MAP.")
          end
        end,
      },
      {
        label = "Delete",
        onSelect = function()
          table.remove(def.warps, index)
          markDirty(mapId, "warps")
          refreshLive(game, mapId)
          H.showMsg(game, "WARP DELETED.")
        end,
      },
    }
    H.pushList(game, rows)
  end

  local function openWarps(game)
    local def = currentDef(game)
    if not def then
      H.showMsg(game, "NO MAP.")
      return
    end
    def.warps = def.warps or {}
    local rows = {
      {
        label = "Add at player...",
        keepOpen = true,
        onSelect = function()
          pickMap(game, "WARP DEST", function(destId)
            local warp = newWarp(game, destId)
            def.warps[#def.warps + 1] = warp
            markDirty(currentMapId(game), "warps")
            refreshLive(game, currentMapId(game))
            H.showMsg(game, "WARP ADDED.")
          end)
        end,
      },
    }
    for i, warp in ipairs(def.warps) do
      local idx = i
      local w = warp
      rows[#rows + 1] = {
        label = string.format("%d (%d,%d) > %s#%s",
          i, w.x or 0, w.y or 0, tostring(w.destMap or "?"), tostring(w.destWarp or "?")),
        keepOpen = true,
        onSelect = function() openWarpEdit(game, w, idx) end,
      }
    end
    H.pushList(game, rows, { emptyMsg = "NO WARPS." })
  end

  local function openObjects(game)
    local def = currentDef(game)
    local world = H.worldOf(game)
    if not def then
      H.showMsg(game, "NO MAP.")
      return
    end
    local rows = {}
    for i, obj in ipairs(def.objects or {}) do
      local o = obj
      local name = o.name or o.sprite or ("OBJ " .. tostring(i))
      rows[#rows + 1] = {
        label = string.format("%s (%s,%s)", tostring(name), tostring(o.x), tostring(o.y)),
        keepOpen = true,
        onSelect = function()
          H.pushList(game, {
            {
              label = "Move here",
              onSelect = function()
                local p = world and world.player
                if not p then return end
                o.x, o.y = p.cellX, p.cellY
                for _, npc in ipairs((world and world.npcs) or {}) do
                  if npc.def == o or (npc.def and npc.def.index == o.index) then
                    npc.cellX, npc.cellY = p.cellX, p.cellY
                    npc.px = (p.cellX or 0) * 16
                    npc.py = (p.cellY or 0) * 16
                  end
                end
                H.showMsg(game, "MOVED.")
              end,
            },
          })
        end,
      }
    end
    H.pushList(game, rows, { emptyMsg = "NO OBJECTS." })
  end

  local paintMode = false
  local paintWalk = false
  local paintLayer = "block" -- "block" | "coll"
  local brush = 0
  local collType = "walk"
  local lastPaintBx, lastPaintBy
  local lastPaintCx, lastPaintCy
  local lastPaintMap
  local hoverHit
  local mousePaint = false
  local mousePick = false
  local hoverBx, hoverBy
  local hoverCx, hoverCy
  local undoStack = {}
  local stroke = nil
  local UNDO_MAX = 50
  local quadCache = {}

  local COLL_ORDER = { "walk", "blocked", "water", "grass", "ledge", "other" }
  local COLL_BYTE = {
    walk = 0x00, blocked = 0x07, water = 0x29,
    grass = 0x18, ledge = 0xa3, other = 0x23,
  }
  local COLL_LABEL = {
    walk = "WALK", blocked = "BLOCK", water = "WATER",
    grass = "GRASS", ledge = "LEDGE", other = "OTHER",
  }

  local function overworldFree(game)
    local top = game and game.stack and game.stack:top()
    return not (top and not top.isOverworld)
  end

  local function tilesetOf(game, def)
    local world = H.worldOf(game)
    if def and world and world.map and world.map.def == def and world.map.tileset then
      return world.map.tileset
    end
    local data = game and game.data
    local id = def and def.tileset
    if not (data and id) then
      if world and world.map and world.map.tileset then return world.map.tileset end
      return nil
    end
    return (data.gen2Tilesets and data.gen2Tilesets[id])
      or (data.tilesets and data.tilesets[id])
      or (world and world.tilesets and world.tilesets[id])
  end

  local function blockCount(game, def)
    local ts = tilesetOf(game, def)
    local n = ts and ts.blocks and #ts.blocks
    return (n and n > 0) and n or 256
  end

  local function playerBlockXY(game)
    local world = H.worldOf(game)
    local p = world and world.player
    if not p then return nil end
    return math.floor((p.cellX or 0) / 2), math.floor((p.cellY or 0) / 2)
  end

  local function readBlock(def, bx, by)
    if not (def and def.blocks and def.width) then return 0 end
    if bx < 0 or by < 0 or bx >= def.width or by >= (def.height or 0) then
      return def.borderBlock or 0
    end
    return def.blocks[by * def.width + bx + 1] or 0
  end

  local function hitMap(mapId, def, ox, oy, wx, wy)
    if not (mapId and def and def.width and def.height) then return nil end
    local w, h = def.width * 32, def.height * 32
    if wx < ox or wy < oy or wx >= ox + w or wy >= oy + h then return nil end
    local lx, ly = wx - ox, wy - oy
    return {
      mapId = mapId, def = def,
      bx = math.floor(lx / 32), by = math.floor(ly / 32),
      cx = math.floor(lx / 16), cy = math.floor(ly / 16),
    }
  end

  -- World pixel -> current map or a visible connection strip.
  local function resolveAtWorld(game, wx, wy)
    if not (wx and wy) then return nil end
    local maps = mapsOf(game)
    local curId = currentMapId(game)
    local curDef = currentDef(game)
    local hit = hitMap(curId, curDef, 0, 0, wx, wy)
    if hit then return hit end
    local world = H.worldOf(game)
    for _, nb in ipairs((world and world.neighbors) or {}) do
      local nid = nb.id or (nb.map and nb.map.id)
      local ndef = (nb.map and nb.map.def) or (maps and nid and maps[nid])
      hit = hitMap(nid, ndef, nb.ox or 0, nb.oy or 0, wx, wy)
      if hit then return hit end
    end
    if curDef then
      for dir, conn in pairs(curDef.connections or {}) do
        local destId = connDest(conn)
        local destDef = maps and destId and maps[destId]
        if destDef then
          local offset = conn.offset or 0
          local ox, oy
          if dir == "north" then
            ox, oy = offset * 32, -(destDef.height or 0) * 32
          elseif dir == "south" then
            ox, oy = offset * 32, (curDef.height or 0) * 32
          elseif dir == "west" then
            ox, oy = -(destDef.width or 0) * 32, offset * 32
          else
            ox, oy = (curDef.width or 0) * 32, offset * 32
          end
          hit = hitMap(destId, destDef, ox, oy, wx, wy)
          if hit then return hit end
        end
      end
    end
    return nil
  end

  local function finishStroke()
    if stroke and #stroke > 0 then
      undoStack[#undoStack + 1] = stroke
      while #undoStack > UNDO_MAX do
        table.remove(undoStack, 1)
      end
    end
    stroke = nil
  end

  local function startStroke()
    finishStroke()
    stroke = {}
  end

  local function recordPaint(mapId, bx, by, old)
    if not stroke then startStroke() end
    for i = 1, #stroke do
      local e = stroke[i]
      if e.kind == "block" and e.mapId == mapId and e.bx == bx and e.by == by then
        return
      end
    end
    stroke[#stroke + 1] = { kind = "block", mapId = mapId, bx = bx, by = by, old = old }
  end

  local function recordColl(entry)
    if not stroke then startStroke() end
    for i = 1, #stroke do
      local e = stroke[i]
      if e.kind == "coll" and e.tsId == entry.tsId
         and e.blockId == entry.blockId and e.idx == entry.idx
         and e.tile == entry.tile then
        return
      end
    end
    entry.kind = "coll"
    stroke[#stroke + 1] = entry
  end

  local function refreshTiles(game, mapId)
    local world = H.worldOf(game)
    if not world then return end
    if world.blockEdits and mapId and world.blockEdits[mapId] then
      world.blockEdits[mapId] = nil
    end
    local current = currentMapId(game)
    if mapId == current then
      if world.map and world.map.def and world.map.def.blocks then
        world.map.blocks = world.map.def.blocks
      end
      if world.map and world.map.renderer and world.map.renderer.rebuild then
        pcall(function() world.map.renderer:rebuild() end)
      end
      if H.isGen2() then
        if world.dropMapImages and mapId then
          pcall(function() world:dropMapImages(mapId) end)
        end
        if world.refreshMapImages then
          pcall(function() world:refreshMapImages() end)
        end
      end
      return
    end
    for _, nb in ipairs(world.neighbors or {}) do
      local nid = nb.id or (nb.map and nb.map.id)
      if nid == mapId and nb.map then
        if nb.map.def and nb.map.def.blocks then
          nb.map.blocks = nb.map.def.blocks
        end
        if nb.map.renderer and nb.map.renderer.rebuild then
          pcall(function() nb.map.renderer:rebuild() end)
        end
      end
    end
    if H.isGen2() then
      if world.dropMapImages and mapId then
        pcall(function() world:dropMapImages(mapId) end)
      end
      if world.imageFor then
        for _, nb in ipairs(world.neighbors or {}) do
          if nb.id == mapId then
            local ok, img = pcall(function() return world:imageFor(mapId) end)
            if ok then nb.image = img end
          end
        end
      elseif world.rebuildNeighbors then
        pcall(function() world:rebuildNeighbors() end)
      end
    elseif world.rebuildNeighbors then
      pcall(function() world:rebuildNeighbors() end)
    end
  end

  local function writeBlockOn(game, mapId, def, bx, by, block)
    if not (def and def.blocks and def.width and mapId) then
      return false, "NO MAP."
    end
    if bx < 0 or by < 0 or bx >= def.width or by >= (def.height or 0) then
      return false, "OUT OF MAP."
    end
    local n = blockCount(game, def)
    block = math.max(0, math.min(n - 1, math.floor(tonumber(block) or 0)))
    local i = by * def.width + bx + 1
    local old = def.blocks[i]
    if old == block then return true end
    recordPaint(mapId, bx, by, old)
    def.blocks[i] = block
    markDirty(mapId, "blocks")
    refreshTiles(game, mapId)
    return true
  end

  local function writeBlock(game, bx, by, block)
    return writeBlockOn(game, currentMapId(game), currentDef(game), bx, by, block)
  end

  local function playerCellXY(game)
    local world = H.worldOf(game)
    local p = world and world.player
    if not p then return nil end
    return p.cellX, p.cellY
  end

  local function collIndex(cx, cy)
    return (cy % 2) * 2 + (cx % 2) + 1
  end

  local function listHas(list, tile)
    for _, t in ipairs(list or {}) do
      if t == tile then return true end
    end
    return false
  end

  local function listAdd(list, tile)
    list = list or {}
    if listHas(list, tile) then return list end
    list[#list + 1] = tile
    return list
  end

  local function listRemove(list, tile)
    local out = {}
    for _, t in ipairs(list or {}) do
      if t ~= tile then out[#out + 1] = t end
    end
    return out
  end

  local function classifyByte(byte)
    if byte == nil then return "blocked" end
    local ok, P = pcall(require, "src.world.gen2.Permissions")
    if ok and P then
      if P.isLedge and P.isLedge(byte) then return "ledge" end
      if P.isGrass and P.isGrass(byte) then return "grass" end
      if P.isWater and P.isWater(byte) then return "water" end
      if P.isIce and P.isIce(byte) then return "other" end
      if P.isWalkable and P.isWalkable(byte) then return "walk" end
    end
    if byte == 0 then return "walk" end
    return "blocked"
  end

  local function readCollType(game, cx, cy, def)
    def = def or currentDef(game)
    local ts = tilesetOf(game, def)
    if not (def and ts and cx) then return "blocked" end
    if H.isGen2() then
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local id = readBlock(def, bx, by)
      if id == 0 then return "blocked" end
      local quad = ts.collision and ts.collision[id + 1]
      local byte = type(quad) == "table" and quad[collIndex(cx, cy)] or 0xff
      return classifyByte(byte)
    end
    local world = H.worldOf(game)
    local map = world and world.map
    local tile
    if map and map.def == def and map.cellTile then
      tile = map:cellTile(cx, cy)
      if map.isGrassCell and map:isGrassCell(cx, cy) then return "grass" end
      if map.isWaterCell and map:isWaterCell(cx, cy) then return "water" end
      if map.isWalkableCell and map:isWalkableCell(cx, cy) then
        local field = game.data and game.data.field
        if field and field.ledges then
          local tsId = def.tileset
          for _, ledge in ipairs(field.ledges) do
            if (ledge.tileset or "OVERWORLD") == tsId and ledge.ledgeTile == tile then
              return "ledge"
            end
          end
        end
        return "walk"
      end
      return "blocked"
    end
    local okM, MapMod = pcall(require, "src.world.Map")
    if okM and MapMod and MapMod.defCellTile then
      tile = MapMod.defCellTile(def, ts, cx, cy)
    end
    if tile == nil then return "blocked" end
    if ts.grassTile ~= nil and tile == ts.grassTile then return "grass" end
    if listHas(ts.waterTiles, tile) or listHas(ts.shoreTiles, tile) then return "water" end
    if listHas(ts.walkable, tile) then return "walk" end
    return "blocked"
  end

  local function syncLiveCollision(game, ts)
    local world = H.worldOf(game)
    local map = world and world.map
    if not (map and ts) then return end
    if map.tileset and map.tileset ~= ts then return end
    if H.isGen2() then
      if ts.collision then map.collision = ts.collision end
      return
    end
    map.walkable = {}
    for _, t in ipairs(ts.walkable or {}) do map.walkable[t] = true end
    map.waterTiles = {}
    for _, t in ipairs(ts.waterTiles or {}) do map.waterTiles[t] = true end
    for _, t in ipairs(ts.shoreTiles or {}) do map.waterTiles[t] = true end
  end

  local function writeColl(game, cx, cy, kind, def, mapId)
    def = def or currentDef(game)
    mapId = mapId or currentMapId(game)
    local ts = tilesetOf(game, def)
    local tsId = def and def.tileset
    if not (def and ts and tsId and mapId and cx) then
      return false, "NO MAP."
    end
    if cx < 0 or cy < 0
       or cx >= (def.width or 0) * 2 or cy >= (def.height or 0) * 2 then
      return false, "OUT OF MAP."
    end
    kind = kind or collType
    if H.isGen2() then
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local id = readBlock(def, bx, by)
      if id == 0 then return false, "BLOCK 0." end
      ts.collision = ts.collision or {}
      local quad = ts.collision[id + 1]
      if type(quad) ~= "table" then
        quad = { 0x07, 0x07, 0x07, 0x07 }
        ts.collision[id + 1] = quad
      end
      local idx = collIndex(cx, cy)
      local old = quad[idx]
      local byte = COLL_BYTE[kind] or 0x07
      if old == byte then return true end
      recordColl({ tsId = tsId, blockId = id, idx = idx, old = old })
      quad[idx] = byte
      dirtyTilesets[tsId] = true
      syncLiveCollision(game, ts)
      return true
    end
    local world = H.worldOf(game)
    local map = world and world.map
    local tile
    if map and map.def == def and map.cellTile then
      tile = map:cellTile(cx, cy)
    else
      local okM, MapMod = pcall(require, "src.world.Map")
      if okM and MapMod and MapMod.defCellTile then
        tile = MapMod.defCellTile(def, ts, cx, cy)
      end
    end
    if tile == nil then return false, "NO TILE." end
    if readCollType(game, cx, cy, def) == kind then return true end
    local wasWalk = listHas(ts.walkable, tile)
    local wasWater = listHas(ts.waterTiles, tile) or listHas(ts.shoreTiles, tile)
    recordColl({
      tsId = tsId, tile = tile,
      wasWalk = wasWalk, wasWater = wasWater,
      grassTile = ts.grassTile,
    })
    if kind == "walk" then
      ts.walkable = listAdd(ts.walkable, tile)
      ts.waterTiles = listRemove(ts.waterTiles, tile)
      ts.shoreTiles = listRemove(ts.shoreTiles, tile)
      if ts.grassTile == tile then ts.grassTile = nil end
    elseif kind == "blocked" then
      ts.walkable = listRemove(ts.walkable, tile)
      ts.waterTiles = listRemove(ts.waterTiles, tile)
      ts.shoreTiles = listRemove(ts.shoreTiles, tile)
      if ts.grassTile == tile then ts.grassTile = nil end
    elseif kind == "water" then
      ts.walkable = listRemove(ts.walkable, tile)
      ts.waterTiles = listAdd(ts.waterTiles, tile)
      ts.shoreTiles = listRemove(ts.shoreTiles, tile)
      if ts.grassTile == tile then ts.grassTile = nil end
    elseif kind == "grass" then
      ts.walkable = listAdd(ts.walkable, tile)
      ts.waterTiles = listRemove(ts.waterTiles, tile)
      ts.grassTile = tile
    elseif kind == "ledge" then
      ts.walkable = listAdd(ts.walkable, tile)
      local field = game.data and game.data.field
      if field then
        field.ledges = field.ledges or {}
        local standing
        if map and map.def == def and map.cellTile then
          standing = map:cellTile(cx, cy - 1)
        else
          local okM, MapMod = pcall(require, "src.world.Map")
          if okM and MapMod and MapMod.defCellTile then
            standing = MapMod.defCellTile(def, ts, cx, cy - 1)
          end
        end
        local already
        for _, ledge in ipairs(field.ledges) do
          if ledge._debug and ledge.ledgeTile == tile
             and ledge.standingTile == standing then
            already = true
            break
          end
        end
        if not already then
          field.ledges[#field.ledges + 1] = {
            tileset = tsId, facing = "down", input = "down",
            standingTile = standing, ledgeTile = tile, _debug = true,
          }
        end
      end
    else
      ts.walkable = listRemove(ts.walkable, tile)
      ts.shoreTiles = listAdd(ts.shoreTiles, tile)
      ts.waterTiles = listAdd(ts.waterTiles, tile)
    end
    dirtyTilesets[tsId] = true
    syncLiveCollision(game, ts)
    return true
  end

  local function restoreColl(game, e)
    local ts = tilesetById(game, e.tsId)
    if not ts then return end
    if e.blockId then
      ts.collision = ts.collision or {}
      local quad = ts.collision[e.blockId + 1]
      if type(quad) == "table" and e.idx then
        quad[e.idx] = e.old
      end
    elseif e.tile ~= nil then
      if e.wasWalk then ts.walkable = listAdd(ts.walkable, e.tile)
      else ts.walkable = listRemove(ts.walkable, e.tile) end
      if e.wasWater then ts.waterTiles = listAdd(ts.waterTiles, e.tile)
      else ts.waterTiles = listRemove(ts.waterTiles, e.tile) end
      if e.grassTile ~= nil then ts.grassTile = e.grassTile end
    end
    dirtyTilesets[e.tsId] = true
    syncLiveCollision(game, ts)
  end

  local function paintHere(game)
    if paintLayer == "coll" then
      local cx, cy = playerCellXY(game)
      if not cx then return false, "NO MAP." end
      startStroke()
      local ok, err = writeColl(game, cx, cy, collType)
      finishStroke()
      return ok, err
    end
    local bx, by = playerBlockXY(game)
    if not bx then return false, "NO MAP." end
    startStroke()
    local ok, err = writeBlock(game, bx, by, brush)
    finishStroke()
    return ok, err
  end

  local function undoPaint(game)
    local group = nil
    if stroke and #stroke > 0 then
      group = stroke
      stroke = nil
    elseif #undoStack > 0 then
      group = undoStack[#undoStack]
      undoStack[#undoStack] = nil
    else
      return false, "NOTHING TO UNDO."
    end
    mousePaint = false
    local seen = {}
    for i = #group, 1, -1 do
      local e = group[i]
      if e.kind == "coll" then
        restoreColl(game, e)
      else
        local maps = mapsOf(game)
        local def = maps and maps[e.mapId]
        if not def and currentMapId(game) == e.mapId then def = currentDef(game) end
        if def and def.blocks and def.width then
          if e.bx >= 0 and e.by >= 0 and e.bx < def.width and e.by < (def.height or 0) then
            def.blocks[e.by * def.width + e.bx + 1] = e.old
            markDirty(e.mapId, "blocks")
            seen[e.mapId] = true
          end
        end
      end
    end
    for mapId in pairs(seen) do
      refreshTiles(game, mapId)
    end
    lastPaintBx, lastPaintBy = playerBlockXY(game)
    lastPaintCx, lastPaintCy = playerCellXY(game)
    return true
  end

  local function pickBlockAt(game, bx, by, def)
    def = def or currentDef(game)
    if not (def and bx) then return false, "NO MAP." end
    brush = readBlock(def, bx, by)
    return true
  end

  local function pickCollAt(game, cx, cy, def)
    if not cx then return false, "NO MAP." end
    collType = readCollType(game, cx, cy, def)
    return true
  end

  local function pickHere(game)
    if paintLayer == "coll" then
      local cx, cy = playerCellXY(game)
      return pickCollAt(game, cx, cy)
    end
    local bx, by = playerBlockXY(game)
    return pickBlockAt(game, bx, by)
  end

  local function cycleColl(delta)
    local idx = 1
    for i, id in ipairs(COLL_ORDER) do
      if id == collType then idx = i; break end
    end
    idx = ((idx - 1 + delta) % #COLL_ORDER) + 1
    collType = COLL_ORDER[idx]
    return true
  end

  -- Window pointer (LOVE units, same as input.pointer) to world pixels.
  -- Gold draws the overworld at (0,0) with world:zoomScale(). Gen 1 blits the
  -- world canvas with Zoom.scale(fitScale) and a letterbox origin.
  local function pointerToWorld(game, x, y)
    local world = H.worldOf(game)
    local cam = world and world.camera
    if not (cam and x and y) then return nil end
    local s, ox, oy = 1, 0, 0
    if H.isGen2() then
      s = (world.zoomScale and world:zoomScale()) or 1
    else
      local R = game.renderer
      local Sp = 1
      if R and R.fitScale then
        local ok, v = pcall(function() return R:fitScale() end)
        if ok and v then Sp = v end
      end
      local okZ, Zoom = pcall(require, "src.render.Zoom")
      s = (okZ and Zoom.scale and Zoom.scale(Sp)) or Sp
      local vw, vh
      local canvas = R and R.worldCanvas
      if canvas and canvas.getDimensions then
        vw, vh = canvas:getDimensions()
      elseif R and R.worldViewSize then
        local ok, a, b = pcall(function() return R:worldViewSize() end)
        if ok then vw, vh = a, b end
      end
      if vw and vh then
        local ww, wh = love.graphics.getDimensions()
        ox = math.floor((ww - vw * s) / 2)
        oy = math.floor((wh - vh * s) / 2)
      end
    end
    if not s or s <= 0 then return nil end
    local wx = cam.x + (x - ox) / s
    local wy = cam.y + (y - oy) / s
    return wx, wy
  end

  local function pointerToBlock(game, x, y)
    local wx, wy = pointerToWorld(game, x, y)
    if not wx then return nil end
    return math.floor(wx / 32), math.floor(wy / 32)
  end

  local function pointerToCell(game, x, y)
    local wx, wy = pointerToWorld(game, x, y)
    if not wx then return nil end
    return math.floor(wx / 16), math.floor(wy / 16)
  end

  local function cycleBrush(game, delta)
    local n = blockCount(game, currentDef(game))
    brush = (brush + delta) % n
    if brush < 0 then brush = brush + n end
    return true
  end

  local function openPaint(game)
    local def = currentDef(game)
    if not def then
      H.showMsg(game, "NO MAP.")
      return
    end
    local n = blockCount(game, def)
    local rows = {
      H.toggleRow(function()
        return paintMode and "Paint mode: ON (click/drag)" or "Paint mode: OFF"
      end, function()
        paintMode = not paintMode
        lastPaintBx, lastPaintBy = nil, nil
        lastPaintCx, lastPaintCy = nil, nil
        lastPaintMap = nil
        finishStroke()
      end),
      H.toggleRow(function()
        return paintWalk and "Paint walk: ON" or "Paint walk: OFF"
      end, function()
        paintWalk = not paintWalk
        if paintWalk then paintMode = true else finishStroke() end
        lastPaintBx, lastPaintBy = nil, nil
        lastPaintCx, lastPaintCy = nil, nil
        lastPaintMap = nil
      end),
      H.toggleRow(function()
        return paintLayer == "coll" and "Paint: COLLISION" or "Paint: BLOCKS"
      end, function()
        paintLayer = paintLayer == "coll" and "block" or "coll"
      end),
      H.toggleRow(function()
        return "Type: " .. (COLL_LABEL[collType] or collType:upper())
      end, function()
        cycleColl(1)
      end),
      {
        label = "Undo (Ctrl+Z)",
        keepOpen = true,
        onSelect = function()
          local ok, err = undoPaint(game)
          H.showMsg(game, ok and "UNDONE." or (err or "FAIL."))
        end,
      },
      {
        label = "Paint here",
        keepOpen = true,
        onSelect = function()
          local ok, err = paintHere(game)
          H.showMsg(game, ok and ("PAINTED " .. brush) or (err or "FAIL."))
        end,
      },
      {
        label = "Pick here",
        keepOpen = true,
        onSelect = function()
          pickHere(game)
          H.showMsg(game, "BRUSH " .. brush)
        end,
      },
      {
        label = "Choose block...",
        keepOpen = true,
        onSelect = function()
          H.pushNumberPicker(game, {
            title = "BLOCK",
            min = 0, max = n - 1, value = brush,
            onConfirm = function(v)
              brush = v
              H.showMsg(game, "BRUSH " .. brush)
            end,
          })
        end,
      },
    }
    H.pushList(game, rows)
  end

  local function drawBlockPreview(game, x, y)
    local def = currentDef(game)
    local ts = tilesetOf(game, def)
    local block = ts and ts.blocks and ts.blocks[brush + 1]
    if not block then return end
    local okA, Assets = pcall(require, "src.render.Assets")
    local img = okA and ts.image and Assets.image(ts.image)
    if not img then return end
    local perRow = ts.tilesPerRow or 16
    local iw, ih = img:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    for i = 0, 15 do
      local tile = block[i + 1] or 0
      local sx = (tile % perRow) * 8
      local sy = math.floor(tile / perRow) * 8
      local key = ts.image .. ":" .. tile
      local q = quadCache[key]
      if not q then
        q = love.graphics.newQuad(sx, sy, 8, 8, iw, ih)
        quadCache[key] = q
      end
      love.graphics.draw(img, q, x + (i % 4) * 8, y + math.floor(i / 4) * 8)
    end
  end

  local function openMenu(game)
    local mapId = currentMapId(game) or "?"
    local rows = {
      H.toggleRow(function()
        return H.hudOn() and "HUD: ON" or "HUD: OFF"
      end, function()
        H.setHudOn(not H.hudOn())
      end),
      H.toggleRow(function()
        return liveEdit and "Live edit: ON" or "Live edit: OFF"
      end, function()
        liveEdit = not liveEdit
      end),
      {
        label = "Connections...",
        keepOpen = true,
        onSelect = function() openConnections(game) end,
      },
      {
        label = "Warps...",
        keepOpen = true,
        onSelect = function() openWarps(game) end,
      },
      {
        label = "Objects...",
        keepOpen = true,
        onSelect = function() openObjects(game) end,
      },
      {
        label = "Paint tiles...",
        keepOpen = true,
        onSelect = function() openPaint(game) end,
      },
      {
        label = "Rebuild neighbors",
        onSelect = function()
          refreshLive(game, mapId)
          H.showMsg(game, "NEIGHBORS REBUILT.")
        end,
      },
      {
        label = "Dump Lua",
        onSelect = function()
          local ok = writeSaved(game)
          H.showMsg(game, ok and "DUMPED EDITS." or "DUMP FAILED.")
        end,
      },
    }
    H.pushList(game, rows)
  end

  local function hudExtra(game)
    local def = currentDef(game)
    if not def then return nil end
    local function part(dir)
      local conn = def.connections and def.connections[dir]
      local dest = connDest(conn)
      if not dest then return dir:sub(1, 1):upper() .. ":--" end
      return string.format("%s:%s@%d", dir:sub(1, 1):upper(), dest, conn.offset or 0)
    end
    local lines = {
      part("north") .. "  " .. part("south"),
      part("east") .. "  " .. part("west"),
    }
    if liveEdit then
      lines[#lines + 1] = "MAPEDIT " .. facingDir(game):upper() .. " ,/. offset"
    end
    if paintMode then
      if paintLayer == "coll" then
        local cx, cy = playerCellXY(game)
        local here = (cx and readCollType(game, cx, cy)) or "blocked"
        lines[#lines + 1] = string.format("COLL %s  HERE %s  Q/E",
          COLL_LABEL[collType] or "?", COLL_LABEL[here] or here:upper())
        if hoverHit then
          local under = readCollType(game, hoverHit.cx, hoverHit.cy, hoverHit.def)
          if hoverHit.mapId == currentMapId(game) then
            lines[#lines + 1] = string.format("MOUSE %d,%d  %s",
              hoverHit.cx, hoverHit.cy, COLL_LABEL[under] or under:upper())
          else
            lines[#lines + 1] = string.format("%s %d,%d %s",
              hoverHit.mapId, hoverHit.cx, hoverHit.cy,
              COLL_LABEL[under] or under:upper())
          end
        end
      else
        local bx, by = playerBlockXY(game)
        local here = (bx and def) and readBlock(def, bx, by) or 0
        lines[#lines + 1] = string.format("PAINT %d  HERE %d  CLICK/RMB Q/E", brush, here)
        if hoverHit then
          local under = readBlock(hoverHit.def, hoverHit.bx, hoverHit.by)
          if hoverHit.mapId == currentMapId(game) then
            lines[#lines + 1] = string.format("MOUSE %d,%d  %d",
              hoverHit.bx, hoverHit.by, under)
          else
            lines[#lines + 1] = string.format("%s %d,%d %d",
              hoverHit.mapId, hoverHit.bx, hoverHit.by, under)
          end
        end
      end
      if paintWalk then lines[#lines + 1] = "PAINT WALK" end
      lines[#lines + 1] = "CTRL+Z UNDO"
    end
    return lines
  end

  local function drawHud(game)
    if not paintMode or paintLayer == "coll" or not H.hudOn or not H.hudOn() then
      return
    end
    pcall(drawBlockPreview, game, 128, 104)
  end

  local function tick(game)
    if not (paintMode and paintWalk and game and overworldFree(game)) then
      return
    end
    if paintLayer == "coll" then
      local cx, cy = playerCellXY(game)
      if not cx then return end
      if lastPaintCx == cx and lastPaintCy == cy then return end
      lastPaintCx, lastPaintCy = cx, cy
      writeColl(game, cx, cy, collType)
      return
    end
    local bx, by = playerBlockXY(game)
    if not bx then return end
    if lastPaintBx == bx and lastPaintBy == by then return end
    lastPaintBx, lastPaintBy = bx, by
    writeBlock(game, bx, by, brush)
  end

  -- input.pointer: left click/drag paints, right click/drag picks.
  -- Return true to consume so the click does not fall through.
  local function onPointer(game, ev)
    if not paintMode or not game or not ev then return false end
    if ev.phase == "cancelled" then
      if mousePaint then finishStroke() end
      mousePaint, mousePick = false
      return false
    end
    if not overworldFree(game) then
      if mousePaint then finishStroke() end
      mousePaint, mousePick = false
      return false
    end
    local wx, wy = pointerToWorld(game, ev.x, ev.y)
    local hit = resolveAtWorld(game, wx, wy)
    hoverHit = hit
    if hit then
      hoverBx, hoverBy = hit.bx, hit.by
      hoverCx, hoverCy = hit.cx, hit.cy
    else
      hoverBx, hoverBy, hoverCx, hoverCy = nil, nil, nil, nil
    end
    local function stamp()
      if not hit then return end
      if paintLayer == "coll" then
        writeColl(game, hit.cx, hit.cy, collType, hit.def, hit.mapId)
        lastPaintCx, lastPaintCy = hit.cx, hit.cy
      else
        writeBlockOn(game, hit.mapId, hit.def, hit.bx, hit.by, brush)
        lastPaintBx, lastPaintBy = hit.bx, hit.by
      end
      lastPaintMap = hit.mapId
    end
    local function pick()
      if not hit then return end
      if paintLayer == "coll" then
        pickCollAt(game, hit.cx, hit.cy, hit.def)
      else
        pickBlockAt(game, hit.bx, hit.by, hit.def)
      end
    end
    local function sameCell()
      if not hit then return true end
      if lastPaintMap ~= hit.mapId then return false end
      if paintLayer == "coll" then
        return lastPaintCx == hit.cx and lastPaintCy == hit.cy
      end
      return lastPaintBx == hit.bx and lastPaintBy == hit.by
    end
    if ev.phase == "pressed" then
      if ev.button == 2 then
        mousePick = true
        pick()
        return true
      end
      if ev.button == nil or ev.button == 1 then
        mousePaint = true
        startStroke()
        stamp()
        return true
      end
      return false
    elseif ev.phase == "moved" then
      if mousePaint and hit then
        if not sameCell() then stamp() end
        return true
      end
      if mousePick then
        pick()
        return true
      end
      return false
    elseif ev.phase == "released" then
      local was = mousePaint or mousePick
      if mousePaint then finishStroke() end
      mousePaint, mousePick = false
      return was
    end
    return false
  end

  -- Called from input.step on a key edge. Engine F-keys are not used.
  local function onKey(key)
    local game = H.liveGame()
    if not game or not overworldFree(game) then return false end
    if paintMode then
      if key == "undo" then
        local ok, err = undoPaint(game)
        if not ok and err then H.showMsg(game, err) end
        return true
      elseif key == "p" then
        local ok, err = paintHere(game)
        if not ok and err then H.showMsg(game, err) end
        return true
      elseif key == "o" then
        pickHere(game)
        return true
      elseif key == "q" then
        if paintLayer == "coll" then cycleColl(-1) else cycleBrush(game, -1) end
        return true
      elseif key == "e" then
        if paintLayer == "coll" then cycleColl(1) else cycleBrush(game, 1) end
        return true
      end
    end
    if not liveEdit then return false end
    local left = key == "[" or key == ","
    local right = key == "]" or key == "."
    if not (left or right) then return false end
    local ok, err = nudgeFacingOffset(game, right and 1 or -1)
    if not ok and err then H.showMsg(game, err) end
    return true
  end

  return {
    openMenu = openMenu,
    hudExtra = hudExtra,
    drawHud = drawHud,
    tick = tick,
    onKey = onKey,
    onPointer = onPointer,
    applySaved = applySaved,
    liveEdit = function() return liveEdit end,
  }
end
