// Follower graphics fact (fact 0x01), built the same way as o2's games/alttp/followerfact.go, from the ROM over the
// bus.
//
// A follower (Zelda, the old man, the blind maiden, the frogsmith and smithy, the locksmith, Kiki, the purple chest, the
// super bomb) is drawn as two 16x16 sprites, chrs $20 and $22 (only $22 for the purple chest and the super bomb). Every
// frame NMI_DoUpdates uploads their top rows from $7EB940 + dma_var6*2 and + dma_var7*2 ($0AE8, $0AEA, which
// Tagalong_Draw sets from the pose) and their bottom rows from $200 bytes further on (chrs $30-$31, $32-$33). The 32
// tiles at $7EB940..$7EBD3F are what LoadFollowerGraphics built from ROM sprite sheets for the follower ($7EF3CC).
//
// The fact holds that buffer for every follower $00-$0D, $400 bytes each at follower * $400 ($3800 = 14,336 bytes).
// msg_sprite_chrs binds a follower's chrs to it by pose: chr $20 (n = 2) to tile follower*32 + dma_var6/16, chr $30 to
// 16 tiles after it, and the same for chr $22 and $32 with dma_var7 (see follower_chr_rows).
const uint8 fact_follower_graphics = 0x01;

const uint follower_count = 14;
const uint follower_gfx_size = 0x400;
const uint follower_fact_size = follower_count * follower_gfx_size;
const uint follower_fact_tiles = follower_gfx_size >> 5;
const uint follower_fact_bottom_row = 0x200 >> 5;

// LoadFollowerGraphics' code (US 1.0 at $00D423, JP 1.0 at $00D463); -1 marks the bytes read (sheets, thresholds) or
// that differ between ROMs (JSR targets, the offset table's address):
const array<int> follower_gfx_pattern = {
  0x8B, 0x4B, 0xAB,
  0xA0, -1, 0xAF, 0xCC, 0xF3, 0x7E, 0xC9, -1, 0xF0, 0x12,
  0xA0, -1, 0xAF, 0xCC, 0xF3, 0x7E, 0xC9, -1, 0x90, 0x08,
  0xA0, -1, 0xC9, -1, 0x90, 0x02,
  0xA0, -1,
  0x20, -1, -1, 0xA0, -1, 0x20, -1, -1,
  0xC2, 0x30, 0xAF, 0xCC, 0xF3, 0x7E, 0x29, 0xFF, 0x00, 0x0A, 0xAA,
  0xA5, 0x00, 0x18, 0x7F, -1, -1, -1,
  0xA0, 0x20, 0x00, 0xA2, 0x40, 0x29
};

class FollowerFactBuilder {
  // LoadFollowerGraphics' code, once found:
  array<uint8> code;

  bool find() {
    array<uint32> addrs = {0x00D423, 0x00D463};
    for (uint i = 0; i < addrs.length(); i++) {
      code.resize(follower_gfx_pattern.length());
      bool ok = true;
      for (uint k = 0; k < follower_gfx_pattern.length() && ok; k++) {
        code[k] = bus::read_u8(addrs[i] + k);
        if (follower_gfx_pattern[k] >= 0 && code[k] != uint8(follower_gfx_pattern[k])) ok = false;
      }
      if (ok) return true;
    }
    return false;
  }

  // sheet returns the sheet LoadFollowerGraphics decompresses to $7F4600 for a follower: one for Zelda, then by the
  // two thresholds.
  uint8 sheet(uint8 follower) {
    if (follower == code[10]) return code[4];
    if (follower < code[20]) return code[14];
    if (follower < code[26]) return code[24];
    return code[30];
  }

  bool build(array<uint8> &fact) {
    LinkFactBuilder lb;
    if (!lb.find()) {
      message("facts: sprite sheet routines not found in ROM; no follower graphics fact");
      return false;
    }
    if (!find()) {
      message("facts: LoadFollowerGraphics not found in ROM; no follower graphics fact");
      return false;
    }
    uint32 offsets = uint32(code[54]) | (uint32(code[55]) << 8) | (uint32(code[56]) << 16);
    fact.resize(follower_fact_size);
    for (uint f = 0; f < follower_count; f++) {
      // bank $7F, empty for each follower:
      array<uint8> bank7F(0x10000);
      if (!lb.decompress(sheet(uint8(f)), bank7F, 0x4600)) return false;
      if (!lb.decompress(code[35], bank7F, 0x4000)) return false;
      uint src = 0x4000 + bus::read_u16(offsets + f * 2);
      if (src + (follower_gfx_size >> 5) * 24 > bank7F.length()) return false;
      expand_3to4_low(bank7F, src, fact, f * follower_gfx_size, follower_gfx_size >> 5);
    }
    return true;
  }
}

// expand_3to4_low is the game's Do3bppToWRAM4bpp_LeftPal: num 3bpp tiles from src[off:] to 4bpp tiles at dst[x:], with
// the 4th bitplane clear.
void expand_3to4_low(const array<uint8> &in src, uint off, array<uint8> &dst, uint x, uint num) {
  for (; num > 0; num--) {
    uint p2 = off + 0x10;
    for (int row = 0; row < 8; row++) {
      dst[x] = src[off];
      dst[x + 1] = src[off + 1];
      dst[x + 0x10] = src[p2];
      dst[x + 0x11] = 0;
      off += 2;
      p2++;
      x += 2;
    }
    x += 0x10;
    off = p2;
  }
}

// follower_fact_tile returns the tile of fact 0x01 that a follower's chr $20 (dma = dma_var6) or $22 (dma = dma_var7)
// shows; no_fact_tile for no follower, a follower not in the fact, or a source that isn't 2 whole tiles of the top row.
uint16 follower_fact_tile(uint8 follower, uint8 dma) {
  if (follower == 0 || follower >= follower_count || (dma & 0x0F) != 0 || dma > 0xE0) return no_fact_tile;
  return uint16(follower * follower_fact_tiles + (dma >> 4));
}

// follower_chr_rows appends the rows of the follower's chrs ($20-$23, $30-$33) bound to tiles of fact 0x01 this
// frame, from the follower ($7EF3CC) and dma_var6 and dma_var7; none without a follower.
void follower_chr_rows(array<ChrRow@> &rows) {
  if (local_fact(fact_follower_graphics) is null) return;
  uint8 follower = bus::read_u8(0x7EF3CC);
  array<uint8> chr = {0x20, 0x30, 0x22, 0x32};
  array<uint16> dma = {0x0AE8, 0x0AE8, 0x0AEA, 0x0AEA};
  for (uint r = 0; r < chr.length(); r++) {
    uint16 t = follower_fact_tile(follower, bus::read_u8(0x7E0000 | dma[r]));
    if (t == no_fact_tile) continue;
    ChrRow row;
    row.chr = chr[r];
    row.n = 2;
    row.fact = fact_follower_graphics;
    row.tile = t + (((chr[r] & 0x10) != 0) ? uint16(follower_fact_bottom_row) : 0);
    rows.insertLast(row);
  }
}

// build_follower_fact builds fact 0x01 from the ROM, for ALTTP ROMs.
void build_follower_fact() {
  if (rom is null || !rom.is_alttp()) return;
  FollowerFactBuilder b;
  LocalFact lf;
  lf.num = fact_follower_graphics;
  if (!b.build(lf.data)) return;
  local_facts.insertLast(lf);
  message("facts: built the follower graphics fact, " + fmtInt(lf.data.length()) + " bytes");
}
