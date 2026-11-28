// o2-server protocol 0x05 and game protocol v2 (see o2-server's PROTOCOL05.md), shared with o2.
//
// Every packet starts with u16 0x651F, u8 0x05 (protocol), u8 kind. All integers are little-endian. The data of
// broadcasts, relays and fact chunks runs to the end of the datagram.

const uint8 p5_protocol = 0x05;

// client -> server kinds:
const uint8 p5_join_group = 0x01;
const uint8 p5_leave_group = 0x02;
const uint8 p5_join_sector = 0x03;
const uint8 p5_leave_sector = 0x04;
const uint8 p5_echo = 0x05;
const uint8 p5_who_is = 0x06;
const uint8 p5_fact_put = 0x07;
const uint8 p5_fact_get = 0x08;
const uint8 p5_broadcast_all = 0x09;
const uint8 p5_broadcast_sector = 0x0A;
// broadcast-sectors: `u8 n (1..8), n x u32 sector, data`; the server relays it once, as a relay-sector, to every
// client in any of the sectors (only when the join-ack had p5_ack_multi_sector):
const uint8 p5_broadcast_sectors = 0x0C;

// server -> client kinds:
const uint8 p5_join_ack = 0x81;
const uint8 p5_join_nak = 0x82;
const uint8 p5_sector_ack = 0x83;
const uint8 p5_echo_reply = 0x84;
const uint8 p5_player_info = 0x85;
const uint8 p5_player_left = 0x86;
const uint8 p5_fact_status = 0x87;
const uint8 p5_fact_list = 0x88;
const uint8 p5_fact_data = 0x89;
const uint8 p5_relay_all = 0x8A;
const uint8 p5_relay_sector = 0x8B;

// join-ack flags, the optional u8 after the server time (older servers send none):
const uint8 p5_ack_spectator = 0x01;     // the join was taken as a spectator's (alttpo never asks to be one)
const uint8 p5_ack_multi_sector = 0x02;  // the server takes set-sectors and broadcast-sectors

// join-nak reasons (the nak's body is the reason byte; 0 and 1 are not joined and group full):
const uint8 p5_nak_auth_required = 2;    // the group has a password and the join had no token
const uint8 p5_nak_auth_failed = 3;      // the token isn't the group's
const uint8 p5_nak_auth_unexpected = 4;  // the group exists without a password, or the auth field is malformed

// Group passwords keep uninvited players out of a group; they don't hold up against someone who can see the network's
// packets. A join-group may end with an auth field, `u8 32, token`, where token is SHA-256("o2-p5-group:" || password).
// The first player to join a group that doesn't exist sets its token; every later join of that group must carry the
// same one. No password, no auth field. p5_auth_token returns the token as 64 hex digits, or "" without a password.
string p5_auth_token(const string &in password) {
  if (password.length() == 0) return "";
  return sha256("o2-p5-group:" + password);
}

// fact-status states:
const uint8 p5_fact_receiving = 0;
const uint8 p5_fact_complete = 1;
const uint8 p5_fact_rejected = 2;

const uint p5_fact_chunk_size = 1024;
const uint p5_fact_max_size = 65536;
const uint p5_hash_size = 16;

// Game protocol v2: a broadcast is `u8 frame`, then messages of `u8 type, length, body`; the length is 1 byte below
// 0x80, or 2 bytes (0x80 | low 7 bits, then the high 8 bits). Receivers skip message types they don't know by their
// length. The info blob of a join-group is `u8 script_protocol, u8 team`.
const uint8 msg_location = 0x01;
const uint8 msg_location_changes = 0x02;
const uint8 msg_sfx = 0x03;
const uint8 msg_sprites = 0x04;
const uint8 msg_sprite_chrs = 0x05;
const uint8 msg_sprite_palettes = 0x06;
const uint8 msg_wram = 0x07;
const uint8 msg_sram = 0x08;
const uint8 msg_ancillae = 0x09;
const uint8 msg_torches = 0x0A;
const uint8 msg_pvp = 0x0B;
const uint8 msg_map16 = 0x0C;
const uint8 msg_manip = 0x0D;
const uint8 msg_star_switch = 0x0E;
const uint8 msg_room_state = 0x0F;
const uint8 msg_room_doors = 0x10;
const uint8 msg_ow_events = 0x11;
const uint8 msg_flying_tiles = 0x12;
const uint8 msg_room_kills = 0x13;
const uint8 msg_enemies_killed = 0x14;
const uint8 msg_rupees = 0x15;
const uint8 msg_enemy_data = 0x16;
const uint8 msg_enemy_segment_data = 0x17;
const uint8 msg_overlord_data = 0x18;
const uint8 msg_small_keys = 0x19;
const uint8 msg_small_keys_changes = 0x1A;
const uint8 msg_hearts = 0x1B;
const uint8 msg_reset = 0x1C;
const uint8 msg_run_timing = 0x1D;
const uint8 msg_run_restore = 0x1E;
const uint8 msg_run_gap = 0x1F;
const uint8 msg_sm_location = 0x20;
const uint8 msg_sm_events = 0x21;
const uint8 msg_sm_sram = 0x22;
const uint8 msg_sm_enemies = 0x23;
const uint8 msg_consumables = 0x24;
// sprites that carry their own tiles (the item Link holds up or that rises from a chest); see o2's sprites.go:
const uint8 msg_sprite_tiles = 0x25;
// progressive sword, shield, mail and gloves levels gained, in the VT randomizers; see Progressive.as:
const uint8 msg_progressive = 0x26;

const uint msg_max_len = 0x7FFF;

// msg_begin starts a message of the given type at the end of r and returns where it starts, for msg_end.
uint msg_begin(array<uint8> &r, uint8 type) {
  uint start = r.length();
  r.write_u8(type);
  return start;
}

// msg_end inserts the length of the message that starts at start (see msg_begin) after its type.
void msg_end(array<uint8> &r, uint start) {
  uint n = r.length() - start - 1;
  if (n < 0x80) {
    r.insertAt(start + 1, uint8(n));
  } else {
    r.insertAt(start + 1, uint8(0x80 | (n & 0x7F)));
    r.insertAt(start + 2, uint8((n >> 7) & 0xFF));
  }
}

// write_msg appends m, one message (its type, then its body) without a length, framed.
void write_msg(array<uint8> &r, const array<uint8> &in m) {
  if (m.length() == 0) return;
  uint start = r.length();
  r.write_arr(m);
  msg_end(r, start);
}

// msg_read_len reads a message length at r[c], returning it, or -1 if r ends; width is the bytes it took.
int msg_read_len(const array<uint8> &in r, int c, int &out width) {
  int maxc = int(r.length());
  width = 0;
  if (c >= maxc) return -1;
  int n = r[c];
  width = 1;
  if (n < 0x80) return n;
  if (c + 1 >= maxc) return -1;
  width = 2;
  return (n & 0x7F) | (int(r[c + 1]) << 7);
}

// p5_packet starts a client -> server packet of the given kind.
array<uint8> @p5_packet(uint8 kind) {
  array<uint8> @b = {};
  b.reserve(MaxPacketSize);
  b.write_u16(uint16(25887));
  b.write_u8(p5_protocol);
  b.write_u8(kind);
  return b;
}

uint16 p5_u16(const array<uint8> &in r, int c) {
  return uint16(r[c]) | (uint16(r[c+1]) << 8);
}

uint32 p5_u32(const array<uint8> &in r, int c) {
  return uint32(r[c]) | (uint32(r[c+1]) << 8) | (uint32(r[c+2]) << 16) | (uint32(r[c+3]) << 24);
}

uint64 p5_u64(const array<uint8> &in r, int c) {
  uint64 v = 0;
  for (int i = 7; i >= 0; i--) {
    v = (v << 8) | uint64(r[c + i]);
  }
  return v;
}

// p5_expand_server_time rebuilds a full server time (ns since the Unix epoch) from the low 16 bits of its Unix
// milliseconds: the latest time no later than estimate + 1 s whose low 16 bits match.
int64 p5_expand_server_time(uint16 ms, int64 estimate_ns) {
  int64 limit = estimate_ns / 1000000 + 1000;
  int64 t = (limit & ~int64(0xFFFF)) | int64(ms);
  if (t > limit) t -= 0x10000;
  return t * 1000000;
}
