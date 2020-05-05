array<int> torchOwner(0x10);

void init_torches() {
  cpu::register_pc_interceptor(rom.fn_dungeon_light_torch_success, @on_torch_light_success);
}

// called when local player lights a torch successfully:
bool ignore_light = false;
void on_torch_light_success(uint32 pc) {
  if (ignore_light) return;

  auto t = bus::read_u8(0x7E0333);
  if (t < 0xC0) return;

  t -= 0xC0;
  message("torch[" + fmtHex(t,1) + "].owner = " + fmtInt(local.index));
  torchOwner[t] = local.index;
}

void update_torches() {
  ignore_light = false;

  // MUST be in a dungeon and not in room transition:
  if (!local.is_in_dungeon()) return;
  if (local.sub_module != 0) return;

  array<bool>  is_lit(0x10);
  array<bool>  to_light(0x10);
  array<uint8> maxtimer(0x10);

  for (uint t = 0; t < 0x10; t++) {
    maxtimer[t] = local.torchTimers[t];
    is_lit[t] = local.is_torch_lit(t);
    to_light[t] = false;
    //message("torch[" + fmtHex(t,1) + "].timer = " + fmtHex(maxtimer[t],2));
  }

  // find torches to light from remote players:
  for (uint i = 0; i < players.length(); i++) {
    auto @remote = players[i];
    if (remote is null) continue;
    if (remote is local) continue;
    if (remote.ttl <= 0) continue;
    if (!local.can_see(remote.location)) continue;

    for (uint t = 0; t < 0x10; t++) {
      // if torch already lit don't bother checking:
      if (is_lit[t]) continue;

      // dumb trick to make sure torches don't flicker on/off/on/off when they get close to extinguishing:
      if (remote.torchTimers[t] > 1) {
        to_light[t] = true;
        if (remote.torchTimers[t] > maxtimer[t]) {
          maxtimer[t] = remote.torchTimers[t];
        }
      }
    }
  }

  // build a torch update routine to update local game state:
  for (uint t = 0; t < 0x10; t++) {
    // did a remote player light a torch or has already lit one when we entered the room?
    if (!to_light[t]) continue;

    //message("torch[" + fmtHex(t,1) + "] lit");

    // Set $0333 in WRAM to the tile number of a torch (C0-CF) to light:
    pb.lda_immed(0xC0 + t);     // LDA #{$C0 + t}
    pb.sta_bank(0x0333);        // STA $0333

    // JSL Dungeon_LightTorch
    pb.jsl(rom.fn_dungeon_light_torch);

    // ignore the calls to light torch for owner tracking:
    ignore_light = true;

    // override the torch's timer:
    pb.lda_immed(maxtimer[t]);  // LDA #{maxtimer[t]}
    pb.sta_bank(0x04F0 + t);    // STA {$04F0 + t}
  }

  pb.jsl(rom.fn_main_routing);  // JSL MainRouting
  pb.rtl();                     // RTL
}
