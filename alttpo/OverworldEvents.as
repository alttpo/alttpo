// Overworld event synchronization, wire-compatible with o2 (see o2's games/alttp/syncowevents.go and ALTTPO_COMPAT.md).
//
// Some overworld changes happen while a player is in the area and are animated, but the game only draws them for the
// player who caused them. The area flags ($7EF280+area) make other players load the result once they enter the area
// again; players already in the area see nothing. These events are shared with the players in the same area so they
// see the same animation:
//
//   - Entrance animations. Setting $04C6 (1: Palace of Darkness (Kiki), 2: Skull Woods (fire rod), 3: Misery Mire
//     (medallion), 4: Turtle Rock (medallion), 5: Ganon's Tower (crystals)) with $B0 = $C8 = 0 makes
//     Module09_00_PlayerControl run Overworld_AnimateEntrance every frame, which freezes Link, draws the opened entrance
//     step by step (Overworld_DrawMap16_Persist, which does not log the changes for the map16 sync), sets bit $20 of
//     the area's flags and clears $04C6 when done. Skull Woods is started with FireRodShot_BecomeSkullWoodsFire, which
//     also lights the fire around the entrance.
//   - The Desert Palace statues move apart once $02F0 is set (Link reads the tablet with the Book of Mudora), until the
//     area reloads (Sprite_ResetAll clears $02F0).
//   - The lumberjacks' tree top (sprite $3B with $0DC0 = 2, in area $02) hops and falls apart in leaves when Link
//     dashes into it ($0D80 = 1, $0F80 = 20), revealing the hole under it until the area reloads.
//
// Message 0x1C, broadcastSector: uint24 location (like map16 changes in message 0x17: the area $8A, and bit 17 for the
// dark world; see ow_location), uint8 entrance ($04C6 while an entrance animation runs, else 0),
// uint8 flags (bit 0: the desert statues were released, bit 1: the tree top was dashed into, both during this area
// visit). It is sent in its own packet every frame while something is set, and for a few frames after, in overworld
// modules $09/$0B (and the menus in $0E).
//
// While in the overworld module ($09), submodule 0, in exactly the same location (area and world) as a remote player on
// the same team:
//
//   - If the remote entrance is set, ours is not and the area's overlay (bit $20) was not drawn when the area loaded
//     (nor since by an entrance animation here), start the same entrance animation. Link must be standing on the ground
//     ($5D = 0, $4D = 0, $02E4 = 0), since the animation keeps him frozen in place.
//   - If the remote desert statues were released and ours were not, set $02F0.
//   - If the remote tree top was dashed into and ours still stands, make it hop like the dash does.

const uint8 msg_ow_events = 0x1C;
const uint16 ow_entrance_offs = 0x04C6;
const uint16 ow_desert_offs = 0x02F0;
const uint16 ow_lumberjack_area = 0x02;
const uint8 ow_tree_sprite = 0x3B;
const uint8 ow_event_desert = 0x01;
const uint8 ow_event_tree = 0x02;
const uint8 ow_entrance_skull_woods = 0x02;
const uint8 ow_entrance_max = 0x05;
// frames to keep sending the events after they cleared, so receivers see them clear:
const int ow_events_trail_frames = 16;
// remote events not refreshed within this time (msec) are ignored:
const uint64 ow_events_remote_ttl = 500;

class OverworldEventsLocal {
  // valid is true when the area was sampled in the overworld module, submodule 0:
  bool valid = false;
  // location (see ow_location) and its area:
  uint32 loc = 0;
  uint16 area = 0;
  // shown is true when the area's overlay was drawn: bit $20 of its flags was set when it loaded, or an entrance
  // animation ran here since:
  bool shown = false;
  uint8 entrance = 0;
  // events (ow_event_*) that happened here during this visit:
  uint8 flags = 0;
  int trail = 0;

  void reset() {
    valid = false;
    loc = 0;
    area = 0;
    shown = false;
    entrance = 0;
    flags = 0;
    trail = 0;
  }

  bool tree_dashed() {
    for (uint32 i = 0; i < 0x10; i++) {
      if (bus::read_u8(0x7E0DD0 + i) == 0) continue;
      if (bus::read_u8(0x7E0E20 + i) != ow_tree_sprite) continue;
      if (bus::read_u8(0x7E0DC0 + i) != 2) continue;
      if (bus::read_u8(0x7E0D80 + i) != 0) return true;
    }
    return false;
  }

  // called every frame from LocalGameState::update_wram:
  void update() {
    auto module = local.module;
    if (module == 0x0E) {
      // menus and text boxes keep the area:
      return;
    }
    if (!(module == 0x09 || module == 0x0B) || bus::read_u8(0x7E001B) != 0) {
      reset();
      return;
    }
    uint32 l = ow_location();
    if (l == ow_location_none) return;
    uint16 a = uint16(l);
    if (valid && l != loc) {
      reset();
    }
    // area loads happen in other submodules:
    if (local.sub_module != 0) return;
    if (!valid) {
      if (a >= 0xC0) return;
      valid = true;
      loc = l;
      area = a;
      shown = (bus::read_u8(0x7EF280 + uint32(a)) & 0x20) != 0;
    }

    entrance = bus::read_u8(0x7E0000 + ow_entrance_offs);
    if (entrance != 0) shown = true;
    if (bus::read_u8(0x7E0000 + ow_desert_offs) != 0) flags |= ow_event_desert;
    if (area == ow_lumberjack_area && tree_dashed()) flags |= ow_event_tree;

    apply();
  }

  void apply() {
    if (!settings.SyncOverworldLocal) return;
    if (local.module != 0x09 || local.sub_module != 0) return;
    if (ow_location() != loc) return;

    uint64 now = chrono::monotonic::millisecond;
    uint len = players.length();
    for (uint i = 0; i < len; i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (remote.get_in_sm()) continue;
      // game worlds are team specific:
      if (remote.team != local.team) continue;
      if (!(remote.is_in_overworld_module() || remote.module == 0x0E)) continue;
      // only events in exactly this location, including the world, from players who are still there:
      if (remote.location != loc) continue;
      if (!remote.ow_events_valid || remote.ow_events_loc != loc) continue;
      if (now - remote.ow_events_received > ow_events_remote_ttl) continue;

      auto re = remote.ow_events_entrance;
      if (re != 0 && re <= ow_entrance_max && !shown && entrance == 0) {
        // the animation keeps Link frozen in place; he must be standing on the ground:
        bool ground = bus::read_u8(0x7E005D) == 0 && bus::read_u8(0x7E004D) == 0 && bus::read_u8(0x7E02E4) == 0;
        if (ground) {
          if (re == ow_entrance_skull_woods) {
            if (rom.fn_skull_woods_fire != 0) {
              // light the fire and start the animation like a fire rod shot does:
              pb.jsl(rom.fn_skull_woods_fire);
              shown = true;
            }
          } else {
            bus::write_u8(0x7E0000 + ow_entrance_offs, re);
            bus::write_u8(0x7E00B0, 0);
            bus::write_u8(0x7E00C8, 0);
            entrance = re;
            shown = true;
          }
        }
      }

      auto f = remote.ow_events_flags & ~flags;
      if ((f & ow_event_desert) != 0) {
        // release the desert statues:
        if (bus::read_u8(0x7E0000 + ow_desert_offs) == 0) {
          bus::write_u8(0x7E0000 + ow_desert_offs, 1);
        }
        flags |= ow_event_desert;
      }
      if ((f & ow_event_tree) != 0) {
        // make the tree top hop like dashing into it does:
        for (uint32 s = 0; s < 0x10; s++) {
          if (bus::read_u8(0x7E0DD0 + s) == 0) continue;
          if (bus::read_u8(0x7E0E20 + s) != ow_tree_sprite) continue;
          if (bus::read_u8(0x7E0DC0 + s) != 2) continue;
          if (bus::read_u8(0x7E0D80 + s) != 0) continue;
          bus::write_u8(0x7E0D80 + s, 1);
          bus::write_u8(0x7E0F80 + s, 20);
        }
        flags |= ow_event_tree;
      }
    }
  }

  // sends the events to the players in the same area:
  uint send(uint p) {
    if (!valid) return p;
    if (!(local.is_in_overworld_module() || local.module == 0x0E)) return p;
    if (entrance != 0 || flags != 0) {
      trail = ow_events_trail_frames;
    } else if (trail > 0) {
      trail--;
    } else {
      return p;
    }

    array<uint8> @r = local.make_packet_broadcast_to_sector(local.broadcast_sector());
    r.write_u8(msg_ow_events);
    r.write_u24(loc);
    r.write_u8(entrance);
    r.write_u8(flags);
    return local.send_packet(r, p);
  }
};

OverworldEventsLocal owEvents;

// draw_opened_overlay draws an area's overlay with fn when another player set bit $20 of its flags while the local
// player is in the area (Overworld_AlterWeathervane, OpenGargoylesDomain, CreatePyramidHole); the overlay is otherwise
// only loaded with the area, the next time it is entered. Removes sprites of type sprite (if not 0), e.g. the Thieves'
// Town grate. Called from the SyncableItem of the area's flags, when they change.
void draw_opened_overlay(uint8 area, uint32 fn, uint8 sprite, uint16 oldValue, uint16 newValue, const string &in what) {
  if ((oldValue & 0x20) != 0 || (newValue & 0x20) == 0) return;
  if (fn == 0) return;
  if (local.module != 0x09 || local.sub_module != 0) return;
  if (bus::read_u8(0x7E001B) != 0 || bus::read_u8(0x7E008A) != area) return;

  pb.jsl(fn);
  if (sprite != 0) {
    for (uint32 i = 0; i < 0x10; i++) {
      if (bus::read_u8(0x7E0E20 + i) != sprite) continue;
      bus::write_u8(0x7E0DD0 + i, 0);
    }
  }
  local.notify(what);
}
