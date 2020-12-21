MemoryWindow @memoryWindow;

const uint memRows = 0x20;
const uint memWindowBytes = 0x10 * memRows;

class MemoryWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  private GUI::LineEdit @txtAddr;
  private GUI::Button @btnCapture;
  private GUI::LineEdit @txtWAddr;
  private GUI::LineEdit @txtWValue;
  private GUI::Button @btnWrite;

  uint32 addr;
  uint32 addrCapture;
  array<uint8> page(memWindowBytes);
  array<uint8> base(memWindowBytes);

  array<GUI::Label@> lblAddrRow(memRows);
  array<GUI::Label@> lblAddrCol(0x10);
  array<GUI::Label@> lblData(memWindowBytes);

  GUI::Color gridColor = GUI::Color( 80,  80,  80);
  GUI::Color addrColor = GUI::Color(220, 220,   0);
  GUI::Color dataColor = GUI::Color(160, 160, 160);
  GUI::Color diffColor = GUI::Color(255,  20,  20);

  MemoryWindow() {
    addr = 0x7E0000;

    // relative position to bsnes window:
    @window = GUI::Window(256, 16, true);
    window.title = "Memory";
    window.font = GUI::Font("{mono}", 8);
    window.size = GUI::Size((16*3 + 6 + 3) * 8, (memRows + 2) * 16);
    window.backgroundColor = GUI::Color( 20,  20,  20);

    @vl = GUI::VerticalLayout();
    window.append(vl);

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 5);

      auto @lbl = GUI::Label();
      lbl.text = "address: ";
      lbl.foregroundColor = addrColor;
      hz.append(lbl, GUI::Size(0, 0), 5);

      @txtAddr = GUI::LineEdit();
      txtAddr.text = fmtHex(addr, 6);
      txtAddr.foregroundColor = GUI::Color(192, 192, 192);
      txtAddr.onChange(@GUI::Callback(txtAddrChanged));
      hz.append(txtAddr, GUI::Size(-1, 0), 5);

      @btnCapture = GUI::Button();
      btnCapture.text = "capture";
      btnCapture.onActivate(@GUI::Callback(btnCaptureClicked));
      hz.append(btnCapture, GUI::Size(0, 0), 5);
    }

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 0);

      auto @lbl = GUI::Label();
      lbl.text = "      ";
      lbl.foregroundColor = addrColor;
      hz.append(lbl, GUI::Size(0, 0), 0);

      @lbl = GUI::Label();
      lbl.text = " | ";
      lbl.foregroundColor = gridColor;
      hz.append(lbl, GUI::Size(0, 0), 0);

      // U+2007 = FIGURE SPACE = "Tabular width", the width of digits.
      for (uint i = 0; i < 0x10; i++) {
        @lblAddrCol[i] = GUI::Label();
        lblAddrCol[i].text = fmtHex((addr + i) & 0x0F, 2) + "\u2007";
        lblAddrCol[i].foregroundColor = addrColor;
        hz.append(lblAddrCol[i], GUI::Size(0, 0), 0);
      }

      @lbl = GUI::Label();
      lbl.text = "-------+------------------------------------------------";
      lbl.foregroundColor = gridColor;
      vl.append(lbl, GUI::Size(0, 0), 0);
    }

    for (uint i = 0; i < memRows; i++) {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 0);

      @lblAddrRow[i] = GUI::Label();
      lblAddrRow[i].text = fmtHex(addr + (i << 4), 6);
      lblAddrRow[i].foregroundColor = addrColor;
      hz.append(lblAddrRow[i], GUI::Size(0, 0), 0);

      auto @lbl = GUI::Label();
      lbl.text = " | ";
      lbl.foregroundColor = gridColor;
      hz.append(lbl, GUI::Size(0, 0), 0);

      for (uint x = 0; x < 16; x++) {
        auto j = (i << 4) + x;
        @lblData[j] = GUI::Label();
        lblData[j].text = "00\u2007";
        lblData[j].foregroundColor = dataColor;
        hz.append(lblData[j], GUI::Size(0, 0), 0);
      }
    }

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 5);

      auto @lbl = GUI::Label();
      lbl.text = "address: ";
      lbl.foregroundColor = addrColor;
      hz.append(lbl, GUI::Size(0, 0), 5);

      @txtWAddr = GUI::LineEdit();
      txtWAddr.text = "7ef340";
      txtWAddr.foregroundColor = GUI::Color(192, 192, 192);
      hz.append(txtWAddr, GUI::Size(120, 0), 5);

      @txtWValue = GUI::LineEdit();
      txtWValue.text = "00";
      txtWValue.foregroundColor = GUI::Color(192, 192, 192);
      hz.append(txtWValue, GUI::Size(80, 0), 5);

      @btnWrite = GUI::Button();
      btnWrite.text = "write";
      btnWrite.onActivate(@GUI::Callback(btnWriteClicked));
      hz.append(btnWrite, GUI::Size(0, 0), 5);
    }

    vl.resize();
    btnCaptureClicked();
    window.visible = true;
  }

  void btnCaptureClicked() {
    // capture current page:
    addrCapture = addr;
    bus::read_block_u8(addrCapture, 0, memWindowBytes, base);

    update();
  }

  void btnWriteClicked() {
    auto waddr = txtWAddr.text.hex();
    auto wvalue = txtWValue.text.hex();
    bus::write_u8(waddr, wvalue);

    update();
  }

  void txtAddrChanged() {
    addr = txtAddr.text.hex();
    if (addr + memWindowBytes >= 0x1000000) {
      addr = 0x1000000 - memWindowBytes;
    }

    update();
  }

  void update() {
    // read data:
    bus::read_block_u8(addr, 0, memWindowBytes, page);

    // update address columns:
    for (uint i = 0; i < 0x10; i++) {
      lblAddrCol[i].text = fmtHex((addr + i) & 0x0F, 2) + "\u2007";
    }

    // update display:
    int32 offs = addr - addrCapture;
    for (uint i = 0; i < memRows; i++) {
      auto row = i << 4;
      auto absAddr = addr + row;
      lblAddrRow[i].text = fmtHex(absAddr, 6);

      if ((absAddr < addrCapture) || (absAddr >= addrCapture + memWindowBytes)) {
        // no capture window overlap:
        for (uint x = 0; x < 0x10; x++, absAddr++) {
          auto j = row + x;
          lblData[j].text = fmtHex(page[j], 2) + "\u2007";
          lblData[j].foregroundColor = dataColor;
        }
      } else {
        // capture window overlap:
        for (uint x = 0; x < 0x10; x++, absAddr++) {
          auto j = row + x;
          lblData[j].text = fmtHex(page[j], 2) + "\u2007";

          // determine color:
          if ((absAddr >= addrCapture) && (absAddr < addrCapture + memWindowBytes)) {
            // compare current to snapshot:
            if (page[j] != base[j+offs]) {
              lblData[j].foregroundColor = diffColor;
            } else {
              lblData[j].foregroundColor = dataColor;
            }
          } else {
            lblData[j].foregroundColor = dataColor;
          }
        }
      }
    }
  }
};
