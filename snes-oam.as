// AngelScript to draw rectangles around OAM sprites.

void post_frame() {
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
    auto palette = ppu::oam.palette;
    auto chr = ppu::oam.character;
    ppu::frame.rect(x, y, width, height);
    //ppu::frame.text(x, y-8, fmtHex(palette, 1));
    //ppu::frame.text(x, y-16, fmtHex(chr, 2));
  }
}
