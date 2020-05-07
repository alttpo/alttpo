PatchBuffer pb;

class CodeWriter {
  Writer @w = @NullWriter();

  void setWriter(Writer @w) {
    @this.w = @w;
  }

  void seek(uint p) {
    w.seek(p);
  }

  void jsl(uint32 addr) {
    w.u8(0x22); // JSL
    w.u24(addr);
  }

  void rtl() {
    w.u8(0x6B); // RTL
  }

  void lda_immed(uint8 imm) {
    w.u8(0xA9);
    w.u8(imm);
  }

  void sta_bank(uint16 bank) {
    w.u8(0x8D); // STA $xxxx
    w.u16(bank);
  }
}

class PatchBuffer : CodeWriter {
  array<uint8> @code = @array<uint8>(0x100);
  ArrayWriter @aw = ArrayWriter(@code);

  PatchBuffer() {
    setWriter(@aw);

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
    bus::map("ff:8000-80ff", 0, 0x00ff, 0, code);

    // patch ROM to JSL to our code:
    // JSL 0xBF8000
    auto @bw = @BusWriter(rom.fn_patch);
    setWriter(@bw);
    jsl(0xFF8000);
    setWriter(@aw);

    //message(fmtHex(bus::read_u8(rom.fn_patch+1), 2));
    //message(fmtHex(bus::read_u8(rom.fn_patch+2), 2));
    //message(fmtHex(bus::read_u8(rom.fn_patch+3), 2));

    @bw = null;
  }

  void unload() {
    // restore JSL MainRouting to its original value:
    auto @bw = @BusWriter(rom.fn_patch);
    setWriter(@bw);
    jsl(rom.fn_main_routing);
    setWriter(@aw);
  }

  void restore() {
    seek(0);
    // JSL MainRouting
    jsl(rom.fn_main_routing);
    // RTL
    rtl();
    seek(0);
  }
};
