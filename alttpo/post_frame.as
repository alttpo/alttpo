
void post_frame() {
  if (@oamWindow != null) {
    oamWindow.update();
  }

  if (@worldMapWindow != null) {
    worldMapWindow.update(local);
    worldMapWindow.renderPlayers();
  }

  if (debugData) {
    ppu::frame.text_shadow = true;
    ppu::frame.color = 0x7fff;
    ppu::frame.text( 0, 0, fmtHex(local.module, 2));
    ppu::frame.text(20, 0, fmtHex(local.sub_module, 2));
    ppu::frame.text(40, 0, fmtHex(local.sub_sub_module, 2));

    ppu::frame.text(60, 0, fmtHex(local.actual_location, 6));
    //ppu::frame.text(60, 0, fmtHex(local.in_dark_world, 1));
    //ppu::frame.text(68, 0, fmtHex(local.in_dungeon, 1));
    //ppu::frame.text(76, 0, fmtHex(local.overworld_room, 2));
    //ppu::frame.text(92, 0, fmtHex(local.dungeon_room, 2));

    ppu::frame.text(112, 0, fmtHex(local.x, 4));
    ppu::frame.text(152, 0, fmtHex(local.y, 4));

    //ppu::frame.text(188, 0, fmtHex(bus::read_u8(0x7E009A), 2));

    //ppu::frame.text(188, 0, fmtHex(bus::read_u16(0x7E0708), 4));
    //ppu::frame.text(188, 8, fmtHex(bus::read_u16(0x7E070C), 4));

    //ppu::frame.text(224, 0, fmtHex(bus::read_u16(0x7E070A), 4));
    //ppu::frame.text(224, 8, fmtHex(bus::read_u16(0x7E070E), 4));

    // top-left WRAM $7e2000 offset
    //ppu::frame.text(224, 16, fmtHex(bus::read_u16(0x7E0084), 4));

    // last entrance number in dungeon:
    //ppu::frame.text(224, 8, fmtHex(bus::read_u16(0x7E010E), 4));

    // heart pieces, heart containers:
    //ppu::frame.text(224,  8, fmtHex(bus::read_u16(0x7EF36B), 4));
    // freeze link:
    //ppu::frame.text(224, 16, fmtHex(bus::read_u8 (0x7E02E4), 2));

    // Link's map16 tilemap coords:
    ppu::frame.text(224, 0, fmtHex(
      ((((bus::read_u16(0x7E0022) + 0x08) >> 3) - bus::read_u16(0x7E070C)) & bus::read_u16(0x7E070E)) +
      (((bus::read_u16(0x7E0020) + 0x0C - bus::read_u16(0x7E0708)) & bus::read_u16(0x7E070A)) << 3),
      4
    ));
  }

  if (@sprites != null) {
    for (int i = 0; i < 16; i++) {
      palette7[i] = ppu::cgram[(15 << 4) + i];
    }
    sprites.render(palette7);
    sprites.update();
  }

  if (@gameSpriteWindow != null) {
    gameSpriteWindow.update();
  }
}
