ROMSpritesWindow @romSprites;

const int romScale = 3;

const int romPages = 7;
const int romCols = 2;
const int romRows = 2;

class ROMSpritesWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  GUI::SNESCanvas @canvas;

  array<uint16> data(0x1000 * romPages);

  ROMSpritesWindow() {
    // relative position to bsnes window:
    @window = GUI::Window(0, 240*3, true);
    window.title = "ROM Sprites";
    window.size = GUI::Size(128*romScale*romCols, 128*romScale*romRows);

    @vl = GUI::VerticalLayout();
    window.append(vl);

    @canvas = GUI::SNESCanvas();
    canvas.size = GUI::Size(128*romCols, 128*romRows);
    vl.append(canvas, GUI::Size(-1, -1));

    vl.resize();
    canvas.update();
    window.visible = true;
  }

  void update() {
    canvas.update();
  }

  void render(const array<uint16> &palette) {
    bus::read_block_u16(0x108000, 0, 0x800 * romPages, data);

    // draw 4bpp tiles:
    canvas.fill(0x0000);
    for (int page = 0; page < romPages; page++) {
      int col = page % romCols;
      int row = page / romCols;
      canvas.draw_sprite_4bpp(128*col, 128*row, 0x100 * page, 128, 128, data, palette);
    }
  }
};
