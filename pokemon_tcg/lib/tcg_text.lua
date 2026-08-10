-- Decode pret/poketcg text IDs (TextOffsets + halfwidth ASCII strings).
local V = ...
local Layout = V.require("data.import_layout")
local bit = require("bit")

local TcgText = {}

local TX_END = 0x00
local TX_HALFWIDTH = 0x06
local TX_LINE = 0x0A

local function bankFileOffset(bank, offsetInBank)
  if bank == 0 then return offsetInBank end
  return bank * 0x4000 + (offsetInBank - 0x4000)
end

function TcgText.textOffsetsBase()
  return bankFileOffset(Layout.TEXT_OFFSETS_BANK, Layout.TEXT_OFFSETS_OFFSET)
end

function TcgText.addr(rom, textId)
  if not rom or not textId or textId == 0 then return nil end
  local base = TcgText.textOffsetsBase()
  local e = base + textId * 3
  if e + 2 >= #rom then return nil end
  local lo = rom:byte(e + 1) + rom:byte(e + 2) * 256
  local hi = rom:byte(e + 3)
  local rel = lo + hi * 65536
  local addr = base + rel
  if addr < 1 or addr >= #rom then return nil end
  return addr
end

function TcgText.decode(rom, textId, opts)
  opts = opts or {}
  local addr = TcgText.addr(rom, textId)
  if not addr then return nil end
  local chars = {}
  local i = addr
  local guard = 0
  while guard < 96 do
    guard = guard + 1
    local b = rom:byte(i + 1)
    if not b or b == TX_END then break end
    if b == TX_HALFWIDTH then
      i = i + 1
    elseif b == TX_LINE then
      if opts.keepNewlines then
        chars[#chars + 1] = "\n"
      else
        break -- first line only for names
      end
      i = i + 1
    elseif b >= 0x20 and b <= 0x7E then
      chars[#chars + 1] = string.char(b)
      i = i + 1
    else
      -- skip unknown control bytes
      i = i + 1
    end
  end
  local s = table.concat(chars)
  if s == "" then return nil end
  if opts.upper then s = s:upper() end
  return s
end

return TcgText
