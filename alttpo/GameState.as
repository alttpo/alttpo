
const uint8 script_protocol = 0x13;

// for message rate limiting to prevent noise
uint8 rate_limit = 0x00;

bool locations_equal(uint32 a, uint32 b) {
  // easiest check:
  if (a == b) return true;
  // if both players in underworld, then ignore light/dark world check:
  if ((a & 0x010000) == 0x010000 && (b & 0x010000) == 0x010000) {
    // same underworld room?
    if ((a & 0xFFFF) == (b & 0xFFFF)) return true;
    return false;
  }
  return false;
}

const uint16 small_keys_min_offs = 0xF37C;
const uint16 small_keys_max_offs = 0xF38C;

const uint spr_stun = 0;
const uint spr_tiledie = 1;
const uint spr_prio = 2;
const uint spr_bpf = 3;
const uint spr_ancid = 4;
const uint spr_slot = 5;
const uint spr_prize = 7;
const uint spr_scr = 8;
const uint spr_defl = 9;
const uint spr_drop = 10;
const uint spr_bump = 11;
const uint spr_dmg = 12;
const uint spr_yl = 13;
const uint spr_xl = 14;
const uint spr_yh = 15;
const uint spr_xh = 16;
const uint spr_vy = 17;
const uint spr_vx = 18;
const uint spr_subvy = 19;
const uint spr_subvx = 20;
const uint spr_gfxstep = 25;
const uint spr_aimode = 26;
const uint spr_timer_a = 28;
const uint spr_timer_b = 29;
const uint spr_timer_c = 30;
const uint spr_id = 31;
const uint spr_auxs = 32;
const uint spr_oamharm = 33;
const uint spr_hp = 34;
const uint spr_props = 35;
const uint spr_collide = 36;
const uint spr_timer_d = 43;
const uint spr_dmgtimer = 44;
const uint spr_halt = 45;
const uint spr_timer_e = 46;
const uint spr_layer = 47;
const uint spr_recoily = 48;
const uint spr_recoilx = 49;
const uint spr_oamprop = 50;
const uint spr_colprop = 51;
const uint spr_z = 52;
const uint spr_vz = 53;
const uint spr_subz = 54;

// offsets from $7E0000
const array<uint16> enemy_data_ptrs = {
  0x0B58, // [ 0] stun
  0x0B6B, // [ 1] tiledie
  0x0B89, // [ 2] prio
  0x0BA0, // [ 3] bpf
  0x0BB0, // [ 4] ancid
  0x0BC0, // [ 5] slot *** (underworld); uint16 OWDEATH index (overworld)
  0x0BD0, // [ 6] 2nd half of OWDEATH array (overworld)
  0x0BE0, // [ 7] prize
  0x0C9A, // [ 8] scr (overworld)
  0x0CAA, // [ 9] defl
  0x0CBA, // [10] drop
  0x0CD2, // [11] bump
  0x0CE2, // [12] dmg
  0x0D00, // [13] yl
  0x0D10, // [14] xl
  0x0D20, // [15] yh
  0x0D30, // [16] xh
  0x0D40, // [17] vy
  0x0D50, // [18] vx
  0x0D60, // [19] subvy
  0x0D70, // [20] subvx
  0x0D80, // [21]
  0x0D90, // [22]
  0x0DA0, // [23]
  0x0DB0, // [24]
  0x0DC0, // [25] gfxstep
  0x0DD0, // [26] aimode ***
  0x0DE0, // [27]
  0x0DF0, // [28] timer_a
  0x0E00, // [29] timer_b
  0x0E10, // [30] timer_c
  0x0E20, // [31] id ***
  0x0E30, // [32] auxs
  0x0E40, // [33] oamharm
  0x0E50, // [34] hp
  0x0E60, // [35] props
  0x0E70, // [36] collide
  0x0E80, // [37]
  0x0E90, // [38]
  0x0EA0, // [39]
  0x0EB0, // [40]
  0x0EC0, // [41]
  0x0ED0, // [42]
  0x0EE0, // [43] timer_d
  0x0EF0, // [44] dmgtimer
  0x0F00, // [45] halt ***
  0x0F10, // [46] timer_e
  0x0F20, // [47] layer
  0x0F30, // [48] recoily
  0x0F40, // [49] recoilx
  0x0F50, // [50] oamprop
  0x0F60, // [51] colprop
  0x0F70, // [52] z
  0x0F80, // [53] vz
  0x0F90  // [54] subz
};
const int enemy_data_size = enemy_data_ptrs.length() * 0x10;

// 0x7FFB00[$80], 0x7FFB80[$80], 0x7FFC00[$80], 0x7FFC80[$80], ..., 0x7FFE80[$80]
// careful: $7FFE00 is race game timer and dig game counter
const int enemy_segment_data_size = 8 * 0x80;

// offsets from $7F0000 for
//   u8[7 properties][8 segments][16 sprites];
const array<uint16> enemy_segments_data_ptrs = {
  0xFC00,
  0xFC80,
  0xFD00,
  0xFD80,
  0xFE00,
  0xFE80,
  0xFF00
};
const int enemy_segments_data_size = 0x400;

// offsets from $7F0000 for properties of lanmolas segmented enemies:
const array<uint16> lanmolas_segments_data_ptrs = {
  0xFC00,
  0xFD00,
  0xFE00,
  0xFF00
};


// offsets from $7F0000 for properties of swamola segmented enemies:
//   u8[4 properties][6 sprites][20 points];
const array<uint16> swamola_segments_data_ptrs = {
  0xFA5C,
  0xFB1C,
  0xFBDC,
  0xFC9C
};
const int swamola_segments_data_size = swamola_segments_data_ptrs.length() * 0xC0;

bool is_segmented_enemy_id(uint8 id) {
  return id == 0x09 // moldorm
      || id == 0x18 // mini moldorm
      || id == 0x54 // lanmolas
      || id == 0x6A // chain chomp
      || id == 0xCB // trinexx rock head
      || id == 0xCC // trinexx fire head
      || id == 0xCD // trinexx ice head
      || id == 0xCF // swamolas (special case; uses overlapping $7FFA5C..7FFD5C region)
    ;
}

bool players_updated = false;

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

  void player_changed() {
    players_updated = true;
  }

  string _name = "";
  string name {
    get const { return _name; }
    set {
      string lastName = _name;
      string stripped = value.strip();

      _name = stripped;
      _namePadded = padTo(value, 20);

      if (lastName != stripped) {
        player_changed();
      }
    }
  }

  string _namePadded = "                    ";  // 20 spaces
  string namePadded {
    get const { return _namePadded; }
    set {
      string lastName = _name;
      string stripped = value.strip();

      _name = stripped;
      if (value.length() == 20) {
        _namePadded = value;
      } else {
        _namePadded = padTo(value, 20);
      }

      if (lastName != stripped) {
        player_changed();
      }
    }
  }

  uint8 team {
    get const { return _team; }
    set {
      auto lastValue = _team;
      _team = value;
      dbgData("[{0}] team = {1}".format({index, _team}));

      if (value != lastValue) {
        player_changed();
      }
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
  uint8 sm_room_x, sm_room_y, sm_pose;
  uint16 offsm1, offsm2;
  uint8 in_sm;
  uint8 sm_clear, z3_clear;

  uint8 _module;
  uint8 module {
    get const { return _module; }
    set {
      uint8 lastValue = _module;
      _module = value;
      if (value != lastValue) {
        player_changed();
      }
    }
  }
  uint8 sub_module;
  uint8 sub_sub_module;

  uint8 in_dark_world;
  uint8 in_dungeon;
  uint16 _overworld_room;
  uint16 overworld_room {
    get const { return _overworld_room; }
    set {
      auto lastValue = _overworld_room;
      _overworld_room = value;
      if (value != lastValue) {
        player_changed();
      }
    }
  }

  uint16 _dungeon_room;
  uint16 dungeon_room {
    get const { return _dungeon_room; }
    set {
      auto lastValue = _dungeon_room;
      _dungeon_room = value;
      if (value != lastValue) {
        player_changed();
      }
    }
  }

  uint16 dungeon;
  uint16 dungeon_entrance;

  uint16 last_overworld_x;
  uint16 last_overworld_y;

  private uint16 _player_color;
  uint16 player_color {
    get const { return _player_color; }
    set {
      auto lastValue = _player_color;

      _player_color = value;
      calculate_player_color_dark();

      if (value != lastValue) {
        player_changed();
      }
    }
  }

  uint16 player_color_dark_75;
  uint16 player_color_dark_50;
  uint16 player_color_dark_33;

  uint8 sfx1;
  uint8 sfx2;

  uint8 sfx1_ttl = 0;
  uint8 sfx2_ttl = 0;

  array<uint8> sram(0x1500);
  array<uint8> sram_buffer(0x500);
  bool in_sm_for_items;

  array<uint8> sm_events(0x54);
  array<uint16> sm_palette(0x10);

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

  array<uint8> enemyData(enemy_data_size);
  array<uint8> enemySegments(enemy_segments_data_size);
  array<uint8> swamolaSegments(swamola_segments_data_size);

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
    justJoined = true;

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
    for (uint i = 0x500; i < 0x1500; i++) {
      sram[i] = 0;
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

  bool is_in_game_module() const {
    if (module <= 0x05) return false;
    if (module == 0x14) return false;
    if (module >= 0x1B) return false;

    return true;
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
  
  // tests if the remote sm player is in the same room as the local one
  bool can_see_sm(GameState @remote){
    if(remote.in_sm != 1) return false;
    return (remote.sm_room_x == this.sm_room_x && remote.sm_room_y == this.sm_room_y && remote.sm_area == this.sm_area);
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

  bool justJoined = false;

  void ttl_count() {
    if (ttl > 0) {
      ttl--;
      if (ttl == 0) {
        justJoined = false;
        local.notify(name + " left");
        if (playersWindow !is null) {
          playersWindow.update();
        }
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
        case 0x10: c = deserialize_sm_sprite(r, c); break;
        case 0x11: c = deserialize_enemy_data(r, c); break;
        case 0x12: c = deserialize_enemy_segment_data(r, c); break;
        default:
          message("unknown packet type " + fmtHex(packetType, 2) + " at offs " + fmtHex(c, 3));
          break;
      }
    }

    if (ttl <= 0) {
      justJoined = true;
    }
    ttl = 255;
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

    if (is_in_dungeon_location()) {
      dungeon_room = location & 0xFFFF;
    } else {
      overworld_room = location & 0xFFFF;
    }

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
    sm_room_x = r[c++];
    sm_room_y = r[c++];
    sm_pose = r[c++];

    return c;
  }
  
  int deserialize_sm_sprite(array<uint8> r, int c){
    
    offsm1 = uint16(r[c++]) | (uint16(r[c++]) << 8);
    offsm2 = uint16(r[c++]) | (uint16(r[c++]) << 8);
    
    for(int i = 0; i < 0x10; i++){
        sm_palette[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
        }
    
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
    } else {
      // discard data we don't understand yet:
      for (uint i = 0; i < count; i++) {
        c = SyncableByte(offs + i).deserialize(r, c);
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

  int deserialize_enemy_data(array<uint8> r, int c) {
    uint16 mask = uint16(r[c++]) | (uint16(r[c++]) << 8);
    uint8 in_dungeon = r[c++];

    uint len = enemy_data_ptrs.length();
    for (uint s = 0; s < 16; s++) {
      if ((mask & (1 << s)) == 0) {
        enemyData[(spr_aimode<<4)+s] = 0;
        continue;
      }

      for (uint x = 0; x < len; x++) {
        // handle spr_slot specially for overworld:
        if (x == spr_slot && in_dungeon == 0) {
          enemyData[(spr_slot<<4)+(s<<1)] = r[c++];
          enemyData[(spr_slot<<4)+(s<<1)+1] = r[c++];
        }
        if (x == spr_slot+1 && in_dungeon == 0) continue;

        enemyData[(x<<4)+s] = r[c++];
      }
    }

    return c;
  }

  int deserialize_enemy_segment_data(array<uint8> r, int c) {
    // mask determines what subset of 16 sprites have segmented data available:
    uint16 mask = uint16(r[c++]) | (uint16(r[c++]) << 8);

    for (uint s = 0; s < 16; s++) {
      if ((mask & (1 << s)) == 0) {
        continue;
      }

      // sprite id affects serialization of data:
      uint8 id = r[c++];
      switch (id) {
        case 0xCF: // swamola special case:
          if (s >= 6) continue;
          for (uint x = 0; x < swamola_segments_data_ptrs.length(); x++) {
            for (uint i = 0; i < 0x20; i++) {
              swamolaSegments[(x * 0xC0) + (s * 0x20) + i] = r[c++];
            }
          }
          break;
        case 0x09: // moldorm
          // moldorm uses all $80 bytes per segment:
          for (uint x = 0; x < enemy_segments_data_ptrs.length(); x++) {
            for (uint i = 0; i < 0x80; i++) {
              enemySegments[(x * 0x80) + i] = r[c++];
            }
          }
          break;
        case 0x54: // lanmolas
          if (s >= 4) continue;
          // lanmolas uses $40 bytes per segment:
          for (uint x = 0; x < lanmolas_segments_data_ptrs.length(); x++) {
            for (uint i = 0; i < 0x40; i++) {
              enemySegments[(x * 0x100) + (s * 0x40) + i] = r[c++];
            }
          }
          break;
        default: // assume all other enemies use all 7 properties
          if (s >= 8) continue;
          for (uint x = 0; x < enemy_segments_data_ptrs.length(); x++) {
            for (uint i = 0; i < 0x10; i++) {
              enemySegments[(x*0x80)+(s*0x10)+i] = r[c++];
            }
          }
          break;
      }
    }

    return c;
  }

  int deserialize_name(array<uint8> r, int c) {
    namePadded = r.toString(c, 20);
    c += 20;

    bool update = false;
    if (justJoined) {
      local.notify(name + " joined");
      justJoined = false;
    }

    return c;
  }

  int deserialize_sm_events(array<uint8> r, int c) {
    for (int i = 0; i < 0x54; i++) {
        sm_events[i] = r[c++];
    }
    sm_clear = r[c++];
    z3_clear = r[c++];
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
  
  int render_sm_label(int dx, int dy, int ei) {

    // render player name as text:
    auto @label = ppu::extra[ei++];
    label.reset();
    label.index = 127;
    label.source = 4;
    label.priority = 0x106;

    // measure player name to set bounds of tile with:
    auto width = ppu::extra.font.measureText(_name);
    label.width = width + 2;
    label.height = ppu::extra.font.height + 2;

    // render player name as text into tile, making room for 1px outline:
    ppu::extra.color = player_color;
    ppu::extra.outline_color = player_color_dark_33;
    label.text(1, 1, _name);

    label.x = (dx + 8) - (label.width >> 1);
    label.y = (17 + dy) + 8;

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
  
  int draw_samus(int x, int y, int ei){
    //message("attempted to draw a samus");
    
    array<array<uint16>> sprs(32, array<uint16>(16)); // array of 32 different 8x8 sprite blocks
    array<uint16> palette = sm_palette;
    int p = 0; // palette int, use is unknown
    int protocol = determine_protocol(sm_pose); // decides which protocol is used for placing samus' blocks to build the sprite
    
    int offsx = offs_x(sm_pose); // X offset to align sprite with actual location, differs by pose
    int offsy = offs_y(sm_pose); // Y offset to align sprite with actual location, differs by pose 
    
    //initialize tile
    auto @tile = ppu::extra[ei++];
    tile.index = 127;
    tile.source = 4;
    tile.x = x + offsx;
    tile.y = y + offsy;
    tile.priority = 0x106; //0x106-0x108
    tile.hflip = false;
    tile.vflip = false;
    tile.width = 64;
    tile.height = 128;
    tile.pixels_clear();

    uint8 bank = bus::read_u8(0x920000 + offsm1 + 2);
    uint16 address = bus::read_u16(0x920000 + offsm1);
    uint16 size0 = bus::read_u16(0x920000 + offsm1 + 3);
    uint16 size1 = bus::read_u16(0x920000 + offsm1 + 5);
    
    uint8 bank2 = bus::read_u8(0x920000 + offsm2 + 2);
    uint16 address2 = bus::read_u16(0x920000 + offsm2);
    uint16 size2 = bus::read_u16(0x920000 + offsm2 + 3);
    uint16 size3 = bus::read_u16(0x920000 + offsm2 + 5);
    
    
    uint32 transfer0;
    uint32 transfer1;
    uint16 len1;
    uint16 len2;
    if (sm_pose == 0x1a || sm_pose == 0x19 || sm_pose == 0x81 || sm_pose == 0x82 || sm_pose == 0x1b || sm_pose == 0x1c){
        transfer0 = 0x010000 * bank2 + address2;
        transfer1 = transfer0 + size2;
        
        len1 = min(size2 / 32, 16);
        len2 = min(size3 / 32, 16);
    } else {
        transfer0 = 0x010000 * bank + address;
        transfer1 = transfer0 + size0;
        
        len1 = min(size0 / 32, 16);
        len2 = min(size1 / 32, 16);
    }
    //load data from vram into sprs
    
    for (uint16 i = 0; i < len1; i++) {
        bus::read_block_u16(transfer0 + 0x20 * i, 0, 16, sprs[i]);
    }
    for (uint16 i = 0; i < len2; i++) {
        bus::read_block_u16(transfer1 + 0x20 * i, 0, 16, sprs[i+16]);
    }
    
    //most of samus' poses, with only a few exceptions
    if (protocol == 0){
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
        tile.draw_sprite_4bpp(32, 32, p, sprs[14], palette);
        tile.draw_sprite_4bpp(32, 24, p, sprs[29], palette);
        tile.draw_sprite_4bpp(32, 40, p, sprs[30], palette);
    }
    // aim upwards
    else if(protocol == 1){
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
        tile.draw_sprite_4bpp(8, 48, p, sprs[28], palette);
        tile.draw_sprite_4bpp(0, 48, p, sprs[12], palette);
        tile.draw_sprite_4bpp(16, 48, p, sprs[13], palette);
        tile.draw_sprite_4bpp(24, 48, p, sprs[29], palette);
        tile.draw_sprite_4bpp(32, 48, p, sprs[30], palette);
    }
    // crouching no aim
    else if (protocol == 2){
        for (int i = 0; i < 8; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 8; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
        tile.draw_sprite_4bpp(16, 32, p, sprs[9], palette);
        tile.draw_sprite_4bpp(8, 32, p, sprs[24], palette);
    }
    // crouching aim diagonally
    else if (protocol == 3){
        for (int i = 0; i < 8; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 8; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
        tile.draw_sprite_4bpp(24, 32, p, sprs[27], palette);
        tile.draw_sprite_4bpp(16, 32, p, sprs[11], palette);
        tile.draw_sprite_4bpp(8, 32, p, sprs[26], palette);
    }
    // morph ball
    else if (protocol == 4){
        for (int i = 0; i < 4; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 4; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
        tile.draw_sprite_4bpp(16, 16, p, sprs[5], palette);
        tile.draw_sprite_4bpp(8, 16, p, sprs[20], palette);
    }
    //spin jump
    else if (protocol == 5){
        for (int i = 0; i < 16; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 16; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
    }
    //facing toward the camera
    else if (protocol == 6){
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
        tile.draw_sprite_4bpp(0, 48, p, sprs[12], palette);
        tile.draw_sprite_4bpp(16, 48, p, sprs[13], palette);
        tile.draw_sprite_4bpp(8, 48, p, sprs[28], palette);
        tile.draw_sprite_4bpp(24, 48, p, sprs[29], palette);
    }
    // vertical leap
    else if (protocol == 7){
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4), p, sprs[i], palette);
        }
        for (int i = 0; i < 12; i++){
            tile.draw_sprite_4bpp(8*(i%4), 16*(i/4)+8, p, sprs[i+16], palette);
        }
        tile.draw_sprite_4bpp(16, 48, p, sprs[13], palette);
        tile.draw_sprite_4bpp(8, 48, p, sprs[28], palette);
    }
    
    return ei;
  }
  
  int determine_protocol(uint8 pose){
    switch(pose){
        case 0x00: return 6;
        case 0x03: return 1;
        case 0x04: return 1;
        case 0x1d: return 4;
        case 0x1e: return 4;
        case 0x1f: return 4;
        case 0x27: return 2;
        case 0x28: return 2;
        case 0x29: return 1;
        case 0x2a: return 1;
        case 0x31: return 4;
        case 0x32: return 4;
        case 0x38: return 3;
        case 0x3e: return 3;
        case 0x41: return 4;
        case 0x43: return 3;
        case 0x44: return 3;
        case 0x4b: return 7;
        case 0x4c: return 7;
        case 0x4d: return 7;
        case 0x4e: return 7;
        case 0x71: return 3;
        case 0x72: return 3;
        case 0x73: return 3;
        case 0x74: return 3;
        case 0x79: return 4;
        case 0x7a: return 4;
        case 0x7b: return 4;
        case 0x7c: return 4;
        case 0x7d: return 4;
        case 0x7e: return 4;
        case 0x7f: return 4;
        case 0x80: return 4;
        case 0x81: return 5;
        case 0x82: return 5;
        case 0x9b: return 1;
        case 0xa4: return 7;
        case 0xa5: return 7;
        default: return 0;
    
    }
    return 0;
}

  int offs_x(uint8 pose){
    switch (pose){
        case 0x06: return -22;
        case 0x08: return -22;
        
        default: return -13;
    }
    
    
    return -15;
  }

  int offs_y(uint8 pose){
    //do stuff here
    switch (pose){
        case 0x03: return -34;
        case 0x04: return -34;
        case 0x1d: return -14;
        case 0x1e: return -14;
        case 0x1f: return -14;
        case 0x27: return -22;
        case 0x28: return -22;
        case 0x31: return -14;
        case 0x32: return -14;
        case 0x41: return -14;
        case 0x43: return -22;
        case 0x44: return -22;
        case 0x71: return -22;
        case 0x72: return -22;
        case 0x73: return -22;
        case 0x74: return -22;
        case 0x79: return -14;
        case 0x7a: return -14;
        case 0x7b: return -14;
        case 0x7c: return -14;
        case 0x7d: return -14;
        case 0x7e: return -14;
        case 0x7f: return -14;
        case 0x80: return -14;
        case 0x81: return -17;
        case 0x82: return -17;
        
        
        default: return -26;
    }
    
    return -26;
  }
};
