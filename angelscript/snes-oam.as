// AngelScript to debug OAM sprites with a wall of text

// shows OAM sprite index contents; character value only; grays out text for sprites that are not visible
void post_frame() {
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

    ppu::frame.text((i / 28) * (4*8 + 8) + 16, (i % 28) * 8, fmtHex(tile.character, 2));
  }
}
