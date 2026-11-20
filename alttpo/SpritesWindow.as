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
  // a gray ramp for the CHRs that no OAM entry uses and that cannot be told from their neighbors:
  private array<uint16> grayPalette(16);

  // the sprite palette (0-7) of each of the 512 CHRs as used by the OAM entries of this frame, or -1 if no OAM entry
  // uses it:
  private array<int> chrPalette(512);
  // per palette, how many CHRs of a strip use it:
  private array<int> votes(8);

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
    for (uint i = 0; i < 16; i++) {
      // 5 bit gray, color 0 is transparent and never drawn:
      uint c = i * 31 / 15;
      grayPalette[i] = uint16(c | (c << 5) | (c << 10));
    }

    vl.resize();
    canvas.update();
    windowLayout.attach("vram", window);
    window.visible = true;
  }

  bool isOpen() {
    return window.visible;
  }

  void show() {
    window.visible = true;
    window.setFocused();
  }

  void update() {
    if (!window.visible) return;
    canvas.update();
  }

  // assign sets the palette of a CHR in the 16x32 grid of CHRs of both pages, chrs wrap around within their row:
  private void assign(uint chr, int pal) {
    chrPalette[chr & 0x1FF] = pal;
  }

  // findPalettes works out which palette each CHR is drawn with from the OAM entries of the frame. Sprites are 8x8 or
  // 16x16 here; a 16x16 sprite is made of its CHR, the next CHR, and those 16 CHRs below.
  private void findPalettes() {
    for (uint i = 0; i < 512; i++) {
      chrPalette[i] = -1;
    }

    if (local is null) return;

    for (uint i = 0; i < 128; i++) {
      auto @s = local.sprs[i];
      // the Y of an unused OAM entry is $F0; entries off screen are still in VRAM so they count:
      if (s.b1 == 0xF0) continue;

      uint chr = uint(s.b2) | (uint(s.b3 & 1) << 8);
      int pal = (s.b3 >> 1) & 7;
      bool large = ((s.b4 >> 1) & 1) != 0;

      assign(chr, pal);
      if (large) {
        uint page = chr & 0x100;
        uint row = (chr >> 4) & 15;
        uint col = chr & 15;
        assign(page | (row << 4) | ((col + 1) & 15), pal);
        assign(page | (((row + 1) & 15) << 4) | col, pal);
        assign(page | (((row + 1) & 15) << 4) | ((col + 1) & 15), pal);
      }
    }
  }

  // stripPalette is the palette most of the known CHRs of the 16 CHR strip (one row of a page) use, to draw the CHRs
  // in the strip that no OAM entry uses. Sprite graphics are loaded in sheets of whole strips that share a palette in
  // practice; -1 if no CHR in the strip is known.
  private int stripPalette(uint strip) {
    for (uint p = 0; p < 8; p++) votes[p] = 0;

    bool any = false;
    for (uint i = 0; i < 16; i++) {
      int pal = chrPalette[(strip << 4) + i];
      if (pal < 0) continue;
      votes[pal]++;
      any = true;
    }
    if (!any) return -1;

    int best = 0;
    for (uint p = 1; p < 8; p++) {
      if (votes[p] > votes[best]) best = p;
    }
    return best;
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

    // draw VRAM as 4bpp tiles, each with its own palette:
    canvas.fill(0x0000);
    for (uint strip = 0; strip < 32; strip++) {
      int stripPal = stripPalette(strip);

      for (uint col = 0; col < 16; col++) {
        uint chr = (strip << 4) + col;
        int pal = chrPalette[chr];
        if (pal < 0) pal = stripPal;

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
