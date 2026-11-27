// Consumable synchronization: rupees, bombs and arrows, wire-compatible with o2 (see o2's
// games/alttp/syncconsumables.go and ALTTPO_COMPAT.md).
//
// The consumables go up (picked up, bought, refilled) and down (spent, used) at any time by any player, like small
// keys, so they are synced the same way (SmallKeys.as), as per-player counters of *changes*. Each consumable has its
// own sync setting (SyncRupees, SyncBombs, SyncArrows):
//
//   - Each player tracks `net[k]`: the cumulative sum of the changes the local player made to consumable k during this
//     sync session, not counting sync writes, and broadcasts (session, net[], value[], timestamp[]) in message 0x24
//     when it changes and every 32 sends (see SendState.as). While a consumable's sync is off its net does not change
//     and its value is sent as unknown; turning it on catches up to the group's count again.
//   - When a receiver with that consumable's sync on sees a remote player's net[k] change, it adds the difference to
//     its own count between frames. The first message from a remote session only establishes a baseline.
//   - A player with no history (fresh session, game reloaded, sync just turned on) catches up once by adopting the
//     count of the remote player that most recently changed it (or the highest count if nobody has changed it yet).
//
// The counts:
//
//   - Rupees: $7EF360, the 16-bit goal the shown count ($7EF362) counts towards. The HUD's refill logic caps it at 999
//     (9999 in randomizers), read from the ROM; the count is taken as at most that, so the capping is not a change.
//   - Bombs: $7EF343. Picking up bombs adds to the bomb refill counter ($7EF375), which adds a bomb a frame while below
//     the capacity: by the upgrade level $7EF370 in the vanilla game (10, 15, ... 50), $7EF370 itself in randomizers.
//   - Arrows: $7EF377, like bombs, with $7EF376 and the capacity $7EF371 (30, 35, ... 70 in the vanilla game). The bow
//     ($7EF340: 1 or 3 without arrows, 2 or 4 with) is updated when a sync write takes the count to or from zero, as the
//     game's Hud_RefreshIcon would. The archery game (sprite $65) sets the arrows back to the count it saved every
//     frame, so the arrows are neither sampled nor written while one is active.
//
// Sync writes are capped at the capacity, and at zero.
//
// Message 0x24 format (all integers little-endian):
//   uint32 session, uint8 count (3), then per consumable k (rupees, bombs, arrows):
//     int32  net        cumulative change made by that player this session
//     uint16 value      current count; $FFFF if unknown or not synced
//     uint32 timestamp  server time in msec (truncated to 32 bits) of the last change; 0 if none this session


const int consumable_rupees = 0;
const int consumable_bombs = 1;
const int consumable_arrows = 2;
const int consumable_count = 3;
// sent as the value of a count not yet read or not synced:
const uint16 consumable_unknown = 0xFFFF;

const array<string> consumable_names = {"rupees", "bombs", "arrows"};

// the vanilla game's capacities for each upgrade level of $7EF370 and $7EF371:
const array<uint8> vanilla_max_bombs = {10, 15, 20, 25, 30, 35, 40, 50};
const array<uint8> vanilla_max_arrows = {30, 35, 40, 45, 50, 55, 60, 70};

// the `LDA.w #999` of the HUD's refill logic that caps the rupees (randomizers change it to 9999):
const uint32 rupee_limit_lda = 0x0DDBF0;
const uint16 vanilla_rupee_limit = 999;

bool consumable_sync_enabled(int k) {
  switch (k) {
    case consumable_rupees: return settings.SyncRupees;
    case consumable_bombs: return settings.SyncBombs;
    case consumable_arrows: return settings.SyncArrows;
  }
  return false;
}

bool any_consumable_sync_enabled() {
  return settings.SyncRupees || settings.SyncBombs || settings.SyncArrows;
}

// rupee_limit returns the most rupees the game holds, from the ROM's HUD refill logic.
uint16 rupee_limit() {
  if (bus::read_u8(rupee_limit_lda) != 0xA9) return vanilla_rupee_limit;
  uint16 v = bus::read_u16(rupee_limit_lda + 1);
  if (v == 0 || v > 9999) return vanilla_rupee_limit;
  return v;
}

// consumable_max returns the most of consumable k the local player can hold now.
uint16 consumable_max(int k) {
  if (k == consumable_rupees) return rupee_limit();

  uint8 level = bus::read_u8(0x7EF370 + uint32(k - consumable_bombs));
  if (cast<RandomizerMapping>(rom) !is null) {
    // randomizers keep the capacity itself:
    return level;
  }
  if (level > 7) level = 7;
  if (k == consumable_bombs) return vanilla_max_bombs[level];
  return vanilla_max_arrows[level];
}

// consumable_value reads consumable k's count.
uint16 consumable_value(int k) {
  switch (k) {
    case consumable_rupees: {
      uint16 v = bus::read_u16(0x7EF360);
      uint16 limit = rupee_limit();
      // the refill logic caps the goal once the count shown reaches it:
      if (v > limit) v = limit;
      return v;
    }
    case consumable_bombs: return bus::read_u8(0x7EF343);
    case consumable_arrows: return bus::read_u8(0x7EF377);
  }
  return 0;
}

// consumable_write writes consumable k's count, and the bow for the arrows.
void consumable_write(int k, uint16 v) {
  switch (k) {
    case consumable_rupees:
      bus::write_u16(0x7EF360, v);
      return;
    case consumable_bombs:
      bus::write_u8(0x7EF343, uint8(v));
      return;
    case consumable_arrows: {
      bus::write_u8(0x7EF377, uint8(v));
      // the bow with or without arrows (1, 3 without; 2, 4 with), as Hud_RefreshIcon sets it:
      uint8 bow = bus::read_u8(0x7EF340);
      if (bow != 0) {
        uint8 nb = uint8(((bow - 1) & 2) + 1 + (v != 0 ? 1 : 0));
        if (nb != bow) bus::write_u8(0x7EF340, nb);
      }
      return;
    }
  }
}

// archery_game_active reports whether an archery game sprite ($65) is active, which pins the arrow count.
bool archery_game_active() {
  for (uint32 i = 0; i < 0x10; i++) {
    if (bus::read_u8(0x7E0DD0 + i) != 0 && bus::read_u8(0x7E0E20 + i) == 0x65) return true;
  }
  return false;
}

// ConsumablesRemote is the last consumable state received from a remote player.
class ConsumablesRemote {
  bool valid = false;
  uint32 session = 0;
  array<int32> net(3);
  array<uint16> value(3);
  array<uint32> ts(3);

  // applied is the remote player's net[] already accounted for (applied to our counts or taken as a baseline):
  array<int32> applied(3);

  void reset() {
    valid = false;
    session = 0;
    for (int k = 0; k < consumable_count; k++) {
      net[k] = 0;
      value[k] = consumable_unknown;
      ts[k] = 0;
      applied[k] = 0;
    }
  }
};

// ConsumablesLocal tracks the local player's consumable state.
class ConsumablesLocal {
  // uniquely identifies this player's sync session; changes on reset so remote baselines are re-established:
  uint32 session = 0;

  // each consumable's sync setting when last updated, to catch up when it is turned on:
  array<bool> enabled(3);
  // valid is true when observed holds a value read while in a stable game state:
  array<bool> valid(3);
  // observed is the last known count, accounting for all local changes and sync writes:
  array<uint16> observed(3);
  // net is the cumulative sum of changes made by the local player during this session:
  array<int32> net(3);
  // ts is the server time (msec) of the last change to the count; 0 means no change during this session:
  array<uint32> ts(3);
  // caughtUp is true once we have either adopted the group's count or had any activity this session:
  array<bool> caughtUp(3);

  // pending is the sum of remote changes not yet applied to our counts:
  array<int> pending(3);

  // last module seen, to detect returning to the title/file select screens:
  uint8 lastModule = 0;

  // start a new sync session:
  void init() {
    session = small_key_new_session();
    for (int k = 0; k < consumable_count; k++) {
      valid[k] = false;
      observed[k] = 0;
      net[k] = 0;
      ts[k] = 0;
      caughtUp[k] = false;
      pending[k] = 0;
    }
    if (debugData) {
      dbgData("consumables: new session " + fmtHex(session, 8));
    }
  }

  // forget consumable k's observed count so it is re-read without counting any difference as a local change. When
  // adopt is true, also catch up to the group's count again.
  void invalidate(int k, bool adopt) {
    valid[k] = false;
    if (adopt) {
      ts[k] = 0;
      pending[k] = 0;
      caughtUp[k] = false;
    }
  }

  void record_local_change(int k, int delta, uint32 nowTs) {
    if (delta == 0) return;
    net[k] = net[k] + delta;
    ts[k] = nowTs;
    caughtUp[k] = true;
    dbgData("consumables: local: " + consumable_names[k] + " " + fmtInt(delta) + " (net " + fmtInt(net[k]) + ")");
  }

  // called once per frame from on_main_alttp, between frames, after receiving network updates:
  void update() {
    if (session == 0) {
      init();
    }

    uint8 module = local.module;
    bool reloaded = module <= 0x05 && lastModule > 0x05;
    lastModule = module;

    for (int k = 0; k < consumable_count; k++) {
      bool on = consumable_sync_enabled(k);
      if (reloaded || on != enabled[k]) {
        // back at the title, file select or loading screens, where a different game may be loaded, or sync was just
        // turned on or off: re-read the count without attributing any change to the local player and catch up to
        // the group's count, so remote players don't apply changes made while sync was off and we get theirs:
        invalidate(k, true);
      }
      enabled[k] = on;
    }
    if (!any_consumable_sync_enabled()) return;

    // only sample during stable game states:
    if (!(module == 0x07 || module == 0x09 || module == 0x0B) || local.sub_module != 0) {
      return;
    }

    bool archery = archery_game_active();

    // record changes made by the local player:
    uint32 nowTs = 0;
    for (int k = 0; k < consumable_count; k++) {
      if (!enabled[k]) continue;
      if (k == consumable_arrows && archery) continue;

      uint16 v = consumable_value(k);
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
    for (int k = 0; k < consumable_count; k++) {
      if (!enabled[k] || !valid[k] || pending[k] == 0) continue;
      if (k == consumable_arrows && archery) continue;

      int delta = pending[k];
      pending[k] = 0;

      int max = consumable_max(k);
      int before = observed[k];
      int after = before + delta;
      bool underflow = false;
      if (after < 0) {
        after = 0;
        underflow = true;
      } else if (after > max) {
        after = max;
      }
      if (after == before) continue;

      consumable_write(k, uint16(after));
      observed[k] = uint16(after);
      if (nowTs == 0) nowTs = small_key_now_ts();
      ts[k] = nowTs;
      caughtUp[k] = true;

      dbgData("consumables: update: " + consumable_names[k] + " " + fmtInt(before) + " " + fmtInt(delta) + " -> " + fmtInt(after));
      if (underflow) {
        dbgData("consumables: " + consumable_names[k] + " spent more than we had");
      }
    }
  }

  // adopt makes a player with no history catch up to the group's current counts. This only happens once per session
  // (or after the game is reloaded or sync is turned on) so that it never discards deltas during normal play.
  void adopt() {
    uint plen = players.length();
    for (int k = 0; k < consumable_count; k++) {
      if (!enabled[k] || !valid[k] || caughtUp[k]) continue;

      // find the remote player that changed the count most recently, else the one with the highest count:
      GameState@ latest = null;
      GameState@ highest = null;
      for (uint i = 0; i < plen; i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is local) continue;
        if (remote.ttl <= 0) continue;
        if (remote.team != local.team) continue;

        auto @rc = remote.consumables;
        if (!rc.valid || rc.value[k] == consumable_unknown) continue;

        if (rc.ts[k] != 0 && (latest is null || rc.ts[k] > latest.consumables.ts[k])) {
          @latest = remote;
        }
        if (highest is null || rc.value[k] > highest.consumables.value[k]) {
          @highest = remote;
        }
      }
      if (highest is null) {
        // no remote players with known counts yet:
        continue;
      }

      caughtUp[k] = true;

      GameState@ winner = latest;
      if (winner is null) {
        if (highest.consumables.value[k] <= observed[k]) continue;
        @winner = highest;
      } else {
        ts[k] = winner.consumables.ts[k];
      }

      uint16 value = winner.consumables.value[k];
      // replace any pending changes since the adopted value already includes them:
      pending[k] = int(value) - int(observed[k]);
      if (pending[k] != 0) {
        dbgData("consumables: catch up " + consumable_names[k] + " = " + fmtInt(value) + " from player '" + winner.name + "'");
      }
    }
  }

  void serialize(array<uint8> &r) {
    uint mst = msg_begin(r, msg_consumables);
    r.write_u32(session);
    r.write_u8(uint8(consumable_count));
    for (int k = 0; k < consumable_count; k++) {
      r.write_u32(uint32(net[k]));
      if (enabled[k] && valid[k]) {
        r.write_u16(observed[k]);
        r.write_u32(ts[k]);
      } else {
        // don't let anyone adopt a value we haven't read yet or don't sync:
        r.write_u16(consumable_unknown);
        r.write_u32(0);
      }
    }
    msg_end(r, mst);
  }

  // receive_remote handles a consumables message from a remote player.
  void receive_remote(GameState@ remote, uint32 rsession, const array<int32> &in rnet, const array<uint16> &in rvalue, const array<uint32> &in rts) {
    auto @rc = remote.consumables;

    if (!rc.valid || rc.session != rsession) {
      // first message from this session; only establish a baseline:
      rc.valid = true;
      rc.session = rsession;
      for (int k = 0; k < consumable_count; k++) {
        rc.applied[k] = rnet[k];
      }
      dbgData("consumables: player '" + remote.name + "' session " + fmtHex(rsession, 8) + " baseline");
    } else {
      for (int k = 0; k < consumable_count; k++) {
        int d = rnet[k] - rc.applied[k];
        if (d == 0) continue;
        rc.applied[k] = rnet[k];
        if (!consumable_sync_enabled(k)) continue;
        if (remote.team != local.team) continue;
        pending[k] += d;
        dbgData("consumables: remote: player '" + remote.name + "' " + consumable_names[k] + " " + fmtInt(d));
      }
    }

    for (int k = 0; k < consumable_count; k++) {
      rc.net[k] = rnet[k];
      rc.value[k] = rvalue[k];
      rc.ts[k] = rts[k];
    }
  }
};

ConsumablesLocal consumablesSync;
