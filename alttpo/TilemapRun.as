
// represents a horizontal or vertical run of tilemap changes, either all the same tile or all different tiles:
class TilemapRun {
  uint16 offs;
  bool same;
  bool vertical;

  uint8 count;
  uint16 tile;
  array<uint16> tiles;

  int deserialize(array<uint8> @r, int c) {
    offs = uint16(r[c++]) | uint16(r[c++]) << 8;

    // all tiles are the same value:
    if ((offs & 0x8000) == 0x8000) {
      same = true;
    } else {
      same = false;
    }

    // head in a vertical increasing direction:
    if ((offs & 0x4000) == 0x4000) {
      vertical = true;
    } else {
      vertical = false;
    }

    // mask off signal bits to get pure offset:
    offs &= 0x1FFF;

    // read count of tiles:
    count = r[c++];

    if (same) {
      // if all the same tile, read single value:
      tile = uint16(r[c++]) | uint16(r[c++]) << 8;
    } else {
      // if not all the same tile, read all tile values:
      tiles.resize(count);
      for (uint i = 0; i < count; i++) {
        tiles[i] = uint16(r[c++]) | uint16(r[c++]) << 8;
      }
    }

    return c;
  }

  void serialize(array<uint8> @r) {
    uint16 t = offs;
    if (same) {
      t |= 0x8000;
    }
    if (vertical) {
      t |= 0x4000;
    }

    r.write_u16(t);
    r.write_u8(count);
    if (same) {
      r.write_u16(tile);
    } else {
      for (uint i = 0; i < count; i++) {
        r.write_u16(tiles[i]);
      }
    }
  }
};
