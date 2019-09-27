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
    auto tile = ppu::oam[i];

    // grab X coordinate which is useful for checking if a sprite is off-screen:
    int x = int(tile.x);

    // adjust x to allow for slightly off-screen sprites:
    if (x >= 256) x -= 512;

    // width height here is a hack; need to get proper width,height in pixels from OAM and PPU state
    auto width = (tile.size + 1) * 8;
    auto height = (tile.size + 1) * 8;

    // skip sprite if truly invisible:
    if (x <= -width) continue;
    if (x >= 256) continue;

    auto y = tile.y;

    auto chr = tile.character;
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

    auto palette = tile.palette;
    ppu::frame.rect(x, y, width, height);

    //if (ppu::oam.hflip == 1) continue;
    ppu::frame.text(x+8, y-8, fmtHex(chr >> 4, 1));
    ppu::frame.text(x+16, y-8, fmtHex(chr, 1));
  }
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

  for (int c = 0; c < 0x200; c++) {
    auto x = 128 + (c & 15) * 8;
    auto y = (224 - 256) + (c >> 4) * 8;

    ppu::frame.draw_4bpp_8x8(x, y, tiles[c], palette[pa]);
  }
}

int16 link_x, link_y, link_z, link_floor_y, xoffs, yoffs, rx, ry;

void pre_frame_alttp1() {
  //   $7E0020[2] = Link's Y coordinate
  link_y = int16(bus::read_u16(0x7E0020, 0x7E0021));
  //   $7E0022[2] = Link's X coordinate
  link_x = int16(bus::read_u16(0x7E0022, 0x7E0023));
  //   $7E0024[2] = Link's Z coordinate ($FFFF usually)
  link_z = int16(bus::read_u16(0x7E0024, 0x7E0025));

  link_floor_y = int16(bus::read_u16(0x7E0051, 0x7E0052));

  //auto in_dark_world = bus::read_u8(0x7E0FFF);
  //auto in_dungeon = bus::read_u8(0x7E001B);
  //auto overworld_room = bus::read_u16(0x7E008A, 0x7E008B);
  //auto dungeon_room = bus::read_u16(0x7E00A0, 0x7E00A1);

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

  //ppu::frame.text(0, 0, fmtHex(link_x, 4) + "," + fmtHex(link_y, 4) + "," + fmtHex(link_z, 4) + "  " + fmtHex(link_floor_y, 4));

  // draw some debug info:
  for (int i = 0; i < 16; i++) {
    switch (i & 3) {
      case 0: ppu::frame.color = ppu::rgb(28, 28, 28); break;
      case 1: ppu::frame.color = ppu::rgb(28, 28,  0); break;
      case 2: ppu::frame.color = ppu::rgb(28,  0, 28); break;
      case 3: ppu::frame.color = ppu::rgb( 0, 28, 28); break;
    }
    ppu::frame.text(i * 16, 224-32, fmtHex(bus::read_u8(0x7E0110 + i), 2));
  }
}

// shows OAM sprite index contents; character value only; grays out text for sprites that are not visible
void post_frame_oam() {
  ppu::frame.draw_op = ppu::draw_op::op_alpha;
  ppu::frame.color = ppu::rgb(28, 28, 28);
  ppu::frame.alpha = 28;
  ppu::frame.text_shadow = true;

  for (int i = 0; i < 128; i++) {
    // access current OAM sprite index:
    auto tile = ppu::oam[i];

    auto chr = tile.character;
    auto x = int16(tile.x);
    auto y = int16(tile.y);
    if (x >= 256) x -= 512;

    //ppu::frame.rect(x, y, width, height);

    ppu::frame.color = ppu::rgb(28, 28, 0);
    ppu::frame.text((i / 28) * (4*8 + 8), (i % 28) * 8, fmtHex(i, 2));

    if (tile.is_enabled) {
      ppu::frame.color = ppu::rgb(28, 28, 28);
    } else {
      ppu::frame.color = ppu::rgb(8, 8, 12);
    }

    ppu::frame.text((i / 28) * (4*8 + 8) + 16, (i % 28) * 8, fmtHex(chr, 2));
  }
}
