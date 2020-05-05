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

void receive() {
  array<uint8> buf(1500);
  int n;
  while ((n = sock.recv(0, 1500, buf)) > 0) {
    int c = 0;

    // copy to new buffer and trim to size:
    array<uint8> r = buf;
    r.resize(n);

    // verify envelope header:
    uint16 header = uint16(r[c++]) | (uint16(r[c++]) << 8);
    if (header != 25887) {
      message("receive(): bad envelope header!");
      continue;
    }

    uint16 index = 0;

    // check protocol:
    uint8 protocol = r[c++];
    if (protocol == 0x01) {
      // skip group name:
      uint8 groupLen = r[c++];
      c += groupLen;

      // skip player name:
      uint8 nameLen = r[c++];
      c += nameLen;

      // read player index:
      index = uint16(r[c++]) | (uint16(r[c++]) << 8);

      // check client type (spectator=0, player=1):
      uint8 clientType = r[c++];
      // skip messages from non-players (e.g. spectators):
      if (clientType != 1) {
        message("receive(): ignore non-player message");
        continue;
      }
    } else if (protocol == 0x02) {
      // skip 20 byte group name:
      c += 20;

      // message kind:
      uint8 kind = r[c++];
      if (kind == 0x80) {
        // read client index:
        index = uint16(r[c++]) | (uint16(r[c++]) << 8);

        // assign to local player:
        if (local.index != int(index)) {
          if (local.index >= 0 && local.index < int(players.length())) {
            // reset old player slot:
            @players[local.index] = @GameState();
          }
          // reassign local index:
          local.index = index;

          message("assign local.index = " + fmtInt(index));

          // make room for local player if needed:
          while (index >= players.length()) {
            players.insertLast(@GameState());
          }

          // assign the local player into the players[] array:
          @players[index] = local;
        }
        continue;
      }

      // kind == 0x81 should be response to another player's broadcast.
      index = uint16(r[c++]) | (uint16(r[c++]) << 8);
    } else {
      message("receive(): unknown protocol 0x" + fmtHex(protocol, 2));
      continue;
    }

    while (index >= players.length()) {
      players.insertLast(@GameState());
    }

    // deserialize data packet:
    players[index].ttl = 255;
    players[index].index = index;
    players[index].deserialize(r, c);
  }
}

void pre_nmi() {
  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;

  // Attempt to open a server socket:
  if (@sock == null) {
    try {
      // open a UDP socket to receive data from:
      @address = net::resolve_udp(settings.ServerAddress, "4590");
      // open a UDP socket to receive data from:
      @sock = net::Socket(address);
      // connect to remote address so recv() and send() work:
      sock.connect(address);
    } catch {
      // Probably server IP field is invalid; prompt user again:
      @sock = null;
      settings.started = false;
      settings.show();
    }
  }

  // restore previous VRAM tiles:
  localFrameState.restore();

  local.ttl = 255;

  // fetch next frame's game state from WRAM:
  local.fetch_module();

  local.fetch_sfx();

  local.fetch();

  if (!local.is_it_a_bad_time()) {
    // play remote sfx:
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (@remote == null) continue;

      if (@remote == @local) continue;
      if (remote.ttl <= 0) {
        remote.ttl = 0;
        continue;
      }

      // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
      if (local.can_see(remote.location)) {
        // attempt to play remote sfx:
        remote.play_sfx();
      }
    }
  }
}

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
