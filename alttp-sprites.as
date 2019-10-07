// AngelScript for ALTTP to draw white rectangles around in-game sprites
uint16   xoffs, yoffs;
uint16[] sprx(16);
uint16[] spry(16);
uint8[]  sprs(16);
uint8[]  sprk(16);
uint32   location;

uint8 module, sub_module;
// top -> $4000, bot -> $4100
array<uint16> dma10top(3), dma10bot(3);
array<uint16> dma7Etop(6), dma7Ebot(6);

uint8 sp00, sp50, sp60, sp61;

void init() {
  // initialize script state here.
  message("hello world!");
}

void pre_frame() {
  module     = bus::read_u8(0x7E0010);
  sub_module = bus::read_u8(0x7E0011);

  // [$10]$0ACE -> $4100 (0x40 bytes) (bottom of head)
  // [$10]$0AD2 -> $4120 (0x40 bytes) (bottom of body)
  // [$10]$0AD6 -> $4140 (0x20 bytes) (bottom sweat)

  dma10bot[0] = bus::read_u16(0x7E0ACE, 0x7E0ACF);
  dma10bot[1] = bus::read_u16(0x7E0AD2, 0x7E0AD3);
  dma10bot[2] = bus::read_u16(0x7E0AD6, 0x7E0AD7);

  // [$10]$0ACC -> $4000 (0x40 bytes) (top of head)
  // [$10]$0AD0 -> $4020 (0x40 bytes) (top of body)
  // [$10]$0AD4 -> $4040 (0x20 bytes) (top sweat)

  dma10top[0] = bus::read_u16(0x7E0ACC, 0x7E0ACD);
  dma10top[1] = bus::read_u16(0x7E0AD0, 0x7E0AD1);
  dma10top[2] = bus::read_u16(0x7E0AD4, 0x7E0AD5);

  // [$7E]$0AC0 -> $4050 (0x40 bytes) (top of sword slash)
  // [$7E]$0AC4 -> $4070 (0x40 bytes) (top of shield)
  // [$7E]$0AC8 -> $4090 (0x40 bytes) (Zz sprites)
  // [$7E]$0AE0 -> $40B0 (0x20 bytes) (top of rupee)
  // [$7E]$0AD8 -> $40C0 (0x40 bytes) (top of movable block)

  dma7Etop[0] = bus::read_u16(0x7E0AC0, 0x7E0AC1);
  dma7Etop[1] = bus::read_u16(0x7E0AC4, 0x7E0AC5);
  dma7Etop[2] = bus::read_u16(0x7E0AC8, 0x7E0AC9);
  dma7Etop[3] = bus::read_u16(0x7E0AE0, 0x7E0AE1);
  dma7Etop[4] = bus::read_u16(0x7E0AD8, 0x7E0AD9);

  // only if bird is active
  // [$7E]$0AF6 -> $40E0 (0x40 bytes) (top of hammer sprites)
  dma7Etop[5] = bus::read_u16(0x7E0AF6, 0x7E0AF7);

  // [$7E]$0AC2 -> $4150 (0x40 bytes) (bottom of sword slash)
  // [$7E]$0AC6 -> $4170 (0x40 bytes) (bottom of shield)
  // [$7E]$0ACA -> $4190 (0x40 bytes) (music note sprites)
  // [$7E]$0AE2 -> $41B0 (0x20 bytes) (bottom of rupee)
  // [$7E]$0ADA -> $41C0 (0x40 bytes) (bottom of movable block)

  dma7Ebot[0] = bus::read_u16(0x7E0AC2, 0x7E0AC3);
  dma7Ebot[1] = bus::read_u16(0x7E0AC6, 0x7E0AC7);
  dma7Ebot[2] = bus::read_u16(0x7E0ACA, 0x7E0ACB);
  dma7Ebot[3] = bus::read_u16(0x7E0AE2, 0x7E0AE3);
  dma7Ebot[4] = bus::read_u16(0x7E0ADA, 0x7E0ADB);

  // only if bird is active
  // [$7E]$0AF8 -> $41E0 (0x40 bytes) (bottom of hammer sprites)
  dma7Ebot[5] = bus::read_u16(0x7E0AF8, 0x7E0AF9);

  sp00 = bus::read_u8(0x7E0AAC);
  sp50 = bus::read_u8(0x7E0AAD);
  sp60 = bus::read_u8(0x7E0AAE);
  sp61 = bus::read_u8(0x7E0AB1);

  // fetch various room indices and flags about where exactly Link currently is:
  auto in_dark_world  = bus::read_u8 (0x7E0FFF);
  auto in_dungeon     = bus::read_u8 (0x7E001B);
  auto overworld_room = bus::read_u16(0x7E008A, 0x7E008B);
  auto dungeon_room   = bus::read_u16(0x7E00A0, 0x7E00A1);

  // compute aggregated location for Link into a single 24-bit number:
  location =
    uint32(in_dark_world & 1) << 17 |
    uint32(in_dungeon & 1) << 16 |
    uint32(in_dungeon != 0 ? dungeon_room : overworld_room);

  // get screen x,y offset by reading BG2 scroll registers:
  xoffs = bus::read_u16(0x7E00E2, 0x7E00E3);
  yoffs = bus::read_u16(0x7E00E8, 0x7E00E9);

  for (int i = 0; i < 16; i++) {
    // sprite x,y coords are absolute from BG2 top-left:
    spry[i] = bus::read_u16(0x7E0D00 + i, 0x7E0D20 + i);
    sprx[i] = bus::read_u16(0x7E0D10 + i, 0x7E0D30 + i);
    // sprite state (0 = dead, else alive):
    sprs[i] = bus::read_u8(0x7E0DD0 + i);
    // sprite kind:
    sprk[i] = bus::read_u8(0x7E0E20 + i);
  }
}

void post_frame() {
  // set drawing state
  // select 8x8 or 8x16 font for text:
  ppu::frame.font_height = 8;
  // draw using alpha blending:
  ppu::frame.draw_op = ppu::draw_op::op_alpha;
  // alpha is xx/31:
  ppu::frame.alpha = 20;
  // color is 0x7fff aka white (15-bit RGB)
  ppu::frame.color = ppu::rgb(31, 31, 31);

  // enable shadow under text for clearer reading:
  ppu::frame.text_shadow = true;

  // module/sub_module:
  ppu::frame.text(0, 0, fmtHex(module, 2));
  ppu::frame.text(20, 0, fmtHex(sub_module, 2));

  // draw Link's location value in top-left:
  ppu::frame.text(40, 0, fmtHex(location, 6));

  for (uint i = 0; i < 3; i++) {
    ppu::frame.text(i * (4 * 8 + 4), 224 - 24, fmtHex(dma10top[i], 4));
    ppu::frame.text(i * (4 * 8 + 4), 224 - 32, fmtHex(dma10bot[i], 4));

    ppu::frame.text(i * (4 * 8 + 4), 224 -  8, fmtHex(dma7Etop[i], 4));
    ppu::frame.text(i * (4 * 8 + 4), 224 - 16, fmtHex(dma7Ebot[i], 4));
  }

  for (uint i = 3; i < 6; i++) {
    ppu::frame.text(i * (4 * 8 + 4), 224 -  8, fmtHex(dma7Etop[i], 4));
    ppu::frame.text(i * (4 * 8 + 4), 224 - 16, fmtHex(dma7Ebot[i], 4));
  }

  ppu::frame.text( 0, 224 - 40, fmtHex(sp00, 2));
  ppu::frame.text(20, 224 - 40, fmtHex(sp50, 2));
  ppu::frame.text(40, 224 - 40, fmtHex(sp60, 2));
  ppu::frame.text(60, 224 - 40, fmtHex(sp61, 2));

  for (int i = 0; i < 16; i++) {
    // skip dead sprites:
    if (sprs[i] == 0) continue;

    // subtract BG2 offset from sprite x,y coords to get local screen coords:
    int16 rx = int16(sprx[i]) - int16(xoffs);
    int16 ry = int16(spry[i]) - int16(yoffs);

    // draw box around the sprite:
    ppu::frame.rect(rx, ry, 16, 16);

    // draw sprite type value above box:
    ry -= ppu::frame.font_height;
    ppu::frame.text(rx, ry, fmtHex(sprk[i], 2));
  }
}
