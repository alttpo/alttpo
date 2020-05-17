OAMWindow @oamWindow;

class OAMWindow {
  gui::Color yellow;
  gui::Color clrEnabled;
  gui::Color clrDisabled;

  gui::Window @window;
  array<array<gui::Label@>> col(8);

  OAMWindow() {
    yellow      = gui::Color(240, 240,   0);
    clrEnabled  = gui::Color(240, 240, 240);
    clrDisabled = gui::Color(110, 110, 110);

    @window = gui::Window(0, 240*8*3, true);
    window.title = "OAM";
    window.size = gui::Size(70*8, 20*16);

    auto @hl = gui::HorizontalLayout();
    for (int i=0; i<8; i++) {
      // first label column:
      auto @vl = gui::VerticalLayout();
      for (int j=0; j<16; j++) {
        auto @lbl = gui::Label();
        lbl.foregroundColor = yellow;
        lbl.text = fmtHex(i*16+j,2);
        vl.append(lbl, gui::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, gui::Size(20, -1));

      // second value column:
      @vl = gui::VerticalLayout();
      col[i].resize(16);
      for (int j=0; j<16; j++) {
        @col[i][j] = gui::Label();
        col[i][j].foregroundColor = clrDisabled;
        col[i][j].text = "---";
        vl.append(col[i][j], gui::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, gui::Size(40, -1));
    }
    window.append(hl);

    hl.resize();
    window.visible = true;
  }

  void show() {
    window.visible = true;
  }

  void hide() {
    window.visible = false;
  }

  void update() {
    Sprite s;
    for (uint i = 0; i < 8; i++) {
      for (uint j = 0; j < 16; j++) {
        //s.decodeOAMTable(i*16+j);
        s.fetchOAM(i*16+j);
        col[i][j].foregroundColor = s.is_enabled ? clrEnabled : clrDisabled;
        col[i][j].text = fmtHex(s.chr, 3);
      }
    }
  }
};
