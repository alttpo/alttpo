SpritesWindow @sprites;

const int scale = 3;

class SpritesWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  GUI::SNESCanvas @canvas;

  array<uint16> page0(0x1000);
  array<uint16> page1(0x1000);

  // the 8 sprite palettes in CGRAM, indexed by the palette number of OAM entries:
  private array<array<uint16>@> palettes(8);
  // a gray ramp for the CHRs without a known palette:
  private array<uint16> grayPalette(16);

  // the sprite palette (0-7) each of the 512 CHRs was last seen drawn with by an OAM entry, or -1 if never seen:
  private array<int> chrPalette(512);

  // the CHR palettes are kept in their own file between runs, for each game: a section per game with a line of 16
  // characters per row of CHRs, each the palette 0-7 or - if not seen. The sections of the games not played are kept as
  // they were read.
  private string file = "alttpo-vram.bml";
  private array<string> savedAlttp(32);
  private array<string> savedSm(32);
  private bool dirty = false;
  private uint framesSinceSave = 0;

  SpritesWindow() {
    // relative position to bsnes window:
    @window = GUI::Window(0, 240*3, true);
    window.title = "Sprite VRAM";
    window.size = GUI::Size(256*scale, 128*scale);

    @vl = GUI::VerticalLayout();
    window.append(vl);

    @canvas = GUI::SNESCanvas();
    canvas.size = GUI::Size(256, 128);
    vl.append(canvas, GUI::Size(-1, -1));

    for (uint i = 0; i < 8; i++) {
      @palettes[i] = array<uint16>(16);
    }
    for (uint i = 0; i < 512; i++) {
      chrPalette[i] = -1;
    }
    for (uint i = 0; i < 16; i++) {
      // 5 bit gray, color 0 is transparent and never drawn:
      uint c = i * 31 / 15;
      grayPalette[i] = uint16(c | (c << 5) | (c << 10));
    }

    load();

    vl.resize();
    canvas.update();
    windowLayout.attach("vram", window);
    window.visible = true;
  }

  bool isOpen() {
    return window.visible;
  }

  void hide() {
    window.visible = false;
  }

  void show() {
    window.visible = true;
    window.setFocused();
  }

  void update() {
    if (!window.visible) return;
    canvas.update();
  }

  private bool isAlttp() {
    return rom is null || rom.is_alttp();
  }

  // load reads the saved palettes of the game and the saved text of the other game's:
  private void load() {
    auto doc = UserSettings::load(file);
    for (uint strip = 0; strip < 32; strip++) {
      string key = fmtHex(strip, 2);
      savedAlttp[strip] = doc["alttp/" + key].textOr("");
      savedSm[strip] = doc["sm/" + key].textOr("");
    }

    auto @mine = isAlttp() ? savedAlttp : savedSm;
    for (uint strip = 0; strip < 32; strip++) {
      string text = mine[strip];
      if (text.length() != 16) continue;

      for (uint col = 0; col < 16; col++) {
        // '0' to '7' are palettes and anything else is not known:
        int c = int(text[col]) - 0x30;
        chrPalette[(strip << 4) + col] = (c >= 0 && c <= 7) ? c : -1;
      }
    }
  }

  // save writes the palettes of the game with those of the other game, if there were any changes:
  void save() {
    if (!dirty) return;
    dirty = false;
    framesSinceSave = 0;

    auto @mine = isAlttp() ? savedAlttp : savedSm;
    for (uint strip = 0; strip < 32; strip++) {
      string text = "";
      for (uint col = 0; col < 16; col++) {
        int pal = chrPalette[(strip << 4) + col];
        text += (pal < 0) ? "-" : fmtInt(pal);
      }
      mine[strip] = text;
    }

    auto doc = BML::Node();
    for (uint strip = 0; strip < 32; strip++) {
      string key = fmtHex(strip, 2);
      if (savedAlttp[strip].length() == 16) doc.create("alttp/" + key).value = savedAlttp[strip];
      if (savedSm[strip].length() == 16) doc.create("sm/" + key).value = savedSm[strip];
    }
    UserSettings::save(file, doc);
  }

  // defaultPalette is the palette the game draws a CHR with when no OAM entry shows it, or -1 if it varies.
  //
  // The game does not tie palettes to CHRs: the palette is in the flags of every OAM entry, which the code drawing each
  // sprite sets. What is fixed is where the graphics sheets of 64 CHRs ($400 words) go in sprite VRAM, in ALTTP:
  //   chr $000-$03F  Link's body, head, sword, shield and the like, always drawn with palette 7 (the player's OAM flags
  //                  are $0E, see link_palette_bits_of_oam in player_oam.c)
  //   chr $040-$07F  misc sprites (items, bombs, rupees, hearts, ...)
  //   chr $080-$1FF  the sheets of the sprite sets for the area, loaded per area
  // Only Link's sheet is the same everywhere. Enemies and objects of the other sheets get the palette of their sprite
  // type (kSpriteInit_Flags3 bits 1-3), which depends on which sprites the area has, so those CHRs are only known once
  // a sprite using them is drawn.
  private int defaultPalette(uint chr) {
    if (rom is null || !rom.is_alttp()) return -1;
    if (chr < 0x40) return 7;
    return -1;
  }

  // findPalettes records the palette of the CHRs the OAM entries of the frame draw; a CHR stays as it was last seen
  // until another OAM entry draws it. A 16x16 sprite is made of its CHR, the next CHR, and those 16 CHRs below.
  private void findPalettes() {
    if (local is null) return;

    for (uint i = 0; i < 128; i++) {
      auto @s = local.sprs[i];
      // the Y of an unused OAM entry is $F0; entries off screen are still in VRAM so they count:
      if (s.b1 == 0xF0) continue;

      uint chr = uint(s.b2) | (uint(s.b3 & 1) << 8);
      int pal = (s.b3 >> 1) & 7;
      bool large = ((s.b4 >> 1) & 1) != 0;

      remember(chr, pal);
      if (large) {
        uint page = chr & 0x100;
        uint row = (chr >> 4) & 15;
        uint col = chr & 15;
        remember(page | (row << 4) | ((col + 1) & 15), pal);
        remember(page | (((row + 1) & 15) << 4) | col, pal);
        remember(page | (((row + 1) & 15) << 4) | ((col + 1) & 15), pal);
      }
    }
  }

  private void remember(uint chr, int pal) {
    if (chrPalette[chr] == pal) return;
    chrPalette[chr] = pal;
    dirty = true;
  }

  void render() {
    if (!window.visible) return;

    // read VRAM:

    // NOTE: these offets are true for ALTTP specifically...
    // ppu::vram.read_block(0x4000, 0, 0x1000, page0);
    // ppu::vram.read_block(0x5000, 0, 0x1000, page1);

    // ...but let's use chr_address function to figure out dynamically where chr page 0 and 1 are:
    ppu::vram.read_block(ppu::vram.chr_address(0x000), 0, 0x1000, page0);
    ppu::vram.read_block(ppu::vram.chr_address(0x100), 0, 0x1000, page1);

    // read the sprite palettes, which are the second half of CGRAM:
    for (uint p = 0; p < 8; p++) {
      for (uint i = 0; i < 16; i++) {
        palettes[p][i] = ppu::cgram[128 + (p << 4) + i];
      }
    }

    findPalettes();

    // save a few seconds after a change, not on every change as they come in bursts:
    if (dirty && ++framesSinceSave >= 180) save();

    // draw VRAM as 4bpp tiles, each with its own palette:
    canvas.fill(0x0000);
    for (uint strip = 0; strip < 32; strip++) {
      for (uint col = 0; col < 16; col++) {
        uint chr = (strip << 4) + col;
        // last seen in OAM, else what the game uses for it, else gray:
        int pal = chrPalette[chr];
        if (pal < 0) pal = defaultPalette(chr);

        // chrs 0-255 are in the first page and 256-511 in the second, which is drawn next to it:
        uint tile = chr & 0xFF;
        int x = ((chr >> 8) << 7) + ((tile & 15) << 3);
        int y = (tile >> 4) << 3;
        array<uint16>@ colors = grayPalette;
        if (pal >= 0) @colors = palettes[pal];

        if (chr < 0x100) {
          canvas.draw_sprite_4bpp(x, y, tile, 8, 8, page0, colors);
        } else {
          canvas.draw_sprite_4bpp(x, y, tile, 8, 8, page1, colors);
        }
      }
    }
  }
};
