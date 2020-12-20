
const uint MaxPacketSize = 1452;

const uint OverworldAreaCount = 0x82;

class ALTTPSRAMArray : SRAMArray {
  bool is_buffer;

  ALTTPSRAMArray(array<uint8>@ sram, bool is_buffer = false) {
    super(sram);
    this.is_buffer = is_buffer;
  }

  void write_u8 (uint16 offs, uint8 value) {
    if (is_buffer) {
      write_u8_buffer(offs, value);
      return;
    }
    if (sram[offs] == value) {
      return;
    }

    bus::write_u8(0x7EF000 + offs, value);
    sram[offs] = value;
  }

  void write_u8_buffer (uint16 offs, uint8 value) {
    if (sram[offs] == value) {
      return;
    }
    if (offs < 0x40) {
      bus::write_u8(0xA17900 + offs, value);
    }
    sram[offs] = value;
  }
}

class SMSRAMArray : SRAMArray {
  bool is_buffer;

  SMSRAMArray(array<uint8>@ sram, bool is_buffer = false) {
    super(sram);
    this.is_buffer = is_buffer;
  }

  void write_u8 (uint16 offs, uint8 value) override {
    if (is_buffer) {
      write_u8_buffer(offs, value);
      return;
    }
    if (sram[offs] == value) {
      return;
    }

    bus::write_u8(0x7E09A2 + offs, value);
    sram[offs] = value;
  }

  void write_u8_buffer (uint16 offs, uint8 value) {
    if (sram[offs] == value) {
      return;
    }

    if (offs >= 0x300 && offs < 0x400) {
      bus::write_u8(0xA17B00 + offs - 0x300, value);
    }
    sram[offs] = value;
  }
}

class LocalGameState : GameState {
  array<SyncableItem@> areas(0x80);
  array<SyncableItem@> rooms(0x128);
  array<Sprite@> sprs(0x80);

  Notify@ notify;
  NotifyItemReceived@ itemReceivedDelegate;
  SerializeSRAMDelegate@ serializeSramDelegate;

  SyncableByte@ small_keys_current;

  uint8 state;
  uint32 last_sent = 0;

  uint8 gotShield;

  AncillaTables ancillaTables;
  array<Projectile> projectiles;

  LocalGameState() {
    @this.notify = Notify(@notificationSystem.notify);
    @this.itemReceivedDelegate = NotifyItemReceived(@this.collectNotifications);
    @this.serializeSramDelegate = SerializeSRAMDelegate(@this.serialize_sram);

    // SRAM [$000..$24f] underworld rooms:
    // create syncable item for each underworld room (word; size=2) using bitwise OR operations (type=2) to accumulate latest state:
    rooms.resize(0x128);
    for (uint a = 0; a < 0x128; a++) {
      @rooms[a] = @SyncableItem(a << 1, 2, 2);
    }

    // desync swamp inner watergate at $7EF06A (supertile $35)
    @rooms[0x035] = @SyncableItem(0x10B << 1, 2, function(SRAM@ sram, uint16 oldValue, uint16 newValue) {
      return oldValue | (newValue & 0xFF7F);
    });

    // SRAM [$250..$27f] unused

    // SRAM [$280..$301] overworld areas:
    // create syncable item for each overworld area (byte; size=1) using bitwise OR operations (type=2) to accumulate latest state:
    areas.resize(OverworldAreaCount);
    for (uint a = 0; a < OverworldAreaCount; a++) {
      @areas[a] = @SyncableItem(0x280 + a, 1, 2);
    }

    // org $30803D ; PC 0x18003D
    // PersistentFloodgate:
    // db #$00 ; #$00 = Off (default) - #$01 = On
    if (bus::read_u8(0x30803D) == 0x00) {
      // desync the indoor flags for the swamp palace and the watergate:
      // LDA $7EF216 : AND.b #$7F : STA $7EF216
      // LDA $7EF051 : AND.b #$FE : STA $7EF051
      @rooms[0x10B] = @SyncableItem(0x10B << 1, 2, function(SRAM@ sram, uint16 oldValue, uint16 newValue) {
        return oldValue | (newValue & 0xFF7F);
      });
      @rooms[0x028] = @SyncableItem(0x028 << 1, 2, function(SRAM@ sram, uint16 oldValue, uint16 newValue) {
        return oldValue | (newValue & 0xFEFF);
      });

      // desync the overlay flags for the swamp palace and its light world counterpart:
      // LDA $7EF2BB : AND.b #$DF : STA $7EF2BB
      // LDA $7EF2FB : AND.b #$DF : STA $7EF2FB
      @areas[0x3B] = @SyncableItem(0x280 + 0x3B, 1, function(SRAM@ sram, uint16 oldValue, uint16 newValue) {
        return oldValue | (newValue & 0xDF);
      });
      @areas[0x7B] = @SyncableItem(0x280 + 0x7B, 1, function(SRAM@ sram, uint16 oldValue, uint16 newValue) {
        return oldValue | (newValue & 0xDF);
      });
    }

    // Pyramid bat crash: ([$7EF2DB] | 0x20)
    @areas[0x5B] = @SyncableItem(0x280 + 0x5B, 1, function(SRAM@ sram, uint16 oldValue, uint16 newValue) {
      // pyramid hole has just opened:
      if ( ((oldValue & 0x20) == 0) && ((newValue & 0x20) == 0x20) ) {
        // local player is on pyramid:
        if (local.overworld_room == 0x5B) {
          // JSL to Overworld_CreatePyramidHole to draw the pyramid hole on screen:
          pb.jsl(rom.fn_overworld_createpyramidhole);
          local.notify("Pyramid opened");
        }
      }

      return oldValue | newValue;
    });

    for (uint i = 0; i < 0x80; i++) {
      @sprs[i] = Sprite();
    }

    // small key sync:
    @small_keys_current = @SyncableByte(0xF36F);
    for (uint i = 0; i < 0x10; i++) {
      @small_keys[i] = @SyncableByte(small_keys_min_offs + i);
    }
  }

  void reset() override {
    GameState::reset();

    small_keys_current.reset();
    last_sent = 0;
    
    gotShield = 0;
  }

  bool registered = false;
  void register(bool force = false) {
    if (force) {
      registered = false;
    }
    if (registered) return;
    if (rom is null) return;

    if (enableObjectSync) {
      cpu::register_pc_interceptor(rom.fn_sprite_init, cpu::PCInterceptCallback(this.on_object_init));
    }

    //message("tilemap intercept register");
    bus::add_write_interceptor("7e:2000-5fff", bus::WriteInterceptCallback(this.tilemap_written));
    bus::add_write_interceptor("7f:2000-3fff", bus::WriteInterceptCallback(this.attributes_written));

    crystal.register(SyncableByteShouldCapture(this.crystal_switch_capture));

    // small key sync:
    small_keys_current.reset();
    small_keys_current.register(SyncableByteShouldCapture(this.small_keys_current_capture));
    for (uint i = 0; i < 0x10; i++) {
      small_keys[i].reset();
      small_keys[i].register(SyncableByteShouldCapture(this.small_key_capture));
    }

    if (debugSRAM) {
      bus::add_write_interceptor("7e:f000-f4fd", bus::WriteInterceptCallback(this.sram_written));
    }

    registered = true;
  }

  void sram_written(uint32 addr, uint8 oldValue, uint8 newValue) {
    if (newValue == oldValue) {
      return;
    }

    dbgData("SRAM: " + fmtHex(addr - 0x7EF000, 3) + "; " + fmtHex(oldValue, 2) + " -> " + fmtHex(newValue, 2) + "; module=" + fmtHex(module, 2) + "," + fmtHex(sub_module, 2));
  }

  bool small_key_capture(uint32 addr, uint8 oldValue, uint8 newValue) {
    bool allow = true;
    if (module <= 0x06) allow = false;
    else if (module == 0x17) allow = false;

    if (debugData) {
      dbgData("keys[" + fmtHex(addr - small_keys_min_offs, 2) + "]: " +
        (allow ? "Y " : "N ") +
        fmtHex(oldValue, 2) + " -> " + fmtHex(newValue, 2) + "; module=" +
        fmtHex(module, 2) + "," + fmtHex(sub_module, 2)
      );
    }

    return allow;
  }

  bool small_keys_current_capture(uint32 addr, uint8 oldValue, uint8 newValue) {
    bool allow = true;
    if (module != 0x07) {
      allow = false;
    }

    // which dungeon are we in:
    auto dung = bus::read_u8(0x7E040C);
    uint i = 0xFF;
    if (dung == 0xFF) {
      allow = false;
    } else if (dung >= 0x20) {
      allow = false;
    } else {
      i = dung >> 1;
    }

    if (debugData) {
      dbgData("keys_current: " +
        (allow ? "Y " : "N ") +
        fmtHex(oldValue, 2) + " -> " + fmtHex(newValue, 2) +
        "; dungeon=" + fmtHex(i,2) + "; module=" + fmtHex(module, 2) + "," + fmtHex(sub_module, 2)
      );
    }

    if (!allow) {
      return false;
    }

    small_keys[i].capture(newValue);

    return true;
  }

  bool crystal_switch_capture(uint32 addr, uint8 oldValue, uint8 newValue) {
    // hitting crystal switch in dungeon:
    if (module == 0x07) {
      //if (debugData) {
      //  dbgData("crystal: " + fmtHex(oldValue, 2) + " -> " + fmtHex(newValue, 2) + "; module=" + fmtHex(module, 2) + "," + fmtHex(sub_module, 2));
      //}
      return true;
    }

    // pre-dungeon, so we need to forget our last state:
    if (module == 0x06) {
      crystal.resetTo(newValue);
      return false;
    }
    // load-dungeon when mirroring, so we need to forget our last state:
    if (module == 0x05) {
      crystal.resetTo(newValue);
      return false;
    }

    return false;
  }

  bool can_sample_location() const {
    switch (module) {
      // dungeon:
      case 0x07:
        // climbing/descending stairs
        if (sub_module == 0x0e) {
          // once main climb animation finishes, sample new location:
          if (sub_sub_module > 0x02) {
            return true;
          }
          // continue sampling old location:
          return false;
        }
        return true;
      case 0x09:  // overworld
        // disallow sampling during screen transition:
        if (sub_module >= 0x01 && sub_module <= 0x08) return false;
        // normal mirror is 0x23
        // mirror fail back to dark world is 0x2c
        if (sub_module == 0x23 || sub_module == 0x2c) {
          // once sub-sub module hits 3 then we are in light world
          if (sub_sub_module < 0x03) {
            return false;
          }
        }
        return true;
      case 0x0e:  // dialogs, maps etc.
        if (sub_module == 0x07) {
          // in-game mode7 map:
          return false;
        }
        return true;
      case 0x05:  // entering dungeon
      case 0x06:  // enter cave from overworld?
      case 0x0b:  // overworld master sword grove / zora waterfall
      case 0x08:  // exit cave to overworld
      case 0x0f:  // closing spotlight
      case 0x10:  // opening spotlight
      case 0x11:  // falling / fade out?
      case 0x12:  // death
      default:
        return true;
    }
    return true;
  }

  void fetch_module() {
    // 0x00 - Triforce / Zelda startup screens
    // 0x01 - File Select screen
    // 0x02 - Copy Player Mode
    // 0x03 - Erase Player Mode
    // 0x04 - Name Player Mode
    // 0x05 - Loading Game Mode
    // 0x06 - Pre Dungeon Mode
    // 0x07 - Dungeon Mode
    // 0x08 - Pre Overworld Mode
    // 0x09 - Overworld Mode
    // 0x0A - Pre Overworld Mode (special overworld)
    // 0x0B - Overworld Mode (special overworld)
    // 0x0C - ???? I think we can declare this one unused, almost with complete certainty.
    // 0x0D - Blank Screen
    // 0x0E - Text Mode/Item Screen/Map
    // 0x0F - Closing Spotlight
    // 0x10 - Opening Spotlight
    // 0x11 - Happens when you fall into a hole from the OW.
    // 0x12 - Death Mode
    // 0x13 - Boss Victory Mode (refills stats)
    // 0x14 - Attract Mode
    // 0x15 - Module for Magic Mirror
    // 0x16 - Module for refilling stats after boss.
    // 0x17 - Quitting mode (save and quit)
    // 0x18 - Ganon exits from Agahnim's body. Chase Mode.
    // 0x19 - Triforce Room scene
    // 0x1A - End sequence
    // 0x1B - Screen to select where to start from (House, sanctuary, etc.)
    module = bus::read_u8(0x7E0010);

    // when module = 0x07: dungeon
    //    sub_module = 0x00: Default behavior
    //               = 0x01: Intra-room transition
    //               = 0x02: Inter-room transition
    //               = 0x03: Perform overlay change (e.g. adding holes)
    //               = 0x04: opening key or big key door
    //               = 0x05: initializing room? / locked doors? / Trigger an animation?
    //               = 0x06: Upward floor transition
    //               = 0x07: Downward floor transition
    //               = 0x08: Walking up/down an in-room staircase
    //               = 0x09: Bombing or using dash attack to open a door.
    //               = 0x0A: Think it has to do with Agahnim's room in Ganon's Tower (before Ganon pops out) (or light level in room changing?)
    //               = 0x0B: Turn off water (used in swamp palace)
    //               = 0x0C: Turn on water submodule (used in swamp palace)
    //               = 0x0D: Watergate room filling with water submodule (no other known uses at the moment)
    //               = 0x0E: Going up or down inter-room spiral staircases (floor to floor)
    //               = 0x0F: Entering dungeon first time (or from mirror)
    //               = 0x10: Going up or down in-room staircases (clarify, how is this different from 0x08. Did I mean in-floor staircases?!
    //               = 0x11: ??? adds extra sprites on screen
    //               = 0x12: Walking up straight inter-room staircase
    //               = 0x13: Walking down straight inter-room staircase
    //               = 0x14: What Happens when Link falls into a damaging pit.
    //               = 0x15: Warping to another room.
    //               = 0x16: Orange/blue barrier state change?
    //               = 0x17: Quick little submodule that runs when you step on a switch to open trap doors?
    //               = 0x18: Used in the crystal sequence.
    //               = 0x19: Magic mirror as used in a dungeon. (Only works in palaces, specifically)
    //               = 0x1A:
    // when module = 0x09: overworld
    //    sub_module = 0x00 normal gameplay in overworld
    //               = 0x0e
    //      sub_sub_module = 0x01 in item menu
    //                     = 0x02 in dialog with NPC
    //               = 0x23 transitioning from light world to dark world or vice-versa
    // when module = 0x12: Link is dying
    //    sub_module = 0x00
    //               = 0x02 bonk
    //               = 0x03 black oval closing in
    //               = 0x04 red screen and spinning animation
    //               = 0x05 red screen and Link face down
    //               = 0x06 fade to black
    //               = 0x07 game over animation
    //               = 0x08 game over screen done
    //               = 0x09 save and continue menu
    sub_module = bus::read_u8(0x7E0011);

    // sub-sub-module goes from 01 to 0f during special animations such as link walking up/down stairs and
    // falling from ceiling and used as a counter for orange/blue barrier blocks transition going up/down
    sub_sub_module = bus::read_u8(0x7E00B0);
  }

  bool sprites_need_vram = false;

  void fetch() {
    sprites_need_vram = false;

    fetch_sram();

    // player state:
    // 0x00 - ground state
    // 0x01 - falling into a hole
    // 0x02 - recoil from hitting wall / enemies
    // 0x03 - spin attacking
    // 0x04 - swimming
    // 0x05 - Turtle Rock platforms
    // 0x06 - recoil again (other movement)
    // 0x07 - Being electrocuted
    // 0x08 - using ether medallion
    // 0x09 - using bombos medallion
    // 0x0A - using quake medallion
    // 0x0B - Falling into a hold by jumping off of a ledge.
    // 0x0C - Falling to the left / right off of a ledge.
    // 0x0D - Jumping off of a ledge diagonally up and left / right.
    // 0x0E - Jumping off of a ledge diagonally down and left / right.
    // 0x0F - More jumping off of a ledge but with dashing maybe + some directions.
    // 0x10 - Same or similar to 0x0F?
    // 0x11 - Falling off a ledge
    // 0x12 - Used when coming out of a dash by pressing a direction other than the
    //        dash direction.
    // 0x13 - hookshot
    // 0x14 - magic mirror
    // 0x15 - holding up an item
    // 0x16 - asleep in his bed
    // 0x17 - permabunny
    // 0x18 - stuck under a heavy rock
    // 0x19 - Receiving Ether Medallion
    // 0x1A - Receiving Bombos Medallion
    // 0x1B - Opening Desert Palace
    // 0x1C - temporary bunny
    // 0x1D - Rolling back from Gargoyle gate or PullForRupees object
    // 0x1E - The actual spin attack motion.
    state = bus::read_u8(0x7E005D);

    // fetch various room indices and flags about where exactly Link currently is:
    in_dark_world = bus::read_u8(0x7E0FFF);
    in_dungeon = bus::read_u8(0x7E001B);
    overworld_room = bus::read_u16(0x7E008A);
    dungeon_room = bus::read_u16(0x7E00A0);

    dungeon = bus::read_u16(0x7E040C);
    dungeon_entrance = bus::read_u16(0x7E010E);

    fetch_pvp();

    // compute aggregated location for Link into a single 24-bit number:
    last_actual_location = actual_location;
    actual_location =
      uint32(in_dark_world & 1) << 17 |
      uint32(in_dungeon & 1) << 16 |
      uint32(in_dungeon != 0 ? dungeon_room : overworld_room);

    if (is_in_overworld_module()) {
      last_overworld_x = x;
      last_overworld_y = y;
      //last_overworld_x = bus::read_u16(0x7EC14A);
      //last_overworld_y = bus::read_u16(0x7EC148);
    }

    if (is_it_a_bad_time()) {
      //if (!can_sample_location()) {
      //  x = 0xFFFF;
      //  y = 0xFFFF;
      //}
      return;
    }

    // $7E0410 = OW screen transitioning directional
    //ow_screen_transition = bus::read_u8(0x7E0410);

    // Don't update location until screen transition is complete:
    if (can_sample_location() && !is_in_screen_transition()) {
      last_location = location;
      location = actual_location;

      // clear out list of room changes if location changed:
      if (last_location != location) {
        //message("room from 0x" + fmtHex(last_location, 6) + " to 0x" + fmtHex(location, 6));

        // disown any of our torches:
        for (uint t = 0; t < 0x10; t++) {
          torchOwner[t] = -2;
        }
      }
    }

    x = bus::read_u16(0x7E0022);
    y = bus::read_u16(0x7E0020);

    calc_hitbox();

    // get screen x,y offset by reading BG2 scroll registers:
    xoffs = int16(bus::read_u16(0x7E00E2)) - int16(bus::read_u16(0x7E011A));
    yoffs = int16(bus::read_u16(0x7E00E8)) - int16(bus::read_u16(0x7E011C));

    fetch_sprites();

    fetch_objects();

    fetch_ancillae();

    fetch_tilemap_changes();

    fetch_torches();
    
    if (rom.is_smz3()){
      fetch_sm_events_buffer();
    }
  }

  void fetch_pvp() {
    if (!settings.EnablePvP) {
      return;
    }
    if (rom is null) {
      return;
    }

    // calculate hitbox for melee attack (sword, hammer, bugnet):
    rom.calc_action_hitbox();

    action_hitbox.setActive(rom.action_hitbox_active);
    action_hitbox.setBox(
      rom.action_hitbox_x,
      rom.action_hitbox_y,
      rom.action_hitbox_w,
      rom.action_hitbox_h
    );

    //     $3C = sword out time / spin attack
    action_sword_time = bus::read_u8(0x7E003C);
    // $7EF359 = sword type
    action_sword_type = bus::read_u8(0x7EF359);
    //   $0301 = item in hand (bitfield, one bit at a time)
    action_item_used = bus::read_u8(0x7E0301);
    //     $EE = level in room
    action_room_level = bus::read_u8(0x7E00EE);

    // read projectile data from WRAM and filter out unimportant effect sparkles:
    ancillaTables.read_ram();
    projectiles.reserve(10);
    projectiles.resize(0);
    for (uint8 i = 0; i < ancilla_count; i++) {
      if (!ancillaTables.is_projectile(i)) {
        continue;
      }

      projectiles.insertLast(Projectile(ancillaTables, i));
    }
    //dbgData("projectiles: {0}".format({projectileAncillae.length()}));
  }

  void fetch_sfx() {
    if (is_it_a_bad_time()) {
      sfx1 = 0;
      sfx2 = 0;
      return;
    }

    // NOTE: sfx are 6-bit values with top 2 MSBs indicating panning:
    //   00 = center, 01 = right, 10 = left, 11 = left

    uint8 lfx1 = bus::read_u8(0x7E012E);
    // filter out unwanted synced sounds:
    switch (lfx1) {
      case 0x2B: break; // low life warning beep
      default:
        sfx1 = lfx1;
    }

    uint8 lfx2 = bus::read_u8(0x7E012F);
    // filter out unwanted synced sounds:
    switch (lfx2) {
      case 0x0C: break; // text scrolling flute noise
      case 0x10: break; // switching to map sound effect
      case 0x11: break; // menu screen going down
      case 0x12: break; // menu screen going up
      case 0x20: break; // switch menu item
      case 0x24: break; // switching between different mode 7 map perspectives
      default:
        sfx2 = lfx2;
    }
  }

  bool is_frozen() {
    return bus::read_u8(0x7E02E4) != 0;
  }

  void fetch_sram() {
    // don't fetch latest SRAM when Link is frozen e.g. opening item chest for heart piece -> heart container:
    // NOTE: disabled this check so that items sync instantly when you get them during dialogs.
    //if (is_frozen()) return;
    local.in_sm_for_items = false;
    bus::read_block_u8(0x7EF000, 0, 0x500, sram);
    bus::read_block_u8(0xA17900, 0, 0x40, sram_buffer);
  }

  void fetch_objects() {
    if (!enableObjectSync && !debugGameObjects) return;
    if (is_dead()) return;

    // $7E0D00 - $7E0FA0
    uint i = 0;

    bus::read_block_u8(0x7E0D00, 0, 0x2A0, objectsBlock);
    for (i = 0; i < 0x10; i++) {
      auto @en = objects[i];
      if (en is null) {
        @en = @objects[i] = @GameSprite();
      }
      // copy in facts about each enemy from the large block of WRAM:
      objects[i].readFromBlock(objectsBlock, i);
    }
  }

  void fetch_sprites() {
    numsprites = 0;
    sprites.resize(0);
    if (is_it_a_bad_time()) {
      //message("clear sprites");
      return;
    }

    sprites_need_vram = true;

    // read OAM offset where link's sprites start at:
    int link_oam_start = bus::read_u16(0x7E0352) >> 2;
    //message(fmtInt(link_oam_start));

    // read in relevant sprites from OAM:
    array<uint8> oam(0x220);
    ppu::oam.read_block_u8(0, 0, 0x220, oam);

    // extract OAM sprites to class instances:
    sprites.reserve(128);
    for (int i = 0x00; i <= 0x7f; i++) {
      sprs[i].decodeOAMArray(oam, i);
    }

    // start from reserved region for Link (either at 0x64 or ):
    for (int j = 0; j < 0x0C; j++) {
      auto i = (link_oam_start + j) & 0x7F;

      auto @spr = sprs[i];
      // skip OAM sprite if not enabled:
      if (!spr.is_enabled) continue;

      //message("[" + fmtInt(spr.index) + "] " + fmtInt(spr.x) + "," + fmtInt(spr.y) + "=" + fmtInt(spr.chr));

      // append the sprite to our array:
      sprites.resize(++numsprites);
      @sprites[numsprites-1] = spr;
    }

    // don't sync OAM beyond link's body during or after GAME OVER animation after death:
    if (is_dead()) return;

    // capture effects sprites:
    for (int i = 0x00; i <= 0x7f; i++) {
      // skip already synced Link sprites:
      if ((i >= link_oam_start) && (i < link_oam_start + 0x0C)) continue;

      auto @spr = sprs[i];
      // skip OAM sprite if not enabled:
      if (!spr.is_enabled) continue;

      auto chr = spr.chr;
      if (chr >= 0x100) continue;

      if (i > 0) {
        auto @sprp1 = sprs[i-1];
        // Work around a bug with Leevers where they show up for a few frames as boomerangs:
        if (chr == 0x026 && sprp1.chr == 0x126) {
          continue;
        }
        // shadow underneath pot / bush or small stone
        if (chr == 0x6c && (sprp1.chr == 0x46 || sprp1.chr == 0x44 || sprp1.chr == 0x42)) {
          // append the sprite to our array:
          sprites.resize(++numsprites);
          @sprites[numsprites-1] = spr;
          continue;
        }
      }

      // water/sand/grass:
      if ((chr >= 0xc8 && chr <= 0xca) || (chr >= 0xd8 && chr <= 0xda)) {
        if (i > 0 && i <= 0x7D) {
          auto @sprp1 = sprs[i-1];
          auto @sprn1 = sprs[i+1];
          auto @sprn2 = sprs[i+2];
          // must be over follower to sync:
          if (
               // first water/sand/grass sprite:
               (chr == sprn1.chr && (sprn2.chr == 0x22 || sprn2.chr == 0x20))
               // second water/sand/grass sprite:
            || (chr == sprp1.chr && (sprn1.chr == 0x22 || sprn1.chr == 0x20))
          ) {
            // append the sprite to our array:
            sprites.resize(++numsprites);
            @sprites[numsprites-1] = spr;
            continue;
          }
        }

        continue;
      }

      // ether, bombos, quake:
      if (state == 0x08 || state == 0x09 || state == 0x0A) {
        if (
           (chr >= 0x40 && chr <= 0x4f)
        || (chr >= 0x60 && chr < 0x6c)
        ) {
          // append the sprite to our array:
          sprites.resize(++numsprites);
          @sprites[numsprites-1] = spr;
          continue;
        }
      }

      // hookshot:
      if (state == 0x13) {
        if (
           chr == 0x09 || chr == 0x0a || chr == 0x19
        ) {
          // append the sprite to our array:
          sprites.resize(++numsprites);
          @sprites[numsprites-1] = spr;
          continue;
        }
      }

      if (
        // sparkles around sword spin attack AND magic boomerang:
           chr == 0x80 || chr == 0x83 || chr == 0xb7
        // when boomerang hits solid tile:
        || chr == 0x81 || chr == 0x82
        // exclusively for spin attack:
        || chr == 0x8c || chr == 0x92 || chr == 0x93 || chr == 0xd6 || chr == 0xd7
        // bush leaves
        || chr == 0x59
        // cut grass
        || chr == 0xe2 || chr == 0xf2
        // pot shards or stone shards (large and small)
        || chr == 0x58 || chr == 0x48
        // boomerang
        || chr == 0x26
        // magic powder
        || chr == 0x09 || chr == 0x0a
        // magic cape
        || chr == 0x86 || chr == 0xa9 || chr == 0x9b
        // push block
        || chr == 0x0c
        // large stone
        || chr == 0x4a
        // holding pot / bush or small stone or sign
        || chr == 0x46 || chr == 0x44 || chr == 0x42
        // follower:
        || chr == 0x20 || chr == 0x22
      ) {
        // append the sprite to our array:
        sprites.resize(++numsprites);
        @sprites[numsprites-1] = spr;
        continue;
      }

      // don't sync the following sprites in ganon's room as it gets too busy:
      if (module == 0x07 && dungeon_room == 0x00) continue;

      if (
        // arrow:
           chr == 0x2a || chr == 0x2b || chr == 0x3a || chr == 0x3b
        || chr == 0x2c || chr == 0x2d || chr == 0x3c || chr == 0x3d
        // fire rod shot:
        || chr == 0x8d || chr == 0x9c || chr == 0x9d
        // fire rod shot flame up:
        || chr == 0x8e || chr == 0xa0 || chr == 0xa2 || chr == 0xa4 || chr == 0xa5
        // ice rod shot:
        || chr == 0xb6 || chr == 0xb7 || chr == 0x83 || chr == 0x80 || chr == 0xcf || chr == 0xdf
        // lantern fire:
        || chr == 0xe3 || chr == 0xf3 || chr == 0xa4 || chr == 0xa5 || chr == 0xb2 || chr == 0xb3 || chr == 0x9c
        // somaria block:
        || chr == 0xe9
        // somaria block explosion:
        || chr == 0xc4 || chr == 0xc5 || chr == 0xc6 || chr == 0xd2
        // somaria block shot:
        || chr == 0xc2 || chr == 0xc3 || chr == 0xd3 || chr == 0xd4
        // somaria shot explode:
        || chr == 0xd5 || chr == 0xd6
      ) {
        // append the sprite to our array:
        sprites.resize(++numsprites);
        @sprites[numsprites-1] = spr;
        continue;
      }
    }
  }

  void capture_sprites_vram() {
    if (!sprites_need_vram) {
      return;
    }

    for (int i = 0; i < numsprites; i++) {
      auto @spr = @sprites[i];
      capture_sprite(spr);
    }

    sprites_need_vram = false;
  }

  void capture_sprite(Sprite &sprite) {
    //message("capture_sprite " + fmtInt(sprite.index));
    // load character(s) from VRAM:
    if (sprite.size == 0) {
      // 8x8 sprite:
      //message("capture  x8 CHR=" + fmtHex(sprite.chr, 3));
      /*if (chrs[sprite.chr].length() == 0)*/ {
        chrs[sprite.chr].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr), 0, 16, chrs[sprite.chr]);
      }
    } else {
      // 16x16 sprite:
      //message("capture x16 CHR=" + fmtHex(sprite.chr, 3));
      /*if (chrs[sprite.chr + 0x00].length() == 0)*/ {
        chrs[sprite.chr + 0x00].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x00), 0, 16, chrs[sprite.chr + 0x00]);
      }
      /*if (chrs[sprite.chr + 0x01].length() == 0)*/ {
        chrs[sprite.chr + 0x01].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x01), 0, 16, chrs[sprite.chr + 0x01]);
      }
      /*if (chrs[sprite.chr + 0x10].length() == 0)*/ {
        chrs[sprite.chr + 0x10].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x10), 0, 16, chrs[sprite.chr + 0x10]);
      }
      /*if (chrs[sprite.chr + 0x11].length() == 0)*/ {
        chrs[sprite.chr + 0x11].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x11), 0, 16, chrs[sprite.chr + 0x11]);
      }
    }
  }

  uint8 get_area_size() property {
    if (module == 0x06 || is_in_dungeon_module()) {
      // underworld is always 64x64 tiles:
      return 0x40;
    }
    // assume overworld:
    return bus::read_u8(0x7E0712) > 0 ? 0x40 : 0x20;
  }

  void fetch_tilemap_changes() {
    // disable tilemap sync based on settings:
    if (settings.DisableTilemap) {
      return;
    }

    if (is_dead()) {
      return;
    }

    bool clear = false;
    if (actual_location != last_actual_location) {
      // generic location changed event:
      clear = true;
    }

    if (!clear) {
      return;
    }

    // clear tilemap to -1 when changing rooms:
    if (debugRTDScapture) {
      message("tilemap.reset()");
    }
    tilemap.reset(area_size);
    tilemapLocation = actual_location;

    // we need to load in new tilemap from other players:
    tilemapTimestamp = 0;
  }

  bool is_safe_to_sample_tilemap() {
    if (module == 0x09) {
      // overworld:
      // during screen transition:
      if (sub_module >= 0x01 && sub_module < 0x07) return false;
      // during lost woods transition:
      if (sub_module >= 0x0d && sub_module < 0x16) return false;
      // when coming out of map screen:
      if (sub_module >= 0x20 && sub_module <= 0x22) return false;
      // or during LW/DW transition:
      if (sub_module >= 0x23) return false;
    } else if (module == 0x0B) {
      // master sword or zora:
      // safety measure here:
      if (sub_module >= 0x01) return false;
      // (sub_module == 0x18 || sub_module == 0x19) for loading master sword area
      // sub_module == 0x1C mosaic in
      // sub_module == 0x24 mosaic out
    } else if (module == 0x07) {
      // underworld:
      // scrolling between rooms in same supertile:
      if (sub_module == 0x01) return false;
      // loading new supertile:
      if (sub_module == 0x02) return false;
      // up/down through floor:
      if (sub_module == 0x06) return false;
      if (sub_module == 0x07) return false;
      // going up/down spiral stairwells between floors:
      if (sub_module == 0x08) return false;
      if (sub_module == 0x0e) return false;
      if (sub_module == 0x10) return false;
      // going up/down straight stairwells between floors:
      if (sub_module == 0x12) return false;
      if (sub_module == 0x13) return false;
      // warp to another room:
      if (sub_module == 0x15) return false;
      // crystal sequence:
      if (sub_module == 0x18) return false;
      // using mirror:
      if (sub_module == 0x19) return false;

      // in Ganon's room:
      if (dungeon_room == 0x00) return false;
    } else {
      // don't sample tilemap changes:
      return false;
    }

    // allow tilemap sampling:
    return true;
  }

  // intercept 8-bit writes to a 8-bit array in WRAM at $7f2000:
  void attributes_written(uint32 addr, uint8 oldValue, uint8 newValue) {
    if (newValue == oldValue) {
      return;
    }

    if (is_it_a_bad_time()) {
      return;
    }

    if (!is_safe_to_sample_tilemap()) {
      return;
    }

    // don't capture barrier tiles since crystal switch sync now takes care of that:
    if (module == 0x07 && sub_module == 0x16) {
      if (newValue == 0x66 || newValue == 0x67) {
        return;
      }
    }

    if (debugRTDScapture) {
      message("a: " + fmtHex(addr, 6) + " <- " + fmtHex(newValue, 2) + " (was " + fmtHex(oldValue, 2) + ") at cpu.r.pc = " + fmtHex(cpu::r.pc, 6));
    }

    // figure out offset from $7f2000:
    auto i = addr - 0x7F2000;

    if (tilemap[i] == -1) {
      // sample tile and attribute simultaneously:
      tilemap[i] = int32(bus::read_u16(0x7E2000 + (i << 1))) | (int32(newValue) << 16);
    } else {
      // just overwrite attribute:
      tilemap[i] = (tilemap[i] & 0x0000ffff) | (int32(newValue) << 16);
    }
    //if (debugRTDScapture) {
    //  message("tile[0x" + fmtHex(i, 4) + "] -> 0x" + fmtHex(tilemap[i], 6));
    //}
    tilemapTimestamp = timestamp_now;
  }

  // intercept 8-bit writes to a 16-bit array in WRAM at $7e2000:
  void tilemap_written(uint32 addr, uint8 oldValue, uint8 newValue) {
    if (newValue == oldValue) {
      return;
    }

    if (is_it_a_bad_time()) {
      return;
    }

    if (!is_safe_to_sample_tilemap()) {
      return;
    }

    if (debugRTDScapture) {
      message("t: " + fmtHex(addr, 6) + " <- " + fmtHex(newValue, 2) + " (was " + fmtHex(oldValue, 2) + ") at cpu.r.pc = " + fmtHex(cpu::r.pc, 6));
    }

    // read current entire word at address being written to:
    uint16 word = bus::read_u16(addr & 0xFFFFFE);

    // figure out offset from $7E2000:
    addr -= 0x7E2000;

    // mask off low bit of offset and divide by 2 for 16-bit index:
    uint i = addr >> 1;

    // apply the write to either side of the uint16 (upcast to int32):
    if ((addr & 1) == 1) {
      // high byte:

      if (tilemap[i] == -1) {
        // sample high byte of tile and attribute simultaneously:
        tilemap[i] = (int32(bus::read_u8(0x7F2000 + i)) << 16) | (int32(word) & 0x00ff) | (int32(newValue) << 8);
      } else {
        // just overwrite high byte of tile:
        tilemap[i] = (tilemap[i] & 0x00ff00ff) | (int32(newValue) << 8);
      }
    } else {
      // low byte:

      if (tilemap[i] == -1) {
        // sample low byte of tile and attribute simultaneously:
        tilemap[i] = (int32(bus::read_u8(0x7F2000 + i)) << 16) | (word & 0xff00) | (int32(newValue));
      } else {
        // just overwrite low byte of tile:
        tilemap[i] = (tilemap[i] & 0x00ffff00) | (int32(newValue));
      }
    }
    //if (debugRTDScapture) {
    //  message("tile[0x" + fmtHex(i, 4) + "] -> 0x" + fmtHex(tilemap[i], 6));
    //}
    tilemapTimestamp = timestamp_now;
  }

  void fetch_ancillae() {
    if (is_dead()) return;

    // update ancillae array from WRAM:
    array<uint8> u280(0x32);
    array<uint8> u380(0x4F);
    array<uint8> uBF0(0xAA);
    bus::read_block_u8(0x7E0280, 0, 0x32, u280);
    bus::read_block_u8(0x7E0380, 0, 0x4F, u380);
    bus::read_block_u8(0x7E0BF0, 0, 0xAA, uBF0);
    for (uint i = 0; i < 0x0A; i++) {
      auto @anc = @ancillae[i];
      anc.readRAM(i, u280, u380, uBF0);

      // Update ownership:
      if (ancillaeOwner[i] == index) {
        anc.requestOwnership = false;
        if (anc.type == 0) {
          ancillaeOwner[i] = -2;
        }
      } else if (ancillaeOwner[i] == -1) {
        if (anc.type != 0) {
          ancillaeOwner[i] = index;
          anc.requestOwnership = false;
        }
      } else if (ancillaeOwner[i] == -2) {
        ancillaeOwner[i] = -1;
        anc.requestOwnership = false;
      }
    }
  }

  void fetch_torches() {
    if (!is_in_dungeon_module()) return;
    if (is_dead()) return;

    torchTimers.resize(0x10);
    bus::read_block_u8(0x7E04F0, 0, 0x10, torchTimers);
  }

  bool is_torch_lit(uint8 t) {
    if (!is_in_dungeon_module()) return false;
    if (t >= 0x10) return false;

    auto idx = (t << 1) + bus::read_u16(0x7E0478);
    auto tm = bus::read_u16(0x7E0540 + idx);
    return (tm & 0x8000) == 0x8000;
  }

  void fetch_sm_events() {
  
    for (int i = 0; i < 0x14; i++) {
      sm_events[i] = bus::read_u8(0x7ED820 + i);
    }
    for (int i = 0; i < 0x20; i++) {
      sm_events[i + 0x14] = bus::read_u8(0x7ED870 + i);
    }
    for (int i = 0; i < 0x20; i++) {
      sm_events[i + 0x14 + 0x20] = bus::read_u8(0x7ED8B0 + i);
    }
  }
  
  void fetch_sm_events_buffer() {
    
    //$a16070 is the start of the buffer for the super metroid events
    
    for (int i = 0; i < 0x14; i++) {
      sm_events[i] = bus::read_u8(0xa16070 + i);
    }
    for (int i = 0; i < 0x20; i++) {
      sm_events[i + 0x14] = bus::read_u8(0xa160c0 + i);
    }
    for (int i = 0; i < 0x20; i++) {
      sm_events[i + 0x14 + 0x20] = bus::read_u8(0xa16100 + i);
    }
  }
  
  void fetch_games_won(){
    sm_clear = bus::read_u8(0xa17402);
    z3_clear = bus::read_u8(0xa17506);
  }

  void serialize_location(array<uint8> &r) {
    r.write_u8(uint8(0x01));

    r.write_u8(module);
    r.write_u8(sub_module);
    r.write_u8(sub_sub_module);

    r.write_u24(location);

    r.write_u16(x);
    r.write_u16(y);

    r.write_u16(dungeon);
    r.write_u16(dungeon_entrance);

    r.write_u16(last_overworld_x);
    r.write_u16(last_overworld_y);

    r.write_u16(xoffs);
    r.write_u16(yoffs);

    r.write_u16(player_color);

    r.write_u8(in_sm);
  }

  void serialize_sm_location(array<uint8> &r) {
    r.write_u8(uint8(0x0F));

    r.write_u8(sm_area);
    r.write_u8(sm_x);
    r.write_u8(sm_y);
    r.write_u8(sm_sub_x);
    r.write_u8(sm_sub_y);
    r.write_u8(in_sm);
    r.write_u8(sm_room_x);
    r.write_u8(sm_room_y);
    r.write_u8(sm_pose);
  }
  
  void serialize_sm_sprite(array<uint8> &r){
    r.write_u8(uint8(0x10));
    
    r.write_u16(offsm1);
    r.write_u16(offsm2);
    
    for(int i = 0; i < 0x10; i++){
      r.write_u16(sm_palette[i]);
    }
  }

  void serialize_sfx(array<uint8> &r) {
    r.write_u8(uint8(0x02));

    r.write_u8(sfx1);
    r.write_u8(sfx2);
  }

  void serialize_sram(array<uint8> &r, uint16 start, uint16 endExclusive) {
    r.write_u8(uint8(0x06));

    r.write_u8(start == 0 ? 1 : 0);
    r.write_u8(in_sm_for_items ? 1 : 0);

    r.write_u16(start);
    uint16 count = uint16(endExclusive - start);
    r.write_u16(count);
    for (uint i = 0; i < count; i++) {
      auto offs = start + i;
      auto b = sram[offs];
      r.write_u8(b);
    }
  }

  void serialize_sram_buffer(array<uint8> &r, uint16 start, uint16 endExclusive) {
    r.write_u8(uint8(0x0E));

    r.write_u16(start);
    uint16 count = uint16(endExclusive - start);
    r.write_u16(count);
    for (uint i = 0; i < count; i++) {
      auto offs = start + i;
      auto b = sram_buffer[offs];
      r.write_u8(b);
    }
  }

  void serialize_wram(array<uint8> &r) {
    // write a table of 1 sync-byte for dungeon crystal switch state:
    r.write_u8(uint8(0x05));
    r.write_u8(uint8(0x01));
    r.write_u16(crystal.offs);
    crystal.serialize(r);

    if (enableSmallKeySync) {
      // write a table of 16 sync-bytes for dungeon small keys:
      r.write_u8(uint8(0x05));
      r.write_u8(uint8(0x10));
      r.write_u16(small_keys_min_offs);
      for (uint8 i = 0; i < 0x10; i++) {
        auto @k = @small_keys[i];
        k.serialize(r);
      }
    }
  }

  void serialize_objects(array<uint8> &r) {
    if (!enableObjectSync) return;

    r.write_u8(uint8(0x08));

    // 0x2A0 bytes
    r.write_arr(objectsBlock);
  }

  void serialize_ancillae(array<uint8> &r) {
    if (ancillaeOwner.length() == 0) return;
    if (ancillae.length() == 0) return;

    r.write_u8(uint8(0x09));

    uint8 count = 0;
    for (uint i = 0; i < 0x0A; i++) {
      if (!ancillae[i].requestOwnership) {
        if (ancillaeOwner[i] != index && ancillaeOwner[i] != -1) continue;
      }
      if (!ancillae[i].is_syncable()) continue;

      count++;
    }

    // count of active+owned ancillae:
    r.write_u8(count);
    for (uint i = 0; i < 0x0A; i++) {
      if (!ancillae[i].requestOwnership) {
        if (ancillaeOwner[i] != index && ancillaeOwner[i] != -1) continue;
      }
      if (!ancillae[i].is_syncable()) continue;

      ancillae[i].serialize(r);
    }
  }

  void serialize_torches(array<uint8> &r) {
    // dungeon torches:
    r.write_u8(uint8(0x0A));

    uint8 count = 0;
    for (uint8 t = 0; t < 0x10; t++) {
      if (torchOwner[t] != index) continue;
      count++;
    }

    //message("torches="+fmtInt(count));
    r.write_u8(count);
    for (uint8 t = 0; t < 0x10; t++) {
      if (torchOwner[t] != index) continue;
      r.write_u8(t);
      r.write_u8(torchTimers[t]);
    }
  }

  void serialize_pvp(array<uint8> &r) {
    r.write_u8(uint8(0x0B));

    r.write_u8(action_hitbox.active ? uint8(1) : uint8(0));
    if (action_hitbox.active) {
      r.write_u16(action_hitbox.x);
      r.write_u16(action_hitbox.y);
      r.write_u8 (action_hitbox.w);
      r.write_u8 (action_hitbox.h);
      r.write_u8 (action_sword_time);
      r.write_u8 (action_item_used);
    }

    r.write_u8 (action_sword_type);
    r.write_u8 (action_room_level);

    // serialize PvP attacks:
    auto len = uint8(pvp_attacks.length());
    r.write_u8(len);
    for (uint i = 0; i < len; i++) {
      auto @a = pvp_attacks[i];

      r.write_u16(a.player_index);
      r.write_u8 (a.sword_time);
      r.write_u8 (a.melee_item);
      r.write_u8 (a.ancilla_mode);
      r.write_u8 (a.damage);
      r.write_u8 (a.recoil_dx);
      r.write_u8 (a.recoil_dy);
      r.write_u8 (a.recoil_dz);
    }
  }

  void serialize_name(array<uint8> &r) {
    r.write_u8(uint8(0x0C));

    r.write_str(namePadded);
  }

  void serialize_sm_events(array<uint8> &r) {
    r.write_u8(uint8(0x0D));

    for (int i = 0; i < 0x54; i++) {
      r.write_u8(sm_events[i]);
    }
    
    r.write_u8(sm_clear);
    r.write_u8(z3_clear);
  }

  uint send_sprites(uint p) {
    uint len = sprites.length();

    uint start = 0;
    uint end = len;

    // never send the shadow sprite or bomb sprite data (or anything for chr >= 0x80):
    array<bool> paletteSent(8);
    array<bool> chrSent(0x80);
    chrSent[0x6c] = true;
    chrSent[0x6d] = true;
    chrSent[0x6e] = true;
    chrSent[0x6f] = true;
    chrSent[0x7c] = true;
    chrSent[0x7d] = true;
    chrSent[0x7e] = true;
    chrSent[0x7f] = true;

    // send out possibly multiple packets to cover all sprites:
    while (start < end) {
      array<uint8> r = create_envelope(0x02);

      // serialize_sprites:
      if (start == 0) {
        // start of sprites:
        r.write_u8(uint8(0x03));
      } else {
        // continuation of sprites:
        r.write_u8(uint8(0x04));
        r.write_u8(uint8(start));
      }

      uint markLen = r.length();
      r.write_u8(uint8(end - start));

      uint mark = r.length();

      uint i;
      //message("build start=" + fmtInt(start));
      for (i = start; i < end; i++) {
        auto @spr = sprites[i];
        auto chr = spr.chr;
        auto index = spr.index;
        uint pal = spr.palette;
        auto b4 = spr.b4;

        // do we need to send the VRAM data?
        if ((chr < 0x80) && !chrSent[chr]) {
          index |= 0x80;
        }
        // do we need to send the palette data?
        if (!paletteSent[pal]) {
          b4 |= 0x80;
        }

        mark = r.length();
        //message("  mark=" + fmtInt(mark));

        // emit the OAM data:
        r.write_u8(index);
        r.write_u8(spr.b0);
        r.write_u8(spr.b1);
        r.write_u8(spr.b2);
        r.write_u8(spr.b3);
        r.write_u8(b4);

        // send VRAM data along:
        if ((index & 0x80) != 0) {
          r.write_arr(chrs[chr+0x00]);
          if (spr.size != 0) {
            r.write_arr(chrs[chr+0x01]);
            r.write_arr(chrs[chr+0x10]);
            r.write_arr(chrs[chr+0x11]);
          }
        }

        // include the palette for this sprite:
        if ((b4 & 0x80) != 0) {
          // sample the palette:
          uint cgaddr = (pal + 8) << 4;
          for (uint k = cgaddr; k < cgaddr + 16; k++) {
            r.write_u16(ppu::cgram[k]);
          }
        }

        // check length of packet:
        if (r.length() <= MaxPacketSize) {
          // mark data as sent:
          if ((index & 0x80) != 0) {
            chrSent[chr+0x00] = true;
            //chrs[chr+0x00].resize(0);
            if (spr.size != 0) {
              chrSent[chr+0x01] = true;
              chrSent[chr+0x10] = true;
              chrSent[chr+0x11] = true;
              //chrs[chr+0x01].resize(0);
              //chrs[chr+0x10].resize(0);
              //chrs[chr+0x11].resize(0);
            }
          }
          if ((b4 & 0x80) != 0) {
            paletteSent[pal] = true;
          }
        } else {
          // back out the last sprite:
          r.removeRange(mark, r.length() - mark);

          // continue at the last sprite in the next packet:
          //message("  scratch last mark");
          break;
        }
      }

      r[markLen] = uint8(i - start);
      start = i;

      // send this packet:
      p = send_packet(r, p);
    }

    return p;
  }

  uint send_tilemaps(uint p) {
    // compress tilemap into horizontal/vertical runs if not already done:
    tilemap.compress_runs();

    auto @runs = tilemap.runs;
    uint len = runs.length();

    uint start = 0;
    uint end = len;

    // degenerate case to clear out tilemap:
    if (len == 0) {
      array<uint8> r = create_envelope(0x02);

      r.write_u8(uint8(0x07));
      // truncating 64-bit timestamp to 32-bit value (in milliseconds):
      r.write_u32(tilemapTimestamp);
      r.write_u24(tilemapLocation);
      r.write_u8(0);
      r.write_u8(0);

      // send this packet:
      p = send_packet(r, p);
      return p;
    }

    // send out possibly multiple packets to cover all sprites:
    while (start < end) {
      array<uint8> r = create_envelope(0x02);

      r.write_u8(uint8(0x07));
      // truncating 64-bit timestamp to 32-bit value (in milliseconds):
      r.write_u32(tilemapTimestamp);
      r.write_u24(tilemapLocation);
      r.write_u8(uint8(start));

      // serialize as many runs as can fit into packet:
      uint markLen = r.length();
      r.write_u8(uint8(end - start));

      uint mark = r.length();

      uint i;
      for (i = start; i < end; i++) {
        auto @run = runs[i];

        mark = r.length();
        run.serialize(r);

        if (r.length() > MaxPacketSize) {
          // back out the last run:
          r.removeRange(mark, r.length() - mark);

          // continue at the last run in the next packet:
          //message("  scratch last mark");
          break;
        }
      }

      r[markLen] = uint8(i - start);
      start = i;

      // send this packet:
      p = send_packet(r, p);
    }

    return p;
  }

  array<uint8> @create_envelope(uint8 kind = 0x01) {
    array<uint8> @envelope = {};
    envelope.reserve(MaxPacketSize);

    // server envelope:
    {
      // header:
      envelope.write_u16(uint16(25887));
      // server protocol 2:
      envelope.write_u8(uint8(0x02));
      // group name: (20 bytes exactly)
      envelope.write_str(settings.GroupPadded);
      // message kind:
      envelope.write_u8(kind);
      // what we think our index is:
      envelope.write_u16(uint16(index));

      if (kind == 0x02) {
        // broadcast to sector:
        uint16 sector = actual_location;
        if ((sector & 0x010000) != 0) {
          // turn off light/dark world bit so that all underworld locations are equal:
          sector &= 0x01FFFF;
        }
        envelope.write_u32(sector);
      }
    }

    // script protocol:
    envelope.write_u8(uint8(script_protocol));

    // protocol starts with team number:
    envelope.write_u8(team);
    // frame number to correlate separate packets together:
    envelope.write_u8(frame);

    return envelope;
  }

  array<uint16> maxSize(5);

  uint send_packet(array<uint8> &in envelope, uint p) {
    uint len = envelope.length();
    if (len > MaxPacketSize) {
      message("packet[" + fmtInt(p) + "] too big to send! " + fmtInt(len) + " > " + fmtInt(MaxPacketSize));
      return p;
    }

    // send packet to server:
    //message("sent " + fmtInt(envelope.length()) + " bytes");
    sock.send(0, len, envelope);

    // stats on max packet size per 128 frames:
    if (debugNet) {
      if (len > maxSize[p]) {
        maxSize[p] = len;
      }
      if ((frame & 0x7F) == 0) {
        message("["+fmtInt(p)+"] = " + fmtInt(maxSize[p]));
        maxSize[p] = 0;
      }
    }
    p++;

    return p;
  }

  void send() {
    uint p = 0;

    // check if we need to detect our local index:
    if (index == -1) {
      // request our index; receive() will take care of the response:
      array<uint8> request = create_envelope(0x00);
      p = send_packet(request, p);
    }

    // rate limit outgoing packets to 60fps:
    if (timestamp_now - last_sent < 16) {
      return;
    }
    last_sent = timestamp_now;

    // send main packet:
    {
      array<uint8> envelope = create_envelope();

      serialize_location(envelope);
      serialize_name(envelope);
      serialize_sfx(envelope);

      if (settings.EnablePvP) {
        serialize_pvp(envelope);
      }

      if (!settings.RaceMode) {
        serialize_ancillae(envelope);
        serialize_objects(envelope);
        serialize_wram(envelope);
      }

      p = send_packet(envelope, p);
    }

    // send possibly multiple packets for sprites:
    p = send_sprites(p);

    if (!settings.RaceMode) {
      // send posisbly multiple packets for tilemaps:
      if (!settings.DisableTilemap) {
        p = send_tilemaps(p);
      }

      // send packet every other frame:
      if ((frame & 1) == 0) {
        array<uint8> envelope = create_envelope(0x02);
        serialize_torches(envelope);
        p = send_packet(envelope, p);
      }

      // send SRAM updates once every 16 frames:
      if ((frame & 15) == 0) {
        array<uint8> envelope = create_envelope();
        rom.serialize_sram_ranges(envelope, serializeSramDelegate);
        p = send_packet(envelope, p);
      }

      // send dungeon and overworld SRAM alternating every 16 frames:
      if ((frame & 31) == 0) {
        array<uint8> envelope = create_envelope();
        serialize_sram(envelope,   0x0, 0x250); // dungeon rooms
        p = send_packet(envelope, p);
      }
      if ((frame & 31) == 16) {
        array<uint8> envelope = create_envelope();
        serialize_sram(envelope, 0x280, 0x340); // overworld events; heart containers, overlays
        p = send_packet(envelope, p);
      }

      if (rom.is_smz3()) {
        if ((frame & 31) == 0) {
          array<uint8> envelope = create_envelope();
          serialize_sm_events(envelope); // item checks, bosses killed, and doors opened
          p = send_packet(envelope, p);
        }

        if ((frame & 31) == 0) {
          array<uint8> envelope = create_envelope();
          serialize_sram_buffer(envelope, 0x0, 0x40); // sram buffer, only sent if the rom is an smz3
          p = send_packet(envelope, p);
        }

        if ((frame & 31) == 16) {
          array<uint8> envelope = create_envelope();
          serialize_sram_buffer(envelope, 0x300, 0x400); // sram buffer, only sent if the rom is an smz3
          p = send_packet(envelope, p);
        }

        if (!rom.is_alttp()) {
          array<uint8> envelope = create_envelope();
          serialize_sm_location(envelope);
          p = send_packet(envelope, p);
        
          array<uint8> envelope1 = create_envelope();
          serialize_sm_sprite(envelope1);
          p = send_packet(envelope1, p);
        }
      }
    }
  }

  void update_wram() {
    if (module < 0x06) return;

    // reset comparison state:
    crystal.compareStart();
    if (enableSmallKeySync) {
      for (uint j = 0; j < 0x10; j++) {
        small_keys[j].compareStart();
      }
    }

    // compare remote values from all other active players:
    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != team) continue;
      if (remote.is_it_a_bad_time()) continue;
      if (remote.in_sm == 1) continue;

      // update crystal switches to latest state among all players in same dungeon:
      if ((module == 0x07 && sub_module == 0x00) && (remote.module == module) && (remote.dungeon == dungeon)) {
        crystal.compareTo(remote.crystal);
      }

      if (enableSmallKeySync) {
        // update small keys:
        if (remote.small_keys !is null && remote.small_keys.length() >= 0x10) {
          for (uint j = 0; j < 0x10; j++) {
            if (small_keys[j] is null || remote.small_keys[j] is null) {
              continue;
            }

            small_keys[j].compareTo(remote.small_keys[j]);
          }
        }
      }
    }

    if (crystal.winner !is null) {
      // record timestamp so if we just joined we should keep that:
      if (crystal.updateTo(crystal.winner)) {
        //if (debugData) {
        //  message("crystal update " + fmtHex(crystal.oldValue,2) + " -> " + fmtHex(crystal.value,2));
        //}

        // go to switch transition module:
        //LDA.b #$16 : STA $11
        bus::write_u8(0x7E0011, 0x16);

        // trigger sound effect:
        //LDA.b #$25 : JSL Sound_SetSfx3PanLong
      }
    }

    if (enableSmallKeySync) {
      auto this_dungeon = dungeon >> 1;
      for (uint j = 0; j < 0x10; j++) {
        auto @key = small_keys[j];
        if (key.winner is null) {
          continue;
        }

        key.updateTo(key.winner);
        if (debugData) {
          dbgData("keys[" + fmtHex(j,2) + "] update " + fmtHex(key.oldValue,2) + " -> " + fmtHex(key.value,2) + "; ts -> " + pad(key.timestamp,10));
        }

        if (dungeon != 0xFF && module == 0x07) {
          if (this_dungeon == j) {
            // update current dungeon key counter:
            small_keys_current.updateTo(key);
            dbgData("keys_current update " + fmtHex(key.oldValue,2) + " -> " + fmtHex(key.value,2) + "; ts -> " + pad(key.timestamp,10));
          }
        }
      }
    }
  }

  array<string> received_items(0);
  array<string> received_quests(0);
  void collectNotifications(const string &in name) {
    if (name.length() == 0) return;

    if (name.length() >= 2 && name.slice(0, 2) == "Q#") {
      received_quests.insertLast(name.slice(2));
      return;
    }
    received_items.insertLast(name);
  }

  void update_items(SRAM@ d, bool is_sram_buffer = false) {
    if (rom.is_alttp()) {
      if (is_it_a_bad_time()) return;

      // don't update latest SRAM when Link is frozen e.g. opening item chest for heart piece -> heart container:
      // when opening a chest with a heart piece inside and if you have 3 pieces, the piece counter goes from 3 to 0
      // and then the chest is opened, the animation completes, the dialog opens, and you close it, and THEN the heart
      // container counter is increased by 8 (one full heart).
      // we need to not sync in new values while this process is happening (link is frozen in place) otherwise it will
      // break the final calculation and will not increment heart container count.
      if (is_frozen()) return;
    }

    auto @syncables = @rom.syncables;

    // track names of items received:
    received_items.reserve(syncables.length());
    received_items.resize(0);
    received_quests.reserve(16);
    received_quests.resize(0);

    uint len = players.length();
    uint slen = syncables.length();
    for (uint k = 0; k < slen; k++) {
      auto @syncable = @syncables[k];
      // TODO: for some reason syncables.length() is one higher than it should be.
      if (syncable is null) continue;
      if ((in_sm_for_items == syncable.is_sm) == is_sram_buffer) continue;

      // start the sync process for each syncable item in SRAM:
      syncable.start(d);

      // apply remote values from all other active players:
      for (uint i = 0; i < len; i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is this) continue;
        if (remote.ttl <= 0) continue;
        if (remote.team != team) continue;
        //if (remote.is_it_a_bad_time()) continue;

        // apply the remote values:
        if (remote.in_sm_for_items == syncable.is_sm) {
          syncable.apply(d, @SRAMArray(remote.sram));
        } else {
          syncable.apply(d, @SRAMArray(remote.sram_buffer));
        }
      }

      // write back any new updates:
      syncable.finish(d, itemReceivedDelegate);
    }

    // Generate notification messages:
    if (received_items.length() > 0) {
      for (uint i = 0; i < received_items.length(); i++) {
        notify("Got " + received_items[i]);
      }
    }
    if (received_quests.length() > 0) {
      for (uint i = 0; i < received_quests.length(); i++) {
        notify("Quest " + received_quests[i]);
      }
    }
  }

  void update_overworld(SRAM@ d) {
    if (is_it_a_bad_time()) return;

    uint len = players.length();

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != team) continue;
      if (remote.in_sm_for_items) continue;

      // read current state from SRAM:
      for (uint a = 0; a < OverworldAreaCount; a++) {
        areas[a].start(d);
      }
    }

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != team) continue;
      if (remote.in_sm_for_items) continue;

      for (uint a = 0; a < OverworldAreaCount; a++) {
        areas[a].apply(d, @SRAMArray(remote.sram));
      }
    }

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != team) continue;
      if (remote.in_sm_for_items) continue;

      for (uint a = 0; a < OverworldAreaCount; a++) {
        // write new state to SRAM:
        areas[a].finish(d);
      }
    }
  }

  void update_rooms(SRAM@ d) {
    uint len = players.length();

    // $000 - $24F : Data for Rooms (two bytes per room)
    //
    // High Byte               Low Byte
    // d d d d b k ck cr       c c c c q q q q
    //
    // c - chest, big key chest, or big key lock. Any combination of them totalling to 6 is valid.
    // q - quadrants visited:
    // k - key or item (such as a 300 rupee gift)
    // d - door opened (either unlocked, bombed or other means)
    // r - special rupee tiles, whether they've been obtained or not.
    // b - boss battle won
    //
    // qqqq corresponds to 4321, so if quadrants 4 and 1 have been "seen" by Link, then qqqq will look like 1001. The quadrants are laid out like so in each room:

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != team) continue;
      if (remote.in_sm_for_items) continue;

      // read current state from SRAM:
      for (uint a = 0; a < 0x128; a++) {
        rooms[a].start(d);
      }
    }

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != team) continue;
      if (remote.in_sm_for_items) continue;

      for (uint a = 0; a < 0x128; a++) {
        rooms[a].apply(d, @SRAMArray(remote.sram));
      }
    }

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != team) continue;
      if (remote.in_sm_for_items) continue;

      // write new state to SRAM:
      for (uint a = 0; a < 0x128; a++) {
        rooms[a].finish(d);
      }
    }
  }

  void tilemap_testcase() {
    if (actual_location == 0x02005b) {
      message("testcase!");
      tilemap[0x0aae]=0x0dc5;
      tilemap[0x0aad]=0x0dc5;
      tilemap[0x0aac]=0x0dc5;
      tilemap[0x0aab]=0x0dc5;
      tilemap[0x0a6f]=0x0dc5;
      tilemap[0x0a6e]=0x0dc5;
      tilemap[0x0a6d]=0x0dc5;
      tilemap[0x0a6c]=0x0dc5;
      tilemap[0x0a6b]=0x0dc5;
      tilemap[0x0a6a]=0x0dc5;
      tilemap[0x0a30]=0x0dc5;
      tilemap[0x0a2f]=0x0dc5;
      tilemap[0x0a2e]=0x0dc5;
      tilemap[0x0a2d]=0x0dc5;
      tilemap[0x0a2c]=0x0dc5;
      tilemap[0x0a2b]=0x0dc5;
      tilemap[0x0a2a]=0x0dc5;
      tilemap[0x0aed]=0x0dc5;
      tilemap[0x0aec]=0x0dc5;
      tilemap[0x0b31]=0x0dcd;
      tilemap[0x0b32]=0x0dce;
      tilemap[0x0b71]=0x0dcf;
      tilemap[0x0b72]=0x0dd0;
      tilemap[0x09f3]=0x0dc5;
      tilemap[0x09f2]=0x0dc5;
      tilemap[0x09f1]=0x0dc5;
      tilemap[0x09f0]=0x0dc5;
      tilemap[0x09ef]=0x0dc5;
      tilemap[0x09ee]=0x0dc5;
      tilemap[0x09ed]=0x0dc5;
      tilemap[0x09ec]=0x0dc5;
      tilemap[0x09eb]=0x0dc5;
    } else if (actual_location == 0x020065) {
      message("testcase!");
      tilemap[0x0242]=0x0dc6;
      tilemap[0x03c4]=0x0dc7;
      tilemap[0x0444]=0x0dc7;
      tilemap[0x0484]=0x0dc7;
      tilemap[0x04c4]=0x0dc7;
      tilemap[0x0745]=0x0dc7;
    } else if (actual_location == 0x02005d) {
      message("testcase!");
      tilemap[0x0217]=0x0dc7;
      tilemap[0x0198]=0x0dcd;
      tilemap[0x0199]=0x0dce;
      tilemap[0x01d8]=0x0dcf;
      tilemap[0x01d9]=0x0dd0;
      tilemap[0x0197]=0x0dcb;
    } else if (actual_location == 0x000013) {
      message("testcase!");
      tilemap[0x030e]=0x0dc7;
      tilemap[0x024e]=0x0dcd;
      tilemap[0x024f]=0x0dce;
      tilemap[0x028e]=0x0dcf;
      tilemap[0x028f]=0x0dd0;
      tilemap[0x03d4]=0x0dc7;
      tilemap[0x03d3]=0x0dc7;
      tilemap[0x03d1]=0x0dc7;
      tilemap[0x03d0]=0x0dc7;
      tilemap[0x03d7]=0x0dc7;
      tilemap[0x03d8]=0x0dc7;
      tilemap[0x03da]=0x0dc7;
      tilemap[0x03db]=0x0dc7;
      tilemap[0x0417]=0x0dc7;
      tilemap[0x0418]=0x0dc7;
      tilemap[0x041a]=0x0dc7;
      tilemap[0x041b]=0x0dc7;
      tilemap[0x0414]=0x0dc7;
      tilemap[0x0413]=0x0dc7;
      tilemap[0x0411]=0x0dc7;
      tilemap[0x0410]=0x0dc7;
      tilemap[0x03dd]=0x0dc5;
    } else {
      message("no testcase");
    }
  }

  bool is_safe_to_write_tilemap() {
    if (module == 0x09) {
      // overworld:
      // during screen transition:
      if (sub_module >= 0x01 && sub_module < 0x07) return false;
      // during lost woods transition:
      if (sub_module >= 0x0d && sub_module < 0x16) return false;
      // when coming out of map screen:
      if (sub_module >= 0x20 && sub_module <= 0x22) return false;
      // during LW/DW transition:
      if (sub_module >= 0x23) return false;

      return true;
    } else if (module == 0x0B) {
      // master sword or zora:
      // safety measure here:
      if (sub_module >= 0x01) return false;
      // (sub_module == 0x18 || sub_module == 0x19) for loading master sword area
      // sub_module == 0x1C mosaic in
      // sub_module == 0x24 mosaic out

      return true;
    } else if (module == 0x07) {
      // underworld:
      // scrolling between rooms in same supertile:
      if (sub_module == 0x01) return false;
      // loading new supertile:
      if (sub_module == 0x02) return false;
      // up/down through floor:
      if (sub_module == 0x06) return false;
      if (sub_module == 0x07) return false;
      // going up/down spiral stairwells between floors:
      if (sub_module == 0x08) return false;
      if (sub_module == 0x0e) return false;
      if (sub_module == 0x10) return false;
      // going up/down straight stairwells between floors:
      if (sub_module == 0x12) return false;
      if (sub_module == 0x13) return false;
      // warp to another room:
      if (sub_module == 0x15) return false;
      // crystal sequence:
      if (sub_module == 0x18) return false;
      // using mirror:
      if (sub_module == 0x19) return false;

      // in Ganon's room:
      if (dungeon_room == 0x0000) return false;

      return true;
    } else if (module == 0x10) {
      // opening spotlight:
      return true;
    }

    // don't write tilemap changes:
    return false;
  }

  void update_tilemap() {
    // disable tilemap sync based on settings:
    if (settings.DisableTilemap) {
      return;
    }

    bool write_to_vram = false;
    bool team_check = true;

    if (!is_safe_to_write_tilemap()) {
      return;
    }

    // don't write to VRAM when...
    if (module == 0x09) {
      // overworld:
      write_to_vram = true;

      // during screen transition:
      if (sub_module >= 0x01 && sub_module < 0x07) write_to_vram = false;
      // during lost woods transition:
      if (sub_module >= 0x0d && sub_module < 0x16) write_to_vram = false;
      // when coming out of map screen:
      if (sub_module >= 0x20 && sub_module <= 0x22) write_to_vram = false;
      // or during LW/DW transition:
      if (sub_module >= 0x23) write_to_vram = false;

      tilemap.determine_vram_bounds_overworld();

      // allow overworld tilemap changes to sync across teams:
      team_check = false;
    } else if (module == 0x0B) {
      // master sword or zora:
      write_to_vram = true;

      // safety measure here:
      if (sub_module >= 0x01) write_to_vram = false;
      // (sub_module == 0x18 || sub_module == 0x19) for loading master sword area
      // sub_module == 0x1C mosaic in
      // sub_module == 0x24 mosaic out

      tilemap.determine_vram_bounds_overworld();

      // allow overworld tilemap changes to sync across teams:
      team_check = false;
    } else if (module == 0x07) {
      // underworld:
      write_to_vram = true;

      // scrolling between rooms in same supertile:
      if (sub_module == 0x01) write_to_vram = false;
      // loading new supertile:
      if (sub_module == 0x02) write_to_vram = false;
      // up/down through floor:
      if (sub_module == 0x06) write_to_vram = false;
      if (sub_module == 0x07) write_to_vram = false;
      // going up/down spiral stairwells between floors:
      if (sub_module == 0x08) write_to_vram = false;
      if (sub_module == 0x0e) write_to_vram = false;
      if (sub_module == 0x10) write_to_vram = false;
      // going up/down straight stairwells between floors:
      if (sub_module == 0x12) write_to_vram = false;
      if (sub_module == 0x13) write_to_vram = false;
      // warp to another room:
      if (sub_module == 0x15) write_to_vram = false;
      // crystal sequence:
      if (sub_module == 0x18) write_to_vram = false;
      // using mirror:
      if (sub_module == 0x19) write_to_vram = false;

      // in Ganon's room:
      if (dungeon_room == 0x00) write_to_vram = false;

      tilemap.determine_vram_bounds_underworld();
    }

    uint len = players.length();

    // integrate tilemap changes from other players:
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (team_check && (remote.team != team)) continue;
      if (remote.tilemapLocation == 0) continue;
      if (!is_really_in_same_location(remote.location)) {
        continue;
      }
      if (remote.in_sm_for_items) continue;

      if (!locations_equal(actual_location, remote.tilemapLocation)) {
        if (debugRTDSapply) {
          message("rtds: apply from player " + fmtInt(remote.index) + "; skipping as locations do not match: local " + fmtHex(actual_location, 6) + " != " + fmtHex(remote.tilemapLocation, 6));
        }
        continue;
      }

      if (debugRTDSapply) {
        message("rtds: apply from player " + fmtInt(remote.index) + "; " + fmtInt(remote.tilemapRuns.length()) + " runs with VRAM write " + fmtBool(write_to_vram));
      }

      // only apply newer updates:
      if (remote.tilemapTimestamp > tilemapTimestamp) {
        for (uint j = 0; j < remote.tilemapRuns.length(); j++) {
          auto @run = remote.tilemapRuns[j];
          // apply the run to the local tilemap state and update VRAM if applicable on screen:
          tilemap.apply_wram(run);
        }

        // accept this new timestamp as latest:
        tilemapTimestamp = remote.tilemapTimestamp;
      }

      // update VRAM with latest state:
      if (write_to_vram) {
        for (uint j = 0; j < remote.tilemapRuns.length(); j++) {
          auto @run = remote.tilemapRuns[j];
          // apply the run to the local tilemap state and update VRAM if applicable on screen:
          tilemap.apply_vram(run);
        }
      }
    }
  }

  void update_ancillae() {
    if (is_dead()) return;

    uint len = players.length();

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote.ttl <= 0) continue;
      // NOTE: allow bombs to sync across team boundaries for teh lulz
      //if (remote.team != team) continue;
      if (!is_really_in_same_location(remote.location)) continue;
      if (remote.in_sm_for_items) continue;

      //message("[" + fmtInt(i) + "].ancillae.len = " + fmtInt(remote.ancillae.length()));
      if (remote is this) {
        continue;
      }

      uint alen = remote.ancillae.length();
      if (alen > 0) {
        for (uint j = 0; j < alen; j++) {
          auto @an = remote.ancillae[j];
          auto k = an.index;

          if (k < 0x05) {
            // Doesn't work; needs more debugging.
            if (false) {
              // if local player picks up remotely owned ancillae:
              if (ancillae[k].held == 3 && an.held != 3) {
                an.requestOwnership = false;
                ancillae[k].requestOwnership = true;
                ancillaeOwner[k] = index;
              }
            }
          }

          // ownership transfer:
          if (an.requestOwnership) {
            ancillae[k].requestOwnership = false;
            ancillaeOwner[k] = remote.index;
          }

          if (ancillaeOwner[k] == remote.index) {
            an.writeRAM();
            if (an.type == 0) {
              // clear owner if type went to 0:
              ancillaeOwner[k] = -1;
              ancillae[k].requestOwnership = false;
            }
          } else if (ancillaeOwner[k] == -1 && an.type != 0) {
            an.writeRAM();
            ancillaeOwner[k] = remote.index;
            ancillae[k].requestOwnership = false;
          }
        }
      }

      continue;
    }
  }

  // local player owns whatever it spawns:
  void on_object_init(uint32 pc) {
    auto j = cpu::r.x;
    objectOwner[j] = index;
    message("owner["+fmtHex(j,1)+"]="+fmtInt(objectOwner[j]));
  }

  array<int> objectOwner(0x10);
  array<int> objectHeat(0x10);
  void update_objects() {
    // clear ownership of local dead objects:
    for (uint j = 0; j < 0x10; j++) {
      GameSprite l;
      l.readRAM(j);

      if (!l.is_enabled) {
        if (objectHeat[j] > 0) {
          objectHeat[j]--;
          if (objectHeat[j] == 0) {
            objectOwner[j] = -2;
          }
        }

        if (objectOwner[j] == index) {
          objectOwner[j] = -2;
          objectHeat[j] = 32;
        } else if (objectOwner[j] >= 0) {
          // locally destroyed the object:
          objectOwner[j] = index;
          objectHeat[j] = 32;
        }
      }
    }

    // sync in remote objects:
    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (remote.in_sm_for_items) continue;
      if (!is_really_in_same_location(remote.location)) {
        // free ownership of any objects left behind:
        for (uint j = 0; j < 0x10; j++) {
          if (objectOwner[j] == remote.index) {
            objectOwner[j] = -2;
            objectHeat[j] = 32;
          }
        }
        continue;
      }

      for (uint j = 0; j < 0x10; j++) {
        GameSprite r;
        r.readFromBlock(remote.objectsBlock, j);

        if (!r.is_enabled) {
          // release ownership if owned:
          if (objectOwner[j] == remote.index) {
            if (objectHeat[j] == 0) {
              //objectOwner[j] = -2;
              objectHeat[j] = 32;
            }
            r.writeRAM();
          }
          continue;
        }

        // only copy in picked-up objects:
        if (r.type != 0xEC) continue;

        GameSprite l;
        l.readRAM(j);

        if (objectOwner[j] >= 0) {
          // not the owning player?
          if (objectOwner[j] != remote.index) {
            continue;
          }
        } else {
          // wait for the heat to die down:
          if (objectHeat[j] > 0) continue;

          // now this remote player owns it since no one has before:
          objectOwner[j] = remote.index;
          message("owner["+fmtHex(j,1)+"]="+fmtInt(objectOwner[j]));
        }

        // translate it from picked-up to a normal object, else local Link holds it above his head:
        if (r.state == 0x0A) r.state = 0x09;

        r.writeRAM();
      }
    }
  }

  // update's link's tunic colors in his palette:
  void update_palette() {
    // make sure we're in a game module where Link is shown:
    if (module <= 0x05) return;
    if (module >= 0x14 && module <= 0x18) return;
    if (module >= 0x1B) return;

    // read OAM offset where link's sprites start at:
    uint link_oam_start = bus::read_u16(0x7E0352) >> 2;

    uint8 palette = 8;
    for (uint j = link_oam_start; j < link_oam_start + 0xC; j++) {
      auto @sprite = sprs[j];

      // looking for Link body sprites only to grab the palette number:
      if (!sprite.is_enabled) continue;
      //message("chr: " + fmtHex(sprite.chr, 3));
      if ((sprite.chr & 0x0f) >= 0x04) continue;
      if ((sprite.chr & 0xf0) >= 0x20) continue;

      palette = sprite.palette;
      //message("chr="+fmtHex(sprite.chr,3) + " pal="+fmtHex(sprite.palette,1));

      // assign light/dark palette colors:
      auto light = player_color;
      auto dark  = player_color_dark_75;
      for (uint i = 0, m = 1; i < 16; i++, m <<= 1) {
        if ((settings.SyncTunicLightColors & m) == m) {
          auto c = (128 + (palette << 4)) + i;
          auto color = ppu::cgram[c];
          if (color != light) {
            ppu::cgram[c] = light;
          }
        } else if ((settings.SyncTunicDarkColors & m) == m) {
          auto c = (128 + (palette << 4)) + i;
          auto color = ppu::cgram[c];
          if (color != dark) {
            ppu::cgram[c] = dark;
          }
        }
      }
    }
  }

  void update_sm_events() {
    uint len = players.length();

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl < 0) continue;
      if (remote.team != team) continue;

      for (int j = 0; j < 0x54; j++) {
        sm_events[j] = remote.sm_events[j] | sm_events[j];
      }
    }

    for (int i = 0; i < 0x14; i++) {
      bus::write_u8(0x7ED820 + i, sm_events[i]);
    }
    for (int i = 0; i < 0x20; i++) {
      bus::write_u8(0x7ED870 + i, sm_events[i + 0x14]);
    }
    for (int i = 0; i < 0x20; i++) {
      bus::write_u8(0x7ED8B0 + i, sm_events[i + 0x14 + 0x20]);
    }
  }
  
  void update_sm_events_buffer() {
    uint len = players.length();

    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl < 0) continue;
      if (remote.team != team) continue;

      for (int j = 0; j < 0x54; j++) {
        sm_events[j] = remote.sm_events[j] | sm_events[j];
      }
    }

    for (int i = 0; i < 0x14; i++) {
      bus::write_u8(0xa16070 + i, sm_events[i]);
    }
    for (int i = 0; i < 0x20; i++) {
      bus::write_u8(0xa160c0 + i, sm_events[i + 0x14]);
    }
    for (int i = 0; i < 0x20; i++) {
      bus::write_u8(0xa16100 + i, sm_events[i + 0x14 + 0x20]);
    }
  }
  
  void update_games_won(){
    uint len = players.length();
      
    uint8 temp_sm_clear = sm_clear;
    uint8 temp_z3_clear = z3_clear;
      
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl < 0) continue;
      if (remote.team != team) continue;
      if (!remote.in_sm_for_items) continue;

      sm_clear = sm_clear | remote.sm_clear;
      z3_clear = z3_clear | remote.z3_clear;
    }
    
    if (temp_sm_clear != sm_clear){
      notify("Quest Kill Mother Brain Completed");
      bus::write_u8(0xa17402, sm_clear);
    }
    
    if (temp_z3_clear !=z3_clear){
      notify("Quest Kill Gannon Completed");
      bus::write_u8(0xa17506, z3_clear);
    }
  }

  void set_in_sm(bool b) {
    in_sm = b ? 1 : 0;
  }
  
  void get_sm_coords() {
    if (sm_loading_room()) return;
    sm_area = bus::read_u8(0x7E079f);
    sm_x = bus::read_u8(0x7E0AF7);
    sm_y = bus::read_u8(0x7E0AFB);
    sm_sub_x = bus::read_u8(0x7E0AF6);
    sm_sub_y = bus::read_u8(0x7E0AFA);
    sm_room_x = bus::read_u8(0x7E07A1);
    sm_room_y = bus::read_u8(0x7E07A3);
    sm_pose = bus::read_u8(0x7E0A1C);
  }
  
  void get_sm_sprite_data(){
    offsm1 = bus::read_u16(0x7e071f);
    offsm2 = bus::read_u16(0x7e0721);
    bus::read_block_u16(0x7eC180, 0, sm_palette.length(), sm_palette);
  }
  
  bool deselect_tunic_sync_sm;
  void update_sm_palette(){
    sm_palette[1] = player_color_dark_33;
    sm_palette[2] = player_color;
    sm_palette[11] = player_color_dark_33;
    sm_palette[10] = player_color_dark_50;
  }
  
  void update_local_suit(){
    if(!rom.is_alttp()){
    if(settings.SyncTunic){
      bus::write_u16(0x7ec182, player_color_dark_33);
      bus::write_u16(0x7ec184, player_color);
      bus::write_u16(0x7ec196, player_color_dark_33);
      bus::write_u16(0x7ec194, player_color_dark_33);
     } else if(deselect_tunic_sync_sm){
      bus::write_u16(0x7e0a48, 0x06);
     }
  }
  
  deselect_tunic_sync_sm = settings.SyncTunic;
  }

  // detect attacks from us against all nearby players:
  void attack_pvp() {
    pvp_attacks.reserve(playerCount);
    pvp_attacks.resize(0);

    uint8 recoil_timer = 0;
    int8 recoil_dx = 0;
    int8 recoil_dy = 0;
    int8 recoil_dz = 0;

    int sword = action_sword_type;       // 0 = none, 1 = fighter, 2 = master, 3 = tempered, 4 = gold
    int sword_time = action_sword_time;  // 0 = not out, $1..8 = slash, $9..C = stab, $90 = spin

    // determine overlap with other players' hitboxes:
    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;

      // make sure in same general map:
      if (!is_in_same_map(remote.actual_location)) continue;

      // if we are swinging and hit the remote player then stop our attack:
      if (action_hitbox.active) {
        if (remote.hitbox.active && action_hitbox.intersects(remote.hitbox)) {
          if (bus::read_u8(0x7E0372) != 0) {
            // dashing

            //// halt dash:
            //bus::write_u8(0x7E0374, 0);
            //bus::write_u8(0x7E005E, 0);
            //bus::write_u8(0x7E0372, 0);
            //bus::write_u8(0x7E0050, 0);
            //bus::write_u8(0x7E032B, 0);
          } else if (sword_time >= 0x09 && sword_time < 0x80) {
            // stabbing:

            // retract sword:
            action_sword_time = 0;
            bus::write_u8(0x7E003C, 0);
            bus::write_u8(0x7E003A, 0);

            // determine recoil vector from this player:
            int dx = action_hitbox.mx - remote.hitbox.mx;
            int dy = action_hitbox.my - remote.hitbox.my;
            float mag = mathf::sqrt(float(dx * dx + dy * dy));
            if (mag == 0) {
              mag = 1.0f;
            }

            dx = int(dx * 16.0f / mag);
            dy = int(dy * 16.0f / mag);

            // add recoil vector:
            recoil_dx   += dx;
            recoil_dy   += dy;
            recoil_timer = 0x04;
          }
        }

        // if we're attacking remote player with a melee item (hammer, bugnet) or sword:
        if (remote.action_hitbox.active && action_hitbox.intersects(remote.action_hitbox)) {
          // our sword/item intersects their sword/item:

          // determine recoil vector from this player:
          int dx = hitbox.mx - remote.hitbox.mx;
          int dy = hitbox.my - remote.hitbox.my;
          float mag = mathf::sqrt(float(dx * dx + dy * dy));
          if (mag == 0) {
            mag = 1.0f;
          }

          // scale recoil vector with damage amount:
          dx = int(dx * 16.0f / mag);
          dy = int(dy * 16.0f / mag);

          recoil_dx += dx;
          recoil_dy += dy;
          recoil_timer = 0x04;

          // tink sparkles
          //LDA $0FAC : BNE .respulse_spark_already_active
          auto repulse_timer = bus::read_u8(0x7E0FAC);
          if (repulse_timer == 0) {
            //LDA.b #$05 : STA $0FAC
            bus::write_u8(0x7E0FAC, 0x05);

            //LDA $0022 : ADC $0045 : STA $0FAD
            bus::write_u8(0x7E0FAD, (x & 0xFF) + bus::read_u8(0x7E0045));
            //LDA $0020 : ADC $0044 : STA $0FAE
            bus::write_u8(0x7E0FAE, (y & 0xFF) + bus::read_u8(0x7E0044));

            //LDA $EE : STA $0B68
            bus::write_u8(0x7E0B68, action_room_level);
          }

          //; Make "clink" against wall noise
          //JSL Sound_SetSfxPanWithPlayerCoords
          //ORA.b #$05 : STA $012E
          bus::write_u8(0x7E012E, 0x05);  // TODO: OR with 0x40 or 0x80 for left/right panning
        }

        // check our sword/melee hitbox against remote player hitbox:
        if (remote.hitbox.active && action_hitbox.intersects(remote.hitbox)) {
          // sword/melee attack:
          PvPAttack attack;
          attack.player_index = remote.index;
          attack.ancilla_mode = 0;

          // hitboxes intersect; attacking:
          int base_dmg = 4; // fighter sword does 1/2 heart against green armor

          // determine remote player's sword strength:
          attack.sword_time = sword_time;
          attack.melee_item = action_item_used;

          if (action_item_used != 0) {
            // bugnet does fighter-sword damage
            sword = 1;
          }
          // no damage:
          if (sword == 0) {
            // just shove:
            base_dmg = 0;
          }

          int curr_dmg = 0;
          if (sword > 0 && sword_time != 0) {
            // take away the no-sword case to get a bit shift left amount:
            int sword_shl = sword - 1;    // 0 = fighter, 1 = master, 2 = tempered, 3 = gold

            // 8 damage = 1 whole heart
            curr_dmg = base_dmg << sword_shl;

            // scale damage for stabbing/spinning attacks:
            if (sword_time >= 0x09 && sword_time < 0x80) {
              // stabbing:
              curr_dmg >>= 1;
            } else if (sword_time == 0x90) {
              // spinning:
              curr_dmg <<= 1;
            }
          }

          // if using hammer, apply 10 hearts damage regardless of armor:
          if ((action_item_used & 0x02) != 0) {
            curr_dmg = 10 * 8;
          }

          // minimum 1/4 heart damage; let's not mess with 1/8th hearts:
          if (curr_dmg == 1) {
            curr_dmg = 2;
          }

          // determine recoil vector for this player:
          int dx = (remote.hitbox.mx - action_hitbox.mx);
          int dy = (remote.hitbox.my - action_hitbox.my);
          float mag = mathf::sqrt(float(dx * dx + dy * dy));
          if (mag == 0) {
            mag = 1.0f;
          }

          // scale recoil vector with damage amount:
          dx = int(dx * (16 + curr_dmg * 0.25f) / mag);
          dy = int(dy * (16 + curr_dmg * 0.25f) / mag);

          // record attack:
          attack.damage       = curr_dmg;
          attack.recoil_dx    = dx;
          attack.recoil_dy    = dy;
          attack.recoil_dz    = curr_dmg / 2;
          pvp_attacks.insertLast(attack);
        }
      } // sword/melee

      // projectiles:
      auto plen = projectiles.length();
      for (uint j = 0; j < plen; j++) {
        auto @pr = @projectiles[j];

        // calculate damage to remote player with recoil:
        if (!pr.calc_damage(remote, local)) {
          continue;
        }

        // record attack:
        PvPAttack attack;
        attack.player_index = remote.index;
        attack.melee_item   = 0;
        attack.ancilla_mode = pr.mode;
        attack.damage       = pr.damage;
        attack.recoil_dx    = pr.recoil_dx;
        attack.recoil_dy    = pr.recoil_dy;
        attack.recoil_dz    = pr.damage / 2;
        pvp_attacks.insertLast(attack);

        // destroy projectile:
        pr.destroy();
      }
    }

    // apply local recoil:
    if (recoil_dx != 0 || recoil_dy != 0) {
      // recoil timer:
      bus::write_u8(0x7E0046, recoil_timer);
      bus::write_u8(0x7E02C7, recoil_timer);

      // recoil X velocity:
      bus::write_u8(0x7E0028, recoil_dx);
      // recoil Y velocity:
      bus::write_u8(0x7E0027, recoil_dy);
      // recoil Z velocity:
      bus::write_u8(0x7E0029, recoil_dz);
      bus::write_u8(0x7E00C7, recoil_dz);

      // reset Z offset:
      bus::write_u16(0x7E0024, 0);
    }
  }

  void apply_pvp() {
    // invulnerable:
    if (bus::read_u8(0x7E037B) != 0) {
      //dbgData("invlun");
      return;
    }
    if (bus::read_u8(0x7E004D) == 1) {
      //dbgData("recoiling");
      return;
    }

    // end result to apply to local player:
    bool recoil_state = false;
    uint8 actual_dmg = 0;
    uint8 recoil_timer = 0;
    int recoil_dx = 0;
    int recoil_dy = 0;
    int recoil_dz = 0;

    // process PvP attacks against us:
    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;

      // make sure in same general map:
      if (!is_in_same_map(remote.actual_location)) continue;

      uint alen = remote.pvp_attacks.length();
      for (uint a = 0; a < alen; a++) {
        auto @attack = @remote.pvp_attacks[a];
        if (int(attack.player_index) != index) {
          continue;
        }

        // determine our armor strength as a bit shift right amount to reduce damage by:
        int armor = sram[0x35B];  // 0 = green, 1 = blue, 2 = red
        int armor_shr = 0;

        // apply armor reduction for sword attacks:
        if (attack.sword_time != 0) {
          armor_shr = armor;
        }

        // apply armor reduction for arrow attacks:
        if (attack.ancilla_mode == 0x09) {
          armor_shr = armor;
        }

        // reduce damage by armor bit shift right:
        if (enablePvPFriendlyFire || (remote.team != team)) {
          actual_dmg += attack.damage >> armor_shr;
        }
        recoil_state = true;
        recoil_dx   += attack.recoil_dx;
        recoil_dy   += attack.recoil_dy;
        recoil_dz   += attack.recoil_dz;
        recoil_timer = 0x20;

        // TODO: reduce attack TTL so that attacks do not last infinitely long if player disconnects
      }
    }

    // apply damage:
    if (actual_dmg != 0) {
      bus::write_u8(0x7E0373, actual_dmg);
    }

    // apply recoil:
    if (recoil_dx != 0 || recoil_dy != 0 || recoil_dz != 0) {
      if (recoil_state) {
        // recoil state:
        bus::write_u8(0x7E004D, 0x01);
      }

      // recoil timer:
      bus::write_u8(0x7E0046, recoil_timer);
      bus::write_u8(0x7E02C7, recoil_timer);

      // recoil X velocity:
      bus::write_u8(0x7E0028, recoil_dx);
      // recoil Y velocity:
      bus::write_u8(0x7E0027, recoil_dy);
      // recoil Z velocity:
      bus::write_u8(0x7E0029, recoil_dz);
      bus::write_u8(0x7E00C7, recoil_dz);

      // reset Z offset:
      bus::write_u16(0x7E0024, 0);
    }
  }
};
