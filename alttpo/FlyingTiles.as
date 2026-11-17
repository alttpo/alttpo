// Flying floor tile synchronization, wire-compatible with o2 (see o2's games/alttp/synctiles.go and ALTTPO_COMPAT.md).
//
// Some dungeon rooms have a tile room overlord (type $14, Overlord14_TileRoom) that, while it is on screen, lifts the
// room's floor tiles one after another and flings them at Link: 128 frames after the room loads and then every 96
// frames it spawns the next of 22 tile sprites ($94) at a fixed position (TileRoom_SpawnTile). The tile erases its floor
// tile right away (UpdateTilemapWithCommonObject with object 6), rises and flies at Link. After the 22nd tile the
// overlord frees its slot. The state is the overlord's $0B28+k (tiles spawned) and its timer $0B30+k, counting down
// from 0 (first tile) or $E0 to $80.
//
//   - It is sent in message 0x1D (uint16 room, uint8 count (22 once the overlord is done), uint8 timer) in a
//     broadcastSector packet to the current room's sector, once the room's tile room overlord was seen in this room
//     visit. A receiver drops a player's state whenever that player's location changes.
//   - A player takes the state of a remote player in the same room that is further along by more than a few frames
//     (more tiles spawned, or the same number and more time elapsed), while the local overlord is on screen and so
//     ticking: it erases the floor tiles the remote player's overlord already lifted (at most 4 per frame, since every
//     erased tile queues a VRAM upload) and takes over the remote count and timer, or frees the overlord when the
//     remote one is done. The tiles already flying for the remote player are not spawned here.
//
// With "Sync enemies" on, alttpo players also copy the overlords of the player owning the room's enemies, which agrees
// with this.

const uint8 msg_flying_tiles = 0x1D;
const uint8 overlord_tile_room = 0x14;
const uint8 flying_tiles_count = 22;
// the remote state is always a few frames old, which must not make two players keep taking each other's state:
const int flying_tiles_ahead = 8;
const uint8 flying_tiles_per_frame = 4;

// the floor tile positions TileRoom_SpawnTile spawns the tiles at, in spawn order (kSpawnFlyingTile_X/Y):
const array<uint8> flying_tile_x = {
  0x70, 0x80, 0x60, 0x90, 0x90, 0x60, 0x70, 0x80, 0x80, 0x70, 0x50, 0xA0, 0xA0, 0x50, 0x50, 0xA0,
  0xA0, 0x50, 0x70, 0x80, 0x80, 0x70
};
const array<uint8> flying_tile_y = {
  0x80, 0x80, 0x70, 0x90, 0x70, 0x90, 0x60, 0xA0, 0x60, 0xA0, 0x60, 0xB0, 0x60, 0xB0, 0x80, 0x90,
  0x80, 0x90, 0x70, 0x90, 0x70, 0x90
};

// flying_tiles_progress orders tile room overlord states by how far along they are.
int flying_tiles_progress(uint8 count, uint8 timer) {
  if (count >= flying_tiles_count) return int(flying_tiles_count) << 8;
  uint8 start = (count == 0) ? 0x00 : 0xE0;
  return (int(count) << 8) | int(uint8(start - timer));
}

class FlyingTilesLocal {
  // valid is true once the tile room overlord was seen in room during this room visit:
  bool valid = false;
  uint16 room = 0;
  uint8 count = 0;
  uint8 timer = 0;
  // active is true while the overlord is in slot:
  bool active = false;
  uint8 slot = 0;

  void reset() {
    valid = false;
    active = false;
    count = 0;
    timer = 0;
  }

  // called every frame from LocalGameState::update_wram:
  void update() {
    auto module = local.module;
    if (module == 0x0E) {
      // menus pause the overlords; keep the state:
      return;
    }
    if (module != 0x07) {
      reset();
      return;
    }
    auto r = bus::read_u16(0x7E00A0);
    if (r != room) {
      // every room load reloads the overlords:
      reset();
      room = r;
    }
    // room loads happen in other submodules:
    if (local.sub_module != 0x00) return;

    int k = -1;
    for (uint i = 0; i < 8; i++) {
      if (bus::read_u8(0x7E0B00 + i) == overlord_tile_room) {
        k = int(i);
        break;
      }
    }
    if (k < 0) {
      if (active) {
        // the overlord freed its slot after the last tile:
        active = false;
        count = flying_tiles_count;
        timer = 0;
      }
      return;
    }

    valid = true;
    active = true;
    slot = uint8(k);
    count = bus::read_u8(0x7E0B28 + k);
    timer = bus::read_u8(0x7E0B30 + k);

    if (!settings.SyncTilemap) return;

    // Overlord14_TileRoom only ticks while its position is on screen:
    uint8 xHi = bus::read_u8(0x7E0B10 + k);
    uint8 yHi = bus::read_u8(0x7E0B20 + k);
    uint16 x = uint16((uint16(bus::read_u8(0x7E0B08 + k)) | (uint16(xHi) << 8)) - bus::read_u16(0x7E00E2));
    uint16 y = uint16((uint16(bus::read_u8(0x7E0B18 + k)) | (uint16(yHi) << 8)) - bus::read_u16(0x7E00E8));
    if ((x & 0xFF00) != 0 || (y & 0xFF00) != 0) return;

    if (rom.fn_update_tilemap_with_common_object == 0) return;

    // find the remote player in the same room furthest along:
    GameState@ winner = null;
    int best = flying_tiles_progress(count, timer) + flying_tiles_ahead;
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
      if (!remote.flying_tiles_valid || remote.flying_tiles_room != room) continue;

      int pr = flying_tiles_progress(remote.flying_tiles_count, remote.flying_tiles_timer);
      if (pr > best) {
        best = pr;
        @winner = remote;
      }
    }
    if (winner is null) return;

    uint8 newCount = winner.flying_tiles_count;
    uint8 newTimer = winner.flying_tiles_timer;
    if (newCount > flying_tiles_count) newCount = flying_tiles_count;
    if (newCount < count) return;

    // erase the floor tiles the remote overlord already lifted, a few per frame and as many as fit in the patch
    // buffer (24 bytes each, and 5 to end it):
    uint8 most = flying_tiles_per_frame;
    int room_left = (0x100 - 5 - int(pb.offset)) / 24;
    if (room_left < int(most)) most = uint8(room_left < 0 ? 0 : room_left);
    if (newCount > count + most) {
      newCount = count + most;
      // keep waiting for the next tile while the remaining tiles are erased:
      newTimer = 0xE0;
    }
    if (newCount == count && newCount < winner.flying_tiles_count) return;

    for (uint8 i = count; i < newCount; i++) {
      // erase the floor tile like Tile_DeleteFloor:
      pb.lda_immed(flying_tile_x[i]);
      pb.sta_dp(0x00);
      pb.lda_immed(xHi);
      pb.sta_dp(0x01);
      pb.lda_immed(flying_tile_y[i]);
      pb.sta_dp(0x02);
      pb.lda_immed(yHi);
      pb.sta_dp(0x03);
      pb.ldy_immed(0x06);
      pb.jsl(rom.fn_update_tilemap_with_common_object);
    }
    if (newCount >= flying_tiles_count) {
      // the overlord is done:
      bus::write_u8(0x7E0B00 + k, 0);
      active = false;
    }
    bus::write_u8(0x7E0B28 + k, newCount);
    bus::write_u8(0x7E0B30 + k, newTimer);
    count = newCount;
    timer = newTimer;
  }

  void serialize(array<uint8> &r) {
    if (!valid) return;
    r.write_u8(msg_flying_tiles);
    r.write_u16(room);
    r.write_u8(count);
    r.write_u8(timer);
  }
};

FlyingTilesLocal flyingTiles;
