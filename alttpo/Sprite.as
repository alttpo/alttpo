
class Sprite {
  // OAM index:
  uint8 index;
  // actual data stored in bit-compressed format:
  uint8 b0, b1, b2, b3, b4;

  // computed properties:
  uint16 chr;
  int32 x;
  int32 y;
  uint8 palette;
  uint8 priority;
  bool hflip;
  bool vflip;
  uint8 size;
  bool is_enabled;

  // fetches all the OAM sprite data for OAM sprite at `index`
  //void fetchOAM(uint8 i) {
  //  auto @tile = ppu::oam[i];
  //
  //  index = i;
  //
  //  auto x = tile.x;
  //  auto chr = tile.character;
  //  b0 = x & 0xff;
  //  b1 = tile.y;
  //  b2 = chr & 0xff;
  //  b3 = ((chr >> 8) & 1) |
  //        (tile.palette << 1) |
  //        (tile.priority << 4) |
  //        (tile.hflip ? 1<<6 : 0) |
  //        (tile.vflip ? 1<<7 : 0);
  //  b4 = ((x >> 8) & 1) |
  //        (tile.size << 1);
  //}

  // b0-b3 are main 4 bytes of OAM table
  // b4 is the 5th byte of extended OAM table
  // b4 must be right-shifted to be the two least significant bits and all other bits cleared.
  void decodeOAMTableBytes() {
    // decode the bytes into actual fields:
    if (b1 == 0xF0) {
      is_enabled = false;
      return;
    }

    x = int32(uint16(b0) | (uint16(b4 & 1) << 8));
    if (x >= 256) x -= 512;

    size = (b4 >> 1) & 1;
    int px = size == 0 ? 8 : 16;

    is_enabled = (x > -px && x < 256);
    if (!is_enabled) {
      return;
    }

    y = int32(b1);
    chr = uint16(b2) | (uint16(b3 & 1) << 8);

    palette = (b3 >> 1) & 7;
    priority = (b3 >> 4) & 3;
    hflip = ((b3 >> 6) & 1) != 0 ? true : false;
    vflip = ((b3 >> 7) & 1) != 0 ? true : false;
  }

  void decodeOAMTable(uint16 i) {
    b0 = bus::read_u8(0x7E0800 + (i << 2));
    b1 = bus::read_u8(0x7E0801 + (i << 2));
    b2 = bus::read_u8(0x7E0802 + (i << 2));
    b3 = bus::read_u8(0x7E0803 + (i << 2));
    b4 = bus::read_u8(0x7E0A00 + (i >> 2));
    b4 = (b4 >> ((i&3)<<1)) & 3;
    index = i;
    decodeOAMTableBytes();
  }

  // assumes tbl is 0x220 bytes, read from 0x7E0800
  void decodeOAMArray(const array<uint8> &in tbl, uint16 i) {
    auto addr = i << 2;
    b0 = tbl[0x000 + addr];
    b1 = tbl[0x001 + addr];
    b2 = tbl[0x002 + addr];
    b3 = tbl[0x003 + addr];
    b4 = tbl[0x200 + (i >> 2)];
    b4 = (b4 >> ((i&3)<<1)) & 3;
    index = i;
    decodeOAMTableBytes();
  }
};
