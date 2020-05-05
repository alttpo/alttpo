// ALTTP script to draw current Link sprites on top of rendered frame:
net::Socket@ sock;
net::Address@ address;
SettingsWindow @settings;

bool debug = false;
bool debugData = false;
bool debugOAM = false;
bool debugSprites = false;
bool debugGameObjects = false;

void init() {
  // Auto-detect ROM version:
  @rom = detect();

  @settings = SettingsWindow();
  settings.ServerAddress = "bittwiddlers.org";
  settings.Group = "enemy-sync";
  settings.Name = "";
  if (debug) {
    //settings.ServerAddress = "127.0.0.1";
    //settings.Group = "debug";
    settings.start();
    settings.hide();
  }

  if (debugSprites) {
    @sprites = SpritesWindow();
  }

  @worldMap = WorldMap();

  if (debugOAM) {
    @oamWindow = OAMWindow();
  }

  if (debugGameObjects) {
    @gameSpriteWindow = GameSpriteWindow();
  }
}

// TODO: debug window to show current full area and place GameSprites on it with X,Y coordinates

GameState local;
array<GameState@> players(0);
uint8 isRunning;

bool intercepting = false;

void pre_frame() {
  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;

  if (null == @sock) return;

  //message("pre-frame");

  // backup VRAM for OAM tiles which are in-use by game:
  localFrameState.backup();

  // fetch local VRAM data for sprites:
  local.capture_sprites_vram();

  // send updated state for our Link to server:
  local.send();

  // receive network updates from remote players:
  receive();

  // render remote players:
  for (uint i = 0; i < players.length(); i++) {
    auto @remote = players[i];
    if (@remote == null) continue;

    if (@remote == @local) continue;
    if (remote.ttl <= 0) {
      remote.ttl = 0;
      continue;
    }

    remote.ttl = remote.ttl - 1;

    remote.update_rooms_sram();

    // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
    if (local.can_see(remote.location)) {
      // subtract BG2 offset from sprite x,y coords to get local screen coords:
      int16 rx = int16(remote.x) - local.xoffs;
      int16 ry = int16(remote.y) - local.yoffs;

      // draw remote player relative to current BG offsets:
      remote.render(rx, ry);

      // update current room state in WRAM:
      remote.update_room_current();

      // update tilemap:
      remote.update_tilemap();
    }
  }

  {
    // synchronize torches:
    if (local.is_in_dungeon()) {
      for (uint i = 0; i < players.length(); i++) {
        auto @remote = players[i];
        if (@remote == null) continue;
        if (remote.ttl <= 0) continue;
        if (!local.can_see(remote.location)) continue;

        for (uint t = 0; t < 0x10; t++) {
          if (remote.torchTimers[t] > local.torchTimers[t]) {
            local.torchTimers[t] = remote.torchTimers[t];
            bus::write_u8(0x7E04F0 + t, local.torchTimers[t]);
          }
        }
      }

      // recalculate torch lit count:
      uint8 count = 0;
      for (uint t = 0; t < 0x10; t++) {
        if (local.torchTimers[t] > 0) {
          count++;
        }
      }
      //bus::write_u8(0x7E045A, count);
    }
  }

  {
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;
      if (remote.ttl <= 0) continue;
      if (!local.can_see(remote.location)) continue;

      //message("[" + fmtInt(i) + "].ancillae.len = " + fmtInt(remote.ancillae.length()));
      if (remote is local) {
        continue;
      }

      if (remote.ancillae.length() > 0) {
        for (uint j = 0; j < remote.ancillae.length(); j++) {
          auto @an = remote.ancillae[j];
          auto k = an.index;

          if (k < 0x05) {
            // Doesn't work; needs more debugging.
            if (false) {
              // if local player picks up remotely owned ancillae:
              if (local.ancillae[k].held == 3 && an.held != 3) {
                an.requestOwnership = false;
                local.ancillae[k].requestOwnership = true;
                local.ancillaeOwner[k] = local.index;
              }
            }
          }

          // ownership transfer:
          if (an.requestOwnership) {
            local.ancillae[k].requestOwnership = false;
            local.ancillaeOwner[k] = remote.index;
          }

          if (local.ancillaeOwner[k] == remote.index) {
            an.writeRAM();
            if (an.type == 0) {
              // clear owner if type went to 0:
              local.ancillaeOwner[k] = -1;
              local.ancillae[k].requestOwnership = false;
            }
          } else if (local.ancillaeOwner[k] == -1 && an.type != 0) {
            an.writeRAM();
            local.ancillaeOwner[k] = remote.index;
            local.ancillae[k].requestOwnership = false;
          }
        }
      }

      continue;
    }
  }

  if (false) {
    auto updated_objects = false;

    // update objects state from lowest-indexed player in the room:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;
      if (remote.ttl <= 0) continue;
      if (!local.can_see(remote.location)) continue;

      if (!updated_objects && remote.objectsBlock.length() == 0x2A0) {
        updated_objects = true;
        local.objects_index_source = i;
      }
    }

    if (updated_objects) {
      if (local.objects_index_source == local.index) {
        // we are the player that controls the objects in the room. run through each player in the same room
        // and synchronize any attempted changes to objects.

      } else {
        // we are not in control of objects in the room so just copy the state from the player who is:
        //bus::write_block_u8(0x7E0D00, 0, 0x2A0, remote.objectsBlock);

        auto @remote = players[local.objects_index_source];
        for (uint j = 0; j < 0x10; j++) {
          GameSprite r;
          GameSprite l;
          r.readFromBlock(remote.objectsBlock, j);
          l.readRAM(j);

          // don't overwrite locally picked up objects:
          if (l.state == 0x0A) continue;
          // don't copy in remotely picked up objects:
          if (r.state == 0x0A) r.state = 0;
          r.writeRAM();
        }
      }
    }
  }

  local.update_items();

  if (@worldMap != null) {
    worldMap.renderPlayers(local, players);
  }
}

void post_frame() {
  if (@oamWindow != null) {
    oamWindow.update();
  }

  if (@worldMap != null) {
    worldMap.loadMap();
    worldMap.drawMap();
  }

  if (debugData) {
    ppu::frame.text_shadow = true;
    ppu::frame.color = 0x7fff;
    ppu::frame.text( 0, 0, fmtHex(local.module, 2));
    ppu::frame.text(20, 0, fmtHex(local.sub_module, 2));
    ppu::frame.text(40, 0, fmtHex(local.sub_sub_module, 2));

    ppu::frame.text(60, 0, fmtHex(local.location, 6));
    //ppu::frame.text(60, 0, fmtHex(local.in_dark_world, 1));
    //ppu::frame.text(68, 0, fmtHex(local.in_dungeon, 1));
    //ppu::frame.text(76, 0, fmtHex(local.overworld_room, 2));
    //ppu::frame.text(92, 0, fmtHex(local.dungeon_room, 2));

    ppu::frame.text(120, 0, fmtHex(local.x, 4));
    ppu::frame.text(160, 0, fmtHex(local.y, 4));
  }

  if (@sprites != null) {
    for (int i = 0; i < 16; i++) {
      palette7[i] = ppu::cgram[(15 << 4) + i];
    }
    sprites.render(palette7);
    sprites.update();
  }

  if (@worldMap != null) {
    worldMap.update(local);
  }

  if (@gameSpriteWindow != null) {
    gameSpriteWindow.update();
  }
}

// called when bsnes changes its color palette:
void palette_updated() {
  //message("palette_updated()");
  if (@worldMap != null) {
    worldMap.redrawMap();
  }
}
