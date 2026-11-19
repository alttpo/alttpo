// Run timing, shared with o2: see o2's RUN_TIMING.md for the contract, and games/alttp/runtiming.go and reset.go for
// o2's side.
//
// A run lasts from the first player's start (the first frame of Module05_LoadFile after the run was reset) to the last
// player's finish (the first frame of Module19_TriforceRoom after the start), on the server's clock. The o2 patch,
// which every player of a timed run runs (alttpo players use the ROM that o2's alttpo-patcher writes), counts NMI
// frames and main loop iterations in SRAM and latches the NMI frame of the start and the finish:
//
//   $707000 u24 nmiFrames    incremented on every NMI, including lag frames
//   $707003 u24 loopFrames   incremented once per main loop iteration
//   $707006 u24 startFrame   nmiFrames at the start
//   $707009 u24 finishFrame  nmiFrames at the finish
//   $70700C u8  latches      bit 0: startFrame is set; bit 1: finishFrame is set; clients reset the run by writing 0
//   $70700D u8  gates        optional features of the patch; bit 0: remote sprites. The init code zeroes it.
//   $707FF0 [16] the patch signature: "O2-PATCH", the patch version, the CRC32 of the unpatched ROM
//
// alttpo reads them after every frame, and stamps the server clock when a latch bit appears, minus a frame period for
// every frame the latched value is behind nmiFrames. Every player broadcasts its run timing in message 0x84, in its
// own packet. The run is reset with o2's group reset state machine (message 0x81), which alttpo takes part in.

const uint32 rt_addr = 0x707000;
const uint rtm_nmi = 0x00;
const uint rtm_loop = 0x03;
const uint rtm_start = 0x06;
const uint rtm_finish = 0x09;
const uint rtm_latches = 0x0C;
const uint rtm_gates = 0x0D;
const uint rt_read_size = 0x0E;
const uint8 rt_latch_start = 0x01;
const uint8 rt_latch_finish = 0x02;
const uint8 rt_gate_sprites = 0x01;

const uint32 rt_signature_addr = 0x707FF0;
const uint rt_signature_size = 16;

// the remote sprites state o2's patch keeps; cleared before turning the sprites gate on (see o2's writeRunTiming):
const uint32 rs_state_addr = 0x706BC0;
const uint32 rs_nmi_len = 0x24;
const uint32 rs_skip_slots = 0x6A;

const uint8 msg_run_timing = 0x84;
const uint8 msg_reset = 0x81;
const uint8 run_timing_version = 1;
const uint8 run_timing_size = 72;

// run timing message flags:
const uint8 rt_flag_started = 0x01;
const uint8 rt_flag_finished = 0x02;
const uint8 rt_flag_discontinuity = 0x04;
const uint8 rt_flag_rate = 0x08;
const uint8 rt_flag_state_load = 0x10;
const uint8 rt_flag_no_counter = 0x20;

// the SNES's frame period (NTSC), 1 / 60.0988 seconds, in nanoseconds:
const int64 snes_frame_ns = 16639356;
// frames off by more than this from the wall time start a new stretch of the counter:
const int64 rt_jump_ns = 2000000000;
// the rate is checked over this long, with this tolerance:
const int64 rt_rate_window_ns = 10000000000;
const double rt_rate_tolerance = 0.01;

uint32 rt_u24(const array<uint8> &in b, uint o) {
  return uint32(b[o]) | (uint32(b[o+1]) << 8) | (uint32(b[o+2]) << 16);
}

// rt_u24_diff returns b - a for the u24 counters a and b, from -2^23 to 2^23-1.
int rt_u24_diff(uint32 a, uint32 b) {
  int d = int((b - a) & 0xFFFFFF);
  if (d >= 0x800000) d -= 0x1000000;
  return d;
}

int64 rt_read_i64(const array<uint8> &in r, int c) {
  uint64 v = 0;
  for (int i = 7; i >= 0; i--) {
    v = (v << 8) | uint64(r[c + i]);
  }
  return int64(v);
}

void rt_write_i64(array<uint8> &r, int64 v) {
  r.write_u32(uint32(uint64(v) & 0xFFFFFFFF));
  r.write_u32(uint32(uint64(v) >> 32));
}

// the server clock, estimated from the echoes NTP style: the offset of the echo with the shortest round trip out of
// the last 30 (see o2's clock.go):
const int server_clock_samples = 30;
const int64 server_clock_max_rtt = 5000000000;
array<int64> server_clock_rtt(server_clock_samples);
array<int64> server_clock_offset(server_clock_samples);
int server_clock_n = 0;
int server_clock_next = 0;
int64 server_clock_best_offset = 0;

// server_clock_echo adds the round trip of our echo sent at sent_ns (our realtime clock), stamped by the server at
// server_ns and received now.
void server_clock_echo(int64 sent_ns, int64 server_ns) {
  if (sent_ns == 0 || server_ns == 0) return;
  int64 rtt = int64(chrono::realtime::nanosecond) - sent_ns;
  if (rtt < 0 || rtt > server_clock_max_rtt) return;
  server_clock_rtt[server_clock_next] = rtt;
  server_clock_offset[server_clock_next] = server_ns - sent_ns - rtt / 2;
  server_clock_next = (server_clock_next + 1) % server_clock_samples;
  if (server_clock_n < server_clock_samples) server_clock_n++;
  int best = 0;
  for (int i = 1; i < server_clock_n; i++) {
    if (server_clock_rtt[i] < server_clock_rtt[best]) best = i;
  }
  server_clock_best_offset = server_clock_offset[best];
}

void server_clock_reset() {
  server_clock_n = 0;
  server_clock_next = 0;
  server_clock_best_offset = 0;
}

// rt_format_duration formats a duration in nanoseconds as hh:mm:ss.mmm.
string rt_format_duration(int64 ns) {
  if (ns < 0) ns = 0;
  int64 ms = ns / 1000000;
  return fmtInt(ms / 3600000) + ":" + pad0(int((ms / 60000) % 60), 2) + ":" + pad0(int((ms / 1000) % 60), 2) + "." +
    pad0(int(ms % 1000), 3);
}

string pad0(int v, int n) {
  string s = fmtInt(v);
  while (int(s.length()) < n) s = "0" + s;
  return s;
}

// RunTimingRemote is a player's run timing as last received in message 0x84.
class RunTimingRemote {
  bool ok = false;
  uint8 flags = 0;
  uint64 reset_id = 0;
  uint16 reset_initiator = 0;
  array<uint8> signature(rt_signature_size);
  uint8 gates = 0;
  bool gates_changed = false;
  int64 start_at = 0;
  int64 finish_at = 0;
  uint32 start_frame = 0;
  uint32 finish_frame = 0;
  uint32 nmi_frames = 0;
  uint32 loop_frames = 0;
  int64 sample_at = 0;
  uint32 lag_frames = 0;
  uint32 penalty_ms = 0;

  void serialize(array<uint8> &r) {
    r.write_u8(msg_run_timing);
    r.write_u8(run_timing_version);
    r.write_u8(run_timing_size);
    r.write_u8(flags);
    r.write_u32(uint32(reset_id & 0xFFFFFFFF));
    r.write_u32(uint32(reset_id >> 32));
    r.write_u16(reset_initiator);
    for (uint i = 0; i < rt_signature_size; i++) r.write_u8(signature[i]);
    r.write_u8(gates);
    r.write_u8(gates_changed ? 1 : 0);
    rt_write_i64(r, start_at);
    rt_write_i64(r, finish_at);
    r.write_u24(start_frame);
    r.write_u24(finish_frame);
    r.write_u24(nmi_frames);
    r.write_u24(loop_frames);
    rt_write_i64(r, sample_at);
    r.write_u24(lag_frames);
    r.write_u32(penalty_ms);
  }

  // deserialize reads message 0x84 after its type byte; returns the offset after it, skipping versions it doesn't
  // know by their size. Messages of another group reset than our own last one are ignored.
  int deserialize(const array<uint8> &in r, int c) {
    int maxc = int(r.length());
    if (c + 2 > maxc) return maxc;
    uint8 version = r[c++];
    int size = int(r[c++]);
    int end = c + size;
    if (end > maxc) return maxc;
    if (version != run_timing_version || size < int(run_timing_size)) return end;

    uint64 id = uint64(rt_read_i64(r, c + 1));
    uint16 initiator = uint16(r[c + 9]) | (uint16(r[c + 10]) << 8);
    if (runReset.last_id != 0 && id != 0 && (id != runReset.last_id || initiator != runReset.last_initiator)) {
      return end;
    }

    ok = true;
    flags = r[c++];
    reset_id = id;
    reset_initiator = initiator;
    c += 10;
    for (uint i = 0; i < rt_signature_size; i++) signature[i] = r[c++];
    gates = r[c++];
    gates_changed = r[c++] != 0;
    int64 s = rt_read_i64(r, c); c += 8;
    int64 f = rt_read_i64(r, c); c += 8;
    start_frame = rt_u24(r, c); c += 3;
    finish_frame = rt_u24(r, c); c += 3;
    nmi_frames = rt_u24(r, c); c += 3;
    loop_frames = rt_u24(r, c); c += 3;
    sample_at = rt_read_i64(r, c); c += 8;
    lag_frames = rt_u24(r, c); c += 3;
    penalty_ms = uint32(r[c]) | (uint32(r[c+1]) << 8) | (uint32(r[c+2]) << 16) | (uint32(r[c+3]) << 24);
    if (s != start_at || f != finish_at) {
      players_updated = true;
    }
    start_at = s;
    finish_at = f;
    return end;
  }

  // the cost players pay per frame: the patch and the gates; equal for every player of a fair run:
  string cost_key() const {
    string k = fmtHex(gates, 2);
    for (uint i = 0; i < rt_signature_size; i++) k += fmtHex(signature[i], 2);
    return k;
  }
};

// RunTimingLocal follows the local player's run timing in SRAM.
class RunTimingLocal {
  // the ROM runs the o2 patch, as its signature in SRAM shows:
  bool patched = false;
  array<uint8> signature(rt_signature_size);
  uint8 gates = 0;

  // the last counter sample, and when (our monotonic clock):
  bool sampled = false;
  uint32 nmi = 0;
  uint32 loop = 0;
  uint64 sampled_mono = 0;
  // the first sample of the current continuous stretch of the counter; latches from before it can't be timed:
  uint32 stretch_nmi = 0;
  // the start of the window the rate is checked over:
  uint32 rate_nmi = 0;
  uint64 rate_mono = 0;
  // the loop counter advanced while the NMI counter didn't: the ROM has no NMI counter:
  bool no_counter = false;

  bool started = false;
  bool finished = false;
  uint32 start_frame = 0;
  uint32 finish_frame = 0;
  int64 start_at = 0;
  int64 finish_at = 0;
  // the lag frames of the run's earlier stretches of the counter, and NMI frames minus loop frames when the current
  // one began (or the run started in it):
  uint32 lag_acc = 0;
  uint32 lag_base = 0;
  uint32 lag_frames = 0;
  uint8 gates_at_start = 0;
  bool gates_changed = false;
  uint8 flags = 0;
  int64 penalty_ns = 0;

  // write 0 to the latches with the next frame:
  bool clear_latches = false;
  // send message 0x84 now:
  bool send_now = false;

  bool in_run() const { return started && !finished; }

  // reset_run clears the run and has the latches in SRAM cleared.
  void reset_run() {
    started = false;
    finished = false;
    start_frame = 0;
    finish_frame = 0;
    start_at = 0;
    finish_at = 0;
    lag_acc = 0;
    lag_base = 0;
    lag_frames = 0;
    gates_at_start = 0;
    gates_changed = false;
    flags = 0;
    penalty_ns = 0;
    clear_latches = true;
    players_updated = true;
  }

  // post_frame reads the counters, latches and gates after the frame ran.
  void post_frame() {
    array<uint8> sig(rt_signature_size);
    bus::read_block_u8(rt_signature_addr, 0, rt_signature_size, sig);
    patched = sig[0] == 0x4F && sig[1] == 0x32 && sig[2] == 0x2D && sig[3] == 0x50 &&
              sig[4] == 0x41 && sig[5] == 0x54 && sig[6] == 0x43 && sig[7] == 0x48;
    if (!patched) {
      sampled = false;
      return;
    }
    if (sampled && sig != signature) {
      // another ROM was loaded (bsnes keeps the script loaded): its SRAM counter has nothing to do with the last one's,
      // so follow it from scratch rather than take the difference for a savestate load or fast-forward:
      message("run timing: the patch signature changed; following the new ROM's counter");
      if (in_run()) flags |= rt_flag_discontinuity;
      sampled = false;
    }
    signature = sig;

    if (clear_latches) {
      bus::write_u8(rt_addr + rtm_latches, 0);
      clear_latches = false;
    }
    write_gates();

    array<uint8> d(rt_read_size);
    bus::read_block_u8(rt_addr, 0, rt_read_size, d);
    gates = d[rtm_gates];
    if (in_run() && gates != gates_at_start && !gates_changed) {
      message("run timing: gates changed from $" + fmtHex(gates_at_start, 2) + " to $" + fmtHex(gates, 2) + " during the run");
      gates_changed = true;
    }
    sample(rt_u24(d, rtm_nmi), rt_u24(d, rtm_loop));

    int64 now = server_now();
    if (now == 0) {
      // the latches wait until the server clock is known:
      return;
    }
    uint8 latches = d[rtm_latches];
    if (!started && (latches & rt_latch_start) != 0) {
      uint32 f = rt_u24(d, rtm_start);
      if ((latches & rt_latch_finish) != 0) {
        // a finish latched along with a start we never saw on its own: SRAM from before the run (fresh SRAM reads $FF
        // everywhere, so both latch bits look set and both frames are $FFFFFF); start over:
        message("run timing: start and finish latched together (latches $" + fmtHex(latches, 2) + ", start $" +
          fmtHex(f, 6) + ", finish $" + fmtHex(rt_u24(d, rtm_finish), 6) + ") before the start was seen; clearing");
        clear_latches = true;
        return;
      }
      int64 at;
      if (!latch_time(f, now, at)) {
        message("run timing: start latched before the counter was followed; clearing");
        clear_latches = true;
        return;
      }
      started = true;
      start_frame = f;
      start_at = at;
      lag_acc = 0;
      lag_base = (nmi - loop) & 0xFFFFFF;
      gates_at_start = gates;
      gates_changed = false;
      flags |= rt_flag_started;
      send_now = true;
      players_updated = true;
      message("run timing: started at NMI frame $" + fmtHex(f, 6));
    }
    if (in_run()) {
      lag_frames = (lag_acc + nmi - loop - lag_base) & 0xFFFFFF;
      uint32 sram_start = rt_u24(d, rtm_start);
      if ((latches & rt_latch_start) == 0 || sram_start != start_frame ||
          ((latches & rt_latch_finish) != 0 && rt_u24(d, rtm_finish) == start_frame)) {
        // the SRAM doesn't hold this run's start (another ROM or SRAM file, or a savestate from before the start or of
        // another run): put it back, so that the patch latches the finish, and a finish latched against another start
        // or in the start's own frame, isn't taken for this run's:
        message("run timing: SRAM lost the run's start (latches $" + fmtHex(latches, 2) + ", start $" + fmtHex(sram_start, 6) + "); restoring it");
        bus::write_u8(rt_addr + rtm_start, uint8(start_frame));
        bus::write_u8(rt_addr + rtm_start + 1, uint8(start_frame >> 8));
        bus::write_u8(rt_addr + rtm_start + 2, uint8(start_frame >> 16));
        bus::write_u8(rt_addr + rtm_latches, rt_latch_start);
        return;
      }
    }
    if (in_run() && (latches & rt_latch_finish) != 0) {
      uint32 f = rt_u24(d, rtm_finish);
      int64 at;
      if (!latch_time(f, now, at)) {
        at = now;
        flags |= rt_flag_discontinuity;
      }
      finished = true;
      finish_frame = f;
      finish_at = at;
      flags |= rt_flag_finished;
      send_now = true;
      players_updated = true;
      message("run timing: finished in " + rt_format_duration(finish_at - start_at));
    }
  }

  // latch_time maps a latched frame of the current stretch to the server clock: the read is right after the frame
  // that nmi counted, so each frame behind it is a frame period earlier.
  bool latch_time(uint32 frame, int64 now, int64 &out at) {
    if (no_counter) {
      flags |= rt_flag_no_counter;
      at = now;
      return true;
    }
    if (rt_u24_diff(stretch_nmi, frame) < 0) return false;
    int behind = rt_u24_diff(frame, nmi);
    if (behind < 0) return false;
    at = now - int64(behind) * snes_frame_ns;
    return true;
  }

  // sample follows the counters, and notices savestate loads, fast-forward and pauses (see RUN_TIMING.md,
  // Discontinuities).
  void sample(uint32 n, uint32 l) {
    uint64 mono = chrono::monotonic::nanosecond;
    if (!sampled) {
      sampled = true;
      nmi = n; loop = l; sampled_mono = mono;
      start_stretch();
      return;
    }
    int frames = rt_u24_diff(nmi, n);
    int64 wall = int64(mono - sampled_mono);
    int64 d = int64(frames) * snes_frame_ns - wall;
    if (frames == 0 && rt_u24_diff(loop, l) > 0 && wall > 10 * snes_frame_ns) {
      if (!no_counter) message("run timing: the ROM doesn't count NMI frames; timing from module changes only");
      no_counter = true;
    }
    nmi = n; loop = l; sampled_mono = mono;
    if (frames < 0) {
      // the counter went back: a savestate load or the SRAM replaced:
      if (in_run()) flags |= rt_flag_discontinuity | rt_flag_state_load;
      message("run timing: NMI frames went back by " + fmtInt(-frames));
      start_stretch();
      return;
    }
    if (d > rt_jump_ns) {
      // more frames than the wall time allows: a forward savestate or fast-forward; charge what it saved:
      if (in_run()) {
        flags |= rt_flag_discontinuity;
        penalty_ns += d;
      }
      start_stretch();
      return;
    }
    if (d < -rt_jump_ns) {
      // paused or slowed down:
      start_stretch();
      return;
    }
    check_rate(mono);
  }

  // start_stretch begins a new stretch of the counter at the last sample.
  void start_stretch() {
    stretch_nmi = nmi;
    rate_nmi = nmi;
    rate_mono = sampled_mono;
    if (in_run()) {
      // the lag frames counted so far stay; the new stretch's are counted from its own start:
      lag_acc = lag_frames;
      lag_base = (nmi - loop) & 0xFFFFFF;
    }
  }

  // check_rate compares the frames with the wall time over the rate window during the run, and charges the wall time
  // that running fast saved. Running slow can't shorten the wall time, and a console reset, loading a ROM or a stall of
  // the emulator's window runs frames without NMIs or not at all, so slow windows aren't flagged.
  void check_rate(uint64 mono) {
    int64 wall = int64(mono - rate_mono);
    if (wall < rt_rate_window_ns) return;
    int64 frames = int64(rt_u24_diff(rate_nmi, nmi)) * snes_frame_ns;
    rate_nmi = nmi;
    rate_mono = mono;
    if (!in_run()) return;
    double ratio = double(frames) / double(wall);
    if (ratio > 1.0 + rt_rate_tolerance) {
      message("run timing: running " + fmtFloat((ratio - 1.0) * 100.0) + "% fast");
      flags |= rt_flag_rate;
      penalty_ns += frames - wall;
    }
  }

  // write_gates sets the gate byte from the settings. alttpo draws remote players itself, but sets the sprites gate
  // whenever the run uses remote sprites so that it pays for the patch's sprites code like o2 players do.
  void write_gates() {
    uint8 want = 0;
    if (settings.SyncSprites) want |= rt_gate_sprites;
    uint8 have = bus::read_u8(rt_addr + rtm_gates);
    if (have == want) return;
    if ((want & ~have & rt_gate_sprites) != 0) {
      // what the patch's remote sprites code last left for its NMI hooks is stale:
      bus::write_u16(rs_state_addr + rs_nmi_len, 0);
      bus::write_u16(rs_state_addr + rs_skip_slots, 0);
      bus::write_u16(rs_state_addr + rs_skip_slots + 2, 0);
    }
    bus::write_u8(rt_addr + rtm_gates, want);
  }

  // message fills in the local player's message 0x84.
  RunTimingRemote@ make_message() {
    RunTimingRemote m;
    m.ok = true;
    m.flags = flags;
    if (no_counter) m.flags |= rt_flag_no_counter;
    m.reset_id = runReset.last_id;
    m.reset_initiator = runReset.last_initiator;
    m.signature = signature;
    m.gates = gates;
    m.gates_changed = gates_changed;
    m.start_at = start_at;
    m.finish_at = finish_at;
    m.start_frame = start_frame;
    m.finish_frame = finish_frame;
    m.nmi_frames = nmi;
    m.loop_frames = loop;
    m.sample_at = sampled ? server_now() - int64(chrono::monotonic::nanosecond - sampled_mono) : 0;
    m.lag_frames = lag_frames;
    int64 ms = penalty_ns / 1000000;
    if (ms < 0) ms = 0;
    if (ms > int64(0xFFFFFFFF)) ms = int64(0xFFFFFFFF);
    m.penalty_ms = uint32(ms);
    return m;
  }
};

RunTimingLocal runTiming;

// player_run_timing returns a player's run timing: the local player's own, else the last received.
RunTimingRemote@ player_run_timing(GameState@ p) {
  if (p is local) return runTiming.make_message();
  return p.run_timing;
}

// run_time_text returns the run timer: the latest finish (plus its penalty) minus the earliest start, over the players
// who started, counting up until they all finished.
string run_time_text() {
  int64 min_start = 0;
  int64 max_finish = 0;
  bool all_finished = true;
  bool any = false;
  for (uint i = 0; i < players.length(); i++) {
    auto @p = players[i];
    if (p is null) continue;
    if (!(p is local) && p.ttl <= 0) continue;
    auto @rt = player_run_timing(p);
    if (!rt.ok || rt.start_at == 0) continue;
    any = true;
    if (min_start == 0 || rt.start_at < min_start) min_start = rt.start_at;
    if (rt.finish_at == 0) {
      all_finished = false;
    } else {
      int64 f = rt.finish_at + int64(rt.penalty_ms) * 1000000;
      if (f > max_finish) max_finish = f;
    }
  }
  if (!any) return "";
  int64 end = all_finished ? max_finish : server_now();
  return rt_format_duration(end - min_start);
}

// run_cost_warning returns a warning when players run with different patched ROMs or gates.
string run_cost_warning() {
  string first = "";
  for (uint i = 0; i < players.length(); i++) {
    auto @p = players[i];
    if (p is null) continue;
    if (!(p is local) && p.ttl <= 0) continue;
    auto @rt = player_run_timing(p);
    if (!rt.ok) continue;
    if (p is local && !runTiming.patched) continue;
    string k = rt.cost_key();
    if (first == "") {
      first = k;
    } else if (k != first) {
      return "players run with different patched ROMs or gates, so their frames don't cost the same";
    }
  }
  return "";
}

// player_time_text describes a player's run time for the players list.
string player_time_text(GameState@ p) {
  auto @rt = player_run_timing(p);
  if (!rt.ok || rt.start_at == 0) return "";
  string s;
  if (rt.finish_at != 0) {
    s = rt_format_duration(rt.finish_at - rt.start_at);
    if (rt.penalty_ms != 0) s += " +" + fmtFloat(double(rt.penalty_ms) / 1000.0) + "s";
  } else {
    s = "running";
  }
  s += ", " + fmtInt(rt.lag_frames) + " lag";
  if ((rt.flags & (rt_flag_discontinuity | rt_flag_rate | rt_flag_state_load | rt_flag_no_counter)) != 0) s += " *";
  if (rt.gates_changed) s += " (gates changed)";
  return s;
}

// Group reset, wire-compatible with o2's (games/alttp/reset.go): the initiator announces a reset; every player stops
// syncing, clears its state and run timing, and acknowledges; once everyone acknowledged and a quiet period passed,
// the initiator finalizes and everyone resumes syncing.
const uint8 reset_phase_idle = 0;
const uint8 reset_phase_initiate = 1;
const uint8 reset_phase_cleared = 2;
const uint8 reset_phase_finalize = 3;

const uint64 reset_quiet_ms = 750;
const uint64 reset_ack_timeout_ms = 5000;
const uint64 reset_participant_timeout_ms = 15000;
const uint64 reset_finalize_repeat_ms = 1000;
const uint64 reset_resend_ms = 250;

// reset_less orders resets so that concurrently initiated resets converge on the same one:
bool reset_less(uint64 id1, uint16 i1, uint64 id2, uint16 i2) {
  if (id1 != id2) return id1 < id2;
  return i1 < i2;
}

class RunReset {
  uint8 phase = reset_phase_idle;
  uint64 id = 0;
  uint16 initiator = 0;
  bool is_initiator = false;
  uint64 started_ms = 0;
  uint64 last_ack_ms = 0;
  // the participants the initiator waits for, and whether they acknowledged:
  array<int> ack_index;
  array<bool> ack_done;

  // the last completed reset:
  uint64 last_id = 0;
  uint16 last_initiator = 0;
  uint64 finalize_until_ms = 0;
  uint64 last_sent_ms = 0;

  bool get_resetting() const property { return phase != reset_phase_idle; }

  // request starts a group reset from the local player.
  void request() {
    if (sock is null || local.index < 0) {
      // not in a group; just clear our own state, dropping any group reset the disconnect left unfinished:
      phase = reset_phase_idle;
      id = 0;
      initiator = 0;
      is_initiator = false;
      clear_state();
      message("run reset: offline; reset our own state only");
      return;
    }
    if (phase != reset_phase_idle) return;
    int64 now = server_now();
    if (now == 0) now = int64(chrono::realtime::nanosecond);
    ack_index.resize(0);
    ack_done.resize(0);
    for (uint i = 0; i < players.length(); i++) {
      auto @p = players[i];
      if (p is null || p is local || p.ttl <= 0) continue;
      ack_index.insertLast(int(i));
      ack_done.insertLast(false);
    }
    enter(uint64(now), uint16(local.index), true);
    message("run reset: initiated; waiting on " + fmtInt(ack_index.length()) + " players");
    send(reset_phase_initiate, id, initiator);
    clear_state();
    phase = reset_phase_cleared;
  }

  void enter(uint64 key_id, uint16 key_initiator, bool initiating) {
    phase = reset_phase_initiate;
    id = key_id;
    initiator = key_initiator;
    is_initiator = initiating;
    started_ms = chrono::monotonic::millisecond;
    last_ack_ms = 0;
    if (!initiating) {
      ack_index.resize(0);
      ack_done.resize(0);
    }
  }

  // clear_state clears what the group syncs, and the run timing, keeping our identity in the group.
  void clear_state() {
    for (uint i = 0; i < players.length(); i++) {
      auto @p = players[i];
      if (p is null || p is local) continue;
      @players[i] = @GameState();
    }
    smallKeys.init();
    heartsSync.init();
    runTiming.reset_run();
    players_updated = true;
  }

  void finish(const string &in why) {
    message("run reset: " + why);
    last_id = id;
    last_initiator = initiator;
    if (is_initiator) finalize_until_ms = chrono::monotonic::millisecond + reset_finalize_repeat_ms;
    phase = reset_phase_idle;
    id = 0;
    initiator = 0;
    is_initiator = false;
    runTiming.send_now = true;
    players_updated = true;
  }

  // receive handles a reset message from player index from.
  void receive(int from, uint8 msg_phase, uint64 key_id, uint16 key_initiator) {
    if (last_id != 0 && !reset_less(last_id, last_initiator, key_id, key_initiator)) {
      // re-sent messages of a completed (or older) reset:
      return;
    }
    if (msg_phase == reset_phase_initiate) {
      if (phase != reset_phase_idle) {
        if (key_id == id && key_initiator == initiator) {
          if (!is_initiator && phase == reset_phase_cleared) send(reset_phase_cleared, id, initiator);
          return;
        }
        if (!reset_less(key_id, key_initiator, id, initiator)) {
          // a concurrent reset that loses to ours:
          return;
        }
      }
      message("run reset: initiated by player " + fmtInt(from));
      enter(key_id, key_initiator, false);
      clear_state();
      phase = reset_phase_cleared;
      send(reset_phase_cleared, id, initiator);
    } else if (msg_phase == reset_phase_cleared) {
      if (phase == reset_phase_idle || !is_initiator || key_id != id || key_initiator != initiator) return;
      for (uint i = 0; i < ack_index.length(); i++) {
        if (ack_index[i] == from && !ack_done[i]) {
          ack_done[i] = true;
          last_ack_ms = chrono::monotonic::millisecond;
        }
      }
    } else if (msg_phase == reset_phase_finalize) {
      if (phase == reset_phase_idle || is_initiator || key_id != id || key_initiator != initiator) return;
      finish("complete");
    }
  }

  // tick drives the timeouts and re-sends; called every frame while connected.
  void tick() {
    uint64 now = chrono::monotonic::millisecond;
    bool resend = now - last_sent_ms >= reset_resend_ms;
    if (phase == reset_phase_idle) {
      if (last_id != 0 && now < finalize_until_ms && resend) send(reset_phase_finalize, last_id, last_initiator);
      return;
    }
    uint64 elapsed = now - started_ms;
    if (!is_initiator) {
      if (elapsed >= reset_participant_timeout_ms) {
        finish("timed out waiting for the initiator; resuming sync");
        return;
      }
      if (resend) send(reset_phase_cleared, id, initiator);
      return;
    }
    bool all = true;
    for (uint i = 0; i < ack_done.length(); i++) {
      if (!ack_done[i]) all = false;
    }
    uint64 quiet_since = started_ms;
    if (last_ack_ms > quiet_since) quiet_since = last_ack_ms;
    if ((all && now - quiet_since >= reset_quiet_ms) || elapsed >= reset_ack_timeout_ms) {
      send(reset_phase_finalize, id, initiator);
      finish("complete");
      return;
    }
    if (resend) send(reset_phase_initiate, id, initiator);
  }

  void send(uint8 msg_phase, uint64 key_id, uint16 key_initiator) {
    if (sock is null || local.index < 0) return;
    last_sent_ms = chrono::monotonic::millisecond;
    auto @envelope = local.make_packet_broadcast();
    envelope.write_u8(msg_reset);
    envelope.write_u8(msg_phase);
    envelope.write_u32(uint32(key_id & 0xFFFFFFFF));
    envelope.write_u32(uint32(key_id >> 32));
    envelope.write_u16(key_initiator);
    local.send_packet(envelope, 0);
  }
};

RunReset runReset;
