
class LocalGameState : GameState {
  LocalGameState() {
    //message("tilemap intercept register");
    bus::add_write_interceptor("7e:2000-3fff", 0, bus::WriteInterceptCallback(this.tilemap_written));
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

    // compute aggregated location for Link into a single 24-bit number:
    actual_location =
      uint32(in_dark_world & 1) << 17 |
      uint32(in_dungeon & 1) << 16 |
      uint32(in_dungeon != 0 ? dungeon_room : overworld_room);

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
        message("room from 0x" + fmtHex(last_location, 6) + " to 0x" + fmtHex(location, 6));
        // when moving from overworld to dungeon, track last overworld location:
        if ((last_location & (1 << 16)) < (location & (1 << 16))) {
          last_overworld_x = x;
          last_overworld_y = y;
        }

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

    y = bus::read_u16(0x7E0020);
    x = bus::read_u16(0x7E0022);

    // get screen x,y offset by reading BG2 scroll registers:
    xoffs = int16(bus::read_u16(0x7E00E2)) - int16(bus::read_u16(0x7E011A));
    yoffs = int16(bus::read_u16(0x7E00E8)) - int16(bus::read_u16(0x7E011C));

    fetch_items();

    fetch_sprites();

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

  void fetch_items() {
    // items: (MUST be sorted by offs)
    items.resize(syncableItems.length());
    for (uint i = 0; i < syncableItems.length(); i++) {
      auto @syncable = syncableItems[i];

      auto @item = items[i];
      if (@item == null) {
        @item = @items[i] = SyncedItem();
        item.lastValue = 0;
        item.value = 0;
        item.offs = syncable.offs;
      }

      // record previous frame's value:
      item.lastValue = item.value;

      // read latest value:
      if (syncable.size == 1) {
        item.value = bus::read_u8(0x7EF000 + syncable.offs);
      } else if (syncable.size == 2) {
        item.value = bus::read_u16(0x7EF000 + syncable.offs);
      }
      //if (item.value != item.lastValue) {
      //  message("local[" + fmtHex(item.offs, 3) + "]=" + fmtHex(item.value, 4));
      //}
    }
  }

  void fetch_objects() {
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
    if (is_it_a_bad_time()) {
      return;
    }

    // get link's on-screen coordinates in OAM space:
    int16 rx = int16(x) - xoffs;
    int16 ry = int16(y) - yoffs;

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

      sprite.adjustXY(rx, ry);

      // append the sprite to our array:
      sprites.resize(++numsprites);
      @sprites[numsprites-1] = sprite;
    }

    /*
    // capture effects sprites:
    for (int i = 0x00; i <= 0x7f; i++) {
      // skip already synced Link sprites:
      if ((i >= link_oam_start) && (i <= link_oam_start + 0x0C)) continue;

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
        chr == 0x80 || chr == 0x81 || chr == 0x82 || chr == 0x83 || chr == 0xb7 ||
        // exclusively for spin attack:
        chr == 0x8c || chr == 0x93 || chr == 0xd6 || chr == 0xd7 ||  // chr == 0x92 is also used here
        // sword tink on hard tile when poking:
        chr == 0x90 || chr == 0x92 || chr == 0xb9 ||
        // dash dust
        chr == 0xa9 || chr == 0xcf || chr == 0xdf ||
        // bush leaves
        chr == 0x59 ||
        // item rising from opened chest
        chr == 0x24
      );
      bool weapons = (
        // arrows
        chr == 0x2a || chr == 0x2b || chr == 0x2c || chr == 0x2d ||
        chr == 0x3a || chr == 0x3b || chr == 0x3c || chr == 0x3d ||
        // hookshot
        chr == 0x09 || chr == 0x19 || chr == 0x1a ||
        // boomerang
        chr == 0x26 ||
        // magic powder
        chr == 0x09 || chr == 0x0a ||
        // lantern fire
        chr == 0xe3 || chr == 0xf3 || chr == 0xa4 || chr == 0xa5 || chr == 0xb2 || chr == 0xb3 || chr == 0x9c ||
        // fire rod
        chr == 0x09 || chr == 0x9c || chr == 0x9d || chr == 0x8d || chr == 0x8e || chr == 0xa0 || chr == 0xa2 ||
        chr == 0xa4 || chr == 0xa5 ||
        // ice rod
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0xb6 || chr == 0xb7 || chr == 0x80 || chr == 0x83 ||
        chr == 0xcf || chr == 0xdf ||
        // hammer
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0x91 ||
        // cane of somaria
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0xe9 ||
        // cane of bryna
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0x92 || chr == 0xd6 || chr == 0x8c || chr == 0x93 ||
        chr == 0xd7 || chr == 0xb7 || chr == 0x80 || chr == 0x83 ||
        // magic cape
        chr == 0x86 || chr == 0xa9 || chr == 0x9b ||
        // quake & ether:
        chr == 0x40 || chr == 0x42 || chr == 0x44 || chr == 0x46 || chr == 0x48 || chr == 0x4a || chr == 0x4c || chr == 0x4e ||
        chr == 0x60 || chr == 0x62 || chr == 0x63 || chr == 0x64 || chr == 0x66 || chr == 0x68 || chr == 0x6a ||
        // bombs:
        chr == 0x6e ||
        // 8 count:
        chr == 0x79 ||
        // push block
        chr == 0x0c ||
        // large stone
        chr == 0x4a ||
        // holding pot / bush or small stone or sign
        chr == 0x46 || chr == 0x44 || chr == 0x42 ||
        // shadow underneath pot / bush or small stone
        (i >= 1 && (sprp1.chr == 0x46 || sprp1.chr == 0x44 || sprp1.chr == 0x42) && chr == 0x6c) ||
        // pot shards or stone shards (large and small)
        chr == 0x58 || chr == 0x48
      );
      bool bombs = (
        // explosion:
        chr == 0x84 || chr == 0x86 || chr == 0x88 || chr == 0x8a || chr == 0x8c || chr == 0x9b ||
        // bomb and its shadow:
        (i <= 125 && chr == 0x6e && sprn1.chr == 0x6c && sprn2.chr == 0x6c) ||
        (i >= 1 && sprp1.chr == 0x6e && chr == 0x6c && sprn1.chr == 0x6c) ||
        (i >= 2 && sprp2.chr == 0x6e && sprp1.chr == 0x6c && chr == 0x6c)
      );
      bool follower = (
        chr == 0x20 || chr == 0x22
      );

      // skip OAM sprites that are not related to Link:
      if (!(fx || weapons || bombs || follower)) continue;

      spr.adjustXY(rx, ry);

      // append the sprite to our array:
      sprites.resize(++numsprites);
      @sprites[numsprites-1] = spr;
    }
    */
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

    if ((location == 0x02005b) && (location != last_location)) {
      message("testcase!");
      tilemap_testcase();
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
      message("tilemap[0x" + fmtHex(i, 4) + "]=0x" + fmtHex(tilemap[i], 4));
    } else {
      // low byte:
      tilemap[i] = int32( (uint16(tilemap[i]) & 0xff00) | (int32(value)) );
    }
  }

  void fetch_ancillae() {
    // initialize owner array with -1 for no owner:
    if (ancillaeOwner.length() == 0) {
      ancillaeOwner.resize(0x0A);
      for (uint i = 0; i < 0x0A; i++) {
        ancillaeOwner[i] = -1;
      }
    }

    // initialize array of ancillae:
    if (ancillae.length() == 0) {
      ancillae.resize(0x0A);
      for (uint i = 0; i < 0x0A; i++) {
        @ancillae[i] = @GameAncilla();
      }
    }

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
          ancillaeOwner[i] = local.index;
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

    r.write_u16(last_overworld_x);
    r.write_u16(last_overworld_y);
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

  void serialize_items(array<uint8> &r) {
    r.write_u8(uint8(0x06));

    // items: (MUST be sorted by offs)
    //message("serialize: items="+fmtInt(items.length()));
    r.write_u8(uint8(items.length()));
    for (uint8 i = 0; i < items.length(); i++) {
      auto @item = items[i];
      // NOTE if @item == null a null exception will occur which is better to know about than to ignore.

      // possible offsets are between 0x340 to 0x406 max, so subtract 0x340 to get a single byte between 0x00 and 0xC6
      r.write_u8(uint8(items[i].offs - 0x340));
      r.write_u16(items[i].value);
    }
  }

  void serialize_tilemaps(array<uint8> &r) {
    r.write_u8(uint8(0x07));

    tilemap.serialize(r);
  }

  void serialize_objects(array<uint8> &r) {
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

  void send_packet(array<uint8> &in envelope) {
    if (envelope.length() > 1452) {
      message("packet too big to send! " + fmtInt(envelope.length()));
      return;
    }

    // send packet to server:
    //message("sent " + fmtInt(envelope.length()) + " bytes");
    sock.send(0, envelope.length(), envelope);
  }

  void send() {
    // check if we need to detect our local index:
    if (local.index == -1) {
      // request our index; receive() will take care of the response:
      array<uint8> request = create_envelope(0x00);
      send_packet(request);
    }

    // send main packet:
    {
      // build server envelope:
      array<uint8> envelope = create_envelope(0x01);

      // append local state to remote player:
      serialize_location(envelope);
      serialize_sfx(envelope);
      serialize_sprites(envelope);
      serialize_chr0(envelope);

      send_packet(envelope);
    }

    // send another packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      serialize_items(envelope);
      serialize_objects(envelope);
      serialize_ancillae(envelope);
      serialize_torches(envelope);

      send_packet(envelope);
    }

/*
    // send another packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      // send chr1 to remote player:
      serialize_chr1(envelope);

      send_packet(envelope);
    }
*/

    // send another packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      // append local state to remote player:
      serialize_tilemaps(envelope);

      send_packet(envelope);
    }
  }


  void update_items() {
    if (is_it_a_bad_time()) return;

    // update local player with items from all remote players:
    array<uint16> values;
    values.resize(syncableItems.length());

    // start with our own values:
    for (uint k = 0; k < syncableItems.length(); k++) {
      auto @syncable = syncableItems[k];

      if (syncable.type == 1) {
        // max value:
        values[k] = this.items[k].value;
      } else if (syncable.type == 2) {
        // bitfield:
        values[k] = this.items[k].value;
      }
    }

    // find higher max values among remote players:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;
      if (@remote == @local) continue;
      if (remote.ttl <= 0) {
        continue;
      }

      for (uint j = 0; j < remote.items.length(); j++) {
        uint16 offs = remote.items[j].offs;

        // find a match by offs:
        uint k = 0;
        for (; k < syncableItems.length(); k++) {
          if (offs == syncableItems[k].offs) {
            break;
          }
        }
        if (k == syncableItems.length()) {
          message("["+fmtInt(i)+"] offs="+fmtHex(offs,3)+" not found!");
          continue;
        }

        auto @syncable = syncableItems[k];

        // apply operation to values:
        uint16 value = remote.items[j].value;
        values[k] = syncable.modify(value, values[k]);
      }
    }

    // write back our values:
    for (uint k = 0; k < syncableItems.length(); k++) {
      auto @syncable = syncableItems[k];

      uint16 oldValue = this.items[k].value;
      uint16 newValue = oldValue;

      this.items[k].value = syncable.modify(oldValue, values[k]);

      // write back to SRAM:
      if (this.items[k].value != oldValue) {
        syncable.write(this.items[k].value);
      }
    }
  }

  void update_rooms_sram() {
    // DISABLED
    return;

    for (uint i = 0; i < rooms.length(); i++) {
      // High Byte           Low Byte
      // d d d d b k ck cr   c c c c q q q q
      // c - chest, big key chest, or big key lock. Any combination of them totalling to 6 is valid.
      // q - quadrants visited:
      // k - key or item (such as a 300 rupee gift)
      // 638
      // d - door opened (either unlocked, bombed or other means)
      // r - special rupee tiles, whether they've been obtained or not.
      // b - boss battle won

      //uint8 lo = rooms[i] & 0xff;
      uint8 hi = rooms[i] >> 8;

      // mask off everything but doors opened state:
      hi = hi & 0xF0;

      // OR door state with local WRAM:
      uint8 lhi = bus::read_u8(0x7EF000 + (i << 1) + 1);
      lhi |= hi;
      bus::write_u8(0x7EF000 + (i << 1) + 1, lhi);
    }
  }

  void update_room_current() {
    if (rooms.length() == 0) return;

    // only update dungeon room state:
    auto in_dungeon = bus::read_u8(0x7E001B);
    if (in_dungeon == 0) return;

    auto dungeon_room = bus::read_u16(0x7E00A0);
    if (dungeon_room >= rooms.length()) return;

    // $0400
    // $0401 - Tops four bits: In a given room, each bit corresponds to a door being opened.
    //  If set, it has been opened by some means (bomb, key, etc.)
    // $0402[0x01] - Certainly related to $0403, but contains other information I haven’t looked at yet.
    // $0403[0x01] - Contains room information, such as whether the boss in this room has been defeated.
    //  Loaded on every room load according to map information that is stored as you play the game.
    //  Bit 0: Chest 1
    //  Bit 1: Chest 2
    //  Bit 2: Chest 3
    //  Bit 3: Chest 4
    //  Bit 4: Chest 5
    //  Bit 5: Chest 6 / A second Key. Having 2 keys and 6 chests will cause conflicts here.
    //  Bit 6: A key has been obtained in this room.
    //  Bit 7: Heart Piece has been obtained in this room.

    uint8 hi = rooms[dungeon_room] >> 8;
    // mask off everything but doors opened state:
    hi = hi & 0xF0;

    // OR door state with current room state:
    uint8 lhi = bus::read_u8(0x7E0401);
    lhi |= hi;
    bus::write_u8(0x7E0401, lhi);
  }

  // convert overworld tilemap address to VRAM address:
  uint16 ow_tilemap_to_vram_address(uint16 addr) {
    uint16 vaddr = 0;

    if ((addr & 0x003F) >= 0x0020) {
      vaddr = 0x0400;
    }

    if ((addr & 0x0FFF) >= 0x0800) {
      vaddr += 0x0800;
    }

    vaddr += (addr & 0x001F);
    vaddr += (addr & 0x0780) >> 1;

    return vaddr;
  }

  void tilemap_testcase() {
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
  }

  void update_tilemap() {
    // TODO: sync dungeon tilemap changes
    if (is_in_dungeon()) {
      return;
    }

    if (module == 0x09) {
      // don't fetch tilemap during screen transition:
      if (sub_module >= 0x01 && sub_module < 0x07) {
        return;
      }
      // during LW/DW transition:
      if (sub_module >= 0x23) {
        return;
      }
    }

    // integrate tilemap changes from other players:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is this) continue;

      //
    }

    tilemap.copy_to_wram();

    //// apply change to 0x7E2000 in-memory map:
    //bus::write_u16(0x7E2000 + addr, tile);
    //
    //// TODO: dont update VRAM if area is 1024x1024 instead of normal 512x512. this glitches out.
    //if (bus::read_u16(0x7E0712) > 0) continue;
    //
    //// update VRAM with changes:
    //// convert tilemap address to VRAM address:
    //uint16 vaddr = ow_tilemap_to_vram_address(addr);
    //
    //// look up tile in tile gfx:
    //uint16 a = tile << 3;
    //array <uint16> t(4);
    //t[0] = bus::read_u16(0x0F8000 + a);
    //t[1] = bus::read_u16(0x0F8002 + a);
    //t[2] = bus::read_u16(0x0F8004 + a);
    //t[3] = bus::read_u16(0x0F8006 + a);
    //
    //// update 16x16 tilemap in VRAM:
    //ppu::vram.write_block(vaddr, 0, 2, t);
    //ppu::vram.write_block(vaddr + 0x0020, 2, 2, t);
  }
};
