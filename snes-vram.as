SpriteWindow @sprites;
BGWindow @bg;

class SpriteWindow {
  private gui::Window @window;
  gui::Canvas @canvas;

  SpriteWindow() {
    // relative position to bsnes window:
    @window = gui::Window(256*3, 0, true);
    window.title = "Sprite VRAM";
    window.size = gui::Size(256, 512);

    @canvas = gui::Canvas();
    canvas.size = gui::Size(128, 256);
    window.append(canvas);

    window.visible = true;
    canvas.update();
  }

  void update() {
    canvas.update();
  }
};

class BGWindow {
  private gui::Window @window;
  private gui::VerticalLayout @vl;
  gui::Canvas @canvas;

  BGWindow() {
    // relative position to bsnes window:
    @window = gui::Window(256*4, 0, true);
    window.title = "BG VRAM";
    window.size = gui::Size(256, 512);

    @vl = gui::VerticalLayout();
    window.append(vl);

    @canvas = gui::Canvas();
    canvas.size = gui::Size(128, 256);
    vl.append(canvas, gui::Size(0, 0));

    vl.resize();
    canvas.update();
    window.visible = true;
  }

  void update() {
    canvas.update();
  }
};

void init() {
  @sprites = SpriteWindow();
  @bg = BGWindow();
}

array<array<uint32>> fgtiles(0x200);
array<array<uint32>> bgtiles(0x200);
array<array<uint16>> palette(16);

void pre_frame() {
  // copy out palette 7:
  for (int c = 0; c < 16; c++) {
    palette[c] = array<uint16>(16);
    for (int i = 0; i < 16; i++) {
      palette[c][i] = ppu::cgram[(c << 4) + i];
    }
  }

  // fetch VRAM sprite tiles:
  for (int c = 0; c < 0x100; c++) {
    ppu::vram.read_sprite(0x4000, c, 8, 8, fgtiles[c]);
    ppu::vram.read_sprite(0x2000, c, 8, 8, bgtiles[c]);
  }
  for (int c = 0x100; c < 0x200; c++) {
    ppu::vram.read_sprite(0x5000, c, 8, 8, fgtiles[c]);
    ppu::vram.read_sprite(0x3000, c, 8, 8, bgtiles[c]);
  }
}

int pa = 0, pasub = 0;

void post_frame() {
  ppu::frame.alpha = 31;

  // cycle palette:
  pasub++;
  if (pasub >= 96) {
    pasub = 0;
    pa++;
    if (pa >= 8) {
      pa = 0;
    }
  }

  // clear canvas to zero alpha black:
  sprites.canvas.fill(0x0000);
  for (int c = 0; c < 0x200; c++) {
    auto x = 0 + (c & 15) * 8;
    auto y = 0 + (c >> 4) * 8;

    sprites.canvas.draw_sprite_4bpp(x, y, fgtiles[c], palette[8 + pa]);
  }
  sprites.update();

  bg.canvas.fill(0x0000);
  for (int c = 0; c < 0x200; c++) {
    auto x = 0 + (c & 15) * 8;
    auto y = 0 + (c >> 4) * 8;

    bg.canvas.draw_sprite_4bpp(x, y, bgtiles[c], palette[0 + pa]);
  }
  bg.update();
}
