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

  // 8-bit index registers only:
  void ldy_immed(uint8 imm) {
    w.u8(0xA0); // LDY #imm
    w.u8(imm);
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

  void pha() { w.u8(0x48); }
  void pla() { w.u8(0x68); }
  void txa() { w.u8(0x8A); }

  void lda_bank(uint16 addr) {
    w.u8(0xAD); // LDA $xxxx
    w.u16(addr);
  }

  void sta_dp(uint8 addr) {
    w.u8(0x85); // STA $xx
    w.u8(addr);
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

  // jsr_banked calls a routine in any bank that returns with RTS through an RTL in the same bank, like jsr_bank01:
  void jsr_banked(uint32 routine, uint32 rtl) {
    jsr_bank01(routine, rtl);
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

  // offset of the first byte after the frame guard, where the frame's code starts; see restore():
  uint code_start = 0;

  // empty is true while no code was written for this frame:
  bool get_empty() property { return offset <= code_start; }

  // restore starts this frame's code. The buffer runs at the main loop's JSL MainRouting, and on_main_alttp rewrites it
  // just before that every frame. If the buffer were not rewritten for a frame (the PC interceptor was not called, or a
  // save state was loaded), the previous frame's code would run again in a frame it was not written for: e.g. map16
  // changes queue VRAM stripes ($14 = 1), and in the first frame of the item menu, which fills the stripe buffer at
  // $1000 with its tilemap, the NMI would take that tilemap for stripes and fill most of VRAM (BG2 and BG3) with
  // garbage. So the code starts with a guard that only runs MainRouting unless $1A, which the main loop increments
  // right before, is the frame it was written for. The rest of the buffer is NOPs up to a final JSL MainRouting; RTL so
  // that code cut short by a script exception still returns.
  void restore() {
    for (uint i = 0; i < 0x100; i++) {
      code[i] = 0xEA; // NOP
    }
    seek(0x100 - 5);
    jsl(rom.fn_main_routing);
    rtl();

    seek(0);
    sep(0x30);
    w.u8(0xA5); // LDA $1A
    w.u8(0x1A);
    w.u8(0xC9); // CMP #frame
    w.u8(bus::read_u8(0x7E001A));
    w.u8(0xF0); // BEQ +5
    w.u8(0x05);
    jsl(rom.fn_main_routing);
    rtl();
    code_start = offset;

    // nothing else to do yet:
    jsl(rom.fn_main_routing);
    rtl();
    seek(code_start);
  }

};
