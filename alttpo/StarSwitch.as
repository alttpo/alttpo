// Star switch synchronization, wire-compatible with o2 (see o2's games/alttp/syncstar.go and ALTTPO_COMPAT.md).
//
// Star tiles (Misery Mire, Turtle Rock, ...) open and close holes in the current room. Stepping on a star tile
// (RoomTag_TriggerHoles) picks the hole overlay for the tile ($04BA), switches to submodule $03 which draws the
// overlay, toggles the star tile state $04BC and swaps the star tile graphics (ToggleStarTileGraphics). The state is
// reset whenever a room is loaded, so it only means something for the current room. It is synced as a last-writer-wins
// value, like the crystal switch state:
//
//   - It is sent in a WRAM syncables message (0x05) for offset $04BC in a broadcastSector packet to the current room's
//     sector. The u16 value carries $04BC in the low byte and the overlay $04BA in the high byte, which a remote player
//     needs to draw the same holes.
//   - Writes to $04BC while in submodule $03 of the dungeon module are the local player stepping on a star tile and are
//     timestamped; any other write (room loads) and any change of room ($A0) only records a new baseline.
//   - While in the dungeon module with submodule 0 and no animation running ($0112), take the state of the remote
//     player in the same room and in the dungeon module with the latest timestamp (or, on a timestamp tie, a higher
//     value). If it differs from ours, do what stepping on the star tile does: set $04BA and $04BC, swap the star tile
//     graphics and switch to submodule $03.

const uint16 star_switch_offs = 0x04BC;
const uint16 star_overlay_offs = 0x04BA;

class StarSwitchLocal {
  // valid is true when value was read in the dungeon module for room:
  bool valid = false;
  uint16 room = 0;
  uint8 value = 0;
  // overlay is $04BA, the hole overlay drawn for the current star tile state:
  uint8 overlay = 0;
  // ts is the time (msec) of the last change in this room; 0 means no change:
  uint32 ts = 0;

  // set while we write $04BC ourselves so the write is not captured as a local change:
  bool applying = false;

  // called from LocalGameState::register:
  void register() {
    // interceptors match the exact bus address and the game writes $04BC with absolute addressing (STA.w $04BC), so
    // register the low WRAM mirrors in banks $00-$3F and $80-$BF as well as bank $7E:
    bus::add_write_interceptor(
      "00-3f,80-bf,7e:" + fmtHex(star_switch_offs, 4),
      bus::WriteInterceptCallback(this.wram_written)
    );
    reset();
  }

  void reset() {
    valid = false;
    ts = 0;
  }

  void baseline() {
    valid = true;
    room = bus::read_u16(0x7E00A0);
    value = bus::read_u8(0x7E0000 + star_switch_offs);
    overlay = bus::read_u8(0x7E0000 + star_overlay_offs);
    ts = 0;
  }

  // bus::WriteInterceptCallback
  void wram_written(uint32 addr, uint8 oldValue, uint8 newValue) {
    if (applying) return;
    if (bus::read_u8(0x7E0010) != 0x07) return;

    auto r = bus::read_u16(0x7E00A0);
    if (bus::read_u8(0x7E0011) != 0x03 || !valid || r != room) {
      // room load (or not seen this room yet); nothing to attribute:
      baseline();
      value = newValue;
      return;
    }
    if (newValue == value) return;

    // the local player stepped on a star tile:
    value = newValue;
    overlay = bus::read_u8(0x7E0000 + star_overlay_offs);
    // server clock, like o2 and small keys:
    ts = small_key_now_ts();
  }

  // called every frame from LocalGameState::update_wram:
  void update() {
    auto module = local.module;
    if (module == 0x0E) {
      // menus don't touch the star switch state; keep it:
      return;
    }
    if (module != 0x07) {
      // left the dungeon module; the next room load resets the state:
      reset();
      return;
    }
    if (!valid || bus::read_u16(0x7E00A0) != room) {
      baseline();
    } else {
      overlay = bus::read_u8(0x7E0000 + star_overlay_offs);
    }

    if (!settings.SyncTilemap) return;
    if (local.sub_module != 0x00 || local.animation_timer != 0) return;
    if (rom.fn_toggle_star_tile_graphics == 0) return;

    // find the latest state among remote players in the same room:
    GameState@ winner = null;
    uint32 tsCompare = ts;
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

      auto rv = uint8(remote.star_value & 0xFF);
      if (remote.star_timestamp > tsCompare) {
        @winner = remote;
        tsCompare = remote.star_timestamp;
      } else if (remote.star_timestamp == ts && rv > value) {
        // somebody may have a larger value that we overwrote:
        @winner = remote;
      }
    }
    if (winner is null) return;

    auto newValue = uint8(winner.star_value & 0xFF);
    auto newOverlay = uint8(winner.star_value >> 8);
    if (newValue == value) {
      // already in agreement; keep the latest timestamp:
      ts = winner.star_timestamp;
      return;
    }
    if (newOverlay == 0) {
      // no overlay to draw; the remote state is not from stepping on a star tile:
      return;
    }

    // do what stepping on the star tile does (RoomTag_TriggerHoles):
    applying = true;
    bus::write_u8(0x7E0000 + star_overlay_offs, newOverlay);
    bus::write_u8(0x7E00BA, 0);
    bus::write_u8(0x7E00BB, 0);
    bus::write_u8(0x7E00B0, 0);
    bus::write_u8(0x7E012F, 0x1B); // SFX3.1B
    bus::write_u8(0x7E0011, 0x03); // draw the overlay
    bus::write_u8(0x7E0000 + star_switch_offs, newValue);
    applying = false;
    // swap the star tile graphics:
    pb.jsl(rom.fn_toggle_star_tile_graphics);

    value = newValue;
    overlay = newOverlay;
    ts = winner.star_timestamp;
  }

  void serialize(array<uint8> &r) {
    uint16 v = 0;
    uint32 t = 0;
    if (valid) {
      v = uint16(value) | (uint16(overlay) << 8);
      t = ts;
    }
    r.write_u8(uint8(0x05));
    r.write_u8(uint8(0x01));
    r.write_u16(star_switch_offs);
    r.write_u32(t);
    r.write_u16(v);
  }
};

StarSwitchLocal starSwitch;
