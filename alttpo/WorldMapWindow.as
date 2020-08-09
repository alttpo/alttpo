WorldMapWindow @worldMapWindow;

class WorldMapWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  private GUI::ComboButton @dd;
  private GUI::CheckLabel @chkAuto;
  GUI::SNESCanvas @lightWorld;
  GUI::SNESCanvas @darkWorld;
  GUI::Canvas @underworld;

  array<GUI::SNESCanvas@> dots;
  array<float> dotX(0);
  array<float> dotY(0);
  array<uint16> colors;

  // expressed in map 8x8 tile sizes:
  int mtop = 4;
  int mleft = 8;
  int mwidth = 48;
  int mheight = 57;

  int top = mtop*8;
  int left = mleft*8;
  int width = mwidth*8;
  int height = mheight*8;
  float mapscale = 2;
  int dotDiam = 12;
  float dotTop = 0;
  float dotLeft = 0;

  // showing light world (false) or dark world (true):
  int screen = -1;

  WorldMapWindow() {
    // relative position to bsnes window:
    @window = GUI::Window(256*2*8/7.0, 0, true);
    window.title = "World Map";
    window.size = GUI::Size(sx(width*mapscale), sy(height*mapscale + 32));
    window.resizable = true;
    window.dismissable = false;

    @vl = GUI::VerticalLayout();
    window.append(vl);

    @lightWorld = GUI::SNESCanvas();
    vl.append(lightWorld, GUI::Size(-1, -1));
    lightWorld.size = GUI::Size(width, height);
    lightWorld.setPosition(0, 0);
    lightWorld.setAlignment(0, 0);
    lightWorld.setCollapsible(true);
    lightWorld.visible = true;

    @darkWorld = GUI::SNESCanvas();
    vl.append(darkWorld, GUI::Size(-1, -1));
    darkWorld.size = GUI::Size(width, height);
    darkWorld.setPosition(0, 0);
    darkWorld.setAlignment(0, 0);
    darkWorld.setCollapsible(true);
    darkWorld.visible = false;

    {
      @underworld = GUI::Canvas();
      vl.append(underworld, GUI::Size(-1, -1));

      underworld.setPosition(0, 0);
      underworld.setAlignment(0, 0);
      underworld.collapsible = true;
      underworld.visible = false;

      // NOTE(jsd): this takes about 4 seconds to load on my MacBook Pro. yuck.
      if (!underworld.loadPNG("map-underworld.png")) {
        message("failed to load map-underworld.png");
        // fill the canvas with red to denote failure:
        underworld.color = GUI::Color(192, 0, 0);
      }
    }

    auto @hl = GUI::HorizontalLayout();
    vl.append(hl, GUI::Size(-1, sy(24)));

    @dd = GUI::ComboButton();
    hl.append(dd, GUI::Size(-1, 0));
    @chkAuto = GUI::CheckLabel();
    hl.append(chkAuto, GUI::Size(0, 0));

    // this combo box determines screen shown, 0 = light, 1 = dark, 2 = underworld
    auto @di = GUI::ComboButtonItem();
    di.text = "Light World";
    di.setSelected();
    dd.append(di);

    @di = GUI::ComboButtonItem();
    di.text = "Dark World";
    dd.append(di);

    @di = GUI::ComboButtonItem();
    di.text = "Underworld";
    dd.append(di);

    dd.onChange(@GUI::Callback(toggledLightDarkWorld));
    dd.enabled = false;

    chkAuto.text = "Auto";
    chkAuto.checked = true;
    chkAuto.onToggle(@GUI::Callback(toggledAuto));

    lightWorld.onSize(@GUI::Callback(onSize));
    darkWorld.onSize(@GUI::Callback(onSize));
    underworld.onSize(@GUI::Callback(onSize));

    lightWorld.doSize();

    window.visible = true;
  }

  // callback:
  private void onSize() {
    float screenWidth = width;
    float screenHeight = height;

    GUI::Size s;
    if (screen == 0) {
      s = lightWorld.geometry.size;
    } else if (screen == 1) {
      s = darkWorld.geometry.size;
    } else if (screen == 2) {
      s = underworld.geometry.size;
      screenWidth = 8192;
      screenHeight = 9728;
    }
    //message("onSize: " + fmtFloat(s.width) + "," + fmtFloat(s.height));

    // assume map image is scaling proportionally up or down, so take minimum dimension:
    if (s.width / screenWidth <= s.height / screenHeight) {
      mapscale = s.width / screenWidth;
    } else {
      mapscale = s.height / screenHeight;
    }

    dotLeft = 0;
    dotTop = 0;
    redrawDots();
  }

  void redrawDots() {
    // reset dots:
    uint len = dots.length();
    for (uint i = 0; i < len; i++) {
      if (dots[i] is null) continue;

      dotX[i] = -127;
      dotY[i] = -127;
      colors[i] = 0xffff;
    }

    // redraw dots:
    renderPlayers();
  }

  void toggledAuto() {
    dd.enabled = !chkAuto.checked;
  }

  void toggledLightDarkWorld() {
    // show light or dark world depending on dropdown selection offset (0 = light, 1 = dark, 2 = underworld):
    screen = dd.selected.offset;
    showWorld();
  }

  bool forceSwitch = true;
  int lastScreen = -2;
  void showWorld() {
    if (screen != lastScreen || forceSwitch) {
      forceSwitch = false;
      lightWorld.visible = (screen == 0);
      darkWorld.visible = (screen == 1);
      underworld.visible = (screen == 2);
      vl.resize();
      redrawDots();
      lastScreen = screen;
    }
  }

  int screenFor(const GameState &in p) {
    // cave = (actual_location & 0x010000) == 0x010000
    // dark = (actual_location & 0x020000) == 0x020000

    if (((p.actual_location & 0x010000) == 0x010000) && (p.dungeon != 0xFF)) {
      // 2 = underworld, only for dungeons:
      return 2;
    } else {
      // 0 = light overworld, 1 = dark overworld:
      return (p.actual_location & 0x020000) >> 17;
    }
  }

  bool showsOnScreen(const GameState &in p, int screen) {
    if (screen == 0) {
      // must be in light world:
      return (p.actual_location & 0x020000) == 0;
    } else if (screen == 1) {
      // must be in dark world:
      return (p.actual_location & 0x020000) == 0x020000;
    } else if (screen == 2) {
      // must be in underworld in light or dark world:
      return (p.actual_location & 0x010000) == 0x010000;
    }
    return false;
  }

  void update(const GameState &in local) {
    if (!chkAuto.checked) {
      toggledLightDarkWorld();
      return;
    }

    // show the appropriate map:
    screen = screenFor(local);
    showWorld();

    // update dropdown selection if changed:
    auto selectedOffset = screen;
    if (dd.selected.offset != selectedOffset) {
      dd[selectedOffset].setSelected();
    }
  }

  bool loaded = false;
  array<uint16> paletteLight;
  array<uint16> paletteDark;
  array<uint8> tilemapLight;
  array<uint8> tilemapDark;
  array<uint8> gfx;
  void loadMap(bool reload = false) {
    if (reload) {
      loaded = false;
    }
    if (loaded) {
      return;
    }

    // mode7 tile map and gfx data for world maps:
    paletteLight.resize(0x100);
    tilemapLight.resize(0x4000);
    gfx.resize(0x4000);

    // from bank00.asm CopyMode7Chr:
    bus::read_block_u8(0x18C000, 0, 0x4000, gfx);

    // read light world map palette:
    bus::read_block_u16(rom.palette_lightWorldMap, 0, 0x100, paletteLight);

    // load light world's map:
    {
      // direct translation of NMI_LightWorldMode7Tilemap from bank00.asm:
      int p02 = 0;
      array<uint16> offsets = {0x0000, 0x0020, 0x1000, 0x1020};
      for (int p04 = 0; p04 < 8; p04 += 2) {
        //uint16 p00 = bus::read_u16(0x008E4C + p04);
        uint16 p00 = offsets[p04 >> 1];
        for (int p06 = 0; p06 < 0x20; p06++) {
          int dest = p00;
          p00 += 0x80;  // = width of mode7 tilemap (128x128 tiles)
          bus::read_block_u8(rom.tilemap_lightWorldMap + p02, dest, 0x20, tilemapLight);
          p02 += 0x20;
        }
      }
    }

    paletteDark.resize(0x100);
    tilemapDark = tilemapLight;

    // load dark world palette:
    bus::read_block_u16(rom.palette_darkWorldMap, 0, 0x100, paletteDark);

    // load dark world tilemap:
    {
      int p02 = 0;
      uint16 p00 = 0x0810;
      for (int p06 = 0; p06 < 0x20; p06++) {
        int dest = p00;
        p00 += 0x80;  // = width of mode7 tilemap (128x128 tiles)
        bus::read_block_u8(rom.tilemap_darkWorldMap + p02, dest, 0x20, tilemapDark);
        p02 += 0x20;
      }
    }

    loaded = true;
  }

  bool drawn = false;
  void redrawMap() {
    drawn = false;
    drawMap();
  }

  void drawMap() {
    if (drawn) return;

    // render map to canvas:
    lightWorld.fill(0x0000);
    drawMode7Map(lightWorld, tilemapLight, gfx, paletteLight);
    lightWorld.update();

    // render map to canvas:
    darkWorld.fill(0x0000);
    drawMode7Map(darkWorld, tilemapDark, gfx, paletteDark);
    darkWorld.update();

    drawn = true;
  }

  void drawMode7Map(GUI::SNESCanvas @canvas, const array<uint8> &in tilemap, const array<uint8> &in gfx, const array<uint16> &in palette) {
    // draw map as mode 7 tiles:
    for (int my = mtop; my < mtop + mheight; my++) {
      for (int mx = mleft; mx < mleft + mwidth; mx++) {
        // pick tile:
        uint8 t = tilemap[(my*128+mx)];

        // draw tile:
        for (int y = 0; y < 8; y++) {
          for (int x = 0; x < 8; x++) {
            uint8 c = gfx[(t*64)+((y*8)+x)];
            uint16 color = palette[c] | 0x8000;

            int px = (mx-mleft)*8+x;
            int py = (my-mtop)*8+y;

            canvas.pixel(px, py, color);
          }
        }
      }
    }
  }

  void horizontalLine(GUI::SNESCanvas @c, uint16 color, int x0, int y0, int x1) {
    for (int x = x0; x <= x1; ++x)
      c.pixel(x, y0, color);
  }

  void plot4points(GUI::SNESCanvas @c, uint16 color, bool fill, int cx, int cy, int x, int y) {
    if (fill) {
      horizontalLine(c, color, cx - x, cy + y, cx + x);
      if (y != 0)
        horizontalLine(c, color, cx - x, cy - y, cx + x);
    } else {
      c.pixel(cx + x, cy + y, color);
      c.pixel(cx - x, cy + y, color);
      c.pixel(cx + x, cy - y, color);
      c.pixel(cx - x, cy - y, color);
    }
  }

  void circle(GUI::SNESCanvas @c, uint16 color, bool fill, int x0, int y0, int radius) {
    int error = -radius;
    int x = radius;
    int y = 0;

    while (x >= y) {
      plot4points(c, color, fill, x0, y0, x, y);
      if (!fill && (x != y)) {
        plot4points(c, color, fill, x0, y0, y, x);
      }

      error += y;
      ++y;
      error += y;

      if (error >= 0) {
        if (fill) {
          plot4points(c, color, fill, x0, y0, y - 1, x);
        }

        error -= x;
        --x;
        error -= x;
      }
    }
  }

  GUI::SNESCanvas @makeDot() {
    int max = dotDiam-1;
    int s = dotDiam/2;

    auto @c = GUI::SNESCanvas();
    c.layoutExcluded = true;
    vl.append(c, GUI::Size(sx(dotDiam), sy(dotDiam)));
    c.size = GUI::Size(dotDiam, dotDiam);
    c.setPosition(-128, -128);
    c.setAlignment(0.5, 0.5);

    return c;
  }

  void fillDot(GUI::SNESCanvas @c, uint16 color) {
    int max = dotDiam-1;
    int s = dotDiam/2;

    uint16 outline = ppu::rgb(0x1f, 0x1f, 0x1f) | 0x8000;
    color |= 0x8000;

    if (false) {
      // filled square with outline:
      c.fill(color);

      for (int i = 0; i < s; i++) {
        // top line:
        c.pixel(    i,     0, outline);
        c.pixel(max-i,     0, outline);
        // bottom line:
        c.pixel(    i,   max, outline);
        c.pixel(max-i,   max, outline);
        // left line:
        c.pixel(    0,     i, outline);
        c.pixel(    0, max-i, outline);
        // right line:
        c.pixel(  max,     i, outline);
        c.pixel(  max, max-i, outline);
      }
    } else {
      // filled circle with outline:
      circle(c, color,   true,  s, s, s-1);
      circle(c, outline, false, s, s, s-1);
    }

    c.update();
  }

  int mapsprleft = 2048;
  int mapsprtop = 2132;
  //int mapsprtop = 2096;
  void mapCoord(GameState@ p, float &out x, float &out y) {
    if (rom is null) {
      x = 0;
      y = 0;
      return;
    }

    if (screen == 0 || screen == 1) {
      // overworld map screen:
      int px = p.last_overworld_x;
      int py = p.last_overworld_y;

      if (p.is_in_overworld_module() || p.module == 0x10) {
        // in overworld:
        px = p.x;
        py = p.y;

        if (p.location == 0x000080) {
          if (px < 0x100) {
            // in master sword grove:
            px += 0x20;
            py += -0x146;
          } else if (px < 0x200) {
            // under the bridge:
            // bridge underside from x=0108 to x=01f0 (e8)
            // bridge underside from y=0018 to y=00c0 (a8)
            // bridge overworld from x=0af0 to y=0b30 (40)
            // bridge overworld from y=0af0 to y=0b40 (50)
            px = ((px - 0x108) * 0x40 / 0xe8) + 0xaf0;
            py = ((py - 0x018) * 0x50 / 0xa0) + 0xaf0;
          }
        } else if (p.location == 0x000081) {
          // in zora's waterfall:
          px = 0xf50;
          py = 0x213;
        }
      } else if (p.is_in_dungeon_module()) {
        // in a dungeon:
      }

      x = (float(px + mapsprleft) / 16.0 - left) * mapscale + dotLeft;
      y = (float(py + mapsprtop) / 16.0 - top) * mapscale + dotTop;
    } else if (screen == 2) {
      int px = p.x;
      int py = p.y;

      x = float(px) * mapscale + dotLeft;
      y = float(py) * mapscale + dotTop;
    }
  }

  private array<GameState@>@ playersArray() {
    array<GameState@> @ps;

    if (sock is null) {
      @ps = onlyLocalPlayer;
    } else {
      @ps = players;
    }

    return ps;
  }

  void renderPlayers() {
    array<GameState@> @ps = playersArray();

    // grow dots array and create new Canvas instances:
    uint psLen = ps.length();
    uint dotsLen = dots.length();
    if (psLen > dotsLen) {
      dots.resize(psLen);
      colors.resize(psLen);
      dotX.resize(psLen);
      dotY.resize(psLen);
      for (uint i = 0; i < psLen; i++) {
        if (null != @dots[i]) continue;

        // create new dot:
        @dots[i] = makeDot();
        dotX[i] = -127;
        dotY[i] = -127;
        colors[i] = 0xffff;
      }
    }

    // Map world-pixel coordinates to world-map coordinates:
    float x, y;
    for (uint i = 0; i < psLen; i++) {
      auto @p = ps[i];
      auto @dot = dots[i];

      if ((p.ttl <= 0) || (!showsOnScreen(p, screen))) {
        // If player disappeared, hide their dot:
        dot.setPosition(-128, -128);
        dotX[i] = -127;
        dotY[i] = -127;
        continue;
      }

      // check if we need to fill the dot in with the player's color:
      if (p.player_color != colors[i]) {
        fillDot(dot, p.player_color | 0x8000);
        colors[i] = p.player_color;
      }

      // position the dot:
      mapCoord(p, x, y);
      if (x != dotX[i] || y != dotY[i]) {
        dot.setPosition(x - dotDiam / 2.0, y - dotDiam / 2.0);
        dotX[i] = x;
        dotY[i] = y;
      }
    }
  }
};
