// ALTTP script to draw current Link sprites on top of rendered frame:
net::Socket@ sock;
net::Address@ address;
SettingsWindow @settings;

bool debug = false;
bool debugData = false;
bool debugOAM = false;
bool debugSprites = false;
bool debugGameObjects = false;

void init() {
  // Auto-detect ROM version:
  @rom = detect();

  @settings = SettingsWindow();
  settings.ServerAddress = "bittwiddlers.org";
  settings.Group = "enemy-sync";
  settings.Name = "";
  if (debug) {
    //settings.ServerAddress = "127.0.0.1";
    //settings.Group = "debug";
    settings.start();
    settings.hide();
  }

  if (debugSprites) {
    @sprites = SpritesWindow();
  }

  @worldMap = WorldMap();

  if (debugOAM) {
    @oamWindow = OAMWindow();
  }

  if (debugGameObjects) {
    @gameSpriteWindow = GameSpriteWindow();
  }
}

// Lookup table of ROM addresses depending on version:
abstract class ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0; }
  uint32 get_tilemap_darkWorldMap()  property { return 0; }
  uint32 get_palette_lightWorldMap() property { return 0; }
  uint32 get_palette_darkWorldMap()  property { return 0; }
};

class JPROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC739; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD739; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB39; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC39; }
};

class USROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC727; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD727; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB27; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC27; }
};

class EUROMMapping : ROMMapping {
  uint32 get_tilemap_lightWorldMap() property { return 0x0AC727; }
  uint32 get_tilemap_darkWorldMap()  property { return 0x0AD727; }
  uint32 get_palette_lightWorldMap() property { return 0x0ADB27; }
  uint32 get_palette_darkWorldMap()  property { return 0x0ADC27; }
};

ROMMapping@ detect() {
  array<uint8> sig(22);
  bus::read_block_u8(0x00FFC0, 0, 22, sig);
  auto title = sig.toString(0, 22);
  message("ROM title: \"" + title + "\"");
  if (title == "THE LEGEND OF ZELDA   ") {
    auto region = bus::read_u8(0x00FFD9);
    if (region == 0x01) {
      message("Recognized US ROM version.");
      return USROMMapping();
    } else if (region == 0x02) {
      message("Recognized EU ROM version.");
      return EUROMMapping();
    } else {
      message("Unrecognized ROM version but has US title; assuming US ROM.");
      return USROMMapping();
    }
  } else if (title == "ZELDANODENSETSU       ") {
    message("Recognized JP ROM version.");
    return JPROMMapping();
  } else if (sig.toString(0, 3) == "VT ") {
    // randomizer. use JP ROM by default.
    message("Recognized randomized JP ROM version. Seed: " + sig.toString(3, 10));
    return JPROMMapping();
  } else {
    message("Unrecognized ALTTP ROM version! Assuming JP ROM version.");
    return JPROMMapping();
  }
}

ROMMapping @rom = null;

class SettingsWindow {
  private gui::Window @window;
  private gui::LineEdit @txtServerAddress;
  private gui::LineEdit @txtGroup;
  private gui::LineEdit @txtName;
  private gui::Button @ok;

  private string serverAddress;
  string ServerAddress {
    get { return serverAddress; }
    set {
      serverAddress = value;
      txtServerAddress.text = value;
    }
  }

  private string group;
  string Group {
    get { return group; }
    set {
      txtGroup.text = value;
      assignGroup(value);
    }
  }
  private void assignGroup(string value) {
    // pad out to exactly 20 bytes:
    auto newValue = value.slice(0, 20);
    for (int i = newValue.length(); i < 20; i++) {
      newValue += " ";
    }
    group = newValue;
  }

  private string name;
  string Name {
    get { return name; }
    set {
      name = value;
      txtName.text = value;
    }
  }

  bool started;

  SettingsWindow() {
    @window = gui::Window(164, 22, true);
    window.title = "Join a Game";
    window.size = gui::Size(256, 24*5);

    auto vl = gui::VerticalLayout();
    {
      auto @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Address:";
        hz.append(lbl, gui::Size(100, 0));

        @txtServerAddress = gui::LineEdit();
        hz.append(txtServerAddress, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Group:";
        hz.append(lbl, gui::Size(100, 0));

        @txtGroup = gui::LineEdit();
        hz.append(txtGroup, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Player Name:";
        hz.append(lbl, gui::Size(100, 0));

        @txtName = gui::LineEdit();
        hz.append(txtName, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        @ok = gui::Button();
        ok.text = "Connect";
        @ok.on_activate = @gui::ButtonCallback(this.startClicked);
        hz.append(ok, gui::Size(-1, -1));
      }
      vl.append(hz, gui::Size(-1, -1));
    }
    window.append(vl);

    vl.resize();
    window.visible = true;
  }

  private void startClicked(gui::Button @self) {
    start();
    hide();
  }

  void start() {
    serverAddress = txtServerAddress.text;
    assignGroup(txtGroup.text);
    name = txtName.text;
    started = true;
  }

  void show() {
    window.visible = true;
  }

  void hide() {
    window.visible = false;
  }
};

const int scale = 3;
class SpritesWindow {
  private gui::Window @window;
  private gui::VerticalLayout @vl;
  gui::Canvas @canvas;

  array<uint16> page0(0x1000);
  array<uint16> page1(0x1000);

  SpritesWindow() {
    // relative position to bsnes window:
    @window = gui::Window(0, 240*3, true);
    window.title = "Sprite VRAM";
    window.size = gui::Size(256*scale, 128*scale);

    @vl = gui::VerticalLayout();
    window.append(vl);

    @canvas = gui::Canvas();
    canvas.size = gui::Size(256, 128);
    vl.append(canvas, gui::Size(-1, -1));

    vl.resize();
    canvas.update();
    window.visible = true;
  }

  void update() {
    canvas.update();
  }

  void render(const array<uint16> &palette) {
    // read VRAM:
    ppu::vram.read_block(0x4000, 0, 0x1000, page0);
    ppu::vram.read_block(0x5000, 0, 0x1000, page1);

    // draw VRAM as 4bpp tiles:
    canvas.fill(0x0000);
    canvas.draw_sprite_4bpp(  0, 0, 0, 128, 128, page0, palette);
    canvas.draw_sprite_4bpp(128, 0, 0, 128, 128, page1, palette);
  }
};
SpritesWindow @sprites;
array<uint16> palette7(16);

class WorldMap {
  private gui::Window @window;
  private gui::VerticalLayout @vl;
  gui::Canvas @lightWorld;
  gui::Canvas @darkWorld;

  gui::Canvas @localDot;
  array<gui::Canvas@> dots;

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

  WorldMap() {
    // relative position to bsnes window:
    @window = gui::Window(256*3*8/7, 0, true);
    window.title = "World Map";
    window.size = gui::Size(width*mapscale, height*mapscale);

    @vl = gui::VerticalLayout();
    window.append(vl);

    @lightWorld = gui::Canvas();
    vl.append(lightWorld, gui::Size(width*mapscale, height*mapscale));
    lightWorld.size = gui::Size(width*mapscale, height*mapscale);
    lightWorld.setAlignment(0.0, 0.0);
    lightWorld.setCollapsible(true);
    lightWorld.setPosition(0, 0);
    lightWorld.visible = true;

    @darkWorld = gui::Canvas();
    vl.append(darkWorld, gui::Size(width*mapscale, height*mapscale));
    darkWorld.size = gui::Size(width*mapscale, height*mapscale);
    darkWorld.setAlignment(0.0, 0.0);
    darkWorld.setCollapsible(true);
    darkWorld.setPosition(0, 0);
    darkWorld.visible = false;

    @localDot = makeDot(ppu::rgb(0, 0, 0x1f));

    vl.resize();

    window.visible = true;
  }

  void update(const GameState &in local) {
    bool is_dark = local.is_in_dark_world();

    darkWorld.visible = is_dark;
    lightWorld.visible = !is_dark;
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

  void drawMode7Map(gui::Canvas @canvas, const array<uint8> &in tilemap, const array<uint8> &in gfx, const array<uint16> &in palette) {
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

  void horizontalLine(gui::Canvas @c, uint16 color, int x0, int y0, int x1) {
    for (int x = x0; x <= x1; ++x)
      c.pixel(x, y0, color);
  }

  void plot4points(gui::Canvas @c, uint16 color, bool fill, int cx, int cy, int x, int y) {
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

  void circle(gui::Canvas @c, uint16 color, bool fill, int x0, int y0, int radius) {
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

  gui::Canvas @makeDot(uint16 color) {
    int diam = 12;
    int max = diam-1;
    int s = diam/2;

    auto @c = gui::Canvas();
    vl.append(c, gui::Size(diam, diam));
    c.size = gui::Size(diam, diam);
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
      px = p.last_overworld_x;
      py = p.last_overworld_y;
      //x = -128;
      //y = -128;
      //return;
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

  void renderPlayers(const GameState &in local, const array<GameState@> &in players) {
    auto dw = local.is_in_dark_world();

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
      auto @p = players[i];
      if ((p.ttl <= 0) || (p.is_in_dark_world() != dw)) {
        // If player disappeared, hide their dot:
        dots[i].setPosition(-128, -128);
        continue;
      }

      mapCoord(p, x, y);
      dots[i].setPosition(x, y);
    }
  }
};
WorldMap @worldMap;

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
OAMWindow @oamWindow;

class GameSpriteWindow {
  gui::Color clrYellow;
  gui::Color clrDisabled;
  gui::Color clrBlack;

  gui::Window @window;
  array<gui::Label@> col(16);

  GameSpriteWindow() {
    clrYellow   = gui::Color(240, 240,   0);
    clrDisabled = gui::Color( 80,  80,  80);
    clrBlack    = gui::Color(0,0,0);

    int charCount = 34+84;

    @window = gui::Window(300, 240*3, true);
    window.title = "Game Sprites";
    window.backgroundColor = clrBlack;
    window.font = gui::Font("{mono}", 8);
    window.size = gui::Size(8*charCount+10+5, 19*16);

    auto @hl = gui::HorizontalLayout();
      // first label column:
      auto @vl = gui::VerticalLayout();
      for (int j=0; j<16; j++) {
        auto @lbl = gui::Label();
        lbl.foregroundColor = clrYellow;
        lbl.text = fmtHex(j,1)+":";
        vl.append(lbl, gui::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, gui::Size(10, -1));

      // second value column:
      @vl = gui::VerticalLayout();
      col.resize(16);
      for (int j=0; j<16; j++) {
        @col[j] = gui::Label();
        col[j].foregroundColor = clrBlack;
        col[j].backgroundColor = clrDisabled;
        col[j].text = "";
        vl.append(col[j], gui::Size(-1, 0));
      }
      vl.resize();
      hl.append(vl, gui::Size(8*charCount, -1));
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
      auto rgbColor = gui::Color(
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
GameSpriteWindow @gameSpriteWindow;

class Sprite {
  uint8 index;
  uint16 chr;
  int16 x;
  int16 y;
  uint8 size;
  uint8 palette;
  uint8 priority;
  bool hflip;
  bool vflip;

  bool is_enabled;

  // fetches all the OAM sprite data for OAM sprite at `index`
  void fetchOAM(uint8 i) {
    auto tile = ppu::oam[i];

    index    = i;
    chr      = tile.character;
    x        = int16(tile.x);
    y        = int16(tile.y);
    size     = tile.size;
    palette  = tile.palette;
    priority = tile.priority;
    hflip    = tile.hflip;
    vflip    = tile.vflip;

    is_enabled = tile.is_enabled;
  }

  // b0-b3 are main 4 bytes of OAM table
  // b4 is the 5th byte of extended OAM table
  // b4 must be right-shifted to be the two least significant bits and all other bits cleared.
  void decodeOAMTableBytes(uint16 i, uint8 b0, uint8 b1, uint8 b2, uint8 b3, uint8 b4) {
    index    = i;
    x        = b0;
    y        = b1;
    chr      = b2;
    chr      = chr | (uint16(b3 >> 0 & 1) << 8);
    palette  = b3 >> 1 & 7;
    priority = b3 >> 4 & 3;
    hflip    = (b3 >> 6 & 1) != 0 ? true : false;
    vflip    = (b3 >> 7 & 1) != 0 ? true : false;

    x    = (x & 0xff) | (uint16(b4) << 8 & 0x100);
    size = (b4 >> 1) & 1;

    is_enabled = (y != 0xF0);
  }

  void decodeOAMTable(uint16 i) {
    uint8 b0, b1, b2, b3, b4;
    b0 = bus::read_u8(0x7E0800 + (i << 2));
    b1 = bus::read_u8(0x7E0801 + (i << 2));
    b2 = bus::read_u8(0x7E0802 + (i << 2));
    b3 = bus::read_u8(0x7E0803 + (i << 2));
    b4 = bus::read_u8(0x7E0A00 + (i >> 2));
    b4 = (b4 >> ((i&3)<<1)) & 3;
    decodeOAMTableBytes(i, b0, b1, b2, b3, b4);
  }

  void adjustXY(int16 rx, int16 ry) {
    int16 ax = x;
    int16 ay = y;

    // adjust x to allow for slightly off-screen sprites:
    if (ax >= 256) ax -= 512;
    //if (ay + tile.height >= 256) ay -= 256;

    // Make sprite x,y relative to incoming rx,ry coordinates (where Link is in screen coordinates):
    x = ax - rx;
    y = ay - ry;
  }

  void serialize(array<uint8> &r) {
    r.insertLast(index);
    r.insertLast(chr);
    r.insertLast(uint16(x));
    r.insertLast(uint16(y));
    r.insertLast(size);
    r.insertLast(palette);
    r.insertLast(priority);
    r.insertLast(hflip ? uint8(1) : uint8(0));
    r.insertLast(vflip ? uint8(1) : uint8(0));
  }

  int deserialize(array<uint8> &r, int c) {
    index = r[c++];
    chr = uint16(r[c++]) | uint16(r[c++] << 8);
    x = int16(uint16(r[c++]) | uint16(r[c++] << 8));
    y = int16(uint16(r[c++]) | uint16(r[c++] << 8));
    size = r[c++];
    palette = r[c++];
    priority = r[c++];
    hflip = (r[c++] != 0 ? true : false);
    vflip = (r[c++] != 0 ? true : false);
    return c;
  }
};

class Tile {
  uint16 addr;
  array<uint16> tiledata;

  Tile(uint16 addr, array<uint16> tiledata) {
    this.addr = addr;
    this.tiledata = tiledata;
  }
};

// captures local frame state for rendering purposes:
class LocalFrameState {
  // true/false map to determine which local characters are free for replacement in current frame:
  array<bool> chr(512);
  // backup of VRAM tiles overwritten:
  array<Tile@> chr_backup;

  void backup() {
    //message("frame.backup");
    // assume first 0x100 characters are in-use (Link body, sword, shield, weapons, rupees, etc):
    for (uint j = 0; j < 0x100; j++) {
      chr[j] = true;
    }
    for (uint j = 0x100; j < 0x200; j++) {
      chr[j] = false;
    }

    // run through OAM sprites and determine which characters are actually in-use:
    for (uint j = 0; j < 128; j++) {
      Sprite sprite;
      sprite.decodeOAMTable(j);
      // NOTE: we could skip the is_enabled check which would make the OAM appear to be a LRU cache of characters
      //if (!sprite.is_enabled) continue;

      // mark chr as used in current frame:
      uint addr = sprite.chr;
      if (sprite.size == 0) {
        // 8x8 tile:
        chr[addr] = true;
      } else {
        if (addr > 0x1EE) continue;
        // 16x16 tile:
        chr[addr+0x00] = true;
        chr[addr+0x01] = true;
        chr[addr+0x10] = true;
        chr[addr+0x11] = true;
      }
    }
  }

  void overwrite_tile(uint16 addr, array<uint16> tiledata) {
    if (tiledata.length() == 0) {
      message("overwrite_tile: empty tiledata for addr=0x" + fmtHex(addr,4));
      return;
    }

    // read previous VRAM tile:
    array<uint16> backup(16);
    ppu::vram.read_block(addr, 0, 16, backup);

    // overwrite VRAM tile:
    ppu::vram.write_block(addr, 0, 16, tiledata);

    // store backup:
    chr_backup.insertLast(Tile(addr, backup));
  }

  void restore() {
    //message("frame.restore");

    // restore VRAM contents:
    auto len = chr_backup.length();
    for (uint i = 0; i < len; i++) {
      ppu::vram.write_block(
        chr_backup[i].addr,
        0,
        16,
        chr_backup[i].tiledata
      );
    }

    // clear backup of VRAM data:
    chr_backup.resize(0);
  }
};
LocalFrameState localFrameState;

funcdef void ItemModifiedCallback(uint16 offs, uint16 oldValue, uint16 newValue);

// list of SRAM values to sync as items:
class SyncableItem {
  uint16  offs;   // SRAM offset from $7EF000 base address
  uint8   size;   // 1 - byte, 2 - word
  uint8   type;   // 1 - highest wins, 2 - bitfield, 3+ TBD...

  ItemModifiedCallback@ modifiedCallback = null;

  SyncableItem(uint16 offs, uint8 size, uint8 type) {
    this.offs = offs;
    this.size = size;
    this.type = type;
    @this.modifiedCallback = null;
  }

  SyncableItem(uint16 offs, uint8 size, uint8 type, ItemModifiedCallback@ callback) {
    this.offs = offs;
    this.size = size;
    this.type = type;
    @this.modifiedCallback = @callback;
  }

  void modified(uint16 oldValue, uint16 newValue) {
    if (modifiedCallback is null) return;
    modifiedCallback(offs, oldValue, newValue);
  }
};

void LoadShieldGfx(uint16 offs, uint16 oldValue, uint16 newValue) {
  // JSL DecompShieldGfx
  //cpu::call(0x005308);
}

void MoonPearlBunnyLink(uint16 offs, uint16 oldValue, uint16 newValue) {
  // Switch Link's graphics between bunny and regular:
  // FAIL: This doesn't work immediately and instead causes bunny to retain even into light world until dashing.
  //bus::write_u8(0x7E0056, 0);
}

// items MUST be sorted by offs:
array<SyncableItem@> @syncableItems = {
  SyncableItem(0x340, 1, 1),  // bow
  SyncableItem(0x341, 1, 1),  // boomerang
  SyncableItem(0x342, 1, 1),  // hookshot
  //SyncableItem(0x343, 1, 3),  // bombs (TODO)
  SyncableItem(0x344, 1, 1),  // mushroom
  SyncableItem(0x345, 1, 1),  // fire rod
  SyncableItem(0x346, 1, 1),  // ice rod
  SyncableItem(0x347, 1, 1),  // bombos
  SyncableItem(0x348, 1, 1),  // ether
  SyncableItem(0x349, 1, 1),  // quake
  SyncableItem(0x34A, 1, 1),  // lantern
  SyncableItem(0x34B, 1, 1),  // hammer
  SyncableItem(0x34C, 1, 1),  // flute
  SyncableItem(0x34D, 1, 1),  // bug net
  SyncableItem(0x34E, 1, 1),  // book
  //SyncableItem(0x34F, 1, 1),  // have bottles - FIXME: syncing this without bottle contents causes softlock for randomizer
  SyncableItem(0x350, 1, 1),  // cane of somaria
  SyncableItem(0x351, 1, 1),  // cane of byrna
  SyncableItem(0x352, 1, 1),  // magic cape
  SyncableItem(0x353, 1, 1),  // magic mirror
  SyncableItem(0x354, 1, 1),  // gloves
  SyncableItem(0x355, 1, 1),  // boots
  SyncableItem(0x356, 1, 1),  // flippers
  SyncableItem(0x357, 1, 1, @MoonPearlBunnyLink),  // moon pearl
  // 0x358 unused
  SyncableItem(0x359, 1, 1),  // sword
  SyncableItem(0x35A, 1, 1, @LoadShieldGfx),  // shield
  SyncableItem(0x35B, 1, 1),  // armor

  // bottle contents 0x35C-0x35F - TODO: sync bottle contents iff local bottle value == 0x02 (empty)

  SyncableItem(0x364, 1, 2),  // dungeon compasses 1/2
  SyncableItem(0x365, 1, 2),  // dungeon compasses 2/2
  SyncableItem(0x366, 1, 2),  // dungeon big keys 1/2
  SyncableItem(0x367, 1, 2),  // dungeon big keys 2/2
  SyncableItem(0x368, 1, 2),  // dungeon maps 1/2
  SyncableItem(0x369, 1, 2),  // dungeon maps 2/2

  SyncableItem(0x36B, 1, 1),  // heart pieces (out of four)
  SyncableItem(0x36C, 1, 1),  // health capacity

  SyncableItem(0x370, 1, 1),  // bombs capacity
  SyncableItem(0x371, 1, 1),  // arrows capacity

  SyncableItem(0x374, 1, 2),  // pendants
  SyncableItem(0x379, 1, 2),  // player ability flags
  SyncableItem(0x37A, 1, 2),  // crystals

  SyncableItem(0x37B, 1, 1),  // magic usage

  SyncableItem(0x3C5, 1, 1),  // general progress indicator
  SyncableItem(0x3C6, 1, 2),  // progress event flags 1/2
  SyncableItem(0x3C7, 1, 1),  // map icons shown
  SyncableItem(0x3C8, 1, 1),  // start at location… options
  SyncableItem(0x3C9, 1, 2)   // progress event flags 2/2

// NO TRAILING COMMA HERE!
};

class SyncedItem {
  uint16  offs;
  uint16  value;
  uint16  lastValue;
};

// Represents an ALTTP object from 0x10-sized tables at $7E0D00-0FA0:
class GameSprite {
  array<uint8> facts(0x2A);
  uint8 index;

  void readFromBlock(const array<uint8> &in block, uint8 index) {
    this.index = index;

    // copy object facts from the striped contiguous block of RAM:
    uint j = index;
    facts.resize(0x2A);
    for (uint i = 0; i < 0x2A; i++, j += 0x10) {
      facts[i] = block[j];
    }
  }

  void readRAM(uint8 index) {
    this.index = index;

    // copy object facts from the striped contiguous block of RAM:
    uint j = index;
    facts.resize(0x2A);
    for (uint i = 0; i < 0x2A; i++, j += 0x10) {
      facts[i] = bus::read_u8(0x7E0D00 + j);
    }
  }

  void writeRAM() {
    uint j = index;
    for (uint i = 0; i < 0x2A; i++, j += 0x10) {
      bus::write_u8(0x7E0D00 + j, facts[i]);
    }
  }

  uint16 y         { get { return uint16(facts[0x00]) | uint16(facts[0x02] << 8); } };
  uint16 x         { get { return uint16(facts[0x01]) | uint16(facts[0x03] << 8); } };
  uint8  ai        { get { return facts[0x08]; } };         // 0x00 = not spawned, else spawned - used as AI pointer
  uint8  state     {
    get { return facts[0x0D]; }         // valid [0x00..0x0B]; 0x00 = dead/inactive, 0x02 = xform to puff of smoke, 0x0A = carried by Link
    set { facts[0x0D] = value; }
  };
  uint8  type      { get { return facts[0x12]; } };         // valid [0x00..0xF2]; will want to filter for enemies only
  uint8  subtype   { get { return facts[0x13] & 0x1F; } };  // valid [0x00..0x1F]; based on X/Y coordinates
  uint8  oam_count { get { return facts[0x14] & 0x0F; } };  // valid [0x00..0x0F]; count of OAM slots used; 0 means invisible
  uint8  hp        { get { return facts[0x15]; } };
  uint8  hitbox    { get { return facts[0x26] & 0x1F; } };

  bool is_enabled  { get { return state != 0; } };
};

// Represents an ALTTP ancilla object with fields scattered about WRAWM:
const int ancillaeFactsCount1 = 0x20;
const int ancillaeFactsCount2 = 0x16;
class GameAncilla {
  // for all 10 ancillae:
  // $0BF0 = 0x00..0x10
  // $0280 = 0x11..0x15

  // for lowest 5 ancillae indexes only:
  // $0380 = 0x16
  // $0385 = 0x17
  // $038A = 0x18
  // $038F = 0x19
  // $0394 = 0x1A
  // skip $0399 which is special for boomearngs
  // $039F = 0x1B
  // skip $03A4 which is for receiving items
  // $03A9 = 0x1C
  // $03B1 = 0x1D
  // -- $03C4 special for rock debris, maybe bombs
  // $03C5 = 0x1E
  // $03CA = 0x1F

  array<uint8> facts;
  uint8 index;

  int deserialize(const array<uint8> &in r, int c) {
    this.index = r[c++];

    // copy ancilla facts from:
    if (index < 5) {
      facts.resize(ancillaeFactsCount1);
    } else {
      facts.resize(ancillaeFactsCount2);
    }
    for (uint i = 0; i < facts.length(); i++) {
      facts[i] = r[c++];
    }

    return c;
  }

  void serialize(array<uint8> &r) {
    r.insertLast(uint8(index));
    r.insertLast(facts);
  }

  void readRAM(uint8 index) {
    this.index = index;

    if (index < 5) {
      facts.resize(ancillaeFactsCount1);
    } else {
      facts.resize(ancillaeFactsCount2);
    }

    for (uint i = 0, j = index; i < 0x11; i++, j += 0x0A) {
      facts[0x00+i] = bus::read_u8(0x7E0BF0 + j);
    }
    for (uint i = 0, j = index; i < 0x05; i++, j += 0x0A) {
      facts[0x11+i] = bus::read_u8(0x7E0280 + j);
    }

    // first 5 ancillae are special and have more supporting data:
    if (index < 5) {
      facts[0x16] = bus::read_u8(0x7E0380 + index);
      facts[0x17] = bus::read_u8(0x7E0385 + index);
      facts[0x18] = bus::read_u8(0x7E038A + index);
      facts[0x19] = bus::read_u8(0x7E038F + index);
      facts[0x1A] = bus::read_u8(0x7E0394 + index);
      facts[0x1B] = bus::read_u8(0x7E039F + index);
      facts[0x1C] = bus::read_u8(0x7E03A9 + index);
      facts[0x1D] = bus::read_u8(0x7E03B1 + index);
      facts[0x1E] = bus::read_u8(0x7E03C5 + index);
      facts[0x1F] = bus::read_u8(0x7E03CA + index);
    }
  }

  void writeRAM() {
    for (uint i = 0, j = index; i < 0x11; i++, j += 0x0A) {
      bus::write_u8(0x7E0BF0 + j, facts[0x00+i]);
    }
    for (uint i = 0, j = index; i < 0x05; i++, j += 0x0A) {
      bus::write_u8(0x7E0280 + j, facts[0x11+i]);
    }
    if (index < 5) {
      bus::write_u8(0x7E0380 + index, facts[0x16]);
      bus::write_u8(0x7E0385 + index, facts[0x17]);
      bus::write_u8(0x7E038A + index, facts[0x18]);
      bus::write_u8(0x7E038F + index, facts[0x19]);
      bus::write_u8(0x7E0394 + index, facts[0x1A]);
      bus::write_u8(0x7E039F + index, facts[0x1B]);
      bus::write_u8(0x7E03A9 + index, facts[0x1C]);
      bus::write_u8(0x7E03B1 + index, facts[0x1D]);
      bus::write_u8(0x7E03C5 + index, facts[0x1E]);
      bus::write_u8(0x7E03CA + index, facts[0x1F]);
    }
  }

  //uint16 y         { get { return uint16(facts[0x01]) | uint16(facts[0x03] << 8); } };
  //uint16 x         { get { return uint16(facts[0x02]) | uint16(facts[0x04] << 8); } };
  uint8  type      { get { return facts[0x09]; } };
  //uint8  oam_index { get { return facts[0x0F]; } };
  //uint8  oam_count { get { return facts[0x10]; } };

  bool is_enabled  { get { return type != 0; } };

  // Determine if this ancilla should be synced based on its type:
  bool is_syncable() {
    uint8 t = type;

    // 0x00 - Nothing - means slot is unused
    if (t == 0x00) return true;

    // 0x01 - Somarian Blast; Results from splitting a Somarian Block
    if (t == 0x01) return true;
    // 0x02 - Fire Rod Shot
    if (t == 0x02) return true;
    // 0x03 - Unused; Instantiating one of these creates an object that does nothing.
    // 0x04 - Beam Hit; Master sword beam or Somarian Blast dispersing after hitting something
    // 0x05 - Boomerang
    if (t == 0x05) return true;
    // 0x06 - Wall Hit; Spark-like effect that occurs when you hit a wall with a boomerang or hookshot
    if (t == 0x06) return true;
    // 0x07 - Bomb; Normal bombs laid by the player
    if (t == 0x07) return true;
    // 0x08 - Door Debris; Rock fall effect from bombing a cracked cave or dungeon wall
    if (t == 0x08) return true;
    // 0x09 - Arrow; Fired from the player's bow
    if (t == 0x09) return true;
    // 0x0A - Halted Arrow; Player's arrow that is stuck in something (wall or sprite)
    if (t == 0x0A) return true;
    // 0x0B - Ice Rod Shot
    if (t == 0x0B) return true;
    // 0x0C - Sword Beam
    //if (t == 0x0C) return true;
    // 0x0D - Sword Full Charge Spark; The sparkle that briefly appears at the tip of the player's sword when their spin attack fully charges up.
    //if (t == 0x0D) return true;
    // 0x0E - Unused; Duplicate of the Blast Wall
    // 0x0F - Unused; Duplicate of the Blast Wall
    
    // 0x10 - Unused; Duplicate of the Blast Wall
    // 0x11 - Ice Shot Spread; Ice shot dispersing after hitting something.
    if (t == 0x11) return true;
    // 0x12 - Unused; Duplicate of the Blast Wall
    // 0x13 - Ice Shot Sparkle; The only actually visible parts of the ice shot.
    if (t == 0x13) return true;
    // 0x14 - Unused; Don't use as it will crash the game.
    // 0x15 - Jump Splash; Splash from the player jumping into or out of deep water
    if (t == 0x15) return true;
    // 0x16 - The Hammer's Stars / Stars from hitting hard ground with the shovel
    if (t == 0x16) return true;
    // 0x17 - Dirt from digging a hole with the shovel
    if (t == 0x17) return true;
    // 0x18 - The Ether Effect
    //if (t == 0x18) return true;
    // 0x19 - The Bombos Effect
    //if (t == 0x19) return true;
    // 0x1A - Precursor to torch flame / Magic powder
    if (t == 0x1A) return true;
    // 0x1B - Sparks from tapping a wall with your sword
    if (t == 0x1B) return true;
    // 0x1C - The Quake Effect
    // BREAKS TILEMAP AND VRAM!!!
    //if (t == 0x1C) return true;
    // 0x1D - Jarring effect from hitting a wall while dashing
    // 0x1E - Pegasus boots dust flying
    if (t == 0x1E) return true;
    // 0x1F - Hookshot
    // Messed up graphics
    //if (t == 0x1F) return true;
    
    // 0x20 - Link's Bed Spread
    // 0x21 - Link's Zzzz's from sleeping
    // 0x22 - Received Item Sprite
    // 0x23 - Bunny / Cape transformation poof
    // 0x24 - Gravestone sprite when in motion
    if (t == 0x24) return true;
    // 0x25 - 
    // 0x26 - Sparkles when swinging lvl 2 or higher sword
    //if (t == 0x26) return true;
    // 0x27 - the bird (when called by flute)
    if (t == 0x27) return true;
    // 0x28 - item sprite that you throw into magic faerie ponds.
    if (t == 0x28) return true;
    // 0x29 - Pendants and crystals
    if (t == 0x29) return true;
    // 0x2A - Start of spin attack sparkle
    // 0x2B - During Spin attack sparkles
    // 0x2C - Cane of Somaria blocks
    if (t == 0x2C) return true;
    // 0x2D - 
    // 0x2E - ????
    // 0x2F - Torch's flame
    if (t == 0x2F) return true;

    // 0x30 - Initial spark for the Cane of Byrna activating
    // 0x31 - Cane of Byrna spinning sparkle
    // 0x32 - Flame blob, possibly from wall explosion
    // 0x33 - Series of explosions from blowing up a wall (after pulling a switch)
    if (t == 0x33) return true;
    // 0x34 - Burning effect used to open up the entrance to skull woods.
    // 0x35 - Master Sword ceremony.... not sure if it's the whole thing or a part of it
    // 0x36 - Flute that pops out of the ground in the haunted grove.
    // 0x37 - Appears to trigger the weathervane explosion.
    // 0x38 - Appears to give Link the bird enabled flute.
    // 0x39 - Cane of Somaria blast which creates platforms (sprite 0xED)
    // 0x3A - super bomb explosion (also does things normal bombs can)
    if (t == 0x3A) return true;
    // 0x3B - Unused hit effect. Looks similar to Somaria block being nulled out.
    // 0x3C - Sparkles from holding the sword out charging for a spin attack.
    // 0x3D - splash effect when things fall into the water
    if (t == 0x3D) return true;
    // 0x3E - 3D crystal effect (or transition into 3D crystal?)
    // 0x3F - Disintegrating bush poof (due to magic powder)
    if (t == 0x3F) return true;

    // 0x40 - Dwarf transformation cloud
    // 0x41 - Water splash in the waterfall of wishing entrance (and swamp palace)
    if (t == 0x41) return true;
    // 0x42 - Rupees that you throw in to the Pond of Wishing
    if (t == 0x42) return true;
    // 0x43 - Ganon's Tower seal being broken. (not opened up though!)                

    return false;
  }
};

// TODO: debug window to show current full area and place GameSprites on it with X,Y coordinates

class GameState {
  int ttl;        // time to live for last update packet
  int index = -1; // player index in server's array (local is always -1)

  // graphics data for current frame:
  array<Sprite@> sprites;
  array<array<uint16>> chrs(512);
  // lookup remote chr number to find local chr number mapped to:
  array<uint16> reloc(512);

  // $3D9-$3E4: 6x uint16 characters for player name
  array<uint16> name(6);

  // local: player index last synced objects from:
  uint16 objects_index_source;

  // values copied from RAM:
  uint8  frame;
  uint32 location;
  uint32 last_location;

  // screen scroll coordinates relative to top-left of room (BG screen):
  int16 xoffs;
  int16 yoffs;

  uint16 x, y;

  uint8 module;
  uint8 sub_module;
  uint8 sub_sub_module;

  uint8 sfx1;
  uint8 sfx2;

  bool is_in_dark_world() const {
    return (location & 0x020000) == 0x020000;
  }

  bool is_in_dungeon() const {
    return (location & 0x010000) == 0x010000;
  }

  bool is_it_a_bad_time() const {
    if (module <= 0x05) return true;
    if (module >= 0x14 && module <= 0x18) return true;
    if (module >= 0x1B) return true;

    if (module == 0x0e) {
      if ( sub_module == 0x07 // mode-7 map
           || sub_module == 0x0b // player select
        ) {
        return true;
      }
    }

    return false;
  }

  bool can_see(uint32 other_location) const {
    if (is_it_a_bad_time()) return false;
    return (location == other_location);
  }

  bool can_sample_location() const {
    switch (module) {
      // dungeon:
      case 0x07:
        // climbing/descending stairs
        if (sub_module == 0x0e) {
          // once main climb animation finishes, sample new location:
          if (sub_sub_module > 0x02) {
            return true;
          }
          // continue sampling old location:
          return false;
        }
        return true;
      case 0x09:  // overworld
        // normal mirror is 0x23
        // mirror fail back to dark world is 0x2c
        if (sub_module == 0x23 || sub_module == 0x2c) {
          // once sub-sub module hits 3 then we are in light world
          if (sub_sub_module < 0x03) {
            return false;
          }
        }
        return true;
      case 0x0e:  // dialogs, maps etc.
        if (sub_module == 0x07) {
          // in-game mode7 map:
          return false;
        }
        return true;
      case 0x06:  // enter cave from overworld?
      case 0x0b:  // overworld master sword grove / zora waterfall
      case 0x08:  // exit cave to overworld
      case 0x0f:  // closing spotlight
      case 0x10:  // opening spotlight
      case 0x11:  // falling / fade out?
      case 0x12:  // death
      default:
        return true;
    }
    return true;
  }

  void fetch_module() {
    // 0x00 - Triforce / Zelda startup screens
    // 0x01 - File Select screen
    // 0x02 - Copy Player Mode
    // 0x03 - Erase Player Mode
    // 0x04 - Name Player Mode
    // 0x05 - Loading Game Mode
    // 0x06 - Pre Dungeon Mode
    // 0x07 - Dungeon Mode
    // 0x08 - Pre Overworld Mode
    // 0x09 - Overworld Mode
    // 0x0A - Pre Overworld Mode (special overworld)
    // 0x0B - Overworld Mode (special overworld)
    // 0x0C - ???? I think we can declare this one unused, almost with complete certainty.
    // 0x0D - Blank Screen
    // 0x0E - Text Mode/Item Screen/Map
    // 0x0F - Closing Spotlight
    // 0x10 - Opening Spotlight
    // 0x11 - Happens when you fall into a hole from the OW.
    // 0x12 - Death Mode
    // 0x13 - Boss Victory Mode (refills stats)
    // 0x14 - Attract Mode
    // 0x15 - Module for Magic Mirror
    // 0x16 - Module for refilling stats after boss.
    // 0x17 - Quitting mode (save and quit)
    // 0x18 - Ganon exits from Agahnim's body. Chase Mode.
    // 0x19 - Triforce Room scene
    // 0x1A - End sequence
    // 0x1B - Screen to select where to start from (House, sanctuary, etc.)
    module = bus::read_u8(0x7E0010);

    // when module = 0x07: dungeon
    //    sub_module = 0x00 normal gameplay in dungeon
    //               = 0x01 going through door
    //               = 0x03 triggered a star tile to change floor hole configuration
    //               = 0x05 initializing room? / locked doors?
    //               = 0x07 falling down hole in floor
    //               = 0x0e going up/down stairs
    //               = 0x0f entering dungeon first time (or from mirror)
    //               = 0x16 when orange/blue barrier blocks transition
    //               = 0x19 when using mirror
    // when module = 0x09: overworld
    //    sub_module = 0x00 normal gameplay in overworld
    //               = 0x0e
    //      sub_sub_module = 0x01 in item menu
    //                     = 0x02 in dialog with NPC
    //               = 0x23 transitioning from light world to dark world or vice-versa
    // when module = 0x12: Link is dying
    //    sub_module = 0x00
    //               = 0x02 bonk
    //               = 0x03 black oval closing in
    //               = 0x04 red screen and spinning animation
    //               = 0x05 red screen and Link face down
    //               = 0x06 fade to black
    //               = 0x07 game over animation
    //               = 0x08 game over screen done
    //               = 0x09 save and continue menu
    sub_module = bus::read_u8(0x7E0011);

    // sub-sub-module goes from 01 to 0f during special animations such as link walking up/down stairs and
    // falling from ceiling and used as a counter for orange/blue barrier blocks transition going up/down
    sub_sub_module = bus::read_u8(0x7E00B0);
  }

  uint8 in_dark_world;
  uint8 in_dungeon;
  uint16 overworld_room;
  uint16 dungeon_room;

  uint16 last_overworld_x;
  uint16 last_overworld_y;

  void fetch() {
    // read frame counter (increments from 00 to FF and wraps around):
    frame = bus::read_u8(0x7E001A);

    if (is_it_a_bad_time()) {
      if (!can_sample_location()) {
        x = 0xFFFF;
        y = 0xFFFF;
      }
      return;
    }

    // $7E0410 = OW screen transitioning directional
    //ow_screen_transition = bus::read_u8(0x7E0410);

    // Don't update location until screen transition is complete:
    if (can_sample_location()) {
      last_location = location;

      // fetch various room indices and flags about where exactly Link currently is:
      in_dark_world = bus::read_u8(0x7E0FFF);
      in_dungeon = bus::read_u8(0x7E001B);
      overworld_room = bus::read_u16(0x7E008A);
      dungeon_room = bus::read_u16(0x7E00A0);

      // compute aggregated location for Link into a single 24-bit number:
      location =
        uint32(in_dark_world & 1) << 17 |
        uint32(in_dungeon & 1) << 16 |
        uint32(in_dungeon != 0 ? dungeon_room : overworld_room);

      // clear out list of room changes if location changed:
      if (last_location != location) {
        message("room from 0x" + fmtHex(last_location, 6) + " to 0x" + fmtHex(location, 6));
        // when moving from overworld to dungeon, track last overworld location:
        if ((last_location & (1 << 16)) < (location & (1 << 16))) {
          last_overworld_x = x;
          last_overworld_y = y;
        }
      }
    }

    // TODO: read player name from SRAM
    //name = bus::read_block_u8(0x7EF3D9);
    // TODO: copy player name to Settings window
    // TODO: allow settings window to rename player and write back to SRAM

    y = bus::read_u16(0x7E0020);
    x = bus::read_u16(0x7E0022);

    // get screen x,y offset by reading BG2 scroll registers:
    xoffs = int16(bus::read_u16(0x7E00E2)) - int16(bus::read_u16(0x7E011A));
    yoffs = int16(bus::read_u16(0x7E00E8)) - int16(bus::read_u16(0x7E011C));

/*
    if (!intercepting) {
      bus::add_write_interceptor("7e:2000-bfff", 0, bus::WriteInterceptCallback(this.mem_written));
      bus::add_write_interceptor("00-3f,80-bf:2100-213f", 0, bus::WriteInterceptCallback(this.ppu_written));
      cpu::register_dma_interceptor(cpu::DMAInterceptCallback(this.dma_intercept));
      intercepting = true;
    }
*/

    fetch_items();

    fetch_sprites();

    fetch_objects();

    fetch_ancillae();

    fetch_tilemap_changes();

    fetch_rooms();
  }

  void fetch_sfx() {
    if (is_it_a_bad_time()) {
      sfx1 = 0;
      sfx2 = 0;
      return;
    }

    // NOTE: sfx are 6-bit values with top 2 MSBs indicating panning:
    //   00 = center, 01 = right, 10 = left, 11 = left

    uint8 lfx1 = bus::read_u8(0x7E012E);
    // filter out unwanted synced sounds:
    switch (lfx1) {
      case 0x2B: break; // low life warning beep
      default:
        sfx1 = lfx1;
    }

    uint8 lfx2 = bus::read_u8(0x7E012F);
    // filter out unwanted synced sounds:
    switch (lfx2) {
      case 0x0C: break; // text scrolling flute noise
      case 0x10: break; // switching to map sound effect
      case 0x11: break; // menu screen going down
      case 0x12: break; // menu screen going up
      case 0x20: break; // switch menu item
      case 0x24: break; // switching between different mode 7 map perspectives
      default:
        sfx2 = lfx2;
    }
  }

  array<SyncedItem@> items;
  void fetch_items() {
    // items: (MUST be sorted by offs)
    items.resize(syncableItems.length());
    for (uint i = 0; i < syncableItems.length(); i++) {
      auto @syncable = syncableItems[i];

      auto @item = items[i];
      if (@item == null) {
        @item = @items[i] = SyncedItem();
        item.lastValue = 0;
        item.value = 0;
        item.offs = syncable.offs;
      }

      // record previous frame's value:
      item.lastValue = item.value;

      // read latest value:
      if (syncable.size == 1) {
        item.value = bus::read_u8(0x7EF000 + syncable.offs);
      } else if (syncable.size == 2) {
        item.value = bus::read_u16(0x7EF000 + syncable.offs);
      }
      //if (item.value != item.lastValue) {
      //  message("local[" + fmtHex(item.offs, 3) + "]=" + fmtHex(item.value, 4));
      //}
    }
  }

  array<GameSprite@> objects(0x10);
  array<uint8> objectsBlock(0x2A0);
  void fetch_objects() {
    // $7E0D00 - $7E0FA0
    uint i = 0;

    bus::read_block_u8(0x7E0D00, 0, 0x2A0, objectsBlock);
    for (i = 0; i < 0x10; i++) {
      auto @en = @objects[i];
      if (@en is null) {
        @en = @objects[i] = GameSprite();
      }
      // copy in facts about each enemy from the large block of WRAM:
      objects[i].readFromBlock(objectsBlock, i);
    }
  }

  array<uint16> rooms;
  void fetch_rooms() {
    // SRAM copy at $7EF000 - $7EF24F
    // room data live in WRAM at $0400,$0401
    // $0403 = 6 chests, key, heart piece

    // BUGS: encountered one-way door effect in fairy cave 0x010008
    // disabling room door sync for now.

    //rooms.resize(0x128);
    //bus::read_block_u16(0x7EF000, 0, 0x128, rooms);
  }

/*
  void mem_written(uint32 addr, uint8 value) {
    message("wram[0x" + fmtHex(addr, 6) + "] = 0x" + fmtHex(value, 2));
  }

  uint8 vmaddrl, vmaddrh;

  void ppu_written(uint32 addr, uint8 value) {
    //message(" ppu[0x__" + fmtHex(addr, 4) + "] = 0x" + fmtHex(value, 2));
    if (addr == 0x2116) vmaddrl = value;
    else if (addr == 0x2117) vmaddrh = value;
  }

  void dma_intercept(cpu::DMAIntercept @dma) {
    uint16 vmaddr = 0;
    // writing to 0x2118 (VMDATAL)
    if (dma.direction == 0 && dma.targetAddress == 0x18) {
      // ignore writes to BG and sprite tiles:
      if (vmaddrh >= 0x30) return;
      // compute vmaddr:
      vmaddr = uint16(vmaddrl) | (uint16(vmaddrh) << 8);
    }
    // ignore OAM sync:
    if (dma.direction == 0 && dma.targetAddress == 0x04) {
      return;
    }

    uint32 addr = uint32(dma.sourceBank) << 16 | uint32(dma.sourceAddress);

    string d = "...";
    if (dma.direction == 0 && dma.transferSize <= 0x20) {
      // from A bus to B bus:
      array<uint16> data;
      uint words = dma.transferSize >> 1;
      data.resize(words);
      bus::read_block_u16(addr, 0, words, data);

      d = "";
      for (uint i = 0; i < words; i++) {
        d += "0x" + fmtHex(data[i], 4);
        if (i < words - 1) d += ",";
      }
    }

    message(
      "dma[" + fmtInt(dma.channel) +
      (dma.direction == 0 ? "] to 0x21" : "] from 0x21") + fmtHex(dma.targetAddress, 2) +
      (dma.targetAddress == 0x18 ? " (vram 0x" + fmtHex(vmaddr, 4) + ")" : "") +
      (dma.direction == 0 ? " from 0x" : " to 0x") + fmtHex(addr, 6) +
      " size 0x" + fmtHex(dma.transferSize, 4) +
      " = {" + d + "}"
    );
  }
*/

  int numsprites;
  void fetch_sprites() {
    numsprites = 0;
    sprites.resize(0);
    if (is_it_a_bad_time()) {
      return;
    }

    // get link's on-screen coordinates in OAM space:
    int16 rx = int16(x) - xoffs;
    int16 ry = int16(y) - yoffs;

    // read OAM offset where link's sprites start at:
    int link_oam_start = bus::read_u16(0x7E0352) >> 2;
    //message(fmtInt(link_oam_start));

    // read in relevant sprites from OAM and VRAM:
    sprites.reserve(128);

    // start from reserved region for Link (either at 0x64 or ):
    for (int j = 0; j < 0x0C; j++) {
      auto i = (link_oam_start + j) & 0x7F;

      // fetch ALTTP's copy of the OAM sprite data from WRAM:
      Sprite sprite;
      sprite.decodeOAMTable(i);

      // skip OAM sprite if not enabled (X, Y coords are out of display range):
      if (!sprite.is_enabled) continue;

      //message("[" + fmtInt(sprite.index) + "] " + fmtInt(sprite.x) + "," + fmtInt(sprite.y) + "=" + fmtInt(sprite.chr));

      sprite.adjustXY(rx, ry);

      // append the sprite to our array:
      sprites.resize(++numsprites);
      @sprites[numsprites-1] = sprite;
    }

    /*
    // capture effects sprites:
    for (int i = 0x00; i <= 0x7f; i++) {
      // skip already synced Link sprites:
      if ((i >= link_oam_start) && (i <= link_oam_start + 0x0C)) continue;

      // fetch ALTTP's copy of the OAM sprite data from WRAM:
      Sprite spr, sprp1, sprp2, sprn1, sprn2;
      // current sprite:
      spr.decodeOAMTable(i);
      // prev 2 sprites:
      if (i >= 1) {
        sprp1.decodeOAMTable(i - 1);
      }
      if (i >= 2) {
        sprp2.decodeOAMTable(i - 2);
      }
      // next 2 sprites:
      if (i <= 0x7E) {
        sprn1.decodeOAMTable(i + 1);
      }
      if (i <= 0x7D) {
        sprn2.decodeOAMTable(i + 2);
      }

      // skip OAM sprite if not enabled (X, Y coords are out of display range):
      if (!spr.is_enabled) continue;

      auto chr = spr.chr;
      if (chr >= 0x100) continue;

      bool fx = (
        // sparkles around sword spin attack AND magic boomerang:
        chr == 0x80 || chr == 0x81 || chr == 0x82 || chr == 0x83 || chr == 0xb7 ||
        // exclusively for spin attack:
        chr == 0x8c || chr == 0x93 || chr == 0xd6 || chr == 0xd7 ||  // chr == 0x92 is also used here
        // sword tink on hard tile when poking:
        chr == 0x90 || chr == 0x92 || chr == 0xb9 ||
        // dash dust
        chr == 0xa9 || chr == 0xcf || chr == 0xdf ||
        // bush leaves
        chr == 0x59 ||
        // item rising from opened chest
        chr == 0x24
      );
      bool weapons = (
        // arrows
        chr == 0x2a || chr == 0x2b || chr == 0x2c || chr == 0x2d ||
        chr == 0x3a || chr == 0x3b || chr == 0x3c || chr == 0x3d ||
        // hookshot
        chr == 0x09 || chr == 0x19 || chr == 0x1a ||
        // boomerang
        chr == 0x26 ||
        // magic powder
        chr == 0x09 || chr == 0x0a ||
        // lantern fire
        chr == 0xe3 || chr == 0xf3 || chr == 0xa4 || chr == 0xa5 || chr == 0xb2 || chr == 0xb3 || chr == 0x9c ||
        // fire rod
        chr == 0x09 || chr == 0x9c || chr == 0x9d || chr == 0x8d || chr == 0x8e || chr == 0xa0 || chr == 0xa2 ||
        chr == 0xa4 || chr == 0xa5 ||
        // ice rod
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0xb6 || chr == 0xb7 || chr == 0x80 || chr == 0x83 ||
        chr == 0xcf || chr == 0xdf ||
        // hammer
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0x91 ||
        // cane of somaria
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0xe9 ||
        // cane of bryna
        chr == 0x09 || chr == 0x19 || chr == 0x1a || chr == 0x92 || chr == 0xd6 || chr == 0x8c || chr == 0x93 ||
        chr == 0xd7 || chr == 0xb7 || chr == 0x80 || chr == 0x83 ||
        // magic cape
        chr == 0x86 || chr == 0xa9 || chr == 0x9b ||
        // quake & ether:
        chr == 0x40 || chr == 0x42 || chr == 0x44 || chr == 0x46 || chr == 0x48 || chr == 0x4a || chr == 0x4c || chr == 0x4e ||
        chr == 0x60 || chr == 0x62 || chr == 0x63 || chr == 0x64 || chr == 0x66 || chr == 0x68 || chr == 0x6a ||
        // bombs:
        chr == 0x6e ||
        // 8 count:
        chr == 0x79 ||
        // push block
        chr == 0x0c ||
        // large stone
        chr == 0x4a ||
        // holding pot / bush or small stone or sign
        chr == 0x46 || chr == 0x44 || chr == 0x42 ||
        // shadow underneath pot / bush or small stone
        (i >= 1 && (sprp1.chr == 0x46 || sprp1.chr == 0x44 || sprp1.chr == 0x42) && chr == 0x6c) ||
        // pot shards or stone shards (large and small)
        chr == 0x58 || chr == 0x48
      );
      bool bombs = (
        // explosion:
        chr == 0x84 || chr == 0x86 || chr == 0x88 || chr == 0x8a || chr == 0x8c || chr == 0x9b ||
        // bomb and its shadow:
        (i <= 125 && chr == 0x6e && sprn1.chr == 0x6c && sprn2.chr == 0x6c) ||
        (i >= 1 && sprp1.chr == 0x6e && chr == 0x6c && sprn1.chr == 0x6c) ||
        (i >= 2 && sprp2.chr == 0x6e && sprp1.chr == 0x6c && chr == 0x6c)
      );
      bool follower = (
        chr == 0x20 || chr == 0x22
      );

      // skip OAM sprites that are not related to Link:
      if (!(fx || weapons || bombs || follower)) continue;

      spr.adjustXY(rx, ry);

      // append the sprite to our array:
      sprites.resize(++numsprites);
      @sprites[numsprites-1] = spr;
    }
    */
  }

  void capture_sprites_vram() {
    for (int i = 0; i < numsprites; i++) {
      auto @spr = @sprites[i];
      capture_sprite(spr);
    }
  }

  void capture_sprite(Sprite &sprite) {
    //message("capture_sprite " + fmtInt(sprite.index));
    // load character(s) from VRAM:
    if (sprite.size == 0) {
      // 8x8 sprite:
      //message("capture  x8 CHR=" + fmtHex(sprite.chr, 3));
      if (chrs[sprite.chr].length() == 0) {
        chrs[sprite.chr].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr), 0, 16, chrs[sprite.chr]);
      }
    } else {
      // 16x16 sprite:
      //message("capture x16 CHR=" + fmtHex(sprite.chr, 3));
      if (chrs[sprite.chr + 0x00].length() == 0) {
        chrs[sprite.chr + 0x00].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x00), 0, 16, chrs[sprite.chr + 0x00]);
      }
      if (chrs[sprite.chr + 0x01].length() == 0) {
        chrs[sprite.chr + 0x01].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x01), 0, 16, chrs[sprite.chr + 0x01]);
      }
      if (chrs[sprite.chr + 0x10].length() == 0) {
        chrs[sprite.chr + 0x10].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x10), 0, 16, chrs[sprite.chr + 0x10]);
      }
      if (chrs[sprite.chr + 0x11].length() == 0) {
        chrs[sprite.chr + 0x11].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x11), 0, 16, chrs[sprite.chr + 0x11]);
      }
    }
  }

  uint16 tilemapCount;
  array<uint16> tilemapAddress;
  array<uint16> tilemapTile;
  void fetch_tilemap_changes() {
    tilemapCount = 0;
    tilemapAddress.resize(0);
    tilemapTile.resize(0);
    if (is_it_a_bad_time()) {
      return;
    }

    // overworld only for the moment:
    if (is_in_dungeon()) {
      return;
    }
    if (local.module == 0x09) {
      // don't fetch tilemap during screen transition:
      if (local.sub_module >= 0x01 && local.sub_module < 0x07) {
        return;
      }
      // during LW/DW transition:
      if (local.sub_module >= 0x23) {
        return;
      }
    }

    // 0x7E04AC : word        = pointer to end of array (in bytes)
    tilemapCount = bus::read_u16(0x7E04AC) >> 1;

    // 0x7EF800 : array[word] = tilemap address for changed tile
    tilemapAddress.resize(tilemapCount);
    bus::read_block_u16(0x7EF800, 0, tilemapCount, tilemapAddress);

    // 0x7EFA00 : array[word] = tilemap tile number
    tilemapTile.resize(tilemapCount);
    bus::read_block_u16(0x7EFA00, 0, tilemapCount, tilemapTile);
  }

  array<int> ancillaeOwner;
  array<GameAncilla@> ancillae;
  void fetch_ancillae() {
    // initialize owner array with -1 for no owner:
    if (ancillaeOwner.length() == 0) {
      ancillaeOwner.resize(0x0A);
      for (uint i = 0; i < 0x0A; i++) {
        ancillaeOwner[i] = -1;
      }
    }

    // initialize array of ancillae:
    if (ancillae.length() == 0) {
      ancillae.resize(0x0A);
      for (uint i = 0; i < 0x0A; i++) {
        @ancillae[i] = @GameAncilla();
      }
    }

    // update ancillae array from WRAM:
    for (uint i = 0; i < 0x0A; i++) {
      ancillae[i].readRAM(i);

      // Update ownership:
      if (ancillaeOwner[i] == index) {
        if (ancillae[i].type == 0) {
          ancillaeOwner[i] = -2;
        }
      } else if (ancillaeOwner[i] == -1) {
        if (ancillae[i].type != 0) {
          ancillaeOwner[i] = local.index;
        }
      } else if (ancillaeOwner[i] == -2) {
        ancillaeOwner[i] = -1;
      }
    }
  }

  array<uint8> @create_envelope(uint8 kind) {
    array<uint8> @envelope = {};

    // server envelope:
    {
      // header:
      envelope.insertLast(uint16(25887));
      // server protocol 2:
      envelope.insertLast(uint8(0x02));
      // group name: (20 bytes exactly)
      envelope.insertLast(settings.Group);
      // message kind:
      envelope.insertLast(kind);
      // what we think our index is:
      envelope.insertLast(uint16(index));
    }

    // script protocol 0x01:
    envelope.insertLast(uint8(0x01));

    // protocol starts with frame number to correlate them together:
    envelope.insertLast(frame);

    return envelope;
  }

  void send_packet(array<uint8> &in envelope) {
    if (envelope.length() > 1452) {
      message("packet too big to send! " + fmtInt(envelope.length()));
      return;
    }

    // send packet to server:
    //message("sent " + fmtInt(envelope.length()) + " bytes");
    sock.send(0, envelope.length(), envelope);
  }

  void send() {
    // check if we need to detect our local index:
    if (local.index == -1) {
      // request our index; receive() will take care of the response:
      array<uint8> request = create_envelope(0x00);
      send_packet(request);
    }

    // send main packet:
    {
      // build server envelope:
      array<uint8> envelope = create_envelope(0x01);

      // append local state to remote player:
      serialize_location(envelope);
      serialize_sfx(envelope);
      serialize_sprites(envelope);
      serialize_chr0(envelope);

      send_packet(envelope);
    }

    // send another packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      // send chr0 to remote player:
      serialize_items(envelope);
      serialize_objects(envelope);
      serialize_ancillae(envelope);

      send_packet(envelope);
    }

/*
    // send another packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      // send chr1 to remote player:
      serialize_chr1(envelope);

      send_packet(envelope);
    }
*/

    // send another packet:
    {
      array<uint8> envelope = create_envelope(0x01);

      // append local state to remote player:
      serialize_tilemaps(envelope);

      send_packet(envelope);
    }
  }

  void serialize_location(array<uint8> &r) {
    r.insertLast(uint8(0x01));

    r.insertLast(module);
    r.insertLast(sub_module);
    r.insertLast(sub_sub_module);

    r.insertLast(location);

    r.insertLast(x);
    r.insertLast(y);

    r.insertLast(last_overworld_x);
    r.insertLast(last_overworld_y);
  }

  void serialize_sfx(array<uint8> &r) {
    r.insertLast(uint8(0x02));

    r.insertLast(sfx1);
    r.insertLast(sfx2);
  }

  void serialize_sprites(array<uint8> &r) {
    r.insertLast(uint8(0x03));

    r.insertLast(uint8(sprites.length()));

    //message("serialize: numsprites = " + fmtInt(sprites.length()));
    // sort 16x16 sprites first so that 8x8 can fit within them if needed (fixes shadows under thrown items):
    for (uint i = 0; i < sprites.length(); i++) {
      if (sprites[i].size == 0) continue;
      sprites[i].serialize(r);
    }
    for (uint i = 0; i < sprites.length(); i++) {
      if (sprites[i].size != 0) continue;
      sprites[i].serialize(r);
    }
  }

  void serialize_chr0(array<uint8> &r) {
    // how many distinct characters:
    uint16 chr_count = 0;
    for (uint16 i = 0; i < 0x100; i++) {
      if (chrs[i].length() == 0) continue;
      ++chr_count;
    }

    //message("serialize: chr0="+fmtInt(chr_count));
    r.insertLast(uint8(0x04));

    // emit how many chrs:
    r.insertLast(uint8(chr_count));
    for (uint16 i = 0; i < 0x100; ++i) {
      if (chrs[i].length() == 0) continue;

      // which chr is it:
      r.insertLast(uint8(i));
      // emit the tile data:
      r.insertLast(chrs[i]);

      // clear the chr tile data for next frame:
      chrs[i].resize(0);
    }
  }

  void serialize_chr1(array<uint8> &r) {
    // how many distinct characters:
    uint16 chr_count = 0;
    for (uint16 i = 0x100; i < 0x200; i++) {
      if (chrs[i].length() == 0) continue;
      ++chr_count;
    }

    //message("serialize: chr1="+fmtInt(chr_count));
    r.insertLast(uint8(0x05));

    // emit how many chrs:
    r.insertLast(uint8(chr_count));
    for (uint16 i = 0x100; i < 0x200; ++i) {
      if (chrs[i].length() == 0) continue;

      // which chr is it:
      r.insertLast(uint8(i - 0x100));
      // emit the tile data:
      r.insertLast(chrs[i]);

      // clear the chr tile data for next frame:
      chrs[i].resize(0);
    }
  }

  void serialize_items(array<uint8> &r) {
    r.insertLast(uint8(0x06));

    // items: (MUST be sorted by offs)
    //message("serialize: items="+fmtInt(items.length()));
    r.insertLast(uint8(items.length()));
    for (uint8 i = 0; i < items.length(); i++) {
      auto @item = items[i];
      // NOTE if @item == null a null exception will occur which is better to know about than to ignore.

      // possible offsets are between 0x340 to 0x406 max, so subtract 0x340 to get a single byte between 0x00 and 0xC6
      r.insertLast(uint8(items[i].offs - 0x340));
      r.insertLast(items[i].value);
    }
  }

  void serialize_tilemaps(array<uint8> &r) {
    r.insertLast(uint8(0x07));

    //message("serialize: tilemap="+fmtInt(tilemapCount));
    r.insertLast(tilemapCount);
    r.insertLast(tilemapAddress);
    r.insertLast(tilemapTile);
  }

  void serialize_objects(array<uint8> &r) {
    r.insertLast(uint8(0x08));

    // 0x2A0 bytes
    r.insertLast(objectsBlock);
  }

  void serialize_ancillae(array<uint8> &r) {
    if (ancillaeOwner.length() == 0) return;
    if (ancillae.length() == 0) return;

    r.insertLast(uint8(0x09));

    uint8 count = 0;
    for (uint i = 0; i < 0x0A; i++) {
      if (ancillaeOwner[i] != index && ancillaeOwner[i] != -1) continue;
      if (!ancillae[i].is_syncable()) continue;

      count++;
    }

    // count of active+owned ancillae:
    r.insertLast(count);
    for (uint i = 0; i < 0x0A; i++) {
      if (ancillaeOwner[i] != index && ancillaeOwner[i] != -1) continue;
      if (!ancillae[i].is_syncable()) continue;

      ancillae[i].serialize(r);
    }
  }

  void serialize_rooms(array<uint8> &r) {
    // DISABLED: room sync
    //r.insertLast(uint8(0xFF));  // TBD
    //r.insertLast(uint16(rooms.length()));
    //if (rooms.length() > 0) {
    //  // write room state:
    //  r.insertLast(rooms);
    //}
  }

  bool deserialize(array<uint8> r, int c) {
    if (c >= r.length()) return false;

    auto protocol = r[c++];
    //message("game protocol = " + fmtHex(protocol, 2));
    if (protocol != 0x01) {
      message("bad game protocol " + fmtHex(protocol, 2) + "!");
      return false;
    }

    auto frame = r[c++];
    //message("frame = " + fmtHex(frame, 2));
    if (frame < this.frame) {
      // stale data:
      // TODO fix check when wrapping around 0xFF to 0x00
      message("stale frame " + fmtHex(frame, 2) + " vs " + fmtHex(this.frame, 2));
      this.frame = frame;
      return false;
    }
    this.frame = frame;

    int maxc = int(r.length());
    while (c < maxc) {
      auto packetType = r[c++];
      //message("packetType = " + fmtHex(packetType, 2));
      switch (packetType) {
        case 0x01: c = deserialize_location(r, c); break;
        case 0x02: c = deserialize_sfx(r, c); break;
        case 0x03: c = deserialize_sprites(r, c); break;
        case 0x04: c = deserialize_chr0(r, c); break;
        case 0x05: c = deserialize_chr1(r, c); break;
        case 0x06: c = deserialize_items(r, c); break;
        case 0x07: c = deserialize_tilemaps(r, c); break;
        case 0x08: c = deserialize_objects(r, c); break;
        case 0x09: c = deserialize_ancillae(r, c); break;
        default:
          message("unknown packet type " + fmtHex(packetType, 2) + " at offs " + fmtHex(c, 3));
          break;
      }
    }

    return true;
  }

  int deserialize_location(array<uint8> r, int c) {
    module = r[c++];
    sub_module = r[c++];
    sub_sub_module = r[c++];

    location = uint32(r[c++])
               | (uint32(r[c++]) << 8)
               | (uint32(r[c++]) << 16)
               | (uint32(r[c++]) << 24);

    x = uint16(r[c++]) | (uint16(r[c++]) << 8);
    y = uint16(r[c++]) | (uint16(r[c++]) << 8);

    // last overworld coordinate when entered dungeon:
    last_overworld_x = uint16(r[c++]) | (uint16(r[c++]) << 8);
    last_overworld_y = uint16(r[c++]) | (uint16(r[c++]) << 8);

    return c;
  }

  int deserialize_sfx(array<uint8> r, int c) {
    uint8 tx1, tx2;
    tx1 = r[c++];
    tx2 = r[c++];
    if (tx1 != 0) {
      sfx1 = tx1;
    }
    if (tx2 != 0) {
      sfx2 = tx2;
    }

    return c;
  }

  int deserialize_sprites(array<uint8> r, int c) {
    // read in OAM sprites:
    auto numsprites = r[c++];
    sprites.resize(numsprites);
    for (uint i = 0; i < numsprites; i++) {
      @sprites[i] = Sprite();
      c = sprites[i].deserialize(r, c);
    }

    return c;
  }

  int deserialize_chr0(array<uint8> r, int c) {
    // read in chr0 data:
    auto chr_count = r[c++];
    for (uint i = 0; i < chr_count; i++) {
      // read chr0 number:
      auto h = uint16(r[c++]);

      // read chr tile data:
      chrs[h].resize(16);
      for (int k = 0; k < 16; k++) {
        chrs[h][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      }
    }

    return c;
  }

  int deserialize_chr1(array<uint8> r, int c) {
    // read in chr1 data:
    auto chr_count = r[c++];
    for (uint i = 0; i < chr_count; i++) {
      // read chr1 number:
      auto h = uint16(r[c++]) + 0x100;

      // read chr tile data:
      chrs[h].resize(16);
      for (int k = 0; k < 16; k++) {
        chrs[h][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      }
    }

    return c;
  }

  int deserialize_rooms(array<uint8> r, int c) {
    // read rooms state:
    //uint16 roomCount = uint16(r[c++]) | (uint16(r[c++]) << 8);
    //if (roomCount > 0x128) {
    //  roomCount = 0x128;
    //}
    //rooms.resize(roomCount);
    //for (uint i = 0; i < roomCount; i++) {
    //  rooms[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
    //}

    return c;
  }

  int deserialize_objects(array<uint8> r, int c) {
    objectsBlock.resize(0x2A0);
    for (int i = 0; i < 0x2A0; i++) {
      objectsBlock[i] = r[c++];
    }

    return c;
  }

  int deserialize_ancillae(array<uint8> r, int c) {
    uint8 count = r[c++];
    ancillae.resize(count);
    for (int i = 0; i < count; i++) {
      if (ancillae[i] is null) {
        @ancillae[i] = @GameAncilla();
      }

      c = ancillae[i].deserialize(r, c);
    }

    return c;
  }

  int deserialize_items(array<uint8> r, int c) {
    // items: (MUST be sorted by offs)
    uint8 itemCount = r[c++];
    items.resize(itemCount);
    for (uint8 i = 0; i < itemCount; i++) {
      auto @item = items[i];
      if (@item == null) {
        @item = @items[i] = SyncedItem();
        item.lastValue = 0;
        item.value = 0;
      }

      // copy current value to last value:
      item.lastValue = item.value;

      // deserialize offset and new value:
      item.offs = uint16(r[c++]) + 0x340;
      item.value = uint16(r[c++]) | (uint16(r[c++]) << 8);
      //if (item.value != item.lastValue) {
      //  message("deser[" + fmtInt(index) + "][" + fmtHex(item.offs, 3) + "] = " + fmtHex(item.value, 4));
      //}
    }

    return c;
  }

  int deserialize_tilemaps(array<uint8> r, int c) {
    // tilemap changes:
    tilemapCount = uint16(r[c++]) | (uint16(r[c++]) << 8);
    tilemapAddress.resize(tilemapCount);
    for (uint i = 0; i < tilemapCount; i++) {
      tilemapAddress[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
    }
    tilemapTile.resize(tilemapCount);
    for (uint i = 0; i < tilemapCount; i++) {
      tilemapTile[i] = uint16(r[c++]) | (uint16(r[c++]) << 8);
    }

    return c;
  }

  void update_items() {
    if (is_it_a_bad_time()) return;

    // update local player with items from all remote players:
    array<uint16> values;
    values.resize(syncableItems.length());

    // start with our own values:
    for (uint k = 0; k < syncableItems.length(); k++) {
      auto @syncable = syncableItems[k];

      if (syncable.type == 1) {
        // max value:
        values[k] = this.items[k].value;
      } else if (syncable.type == 2) {
        // bitfield:
        values[k] = this.items[k].value;
      }
    }

    // find higher max values among remote players:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;
      if (@remote == @local) continue;
      if (remote.ttl <= 0) {
        continue;
      }

      for (uint j = 0; j < remote.items.length(); j++) {
        uint16 offs = remote.items[j].offs;

        // find a match by offs:
        uint k = 0;
        for (; k < syncableItems.length(); k++) {
          if (offs == syncableItems[k].offs) {
            break;
          }
        }
        if (k == syncableItems.length()) {
          message("["+fmtInt(i)+"] offs="+fmtHex(offs,3)+" not found!");
          continue;
        }

        auto @syncable = syncableItems[k];

        // apply operation to values:
        uint16 value = remote.items[j].value;
        if (syncable.type == 1) {
          // max value:
          if (value > values[k]) {
            values[k] = value;
          }
        } else if (syncable.type == 2) {
          // bitfield OR:
          values[k] = values[k] | value;
        }
      }
    }

    // write back our values:
    for (uint k = 0; k < syncableItems.length(); k++) {
      auto @syncable = syncableItems[k];

      bool modified = false;
      uint16 oldValue = this.items[k].value;
      uint16 newValue = oldValue;
      if (syncable.type == 1) {
        // max value:
        newValue = values[k];
        if (newValue > oldValue) {
          this.items[k].value = newValue;
          modified = true;
        }
      } else if (syncable.type == 2) {
        // bitfield:
        newValue = oldValue | values[k];
        if (newValue != oldValue) {
          this.items[k].value = newValue;
          modified = true;
        }
      }

      // write back to SRAM:
      if (modified) {
        if (syncable.size == 1) {
          bus::write_u8(0x7EF000 + syncable.offs, uint8(this.items[k].value));
        } else if (syncable.size == 2) {
          bus::write_u16(0x7EF000 + syncable.offs, this.items[k].value);
        }

        // call post-modification function if applicable:
        syncable.modified(oldValue, newValue);
      }
    }
  }

  void update_rooms_sram() {
    for (uint i = 0; i < rooms.length(); i++) {
      // High Byte           Low Byte
      // d d d d b k ck cr   c c c c q q q q
      // c - chest, big key chest, or big key lock. Any combination of them totalling to 6 is valid.
      // q - quadrants visited:
      // k - key or item (such as a 300 rupee gift)
      // 638
      // d - door opened (either unlocked, bombed or other means)
      // r - special rupee tiles, whether they've been obtained or not.
      // b - boss battle won

      //uint8 lo = rooms[i] & 0xff;
      uint8 hi = rooms[i] >> 8;

      // mask off everything but doors opened state:
      hi = hi & 0xF0;

      // OR door state with local WRAM:
      uint8 lhi = bus::read_u8(0x7EF000 + (i << 1) + 1);
      lhi |= hi;
      bus::write_u8(0x7EF000 + (i << 1) + 1, lhi);
    }
  }

  void update_room_current() {
    if (rooms.length() == 0) return;

    // only update dungeon room state:
    auto in_dungeon = bus::read_u8(0x7E001B);
    if (in_dungeon == 0) return;

    auto dungeon_room = bus::read_u16(0x7E00A0);
    if (dungeon_room >= rooms.length()) return;

    // $0400
    // $0401 - Tops four bits: In a given room, each bit corresponds to a door being opened.
    //  If set, it has been opened by some means (bomb, key, etc.)
    // $0402[0x01] - Certainly related to $0403, but contains other information I haven’t looked at yet.
    // $0403[0x01] - Contains room information, such as whether the boss in this room has been defeated.
    //  Loaded on every room load according to map information that is stored as you play the game.
    //  Bit 0: Chest 1
    //  Bit 1: Chest 2
    //  Bit 2: Chest 3
    //  Bit 3: Chest 4
    //  Bit 4: Chest 5
    //  Bit 5: Chest 6 / A second Key. Having 2 keys and 6 chests will cause conflicts here.
    //  Bit 6: A key has been obtained in this room.
    //  Bit 7: Heart Piece has been obtained in this room.

    uint8 hi = rooms[dungeon_room] >> 8;
    // mask off everything but doors opened state:
    hi = hi & 0xF0;

    // OR door state with current room state:
    uint8 lhi = bus::read_u8(0x7E0401);
    lhi |= hi;
    bus::write_u8(0x7E0401, lhi);
  }

  uint8 adjust_sfx_pan(uint8 sfx) {
    // Try to infer the sound's relative(ish) position from the remote player
    // based on the encoded pan information from their screen:
    int sx = x;
    if ((sfx & 0x80) == 0x80) sx -= 40;
    else if ((sfx & 0x40) == 0x40) sx += 40;

    // clear original panning from remote player:
    sfx = sfx & 0x3F;
    // adjust pan based on sound's relative position to local player:
    if (sx - int(local.x) <= -40) sfx |= 0x80;
    else if (sx - int(local.x) >= 40) sfx |= 0x40;

    return sfx;
  }

  void play_sfx() {
    if (sfx1 != 0) {
      //message("sfx1 = " + fmtHex(sfx1,2));
      uint8 lfx1 = bus::read_u8(0x7E012E);
      if (lfx1 == 0) {
        uint8 sfx = adjust_sfx_pan(sfx1);
        bus::write_u8(0x7E012E, sfx);
        sfx1 = 0;
      }
    }

    if (sfx2 != 0) {
      //message("sfx2 = " + fmtHex(sfx2,2));
      uint8 lfx2 = bus::read_u8(0x7E012F);
      if (lfx2 == 0) {
        uint8 sfx = adjust_sfx_pan(sfx2);
        bus::write_u8(0x7E012F, sfx);
        sfx2 = 0;
      }
    }
  }

  // convert overworld tilemap address to VRAM address:
  uint16 ow_tilemap_to_vram_address(uint16 addr) {
    uint16 vaddr = 0;

    if ((addr & 0x003F) >= 0x0020) {
      vaddr = 0x0400;
    }

    if ((addr & 0x0FFF) >= 0x0800) {
      vaddr += 0x0800;
    }

    vaddr += (addr & 0x001F);
    vaddr += (addr & 0x0780) >> 1;

    return vaddr;
  }

  void update_tilemap() {
    if (local.is_in_dungeon()) {
      return;
    }
    if (local.module == 0x09) {
      // don't fetch tilemap during screen transition:
      if (local.sub_module >= 0x01 && local.sub_module < 0x07) {
        return;
      }
      // during LW/DW transition:
      if (local.sub_module >= 0x23) {
        return;
      }
    }

    // read current local arrays:
    uint16 localTilemapCount = bus::read_u16(0x7E04AC) >> 1;
    array<uint16> localTilemapAddress;
    localTilemapAddress.resize(localTilemapCount);
    bus::read_block_u16(0x7EF800, 0, localTilemapCount, localTilemapAddress);
    array<uint16> localTilemapTile;
    localTilemapTile.resize(localTilemapCount);
    bus::read_block_u16(0x7EFA00, 0, localTilemapCount, localTilemapTile);

    // merge in changes from remote tilemap:
    for (uint i = 0; i < tilemapCount; i++) {
      uint16 addr = tilemapAddress[i];
      uint16 tile = tilemapTile[i];

      // try to find the change in local tilemap:
      int j = localTilemapAddress.find(addr);
      if (j == -1) {
        j = localTilemapCount;
        localTilemapCount++;
        localTilemapAddress.resize(localTilemapCount);
        localTilemapTile.resize(localTilemapCount);
      }
      // update the address entry in the local tilemap:
      localTilemapAddress[j] = addr;
      localTilemapTile[j] = tile;

      // apply change to 0x7E2000 in-memory map:
      bus::write_u16(0x7E2000 + addr, tile);

      // TODO: dont update VRAM if area is 1024x1024 instead of normal 512x512. this glitches out.

      // update VRAM with changes:
      // convert tilemap address to VRAM address:
      uint16 vaddr = ow_tilemap_to_vram_address(addr);

      // look up tile in tile gfx:
      uint16 a = tile << 3;
      array <uint16> t(4);
      t[0] = bus::read_u16(0x0F8000 + a);
      t[1] = bus::read_u16(0x0F8002 + a);
      t[2] = bus::read_u16(0x0F8004 + a);
      t[3] = bus::read_u16(0x0F8006 + a);

      // update 16x16 tilemap in VRAM:
      ppu::vram.write_block(vaddr, 0, 2, t);
      ppu::vram.write_block(vaddr + 0x0020, 2, 2, t);
    }

    // append our changes to end of local tilemap change array:
    bus::write_u16(0x7E04AC, (localTilemapCount << 1));
    bus::write_block_u16(0x7EF800, 0, localTilemapCount, localTilemapAddress);
    bus::write_block_u16(0x7EFA00, 0, localTilemapCount, localTilemapTile);
  }

  void render(int x, int y) {
    for (uint i = 0; i < 512; i++) {
      reloc[i] = 0;
    }

    // shadow sprites copy over directly:
    reloc[0x6c] = 0x6c;
    reloc[0x6d] = 0x6d;
    reloc[0x7c] = 0x7c;
    reloc[0x7d] = 0x7d;

    for (uint i = 0; i < sprites.length(); i++) {
      auto sprite = sprites[i];
      auto px = sprite.size == 0 ? 8 : 16;

      // bounds check for OAM sprites:
      if (sprite.x + x < -px) continue;
      if (sprite.x + x >= 256) continue;
      if (sprite.y + y < -px) continue;
      if (sprite.y + y >= 240) continue;

      // determine which OAM sprite slot is free around the desired index:
      uint j;
      for (j = sprite.index; j < sprite.index + 128; j++) {
        if (!ppu::oam[j & 127].is_enabled) break;
      }
      // no more free slots?
      if (j == sprite.index + 128) return;

      // start building a new OAM sprite:
      j = j & 127;
      auto oam = ppu::oam[j];
      oam.x = uint16(sprite.x + x);
      oam.y = sprite.y + 1 + y;
      oam.hflip = sprite.hflip;
      oam.vflip = sprite.vflip;
      oam.priority = sprite.priority;
      oam.palette = sprite.palette;
      oam.size = sprite.size;

      // find free character(s) for replacement:
      if (sprite.size == 0) {
        // 8x8 sprite:
        if (reloc[sprite.chr] == 0) { // assumes use of chr=0 is invalid, which it is since it is for local Link.
          for (uint k = 0x20; k < 512; k++) {
            // skip chr if in-use:
            if (localFrameState.chr[k]) continue;

            oam.character = k;
            localFrameState.chr[k] = true;
            reloc[sprite.chr] = k;
            if (chrs[sprite.chr].length() == 0) {
              //message("remote CHR="+fmtHex(sprite.chr,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k), chrs[sprite.chr]);
            }
            break;
          }
        } else {
          // use existing chr:
          oam.character = reloc[sprite.chr];
        }
      } else {
        // 16x16 sprite:
        if (reloc[sprite.chr] == 0) { // assumes use of chr=0 is invalid, which it is since it is for local Link.
          for (uint k = 0x20; k < 0x1EF; k++) {
            // skip chr if in-use:
            if (localFrameState.chr[k + 0x00]) continue;
            if (localFrameState.chr[k + 0x01]) continue;
            if (localFrameState.chr[k + 0x10]) continue;
            if (localFrameState.chr[k + 0x11]) continue;

            oam.character = k;
            localFrameState.chr[k + 0x00] = true;
            localFrameState.chr[k + 0x01] = true;
            localFrameState.chr[k + 0x10] = true;
            localFrameState.chr[k + 0x11] = true;
            reloc[sprite.chr + 0x00] = k + 0x00;
            reloc[sprite.chr + 0x01] = k + 0x01;
            reloc[sprite.chr + 0x10] = k + 0x10;
            reloc[sprite.chr + 0x11] = k + 0x11;
            if (chrs[sprite.chr + 0x00].length() == 0) {
              //message("remote CHR="+fmtHex(sprite.chr + 0x00,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x00), chrs[sprite.chr + 0x00]);
            }
            if (chrs[sprite.chr + 0x01].length() == 0) {
              //message("remote CHR="+fmtHex(sprite.chr + 0x01,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x01), chrs[sprite.chr + 0x01]);
            }
            if (chrs[sprite.chr + 0x10].length() == 0) {
              //message("remote CHR="+fmtHex(sprite.chr + 0x10,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x10), chrs[sprite.chr + 0x10]);
            }
            if (chrs[sprite.chr + 0x11].length() == 0) {
              //message("remote CHR="+fmtHex(sprite.chr + 0x11,3)+" data empty!");
            } else {
              localFrameState.overwrite_tile(ppu::vram.chr_address(k + 0x11), chrs[sprite.chr + 0x11]);
            }
            break;
          }
        } else {
          // use existing chrs:
          oam.character = reloc[sprite.chr];
        }
      }

      // update sprite in OAM memory:
      @ppu::oam[j] = oam;
    }
  }
};

GameState local;
array<GameState@> players(0);
uint8 isRunning;

bool intercepting = false;

void receive() {
  array<uint8> buf(1500);
  int n;
  while ((n = sock.recv(0, 1500, buf)) > 0) {
    int c = 0;

    // copy to new buffer and trim to size:
    array<uint8> r = buf;
    r.resize(n);

    // verify envelope header:
    uint16 header = uint16(r[c++]) | (uint16(r[c++]) << 8);
    if (header != 25887) {
      message("receive(): bad envelope header!");
      continue;
    }

    uint16 index = 0;

    // check protocol:
    uint8 protocol = r[c++];
    if (protocol == 0x01) {
      // skip group name:
      uint8 groupLen = r[c++];
      c += groupLen;

      // skip player name:
      uint8 nameLen = r[c++];
      c += nameLen;

      // read player index:
      index = uint16(r[c++]) | (uint16(r[c++]) << 8);

      // check client type (spectator=0, player=1):
      uint8 clientType = r[c++];
      // skip messages from non-players (e.g. spectators):
      if (clientType != 1) {
        message("receive(): ignore non-player message");
        continue;
      }
    } else if (protocol == 0x02) {
      // skip 20 byte group name:
      c += 20;

      // message kind:
      uint8 kind = r[c++];
      if (kind == 0x80) {
        // read client index:
        index = uint16(r[c++]) | (uint16(r[c++]) << 8);

        // assign to local player:
        if (local.index != int(index)) {
          if (local.index >= 0 && local.index < int(players.length())) {
            // reset old player slot:
            @players[local.index] = @GameState();
          }
          // reassign local index:
          local.index = index;

          message("assign local.index = " + fmtInt(index));

          // make room for local player if needed:
          while (index >= players.length()) {
            players.insertLast(@GameState());
          }

          // assign the local player into the players[] array:
          @players[index] = local;
        }
        continue;
      }

      // kind == 0x81 should be response to another player's broadcast.
      index = uint16(r[c++]) | (uint16(r[c++]) << 8);
    } else {
      message("receive(): unknown protocol 0x" + fmtHex(protocol, 2));
      continue;
    }

    while (index >= players.length()) {
      players.insertLast(@GameState());
    }

    // deserialize data packet:
    players[index].ttl = 255;
    players[index].index = index;
    players[index].deserialize(r, c);
  }
}

void pre_nmi() {
  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;

  // Attempt to open a server socket:
  if (@sock == null) {
    try {
      // open a UDP socket to receive data from:
      @address = net::resolve_udp(settings.ServerAddress, "4590");
      // open a UDP socket to receive data from:
      @sock = net::Socket(address);
      // connect to remote address so recv() and send() work:
      sock.connect(address);
    } catch {
      // Probably server IP field is invalid; prompt user again:
      @sock = null;
      settings.started = false;
      settings.show();
    }
  }

  // restore previous VRAM tiles:
  localFrameState.restore();

  local.ttl = 255;

  // fetch next frame's game state from WRAM:
  local.fetch_module();

  local.fetch_sfx();

  local.fetch();

  if (!local.is_it_a_bad_time()) {
    // play remote sfx:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;

      if (@remote == @local) continue;
      if (remote.ttl <= 0) {
        remote.ttl = 0;
        continue;
      }

      // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
      if (local.can_see(remote.location)) {
        // attempt to play remote sfx:
        remote.play_sfx();
      }
    }
  }
}

void pre_frame() {
  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;

  if (null == @sock) return;

  //message("pre-frame");

  // backup VRAM for OAM tiles which are in-use by game:
  localFrameState.backup();

  // fetch local VRAM data for sprites:
  local.capture_sprites_vram();

  // send updated state for our Link to server:
  local.send();

  // receive network updates from remote players:
  receive();

  // render remote players:
  for (uint i = 0; i < players.length(); i++) {
    auto @remote = players[i];
    if (@remote == null) continue;

    if (@remote == @local) continue;
    if (remote.ttl <= 0) {
      remote.ttl = 0;
      continue;
    }

    remote.ttl = remote.ttl - 1;

    remote.update_rooms_sram();

    // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
    if (local.can_see(remote.location)) {
      // subtract BG2 offset from sprite x,y coords to get local screen coords:
      int16 rx = int16(remote.x) - local.xoffs;
      int16 ry = int16(remote.y) - local.yoffs;

      // draw remote player relative to current BG offsets:
      remote.render(rx, ry);

      // update current room state in WRAM:
      remote.update_room_current();

      // update tilemap:
      remote.update_tilemap();
    }
  }

  {
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;
      if (remote.ttl <= 0) continue;
      if (!local.can_see(remote.location)) continue;

      //message("[" + fmtInt(i) + "].ancillae.len = " + fmtInt(remote.ancillae.length()));
      if (remote is local) {
        continue;
      }

      if (remote.ancillae.length() > 0) {
        for (uint j = 0; j < remote.ancillae.length(); j++) {
          auto @an = remote.ancillae[j];
          auto k = an.index;

          if (local.ancillaeOwner[k] == remote.index) {
            an.writeRAM();
            if (an.type == 0) {
              // clear owner if type went to 0:
              local.ancillaeOwner[k] = -1;
            }
          } else if (local.ancillaeOwner[k] == -1 && an.type != 0) {
            an.writeRAM();
            local.ancillaeOwner[k] = remote.index;
          }

          //for (uint k = 0; k < 0x0A; k++) {
            //if (local.ancillaeOwner[k] == remote.index)
          //}
        }
      }

      continue;
    }
  }

  if (false) {
    auto updated_objects = false;

    // update objects state from lowest-indexed player in the room:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;
      if (remote.ttl <= 0) continue;
      if (!local.can_see(remote.location)) continue;

      if (!updated_objects && remote.objectsBlock.length() == 0x2A0) {
        updated_objects = true;
        local.objects_index_source = i;
      }
    }

    if (updated_objects) {
      if (local.objects_index_source == local.index) {
        // we are the player that controls the objects in the room. run through each player in the same room
        // and synchronize any attempted changes to objects.

      } else {
        // we are not in control of objects in the room so just copy the state from the player who is:
        //bus::write_block_u8(0x7E0D00, 0, 0x2A0, remote.objectsBlock);

        auto @remote = players[local.objects_index_source];
        for (uint j = 0; j < 0x10; j++) {
          GameSprite r;
          GameSprite l;
          r.readFromBlock(remote.objectsBlock, j);
          l.readRAM(j);

          // don't overwrite locally picked up objects:
          if (l.state == 0x0A) continue;
          // don't copy in remotely picked up objects:
          if (r.state == 0x0A) r.state = 0;
          r.writeRAM();
        }
      }
    }
  }

  local.update_items();

  if (@worldMap != null) {
    worldMap.renderPlayers(local, players);
  }
}

void post_frame() {
  if (@oamWindow != null) {
    oamWindow.update();
  }

  if (@worldMap != null) {
    worldMap.loadMap();
    worldMap.drawMap();
  }

  if (debugData) {
    ppu::frame.text_shadow = true;
    ppu::frame.color = 0x7fff;
    ppu::frame.text( 0, 0, fmtHex(local.module, 2));
    ppu::frame.text(20, 0, fmtHex(local.sub_module, 2));
    ppu::frame.text(40, 0, fmtHex(local.sub_sub_module, 2));

    ppu::frame.text(60, 0, fmtHex(local.location, 6));
    //ppu::frame.text(60, 0, fmtHex(local.in_dark_world, 1));
    //ppu::frame.text(68, 0, fmtHex(local.in_dungeon, 1));
    //ppu::frame.text(76, 0, fmtHex(local.overworld_room, 2));
    //ppu::frame.text(92, 0, fmtHex(local.dungeon_room, 2));

    ppu::frame.text(120, 0, fmtHex(local.x, 4));
    ppu::frame.text(160, 0, fmtHex(local.y, 4));
  }

  if (@sprites != null) {
    for (int i = 0; i < 16; i++) {
      palette7[i] = ppu::cgram[(15 << 4) + i];
    }
    sprites.render(palette7);
    sprites.update();
  }

  if (@worldMap != null) {
    worldMap.update(local);
  }

  if (@gameSpriteWindow != null) {
    gameSpriteWindow.update();
  }
}

// called when bsnes changes its color palette:
void palette_updated() {
  //message("palette_updated()");
  if (@worldMap != null) {
    worldMap.redrawMap();
  }
}
