-- US Pokémon TCG (U) layout facts from pret/poketcg symbols (poketcg.sym).
-- SHA1 must match pret README. No ROM bytes are stored here.

return {
  SHA1 = "0f8670a583255cff3e5b7ca71b5d7454d928fc48",
  NUM_CARDS = 0xE4, -- 228

  -- bank:offset from symbols → file offset = bank*0x4000 + (offset-0x4000)
  CARD_POINTERS_BANK = 0x0C,
  CARD_POINTERS_OFFSET = 0x4C5C,
  DECK_POINTERS_BANK = 0x0C,
  DECK_POINTERS_OFFSET = 0x4000,
  PRACTICE_PLAYER_DECK_BANK = 0x0C,
  PRACTICE_PLAYER_DECK_OFFSET = 0x4344,
  CARD_GRAPHICS_BANK = 0x31,
  CARD_GRAPHICS_OFFSET = 0x4000,
  TEXT_OFFSETS_BANK = 0x0D,
  TEXT_OFFSETS_OFFSET = 0x4000,


  PKMN_CARD_DATA_LENGTH = 0x41,
  ENERGY_CARD_DATA_LENGTH = 0x0E,
  TRAINER_CARD_DATA_LENGTH = 0x0E,

  TYPE_ENERGY = 0x08,
  TYPE_TRAINER = 0x10,

  RARITY = {
    [0] = "CIRCLE",
    [1] = "DIAMOND",
    [2] = "STAR",
    [0xFF] = "PROMOSTAR",
  },

  STAGE = {
    [0] = "BASIC",
    [1] = "STAGE1",
    [2] = "STAGE2",
    [3] = "STAGE2_WITHOUT_STAGE1",
  },

  TYPE_NAME = {
    [0] = "FIRE",
    [1] = "GRASS",
    [2] = "LIGHTNING",
    [3] = "WATER",
    [4] = "FIGHTING",
    [5] = "PSYCHIC",
    [6] = "COLORLESS",
    [7] = "UNUSED",
    [8] = "ENERGY_FIRE",
    [9] = "ENERGY_GRASS",
    [10] = "ENERGY_LIGHTNING",
    [11] = "ENERGY_WATER",
    [12] = "ENERGY_FIGHTING",
    [13] = "ENERGY_PSYCHIC",
    [14] = "ENERGY_DOUBLE_COLORLESS",
    [16] = "TRAINER",
  },

  WR = {
    [0x80] = "FIRE",
    [0x40] = "GRASS",
    [0x20] = "LIGHTNING",
    [0x10] = "WATER",
    [0x08] = "FIGHTING",
    [0x04] = "PSYCHIC",
  },

  SET_HI = {
    [0] = "COLOSSEUM",
    [1] = "EVOLUTION",
    [2] = "MYSTERY",
    [3] = "LABORATORY",
    [4] = "PROMOTIONAL",
    [5] = "ENERGY",
  },
}
