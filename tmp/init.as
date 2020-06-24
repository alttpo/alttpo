
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
