// Heart container and heart piece synchronization, wire-compatible with o2 (see o2's games/alttp/synchearts.go and
// ALTTPO_COMPAT.md).
//
// Hearts used to be synced by taking the highest value of $7EF36C (health capacity) and $7EF36B (heart pieces). Two
// players collecting different heart pieces at about the same time then ended up with only one of them. Hearts are
// instead synced like small keys (SmallKeys.as), as per-player counters of *changes*:
//
//   - The count is the total number of heart pieces, ($7EF36C & $F8) / 2 + ($7EF36B & 3), a heart container counting
//     as four pieces. It is at most 20 hearts and 3 pieces, 83.
//   - Each player tracks `net`: the number of pieces the local player collected during this sync session, not
//     counting sync writes, and broadcasts (session, net, value) every frame in message type 0x83.
//   - When a receiver sees a remote player's net go up, it adds the difference to its own count between frames. The
//     first message seen from a remote session only establishes a baseline.
//   - A player with no history (fresh session, game reloaded) catches up once by adopting the highest count of the
//     remote players on the same team.
//
// Hearts only go up, except for a moment when the 4th piece is collected: the game sets $7EF36B to 0 right away but
// only adds a heart to $7EF36C once Link stops holding it up. The local count is therefore tracked as a high-water
// mark: decreases are ignored and only counts above it are taken as local changes. Sync writes raise the high-water
// mark by the amount they added.
//
// Message 0x83 format (all integers little-endian):
//   uint32 session
//   int16  net    heart pieces collected by that player this session
//   uint8  value  current heart piece count; $FF if unknown

const uint8 msg_hearts = 0x83;

// highest heart piece count: 20 hearts and 3 pieces:
const int heart_pieces_max = 20 * 4 + 3;
// sent as the value of a heart piece count not yet read:
const uint8 heart_pieces_unknown = 0xFF;

uint8 heart_pieces(uint8 capacity, uint8 pieces) {
  return uint8(((capacity & 0xF8) >> 1) | (pieces & 3));
}

// describe_heart_pieces describes a number of heart pieces in hearts and pieces, e.g. "1 new heart, 2 new heart pieces".
string describe_heart_pieces(int n) {
  int full = n >> 2;
  int pieces = n & 3;
  string hc;
  if (full == 1) {
    hc = "1 new heart";
  } else if (full > 1) {
    hc = fmtInt(full) + " new hearts";
  }
  if (full >= 1 && pieces >= 1) hc += ", ";
  if (pieces == 1) {
    hc += "1 new heart piece";
  } else if (pieces > 1) {
    hc += fmtInt(pieces) + " new heart pieces";
  }
  return hc;
}

// HeartsRemote is the last heart state received from a remote player.
class HeartsRemote {
  bool valid = false;
  uint32 session = 0;
  int16 net = 0;
  uint8 value = heart_pieces_unknown;

  // applied is the remote player's net already accounted for (applied to our count or taken as a baseline):
  int16 applied = 0;
};

// HeartsLocal tracks the local player's heart state.
class HeartsLocal {
  // uniquely identifies this player's sync session; changes on reset so remote baselines are re-established:
  uint32 session = 0;

  // valid is true when observed holds a value read while in a stable game state:
  bool valid = false;
  // observed is the high-water mark of the heart piece count, accounting for all local changes and sync writes:
  uint8 observed = 0;
  // net is the number of heart pieces the local player collected during this session:
  int16 net = 0;
  // caughtUp is true once we adopted the group's heart count (or nobody had a higher one):
  bool caughtUp = false;

  // pending is the number of heart pieces collected by remote players not yet added to our count:
  int pending = 0;
  // names of the players pending was collected by, for the notification:
  array<string> pendingFrom;

  // whether sync was enabled last frame:
  bool enabled = false;
  // last module seen, to detect returning to the title/file select screens:
  uint8 lastModule = 0;

  // start a new sync session:
  void init() {
    session = small_key_new_session();
    valid = false;
    observed = 0;
    net = 0;
    caughtUp = false;
    pending = 0;
    pendingFrom.resize(0);
    if (debugData) {
      dbgData("hearts: new session " + fmtHex(session, 8));
    }
  }

  // forget the observed heart count so it is re-read without counting any difference as a local change. When adopt is
  // true, also catch up to the group's heart count again.
  void invalidate(bool adopt) {
    valid = false;
    if (adopt) {
      pending = 0;
      pendingFrom.resize(0);
      caughtUp = false;
    }
  }

  void record_local_change(int delta) {
    if (delta <= 0) return;
    net = int16(int(net) + delta);
    dbgData("hearts: local: " + fmtInt(delta) + " heart pieces (net " + fmtInt(net) + ")");
  }

  // called once per frame from on_main_alttp, between frames, after receiving network updates:
  void update() {
    if (session == 0) {
      init();
    }

    uint8 module = local.module;
    if (module <= 0x05 && lastModule > 0x05) {
      // back at the title, file select or loading screens; a different game may be loaded so re-read the heart count
      // without attributing any changes to the local player and re-adopt the group's count:
      invalidate(true);
    }
    lastModule = module;

    if (settings.SyncHearts != enabled) {
      enabled = settings.SyncHearts;
      if (enabled) {
        // start fresh so remote players don't apply hearts we collected while sync was disabled:
        init();
      }
    }
    if (!enabled) return;

    // only sample during stable game states:
    if (!(module == 0x07 || module == 0x09 || module == 0x0B) || local.sub_module != 0) {
      return;
    }
    if (local.is_frozen()) {
      // Link is frozen, e.g. holding up an item; a heart container may be about to be added:
      return;
    }

    uint8 v = heart_pieces(bus::read_u8(0x7EF36C), bus::read_u8(0x7EF36B));
    if (!valid) {
      // first observation; nothing to attribute:
      valid = true;
      observed = v;
    } else if (v > observed) {
      record_local_change(int(v) - int(observed));
      observed = v;
    }
    // v < observed: the 4th piece was collected and the heart container is not added yet.

    adopt();

    if (pending <= 0) return;

    // apply pending remote changes; we are between frames so this read-modify-write cannot race with the game:
    int delta = pending;
    if (delta > heart_pieces_max) delta = heart_pieces_max;
    pending = 0;

    int after = int(v) + delta;
    if (after > heart_pieces_max) after = heart_pieces_max;
    bus::write_u8(0x7EF36B, uint8(after & 3));
    uint8 oldCap = bus::read_u8(0x7EF36C);
    uint8 newCap = uint8((after & ~3) << 1);
    bus::write_u8(0x7EF36C, newCap);
    // fill one heart (8) of health for each heart container added:
    if (newCap > oldCap) {
      int health = int(bus::read_u8(0x7EF36D)) + int(newCap - oldCap);
      if (health > int(newCap)) health = int(newCap);
      bus::write_u8(0x7EF36D, uint8(health));
    }

    int mark = int(observed) + delta;
    if (mark > heart_pieces_max) mark = heart_pieces_max;
    observed = uint8(mark);

    dbgData("hearts: update: " + fmtInt(v) + " +" + fmtInt(delta) + " -> " + fmtInt(after));
    if (pendingFrom.length() > 0) {
      string from;
      for (uint i = 0; i < pendingFrom.length(); i++) {
        if (i > 0) from += ", ";
        from += pendingFrom[i];
      }
      local.notify("got " + describe_heart_pieces(delta) + " from " + from);
    }
    pendingFrom.resize(0);
  }

  // adopt makes a player with no heart history catch up to the group's heart count. This only happens once per
  // session (or after the game is reloaded) so that it never discards deltas during normal play.
  void adopt() {
    if (!valid || caughtUp) return;

    GameState@ highest = null;
    uint plen = players.length();
    for (uint i = 0; i < plen; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (remote.team != local.team) continue;

      auto @rh = remote.hearts;
      if (!rh.valid || rh.value == heart_pieces_unknown) continue;
      if (highest is null || rh.value > highest.hearts.value) {
        @highest = remote;
      }
    }
    if (highest is null) {
      // no remote players with known heart counts yet:
      return;
    }

    caughtUp = true;
    uint8 value = highest.hearts.value;
    if (value <= observed) return;

    // replace any pending changes since the adopted value already includes them:
    pending = int(value) - int(observed);
    pendingFrom.resize(0);
    pendingFrom.insertLast(highest.name);
    dbgData("hearts: catch up to " + fmtInt(value) + " heart pieces from player '" + highest.name + "'");
  }

  void serialize(array<uint8> &r) {
    r.write_u8(msg_hearts);
    r.write_u32(session);
    r.write_u16(uint16(net));
    if (valid) {
      r.write_u8(observed);
    } else {
      // don't let anyone adopt a value we haven't read yet:
      r.write_u8(heart_pieces_unknown);
    }
  }

  // receive_remote handles a hearts message from a remote player.
  void receive_remote(GameState@ remote, uint32 rsession, int16 rnet, uint8 rvalue) {
    auto @rh = remote.hearts;

    if (!rh.valid || rh.session != rsession) {
      // first message from this session; only establish a baseline:
      rh.valid = true;
      rh.session = rsession;
      rh.applied = rnet;
      dbgData("hearts: player '" + remote.name + "' session " + fmtHex(rsession, 8) + " baseline");
    } else {
      int d = int(rnet) - int(rh.applied);
      if (d != 0) {
        rh.applied = rnet;
        if (d > 0 && enabled && remote.team == local.team) {
          pending += d;
          if (pendingFrom.find(remote.name) < 0) {
            pendingFrom.insertLast(remote.name);
          }
          dbgData("hearts: remote: player '" + remote.name + "' +" + fmtInt(d) + " heart pieces");
        }
      }
    }

    rh.net = rnet;
    rh.value = rvalue;
  }
};

HeartsLocal heartsSync;

// remove_collected_heart_sprites removes the heart piece ($EB) and heart container ($EA) sprites of the current
// overworld area once its heart was collected. Picking one up sets bit $40 of the area's flags at $7EF280 (which
// SpritePrep_HeartContainer only checks when the area loads), so when another player collected it, the sprite would
// otherwise stay until the area reloads and could be collected twice. Destroying Agahnim's barrier (sprite $40, at
// Hyrule Castle) with the Master Sword sets the same bit, which SpritePrep_AgahnimsBarrier checks to draw it destroyed
// ($0DC0 = 4, which also makes it harmless). Called every frame from on_main_alttp.
void remove_collected_heart_sprites() {
  if (!settings.SyncOverworld) return;
  if (!(local.module == 0x09 || local.module == 0x0B)) return;
  if (bus::read_u8(0x7E001B) != 0) return;

  uint8 area = bus::read_u8(0x7E008A);
  if (area >= 0xC0) return;
  if ((bus::read_u8(0x7EF280 + uint32(area)) & 0x40) == 0) return;

  for (uint32 i = 0; i < 0x10; i++) {
    if (bus::read_u8(0x7E0DD0 + i) == 0) continue;
    uint8 type = bus::read_u8(0x7E0E20 + i);
    if (type == 0x40) {
      if (bus::read_u8(0x7E0DC0 + i) != 4) bus::write_u8(0x7E0DC0 + i, 4);
      continue;
    }
    if (type != 0xEB && type != 0xEA) continue;
    bus::write_u8(0x7E0DD0 + i, 0);
  }
}

// set when overworld area flags ($7EF280..$7EF33F) were received, so they are applied right away:
bool overworld_flags_received = false;
