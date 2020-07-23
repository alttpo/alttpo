GameSpriteWindow @gameSpriteWindow;

class GameSpriteWindow {
  GUI::Color clrYellow   = GUI::Color(240, 240,   0);
  GUI::Color clrDisabled = GUI::Color( 80,  80,  80);
  GUI::Color clrBlack    = GUI::Color(  0,   0,   0);

  GUI::Window @window;
  array<GUI::Label@> col(16);

  GameSpriteWindow() {
    int charCount = 34+84;

    @window = GUI::Window(0, 240*3, true);
    window.title = "Game Sprites";
    window.backgroundColor = clrBlack;
    window.font = GUI::Font("{mono}", 8);
    window.size = GUI::Size(8*charCount+10+5, 19*16);

    auto @hl = GUI::HorizontalLayout();
      // first label column:
      auto @vl = GUI::VerticalLayout();
      for (int j=0; j<16; j++) {
        auto @lbl = GUI::Label();
        lbl.foregroundColor = clrYellow;
        lbl.text = fmtHex(j,1)+":";
        vl.append(lbl, GUI::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, GUI::Size(10, -1));

      // second value column:
      @vl = GUI::VerticalLayout();
      col.resize(16);
      for (int j=0; j<16; j++) {
        @col[j] = GUI::Label();
        col[j].foregroundColor = clrBlack;
        col[j].backgroundColor = clrDisabled;
        col[j].text = "";
        vl.append(col[j], GUI::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, GUI::Size(8*charCount, -1));
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

  // must be run from post_frame():
  void update() {
    if (@local.objects == null) return;

    for (int i = 0; i < 0x10; i++) {
      auto @en = @local.objects[i];
      if (@en is null) continue;

      // generate a color:
      auto color = ppu::rgb(
        ((i & 4) >> 2) * 12 + ((i & 8) >> 3) * 12 + 7,
        ((i & 2) >> 1) * 12 + ((i & 8) >> 3) * 12 + 7,
        ((i & 1)     ) * 12 + ((i & 8) >> 3) * 12 + 7
      );
      GUI::Color rgbColor = GUI::Color(
        ((i & 4) >> 2) * 98 + ((i & 8) >> 3) * 98 + 58,  // red
        ((i & 2) >> 1) * 98 + ((i & 8) >> 3) * 98 + 58,  // green
        ((i & 1)     ) * 98 + ((i & 8) >> 3) * 98 + 58   // blue
      );

      // set 24-bit equivalent color:
      col[i].foregroundColor = (en.is_enabled) ? rgbColor : clrBlack;
      col[i].backgroundColor = (en.is_enabled) ? clrBlack : clrDisabled;
      // format text:
      auto text = "(" + fmtHex(en.x,4) + "," + fmtHex(en.y,4) + ")" +
        " st=" + fmtHex(en.state, 1) +
        " ty=" + fmtHex(en.type, 2) + "." + fmtHex(en.subtype, 2) +
        " ai=" + fmtHex(en.ai, 2) +
        " hp=" + fmtHex(en.hp, 2) +
        " oc=" + fmtHex(en.oam_count, 2) +
        " ";
      for (int j = 0; j < 0x2A; j++) {
        text += fmtHex(en.facts[j],2);
      }
      col[i].text = text;

      // don't draw box around dead sprites:
      if (false && en.is_enabled) {
        // not in normal, active mode:
        //if (en.state != 0x09) continue;

        // subtract BG2 offset from sprite x,y coords to get local screen coords:
        int16 rx = int16(en.x) - int16(local.xoffs);
        int16 ry = int16(en.y) - int16(local.yoffs);

        ppu::frame.color = color;

        // draw box around the sprite:
        ppu::frame.rect(rx, ry, 16, 16);

        // draw sprite type value above box:
        ry -= ppu::frame.font_height;
        ppu::frame.text(rx, ry, fmtHex(en.type, 2));
      }
    }
  }
};
