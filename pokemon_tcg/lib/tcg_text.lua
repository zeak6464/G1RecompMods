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
  local maxChars = opts.maxChars or (opts.keepNewlines and 280 or 96)
  local chars = {}
  local i = addr
  local guard = 0
  while guard < maxChars do
    guard = guard + 1
    if i >= #rom then break end
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
      -- pret halfwidth often uses ` for é (Pokémon)
      local ch = (b == 0x60) and "e" or string.char(b)
      chars[#chars + 1] = ch
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

-- Format multi-line TCG dialog for Gen1 TextBox: 2 lines per page, A to advance.
-- Plain "\n" between every line auto-scrolls; use "\f" page breaks instead.
function TcgText.toTextBox(text, speaker)
  if not text or text == "" then text = "..." end
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then lines[#lines + 1] = line end
  end
  if speaker and speaker ~= "" then
    table.insert(lines, 1, speaker)
  end
  if #lines == 0 then return "..." end
  local pages = {}
  for i = 1, #lines, 2 do
    local a = lines[i]
    local b = lines[i + 1]
    if b then
      pages[#pages + 1] = a .. "\n" .. b
    else
      pages[#pages + 1] = a
    end
  end
  return table.concat(pages, "\f")
end

return TcgText
