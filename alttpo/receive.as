// server clock synchronization; the server stamps every protocol 05 relay with its clock (see Protocol.as):
int64 last_server_time = 0;               // server's clock (nanoseconds since unix epoch) from the last received message
uint64 last_server_time_received_ns = 0;  // our monotonic clock (nanoseconds) when that message was received

// server_now estimates the server's current clock in nanoseconds since unix epoch; 0 if not yet known. Once our
// echoes came back, it is our clock plus the offset of the echo with the shortest round trip (see RunTiming.as);
// before, the last server stamp plus the time since it arrived, which runs late by the trip from the server.
int64 server_now() {
  if (server_clock_n > 0) return int64(chrono::realtime::nanosecond) + server_clock_best_offset;
  if (last_server_time == 0) return 0;
  return last_server_time + int64(chrono::monotonic::nanosecond - last_server_time_received_ns);
}

void note_server_time(int64 t) {
  last_server_time = t;
  last_server_time_received_ns = chrono::monotonic::nanosecond;
}

// Protocol 0x05 client state (see Protocol.as and o2-server's PROTOCOL05.md). The join is resent every p5_resend_ms
// until the join-ack for the current join_seq arrives; the sector likewise until its sector-ack. Other players' names
// and info come in player-info; a relay from a player whose player-info hasn't arrived asks for it with who-is. A
// player that left keeps its slot for p5_grace_ms, during which late relays from it are dropped.
const uint64 p5_resend_ms = 100;
const uint64 p5_whois_ms = 500;
const uint64 p5_grace_ms = 10000;
const int p5_echo_fast_samples = 30;

class P5Info {
  bool known = false;
  bool compatible = false;
  string name;
  uint8 team = 0;
}

class P5State {
  uint64 session = 0;

  uint8 join_seq = 0;
  bool join_acked = false;
  uint64 join_sent_ms = 0;
  bool sent_valid = false;
  string sent_group;
  string sent_token;
  // the server refused the group password (or the lack of one); no more joins until the group or password changes:
  bool auth_blocked = false;
  string auth_msg;
  uint64 auth_notified_ms = 0;
  string sent_name;
  uint8 sent_team = 0;

  uint8 sector_seq = 0;
  bool sector_set = false;
  bool in_sector = false;
  uint32 sector = 0;
  bool sector_acked = false;
  uint64 sector_sent_ms = 0;
  // the server takes broadcast-sectors (the join-ack's p5_ack_multi_sector):
  bool multi_sector = false;

  int echoes = 0;
  uint64 echo_sent_ms = 0;

  array<uint64> grace_until_ms;
  array<uint64> whois_sent_ms;
  array<P5Info@> info;

  P5State() {
    session = chrono::realtime::nanosecond ^ (chrono::monotonic::nanosecond << 17) ^ 0x9E3779B97F4A7C15;
  }

  P5Info@ get_info(uint index) {
    while (index >= info.length()) {
      info.insertLast(P5Info());
      grace_until_ms.insertLast(0);
      whois_sent_ms.insertLast(0);
    }
    return info[index];
  }

  // reset forgets the join and the sector, so that they are sent again on the next connection.
  void reset() {
    join_acked = false;
    join_sent_ms = 0;
    sent_valid = false;
    sector_set = false;
    sector_acked = false;
    echoes = 0;
    echo_sent_ms = 0;
  }
}

P5State p5;

void p5_send(array<uint8> @pkt) {
  if (sock is null) return;
  sock.send(0, pkt.length(), pkt);
  if (enableNetReporting) {
    net_bytes_sent += pkt.length();
  }
}

// p5_tick resends the join and the sector until they are acked, starts a new join when the group, name or team
// changed, and sends echoes. Called every send().
void p5_tick() {
  if (sock is null) return;
  uint64 now = chrono::monotonic::millisecond;

  string group = settings.GroupTrimmed;
  if (group.length() > 255) group = group.slice(0, 255);
  string name = local.name;
  if (name.length() > 255) name = name.slice(0, 255);
  string token = p5_auth_token(settings.Password);
  if (!p5.sent_valid || group != p5.sent_group || token != p5.sent_token || name != p5.sent_name || local.team != p5.sent_team) {
    if (!p5.sent_valid || group != p5.sent_group || token != p5.sent_token) p5.auth_blocked = false;
    p5.join_seq++;
    p5.join_acked = false;
    p5.join_sent_ms = 0;
    p5.sent_valid = true;
    p5.sent_group = group;
    p5.sent_token = token;
    p5.sent_name = name;
    p5.sent_team = local.team;
  }
  if (p5.auth_blocked && (p5.auth_notified_ms == 0 || now - p5.auth_notified_ms >= 8000)) {
    // the warning is up for 5.5 seconds; a refused join says so again every 8 seconds:
    p5.auth_notified_ms = now;
    notificationSystem.warn(p5.auth_msg);
  }
  if (!p5.join_acked && !p5.auth_blocked && (p5.join_sent_ms == 0 || now - p5.join_sent_ms >= p5_resend_ms)) {
    p5.join_sent_ms = now;
    auto @pkt = p5_packet(p5_join_group);
    pkt.write_u8(p5.join_seq);
    pkt.write_u32(uint32(p5.session & 0xFFFFFFFF));
    pkt.write_u32(uint32(p5.session >> 32));
    pkt.write_u8(uint8(group.length()));
    pkt.write_str(group);
    pkt.write_u8(uint8(name.length()));
    pkt.write_str(name);
    // info: game protocol version, team:
    pkt.write_u8(2);
    pkt.write_u8(script_protocol);
    pkt.write_u8(local.team);
    if (token.length() == 64) {
      pkt.write_u8(32);
      for (uint i = 0; i < 32; i++) pkt.write_u8(uint8(token.slice(i * 2, 2).hex()));
    }
    p5_send(pkt);
  }

  if (local.index < 0) return;

  // the sector:
  bool in_sector = local.p5_in_sector();
  uint32 sector = in_sector ? local.broadcast_sector() : 0;
  if (!p5.sector_set || in_sector != p5.in_sector || (in_sector && sector != p5.sector)) {
    p5.sector_seq++;
    p5.sector_set = true;
    p5.in_sector = in_sector;
    p5.sector = sector;
    p5.sector_acked = false;
    p5.sector_sent_ms = 0;
  }
  if (!p5.sector_acked && (p5.sector_sent_ms == 0 || now - p5.sector_sent_ms >= p5_resend_ms)) {
    p5.sector_sent_ms = now;
    if (p5.in_sector) {
      auto @pkt = p5_packet(p5_join_sector);
      pkt.write_u8(p5.sector_seq);
      pkt.write_u32(p5.sector);
      p5_send(pkt);
    } else {
      auto @pkt = p5_packet(p5_leave_sector);
      pkt.write_u8(p5.sector_seq);
      p5_send(pkt);
    }
  }

  // echoes to measure the round trip and the server's clock: every 500 ms for the first samples after a join, then
  // every 2 s:
  uint64 every = p5.echoes >= p5_echo_fast_samples ? 2000 : 500;
  if (p5.echo_sent_ms == 0 || now - p5.echo_sent_ms >= every) {
    p5.echo_sent_ms = now;
    auto @pkt = p5_packet(p5_echo);
    uint64 t = chrono::realtime::nanosecond;
    pkt.write_u32(uint32(t & 0xFFFFFFFF));
    pkt.write_u32(uint32(t >> 32));
    p5_send(pkt);
    runTiming.send_now = true;
  }

  facts_tick();
}

// p5_leave tells the server we left the group (best effort, so twice).
void p5_leave() {
  if (sock is null || local is null || local.index < 0) return;
  for (int i = 0; i < 2; i++) {
    p5_send(p5_packet(p5_leave_group));
  }
}

void p5_send_who_is(uint index) {
  uint64 now = chrono::monotonic::millisecond;
  p5.get_info(index);
  if (p5.whois_sent_ms[index] != 0 && now - p5.whois_sent_ms[index] < p5_whois_ms) return;
  p5.whois_sent_ms[index] = now;
  auto @pkt = p5_packet(p5_who_is);
  pkt.write_u16(uint16(index));
  p5_send(pkt);
}

GameState@ ensure_player(uint index) {
  if (index >= players.length()) {
    players_updated = true;
  }
  while (index >= players.length()) {
    players.insertLast(@GameState());
  }
  return players[index];
}

void receive() {
  array<uint8> buf(1500);
  int n;
  while ((n = sock.recv(0, 1500, buf)) > 0) {
    // copy to new buffer and trim to size:
    array<uint8> r = buf;
    r.resize(n);

    // header, protocol and kind:
    if (n < 4) continue;
    if ((uint16(r[0]) | (uint16(r[1]) << 8)) != 25887) continue;
    if (r[2] != p5_protocol) continue;
    uint8 kind = r[3];
    int c = 4;

    if (kind == p5_join_ack) {
      if (c + 11 > n) continue;
      uint8 seq = r[c];
      uint16 index = p5_u16(r, c + 1);
      int64 serverTime = int64(p5_u64(r, c + 3));
      if (seq != p5.join_seq) continue;
      p5.multi_sector = c + 12 <= n && (r[c + 11] & p5_ack_multi_sector) != 0;
      bool wasJoined = p5.join_acked && local.index >= 0;
      p5.join_acked = true;
      note_server_time(serverTime);
      if (!wasJoined) {
        p5.echoes = 0;
        p5.sector_set = false;
        p5.sector_acked = false;
        facts_joined();
      }
      assign_local_index(index);
    } else if (kind == p5_join_nak) {
      uint8 reason = c < n ? r[c] : 0;
      if (reason >= p5_nak_auth_required) {
        string msg = "this group exists without a password";
        if (reason == p5_nak_auth_required) msg = "this group needs a password";
        else if (reason == p5_nak_auth_failed) msg = "wrong group password";
        // the notification is repeated by p5_tick while the join stays refused:
        p5.auth_msg = msg;
        p5.auth_notified_ms = 0;
        p5.auth_blocked = true;
      } else if (p5.join_acked) {
        // the server lost us (it restarted, or we were away too long); join again:
        message("server: not in a group; joining again");
        p5.join_acked = false;
        p5.join_sent_ms = 0;
      }
    } else if (kind == p5_sector_ack) {
      if (c + 1 > n) continue;
      if (r[c] == p5.sector_seq) p5.sector_acked = true;
    } else if (kind == p5_echo_reply) {
      if (c + 16 > n) continue;
      int64 playerTime = int64(p5_u64(r, c));
      int64 serverTime = int64(p5_u64(r, c + 8));
      p5.echoes++;
      note_server_time(serverTime);
      server_clock_echo(playerTime, serverTime);
    } else if (kind == p5_player_info) {
      while (c + 4 <= n) {
        uint16 index = p5_u16(r, c); c += 2;
        int nameLen = r[c++];
        if (c + nameLen + 1 > n) break;
        string name = r.toString(c, nameLen); c += nameLen;
        int infoLen = r[c++];
        if (c + infoLen > n) break;
        uint8 version = infoLen >= 1 ? r[c] : 0;
        uint8 team = infoLen >= 2 ? r[c + 1] : 0;
        c += infoLen;
        player_info(index, name, version, team);
      }
    } else if (kind == p5_player_left) {
      if (c + 3 > n) continue;
      player_left(p5_u16(r, c));
    } else if (kind == p5_fact_status) {
      if (c + 10 > n) continue;
      facts_status(r[c], r[c + 1], p5_u64(r, c + 2));
    } else if (kind == p5_fact_list) {
      if (c + 2 > n) continue;
      facts_list(p5_u16(r, c), r, c + 2);
    } else if (kind == p5_fact_data) {
      if (c + 4 > n) continue;
      facts_data(p5_u16(r, c), r[c + 2], r[c + 3], r, c + 4);
    } else if (kind == p5_relay_all || kind == p5_relay_sector) {
      if (c + 4 > n) continue;
      uint16 index = p5_u16(r, c); c += 2;
      uint16 ms = p5_u16(r, c); c += 2;
      if (kind == p5_relay_sector) {
        if (c + 4 > n) continue;
        uint32 sector = p5_u32(r, c); c += 4;
        // the server routed it by the sector it last heard us join; drop it if we moved since:
        if (!local.p5_in_sector() || sector != local.broadcast_sector()) continue;
      }
      if (int(index) == local.index) continue;
      auto @pi = p5.get_info(index);
      if (p5.grace_until_ms[index] != 0 && chrono::monotonic::millisecond < p5.grace_until_ms[index]) continue;
      if (!pi.known) {
        p5_send_who_is(index);
        continue;
      }
      if (!pi.compatible) continue;
      int64 now_ns = server_now();
      if (now_ns == 0) now_ns = int64(chrono::realtime::nanosecond);
      int64 stamp = p5_expand_server_time(ms, now_ns);
      note_server_time(stamp);
      process_message(index, stamp, r, c);
    }
  }
}

// player_info records a player's name, team and game protocol version.
void player_info(uint16 index, const string &in name, uint8 version, uint8 team) {
  if (int(index) == local.index) return;
  auto @pi = p5.get_info(index);
  // a player-info during the grace period is the same player coming back:
  p5.grace_until_ms[index] = 0;
  bool compatible = version == script_protocol;
  if (!compatible && (pi.compatible || !pi.known)) {
    message(name + " runs an incompatible version");
  }
  pi.known = true;
  pi.compatible = compatible;
  pi.name = name;
  pi.team = team;

  auto @p = ensure_player(index);
  if (p is local) return;
  p.index = index;
  apply_player_info(p, pi);
  players_updated = true;
}

void apply_player_info(GameState@ p, P5Info@ pi) {
  if (p.name != pi.name) {
    p.name = pi.name;
    players_updated = true;
  }
  if (p.team != pi.team) {
    p.team = pi.team;
    players_updated = true;
  }
}

// player_left clears a player that left the group and reserves its slot for the grace period.
void player_left(uint16 index) {
  if (int(index) == local.index) return;
  auto @pi = p5.get_info(index);
  pi.known = false;
  pi.compatible = false;
  p5.grace_until_ms[index] = chrono::monotonic::millisecond + p5_grace_ms;
  facts_player_left(index);
  if (index < players.length() && !(players[index] is local) && players[index].ttl > 1) {
    // let the TTL run out on the next tick, which announces the player left:
    players[index].ttl = 1;
  }
}

void assign_local_index(uint16 index) {
  if (local.index == int(index)) {
    return;
  }

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
  @players[index] = @local;

  players_updated = true;
}

void process_message(uint16 index, int64 serverTime, array<uint8> r, int c) {
  auto @p = ensure_player(index);

  if (p is local) {
    message("received update from remote player with same index as local player {0}".format({index}));
    // we're confused; reset:
    local.index = -1;
    players.resize(0);
    players_updated = true;
    return;
  }

  // deserialize data packet:
  p.index = index;
  p.server_time = serverTime;
  apply_player_info(p, p5.get_info(index));
  p.deserialize(r, c);
}
