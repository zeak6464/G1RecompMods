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

## Maps

Overworld rooms are pret tilemaps in bank `$20` plus tileset gfx / pals. `lib/map_gfx.lua` decompresses the tilemap + half-res permission map, loads `WarpDataPointers` (`07:4099`), and draws `OWPlayerGfx` (`22:7E90`). NPCs come from `MapScripts` (`04:562a`) → `npc_map_data` + `NPCHeaderPointers` (`04:58f5`) / `Sprites` (`20:516b`) via `lib/npc_gfx.lua`. Talk scans bank-`$03` scripts (`lib/npc_script.lua`) for the first `print_*` text; duelists use header `deckId + 2` → `DeckPointers`. Walkable set: all indoor maps (`data/maps.lua`, mapIds 1–33) except the cursor overworld map.

## Scope

v0.1+ decodes cards, packs, duels, and a small walkable TCG map graph from the ROM (warps, NPCs, dialog, duel start). Full script VMs, preload events, and the overworld map UI are still approximate.

