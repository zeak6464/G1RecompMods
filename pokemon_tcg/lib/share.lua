-- Share folder for custom card/pack files and pictures.
-- Files live in pokemon_tcg_share/ next to the game save.
local V = ...
local Custom = V.require("custom")
local Cache = V.require("cache")
local Save = V.require("save")

local Share = {}

Share.DIR = "pokemon_tcg_share"
Share.ART = "pokemon_tcg_share/art"

local function persistFs()
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok and SaveData and SaveData.persistenceFs then
    local fs = SaveData.persistenceFs()
    if fs and fs.write then return fs end
  end
  return love and love.filesystem
end

local function b64enc(data)
  if love and love.data and love.data.encode then
    return love.data.encode("string", "base64", data)
  end
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local pad = (not b and 2) or (not c and 1) or 0
    for s = 18, 0, -6 do
      out[#out + 1] = alphabet:sub(math.floor(n / (2 ^ s)) % 64 + 1,
        math.floor(n / (2 ^ s)) % 64 + 1)
    end
    if pad > 0 then
      for p = 0, pad - 1 do out[#out - p] = "=" end
    end
  end
  return table.concat(out)
end

local function b64dec(text)
  if type(text) ~= "string" or text == "" then return nil end
  text = text:gsub("%s+", "")
  if love and love.data and love.data.decode then
    local ok, data = pcall(love.data.decode, "string", "base64", text)
    if ok and type(data) == "string" then return data end
  end
  return nil
end

function Share.ensureDirs()
  local fs = persistFs()
  if not fs then return false end
  if fs.createDirectory then
    fs.createDirectory(Share.DIR)
    fs.createDirectory(Share.ART)
  end
  return true
end

function Share.folderPath()
  Share.ensureDirs()
  local fs = persistFs()
  if fs and fs.getSaveDirectory then
    local base = fs.getSaveDirectory()
    if type(base) == "string" and base ~= "" then
      return (base .. "/" .. Share.DIR):gsub("\\", "/")
    end
  end
  return Share.DIR
end

local function addUnique(list, seen, name)
  if type(name) ~= "string" or name == "" or seen[name] then return end
  seen[name] = true
  list[#list + 1] = name
end

local function listDir(rel)
  local fs = persistFs()
  if not (fs and fs.getDirectoryItems) then return {} end
  Share.ensureDirs()
  return fs.getDirectoryItems(rel) or {}
end

function Share.listExports(mod)
  local out, seen = {}, {}
  for _, name in ipairs(listDir(Share.DIR)) do
    if name:lower():match("%.tcg$") then addUnique(out, seen, name) end
  end
  if mod and mod.list then
    for _, name in ipairs(mod.list(mod, "share") or {}) do
      if name:lower():match("%.tcg$") then addUnique(out, seen, name) end
    end
  end
  table.sort(out)
  return out
end

function Share.listArt(mod)
  local out, seen = {}, {}
  for _, name in ipairs(listDir(Share.ART)) do
    local low = name:lower()
    if low:match("%.png$") or low:match("%.jpg$") or low:match("%.jpeg$")
        or low:match("%.bmp$") then
      addUnique(out, seen, name)
    end
  end
  if mod and mod.list then
    for _, name in ipairs(mod.list(mod, "share/art") or {}) do
      local low = name:lower()
      if low:match("%.png$") or low:match("%.jpg$") or low:match("%.jpeg$")
          or low:match("%.bmp$") then
        addUnique(out, seen, name)
      end
    end
  end
  table.sort(out)
  return out
end

function Share.readExport(mod, name)
  local fs = persistFs()
  if fs and fs.read then
    local data = fs.read(Share.DIR .. "/" .. name)
    if type(data) == "string" and #data > 0 then return data end
  end
  if mod and mod.read then
    local data = mod:read("share/" .. name)
    if type(data) == "string" and #data > 0 then return data end
  end
  return nil
end

function Share.readArt(mod, name)
  local fs = persistFs()
  if fs and fs.read then
    local data = fs.read(Share.ART .. "/" .. name)
    if type(data) == "string" and #data > 0 then return data end
  end
  if mod and mod.read then
    local data = mod:read("share/art/" .. name)
    if type(data) == "string" and #data > 0 then return data end
  end
  return nil
end

local function safeFile(name)
  local s = tostring(name or "CUSTOM"):upper():gsub("[^A-Z0-9]", "")
  if s == "" then s = "CUSTOM" end
  return s:sub(1, 12)
end

function Share.writeExport(name, text)
  Share.ensureDirs()
  local fs = persistFs()
  if not (fs and fs.write) then return nil, "Cannot write share folder" end
  local base = safeFile(name)
  local file = base .. ".tcg"
  local n = 2
  while fs.getInfo and fs.getInfo(Share.DIR .. "/" .. file) do
    file = base .. tostring(n) .. ".tcg"
    n = n + 1
    if n > 99 then break end
  end
  local ok, err = fs.write(Share.DIR .. "/" .. file, text)
  if not ok then return nil, err or "Write failed" end
  return file
end

local function newFileData(bytes, filename)
  local fs = persistFs()
  if fs and fs.newFileData then
    local ok, fd = pcall(fs.newFileData, bytes, filename or "pic.png")
    if ok then return fd end
  end
  if love and love.filesystem and love.filesystem.newFileData then
    local ok, fd = pcall(love.filesystem.newFileData, bytes, filename or "pic.png")
    if ok then return fd end
  end
  return nil
end

function Share.encodePicture(bytes, filename, w, h)
  if type(bytes) ~= "string" or bytes == "" then return nil, "Empty image" end
  if not (love and love.image and love.image.newImageData) then
    return nil, "No image loader"
  end
  local fd = newFileData(bytes, filename)
  if not fd then return nil, "Bad image data" end
  local ok, src = pcall(love.image.newImageData, fd)
  if not ok or not src then return nil, "Could not read image" end
  if not w or not h then
    local CardGfx = V.require("card_gfx")
    w, h = CardGfx.WIDTH, CardGfx.HEIGHT
  end
  local dst = love.image.newImageData(w, h)
  local sw, sh = src:getWidth(), src:getHeight()
  if sw < 1 or sh < 1 then return nil, "Image too small" end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local sx = math.min(sw - 1, math.floor(x * sw / w))
      local sy = math.min(sh - 1, math.floor(y * sh / h))
      dst:setPixel(x, y, src:getPixel(sx, sy))
    end
  end
  local encoded = dst:encode("png")
  if not encoded then return nil, "Encode failed" end
  local png = encoded.getString and encoded:getString() or tostring(encoded)
  return b64enc(png)
end

local function field(card, key, value)
  if value == nil or value == "" then return end
  card[#card + 1] = key .. "=" .. tostring(value)
end

local function costLine(cost)
  local parts = {}
  for _, typ in ipairs(Custom.types()) do
    local n = cost and cost[typ]
    if n and n > 0 then parts[#parts + 1] = typ .. ":" .. tostring(n) end
  end
  return table.concat(parts, ",")
end

local function cardLines(card, picB64)
  local lines = {
    "kind=card",
    "name=" .. (card.name or "CARD"),
    "ckind=" .. (card.kind or "pokemon"),
  }
  field(lines, "type", card.type)
  field(lines, "energy", card.energyType)
  field(lines, "hp", card.hp)
  field(lines, "level", card.level)
  field(lines, "stage", card.stage)
  field(lines, "retreat", card.retreat)
  field(lines, "weakness", card.weakness)
  field(lines, "resistance", card.resistance)
  field(lines, "rarity", card.rarity)
  for _, atk in ipairs(card.attacks or {}) do
    lines[#lines + 1] = ("atk=%s|%s|%s"):format(
      atk.name or "ATK", tostring(atk.damage or 0), costLine(atk.cost))
  end
  if picB64 and picB64 ~= "" then
    lines[#lines + 1] = "pic=" .. picB64
  end
  lines[#lines + 1] = "endcard"
  return lines
end

local function parseCost(text)
  local cost = {}
  if type(text) ~= "string" or text == "" then return cost end
  for part in text:gmatch("[^,]+") do
    local typ, n = part:match("^([A-Z]+):(%d+)$")
    if typ then cost[typ] = tonumber(n) end
  end
  return cost
end

local function parseCardLines(lines, from, last)
  local raw = { attacks = {} }
  for i = from, last do
    local line = lines[i]
    local key, val = line:match("^([%w]+)=(.*)$")
    if key == "name" then raw.name = val
    elseif key == "ckind" then raw.kind = val
    elseif key == "type" then raw.type = val
    elseif key == "energy" then raw.energyType = val
    elseif key == "hp" then raw.hp = tonumber(val)
    elseif key == "level" then raw.level = tonumber(val)
    elseif key == "stage" then raw.stage = val
    elseif key == "retreat" then raw.retreat = tonumber(val)
    elseif key == "weakness" then raw.weakness = val
    elseif key == "resistance" then raw.resistance = val
    elseif key == "rarity" then raw.rarity = val
    elseif key == "pic" then raw.picB64 = val
    elseif key == "atk" then
      local name, dmg, cost = val:match("^([^|]+)|([^|]*)|(.*)$")
      if name then
        raw.attacks[#raw.attacks + 1] = {
          name = name,
          damage = tonumber(dmg) or 0,
          cost = parseCost(cost),
        }
      end
    end
  end
  return raw
end

local function splitLines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r$", "")
    if line ~= "" then lines[#lines + 1] = line end
  end
  return lines
end

function Share.parse(text)
  if type(text) ~= "string" or not text:match("^PTCG1") then
    return nil, "Not a TCG share file"
  end
  local lines = splitLines(text)
  local kind
  for _, line in ipairs(lines) do
    if line:match("^kind=pack") then kind = "pack" break end
    if line:match("^kind=card") then kind = "card" break end
  end
  if kind == "card" then
    local last = #lines
    for i, line in ipairs(lines) do
      if line == "endcard" then last = i - 1 break end
    end
    return { type = "card", card = parseCardLines(lines, 1, last) }
  end
  if kind ~= "pack" then return nil, "Unknown share file" end
  local pack = { cards = {}, slots = {} }
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local key, val = line:match("^([%w]+)=(.*)$")
    if line == "kind=card" then
      local start = i
      local stop = #lines
      for j = i, #lines do
        if lines[j] == "endcard" then stop = j - 1 break end
      end
      pack.cards[#pack.cards + 1] = parseCardLines(lines, start, stop)
      i = stop + 1
    elseif key == "name" then pack.name = val
    elseif key == "set" then pack.set = val
    elseif key == "price" then pack.price = tonumber(val)
    elseif key == "packpic" then pack.picB64 = val
    elseif key == "vcard" then
      pack.slots[#pack.slots + 1] = { kind = "v", id = tonumber(val) }
    elseif key == "use" then
      pack.slots[#pack.slots + 1] = { kind = "use", name = val }
    end
    i = i + 1
  end
  return { type = "pack", pack = pack }
end

function Share.exportCard(mod, id)
  local card = Cache.card(id)
  if not card or not card.custom then return nil, "Not a custom card" end
  local lines = { "PTCG1" }
  local body = cardLines(card, Custom.picB64(mod, id))
  for _, line in ipairs(body) do lines[#lines + 1] = line end
  return Share.writeExport(card.name, table.concat(lines, "\n"))
end

function Share.exportPack(mod, setName)
  local pack
  for _, p in ipairs(Custom.packs(mod)) do
    if p.set == setName then pack = p break end
  end
  if not pack then return nil, "Unknown pack" end
  local lines = {
    "PTCG1",
    "kind=pack",
    "name=" .. (pack.name or pack.set),
    "set=" .. pack.set,
    "price=" .. tostring(pack.price or 500),
  }
  local packPic = Custom.packPicB64(mod, pack.set)
  if packPic and packPic ~= "" then
    lines[#lines + 1] = "packpic=" .. packPic
  end
  local seen = {}
  for _, id in ipairs(pack.cards or {}) do
    local card = Cache.card(id)
    if card and card.custom then
      if not seen[id] then
        seen[id] = true
        local body = cardLines(card, Custom.picB64(mod, id))
        for _, line in ipairs(body) do lines[#lines + 1] = line end
      end
      lines[#lines + 1] = "use=" .. (card.name or "")
    elseif id then
      lines[#lines + 1] = "vcard=" .. tostring(id)
    end
  end
  return Share.writeExport(pack.name or pack.set, table.concat(lines, "\n"))
end

local function importOneCard(mod, raw)
  raw.id = nil
  local card, err = Custom.saveCard(mod, raw)
  if not card then return nil, err end
  if raw.picB64 and raw.picB64 ~= "" then
    Custom.setPic(mod, card.id, raw.picB64)
  end
  Save.addCards(mod, { card.id })
  return card
end

function Share.importText(mod, text)
  local parsed, err = Share.parse(text)
  if not parsed then return nil, err end
  if parsed.type == "card" then
    local card, cardErr = importOneCard(mod, parsed.card)
    if not card then return nil, cardErr end
    return { kind = "card", name = card.name, count = 1 }
  end
  local pack = parsed.pack
  local byName = {}
  for _, raw in ipairs(pack.cards or {}) do
    local card = importOneCard(mod, raw)
    if card then byName[card.name] = card.id end
  end
  local ids = {}
  for _, slot in ipairs(pack.slots or {}) do
    if slot.kind == "v" and slot.id and Cache.card(slot.id) then
      ids[#ids + 1] = slot.id
    elseif slot.kind == "use" and slot.name and byName[slot.name] then
      ids[#ids + 1] = byName[slot.name]
    end
  end
  if #ids == 0 then
    for _, id in pairs(byName) do ids[#ids + 1] = id end
  end
  if #ids == 0 then return nil, "Pack has no usable cards" end
  local saved, packErr = Custom.savePack(mod, {
    name = pack.name or "IMPORT",
    price = pack.price or 500,
    cards = ids,
    picB64 = pack.picB64,
  })
  if not saved then return nil, packErr end
  Save.addPack(mod, saved.set, 1)
  return { kind = "pack", name = saved.name or saved.set, count = #ids }
end

function Share.importFile(mod, name)
  local text = Share.readExport(mod, name)
  if not text then return nil, "Could not read file" end
  return Share.importText(mod, text)
end

Share.b64enc = b64enc
Share.b64dec = b64dec

return Share
