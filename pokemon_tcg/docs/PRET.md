# Pokémon TCG ROM import (pret/poketcg)

This mod does **not** ship ROM bytes. Players must provide a US Pokémon TCG `.gbc` ROM.

## Expected ROM

- File: `roms/PokemonTCG.gbc` (project root) or path from mod options
- SHA1: `0f8670a583255cff3e5b7ca71b5d7454d928fc48` (pret US TCG)

## Layout guide

Offsets and struct sizes come from [pret/poketcg](https://github.com/pret/poketcg) symbols:

| Symbol | Bank:offset | Use |
|--------|-------------|-----|
| `CardPointers` | `0C:4C5C` | Card data pointer table |
| `PracticePlayerDeck` | `0C:4344` | Starter 60-card list (`count, id` pairs) |

Card IDs / names are mirrored from pret `card_constants.asm` in `data/card_ids.lua`.

## Card graphics

Each card’s `gfx` field is pret’s packed index:

`offset_from_CardGraphics = gfx * 8`

At that offset: **768** bytes of 64×48 2bpp (rgbgfx `-Z` column order) + **8** bytes GBC RGB555 palette (4 colors). See `lib/card_gfx.lua`.

## Scope

v0.1+ decodes card stats, practice deck, and card face art from the ROM. Full attack effect scripts and authentic booster-pack tiles are still approximate.

