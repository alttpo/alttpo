// AngelScript to draw rectangles around OAM sprites.
array<uint8> link_chrs = {0x00, 0x02, 0x04, 0x05, 0x06, 0x07, 0x15};
// {0xc8, 0xc9, 0xca} are grass swish tiles around link but also around other grass-dwelling sprites
// 0x6c is half of a shadow under link (hflipped to complete oval), but is used by other sprites too

void post_frame_boo() {
  ppu::frame.draw_op = ppu::draw_op::op_alpha;
  ppu::frame.color = ppu::rgb(28, 28, 28);
  ppu::frame.alpha = 16;

  for (int i = 0; i < 128; i++) {
    // Set OAM access index to read sprite properties from:
    ppu::oam.index = i;

    // grab X coordinate which is useful for checking if a sprite is off-screen:
    int x = int(ppu::oam.x);

    // adjust x to allow for slightly off-screen sprites:
    if (x >= 256) x -= 512;

    // width height here is a hack; need to get proper width,height in pixels from OAM and PPU state
    auto width = (ppu::oam.size + 1) * 8;
    auto height = (ppu::oam.size + 1) * 8;

    // skip sprite if truly invisible:
    if (x <= -width) continue;
    if (x >= 256) continue;

    auto y = ppu::oam.y;

    auto chr = ppu::oam.character;
    /*
    if (chr == 0x6c) {
      if (ppu::oam.hflip == false) continue;
      //ppu::frame.text(x+8, y-8, fmtHex(i, 2));
      continue; // skip shadows under sprites
    }
    */
    //ppu::frame.text(x+8, y-8, fmtHex(i, 2));
    //continue;

    if (link_chrs.find(chr) >= 0) continue;

    auto palette = ppu::oam.palette;
    ppu::frame.rect(x, y, width, height);

    //if (ppu::oam.hflip == 1) continue;
    ppu::frame.text(x+8, y-8, fmtHex(chr >> 4, 1));
    ppu::frame.text(x+16, y-8, fmtHex(chr, 1));
  }
}

void pre_frame() {
  array<uint32> tiledata(32);
  array<uint16> palette(16);

  // copy out palette 7:
  for (int i = 0; i < 16; i++) {
    palette[i] = ppu::cgram[128 + (7 << 4) + i];
  }

  // render VRAM tiles:
  int t = 0;
  for (int c = 0; c < 0x100; c++) {
    ppu::vram.read_sprite(0x4000, c, 8, 8, tiledata);
    auto s = ppu::extra[t];
    s.x = 128 + (c & 15) * 8;
    s.y = (224 - 128) + (c >> 4) * 8;
    s.source = 5;
    s.priority = 3;
    s.width = 16;
    s.height = 16;
    s.hflip = false;
    s.vflip = false;
    s.pixels_clear();
    s.draw_sprite(0, 0, 8, 8, tiledata, palette);
    t++;
  }

  ppu::extra.count = t;
}

void post_frame() {
  ppu::frame.draw_op = ppu::draw_op::op_alpha;
  ppu::frame.color = ppu::rgb(28, 28, 28);
  ppu::frame.alpha = 16;

  //string msg = "";
  int numsprites = 0;
  for (int i = 0; i < 128; i++) {
    // access current OAM sprite index:
    ppu::oam.index = i;

    // skip OAM sprite if not enabled (X coord is out of display range):
    if (!ppu::oam.is_enabled) continue;

    if (ppu::oam.nameselect) continue;

    auto chr = ppu::oam.character;
    // not a Link-related sprite?
    if (link_chrs.find(chr) == -1) continue;

    auto size = ppu::oam.size;
    auto width = ppu::sprite_width(ppu::sprite_base_size(), size);
    auto height = ppu::sprite_height(ppu::sprite_base_size(), size);

    auto x = int(ppu::oam.x);
    auto y = int(ppu::oam.y);

    if (x >= 256) x -= 512;

    ppu::frame.rect(x, y, width, height);

    ++numsprites;
    //msg = msg + fmtHex(y, 2) + " ";
  }

  //message(msg);
}
