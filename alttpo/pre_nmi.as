
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
      if (remote is null) continue;
      if (remote is local) continue;
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
