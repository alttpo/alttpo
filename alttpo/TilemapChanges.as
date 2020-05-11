
class TilemapChanges {
  array<int32> state(0x1000); // 0x1000 * 16-bit items (using int32 to allow -1 to mean "no change")
  int size = 0;

  int get_opIndex(int idx) property {
    return state[idx];
  }
  void set_opIndex(int idx, int value) property {
    state[idx] = value;
  }

  void reset(uint8 size) {
    // only 0x20 or 0x40 are acceptable values:
    if (size <= 0x20) size = 0x20;
    else size = 0x40;

    message("tilemap.reset(0x" + fmtHex(size, 2) + ")");
    this.size = size;

    for (uint i = 0; i < 0x1000; i++) {
      state[i] = -1;
    }
  }

  void copy_to_wram() {
    if (size == 0) return;

    for (uint i = 0, n = 0; i < 0x1000; i++, n += 2) {
      if (state[i] < 0) continue;
      bus::write_u16(0x7E2000 + n, uint16(state[i]));
    }
  }

  void apply(TilemapRun @run) {
    // apply the run to the tilemap, overwriting any existing values:
    uint32 addr = run.offs;
    uint32 stride = run.vertical ? size : 1;

    if (run.same) {
      // use same tile value for entire run:
      for (uint n = 0; n < run.count; n++) {
        state[addr] = run.tile;
        addr += stride;
      }
    } else {
      // use individual tile values at each step:
      for (uint n = 0; n < run.count; n++) {
        state[addr] = run.tiles[n];
        addr += stride;
      }
    }
  }

  void serialize(array<uint8> @r) {
    // copy the state to a tmp array so we can mutate it:
    array<int32> tmp = state;
    array<TilemapRun> runs;

    // $20 x $20 or $40 x $40
    uint width = size;
    uint height = size;
    uint stride = 0x40;

    for (uint y = 0; y < height; y++) {
      auto row = (y * stride);
      for (uint x = 0; x < width; x++) {
        // start a run at first tile that's not -1:
        auto tile = tmp[row + x];
        if (tile == -1) continue;

        // measure horizontal span:
        uint hcount = 0;
        bool hsame = true;
        for (uint n = x; n < width; n++) {
          auto i = row + n;
          if (tmp[i] == -1) break;
          if (tmp[i] != tile) hsame = false;
          hcount++;
        }

        // measure vertical span:
        uint vcount = 0;
        bool vsame = true;
        for (uint n = y; n < height; n++) {
          auto i = (n * stride) + x;
          if (tmp[i] == -1) break;
          if (tmp[i] != tile) vsame = false;
          vcount++;
        }

        // create the run:
        TilemapRun run;
        run.offs = row + x;
        if (vcount > hcount) {
          // vertical run:
          run.vertical = true;
          run.count = vcount;
          run.same = vsame;
          if (run.same) {
            run.tile = tile;
          }

          // add each tile to the run:
          for (uint n = y; n < y + vcount; n++) {
            auto i = (n * stride) + x;
            if (!run.same) {
              run.tiles.insertLast(tmp[i]);
            }

            // mark as processed:
            tmp[i] = -1;
          }
        } else {
          // horizontal run:
          run.vertical = false;
          run.count = hcount;
          run.same = hsame;
          if (run.same) {
            run.tile = tile;
          }

          // add each tile to the run:
          for (uint n = x; n < x + hcount; n++) {
            auto i = row + n;
            if (!run.same) {
              run.tiles.insertLast(tmp[i]);
            }

            // mark as processed:
            tmp[i] = -1;
          }
        }

        runs.insertLast(run);
      }
    }

    // serialize runs to message:
    r.write_u8(runs.length());
    for (uint i = 0; i < runs.length(); i++) {
      auto @run = runs[i];
      run.serialize(r);
    }
  }
}
