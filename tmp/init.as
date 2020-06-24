
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

uint16 mutateMax(uint16 oldValue, uint16 newValue) {
  // sync the bigger value:
  if (newValue > oldValue) return newValue;
  return oldValue;
}

void notify(uint16 oldValue, uint16 newValue, NotifyItemReceived @notify) {
}

USROMMapping @rom = null;

// Lookup table of ROM addresses depending on version:
class USROMMapping {
  // MUST be sorted by offs ascending:
  array<SyncableItem@> @syncables = {
    @SyncableItem(0x340, 1, 1, @notify),         // bow
    @SyncableItem(0x341, 1, 1, @notify),   // boomerang
    @SyncableItem(0x342, 1, 1, @notify),    // hookshot
    //SyncableItem(0x343, 1, 3),  // bombs (TODO)
    @SyncableItem(0x344, 1, 1, @notify),    // mushroom
    @SyncableItem(0x345, 1, 1, @notify),     // fire rod
    @SyncableItem(0x346, 1, 1, @notify),      // ice rod
    @SyncableItem(0x347, 1, 1, @notify),      // bombos
    @SyncableItem(0x348, 1, 1, @notify),       // ether
    @SyncableItem(0x349, 1, 1, @notify),       // quake
    @SyncableItem(0x34A, 1, 1, @notify),        // lamp/lantern
    @SyncableItem(0x34B, 1, 1, @notify),      // hammer
    @SyncableItem(0x34C, 1, 1, @notify),       // flute
    @SyncableItem(0x34D, 1, 1, @notify),      // bug net
    @SyncableItem(0x34E, 1, 1, @notify),        // book
    //SyncableItem(0x34F, 1, 1),  // current bottle selection (1-4); do not sync as it locks the bottle selector in place
    @SyncableItem(0x350, 1, 1, @notify), // cane of somaria
    @SyncableItem(0x351, 1, 1, @notify),   // cane of byrna
    @SyncableItem(0x352, 1, 1, @notify),   // magic cape
    @SyncableItem(0x353, 1, 1, @notify), // magic mirror
    @SyncableItem(0x354, 1, @mutateMax, @notify),  // gloves
    @SyncableItem(0x355, 1, 1, @notify),       // boots
    @SyncableItem(0x356, 1, 1, @notify),    // flippers
    @SyncableItem(0x357, 1, 1, @notify),   // moon pearl
    // 0x358 unused
    @SyncableItem(0x359, 1, @mutateMax, @notify),   // sword
    @SyncableItem(0x35A, 1, @mutateMax, @notify),  // shield
    @SyncableItem(0x35B, 1, @mutateMax, @notify),   // armor

    // bottle contents 0x35C-0x35F
    @SyncableItem(0x35C, 1, @mutateMax, @notify),
    @SyncableItem(0x35D, 1, @mutateMax, @notify),
    @SyncableItem(0x35E, 1, @mutateMax, @notify),
    @SyncableItem(0x35F, 1, @mutateMax, @notify),

    @SyncableItem(0x364, 1, 2, @notify),  // dungeon compasses 1/2
    @SyncableItem(0x365, 1, 2, @notify),  // dungeon compasses 2/2
    @SyncableItem(0x366, 1, 2, @notify),   // dungeon big keys 1/2
    @SyncableItem(0x367, 1, 2, @notify),   // dungeon big keys 2/2
    @SyncableItem(0x368, 1, 2, @notify),      // dungeon maps 1/2
    @SyncableItem(0x369, 1, 2, @notify),      // dungeon maps 2/2

    @SyncableHealthCapacity(),  // heart pieces (out of four) [0x36B], health capacity [0x36C]

    @SyncableItem(0x370, 1, 1),  // bombs capacity
    @SyncableItem(0x371, 1, 1),  // arrows capacity

    @SyncableItem(0x374, 1, 2, @notify),  // pendants
    //SyncableItem(0x377, 1, 1),  // arrows
    @SyncableItem(0x379, 1, 2),  // player ability flags
    @SyncableItem(0x37A, 1, 2, @notify),  // crystals

    @SyncableItem(0x37B, 1, 1, @notify),  // magic usage

    @SyncableItem(0x3C5, 1, @mutateMax, @notify),  // general progress indicator
    @SyncableItem(0x3C6, 1, @mutateMax, @notify),  // progress event flags 1/2
    @SyncableItem(0x3C7, 1, 1),  // map icons shown

    //@SyncableItem(0x3C8, 1, 1),  // start at location… options; DISABLED - causes bugs

    // progress event flags 2/2
    @SyncableItem(0x3C9, 1, 2, @notify)

  };
};

void init() {
  message("init()");

  auto @rom = USROMMapping();

  auto len = rom.syncables.length();
  for (uint i = 0; i < len; i++) {
    auto @s = rom.syncables[i];
    if (s is null) {
      message("[" + fmtInt(i) + "] = null");
      continue;
    }
    message("[" + fmtInt(i) + "] = " + fmtHex(s.offs, 3) + ", " + fmtInt(s.size) + ", " + fmtInt(s.type));
  }
}
