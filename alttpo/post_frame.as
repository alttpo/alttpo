
void post_frame() {
  //message("post_frame");

  if (oamWindow !is null) {
    oamWindow.update();
  }

  if (worldMapWindow !is null) {
    worldMapWindow.update(local);
    worldMapWindow.renderPlayers();
  }

  if (debugReadout) {
    ppu::frame.text_shadow = true;
    ppu::frame.color = 0x7fff;

    if (rom.is_alttp()) {
      ppu::frame.text( 0, 0, fmtHex(local.module, 2));
      ppu::frame.text(20, 0, fmtHex(local.sub_module, 2));
      ppu::frame.text(40, 0, fmtHex(local.sub_sub_module, 2));

      ppu::frame.text(60, 0, fmtHex(local.actual_location, 6));
      //ppu::frame.text(60, 0, fmtHex(local.in_dark_world, 1));
      //ppu::frame.text(68, 0, fmtHex(local.in_dungeon, 1));
      //ppu::frame.text(76, 0, fmtHex(local.overworld_room, 2));
      //ppu::frame.text(92, 0, fmtHex(local.dungeon_room, 2));

      //ppu::frame.text(112, 0, fmtHex(local.dungeon, 4));
      //ppu::frame.text(148, 0, fmtHex(local.dungeon_entrance, 4));
      //ppu::frame.text(184, 0, fmtHex(bus::read_u16(0x7E0696), 4));

      ppu::frame.text(112, 0, fmtHex(local.x, 4));
      ppu::frame.text(148, 0, fmtHex(local.y, 4));

      //ppu::frame.text(184, 0, fmtHex(bus::read_u16(0x7E0708), 4));
      //ppu::frame.text(184, 8, fmtHex(bus::read_u16(0x7E070C), 4));

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
      //ppu::frame.text(224, 0, fmtHex(
      //  ((((bus::read_u16(0x7E0022) + 0x08) >> 3) - bus::read_u16(0x7E070C)) & bus::read_u16(0x7E070E)) +
      //  (((bus::read_u16(0x7E0020) + 0x0C - bus::read_u16(0x7E0708)) & bus::read_u16(0x7E070A)) << 3),
      //  4
      //));

      //// water rooms:
      //ppu::frame.text(224,  0, fmtHex(bus::read_u8(0x7E0403), 2));
      //ppu::frame.text(224,  8, fmtHex(bus::read_u8(0x7E0424), 2));
      //ppu::frame.text(224, 16, fmtHex(bus::read_u8(0x7E045C), 2));
      //ppu::frame.text(224, 24, fmtHex(bus::read_u8(0x7E0642), 2));

      // item limits for alttpr:
      //for (uint i = 0; i < 0x10; i++) {
      //  ppu::frame.text(224, i<<3, fmtHex(bus::read_u8(0x7EF390 + i), 2));
      //}

      // chest counters:
      //for (uint i = 0; i < 0x10; i++) {
      //  ppu::frame.text(224, (5+i)<<3, fmtHex(bus::read_u8(0x7EF4C0 + i), 2));
      //  //ppu::frame.text(224, (7+i)<<3, fmtHex(bus::read_u8(0x7EF434 + i), 2));
      //  //ppu::frame.text(224, (7+i)<<3, fmtHex(local.sram[0x434 + i], 2));
      //}
    } else {
      // SM game state:
      ppu::frame.text(  0,  0, fmtHex(bus::read_u8(0x7E0998), 2));
    }
  }

  if (sprites !is null) {
    for (int i = 0; i < 16; i++) {
      palette7[i] = ppu::cgram[(15 << 4) + i];
    }
    sprites.render(palette7);
    sprites.update();
  }

  if (gameSpriteWindow !is null) {
    gameSpriteWindow.update();
  }

  if (memoryWindow !is null) {
    memoryWindow.update();
  }

  if (rom !is null) {
    rom.calc_action_hitbox();
    if (rom.action_hitbox_active) {
      int rx = int(rom.action_hitbox_x - local.xoffs);
      int ry = int(rom.action_hitbox_y - local.yoffs);

      ppu::frame.rect(rx, ry, rom.action_hitbox_width, rom.action_hitbox_height);
    }
  }
}
