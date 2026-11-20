// Enemies killed synchronization, wire-compatible with o2 (see o2's games/alttp/syncenemieskilled.go).
//
// Shares the game's memory of which enemies were killed in the room or area with players in the same room or area, so
// that enemies another player killed stay dead the next time the game would spawn them, without syncing the enemies
// themselves (that is what the LTTP enemy sync does). Enemies alive on the local screen are left alone.
//
//   - Underworld: $7FDF80 is a [$128]uint16 array indexed by room ($048E): bit k is set when the room's k-th sprite
//     (sprite_N $0BC0,X) dies (Sprite_ManuallySetDeathFlagUW), and Dungeon_LoadSingleSprite does not spawn it while
//     set.
//   - Overworld: $7FEF80 is a bitmap of the area's sprite positions (blk; bit $80 >> (blk & 7) of byte blk >> 3) that
//     were loaded. A sprite going off screen clears its bit (Sprite_KillSelf) and so does an overlord; a sprite that
//     dies leaves it set, so it does not spawn again until the area reloads. A killed position is thus a bit that is
//     set while no live sprite ($0DD0,X != 0 with $0BC0,X as a uint16 blk) nor overlord ($0B00,X != 0 with $0B48,X as a
//     uint16 blk) has it. Only bytes $00-$BF are used by an area.
//
// Message 0x1F is sent in its own broadcastSector packet to the room's or the area's sector every 4 sends:
//
//   - `kind u8` = 0 (underworld), `room u16`, `mask u16`: $7FDF80 + room * 2.
//   - `kind u8` = 1 (overworld), `loc u24` (see ow_location), `count u8`, `blk u16` * count: the killed positions.
//
// Applying, in submodule 0 of the dungeon module ($07) or the overworld module ($09), for remote players on the same
// team in the same room or area: the bits they killed that are not set here are set.

const uint8 msg_enemies_killed = 0x1F;
const uint8 enemies_killed_uw = 0;
const uint8 enemies_killed_ow = 1;
const uint32 enemies_killed_room_masks = 0x7FDF80;
const uint32 enemies_killed_ow_loaded = 0x7FEF80;
const uint enemies_killed_ow_bytes = 0xC0;
const uint enemies_killed_max_blks = 64;

class EnemiesKilledLocal {
  // valid is true when sampled in the room or area id this frame:
  bool valid = false;
  uint8 kind = 0;
  // the room (underworld) or the location (overworld):
  uint32 id = 0;
  uint16 mask = 0;
  array<uint16> blks;
  // calls to send() since the last send:
  private uint sendCalls = 0;

  // called every frame from on_main_alttp:
  void update() {
    valid = false;
    blks.resize(0);
    if (!settings.SyncEnemiesKilled) return;
    if (local is null || local.get_in_sm()) return;
    if (bus::read_u8(0x7E0011) != 0) return;

    uint8 module = bus::read_u8(0x7E0010);
    if (module == 0x07) {
      uint16 room = bus::read_u16(0x7E048E);
      if (room != bus::read_u16(0x7E00A0) || room >= 0x128) return;
      update_underworld(room);
    } else if (module == 0x09 && bus::read_u8(0x7E001B) == 0) {
      uint32 loc = ow_location();
      if (loc == ow_location_none) return;
      update_overworld(loc);
    }
  }

  private void update_underworld(uint16 room) {
    uint32 addr = enemies_killed_room_masks + uint32(room) * 2;
    uint16 have = bus::read_u16(addr);
    uint16 want = 0;
    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (!is_remote_here(remote)) continue;
      if (remote.module != 0x07 || remote.in_dungeon == 0 || remote.dungeon_room != room) continue;
      if (remote.ek_kind != enemies_killed_uw || remote.ek_id != room) continue;
      want |= remote.ek_mask & ~have;
    }
    if (want != 0) {
      have |= want;
      bus::write_u16(addr, have);
    }

    valid = true;
    kind = enemies_killed_uw;
    id = room;
    mask = have;
  }

  private void update_overworld(uint32 loc) {
    array<uint8> loaded(enemies_killed_ow_bytes);
    bus::read_block_u8(enemies_killed_ow_loaded, 0, enemies_killed_ow_bytes, loaded);

    // the remote players' killed positions not loaded here:
    uint16 area = uint16(loc);
    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (!is_remote_here(remote)) continue;
      if (!remote.is_in_overworld_module() || remote.in_dungeon != 0 || remote.overworld_room != area) continue;
      if (remote.ek_kind != enemies_killed_ow || remote.ek_id != loc) continue;
      for (uint j = 0; j < remote.ek_blks.length(); j++) {
        uint16 blk = remote.ek_blks[j];
        uint b = blk >> 3;
        if (b >= enemies_killed_ow_bytes) continue;
        uint8 bit = uint8(0x80 >> (blk & 7));
        if ((loaded[b] & bit) != 0) continue;
        loaded[b] |= bit;
        bus::write_u8(enemies_killed_ow_loaded + b, loaded[b]);
      }
    }

    // the loaded positions of the live sprites and overlords are not killed:
    for (uint k = 0; k < 0x10; k++) {
      if (bus::read_u8(0x7E0DD0 + k) == 0) continue;
      clear_blk(loaded, bus::read_u16(0x7E0BC0 + k * 2));
    }
    for (uint k = 0; k < 8; k++) {
      if (bus::read_u8(0x7E0B00 + k) == 0) continue;
      clear_blk(loaded, bus::read_u16(0x7E0B48 + k * 2));
    }
    for (uint b = 0; b < enemies_killed_ow_bytes && blks.length() < enemies_killed_max_blks; b++) {
      uint8 v = loaded[b];
      for (uint j = 0; j < 8 && v != 0; j++) {
        if ((v & (0x80 >> j)) == 0) continue;
        blks.insertLast(uint16((b << 3) | j));
        if (blks.length() >= enemies_killed_max_blks) break;
      }
    }

    valid = true;
    kind = enemies_killed_ow;
    id = loc;
  }

  private void clear_blk(array<uint8> &loaded, uint16 blk) {
    uint b = blk >> 3;
    if (b >= enemies_killed_ow_bytes) return;
    loaded[b] &= ~uint8(0x80 >> (blk & 7));
  }

  private bool is_remote_here(GameState@ remote) {
    if (remote is null) return false;
    if (remote is local) return false;
    if (remote.ttl <= 0) return false;
    if (remote.team != local.team) return false;
    if (remote.get_in_sm()) return false;
    if (!remote.ek_valid) return false;
    return local.is_really_in_same_location(remote.location);
  }

  // sends message 0x1F in its own packet to the room's or the area's sector every 4 calls (not on frames with
  // (frame & 3) == 0, which the net rate limiter can skip every time):
  uint send(uint p) {
    if (!valid) return p;
    if (++sendCalls < 4) return p;
    sendCalls = 0;
    auto @envelope = local.make_packet_broadcast_to_sector(local.broadcast_sector());
    serialize(envelope);
    return local.send_packet(envelope, p);
  }

  void serialize(array<uint8> &r) {
    r.write_u8(msg_enemies_killed);
    r.write_u8(kind);
    if (kind == enemies_killed_uw) {
      r.write_u16(uint16(id));
      r.write_u16(mask);
      return;
    }
    r.write_u8(uint8(id));
    r.write_u8(uint8(id >> 8));
    r.write_u8(uint8(id >> 16));
    r.write_u8(uint8(blks.length()));
    for (uint i = 0; i < blks.length(); i++) {
      r.write_u16(blks[i]);
    }
  }
};

EnemiesKilledLocal enemiesKilled;
