
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
