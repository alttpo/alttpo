
// this function intercepts execution immediately before JSL MainRouting in the reset vector:
// this function is not called for every frame but is for most frames.
void on_main_loop(uint32 pc) {
  // restore our dynamic code buffer to JSL MainRouting; RTL:
  pb.restore();

  // reset ownership of OAM sprites:
  localFrameState.reset_owners();

  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;
  if (sock is null) return;

  // synchronize torches:
  update_torches();

  local.update_ancillae();

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
}

// pre_frame always happens
void pre_frame() {
  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;
  if (sock is null) return;

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

    // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
    if (local.can_see(remote.location)) {
      // subtract BG2 offset from sprite x,y coords to get local screen coords:
      int16 rx = int16(remote.x) - local.xoffs;
      int16 ry = int16(remote.y) - local.yoffs;

      // draw remote player relative to current BG offsets:
      //message("render");
      remote.render(rx, ry);
    }
  }

  // update tilemap:
  local.update_tilemap();
}