OAMWindow @oamWindow;

class OAMWindow {
  GUI::Color yellow;
  GUI::Color clrEnabled;
  GUI::Color clrDisabled;

  GUI::Window @window;
  array<array<GUI::Label@>> col(8);

  OAMWindow() {
    yellow      = GUI::Color(240, 240,   0);
    clrEnabled  = GUI::Color(240, 240, 240);
    clrDisabled = GUI::Color(110, 110, 110);

    @window = GUI::Window(0, 240*8*3, true);
    window.title = "OAM";
    window.size = GUI::Size(70*8, 20*16);

    auto @hl = GUI::HorizontalLayout();
    for (int i=0; i<8; i++) {
      // first label column:
      auto @vl = GUI::VerticalLayout();
      for (int j=0; j<16; j++) {
        auto @lbl = GUI::Label();
        lbl.foregroundColor = yellow;
        lbl.text = fmtHex(i*16+j,2);
        vl.append(lbl, GUI::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, GUI::Size(20, -1));

      // second value column:
      @vl = GUI::VerticalLayout();
      col[i].resize(16);
      for (int j=0; j<16; j++) {
        @col[i][j] = GUI::Label();
        col[i][j].foregroundColor = clrDisabled;
        col[i][j].text = "---";
        vl.append(col[i][j], GUI::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, GUI::Size(40, -1));
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
    for (uint i = 0; i < 8; i++) {
      for (uint j = 0; j < 16; j++) {
        auto @s = local.sprs[i*16+j];
        //s.decodeOAMTable(i*16+j);
        //s.fetchOAM(i*16+j);
        col[i][j].foregroundColor = s.is_enabled ? clrEnabled : clrDisabled;
        col[i][j].text = fmtHex(s.chr, 3);
        //col[i][j].text = fmtInt(s.x) + "," + fmtInt(s.y);
        //col[i][j].text = fmtHex(s.priority, 1);
      }
    }
  }
};
