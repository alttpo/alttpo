// ALTTP script to draw current Link sprites on top of rendered frame:
net::Socket@ sock;
net::Address@ address;
SettingsWindow @settings;

bool debug = false;
bool debugOAM = false;
bool debugSprites = false;

void init() {
  @settings = SettingsWindow();
  if (debugSprites) {
    @sprites = SpritesWindow();
  }
}

class SettingsWindow {
  private gui::Window @window;
  private gui::LineEdit @txtServerAddress;
  private gui::LineEdit @txtGroup;
  private gui::LineEdit @txtName;
  private gui::Button @ok;

  string ServerAddress;
  string Group;
  string Name;
  bool started;

  SettingsWindow() {
    @window = gui::Window(164, 22, true);
    window.title = "Join a Game";
    window.size = gui::Size(256, 24*5);

    auto vl = gui::VerticalLayout();
    {
      auto @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Address:";
        hz.append(lbl, gui::Size(100, 0));

        @txtServerAddress = gui::LineEdit();
        txtServerAddress.text = "bittwiddlers.org";
        hz.append(txtServerAddress, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Group:";
        hz.append(lbl, gui::Size(100, 0));

        @txtGroup = gui::LineEdit();
        txtGroup.text = "test";
        hz.append(txtGroup, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Player Name:";
        hz.append(lbl, gui::Size(100, 0));

        @txtName = gui::LineEdit();
        txtName.text = "player";
        hz.append(txtName, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        @ok = gui::Button();
        ok.text = "Connect";
        @ok.on_activate = @gui::ButtonCallback(this.startClicked);
        hz.append(ok, gui::Size(-1, -1));
      }
      vl.append(hz, gui::Size(-1, -1));
    }
    window.append(vl);

    vl.resize();
    window.visible = true;
  }

  private void startClicked(gui::Button @self) {
    ServerAddress = txtServerAddress.text;
    Group = txtGroup.text;
    Name = txtName.text;
    started = true;
    hide();
  }

  void show() {
    window.visible = true;
  }

  void hide() {
    window.visible = false;
  }
};

const int scale = 2;
class SpritesWindow {
  private gui::Window @window;
  private gui::VerticalLayout @vl;
  gui::Canvas @canvas;

  array<uint16> fgtiles(0x1000);

  SpritesWindow() {
    // relative position to bsnes window:
    @window = gui::Window(0, 256*2, true);
    window.title = "Sprite VRAM";
    window.size = gui::Size(256*scale, 256*scale);

    @vl = gui::VerticalLayout();
    window.append(vl);

    @canvas = gui::Canvas();
    canvas.size = gui::Size(128, 128);
    vl.append(canvas, gui::Size(-1, -1));

    vl.resize();
    canvas.update();
    window.visible = true;
  }

  void update() {
    canvas.update();
  }

  void render(const array<uint16> &palette) {
    // read VRAM:
    ppu::vram.read_block(0x4000, 0, 0x1000, fgtiles);

    // draw VRAM as 4bpp tiles:
    sprites.canvas.fill(0x0000);
    sprites.canvas.draw_sprite_4bpp(0, 0, 0, 128, 128, fgtiles, palette);
  }
};
SpritesWindow @sprites;
array<uint16> palette7(16);

class Sprite {
  uint8 index;
  uint16 chr;
  int16 x;
  int16 y;
  uint8 size;
  uint8 palette;
  uint8 priority;
  bool hflip;
  bool vflip;

  // b0-b3 are main 4 bytes of OAM table
  // b4 is the 5th byte of extended OAM table
  // b4 must be right-shifted to be the two least significant bits and all other bits cleared.
  void decodeOAMTableBytes(uint8 i, uint8 b0, uint8 b1, uint8 b2, uint8 b3, uint8 b4) {
    index = i;
    x    = b0;
    y    = b1;
    chr  = b2;
    chr  = chr | ((b3 >> 0 & 1) << 8);
    palette  = b3 >> 1 & 7;
    priority = b3 >> 4 & 3;
    hflip    = (b3 >> 6 & 1) != 0 ? true : false;
    vflip    = (b3 >> 7 & 1) != 0 ? true : false;

    x    = (x & 0xff) | ((b4 << 8) & 0x100);
    size = (b4 >> 1) & 1;
  }

  void adjustXY(int16 rx, int16 ry) {
    int16 ax = x;
    int16 ay = y;

    // adjust x to allow for slightly off-screen sprites:
    if (ax >= 256) ax -= 512;
    //if (ay + tile.height >= 256) ay -= 256;

    // Make sprite x,y relative to incoming rx,ry coordinates (where Link is in screen coordinates):
    x = ax - rx;
    y = ay - ry;
  }

  // fetches all the OAM sprite data for OAM sprite at `index`
  void fetchOAM(uint8 j, int16 rx, int16 ry) {
    auto tile = ppu::oam[j];

    index = j;

    int16 ax = int16(tile.x);
    int16 ay = int16(tile.y);

    // adjust x to allow for slightly off-screen sprites:
    if (ax >= 256) ax -= 512;
    if (ay + tile.height >= 256) ay -= 256;

    // Make sprite x,y relative to incoming rx,ry coordinates (where Link is in screen coordinates):
    x = ax - rx;
    y = ay - ry;

    chr      = tile.character;
    size     = tile.size;
    palette  = tile.palette;
    priority = tile.priority;
    hflip    = tile.hflip;
    vflip    = tile.vflip;
  }

  void serialize(array<uint8> &r) {
    r.insertLast(index);
    r.insertLast(chr);
    r.insertLast(uint16(x));
    r.insertLast(uint16(y));
    r.insertLast(size);
    r.insertLast(palette);
    r.insertLast(priority);
    r.insertLast(hflip ? uint8(1) : uint8(0));
    r.insertLast(vflip ? uint8(1) : uint8(0));
  }

  int deserialize(array<uint8> &r, int c) {
    index = r[c++];
    chr = uint16(r[c++]) | uint16(r[c++] << 8);
    x = int16(uint16(r[c++]) | uint16(r[c++] << 8));
    y = int16(uint16(r[c++]) | uint16(r[c++] << 8));
    size = r[c++];
    palette = r[c++];
    priority = r[c++];
    hflip = (r[c++] != 0 ? true : false);
    vflip = (r[c++] != 0 ? true : false);
    return c;
  }
};

class Tile {
  uint16 addr;
  array<uint16> tiledata;

  Tile(uint16 addr, array<uint16> tiledata) {
    this.addr = addr;
    this.tiledata = tiledata;
  }
};

class GameState {
  // graphics data for current frame:
  array<Sprite@> sprites;
  array<array<uint16>> chrs(512);
  // backup of VRAM tiles overwritten:
  array<Tile@> chr_backup;

  // values copied from RAM:
  uint32 location;
  uint32 last_location;

  // screen scroll coordinates relative to top-left of room (BG screen):
  int16 xoffs;
  int16 yoffs;

  uint16 x, y, z;

  uint8 module;
  uint8 sub_module;
  uint8 sub_sub_module;

  void update_module() {
    // module     = 0x07 in dungeons
    //            = 0x09 in overworld
    module = bus::read_u8(0x7E0010);

    // when module = 0x07: dungeon
    //    sub_module = 0x00 normal gameplay in dungeon
    //               = 0x01 going through door
    //               = 0x03 triggered a star tile to change floor hole configuration
    //               = 0x05 initializing room? / locked doors?
    //               = 0x07 falling down hole in floor
    //               = 0x0e going up/down stairs
    //               = 0x0f entering dungeon first time (or from mirror)
    //               = 0x16 when orange/blue barrier blocks transition
    //               = 0x19 when using mirror
    // when module = 0x09: overworld
    //    sub_module = 0x00 normal gameplay in overworld
    //               = 0x0e
    //      sub_sub_module = 0x01 in item menu
    //                     = 0x02 in dialog with NPC
    //               = 0x23 transitioning from light world to dark world or vice-versa
    // when module = 0x12: Link is dying
    //    sub_module = 0x00
    //               = 0x02 bonk
    //               = 0x03 black oval closing in
    //               = 0x04 red screen and spinning animation
    //               = 0x05 red screen and Link face down
    //               = 0x06 fade to black
    //               = 0x07 game over animation
    //               = 0x08 game over screen done
    //               = 0x09 save and continue menu
    sub_module = bus::read_u8(0x7E0011);

    // sub-sub-module goes from 01 to 0f during special animations such as link walking up/down stairs and
    // falling from ceiling and used as a counter for orange/blue barrier blocks transition going up/down
    sub_sub_module = bus::read_u8(0x7E00B0);
  }

  bool can_sync() {
    if (module == 0x09) {
      // in overworld, in a room, and during screen transitions:
      if (sub_module == 0x00 || sub_module <= 0x08) {
        return true;
      }
      return false;
    } else if (module == 0x07) {
      // in dungeon:
      if (sub_module == 0x00) {
        return true;
      }
      return true;
    } else if (module == 0x0e) {
      // dialogue:
      return (sub_module == 0x02);
    } else {
      return false;
    }
  }

  bool can_sample_location() {
    if (module == 0x09) {
      // in overworld, in a room, and NOT during screen transitions:
      if (sub_module == 0x00 || sub_module <= 0x08) {
        return true;
      }
      return false;
    } else if (module == 0x07) {
      // in dungeon:
      if (sub_module == 0x00) {
        return true;
      }
      return false;
    } else if (module == 0x0e) {
      // dialogue:
      return (sub_module == 0x02);
    } else {
      return false;
    }
  }

  void fetch() {
    y = bus::read_u16(0x7E0020, 0x7E0021);
    x = bus::read_u16(0x7E0022, 0x7E0023);
    z = bus::read_u16(0x7E0024, 0x7E0025);

    update_module();

    // $7E0410 = OW screen transitioning directional
    //ow_screen_transition = bus::read_u8(0x7E0410);

    // Don't update location until screen transition is complete:
    if (can_sample_location()) {
      last_location = location;

      // fetch various room indices and flags about where exactly Link currently is:
      auto in_dark_world = bus::read_u8(0x7E0FFF);
      auto in_dungeon = bus::read_u8(0x7E001B);
      auto overworld_room = bus::read_u16(0x7E008A, 0x7E008B);
      auto dungeon_room = bus::read_u16(0x7E00A0, 0x7E00A1);

      // compute aggregated location for Link into a single 24-bit number:
      location =
        uint32(in_dark_world & 1) << 17 |
        uint32(in_dungeon & 1) << 16 |
        uint32(in_dungeon != 0 ? dungeon_room : overworld_room);

      // clear out list of room changes if location changed:
      if (last_location != location) {
        message("room from 0x" + fmtHex(last_location, 6) + " to 0x" + fmtHex(location, 6));
      }
    }

    // get screen x,y offset by reading BG2 scroll registers:
    xoffs = int16(bus::read_u16(0x7E00E2, 0x7E00E3)) - int16(bus::read_u16(0x7E011A, 0x7E011B));
    yoffs = int16(bus::read_u16(0x7E00E8, 0x7E00E9)) - int16(bus::read_u16(0x7E011C, 0x7E011D));

/*
    if (!intercepting) {
      bus::add_write_interceptor("7e:2000-bfff", 0, bus::WriteInterceptCallback(this.mem_written));
      bus::add_write_interceptor("00-3f,80-bf:2100-213f", 0, bus::WriteInterceptCallback(this.ppu_written));
      cpu::register_dma_interceptor(cpu::DMAInterceptCallback(this.dma_intercept));
      intercepting = true;
    }
*/

    fetch_sprites();
  }

/*
  void mem_written(uint32 addr, uint8 value) {
    message("wram[0x" + fmtHex(addr, 6) + "] = 0x" + fmtHex(value, 2));
  }

  uint8 vmaddrl, vmaddrh;

  void ppu_written(uint32 addr, uint8 value) {
    //message(" ppu[0x__" + fmtHex(addr, 4) + "] = 0x" + fmtHex(value, 2));
    if (addr == 0x2116) vmaddrl = value;
    else if (addr == 0x2117) vmaddrh = value;
  }

  void dma_intercept(cpu::DMAIntercept @dma) {
    uint16 vmaddr = 0;
    // writing to 0x2118 (VMDATAL)
    if (dma.direction == 0 && dma.targetAddress == 0x18) {
      // ignore writes to BG and sprite tiles:
      if (vmaddrh >= 0x30) return;
      // compute vmaddr:
      vmaddr = uint16(vmaddrl) | (uint16(vmaddrh) << 8);
    }
    // ignore OAM sync:
    if (dma.direction == 0 && dma.targetAddress == 0x04) {
      return;
    }

    uint32 addr = uint32(dma.sourceBank) << 16 | uint32(dma.sourceAddress);

    string d = "...";
    if (dma.direction == 0 && dma.transferSize <= 0x20) {
      // from A bus to B bus:
      array<uint16> data;
      uint words = dma.transferSize >> 1;
      data.resize(words);
      bus::read_block_u16(addr, 0, words, data);

      d = "";
      for (uint i = 0; i < words; i++) {
        d += "0x" + fmtHex(data[i], 4);
        if (i < words - 1) d += ",";
      }
    }

    message(
      "dma[" + fmtInt(dma.channel) +
      (dma.direction == 0 ? "] to 0x21" : "] from 0x21") + fmtHex(dma.targetAddress, 2) +
      (dma.targetAddress == 0x18 ? " (vram 0x" + fmtHex(vmaddr, 4) + ")" : "") +
      (dma.direction == 0 ? " from 0x" : " to 0x") + fmtHex(addr, 6) +
      " size 0x" + fmtHex(dma.transferSize, 4) +
      " = {" + d + "}"
    );
  }
*/

  int numsprites;
  void fetch_sprites() {
    // get link's on-screen coordinates in OAM space:
    int16 rx = int16(x) - xoffs;
    int16 ry = int16(y) - yoffs;

    // read OAM offset where link's sprites start at:
    int link_oam_start = bus::read_u16(0x7E0352, 0x7E0353) >> 2;
    //message(fmtInt(link_oam_start));

    // read in relevant sprites from OAM and VRAM:
    sprites.resize(0);
    sprites.reserve(8);
    numsprites = 0;
    // start from reserved region for Link at 0x64 and cycle back around to 0x63 (up to 0x7F and wrap to 0x00):
    for (int j = 0; j < 0x0C; j++) {
      auto i = (link_oam_start + j) & 0x7F;

      // fetch ALTTP's copy of the OAM sprite data from WRAM:
      Sprite sprite;
      uint8 b0, b1, b2, b3, b4;
      b0 = bus::read_u8(0x7E0800 + (i << 2));
      b1 = bus::read_u8(0x7E0801 + (i << 2));
      b2 = bus::read_u8(0x7E0802 + (i << 2));
      b3 = bus::read_u8(0x7E0803 + (i << 2));
      b4 = bus::read_u8(0x7E0A00 + (i >> 2));
      b4 = (b4 >> ((i&3)<<1)) & 3;
      sprite.decodeOAMTableBytes(i, b0, b1, b2, b3, b4);

      // skip OAM sprite if not enabled (X, Y coords are out of display range):
      if (sprite.y == 0xF0) continue;

      //message("[" + fmtInt(sprite.index) + "] " + fmtInt(sprite.x) + "," + fmtInt(sprite.y) + "=" + fmtInt(sprite.chr));

      sprite.adjustXY(rx, ry);

      capture_sprite(sprite);
    }

    // capture effects sprites:
    for (int i = 0x0C; i < 0x12; i++) {
      // access current OAM sprite index:
      auto tile = ppu::oam[i];

      // skip OAM sprite if not enabled (X, Y coords are out of display range):
      if (!tile.is_enabled) continue;

      auto chr = tile.character;
      if (chr >= 0x100) continue;

      bool fx = (
        // sparkles around sword spin attack AND magic boomerang:
        chr == 0x80 || chr == 0x81 || chr == 0x82 || chr == 0x83 || chr == 0xb7 ||
        // exclusively for spin attack:
        chr == 0x8c || chr == 0x93 || chr == 0xd6 || chr == 0xd7 ||  // chr == 0x92 is also used here
        // sword tink on hard tile when poking:
        chr == 0x90 || chr == 0x92 || chr == 0xb9 ||
        // dash dust
        chr == 0xa9 || chr == 0xcf || chr == 0xdf ||
        // bush leaves
        chr == 0x59 ||
        // item rising from opened chest
        chr == 0x24
      );
      bool weapons = (
        // arrows
        chr == 0x2a || chr == 0x2b || chr == 0x2c || chr == 0x2d ||
        chr == 0x3a || chr == 0x3b || chr == 0x3c || chr == 0x3d ||
        // boomerang
        chr == 0x26 ||
        // magic powder
        chr == 0x09 || chr == 0x0a ||
        // lantern fire
        chr == 0xe3 || chr == 0xf3 || chr == 0xa4 || chr == 0xa5 || chr == 0xb2 || chr == 0xb3 || chr == 0x9c ||
        // push block
        chr == 0x0c ||
        // large stone
        chr == 0x4a ||
        // holding pot / bush or small stone or sign
        chr == 0x46 || chr == 0x44 || chr == 0x42 ||
        // shadow underneath pot / bush or small stone
        (i >= 1 && (ppu::oam[i-1].character == 0x46 || ppu::oam[i-1].character == 0x44) && chr == 0x6c) ||
        // pot shards or stone shards (large and small)
        chr == 0x58 || chr == 0x48
      );
      bool bombs = (
        // explosion:
        chr == 0x84 || chr == 0x86 || chr == 0x88 || chr == 0x8a || chr == 0x8c || chr == 0x9b ||
        // bomb and its shadow:
        (i <= 125 && chr == 0x6e && ppu::oam[i+1].character == 0x6c && ppu::oam[i+2].character == 0x6c) ||
        (i >= 1 && ppu::oam[i-1].character == 0x6e && chr == 0x6c && ppu::oam[i+1].character == 0x6c) ||
        (i >= 2 && ppu::oam[i-2].character == 0x6e && ppu::oam[i-1].character == 0x6c && chr == 0x6c)
      );
      bool follower = (
        chr == 0x20 || chr == 0x22
      );

      // skip OAM sprites that are not related to Link:
      if (!(fx || weapons || bombs || follower)) continue;

      // fetch the sprite data from OAM and VRAM:
      Sprite sprite;
      sprite.fetchOAM(i, rx, ry);

      capture_sprite(sprite);
    }
  }

  void capture_sprite(Sprite &sprite) {
    //message("capture_sprite " + fmtInt(sprite.index));
    // load character(s) from VRAM:
    if (sprite.size == 0) {
      // 8x8 sprite:
      if (chrs[sprite.chr].length() == 0) {
        chrs[sprite.chr].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr), 0, 16, chrs[sprite.chr]);
      }
    } else {
      // 16x16 sprite:
      if (chrs[sprite.chr].length() == 0) {
        chrs[sprite.chr + 0x00].resize(16);
        chrs[sprite.chr + 0x01].resize(16);
        chrs[sprite.chr + 0x10].resize(16);
        chrs[sprite.chr + 0x11].resize(16);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x00), 0, 16, chrs[sprite.chr + 0x00]);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x01), 0, 16, chrs[sprite.chr + 0x01]);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x10), 0, 16, chrs[sprite.chr + 0x10]);
        ppu::vram.read_block(ppu::vram.chr_address(sprite.chr + 0x11), 0, 16, chrs[sprite.chr + 0x11]);
      }
    }

    // append the sprite to our array:
    sprites.resize(++numsprites);
    @sprites[numsprites-1] = sprite;
  }

  bool can_see(uint32 other_location) {
    return (location == other_location);
  }

  void serialize(array<uint8> &r) {
    // start with sentinel value to make sure deserializer knows it's the start of a message:
    r.insertLast(uint16(0xFEEF));
    r.insertLast(location);
    r.insertLast(x);
    r.insertLast(y);
    r.insertLast(z);
    r.insertLast(uint8(sprites.length()));
    //message("serialize: numsprites = " + fmtInt(sprites.length()));
    for (uint i = 0; i < sprites.length(); i++) {
      sprites[i].serialize(r);
    }

    // how many distinct characters:
    uint16 chr_count = 0;
    for (uint16 i = 0; i < 512; i++) {
      if (chrs[i].length() == 0) continue;
      ++chr_count;
    }

    // emit how many chrs:
    r.insertLast(chr_count);
    for (uint16 i = 0; i < 512; ++i) {
      if (chrs[i].length() == 0) continue;

      // which chr is it:
      r.insertLast(i);
      // emit the tile data:
      r.insertLast(chrs[i]);

      // clear the chr tile data for next frame:
      chrs[i].resize(0);
    }
  }

  void send() {
    // build envelope:
    array<uint8> envelope;
    // header
    envelope.insertLast(uint16(25887));
    // clientType = 1 (player)
    envelope.insertLast(uint8(1));
    // group name:
    envelope.insertLast(uint8(settings.Group.length()));
    envelope.insertLast(settings.Group);
    // player name:
    envelope.insertLast(uint8(settings.Name.length()));
    envelope.insertLast(settings.Name);

    // append local state to remote player:
    int beforeLen = envelope.length();
    serialize(envelope);

    // length check:
    //if ((envelope.length() - beforeLen) != int(expected_packet_size)) {
    //  message("send(): failed to produce a packet of the expected size!");
    //  return;
    //}

    // send envelope to server:
    //message("sent " + fmtInt(envelope.length()));
    sock.send(0, envelope.length(), envelope);
  }

  bool deserialize(array<uint8> r, int c) {
    // deserialize data packet:
    auto sentinel = uint16(r[c++]) | (uint16(r[c++]) << 8);
    if (sentinel != 0xFEEF) {
      // garbled or split packet
      message("garbled packet");
      return false;
    }

    location = uint32(r[c++])
               | (uint32(r[c++]) << 8)
               | (uint32(r[c++]) << 16)
               | (uint32(r[c++]) << 24);

    x = uint16(r[c++]) | (uint16(r[c++]) << 8);
    y = uint16(r[c++]) | (uint16(r[c++]) << 8);
    z = uint16(r[c++]) | (uint16(r[c++]) << 8);

    // read in OAM sprites:
    auto numsprites = r[c++];
    sprites.resize(numsprites);
    for (uint i = 0; i < numsprites; i++) {
      @sprites[i] = Sprite();
      c = sprites[i].deserialize(r, c);
    }

    // clear previous chr tile data:
    for (uint i = 0; i < 512; i++) {
      chrs[i].resize(0);
    }

    // read in chr data:
    auto chr_count = uint16(r[c++]) | (uint16(r[c++]) << 8);
    for (uint i = 0; i < chr_count; i++) {
      // read chr number:
      auto h = uint16(r[c++]) | (uint16(r[c++]) << 8);

      // read chr tile data:
      chrs[h].resize(16);
      for (int k = 0; k < 16; k++) {
        chrs[h][k] = uint16(r[c++]) | (uint16(r[c++]) << 8);
      }
    }

    return true;
  }

  void overwrite_tile(uint16 addr, array<uint16> tiledata) {
    // read previous VRAM tile:
    array<uint16> backup(16);
    ppu::vram.read_block(addr, 0, 16, backup);

    // overwrite VRAM tile:
    ppu::vram.write_block(addr, 0, 16, tiledata);

    // store backup:
    chr_backup.insertLast(Tile(addr, backup));
  }

  void render(int x, int y) {
    // true/false map to determine which local characters are free for replacement in current frame:
    array<bool> chr(512);
    // lookup remote chr number to find local chr number mapped to:
    array<uint16> reloc(512);
    // assume first 0x100 characters are in-use (Link body, sword, shield, weapons, rupees, etc):
    for (uint j = 0; j < 0x100; j++) {
      chr[j] = true;
    }
    // exclude follower sprite from default assumption of in-use:
    chr[0x20] = false;
    chr[0x21] = false;
    chr[0x30] = false;
    chr[0x31] = false;
    chr[0x22] = false;
    chr[0x23] = false;
    chr[0x32] = false;
    chr[0x33] = false;
    // run through OAM sprites and determine which characters are actually in-use:
    for (uint j = 0; j < 128; j++) {
      auto tile = ppu::oam[j];
      // NOTE: we could skip the is_enabled check which would make the OAM appear to be a LRU cache of characters
      //if (!tile.is_enabled) continue;

      // mark chr as used in current frame:
      uint addr = tile.character;
      if (tile.size == 0) {
        // 8x8 tile:
        chr[addr] = true;
      } else {
        // 16x16 tile:
        chr[addr+0x00] = true;
        chr[addr+0x01] = true;
        chr[addr+0x10] = true;
        chr[addr+0x11] = true;
      }
    }

    // add in remote sprites:
    chr_backup.resize(0);
    for (uint i = 0; i < sprites.length(); i++) {
      auto sprite = sprites[i];
      auto px = sprite.size == 0 ? 8 : 16;

      // bounds check for OAM sprites:
      if (sprite.x + x < -px) continue;
      if (sprite.x + x >= 256) continue;
      if (sprite.y + y < -px) continue;
      if (sprite.y + y >= 240) continue;

      // determine which OAM sprite slot is free around the desired index:
      int j;
      for (j = sprite.index; j < 128; j++) {
        if (!ppu::oam[j].is_enabled) break;
      }
      if (j == 128) {
        for (j = sprite.index; j >= 0; j--) {
          if (!ppu::oam[j].is_enabled) break;
        }
        // no more free slots?
        if (j == -1) return;
      }

      // start building a new OAM sprite:
      auto oam = ppu::oam[j];
      oam.x = uint16(sprite.x + x);
      oam.y = sprite.y + y;
      oam.hflip = sprite.hflip;
      oam.vflip = sprite.vflip;
      oam.priority = sprite.priority;
      oam.palette = sprite.palette;
      oam.size = sprite.size;

      // find free character(s) for replacement:
      if (sprite.size == 0) {
        // 8x8 sprite:
        if (reloc[sprite.chr] == 0) { // assumes use of chr=0 is invalid, which it is since it is for local Link.
          for (uint k = 0x20; k < 512; k++) {
            // skip chr if in-use:
            if (chr[k]) continue;

            oam.character = k;
            chr[k] = true;
            reloc[sprite.chr] = k;
            overwrite_tile(ppu::vram.chr_address(k), chrs[sprite.chr]);
            break;
          }
        } else {
          // use existing chr:
          oam.character = reloc[sprite.chr];
        }
      } else {
        // 16x16 sprite:
        if (reloc[sprite.chr] == 0) { // assumes use of chr=0 is invalid, which it is since it is for local Link.
          for (uint k = 0x20; k < 512; k += 2) {
            // skip every odd row since 16x16 are aligned on even rows 0x00, 0x20, 0x40, etc:
            if ((k & 0x10) != 0) continue;
            // skip chr if in-use:
            if (chr[k]) continue;

            oam.character = k;
            chr[k + 0x00] = true;
            chr[k + 0x01] = true;
            chr[k + 0x10] = true;
            chr[k + 0x11] = true;
            reloc[sprite.chr + 0x00] = k + 0x00;
            reloc[sprite.chr + 0x01] = k + 0x01;
            reloc[sprite.chr + 0x10] = k + 0x10;
            reloc[sprite.chr + 0x11] = k + 0x11;
            overwrite_tile(ppu::vram.chr_address(k + 0x00), chrs[sprite.chr + 0x00]);
            overwrite_tile(ppu::vram.chr_address(k + 0x01), chrs[sprite.chr + 0x01]);
            overwrite_tile(ppu::vram.chr_address(k + 0x10), chrs[sprite.chr + 0x10]);
            overwrite_tile(ppu::vram.chr_address(k + 0x11), chrs[sprite.chr + 0x11]);
            break;
          }
        } else {
          // use existing chrs:
          oam.character = reloc[sprite.chr];
        }
      }

      // TODO: do this via NMI and DMA transfers in real hardware (aka not faking it via emulator hacks).
      // update sprite in OAM memory:
      @ppu::oam[j] = oam;
    }
  }

  void cleanup() {
    auto len = chr_backup.length();
    for (uint i = 0; i < len; i++) {
      ppu::vram.write_block(
        chr_backup[i].addr,
        0,
        16,
        chr_backup[i].tiledata
      );
    }
    chr_backup.resize(0);
  }
};

GameState local;
array<GameState@> players;
uint8 isRunning;

bool intercepting = false;

void pre_nmi() {
  // Wait until the game starts:
  isRunning = bus::read_u8(0x7E0010);
  if (isRunning < 0x06 || isRunning > 0x13) return;

  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;

  // Attempt to open a server socket:
  if (@sock == null) {
    try {
      // open a UDP socket to receive data from:
      @address = net::resolve_udp(settings.ServerAddress, 4590);
      // open a UDP socket to receive data from:
      @sock = net::Socket(address);
      // connect to remote address so recv() and send() work:
      sock.connect(address);
    } catch {
      // Probably server IP field is invalid; prompt user again:
      @sock = null;
      settings.started = false;
      settings.show();
    }
  }

  // fetch local game state from WRAM:
  local.fetch();

  // send updated state for our Link to player 2:
  local.send();

  // receive network update from remote players:
  receive();
}

void pre_frame() {
  if (@sprites != null) {
    for (int i = 0; i < 16; i++) {
      palette7[i] = ppu::cgram[(15 << 4) + i];
    }
    sprites.render(palette7);
    sprites.update();
  }

  // load 8 sprite palettes from CGRAM:
  array<array<uint16>> palettes(8, array<uint16>(16));
  for (int i = 0; i < 8; i++) {
    for (int c = 0; c < 16; c++) {
      palettes[i][c] = ppu::cgram[128 + (i << 4) + c];
    }
  }

  // render remote players:
  for (uint i = 0; i < players.length(); i++) {
    auto remote = players[i];

    // only draw remote player if location (room, dungeon, light/dark world) is identical to local player's:
    if (local.can_see(remote.location) && local.can_sync()) {
      // subtract BG2 offset from sprite x,y coords to get local screen coords:
      int16 rx = int16(remote.x) - local.xoffs;
      int16 ry = int16(remote.y) - local.yoffs;

      // draw remote player relative to current BG offsets:
      remote.render(rx, ry);
    }
  }
}

void receive() {
  array<GameState@> packets;

  array<uint8> r(9500);
  int n;
  while ((n = sock.recv(0, 9500, r)) > 0) {
    int c = 0;

    // verify envelope header:
    uint16 header = uint16(r[c++]) | (uint16(r[c++]) << 8);
    if (header != 25887) {
      message("receive(): bad envelope header!");
      continue;
    }

    // check client type (spectator=0, player=1):
    uint8 clientType = r[c++];
    // skip messages from non-players (e.g. spectators):
    if (clientType != 1) {
      message("receive(): ignore non-player message");
      continue;
    }

    // skip group name:
    uint8 groupLen = r[c++];
    c += groupLen;

    // skip player name:
    uint8 nameLen = r[c++];
    c += nameLen;

    // deserialize data packet:
    GameState @remote = GameState();
    remote.deserialize(r, c);

    packets.insertLast(remote);
  }

  players = packets;
}

void post_frame() {
  if (debug) {
    ppu::frame.text_shadow = true;
    ppu::frame.color = 0x7fff;
    ppu::frame.text(0, 0, fmtHex(local.module, 2));
    ppu::frame.text(20, 0, fmtHex(local.sub_module, 2));
    ppu::frame.text(40, 0, fmtHex(local.sub_sub_module, 2));

    for (uint i = 0; i < 0x10; i++) {
      // generate CGA 16-color palette, lol.
      auto j = i + 1;
      ppu::frame.color = ppu::rgb(
        ((j & 4) >> 2) * 0x12 + ((j & 8) >> 3) * 0x0d,
        ((j & 2) >> 1) * 0x12 + ((j & 8) >> 3) * 0x0d,
        ((j & 1)) * 0x12 + ((j & 8) >> 3) * 0x0d
      );
      ppu::frame.text(i * 16, 224 - 8, fmtHex(bus::read_u8(0x7E012C + i), 2));
    }
  }

  if (debugOAM) {
    ppu::frame.draw_op = ppu::draw_op::op_alpha;
    ppu::frame.color = ppu::rgb(28, 28, 28);
    ppu::frame.alpha = 28;
    ppu::frame.text_shadow = true;

    for (int i = 0; i < 128; i++) {
      // access current OAM sprite index:
      auto tile = ppu::oam[i];

      auto chr = tile.character;
      auto x = int16(tile.x);
      auto y = int16(tile.y);
      if (x >= 256) x -= 512;

      //ppu::frame.rect(x, y, width, height);

      ppu::frame.color = ppu::rgb(28, 28, 0);
      ppu::frame.text((i / 28) * (4*8 + 8), (i % 28) * 8, fmtHex(i, 2));

      if (tile.is_enabled) {
        ppu::frame.color = ppu::rgb(28, 28, 28);
      } else {
        ppu::frame.color = ppu::rgb(8, 8, 12);
      }

      ppu::frame.text((i / 28) * (4*8 + 8) + 16, (i % 28) * 8, fmtHex(tile.character, 2));
    }
  }

  // module check:
  if (isRunning < 0x06 || isRunning > 0x13) return;

  // Don't do anything until user fills out Settings window inputs:
  if (!settings.started) return;

  // restore previous VRAM tiles:
  for (uint i = 0; i < players.length(); i++) {
    players[i].cleanup();
  }
}
