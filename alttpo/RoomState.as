// Room state synchronization: trap doors, chests, keys, key doors and switches of the current room, wire-compatible
// with o2 (see o2's games/alttp/syncroom.go and ALTTPO_COMPAT.md).
//
// Several pieces of underworld state only live in WRAM while the room is loaded, so the SRAM room flags ($7EF000) do
// not share them with players in the same room until somebody leaves it:
//
//   - $0468 is the trap door (shutter) state of the current room: 0 = open, 1 = closed. Room tags open or close the
//     shutters by changing it, clearing $068E/$0690 and switching to submodule $05, which animates the doors
//     (OperateShutterDoors). Room loads set it to 1 and an inter-room transition closes the shutters behind Link; an
//     intra-room transition (submodule $01) opens and then closes them again.
//   - $0403 holds the room's chest, key and boss flags (written to $7EF000 on leaving the room). Opening chest i
//     (OpenItemChest) sets bit i (chests 0-5). Picking up a small key or big key sprite ($E4/$E5) or a bonk key
//     (sprite $3B with $0DC0 = 1, e.g. on top of a Desert Palace torch) sets $40 (key index 0) or $20 (key index 1,
//     the same bit as chest 5), the index being the key's $0CBA. Key sprites remove themselves when their flag is
//     set; bonk keys only check it when the room loads. Heart pieces ($EB) and heart containers ($EA) on the floor set
//     the same bits, the index being bit 0 of their X high byte ($0D30), but only check them when they spawn. A
//     boss's heart container ($EA with $0D90 != 0) sets $80 instead, which also makes the boss room drop its prize and
//     keeps the boss from coming back.
//   - $0401 (the high byte of $0400) has a bit set for each door opened in the room: unlocking key door slot k sets
//     $80 >> (k & 7) (UnlockKeyDoor_Main), as do bombed and dashed walls.
//   - $0642 is set by a pull switch when it is pulled (also by Swamp Palace's water switches); the pull switch door
//     ($14), pull switch exploding wall ($28) and water tags ($18-$1A) act on it.
//   - The hold switch door tag ($16) recomputes $0468 every frame: open while Link stands on a floor switch or star
//     tile, $0646 is set (a Cane of Somaria block on a floor switch) or $0642 is set (a statue on a floor switch).
//
// Message 0x1A (uint16 room, uint8 flags ($0403), uint32 doorTs, uint8 door ($0468)) and message 0x1B (uint16 room,
// uint8 doors ($0401), uint8 switches (bit 0: pressing a hold switch, bit 1: pulled a switch, bits 2/3: the switch was
// pulled in the east/south quadrant), uint32 pulledTs) are
// sent in a broadcastSector packet to the current room's sector, only once they were sampled in that room.
//
//   - Sampling: in the dungeon module only, while the room ($A0) stays the same. A baseline is taken in submodule 0. A
//     change of $0468 seen in submodule 0, $05 (shutters moving) or $17 (pressure plate) is a local change and is
//     timestamped. Changes of room and intra-room transitions (submodule $01) forget the state, since the game resets
//     the shutters itself.
//   - Key flags ($40, and $20 if chests are synced since it is also chest 5's flag) are OR'ed in from remote players
//     in the same room whose state was sampled there. Bonk keys, heart pieces and heart containers of the newly set
//     flags are removed.
//   - The boss flag ($80) is taken only while the boss's heart container lies on the floor here, so a boss still
//     alive here keeps its fight; the heart container is removed.
//   - Chest flags (bits 0-5, if chests are synced) are OR'ed in as well and small chests still closed here are drawn
//     open the way OpenItemChest does, without giving the item. Not while a tag that hides the room's chests is
//     active, and not bit 3 in water rooms, whose tags use it to remember the water was let out.
//   - Key doors: a door bit set by a remote player whose slot here is a small key or big key door that is still
//     closed is unlocked the way the game does (submodule $04 with $068E pointing at the door's tile attributes),
//     without using a key; the small key sync takes care of the key count. A bombed or dashed wall (door types $28,
//     $2A, $2E) still closed here is opened the same way with submodule $09 (OpenCrackedDoor).
//   - Trap doors are last writer wins among remote players in the same room with a change made in their current visit
//     of the room, also one made before we arrived (our room load closed the shutters, the player inside left them open). They are not applied in rooms with tags
//     that compute the shutter state every frame from what the local player does (hold switch doors, push block
//     doors, torch puzzle doors); those would close again immediately.
//   - Pull switches: a pull made by a remote player after our baseline sets $0642 here once.
//   - Hold switches: while a remote player presses a hold switch, $0646 is set to $80, which holds the doors open; it
//     is cleared again once nobody does. A player whose $0646 is $80 does not count as pressing the switch itself, so
//     players do not hold each other's doors open forever. A local somaria block recomputes $0646 every frame and wins.
//   - Push block doors after an intra-room transition: UnderworldTransition_Intraroom_TriggerShutters clears $0641
//     (ResetThenCacheRoomEntryProperties) and closes the shutters while the block stays pushed and cannot be pushed
//     again, so RoomTag_OperateBlockDoor keeps Link locked in (e.g. Ganon's Tower room $8B after another player pushed
//     the block from the other quadrant). When $0641 was odd in the room before the transition and is 0 after it,
//     $0641 is set back to 1 and the doors are opened like the tag does, also when no other player is in the room.
//
// Kill triggers: room tags that act once the enemies of a quadrant or the whole room are dead. Enemies are not synced,
// so players disagree about them. Trap door tags $01-$0A open the doors (Dung_TagRoutine_TrapdoorsUp) once the screen is
// clear while Link is in the tag's quadrant ($01 NW, $02 NE, $03 SW, $04 SE), half ($05 W, $06 E, $07 N, $08 S) or
// anywhere ($09), $0A once the room is clear; $26 (RoomTag_KillRoomBlock, south east quadrant) clears itself so the
// block can be pushed; $29-$32 are like $01-$0A but reveal the room's chests (RoomTag_OperateChestReveal) and clear
// themselves. A trigger is seen firing from a chest or block tag going to 0, or the trap doors opening locally in a room
// with a trap door kill tag that checks in Link's quadrant, and is recorded as bit k for the tag in $AE+k.
//
// Message 0x1E (uint16 room, uint8 fired: bit k = the kill trigger in $AE+k fired during this room visit) is sent last
// in the room's sector packet, after 0x1D. A trigger fired by a remote player in the same room is applied once per
// visit the way the tag does it, without touching the enemies: the trap doors are opened if still closed (unless a key
// door or push block door uses the submodule), the block tag is cleared, or the chests are revealed (closed small chest
// tiles, attributes $5858 + $0101 * i, VRAM stripes from $1000 = 0, $14 = 1; only while $14 = 0) and the tag cleared.

const uint8 room_flag_key0 = 0x40;
const uint8 room_flag_key1 = 0x20;
const uint8 room_flag_chests = 0x3F;
const uint8 room_flag_water = 0x08;
const uint8 room_flag_boss = 0x80;
const uint8 room_hold_remote = 0x80;
const uint16 room_stripe_limit = 0x0068;

// opened small chest tiles (obj14A4): top left, bottom left, top right, bottom right:
const array<uint16> room_open_chest_tiles = {0x19E2, 0x19F2, 0x59E2, 0x59F2};
const array<uint16> room_open_chest_offs = {0x0000, 0x0080, 0x0002, 0x0082};
// closed small chest tiles (obj149C), drawn by RoomTag_OperateChestReveal:
const array<uint16> room_closed_chest_tiles = {0x19E1, 0x19F1, 0x59E1, 0x59F1};
// DoorOpenSFXPan by door direction:
const array<uint8> room_door_sfx_pan = {0x00, 0x00, 0x80, 0x40};

// RoomTag_BuildChestStripes: VRAM stripe header (stored big endian) for the tile at $7E2000 offset v:
uint16 room_stripe_addr(uint16 v) {
  uint16 a = ((v & 0x0040) << 4) | ((v & 0x303F) >> 1) | ((v & 0x0F80) >> 2);
  return uint16((a << 8) | (a >> 8));
}

// room tag kinds for RoomStateLocal::tag_is:
const int room_tag_computes_doors = 0;
const int room_tag_hold = 1;
const int room_tag_water = 2;
const int room_tag_pull = 3;
const int room_tag_hides_chests = 4;
const int room_tag_block_door = 5;
const int room_tag_water_gate = 6;

class RoomStateLocal {
  // valid is true when the state was read in submodule 0 of the dungeon module for room:
  bool valid = false;
  uint16 room = 0;
  uint8 flags = 0;
  uint8 door = 0;
  // doorTs is the time (msec) of the last change of door; 0 means no change since the baseline:
  uint32 doorTs = 0;
  // since is the time (msec) the baseline was taken; only remote door changes after it are applied:
  uint32 since = 0;
  // doors is $0401; doorsTried are door bits we already tried to open:
  uint8 doors = 0;
  uint8 doorsTried = 0;
  // hold is true while the local player presses a hold switch (not counting $0646 set for remote players):
  bool hold = false;
  // pulled is true once a switch was pulled in this room; pulledTs is when (0 if already pulled at the baseline):
  bool pulled = false;
  uint32 pulledTs = 0;
  // quadrant the switch was pulled in: bit 0 east, bit 1 south:
  uint8 pulledQuad = 0;
  // holdWritten is true once $0646 was set for remote players; it is not set again while they keep pressing, since a
  // local somaria block clears it every frame:
  bool holdWritten = false;

  // the push block door's block across intra-room transitions: pushed once $0641 was seen odd in blockRoom,
  // blockTransition while an intra-room transition runs after that, blockCleared once it cleared $0641:
  uint16 blockRoom = 0;
  bool blockPushed = false;
  bool blockTransition = false;
  bool blockCleared = false;

  // the room tags ($AE, $AF) last sampled; fired has bit k once the kill trigger in $AE+k fired here:
  uint8 tag0 = 0;
  uint8 tag1 = 0;
  uint8 fired = 0;

  void reset() {
    valid = false;
  }

  uint32 now_ts() {
    // server clock, like o2 and small keys:
    auto ts = small_key_now_ts();
    if (ts == 0) ts = 1;
    return ts;
  }

  bool tag_is(uint8 tag, int kind) {
    switch (kind) {
      case room_tag_computes_doors:
        if (tag >= 0x0B && tag <= 0x13) return true; // RoomTag_OperateBlockDoor (push block doors)
        if (tag == 0x16) return true;                // RoomTag_SwitchTrigger_HoldDoor
        if (tag == 0x33) return true;                // RoomTag_TorchPuzzleDoor
        return false;
      case room_tag_hold:
        return tag == 0x16;
      case room_tag_water:
        return tag >= 0x18 && tag <= 0x1B;
      case room_tag_pull:
        // pull switch door, water tags, pull switch exploding wall:
        return tag == 0x14 || tag == 0x18 || tag == 0x19 || tag == 0x1A || tag == 0x28;
      case room_tag_block_door:
        // RoomTag_OperateBlockDoor: $0468 = $0641 ^ 1, only while Link is in the tag's quadrant:
        return tag >= 0x0B && tag <= 0x13;
      case room_tag_water_gate:
        return tag == 0x1A || tag == 0x1B;
      case room_tag_hides_chests:
        return tag == 0x27 || tag == 0x3C || tag == 0x3E || (tag >= 0x29 && tag < 0x33);
    }
    return false;
  }

  bool has_tag(uint8 t0, uint8 t1, int kind) {
    return tag_is(t0, kind) || tag_is(t1, kind);
  }

  uint8 synced_flags(uint8 t0, uint8 t1) {
    // $20 is also chest 5's flag; leave it alone when chests are not synced:
    if (!settings.SyncChests) return room_flag_key0;
    uint8 mask = room_flag_key0 | room_flag_key1 | room_flag_chests;
    // the tag draws the chests closed when it reveals them; wait until it did:
    if (has_tag(t0, t1, room_tag_hides_chests)) mask &= ~room_flag_chests;
    // the water gate tags check bit 3 to know whether the gate was opened already; leave it to them. The fill and
    // drain tags set it too but only act on $0642; with the bit set the room loads filled or drained:
    if (has_tag(t0, t1, room_tag_water_gate)) mask &= ~room_flag_water;
    return mask;
  }

  // Link's quadrant in the room: bit 0 east (bit 8 of X), bit 1 south (bit 8 of Y):
  uint8 local_quadrant() {
    return uint8(((bus::read_u16(0x7E0022) >> 8) & 1) | (((bus::read_u16(0x7E0020) >> 8) & 1) << 1));
  }

  // update_block tracks whether the push block door's block was pushed in the current room:
  void update_block(uint16 r, uint8 sub_module) {
    if (r != blockRoom) {
      blockRoom = r;
      blockPushed = false;
      blockTransition = false;
      blockCleared = false;
    }
    if (!has_tag(bus::read_u8(0x7E00AE), bus::read_u8(0x7E00AF), room_tag_block_door)) return;
    if (sub_module == 0x00) {
      if ((bus::read_u8(0x7E0641) & 1) != 0) {
        blockPushed = true;
        blockTransition = false;
        blockCleared = false;
      } else if (blockTransition) {
        blockTransition = false;
        blockCleared = true;
      }
    } else if (sub_module == 0x01) {
      blockTransition = blockPushed;
    }
  }

  bool local_holds(uint8 t0, uint8 t1, uint8 d) {
    return has_tag(t0, t1, room_tag_hold) && d == 0 && bus::read_u8(0x7E0646) != room_hold_remote;
  }

  // called every frame from LocalGameState::update_wram:
  void update() {
    auto module = local.module;
    if (module == 0x0E) {
      // menus don't touch the room state; keep it:
      return;
    }
    if (module != 0x07) {
      // left the dungeon module:
      reset();
      blockPushed = false;
      blockTransition = false;
      blockCleared = false;
      return;
    }

    auto r = bus::read_u16(0x7E00A0);
    auto sub_module = local.sub_module;
    update_block(r, sub_module);
    if (valid && (r != room || sub_module == 0x01)) {
      // a room or intra-room transition; the game resets the shutters:
      reset();
    }

    auto f = bus::read_u8(0x7E0403);
    auto d = bus::read_u8(0x7E0468);
    auto t0 = bus::read_u8(0x7E00AE);
    auto t1 = bus::read_u8(0x7E00AF);
    if (!valid) {
      // the room load is done once back in submodule 0:
      if (sub_module != 0x00) return;
      valid = true;
      room = r;
      flags = f;
      door = d;
      doorTs = 0;
      since = small_key_now_ts();
      doors = bus::read_u8(0x7E0401);
      doorsTried = 0;
      hold = local_holds(t0, t1, d);
      pulled = has_tag(t0, t1, room_tag_pull) && bus::read_u8(0x7E0642) != 0;
      pulledQuad = local_quadrant();
      pulledTs = 0;
      holdWritten = false;
      tag0 = t0;
      tag1 = t1;
      fired = 0;
      return;
    }

    if (!pulled && has_tag(t0, t1, room_tag_pull)) {
      // water tags take $0642 back the frame after it was set and switch to submodule $0B, $0C or $0D:
      bool water = has_tag(t0, t1, room_tag_water) && sub_module >= 0x0B && sub_module <= 0x0D;
      if (bus::read_u8(0x7E0642) != 0 || water) {
        pulled = true;
        pulledTs = now_ts();
        pulledQuad = local_quadrant();
      }
    }

    // room tags run in submodule 0 and switch to $05 (or $17 for a pressure plate) to move the shutters:
    if (sub_module != 0x00 && sub_module != 0x05 && sub_module != 0x17) return;

    flags = f;
    doors = bus::read_u8(0x7E0401);
    hold = local_holds(t0, t1, d);
    update_kills(t0, t1, d);
    if (d != door) {
      door = d;
      doorTs = now_ts();
    }

    if (!settings.SyncUnderworldLocal) return;
    if (sub_module != 0x00) return;

    apply(t0, t1);
  }

  // kill_tag_base returns the trap door tag ($01-$0A) a kill trigger tag acts like, or 0 if it is not one:
  uint8 kill_tag_base(uint8 tag) {
    if (tag >= 0x01 && tag <= 0x0A) return tag;
    if (tag >= 0x29 && tag <= 0x32) return tag - 0x28; // the chest reveal tags
    if (tag == 0x26) return 0x04;                       // RoomTag_KillRoomBlock, in the south east quadrant
    return 0;
  }

  bool kill_tag_is_door(uint8 tag) { return tag >= 0x01 && tag <= 0x0A; }
  bool kill_tag_is_chest(uint8 tag) { return tag >= 0x29 && tag <= 0x32; }

  // kill_tag_fires reports whether a kill trigger tag checks for its enemies while Link is in quadrant q:
  bool kill_tag_fires(uint8 tag, uint8 q) {
    uint8 base = kill_tag_base(tag);
    if (base == 0) return false;
    if (base <= 0x04) return q == base - 0x01;
    if (base <= 0x06) return (q & 1) == base - 0x05;
    if (base <= 0x08) return (q >> 1) == base - 0x07;
    // $09: any quadrant, $0A: the whole room:
    return true;
  }

  // update_kills records the kill triggers fired locally; d is $0468 now, door as last sampled:
  void update_kills(uint8 t0, uint8 t1, uint8 d) {
    array<uint8> prev = {tag0, tag1};
    array<uint8> cur = {t0, t1};
    for (uint k = 0; k < 2; k++) {
      uint8 bit = uint8(1 << k);
      // a chest reveal or kill room block tag fired:
      if (prev[k] != 0 && cur[k] == 0 && kill_tag_base(prev[k]) != 0 && !kill_tag_is_door(prev[k])) fired |= bit;
    }
    tag0 = t0;
    tag1 = t1;
    if (door == 0 || d != 0) return;
    auto q = local_quadrant();
    for (uint k = 0; k < 2; k++) {
      if (kill_tag_is_door(cur[k]) && kill_tag_fires(cur[k], q)) fired |= uint8(1 << k);
    }
  }

  // apply_kill applies kill trigger k fired by a remote player; returns true when it used the submodule:
  bool apply_kill(uint k, uint8 tag) {
    uint32 tagAddr = 0x7E00AE + k;
    if (kill_tag_is_door(tag)) {
      fired |= uint8(1 << k);
      if (bus::read_u8(0x7E0468) == 0) return false;
      // open the trap doors like Dung_TagRoutine_TrapdoorsUp:
      bus::write_u16(0x7E0468, 0);
      bus::write_u16(0x7E068E, 0);
      bus::write_u16(0x7E0690, 0);
      bus::write_u8(0x7E012F, 0x1B); // SFX3.1B
      bus::write_u8(0x7E0011, 0x05); // move the shutters (OperateShutterDoors)
      // not a local change of the trap doors:
      door = 0;
      return true;
    }
    if (kill_tag_is_chest(tag)) {
      // the reveal writes the VRAM stripes from the start of the buffer; wait until none are pending:
      if (bus::read_u8(0x7E0014) != 0) return false;
      uint n = bus::read_u16(0x7E0496) >> 1;
      if (n == 0 || n > 6) return false;
      fired |= uint8(1 << k);
      bus::write_u8(tagAddr, 0);
      reveal_chests(n);
      return false;
    }
    // RoomTag_KillRoomBlock lets the block be pushed:
    fired |= uint8(1 << k);
    bus::write_u8(tagAddr, 0);
    bus::write_u8(0x7E012F, 0x1B); // SFX3.1B
    return false;
  }

  // reveal_chests draws the room's n chests closed like RoomTag_OperateChestReveal:
  void reveal_chests(uint n) {
    for (uint i = 0; i < n; i++) {
      uint16 tile = bus::read_u16(0x7E06E0 + (i << 1)) & 0x3FFF;
      for (uint t = 0; t < 4; t++) {
        bus::write_u16(0x7E2000 + tile + room_open_chest_offs[t], room_closed_chest_tiles[t]);
        bus::write_u16(0x7E1002 + i * 0x18 + t * 6, room_stripe_addr(tile + room_open_chest_offs[t]));
        bus::write_u16(0x7E1004 + i * 0x18 + t * 6, 0x0100);
        bus::write_u16(0x7E1006 + i * 0x18 + t * 6, room_closed_chest_tiles[t]);
      }
      uint16 attr = uint16(0x5858 + i * 0x0101);
      bus::write_u16(0x7F2000 + (tile >> 1), attr);
      bus::write_u16(0x7F2040 + (tile >> 1), attr);
    }
    bus::write_u16(0x7E101A + (n - 1) * 0x18, 0xFFFF);
    bus::write_u16(0x7E1000, uint16(n * 0x18));
    bus::write_u8(0x7E012F, 0x1A); // SFX3.1A
    bus::write_u8(0x7E0014, 0x01);
  }

  // boss_heart_present reports whether a boss's heart container ($EA with $0D90 != 0) lies on the floor:
  bool boss_heart_present() {
    for (uint x = 0; x < 0x10; x++) {
      if (bus::read_u8(0x7E0DD0 + x) == 0) continue;
      if (bus::read_u8(0x7E0E20 + x) != 0xEA) continue;
      if (bus::read_u8(0x7E0D90 + x) != 0) return true;
    }
    return false;
  }

  void apply(uint8 t0, uint8 t1) {
    uint8 mask = synced_flags(t0, t1);
    // the boss flag only while the boss's heart container is on the floor here:
    if ((flags & room_flag_boss) == 0 && boss_heart_present()) mask |= room_flag_boss;
    uint8 newFlags = 0;
    GameState@ doorWinner = null;
    // a change made before we arrived still counts (remote players forget theirs when they leave the room):
    uint32 tsCompare = doorTs;
    bool hasPull = has_tag(t0, t1, room_tag_pull);
    bool wantHold = false;
    GameState@ pullFrom = null;
    uint8 remoteDoors = 0;
    uint8 remoteFired = 0;
    int remotes = 0;

    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != local.team) continue;
      if (remote.get_in_sm()) continue;
      if (remote.module != 0x07) continue;
      if (!local.is_really_in_same_location(remote.location)) continue;
      // not sampled in this room:
      if (!remote.room_valid || remote.room_room != room) continue;

      remotes++;
      newFlags |= uint8(remote.room_flags & mask & ~flags);

      if (remote.room_door_ts > tsCompare) {
        @doorWinner = remote;
        tsCompare = remote.room_door_ts;
      }
      if (remote.room_kills_valid && remote.room_kills_room == room) remoteFired |= remote.room_kills_fired;

      if (!remote.room_doors_valid || remote.room_doors_room != room) continue;
      remoteDoors |= remote.room_doors;
      if (hasPull && !pulled && pullFrom is null && remote.room_pulled && remote.room_pulled_ts > since) {
        // the water tags flood or drain the quadrant the camera is in, which only works out when Link is where the
        // switch was pulled (e.g. Underworld_FloodSwampWater_CoverFloor never ends with the camera in another
        // quadrant); wait until Link is in the quadrant the switch was pulled in:
        if (!has_tag(t0, t1, room_tag_water) || local_quadrant() == remote.room_pulled_quad) {
          @pullFrom = remote;
        }
      }
      if (remote.room_hold) wantHold = true;
    }

    if (newFlags != 0) {
      flags |= newFlags;
      bus::write_u8(0x7E0403, flags);

      // remove bonk keys, heart pieces and heart containers of those flags (they only check $0403 when they spawn):
      for (uint x = 0; x < 0x10; x++) {
        if (bus::read_u8(0x7E0DD0 + x) == 0) continue;
        auto type = bus::read_u8(0x7E0E20 + x);
        uint8 idx;
        if (type == 0x3B) {
          if (bus::read_u8(0x7E0DC0 + x) != 0x01) continue;
          idx = bus::read_u8(0x7E0CBA + x);
        } else if (type == 0xEA && bus::read_u8(0x7E0D90 + x) != 0) {
          // a boss's heart container:
          if ((newFlags & room_flag_boss) != 0) bus::write_u8(0x7E0DD0 + x, 0);
          continue;
        } else if (type == 0xEA || type == 0xEB) {
          idx = bus::read_u8(0x7E0D30 + x) & 1;
        } else {
          continue;
        }
        if (idx == 0 && (newFlags & room_flag_key0) == 0) continue;
        if (idx == 1 && (newFlags & room_flag_key1) == 0) continue;
        if (idx > 1) continue;
        bus::write_u8(0x7E0DD0 + x, 0);
      }

      // draw newly opened small chests open:
      for (uint i = 0; i < 6; i++) {
        if ((newFlags & (1 << i)) == 0) continue;
        open_chest(i);
      }
    }

    if (pullFrom !is null) {
      if (bus::read_u8(0x7E0642) == 0) bus::write_u8(0x7E0642, 1);
      pulled = true;
      pulledTs = pullFrom.room_pulled_ts;
      pulledQuad = pullFrom.room_pulled_quad;
    }

    if (!wantHold) holdWritten = false;
    if (has_tag(t0, t1, room_tag_hold)) {
      auto h = bus::read_u8(0x7E0646);
      if (wantHold && h == 0 && !holdWritten) {
        bus::write_u8(0x7E0646, room_hold_remote);
        holdWritten = true;
      } else if (!wantHold && h == room_hold_remote) {
        bus::write_u8(0x7E0646, 0);
      }
    }

    // kill triggers fired by remote players; trap doors only when no key door or push block door uses the submodule:
    int killDoor = -1;
    array<uint8> tags = {t0, t1};
    for (uint k = 0; k < 2; k++) {
      if ((remoteFired & ~fired & (1 << k)) == 0 || kill_tag_base(tags[k]) == 0) continue;
      if (kill_tag_is_door(tags[k])) {
        killDoor = int(k);
        continue;
      }
      apply_kill(k, tags[k]);
    }

    // key doors and cracked walls; opening one uses the submodule:
    uint8 newDoors = remoteDoors & ~(doors | doorsTried);
    for (uint b = 0x80; b != 0; b >>= 1) {
      if ((newDoors & b) == 0) continue;
      doorsTried |= uint8(b);
      if (unlock_door(uint8(b))) return;
    }

    // push block doors: the tag only opens the doors while Link is in its quadrant, and a block moved by sync may have
    // toggled $0641 while the doors were busy (e.g. closing behind a player entering the room); open them like the tag:
    if (remotes > 0 && has_tag(t0, t1, room_tag_block_door) && (bus::read_u8(0x7E0641) & 1) != 0 && door != 0) {
      bus::write_u16(0x7E0468, 0);
      bus::write_u16(0x7E068E, 0);
      bus::write_u16(0x7E0690, 0);
      bus::write_u8(0x7E012F, 0x25); // SFX3.25
      bus::write_u8(0x7E0011, 0x05); // move the shutters (OperateShutterDoors)
      return;
    }

    // an intra-room transition cleared $0641 and closed the shutters, but the block is still pushed; take it back:
    if (blockCleared && blockRoom == room && has_tag(t0, t1, room_tag_block_door) &&
        (bus::read_u8(0x7E0641) & 1) == 0 && door != 0) {
      blockCleared = false;
      bus::write_u8(0x7E0641, 1);
      bus::write_u16(0x7E0468, 0);
      bus::write_u16(0x7E068E, 0);
      bus::write_u16(0x7E0690, 0);
      bus::write_u8(0x7E012F, 0x25); // SFX3.25
      bus::write_u8(0x7E0011, 0x05); // move the shutters (OperateShutterDoors)
      return;
    }

    if (killDoor >= 0 && apply_kill(uint(killDoor), tags[uint(killDoor)])) return;

    if (doorWinner is null) return;

    auto newDoor = doorWinner.room_door;
    if (newDoor == door) {
      // already in agreement; keep the latest timestamp:
      doorTs = doorWinner.room_door_ts;
      return;
    }
    if (has_tag(t0, t1, room_tag_computes_doors)) return;

    // do what a room tag does to operate the shutters:
    bus::write_u16(0x7E0468, newDoor);
    bus::write_u16(0x7E068E, 0);
    bus::write_u16(0x7E0690, 0);
    bus::write_u8(0x7E012F, 0x25); // SFX3.25
    bus::write_u8(0x7E0011, 0x05); // move the shutters (OperateShutterDoors)

    door = newDoor;
    doorTs = doorWinner.room_door_ts;
  }

  // open_chest draws small chest i open if it is still closed here, the way OpenItemChest does, without its item.
  void open_chest(uint i) {
    uint16 pos = bus::read_u16(0x7E06E0 + (i << 1));
    // no chest or a big key lock:
    if (pos == 0 || (pos & 0x8000) != 0) return;
    uint16 tile = pos & 0x7FFF;
    uint32 attr = 0x7F2000 + (tile >> 1);
    uint16 closed = uint16(0x5858 + i * 0x0101);
    if (bus::read_u16(attr) != closed) return;
    // big chests are 4 tiles wide:
    if (bus::read_u16(attr + 0x42) == closed) return;
    uint16 x = bus::read_u16(0x7E1000);
    if (x >= room_stripe_limit) return;

    for (uint t = 0; t < 4; t++) {
      bus::write_u16(0x7E2000 + tile + room_open_chest_offs[t], room_open_chest_tiles[t]);
      bus::write_u16(0x7E1002 + x + t * 6, room_stripe_addr(tile + room_open_chest_offs[t]));
      bus::write_u16(0x7E1004 + x + t * 6, 0x0100);
      bus::write_u16(0x7E1006 + x + t * 6, room_open_chest_tiles[t]);
    }
    bus::write_u16(0x7E101A + x, 0xFFFF);
    bus::write_u16(attr, 0x2727);
    bus::write_u16(attr + 0x40, 0x2727);
    bus::write_u16(0x7E1000, x + 0x18);
    bus::write_u8(0x7E0014, 0x01);
  }

  // unlock_door unlocks the key door for a $0401 bit if it is still locked here the way the game does once the key
  // was used: point $068E at the door's tile attributes ($F0 + slot), clear $0690 and switch to submodule $04. A
  // cracked wall is opened the way Bomb_CheckForDestructibles and a dash into it do: $068E the same way, SFX3 $1B and
  // submodule $09 (OpenCrackedDoor, which sets $0690 itself), without the debris.
  bool unlock_door(uint8 b) {
    for (uint k = 0; k < 16; k++) {
      if ((0x80 >> (k & 7)) != b) continue;
      uint32 o = k << 1;
      uint8 t = bus::read_u8(0x7E1980 + o) & 0xFE;
      // small key and big key doors, or bombable and dashable walls:
      bool cracked = (t == 0x28 || t == 0x2A || t == 0x2E);
      if (!cracked && (t < 0x1C || t >= 0x2C || t == 0x28 || t == 0x2A)) continue;
      uint16 pos = bus::read_u16(0x7E19A0 + o);
      if (pos == 0) continue;
      uint16 a = (pos >> 1) + 0x41;
      if (bus::read_u8(0x7F2000 + a) != (0xF0 | k)) continue;
      bus::write_u16(0x7E068E, a);
      if (cracked) {
        bus::write_u8(0x7E0011, 0x09);
        bus::write_u8(0x7E012F, 0x1B); // SFX3.1B
        return true;
      }
      bus::write_u16(0x7E0690, 0);
      bus::write_u8(0x7E0011, 0x04);
      bus::write_u8(0x7E012F, 0x14 | room_door_sfx_pan[bus::read_u8(0x7E19C0 + o) & 3]); // SFX3.14
      return true;
    }
    return false;
  }

  void serialize_kills(array<uint8> &r) {
    if (!valid) return;
    uint mst = msg_begin(r, msg_room_kills);
    r.write_u16(room);
    r.write_u8(fired);
    msg_end(r, mst);
  }

  void serialize(array<uint8> &r) {
    if (!valid) return;
    uint mst = msg_begin(r, msg_room_state);
    r.write_u16(room);
    r.write_u8(flags);
    r.write_u32(doorTs);
    r.write_u8(door);
    msg_end(r, mst);

    mst = msg_begin(r, msg_room_doors);
    r.write_u16(room);
    r.write_u8(doors);
    uint8 switches = 0;
    if (hold) switches |= 0x01;
    if (pulled) switches |= uint8(0x02 | (pulledQuad << 2));
    r.write_u8(switches);
    r.write_u32(pulledTs);
    msg_end(r, mst);
  }
};

RoomStateLocal roomState;
