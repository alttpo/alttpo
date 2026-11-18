// server clock synchronization; the server stamps every protocol 04 message it sends with its clock:
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

uint64 p04_read_u64(const array<uint8> &in r, int c) {
  uint64 v = 0;
  for (int i = 7; i >= 0; i--) {
    v = (v << 8) | uint64(r[c + i]);
  }
  return v;
}

uint32 p04_read_u32(const array<uint8> &in r, int c) {
  return uint32(r[c]) | (uint32(r[c+1]) << 8) | (uint32(r[c+2]) << 16) | (uint32(r[c+3]) << 24);
}

// server protocol 04 GroupMessage (all integers little-endian):
//   uint8   groupLength
//   [N]byte group
//   int64   playerTime
//   int64   serverTime
//   uint32  playerIndex
//   uint64  playerInSector
//   uint8   kind
//   kind-specific body:
//     0x01 join group:       (empty)
//     0x02 broadcast all:    uint16 dataLength, [N]byte data
//     0x03 broadcast sector: uint64 targetSector, uint16 dataLength, [N]byte data
//     0x04 echo:             uint16 dataLength, [N]byte data
void receive() {
  array<uint8> buf(1500);
  int n;
  while ((n = sock.recv(0, 1500, buf)) > 0) {
    int c = 0;

    // copy to new buffer and trim to size:
    array<uint8> r = buf;
    r.resize(n);

    // verify envelope header:
    if (n < 3) continue;
    uint16 header = uint16(r[c++]) | (uint16(r[c++]) << 8);
    if (header != 25887) {
      //message("receive(): bad envelope header!");
      continue;
    }

    // check protocol:
    uint8 protocol = r[c++];
    if (protocol != 0x04) {
      //message("receive(): unknown protocol 0x" + fmtHex(protocol, 2));
      continue;
    }

    // skip group name:
    if (c + 1 > n) continue;
    uint8 groupLen = r[c++];
    c += groupLen;

    // fixed size fields:
    if (c + 8 + 8 + 4 + 8 + 1 > n) continue;
    int64 playerTime = int64(p04_read_u64(r, c)); c += 8;
    int64 serverTime = int64(p04_read_u64(r, c)); c += 8;
    uint32 playerIndex = p04_read_u32(r, c); c += 4;
    // skip playerInSector:
    c += 8;
    uint8 kind = r[c++];

    // record server time:
    last_server_time = serverTime;
    last_server_time_received_ns = chrono::monotonic::nanosecond;

    if (playerIndex > 0xFFFF) continue;
    uint16 index = uint16(playerIndex);

    if (kind == 0x01) {
      // join group response tells us our index:
      assign_local_index(index);
    } else if (kind == 0x02 || kind == 0x03) {
      // broadcast from another player:
      if (kind == 0x03) {
        // skip target sector:
        c += 8;
      }
      if (c + 2 > n) continue;
      uint16 dataLen = uint16(r[c++]) | (uint16(r[c++]) << 8);
      if (c + int(dataLen) > n) continue;
      // ignore any trailing bytes:
      r.resize(c + int(dataLen));
      process_message(index, playerTime, serverTime, r, c);
    } else if (kind == 0x04) {
      // our own echo, sent back by the server with our send time and its own time:
      server_clock_echo(playerTime, serverTime);
    }
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

void process_message(uint16 index, int64 playerTime, int64 serverTime, array<uint8> r, int c) {
  if (index >= players.length()) {
    players_updated = true;
  }

  while (index >= players.length()) {
    players.insertLast(@GameState());
  }

  if (players[index] is local) {
    message("received update from remote player with same index as local player {0}".format({index}));
    // we're confused; reset:
    local.index = -1;
    players.resize(0);
    players_updated = true;
    return;
  }

  // deserialize data packet:
  players[index].index = index;
  players[index].player_time = playerTime;
  players[index].server_time = serverTime;
  players[index].deserialize(r, c);
}
