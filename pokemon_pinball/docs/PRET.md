# pret/pokepinball notes

- Repo: https://github.com/pret/pokepinball
- ROM: `Pokemon Pinball (U) [C][!].gb`  
  SHA1 `9402014d14969432142abfde728c6f1a10ee4dac`
- Default location for this mod: `mods/pokemon_pinball/roms/PokemonPinball.gbc`
- Wild tables: `data/wild_mons.asm` / `data/red_wild_mons.asm` (file off `0x112cc`)
- Stages: `constants/stage_constants.asm` (Red/Blue top+bottom, bonus stages)
- Maps: `constants/map_constants.asm`
- Engine loop: `engine/pinball_game.asm` (`HandlePinballGame`)

This mod uses **custom** pinball mechanics in Lua (gravity, segments,
flipper capsules, follow-camera on a 160×288 world). It does **not** port
pret banks `$39`–`$3F` ball-physics LUTs. ROM data is used for graphics and
wild/map tables only.

## Stage GFX (imported from ROM)

| Asset | Offset |
|-------|--------|
| Red bottom tiles bank0/1 | `0xa2000` / `0xa3000` |
| Red bottom tilemap + attr | `0xbe800` / `0xbec00` |
| Red bottom BG palettes | `0xdca80` |
| Blue bottom tiles bank0/1 | `0xa4000` / `0xa5000` |
| Blue bottom tilemap + attr | `0xc7000` / `0xc7400` |
| Blue bottom BG palettes | `0xdcb80` |
| Red top (assembled bank0 + gfx4) | status `0x9c000`, base `0x9c2a0`, gfx4 `0x9d000` |
| Blue top | status `0xa0000`, base `0xa02a0`, gfx4 `0xa1000` |
| Poké Ball OBJ | `0xa8400` |

Decoded in `lib/stage_gfx.lua` and drawn by `screens/PinPlay.lua`.

Camera follows the ball the same way as pret: swap TOP/BOTTOM
backgrounds when the ball crosses the screen edge
(`engine/pinball_game/vertical_screen_transition.asm`, Y ± `$88`).

Base tiles are loaded to `vTilesSH` ($8800) for $1000 bytes (see
`data/stage_base_gfx.asm`). BG uses signed tile addressing, so ROM blob
order is tiles 128–255 then 0–127 — not 0–255 linear.
