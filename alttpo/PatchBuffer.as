PatchBuffer pb;

// TODO: CodeWriter class that writes to bus::write_u8 or to array<uint8> via dynamic `write` function

class PatchBuffer {
  array<uint8> code(0x100);
  uint p = 0;

  PatchBuffer() {
    // NOP out the code:
    for (uint i = 0; i < 0x100; i++) {
      code[i] = 0xEA; // NOP
    }
  }

  bool powered = false;
  void power(bool force = false) {
    if (force) powered = false;
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
    jsl(rom.fn_main_routing);
    // RTL
    rtl();
    seek(0);
  }

  void seek(uint k) {
    p = k;
  }

  void jsl(uint32 addr) {
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
