// Underworld manipulable object synchronization, wire-compatible with o2 (see o2's games/alttp/syncmanip.go and
// ALTTPO_COMPAT.md).
//
// The room loader registers up to 16 manipulable objects in slots of these arrays:
//
//   - $7E0500 [$10]uint16: type and state. $0000-$0005 and $FFFF are push blocks (stationary, triggered, moving, done
//     moving, falling, on a switch; $FFFF once it can no longer move), $1010-$1212 pots, $2020-$2323 the four quarters
//     of a big gray rock, $3030-$3333 the four quarters of a bombable floor and $4040 hammer pegs.
//   - $7E0520 [$10]uint16: the object's offset in the room data, the same for every client. For push blocks it is the
//     index into the dungeon's push block table at $7EF940 (`room u16`, `pos u16` per block).
//   - $7E0540 [$10]uint16: the tilemap position (offset into $7E2000, $2000 set for the upper layer).
//   - $7E0560/$0580/$05A0/$05C0 [$10]uint16: the tiles drawn when the object goes away.
//
// Slots [0, $0478/2) are manipulables; the slots after them hold the room's torches (see torches.as). Each manipulable
// except bombable floors gets the tile attribute $70+slot in $7F2000. Lifting a pot, pounding a peg or lifting a big
// rock calls RoomDraw_16x16Single, which draws the replacement tiles and attributes and leaves $0500 alone, so the
// attribute tells whether the object is still there. A pushed block draws its replacement tiles, moves 16 pixels and
// then is drawn at its new position (attribute $27, state $FFFF), toggles a switch under it or falls into a pit.
//
// The state is shared with players in the same room in message 0x18 in broadcastSector packets:
//   uint16 room, uint8 count, then per slot: uint16 type, uint16 objx, uint16 pos, uint8 flags
//   (bit 0: revealed, bit 1: four uint16 replacement tiles follow).
//
// Slots are matched by room data offset (and position, except for push blocks). A remote player's revealed object is
// revealed locally by calling RoomDraw_16x16Single with the remote's replacement tiles (a pot can hide a hole or a
// switch); items hidden under pots are not spawned. A remote player's push block that finished moving is moved here in
// one step: draw what was under it, then do what PushBlock_CheckForPit does at its new position.

const uint8 msg_manip = 0x18;
const int manip_slots = 16;

bool manip_is_push_block(uint16 t) {
  return t < 0x0010 || t == 0xFFFF;
}

// pots, big gray rocks and hammer pegs:
bool manip_is_liftable(uint16 t) {
  if (t == 0xFFFF) return false;
  uint16 k = t & 0x00F0;
  return k == 0x10 || k == 0x20 || k == 0x40;
}

uint32 manip_attr_addr(uint16 pos) {
  return 0x7F2000 + (uint32(pos & 0x3FFF) >> 1);
}

bool manip_is_step(uint16 from, uint16 to) {
  uint16 d = uint16(to - from);
  return d == 0xFF00 || d == 0x0100 || d == 0xFFFC || d == 0x0004;
}

// manipulable objects of a remote player as received:
class ManipRemote {
  uint16 room = 0;
  int n = 0;
  array<uint16> typ(16);
  array<uint16> objx(16);
  array<uint16> pos(16);
  array<uint8> flags(16);
  array<uint16> tiles(64);

  void reset() {
    room = 0;
    n = 0;
  }

  int deserialize(array<uint8> r, int c) {
    int maxc = int(r.length());
    if (c + 3 > maxc) return maxc;

    room = uint16(r[c++]) | (uint16(r[c++]) << 8);
    n = r[c++];
    if (n > manip_slots) {
      n = 0;
      return maxc;
    }
    for (int i = 0; i < n; i++) {
      if (c + 7 > maxc) {
        n = 0;
        return maxc;
      }
      typ[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      objx[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      pos[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      flags[i] = r[c++];
      if ((flags[i] & 0x02) != 0) {
        if (c + 8 > maxc) {
          n = 0;
          return maxc;
        }
        for (int t = 0; t < 4; t++) {
          tiles[i * 4 + t] = uint16(r[c++]) | (uint16(r[c++]) << 8);
        }
      }
    }
    return c;
  }
};

// local player's manipulable objects in the current room:
class ManipSync {
  // valid is true when the slots were read in the dungeon module for room:
  bool valid = false;
  uint16 room = 0;
  int n = 0;
  array<uint16> typ(16);
  array<uint16> objx(16);
  array<uint16> pos(16);
  array<uint16> orig_pos(16);
  array<uint16> tiles(64);
  // present is set once the slot's attribute $70+slot was seen at pos:
  array<bool> present(16);
  // revealed is set once the object went away after it was seen present:
  array<bool> revealed(16);

  void reset() {
    valid = false;
    n = 0;
  }

  void read_slot(int i) {
    uint32 o = uint32(i << 1);
    typ[i] = bus::read_u16(0x7E0500 + o);
    pos[i] = bus::read_u16(0x7E0540 + o);
    for (int t = 0; t < 4; t++) {
      tiles[i * 4 + t] = bus::read_u16(0x7E0560 + uint32(t << 5) + o);
    }
  }

  // called every frame from LocalGameState::fetch:
  void fetch() {
    if (local.module == 0x0E) {
      // menus don't touch the room:
      return;
    }
    if (local.module != 0x07) {
      reset();
      return;
    }
    uint16 r = bus::read_u16(0x7E00A0);
    if (valid && r != room) {
      reset();
    }
    // room loads happen in other submodules:
    if (local.sub_module != 0) return;

    int c = int(bus::read_u16(0x7E0478));
    if ((c & 1) != 0 || c > (manip_slots << 1)) return;
    c >>= 1;

    bool baseline = !valid || c != n;
    for (int i = 0; !baseline && i < c; i++) {
      if (bus::read_u16(0x7E0520 + uint32(i << 1)) != objx[i]) baseline = true;
    }
    if (baseline) {
      valid = true;
      room = r;
      n = c;
      for (int i = 0; i < n; i++) {
        objx[i] = bus::read_u16(0x7E0520 + uint32(i << 1));
        read_slot(i);
        orig_pos[i] = pos[i];
        present[i] = false;
        revealed[i] = false;
      }
      return;
    }

    for (int i = 0; i < n; i++) {
      read_slot(i);
      if (!manip_is_liftable(typ[i]) || revealed[i]) continue;
      if (bus::read_u8(manip_attr_addr(pos[i])) == uint8(0x70 + i)) {
        present[i] = true;
      } else if (present[i]) {
        revealed[i] = true;
      }
    }
  }

  void serialize(array<uint8> &r) {
    if (!valid) return;
    r.write_u8(msg_manip);
    r.write_u16(room);
    r.write_u8(uint8(n));
    for (int i = 0; i < n; i++) {
      r.write_u16(typ[i]);
      r.write_u16(objx[i]);
      r.write_u16(pos[i]);
      if (revealed[i]) {
        r.write_u8(0x03);
        for (int t = 0; t < 4; t++) {
          r.write_u16(tiles[i * 4 + t]);
        }
      } else {
        r.write_u8(0x00);
      }
    }
  }

  // returns the local slot matching remote slot i, or -1:
  int find_local(ManipRemote@ rm, int i) {
    bool push = manip_is_push_block(rm.typ[i]);
    for (int j = 0; j < n; j++) {
      if (objx[j] != rm.objx[i]) continue;
      if (manip_is_push_block(typ[j]) != push) continue;
      if (!push && (pos[j] != rm.pos[i] || typ[j] != rm.typ[i])) continue;
      return j;
    }
    return -1;
  }

  // called every frame from on_main_alttp; reveal objects and move push blocks like remote players in the room did:
  void update() {
    if (!settings.SyncTilemap) return;
    if (!valid) return;
    if (local.module != 0x07 || local.sub_module != 0) return;
    if (bus::read_u16(0x7E00A0) != room) return;
    uint32 fn = rom.fn_room_draw_16x16_single;
    uint32 rtl = rom.fn_bank01_rtl;
    if (fn == 0 || rtl == 0) return;

    int stripe = int(bus::read_u16(0x7E1000));
    bool started = false;
    bool full = false;
    array<bool> queued(16);

    uint len = players.length();
    for (uint p = 0; p < len; p++) {
      auto @remote = players[p];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (remote.get_in_sm()) continue;
      if (remote.team != local.team) continue;
      if (remote.module != 0x07) continue;
      if (!local.is_really_in_same_location(remote.location)) continue;
      auto @rm = remote.manip;
      if (rm.room != room) continue;

      for (int i = 0; i < rm.n; i++) {
        int j = find_local(rm, i);
        if (j < 0 || queued[j]) continue;
        uint16 o = uint16(j << 1);

        if (manip_is_push_block(rm.typ[i])) {
          // still moving? a pushed block ends up in $0000, or $0005 on a floor switch ($FFFF: older versions):
          uint16 rt = rm.typ[i];
          if (rt != 0x0000 && rt != 0x0005 && rt != 0xFFFF) continue;
          uint16 to = rm.pos[i];
          if (typ[j] != 0 || pos[j] != orig_pos[j] || to == pos[j] || !manip_is_step(pos[j], to)) continue;
          if (bus::read_u16(0x7E0500 + o) != 0 || bus::read_u16(0x7E0540 + o) != pos[j]) continue;
          // nothing else there, e.g. a hammer peg that is still up here (Ganon's Tower room $8B):
          if ((bus::read_u8(manip_attr_addr(to)) & 0xF0) == 0x70) continue;
          // two stripes; REP, LDY + JSR, LDA + STA, 4 x (LDA + STA), LDY + JSR, LDA + 2 x STA, SEP, end:
          if (stripe + 0x30 > 0x80 || pb.offset + 2 + 14 + 6 + 24 + 14 + 11 + 2 + 5 > 0x100) {
            full = true;
            break;
          }
          if (!started) {
            pb.rep(0x30);
            started = true;
          }
          move_block(j, to, fn, rtl);
          stripe += 0x30;
        } else {
          if ((rm.flags[i] & 0x01) == 0) continue;
          if (!manip_is_liftable(typ[j]) || !present[j] || revealed[j]) continue;
          if (bus::read_u8(manip_attr_addr(pos[j])) != uint8(0x70 + j)) continue;
          // one stripe; REP, LDY + JSR, SEP, end:
          if (stripe + 0x18 > 0x80 || pb.offset + 2 + 14 + 2 + 5 > 0x100) {
            full = true;
            break;
          }
          if (!started) {
            pb.rep(0x30);
            started = true;
          }
          if ((rm.flags[i] & 0x02) != 0) {
            // a pot can hide a hole or a switch; draw what the remote player revealed:
            for (int t = 0; t < 4; t++) {
              bus::write_u16(0x7E0560 + uint32(t << 5) + o, rm.tiles[i * 4 + t]);
            }
          }
          pb.ldy_immed16(o);
          pb.jsr_bank01(fn, rtl);
          stripe += 0x18;
        }
        queued[j] = true;
      }
      if (full) break;
    }

    if (started) {
      pb.sep(0x30);
    }
  }

  // operate_block_door does what RoomTag_OperateBlockDoor ($0B-$13) does ($0468 = $0641 ^ 1, then move the shutters),
  // unless another submodule is running. The tag itself only runs while Link is in the quadrant it is for, which the
  // player who pushed the block always is but other players usually are not.
  void operate_block_door() {
    auto t0 = bus::read_u8(0x7E00AE);
    auto t1 = bus::read_u8(0x7E00AF);
    if (!((t0 >= 0x0B && t0 <= 0x13) || (t1 >= 0x0B && t1 <= 0x13))) return;
    if (bus::read_u8(0x7E0011) != 0) return;
    uint8 d = bus::read_u8(0x7E0641) ^ 0x01;
    if (d == bus::read_u8(0x7E0468)) return;
    bus::write_u8(0x7E0468, d);
    bus::write_u16(0x7E068E, 0);
    bus::write_u16(0x7E0690, 0);
    bus::write_u8(0x7E012F, 0x25); // SFX3.25
    bus::write_u8(0x7E0011, 0x05); // move the shutters (OperateShutterDoors)
  }

  // move the push block in slot j one step to `to` like the game would; emits code in 16-bit mode:
  void move_block(int j, uint16 to, uint32 fn, uint32 rtl) {
    uint16 o = uint16(j << 1);
    uint32 a = manip_attr_addr(to);
    uint8 attr = bus::read_u8(a);

    // draw what was under it at its old position:
    pb.ldy_immed16(o);
    pb.jsr_bank01(fn, rtl);
    pb.lda_immed16(to);
    pb.sta_bank(uint16(0x0540 + o));

    // do what PushBlock_CheckForPit does:
    if ((to & 0x4000) == 0) {
      // upper layer block pushed; push block door ($0B-$13) and chest ($3C) tags act on $0641:
      bus::write_u16(0x7E0641, uint16(bus::read_u16(0x7E0641) ^ 0x0001));
      operate_block_door();
    }
    if (attr == 0x20) {
      // fell into a pit; record where it lands in the room below:
      uint16 x = bus::read_u16(0x7E0520 + o);
      bus::write_u16(0x7EF940 + x, uint16(bus::read_u8(0x7EC000)));
      bus::write_u16(0x7EF942 + x, to);
      return;
    }
    // PushBlock_CheckForPit leaves $FFFF ($0004 on a switch) and PushBlock_Main increments it:
    uint16 state = 0x0000;
    if (attr == 0x23) {
      // on a switch:
      bus::write_u16(0x7E0466, uint16(bus::read_u16(0x7E0468) ^ 0x0001));
      state = 0x0005;
    }
    bus::write_u16(0x7E0500 + o, state);

    // draw the block at its new position:
    pb.lda_immed16(0x0922);
    pb.sta_bank(uint16(0x0560 + o));
    pb.lda_immed16(0x0932);
    pb.sta_bank(uint16(0x0580 + o));
    pb.lda_immed16(0x0923);
    pb.sta_bank(uint16(0x05A0 + o));
    pb.lda_immed16(0x0933);
    pb.sta_bank(uint16(0x05C0 + o));
    pb.ldy_immed16(o);
    pb.jsr_bank01(fn, rtl);
    pb.lda_immed16(0x2727);
    pb.sta_long(a);
    pb.sta_long(a + 0x40);
  }
};

ManipSync manipSync;
