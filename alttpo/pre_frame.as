
void pre_frame() {
  // restore our dynamic code buffer to JSL MainRouting:
  pb.restore();

  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;

  if (sock is null) return;

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
    if (remote is null) continue;

    if (remote is local) continue;
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
      array<bool> activated(0x10);
      array<uint8> maxtimer(0x10);

      for (uint t = 0; t < 0x10; t++) {
        maxtimer[t] = local.torchTimers[t];
        activated[t] = false;
        //message("torch[" + fmtHex(t,1) + "].timer = " + fmtHex(maxtimer[t],2));
      }

      // find max torch timer among players:
      for (uint i = 0; i < players.length(); i++) {
        auto @remote = players[i];
        if (remote is null) continue;
        if (remote is local) continue;
        if (remote.ttl <= 0) continue;
        if (!local.can_see(remote.location)) continue;

        for (uint t = 0; t < 0x10; t++) {
          if (remote.torchTimers[t] > remote.last_torchTimers[t]) {
            activated[t] = true;
            if (remote.torchTimers[t] > maxtimer[t]) {
              maxtimer[t] = remote.torchTimers[t];
            }
          }
        }
      }

      // build a torch update routine to update local game state:
      for (uint t = 0; t < 0x10; t++) {
        // did a remote player activate a torch or has already activated one when we entered the room?
        if (!activated[t]) continue;

        // Cannot light torch if already lit; this would hard-lock the game:
        auto idx = (t << 1) + bus::read_u16(0x7E0478);
        auto tm = bus::read_u16(0x7E0540 + idx);

        // is torch already lit?
        if ((tm & 0x8000) == 0x8000) {
          //message("torch[" + fmtHex(t,1) + "] already lit");
          continue;
        }

        message("torch[" + fmtHex(t,1) + "] lit");

        // Set $0333 in WRAM to the tile number of a torch (C0-CF) to light:
        pb.lda_immed(0xC0 + t);     // LDA #{$C0 + t}
        pb.sta_bank(0x0333);        // STA $0333

        // JSL Dungeon_LightTorch
        pb.jsl(rom.fn_dungeon_light_torch);

        // override the torch timer's value:
        pb.lda_immed(maxtimer[t]);  // LDA #{maxtimer[t]}
        pb.sta_bank(0x04F0 + t);    // STA {$04F0 + t}
      }

      pb.jsl(rom.fn_main_routing);  // JSL MainRouting
      pb.rtl();                     // RTL

      //bus::write_u8(0x7E045A, count);
    }
  }

  {
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (remote is null) continue;
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

  if (@worldMapWindow != null) {
    worldMapWindow.renderPlayers(local, players);
  }
}
