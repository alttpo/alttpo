
ROMMapping @rom = null;

// Lookup table of ROM addresses depending on version:
abstract class ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0; }
  uint32 get_tilemap_darkWorldMap()  property { return 0; }
  uint32 get_palette_lightWorldMap() property { return 0; }
  uint32 get_palette_darkWorldMap()  property { return 0; }
};

class JPROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC739; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD739; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB39; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC39; }
};

class USROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC727; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD727; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB27; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC27; }
};

class EUROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC727; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD727; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB27; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC27; }
};

ROMMapping@ detect() {
  array<uint8> sig(22);
  bus::read_block_u8(0x00FFC0, 0, 22, sig);
  auto title = sig.toString(0, 22);
  message("ROM title: \"" + title + "\"");
  if (title == "THE LEGEND OF ZELDA   ") {
    auto region = bus::read_u8(0x00FFD9);
    if (region == 0x01) {
      message("Recognized US ROM version.");
      return USROMMapping();
    } else if (region == 0x02) {
      message("Recognized EU ROM version.");
      return EUROMMapping();
    } else {
      message("Unrecognized ROM version but has US title; assuming US ROM.");
      return USROMMapping();
    }
  } else if (title == "ZELDANODENSETSU       ") {
    message("Recognized JP ROM version.");
    return JPROMMapping();
  } else if (sig.toString(0, 3) == "VT ") {
    // randomizer. use JP ROM by default.
    message("Recognized randomized JP ROM version. Seed: " + sig.toString(3, 10));
    return JPROMMapping();
  } else {
    message("Unrecognized ALTTP ROM version! Assuming JP ROM version.");
    return JPROMMapping();
  }
}
