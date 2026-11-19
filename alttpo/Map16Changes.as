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
// The log is shared with the other players in message 0x17:
//   uint24 location, uint8 count (entries in the sender's log), uint8 start, uint8 len, then len entries of
//   uint16 pos, uint16 tile for log indices [start, start+len).
// New entries are sent as soon as they are seen and the whole log every 32 frames. It is sent to all players
// (broadcastAll), not just to those in the same area, so that a player entering the area already has the changes
// while the area loads (see on_overworld_area_load).
//
// The location is the one the log was read in, encoded like the location in message 0x01: bit 17 the dark world
// ($0FFF & 1), bit 16 the underworld (0) and bits 0-15 the area ($8A). The log is only read, and changes are only
// applied, while $0FFF agrees with the area's world (areas $40-$7F are the dark world), which it does not while a
// warp switches worlds, and changes are only applied in exactly the sender's location, which must also be the
// sender's current location.
//
// Every overworld area load (scroll transitions, coming out of the underworld or a special area before the spotlight
// opens, warps, the flute, the reload after a mirror bonk) decompresses the area's tilemap into $7E2000 and then calls
// Overworld_HandleOverlaysAndBombDoors, which applies the area's overlay and bombed doors to it, before anything is
// drawn from it. A PC interceptor there writes the remote changes for the area being loaded to $7E2000 first, so the
// game draws them itself and they appear seamlessly (see on_overworld_area_load).
//
// Each receiver remembers how far into each remote player's log it has applied and only applies newly added entries.
// Applying an entry appends it to the local log (so it survives a mirror bonk and is passed on to players who enter the
// area later). If $7E2000,X already holds the tile (applied while the area loaded), that is all; otherwise it calls
// Overworld_DrawMap16_Persist if VRAM holds it (always in small areas; rows/columns -7..+23 of $84 in large areas);
// other tiles are only written to $7E2000 and drawn by the game as it scrolls.
//
// An entry that arrives while the local player has been in the area for a while (longer than the senders take to
// resend their whole log, so not while catching up) is live: the remote player changed the tile just now. If a live
// entry replaces a bush, rock or sign that is still there locally, the secret under it is revealed too (see
// Secrets.as).
//
// Bombing open a cave or house wall (Overworld_BombTile) logs the opening's right half ($0DB5) at the left half's
// position instead of 2 bytes to the right of it: the log has ($pos, $0DB4) followed by ($pos, $0DB5). Applied as
// logged, the right half would replace the left half one tile left of where it belongs, and the opening could not be
// entered. Such an entry is taken as ($pos + 2, $0DB5) both when the local log is read and when a remote log is received
// (see map16_fix_entry).

const uint8 msg_map16 = 0x17;

// the bombed wall opening Overworld_BombTile draws (left and right half), which it logs at the same position:
const uint16 map16_bomb_door_left = 0x0DB4;
const uint16 map16_bomb_door_right = 0x0DB5;

// map16_fix_entry returns the position the entry (p, t) changed, given the entry before it in the same log (pp, pt):
// Overworld_BombTile logs the right half of a bombed opening at the left half's position.
uint16 map16_fix_entry(uint16 pp, uint16 pt, uint16 p, uint16 t) {
  if (t == map16_bomb_door_right && pt == map16_bomb_door_left && pp == p) return uint16(p + 2);
  return p;
}

// ow_location returns the overworld location Link is in, like the location sent in message 0x01 (bit 17 dark world,
// bit 16 underworld = 0, bits 0-15 the area $8A), or 0xFFFFFFFF if $0FFF does not agree with the area's world (the dark
// world areas are $40-$7F), which happens while a mirror or portal warp switches worlds.
const uint32 ow_location_none = 0xFFFFFFFF;
uint32 ow_location() {
  uint16 area = bus::read_u16(0x7E008A);
  uint32 world = bus::read_u8(0x7E0FFF) & 1;
  if (((uint32(area) >> 6) & 1) != world) return ow_location_none;
  return (world << 17) | uint32(area);
}
const int map16_log_max = 0xA0;
const int map16_chunk_max = 0x40;
// frames in an area before entries received are taken as live; the log is sent to all players and senders resend it
// every 32 frames (older versions every 16, to the same area only), so entries made before the local player arrived
// come in before that:
const int map16_live_after = 48;
// calls to Map16Sync::send between sends of the whole log:
const int map16_resend_every = 32;

// map16 change log of a remote player as received:
class Map16Remote {
  // location the sender's log belongs to (see ow_location):
  uint32 loc = 0;
  int count = 0;
  array<uint16> pos(0xA0);
  array<uint16> tile(0xA0);
  array<bool> have(0xA0);
  // live is set for entries first received while the local player was in the area, until they were applied:
  array<bool> live(0xA0);
  // how many entries of this log were applied locally:
  int applied = 0;

  void reset(uint32 loc) {
    this.loc = loc;
    count = 0;
    applied = 0;
    for (uint i = 0; i < have.length(); i++) {
      have[i] = false;
      live[i] = false;
    }
  }

  void clear_live() {
    for (uint i = 0; i < live.length(); i++) {
      live[i] = false;
    }
  }

  int deserialize(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 6 > maxc) return maxc;

    uint32 a = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16);
    int n = r[c++];
    int start = r[c++];
    int len = r[c++];
    if (c + len * 4 > maxc) return maxc;
    if (n > map16_log_max || start + len > n) return c + len * 4;

    if (a != loc || n < count) {
      // another area, or the sender's area was reloaded:
      reset(a);
    }
    count = n;
    // entries arriving while we have been in the area for a while were just made by the sender:
    bool here = map16Sync.valid && map16Sync.loc == a && map16Sync.age >= map16_live_after;
    for (int k = 0; k < len; k++) {
      int i = start + k;
      uint16 p = uint16(r[c++]) | (uint16(r[c++]) << 8);
      uint16 t = uint16(r[c++]) | (uint16(r[c++]) << 8);
      // senders that do not fix the entries of bombed openings yet (the entry before is in this message or an earlier
      // one; logs are sent in order):
      if (i > 0 && have[i - 1]) {
        p = map16_fix_entry(pos[i - 1], tile[i - 1], p, t);
      }
      if (have[i] && (pos[i] != p || tile[i] != t) && i < applied) {
        // the sender's log was replaced without us noticing; apply again from here:
        applied = i;
      }
      if (!have[i] && here) {
        live[i] = true;
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
  // valid is true when the log was read in an overworld module at loc (see ow_location):
  bool valid = false;
  uint32 loc = 0;
  int count = 0;
  array<uint16> pos(0xA0);
  array<uint16> tile(0xA0);
  // how many entries were already sent:
  int sent = 0;
  // calls to send() since the whole log was last sent:
  int sendsSinceFull = 0;
  // frames since the area was loaded; see map16_live_after:
  int age = 0;

  void reset() {
    valid = false;
    count = 0;
    sent = 0;
    reset_applied();
  }

  // the local tilemap was (re)loaded; apply all remote changes again, without revealing secrets again:
  void reset_applied() {
    age = 0;
    for (uint i = 0; i < players.length(); i++) {
      auto @p = players[i];
      if (p is null) continue;
      p.map16.applied = 0;
      p.map16.clear_live();
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

    uint32 a = ow_location();
    if (a == ow_location_none) return;
    if (valid && a != loc) {
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
      loc = a;
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
    if (age < map16_live_after) age++;
    for (int i = count; i < n; i++) {
      pos[i] = bus::read_u16(0x7EF800 + uint32(i << 1));
      tile[i] = bus::read_u16(0x7EFA00 + uint32(i << 1));
      if (i > 0) {
        // send where a bombed opening's right half really went:
        pos[i] = map16_fix_entry(pos[i - 1], tile[i - 1], pos[i], tile[i]);
      }
    }
    count = n;
  }

  void serialize(array<uint8> &r, int start, int end) {
    r.write_u8(msg_map16);
    r.write_u24(loc);
    r.write_u8(uint8(count));
    r.write_u8(uint8(start));
    r.write_u8(uint8(end - start));
    for (int i = start; i < end; i++) {
      r.write_u16(pos[i]);
      r.write_u16(tile[i]);
    }
  }

  // sends the new entries of the log, and the whole log every 32 frames, to all players:
  uint send(uint p) {
    if (!valid) return p;
    // menus and text boxes ($0E) keep the log; keep sending it so players entering the area still catch up:
    if (!local.is_in_overworld_module() && local.module != 0x0E) return p;

    // resend the whole log every 32 calls rather than on frames with (frame & 31) == 0: send() is skipped by the net
    // rate limiter whenever frames come in faster than 16ms apart, which can skip those frames every time:
    int start = sent;
    if (++sendsSinceFull >= map16_resend_every) {
      sendsSinceFull = 0;
      start = 0;
    } else if (start >= count) {
      return p;
    }

    while (true) {
      int end = start + map16_chunk_max;
      if (end > count) end = count;
      // to all players, so that players entering the area have the changes while it loads:
      array<uint8> @r = local.make_packet_broadcast();
      serialize(r, start, end);
      p = local.send_packet(r, p);
      start = end;
      if (start >= count) break;
    }
    sent = count;
    return p;
  }

  // logged returns whether the local log's last change at p is t:
  bool logged(uint16 p, uint16 t) {
    int n = int(bus::read_u16(0x7E04AC)) >> 1;
    if (n > map16_log_max) n = map16_log_max;
    for (int i = n - 1; i >= 0; i--) {
      if (bus::read_u16(0x7EF800 + uint32(i << 1)) == p) {
        return bus::read_u16(0x7EFA00 + uint32(i << 1)) == t;
      }
    }
    return false;
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
    if (ow_location() != loc) return;
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
      // only changes made in exactly this location, including the world, by players who are still there:
      if (remote.location != loc) continue;
      auto @rm = remote.map16;
      if (rm.loc != loc) continue;

      // keep only the latest tile for each position among the new entries; ls is set where the remote player changed
      // it just now:
      array<uint16> ps;
      array<uint16> ts;
      array<bool> ls;
      int end = rm.applied;
      for (; end < rm.count && rm.have[end]; end++) {
        int k = ps.find(rm.pos[end]);
        if (k >= 0) {
          ts[k] = rm.tile[end];
          if (rm.live[end]) ls[k] = true;
        } else {
          ps.insertLast(rm.pos[end]);
          ts.insertLast(rm.tile[end]);
          ls.insertLast(rm.live[end]);
        }
      }
      if (end == rm.applied) continue;

      bool done = true;
      for (uint k = 0; k < ps.length(); k++) {
        uint16 p = ps[k];
        uint16 t = ts[k];
        if (written.find(p) >= 0) continue;
        uint16 cur = bus::read_u16(0x7E2000 + p);
        if (cur == t) {
          // applied while the area loaded (see on_overworld_area_load), or already ours; memorize it unless the local
          // log has it:
          if (!logged(p, t)) memorize(p, t);
          written.insertLast(p);
          continue;
        }

        // the remote player just removed a small object that is still here; reveal the secret under it:
        int toss = -1;
        if (ls[k] && secrets.can_reveal_ow() && secrets.ow_toss(t) < 0) {
          toss = secrets.ow_toss(cur);
        }
        uint reveal_size = toss >= 0 ? secret_reveal_size : 0;

        int dr = (int(p & 0x1F80) >> 7) - row0;
        int dc = (int(p & 0x007E) >> 1) - col0;
        bool near = small_area || (dr >= -7 && dr < 24 && dc >= -7 && dc < 24);
        uint code_size = reveal_size + (near ? 10 : 0);
        if ((code_size > 0 && pb.offset + 2 + code_size + 7 + 5 > 0x100) || (near && stripe + 0x10 > 0x80)) {
          // continue next frame; what was applied is skipped then:
          done = false;
          break;
        }
        if (toss >= 0) {
          if (!started) {
            pb.rep(0x30);
            started = true;
          }
          secrets.emit_ow_reveal(p, uint8(toss));
        }
        if (near) {
          // REP + LDA + LDX + JSL, and SEP + LDA + STA to finish:
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
      for (int e = rm.applied; e < end; e++) {
        rm.live[e] = false;
      }
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

void init_map16_area_load() {
  if (rom.fn_overworld_handle_overlays == 0) return;
  cpu::register_pc_interceptor(rom.fn_overworld_handle_overlays, @on_overworld_area_load);
}

// called at Overworld_HandleOverlaysAndBombDoors, when an overworld area load has just decompressed the area's tilemap
// into $7E2000 and nothing was drawn from it yet: write the changes of the remote players on the same team that are in
// the area being loaded ($8A) to it. They are not added to the local log here (scroll transitions reset $04AC
// afterwards); Map16Sync::update memorizes them once the area is loaded.
void on_overworld_area_load(uint32 pc) {
  if (!settings.SyncTilemap) return;
  if (local is null || local.get_in_sm()) return;
  uint16 area = bus::read_u16(0x7E008A);

  uint len = players.length();
  for (uint i = 0; i < len; i++) {
    auto @remote = players[i];
    if (remote is null) continue;
    if (remote is local) continue;
    if (remote.ttl <= 0) continue;
    if (remote.get_in_sm()) continue;
    if (remote.team != local.team) continue;
    // menus and text boxes ($0E) keep the log:
    if (!remote.is_in_overworld_module() && remote.module != 0x0E) continue;
    auto @rm = remote.map16;
    // the log of the area the player is in:
    if (rm.loc != remote.location) continue;
    if ((rm.loc & 0x010000) != 0) continue;
    if (uint16(rm.loc) != area) continue;

    for (int k = 0; k < rm.count && rm.have[k]; k++) {
      bus::write_u16(0x7E2000 + (rm.pos[k] & 0x1FFE), rm.tile[k]);
    }
  }
}
