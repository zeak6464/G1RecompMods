-- Map Move locations (pret map_constants.asm).
local MAPS = {
  { id = 0,  key = "PALLET_TOWN",       label = "PALLET",   field = "RED" },
  { id = 1,  key = "VIRIDIAN_CITY",     label = "VIRIDIAN", field = "BLUE" },
  { id = 2,  key = "VIRIDIAN_FOREST",   label = "FOREST",   field = "BOTH" },
  { id = 3,  key = "PEWTER_CITY",       label = "PEWTER",   field = "RED" },
  { id = 4,  key = "MT_MOON",           label = "MT MOON",  field = "BLUE" },
  { id = 5,  key = "CERULEAN_CITY",     label = "CERULEAN", field = "BOTH" },
  { id = 6,  key = "VERMILION_SEASIDE", label = "VERM SEA", field = "RED" },
  { id = 7,  key = "VERMILION_STREETS", label = "VERM ST",  field = "BLUE" },
  { id = 8,  key = "ROCK_MOUNTAIN",     label = "ROCK MTN", field = "BOTH" },
  { id = 9,  key = "LAVENDER_TOWN",     label = "LAVENDER", field = "RED" },
  { id = 10, key = "CELADON_CITY",      label = "CELADON",  field = "BLUE" },
  { id = 11, key = "CYCLING_ROAD",      label = "CYCLING",  field = "RED" },
  { id = 12, key = "FUCHSIA_CITY",      label = "FUCHSIA",  field = "BLUE" },
  { id = 13, key = "SAFARI_ZONE",       label = "SAFARI",   field = "BOTH" },
  { id = 14, key = "SAFFRON_CITY",      label = "SAFFRON",  field = "BLUE" },
  { id = 15, key = "SEAFOAM_ISLANDS",   label = "SEAFOAM",  field = "RED" },
  { id = 16, key = "CINNABAR_ISLAND",   label = "CINNABAR", field = "BOTH" },
  { id = 17, key = "INDIGO_PLATEAU",    label = "INDIGO",   field = "BOTH" },
}

local byKey = {}
for _, m in ipairs(MAPS) do byKey[m.key] = m end

return {
  ALL = MAPS,
  byKey = byKey,
  forField = function(field)
    local out = {}
    for _, m in ipairs(MAPS) do
      if m.field == field or m.field == "BOTH" then
        out[#out + 1] = m
      end
    end
    return out
  end,
}
