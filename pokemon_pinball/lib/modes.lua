-- Catch 'Em / Evolution / Map Move state machines (lite).
local V = ...
local Species = V.require("data.species")
local Maps = V.require("data.maps")

local Modes = {}

local function rng(a, b)
  if love and love.math and love.math.random then
    return love.math.random(a, b)
  end
  return math.random(a, b)
end

function Modes.pickWild(catalog, field, mapKey, rare)
  local wild = catalog and catalog.wild and catalog.wild[field]
  if not wild then return 25 end -- Pikachu fallback
  local loc = wild[mapKey]
  if not loc then
    -- first available
    for _, v in pairs(wild) do loc = v; break end
  end
  if not loc then return 25 end
  local pool = rare and loc.rare or loc.common
  if not pool or #pool == 0 then return 25 end
  return pool[rng(1, #pool)]
end

function Modes.newSession(field, mapList, mapIndex)
  return {
    field = field,
    mapList = mapList,
    mapIndex = mapIndex or 1,
    mode = "idle", -- idle | catch | evo | mapmove
    timer = 0,
    targetId = nil,
    hits = 0,
    needHits = 3,
    evoProgress = 0,
    evoNeed = 4,
    evoFrom = nil,
    evoTo = nil,
    catchReady = 0, -- bumper hits toward catch mode
    mapReady = 0,
    evoReady = 0,
  }
end

function Modes.mapLabel(session)
  local m = session.mapList[session.mapIndex]
  return m and m.label or "?"
end

function Modes.mapKey(session)
  local m = session.mapList[session.mapIndex]
  return m and m.key or "PALLET_TOWN"
end

function Modes.bumpCatchMeter(session, n)
  if session.mode ~= "idle" then return end
  session.catchReady = session.catchReady + (n or 1)
  if session.catchReady >= 8 then
    session.catchReady = 0
    return "start_catch"
  end
end

function Modes.bumpMapMeter(session, n)
  if session.mode ~= "idle" then return end
  session.mapReady = session.mapReady + (n or 1)
  if session.mapReady >= 6 then
    session.mapReady = 0
    return "start_map"
  end
end

function Modes.bumpEvoMeter(session, n)
  if session.mode ~= "idle" then return end
  session.evoReady = session.evoReady + (n or 1)
  if session.evoReady >= 10 then
    session.evoReady = 0
    return "start_evo"
  end
end

function Modes.startCatch(session, catalog)
  session.mode = "catch"
  session.timer = 60 * 12 -- ~12s at 60fps
  session.hits = 0
  session.needHits = 3
  local rare = rng(1, 100) <= 20
  session.targetId = Modes.pickWild(catalog, session.field, Modes.mapKey(session), rare)
  return session.targetId
end

function Modes.startMapMove(session)
  session.mode = "mapmove"
  session.timer = 60 * 8
  session.hits = 0
  session.needHits = 2
end

function Modes.startEvo(session, caughtTable)
  -- Pick a caught species that can evolve.
  local candidates = {}
  for key, count in pairs(caughtTable or {}) do
    if (count or 0) > 0 then
      local id = tonumber(key)
      if id then
        local to = Species.evolve(id)
        if to then candidates[#candidates + 1] = { from = id, to = to } end
        if id == 133 then
          for _, e in ipairs(Species.eeveeBranches) do
            candidates[#candidates + 1] = { from = 133, to = e }
          end
        end
      end
    end
  end
  if #candidates == 0 then
    -- fallback: Charmander line starter
    session.evoFrom, session.evoTo = 4, 5
  else
    local c = candidates[rng(1, #candidates)]
    session.evoFrom, session.evoTo = c.from, c.to
  end
  session.mode = "evo"
  session.timer = 60 * 14
  session.evoProgress = 0
  session.evoNeed = 4
  session.targetId = session.evoFrom
end

function Modes.hitTarget(session)
  if session.mode == "catch" or session.mode == "mapmove" then
    session.hits = session.hits + 1
    if session.hits >= session.needHits then
      return "complete"
    end
  elseif session.mode == "evo" then
    session.evoProgress = session.evoProgress + 1
    if session.evoProgress >= session.evoNeed then
      return "complete"
    end
  end
  return nil
end

function Modes.tick(session)
  if session.mode == "idle" then return nil end
  session.timer = session.timer - 1
  if session.timer <= 0 then
    local was = session.mode
    session.mode = "idle"
    return "timeout", was
  end
  return nil
end

function Modes.complete(session)
  local mode = session.mode
  local payload = {
    mode = mode,
    targetId = session.targetId,
    evoFrom = session.evoFrom,
    evoTo = session.evoTo,
  }
  if mode == "mapmove" then
    session.mapIndex = session.mapIndex + 1
    if session.mapIndex > #session.mapList then
      session.mapIndex = 1
    end
    payload.mapIndex = session.mapIndex
    payload.mapKey = Modes.mapKey(session)
  end
  session.mode = "idle"
  session.hits = 0
  session.evoProgress = 0
  return payload
end

function Modes.cancel(session)
  session.mode = "idle"
  session.hits = 0
  session.evoProgress = 0
end

return Modes
