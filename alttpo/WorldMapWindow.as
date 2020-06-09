WorldMapWindow @worldMapWindow;

class WorldMapWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  private GUI::ComboButton @dd;
  private GUI::CheckLabel @chkAuto;
  GUI::SNESCanvas @lightWorld;
  GUI::SNESCanvas @darkWorld;

  GUI::SNESCanvas @localDot;
  array<GUI::SNESCanvas@> dots;
  array<uint16> colors;

  // expressed in map 8x8 tile sizes:
  int mtop = 14;
  int mleft = 14;
  int mwidth = 35;
  int mheight = 35;

  int top = mtop*8;
  int left = mleft*8;
  int width = mwidth*8;
  int height = mheight*8;
  int mapscale = 2;

  // showing light world (false) or dark world (true):
  bool isDark = false;

  WorldMapWindow() {
    // relative position to bsnes window:
    @window = GUI::Window(256*3*8/7, 0, true);
    window.title = "World Map";
    window.size = GUI::Size(width*mapscale, height*mapscale + 32);
    window.resizable = false;
    window.dismissable = false;

    @vl = GUI::VerticalLayout();
    window.append(vl);

    @lightWorld = GUI::SNESCanvas();
    vl.append(lightWorld, GUI::Size(width*mapscale, height*mapscale));
    lightWorld.size = GUI::Size(width*mapscale, height*mapscale);
    lightWorld.setAlignment(0.0, 0.0);
    lightWorld.setCollapsible(true);
    lightWorld.setPosition(0, 0);
    lightWorld.visible = true;

    @darkWorld = GUI::SNESCanvas();
    vl.append(darkWorld, GUI::Size(width*mapscale, height*mapscale));
    darkWorld.size = GUI::Size(width*mapscale, height*mapscale);
    darkWorld.setAlignment(0.0, 0.0);
    darkWorld.setCollapsible(true);
    darkWorld.setPosition(0, 0);
    darkWorld.visible = false;

    auto @hl = GUI::HorizontalLayout();
    vl.append(hl, GUI::Size(-1, 32));

    @dd = GUI::ComboButton();
    hl.append(dd, GUI::Size(-1, 0));
    @chkAuto = GUI::CheckLabel();
    hl.append(chkAuto, GUI::Size(0, 0));

    auto @di = GUI::ComboButtonItem();
    di.text = "Light World";
    di.setSelected();
    dd.append(di);

    @di = GUI::ComboButtonItem();
    di.text = "Dark World";
    dd.append(di);

    dd.onChange(@GUI::Callback(toggledLightDarkWorld));
    dd.enabled = false;

    chkAuto.text = "Auto";
    chkAuto.checked = true;
    chkAuto.onToggle(@GUI::Callback(toggledAuto));

    @localDot = makeDot();
    fillDot(localDot, ppu::rgb(0, 0, 0x1f));

    vl.resize();

    window.visible = true;
  }

  void toggledAuto() {
    dd.enabled = !chkAuto.checked;
  }

  void toggledLightDarkWorld() {
    // show light or dark world depending on dropdown selection offset (0 = light, 1 = dark):
    isDark = (dd.selected.offset == 1);
    showWorld();
  }

  void showWorld() {
    darkWorld.visible = isDark;
    lightWorld.visible = !isDark;
  }

  void update(const GameState &in local) {
    if (!chkAuto.checked) {
      toggledLightDarkWorld();
      return;
    }

    // show the appropriate map:
    isDark = local.is_in_dark_world();
    showWorld();

    // update dropdown selection if changed:
    auto selectedOffset = isDark ? 1 : 0;
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
  void loadMap() {
    if (loaded) return;

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

            // nearest-neighbor scaling:
            px *= mapscale;
            py *= mapscale;
            for (int sy = 0; sy < mapscale; sy++) {
              for (int sx = 0; sx < mapscale; sx++) {
                canvas.pixel(px+sx, py+sy, color);
              }
            }

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

  GUI::SNESCanvas @makeDot(int diam = 12) {
    int max = diam-1;
    int s = diam/2;

    auto @c = GUI::SNESCanvas();
    vl.append(c, GUI::Size(diam, diam));
    c.size = GUI::Size(diam, diam);
    c.setPosition(-128, -128);
    c.setAlignment(0.5, 0.5);

    return c;
  }

  void fillDot(GUI::SNESCanvas @c, uint16 color, int diam = 12) {
    int max = diam-1;
    int s = diam/2;

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

  int mapsprleft = 126;
  int mapsprtop = 130;
  void mapCoord(const GameState &in p, float &out x, float &out y) {
    int px = p.x;
    int py = p.y;

    // in a dungeon:
    if ((p.location & 0x010000) == 0x010000) {
      if (rom is null) {
        px = p.last_overworld_x;
        py = p.last_overworld_y;
        return;
      }

      // get last entrance:
      auto entrance = (p.dungeon_entrance & 0xFF) << 1;
      // get room for entrance:
      auto room = bus::read_u16(rom.entrance_table_room + entrance);
      //auto room = p.location & 0xffff;

      // room 0x0104 is Link's house
      if (room != 0x0104 && room >= 0x100 && room < 0x180) {
        // simple exit:
        px = p.last_overworld_x;
        py = p.last_overworld_y;
      } else {
        // has exit data:
        uint i;
        for (i = 0; i < 0x9E; i += 2) {
          auto exit_room = bus::read_u16(rom.exit_table_room + i);
          if (room == exit_room) {
            // use link X,Y coords for exit:
            px = bus::read_u16(rom.exit_table_link_x + i);
            py = bus::read_u16(rom.exit_table_link_y + i);
            break;
          }
        }

        if (i == 0x9E) {
          // if no exit, use last coords:
          px = p.last_overworld_x;
          py = p.last_overworld_y;
        }
      }
    }

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

    x = float((px / 16) + mapsprleft - left) * mapscale;
    y = float((py / 16) + mapsprtop - top) * mapscale;
  }

  void renderPlayers() {
    const array<GameState@> @ps;

    if (sock is null) {
      @ps = onlyLocalPlayer;
    } else {
      @ps = players;
    }

    // grow dots array and create new Canvas instances:
    if (ps.length() > dots.length()) {
      dots.resize(ps.length());
      colors.resize(ps.length());
      for (uint i = 0; i < dots.length(); i++) {
        if (null != @dots[i]) continue;

        // create new dot:
        @dots[i] = makeDot();
        colors[i] = 0xffff;
      }
    }

    // Map world-pixel coordinates to world-map coordinates:
    float x, y;
    for (uint i = 0; i < ps.length(); i++) {
      auto @p = ps[i];
      auto @dot = dots[i];

      if ((p.ttl <= 0) || (p.is_in_dark_world() != isDark)) {
        // If player disappeared, hide their dot:
        dot.setPosition(-128, -128);
        continue;
      }

      // check if we need to fill the dot in with the player's color:
      if (p.player_color != colors[i]) {
        fillDot(dot, p.player_color | 0x8000);
        colors[i] = p.player_color;
      }

      // position the dot:
      mapCoord(p, x, y);
      dot.setPosition(x, y);
    }
  }
};
