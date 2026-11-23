// Rupee floor synchronization, wire-compatible with o2 (see o2's games/alttp/syncrupees.go and ALTTPO_COMPAT.md).
//
// Some dungeon rooms have a rupee floor (room object $12 of subtype 3): 3x3 rupees of 8x16 pixels drawn into the lower
// layer's tilemap ($7E2000) with tile attribute $60 in $7F2000, e.g. in the north east quadrant of the Palace of
// Darkness room $099. Walking over one gives 5 rupees and calls DeleteRupeeTile with $00/$02 = Y/X, which replaces its
// two tiles and attributes, queues a VRAM stripe ($1000) and sets $0403 bit $10. A room whose $0403 bit $10 is set when
// it loads has no rupees at all, but the rupees collected while another player is in the room were only gone for them
// once they reloaded the room.
//
//   - A PC interceptor at DeleteRupeeTile logs the tilemap offset of each rupee deleted ((y/8 * 64 + x/8) * 2, the
//     routine's $06) with the room ($A0); a rupee deleted in another room empties the log.
//   - It is sent in message 0x20 (uint16 room, uint8 count, count * uint16 pos) in a broadcastSector packet to the
//     current room's sector, in the dungeon module while the log is for the current room. A receiver drops a player's
//     rupees whenever that player's location changes.
//   - A player deletes the rupees that remote players in the same room deleted, by calling DeleteRupeeTile without
//     giving the rupees, for the positions whose attribute is still $60 (and at most 4 a frame, since each queues a
//     VRAM stripe). The rupees deleted this way are logged too, so they are passed on to players who enter later.

const uint rupees_max = 32;
const uint8 rupee_tile_attr = 0x60;
const uint rupees_per_frame = 4;
// DeleteRupeeTile queues $18 bytes of VRAM stripes at $1000; none are queued past this offset:
const uint16 rupee_stripe_limit = 0x0068;

class RupeesLocal {
  // the room of the rupees logged, and their tilemap offsets:
  uint16 log_room = 0;
  array<uint16> log;

  // the room the local player is in, while in the dungeon module, and the remote rupees handled in this room visit:
  bool valid = false;
  uint16 room = 0;
  array<uint16> done;

  void reset() {
    valid = false;
    done.resize(0);
  }

  bool has(const array<uint16> &in list, uint16 pos) {
    for (uint i = 0; i < list.length(); i++) {
      if (list[i] == pos) return true;
    }
    return false;
  }

  // called by the PC interceptor at DeleteRupeeTile:
  void deleted(uint16 r, uint16 x, uint16 y) {
    if (r != log_room) {
      log_room = r;
      log.resize(0);
    }
    uint16 pos = uint16((((y & 0x1F8) << 3) | ((x & 0x1F8) >> 3)) << 1);
    if (has(log, pos) || log.length() >= rupees_max) return;
    log.insertLast(pos);
  }

  // called every frame from LocalGameState::update_wram:
  void update() {
    auto module = local.module;
    if (module == 0x0E) {
      // menus keep the room:
      return;
    }
    if (module != 0x07) {
      reset();
      return;
    }
    auto r = bus::read_u16(0x7E00A0);
    if (!valid || r != room) {
      reset();
      valid = true;
      room = r;
    }
    if (!settings.SyncUnderworldLocal) return;
    if (local.sub_module != 0x00) return;
    if (rom.fn_delete_rupee_tile == 0) return;

    uint n = 0;
    uint16 stripes = bus::read_u16(0x7E1000);
    uint len = players.length();
    for (uint i = 0; i < len && n < rupees_per_frame; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != local.team) continue;
      if (remote.get_in_sm()) continue;
      if (remote.module != 0x07) continue;
      if (!local.is_really_in_same_location(remote.location)) continue;
      if (!remote.rupees_valid || remote.rupees_room != room) continue;

      for (uint j = 0; j < remote.rupees_pos.length() && n < rupees_per_frame; j++) {
        uint16 pos = remote.rupees_pos[j];
        if (pos >= 0x2000 || (pos & 1) != 0) continue;
        if (has(done, pos)) continue;
        if (log_room == room && has(log, pos)) continue;
        uint16 t = pos >> 1;
        if (bus::read_u8(0x7F2000 + t) != rupee_tile_attr) {
          // not here (any more):
          done.insertLast(pos);
          continue;
        }
        // room for the VRAM stripe, and for the code in the patch buffer (20 bytes, and 5 to end it):
        if (stripes + n * 0x18 >= rupee_stripe_limit) return;
        if (int(pb.offset) + 20 > 0x100 - 5) return;

        uint16 x = (t & 0x3F) << 3;
        uint16 y = (t >> 6) << 3;
        pb.lda_immed(uint8(y));
        pb.sta_dp(0x00);
        pb.lda_immed(uint8(y >> 8));
        pb.sta_dp(0x01);
        pb.lda_immed(uint8(x));
        pb.sta_dp(0x02);
        pb.lda_immed(uint8(x >> 8));
        pb.sta_dp(0x03);
        pb.jsl(rom.fn_delete_rupee_tile);
        done.insertLast(pos);
        n++;
      }
    }
  }

  void serialize(array<uint8> &r) {
    if (!valid || log_room != room || log.length() == 0) return;
    uint mst = msg_begin(r, msg_rupees);
    r.write_u16(room);
    r.write_u8(uint8(log.length()));
    for (uint i = 0; i < log.length(); i++) {
      r.write_u16(log[i]);
    }
    msg_end(r, mst);
  }
};

RupeesLocal rupees;

void init_rupees() {
  if (rom.fn_delete_rupee_tile == 0) return;
  cpu::register_pc_interceptor(rom.fn_delete_rupee_tile, @on_delete_rupee_tile);
}

// called at the start of DeleteRupeeTile, with $00/$02 = Y/X of the rupee:
void on_delete_rupee_tile(uint32 pc) {
  if (local is null || local.get_in_sm()) return;
  rupees.deleted(bus::read_u16(0x7E00A0), bus::read_u16(0x7E0002), bus::read_u16(0x7E0000));
}
