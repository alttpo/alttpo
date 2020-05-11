
class TilemapChanges {
  array<int32> state(0x1000); // 0x1000 * 16-bit items (using int32 to allow -1 to mean "no change")
  int size = 0x20;

  int get_opIndex(int idx) property {
    return state[idx];
  }
  void set_opIndex(int idx, int value) property {
    state[idx] = value;
  }

  void setSize(uint8 s) {
    if (s > 0) {
      size = 0x40;
    } else {
      size = 0x20;
    }
  }

  void reset() {
    for (uint i = 0; i < 0x1000; i++) {
      state[i] = -1;
    }
  }

  void apply(TilemapRun @run) {
    // TODO
  }

  void serialize(array<uint8> @r) {
    array<TilemapRun> runs;

    // $20 x $20 or $40 x $40
    uint width = size;
    uint height = size;

    for (uint y = 0; y < height; y++) {
      auto row = (y * width);
      for (uint x = 0; x < width; x++) {
        // start a run at first tile that's not -1:
        auto tile = state[row + x];
        if (tile == -1) continue;

        // measure horizontal span:
        uint hcount = 0;
        bool hsame = true;
        for (uint n = x; n < width; n++) {
          auto i = row + n;
          if (state[i] == -1) break;
          if (state[i] != tile) hsame = false;
          hcount++;
        }

        // measure vertical span:
        uint vcount = 0;
        bool vsame = true;
        for (uint n = y; n < height; n++) {
          auto i = (n*width) + x;
          if (state[i] == -1) break;
          if (state[i] != tile) vsame = false;
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
            auto i = (n*width) + x;
            if (!run.same) {
              run.tiles.insertLast(state[i]);
            }

            // mark as processed:
            state[i] = -1;
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
              run.tiles.insertLast(state[i]);
            }

            // mark as processed:
            state[i] = -1;
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
