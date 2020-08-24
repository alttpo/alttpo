
// Represents an ALTTP object from 0x10-sized tables at $7E0D00-0FA0:
class GameSprite {
  array<uint8> facts(0x2A);
  uint8 index;

  void readFromBlock(const array<uint8> &in block, uint8 index) {
    this.index = index;

    // copy object facts from the striped contiguous block of RAM:
    uint j = this.index;
    facts.resize(0x2A);
    for (uint i = 0; i < 0x2A; i++, j += 0x10) {
      facts[i] = block[j];
    }
  }

  void readRAM(uint8 index) {
    this.index = index;

    // copy object facts from the striped contiguous block of RAM:
    uint j = this.index;
    facts.resize(0x2A);
    for (uint i = 0; i < 0x2A; i++, j += 0x10) {
      facts[i] = bus::read_u8(0x7E0D00 + j);
    }
  }

  void writeRAM() {
    uint j = this.index;
    for (uint i = 0; i < 0x2A; i++, j += 0x10) {
      bus::write_u8(0x7E0D00 + j, facts[i]);
    }
  }

  uint16 y         { get { return uint16(facts[0x00]) | uint16(facts[0x02] << 8); } };
  uint16 x         { get { return uint16(facts[0x01]) | uint16(facts[0x03] << 8); } };
  uint8  ai        { get { return facts[0x08]; } };         // 0x00 = not spawned, else spawned - used as AI pointer
  uint8  state     {
    get { return facts[0x0D]; }         // valid [0x00..0x0B]; 0x00 = dead/inactive, 0x02 = xform to puff of smoke, 0x0A = carried by Link
    set { facts[0x0D] = value; }
  };
  uint8  type      { get { return facts[0x12]; } };         // valid [0x00..0xF2]; will want to filter for enemies only
  uint8  subtype   { get { return facts[0x13] & 0x1F; } };  // valid [0x00..0x1F]; based on X/Y coordinates
  uint8  oam_count { get { return facts[0x14] & 0x0F; } };  // valid [0x00..0x0F]; count of OAM slots used; 0 means invisible
  uint8  hp        { get { return facts[0x15]; } };
  uint8  hitbox    { get { return facts[0x26] & 0x1F; } };

  bool is_enabled  { get { return state != 0; } };
};
