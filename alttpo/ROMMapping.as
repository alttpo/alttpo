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

  uint32 get_fn_decomp_sword_gfx() property    { return 0; }
  uint32 get_fn_decomp_shield_gfx() property   { return 0; }
  uint32 get_fn_sword_palette() property       { return 0; }
  uint32 get_fn_shield_palette() property      { return 0; }
  uint32 get_fn_armor_glove_palette() property { return 0; }

  // MUST be sorted by offs ascending:
  array<SyncableItem@> @syncables = {
    SyncableItem(0x340, 1, 1),  // bow
    SyncableItem(0x341, 1, 1),  // boomerang
    SyncableItem(0x342, 1, 1),  // hookshot
    //SyncableItem(0x343, 1, 3),  // bombs (TODO)
    SyncableItem(0x344, 1, 1),  // mushroom
    SyncableItem(0x345, 1, 1),  // fire rod
    SyncableItem(0x346, 1, 1),  // ice rod
    SyncableItem(0x347, 1, 1),  // bombos
    SyncableItem(0x348, 1, 1),  // ether
    SyncableItem(0x349, 1, 1),  // quake
    SyncableItem(0x34A, 1, 1),  // lantern
    SyncableItem(0x34B, 1, 1),  // hammer
    SyncableItem(0x34C, 1, 1),  // flute
    SyncableItem(0x34D, 1, 1),  // bug net
    SyncableItem(0x34E, 1, 1),  // book
    //SyncableItem(0x34F, 1, 1),  // current bottle selection (1-4); do not sync as it locks the bottle selector in place
    SyncableItem(0x350, 1, 1),  // cane of somaria
    SyncableItem(0x351, 1, 1),  // cane of byrna
    SyncableItem(0x352, 1, 1),  // magic cape
    SyncableItem(0x353, 1, 1),  // magic mirror
    SyncableItem(0x354, 1, @mutateArmorGloves),  // gloves
    SyncableItem(0x355, 1, 1),  // boots
    SyncableItem(0x356, 1, 1),  // flippers
    SyncableItem(0x357, 1, 1),  // moon pearl
    // 0x358 unused
    SyncableItem(0x359, 1, @mutateSword),   // sword
    SyncableItem(0x35A, 1, @mutateShield),  // shield
    SyncableItem(0x35B, 1, @mutateArmorGloves),   // armor

    // bottle contents 0x35C-0x35F
    SyncableItem(0x35C, 1, @mutateBottleItem),
    SyncableItem(0x35D, 1, @mutateBottleItem),
    SyncableItem(0x35E, 1, @mutateBottleItem),
    SyncableItem(0x35F, 1, @mutateBottleItem),

    SyncableItem(0x364, 1, 2),  // dungeon compasses 1/2
    SyncableItem(0x365, 1, 2),  // dungeon compasses 2/2
    SyncableItem(0x366, 1, 2),  // dungeon big keys 1/2
    SyncableItem(0x367, 1, 2),  // dungeon big keys 2/2
    SyncableItem(0x368, 1, 2),  // dungeon maps 1/2
    SyncableItem(0x369, 1, 2),  // dungeon maps 2/2

    SyncableHealthCapacity(),  // heart pieces (out of four) [0x36B], health capacity [0x36C]

    SyncableItem(0x370, 1, 1),  // bombs capacity
    SyncableItem(0x371, 1, 1),  // arrows capacity

    SyncableItem(0x374, 1, 2),  // pendants
    //SyncableItem(0x377, 1, 1),  // arrows
    SyncableItem(0x379, 1, 2),  // player ability flags
    SyncableItem(0x37A, 1, 2),  // crystals

    SyncableItem(0x37B, 1, 1),  // magic usage

    SyncableItem(0x3C5, 1, @mutateWorldState),  // general progress indicator
    SyncableItem(0x3C6, 1, @mutateProgress1),  // progress event flags 1/2
    SyncableItem(0x3C7, 1, 1),  // map icons shown
    //SyncableItem(0x3C8, 1, 1),  // start at location… options; DISABLED - causes bugs
    SyncableItem(0x3C9, 1, 2)   // progress event flags 2/2

  // NO TRAILING COMMA HERE!
  };
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

  uint32 get_fn_decomp_sword_gfx() property    { return 0x00D2C8; }
  uint32 get_fn_decomp_shield_gfx() property   { return 0x00D308; }
  uint32 get_fn_sword_palette() property       { return 0x1BED03; }
  uint32 get_fn_shield_palette() property      { return 0x1BED29; }
  uint32 get_fn_armor_glove_palette() property { return 0x1BEDF9; }
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

  uint32 get_fn_decomp_sword_gfx() property    { return 0x00D2C8; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_decomp_shield_gfx() property   { return 0x00D308; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_sword_palette() property       { return 0x1BED03; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_shield_palette() property      { return 0x1BED29; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_armor_glove_palette() property { return 0x1BEDF9; }  // TODO: unconfirmed! copied from USROMMapping
};

class JPROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC739; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD739; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB39; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC39; }

  // entrance & exit tables:
  uint32 get_entrance_table_room()    property { return 0x02C577; } // 0x14577 in ROM file
  uint32 get_exit_table_room()        property { return 0x02DAEE; }
  uint32 get_exit_table_link_y()      property { return 0x02DDB5; }
  uint32 get_exit_table_link_x()      property { return 0x02DE53; }

  uint32 get_fn_pre_main_loop() property               { return 0x008053; }
  uint32 get_fn_patch() property                       { return 0x008056; }
  //uint32 get_fn_main_routing() property                { return 0x0080B5; }

  uint32 get_fn_dungeon_light_torch() property         { return 0x01F3EA; }
  uint32 get_fn_dungeon_light_torch_success() property { return 0x01F48B; }
  uint32 get_fn_dungeon_extinguish_torch() property    { return 0x01F4A4; }
  uint32 get_fn_sprite_init() property                 { return 0x0DB818; }

  uint32 get_fn_decomp_sword_gfx() property    { return 0x00D308; }
  uint32 get_fn_decomp_shield_gfx() property   { return 0x00D348; }
  uint32 get_fn_sword_palette() property       { return 0x1BED03; }
  uint32 get_fn_shield_palette() property      { return 0x1BED29; }
  uint32 get_fn_armor_glove_palette() property { return 0x1BEDF9; }
};

class RandomizerMapping : JPROMMapping {
  RandomizerMapping() {
    for (int i = syncables.length() - 1; i >= 0; i--) {
      auto @syncable = syncables[i];
      if (syncable is null) continue;

      // bow
      if (syncable.offs == 0x340) {
        @syncables[i] = SyncableItem(0x340, 1, @mutateZeroToNonZero);
        continue;
      }

      // boomerang
      if (syncable.offs == 0x341) {
        @syncables[i] = SyncableItem(0x341, 1, @mutateZeroToNonZero);
        continue;
      }

      // remove mushroom syncable:
      if (syncable.offs == 0x344) {
        syncables.removeAt(i);
        continue;
      }

      // replace flute syncable with less strict behavior:
      if (syncable.offs == 0x34C) {
        @syncables[i] = SyncableItem(0x34C, 1, @mutateFlute);
        continue;
      }

      // Need to insert in offs order, so find the place to insert before:
      if (syncable.offs == 0x3C5) {
        // INVENTORY_SWAP = "$7EF38C"
        // Item Tracking Slot
        // brmpnskf
        // b = blue boomerang
        // r = red boomerang
        // m = mushroom current
        // p = magic powder
        // n = mushroom past
        // s = shovel
        // k = fake flute
        // f = working flute
        syncables.insertAt(i, SyncableItem(0x38C, 1, @mutateRandomizerItems));

        // INVENTORY_SWAP_2 = "$7EF38E"
        // Item Tracking Slot #2
        // bsp-----
        // b = bow
        // s = silver arrow bow
        // p = 2nd progressive bow
        // -
        // -
        // -
        // -
        // -
        syncables.insertAt(i, SyncableItem(0x38E, 1, 2));
      }
    }

    // append extra syncables for randomizer:
    syncables.insertAt(syncables.length(), {
      @SyncableItem(0x410, 1, 2),   // NPC Flags 1
      @SyncableItem(0x411, 1, 2),   // NPC Flags 2
      @SyncableItem(0x418, 1, 1),   // Current Triforce Count
      @SyncableItem(0x434, 1, 1),   // hhhhdddd - item locations checked h - HC d - PoD
      @SyncableItem(0x435, 1, 1),   // dddhhhaa - item locations checked d - DP h - ToH a - AT
      @SyncableItem(0x436, 1, 1),   // gggggeee - item locations checked g - GT e - EP
      @SyncableItem(0x437, 1, 1),   // sssstttt - item locations checked s - SW t - TT
      @SyncableItem(0x438, 1, 1),   // iiiimmmm - item locations checked i - IP m - MM
      @SyncableItem(0x439, 1, 1)    // ttttssss - item locations checked t - TR s - SP
    });

    // sync !SHOP_PURCHASE_COUNTS for VT randomizer shops, e.g. bomb and arrow upgrades in happiness pond:
    for (int i = 0x3C; i >= 0; i--) {
      syncables.insertAt(0, @SyncableItem(0x302 + i, 1, 1));
    }
  }
};

ROMMapping@ detect() {
  array<uint8> sig(21);
  bus::read_block_u8(0x00FFC0, 0, 21, sig);
  auto title = sig.toString(0, 21);
  message("ROM title: \"" + title + "\"");
  if (title == "THE LEGEND OF ZELDA  ") {
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
  } else if (title == "ZELDANODENSETSU      ") {
    message("Recognized JP ROM version.");
    return JPROMMapping();
  } else if (sig.toString(0, 3) == "VT ") {
    // ALTTPR VT randomizer.
    message("Recognized ALTTPR VT randomized JP ROM version. Seed: " + sig.toString(3, 10));
    return RandomizerMapping();
  } else if (sig.toString(0, 6) == "ER002_") {
    // ALTTPR VT-based Entrance Randomizer.
    // e.g. "ER002_1_1_164246190  "
    // "002" represents the __version__ string with '.'s removed.
    // see https://github.com/aerinon/ALttPDoorRandomizer/blob/DoorDev/Main.py#L27
    // and https://github.com/aerinon/ALttPDoorRandomizer/blob/DoorDev/Rom.py#L1316
    message("Recognized ALTTPR VT-based Entrance Randomized JP ROM version. Seed: " + sig.toString(6, 13));
    return RandomizerMapping();
  } else {
    message("Unrecognized ALTTP ROM version! Assuming JP ROM version.");
    return JPROMMapping();
  }
}
