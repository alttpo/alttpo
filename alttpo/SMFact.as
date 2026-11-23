// Samus graphics facts (facts 0x10 and 0x11; see o2-server's PROTOCOL05.md, "Sprites with facts"): Samus' tiles
// from the ROM, which SM DMAs into VRAM chrs $00-$1F by pose. Each fact is the used part of two banks, from $8000:
//
//   fact  banks     tiles          size
//   0x10  $9C, $9D  $3D4 + $3BC    61,952 bytes
//   0x11  $9E, $9F  $3B6 + $3BA    60,928 bytes
//
// The rest of each bank is $FF padding. Fact tiles are numbered from the start of the fact, so a tile of the second
// bank is the first bank's tile count plus its tile in its bank. The facts are built from ROM for every SM ROM (SMZ3
// included), so they are ready at join like fact 0x00.
const uint8 fact_sm_graphics_lo = 0x10;
const uint8 fact_sm_graphics_hi = 0x11;

// the four banks, in fact order, and how many tiles each holds:
const array<uint8> sm_fact_bank = {0x9C, 0x9D, 0x9E, 0x9F};
const array<uint> sm_fact_bank_tiles = {0x3D4, 0x3BC, 0x3B6, 0x3BA};

// sm_fact_tile finds the fact and tile that a ROM address of Samus' graphics shows (n tiles from there, all in the
// same bank). It returns false if the address is outside the facts.
bool sm_fact_tile(uint8 bank, uint16 offs, uint n, uint8 &out fact, uint16 &out tile) {
  if (offs < 0x8000 || (offs & 0x1F) != 0) return false;
  uint t = (offs - 0x8000) >> 5;
  for (uint b = 0; b < sm_fact_bank.length(); b++) {
    if (sm_fact_bank[b] != bank) continue;
    if (t + n > sm_fact_bank_tiles[b]) return false;
    fact = (b < 2) ? fact_sm_graphics_lo : fact_sm_graphics_hi;
    if ((b & 1) != 0) t += sm_fact_bank_tiles[b - 1];
    tile = uint16(t);
    return true;
  }
  return false;
}

// build_sm_facts builds facts 0x10 and 0x11 from the ROM, for SM ROMs.
void build_sm_facts() {
  if (rom is null || !rom.is_sm()) return;
  for (uint f = 0; f < 2; f++) {
    LocalFact lf;
    lf.num = (f == 0) ? fact_sm_graphics_lo : fact_sm_graphics_hi;
    uint o = 0;
    for (uint b = f * 2; b < f * 2 + 2; b++) {
      uint size = sm_fact_bank_tiles[b] << 5;
      lf.data.resize(o + size);
      bus::read_block_u8((uint32(sm_fact_bank[b]) << 16) | 0x8000, o, size, lf.data);
      o += size;
    }
    local_facts.insertLast(lf);
    message("facts: built the Samus graphics fact " + fmtHex(lf.num, 2) + ", " + fmtInt(lf.data.length()) + " bytes");
  }
}

// sm_chr_rows appends the rows of Samus' chrs $00-$1F bound to the SM facts this frame, from her pose's tile
// definitions: the top half's tiles go to chrs $00-$07 (the first part) and $10-$17 (the second), the bottom half's to
// $08-$0F and $18-$1F. Each part is one run of consecutive tiles in ROM.
void sm_chr_rows(uint8 pose, uint8 anim_frame, array<ChrRow@> &rows) {
  uint32 anim_table_offs = bus::read_u16(0x92D94E + (uint32(pose) << 1));
  uint32 anim_frame_addr = 0x920000 + anim_table_offs + (uint32(anim_frame) << 2);
  for (uint half = 0; half < 2; half++) {
    uint32 ptr_idx = uint32(bus::read_u8(anim_frame_addr + half * 2 + 0));
    uint32 def_idx = uint32(bus::read_u8(anim_frame_addr + half * 2 + 1));
    uint32 table = (half == 0) ? 0x92D91E : 0x92D938;
    uint32 def = 0x920000 + uint32(bus::read_u16(table + (ptr_idx << 1))) + def_idx * 7;
    uint16 offs = bus::read_u16(def + 0);
    uint8 bank = bus::read_u8(def + 2);
    array<uint16> part = {bus::read_u16(def + 3), bus::read_u16(def + 5)};
    for (uint row = 0; row < 2; row++) {
      uint n = part[row] >> 5;
      if (n > 8) n = 8;
      uint8 fact;
      uint16 tile;
      if (n > 0 && sm_fact_tile(bank, offs, n, fact, tile)) {
        ChrRow r;
        r.chr = uint8(half * 8 + row * 0x10);
        r.n = uint8(n);
        r.fact = fact;
        r.tile = tile;
        rows.insertLast(r);
      }
      offs += part[row];
    }
  }
}
