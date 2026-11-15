// Room state synchronization: trap doors and key flags of the current room, wire-compatible with o2 (see o2's
// games/alttp/syncroom.go and ALTTPO_COMPAT.md).
//
// Two pieces of underworld state only live in WRAM while the room is loaded, so the SRAM room flags ($7EF000) do not
// share them with players in the same room until somebody leaves it:
//
//   - $0468 is the trap door (shutter) state of the current room: 0 = open, 1 = closed. Room tags open or close the
//     shutters by changing it, clearing $068E/$0690 and switching to submodule $05, which animates the doors
//     (OperateShutterDoors). Room loads set it to 1 and an inter-room transition closes the shutters behind Link; an
//     intra-room transition (submodule $01) opens and then closes them again.
//   - $0403 holds the room's chest, key and boss flags (written to $7EF000 on leaving the room). Picking up a small
//     key or big key sprite ($E4/$E5) or a bonk key (sprite $3B with $0DC0 = 1, e.g. on top of a Desert Palace torch)
//     sets $40 (key index 0) or $20 (key index 1), the index being the key's $0CBA. Key sprites remove themselves when
//     their flag is set; bonk keys only check it when the room loads.
//
// Both are sent in message 0x1A (uint16 room, uint8 flags ($0403), uint32 doorTs, uint8 door ($0468)) in a
// broadcastSector packet to the current room's sector, only once they were sampled in that room.
//
//   - Sampling: in the dungeon module only, while the room ($A0) stays the same. A baseline is taken in submodule 0. A
//     change of $0468 seen in submodule 0, $05 (shutters moving) or $17 (pressure plate) is a local change and is
//     timestamped. Changes of room and intra-room transitions (submodule $01) forget the state, since the game resets
//     the shutters itself.
//   - Key flags ($40, and $20 if chests are synced since it is also chest 5's flag) are OR'ed in from remote players
//     in the same room whose state was sampled there. Bonk keys of the newly set flags are removed.
//   - Trap doors are last writer wins among remote players in the same room with a change made after our baseline was
//     taken (so only changes made while both players are in the room count). They are not applied in rooms with tags
//     that compute the shutter state every frame from what the local player does (hold switch doors, push block
//     doors, torch puzzle doors); those would close again immediately.

const uint8 msg_room_state = 0x1A;
const uint8 room_flag_key0 = 0x40;
const uint8 room_flag_key1 = 0x20;

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

  void reset() {
    valid = false;
  }

  uint8 synced_flags() {
    if (settings.SyncChests) return room_flag_key0 | room_flag_key1;
    // $20 is also chest 5's flag; leave it alone when chests are not synced:
    return room_flag_key0;
  }

  // room tags that recompute the shutter state from local conditions every frame:
  bool tag_computes_doors(uint8 tag) {
    if (tag >= 0x0B && tag <= 0x13) return true; // RoomTag_OperateBlockDoor (push block doors)
    if (tag == 0x16) return true;                // RoomTag_SwitchTrigger_HoldDoor
    if (tag == 0x33) return true;                // RoomTag_TorchPuzzleDoor
    return false;
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
      return;
    }

    auto r = bus::read_u16(0x7E00A0);
    auto sub_module = local.sub_module;
    if (valid && (r != room || sub_module == 0x01)) {
      // a room or intra-room transition; the game resets the shutters:
      reset();
    }

    auto f = bus::read_u8(0x7E0403);
    auto d = bus::read_u8(0x7E0468);
    if (!valid) {
      // the room load is done once back in submodule 0:
      if (sub_module != 0x00) return;
      valid = true;
      room = r;
      flags = f;
      door = d;
      doorTs = 0;
      since = small_key_now_ts();
      return;
    }

    // room tags run in submodule 0 and switch to $05 (or $17 for a pressure plate) to move the shutters:
    if (sub_module != 0x00 && sub_module != 0x05 && sub_module != 0x17) return;

    flags = f;
    if (d != door) {
      door = d;
      // server clock, like o2 and small keys:
      doorTs = small_key_now_ts();
      if (doorTs == 0) doorTs = 1;
    }

    if (!settings.SyncTilemap) return;
    if (sub_module != 0x00) return;

    apply();
  }

  void apply() {
    uint8 mask = synced_flags();
    uint8 newFlags = 0;
    GameState@ doorWinner = null;
    uint32 tsCompare = doorTs;
    if (tsCompare < since) tsCompare = since;

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

      newFlags |= uint8(remote.room_flags & mask & ~flags);

      if (remote.room_door_ts > tsCompare) {
        @doorWinner = remote;
        tsCompare = remote.room_door_ts;
      }
    }

    if (newFlags != 0) {
      flags |= newFlags;
      bus::write_u8(0x7E0403, flags);

      // remove bonk keys of those flags (they only check $0403 when the room loads):
      for (uint x = 0; x < 0x10; x++) {
        if (bus::read_u8(0x7E0DD0 + x) == 0) continue;
        if (bus::read_u8(0x7E0E20 + x) != 0x3B) continue;
        if (bus::read_u8(0x7E0DC0 + x) != 0x01) continue;
        auto idx = bus::read_u8(0x7E0CBA + x);
        if (idx == 0 && (newFlags & room_flag_key0) == 0) continue;
        if (idx == 1 && (newFlags & room_flag_key1) == 0) continue;
        if (idx > 1) continue;
        bus::write_u8(0x7E0DD0 + x, 0);
      }
    }

    if (doorWinner is null) return;

    auto newDoor = doorWinner.room_door;
    if (newDoor == door) {
      // already in agreement; keep the latest timestamp:
      doorTs = doorWinner.room_door_ts;
      return;
    }
    if (tag_computes_doors(bus::read_u8(0x7E00AE)) || tag_computes_doors(bus::read_u8(0x7E00AF))) return;

    // do what a room tag does to operate the shutters:
    bus::write_u16(0x7E0468, newDoor);
    bus::write_u16(0x7E068E, 0);
    bus::write_u16(0x7E0690, 0);
    bus::write_u8(0x7E012F, 0x25); // SFX3.25
    bus::write_u8(0x7E0011, 0x05); // move the shutters (OperateShutterDoors)

    door = newDoor;
    doorTs = doorWinner.room_door_ts;
  }

  void serialize(array<uint8> &r) {
    if (!valid) return;
    r.write_u8(msg_room_state);
    r.write_u16(room);
    r.write_u8(flags);
    r.write_u32(doorTs);
    r.write_u8(door);
  }
};

RoomStateLocal roomState;
