
funcdef bool SyncableByteShouldCapture(uint32 addr, uint8 oldValue, uint8 newValue);

class SyncableByte {
  uint16 offs;

  uint32 timestamp;
  uint8 value;
  uint8 oldValue;

  uint32 timestampCompare;
  SyncableByte@ winner;

  SyncableByteShouldCapture@ shouldCapture;

  SyncableByte(uint16 offs) {
    this.offs = offs;
    @this.shouldCapture = null;

    this.value = 0;
    this.oldValue = 0;
    this.timestamp = 0;
  }

  void register(SyncableByteShouldCapture@ shouldCapture) {
    @this.shouldCapture = shouldCapture;
    bus::add_write_interceptor("7e:" + fmtHex(offs, 4), bus::WriteInterceptCallback(this.wram_written));

    reset();
  }

  // initialize value to current WRAM value:
  void reset() {
    resetTo(bus::read_u8(0x7E0000 + offs));
  }

  // initialize value to specific WRAM value:
  void resetTo(uint8 newValue) {
    this.timestamp = 0;
    this.value = newValue;
    this.oldValue = newValue;
  }

  void capture(uint8 newValue) {
    this.oldValue = this.value;
    this.value = newValue;
    this.timestamp = timestamp_now;
  }

  bool updateTo(SyncableByte@ other) {
    this.oldValue = this.value;
    this.value = other.value;

    this.timestamp = other.timestamp;
    bus::write_u8(0x7E0000 + offs, this.value);

    return (this.value != this.oldValue);
  }

  void serialize(array<uint8> &r) {
    r.write_u32(timestamp);
    r.write_u16(value);
  }

  int deserialize(array<uint8> &r, int c) {
    // deserialize new value:
    timestamp = uint32(r[c++]) | (uint32(r[c++]) << 8) | (uint32(r[c++]) << 16) | (uint32(r[c++]) << 24);
    value = uint16(r[c++]) | (uint16(r[c++]) << 8);

    return c;
  }

  // bus::WriteInterceptCallback
  void wram_written(uint32 addr, uint8 oldValue, uint8 newValue) {
    if (shouldCapture !is null) {
      bool capture = shouldCapture(addr, oldValue, newValue);
      if (!capture) {
        // record the values but not the timestamp:
        this.oldValue = oldValue;
        this.value = newValue;
        return;
      }
    }

    capture(newValue);
  }

  void compareStart() {
    @winner = null;
    timestampCompare = timestamp;
  }

  void compareTo(SyncableByte@ other) {
    //auto otherTimestamp = other.timestamp;
    //if (otherTimestamp > timestampCompare) {
    //  @winner = @other;
    //  timestampCompare = otherTimestamp;
    //}
  }
};
