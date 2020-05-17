
void init_torches() {
  cpu::register_pc_interceptor(rom.fn_dungeon_light_torch_success, @on_torch_light_success);
  cpu::register_pc_interceptor(rom.fn_dungeon_extinguish_torch, @on_torch_extinguish);
}

// called when local player lights a torch successfully:
uint8 ignore_light = 0x00;
void on_torch_light_success(uint32 pc) {
  auto t = bus::read_u8(0x7E0333);
  if (t < 0xC0) return;
  if (t >= 0xD0) return;

  //message("torch[" + fmtHex(t & 0x0f,1) + "] lit by engine");
  if (t == ignore_light) {
    ignore_light = 0x00;
    return;
  }

  t = t & 0x0f;
  local.torchOwner[t] = local.index;
  //message("torch[" + fmtHex(t,1) + "].owner = " + fmtInt(local.torchOwner[t]));
}

// called when torch is extinguished:
void on_torch_extinguish(uint32 pc) {
  if (local is null) return;
  if (local.torchOwner is null) return;
  if (local.torchOwner.length() != 0x10) return;

  auto t = bus::read_u8(0x7E0333);
  if (t < 0xC0) return;
  if (t >= 0xD0) return;

  t = t & 0x0f;
  //message("torch[" + fmtHex(t,1) + "] extinguished by engine");

  local.torchOwner[t] = -2;
  //message("torch[" + fmtHex(t,1) + "].owner = " + fmtInt(local.torchOwner[t]));
}

void update_torches() {
  // MUST be in a dungeon and not in room transition:
  if (!local.is_in_dungeon()) return;
  if (local.sub_module != 0) return;

  array<bool>  is_lit(0x10);
  array<bool>  to_update(0x10);

  for (uint t = 0; t < 0x10; t++) {
    is_lit[t] = local.is_torch_lit(t);
    to_update[t] = false;
    //message("torch[" + fmtHex(t,1) + "].timer = " + fmtHex(maxtimer[t],2));
  }

  // find torches to light from remote players:
  for (uint t = 0; t < 0x10; t++) {
    for (uint i = 0; i < players.length(); i++) {
      auto @remote = players[i];
      if (remote is null) continue;
      if (remote is local) continue;
      if (remote.ttl <= 0) continue;
      if (!local.can_see(remote.location)) {
        if (local.torchOwner[t] == remote.index) {
          // transfer ownership of the torch if left the room:
          if (local.torchTimers[t] > 0) {
            local.torchOwner[t] = local.index;
          } else {
            local.torchOwner[t] = -2;
          }
        }
        continue;
      }

      // skip torches not owned:
      if (remote.torchOwner[t] != remote.index) continue;

      // this torch is owned by remote:
      local.torchTimers[t] = remote.torchTimers[t];
      local.torchOwner[t] = remote.index;

      to_update[t] = true;

      //message("torch[" + fmtHex(t,1) + "].owner = " + fmtInt(local.torchOwner[t]) + "; timer = " + fmtHex(local.torchTimers[t]));

      // don't let higher number players override:
      break;
    }
  }

  // build a torch update routine to update local game state:
  for (uint t = 0; t < 0x10; t++) {
    if (!to_update[t]) continue;

    // Only light unlit torches, and only light one per frame:
    if ((ignore_light == 0x00) && !is_lit[t] && (local.torchTimers[t] > 0)) {
      //message("torch[" + fmtHex(t,1) + "] fired");

      // ignore the calls to light this torch for owner tracking:
      ignore_light = 0xC0 + t;

      // Set $0333 in WRAM to the tile number of a torch (C0-CF) to light:
      pb.lda_immed(ignore_light); // LDA #{ignore_light}
      pb.sta_bank(0x0333);        // STA $0333

      // JSL Dungeon_LightTorch
      pb.jsl(rom.fn_dungeon_light_torch);

      // mark as lit so we update the timer:
      is_lit[t] = true;
    }

    // Override the torch's timer from remote player:
    pb.lda_immed(local.torchTimers[t]); // LDA #{local.torchTimers[t]}
    pb.sta_bank(0x04F0 + t);            // STA {$04F0 + t}
  }

  pb.jsl(rom.fn_main_routing);  // JSL MainRouting
  pb.rtl();                     // RTL
}
