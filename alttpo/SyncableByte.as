
funcdef bool SyncableByteShouldCapture(uint32 addr, uint8 oldValue, uint8 newValue);

class SyncableByte {
  uint16 offs;

  uint32 timestamp;
  uint8 value;

  SyncableByteShouldCapture@ shouldCapture;

  SyncableByte(uint16 offs) {
    this.offs = offs;
    @this.shouldCapture = null;

    this.value = 0;
    this.timestamp = 0;
  }

  void register(SyncableByteShouldCapture@ shouldCapture) {
    @this.shouldCapture = shouldCapture;
    bus::add_write_interceptor("7e:" + fmtHex(offs, 4), bus::WriteInterceptCallback(this.wram_written));
  }

  void serialize(array<uint8> &r) {
    r.write_u16(offs);
    r.write_u32(timestamp);
    r.write_u16(value);
  }

  // bus::WriteInterceptCallback
  void wram_written(uint32 addr, uint8 oldValue, uint8 newValue) {
    if ((shouldCapture !is null) && !shouldCapture(addr, oldValue, newValue)) {
      return;
    }

    this.value = newValue;
    this.timestamp = timestamp_now;
  }
};
