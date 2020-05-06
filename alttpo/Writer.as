
abstract class Writer {
  void seek(uint p) {}

  void u8(uint8 d) {}
  void u16(uint16 d) {}
  void u24(uint32 d) {}
}

class NullWriter : Writer {
  void seek(uint p) {}

  void u8(uint8 d) {}
  void u16(uint16 d) {}
  void u24(uint32 d) {}
}

class ArrayWriter : Writer {
  array<uint8> @a;
  uint p;

  ArrayWriter(array<uint8> @a, uint p = 0) {
    @this.a = @a;
    this.p = p;
  }

  void seek(uint p) {
    this.p = p;
  }

  void u8(uint8 d) {
    a[p++] = d;
  }

  void u16(uint16 d) {
    a[p++] = (d & 0x00ff);
    a[p++] = (d & 0xff00) >> 8;
  }

  void u24(uint32 d) {
    a[p++] = (d & 0x0000ff);        //     L
    a[p++] = (d & 0x00ff00) >> 8;   //     H
    a[p++] = (d & 0xff0000) >> 16;  //     B
  }
}

class BusWriter : Writer {
  uint32 addr;
  uint p;

  BusWriter(uint32 addr, uint p = 0) {
    this.addr = addr;
    this.p = p;
  }

  void seek(uint p) {
    this.p = p;
  }

  void u8(uint8 d) {
    bus::write_u8(addr + p++, d);
  }

  void u16(uint16 d) {
    bus::write_u8(addr + p++, (d & 0x00ff));
    bus::write_u8(addr + p++, (d & 0xff00) >> 8);
  }

  void u24(uint32 d) {
    bus::write_u8(addr + p++, (d & 0x0000ff));        //     L
    bus::write_u8(addr + p++, (d & 0x00ff00) >> 8);   //     H
    bus::write_u8(addr + p++, (d & 0xff0000) >> 16);  //     B
  }
}
