
funcdef void StateUpdated(int state);
funcdef void MessageUpdated(const string &in msg);

class Bridge {
  private int state = 0;
  private net::Address@ addr = null;
  private net::Socket@ sock = null;
  private StateUpdated@ stateUpdated = null;
  private MessageUpdated@ messageUpdated = null;

  Bridge(StateUpdated@ stateUpdated = null, MessageUpdated@ messageUpdated = null) {
    @this.stateUpdated = stateUpdated;
    @this.messageUpdated = messageUpdated;
  }

  private void fail(string what) {
    message("net::" + what + " error " + net::error_code + "; " + net::error_text);
    if (@messageUpdated !is null) messageUpdated(net::error_text);
    stop();
  }

  int _state;
  int state {
    get { return _state; }
    set {
      _state = value;
      if (@stateUpdated !is null) stateUpdated(value);
    }
  }

  void start() {
    @addr = net::resolve_tcp("127.0.0.1", "65398");
    if (net::is_error) {
      fail("resolve_tcp");
      return;
    }

    state = 1;
  }

  void stop() {
    if (state >= 1) {
      if (@sock !is null) {
        sock.close();
      }
      @sock = null;
    }

    state = 0;
  }

  void main() {
    if (state == 0) {
      return;
    } else if (state == 1) {
      // connect:
      @sock = net::Socket(addr);
      sock.connect(addr);
      if (net::is_error && net::error_code != "EINPROGRESS" && net::error_code != "EWOULDBLOCK") {
        fail("connect");
        return;
      }

      // wait for connection success:
      state = 2;
      if (@messageUpdated !is null) messageUpdated("Connecting...");
    } else if (state == 2) {
      // socket writable means connected:
      bool connected = net::is_writable(sock);
      if (!connected && net::is_error) {
        fail("is_writable");
        return;
      }

      // connected:
      state = 3;
      if (@messageUpdated !is null) messageUpdated("Connected");
    } else if (state == 3) {
      //if (!net::is_readable(sock)) {
      //  if (net::is_error) {
      //    fail("is_readable");
      //  }
      //  return;
      //}

      // receive a message:
      array<uint8> m(1500);
      int n = sock.recv(0, 1500, m);
      if (net::is_error && net::error_code != "EWOULDBLOCK") {
        fail("recv");
        return;
      }
      if (n <= 0) {
        return;
      }
      m.resize(n);

      // process the message:
      processMessage(m);
    }
  }

  private void processMessage(const array<uint8> &in m) {
    // convert byte array to string and strip off trailing '\n':
    string t = m.toString(0, m.length());
    //message(t.stripRight());

    auto messages = t.split("\n");
    for (uint k = 0; k < messages.length(); k++) {
      auto line = messages[k].stripRight();
      if (line.length() == 0) {
        continue;
      }

      auto parts = line.split("|");
      uint len = parts.length();
      if (len == 0) {
        continue;
      }

      array<uint8> r();
      if (parts[0] == "Version") {
        r.write_str("Version|Multitroid LUA|4|\n");
      } else if (parts[0] == "Read") {
        auto madr = parts[1].natural();
        auto mlen = parts[2].natural();

        //message("read  0x" + fmtHex(madr,6) + " for 0x" + fmtHex(mlen, 4));

        array<uint8> mblk(mlen);
        bus::read_block_u8(madr, 0, mlen, mblk);
        r.write_str("{\"data\": [");
        for (uint i = 0; i < mlen; i++) {
          if (i > 0) {
            r.write_str(",");
          }
          r.write_str(fmtUint(mblk[i]));
        }
        r.write_str("]}\n");
      } else if (parts[0] == "Write") {
        auto madr = parts[1].natural();
        auto mlen = parts.length() - 2;

        //message("write 0x" + fmtHex(madr,6) + " for 0x" + fmtHex(mlen, 4));

        array<uint8> mblk(mlen);
        for (uint i = 0; i < mlen; i++) {
          mblk[i] = uint8(parts[i+2].natural());
        }
        bus::write_block_u8(madr, 0, mlen, mblk);
      } else if (parts[0] == "Message") {
        // TODO: show on-screen as well
        message("Message: " + parts[1]);
      } else if (parts[0] == "SetName") {
        message("My name is " + parts[1]);
      } else {
        message("'" + line + "'");
      }

      // make sure socket is writable before sending reply:
      if (r.length() > 0) {
        if (!net::is_writable(sock)) {
          if (net::is_error) {
            fail("is_writable");
          }
          return;
        }

        sock.send(0, r.length(), r);
        if (net::is_error) {
          fail("send");
          return;
        }
      }
    }
  }
}

Bridge@ bridge;
