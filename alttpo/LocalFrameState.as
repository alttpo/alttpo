LocalFrameState localFrameState;

class Tile {
  uint16 addr;
  array<uint16> tiledata;

  Tile(uint16 addr, array<uint16> tiledata) {
    this.addr = addr;
    this.tiledata = tiledata;
  }
};

// captures local frame state for rendering purposes:
class LocalFrameState {
  // true/false map to determine which local characters are free for replacement in current frame:
  array<bool> chr(512);
  // backup of VRAM tiles overwritten:
  array<Tile@> chr_backup;

  void backup() {
    //message("frame.backup");
    // assume first 0x100 characters are in-use (Link body, sword, shield, weapons, rupees, etc):
    for (uint j = 0; j < 0x100; j++) {
      chr[j] = true;
    }
    for (uint j = 0x100; j < 0x200; j++) {
      chr[j] = false;
    }

    // run through OAM sprites and determine which characters are actually in-use:
    for (uint j = 0; j < 128; j++) {
      Sprite sprite;
      sprite.decodeOAMTable(j);
      // NOTE: we could skip the is_enabled check which would make the OAM appear to be a LRU cache of characters
      //if (!sprite.is_enabled) continue;

      // mark chr as used in current frame:
      uint addr = sprite.chr;
      if (sprite.size == 0) {
        // 8x8 tile:
        chr[addr] = true;
      } else {
        if (addr > 0x1EE) continue;
        // 16x16 tile:
        chr[addr+0x00] = true;
        chr[addr+0x01] = true;
        chr[addr+0x10] = true;
        chr[addr+0x11] = true;
      }
    }
  }

  void overwrite_tile(uint16 addr, array<uint16> tiledata) {
    if (tiledata.length() == 0) {
      message("overwrite_tile: empty tiledata for addr=0x" + fmtHex(addr,4));
      return;
    }

    // read previous VRAM tile:
    array<uint16> backup(16);
    ppu::vram.read_block(addr, 0, 16, backup);

    // overwrite VRAM tile:
    ppu::vram.write_block(addr, 0, 16, tiledata);

    // store backup:
    chr_backup.insertLast(Tile(addr, backup));
  }

  void restore() {
    //message("frame.restore");

    // restore VRAM contents:
    auto len = chr_backup.length();
    for (uint i = 0; i < len; i++) {
      ppu::vram.write_block(
        chr_backup[i].addr,
        0,
        16,
        chr_backup[i].tiledata
      );
    }

    // clear backup of VRAM data:
    chr_backup.resize(0);
  }
};
