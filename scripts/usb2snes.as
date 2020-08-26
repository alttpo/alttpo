
class Bridge {
  GUI::Window@ window;
  GUI::LineEdit@ txtHost;
  GUI::LineEdit@ txtPort;
  GUI::Button@ go;
  GUI::Button@ stop;

  Bridge() {
    @window = GUI::Window(120, 120, true);
    window.title = "USB2SNES";
    window.size = GUI::Size(280, 5*25);
    window.dismissable = false;

    auto vl = GUI::VerticalLayout();
    vl.setSpacing();
    vl.setPadding(5, 5);
    window.append(vl);
    {
      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Host:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtHost = GUI::LineEdit();
        txtHost.text = "127.0.0.1";
        hz.append(txtHost, GUI::Size(-1, 20));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Port:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtPort = GUI::LineEdit();
        txtPort.text = "65398";
        hz.append(txtPort, GUI::Size(-1, 20));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @go = GUI::Button();
        go.text = "Connect";
        go.onActivate(@GUI::Callback(goClicked));
        hz.append(go, GUI::Size(-1, -1));

        @stop = GUI::Button();
        stop.text = "Disconnect";
        stop.onActivate(@GUI::Callback(stopClicked));
        stop.enabled = false;
        hz.append(stop, GUI::Size(-1, -1));
      }
    }

    vl.resize();
    window.visible = true;
    window.setFocused();
  }

  private int state = 0;
  private net::Address@ addr = null;
  private net::Socket@ sock = null;

  void reset() {
    sock.close();
    go.enabled = true;
    stop.enabled = false;
    state = 0;
  }

  void fail(string what) {
    message("net::" + what + " error " + net::error_code + "; " + net::error_text);
    reset();
  }

  private void goClicked() {
    @addr = net::resolve_tcp(txtHost.text, txtPort.text);
    if (net::is_error) {
      fail("resolve_tcp");
      return;
    }

    state = 1;
    go.enabled = false;
    stop.enabled = true;
  }

  private void stopClicked() {
    if (state >= 1) {
      sock.close();
      @sock = null;
    }

    state = 0;
    go.enabled = true;
    stop.enabled = false;
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
    } else if (state == 2) {
      // socket writable means connected:
      bool connected = net::is_writable(sock);
      if (!connected && net::is_error) {
        fail("is_writable");
        return;
      }

      // connected:
      state = 3;
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

void init() {
  @bridge = Bridge();
}

void pre_frame() {
  bridge.main();
}
