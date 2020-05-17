
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

  void write(uint16 newValue) {
    if (size == 1) {
      bus::write_u8(0x7EF000 + offs, uint8(newValue));
    } else if (size == 2) {
      bus::write_u16(0x7EF000 + offs, newValue);
    }
  }
};

uint16 mutateProgress1(uint16 oldValue, uint16 newValue) {
  // if local player has not achieved uncle leaving house, leave it cleared otherwise link never wakes up.
  if (oldValue & 0x10 == 0) {
    newValue &= ~uint8(0x10);
  }
  return newValue | oldValue;
}

// items MUST be sorted by offs:
array<SyncableItem@> @syncableItems = {
  SyncableItem(0x340, 1, 1),  // bow
  SyncableItem(0x341, 1, 1),  // boomerang
  SyncableItem(0x342, 1, 1),  // hookshot
  //SyncableItem(0x343, 1, 3),  // bombs (TODO)
  SyncableItem(0x344, 1, 1),  // mushroom
  SyncableItem(0x345, 1, 1),  // fire rod
  SyncableItem(0x346, 1, 1),  // ice rod
  SyncableItem(0x347, 1, 1),  // bombos
  SyncableItem(0x348, 1, 1),  // ether
  SyncableItem(0x349, 1, 1),  // quake
  SyncableItem(0x34A, 1, 1),  // lantern
  SyncableItem(0x34B, 1, 1),  // hammer
  SyncableItem(0x34C, 1, 1),  // flute
  SyncableItem(0x34D, 1, 1),  // bug net
  SyncableItem(0x34E, 1, 1),  // book
  //SyncableItem(0x34F, 1, 1),  // have bottles - FIXME: syncing this without bottle contents causes softlock for randomizer
  SyncableItem(0x350, 1, 1),  // cane of somaria
  SyncableItem(0x351, 1, 1),  // cane of byrna
  SyncableItem(0x352, 1, 1),  // magic cape
  SyncableItem(0x353, 1, 1),  // magic mirror
  SyncableItem(0x354, 1, 1),  // gloves
  SyncableItem(0x355, 1, 1),  // boots
  SyncableItem(0x356, 1, 1),  // flippers
  SyncableItem(0x357, 1, 1),  // moon pearl
  // 0x358 unused
  SyncableItem(0x359, 1, 1),  // sword
  SyncableItem(0x35A, 1, 1),  // shield
  SyncableItem(0x35B, 1, 1),  // armor

  // bottle contents 0x35C-0x35F - TODO: sync bottle contents iff local bottle value == 0x02 (empty)

  SyncableItem(0x364, 1, 2),  // dungeon compasses 1/2
  SyncableItem(0x365, 1, 2),  // dungeon compasses 2/2
  SyncableItem(0x366, 1, 2),  // dungeon big keys 1/2
  SyncableItem(0x367, 1, 2),  // dungeon big keys 2/2
  SyncableItem(0x368, 1, 2),  // dungeon maps 1/2
  SyncableItem(0x369, 1, 2),  // dungeon maps 2/2

  SyncableItem(0x36B, 1, 1),  // heart pieces (out of four)
  SyncableItem(0x36C, 1, 1),  // health capacity

  SyncableItem(0x370, 1, 1),  // bombs capacity
  SyncableItem(0x371, 1, 1),  // arrows capacity

  SyncableItem(0x374, 1, 2),  // pendants
  SyncableItem(0x379, 1, 2),  // player ability flags
  SyncableItem(0x37A, 1, 2),  // crystals

  SyncableItem(0x37B, 1, 1),  // magic usage

  SyncableItem(0x3C5, 1, 1),  // general progress indicator
  SyncableItem(0x3C6, 1, @mutateProgress1),  // progress event flags 1/2
  SyncableItem(0x3C7, 1, 1),  // map icons shown
  SyncableItem(0x3C8, 1, 1),  // start at location… options
  SyncableItem(0x3C9, 1, 2)   // progress event flags 2/2

// NO TRAILING COMMA HERE!
};

class SyncedItem {
  uint16  offs;
  uint16  value;
  uint16  lastValue;
};
