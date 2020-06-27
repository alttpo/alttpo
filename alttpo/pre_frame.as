
// this function intercepts execution immediately before JSL MainRouting in the reset vector:
// this function is not called for every frame but is for most frames.
// when it is called, this function is always called before pre_frame.
void on_main_loop(uint32 pc) {
  //message("main");

  // restore our dynamic code buffer to JSL MainRouting; RTL:
  pb.restore();

  if (!enableRenderToExtra) {
    // reset ownership of OAM sprites:
    localFrameState.reset_owners();
  }

  local.fetch();

  if (settings.SyncTunic) {
    local.update_palette();
  }

  if (!enableRenderToExtra) {
    // backup VRAM for OAM tiles which are in-use by game:
    localFrameState.backup();
  }

  // fetch local VRAM data for sprites:
  local.capture_sprites_vram();

  if (settings.started && !(sock is null)) {
    // send updated state for our Link to server:
    local.send();

    // receive network updates from remote players:
    receive();
  }

  if (!settings.RaceMode) {
    local.update_tilemap();

    local.update_ancillae();

    if ((local.frame & 15) == 0) {
      local.update_items();
    }

    if ((local.frame & 31) == 0) {
      local.update_rooms();
    }
    if ((local.frame & 31) == 16) {
      local.update_overworld();
    }

    if (enableObjectSync) {
      local.update_objects();
    }

    // synchronize torches:
    update_torches();
  }

  if (pb.offset > 0) {
    // end the patch buffer:
    pb.jsl(rom.fn_main_routing);  // JSL MainRouting
    pb.rtl();                     // RTL
  }
}

// pre_frame always happens
void pre_frame() {
  //message("pre_frame");

  if (settings.DiscordEnable) {
    discord::pre_frame();
  }

  if (enableRenderToExtra) {
    ppu::extra.count = 0;
    ppu::extra.text_outline = true;
    if (!font_set) {
      @ppu::extra.font = settings.Font;
      font_set = true;
    }
  }

  // don't render players or labels in pre-game modules:
  if (local.module < 0x05) return;

  // render remote players:
  int ei = 0;
  uint len = players.length();
  for (uint i = 0; i < len; i++) {
    auto @remote = players[i];
    if (remote is null) continue;
    if (remote is local) continue;
    if (remote.ttl <= 0) {
      remote.ttl = 0;
      continue;
    }

    if (remote.ttl > 0) {
      remote.ttl = remote.ttl - 1;
    }

    // don't render on in-game map:
    if (local.module == 0x0e && local.sub_module == 0x07) continue;

    // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
    if (local.can_see(remote.location)) {
      // calculate screen scroll offset between both players to adjust OAM sprite x,y coords:
      int rx = int(remote.xoffs - local.xoffs);
      int ry = int(remote.yoffs - local.yoffs);

      // draw remote player relative to current BG offsets:
      if (enableRenderToExtra) {
        ei = remote.renderToExtra(rx, ry, ei);

        if (settings.ShowLabels) {
          ei = remote.renderLabel(rx, ry, ei);
        }
      } else {
        remote.renderToPPU(rx, ry);
      }
    }
  }

  if (enableRenderToExtra) {
    if (settings.ShowMyLabel) {
      // don't render on in-game map:
      if (!( local.module == 0x0e && local.sub_module == 0x07 )) {
        ei = local.renderLabel(0, 0, ei);
      }
    }

    // don't render notifications during spotlight open/close:
    if (local.module >= 0x07 && local.module <= 0x18) {
      if (local.module != 0x08 && local.module != 0x0a
       && local.module != 0x0d && local.module != 0x0e
       && local.module != 0x0f && local.module != 0x10) {
        // TODO: checkbox to enable/disable
        ei = local.renderNotifications(ei);
      }
    }

    if (ei > 0) {
      ppu::extra.count = ei;
    }
  }
}