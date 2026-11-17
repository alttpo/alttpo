// Secrets under objects lifted by remote players, compatible with o2 (see o2's games/alttp/syncsecrets.go and
// ALTTPO_COMPAT.md).
//
// When Link lifts a bush, rock or sign in the overworld (Overworld_HandleLiftableTiles) the game looks its position up
// in the area's hidden items (Overworld_RevealSecret), which sets the low byte of $0B9C to the item's secret index (0
// if none). Sprite_SpawnThrowableTerrain then spawns the carried object and, under it, the secret: for bushes without
// a hidden item Overworld_SubstituteAlternateSecret may pick a green rupee, an enemy or a bee instead, and in the
// overworld Sprite_SpawnSecret only spawns anything half of the time and picks a random prize for secret 4. Lifting a
// pot in the underworld looks it up in the room's pot items instead (RevealPotItem), which also marks the item taken
// in $7EF580 (except keys, whose sprite checks the room's key flags).
//
// When a remote player lifts one while the local player is in the same area or room (Map16Changes.as and
// Manipulables.as find out), the patch buffer first does the same lookup at that position and calls
// Sprite_SpawnThrowableTerrain_silently there like the game, so the local player gets the same item (or the game's
// own random prize) to pick up, then removes the carried object sprite it spawned. $0B9C, $0314 and $0FB2 are restored
// afterwards.

// bytes emit_ow_reveal and emit_pot_reveal write to the patch buffer, at most:
const uint secret_reveal_size = 72;

// LinkToss_liftable_tiles: the tile types Link can lift, by thrown object type:
const array<uint8> link_toss_liftable_tiles = {0x54, 0x52, 0x50, 0xFF, 0x51, 0x53, 0x55, 0x56, 0x57};

class Secrets {
  bool read = false;
  // the small objects Overworld_HandleLiftableTiles reveals secrets under (bush, dark bush, light rock, dark rock,
  // sign) and the thrown object type of each:
  array<uint16> tiles;
  array<uint8> toss;

  uint32 read_u24(uint32 addr) {
    return uint32(bus::read_u16(addr)) | (uint32(bus::read_u8(addr + 2)) << 16);
  }

  // reads the small liftable objects from the ROM's code (the tile operands of Overworld_HandleLiftableTiles' CMPs,
  // which differ between US and JP ROMs), and their thrown object types the way Overworld_GetLiftableTileType finds
  // them: the tile type (OverworldTileTypes) of the top left 8x8 tile of the map16 tile (Map16Definitions):
  void read_liftables() {
    if (read) return;
    read = true;
    tiles.resize(0);
    toss.resize(0);
    // operands of `LDA.l Map16Definitions,X` and `LDA.l OverworldTileTypes,X`:
    uint32 defs = read_u24(0x1BC041);
    uint32 types = read_u24(0x1BC04F);
    array<uint32> operands = {0x1BBFE7, 0x1BBFEF, 0x1BBFF7, 0x1BBFFC, 0x1BC001};
    for (uint k = 0; k < operands.length(); k++) {
      uint16 tile = bus::read_u16(operands[k]);
      uint16 chr = bus::read_u16(defs + (uint32(tile) << 3)) & 0x01FF;
      uint8 typ = bus::read_u8(types + chr);
      int t = link_toss_liftable_tiles.find(typ);
      if (t < 0) continue;
      tiles.insertLast(tile);
      toss.insertLast(uint8(t));
    }
  }

  // returns the thrown object type of a small liftable object, or -1:
  int ow_toss(uint16 tile) {
    read_liftables();
    int k = tiles.find(tile);
    if (k < 0) return -1;
    return toss[k];
  }

  bool can_reveal_ow() {
    return rom.fn_overworld_reveal_secret != 0 && rom.fn_bank1b_rtl != 0 && rom.fn_spawn_throwable_terrain_silently != 0;
  }

  bool can_reveal_pot() {
    return rom.fn_reveal_pot_item != 0 && rom.fn_bank01_rtl != 0 && rom.fn_spawn_throwable_terrain_silently != 0;
  }

  // emit_ow_reveal reveals the secret under the small liftable object of thrown object type t at tilemap offset p
  // like lifting it does. 16-bit registers:
  void emit_ow_reveal(uint16 p, uint8 t) {
    save();
    pb.ldx_immed16(p);
    pb.jsr_banked(rom.fn_overworld_reveal_secret, rom.fn_bank1b_rtl);
    // like Overworld_GetLinkMap16Coords: $0708 = the area's Y, $070C = its X >> 3:
    uint16 x = uint16(((p & 0x007E) + bus::read_u16(0x7E070C)) << 3);
    uint16 y = uint16(((p & 0x1F80) >> 3) + bus::read_u16(0x7E0708));
    spawn(x, y, t);
  }

  // emit_pot_reveal reveals the item under the pot at tilemap position p ($0540) in room like lifting it does.
  // 16-bit registers:
  void emit_pot_reveal(uint16 room, uint16 p) {
    save();
    pb.lda_immed16(uint16((p & 0x3FFF) >> 1));
    pb.sta_dp(0x06);
    pb.lda_immed16(p);
    pb.jsr_banked(rom.fn_reveal_pot_item, rom.fn_bank01_rtl);
    // rooms are 512x512 pixels at (room & $0F, (room & $F0) >> 4) and the tilemap is 64x64 8x8 tiles:
    uint16 x = uint16(((room & 0x0F) << 9) + ((p & 0x007E) << 2));
    uint16 y = uint16(((room & 0xF0) << 5) + ((p & 0x1F80) >> 4));
    spawn(x, y, 0);
  }

  private void save() {
    pb.lda_bank(0x0B9C);
    pb.pha();
    pb.lda_bank(0x0314);
    pb.pha();
    pb.lda_bank(0x0FB2);
    pb.pha();
  }

  // spawn the secret the game put in $0B9C at x, y like lifting an object of type t does, remove the carried object
  // sprite it spawned and restore what save() saved:
  private void spawn(uint16 x, uint16 y, uint8 t) {
    pb.lda_immed16(x);
    pb.sta_dp(0x00);
    pb.lda_immed16(y);
    pb.sta_dp(0x02);
    pb.sep(0x30);
    pb.lda_immed(t);
    pb.jsl(rom.fn_spawn_throwable_terrain_silently);
    // X = the carried object's slot, or $FF if none was free:
    pb.txa();
    pb.w.u8(0x30); // BMI +3
    pb.w.u8(0x03);
    pb.w.u8(0x9E); // STZ $0DD0,X
    pb.w.u16(0x0DD0);
    pb.rep(0x30);
    pb.pla();
    pb.sta_bank(0x0FB2);
    pb.pla();
    pb.sta_bank(0x0314);
    pb.pla();
    pb.sta_bank(0x0B9C);
  }
};

Secrets secrets;
