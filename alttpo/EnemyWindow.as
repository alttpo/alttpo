EnemyWindow @enemyWindow;

class EnemyWindow {
  GUI::Color clrYellow   = GUI::Color(240, 240,   0);
  GUI::Color clrDisabled = GUI::Color( 80,  80,  80);
  GUI::Color clrBlack    = GUI::Color(  0,   0,   0);

  GUI::Window @window;
  GUI::VerticalLayout @vl;
  array<GUI::Label@> col(16);

  EnemyWindow() {
    int charCount = 16+(enemy_data_ptrs.length()*3);

    @window = GUI::Window(0, 240*3, true);
    window.title = "Enemies";
    window.font = GUI::Font("{mono}", 8);
    window.size = GUI::Size(8*charCount+10+5, 14*17);
    window.backgroundColor = clrBlack;

    @vl = GUI::VerticalLayout();
    window.append(vl);
    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 0);

      auto @lbl = GUI::Label();
      string txt = "-------------------------------- ";
      for (uint j = 0; j < enemy_data_ptrs.length(); j++) {
        txt += fmtHex(j, 2) + " ";
      }
      lbl.text = txt;
      hz.append(lbl, GUI::Size(-1, 0), 0);
      hz.resize();
    }

    for (uint j=0; j<16; j++) {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0), 0);

      @col[j] = GUI::Label();
      col[j].text = fmtHex(j,1)+": ";
      col[j].foregroundColor = clrBlack;
      col[j].backgroundColor = clrDisabled;
      hz.append(col[j], GUI::Size(-1, 0), 0);
      hz.resize();
    }

    vl.resize();
    window.visible = true;
  }

  void show() {
    window.visible = true;
  }

  void hide() {
    window.visible = false;
  }

  // must be run from post_frame():
  void update() {
    if (local.enemyData is null) {
      return;
    }

    for (uint i = 0; i < 0x10; i++) {
      uint8 aimode = local.enemyData[(spr_aimode<<4) + i];
      uint8 id = local.enemyData[(spr_id<<4) + i];
      uint16 y = uint16(local.enemyData[(spr_yl<<4) + i]) | uint16(local.enemyData[(spr_yh<<4) + i])<<8;
      uint16 x = uint16(local.enemyData[(spr_xl<<4) + i]) | uint16(local.enemyData[(spr_xh<<4) + i])<<8;
      uint8 hp = local.enemyData[(spr_hp<<4) + i];

      // generate a color:
      //auto color = ppu::rgb(
      //  ((i & 4) >> 2) * 12 + ((i & 8) >> 3) * 12 + 7,
      //  ((i & 2) >> 1) * 12 + ((i & 8) >> 3) * 12 + 7,
      //  ((i & 1)     ) * 12 + ((i & 8) >> 3) * 12 + 7
      //);
      GUI::Color rgbColor = GUI::Color(
        ((i & 4) >> 2) * 98 + 98 + 59,  // red
        ((i & 2) >> 1) * 98 + 98 + 59,  // green
        ((i & 1)     ) * 98 + 98 + 59   // blue
      );

      // set 24-bit equivalent color:
      col[i].foregroundColor = (aimode != 0) ? rgbColor : clrBlack;
      col[i].backgroundColor = (aimode != 0) ? clrBlack : clrDisabled;
      // format text:
      auto txt = fmtHex(i,1)+": (" + fmtHex(x, 4) + "," + fmtHex(y, 4) + ")" +
        " ai=" + fmtHex(aimode, 2) +
        " id=" + fmtHex(id, 2) +
        " hp=" + fmtHex(hp, 2) +
        " ";
      for (uint j = 0; j < enemy_data_ptrs.length(); j++) {
        txt += fmtHex(local.enemyData[(j<<4) + i], 2) + " ";
      }
      col[i].text = txt;
    }
  }
};
