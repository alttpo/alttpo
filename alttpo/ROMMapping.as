ROMMapping @rom = null;

// Lookup table of ROM addresses depending on version:
abstract class ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0; }
  uint32 get_tilemap_darkWorldMap()  property { return 0; }
  uint32 get_palette_lightWorldMap() property { return 0; }
  uint32 get_palette_darkWorldMap()  property { return 0; }

  // entrance & exit tables:
  uint32 get_entrance_table_room()    property { return 0; }
  uint32 get_exit_table_room()        property { return 0; }
  uint32 get_exit_table_link_y()      property { return 0; }
  uint32 get_exit_table_link_x()      property { return 0; }

  uint32 get_fn_pre_main_loop() property               { return 0; }  // points to JSR ClearOamBuffer
  uint32 get_fn_patch() property                       { return 0; }  // points to JSL Module_MainRouting

  uint32 addr_main_routing = 0;
  void read_main_routing() {
    // don't overwrite our last read value to avoid reading a patched-over value:
    if (addr_main_routing != 0) return;

    // read JSL instruction's 24-bit address at the patch point from RESET vector:
    auto offs = uint32(bus::read_u16(fn_patch + 1));
    auto bank = uint32(bus::read_u8(fn_patch + 3));
    addr_main_routing = (bank << 16) | offs;

    message("main_routing = 0x" + fmtHex(addr_main_routing, 6));
  }
  uint32 get_fn_main_routing() property                { return addr_main_routing; }

  uint32 get_fn_dungeon_light_torch() property         { return 0; }
  uint32 get_fn_dungeon_light_torch_success() property { return 0; }
  uint32 get_fn_dungeon_extinguish_torch() property    { return 0; }
  uint32 get_fn_sprite_init() property                 { return 0; }
};

class USROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC727; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD727; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB27; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC27; }

  // entrance & exit tables:
  uint32 get_entrance_table_room()    property { return 0x02C813; }
  uint32 get_exit_table_room()        property { return 0x02DD8A; }
  uint32 get_exit_table_link_y()      property { return 0x02E051; }
  uint32 get_exit_table_link_x()      property { return 0x02E0EF; }

  uint32 get_fn_pre_main_loop() property               { return 0x008053; }
  uint32 get_fn_patch() property                       { return 0x008056; }
  //uint32 get_fn_main_routing() property                { return 0x0080B5; }

  uint32 get_fn_dungeon_light_torch() property         { return 0x01F3EC; }
  uint32 get_fn_dungeon_light_torch_success() property { return 0x01F48D; }
  uint32 get_fn_dungeon_extinguish_torch() property    { return 0x01F4A6; }
  uint32 get_fn_sprite_init() property                 { return 0x0DB818; }
};

class EUROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC727; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD727; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB27; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC27; }

  // entrance & exit tables:
  uint32 get_entrance_table_room()    property { return 0x02C813; } // TODO
  uint32 get_exit_table_room()        property { return 0x02DD8A; } // TODO
  uint32 get_exit_table_link_y()      property { return 0x02E051; } // TODO
  uint32 get_exit_table_link_x()      property { return 0x02E0EF; } // TODO

  uint32 get_fn_pre_main_loop() property               { return 0x008053; } // TODO
  uint32 get_fn_patch() property                       { return 0x008056; } // TODO
  //uint32 get_fn_main_routing() property                { return 0x0080B5; }

  uint32 get_fn_dungeon_light_torch() property         { return 0xFFFFFF; } // TODO
  uint32 get_fn_dungeon_light_torch_success() property { return 0xFFFFFF; } // TODO
  uint32 get_fn_dungeon_extinguish_torch() property    { return 0xFFFFFF; } // TODO
  uint32 get_fn_sprite_init() property                 { return 0xFFFFFF; } // TODO
};

class JPROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC739; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD739; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB39; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC39; }

  // entrance & exit tables:
  uint32 get_entrance_table_room()    property { return 0x02C813; } // TODO
  uint32 get_exit_table_room()        property { return 0x02DD8A; } // TODO
  uint32 get_exit_table_link_y()      property { return 0x02E051; } // TODO
  uint32 get_exit_table_link_x()      property { return 0x02E0EF; } // TODO

  uint32 get_fn_pre_main_loop() property               { return 0x008053; } // TODO
  uint32 get_fn_patch() property                       { return 0x008056; } // TODO
  //uint32 get_fn_main_routing() property                { return 0x0080B5; }

  uint32 get_fn_dungeon_light_torch() property         { return 0xFFFFFF; } // TODO
  uint32 get_fn_dungeon_light_torch_success() property { return 0xFFFFFF; } // TODO
  uint32 get_fn_dungeon_extinguish_torch() property    { return 0xFFFFFF; } // TODO
  uint32 get_fn_sprite_init() property                 { return 0xFFFFFF; } // TODO
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
