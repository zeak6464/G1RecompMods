-- Pokémon Pinball (U) layout facts from pret/pokepinball.
-- SHA1 must match pret README. No ROM bytes are stored here.

return {
  SHA1 = "9402014d14969432142abfde728c6f1a10ee4dac",
  NUM_POKEMON = 151,

  -- File offsets from pret labels (absolute ROM offset).
  WILD_MON_OFFSETS_POINTERS = 0x1126c,
  RED_STAGE_WILD_MONS = 0x112cc,
  -- Blue wilds follow red block in bank (see data/blue_wild_mons.asm).
  BLUE_STAGE_WILD_MONS = 0x1144e,

  WILD_SLOT_COUNT = 16, -- common + rare each

  -- Stage GBC bottom backgrounds (pret main.asm labels).
  RED_BOTTOM_GFX0 = 0xa2000,
  RED_BOTTOM_GFX1 = 0xa3000,
  RED_BOTTOM_TILEMAP = 0xbe800,
  RED_BOTTOM_ATTR = 0xbec00,
  RED_BOTTOM_PAL = 0xdca80,

  BLUE_BOTTOM_GFX0 = 0xa4000,
  BLUE_BOTTOM_GFX1 = 0xa5000,
  BLUE_BOTTOM_TILEMAP = 0xc7000,
  BLUE_BOTTOM_ATTR = 0xc7400,
  BLUE_BOTTOM_PAL = 0xdcb80,

  -- Stage GBC top (vTilesSH is assembled: status + gfx3 + base; bank1 = gfx4).
  RED_TOP_STATUS = 0x9c000,
  RED_TOP_GFX3 = 0x97a00,
  RED_TOP_BASE = 0x9c2a0,
  RED_TOP_GFX4 = 0x9d000,
  RED_TOP_TILEMAP = 0xbe000,
  RED_TOP_ATTR = 0xbe400,
  RED_TOP_PAL = 0xdc980,

  BLUE_TOP_STATUS = 0xa0000,
  BLUE_TOP_GFX3 = 0xd6600,
  BLUE_TOP_BASE = 0xa02a0,
  BLUE_TOP_GFX4 = 0xa1000,
  BLUE_TOP_TILEMAP = 0xc6800,
  BLUE_TOP_ATTR = 0xc6c00,
  BLUE_TOP_PAL = 0xdcb00,

  BALL_GFX = 0xa8400,
  FLIPPER_GFX = 0xa8600,

  -- pret CheckStageTransition: ball Y +/- $88 when swapping halves.
  HALF_Y_SHIFT = 136,
}
