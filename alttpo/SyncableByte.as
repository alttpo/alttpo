
funcdef bool SyncableByteShouldCapture(uint32 addr, uint8 oldValue, uint8 newValue);

class SyncableByte {
  uint16 offs;

  uint32 timestamp;
  uint8 value;
  uint8 oldValue;

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
    r.write_u32(timestamp);
    r.write_u16(value);
  }

  int deserialize(array<uint8> &r, int c) {
    // save old value:
    this.oldValue = this.value;

    // deserialize new value:
    timestamp = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    value = uint16(r[c++]) | (uint16(r[c++]) << 8);

    return c;
  }

  // bus::WriteInterceptCallback
  void wram_written(uint32 addr, uint8 oldValue, uint8 newValue) {
    if ((shouldCapture !is null) && !shouldCapture(addr, oldValue, newValue)) {
      return;
    }

    this.oldValue = oldValue;
    this.value = newValue;
    this.timestamp = timestamp_now;
  }
};
