DungeonMapWindow @dungeonMapWindow;

class DungeonMapWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  GUI::SNESCanvas @dungeonMap;

  GUI::SNESCanvas @localDot;
  array<GUI::SNESCanvas@> dots;

  int width = 5*16;
  int height = 5*16;
  int mapscale = 3;

  // showing light world (false) or dark world (true):
  bool isDark = false;

  WorldMapWindow() {
    // relative position to bsnes window:
    @window = GUI::Window(256*3*8/7, height, true);
    window.title = "Dungeon Map";
    window.size = GUI::Size(width*mapscale, height*mapscale);
    window.resizable = false;
    window.dismissable = false;

    @vl = GUI::VerticalLayout();
    window.append(vl);

    @dungeonMap = GUI::SNESCanvas();
    vl.append(dungeonMap, GUI::Size(width*mapscale, height*mapscale));
    dungeonMap.size = GUI::Size(width*mapscale, height*mapscale);
    dungeonMap.setAlignment(0.0, 0.0);
    dungeonMap.setCollapsible(true);
    dungeonMap.setPosition(0, 0);
    dungeonMap.visible = true;

    auto @hl = GUI::HorizontalLayout();
    vl.append(hl, GUI::Size(-1, 32));

    chkAuto.text = "Auto";
    chkAuto.checked = true;
    chkAuto.onToggle(@GUI::Callback(toggledAuto));

    @localDot = makeDot(ppu::rgb(0, 0, 0x1f));

    vl.resize();

    window.visible = true;
  }

  void update(const GameState &in local) {
  }

  bool loaded = false;
  array<uint16> paletteLight;
  array<uint8> gfx;
  void loadMap() {
    if (loaded) return;

    // mode7 tile map and gfx data for world maps:
    paletteLight.resize(0x100);

    // read light world map palette:
    bus::read_block_u16(rom.palette_lightWorldMap, 0, 0x100, paletteLight);

    k=(basements+curfloor)*25;
    n=0x92;
    for(o=0;o<25;o+=5) {
      for(i=0;i<5;i++) {
        l=rbuf[k];
        if(l==15) j=0x51; else {
          q=0;
          for(p=0;;p++) {
            j=rbuf[p];
            if(j!=15) if(j==l) break; else q++;
          }
          j=buf[q];
        }
        j<<=2;
        l=((short*)(rom+0x57009))[j];
        nbuf[n]=l;
        l=((short*)(rom+0x5700b))[j];
        nbuf[n+1]=l;
        l=((short*)(rom+0x5700d))[j];
        nbuf[n+32]=l;
        l=((short*)(rom+0x5700f))[j];
        nbuf[n+33]=l;
        n+=2;
        k++;
      }
      n+=54;
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

  GUI::SNESCanvas @makeDot(uint16 color) {
    int diam = 12;
    int max = diam-1;
    int s = diam/2;

    auto @c = GUI::SNESCanvas();
    vl.append(c, GUI::Size(diam, diam));
    c.size = GUI::Size(diam, diam);
    c.setPosition(-128, -128);
    c.setAlignment(0.5, 0.5);

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
    return c;
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

  void renderPlayers(const GameState @local, const array<GameState@> @players) {
    // grow dots array and create new Canvas instances:
    if (players.length() > dots.length()) {
      dots.resize(players.length());
      for (uint i = 0; i < dots.length(); i++) {
        if (null != @dots[i]) continue;

        // create new dot:
        auto j = i + 1;
        auto color = ppu::rgb(
          ((j & 4) >> 2) * 0x12 + ((j & 8) >> 3) * 0x0d,
          ((j & 2) >> 1) * 0x12 + ((j & 8) >> 3) * 0x0d,
          ((j & 1)) * 0x12 + ((j & 8) >> 3) * 0x0d
        );
        @dots[i] = makeDot(color);
      }
    }

    // Map world-pixel coordinates to world-map coordinates:
    float x, y;
    for (uint i = 0; i < players.length(); i++) {
      auto @p = @players[i];
      if ((p.ttl <= 0) || (p.is_in_dark_world() != isDark)) {
        // If player disappeared, hide their dot:
        dots[i].setPosition(-128, -128);
        continue;
      }

      mapCoord(p, x, y);
      dots[i].setPosition(x, y);
    }
  }
};
