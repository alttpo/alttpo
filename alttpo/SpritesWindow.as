SpritesWindow @sprites;
array<uint16> palette7(16);

const int scale = 3;

class SpritesWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  GUI::SNESCanvas @canvas;

  array<uint16> page0(0x1000);
  array<uint16> page1(0x1000);

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

    vl.resize();
    canvas.update();
    window.visible = true;
  }

  void update() {
    canvas.update();
  }

  void render(const array<uint16> &palette) {
    // read VRAM:
    ppu::vram.read_block(0x6000, 0, 0x1000, page0);
    ppu::vram.read_block(0x7000, 0, 0x1000, page1);
	
	array<uint16> temp_palette(palette.length());
	uint8 temp = 0x1F;
	if (temp > palette.length()){
		temp = palette.length();
	}
	bus::read_block_u16(0x7eC180, 0, temp, temp_palette);
	
    // draw VRAM as 4bpp tiles:
    canvas.fill(0xFFFF);
    canvas.draw_sprite_4bpp(  0, 0, 0, 128, 128, page0, temp_palette);
    canvas.draw_sprite_4bpp(128, 0, 0, 128, 128, page1, palette);
  }
};
