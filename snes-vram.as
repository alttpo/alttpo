SpriteWindow @sprites;
BGWindow @bg;

class SpriteWindow {
  private gui::Window @window;
  private gui::VerticalLayout @vl;
  gui::Canvas @canvas;

  array<uint16> fgtiles(0x2000);

  SpriteWindow() {
    // relative position to bsnes window:
    @window = gui::Window(256*2, 0, true);
    window.title = "Sprite VRAM";
    window.size = gui::Size(256, 512);

    @vl = gui::VerticalLayout();
    window.append(vl);

    @canvas = gui::Canvas();
    canvas.size = gui::Size(128, 256);
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
    ppu::vram.read_block(0x4000, 0, 0x2000, fgtiles);

    // draw VRAM as 4bpp tiles:
    sprites.canvas.fill(0x0000);
    sprites.canvas.draw_sprite_4bpp(0, 0, 0, 128, 256, fgtiles, palette);
  }
};

class BGWindow {
  private gui::Window @window;
  private gui::VerticalLayout @vl;
  gui::Canvas @canvas;

  array<uint16> bgtiles(0x2000);

  BGWindow() {
    // relative position to bsnes window:
    @window = gui::Window(256*3, 0, true);
    window.title = "BG VRAM";
    window.size = gui::Size(256, 512);

    @vl = gui::VerticalLayout();
    window.append(vl);

    @canvas = gui::Canvas();
    canvas.size = gui::Size(128, 256);
    vl.append(canvas, gui::Size(-1, -1));

    vl.resize();
    canvas.update();
    window.visible = true;
  }

  void update() {
    canvas.update();
  }

  void render(const array<uint16> &palette) {
    ppu::vram.read_block(0x2000, 0, 0x2000, bgtiles);

    bg.canvas.fill(0x0000);
    bg.canvas.draw_sprite_4bpp(0, 0, 0, 128, 256, bgtiles, palette);
  }
};

void init() {
  @sprites = SpriteWindow();
  //@bg = BGWindow();
}

array<array<uint16>> palette(16);

int pa = 0, pasub = 0;

void pre_frame() {
  // cycle palette:
  pasub++;
  if (pasub >= 96) {
    pasub = 0;
    pa++;
    if (pa >= 8) {
      pa = 0;
    }
  }

  // copy out all palettes:
  for (int c = 0; c < 16; c++) {
    palette[c] = array<uint16>(16);
    for (int i = 0; i < 16; i++) {
      palette[c][i] = ppu::cgram[(c << 4) + i];
    }
  }

  if (sprites != null) {
    sprites.render(palette[8 + pa]);
    sprites.update();
  }

  if (bg != null) {
    bg.render(palette[0 + pa]);
    bg.update();
  }
}
