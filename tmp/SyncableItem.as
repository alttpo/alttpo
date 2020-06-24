
funcdef uint16 ItemMutate(uint16 oldValue, uint16 newValue);

funcdef void NotifyItemReceived(const string &in name);
funcdef void NotifyNewItems(uint16 oldValue, uint16 newValue, NotifyItemReceived @notify);

// list of SRAM values to sync as items:
class SyncableItem {
  uint16  offs;   // SRAM offset from $7EF000 base address
  uint8   size;   // 1 - byte, 2 - word
  uint8   type;   // 0 - custom mutate, 1 - highest wins, 2 - bitfield, 3+ TBD...
  ItemMutate @mutate = null;
  NotifyNewItems @notifyNewItems = null;

  SyncableItem(uint16 offs, uint8 size, uint8 type, NotifyNewItems @notifyNewItems = null) {
    this.offs = offs;
    this.size = size;
    this.type = type;
    @this.notifyNewItems = notifyNewItems;
  }

  SyncableItem(uint16 offs, uint8 size, ItemMutate @mutate, NotifyNewItems @notifyNewItems = null) {
    this.offs = offs;
    this.size = size;
    this.type = 0;
    @this.mutate = mutate;
    @this.notifyNewItems = notifyNewItems;
  }
};

class SyncableHealthCapacity : SyncableItem {
  SyncableHealthCapacity() {
    super(0x36C, 1, 0);

    // this custom SyncableItem covers both:
    // SyncableItem(0x36B, 1, 1),  // heart pieces (out of four)
    // SyncableItem(0x36C, 1, 1),  // health capacity
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

uint16 mutateSword(uint16 oldValue, uint16 newValue) {
  // during the dwarven swordsmith quest, sword goes to 0xFF when taken away, so avoid that trap:
  if (newValue >= 1 && newValue <= 4 && newValue > oldValue) {
    // JSL DecompSwordGfx
    return newValue;
  }
  return oldValue;
}

uint16 mutateShield(uint16 oldValue, uint16 newValue) {
  if (newValue > oldValue) {
    // JSL DecompShieldGfx
    return newValue;
  }
  return oldValue;
}

// NOTE: this is called for both gloves and armor separately so could JSL twice in succession for one frame.
uint16 mutateArmorGloves(uint16 oldValue, uint16 newValue) {
  if (newValue > oldValue) {
    // JSL Palette_ChangeGloveColor
    return newValue;
  }
  return oldValue;
}

uint16 mutateBottleItem(uint16 oldValue, uint16 newValue) {
  // only sync gaining a new bottle: 0 = no bottle, 2 = empty bottle.
  if (oldValue == 0 && newValue != 0) return newValue;
  return oldValue;
}

uint16 mutateZeroToNonZero(uint16 oldValue, uint16 newValue) {
  // Allow if replacing 'no item':
  if (oldValue == 0 && newValue != 0) return newValue;
  return oldValue;
}

uint16 mutateFlute(uint16 oldValue, uint16 newValue) {
  // Allow if replacing 'no item':
  if (oldValue == 0 && newValue != 0) return newValue;
  // Allow if replacing 'flute' with 'bird+flute':
  if (oldValue == 2 && newValue == 3) return newValue;
  return oldValue;
}

const uint8 bitPowder   = 1<<4;
const uint8 bitMushroom = 1<<5;

uint16 mutateRandomizerItems(uint16 oldValue, uint16 newValue) {
  // INVENTORY_SWAP = "$7EF38C"
  // Item Tracking Slot
  // brmpnskf
  // b = blue boomerang
  // r = red boomerang
  // m = mushroom current
  // p = magic powder
  // n = mushroom past
  // s = shovel
  // k = fake flute
  // f = working flute

  uint8 mushroom = bus::read_u8(0x7EF344);
  // if gaining powder and have no inventory:
  if (
    ((oldValue & bitPowder) == 0) &&
    ((newValue & bitPowder) == bitPowder) &&
    mushroom == 0
  ) {
    // set powder in inventory:
    bus::write_u8(0x7EF344, 2);
  }

  // if gaining mushroom and have no inventory:
  if (
    ((oldValue & bitMushroom) == 0) &&
    ((newValue & bitMushroom) == bitMushroom) &&
    mushroom == 0
  ) {
    // set mushroom in inventory:
    bus::write_u8(0x7EF344, 1);
  }

  //// if had mushroom and lost mushroom:
  //if (
  //  ((oldValue & bitMushroom) == bitMushroom) &&
  //  ((newValue & bitMushroom) == 0) &&
  //  mushroom == 1
  //) {
  //  // if don't have powder, set to empty:
  //  if ((oldValue & bitPowder) == 0) {
  //    bus::write_u8(0x7EF344, 0);
  //  } else {
  //    // else set powder in inventory:
  //    bus::write_u8(0x7EF344, 2);
  //  }
  //}

  return oldValue | newValue;
}

void notify(uint16 oldValue, uint16 newValue, NotifyItemReceived @notify) {
}
