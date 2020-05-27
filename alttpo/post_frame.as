
array<GameState@> onlyLocalPlayer(1);

void post_frame() {
  if (@oamWindow != null) {
    oamWindow.update();
  }

  if (@worldMapWindow != null) {
    worldMapWindow.update(local);
    if (sock is null) {
      @onlyLocalPlayer[0] = local;
      worldMapWindow.renderPlayers(local, onlyLocalPlayer);
    } else {
      worldMapWindow.renderPlayers(local, players);
    }
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

    //ppu::frame.text(188, 0, fmtHex(bus::read_u16(0x7E0708), 4));
    //ppu::frame.text(188, 8, fmtHex(bus::read_u16(0x7E070C), 4));

    //ppu::frame.text(224, 0, fmtHex(bus::read_u16(0x7E070A), 4));
    //ppu::frame.text(224, 8, fmtHex(bus::read_u16(0x7E070E), 4));

    // top-left WRAM $7e2000 offset
    //ppu::frame.text(224, 0, fmtHex(bus::read_u16(0x7E0084) >> 1, 4));
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
