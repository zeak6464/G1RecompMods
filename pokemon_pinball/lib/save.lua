local Save = {}

local function ensure(mod)
  if mod.save:get("initialized") then return end
  mod.save:set("high_scores", {})
  mod.save:set("caught", {})
  mod.save:set("last_field", "RED")
  mod.save:set("map_index", 1)
  mod.save:set("initialized", true)
end

function Save.init(mod)
  ensure(mod)
end

function Save.lastField(mod)
  ensure(mod)
  return mod.save:get("last_field", "RED")
end

function Save.setField(mod, field)
  ensure(mod)
  mod.save:set("last_field", field)
end

function Save.caught(mod)
  ensure(mod)
  local c = mod.save:get("caught", {})
  if type(c) ~= "table" then c = {}; mod.save:set("caught", c) end
  return c
end

function Save.catch(mod, speciesId)
  local c = Save.caught(mod)
  local key = tostring(tonumber(speciesId) or speciesId)
  c[key] = (c[key] or 0) + 1
  mod.save:set("caught", c)
end

function Save.isCaught(mod, speciesId)
  local c = Save.caught(mod)
  local key = tostring(tonumber(speciesId) or speciesId)
  return (c[key] or 0) > 0
end

function Save.caughtCount(mod)
  local n = 0
  for _, v in pairs(Save.caught(mod)) do
    if (v or 0) > 0 then n = n + 1 end
  end
  return n
end

function Save.highScores(mod)
  ensure(mod)
  local hs = mod.save:get("high_scores", {})
  if type(hs) ~= "table" then hs = {}; mod.save:set("high_scores", hs) end
  return hs
end

function Save.submitScore(mod, field, score)
  local hs = Save.highScores(mod)
  local key = field or "RED"
  local list = hs[key]
  if type(list) ~= "table" then list = {} end
  list[#list + 1] = score
  table.sort(list, function(a, b) return a > b end)
  while #list > 5 do list[#list] = nil end
  hs[key] = list
  mod.save:set("high_scores", hs)
  return list[1] == score
end

function Save.mapIndex(mod)
  ensure(mod)
  return mod.save:get("map_index", 1) or 1
end

function Save.setMapIndex(mod, i)
  ensure(mod)
  mod.save:set("map_index", i)
end

return Save
