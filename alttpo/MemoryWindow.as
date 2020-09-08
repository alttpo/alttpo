MemoryWindow @memoryWindow;

class MemoryWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  private GUI::LineEdit @txtAddr;

  uint32 addr;
  array<uint8> page(0x100);

  array<GUI::Label@> lblAddr(0x10);
  array<GUI::Label@> lblData(0x10);

  GUI::Color gridColor = GUI::Color( 80,  80,  80);
  GUI::Color addrColor = GUI::Color(220, 220,   0);
  GUI::Color dataColor = GUI::Color(180, 180, 180);

  MemoryWindow() {
    addr = 0x7E0000;

    // relative position to bsnes window:
    @window = GUI::Window(128, 128, true);
    window.title = "Memory";
    window.font = GUI::Font("{mono}", 8);
    window.size = GUI::Size((16*3 + 6 + 4) * 8, (16 + 2) * 16);
    window.backgroundColor = GUI::Color( 20,  20,  20);

    @vl = GUI::VerticalLayout();
    window.append(vl);

    @txtAddr = GUI::LineEdit();
    txtAddr.text = fmtHex(addr, 6);
    txtAddr.onChange(@GUI::Callback(txtAddrChanged));
    vl.append(txtAddr, GUI::Size(-1, 0));

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 0);

      auto @lbl = GUI::Label();
      lbl.text = "address";
      lbl.foregroundColor = addrColor;
      hz.append(lbl, GUI::Size(0, 0), 0);

      @lbl = GUI::Label();
      lbl.text = " | ";
      lbl.foregroundColor = gridColor;
      hz.append(lbl, GUI::Size(0, 0), 0);

      @lbl = GUI::Label();
      lbl.text = "00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F";
      lbl.foregroundColor = addrColor;
      hz.append(lbl, GUI::Size(-1, 0), 0);

      @lbl = GUI::Label();
      lbl.text = "--------+------------------------------------------------";
      lbl.foregroundColor = gridColor;
      vl.append(lbl, GUI::Size(0, 0), 0);
    }

    for (uint i = 0; i < 16; i++) {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 0);

      @lblAddr[i] = GUI::Label();
      lblAddr[i].text = "$" + fmtHex(addr + (i << 4), 6);
      lblAddr[i].foregroundColor = addrColor;
      hz.append(lblAddr[i], GUI::Size(0, 0), 0);

      auto @lbl = GUI::Label();
      lbl.text = " | ";
      lbl.foregroundColor = gridColor;
      hz.append(lbl, GUI::Size(0, 0), 0);

      @lblData[i] = GUI::Label();
      lblData[i].text = "";
      lblData[i].foregroundColor = dataColor;
      hz.append(lblData[i], GUI::Size(-1, 0), 0);
    }

    vl.resize();
    window.visible = true;
  }

  void txtAddrChanged() {
    // mask off last 4 bits to align base address to 16 bytes:
    addr = txtAddr.text.hex() & 0xFFFFF0;
  }

  void update() {
    // read data:
    bus::read_block_u8(addr & 0xFFFFF0, 0, 0x100, page);

    // update display:
    for (uint i = 0; i < 16; i++) {
      string_format fa = {
        fmtHex(page[(i << 4) + 0x0], 2),
        fmtHex(page[(i << 4) + 0x1], 2),
        fmtHex(page[(i << 4) + 0x2], 2),
        fmtHex(page[(i << 4) + 0x3], 2),
        fmtHex(page[(i << 4) + 0x4], 2),
        fmtHex(page[(i << 4) + 0x5], 2),
        fmtHex(page[(i << 4) + 0x6], 2),
        fmtHex(page[(i << 4) + 0x7], 2),
        fmtHex(page[(i << 4) + 0x8], 2),
        fmtHex(page[(i << 4) + 0x9], 2),
        fmtHex(page[(i << 4) + 0xA], 2),
        fmtHex(page[(i << 4) + 0xB], 2),
        fmtHex(page[(i << 4) + 0xC], 2),
        fmtHex(page[(i << 4) + 0xD], 2),
        fmtHex(page[(i << 4) + 0xE], 2),
        fmtHex(page[(i << 4) + 0xF], 2)
      };
      lblData[i].text = "{0} {1} {2} {3} {4} {5} {6} {7} {8} {9} {10} {11} {12} {13} {14} {15}".format(fa);
      lblAddr[i].text = "$" + fmtHex(addr + (i << 4), 6);
    }
  }
};
