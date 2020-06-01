
class LocalGameState : GameState {
  LocalGameState() {
    ancillaeOwner.resize(0x0A);
    for (uint i = 0; i < 0x0A; i++) {
      ancillaeOwner[i] = -1;
    }

    ancillae.resize(0x0A);
    for (uint i = 0; i < 0x0A; i++) {
      @ancillae[i] = @GameAncilla();
    }
  }

  bool registered = false;
  void register() {
    if (registered) return;
    if (rom is null) return;

    if (enableObjectSync) {
      cpu::register_pc_interceptor(rom.fn_sprite_init, cpu::PCInterceptCallback(this.on_object_init));
    }

    //message("tilemap intercept register");
    bus::add_write_interceptor("7e:2000-3fff", 0, bus::WriteInterceptCallback(this.tilemap_written));

    registered = true;
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
    //    sub_module = 0x00 normal gameplay in dungeon
    //               = 0x01 going through door
    //               = 0x03 triggered a star tile to change floor hole configuration
    //               = 0x05 initializing room? / locked doors?
    //               = 0x07 falling down hole in floor
    //               = 0x0e going up/down stairs
    //               = 0x0f entering dungeon first time (or from mirror)
    //               = 0x16 when orange/blue barrier blocks transition
    //               = 0x19 when using mirror
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

  void fetch() {
    // read frame counter (increments from 00 to FF and wraps around):
    frame = bus::read_u8(0x7E001A);

    // fetch various room indices and flags about where exactly Link currently is:
    in_dark_world = bus::read_u8(0x7E0FFF);
    in_dungeon = bus::read_u8(0x7E001B);
    overworld_room = bus::read_u16(0x7E008A);
    dungeon_room = bus::read_u16(0x7E00A0);

    dungeon = bus::read_u16(0x7E040C);
    dungeon_entrance = bus::read_u16(0x7E010E);

    // compute aggregated location for Link into a single 24-bit number:
    actual_location =
      uint32(in_dark_world & 1) << 17 |
      uint32(in_dungeon & 1) << 16 |
      uint32(in_dungeon != 0 ? dungeon_room : overworld_room);

    // last overworld x,y coords are cached in WRAM; only used for "simple" exits from caves:
    last_overworld_x = bus::read_u16(0x7EC14A);
    last_overworld_y = bus::read_u16(0x7EC148);

    if (is_it_a_bad_time()) {
      if (!can_sample_location()) {
        x = 0xFFFF;
        y = 0xFFFF;
      }
      return;
    }

    // $7E0410 = OW screen transitioning directional
    //ow_screen_transition = bus::read_u8(0x7E0410);

    // Don't update location until screen transition is complete:
    if (can_sample_location()) {
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

    // TODO: read player name from SRAM
    //name = bus::read_block_u8(0x7EF3D9);
    // TODO: copy player name to Settings window
    // TODO: allow settings window to rename player and write back to SRAM

    x = bus::read_u16(0x7E0022);
    y = bus::read_u16(0x7E0020);

    // get screen x,y offset by reading BG2 scroll registers:
    xoffs = int16(bus::read_u16(0x7E00E2)) - int16(bus::read_u16(0x7E011A));
    yoffs = int16(bus::read_u16(0x7E00E8)) - int16(bus::read_u16(0x7E011C));

    fetch_sprites();

    fetch_sram();

    fetch_objects();

    fetch_ancillae();

    fetch_tilemap_changes();

    fetch_rooms();

    fetch_torches();
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
    if (is_frozen()) return;

    bus::read_block_u8(0x7EF000, 0, 0x500, sram);
  }

  void fetch_objects() {
    if (is_dead()) return;

    // $7E0D00 - $7E0FA0
    uint i = 0;

    bus::read_block_u8(0x7E0D00, 0, 0x2A0, objectsBlock);
    for (i = 0; i < 0x10; i++) {
      auto @en = @objects[i];
      if (@en is null) {
        @en = @objects[i] = GameSprite();
      }
      // copy in facts about each enemy from the large block of WRAM:
      objects[i].readFromBlock(objectsBlock, i);
    }
  }

  void fetch_rooms() {
    if (is_dead()) return;

    // SRAM copy at $7EF000 - $7EF24F
    // room data live in WRAM at $0400,$0401
    // $0403 = 6 chests, key, heart piece

    // BUGS: encountered one-way door effect in fairy cave 0x010008
    // disabling room door sync for now.

    //rooms.resize(0x128);
    //bus::read_block_u16(0x7EF000, 0, 0x128, rooms);
  }

  void fetch_sprites() {
    numsprites = 0;
    sprites.resize(0);
    if (is_it_a_bad_time()) return;

    sprites.reserve(64);

    // read OAM offset where link's sprites start at:
    int link_oam_start = bus::read_u16(0x7E0352) >> 2;
    //message(fmtInt(link_oam_start));

    // read in relevant sprites from OAM and VRAM:
    sprites.reserve(128);

    // start from reserved region for Link (either at 0x64 or ):
    for (int j = 0; j < 0x0C; j++) {
      auto i = (link_oam_start + j) & 0x7F;

      // fetch ALTTP's copy of the OAM sprite data from WRAM:
      Sprite sprite;
      sprite.decodeOAMTable(i);

      // skip OAM sprite if not enabled (X, Y coords are out of display range):
      if (!sprite.is_enabled) continue;

      //message("[" + fmtInt(sprite.index) + "] " + fmtInt(sprite.x) + "," + fmtInt(sprite.y) + "=" + fmtInt(sprite.chr));

      // append the sprite to our array:
      sprites.resize(++numsprites);
      @sprites[numsprites-1] = sprite;
    }

    // don't sync OAM beyond link's body during or after GAME OVER animation after death:
    if (is_dead()) return;

    // capture effects sprites:
    for (int i = 0x00; i <= 0x7f; i++) {
      // skip already synced Link sprites:
      if ((i >= link_oam_start) && (i < link_oam_start + 0x0C)) continue;

      // fetch ALTTP's copy of the OAM sprite data from WRAM:
      Sprite spr, sprp1, sprp2, sprn1, sprn2;
      // current sprite:
      spr.decodeOAMTable(i);
      // prev 2 sprites:
      if (i >= 1) {
        sprp1.decodeOAMTable(i - 1);
      }
      if (i >= 2) {
        sprp2.decodeOAMTable(i - 2);
      }
      // next 2 sprites:
      if (i <= 0x7E) {
        sprn1.decodeOAMTable(i + 1);
      }
      if (i <= 0x7D) {
        sprn2.decodeOAMTable(i + 2);
      }

      // skip OAM sprite if not enabled (X, Y coords are out of display range):
      if (!spr.is_enabled) continue;

      auto chr = spr.chr;
      if (chr >= 0x100) continue;

      bool fx = (
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
      );
      bool weapons = (
        // boomerang
           chr == 0x26
        // magic powder
        || chr == 0x09 || chr == 0x0a
        // magic cape
        || chr == 0x86 || chr == 0xa9 || chr == 0x9b
        // quake & ether:
        || chr == 0x40 || chr == 0x42 || chr == 0x44 || chr == 0x46 || chr == 0x48 || chr == 0x4a || chr == 0x4c || chr == 0x4e
        || chr == 0x60 || chr == 0x62 || chr == 0x63 || chr == 0x64 || chr == 0x66 || chr == 0x68 || chr == 0x6a
        // push block
        || chr == 0x0c
        // large stone
        || chr == 0x4a
        // holding pot / bush or small stone or sign
        || chr == 0x46 || chr == 0x44 || chr == 0x42
        // shadow underneath pot / bush or small stone
        || (chr == 0x6c && (sprp1.chr == 0x46 || sprp1.chr == 0x44 || sprp1.chr == 0x42))
      );
      bool follower = (
           chr == 0x20 || chr == 0x22
        // water under follower:
        || (chr == 0xd8 && (sprn1.chr == 0xd8 || sprn1.chr == 0x22 || sprn1.chr == 0x20))
        || (chr == 0xd9 && (sprn1.chr == 0xd9 || sprn1.chr == 0x22 || sprn1.chr == 0x20))
        || (chr == 0xda && (sprn1.chr == 0xda || sprn1.chr == 0x22 || sprn1.chr == 0x20))
        // grass under follower:
        || (chr == 0xc8 && (sprn1.chr == 0xc8 || sprn1.chr == 0x22 || sprn1.chr == 0x20))
        || (chr == 0xc9 && (sprn1.chr == 0xc9 || sprn1.chr == 0x22 || sprn1.chr == 0x20))
        || (chr == 0xca && (sprn1.chr == 0xca || sprn1.chr == 0x22 || sprn1.chr == 0x20))
      );

      // skip OAM sprites that are not related to Link:
      if (!(fx || weapons || follower)) continue;

      // append the sprite to our array:
      sprites.resize(++numsprites);
      @sprites[numsprites-1] = spr;
    }
  }

  void capture_sprites_vram() {
    for (int i = 0; i < numsprites; i++) {
      auto @spr = @sprites[i];
      capture_sprite(spr);
    }
  }

  void capture_sprite(Sprite &sprite) {
    //message("capture_sprite " + fmtInt(sprite.index));
    // load character(s) from VRAM:
    if (sprite.size == 0) {
      // 8x8 sprite:
      //message("capture  x8 CHR=" + fmtHex(sprite.chr, 3));
      if (chrs[sprite.chr].length() == 0) {
        chrs[sprite.chr].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr), 0, 16, chrs[sprite.chr]);
      }
    } else {
      // 16x16 sprite:
      //message("capture x16 CHR=" + fmtHex(sprite.chr, 3));
      if (chrs[sprite.chr + 0x00].length() == 0) {
        chrs[sprite.chr + 0x00].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x00), 0, 16, chrs[sprite.chr + 0x00]);
      }
      if (chrs[sprite.chr + 0x01].length() == 0) {
        chrs[sprite.chr + 0x01].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x01), 0, 16, chrs[sprite.chr + 0x01]);
      }
      if (chrs[sprite.chr + 0x10].length() == 0) {
        chrs[sprite.chr + 0x10].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x10), 0, 16, chrs[sprite.chr + 0x10]);
      }
      if (chrs[sprite.chr + 0x11].length() == 0) {
        chrs[sprite.chr + 0x11].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x11), 0, 16, chrs[sprite.chr + 0x11]);
      }
    }
  }

  void fetch_tilemap_changes() {
    if (is_dead()) return;

    bool clear = false;
    /*
    if (module == 0x09 && sub_module == 0x05) {
      // scrolling overworld areas:
      clear = true;
    } else
    */
    if (location != last_location) {
      // generic location changed event:
      clear = true;
    }

    if (!clear) return;

    // clear tilemap to -1 when changing rooms:
    tilemap.reset(area_size);

    if (actual_location != last_location) {
      //tilemap_testcase();
    }
  }

  // intercept 8-bit writes to a 16-bit array in WRAM at $7e2000:
  void tilemap_written(uint32 addr, uint8 value) {
    if (is_it_a_bad_time()) {
      return;
    }

    // overworld only for the moment:
    if (module != 0x09) {
      return;
    }

    // don't fetch tilemap during lost woods transition:
    if (sub_module >= 0x0d && sub_module < 0x16) return;
    // don't fetch tilemap during screen transition:
    if (sub_module >= 0x01 && sub_module < 0x07) return;
    // or during LW/DW transition:
    if (sub_module >= 0x23) return;

    // figure out offset from $7e2000:
    addr -= 0x7e2000;

    // mask off low bit of offset and divide by 2 for 16-bit index:
    uint i = (addr & 0x1ffe) >> 1;

    // apply the write to either side of the uint16 (upcast to int32):
    if ((addr & 1) == 1) {
      // high byte:
      tilemap[i] = int32( (uint16(tilemap[i]) & 0x00ff) | (int32(value) << 8) );
      //message("tilemap[0x" + fmtHex(i, 4) + "]=0x" + fmtHex(tilemap[i], 4));
    } else {
      // low byte:
      tilemap[i] = int32( (uint16(tilemap[i]) & 0xff00) | (int32(value)) );
    }
  }

  void fetch_ancillae() {
    if (is_dead()) return;

    // update ancillae array from WRAM:
    for (uint i = 0; i < 0x0A; i++) {
      ancillae[i].readRAM(i);

      // Update ownership:
      if (ancillaeOwner[i] == index) {
        ancillae[i].requestOwnership = false;
        if (ancillae[i].type == 0) {
          ancillaeOwner[i] = -2;
        }
      } else if (ancillaeOwner[i] == -1) {
        if (ancillae[i].type != 0) {
          ancillaeOwner[i] = index;
          ancillae[i].requestOwnership = false;
        }
      } else if (ancillaeOwner[i] == -2) {
        ancillaeOwner[i] = -1;
        ancillae[i].requestOwnership = false;
      }
    }
  }

  void fetch_torches() {
    if (!is_in_dungeon()) return;
    if (is_dead()) return;

    torchTimers.resize(0x10);
    bus::read_block_u8(0x7E04F0, 0, 0x10, torchTimers);
  }

  bool is_torch_lit(uint8 t) {
    if (!is_in_dungeon()) return false;
    if (t >= 0x10) return false;

    auto idx = (t << 1) + bus::read_u16(0x7E0478);
    auto tm = bus::read_u16(0x7E0540 + idx);
    return (tm & 0x8000) == 0x8000;
  }

  void serialize_location(array<uint8> &r) {
    r.write_u8(uint8(0x01));

    r.write_u8(module);
    r.write_u8(sub_module);
    r.write_u8(sub_sub_module);

    r.write_u32(location);

    r.write_u16(x);
    r.write_u16(y);

    r.write_u16(dungeon);
    r.write_u16(dungeon_entrance);

    r.write_u16(last_overworld_x);
    r.write_u16(last_overworld_y);

    r.write_u16(xoffs);
    r.write_u16(yoffs);
  }

  void serialize_sfx(array<uint8> &r) {
    r.write_u8(uint8(0x02));

    r.write_u8(sfx1);
    r.write_u8(sfx2);
  }

  void serialize_sprites(array<uint8> &r) {
    r.write_u8(uint8(0x03));

    r.write_u8(uint8(sprites.length()));

    //message("serialize: numsprites = " + fmtInt(sprites.length()));
    // sort 16x16 sprites first so that 8x8 can fit within them if needed (fixes shadows under thrown items):
    for (uint i = 0; i < sprites.length(); i++) {
      if (sprites[i].size == 0) continue;
      sprites[i].serialize(r);
    }
    for (uint i = 0; i < sprites.length(); i++) {
      if (sprites[i].size != 0) continue;
      sprites[i].serialize(r);
    }
  }

  void serialize_chr0(array<uint8> &r) {
    // how many distinct characters:
    uint16 chr_count = 0;
    for (uint16 i = 0; i < 0x100; i++) {
      if (chrs[i].length() == 0) continue;
      ++chr_count;
    }

    //message("serialize: chr0="+fmtInt(chr_count));
    r.write_u8(uint8(0x04));

    // emit how many chrs:
    r.write_u8(uint8(chr_count));
    for (uint16 i = 0; i < 0x100; ++i) {
      if (chrs[i].length() == 0) continue;

      // which chr is it:
      r.write_u8(uint8(i));
      // emit the tile data:
      r.write_arr(chrs[i]);

      // clear the chr tile data for next frame:
      chrs[i].resize(0);
    }
  }

  void serialize_chr1(array<uint8> &r) {
    // how many distinct characters:
    uint16 chr_count = 0;
    for (uint16 i = 0x100; i < 0x200; i++) {
      if (chrs[i].length() == 0) continue;
      ++chr_count;
    }

    //message("serialize: chr1="+fmtInt(chr_count));
    r.write_u8(uint8(0x05));

    // emit how many chrs:
    r.write_u8(uint8(chr_count));
    for (uint16 i = 0x100; i < 0x200; ++i) {
      if (chrs[i].length() == 0) continue;

      // which chr is it:
      r.write_u8(uint8(i - 0x100));
      // emit the tile data:
      r.write_arr(chrs[i]);

      // clear the chr tile data for next frame:
      chrs[i].resize(0);
    }
  }

  void serialize_sram(array<uint8> &r, uint16 start, uint16 endExclusive) {
    r.write_u8(uint8(0x06));

    r.write_u16(start);
    uint16 count = uint16(endExclusive - start);
    r.write_u16(count);
    for (uint i = 0; i < count; i++) {
      r.write_u8(sram[start + i]);
    }
  }

  void serialize_tilemaps(array<uint8> &r) {
    r.write_u8(uint8(0x07));

    tilemap.serialize(r);
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

  array<uint8> @create_envelope(uint8 kind) {
    array<uint8> @envelope = {};
    envelope.reserve(1452);

    // server envelope:
    {
      // header:
      envelope.write_u16(uint16(25887));
      // server protocol 2:
      envelope.write_u8(uint8(0x02));
      // group name: (20 bytes exactly)
      envelope.write_str(settings.Group);
      // message kind:
      envelope.write_u8(kind);
      // what we think our index is:
      envelope.write_u16(uint16(index));
    }

    // script protocol:
    envelope.write_u8(uint8(script_protocol));

    // protocol starts with frame number to correlate them together:
    envelope.write_u8(frame);

    return envelope;
  }

  array<uint16> maxSize(5);

  uint send_packet(array<uint8> &in envelope, uint p) {
    if (envelope.length() > 1452) {
      message("packet too big to send! " + fmtInt(envelope.length()));
      return p;
    }

    // send packet to server:
    //message("sent " + fmtInt(envelope.length()) + " bytes");
    sock.send(0, envelope.length(), envelope);

    // stats on max packet size per 128 frames:
    if (debugNet) {
      if (envelope.length() > maxSize[p]) {
        maxSize[p] = envelope.length();
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

    // send main packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      serialize_location(envelope);
      serialize_sfx(envelope);

      serialize_ancillae(envelope);
      serialize_objects(envelope);

      p = send_packet(envelope, p);
    }

    // send another packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      serialize_sprites(envelope);
      serialize_chr0(envelope);
      //serialize_chr1(envelope);

      p = send_packet(envelope, p);
    }

    // send packet every other frame:
    if ((frame & 1) == 0) {
      array<uint8> envelope = create_envelope(0x01);

      serialize_torches(envelope);

      serialize_tilemaps(envelope);

      p = send_packet(envelope, p);
    }

    // send SRAM updates once every 16 frames:
    if ((frame & 15) == 0) {
      array<uint8> envelope = create_envelope(0x01);

      serialize_sram(envelope, 0x340, 0x390); // items earned
      serialize_sram(envelope, 0x3C5, 0x439); // progress made

      // and include dungeon and overworld sync alternating:
      if ((frame & 31) == 0) {
        serialize_sram(envelope,   0x0, 0x250); // dungeon rooms
      }
      if ((frame & 31) == 15) {
        serialize_sram(envelope, 0x280, 0x340); // overworld events; heart containers, overlays
      }

      p = send_packet(envelope, p);
    }
  }


  void update_items() {
    if (is_it_a_bad_time()) return;
    // don't fetch latest SRAM when Link is frozen e.g. opening item chest for heart piece -> heart container:
    if (is_frozen()) return;

    auto @syncables = rom.syncables;
    for (uint k = 0; k < syncables.length(); k++) {
      auto @syncable = syncables[k];

      // start the sync process for each syncable item in SRAM:
      syncable.start();

      // apply remote values from all other active players:
      for (uint i = 0; i < players.length(); i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is this) continue;
        if (remote.ttl <= 0) continue;

        // apply the remote values:
        syncable.apply(remote);
      }

      // write back any new updates:
      syncable.finish();
    }
  }

  void update_overworld() {
    if (is_it_a_bad_time()) return;

    // SRAM [$280..$33f] overworld events:
    for (uint a = 0; a < 0xC0; a++) {
      // create temporary syncable item for each overworld area using bitwise OR operations (type=2) to accumulate latest state:
      SyncableItem area(0x280 + a, 1, 2);

      // read current state from SRAM:
      area.start();

      for (uint i = 0; i < players.length(); i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is this) continue;
        if (remote.ttl <= 0) continue;

        area.apply(remote);
      }

      // write new state to SRAM:
      area.finish();
    }
  }

  void update_rooms() {
    uint16 room_count = 0x128;  // 0x250 / 2
    for (uint a = 0; a < room_count; a++) {
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

      // create temporary syncable item for each room (word; size=2) using bitwise OR operations (type=2) to accumulate latest state:
      SyncableItem area(a << 1, 2, 2);

      // read current state from SRAM:
      area.start();

      for (uint i = 0; i < players.length(); i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is this) continue;
        if (remote.ttl <= 0) continue;

        area.apply(remote);
      }

      // write new state to SRAM:
      area.finish();
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

  void update_tilemap() {
    // TODO: sync dungeon tilemap changes
    if (module != 0x09) return;

    // don't write during LW/DW transition:
    if (sub_module >= 0x23) return;

    // integrate tilemap changes from other players:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;
      if (remote.ttl <= 0) continue;
      if (!can_see(remote.location)) continue;

      // TODO: may need to order updates by timestamp - e.g. sanctuary doors opening animation
      for (uint j = 0; j < remote.tilemapRuns.length(); j++) {
        auto @run = remote.tilemapRuns[j];
        // apply the run to the local tilemap state:
        tilemap.apply(run);
      }
    }

    // don't write to vram during area transition:
    bool write_to_vram = true;
    if (sub_module > 0x00 && sub_module < 0x07) write_to_vram = false;
    tilemap.copy_to_wram(write_to_vram);
  }

  void update_ancillae() {
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote.ttl <= 0) continue;
      if (!can_see(remote.location)) continue;

      //message("[" + fmtInt(i) + "].ancillae.len = " + fmtInt(remote.ancillae.length()));
      if (remote is this) {
        continue;
      }

      if (remote.ancillae.length() > 0) {
        for (uint j = 0; j < remote.ancillae.length(); j++) {
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
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (!can_see(remote.location)) {
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

};
