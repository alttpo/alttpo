PatchBuffer pb;

class CodeWriter {
  Writer @w = @NullWriter();

  void setWriter(Writer @w) {
    @this.w = @w;
  }

  void seek(uint p) {
    w.seek(p);
  }

  uint get_offset() property { return w.offset; }

  uint marked_offset = 0;
  void mark() {
    marked_offset = offset;
  }

  void rewind() {
    w.seek(marked_offset);
    marked_offset = 0;
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

  void rep(uint8 flags) {
    w.u8(0xC2); // REP #flags
    w.u8(flags);
  }

  void sep(uint8 flags) {
    w.u8(0xE2); // SEP #flags
    w.u8(flags);
  }

  // 16-bit accumulator (REP #$20) only:
  void lda_immed16(uint16 imm) {
    w.u8(0xA9); // LDA #imm
    w.u16(imm);
  }

  // 16-bit index registers (REP #$10) only:
  void ldx_immed16(uint16 imm) {
    w.u8(0xA2); // LDX #imm
    w.u16(imm);
  }

  // 16-bit index registers (REP #$10) only:
  void ldy_immed16(uint16 imm) {
    w.u8(0xA0); // LDY #imm
    w.u16(imm);
  }

  void sta_long(uint32 addr) {
    w.u8(0x8F); // STA $bbxxxx
    w.u24(addr);
  }

  // jsr_bank01 calls a routine in bank $01 that returns with RTS: push our return address for an RTL, then the
  // address of an RTL instruction in bank $01 (minus one) for the routine's RTS, then jump to the routine. 11 bytes.
  void jsr_bank01(uint32 routine, uint32 rtl) {
    // the return address is the instruction after the JML, 11 bytes from here:
    uint16 ret = uint16(0x7F00 + offset + 11);
    w.u8(0x4B); // PHK
    w.u8(0xF4); // PEA ret-1
    w.u16(ret - 1);
    w.u8(0xF4); // PEA rtl-1
    w.u16(uint16(rtl - 1));
    w.u8(0x5C); // JML routine
    w.u24(routine);
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

    // map 7f00-7fff in bank bf to our code array:
    bus::map("ff:7f00-7fff", 0, 0x00ff, 0, code);

    // patch ROM to JSL to our code:
    // JSL 0xFF7F00
    auto @bw = @BusWriter(rom.fn_patch);
    setWriter(@bw);
    jsl(0xFF7F00);
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
