// Overworld map16 change synchronization, wire-compatible with o2 (see o2's games/alttp/syncmap16.go and
// ALTTPO_COMPAT.md).
//
// The game records every persistent map16 change it makes in the current overworld area (lifted bushes and rocks,
// bombed walls, opened entrances, ...) in a log so that it can restore them after a mirror bonk
// (MirrorBonk_RecoverChangedTiles):
//
//   - $7E04AC is the byte index of the next free log entry. Every area load resets it to 0.
//   - $7EF800 is a [$A0]uint16 array of the tilemap offsets ($7E2000,X) of the changed tiles.
//   - $7EFA00 is a [$A0]uint16 array of the map16 tiles written there.
//
// Overworld_MemorizeMap16Change appends to the log (except for cut grass and dirt patches, which the game never
// restores) and Overworld_DoMapUpdate32x32 appends four entries at once.
//
// The log is shared with the players in the same area in message 0x17 in broadcastSector packets:
//   uint16 area ($8A), uint8 count (entries in the sender's log), uint8 start, uint8 len, then len entries of
//   uint16 pos, uint16 tile for log indices [start, start+len).
// New entries are sent as soon as they are seen and the whole log is sent every 16 frames so players entering the
// area catch up.
//
// Each receiver remembers how far into each remote player's log it has applied and only applies newly added entries.
// Applying an entry skips it if $7E2000,X already holds the tile, otherwise appends it to the local log (so it survives
// a mirror bonk and is passed on to players who enter the area later) and calls Overworld_DrawMap16_Persist if VRAM
// holds it (always in small areas; rows/columns -7..+23 of $84 in large areas); other tiles are only written to
// $7E2000 and drawn by the game as it scrolls.

const uint8 msg_map16 = 0x17;
const int map16_log_max = 0xA0;
const int map16_chunk_max = 0x40;

// map16 change log of a remote player as received:
class Map16Remote {
  uint16 area = 0;
  int count = 0;
  array<uint16> pos(0xA0);
  array<uint16> tile(0xA0);
  array<bool> have(0xA0);
  // how many entries of this log were applied locally:
  int applied = 0;

  void reset(uint16 area) {
    this.area = area;
    count = 0;
    applied = 0;
    for (uint i = 0; i < have.length(); i++) {
      have[i] = false;
    }
  }

  int deserialize(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 5 > maxc) return maxc;

    uint16 a = uint16(r[c++]) | (uint16(r[c++]) << 8);
    int n = r[c++];
    int start = r[c++];
    int len = r[c++];
    if (c + len * 4 > maxc) return maxc;
    if (n > map16_log_max || start + len > n) return c + len * 4;

    if (a != area || n < count) {
      // another area, or the sender's area was reloaded:
      reset(a);
    }
    count = n;
    for (int k = 0; k < len; k++) {
      int i = start + k;
      uint16 p = uint16(r[c++]) | (uint16(r[c++]) << 8);
      uint16 t = uint16(r[c++]) | (uint16(r[c++]) << 8);
      if (have[i] && (pos[i] != p || tile[i] != t) && i < applied) {
        // the sender's log was replaced without us noticing; apply again from here:
        applied = i;
      }
      pos[i] = p;
      tile[i] = t;
      have[i] = true;
    }
    return c;
  }
};

// local player's map16 change log:
class Map16Sync {
  // valid is true when the log was read in an overworld module for area:
  bool valid = false;
  uint16 area = 0;
  int count = 0;
  array<uint16> pos(0xA0);
  array<uint16> tile(0xA0);
  // how many entries were already sent:
  int sent = 0;
  // calls to send() since the whole log was last sent:
  int sendsSinceFull = 0;

  void reset() {
    valid = false;
    count = 0;
    sent = 0;
    reset_applied();
  }

  // the local tilemap was (re)loaded; apply all remote changes again:
  void reset_applied() {
    for (uint i = 0; i < players.length(); i++) {
      auto @p = players[i];
      if (p is null) continue;
      p.map16.applied = 0;
    }
  }

  // called every frame from LocalGameState::fetch:
  // log_belongs_to_area returns false while Link lands from a mirror or portal warp. The warp (Module09_MirrorWarp)
  // changes the area and returns to submodule 0 but keeps the previous area's log, which LinkState_CrossingWorlds only
  // resets once Link lands in the other world (and keeps for a mirror bonk, which takes him back to that area). Reading
  // it before would send the previous area's changes as changes of the new area.
  bool log_belongs_to_area() {
    // kPlayerState_Mirror:
    return bus::read_u8(0x7E005D) != 0x14;
  }

  void fetch() {
    if (local.module == 0x0E) {
      // menus don't touch the log:
      return;
    }
    if (!local.is_in_overworld_module()) {
      // the next area load resets the log:
      if (valid) reset();
      return;
    }

    uint16 a = bus::read_u16(0x7E008A);
    if (valid && a != area) {
      reset();
    }
    // area loads reset the log in other submodules:
    if (local.sub_module != 0) return;
    if (!log_belongs_to_area()) return;

    int n = int(bus::read_u16(0x7E04AC));
    if ((n & 1) != 0 || n > (map16_log_max << 1)) return;
    n >>= 1;

    if (!valid) {
      valid = true;
      area = a;
      count = 0;
      sent = 0;
      reset_applied();
    }
    if (n < count) {
      // the area was reloaded:
      count = 0;
      sent = 0;
      reset_applied();
    }
    for (int i = count; i < n; i++) {
      pos[i] = bus::read_u16(0x7EF800 + uint32(i << 1));
      tile[i] = bus::read_u16(0x7EFA00 + uint32(i << 1));
    }
    count = n;
  }

  void serialize(array<uint8> &r, int start, int end) {
    r.write_u8(msg_map16);
    r.write_u16(area);
    r.write_u8(uint8(count));
    r.write_u8(uint8(start));
    r.write_u8(uint8(end - start));
    for (int i = start; i < end; i++) {
      r.write_u16(pos[i]);
      r.write_u16(tile[i]);
    }
  }

  // sends the new entries of the log, and the whole log every 16 frames, to the players in the same area:
  uint send(uint p) {
    if (!valid) return p;
    // menus and text boxes ($0E) keep the log; keep sending it so players entering the area still catch up:
    if (!local.is_in_overworld_module() && local.module != 0x0E) return p;

    // resend the whole log every 16 calls rather than on frames with (frame & 15) == 0: send() is skipped by the net
    // rate limiter whenever frames come in faster than 16ms apart, which can skip those frames every time:
    int start = sent;
    if (++sendsSinceFull >= 16) {
      sendsSinceFull = 0;
      start = 0;
    } else if (start >= count) {
      return p;
    }

    while (true) {
      int end = start + map16_chunk_max;
      if (end > count) end = count;
      array<uint8> @r = local.make_packet_broadcast_to_sector(local.broadcast_sector());
      serialize(r, start, end);
      p = local.send_packet(r, p);
      start = end;
      if (start >= count) break;
    }
    sent = count;
    return p;
  }

  // append a change to the local log like Overworld_MemorizeMap16Change, if it has room:
  void memorize(uint16 p, uint16 t) {
    uint16 x = bus::read_u16(0x7E04AC);
    if (x >= uint16(map16_log_max << 1)) return;
    bus::write_u16(0x7EFA00 + x, t);
    bus::write_u16(0x7EF800 + x, p);
    bus::write_u16(0x7E04AC, uint16(x + 2));
  }

  // called every frame from on_main_alttp; apply the remote changes not applied yet:
  void update() {
    if (!settings.SyncTilemap) return;
    if (!valid) return;
    if (!local.is_in_overworld_module() || local.sub_module != 0) return;
    if (bus::read_u16(0x7E008A) != area) return;
    if (!log_belongs_to_area()) return;
    uint32 fn = rom.fn_overworld_draw_map16_persist;
    if (fn == 0) return;

    // small areas ($0712 = 0) are entirely in VRAM and never stream tiles while scrolling, so always draw there.
    // large areas keep a 32x32 map16 ring in VRAM around $84 (the scroll position in the tilemap): the area load
    // draws rows -7..+24 and columns -8..+23, and scrolling draws the next row or column (-8 or +24) from $7E2000
    // before moving $84, even if it was in VRAM already. Rows and columns -7..+23 are always in VRAM; anything else is
    // drawn by the game when scrolled to:
    bool small_area = bus::read_u8(0x7E0712) == 0;
    uint16 s84 = bus::read_u16(0x7E0084);
    int row0 = int(s84 & 0x1F80) >> 7;
    int col0 = int(s84 & 0x007E) >> 1;
    int stripe = int(bus::read_u16(0x7E1000));
    bool started = false;
    array<uint16> written;

    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (remote.get_in_sm()) continue;
      // game worlds are team specific:
      if (remote.team != local.team) continue;
      if (!local.is_really_in_same_location(remote.location)) continue;
      auto @rm = remote.map16;
      if (rm.area != area) continue;

      // keep only the latest tile for each position among the new entries:
      array<uint16> ps;
      array<uint16> ts;
      int end = rm.applied;
      for (; end < rm.count && rm.have[end]; end++) {
        int k = ps.find(rm.pos[end]);
        if (k >= 0) {
          ts[k] = rm.tile[end];
        } else {
          ps.insertLast(rm.pos[end]);
          ts.insertLast(rm.tile[end]);
        }
      }
      if (end == rm.applied) continue;

      bool done = true;
      for (uint k = 0; k < ps.length(); k++) {
        uint16 p = ps[k];
        uint16 t = ts[k];
        if (written.find(p) >= 0) continue;
        if (bus::read_u16(0x7E2000 + p) == t) continue;

        int dr = (int(p & 0x1F80) >> 7) - row0;
        int dc = (int(p & 0x007E) >> 1) - col0;
        bool near = small_area || (dr >= -7 && dr < 24 && dc >= -7 && dc < 24);
        if (near) {
          // REP + LDA + LDX + JSL, and SEP + LDA + STA to finish:
          if (stripe + 0x10 > 0x80 || pb.offset + 2 + 10 + 7 + 5 > 0x100) {
            // continue next frame; what was applied is skipped then:
            done = false;
            break;
          }
          if (!started) {
            pb.rep(0x30);
            started = true;
          }
          memorize(p, t);
          pb.lda_immed16(t);
          pb.ldx_immed16(p);
          pb.jsl(fn);
          stripe += 0x10;
        } else {
          memorize(p, t);
          bus::write_u16(0x7E2000 + p, t);
        }
        written.insertLast(p);
      }
      if (!done) break;
      rm.applied = end;
    }

    if (started) {
      pb.sep(0x30);
      // upload the stripes in NMI:
      pb.lda_immed(0x01);
      pb.sta_bank(0x0014);
    }
  }
};

Map16Sync map16Sync;
