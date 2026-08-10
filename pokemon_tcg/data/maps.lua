-- pret/poketcg maps (US). mapId matches map_constants.asm.
-- Warps are loaded from WarpDataPointers (bank $07) by mapId.
-- Tilemap / tileset / pal offsets from pret symbols (non-CGB tilemaps).
return {
  -- id 0 OVERWORLD_MAP → exits map screen (hub); not a walkable room here

  MASON_LABORATORY = {
    mapId = 1, label = "MASON LAB",
    mapBank = 0x20, mapOffset = 0x5C13,
    tilesBank = 0x22, tilesOffset = 0x4C12,
    palBank = 0x2D, palOffset = 0x740F,
    spawnX = 14, spawnY = 26,
  },
  DECK_MACHINE_ROOM = {
    mapId = 2, label = "DECK MACHINE",
    mapBank = 0x20, mapOffset = 0x5F26,
    tilesBank = 0x22, tilesOffset = 0x4C12,
    palBank = 0x2D, palOffset = 0x740F,
    spawnX = 2, spawnY = 10,
  },
  ISHIHARAS_HOUSE = {
    mapId = 3, label = "ISHIHARA",
    mapBank = 0x20, mapOffset = 0x6160,
    tilesBank = 0x21, tilesOffset = 0x7828,
    palBank = 0x2D, palOffset = 0x7451,
    spawnX = 8, spawnY = 20,
  },

  FIGHTING_CLUB_ENTRANCE = {
    mapId = 4, label = "FIGHT ENT",
    mapBank = 0x20, mapOffset = 0x6336,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x7493,
    spawnX = 8, spawnY = 14,
  },
  FIGHTING_CLUB_LOBBY = {
    mapId = 5, label = "FIGHT LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  FIGHTING_CLUB = {
    mapId = 6, label = "FIGHTING CLUB",
    mapBank = 0x20, mapOffset = 0x76DB,
    tilesBank = 0x22, tilesOffset = 0x6518,
    palBank = 0x2D, palOffset = 0x76E5,
    spawnX = 10, spawnY = 14,
  },

  ROCK_CLUB_ENTRANCE = {
    mapId = 7, label = "ROCK ENT",
    mapBank = 0x20, mapOffset = 0x651D,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x74D5,
    spawnX = 8, spawnY = 14,
  },
  ROCK_CLUB_LOBBY = {
    mapId = 8, label = "ROCK LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  ROCK_CLUB = {
    mapId = 9, label = "ROCK CLUB",
    mapBank = 0x20, mapOffset = 0x788D,
    tilesBank = 0x22, tilesOffset = 0x6B4A,
    palBank = 0x2D, palOffset = 0x7727,
    spawnX = 12, spawnY = 26,
  },

  WATER_CLUB_ENTRANCE = {
    mapId = 10, label = "WATER ENT",
    mapBank = 0x20, mapOffset = 0x6704,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x7517,
    spawnX = 8, spawnY = 14,
  },
  WATER_CLUB_LOBBY = {
    mapId = 11, label = "WATER LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  WATER_CLUB = {
    mapId = 12, label = "WATER CLUB",
    mapBank = 0x21, mapOffset = 0x4000,
    tilesBank = 0x22, tilesOffset = 0x6F0C,
    palBank = 0x2D, palOffset = 0x7769,
    spawnX = 12, spawnY = 28,
  },

  LIGHTNING_CLUB_ENTRANCE = {
    mapId = 13, label = "LIGHT ENT",
    mapBank = 0x20, mapOffset = 0x68EB,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x7559,
    spawnX = 8, spawnY = 14,
  },
  LIGHTNING_CLUB_LOBBY = {
    mapId = 14, label = "LIGHT LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  LIGHTNING_CLUB = {
    mapId = 15, label = "LIGHTNING CLUB",
    mapBank = 0x21, mapOffset = 0x43BB,
    tilesBank = 0x23, tilesOffset = 0x4000,
    palBank = 0x2D, palOffset = 0x77AB,
    spawnX = 12, spawnY = 28,
  },

  GRASS_CLUB_ENTRANCE = {
    mapId = 16, label = "GRASS ENT",
    mapBank = 0x20, mapOffset = 0x6AD2,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x759B,
    spawnX = 8, spawnY = 14,
  },
  GRASS_CLUB_LOBBY = {
    mapId = 17, label = "GRASS LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  GRASS_CLUB = {
    mapId = 18, label = "GRASS CLUB",
    mapBank = 0x21, mapOffset = 0x472E,
    tilesBank = 0x22, tilesOffset = 0x791E,
    palBank = 0x2D, palOffset = 0x77ED,
    spawnX = 12, spawnY = 28,
  },

  PSYCHIC_CLUB_ENTRANCE = {
    mapId = 19, label = "PSYCH ENT",
    mapBank = 0x20, mapOffset = 0x6CB9,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x75DD,
    spawnX = 8, spawnY = 14,
  },
  PSYCHIC_CLUB_LOBBY = {
    mapId = 20, label = "PSYCH LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  PSYCHIC_CLUB = {
    mapId = 21, label = "PSYCHIC CLUB",
    mapBank = 0x21, mapOffset = 0x4B73,
    tilesBank = 0x23, tilesOffset = 0x4832,
    palBank = 0x2D, palOffset = 0x782F,
    spawnX = 12, spawnY = 24,
  },

  SCIENCE_CLUB_ENTRANCE = {
    mapId = 22, label = "SCIENCE ENT",
    mapBank = 0x20, mapOffset = 0x6EA0,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x761F,
    spawnX = 8, spawnY = 14,
  },
  SCIENCE_CLUB_LOBBY = {
    mapId = 23, label = "SCIENCE LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  SCIENCE_CLUB = {
    mapId = 24, label = "SCIENCE CLUB",
    mapBank = 0x21, mapOffset = 0x4DFE,
    tilesBank = 0x23, tilesOffset = 0x4BD4,
    palBank = 0x2D, palOffset = 0x7871,
    spawnX = 12, spawnY = 28,
  },

  FIRE_CLUB_ENTRANCE = {
    mapId = 25, label = "FIRE ENT",
    mapBank = 0x20, mapOffset = 0x7087,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x7661,
    spawnX = 8, spawnY = 14,
  },
  FIRE_CLUB_LOBBY = {
    mapId = 26, label = "FIRE LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  FIRE_CLUB = {
    mapId = 27, label = "FIRE CLUB",
    mapBank = 0x21, mapOffset = 0x50B6,
    tilesBank = 0x23, tilesOffset = 0x50F6,
    palBank = 0x2D, palOffset = 0x78B3,
    spawnX = 12, spawnY = 28,
  },

  CHALLENGE_HALL_ENTRANCE = {
    mapId = 28, label = "CHALLENGE ENT",
    mapBank = 0x20, mapOffset = 0x726E,
    tilesBank = 0x22, tilesOffset = 0x5584,
    palBank = 0x2D, palOffset = 0x7493, -- same as fighting entrance in pret headers
    spawnX = 8, spawnY = 14,
  },
  CHALLENGE_HALL_LOBBY = {
    mapId = 29, label = "CHALLENGE LOBBY",
    mapBank = 0x20, mapOffset = 0x7424,
    tilesBank = 0x22, tilesOffset = 0x5D96,
    palBank = 0x2D, palOffset = 0x76A3,
    spawnX = 24, spawnY = 10,
  },
  CHALLENGE_HALL = {
    mapId = 30, label = "CHALLENGE HALL",
    mapBank = 0x21, mapOffset = 0x5315,
    tilesBank = 0x23, tilesOffset = 0x5668,
    palBank = 0x2D, palOffset = 0x78F5,
    spawnX = 14, spawnY = 28,
  },

  POKEMON_DOME_ENTRANCE = {
    mapId = 31, label = "DOME ENT",
    mapBank = 0x21, mapOffset = 0x570A,
    tilesBank = 0x23, tilesOffset = 0x603A,
    palBank = 0x2D, palOffset = 0x7937,
    spawnX = 14, spawnY = 14,
  },
  POKEMON_DOME = {
    mapId = 32, label = "POKEMON DOME",
    mapBank = 0x21, mapOffset = 0x58EF,
    tilesBank = 0x23, tilesOffset = 0x651C,
    palBank = 0x2D, palOffset = 0x7979,
    spawnX = 14, spawnY = 28,
  },
  HALL_OF_HONOR = {
    mapId = 33, label = "HALL OF HONOR",
    mapBank = 0x21, mapOffset = 0x5CE2,
    tilesBank = 0x23, tilesOffset = 0x720E,
    palBank = 0x2D, palOffset = 0x79BB,
    spawnX = 10, spawnY = 22,
  },
}
