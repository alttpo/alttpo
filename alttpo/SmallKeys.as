// Small key synchronization, wire-compatible with o2 (see o2's games/alttp/syncsmallkeys.go and ALTTPO_COMPAT.md).
//
// Small key counts can go up (key picked up) or down (key spent on a door) at any time by any player, so they cannot
// be synced by taking the highest value, nor reliably by "last writer wins" of absolute values: two players changing
// the same dungeon's count at about the same time would lose one of the changes.
//
// Instead, small keys are synced as per-player counters of *changes* (deltas):
//
//   - Each player tracks `net[k]`: the cumulative sum of key changes made by the local player in dungeon k during this
//     sync session. Only changes made by the local player are counted; changes made by sync writes are not.
//   - Each player broadcasts its (session, net[], value[], timestamp[]) in message type 0x82 when it changes and every
//     32 sends (see SendState.as); a frame without it is no change.
//   - When a receiver sees a remote player's net[k] change, it adds the difference to a pending adjustment which is
//     applied to its own key count. The first message seen from a remote session only establishes a baseline.
//   - Adjustments are applied as a read-modify-write between frames (from on_main_alttp) so they can never clobber a
//     local change, and the written value becomes the new observed value so it is never mistaken for a local change.
//   - A player with no history (fresh session, e.g. just connected or reloaded the game) catches up once by adopting
//     the absolute key count of the remote player that most recently changed it (or the highest count if nobody has
//     changed it yet). After that, only deltas are exchanged.
//
// Where the current key count lives:
//
//   - While inside dungeon k, the game uses $7EF36F as the live key count; the per-dungeon slot $7EF37C+k is stale and
//     only gets written back when leaving the dungeon. The slot must be ignored while inside the dungeon.
//   - Otherwise, the per-dungeon slot $7EF37C+k holds the key count.
//   - Sewers ($040C=$00) and Hyrule Castle ($040C=$02) share a single key count; vanilla stores it at $7EF37C and VT
//     randomizers store it in both $7EF37C and $7EF37D. Both are treated as one counter (index 0) and both slots are
//     written.
//
// Message 0x82 format (all integers little-endian):
//   uint32 session, uint8 count (16), then per dungeon slot k:
//     int16  net        cumulative change made by that player this session
//     uint8  value      current key count; $FF if unknown
//     uint32 timestamp  server time in msec (truncated to 32 bits) of the last change; 0 if none this session


const uint16 small_key_first = 0xF37C;
const int small_key_count = 16;
// highest small key count we will write:
const int small_key_max = 99;
// sent as the value of a key count not yet read:
const uint8 small_key_unknown = 0xFF;
// slot index for Hyrule Castle which mirrors the Sewers slot (index 0):
const int small_key_mirror = 1;

const array<string> small_key_names = {
  "Sewers/Hyrule Castle",
  "Hyrule Castle",
  "Eastern Palace",
  "Desert Palace",
  "Agahnim's Tower",
  "Swamp Palace",
  "Palace of Darkness",
  "Misery Mire",
  "Skull Woods",
  "Ice Palace",
  "Tower of Hera",
  "Thieves' Town",
  "Turtle Rock",
  "Ganon's Tower",
  "Extra Dungeon 1",
  "Extra Dungeon 2"
};

// small_key_index returns the small key counter index for the dungeon the player is in ($040C), or -1 if not in a
// dungeon.
int small_key_index(uint8 dungeon) {
  if (dungeon == 0xFF || dungeon >= uint8(small_key_count << 1)) {
    return -1;
  }
  int k = int(dungeon >> 1);
  if (k == small_key_mirror) {
    k = 0;
  }
  return k;
}

// small_key_now_ts returns the current server time in msec truncated to 32 bits; never 0.
uint32 small_key_now_ts() {
  int64 now = server_now();
  uint32 ts;
  if (now == 0) {
    // server clock not yet known; fall back to our own clock:
    ts = uint32(chrono::realtime::millisecond);
  } else {
    ts = uint32(now / 1000000);
  }
  if (ts == 0) ts = 1;
  return ts;
}

uint32 small_key_new_session() {
  uint64 t = chrono::realtime::nanosecond ^ (chrono::monotonic::nanosecond << 17);
  uint32 s = uint32(t & 0xFFFFFFFF) ^ uint32(t >> 32);
  // mix bits so that sessions started close together differ everywhere:
  s ^= s >> 16;
  s *= 0x7feb352d;
  s ^= s >> 15;
  s *= 0x846ca68b;
  s ^= s >> 16;
  if (s == 0) s = 1;
  return s;
}

// SmallKeysRemote is the last small key state received from a remote player.
class SmallKeysRemote {
  bool valid = false;
  uint32 session = 0;
  array<int16> net(16);
  array<uint8> value(16);
  array<uint32> ts(16);

  // applied is the remote player's net[] already accounted for (applied to our key counts or taken as a baseline):
  array<int16> applied(16);

  void reset() {
    valid = false;
    session = 0;
    for (int k = 0; k < small_key_count; k++) {
      net[k] = 0;
      value[k] = small_key_unknown;
      ts[k] = 0;
      applied[k] = 0;
    }
  }
};

// SmallKeysLocal tracks the local player's small key state.
class SmallKeysLocal {
  // uniquely identifies this player's sync session; changes on reset so remote baselines are re-established:
  uint32 session = 0;

  // valid is true when observed holds a value read while in a stable game state:
  array<bool> valid(16);
  // observed is the last known key count, accounting for all local changes and sync writes:
  array<uint8> observed(16);
  // net is the cumulative sum of changes made by the local player during this session:
  array<int16> net(16);
  // ts is the server time (msec) of the last change to the key count; 0 means no change during this session:
  array<uint32> ts(16);
  // caughtUp is true once we have either adopted the group's key count or had any key activity this session:
  array<bool> caughtUp(16);

  // pending is the sum of remote changes not yet applied to our key counts:
  array<int16> pending(16);

  // whether sync was enabled last frame:
  bool enabled = false;
  // last module seen, to detect returning to the title/file select screens:
  uint8 lastModule = 0;

  // start a new sync session:
  void init() {
    session = small_key_new_session();
    for (int k = 0; k < small_key_count; k++) {
      valid[k] = false;
      observed[k] = 0;
      net[k] = 0;
      ts[k] = 0;
      caughtUp[k] = false;
      pending[k] = 0;
    }
    if (debugData) {
      dbgData("smallkeys: new session " + fmtHex(session, 8));
    }
  }

  // forget the observed key counts so they are re-read without counting any difference as a local change. When adopt
  // is true, also catch up to the group's key counts again.
  void invalidate(bool adopt) {
    for (int k = 0; k < small_key_count; k++) {
      valid[k] = false;
      if (adopt) {
        ts[k] = 0;
        pending[k] = 0;
        caughtUp[k] = false;
      }
    }
  }

  void record_local_change(int k, int delta, uint32 nowTs) {
    if (delta == 0) return;
    net[k] = int16(int(net[k]) + delta);
    ts[k] = nowTs;
    caughtUp[k] = true;
    dbgData("smallkeys: local: " + small_key_names[k] + " " + fmtInt(delta) + " (net " + fmtInt(net[k]) + ")");
  }

  // called once per frame from on_main_alttp, between frames, after receiving network updates:
  void update() {
    if (session == 0) {
      init();
    }

    uint8 module = local.module;
    if (module <= 0x05 && lastModule > 0x05) {
      // back at the title, file select or loading screens; a different game may be loaded so re-read key counts
      // without attributing any changes to the local player and re-adopt the group's counts:
      invalidate(true);
    }
    lastModule = module;

    if (settings.SyncSmallKeys != enabled) {
      enabled = settings.SyncSmallKeys;
      if (enabled) {
        // start fresh so remote players don't apply changes we made while sync was disabled:
        init();
      }
    }
    if (!enabled) return;

    // only sample during stable game states where the key count locations are consistent:
    if (!(module == 0x07 || module == 0x09 || module == 0x0B) || local.sub_module != 0) {
      return;
    }

    uint8 dungeon = bus::read_u8(0x7E040C);
    int current = small_key_index(dungeon);
    uint8 currentKeys = bus::read_u8(0x7EF36F);
    if (dungeon != 0xFF && current < 0) {
      // unknown dungeon:
      return;
    }
    if (current >= 0 && currentKeys == 0xFF) {
      // in transition between overworld and dungeon:
      return;
    }

    // record changes made by the local player:
    uint32 nowTs = 0;
    for (int k = 0; k < small_key_count; k++) {
      if (k == small_key_mirror) continue;

      uint8 v;
      if (k == current) {
        v = currentKeys;
      } else {
        v = bus::read_u8(0x7E0000 + uint32(small_key_first) + uint32(k));
      }

      if (!valid[k]) {
        // first observation; nothing to attribute:
        valid[k] = true;
        observed[k] = v;
        continue;
      }

      if (v == observed[k]) continue;

      if (nowTs == 0) nowTs = small_key_now_ts();
      record_local_change(k, int(v) - int(observed[k]), nowTs);
      observed[k] = v;
    }

    adopt();

    // apply pending remote changes; we are between frames so this read-modify-write cannot race with the game:
    for (int k = 0; k < small_key_count; k++) {
      if (k == small_key_mirror) continue;
      if (!valid[k] || pending[k] == 0) continue;

      int delta = pending[k];
      pending[k] = 0;

      int before = observed[k];
      int after = before + delta;
      bool underflow = false;
      if (after < 0) {
        after = 0;
        underflow = true;
      } else if (after > small_key_max) {
        after = small_key_max;
      }

      uint32 slot = 0x7E0000 + uint32(small_key_first) + uint32(k);
      if (k == current) {
        bus::write_u8(0x7EF36F, uint8(after));
      }
      bus::write_u8(slot, uint8(after));
      if (k == 0) {
        bus::write_u8(slot + small_key_mirror, uint8(after));
      }

      observed[k] = uint8(after);
      if (nowTs == 0) nowTs = small_key_now_ts();
      ts[k] = nowTs;
      caughtUp[k] = true;

      dbgData("smallkeys: update: " + small_key_names[k] + " " + fmtInt(before) + " " + fmtInt(delta) + " -> " + fmtInt(after));
      if (underflow) {
        local.notify(small_key_names[k] + " small key double-spend detected");
      }
      local.notify("update " + small_key_names[k] + " small keys to " + fmtInt(after));
    }
  }

  // adopt makes a player with no small key history catch up to the group's current small key counts. This only
  // happens once per session (or after the game is reloaded) so that it never discards deltas during normal play.
  void adopt() {
    uint plen = players.length();
    for (int k = 0; k < small_key_count; k++) {
      if (k == small_key_mirror) continue;
      if (!valid[k] || caughtUp[k]) continue;

      // find the remote player that changed the key count most recently, else the one with the highest count:
      GameState@ latest = null;
      GameState@ highest = null;
      for (uint i = 0; i < plen; i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is local) continue;
        if (remote.ttl <= 0) continue;
        if (remote.team != local.team) continue;

        auto @rk = remote.small_keys;
        if (!rk.valid || rk.value[k] == small_key_unknown) continue;

        if (rk.ts[k] != 0 && (latest is null || rk.ts[k] > latest.small_keys.ts[k])) {
          @latest = remote;
        }
        if (highest is null || rk.value[k] > highest.small_keys.value[k]) {
          @highest = remote;
        }
      }
      if (highest is null) {
        // no remote players with known key counts yet:
        continue;
      }

      caughtUp[k] = true;

      GameState@ winner = latest;
      if (winner is null) {
        if (highest.small_keys.value[k] <= observed[k]) continue;
        @winner = highest;
      } else {
        ts[k] = winner.small_keys.ts[k];
      }

      uint8 value = winner.small_keys.value[k];
      // replace any pending changes since the adopted value already includes them:
      pending[k] = int16(int(value) - int(observed[k]));
      if (pending[k] != 0) {
        dbgData("smallkeys: catch up " + small_key_names[k] + " = " + fmtInt(value) + " from player '" + winner.name + "'");
      }
    }
  }

  void serialize(array<uint8> &r) {
    uint mst = msg_begin(r, msg_small_keys);
    r.write_u32(session);
    r.write_u8(uint8(small_key_count));
    for (int k = 0; k < small_key_count; k++) {
      r.write_u16(uint16(net[k]));
      int kv = k;
      if (k == small_key_mirror) kv = 0;
      if (valid[kv]) {
        r.write_u8(observed[kv]);
        r.write_u32(ts[kv]);
      } else {
        // don't let anyone adopt a value we haven't read yet:
        r.write_u8(small_key_unknown);
        r.write_u32(0);
      }
    }
    msg_end(r, mst);
  }

  // receive_remote handles a small key message from a remote player.
  void receive_remote(GameState@ remote, uint32 rsession, const array<int16> &in rnet, const array<uint8> &in rvalue, const array<uint32> &in rts) {
    auto @rk = remote.small_keys;

    if (!rk.valid || rk.session != rsession) {
      // first message from this session; only establish a baseline:
      rk.valid = true;
      rk.session = rsession;
      for (int k = 0; k < small_key_count; k++) {
        rk.applied[k] = rnet[k];
      }
      dbgData("smallkeys: player '" + remote.name + "' session " + fmtHex(rsession, 8) + " baseline");
    } else {
      for (int k = 0; k < small_key_count; k++) {
        int d = int(rnet[k]) - int(rk.applied[k]);
        if (d == 0) continue;
        rk.applied[k] = rnet[k];
        if (k == small_key_mirror || !enabled) continue;
        if (remote.team != local.team) continue;
        pending[k] = int16(int(pending[k]) + d);
        dbgData("smallkeys: remote: player '" + remote.name + "' " + small_key_names[k] + " " + fmtInt(d));
      }
    }

    for (int k = 0; k < small_key_count; k++) {
      rk.net[k] = rnet[k];
      rk.value[k] = rvalue[k];
      rk.ts[k] = rts[k];
    }
  }
};

SmallKeysLocal smallKeys;
