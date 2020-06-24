
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
};

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
    @SyncableItem(0x340, 1, 1),
    @SyncableItem(0x341, 1, 1),
    @SyncableItem(0x342, 1, 1),
    @SyncableItem(0x344, 1, 1),
    @SyncableItem(0x345, 1, 1),
    @SyncableItem(0x346, 1, 1),
    @SyncableItem(0x347, 1, 1),
    @SyncableItem(0x348, 1, 1),
    @SyncableItem(0x349, 1, 1),
    @SyncableItem(0x34A, 1, 1),
    @SyncableItem(0x34B, 1, 1),
    @SyncableItem(0x34C, 1, 1),
    @SyncableItem(0x34D, 1, 1),
    @SyncableItem(0x34E, 1, 1),
    @SyncableItem(0x350, 1, 1),
    @SyncableItem(0x351, 1, 1),
    @SyncableItem(0x352, 1, 1),
    @SyncableItem(0x353, 1, 1)
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
