
const uint8 script_protocol = 0x11;

// for message rate limiting to prevent noise
uint8 rate_limit = 0x00;

bool locations_equal(uint32 a, uint32 b) {
  // easiest check:
  if (a == b) return true;
  if ((a & 0x010000) == 0x010000 && (b & 0x010000) == 0x010000) {
    if ((a & 0xFFFF) == (b & 0xFFFF)) return true;
    return false;
  }
  return false;
}

const uint16 small_keys_min_offs = 0xF37C;
const uint16 small_keys_max_offs = 0xF38C;

class GameState {
  int ttl;        // time to live for last update packet
  int index = -1; // player index in server's array (local is always -1)
  uint8 _team = 0; // team number to sync with

  // graphics data for current frame:
  array<Sprite@> sprites;
  array<array<uint16>> chrs(512);
  array<uint16> palettes(8 * 16);
  // lookup remote chr number to find local chr number mapped to:
  array<uint16> reloc(512);

  // $3D9-$3E4: 6x uint16 characters for player name

  string _name = "";
  string name {
    get { return _name; }
    set {
      _name = value.strip();
      _namePadded = padTo(value, 20);
    }
  }

  string _namePadded = "                    ";  // 20 spaces
  string namePadded {
    get { return _namePadded; }
    set {
      _name = value.strip();
      if (value.length() == 20) {
        _namePadded = value;
      } else {
        _namePadded = padTo(value, 20);
      }
    }
  }

  uint8 team {
    get { return _team; }
    set {
      _team = value;
      dbgData("[{0}] team = {1}".format({index, _team}));
    }
  }

  // local: player index last synced objects from:
  uint16 objects_index_source;

  // values copied from RAM:
  uint8  frame;
  uint32 actual_location;
  uint32 last_actual_location;
  uint32 location;
  uint32 last_location;

  // screen scroll coordinates relative to top-left of room (BG screen):
  int16 xoffs;
  int16 yoffs;

  uint16 x, y;
  
  //coordinates for super metroid game
  uint8 sm_area, sm_sub_x, sm_sub_y, sm_x, sm_y;
  uint8 in_sm;

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

  private uint16 _player_color;
  uint16 player_color {
    get { return _player_color; }
    set {
      _player_color = value;
      calculate_player_color_dark();
    }
  }

  uint16 player_color_dark_75;
  uint16 player_color_dark_50;
  uint16 player_color_dark_33;

  uint8 sfx1;
  uint8 sfx2;

  uint8 sfx1_ttl = 0;
  uint8 sfx2_ttl = 0;

  array<uint8> sram(0x500);
  array<uint8> sram_buffer(0x500);
  bool in_sm_for_items;

  array<uint8> sm_events(0x50);

  array<GameSprite@> objects(0x10);
  array<uint8> objectsBlock(0x2A0);

  SyncableByte@ crystal = @SyncableByte(0xC172);
  array<SyncableByte@> small_keys(0x10);

  int numsprites;

  TilemapChanges tilemap;
  array<TilemapRun> tilemapRuns;
  uint32 tilemapTimestamp;
  uint32 tilemapLocation;

  array<int> ancillaeOwner;
  array<GameAncilla@> ancillae;

  array<int> torchOwner(0x10);
  array<uint8> torchTimers(0x10);

  Hitbox hitbox;

  Hitbox action_hitbox;
  uint8 action_sword_time;    //     $3C = sword out time / spin attack
  uint8 action_sword_type;    // $7EF359 = sword type
  uint8 action_item_used;     //   $0301 = item in hand (bitfield, one bit at a time)
  uint8 action_room_level;    //     $EE = level in room

  array<PvPAttack> pvp_attacks;

  GameState() {
    torchOwner.resize(0x10);
    for (uint t = 0; t < 0x10; t++) {
      torchOwner[t] = -2;
    }
  }

  void reset() {
    dbgData("local.reset()");

    index = -1;
    team = 0;

    frame = 0;
    actual_location = 0;
    last_actual_location = 0;
    location = 0;
    last_location = 0;

    // screen scroll coordinates relative to top-left of room (BG screen):
    xoffs = 0;
    yoffs = 0;

    x = 0;
    y = 0;

    module = 0;
    sub_module = 0;
    sub_sub_module = 0;

    in_dark_world = 0;
    in_dungeon = 0;
    overworld_room = 0;
    dungeon_room = 0;

    dungeon = 0;
    dungeon_entrance = 0;

    last_overworld_x = 0;
    last_overworld_y = 0;

    sfx1 = 0;
    sfx2 = 0;

    sfx1_ttl = 0;
    sfx2_ttl = 0;

    for (uint i = 0; i < 0x500; i++) {
      sram[i] = 0;
      sram_buffer[i] = 0;
    }

    for (uint i = 0; i < 0x50; i++) {
      sm_events[i] = 0;
    }

    //array<GameSprite@> objects(0x10);

    for (uint i = 0; i < 0x2A0; i++) {
      objectsBlock[i] = 0;
    }

    crystal.reset();

    numsprites = 0;

    tilemap.reset(0x40);
    tilemapRuns.resize(0);
    tilemapTimestamp = 0;
    tilemapLocation = 0;

    ancillaeOwner.resize(0xA);
    ancillae.resize(0xA);
    for (uint i = 0; i < 0x0A; i++) {
      ancillaeOwner[i] = -1;
      @ancillae[i] = @GameAncilla();
    }
    //array<GameAncilla@> ancillae;

    for (uint i = 0; i < 0x0A; i++) {
      torchOwner[i] = -1;
      torchTimers[i] = 0;
    }

    for (uint i = 0; i < 0x0A; i++) {
      small_keys[i].reset();
    }
  }

  void calculate_player_color_dark() {
    // make 75% as bright:
    player_color_dark_75 =
        ((_player_color & 31) * 3 / 4) |
      ((((_player_color >>  5) & 31) * 3 / 4) << 5) |
      ((((_player_color >> 10) & 31) * 3 / 4) << 10);

    // make 50% as bright:
    player_color_dark_50 =
        ((_player_color & 31) * 2 / 4) |
      ((((_player_color >>  5) & 31) * 2 / 4) << 5) |
      ((((_player_color >> 10) & 31) * 2 / 4) << 10);

    // make 33% as bright:
    player_color_dark_33 =
        ((_player_color & 31) * 1 / 3) |
      ((((_player_color >>  5) & 31) * 1 / 3) << 5) |
      ((((_player_color >> 10) & 31) * 1 / 3) << 10);
  }

  bool is_in_dark_world() const {
    return (actual_location & 0x020000) == 0x020000;
  }

  bool is_in_dungeon_location() const {
    return (actual_location & 0x010000) == 0x010000;
  }

  bool is_in_overworld_module() const {
    if (module == 0x09 || module == 0x0B) return true;
    return false;
  }

  bool is_in_dungeon_module() const {
    if (module == 0x07) return true;
    return false;
  }

  bool is_it_a_bad_time() const {
    if (module <= 0x05) return true;
    if (module == 0x14) return true;
    if (module >= 0x1B) return true;

    if (module == 0x0e) {
      if (sub_module == 0x07) {
        // mode-7 map
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

  bool is_in_screen_transition() const {
    // scrolling between overworld areas:
    if (module == 0x09 && sub_module >= 0x01) return true;
    // scrolling between dungeon rooms:
    if (module == 0x07 && sub_module == 0x02) return true;
    // mirroring in dungeon:
    if (module == 0x07 && sub_module == 0x19) return true;
    return false;
  }

  bool can_see(uint32 other_location) const {
    // use location the player thinks it can see:
    if (locations_equal(location, other_location)) return true;
    // allow to see both old and new location during screen transition:
    if (is_in_screen_transition()) {
      if (locations_equal(actual_location, other_location)) return true;
      return locations_equal(last_location, other_location);
    }
    return false;
  }

  bool is_really_in_same_location(uint32 other_location) const {
    // use the location the game thinks is real:
    return locations_equal(actual_location, other_location);
  }

  bool is_in_same_map(uint32 other_location) const {
    // in underworld, doesn't matter if light vs dark:
    if ((actual_location & 0x010000) == 0x010000 && (other_location & 0x010000) == 0x010000) {
      return true;
    }

    // in overworld both must be in light or dark world:
    return (actual_location & 0x020000) == (other_location & 0x020000);
  }

  void ttl_count() {
    if (ttl > 0) {
      ttl--;
      if (ttl == 0) {
        local.notify(name + " left");
      }
    }
    if (sfx1_ttl > 0) {
      sfx1_ttl--;
    }
    if (sfx2_ttl > 0) {
      sfx2_ttl--;
    }
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

    // read team number:
    uint8 t = r[c++];
    if (team != t) {
      team = t;
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
        case 0x04: c = deserialize_sprites(r, c, true); break;
        case 0x05: c = deserialize_wram(r, c); break;
        case 0x06: c = deserialize_sram(r, c); break;
        case 0x07: c = deserialize_tilemaps(r, c); break;
        case 0x08: c = deserialize_objects(r, c); break;
        case 0x09: c = deserialize_ancillae(r, c); break;
        case 0x0A: c = deserialize_torches(r, c); break;
        case 0x0B: c = deserialize_pvp(r, c); break;
        case 0x0C: c = deserialize_name(r, c); break;
        case 0x0D: c = deserialize_sm_events(r, c); break;
        case 0x0E: c = deserialize_sram_buffer(r, c); break;
        case 0x0F: c = deserialize_sm_location(r, c); break;
        default:
          message("unknown packet type " + fmtHex(packetType, 2) + " at offs " + fmtHex(c, 3));
          break;
      }
    }

    return true;
  }

  void calc_hitbox() {
    hitbox.setBox(x + 4, y + 8, 8, 8);
    hitbox.setActive(!is_dead() && !is_game_over() && (is_in_overworld_module() || is_in_dungeon_module()));
  }

  int deserialize_location(array<uint8> r, int c) {
    module = r[c++];
    sub_module = r[c++];
    sub_sub_module = r[c++];

    location = uint32(r[c++])
               | (uint32(r[c++]) << 8)
               | (uint32(r[c++]) << 16);
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

    player_color = uint16(r[c++]) | (uint16(r[c++]) << 8);

    in_sm = r[c++];

    calc_hitbox();

    return c;
  }

  int deserialize_sm_location(array<uint8> r, int c) {
    sm_area = r[c++];
    sm_x = r[c++];
    sm_y = r[c++];
    sm_sub_x = r[c++];
    sm_sub_y = r[c++];
    in_sm = r[c++];

    return c;
  }

  int deserialize_sfx(array<uint8> r, int c) {
    uint8 tx1, tx2;
    tx1 = r[c++];
    tx2 = r[c++];
    if (tx1 != 0) {
      sfx1 = tx1;
      sfx1_ttl = 16;
    }
    if (tx2 != 0) {
      sfx2 = tx2;
      sfx2_ttl = 16;
    }

    return c;
  }

  int deserialize_sprites(array<uint8> r, int c, bool continuation = false) {
    // read in OAM sprites:
    uint start = 0;
    if (continuation) {
      start = r[c++];
    }
    uint len = r[c++];

    sprites.resize(start + len);
    //message("start=" + fmtInt(start) + " len=" + fmtInt(len) + "; msglen=" + fmtInt(r.length()));

    for (uint i = start; i < start + len; i++) {
      auto @spr = Sprite();
      @sprites[i] = spr;

      //message("  c=" + fmtInt(c));
      auto fl = r[c++];
      spr.index = fl & 0x7f;
      spr.b0 = r[c++];
      spr.b1 = r[c++];
      spr.b2 = r[c++];
      spr.b3 = r[c++];
      auto b4 = r[c++];
      spr.b4 = b4 & 0x7f;
      spr.decodeOAMTableBytes();
      //message("oam " + fmtHex(spr.index, 2));

      // read VRAM for chrs:
      if ((fl & 0x80) != 0) {
        auto h = spr.chr;
        //message(" chr=" + fmtHex(h+0x00, 3));
        chrs[h+0x00].resize(16);
        for (int k = 0; k < 16; k++) {
          chrs[h+0x00][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
        }
        if (spr.size != 0) {
          //message(" chr=" + fmtHex(h+0x01, 3));
          chrs[h+0x01].resize(16);
          for (int k = 0; k < 16; k++) {
            chrs[h+0x01][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
          }
          //message(" chr=" + fmtHex(h+0x10, 3));
          chrs[h+0x10].resize(16);
          for (int k = 0; k < 16; k++) {
            chrs[h+0x10][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
          }
          //message(" chr=" + fmtHex(h+0x11, 3));
          chrs[h+0x11].resize(16);
          for (int k = 0; k < 16; k++) {
            chrs[h+0x11][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
          }
        }
      }

      // read palette data:
      if ((b4 & 0x80) != 0) {
        uint pal = spr.palette << 4;

        // read 16 colors:
        for (uint k = pal; k < pal + 16; k++) {
          palettes[k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
        }
      }
    }

    return c;
  }

  int deserialize_pvp(array<uint8> r, int c) {
    action_hitbox.setActive((r[c++] == 1) ? true : false);
    if (action_hitbox.active) {
      uint16 bx = uint16(r[c++]) | (uint16(r[c++]) << 8);
      uint16 by = uint16(r[c++]) | (uint16(r[c++]) << 8);
      uint8  bw = r[c++];
      uint8  bh = r[c++];

      action_hitbox.setBox(bx, by, bw, bh);

      action_sword_time = r[c++];
      action_item_used =  r[c++];
    }

    action_sword_type = r[c++];
    action_room_level = r[c++];

    // deserialize pvp attacks:
    uint8 len = r[c++];
    pvp_attacks.resize(len);
    for (uint i = 0; i < len; i++) {
      pvp_attacks[i].player_index = uint16(r[c++]) | (uint16(r[c++]) << 8);
      pvp_attacks[i].sword_time = r[c++];
      pvp_attacks[i].melee_item = r[c++];
      pvp_attacks[i].ancilla_mode = r[c++];
      pvp_attacks[i].damage = r[c++];
      pvp_attacks[i].recoil_dx = int8(r[c++]);
      pvp_attacks[i].recoil_dy = int8(r[c++]);
      pvp_attacks[i].recoil_dz = int8(r[c++]);
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

  int deserialize_wram(array<uint8> r, int c) {
    auto count = r[c++];
    auto offs = uint16(r[c++]) | (uint16(r[c++]) << 8);

    if (offs == crystal.offs) {
      // no need for count loop since there's only one byte:
      c = crystal.deserialize(r, c);
    } else if (offs == small_keys_min_offs) {
      // read small key data:
      for (uint i = 0; i < count; i++) {
        if (small_keys[i] is null) {
          @small_keys[i] = @SyncableByte(offs + i);
        }
        c = small_keys[i].deserialize(r, c);
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
    bool temp = r[c++] == 1 ? true : false;
    if (temp) {
      in_sm_for_items = r[c++] == 1 ? true : false;
    } else {
      c++;
    }

    uint16 start = uint16(r[c++]) | (uint16(r[c++]) << 8);
    uint16 count = uint16(r[c++]) | (uint16(r[c++]) << 8);

    for (uint i = 0; i < count; i++) {
      auto offs = start + i;
      auto b = r[c++];

      sram[offs] = b;
    }

    return c;
  }
  
  int deserialize_sram_buffer(array<uint8> r, int c) {
    uint16 start = uint16(r[c++]) | (uint16(r[c++]) << 8);
    uint16 count = uint16(r[c++]) | (uint16(r[c++]) << 8);

    for (uint i = 0; i < count; i++) {
      auto offs = start + i;
      auto b = r[c++];

      sram_buffer[offs] = b;
    }

    return c;
  }

  int deserialize_tilemaps(array<uint8> r, int c) {
    // read timestamp:
    tilemapTimestamp = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    // read location:
    tilemapLocation = uint32(r[c++])
             | (uint32(r[c++]) << 8)
             | (uint32(r[c++]) << 16);
    // start in array:
    uint8 start = r[c++];
    // read number of runs:
    uint8 len = r[c++];

    if (debugRTDSapply) {
      message("rtds: receive for player " + fmtInt(index) + "; loc=" + fmtHex(tilemapLocation, 6) + ", start=" + fmtInt(start) + ", len=" + fmtInt(len));
    }

    tilemapRuns.resize(start + len);
    for (uint i = start; i < start + len; i++) {
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

  int deserialize_name(array<uint8> r, int c) {
    namePadded = r.toString(c, 20);
    c += 20;
    return c;
  }
  
  int deserialize_sm_events(array<uint8> r, int c) {
    for (int i = 0; i < 0x50; i++) {
        sm_events[i] = r[c++];
    }
    return c;
  }

  void renderToPPU(int dx, int dy) {
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

    uint len = sprites.length();
    for (uint i = 0; i < len; i++) {
      auto @sprite = sprites[i];
      if (sprite is null) continue;
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

  int renderToExtra(int dx, int dy, int ei) {
    uint len = sprites.length();
    for (uint i = 0; i < len; i++) {
      auto @sprite = sprites[i];
      if (sprite is null) continue;
      if (!sprite.is_enabled) continue;

      int32 px = sprite.size == 0 ? 8 : 16;

      // bounds check for OAM sprites:
      if (sprite.x + dx <= -px) continue;
      if (sprite.x + dx >= 256) continue;
      if (sprite.y + dy <= -px) continue;
      if (sprite.y + dy >= 240) continue;

      // start building a new OAM sprite (on "extra" layer):
      auto @tile = ppu::extra[ei++];
      tile.index = (sprite.index + 0x8);  // artificially lower remote sprites priority beneath local sprites
      if (tile.index > 127) tile.index = 127;
      tile.source = (sprite.palette < 4) ? 4 : 5; // Source: 4 = OBJ1, 5 = OBJ2 used for windowing purposes
      tile.x = sprite.x + dx;
      tile.y = sprite.y + 1 + dy;
      tile.hflip = sprite.hflip;
      tile.vflip = sprite.vflip;
      tile.priority = sprite.priority;
      tile.width = px;
      tile.height = px;
      tile.pixels_clear();

      auto k = sprite.chr;
      auto p = sprite.palette;

      // draw sprite:
      if (chrs[k + 0x00].length() == 0) {
        chrs[k + 0x00].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(k + 0x00), 0, 16, chrs[k + 0x00]);
      }
      tile.draw_sprite_4bpp(0, 0, p, chrs[k + 0x00], palettes);
      if (sprite.size != 0) {
        if (chrs[k + 0x01].length() == 0) {
          chrs[k + 0x01].resize(16);
          ppu::vram.read_block(ppu::vram.chr_address(k + 0x01), 0, 16, chrs[k + 0x01]);
        }
        tile.draw_sprite_4bpp(8, 0, p, chrs[k + 0x01], palettes);

        if (chrs[k + 0x10].length() == 0) {
          chrs[k + 0x10].resize(16);
          ppu::vram.read_block(ppu::vram.chr_address(k + 0x10), 0, 16, chrs[k + 0x10]);
        }
        tile.draw_sprite_4bpp(0, 8, p, chrs[k + 0x10], palettes);

        if (chrs[k + 0x11].length() == 0) {
          chrs[k + 0x11].resize(16);
          ppu::vram.read_block(ppu::vram.chr_address(k + 0x11), 0, 16, chrs[k + 0x11]);
        }
        tile.draw_sprite_4bpp(8, 8, p, chrs[k + 0x11], palettes);
      }
    }

    return ei;
  }

  Sprite@ findPlayerBody() {
    uint len = sprites.length();
    for (uint i = 0; i < len; i++) {
      auto @sprite = sprites[i];
      auto px = sprite.size == 0 ? 8 : 16;

      auto k = sprite.chr;

      // find body sprite since that's always guaranteed to be seen:
      if (k == 0x00) {
        return sprite;
      }
    }

    return null;
  }

  int renderLabel(int dx, int dy, int ei) {
    auto @sprite = findPlayerBody();
    if (sprite is null) {
      return ei;
    }

    // render player name as text:
    auto @label = ppu::extra[ei++];
    label.reset();
    label.index = 127;
    label.source = (sprite.palette < 4) ? 4 : 5;
    label.priority = sprite.priority;

    // measure player name to set bounds of tile with:
    auto width = ppu::extra.font.measureText(_name);
    label.width = width + 2;
    label.height = ppu::extra.font.height + 2;

    // render player name as text into tile, making room for 1px outline:
    ppu::extra.color = player_color;
    ppu::extra.outline_color = player_color_dark_33;
    label.text(1, 1, _name);

    label.x = (x - xoffs + dx + 8) - (label.width >> 1);
    label.y = (y - yoffs + 17 + dy) + 8;

    return ei;
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
    if (sfx1 != 0 && sfx1_ttl > 0) {
      //message("sfx1 = " + fmtHex(sfx1,2));
      uint8 lfx1 = bus::read_u8(0x7E012E);
      if (lfx1 == 0) {
        uint8 sfx = adjust_sfx_pan(sfx1);
        bus::write_u8(0x7E012E, sfx);
        sfx1 = 0;
      }
    }

    if (sfx2 != 0 && sfx2_ttl > 0) {
      //message("sfx2 = " + fmtHex(sfx2,2));
      uint8 lfx2 = bus::read_u8(0x7E012F);
      if (lfx2 == 0) {
        uint8 sfx = adjust_sfx_pan(sfx2);
        bus::write_u8(0x7E012F, sfx);
        sfx2 = 0;
      }
    }
  }

  void get_sm_coords() {
    if (sm_loading_room()) return;
    sm_area = bus::read_u8(0x7E079f);
    sm_x = bus::read_u8(0x7E0AF7) + bus::read_u8(0x7E07A1);
    sm_y = bus::read_u8(0x7E0AFB) + bus::read_u8(0x07A3);
    sm_sub_x = bus::read_u8(0x7E0AF6);
    sm_sub_y = bus::read_u8(0x7E0AFA);
  }
};
