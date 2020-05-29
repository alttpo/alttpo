
funcdef uint16 ItemMutate(uint16 oldValue, uint16 newValue);

// list of SRAM values to sync as items:
class SyncableItem {
  uint16  offs;   // SRAM offset from $7EF000 base address
  uint8   size;   // 1 - byte, 2 - word
  uint8   type;   // 0 - custom mutate, 1 - highest wins, 2 - bitfield, 3+ TBD...
  ItemMutate @mutate = null;

  SyncableItem(uint16 offs, uint8 size, uint8 type) {
    this.offs = offs;
    this.size = size;
    this.type = type;
  }

  SyncableItem(uint16 offs, uint8 size, ItemMutate @mutate) {
    this.offs = offs;
    this.size = size;
    this.type = 0;
    @this.mutate = @mutate;
  }

  uint16 oldValue;
  uint16 newValue;
  void start() {
    oldValue = readRAM();
    newValue = oldValue;
  }

  void apply(GameState @remote) {
    auto remoteValue = read(remote.sram);
    newValue = modify(newValue, remoteValue);
  }

  void finish() {
    if (newValue != oldValue) {
      write(newValue);
    }
  }

  uint16 modify(uint16 oldValue, uint16 newValue) {
    if (type == 0) {
      if (@this.mutate is null) {
        return oldValue;
      }
      return this.mutate(oldValue, newValue);
    } else if (type == 1) {
      // max value:
      if (newValue > oldValue) {
        return newValue;
      }
      return oldValue;
    } else if (type == 2) {
      // bitfield OR:
      newValue = oldValue | newValue;
      return newValue;
    }
    return oldValue;
  }

  uint16 readRAM() {
    if (size == 1) {
      return bus::read_u8(0x7EF000 + offs);
    } else {
      return bus::read_u16(0x7EF000 + offs);
    }
  }

  uint16 read(const array<uint8> &in sram) {
    if (size == 1) {
      return sram[offs];
    } else {
      return uint16(sram[offs]) | (uint16(sram[offs+1]) << 8);
    }
  }

  void write(uint16 newValue) {
    if (size == 1) {
      bus::write_u8(0x7EF000 + offs, uint8(newValue));
    } else if (size == 2) {
      bus::write_u16(0x7EF000 + offs, newValue);
    }
  }
};

class SyncableHealthCapacity : SyncableItem {
  SyncableHealthCapacity() {
    super(0x36C, 1, 0);

    // this custom SyncableItem covers both:
    // SyncableItem(0x36B, 1, 1),  // heart pieces (out of four)
    // SyncableItem(0x36C, 1, 1),  // health capacity
  }

  uint16 modify(uint16 oldValue, uint16 newValue) override {
    // max value:
    if (newValue > oldValue) {
      return newValue;
    }
    return oldValue;
  }

  uint16 readRAM() override {
    return (bus::read_u8(0x7EF36C) & ~7) | (bus::read_u8(0x7EF36B) & 3);
  }

  uint16 read(const array<uint8> &in sram) override {
    // this works because [0x36C] is always a multiple of 8 and the lower 3 bits are always zero
    // and [0x36B] is in the range [0..3] aka 2 bits:
    return (sram[0x36C] & ~7) | (sram[0x36B] & 3);
  }

  void write(uint16 newValue) override {
    // split out the full hearts from the heart pieces:
    auto hearts = uint8(newValue) & ~uint8(7);
    auto pieces = uint8(newValue) & uint8(3);
    //message("heart write! " + fmtHex(uint8(oldValue),2) + " -> " + fmtHex(uint8(newValue),2) + " = " + fmtInt(hearts) + ", " + fmtInt(pieces));
    bus::write_u8(0x7EF36C, hearts);
    bus::write_u8(0x7EF36B, pieces);
  }
}

uint16 mutateWorldState(uint16 oldValue, uint16 newValue) {
  // if local player is in the intro sequence, keep them there:
  if (oldValue < 2) return oldValue;

  // sync the bigger value:
  if (newValue > oldValue) return newValue;
  return oldValue;
}

uint16 mutateProgress1(uint16 oldValue, uint16 newValue) {
  // don't sync progress bits unless we're past the escape sequence; too many opportunities for soft-locks:
  auto worldState = bus::read_u8(0x7EF000 + 0x3C5);
  if (worldState < 2) {
    return oldValue;
  }

  // if local player has not grabbed gear from uncle, then keep uncle alive in the secret passage otherwise Zelda's
  // telepathic prompts will get rather annoying.
  if (oldValue & 0x01 == 0) {
    newValue &= ~uint8(0x01);
  }
  // if local player has not achieved uncle leaving house, leave it cleared otherwise link never wakes up.
  if (oldValue & 0x10 == 0) {
    newValue &= ~uint8(0x10);
  }
  return newValue | oldValue;
}

uint16 mutateBottleItem(uint16 oldValue, uint16 newValue) {
  // only sync gaining a new bottle: 0 = no bottle, 2 = empty bottle.
  if (oldValue == 0 && newValue != 0) return newValue;
  return oldValue;
}
