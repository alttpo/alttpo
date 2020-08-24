
void receive() {
  array<uint8> buf(1500);
  int n;
  while ((n = sock.recv(0, 1500, buf)) > 0) {
    int c = 0;

    // copy to new buffer and trim to size:
    array<uint8> r = buf;
    r.resize(n);

    // verify envelope header:
    uint16 header = uint16(r[c++]) | (uint16(r[c++]) << 8);
    if (header != 25887) {
      message("receive(): bad envelope header!");
      continue;
    }

    uint16 index = 0;

    // check protocol:
    uint8 protocol = r[c++];
    if (protocol == 0x01) {
      // skip group name:
      uint8 groupLen = r[c++];
      c += groupLen;

      // skip player name:
      uint8 nameLen = r[c++];
      c += nameLen;

      // read player index:
      index = uint16(r[c++]) | (uint16(r[c++]) << 8);

      // check client type (spectator=0, player=1):
      uint8 clientType = r[c++];
      // skip messages from non-players (e.g. spectators):
      if (clientType != 1) {
        message("receive(): ignore non-player message");
        continue;
      }
    } else if (protocol == 0x02) {
      // skip 20 byte group name:
      c += 20;

      // message kind:
      uint8 kind = r[c++];
      if (kind == 0x80) {
        // read client index:
        index = uint16(r[c++]) | (uint16(r[c++]) << 8);

        // assign to local player:
        if (local.index != int(index)) {
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
          @players[index] = local;
        }
        continue;
      }

      // kind == 0x81 should be response to another player's broadcast.
      index = uint16(r[c++]) | (uint16(r[c++]) << 8);
    } else {
      message("receive(): unknown protocol 0x" + fmtHex(protocol, 2));
      continue;
    }

    while (index >= players.length()) {
      players.insertLast(@GameState());
    }

    // deserialize data packet:
    bool joined = false;
    if (players[index].ttl <= 0) {
      joined = true;
    }
    players[index].ttl = 255;
    players[index].index = index;
    players[index].deserialize(r, c);
    if (joined) {
      local.notify(players[index].name + " joined");
    }
  }
}
