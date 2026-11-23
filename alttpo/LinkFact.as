// Link graphics fact (fact 0x00; see o2-server's PROTOCOL05.md, "Sprites with facts"), built the same way as o2's
// games/alttp/linkfact.go, from the ROM over the bus:
//
//   offset  size   contents
//   $0000   $7000  bank $10 LinkGraphics
//   $7000   $0C00  swords 1-4, $300 each, laid out as WRAM $7E9000 for that level
//   $7C00   $0480  shields 1-3, $180 each, laid out as WRAM $7E9300 for that level
//   $8080   $0D00  the item buffer, as WRAM $7E9480-$7EA17F
//
// The flute's bird (chrs $0E-$0F, $1E-$1F, from WRAM $7EB540) isn't in it: the bird isn't synced.
const uint8 fact_link_graphics = 0x00;

const uint lf_body = 0x0000;
const uint lf_body_size = 0x7000;
const uint lf_swords = 0x7000;
const uint lf_sword_size = 0x300;
const uint lf_shields = 0x7C00;
const uint lf_shield_size = 0x180;
const uint lf_items = 0x8080;
const uint lf_items_size = 0xD00;
const uint link_fact_size = lf_items + lf_items_size;

const uint lf_sword_wram = 0x9000;
const uint lf_shield_wram = 0x9300;
const uint lf_items_wram = 0x9480;

const uint16 no_fact_tile = 0xFFFF;

// LoadItemGFXIntoWRAM4BPPBuffer's item animations: sheet (0 = sprite sheet 0, uncompressed in ROM), first 3bpp tile,
// number of 16 pixel wide columns:
const array<uint8> lf_item_sheet = {0x00, 0x00, 0x00, 0x5F, 0x5F, 0x5F, 0x00, 0x60, 0x60, 0x5F};
const array<int> lf_item_tile = {0, 11, 8, 38, 42, 45, 34, 3, 33, 46};
const array<int> lf_item_num = {7, 7, 3, 4, 3, 1, 4, 14, 7, 2};

class LinkFactBuilder {
  uint32 sheetBank, sheetHigh, sheetLow;
  uint32 swordOffsets, shieldOffsets;
  // the ROM address the decompressor reads next:
  uint32 src;

  // operand returns the 16-bit operand of the instruction at addr if its opcode is op, else 0.
  uint32 operand(uint32 addr, uint8 op) {
    if (bus::read_u8(addr) != op) return 0;
    return bus::read_u16(addr + 1);
  }

  // find locates the sprite sheet pointer tables and the sword and shield offset tables by the instructions that use
  // them: `LDA.w GFXSheetPointers_sprite_bank,Y` in Decompress_sprite_arbitrary and `ADC.w .offset,Y` in
  // DecompressSwordGraphics and DecompressShieldGraphics (US 1.0, then JP 1.0 addresses).
  bool find() {
    array<uint32> sheets = {0x00E772, 0x00E7B2};
    array<uint32> swords = {0x00D2E2, 0x00D322};
    array<uint32> shields = {0x00D31F, 0x00D35F};
    for (uint i = 0; i < sheets.length(); i++) {
      sheetBank = operand(sheets[i], 0xB9);
      sheetHigh = operand(sheets[i] + 5, 0xB9);
      sheetLow = operand(sheets[i] + 10, 0xB9);
      swordOffsets = operand(swords[i], 0x79);
      shieldOffsets = operand(shields[i], 0x79);
      if (sheetBank != 0 && sheetHigh != 0 && sheetLow != 0 && swordOffsets != 0 && shieldOffsets != 0) return true;
    }
    return false;
  }

  uint32 sheet_ptr(uint8 sheet) {
    return (uint32(bus::read_u8(sheetBank + sheet)) << 16) | (uint32(bus::read_u8(sheetHigh + sheet)) << 8) |
      uint32(bus::read_u8(sheetLow + sheet));
  }

  // next reads the byte at src and advances it, wrapping to the next LoROM bank (Decompression_GetNextByte).
  uint8 next() {
    uint8 v = bus::read_u8(src);
    if ((src & 0xFFFF) == 0xFFFF) {
      src = ((src & 0xFF0000) + 0x010000) | 0x8000;
    } else {
      src++;
    }
    return v;
  }

  // decompress implements the game's Decompress routine for a sprite graphics sheet, writing to buf[base:].
  bool decompress(uint8 sheet, array<uint8> &buf, uint base) {
    src = sheet_ptr(sheet);
    uint y = 0;
    for (int steps = 0; steps < 0x10000; steps++) {
      uint8 cmd = next();
      if (cmd == 0xFF) return true;
      uint8 kind;
      int length;
      if ((cmd & 0xE0) == 0xE0) {
        // expanded: 3 bit command and 10 bit length:
        kind = (cmd << 3) & 0xE0;
        length = ((int(cmd & 0x03) << 8) | int(next())) + 1;
      } else {
        kind = cmd & 0xE0;
        length = int(cmd & 0x1F) + 1;
      }
      if (base + y + uint(length) > buf.length()) return false;
      if (kind == 0x00) {
        for (int i = 0; i < length; i++) buf[base + y++] = next();
      } else if ((kind & 0x80) != 0) {
        uint x = next();
        x |= uint(next()) << 8;
        for (int i = 0; i < length; i++) {
          buf[base + y++] = buf[base + (x & 0xFFFF)];
          x++;
        }
      } else if (kind == 0x20) {
        uint8 v = next();
        for (int i = 0; i < length; i++) buf[base + y++] = v;
      } else if (kind == 0x40) {
        uint8 v0 = next();
        uint8 v1 = next();
        for (int i = 0; i < length; i++) buf[base + y++] = (i & 1) == 0 ? v0 : v1;
      } else if (kind == 0x60) {
        uint8 v = next();
        for (int i = 0; i < length; i++) buf[base + y++] = v++;
      }
    }
    return false;
  }

  // sprite_sheet returns a sprite graphics sheet: sheet 0 read as it is from ROM (stored uncompressed), others
  // decompressed.
  bool sprite_sheet(uint8 sheet, array<uint8> &buf) {
    buf.resize(0x10000);
    if (sheet != 0) return decompress(sheet, buf, 0);
    src = sheet_ptr(0);
    // the item animations read up to 2 rows of 16 tiles past the end of the sheet's first $600 bytes:
    for (uint i = 0; i < 0x900; i++) buf[i] = next();
    return true;
  }

  bool build(array<uint8> &fact) {
    if (!find()) {
      message("facts: sprite sheet routines not found in ROM; no Link graphics fact");
      return false;
    }
    fact.resize(link_fact_size);

    // LinkGraphics: the bank NMI_DoUpdates loads, `LDA.b #imm` or, in randomizers, `LDA.b dp`:
    uint8 op = bus::read_u8(0x008A01);
    uint8 bank = 0x10;
    if (op == 0xA9) {
      bank = bus::read_u8(0x008A02);
    } else if (op == 0xA5) {
      bank = bus::read_u8(0x7E0000 | bus::read_u8(0x008A02));
    }
    bus::read_block_u8((uint32(bank) << 16) | 0x8000, lf_body, lf_body_size, fact);

    // swords and shields: as DecompressSwordGraphics and DecompressShieldGraphics, from sheets $5E and $5F, which the
    // game decompresses to $7F4000 and $7F4600:
    array<uint8> bank7F(0x10000);
    if (!decompress(0x5F, bank7F, 0x4600)) return false;
    if (!decompress(0x5E, bank7F, 0x4000)) return false;
    for (uint level = 1; level <= 4; level++) {
      uint offset = bus::read_u16(swordOffsets + level * 2);
      uint x = lf_swords + (level - 1) * lf_sword_size;
      x = expand_3to4_high(bank7F, 0x4000 + offset, fact, x, 12);
      expand_3to4_high(bank7F, 0x4000 + offset + 0x180, fact, x, 12);
    }
    for (uint level = 1; level <= 3; level++) {
      uint offset = bus::read_u16(shieldOffsets + level * 2);
      uint x = lf_shields + (level - 1) * lf_shield_size;
      x = expand_3to4_high(bank7F, 0x4000 + offset, fact, x, 6);
      expand_3to4_high(bank7F, 0x4000 + offset + 0x180, fact, x, 6);
    }

    // the item buffer, as LoadItemGFXIntoWRAM4BPPBuffer (LoadItemAnimationGfxOne):
    array<uint8> sheet0, sheetA, sheetB;
    if (!sprite_sheet(0x00, sheet0) || !sprite_sheet(0x5F, sheetA) || !sprite_sheet(0x60, sheetB)) return false;
    uint x = lf_items;
    for (uint i = 0; i < lf_item_sheet.length(); i++) {
      uint off = uint(lf_item_tile[i]) * 24;
      int num = lf_item_num[i];
      if (lf_item_sheet[i] == 0x00) {
        x = expand_3to4_high(sheet0, off, fact, x, num);
        x = expand_3to4_high(sheet0, off + 0x180, fact, x, num);
      } else if (lf_item_sheet[i] == 0x5F) {
        x = expand_3to4_high(sheetA, off, fact, x, num);
        x = expand_3to4_high(sheetA, off + 0x180, fact, x, num);
      } else {
        x = expand_3to4_high(sheetB, off, fact, x, num);
        x = expand_3to4_high(sheetB, off + 0x180, fact, x, num);
      }
    }
    if (x != lf_items + lf_items_size) {
      message("facts: item buffer is " + fmtHex(x - lf_items, 4) + " bytes; expected " + fmtHex(lf_items_size, 4));
      return false;
    }
    return true;
  }
}

// expand_3to4_high is the game's Expand3To4High (Do3bppToWRAM4bpp_RightPal): num 3bpp tiles from src[off:] to 4bpp
// tiles at dst[x:], with the 4th bitplane set wherever a pixel is opaque. Rows of 16 tiles in src are $180 bytes apart.
// Returns x after the tiles.
uint expand_3to4_high(const array<uint8> &in src, uint off, array<uint8> &dst, uint x, int num) {
  for (; num > 0; num--) {
    uint p2 = off + 0x10;
    for (int row = 0; row < 8; row++) {
      uint8 lo = src[off];
      uint8 hi = src[off + 1];
      uint8 b2 = src[p2];
      dst[x] = lo;
      dst[x + 1] = hi;
      dst[x + 0x10] = b2;
      dst[x + 0x11] = lo | hi | b2;
      off += 2;
      p2++;
      x += 2;
    }
    x += 0x10;
    off = p2;
    if ((off & 0x78) == 0) off += 0x180;
  }
  return x;
}

// link_fact_tile returns the tile of fact 0x00 that the DMA source address src (bank $10 for the head, body and aux,
// else WRAM bank $7E) shows, with the sword and shield levels the player has; no_fact_tile if none.
uint16 link_fact_tile(uint16 src, bool wram, uint8 sword, uint8 shield) {
  uint a = src;
  if (!wram) {
    if (a < 0x8000 || a - 0x8000 >= lf_body_size) return no_fact_tile;
    return uint16((lf_body + a - 0x8000) >> 5);
  }
  if (a >= lf_sword_wram && a < lf_sword_wram + lf_sword_size) {
    if (sword < 1 || sword > 4) return no_fact_tile;
    return uint16((lf_swords + (sword - 1) * lf_sword_size + a - lf_sword_wram) >> 5);
  }
  if (a >= lf_shield_wram && a < lf_shield_wram + lf_shield_size) {
    if (shield < 1 || shield > 3) return no_fact_tile;
    return uint16((lf_shields + (shield - 1) * lf_shield_size + a - lf_shield_wram) >> 5);
  }
  if (a >= lf_items_wram && a < lf_items_wram + lf_items_size) return uint16((lf_items + a - lf_items_wram) >> 5);
  return no_fact_tile;
}

// build_link_fact builds fact 0x00 from the ROM, for ALTTP ROMs.
void build_link_fact() {
  if (rom is null || !rom.is_alttp()) return;
  LinkFactBuilder b;
  LocalFact lf;
  lf.num = fact_link_graphics;
  if (!b.build(lf.data)) return;
  local_facts.insertLast(lf);
  message("facts: built the Link graphics fact, " + fmtInt(lf.data.length()) + " bytes");
}
