
namespace CrowdControl {
  // funcdefs:

  funcdef void StateUpdated(int state);
  funcdef void MessageUpdated(const string &in msg);

  // version:
  const uint8 VERSION_MAJOR = 2;
  const uint8 VERSION_MINOR = 2;
  const uint8 VERSION_PATCH = 0;
  const uint version = (uint(VERSION_MAJOR) << 16) | (uint(VERSION_MINOR) << 8) | uint(VERSION_PATCH);

  // host:port to connect to CrowdControl app server:
  const string host = "127.0.0.1";
  const string port = "43884";

  class Connector {
    bool debugJSON = false;   // debug JSON
    bool debugProto = false;  // debug protocol
    bool debugState = false;  // debug state transitions and function calls made

    private net::Address@ addr = null;
    private net::Socket@ sock = null;

    private StateUpdated@ stateUpdated = null;
    private MessageUpdated@ messageUpdated = null;
    private Notify@ dgNotify = null;

    Connector(
      StateUpdated@ stateUpdated = null,
      MessageUpdated@ messageUpdated = null,
      Notify@ notify = null
    ) {
      @this.stateUpdated = stateUpdated;
      @this.messageUpdated = messageUpdated;
      @this.dgNotify = notify;
    }

    private void notify(const string &in msg) {
      if (dgNotify is null) {
        ::message(msg);
        return;
      }
      dgNotify(msg);
    }

    private void status(const string &in text) {
      if (messageUpdated !is null) messageUpdated(text);
    }

    int _state;
    int state {
      get { return _state; }
      set {
        _state = value;
        if (stateUpdated !is null) stateUpdated(value);
      }
    }

    void fail(string what) {
      message("net::" + what + " error " + net::error_code + "; " + net::error_text);
      status(net::error_text);
      stop();
    }

    void start() {
      @addr = net::resolve_tcp(host, port);
      if (net::is_error) {
        fail("resolve_tcp");
        return;
      }

      state = 1;
    }

    void stop() {
      if (state >= 1) {
        if (sock !is null) {
          sock.close();
        }
        @sock = null;
      }

      state = 0;
      status("Disconnected");
    }

    array<uint8> sizeUint(4);
    int sizeN;
    int size;
    array<uint8> buf;
    int bufN;

    void main() {
      // run up to 16 steps (arbitrary limit) of this state machine per frame:
      for (uint i = 0; i < 16; i++) {
        if (!step()) return;
      }
    }

    // returns true if we can run another step immediately after, false if need to wait for next frame.
    bool step() {
      if (state == 0) {
        // not connected; need to wait for external event:
        return false;
      } else if (state == 1) {
        // connect:
        if (debugState) {
          message("state " + fmtInt(state) + " connecting...");
        }

        @sock = net::Socket(addr);
        sock.connect(addr);
        if (net::is_error && net::error_code != "EINPROGRESS" && net::error_code != "EWOULDBLOCK") {
          fail("connect");
          return false;
        }

        // wait for connection success:
        state = 2;
        status("Connecting...");
        return true;
      } else if (state == 2) {
        // socket writable means connected:
        if (debugState) {
          message("state " + fmtInt(state) + " checking is_writable()");
        }

        bool connected = net::is_writable(sock);
        if (!connected && net::is_error) {
          fail("is_writable");
          return false;
        }

        // connected:
        state = 3;
        status("Connected");
        return true;
      } else if (state == 3) {
        // entry state
        if (debugState) {
          message("state " + fmtInt(state) + "");
        }
        // start expecting JSON messages with 4-byte size prefix:
        sizeN = 0;
        state = 4;
        return true;
      } else if (state == 4) {
        // read 4-byte size prefix:
        if (debugState) {
          message("state " + fmtInt(state) + " checking is_readable()");
        }
        if (!net::is_readable(sock)) {
          if (net::is_error) {
            fail("is_readable");
          }
          return false;
        }

        // receive bytes and delineate NUL-terminated messages:
        if (debugState) {
          message("state " + fmtInt(state) + " recv()");
        }
        int n = sock.recv(sizeN, 4 - sizeN, sizeUint);
        if (net::is_error && net::error_code != "EWOULDBLOCK") {
          fail("recv");
          return false;
        }
        if (debugState) {
          message("state " + fmtInt(state) + " recv() n=" + fmtInt(n));
        }

        // no data available:
        if (n < 0) {
          return false;
        }
        // connection closed:
        if (n == 0) {
          stop();
          return false;
        }

        sizeN += n;

        if (sizeN < 4) {
          // see if more data is available to read:
          return true;
        }

        // reset for next message:
        sizeN = 0;

        // read big-endian size of message to read:
        size = (uint(sizeUint[0]) << 24)
          | (uint(sizeUint[1]) << 16)
          | (uint(sizeUint[2]) << 8)
          | (uint(sizeUint[3]));

        // resize our buffer:
        buf.resize(size);
        bufN = 0;

        // move on to read message:
        state = 5;
        return true;
      } else if (state == 5) {
        // read JSON message of size `size`:
        if (debugState) {
          message("state " + fmtInt(state) + " checking is_readable()");
        }
        if (!net::is_readable(sock)) {
          if (net::is_error) {
            fail("is_readable");
          }
          return false;
        }

        // async recv; will return instantly if no data available:
        if (debugState) {
          message("state " + fmtInt(state) + " recv()");
        }
        int n = sock.recv(bufN, size - bufN, buf);
        if (net::is_error && net::error_code != "EWOULDBLOCK") {
          fail("recv");
          return false;
        }
        if (debugState) {
          message("state " + fmtInt(state) + " recv() n=" + fmtInt(n));
        }

        // no data available:
        if (n < 0) {
          return false;
        }
        // connection closed:
        if (n == 0) {
          stop();
          return false;
        }

        bufN += n;

        if (bufN < size) {
          // see if more data is available to read:
          return true;
        }

        state = 6;
        return true;
      } else if (state == 6) {
        // make sure socket is writable before sending reply:
        if (debugState) {
          message("state " + fmtInt(state) + " checking is_writable()");
        }

        if (!net::is_writable(sock)) {
          if (net::is_error) {
            fail("is_writable");
          }
          return false;
        }

        // process this message as a string:
        processMessage(buf.toString(0, bufN));

        // await next message:
        state = 3;
        return true;
      }

      // unknown state!
      return false;
    }

    private uint32 busAddressFor(const string &in domain, uint32 offset) {
      if (domain == "WRAM") {
        return 0x7E0000 + offset;
      } else if (domain == "CARTROM") {
        // convert PC address to bus address:
        //message("CARTROM $" + fmtHex(offset, 6));
        auto offs = offset & 0x7FFF;
        return ((offset >> 15) << 16) | offs | 0x8000;
      } else if (domain == "") {
        return offset;
      // TODO: confirm these domain names:
      //} else if (domain == "SRAM") {
      //  return 0x700000 + offset;
      } else {
        if (debugProto) {
          message("!!!! unhandled domain `" + domain + "`, offset=$" + fmtHex(offset, 6));
        }
        //case "ROM":
        //case "System Bus":
        //default:
        return offset;
      }
    }

    private void processMessage(const string &in t) {
      if (debugJSON) {
        message("recv: `" + t + "`");
      }

      // parse as JSON:
      auto j = JSON::parse(t).object;

      // extract useful values or sensible defaults:
      auto commandType = j["type"].naturalOr(0xFF);

      auto domain      = j["domain"].stringOr("");
      auto address     = j["address"].naturalOr(0);

      uint32 busAddress = 0xFFFFFF;
      if (j.containsKey("address")) {
        busAddress = busAddressFor(domain, address);
      }

      auto value       = j["value"].naturalOr(0);
      auto size        = j["size"].naturalOr(0);

      JSON::Object response;
      response["id"] = j["id"];
      response["stamp"] = JSON::Value(chrono::realtime::second);
      response["type"] = j["type"];
      if (j.containsKey("message")) response["message"] = JSON::Value("");
      if (j.containsKey("address")) response["address"] = j["address"];
      if (j.containsKey("size"))    response["size"] = j["size"];
      if (j.containsKey("domain"))  response["domain"] = j["domain"];
      if (j.containsKey("value"))   response["value"] = j["value"];

      switch (commandType) {
        case 0xe3:  // get emulator id
          if (debugProto) {
            message("< emulator id");
          }
          response["value"]   = JSON::Value(version);
          response["message"] = JSON::Value("SNES");
          break;

      // reads:
        case 0x00:  // read byte
          response["value"] = JSON::Value(bus::read_u8(busAddress));
          if (debugProto) {
            message("<  read_u8 ($" + fmtHex(busAddress, 6) + ") > $" + fmtHex(response["value"].natural, 2));
          }
          break;
        case 0x01:  // read short
          response["value"] = JSON::Value(bus::read_u16(busAddress));
          if (debugProto) {
            message("<  read_u16($" + fmtHex(busAddress, 6) + ") > $" + fmtHex(response["value"].natural, 4));
          }
          break;
        case 0x02:  // read uint32 (jsd: why not uint24 as well?)
          response["value"] = JSON::Value( uint(bus::read_u16(busAddress)) | (uint(bus::read_u16(busAddress+2) << 16)) );
          if (debugProto) {
            message("<  read_u32($" + fmtHex(busAddress, 6) + ") > $" + fmtHex(response["value"].natural, 8));
          }
          break;
        case 0x0f: { // read block
          if (debugProto) {
            message("<  read_blk($" + fmtHex(busAddress, 6) + ", size=$" + fmtHex(value, 6) + ")");
          }
          array<uint8> buf(value);
          bus::read_block_u8(busAddress, 0, value, buf);
          auto blockStr = base64::encode(0, value, buf);
          response["block"] = JSON::Value(blockStr);
          break;
        }

      // writes:
        case 0x10:  // write byte
          // TODO: freezes
          if (debugProto) {
            message("< write_u8 ($" + fmtHex(busAddress, 6) + ", $" + fmtHex(value, 2) + ")");
          }
          bus::write_u8(busAddress, value);
          break;
        case 0x11:  // write short
          // TODO: freezes
          if (debugProto) {
            message("< write_u16($" + fmtHex(busAddress, 6) + ", $" + fmtHex(value, 4) + ")");
          }
          bus::write_u16(busAddress, value);
          break;
        case 0x12:  // write uint32
          // TODO: freezes
          if (debugProto) {
            message("< write_u32($" + fmtHex(busAddress, 6) + ", $" + fmtHex(value, 8) + ")");
          }
          bus::write_u16(busAddress  , value & 0xFFFF);
          bus::write_u16(busAddress+2, (value >> 16) & 0xFFFF);
          break;
        case 0x1f: { // write block
          if (debugProto) {
            message("< write_blk($" + fmtHex(busAddress, 6) + ", size=$" + fmtHex(size, 6) + ")");
          }
          if (j.containsKey("block") && j["block"].isString) {
            auto block = j["block"].string;
            array<uint8> data;
            auto decSize = base64::decode(block, data);
            if (size != decSize) {
              message("size does not match base64 decoded size!");
            } else {
              bus::write_block_u8(busAddress, 0, size, data);
            }
          } else {
            message("missing block!");
          }
          break;
        }

        case 0x20: { // safe bit flip
          auto old = bus::read_u8(busAddress);
          response["value"] = JSON::Value(old);
          auto newval = old | value;
          bus::write_u8(busAddress, newval);
          if (debugProto) {
            message("<      flip($" + fmtHex(busAddress, 6) + ") > $" + fmtHex(old, 2) + " | $" + fmtHex(value, 2) + " = $" + fmtHex(newval, 2));
          }
          break;
        }
        case 0x21: { // safe bit unflip
          auto old = bus::read_u8(busAddress);
          response["value"] = JSON::Value(old);
          auto mask = ~uint8(value);
          auto newval = old & mask;
          bus::write_u8(busAddress, newval);
          if (debugProto) {
            message("<    unflip($" + fmtHex(busAddress, 6) + ") > $" + fmtHex(old, 2) + " & $" + fmtHex(mask, 2) + " = $" + fmtHex(newval, 2));
          }
          break;
        }

      // misc:
        case 0xf0:  // display message
          if (j.containsKey("message") && j["message"].isString) {
            notify(j["message"].string);
          }
        case 0xff:
          // do nothing.
          break;

        default:
          if (debugProto) {
            if (!debugJSON) {
              message("<!!UNKNOWN `" + t + "`");
            } else {
              message("!!!UNKNOWN command 0x" + fmtHex(commandType, 2));
            }
          }
          break;
      }

      {
        // compose response packet:
        auto data = JSON::serialize(JSON::Value(response));
        uint dataSize = data.length();

        array<uint8> r;
        r.reserve(4 + dataSize);
        r.insertLast(uint8((dataSize >> 24) & 0xFF));
        r.insertLast(uint8((dataSize >> 16) & 0xFF));
        r.insertLast(uint8((dataSize >> 8) & 0xFF));
        r.insertLast(uint8((dataSize) & 0xFF));
        r.write_str(data);

        if (debugJSON) {
          message("send: `" + data + "`");
        }

        sock.send(0, r.length(), r);
        if (net::is_error) {
          fail("send");
          return;
        }
      }
    }
  }

  Connector@ connector;
}
