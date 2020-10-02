ROMMapping @rom = null;

funcdef void SerializeSRAMDelegate(array<uint8> &r, uint16 start, uint16 endExclusive);

// Lookup table of ROM addresses depending on version:
abstract class ROMMapping {
  protected string _title;
  string get_title() property {
    return _title;
  }

  void check_game() {}
  bool is_alttp() { return true; }
  bool is_smz3()  { return false;}
  void register_pc_intercepts() {
    // intercept at PC=`JSR ClearOamBuffer; JSL MainRouting`:
    cpu::register_pc_interceptor(rom.fn_pre_main_loop, @on_main_alttp);
  }

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

  uint32 get_fn_overworld_finish_mirror_warp() property { return 0; }
  uint32 get_fn_sprite_load_gfx_properties() property { return 0; }

  // MUST be sorted by offs ascending:
  array<SyncableItem@> @syncables = {
    @SyncableItem(0x340, 1, 1, @nameForBow),         // bow
    @SyncableItem(0x341, 1, 1, @nameForBoomerang),   // boomerang
    @SyncableItem(0x342, 1, 1, @nameForHookshot),    // hookshot
    //SyncableItem(0x343, 1, 3),  // bombs (TODO)
    @SyncableItem(0x344, 1, 1, @nameForMushroom),    // mushroom
    @SyncableItem(0x345, 1, 1, @nameForFirerod),     // fire rod
    @SyncableItem(0x346, 1, 1, @nameForIcerod),      // ice rod
    @SyncableItem(0x347, 1, 1, @nameForBombos),      // bombos
    @SyncableItem(0x348, 1, 1, @nameForEther),       // ether
    @SyncableItem(0x349, 1, 1, @nameForQuake),       // quake
    @SyncableItem(0x34A, 1, 1, @nameForLamp),        // lamp/lantern
    @SyncableItem(0x34B, 1, 1, @nameForHammer),      // hammer
    @SyncableItem(0x34C, 1, 1, @nameForFlute),       // flute
    @SyncableItem(0x34D, 1, 1, @nameForBugnet),      // bug net
    @SyncableItem(0x34E, 1, 1, @nameForBook),        // book
    //SyncableItem(0x34F, 1, 1),  // current bottle selection (1-4); do not sync as it locks the bottle selector in place
    @SyncableItem(0x350, 1, 1, @nameForCanesomaria), // cane of somaria
    @SyncableItem(0x351, 1, 1, @nameForCanebyrna),   // cane of byrna
    @SyncableItem(0x352, 1, 1, @nameForMagiccape),   // magic cape
    @SyncableItem(0x353, 1, 1, @nameForMagicmirror), // magic mirror
    @SyncableItem(0x354, 1, @mutateArmorGloves, @nameForGloves),  // gloves
    @SyncableItem(0x355, 1, 1, @nameForBoots),       // boots
    @SyncableItem(0x356, 1, 1, @nameForFlippers),    // flippers
    @SyncableItem(0x357, 1, 1, @nameForMoonpearl),   // moon pearl
    // 0x358 unused
    @SyncableItem(0x359, 1, @mutateSword, @nameForSword),   // sword
    @SyncableItem(0x35A, 1, @mutateShield, @nameForShield),  // shield
    @SyncableItem(0x35B, 1, @mutateArmorGloves, @nameForArmor),   // armor

    // bottle contents 0x35C-0x35F
    @SyncableItem(0x35C, 1, @mutateBottleItem, @nameForBottle),
    @SyncableItem(0x35D, 1, @mutateBottleItem, @nameForBottle),
    @SyncableItem(0x35E, 1, @mutateBottleItem, @nameForBottle),
    @SyncableItem(0x35F, 1, @mutateBottleItem, @nameForBottle),

    @SyncableItem(0x364, 1, 2, @nameForCompass1),  // dungeon compasses 1/2
    @SyncableItem(0x365, 1, 2, @nameForCompass2),  // dungeon compasses 2/2
    @SyncableItem(0x366, 1, 2, @nameForBigkey1),   // dungeon big keys 1/2
    @SyncableItem(0x367, 1, 2, @nameForBigkey2),   // dungeon big keys 2/2
    @SyncableItem(0x368, 1, 2, @nameForMap1),      // dungeon maps 1/2
    @SyncableItem(0x369, 1, 2, @nameForMap2),      // dungeon maps 2/2

    @SyncableHealthCapacity(),  // heart pieces (out of four) [0x36B], health capacity [0x36C]

    @SyncableItem(0x370, 1, 1),  // bombs capacity
    @SyncableItem(0x371, 1, 1),  // arrows capacity

    @SyncableItem(0x374, 1, 2, @nameForPendants),  // pendants
    //SyncableItem(0x377, 1, 1),  // arrows
    @SyncableItem(0x379, 1, 2),  // player ability flags
    @SyncableItem(0x37A, 1, 2, @nameForCrystals),  // crystals

    @SyncableItem(0x37B, 1, 1, @nameForMagic),  // magic usage

    @SyncableItem(0x3C5, 1, @mutateWorldState, @nameForWorldState),  // general progress indicator
    @SyncableItem(0x3C6, 1, @mutateProgress1, @nameForProgress1),  // progress event flags 1/2
    @SyncableItem(0x3C7, 1, 1),  // map icons shown

    //@SyncableItem(0x3C8, 1, 1),  // start at location… options; DISABLED - causes bugs

    // progress event flags 2/2
    @SyncableItem(0x3C9, 1, @mutateProgress2, @nameForProgress2),

    // sentinel null value as last item in array to work around bug where last array item is always nulled out.
    null

  };

  void serialize_sram_ranges(array<uint8> &r, SerializeSRAMDelegate @serialize) {
    serialize(r, 0x340, 0x37C); // items earned
    serialize(r, 0x3C5, 0x3CA); // progress made
  }

  uint32 get_table_hitbox_pose_x_addr() property { return 0x06F46D; }                         // 0x06F46D
  uint32 get_table_hitbox_pose_w_addr() property { return table_hitbox_pose_x_addr + 0x41; }  // 0x06F4AE
  uint32 get_table_hitbox_pose_y_addr() property { return table_hitbox_pose_x_addr + 0x82; }  // 0x06F4EF
  uint32 get_table_hitbox_pose_h_addr() property { return table_hitbox_pose_x_addr + 0xC3; }  // 0x06F530

  uint16 action_hitbox_x;       // $00,$08
  uint16 action_hitbox_y;       // $01,$09
  uint8  action_hitbox_w;       // $02
  uint8  action_hitbox_h;       // $03
  bool   action_hitbox_active;

  void calc_action_hitbox_special_pose(uint8 x) {
    //dbgData("calc_action_hitbox_special_pose(x={0})".format({x}));

    int8 y;

    // LDY.b #$00

    // LDA $45 : ADD $F46D, X : BPL .positive
    int a = int8(bus::read_u8(0x7E0045)) + int8(bus::read_u8(table_hitbox_pose_x_addr + x));
    //dbgData("     a = {0}".format({fmtInt(a)}));
    // DEY
    //       ADD $22 : STA $00
    // TYA : ADC $23 : STA $08
    action_hitbox_x  = uint16(bus::read_u16(0x7E0022) + a);

    // LDY.b #$00

    // LDA $44 : ADD $F4EF, X : BPL .positive_2
    uint8 m44 = bus::read_u8(0x7E0044);
    a = int8(m44) + int8(bus::read_u8(table_hitbox_pose_y_addr + x));
    //dbgData("     a = {0}".format({fmtInt(a)}));
    // DEY
    //       ADC $20 : STA $01
    // TYA : ADC $21 : STA $09
    action_hitbox_y  = uint16(bus::read_u16(0x7E0020) + a);

    // LDA $F4AE, X : STA $02
    // LDA $F530, X : STA $03
    action_hitbox_w = bus::read_u8(table_hitbox_pose_w_addr + x);
    action_hitbox_h = bus::read_u8(table_hitbox_pose_h_addr + x);
    action_hitbox_active = (m44 != 0x80);

    //dbgData("  hb = ({0},{1},{2},{3})".format({
    //  fmtHex(action_hitbox_x,4),
    //  fmtHex(action_hitbox_y,4),
    //  fmtHex(action_hitbox_w,2),
    //  fmtHex(action_hitbox_h,2)
    //}));
  }

  uint32 get_table_hitbox_dash_y_hi() property { return 0x06F586; }                       // 0x06F586
  uint32 get_table_hitbox_dash_x_lo() property { return table_hitbox_dash_y_hi + 0x02; }  // 0x06F588
  uint32 get_table_hitbox_dash_x_hi() property { return table_hitbox_dash_y_hi + 0x06; }  // 0x06F58C
  uint32 get_table_hitbox_dash_y_lo() property { return table_hitbox_dash_y_hi + 0x0A; }  // 0x06F590

  uint32 get_table_hitbox_sword_toggle() property { return 0x06F571; } // 0x06F571

  void calc_action_hitbox() {
    if (bus::read_u8(0x7E0372) != 0) {
      // dash hit box:

      // LDA $2F : LSR A : TAY
      uint8 y = bus::read_u8(0x7E002F) >> 1;

      // LDA $22 : ADD $F588, Y : STA $00
      // LDA $23 : ADC $F58C, Y : STA $08
      int offs = int(uint16(bus::read_u8(table_hitbox_dash_x_lo + y)) | (uint16(bus::read_u8(table_hitbox_dash_x_hi + y)) << 8));
      action_hitbox_x  = uint16(bus::read_u16(0x7E0022) + offs);

      // LDA $20 : ADD $F590, Y : STA $01
      // LDA $21 : ADC $F586, Y : STA $09
      offs = int(uint16(bus::read_u8(table_hitbox_dash_y_lo + y)) | (uint16(bus::read_u8(table_hitbox_dash_y_hi + y)) << 8));
      action_hitbox_y  = uint16(bus::read_u16(0x7E0020) + offs);

      // LDA.b #$10 : STA $02 : STA $03
      action_hitbox_w = 0x10;
      action_hitbox_h = 0x10;

      // determine if hitbox is active:
      uint8 m44 = bus::read_u8(0x7E0044);
      action_hitbox_active = (m44 != 0x80);

      //dbgData("  hb = ({0},{1},{2},{3})".format({
      //  fmtHex(action_hitbox_x,4),
      //  fmtHex(action_hitbox_y,4),
      //  fmtHex(action_hitbox_w,2),
      //  fmtHex(action_hitbox_h,2)
      //}));

      return;
    }

    // LDX.b #$00
    uint8 x = 0;

    // LDA $0301 : AND.b #$0A : BNE .special_pose
    if ((bus::read_u8(0x7E0301) & 0x0A) != 0) {
      calc_action_hitbox_special_pose(0);
      return;
    }

    // LDA $037A : AND.b #$10 : BNE .special_pose
    if ((bus::read_u8(0x7E037A) & 0x10) != 0) {
      calc_action_hitbox_special_pose(0);
      return;
    }

    // LDY $3C : BMI .spin_attack_hit_box
    uint8 m3c = bus::read_u8(0x7E003C);
    if (int8(m3c) < 0) {
      // spin attack hit box:

      //LDA $22 : SUB.b #$0E : STA $00
      //LDA $23 : SBC.b #$00 : STA $08
      action_hitbox_x  = (bus::read_u16(0x7E0022) - 0x0E);

      //LDA $20 : SUB.b #$0A : STA $01
      //LDA $21 : SBC.b #$00 : STA $09
      action_hitbox_y  = (bus::read_u16(0x7E0020) - 0x0A);

      //LDA.b #$2C : STA $02
      //INC A      : STA $03
      action_hitbox_w = 0x2C;
      action_hitbox_h = 0x2D;
      action_hitbox_active = true;

      //dbgData("  hb = ({0},{1},{2},{3})".format({
      //  fmtHex(action_hitbox_x,4),
      //  fmtHex(action_hitbox_y,4),
      //  fmtHex(action_hitbox_w,2),
      //  fmtHex(action_hitbox_h,2)
      //}));

      return;
    }

    // LDA $F571, Y : BNE .return
    if (bus::read_u8(table_hitbox_sword_toggle + m3c) != 0) {
      // LDA.b #$80 : STA $08
      action_hitbox_x = 0x8000;
      action_hitbox_active = false;

      return;
    }

    // ; Adding $3C seems to be for the pokey player hit box with the swordy.
    // LDA $2F : ASL #3 : ADD $3C : TAX : INX
    x = (bus::read_u8(0x7E002F) << 3) + m3c + 1;
    calc_action_hitbox_special_pose(x);
    return;
  }

  // address of the ancilla hitbox tables: (x, w, y, h) * 12 items each
  uint32 get_table_hitbox_ancilla() const property { return 0x088E7D; }

  // fetch the hitbox values:
   int8 get_hitbox_ancilla_x(int n) const property { return  int8(bus::read_u8(table_hitbox_ancilla + 12*0 + n)); }    // 0x088E7D
  uint8 get_hitbox_ancilla_w(int n) const property { return uint8(bus::read_u8(table_hitbox_ancilla + 12*1 + n)); }    // 0x088E89
   int8 get_hitbox_ancilla_y(int n) const property { return  int8(bus::read_u8(table_hitbox_ancilla + 12*2 + n)); }    // 0x088E95
  uint8 get_hitbox_ancilla_h(int n) const property { return uint8(bus::read_u8(table_hitbox_ancilla + 12*3 + n)); }    // 0x088EA1
};

class USAROMMapping : ROMMapping {
  USAROMMapping() {
    _title = "USA v1." + fmtInt(bus::read_u8(0x00FFDB));
  }

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

  uint32 get_fn_overworld_finish_mirror_warp() property { return 0x02B260; }  // $13260
  uint32 get_fn_sprite_load_gfx_properties() property { return 0x00FC62; }  // $7C62 (lightWorld)
};

class EURROMMapping : ROMMapping {
  EURROMMapping() {
    _title = "EUR v1." + fmtInt(bus::read_u8(0x00FFDB));
  }

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

  uint32 get_fn_dungeon_light_torch() property         { return 0x01F3C6; } // TODO: unconfirmed! copied from GER_EURROMMapping
  uint32 get_fn_dungeon_light_torch_success() property { return 0x01F3E3; } // TODO: unconfirmed! copied from GER_EURROMMapping
  uint32 get_fn_dungeon_extinguish_torch() property    { return 0x01F480; } // TODO: unconfirmed! copied from GER_EURROMMapping
  uint32 get_fn_sprite_init() property                 { return 0x0DB818; } // TODO: unconfirmed! copied from USROMMapping

  uint32 get_fn_decomp_sword_gfx() property    { return 0x00D2C8; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_decomp_shield_gfx() property   { return 0x00D308; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_sword_palette() property       { return 0x1BED03; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_shield_palette() property      { return 0x1BED29; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_armor_glove_palette() property { return 0x1BEDF9; }  // TODO: unconfirmed! copied from USROMMapping
};

class GER_EURROMMapping : ROMMapping {
  GER_EURROMMapping() {
    _title = "GER-EUR v1." + fmtInt(bus::read_u8(0x00FFDB));
  }

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

  uint32 get_fn_dungeon_light_torch() property         { return 0x01F3C6; }
  uint32 get_fn_dungeon_light_torch_success() property { return 0x01F3E3; }
  uint32 get_fn_dungeon_extinguish_torch() property    { return 0x01F480; }
  uint32 get_fn_sprite_init() property                 { return 0x0DB818; } // TODO: unconfirmed! copied from USROMMapping

  uint32 get_fn_decomp_sword_gfx() property    { return 0x00D2C8; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_decomp_shield_gfx() property   { return 0x00D308; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_sword_palette() property       { return 0x1BED03; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_shield_palette() property      { return 0x1BED29; }  // TODO: unconfirmed! copied from USROMMapping
  uint32 get_fn_armor_glove_palette() property { return 0x1BEDF9; }  // TODO: unconfirmed! copied from USROMMapping
};

class JPROMMapping : ROMMapping {
  JPROMMapping() {
    _title = "JP v1." + fmtInt(bus::read_u8(0x00FFDB));
  }

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

  uint32 get_fn_overworld_finish_mirror_warp() property { return 0x02B186; }  // $13186
  uint32 get_fn_sprite_load_gfx_properties() property { return 0x00FC62; }  // $7C62 (lightWorld)

  uint32 get_table_hitbox_pose_x_addr()  property { return 0x06F473; }
  uint32 get_table_hitbox_sword_toggle() property { return 0x06F577; }
  uint32 get_table_hitbox_dash_y_hi()    property { return 0x06F58C; }

};

class RandomizerMapping : JPROMMapping {
  protected string _seed;
  protected string _kind;

  RandomizerMapping(const string &in kind, const string &in seed) {
    _seed = seed;
    _kind = kind;
    _title = kind + " seed " + _seed;
    syncAll();
  }

  void syncAll() {
    syncItems();
    syncShops();
    syncFlags();
    syncStats();
    syncChestCounters();
  }

  void syncItems() {
    for (int i = syncables.length() - 1; i >= 0; i--) {
      auto @syncable = syncables[i];
      if (syncable is null) continue;

      // bow
      if (syncable.offs == 0x340) {
        @syncables[i] = SyncableItem(0x340, 1, @mutateZeroToNonZero); // no name here; INVENTORY_SWAP takes care of that
        continue;
      }

      // boomerang
      if (syncable.offs == 0x341) {
        @syncables[i] = SyncableItem(0x341, 1, @mutateZeroToNonZero); // no name here; INVENTORY_SWAP takes care of that
        continue;
      }

      // remove mushroom syncable:
      if (syncable.offs == 0x344) {
        syncables.removeAt(i);
        continue;
      }

      // replace flute syncable with less strict behavior:
      if (syncable.offs == 0x34C) {
        @syncables[i] = SyncableItem(0x34C, 1, @mutateFlute); // no name here; INVENTORY_SWAP takes care of that
        continue;
      }

      // Need to insert in offs order, so find the place to insert before:
      if (syncable.offs == 0x3C5) {
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
        syncables.insertAt(i, @SyncableItem(0x38E, 1, 2, @nameForRandomizerItems2));

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
        syncables.insertAt(i, @SyncableItem(0x38C, 1, @mutateRandomizerItems, @nameForRandomizerItems1));
      }
    }

    // track progressive shield:
    syncables.insertLast(@SyncableItem(0x416, 1, @mutateProgressiveShield));
  }

  void syncShops() {
    // sync !SHOP_PURCHASE_COUNTS for VT randomizer shops, e.g. bomb and arrow upgrades in happiness pond:
    for (int i = 0x3D; i >= 0; i--) {
      syncables.insertAt(0, @SyncableItem(0x302 + i, 1, 1));
    }
  }

  void syncFlags() {
    syncables.insertLast(@SyncableItem(0x410, 1, 2)); // NPC Flags 1
    syncables.insertLast(@SyncableItem(0x411, 1, 2)); // NPC Flags 2
  }

  void syncStats() {
    // item limit counters:
    for (uint i = 0x390; i < 0x3C5; i++) {
      syncables.insertLast(@SyncableItem(i, 1, 1));
    }

    syncables.insertLast(@SyncableItem(0x418, 1, 1, @nameForTriforcePieces)); // Current Triforce Count
  }

  void syncChestCounters() {
    syncables.insertLast(@SyncableItem(0x434, 1, 1));                         // hhhhdddd - item locations checked h - HC d - PoD
    syncables.insertLast(@SyncableItem(0x435, 1, 1));                         // dddhhhaa - item locations checked d - DP h - ToH a - AT
    syncables.insertLast(@SyncableItem(0x436, 1, 1));                         // gggggeee - item locations checked g - GT e - EP
    syncables.insertLast(@SyncableItem(0x437, 1, 1));                         // sssstttt - item locations checked s - SW t - TT
    syncables.insertLast(@SyncableItem(0x438, 1, 1));                         // iiiimmmm - item locations checked i - IP m - MM
    syncables.insertLast(@SyncableItem(0x439, 1, 1));                         // ttttssss - item locations checked t - TR s - SP
  }

  void serialize_sram_ranges(array<uint8> &r, SerializeSRAMDelegate @serialize) override {
    serialize(r, 0x340, 0x390); // items earned
    serialize(r, 0x390, 0x3C5); // item limit counters
    serialize(r, 0x3C5, 0x43A); // progress made
  }
};

class MultiworldMapping : RandomizerMapping {
  MultiworldMapping(const string &in kind, const string &in seed) {
    super(kind, seed);
  }
};

class DoorRandomizerMapping : RandomizerMapping {
  DoorRandomizerMapping(const string &in kind, const string &in seed) {
    super(kind, seed);
  }

  void syncAll() override {
    syncItems();
    syncShops();
    syncFlags();
    syncStats();
    syncChestCounters();
  }

  void syncChestCounters() override {
    for (uint i = 0; i <= 0xC; i++) {
      syncables.insertLast(@SyncableItem(0x4c0 + i, 1, 1));
    }
    for (uint i = 0; i <= 0xC; i++) {
      syncables.insertLast(@SyncableItem(0x4e0 + i, 1, 1));
    }
  }

  void serialize_sram_ranges(array<uint8> &r, SerializeSRAMDelegate @serialize) override {
    serialize(r, 0x340, 0x390); // items earned
    serialize(r, 0x390, 0x3C5); // item limit counters
    serialize(r, 0x3C5, 0x43A); // progress made
    serialize(r, 0x4C0, 0x4CD); // chests
    serialize(r, 0x4E0, 0x4ED); // chest-keys
  }
};

class SMZ3Mapping : RandomizerMapping {
  SMZ3Mapping(const string &in kind, const string &in seed) {
    super(kind, seed);
    update_syncables();
  }

  void update_syncables() {
    //metroid items
    syncables.insertLast(@SyncableItem(0x02, 1, 2, @nameForMetroidSuits, true));
    syncables.insertLast(@SyncableItem(0x03, 1, 2, @nameForMetroidBoots, true));
    syncables.insertLast(@SyncableItem(0x06, 1, 2, @nameForMetroidBeams, true));
    syncables.insertLast(@SyncableItem(0x07, 1, 1, null, true)); // charge beam
    syncables.insertLast(@SyncableItem(0x26, 1, 1, null, true)); // missile capacity
    syncables.insertLast(@SyncableItem(0x2a, 1, 1, null, true)); // super missile capacity
    syncables.insertLast(@SyncableItem(0x2e, 1, 1, null, true)); // power bomb capacity
    syncables.insertLast(@SyncableItem(0x32, 2, 1, null, true)); // reserve tanks
    syncables.insertLast(@SyncableItem(0x22, 2, 1, null, true)); // energy tanks
  }

  void syncAll() override {
    RandomizerMapping::syncAll();
  }

  uint8 game = 0;
  void check_game() override {
    game = bus::read_u8(0xA173FE);
  }

  bool is_alttp() override { return game == 0; }
  bool is_smz3() override { return true;}

  void register_pc_intercepts() override {
    cpu::register_pc_interceptor(rom.fn_pre_main_loop, @on_main_alttp);

    // SM main is at 0x82893D (PHK; PLB)
    // SM main @loop (PHP; REP #$30) https://github.com/strager/supermetroid/blob/master/src/bank82.asm#L1066
    cpu::register_pc_interceptor(0x828948, @on_main_sm);
  }
}

ROMMapping@ detect() {
  array<uint8> sig(21);
  bus::read_block_u8(0x00FFC0, 0, 21, sig);
  auto region  = bus::read_u8(0x00FFD9);
  auto version = bus::read_u8(0x00FFDB);
  auto title   = sig.toString(0, 21);
  message("ROM title: \"" + title.trimRight("\0") + "\"");
  if (title == "THE LEGEND OF ZELDA  ") {
    if (region == 0x01) {
      message("Recognized USA region ROM version v1." + fmtInt(version));
      return USAROMMapping();
    } else if (region == 0x02) {
      message("Recognized EUR region ROM version v1." + fmtInt(version));
      return EURROMMapping();
    } else if (region == 0x09) {
      message("Recognized GER-EUR region ROM version v1." + fmtInt(version));
      return GER_EURROMMapping();
    } else {
      message("Unrecognized ROM region but has US title; assuming USA ROM v1." + fmtInt(version));
      return USAROMMapping();
    }
  } else if (title == "ZELDANODENSETSU      ") {
    message("Recognized JP ROM version v1." + fmtInt(version));
    return JPROMMapping();
  } else if (title == "LOZ: PARALLEL WORLDS ") {
    message("Recognized Parallel Worlds ROM hack. Most functionality will not work due to the extreme customization of this hack.");
    return USAROMMapping();
  } else if (title.slice(0, 3) == "VT ") {
    // ALTTPR VT randomizer.
    auto seed = title.slice(3, 10);
    message("Recognized ALTTPR VT randomized JP ROM version. Seed: " + seed);
    return RandomizerMapping("VT", seed);
  } else if ( (title.slice(0, 2) == "BM") && (title[5] == '_') ) {
    // Berserker MultiWorld randomizer.
    //  0123456789
    // "BM250_1_1_16070690178"
    // "250" represents the __version__ string with '.'s removed.
    auto seed = title.slice(6, 13);
    auto kind = title.slice(0, 2) + " v" + title.slice(2, 3);
    message("Recognized Berserker MultiWorld " + kind + " randomized JP ROM version. Seed: " + seed);
    return MultiworldMapping(kind, seed);
  } else if ( title.slice(0, 2) == "BD" && (title[5] == '_') ) {
    // Berserker MultiWorld Door Randomizer.
    //  0123456789
    // "BD251_1_1_23654700304"
    // "251" represents the __version__ string with '.'s removed.
    auto seed = title.slice(6, 13);
    auto kind = title.slice(0, 2) + " v" + title.slice(2, 3);
    message("Recognized Berserker MultiWorld Door Randomizer " + kind + " randomized JP ROM version. Seed: " + seed);
    return DoorRandomizerMapping(kind, seed);
  } else if ( (title.slice(0, 2) == "ER") && (title[5] == '_') ) {
    // ALTTPR Entrance or Door Randomizer.
    //  0123456789
    // "ER002_1_1_164246190  "
    // "002" represents the __version__ string with '.'s removed.
    // see https://github.com/aerinon/ALttPDoorRandomizer/blob/DoorDev/Main.py#L27
    // and https://github.com/aerinon/ALttPDoorRandomizer/blob/DoorDev/Rom.py#L1316
    auto seed = title.slice(6, 13);
    string kind;
    bool isDoor = false;
    if (bus::read_u16(0x278000) != 0) {
      // door randomizer
      isDoor = true;
      kind = title.slice(0, 2) + " (door) v" + title.slice(2, 3);
    } else {
      // entrance randomizer
      kind = title.slice(0, 2) + " (entrance) v" + title.slice(2, 3);
    }
    message("Recognized " + kind + " randomized JP ROM version. Seed: " + seed);
    if (isDoor) {
      return DoorRandomizerMapping(kind, seed);
    } else {
      return RandomizerMapping(kind, seed);
    }
  } else if (title.slice(0, 3) == "ZSM") {
    // SMZ3 randomized
    auto seed = fmtInt(title.slice(9, 8).hex());
    auto kind = title.slice(0, 3) + " v" + title.slice(3, 4);
    message("Recognized " + kind + " randomized ROM version. Seed: " + seed);
    return SMZ3Mapping(kind, seed);
  } else {
    switch (region) {
      case 0x00:
        message("Unrecognized ALTTP ROM title but region is JP v1." + fmtInt(version));
        return JPROMMapping();
      case 0x01:
        message("Unrecognized ALTTP ROM title but region is USA v1." + fmtInt(version));
        return USAROMMapping();
      case 0x02:
        message("Unrecognized ALTTP ROM title but region is EUR v1." + fmtInt(version));
        return EURROMMapping();
    }
    message("Unrecognized ALTTP ROM title and region! Assuming JP ROM region; version v1." + fmtInt(version));
    return JPROMMapping();
  }
}
