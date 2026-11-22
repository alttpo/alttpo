// Sending state only when it changes (see o2's BANDWIDTH.md and games/alttp/send.go).
//
// The state messages that don't change every frame are sent when they change and again every few sends, so that a
// lost packet or a player who just arrived catches up: small keys and hearts, the crystal switch, Link's sprites and
// their palettes, the room's state and the enemies killed. The underworld and overworld SRAM are sent only where they
// changed, and whole every 16 sends or when a player joins the group.

// how often an unchanged message is sent again, in sends (at most 60 a second):
const int crystal_refresh = 32;
const int small_keys_refresh = 32;
const int room_refresh = 16;
const int enemies_killed_refresh = 16;
// remote sprites are drawn for remote_sprites_stale (250 ms) after they arrive, here and in o2:
const int sprites_refresh = 8;
const int palette_refresh = 32;
// SRAM checks for changes between whole sends:
const uint sram_full_refresh = 16;

// Compact messages, shared with o2 (see its games/alttp/compact.go). Players whose clients have them send the location
// and small keys as changes to the last full message:
//
//   - 0x87 features: `features u8`, sent with the name every 30 sends; bit 0 (feature_compact) says the client reads
//     0x88 and 0x89. While any player in the group hasn't said so, the full messages are sent as before.
//   - 0x89 location changes: `base u8`, `mask u8`, then a u16 for each bit of mask: X ($01), Y ($02), X scroll offset
//     ($04), Y scroll offset ($08), the values that differ from those of the full location 0x01 sent in the packet with
//     frame number base. A full location goes out when any other field changes and every location_key_refresh sends.
//   - 0x88 small key changes: `base u8`, `count u8`, then `k u8`, `net i16`, `value u8`, `ts u32` for each dungeon that
//     differs from the full small keys 0x82 sent in the packet with frame number base. Sent when they change and every
//     small_keys_refresh sends (with no dungeons when nothing changed); a full 0x82 goes out when more than
//     small_keys_max_changes dungeons differ and every small_keys_key_refresh sends.
//
// Both go out in full when a player joins. A receiver without the base of a change ignores it until the next full
// message; since changes are relative to the full message, a lost packet is repaired by the next one.
const uint8 feature_compact = 0x01;
const int location_key_refresh = 60;
const int small_keys_key_refresh = 256;
const int small_keys_max_changes = 2;
const uint32 name_refresh = 30;

bool bytes_equal(array<uint8> &in a, array<uint8> &in b) {
  if (a.length() != b.length()) return false;
  for (uint i = 0; i < a.length(); i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ChangeSender is what was last sent of a message that is only sent when it changes.
class ChangeSender {
  array<uint8> last;
  uint32 lastSeq = 0;
  int age = 0;
  bool ok = false;

  // due reports whether m is to be sent on send number seq: when it changed, was not sent on the previous send, or
  // every `every` sends. If so it is recorded as sent.
  bool due(array<uint8> &in m, uint32 seq, int every) {
    age++;
    if (ok && lastSeq + 1 == seq && age < every && bytes_equal(m, last)) {
      lastSeq = seq;
      return false;
    }
    lastSeq = seq;
    last = m;
    age = 0;
    ok = true;
    return true;
  }
};

// SramSender is what was last sent of an SRAM range that is sent only where it changed.
class SramSender {
  // the SRAM last sent, by offset:
  array<uint8> last(0x500);
  uint checks = 0;
  // full is set to send all of it next time:
  bool full = true;
};
