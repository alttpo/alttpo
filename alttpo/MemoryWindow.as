MemoryWindow @memoryWindow;

class MemoryWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  private GUI::LineEdit @txtAddr;
  private GUI::Button @btnCapture;

  uint32 addr;
  uint32 addrCapture;
  array<uint8> page(0x100);
  array<uint8> base(0x100);

  array<GUI::Label@> lblAddr(0x10);
  array<GUI::Label@> lblData(0x100);

  GUI::Color gridColor = GUI::Color( 80,  80,  80);
  GUI::Color addrColor = GUI::Color(220, 220,   0);
  GUI::Color dataColor = GUI::Color(160, 160, 160);
  GUI::Color diffColor = GUI::Color(255,  20,  20);

  MemoryWindow() {
    addr = 0x7E0000;

    auto fontWidth = 7.225; // looks nice on my mac with 8pt font

    // relative position to bsnes window:
    @window = GUI::Window(256, 16, true);
    window.title = "Memory";
    window.font = GUI::Font("{mono}", 8);
    window.size = GUI::Size((16*3 + 6 + 2) * 8, (16 + 2) * 16);
    window.backgroundColor = GUI::Color( 20,  20,  20);

    @vl = GUI::VerticalLayout();
    window.append(vl);

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 5);

      auto @lbl = GUI::Label();
      lbl.text = "address: ";
      //lbl.foregroundColor = addrColor;
      hz.append(lbl, GUI::Size(0, 0), 5);

      @txtAddr = GUI::LineEdit();
      txtAddr.text = fmtHex(addr, 6);
      txtAddr.onChange(@GUI::Callback(txtAddrChanged));
      hz.append(txtAddr, GUI::Size(-1, 0), 5);

      @btnCapture = GUI::Button();
      btnCapture.text = "Capture";
      btnCapture.onActivate(@GUI::Callback(btnCaptureClicked));
      hz.append(btnCapture, GUI::Size(0, 0), 5);
    }

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 0);

      auto @lbl = GUI::Label();
      lbl.text = "       ";
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

      for (uint x = 0; x < 16; x++) {
        auto j = (i << 4) + x;
        @lblData[j] = GUI::Label();
        lblData[j].text = "00 ";
        lblData[j].foregroundColor = dataColor;
        hz.append(lblData[j], GUI::Size(fontWidth*3, 0), 0);
      }
    }

    vl.resize();
    btnCaptureClicked();
    window.visible = true;
  }

  void btnCaptureClicked() {
    // capture current page:
    addrCapture = addr & 0xFFFFF0;
    bus::read_block_u8(addrCapture, 0, 0x100, base);

    update();
  }

  void txtAddrChanged() {
    // mask off last 4 bits to align base address to 16 bytes:
    addr = txtAddr.text.hex() & 0xFFFFF0;

    update();
  }

  void update() {
    // read data:
    bus::read_block_u8(addr & 0xFFFFF0, 0, 0x100, page);

    // update display:
    for (uint i = 0; i < 16; i++) {
      auto row = i << 4;
      lblAddr[i].text = "$" + fmtHex(addr + row, 6);

      auto absAddr = (addr + row);
      if ((absAddr >= addrCapture) && (absAddr < addrCapture + 0x100)) {
        // compare current to snapshot:
        int32 offs = addr - addrCapture;
        for (uint x = 0; x < 16; x++) {
          auto j = row + x;
          lblData[j].text = fmtHex(page[j], 2);
          if (page[j] != base[j+offs]) {
            lblData[j].foregroundColor = diffColor;
          } else {
            lblData[j].foregroundColor = dataColor;
          }
        }
      } else {
        for (uint x = 0; x < 16; x++) {
          auto j = row + x;
          lblData[j].text = fmtHex(page[j], 2);
          lblData[j].foregroundColor = dataColor;
        }
      }
    }
  }
};
