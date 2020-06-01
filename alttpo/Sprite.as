
class Sprite {
  // OAM index:
  uint8 index;
  // actual data stored in bit-compressed format:
  uint8 b0, b1, b2, b3, b4;

  uint16 get_chr() property {
    return uint16(b2) | (uint16(b3 & 1) << 8);
  }

  int16 get_x() property {
    return int16((uint16(b0) & 0xFF) | (uint16(b4 & 1) << 8));
  }
  void set_x(int16 value) property {
    b0 = uint8(uint16(value) & 0xFF);
    b4 = uint8((b4 & ~1) | ((uint16(value) >> 8) & 1));
  }

  int16 get_y() property {
    return b1;
  }
  void set_y(int16 value) property {
    b1 = value;
  }

  uint8 get_palette() property  { return (b3 >> 1) & 7; }
  uint8 get_priority() property { return (b3 >> 4) & 3; }
  bool get_hflip() property     { return ((b3 >> 6) & 1) != 0 ? true : false; }
  bool get_vflip() property     { return ((b3 >> 7) & 1) != 0 ? true : false; }

  uint8 get_size() property     { return (b4 >> 1) & 1; }

  bool get_is_enabled() property { return (b1 != 0xF0); }

  // fetches all the OAM sprite data for OAM sprite at `index`
  void fetchOAM(uint8 i) {
    auto tile = ppu::oam[i];

    index = i;

    b0 = tile.x & 0xff;
    b1 = tile.y;
    b2 = tile.character & 0xff;
    b3 = ((tile.character >> 8) & 1) |
          (tile.palette << 1) |
          (tile.priority << 4) |
          (tile.hflip ? 1<<6 : 0) |
          (tile.vflip ? 1<<7 : 0);
    b4 = ((tile.x >> 8) & 1) |
          (tile.size << 1);
  }

  // b0-b3 are main 4 bytes of OAM table
  // b4 is the 5th byte of extended OAM table
  // b4 must be right-shifted to be the two least significant bits and all other bits cleared.
  void decodeOAMTableBytes(uint16 i, uint8 b0, uint8 b1, uint8 b2, uint8 b3, uint8 b4) {
    index    = i;
    this.b0 = b0;
    this.b1 = b1;
    this.b2 = b2;
    this.b3 = b3;
    this.b4 = b4;
  }

  void decodeOAMTable(uint16 i) {
    uint8 b0, b1, b2, b3, b4;
    b0 = bus::read_u8(0x7E0800 + (i << 2));
    b1 = bus::read_u8(0x7E0801 + (i << 2));
    b2 = bus::read_u8(0x7E0802 + (i << 2));
    b3 = bus::read_u8(0x7E0803 + (i << 2));
    b4 = bus::read_u8(0x7E0A00 + (i >> 2));
    b4 = (b4 >> ((i&3)<<1)) & 3;
    decodeOAMTableBytes(i, b0, b1, b2, b3, b4);
  }

  void serialize(array<uint8> &r) {
    r.write_u8(index);
    r.write_u8(b0);
    r.write_u8(b1);
    r.write_u8(b2);
    r.write_u8(b3);
    r.write_u8(b4);
  }

  int deserialize(array<uint8> &r, int c) {
    index = r[c++];
    b0 = r[c++];
    b1 = r[c++];
    b2 = r[c++];
    b3 = r[c++];
    b4 = r[c++];
    return c;
  }
};
