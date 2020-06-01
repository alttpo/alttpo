
const uint8 script_protocol = 0x06;

// for message rate limiting to prevent noise
uint8 rate_limit = 0x00;

class GameState {
  int ttl;        // time to live for last update packet
  int index = -1; // player index in server's array (local is always -1)

  // graphics data for current frame:
  array<Sprite@> sprites;
  array<array<uint16>> chrs(512);
  // lookup remote chr number to find local chr number mapped to:
  array<uint16> reloc(512);

  // $3D9-$3E4: 6x uint16 characters for player name
  array<uint16> name(6);

  // local: player index last synced objects from:
  uint16 objects_index_source;

  // values copied from RAM:
  uint8  frame;
  uint32 actual_location;
  uint32 location;
  uint32 last_location;

  // screen scroll coordinates relative to top-left of room (BG screen):
  int16 xoffs;
  int16 yoffs;

  uint16 x, y;

  uint8 module;
  uint8 sub_module;
  uint8 sub_sub_module;

  uint8 in_dark_world;
  uint8 in_dungeon;
  uint16 overworld_room;
  uint16 dungeon_room;

  uint16 dungeon;
  uint16 dungeon_entrance;

  uint16 last_overworld_x;
  uint16 last_overworld_y;

  uint8 sfx1;
  uint8 sfx2;

  array<uint8> sram(0x500);

  array<GameSprite@> objects(0x10);
  array<uint8> objectsBlock(0x2A0);

  array<uint16> rooms;

  int numsprites;

  TilemapChanges tilemap;
  array<TilemapRun> tilemapRuns;

  array<int> ancillaeOwner;
  array<GameAncilla@> ancillae;

  array<int> torchOwner(0x10);
  array<uint8> torchTimers(0x10);

  GameState() {
    torchOwner.resize(0x10);
    for (uint t = 0; t < 0x10; t++) {
      torchOwner[t] = -2;
    }
  }

  bool is_in_dark_world() const {
    return (actual_location & 0x020000) == 0x020000;
  }

  bool is_in_dungeon() const {
    return (actual_location & 0x010000) == 0x010000;
  }

  uint8 get_area_size() property {
    return bus::read_u8(0x7E0712) > 0 ? 0x40 : 0x20;
  }

  bool is_it_a_bad_time() const {
    if (module <= 0x05) return true;
    if (module >= 0x14 && module <= 0x18) return true;
    if (module >= 0x1B) return true;

    if (module == 0x0e) {
      if ( sub_module == 0x07 // mode-7 map
           || sub_module == 0x0b // player select
        ) {
        return true;
      }
    }

    return false;
  }

  bool is_dead() const {
    // death handled entirely in module 12:
    if (module == 0x12) {
      return true;
    }

    return false;
  }

  bool is_game_over() const {
    // GAME OVER animation starts at sub_module 06 in module 12:
    if (module == 0x12 && sub_module >= 0x06) {
      return true;
    }

    return false;
  }

  bool can_see(uint32 other_location) const {
    // easiest check:
    if (actual_location == other_location) return true;
    if ((actual_location & 0x010000) == 0x010000 && (other_location & 0x010000) == 0x010000) {
      if ((actual_location & 0xFFFF) == (other_location & 0xFFFF)) return true;
      return false;
    }
    return false;
  }

  bool deserialize(array<uint8> r, int c) {
    if (c >= int(r.length())) return false;

    auto protocol = r[c++];
    //message("game protocol = " + fmtHex(protocol, 2));
    if (protocol != script_protocol) {
      if ((rate_limit++ & 0x7f) == 0) {
        message("bad game protocol " + fmtHex(protocol, 2) + "!");
      }
      return false;
    }

    auto frame = r[c++];
    //message("frame = " + fmtHex(frame, 2));
    if (frame < this.frame && this.frame < 0xff) {
      // stale data:
      // TODO fix check when wrapping around 0xFF to 0x00
      //message("stale frame " + fmtHex(frame, 2) + " vs " + fmtHex(this.frame, 2));
      this.frame = frame;
      return false;
    }
    this.frame = frame;

    int maxc = int(r.length());
    while (c < maxc) {
      auto packetType = r[c++];
      //message("packetType = " + fmtHex(packetType, 2));
      switch (packetType) {
        case 0x01: c = deserialize_location(r, c); break;
        case 0x02: c = deserialize_sfx(r, c); break;
        case 0x03: c = deserialize_sprites(r, c); break;
        case 0x04: c = deserialize_chr0(r, c); break;
        case 0x05: c = deserialize_chr1(r, c); break;
        case 0x06: c = deserialize_sram(r, c); break;
        case 0x07: c = deserialize_tilemaps(r, c); break;
        case 0x08: c = deserialize_objects(r, c); break;
        case 0x09: c = deserialize_ancillae(r, c); break;
        case 0x0A: c = deserialize_torches(r, c); break;
        default:
          message("unknown packet type " + fmtHex(packetType, 2) + " at offs " + fmtHex(c, 3));
          break;
      }
    }

    return true;
  }

  int deserialize_location(array<uint8> r, int c) {
    module = r[c++];
    sub_module = r[c++];
    sub_sub_module = r[c++];

    location = uint32(r[c++])
               | (uint32(r[c++]) << 8)
               | (uint32(r[c++]) << 16)
               | (uint32(r[c++]) << 24);
    actual_location = location;

    x = uint16(r[c++]) | (uint16(r[c++]) << 8);
    y = uint16(r[c++]) | (uint16(r[c++]) << 8);

    dungeon = uint16(r[c++]) | (uint16(r[c++]) << 8);
    dungeon_entrance = uint16(r[c++]) | (uint16(r[c++]) << 8);

    // last overworld coordinate when entered dungeon:
    last_overworld_x = uint16(r[c++]) | (uint16(r[c++]) << 8);
    last_overworld_y = uint16(r[c++]) | (uint16(r[c++]) << 8);

    xoffs = uint16(r[c++]) | (uint16(r[c++]) << 8);
    yoffs = uint16(r[c++]) | (uint16(r[c++]) << 8);

    return c;
  }

  int deserialize_sfx(array<uint8> r, int c) {
    uint8 tx1, tx2;
    tx1 = r[c++];
    tx2 = r[c++];
    if (tx1 != 0) {
      sfx1 = tx1;
    }
    if (tx2 != 0) {
      sfx2 = tx2;
    }

    return c;
  }

  int deserialize_sprites(array<uint8> r, int c) {
    // read in OAM sprites:
    auto numsprites = r[c++];
    sprites.resize(numsprites);
    for (uint i = 0; i < numsprites; i++) {
      @sprites[i] = Sprite();
      c = sprites[i].deserialize(r, c);
    }

    return c;
  }

  int deserialize_chr0(array<uint8> r, int c) {
    // read in chr0 data:
    auto chr_count = r[c++];
    for (uint i = 0; i < chr_count; i++) {
      // read chr0 number:
      auto h = uint16(r[c++]);

      // read chr tile data:
      chrs[h].resize(16);
      for (int k = 0; k < 16; k++) {
        chrs[h][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      }
    }

    return c;
  }

  int deserialize_chr1(array<uint8> r, int c) {
    // read in chr1 data:
    auto chr_count = r[c++];
    for (uint i = 0; i < chr_count; i++) {
      // read chr1 number:
      auto h = uint16(r[c++]) + 0x100;

      // read chr tile data:
      chrs[h].resize(16);
      for (int k = 0; k < 16; k++) {
        chrs[h][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      }
    }

    return c;
  }

  int deserialize_objects(array<uint8> r, int c) {
    objectsBlock.resize(0x2A0);
    for (int i = 0; i < 0x2A0; i++) {
      objectsBlock[i] = r[c++];
    }

    return c;
  }

  int deserialize_ancillae(array<uint8> r, int c) {
    uint8 count = r[c++];
    ancillae.resize(count);
    for (uint i = 0; i < count; i++) {
      if (ancillae[i] is null) {
        @ancillae[i] = @GameAncilla();
      }

      c = ancillae[i].deserialize(r, c);
    }

    return c;
  }

  int deserialize_sram(array<uint8> r, int c) {
    uint16 start = uint16(r[c++]) | (uint16(r[c++]) << 8);
    uint16 count = uint16(r[c++]) | (uint16(r[c++]) << 8);

    for (uint i = 0; i < count; i++) {
      sram[start + i] = r[c++];
    }

    return c;
  }

  int deserialize_tilemaps(array<uint8> r, int c) {
    // read number of runs:
    uint8 runCount = r[c++];
    tilemapRuns.resize(runCount);
    for (uint i = 0; i < runCount; i++) {
      // deserialize the run's parameters:
      auto @run = tilemapRuns[i];
      c = run.deserialize(r, c);
    }

    return c;
  }

  array<uint8> last_torchTimers(0x10);
  int deserialize_torches(array<uint8> r, int c) {
    // copy data from last torch timers received:
    last_torchTimers = torchTimers;

    // reset ownership tracking:
    torchOwner.resize(0x10);
    for (uint i = 0; i < 0x10; i++) {
      torchOwner[i] = -2;
    }

    // deserialize new data:
    uint8 count = r[c++];
    torchTimers.resize(0x10);
    for (uint i = 0; i < count; i++) {
      uint8 t = r[c++];
      torchTimers[t] = r[c++];
      torchOwner[t] = index;
    }

    return c;
  }

  void render(int dx, int dy) {
    for (uint i = 0; i < 512; i++) {
      reloc[i] = 0;
    }

    // disable previously owned OAM sprites:
    for (uint j = 0; j < 128; j++) {
      if (!localFrameState.is_owned_by(j, index)) continue;

      // disable:
      auto oam = ppu::oam[j];
      oam.y = 0xF0;
      @ppu::oam[j] = oam;
    }

    // shadow sprites copy over directly:
    reloc[0x6c] = 0x6c;
    reloc[0x6d] = 0x6d;
    reloc[0x7c] = 0x7c;
    reloc[0x7d] = 0x7d;

    for (uint i = 0; i < sprites.length(); i++) {
      auto sprite = sprites[i];
      auto px = sprite.size == 0 ? 8 : 16;

      // bounds check for OAM sprites:
      if (sprite.x + dx < -px) continue;
      if (sprite.x + dx >= 256) continue;
      if (sprite.y + dy < -px) continue;
      if (sprite.y + dy >= 240) continue;

      // determine which OAM sprite slot is free around the desired index:
      uint j;
      for (j = sprite.index; j < sprite.index + 128; j++) {
        if (!ppu::oam[j & 127].is_enabled) break;
      }
      // no more free slots?
      if (j == sprite.index + 128) return;

      // start building a new OAM sprite:
      j = j & 127;
      auto oam = ppu::oam[j];
      oam.x = uint16(sprite.x + dx);
      oam.y = sprite.y + 1 + dy;
      oam.hflip = sprite.hflip;
      oam.vflip = sprite.vflip;
      oam.priority = sprite.priority;
      oam.palette = sprite.palette;
      oam.size = sprite.size;

      // find free character(s) for replacement:
      if (sprite.size == 0) {
        // 8x8 sprite:
        if (reloc[sprite.chr] == 0) { // assumes use of chr=0 is invalid, which it is since it is for local Link.
          for (uint k = 0x100; k < 0x200; k++) {
            // skip chr if in-use:
            if (localFrameState.chr[k]) continue;

            oam.character = k;
            localFrameState.chr[k] = true;
            reloc[sprite.chr] = k;

            if (chrs[sprite.chr].length() == 0) {
              message("remote CHR="+fmtHex(sprite.chr,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k), chrs[sprite.chr]);
            }
            break;
          }
        } else {
          // use existing chr:
          oam.character = reloc[sprite.chr];
        }
      } else {
        // 16x16 sprite:
        if (reloc[sprite.chr] == 0) { // assumes use of chr=0 is invalid, which it is since it is for local Link.
          for (uint k = 0x100; k < 0x1EF; k++) {
            // skip chr if in-use:
            if (localFrameState.chr[k + 0x00]) continue;
            if (localFrameState.chr[k + 0x01]) continue;
            if (localFrameState.chr[k + 0x10]) continue;
            if (localFrameState.chr[k + 0x11]) continue;

            oam.character = k;
            localFrameState.chr[k + 0x00] = true;
            localFrameState.chr[k + 0x01] = true;
            localFrameState.chr[k + 0x10] = true;
            localFrameState.chr[k + 0x11] = true;
            reloc[sprite.chr + 0x00] = k + 0x00;
            reloc[sprite.chr + 0x01] = k + 0x01;
            reloc[sprite.chr + 0x10] = k + 0x10;
            reloc[sprite.chr + 0x11] = k + 0x11;
            if (chrs[sprite.chr + 0x00].length() == 0) {
              message("remote CHR="+fmtHex(sprite.chr + 0x00,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x00), chrs[sprite.chr + 0x00]);
            }
            if (chrs[sprite.chr + 0x01].length() == 0) {
              message("remote CHR="+fmtHex(sprite.chr + 0x01,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x01), chrs[sprite.chr + 0x01]);
            }
            if (chrs[sprite.chr + 0x10].length() == 0) {
              message("remote CHR="+fmtHex(sprite.chr + 0x10,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x10), chrs[sprite.chr + 0x10]);
            }
            if (chrs[sprite.chr + 0x11].length() == 0) {
              message("remote CHR="+fmtHex(sprite.chr + 0x11,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x11), chrs[sprite.chr + 0x11]);
            }
            break;
          }
        } else {
          // use existing chrs:
          oam.character = reloc[sprite.chr];
        }
      }

      // update sprite in OAM memory:
      localFrameState.claim_owner(j, index);
      @ppu::oam[j] = oam;
    }
  }

  uint8 adjust_sfx_pan(uint8 sfx) {
    // Try to infer the sound's relative(ish) position from the remote player
    // based on the encoded pan information from their screen:
    int sx = x;
    if ((sfx & 0x80) == 0x80) sx -= 40;
    else if ((sfx & 0x40) == 0x40) sx += 40;

    // clear original panning from remote player:
    sfx = sfx & 0x3F;
    // adjust pan based on sound's relative position to local player:
    if (sx - int(local.x) <= -40) sfx |= 0x80;
    else if (sx - int(local.x) >= 40) sfx |= 0x40;

    return sfx;
  }

  void play_sfx() {
    if (sfx1 != 0) {
      //message("sfx1 = " + fmtHex(sfx1,2));
      uint8 lfx1 = bus::read_u8(0x7E012E);
      if (lfx1 == 0) {
        uint8 sfx = adjust_sfx_pan(sfx1);
        bus::write_u8(0x7E012E, sfx);
        sfx1 = 0;
      }
    }

    if (sfx2 != 0) {
      //message("sfx2 = " + fmtHex(sfx2,2));
      uint8 lfx2 = bus::read_u8(0x7E012F);
      if (lfx2 == 0) {
        uint8 sfx = adjust_sfx_pan(sfx2);
        bus::write_u8(0x7E012F, sfx);
        sfx2 = 0;
      }
    }
  }

};
