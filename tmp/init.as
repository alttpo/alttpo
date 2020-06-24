
funcdef uint16 ItemMutate(uint16 oldValue, uint16 newValue);

funcdef void NotifyItemReceived(const string &in name);
funcdef void NotifyNewItems(uint16 oldValue, uint16 newValue, NotifyItemReceived @notify);

// list of SRAM values to sync as items:
class SyncableItem {
  NotifyNewItems @notifyNewItems = null;

  SyncableItem(NotifyNewItems @notifyNewItems = null) {
    @this.notifyNewItems = notifyNewItems;
  }
};

// Lookup table of ROM addresses depending on version:
class Container {
  // MUST be sorted by offs ascending:
  array<SyncableItem@> @syncables = {
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem(),
    @SyncableItem()
  };
};

void init() {
  message("init()");

  auto @list = Container();

  auto len = list.syncables.length();
  for (uint i = 0; i < len; i++) {
    auto @s = list.syncables[i];
    if (s is null) {
      message("[" + fmtInt(i) + "] = null");
      continue;
    }
    message("[" + fmtInt(i) + "] = yes");
  }
}
