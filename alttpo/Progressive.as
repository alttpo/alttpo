// Progressive item synchronization (VT randomizers), wire-compatible with o2 (see o2's games/alttp/syncprogressive.go
// and ALTTPO_COMPAT.md).
//
// The randomizers built on z3randomizer (ALTTPR, the Door, Entrance and Overworld Randomizers) place progressive
// swords, shields, mails and gloves. Picking one up gives the next level after the one the player has: ResolveLootID
// reads HighestSword ($7EF417), HighestShield ($7EF422), HighestMail ($7EF46E) or GloveEquipment ($7EF354). These used
// to be synced by their highest value, so two players who each found a progressive sword both stayed at the fighter
// sword: each had gone from 0 to 1. Every progressive item found by anyone should upgrade everybody, so the levels are
// synced like the consumables (Consumables.as), as per-player counters of *changes*, in message 0x26:
//
//   - Each player tracks `net[k]`: the cumulative number of levels item k went up during this sync session, not
//     counting sync writes, and broadcasts (session, net[], value[]) when it changes and every small_keys_refresh sends.
//   - When a receiver sees a remote player's net[k] go up, it adds the difference to its own level between frames,
//     capped at the item's highest level. The first message from a remote session only establishes a baseline.
//   - A player with no history (fresh session, game reloaded) catches up once by adopting the highest level of the
//     remote players on the same team.
//
// The equipment (SwordEquipment $7EF359, ShieldEquipment $7EF35A, ArmorEquipment $7EF35B) is raised to the new level
// where it is below it, and the sword and shield graphics and palettes are redrawn. The equipment itself is still synced
// by its highest value too.
//
// Message 0x26 format (all integers little-endian):
//   uint32 session, uint8 count (4), then per item k (sword, shield, mail, gloves):
//     int16 net    cumulative levels gained by that player this session
//     uint8 value  current level; $FF if unknown or not synced
//
// Pendant and crystal counters: z3randomizer counts the pendants and crystals given in PendantCounter ($7EF429) and
// CrystalCounter ($7EF476), which open Ganon's Tower, pull the pedestal and make Ganon vulnerable (the Door
// Randomizer's GoalConditionTable). Synced by their highest value, players with different prizes each kept the larger
// of their own counts. They are not synced; each is kept at the number of bits set in its field ($7EF374, $7EF37A),
// which are synced, outside of item receipts ($02E4 = 0): the game sets the bit and adds to the counter at different
// times. That also undoes the count the game adds when a crystal it already has is picked up again.

const int progressive_sword = 0;
const int progressive_shield = 1;
const int progressive_mail = 2;
const int progressive_gloves = 3;
const int progressive_count = 4;
// sent as the value of a level not yet read or not synced:
const uint8 progressive_unknown = 0xFF;

const array<string> progressive_names = {"sword", "shield", "mail", "gloves"};
// the SRAM offset of each item's level that the next progressive pickup is based on:
const array<uint16> progressive_level = {0x417, 0x422, 0x46E, 0x354};
// the SRAM offset of the equipment raised along with it, or 0 for the level itself:
const array<uint16> progressive_equipment = {0x359, 0x35A, 0x35B, 0};
const array<uint8> progressive_max = {4, 3, 2, 2};

// progressive_sync_enabled reports whether progressive item levels are synced as deltas: in the VT randomizers, with
// items. SMZ3 keeps its own item rules.
bool progressive_sync_enabled() {
  if (settings is null || !settings.SyncItems) return false;
  return is_vt_randomizer();
}

// is_vt_randomizer reports whether the ROM is one of the randomizers built on z3randomizer, other than SMZ3:
bool is_vt_randomizer() {
  if (rom is null) return false;
  if (cast<SMZ3Mapping>(rom) !is null) return false;
  return cast<RandomizerMapping>(rom) !is null;
}

// progressive_level_names returns the name of each level 1..max of item k:
const array<string>@ progressive_level_names(int k) {
  switch (k) {
    case progressive_sword: return swordNames;
    case progressive_shield: return shieldNames;
    case progressive_mail: return armorNames;
  }
  return glovesNames;
}

// ProgressiveRemote is the last progressive item state received from a remote player.
class ProgressiveRemote {
  bool valid = false;
  uint32 session = 0;
  array<int16> net(4);
  array<uint8> value(4);

  // applied is the remote player's net[] already accounted for (applied to our levels or taken as a baseline):
  array<int16> applied(4);

  void reset() {
    valid = false;
    session = 0;
    for (int k = 0; k < progressive_count; k++) {
      net[k] = 0;
      value[k] = progressive_unknown;
      applied[k] = 0;
    }
  }
};

// ProgressiveLocal tracks the local player's progressive item levels.
class ProgressiveLocal {
  // uniquely identifies this player's sync session; changes on reset so remote baselines are re-established:
  uint32 session = 0;

  bool enabled = false;
  // valid is true when observed holds a value read while in a stable game state:
  array<bool> valid(4);
  // observed is the last known level, accounting for all local changes and sync writes:
  array<uint8> observed(4);
  // net is the number of levels the local player gained during this session:
  array<int16> net(4);
  // caughtUp is true once we adopted the group's level (or nobody had a higher one):
  array<bool> caughtUp(4);

  // pending is the number of levels gained by remote players not yet added to ours:
  array<int> pending(4);
  // pendingFrom names the players pending was gained by, for the notification:
  array<array<string>> pendingFrom(4);

  // last module seen, to detect returning to the title/file select screens:
  uint8 lastModule = 0;

  void init() {
    session = small_key_new_session();
    for (int k = 0; k < progressive_count; k++) {
      valid[k] = false;
      observed[k] = 0;
      net[k] = 0;
      caughtUp[k] = false;
      pending[k] = 0;
      pendingFrom[k].resize(0);
    }
    if (debugData) {
      dbgData("progressive: new session " + fmtHex(session, 8));
    }
  }

  // forget the observed levels so they are re-read without counting any difference as a local change, and catch up to
  // the group's levels again:
  void invalidate() {
    for (int k = 0; k < progressive_count; k++) {
      valid[k] = false;
      pending[k] = 0;
      pendingFrom[k].resize(0);
      caughtUp[k] = false;
    }
  }

  void record_local_change(int k, int delta) {
    if (delta <= 0) return;
    net[k] = int16(net[k] + delta);
    dbgData("progressive: local: " + progressive_names[k] + " +" + fmtInt(delta) + " (net " + fmtInt(net[k]) + ")");
  }

  // called once per frame from update_wram, between frames, after receiving network updates:
  void update() {
    if (session == 0) {
      init();
    }

    uint8 module = local.module;
    bool reloaded = module <= 0x05 && lastModule > 0x05;
    lastModule = module;

    bool on = progressive_sync_enabled();
    if (reloaded || on != enabled) {
      // back at the title, file select or loading screens, where a different game may be loaded, or sync was just
      // turned on or off:
      invalidate();
    }
    enabled = on;
    if (!enabled) return;

    // only sample during stable game states:
    if (!(module == 0x07 || module == 0x09 || module == 0x0B) || local.sub_module != 0) {
      return;
    }

    // record levels gained by the local player:
    for (int k = 0; k < progressive_count; k++) {
      uint8 v = bus::read_u8(0x7EF000 + progressive_level[k]);
      if (!valid[k] || v < observed[k]) {
        // first observation, or the game went back (debug, a reload): nothing to attribute:
        valid[k] = true;
        observed[k] = v;
        continue;
      }
      if (v == observed[k]) continue;

      record_local_change(k, int(v) - int(observed[k]));
      observed[k] = v;
    }

    adopt();

    // add the levels remote players gained; we are between frames so this read-modify-write cannot race with the game:
    for (int k = 0; k < progressive_count; k++) {
      if (!valid[k] || pending[k] <= 0) continue;

      int delta = pending[k];
      pending[k] = 0;
      array<string> from = pendingFrom[k];
      pendingFrom[k].resize(0);

      int before = observed[k];
      int after = before + delta;
      if (after > int(progressive_max[k])) after = progressive_max[k];
      if (after <= before) continue;

      write(k, uint8(after));
      observed[k] = uint8(after);
      caughtUp[k] = true;

      dbgData("progressive: update: " + progressive_names[k] + " " + fmtInt(before) + " +" + fmtInt(delta) + " -> " + fmtInt(after));
      if (from.length() > 0) {
        auto @names = progressive_level_names(k);
        string name = "progressive " + progressive_names[k];
        if (after - 1 < int(names.length())) name = names[after - 1];
        string who = "";
        for (uint i = 0; i < from.length(); i++) {
          if (i > 0) who += ", ";
          who += from[i];
        }
        notificationSystem.notify("Got " + name + " from " + who);
      }
    }
  }

  // write sets item k's level, raises its equipment to it, and redraws the sword, shield or palette:
  void write(int k, uint8 level) {
    bus::write_u8(0x7EF000 + progressive_level[k], level);
    uint16 equipment = progressive_equipment[k];
    if (equipment != 0) {
      uint8 e = bus::read_u8(0x7EF000 + equipment);
      if (e < level) bus::write_u8(0x7EF000 + equipment, level);
    }
    switch (k) {
      case progressive_sword:
        pb.jsl(rom.fn_decomp_sword_gfx);
        pb.jsl(rom.fn_sword_palette);
        break;
      case progressive_shield:
        pb.jsl(rom.fn_decomp_shield_gfx);
        pb.jsl(rom.fn_shield_palette);
        break;
      default:
        pb.jsl(rom.fn_armor_glove_palette);
        break;
    }
  }

  // adopt makes a player with no history catch up to the group's levels. This only happens once per session (or after
  // the game is reloaded) so that it never discards deltas during normal play.
  void adopt() {
    uint plen = players.length();
    for (int k = 0; k < progressive_count; k++) {
      if (!valid[k] || caughtUp[k]) continue;

      GameState@ highest = null;
      for (uint i = 0; i < plen; i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is local) continue;
        if (remote.ttl <= 0) continue;
        if (remote.team != local.team) continue;

        auto @rp = remote.progressive;
        if (!rp.valid || rp.value[k] == progressive_unknown) continue;
        if (highest is null || rp.value[k] > highest.progressive.value[k]) {
          @highest = remote;
        }
      }
      if (highest is null) {
        // no remote players with known levels yet:
        continue;
      }

      caughtUp[k] = true;
      uint8 value = highest.progressive.value[k];
      if (value <= observed[k]) continue;

      // replace any pending changes since the adopted value already includes them:
      pending[k] = int(value) - int(observed[k]);
      pendingFrom[k].resize(0);
      pendingFrom[k].insertLast(highest.name);
      dbgData("progressive: catch up to " + progressive_names[k] + " " + fmtInt(value) + " from player '" + highest.name + "'");
    }
  }

  void serialize(array<uint8> &r) {
    uint mst = msg_begin(r, msg_progressive);
    r.write_u32(session);
    r.write_u8(uint8(progressive_count));
    for (int k = 0; k < progressive_count; k++) {
      r.write_u16(uint16(net[k]));
      if (enabled && valid[k]) {
        r.write_u8(observed[k]);
      } else {
        // don't let anyone adopt a value we haven't read yet or don't sync:
        r.write_u8(progressive_unknown);
      }
    }
    msg_end(r, mst);
  }

  // receive_remote handles a progressive items message from a remote player.
  void receive_remote(GameState@ remote, uint32 rsession, const array<int16> &in rnet, const array<uint8> &in rvalue) {
    auto @rp = remote.progressive;

    if (!rp.valid || rp.session != rsession) {
      // first message from this session; only establish a baseline:
      rp.valid = true;
      rp.session = rsession;
      for (int k = 0; k < progressive_count; k++) {
        rp.applied[k] = rnet[k];
      }
      dbgData("progressive: player '" + remote.name + "' session " + fmtHex(rsession, 8) + " baseline");
    } else {
      for (int k = 0; k < progressive_count; k++) {
        int d = int(rnet[k]) - int(rp.applied[k]);
        if (d == 0) continue;
        rp.applied[k] = rnet[k];
        if (d < 0 || !progressive_sync_enabled()) continue;
        if (remote.team != local.team) continue;
        pending[k] += d;
        if (pendingFrom[k].find(remote.name) < 0) {
          pendingFrom[k].insertLast(remote.name);
          pendingFrom[k].sortAsc();
        }
        dbgData("progressive: remote: player '" + remote.name + "' " + progressive_names[k] + " +" + fmtInt(d));
      }
    }

    for (int k = 0; k < progressive_count; k++) {
      rp.net[k] = rnet[k];
      rp.value[k] = rvalue[k];
    }
  }
};

ProgressiveLocal progressiveSync;

// update_prize_counters keeps PendantCounter and CrystalCounter at the number of pendants and crystals (see above).
// Called once per frame from update_wram, between frames.
void update_prize_counters() {
  if (settings is null || !is_vt_randomizer()) return;
  if (!(local.module == 0x07 || local.module == 0x09) || local.sub_module != 0) return;
  // Link is holding up an item; the game may be about to add to a counter:
  if (local.is_frozen()) return;

  if (settings.SyncPendants) {
    update_prize_counter(0x7EF429, 0x7EF374, 0x07);
  }
  if (settings.SyncCrystals) {
    update_prize_counter(0x7EF476, 0x7EF37A, 0x7F);
  }
}

void update_prize_counter(uint32 counter, uint32 field, uint8 mask) {
  uint8 bits = bus::read_u8(field) & mask;
  uint8 want = 0;
  for (; bits != 0; bits &= bits - 1) want++;
  if (bus::read_u8(counter) != want) {
    dbgData("prize counter $" + fmtHex(counter, 6) + " = " + fmtInt(want));
    bus::write_u8(counter, want);
  }
}
