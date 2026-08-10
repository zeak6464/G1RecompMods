import pathlib, re, urllib.request

url = "https://raw.githubusercontent.com/pret/poketcg/master/src/constants/card_constants.asm"
text = urllib.request.urlopen(url).read().decode("utf-8", "replace")
ids = {}
n = 1
for line in text.splitlines():
    m = re.match(r"\s*const\s+([A-Z0-9_]+)", line)
    if m:
        ids[n] = m.group(1)
        n += 1

root = pathlib.Path(__file__).resolve().parent
(root / "data").mkdir(parents=True, exist_ok=True)
lines = [
    "-- Card IDs from pret/poketcg card_constants.asm (open-source labels).",
    "return {",
]
for k in sorted(ids):
    lines.append(f'  [{k}] = "{ids[k]}",')
lines.append("}")
(root / "data" / "card_ids.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("cards", len(ids), "bulb", ids.get(8))

rom = pathlib.Path(
    r"C:\Users\amand\OneDrive\Documents\GitHub\Gen1Recomp Content Editor\roms\PokemonTCG.gbc"
).read_bytes()


def bank_addr(bank, off):
    return bank * 0x4000 + (off - 0x4000) if bank else off


cp = bank_addr(0x0C, 0x4C5C)
idx = 8
ptr = rom[cp + idx * 2] | (rom[cp + idx * 2 + 1] << 8)
off = bank_addr(0x0C, ptr)
print(
    "ptr",
    hex(ptr),
    "type",
    rom[off],
    "hp",
    rom[off + 8],
    "id",
    rom[off + 7],
    "retreat",
    rom[off + 0x32],
    "weak",
    hex(rom[off + 0x33]),
    "atk1dmg",
    rom[off + 0x16],
)
