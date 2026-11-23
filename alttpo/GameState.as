
const uint8 script_protocol = 0x01;

// for message rate limiting to prevent noise
uint8 rate_limit = 0x00;

// a remote player's enemy data older than this (msec) means it stopped sending it; see GameState::sends_enemy_data:
const uint64 enemy_data_stale = 1000;

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

void insertUnique(array<uint16> &a, uint16 v) {
  int i;
  for (i = a.length() - 1; i >= 0; i--) {
    // don't insert duplicate value:
    if (a[i] == v) return;
    if (a[i] < v) break;
  }

  a.insertAt(i + 1, v);
}


const uint ol8_id = 0;
const uint ol8_xl = 1;
const uint ol8_xh = 2;
const uint ol8_yl = 3;
const uint ol8_yh = 4;
const uint ol8_ta = 5;
const uint ol8_tb = 6;
const uint ol8_tc = 7;
const uint ol8_layer = 8;

const array<uint16> overlord_u8_ptrs = {
  0x0B00, // [ 0] id
  0x0B08, // [ 1] xl
  0x0B10, // [ 2] xh
  0x0B18, // [ 3] yl
  0x0B20, // [ 4] yh
  0x0B28, // [ 5] ta
  0x0B30, // [ 6] tb
  0x0B38, // [ 7] tc
  0x0B40  // [ 8] layer
};

const uint ol16_scr = 0;

const array<uint16> overlord_u16_ptrs = {
  0x0B48  // [ 9] scr
};

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

// LTTP Link  uses $04F0 uniq tiles
//   SM Samus uses $0F00 uniq tiles
// total tiles  =  $13F0
const uint lttp_uniq4bpptile_count = 0x4F0 + 4;
const uint   sm_uniq4bpptile_count = 0xF00;

class GameState {
  int ttl;        // time to live for last update packet
  int index = -1; // player index in server's array (local is always -1)
  // timestamps (nanoseconds since unix epoch) from the last server protocol 04 message received from this player:
  int64 player_time = 0; // player's clock when the message was sent
  int64 server_time = 0; // server's clock when the message passed through the server
  uint8 _team = 0; // team number to sync with

  // the player's run timing from message 0x84 (see RunTiming.as):
  RunTimingRemote run_timing;
  // the name the player had when its start was first seen, so that the run isn't given to another player that took
  // its slot; when it was last sent its run back; the gaps it announced (see RunTiming.as):
  string run_name = "";
  uint64 restore_sent_ms = 0;
  array<uint8> gaps_seen_kind;
  array<int64> gaps_seen_lost;

  // graphics data for current frame:
  array<Sprite@> sprites;
  array<array<uint16>> chrs(512);
  array<uint16> palettes(8 * 16);
  // lookup remote chr number to find local chr number mapped to:
  array<uint16> reloc(512);

  // lttp: unique tiles' 4bpp data ($20 uint8s | $10 uint16s, each):
  array<array<uint16>> lttp_uniqtile_4bpp(lttp_uniq4bpptile_count);
  //   sm: unique tiles' 4bpp data ($20 uint8s | $10 uint16s, each):
  array<array<uint16>>   sm_uniqtile_4bpp(  sm_uniq4bpptile_count);

  // currently missing unique tiles:
  array<uint16> missing_uniq_absidx;

  array<uint16> @uniqtile_get(uint16 absidx) {
    if (absidx < 0x1000) {
      return @lttp_uniqtile_4bpp[absidx];
    } else if (absidx < 0x2000) {
      return   @sm_uniqtile_4bpp[absidx - 0x1000];
    } else {
      return null;
    }
  }

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

  // values copied from RAM:
  uint8  frame;
  uint32 actual_location;
  uint32 last_actual_location;
  uint32 location;
  uint32 last_location;

  // screen scroll coordinates relative to top-left of room (BG screen):
  int16 xoffs;
  int16 yoffs;

  // when the last sprites (0x03/0x04) arrived, and the scroll offsets the player sent with them. Players send their
  // location (with the offsets) before their sprites in the same frame, so these are the offsets the sprites were drawn
  // with; the latest offsets can be a frame ahead or behind, which shifts the sprites while the screen scrolls:
  uint64 sprites_received = 0;
  int16 sprites_xoffs;
  int16 sprites_yoffs;

  uint16 x, y;

  //coordinates for super metroid game
  uint8 sm_area, sm_sub_x, sm_sub_y, sm_x, sm_y;
  uint8 sm_room_x, sm_room_y, sm_pose, sm_anim_frame;
  uint16 sm_screen_x, sm_screen_y;
  uint16 offsm1, offsm2;
  uint8 in_sm;
  uint8 sm_clear, z3_clear;

  array<SM_Enemy> enemies(0x20);
  bool enemySyncEnabled;
  uint16 timeInRoom = 0;

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
  array<uint8> sm_sram(0x40);

  array<uint8> sm_events(0x54);

  SyncableByte@ crystal = @SyncableByte(0xC172);
  // star switch state of star_room as received (see StarSwitch.as):
  bool star_valid = false;
  uint16 star_room = 0;
  uint32 star_timestamp = 0;
  uint8 star_value = 0;
  uint8 star_overlay = 0;
  // tile room overlord state of flying_tiles_room as received (see FlyingTiles.as):
  bool flying_tiles_valid = false;
  uint16 flying_tiles_room = 0;
  uint8 flying_tiles_count = 0;
  uint8 flying_tiles_timer = 0;
  // rupees of rupee floors deleted in rupees_room as received (see Rupees.as):
  bool rupees_valid = false;
  uint16 rupees_room = 0;
  array<uint16> rupees_pos;
  // trap doors and key flags of room_room as received (see RoomState.as):
  bool room_valid = false;
  uint16 room_room = 0;
  uint8 room_flags = 0;
  uint32 room_door_ts = 0;
  uint8 room_door = 0;
  // key doors and switches of room_doors_room as received (see RoomState.as):
  bool room_doors_valid = false;
  uint16 room_doors_room = 0;
  uint8 room_doors = 0;
  bool room_hold = false;
  bool room_pulled = false;
  uint32 room_pulled_ts = 0;
  // quadrant the switch was pulled in: bit 0 east, bit 1 south:
  uint8 room_pulled_quad = 0;
  // kill triggers fired in room_kills_room as received (see RoomState.as): bit k for the tag in $AE+k:
  bool room_kills_valid = false;
  uint16 room_kills_room = 0;
  uint8 room_kills_fired = 0;
  // the features the player's client has, and the full location (0x01) and small keys (0x82) its change messages are
  // relative to, with the frame numbers of their packets (see Compact.as):
  uint8 features = 0;
  bool loc_key_ok = false;
  uint8 loc_key_frame = 0;
  array<uint16> loc_key(4);
  bool sk_key_ok = false;
  uint8 sk_key_frame = 0;
  array<uint8> sk_key;

  // enemies killed in the room or area as received (see EnemiesKilled.as):
  bool ek_valid = false;
  uint8 ek_kind = 0;
  uint32 ek_id = 0;
  uint16 ek_mask = 0;
  // the underworld rooms' masks last received, of the player's current room and of the other recent rooms, and when
  // (ms):
  array<uint16> ek_room_ids(4, 0xFFFF);
  array<uint16> ek_room_masks(4, 0);
  array<uint64> ek_room_times(4, 0);
  uint32 ek_logged_id = 0;
  uint16 ek_logged_mask = 0;
  array<uint16> ek_blks;
  // overworld events at location ow_events_loc as received (see OverworldEvents.as):
  bool ow_events_valid = false;
  uint32 ow_events_loc = 0;
  uint8 ow_events_entrance = 0;
  uint8 ow_events_flags = 0;
  uint64 ow_events_received = 0;
  SmallKeysRemote small_keys;
  HeartsRemote hearts;

  int numsprites;

  // overworld map16 change log (Map16Changes.as) and underworld manipulable objects (Manipulables.as) as received:
  Map16Remote map16;
  ManipRemote manip;

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

  array<uint8> overlordU8Data(overlord_u8_ptrs.length() * 0x08);
  array<uint8> overlordU16Data(overlord_u16_ptrs.length() * 0x10);
  array<uint8> enemyData(enemy_data_size);
  // when enemy data (message 0x12) was last received from this player, in msec; 0 if never:
  uint64 enemy_data_received = 0;

  // sends_enemy_data is true if this remote player is sending its enemies (message 0x12), so its enemy data can be
  // copied. o2 never sends them, nor do alttpo players with "Sync enemies" off; taking such a player as the owner of
  // the room's enemies would copy empty sprite slots over every local sprite each frame (enemies, and the items
  // revealed under pots and bushes):
  bool sends_enemy_data() const {
    if (enemy_data_received == 0) return false;
    return chrono::monotonic::millisecond - enemy_data_received < enemy_data_stale;
  }
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
    timeInRoom = 0;

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

    for (uint i = 0; i < 0x1500; i++) {
      sram[i] = 0;
    }
    for (uint i = 0; i < 0x40; i++) {
      sm_sram[i] = 0;
    }

    for (uint i = 0; i < 0x50; i++) {
      sm_events[i] = 0;
    }

    for (uint i = 0; i < 0x20; i++){
      enemies[i] = SM_Enemy(i);
    }

    crystal.reset();
    star_valid = false;
    star_room = 0;
    star_timestamp = 0;
    star_value = 0;
    star_overlay = 0;
    flying_tiles_valid = false;
    rupees_valid = false;
    room_valid = false;
    room_doors_valid = false;
    room_kills_valid = false;
    ek_valid = false;

    numsprites = 0;

    map16.reset(0);
    manip.reset();

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

    small_keys.reset();

    missing_uniq_absidx.reserve(64);
    missing_uniq_absidx.resize(0);
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

  bool get_in_sm(){
    return in_sm == 1;
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

  // has_link_body reports whether the last sprites received have Link's head or body: 16x16 sprites drawn from chrs
  // $00..$03 and $10..$13. Players always send Link's 12 reserved OAM entries, so while Link is invisible (flickering)
  // they still have his shadow but no head or body.
  bool has_link_body() const {
    for (uint i = 0; i < sprites.length(); i++) {
      auto @spr = sprites[i];
      if (spr is null) continue;
      if (spr.b1 == 0xF0) continue;
      if (((spr.b4 >> 1) & 1) == 0) continue;
      uint16 chr = uint16(spr.b2) | (uint16(spr.b3 & 1) << 8);
      if (chr < 0x20 && (chr & 0x0F) < 0x04) return true;
    }
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
    if(!remote.get_in_sm()) return false;
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

  // deserialize reads a broadcast of game protocol v2 (see Protocol.as): the frame number, then messages of
  // `type, length, body`. A message type that isn't known is skipped by its length, and each message is read from a
  // copy of the packet that ends with it, so that no message reads into the next.
  bool deserialize(array<uint8> r, int c) {
    if (c >= int(r.length())) return false;

    auto frame = r[c++];
    // discard stale frame data. frame numbers wrap around from 0xFF to 0x00, so compare them as a signed 8-bit
    // distance: a frame up to 127 behind the last one seen is stale; anything else (including the same frame, since
    // one frame's state is split across several packets) is current. this matches o2's check.
    // a player that has timed out has no meaningful last frame, so accept whatever they send to resync.
    int delta = int((uint(frame) - uint(this.frame)) & 0xff);
    if (delta >= 0x80) delta -= 0x100;
    if (delta < 0 && ttl > 0) {
      return false;
    }
    this.frame = frame;

    int maxc = int(r.length());
    while (c < maxc) {
      auto packetType = r[c++];
      int width;
      int len = msg_read_len(r, c, width);
      c += width;
      if (len < 0 || c + len > maxc) {
        message("message " + fmtHex(packetType, 2) + " truncated");
        break;
      }
      int end = c + len;
      if (runReset.resetting && packetType != msg_reset) {
        // no state is accepted during a group reset:
        c = end;
        continue;
      }
      array<uint8> m = r;
      m.resize(end);
      switch (packetType) {
        case msg_location: deserialize_location(m, c); break;
        case msg_location_changes: deserialize_location_changes(m, c); break;
        case msg_sfx: deserialize_sfx(m, c); break;
        case msg_wram: deserialize_wram(m, c); break;
        case msg_sram: deserialize_sram(m, c); break;
        case msg_ancillae: deserialize_ancillae(m, c); break;
        case msg_torches: deserialize_torches(m, c); break;
        case msg_pvp: deserialize_pvp(m, c); break;
        case msg_map16: map16.deserialize(m, c); break;
        case msg_manip: manip.deserialize(m, c); break;
        case msg_star_switch: deserialize_star_switch(m, c); break;
        case msg_room_state: deserialize_room_state(m, c); break;
        case msg_room_doors: deserialize_room_doors(m, c); break;
        case msg_ow_events: deserialize_ow_events(m, c); break;
        case msg_flying_tiles: deserialize_flying_tiles(m, c); break;
        case msg_room_kills: deserialize_room_kills(m, c); break;
        case msg_enemies_killed: deserialize_enemies_killed(m, c); break;
        case msg_rupees: deserialize_rupees(m, c); break;
        case msg_enemy_data: deserialize_enemy_data(m, c); break;
        case msg_enemy_segment_data: deserialize_enemy_segment_data(m, c); break;
        case msg_overlord_data: deserialize_overlord_data(m, c); break;
        case msg_small_keys: deserialize_small_keys(m, c); break;
        case msg_small_keys_changes: deserialize_small_keys_changes(m, c); break;
        case msg_hearts: deserialize_hearts(m, c); break;
        case msg_reset: deserialize_reset(m, c); break;
        case msg_run_timing: run_timing.deserialize(m, c, this); break;
        case msg_run_restore: deserialize_run_restore(m, c); break;
        case msg_run_gap: deserialize_run_gap(m, c); break;
        case msg_sprite_chrs: deserialize_sprite_chrs(m, c); break;
        case msg_sprite_palettes: deserialize_sprite_palettes(m, c); break;
        case msg_sprites: deserialize_sprites(m, c); break;
        case msg_sm_location: deserialize_sm_location(m, c); break;
        case msg_sm_events: deserialize_sm_events(m, c); break;
        case msg_sm_sram: deserialize_sm_sram(m, c); break;
        case msg_sm_enemies: deserialize_sm_enemies(m, c); break;
        default:
          // a newer message type; skipped by its length.
          break;
      }
      c = end;
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

  int deserialize_rupees(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 3 > maxc) return maxc;
    rupees_room = uint16(r[c++]) | (uint16(r[c++]) << 8);
    int n = int(r[c++]);
    if (c + n * 2 > maxc) return maxc;
    rupees_pos.resize(n);
    for (int i = 0; i < n; i++) {
      rupees_pos[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
    }
    rupees_valid = true;
    return c;
  }

  int deserialize_flying_tiles(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 4 > maxc) return maxc;
    flying_tiles_room = uint16(r[c++]) | (uint16(r[c++]) << 8);
    flying_tiles_count = r[c++];
    flying_tiles_timer = r[c++];
    flying_tiles_valid = true;
    return c;
  }

  int deserialize_star_switch(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 8 > maxc) return maxc;
    star_room = uint16(r[c++]) | (uint16(r[c++]) << 8);
    star_timestamp = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    star_value = r[c++];
    star_overlay = r[c++];
    star_valid = true;
    return c;
  }

  int deserialize_room_state(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 8 > maxc) return maxc;
    room_room = uint16(r[c++]) | (uint16(r[c++]) << 8);
    room_flags = r[c++];
    room_door_ts = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    room_door = r[c++];
    room_valid = true;
    return c;
  }

  int deserialize_ow_events(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 5 > maxc) return maxc;
    ow_events_loc = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16);
    ow_events_entrance = r[c++];
    ow_events_flags = r[c++];
    ow_events_received = chrono::monotonic::millisecond;
    ow_events_valid = true;
    return c;
  }

  int deserialize_room_doors(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 8 > maxc) return maxc;
    room_doors_room = uint16(r[c++]) | (uint16(r[c++]) << 8);
    room_doors = r[c++];
    uint8 switches = r[c++];
    room_hold = (switches & 0x01) != 0;
    room_pulled = (switches & 0x02) != 0;
    room_pulled_quad = (switches >> 2) & 3;
    room_pulled_ts = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    room_doors_valid = true;
    return c;
  }

  int deserialize_room_kills(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 3 > maxc) return maxc;
    room_kills_room = uint16(r[c++]) | (uint16(r[c++]) << 8);
    room_kills_fired = r[c++];
    room_kills_valid = true;
    return c;
  }

  // records a room's mask, replacing the room's entry or else the oldest:
  void set_ek_room_mask(uint16 room, uint16 mask) {
    uint k = 0;
    for (uint i = 0; i < 4; i++) {
      if (ek_room_ids[i] == room) { k = i; break; }
      if (ek_room_times[i] < ek_room_times[k]) k = i;
    }
    ek_room_ids[k] = room;
    ek_room_masks[k] = mask;
    ek_room_times[k] = chrono::realtime::nanosecond / 1000000;
  }

  // the room's mask if received in the last 2 seconds:
  bool get_ek_room_mask(uint16 room, uint16 &out mask) {
    uint64 now = chrono::realtime::nanosecond / 1000000;
    for (uint i = 0; i < 4; i++) {
      if (ek_room_ids[i] != room) continue;
      if (now - ek_room_times[i] >= 2000) continue;
      mask = ek_room_masks[i];
      return true;
    }
    return false;
  }

  int deserialize_enemies_killed(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 1 > maxc) return maxc;
    uint8 kind = r[c++];
    if (kind == enemies_killed_uw) {
      if (c + 4 > maxc) return maxc;
      ek_id = uint32(r[c++]) | (uint32(r[c++]) << 8);
      ek_mask = uint16(r[c++]) | (uint16(r[c++]) << 8);
      ek_blks.resize(0);
    } else if (kind == enemies_killed_ow) {
      if (c + 4 > maxc) return maxc;
      ek_id = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16);
      uint n = r[c++];
      if (c + int(n) * 2 > maxc) return maxc;
      ek_blks.resize(n);
      for (uint i = 0; i < n; i++) {
        ek_blks[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      }
      ek_mask = 0;
    } else {
      // unknown kind; the rest of the packet cannot be parsed:
      return maxc;
    }
    if (!ek_valid || ek_kind != kind || ek_id != ek_logged_id || ek_mask != ek_logged_mask) {
      message("enemies killed: received from '" + name + "': kind " + fmtInt(kind) + " id " + fmtHex(ek_id, 6) + " mask " + fmtHex(ek_mask, 4) + " blks " + fmtInt(ek_blks.length()));
      ek_logged_id = ek_id;
      ek_logged_mask = ek_mask;
    }
    if (kind == enemies_killed_uw) {
      set_ek_room_mask(uint16(ek_id), ek_mask);
    }
    ek_kind = kind;
    ek_valid = true;
    return c;
  }

  int deserialize_location(array<uint8> r, int c) {
    uint8 last_module = module;
    module = r[c++];
    if (module == 0x07 && last_module != 0x07 && last_module != 0x0E) {
      // entering a dungeon resets its crystal switches; the state last received is of an earlier visit, and players
      // only send it while in the dungeon:
      crystal.reset();
    }
    sub_module = r[c++];
    sub_sub_module = r[c++];

    uint32 last = location;
    location = uint32(r[c++])
               | (uint32(r[c++]) << 8)
               | (uint32(r[c++]) << 16);
    actual_location = location;
    if (location != last) {
      // room and area specific state received so far belongs to the previous location:
      star_valid = false;
      flying_tiles_valid = false;
      rupees_valid = false;
      room_valid = false;
      room_doors_valid = false;
      ow_events_valid = false;
      manip.reset();
      map16.reset(0);
    }

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

    // the base of the location changes that follow (see Compact.as):
    loc_key_ok = true;
    loc_key_frame = this.frame;
    loc_key[0] = x;
    loc_key[1] = y;
    loc_key[2] = uint16(xoffs);
    loc_key[3] = uint16(yoffs);

    return c;
  }

  // deserialize_location_changes reads message 0x89: X, Y and the scroll offsets that differ from the full location
  // sent in the packet with frame number base.
  int deserialize_location_changes(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 2 > maxc) return maxc;
    uint8 base = r[c++];
    uint8 mask = r[c++];
    array<uint16> v = loc_key;
    for (uint i = 0; i < 4; i++) {
      if ((mask & (1 << i)) == 0) continue;
      if (c + 2 > maxc) return maxc;
      v[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
    }
    if (!loc_key_ok || loc_key_frame != base) {
      // relative to a full location we didn't get:
      return c;
    }
    x = v[0];
    y = v[1];
    xoffs = int16(v[2]);
    yoffs = int16(v[3]);
    calc_hitbox();
    return c;
  }

  // deserialize_small_keys_changes reads message 0x88: the dungeons' small keys that differ from the full small keys
  // sent in the packet with frame number base.
  int deserialize_small_keys_changes(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 2 > maxc) return maxc;
    uint8 base = r[c++];
    int count = r[c++];
    if (c + count * 8 > maxc) return maxc;
    array<uint8> body = sk_key;
    for (int i = 0; i < count; i++) {
      uint k = r[c++];
      uint o = 5 + k * 7;
      for (uint j = 0; j < 7; j++) {
        uint8 b = r[c++];
        if (o + j < body.length()) body[o + j] = b;
      }
    }
    if (!sk_key_ok || sk_key_frame != base) {
      // relative to full small keys we didn't get:
      return c;
    }
    deserialize_small_keys(body, 0, false);
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
    timeInRoom = uint16(r[c++]) | (uint16(r[c++]) << 8);
    sm_screen_x = uint16(r[c++]) | (uint16(r[c++]) << 8);
    sm_screen_y = uint16(r[c++]) | (uint16(r[c++]) << 8);

    return c;
  }

  int deserialize_sm_enemies(array<uint8> r, int c){
    // message("deserialize_sm_enemies");

    uint8 is_enemy = r[c++];
    if (is_enemy == 34){
      enemySyncEnabled = false;
      return c;
    } else {
      enemySyncEnabled = true;
    }
    uint8 enemy_index = r[c++];

    if(r[c++] == 0){
      enemies[enemy_index] = SM_Enemy(enemy_index);
      return c;
    }

    array<uint16> temp(0x20);

    for (uint i = 0; i < 32; i++) {
      temp[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
    }

    uint8 constructed_host_index = r[c++];
    enemies[enemy_index] = SM_Enemy(enemy_index, temp, constructed_host_index, r[c++] == 1);

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

  // the tiles of the player's facts its chrs $00-$1F are bound to (msg_sprite_chrs); 0xFFFF where not bound:
  array<uint8> chr_fact(0x20);
  array<uint16> chr_fact_tile(0x20, 0xFFFF);

  // deserialize_sprite_chrs reads msg_sprite_chrs, which replaces the player's bindings.
  int deserialize_sprite_chrs(array<uint8> r, int c) {
    for (uint i = 0; i < 0x20; i++) chr_fact_tile[i] = 0xFFFF;
    uint n = r[c++];
    for (uint i = 0; i < n; i++) {
      uint chr = r[c++];
      uint cnt = r[c++];
      uint8 fact = r[c++];
      uint16 tile = uint16(r[c++]);
      tile |= uint16(r[c++]) << 8;
      for (uint k = 0; k < cnt; k++) {
        if (chr + k >= 0x20) break;
        chr_fact[chr + k] = fact;
        chr_fact_tile[chr + k] = tile + uint16(k);
      }
    }
    resolve_sprite_chrs();
    return c;
  }

  // resolve_sprite_chrs fills chrs $00-$1F with the tiles of the player's facts they are bound to. A chr whose fact
  // isn't here yet (fact_data starts downloading it) stays empty, and chr_tile doesn't draw it.
  void resolve_sprite_chrs() {
    for (uint c = 0; c < 0x20; c++) {
      uint16 t = chr_fact_tile[c];
      if (t == 0xFFFF) {
        chrs[c].resize(0);
        continue;
      }
      auto @data = fact_data(uint16(index), chr_fact[c]);
      uint o = uint(t) * 32;
      if (data is null || o + 32 > data.length()) {
        chrs[c].resize(0);
        continue;
      }
      chrs[c].resize(16);
      for (uint k = 0; k < 16; k++) {
        chrs[c][k] = uint16(data[o + k * 2]) | (uint16(data[o + k * 2 + 1]) << 8);
      }
    }
  }

  // deserialize_sprite_palettes reads msg_sprite_palettes: a mask, then 16 colors for each palette in it.
  int deserialize_sprite_palettes(array<uint8> r, int c) {
    uint8 mask = r[c++];
    for (uint k = 0; k < 8; k++) {
      if ((mask & (1 << k)) == 0) continue;
      for (uint i = k << 4; i < (k << 4) + 16; i++) {
        palettes[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      }
    }
    return c;
  }

  // deserialize_sprites reads msg_sprites: the player's sprites, 5 bytes each (x, y, chr, attributes, ext), in OAM
  // order. They are drawn with the chrs bound to the player's facts, or the local VRAM's for unbound chrs.
  int deserialize_sprites(array<uint8> r, int c) {
    uint len = r[c++];
    sprites.resize(len);
    sprites_received = chrono::monotonic::millisecond;
    sprites_xoffs = xoffs;
    sprites_yoffs = yoffs;
    // a fact that arrived since the bindings did:
    resolve_sprite_chrs();

    for (uint i = 0; i < len; i++) {
      auto @spr = Sprite();
      @sprites[i] = spr;
      // OAM order: draw them from OAM index $40 on, in the same order:
      spr.index = uint8(0x40 + i) & 0x7F;
      spr.b0 = r[c++];
      spr.b1 = r[c++];
      spr.b2 = r[c++];
      spr.b3 = r[c++];
      spr.b4 = r[c++] & 3;
      spr.decodeOAMTableBytes();
      spr.uniq_absidx_0 = 0xFFFF;
      spr.uniq_absidx_1 = 0xFFFF;
      spr.uniq_absidx_2 = 0xFFFF;
      spr.uniq_absidx_3 = 0xFFFF;
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

  int deserialize_small_keys(array<uint8> r, int c, bool full = true) {
    int maxc = int(r.length());
    if (c + 5 > maxc) return maxc;
    if (full) {
      // the base of the small key changes that follow (see Compact.as):
      int n = r[c + 4];
      if (c + 5 + n * 7 <= maxc) {
        sk_key.resize(5 + n * 7);
        for (int i = 0; i < 5 + n * 7; i++) sk_key[i] = r[c + i];
        sk_key_ok = true;
        sk_key_frame = this.frame;
      }
    }

    uint32 session = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    int count = r[c++];
    if (c + count * 7 > maxc) return maxc;

    array<int16> net(small_key_count);
    array<uint8> value(small_key_count);
    array<uint32> ts(small_key_count);
    for (int k = 0; k < count; k++) {
      int16 n = int16(uint16(r[c++]) | (uint16(r[c++]) << 8));
      uint8 v = r[c++];
      uint32 t = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
      if (k < small_key_count) {
        net[k] = n;
        value[k] = v;
        ts[k] = t;
      }
    }

    if (this is local) return c;

    smallKeys.receive_remote(this, session, net, value, ts);
    return c;
  }

  // request_run_restore sends this player its run back in message 0x85, at most once in a while; it reported no start.
  void request_run_restore(RunTimingRemote@ rt, int64 s, int64 f) {
    uint64 now = chrono::monotonic::millisecond;
    if (restore_sent_ms != 0 && now - restore_sent_ms < run_restore_resend_ms) return;
    if (runReset.resetting || local.index < 0 || index < 0 || sock is null || this is local) return;
    restore_sent_ms = now;
    auto @envelope = local.make_packet_broadcast();
    uint mst = msg_begin(envelope, msg_run_restore);
    envelope.write_u8(run_restore_version);
    envelope.write_u8(run_restore_size);
    envelope.write_u16(uint16(index));
    for (uint i = 0; i < 20; i++) {
      envelope.write_u8(i < namePadded.length() ? namePadded[i] : 0x20);
    }
    rt_write_i64(envelope, int64(runReset.last_id));
    envelope.write_u16(runReset.last_initiator);
    envelope.write_u8(rt.flags & (rt_flag_started | rt_flag_finished | rt_flag_discontinuity | rt_flag_rate | rt_flag_state_load));
    rt_write_i64(envelope, s);
    rt_write_i64(envelope, f);
    envelope.write_u24(rt.start_frame);
    envelope.write_u24(rt.finish_frame);
    envelope.write_u24(rt.lag_frames);
    envelope.write_u32(rt.penalty_ms);
    msg_end(envelope, mst);
    local.send_packet(envelope, 0);
    message("run timing: " + rt_player_label(this) + " reports no start; sending it back (start " + rt_format_time(s) + ")");
    msg_end(envelope, mst);
  }

  // deserialize_run_restore reads message 0x85, after its type byte; the local player takes the run if it is for it.
  int deserialize_run_restore(const array<uint8> &in r, int c) {
    int maxc = int(r.length());
    if (c + 2 > maxc) return maxc;
    uint8 version = r[c++];
    int size = int(r[c++]);
    int end = c + size;
    if (end > maxc) return maxc;
    if (version != run_restore_version || size < int(run_restore_size) || this is local) return end;
    runTiming.restore_from(this, r, c);
    return end;
  }

  // deserialize_run_gap reads message 0x86: the player tells for how long it was disconnected. Every gap is noted once.
  int deserialize_run_gap(const array<uint8> &in r, int c) {
    int maxc = int(r.length());
    if (c + 2 > maxc) return maxc;
    uint8 version = r[c++];
    int size = int(r[c++]);
    int end = c + size;
    if (end > maxc) return maxc;
    if (version != run_gap_version || size < int(run_gap_size) || this is local) return end;
    uint8 kind = r[c];
    int64 lost = rt_read_i64(r, c + 1);
    int64 back = rt_read_i64(r, c + 9);
    if (lost <= 0 || back < lost || back - lost > run_gap_max_ns) return end;
    for (uint i = 0; i < gaps_seen_lost.length(); i++) {
      if (gaps_seen_lost[i] == lost && gaps_seen_kind[i] == kind) return end;
    }
    gaps_seen_kind.insertLast(kind);
    gaps_seen_lost.insertLast(lost);
    if (gaps_seen_lost.length() > 16) {
      gaps_seen_kind.removeAt(0);
      gaps_seen_lost.removeAt(0);
    }
    notificationSystem.notify(rt_describe_gap(this, kind, lost, back));
    return end;
  }

  int deserialize_reset(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 11 > maxc) return maxc;
    uint8 phase = r[c++];
    uint64 id = uint64(rt_read_i64(r, c)); c += 8;
    uint16 initiator = uint16(r[c]) | (uint16(r[c+1]) << 8); c += 2;
    if (this is local || index < 0) return c;
    if (phase == reset_phase_idle || phase > reset_phase_finalize) return c;
    runReset.receive(index, phase, id, initiator);
    return c;
  }

  int deserialize_hearts(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 7 > maxc) return maxc;

    uint32 session = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    int16 net = int16(uint16(r[c++]) | (uint16(r[c++]) << 8));
    uint8 value = r[c++];

    if (this is local) return c;

    heartsSync.receive_remote(this, session, net, value);
    return c;
  }

  int deserialize_wram(array<uint8> r, int c) {
    auto count = r[c++];
    auto offs = uint16(r[c++]) | (uint16(r[c++]) << 8);

    if (offs == crystal.offs) {
      // no need for count loop since there's only one byte:
      c = crystal.deserialize(r, c);
    } else {
      // discard data we don't understand yet:
      for (uint i = 0; i < count; i++) {
        c = SyncableByte(offs + i).deserialize(r, c);
      }
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
    in_sm = r[c++];

    uint16 start = uint16(r[c++]) | (uint16(r[c++]) << 8);
    uint16 count = uint16(r[c++]) | (uint16(r[c++]) << 8);

    for (uint i = 0; i < count; i++) {
      auto offs = start + i;
      auto b = r[c++];

      sram[offs] = b;
    }

    if (!(this is local) && start < 0x340 && uint(start) + count > 0x280) {
      // apply overworld area flags right away, e.g. to remove a heart piece another player collected:
      overworld_flags_received = true;
    }

    return c;
  }
  
  int deserialize_sm_sram(array<uint8> r, int c) {
    for (uint i = 0; i < 0x40; i++) {
      auto b = r[c++];

      sm_sram[i] = b;
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
    enemy_data_received = chrono::monotonic::millisecond;
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
          continue;
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
          for (uint x = 0; x < 4; x++) {
            for (uint i = 0; i < 0x80; i++) {
              enemySegments[(x * 0x80) + i] = r[c++];
            }
          }
          break;
        case 0x18: // mini moldorm:
          if (s >= 4) continue;
          for (uint x = 0; x < 4; x++) {
            for (uint i = 0; i < 0x20; i++) {
              enemySegments[(x * 0x80) + (s * 0x20) + i] = r[c++];
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

  int deserialize_overlord_data(array<uint8> r, int c) {
    uint8 mask = r[c++];
    for (uint s = 0; s < 8; s++) {
      if ((mask & (1 << s)) == 0) {
        overlordU8Data[(ol8_id<<3)+s] = 0;
        continue;
      }

      for (uint x = 0; x < overlord_u8_ptrs.length(); x++) {
        overlordU8Data[(x<<3)+s] = r[c++];
      }
      for (uint x = 0; x < overlord_u16_ptrs.length(); x++) {
        overlordU16Data[(x<<4)+(s<<1)  ] = r[c++];
        overlordU16Data[(x<<4)+(s<<1)+1] = r[c++];
      }
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

            {
              // the chr bound to the player's fact, or the local VRAM's (see chr_tile):
              auto @t = chr_tile(sprite.chr);
              if (t.length() != 0) localFrameState.overwrite_tile(ppu::vram.chr_address(k), t);
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
            {
              // the chr bound to the player's fact, or the local VRAM's (see chr_tile):
              auto @t = chr_tile(sprite.chr + 0x00);
              if (t.length() != 0) localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x00), t);
            }
            {
              // the chr bound to the player's fact, or the local VRAM's (see chr_tile):
              auto @t = chr_tile(sprite.chr + 0x01);
              if (t.length() != 0) localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x01), t);
            }
            {
              // the chr bound to the player's fact, or the local VRAM's (see chr_tile):
              auto @t = chr_tile(sprite.chr + 0x10);
              if (t.length() != 0) localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x10), t);
            }
            {
              // the chr bound to the player's fact, or the local VRAM's (see chr_tile):
              auto @t = chr_tile(sprite.chr + 0x11);
              if (t.length() != 0) localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x11), t);
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

  // chr_tile returns the tile data of chr c for drawing the remote player's sprites: the data the remote player sent, or
  // else the local VRAM's chr as it is now. Players don't send data for chrs from the common sprite sheets (alttpo
  // for chrs $80 and up, o2 for any chr but Link's), which are loaded per area, so the local chr is read every frame
  // and never kept: a copy kept from another area showed e.g. a dungeon's pot for a bush carried outside.
  array<uint16> vram_chr(16);
  array<uint16> @chr_tile(uint c) {
    if (chrs[c].length() != 0) return chrs[c];
    // one of the player's chrs bound to a fact that isn't here yet: not drawn:
    if (c < 0x20 && chr_fact_tile[c] != 0xFFFF) {
      vram_chr.resize(0);
      return vram_chr;
    }
    vram_chr.resize(16);
    ppu::vram.read_block(ppu::vram.chr_address(c), 0, 16, vram_chr);
    return vram_chr;
  }

  int renderToExtra(int dx, int dy, int ei) {
    uint len = sprites.length();
    // message("renderToExtra " + fmtInt(len));
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
      array<uint16> @t;
      if (sprite.uniq_absidx_0 == 0xFFFF) {
        @t = chr_tile(k + 0x00);
      } else {
        @t = uniqtile_get(sprite.uniq_absidx_0);
        if (t.length() == 0) {
          insertUnique(missing_uniq_absidx, sprite.uniq_absidx_0);
        }
      }
      if (t.length() > 0) {
        tile.draw_sprite_4bpp(0, 0, p, t, palettes);
      }

      if (sprite.size != 0) {
        if (sprite.uniq_absidx_1 == 0xFFFF) {
          @t = chr_tile(k + 0x01);
        } else {
          @t = uniqtile_get(sprite.uniq_absidx_1);
          if (t.length() == 0) {
            insertUnique(missing_uniq_absidx, sprite.uniq_absidx_1);
          }
        }
        if (t.length() > 0) {
          tile.draw_sprite_4bpp(8, 0, p, t, palettes);
        }

        if (sprite.uniq_absidx_2 == 0xFFFF) {
          @t = chr_tile(k + 0x10);
        } else {
          @t = uniqtile_get(sprite.uniq_absidx_2);
          if (t.length() == 0) {
            insertUnique(missing_uniq_absidx, sprite.uniq_absidx_2);
          }
        }
        if (t.length() > 0) {
          tile.draw_sprite_4bpp(0, 8, p, t, palettes);
        }

        if (sprite.uniq_absidx_3 == 0xFFFF) {
          @t = chr_tile(k + 0x11);
        } else {
          @t = uniqtile_get(sprite.uniq_absidx_3);
          if (t.length() == 0) {
            insertUnique(missing_uniq_absidx, sprite.uniq_absidx_3);
          }
        }
        if (t.length() > 0) {
          tile.draw_sprite_4bpp(8, 8, p, t, palettes);
        }
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
    uint16 abs_x = (uint16(sm_x) << 8) + uint16(sm_sub_x);
    uint16 abs_y = (uint16(sm_y) << 8) + uint16(sm_sub_y);

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

    label.x = (abs_x - sm_screen_x + dx + 8) - (label.width >> 1);
    label.y = (abs_y - sm_screen_y + 17 + dy) + 8;

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
};
