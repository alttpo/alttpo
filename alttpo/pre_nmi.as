
void pre_nmi() {
  //message("pre_nmi");

  // increment our own frame counter since in SMZ3 there is no single frame counter:
  local.frame = (local.frame + 1) & 0xff;

  if (settings.DisableBgMusic) {
    disable_bg_music();
  } else if (bgMusicWasDisabled) {
    restart_bg_music();
  }

  if (settings.started) {
    // Attempt to open a server socket:
    if (sock is null) {
      try {
        // open a UDP socket to receive data from:
        @address = net::resolve_udp(settings.ServerAddress, "4590");
        if (address is null) {
          message("Could not resolve network address '{0}'!".format({settings.ServerAddress}));
          @sock = null;
          return;
        }
        // open a UDP socket to receive data from:
        @sock = net::Socket(address);
        // connect to remote address so recv() and send() work:
        sock.connect(address);
      } catch {
        // Probably server IP field is invalid; prompt user again:
        settings.disconnect();
      }
    }
  }

  if (!enableRenderToExtra) {
    // restore previous VRAM tiles:
    localFrameState.restore();
  }

  // exit early if game is not ALTTP (for SMZ3):
  if (!rom.is_alttp()) {
    return;
  }

  // fetch next frame's game state from WRAM:
  local.fetch_module();

  local.fetch_sfx();

  if (settings.started) {
    if (settings.SyncSfx && !local.is_it_a_bad_time()) {
      // play remote sfx:
      uint len = players.length();
      for (uint i = 0; i < len; i++) {
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
}

// The game requests music in $012C and NMI sends it to the APU unless it equals $0133 (the last track sent), then sets
// $0133 and $0130 (the track playing, unless the request is $F2 or later) to it and clears $012C. The game decides
// what to request by comparing the track an area or room wants with $0130 (fading with $F1 when they differ), so
// while the BG music is disabled the requests of tracks that repeat are swallowed as if NMI sent them: $0130 and $0133
// are set to the track and the request is cleared. The game believes the right track is playing and never fades or
// requests another one. The z3randomizer (VT randomizer, DR) moves the request: after the module it copies $012C to
// $012B and NMI reads $012B instead (the operand of the LDA at $0080DC), so the request is the address NMI reads.
// Requests of tracks that play once (jingles, which the game can wait for), the mirror warp, nothing music and
// commands other than the volume commands are sent.

// the last track that repeats the game requested while the BG music is disabled, and whether it is disabled now:
uint8 bgMusicWanted = 0;
bool bgMusicWasDisabled = false;

// bg_music_request_addr returns the address of the music request that NMI reads, or 0 if the NMI is not one that
// the music can be intercepted in:
uint32 bg_music_request_addr() {
  // LDA.w $xxxx:
  if (bus::read_u8(0x0080DC) != 0xAD || bus::read_u8(0x0080DE) != 0x01) return 0;
  auto lo = bus::read_u8(0x0080DD);
  if (lo != 0x2C && lo != 0x2B) return 0;
  return 0x7E0100 | lo;
}

// restart_bg_music requests the track that repeats the game last requested while the BG music was disabled, once:
void restart_bg_music() {
  bgMusicWasDisabled = false;
  auto req = bg_music_request_addr();
  if (req == 0) return;
  // NMI skips a request equal to the last track sent:
  bus::write_u8(0x7E0133, 0);
  if (bus::read_u8(req) == 0) {
    bus::write_u8(req, bgMusicWanted);
  }
  bgMusicWanted = 0;
}

// is_repeating_track returns true for the tracks that loop; false for commands, nothing music, the mirror warp and
// the tracks that play once (short jingles):
bool is_repeating_track(uint8 cmd) {
  if (cmd == 0 || cmd >= 0x30) return false;
  switch (cmd) {
    case 0x01: case 0x08: case 0x0A: case 0x0F: case 0x13: case 0x1D: case 0x20: case 0x21: case 0x22:
      return false;
  }
  return true;
}

void disable_bg_music() {
  // funny things happen when disabling music from the intro:
  auto module = bus::read_u8(0x7E0010);
  if (module < 0x06) return;

  auto req = bg_music_request_addr();
  if (req == 0) return;

  auto cmd = bus::read_u8(req);

  // the volume commands are swallowed:
  if (cmd == 0xF2 || cmd == 0xF3) {
    bus::write_u8(req, 0);
    return;
  }
  // the game's own fade out is sent the first time:
  if (cmd == 0xF1) {
    if (!bgMusicWasDisabled) {
      bgMusicWasDisabled = true;
      return;
    }
  } else if (cmd != 0) {
    // sent: other commands, the mirror warp, nothing music and tracks that play once:
    if (!is_repeating_track(cmd)) return;
    // remember the track that repeats:
    bgMusicWanted = cmd;
  }

  // the first time, fade out the track that is playing, the only thing the APU is told:
  if (!bgMusicWasDisabled) {
    bgMusicWasDisabled = true;
    auto tune = bus::read_u8(0x7E0130);
    if (tune != 0 && tune != 0x08 && tune < 0xF1) {
      bus::write_u8(req, 0xF1);
      bus::write_u8(0x7E0130, 0xF1);
      bus::write_u8(0x7E0133, 0);
      return;
    }
  }

  if (cmd == 0) return;
  // act as if NMI sent the request: the game believes the track is playing:
  bus::write_u8(0x7E0130, cmd);
  bus::write_u8(0x7E0133, cmd);
  bus::write_u8(req, 0);
}
