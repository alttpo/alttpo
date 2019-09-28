ToolWindow @tool;

class ToolWindow {
  private gui::Window @window;
  gui::Canvas @canvas;

  ToolWindow() {
    // relative position to bsnes window:
    @window = gui::Window(256, 0, true);
    window.title = "Sprite VRAM";
    window.size = gui::Size(256, 256);
    window.visible = true;

    @canvas = gui::Canvas();
    canvas.size = gui::Size(256, 256);
    canvas.update();
    window.append(canvas);
  }

  void update() {
    canvas.update();
  }
};

void init() {
  @tool = ToolWindow();
}

array<array<uint32>> tiles(0x200);
array<array<uint16>> palette(8);

void pre_frame() {
  // copy out palette 7:
  for (int c = 0; c < 8; c++) {
    palette[c] = array<uint16>(16);
    for (int i = 0; i < 16; i++) {
      palette[c][i] = ppu::cgram[128 + (c << 4) + i];
    }
  }

  // fetch VRAM sprite tiles:
  for (int c = 0; c < 0x100; c++) {
    ppu::vram.read_sprite(0x4000, c, 8, 8, tiles[c]);
  }
  for (int c = 0x100; c < 0x200; c++) {
    ppu::vram.read_sprite(0x5000, c, 8, 8, tiles[c]);
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
  tool.canvas.fill(0x0000);
  for (int c = 0; c < 0x200; c++) {
    auto x = 0 + (c & 15) * 8;
    auto y = 0 + (c >> 4) * 8;

    tool.canvas.draw_sprite_4bpp(x, y, tiles[c], palette[pa]);
  }

  tool.update();
}
