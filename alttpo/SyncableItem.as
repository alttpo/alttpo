
funcdef void ItemModifiedCallback(uint16 offs, uint16 oldValue, uint16 newValue);

// list of SRAM values to sync as items:
class SyncableItem {
  uint16  offs;   // SRAM offset from $7EF000 base address
  uint8   size;   // 1 - byte, 2 - word
  uint8   type;   // 1 - highest wins, 2 - bitfield, 3+ TBD...

  ItemModifiedCallback@ modifiedCallback = null;

  SyncableItem(uint16 offs, uint8 size, uint8 type) {
    this.offs = offs;
    this.size = size;
    this.type = type;
    @this.modifiedCallback = null;
  }

  SyncableItem(uint16 offs, uint8 size, uint8 type, ItemModifiedCallback@ callback) {
    this.offs = offs;
    this.size = size;
    this.type = type;
    @this.modifiedCallback = @callback;
  }

  void modified(uint16 oldValue, uint16 newValue) {
    if (modifiedCallback is null) return;
    modifiedCallback(offs, oldValue, newValue);
  }
};

void LoadShieldGfx(uint16 offs, uint16 oldValue, uint16 newValue) {
  // JSL DecompShieldGfx
  //cpu::call(0x005308);
}

void MoonPearlBunnyLink(uint16 offs, uint16 oldValue, uint16 newValue) {
  // Switch Link's graphics between bunny and regular:
  // FAIL: This doesn't work immediately and instead causes bunny to retain even into light world until dashing.
  //bus::write_u8(0x7E0056, 0);
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
  SyncableItem(0x357, 1, 1, @MoonPearlBunnyLink),  // moon pearl
  // 0x358 unused
  SyncableItem(0x359, 1, 1),  // sword
  SyncableItem(0x35A, 1, 1, @LoadShieldGfx),  // shield
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
  SyncableItem(0x3C6, 1, 2),  // progress event flags 1/2
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
