
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
