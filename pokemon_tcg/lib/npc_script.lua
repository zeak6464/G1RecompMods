-- Scan pret bank-$03 NPC scripts for the first printable dialog text.
local V = ...
local TcgText = V.require("tcg_text")

local NpcScript = {}

local SCRIPT_BANK = 0x03
local START_SCRIPT = 0xE7 -- rst $20

-- Operand byte counts for ScriptCommand_* (not including the opcode).
local CMD_OPS = {
  [0x00] = 0, [0x01] = 0, [0x02] = 2, [0x03] = 2, [0x04] = 4, [0x05] = 3,
  [0x06] = 4, [0x07] = 4, [0x08] = 2, [0x09] = 0, [0x0a] = 2, [0x0b] = 0,
  [0x0c] = 3, [0x0d] = 3, [0x0e] = 3, [0x0f] = 1, [0x10] = 1, [0x11] = 2,
  [0x12] = 0, [0x13] = 4, [0x14] = 10, [0x15] = 1, [0x16] = 0, [0x17] = 1,
  [0x18] = 2, [0x19] = 2, [0x1a] = 0, [0x1b] = 2, [0x1c] = 0, [0x1d] = 1,
  [0x1e] = 2, [0x1f] = 1, [0x20] = 1, [0x21] = 3, [0x22] = 3, [0x23] = 2,
  [0x24] = 1, [0x25] = 4, [0x26] = 4, [0x27] = 2, [0x28] = 0, [0x29] = 3,
  [0x2a] = 1, [0x2b] = 1, [0x2c] = 1, [0x2d] = 3, [0x2e] = 6, [0x2f] = 2,
  [0x30] = 0, [0x31] = 2, [0x32] = 0, [0x33] = 0, [0x34] = 0, [0x35] = 0,
  [0x36] = 1, [0x37] = 0, [0x38] = 1, [0x39] = 0, [0x3a] = 5, [0x3b] = 3,
  [0x3c] = 0, [0x3d] = 1, [0x3e] = 1, [0x3f] = 0, [0x40] = 1, [0x41] = 0,
  [0x42] = 1, [0x43] = 0, [0x44] = 0, [0x45] = 0, [0x46] = 1, [0x47] = 1,
  [0x48] = 1, [0x49] = 1, [0x4a] = 0, [0x4b] = 0, [0x4c] = 0, [0x4d] = 0,
  [0x4e] = 1, [0x4f] = 4, [0x50] = 0, [0x51] = 0, [0x52] = 0, [0x53] = 0,
  [0x54] = 0, [0x55] = 0, [0x56] = 0, [0x57] = 0, [0x58] = 2, [0x59] = 3,
  [0x5a] = 3, [0x5b] = 4, [0x5c] = 4, [0x5d] = 4, [0x5e] = 4, [0x5f] = 1,
  [0x60] = 1, [0x61] = 3, [0x62] = 3, [0x63] = 1, [0x64] = 0, [0x65] = 0,
  [0x66] = 0, [0x67] = 0,
}

local function bankFileOffset(bank, offsetInBank)
  if bank == 0 then return offsetInBank end
  return bank * 0x4000 + (offsetInBank - 0x4000)
end

local function u8(rom, off)
  return rom:byte(off + 1)
end

local function u16le(rom, off)
  return u8(rom, off) + u8(rom, off + 1) * 256
end

-- Find first print_npc_text / print_text / print_text_quit_fully / variable print.
-- Returns text string, textId (or nil, nil).
function NpcScript.firstDialogText(rom, scriptPtr)
  if not rom or not scriptPtr or scriptPtr == 0 then return nil, nil end
  local base = bankFileOffset(SCRIPT_BANK, scriptPtr)
  if base < 0 or base >= #rom then return nil, nil end

  local off = base
  -- Some NPCs wrap scripts in ASM; locate start_script (rst $20).
  if u8(rom, off) ~= START_SCRIPT then
    local found = nil
    for i = 0, 47 do
      if base + i < #rom and u8(rom, base + i) == START_SCRIPT then
        found = base + i
        break
      end
    end
    if not found then return nil, nil end
    off = found
  end
  off = off + 1 -- skip rst $20

  for _ = 1, 96 do
    if off >= #rom then break end
    local cmd = u8(rom, off)
    off = off + 1
    if cmd == 0x02 or cmd == 0x03 or cmd == 0x08 then
      local tx = u16le(rom, off)
      local text = TcgText.decode(rom, tx, { keepNewlines = true, maxChars = 280 })
      return text, tx
    elseif cmd == 0x06 or cmd == 0x07 then
      local tx = u16le(rom, off)
      local text = TcgText.decode(rom, tx, { keepNewlines = true, maxChars = 280 })
      return text, tx
    end
    local ops = CMD_OPS[cmd]
    if ops == nil then break end
    off = off + ops
  end
  return nil, nil
end

return NpcScript
