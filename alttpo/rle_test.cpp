#include <stdint.h>
#include <stdio.h>

typedef int32_t int32;
typedef uint16_t uint16;
typedef uint8_t uint8;
typedef uint32_t uint;

#include <vector>
using namespace std;

#define array vector
#define insertLast push_back

struct TilemapRun {
  uint16 offs;
  bool same;
  bool vertical;

  uint8 count;
  uint16 tile;
  array<uint16> tiles;
};

int main() {
  array<int32> tilemap(0x1000);
  for (uint i = 0; i < 0x1000; i++) {
    tilemap[i] = -1;
  }

  // test data:
  tilemap[0x0412]=0x0dc7;
  tilemap[0x0413]=0x0dc7;
  tilemap[0x0452]=0x0dc7;
  tilemap[0x0453]=0x0dc7;
  tilemap[0x0454]=0x0dc7;
  tilemap[0x0492]=0x0dc7;
  tilemap[0x0493]=0x0dc7;
  tilemap[0x0494]=0x0dc7;
  tilemap[0x0495]=0x0dc7;
  tilemap[0x0496]=0x0dc7;
  tilemap[0x04d2]=0x0dc7;
  tilemap[0x04d3]=0x0dc7;
  tilemap[0x04d4]=0x0dc7;
  tilemap[0x04d5]=0x0dc7;
  tilemap[0x04d6]=0x0dc7;
  tilemap[0x0512]=0x0dc7;
  tilemap[0x0513]=0x0dc7;
  tilemap[0x0514]=0x0dc7;
  tilemap[0x0515]=0x0dc7;
  tilemap[0x0516]=0x0dc7;
  tilemap[0x0552]=0x0dc7;
  tilemap[0x0553]=0x0dc7;
  tilemap[0x0592]=0x0dc7;
  tilemap[0x064c]=0x0dc7;
  tilemap[0x064d]=0x0dc7;
  tilemap[0x064e]=0x0dc7;
  tilemap[0x068c]=0x0dc7;
  tilemap[0x068d]=0x0dc7;

  // compress:
  array<TilemapRun> runs;

  // $20 x $20 or $40 x $40
  uint width = 0x40;
  uint height = 0x40;

  for (uint y = 0; y < height; y++) {
    auto row = (y * width);
    for (uint x = 0; x < width; x++) {
      // start a run at first tile that's not -1:
      auto tile = tilemap[row + x];
      if (tile == -1) continue;

      // measure horizontal span:
      int hcount = 0;
      bool hsame = true;
      for (uint n = x; n < width; n++) {
        auto i = row + n;
        if (tilemap[i] == -1) break;
        if (tilemap[i] != tile) hsame = false;
        hcount++;
      }

      // measure vertical span:
      int vcount = 0;
      bool vsame = true;
      for (uint n = y; n < height; n++) {
        auto i = (n*width) + x;
        if (tilemap[i] == -1) break;
        if (tilemap[i] != tile) vsame = false;
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
            run.tiles.insertLast(tilemap[i]);
          }

          // mark as processed:
          tilemap[i] = -1;
        }

        if (run.same) {
          printf("vert same offs=%04x count=%d tiles=%04x\n", run.offs, run.count, run.tile);
        } else {
          printf("vert diff offs=%04x count=%d tiles=", run.offs, run.count);
          for (auto t : run.tiles) {
            printf("%04x ", t);
          }
          printf("\n");
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
            run.tiles.insertLast(tilemap[i]);
          }

          // mark as processed:
          tilemap[i] = -1;
        }

        if (run.same) {
          printf("horz same offs=%04x count=%d tiles=%04x\n", run.offs, run.count, run.tile);
        } else {
          printf("horz diff offs=%04x count=%d tiles=", run.offs, run.count);
          for (auto t : run.tiles) {
            printf("%04x ", t);
          }
          printf("\n");
        }
      }

      runs.insertLast(run);
    }
  }

  return 0;
}