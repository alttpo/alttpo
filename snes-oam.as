// AngelScript to draw rectangles around OAM sprites.
array<uint8> link_chrs = {0x00, 0x02, 0x04, 0x05, 0x06, 0x07, 0x15, 0x28};
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

void pre_frame_poop() {
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
    if (t >= 128) break;
    auto s = ppu::extra[t];
    s.index = 0;
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

int16 link_x, link_y, link_z, link_floor_y, xoffs, yoffs, rx, ry;

void pre_frame() {
  //   $7E0020[2] = Link's Y coordinate
  link_y = int16(bus::read_u16(0x7E0020, 0x7E0021));
  //   $7E0022[2] = Link's X coordinate
  link_x = int16(bus::read_u16(0x7E0022, 0x7E0023));
  //   $7E0024[2] = Link's Z coordinate ($FFFF usually)
  link_z = int16(bus::read_u16(0x7E0024, 0x7E0025));

  link_floor_y = int16(bus::read_u16(0x7E0051, 0x7E0052));

  // get screen x,y offset by reading BG2 scroll registers:
  xoffs = int16(bus::read_u16(0x7E00E2, 0x7E00E3));
  yoffs = int16(bus::read_u16(0x7E00E8, 0x7E00E9));

  // get link's on-screen coordinates in OAM space:
  rx = int16(link_x) - xoffs;
  ry = int16(link_y) - yoffs;
}

void post_frame_alttp1() {
  ppu::frame.draw_op = ppu::draw_op::op_alpha;
  ppu::frame.color = ppu::rgb(28, 28, 28);
  ppu::frame.alpha = 24;

  ppu::frame.text(0, 0, fmtHex(link_x, 4) + "," + fmtHex(link_y, 4) + "," + fmtHex(link_z, 4) + "  " + fmtHex(link_floor_y, 4));


  // draw some debug info:
  for (int i = 0; i < 16; i++) {
    ppu::frame.text(i * 16, 224- 8, fmtHex(bus::read_u8(0x7E0050 + i), 2));
  }


  //string msg = "";
  int numsprites = 0;
  for (int i = 0; i < 128; i++) {
    // access current OAM sprite index:
    ppu::oam.index = i;

    // skip OAM sprite if not enabled (X coord is out of display range):
    if (!ppu::oam.is_enabled) continue;

    if (ppu::oam.nameselect) continue;

    auto chr = ppu::oam.character;
    if (chr != 0x6c && chr != 0x38 && chr != 0x28) continue;
    if (ppu::oam.hflip) continue;

    auto width = ppu::oam.width;
    auto height = ppu::oam.height;

    auto x = int16(ppu::oam.x);
    auto y = int16(ppu::oam.y);

    if (x >= 256) x -= 512;

    ppu::frame.rect(x, y, width, height);

    auto distx = x - rx;
    auto disty = y - ry;

    ppu::frame.text(x+16, y-8, fmtInt(x - rx) + "," + fmtInt(y - ry));

    ++numsprites;
    //msg = msg + fmtHex(y, 2) + " ";
  }

  //message(msg);
}

// shows OAM sprite index contents; character value only; grays out text for sprites that are not visible
void post_frame() {
  ppu::frame.draw_op = ppu::draw_op::op_alpha;
  ppu::frame.color = ppu::rgb(28, 28, 28);
  ppu::frame.alpha = 28;
  ppu::frame.text_shadow = true;

  for (int i = 0; i < 128; i++) {
    // access current OAM sprite index:
    ppu::oam.index = i;

    auto chr = ppu::oam.character;
    auto x = int16(ppu::oam.x);
    auto y = int16(ppu::oam.y);
    if (x >= 256) x -= 512;

    //ppu::frame.rect(x, y, width, height);

    ppu::frame.color = ppu::rgb(28, 28, 0);
    ppu::frame.text((i / 28) * (4*8 + 8), (i % 28) * 8, fmtHex(i, 2));

    if (ppu::oam.is_enabled) {
      ppu::frame.color = ppu::rgb(28, 28, 28);
    } else {
      ppu::frame.color = ppu::rgb(8, 8, 12);
    }

    ppu::frame.text((i / 28) * (4*8 + 8) + 16, (i % 28) * 8, fmtHex(chr, 2));
  }
}
