
void post_power(bool reset) {
  pb.power();
}

class PatchBuffer {
  array<uint8> code(0x100);
  uint p = 0;

  // ALTTP ROM US region
  uint32 mainRouting = 0x0080B5;

  PatchBuffer() {
    // NOP out the code:
    for (uint i = 0; i < 0x100; i++) {
      code[i] = 0xEA; // NOP
    }
  }

  bool powered = false;
  void power() {
    if (powered) return;
    powered = true;

    restore();

    // map 8000-8fff in bank bf to our code array:
    bus::map("bf:8000-80ff", 0, 0x00ff, 0, code);

    // patch ROM to JSL to our code:
    // JSL 0xBF8000
    bus::write_u8(0x008056, 0x22);  // JSL
    bus::write_u8(0x008057, 0x00);  //     L
    bus::write_u8(0x008058, 0x80);  //     H
    bus::write_u8(0x008059, 0xBF);  //     B
  }

  void restore() {
    seek(0);
    // JSL MainRouting
    jsl(mainRouting);
    // RTL
    rtl();
    seek(0);
  }

  void seek(uint k) {
    p = k;
  }

  void jsl(uint32 addr) {
    // JSL Module_MainRouting
    code[p++] = 0x22; // JSL
    code[p++] = (addr & 0x0000ff);        //     L
    code[p++] = (addr & 0x00ff00) >> 8;   //     H
    code[p++] = (addr & 0xff0000) >> 16;  //     B
  }

  void rtl() {
    code[p++] = 0x6B; // RTL
  }

  void lda_immed(uint8 imm) {
    code[p++] = 0xA9;
    code[p++] = imm;
  }

  void sta_bank(uint16 bank) {
    // STA $xxxx
    code[p++] = 0x8D;
    code[p++] = (bank & 0x00ff);
    code[p++] = (bank & 0xff00) >> 8;
  }
};
PatchBuffer pb;

uint16 count = 0x40;
uint8  torch = 0;

void post_frame() {
  pb.power();

  // set up default `JSL MainRouting`:
  pb.restore();

  // Wait until we're into the main game:
  auto module = bus::read_u8(0x7E0010);
  if (module != 7) return;
  auto sub_module = bus::read_u8(0x7E0011);
  if (sub_module != 0) return;

  // Only execute every 128 frames:
  if (--count != 0) return;
  count = 0x180;

  // in a dark room?
  auto darkRoom = bus::read_u16(0x7E0458);
  if (darkRoom != 1) return;

  // Move to next torch:
  auto torchIndex = bus::read_u16(0x7E042E);

  //if (torch >= 3) torch = 0;
  uint8 t = torch++;
  if (torch >= 0x10) torch = 0;

  // Cannot light torch if already lit; this would hard-lock the game:
  auto idx = (uint16(t) << 1) + bus::read_u16(0x7E0478);
  auto tm = bus::read_u16(0x7E0540+idx);
  // already lit?
  if ((tm & 0x8000) == 0x8000) return;

  // Set $0333 in WRAM to the tile number of a torch (C0-CF) to light:
  pb.lda_immed(0xC0 + t); // LDA #$C0 + t
  pb.sta_bank(0x0333);    // STA $0333

  // MUST ONLY BE CALLED ONCE WHEN TORCH IS OFF!
  pb.jsl(0x01F3EC);       // JSL Dungeon_LightTorch

  pb.jsl(pb.mainRouting); // JSL MainRouting
  pb.rtl();               // RTL
}
