
bool main_called = false;

// this function intercepts execution immediately before JSL MainRouting in the reset vector:
// this function is not called for every frame but is for most frames.
// when it is called, this function is always called before pre_frame.
// in SMZ3 this function is only called during ALTTP game.
void on_main_alttp(uint32 pc) {
  //message("main_alttp");
  main_called = true;

  // restore our dynamic code buffer to JSL MainRouting; RTL:
  pb.restore();

  if (!enableRenderToExtra) {
    // reset ownership of OAM sprites:
    localFrameState.reset_owners();
  }

  rom.check_game();
  local.set_in_sm(!rom.is_alttp());

  local.fetch();

  if(rom.is_smz3()){
    local.fetch_games_won();
    local.fetch_sm_events_buffer();
  }

  // NOTE: commented this line out because it causes "X left" "X joined" messages for the local player when in dialogs
  // or cut-scenes.
  //if (local.is_frozen()) return;

  if (settings.SyncTunic) {
    local.update_palette();
  }

  if (!enableRenderToExtra) {
    // backup VRAM for OAM tiles which are in-use by game:
    localFrameState.backup();
  }

  // fetch local VRAM data for sprites:
  local.capture_sprites_vram();

  if (settings.started && (sock !is null)) {
    // receive network updates from remote players:
    receive();
  }

  // calculate PvP damage against nearby players:
  if (settings.EnablePvP) {
    local.attack_pvp();
  }

  if (settings.started && (sock !is null)) {
    // send updated state for our Link to server:
    //message("send");
    local.send();
  } else {
    return;
  }

  {
    local.update_tilemap();

    local.update_wram();

    local.update_ancillae();

    rom.update_extras();

    ALTTPSRAMArray @sram = @ALTTPSRAMArray(@local.sram);
    ALTTPSRAMArray @sram_buffer = @ALTTPSRAMArray(@local.sram_buffer, true);

    if (settings.SyncItems) {
      if ((local.frame & 15) == 0) {
        local.update_items(sram);
        if (rom.is_smz3()) {
          local.update_items(sram_buffer, true);
          local.update_sm_events_buffer();
          local.update_games_won();
        }
      }
    }

    if ((local.frame & 31) == 0) {
      local.update_rooms(sram);
    }
    if ((local.frame & 31) == 16) {
      local.update_overworld(sram);
    }

    if (enableObjectSync) {
      local.update_objects();
    }

    if (settings.SyncUnderworld) {
      update_torches();
    }
  }

  if (settings.EnablePvP) {
    local.apply_pvp();
  }

  if (pb.offset > 0) {
    // end the patch buffer:
    pb.jsl(rom.fn_main_routing);  // JSL MainRouting
    pb.rtl();                     // RTL
  }
}

// This function is called when alttp's Sprite_Main routine begins:
void on_sprite_main_alttp(uint32 pc) {
  if (settings.started && (sock !is null)) {
    // receive network updates from remote players:
    receive();
  }

  if (settings.SyncLttpEnemies) {
    local.fetch_basics(); // for in_dungeon and location checks
    local.fetch_enemy_data(); // to not overwrite picked up sprites

    local.update_overlord_data();
    local.update_enemy_data();
  }
}

// This function is called when alttp's Sprint_Main routine ends (on RTL):
void on_sprite_main_end_alttp(uint32 pc) {
  if (settings.SyncLttpEnemies) {
    local.fetch_overlord_data();
    local.fetch_enemy_data();

    local.send_enemy_data();
  }
}

uint8 sm_state = 0;

bool sm_is_safe_state() {
  // on SM reset: 00, 01, 04, 02, 1f, 07, 08 (in game)
  // on SM transition: 0b

  if (sm_state <= 0x07) return false;
  if (sm_state >= 0x15) return false;

  return true;
}

bool sm_loading_room() {
  return sm_state == 0x0b;
}


bool sm_in_menu() {
  return (sm_state >= 0x0c && sm_state <= 0x12);
}

// Super Metroid main loop intercept:
void on_main_sm(uint32 pc) {
  //message("main_sm");
  main_called = true;

  // ppu::frame.text(  0,  10, "sm main called");

  rom.check_game();
  local.set_in_sm(!rom.is_alttp());

  sm_state = bus::read_u8(0x7E0998);

  local.module = 0x00;
  local.sub_module = 0x00;
  local.sub_sub_module = 0x00;
  local.sprites_need_vram = false;
  local.numsprites = 0;
  local.sprites.resize(0);
  local.actual_location = 0;

  if (!sm_is_safe_state()) {
    return;
  }

  local.get_sm_coords();
  local.fetch_games_won();
  if (!sm_in_menu()) {
    local.fetch_sm_pose();
    local.fetch_sm_sprites();

    // fetch local VRAM data for sprites:
    local.capture_sprites_vram();

    local.fetch_enemies();
  }

  // read ALTTP temporary item buffer from SM SRAM
  //message("read SM");
  local.in_sm_for_items = true;
  bus::read_block_u8(0x7E09A2, 0, 0x40, local.sram);
  bus::read_block_u8(0xA17B00, 0x300, 0x100, local.sram_buffer);
  local.fetch_sm_events();

  if (!settings.started) {
    return;
  }
  if (sock is null) {
    return;
  }

  //message("SM send&recieve");
  // send updated state for our Link to server:
  local.send();

  // receive network updates from remote players:
  receive();

  if (settings.SyncItems) {
    // all we can do is update items:
    if ((local.frame & 15) == 0) {
      if (sm_is_safe_state()) {
        // use SMSRAMArray so that commit() updates SM SRAM:
        SMSRAMArray@ sram = @SMSRAMArray(@local.sram);
        SMSRAMArray@ sram_buffer = @SMSRAMArray(@local.sram_buffer, true);

        local.update_items(sram);
        local.update_items(sram_buffer, true);

        local.update_sm_events();
        local.update_games_won();
      }
    }
  }

  if (!sm_loading_room()) {
    if (settings.SyncSmEnemies) {
      local.update_enemies();
    }
    local.timeInRoom++;
  }
  else {
    local.timeInRoom = 0;
  }
}

uint32 last_net_report = 0;
uint32 net_bytes_sent = 0;

// pre_frame always happens
void pre_frame() {
  //message("pre_frame");

  // capture current timestamp:
  // TODO(jsd): replace this with current server time
  timestamp_now = uint32(chrono::realtime::millisecond);

  if (enableNetReporting) {
    if (last_net_report == 0) {
      last_net_report = timestamp_now;
    }
    if ((timestamp_now - last_net_report) >= 1000) {
      double delta = (timestamp_now - last_net_report);
      message(fmtInt(int(double(net_bytes_sent) * 1000.0 / delta)));
      net_bytes_sent = 0;
      last_net_report = timestamp_now;
    }
  }

  if (enableRenderToExtra) {
    ppu::extra.count = 0;
    ppu::extra.text_outline = true;
    if (!font_set) {
      @ppu::extra.font = settings.Font;
      font_set = true;
    }
  }

  if (settings.DiscordEnable) {
    discord::pre_frame();
  }

  if (rom is null) {
    return;
  }

  if (settings.Bridge) {
    bridge.main();
  }

  if (settings.ConnectorLibConnected) {
    ConnectorLib::connector.main();
  }

  local.ttl = 255;

  if (!main_called) {
    //dbgData("pre_frame send/recv");
    if (settings.started && (sock !is null)) {
      // send updated state for our Link to server:
      local.send();

      // receive network updates from remote players:
      receive();
    }
  }

  if (players_updated) {
    if (playersWindow !is null) {
      playersWindow.update();
    }
    //local.reset_uniqtiles();
  }
  players_updated = false;

  // reset main loop called state:
  main_called = false;

  // render remote players:
  int ei = 0;
  uint len = players.length();
  playerCount = 0;
  for (uint i = 0; i < len; i++) {
    auto @remote = players[i];
    if (remote is null) continue;
    playerCount++;
    if (remote is local) continue;
    if (remote.ttl <= 0) {
      // erase player:
      remote.ttl = 0;
      if (remote.index >= 0) {
        @players[remote.index] = @GameState();
        players_updated = true;
      }
      playerCount--;
      continue;
    }
    remote.ttl_count();

    if (!settings.SyncSprites) {
      continue;
    }

    if (!rom.is_alttp()) {
      // SM:

      //tests if both players are in the same room
      if (!local.can_see_sm(remote)) continue;
      if (sm_state > 0x0c && sm_state < 0x12) continue;

      uint16 remote_offset_x = remote.sm_screen_x;
      uint16 local_offset_x = local.sm_screen_x;
      uint16 remote_offset_y = remote.sm_screen_y;
      uint16 local_offset_y = local.sm_screen_y;
      int rx = int(remote_offset_x) - int(local_offset_x);
      int ry = int(remote_offset_y) - int(local_offset_y);

      // message("SM local " + fmtInt(local_offset_x) + "," + fmtInt(local_offset_y) + "; remote " + fmtInt(remote_offset_x) + "," + fmtInt(remote_offset_y));
      // message("SM rx,ry " + fmtInt(rx) + "," + fmtInt(ry) + "; remoteabs " + fmtInt(remote_abs_x) + "," + fmtInt(remote_abs_y));
      ei = remote.renderToExtra(rx, ry, ei);

      if (settings.ShowLabels && !sm_in_menu()) {
        ei = remote.render_sm_label(rx - 8, ry - 64, ei);
      }
    } else {
      // alttp:

      // don't render players or labels in pre-game modules:
      if (local.is_it_a_bad_time()) continue;

      // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
      if (local.can_see(remote.location)) {
        // don't render player if remote player is in pre-game modules:
        if (remote.is_it_a_bad_time()) continue;

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
  }

  if (enableRenderToExtra) {
    if (settings.ShowMyLabel && rom.is_alttp()) {
      // don't render on in-game map:
      if ((local.module >= 0x06) && !( local.module == 0x0e && local.sub_module == 0x07 )) {
        ei = local.renderLabel(0, 0, ei);
      }
    }

    if (rom.is_alttp()) {
      // don't render notifications during spotlight open/close:
      if (local.module >= 0x07 && local.module <= 0x18) {
        if (local.module != 0x08 && local.module != 0x0a
         && local.module != 0x0d && local.module != 0x0e
         && local.module != 0x0f && local.module != 0x10) {
          // TODO: checkbox to enable/disable
          ei = notificationSystem.renderNotifications(ei);
        }
      }
    } else {
      // SM:
      sm_state = bus::read_u8(0x7E0998);
      if (sm_is_safe_state()) {
        ei = notificationSystem.renderNotifications(ei);
      }

      if (settings.ShowMyLabel && !sm_loading_room() && !sm_in_menu()){
        // int offset_x = int(bus::read_u16(0x7e0b04) & 0x00FF);
        // int offset_y = int(bus::read_u16(0x7e0b06) & 0x00FF);
        
        ei = local.render_sm_label(0 - 8, 0 - 64, ei);
      }
    }

    if (ei > 0) {
      ppu::extra.count = ei;
    }
  }
}