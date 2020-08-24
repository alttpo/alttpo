net::Socket@ sock;
net::Address@ address;

bool debug = false;

bool debugReadout = false;
bool debugData = false;
bool debugSRAM = false;
bool debugNet = false;
bool debugOAM = false;
bool debugSprites = false;
bool debugGameObjects = false;

bool debugRTDScapture = false;
bool debugRTDScompress = false;
bool debugRTDSapply = false;

bool enableMap = true;
bool enableBgMusic = true;

bool enableObjectSync = false;
bool enableRenderToExtra = true;

void init() {
  //message("init()");

  @settings = SettingsWindow();
  settings.ServerAddress = "alttp.online";
  settings.GroupTrimmed = "group1";
  settings.Name = "player1";
  settings.PlayerColor = ppu::rgb(28, 2, 2);
  settings.load();

  @bridge = Bridge(
    @StateUpdated(settings.bridgeStateUpdated),
    @MessageUpdated(settings.bridgeMessageUpdated)
  );

  if (debug) {
    //settings.ServerAddress = "127.0.0.1";
    //settings.Group = "debug";
    settings.connect();
  }

  if (debugSprites) {
    @sprites = SpritesWindow();
  }

  if (enableMap) {
    @worldMapWindow = WorldMapWindow();
  }

  if (debugOAM) {
    @oamWindow = OAMWindow();
  }

  if (debugGameObjects) {
    @gameSpriteWindow = GameSpriteWindow();
  }
}

void cartridge_loaded() {
  //message("cartridge_loaded()");

  // Auto-detect ROM version:
  @rom = detect();

  //auto len = rom.syncables.length();
  //for (uint i = 0; i < len; i++) {
  //  auto @s = rom.syncables[i];
  //  if (s is null) {
  //    message("[" + fmtInt(i) + "] = null");
  //    continue;
  //  }
  //  message("[" + fmtInt(i) + "] = " + fmtHex(s.offs, 3) + ", " + fmtInt(s.size) + ", " + fmtInt(s.type));
  //}

  // read the JSL target address from the RESET vector code:
  rom.read_main_routing();

  // patch the ROM code to inject our control routine:
  pb.power(true);

  // register ROM intercepts for local player:
  local.register(true);

  // draw map window when cartridge loaded:
  if (@worldMapWindow != null) {
    worldMapWindow.loadMap(true);
    worldMapWindow.drawMap();
  }

  if (settings.DiscordEnable) {
    discord::cartridge_loaded();
  }
}

// called when cartridge powered on or reset or after init when cartridge already loaded and script loaded afterwards:
void post_power(bool reset) {
  //message("post_power()");

  if (!reset) {
    // intercept at PC=`JSR ClearOamBuffer; JSL MainRouting`:
    rom.register_pc_intercepts();

    //cpu::register_pc_interceptor(0x008D13, @debug_pc);  // in NMI - scrolling OW tilemap update on every 16x16 change
    //cpu::register_pc_interceptor(0x02F273, @debug_pc);  // in main loop - scrolling OW tilemap update on every 16x16 change

    init_torches();
  }

  // clear state:
  local.reset();

  @onlyLocalPlayer[0] = local;
}

// called when script itself is unloaded:
void unload() {
  if (@rom != null) {
    // restore patched JSL:
    pb.unload();
  }
}

void debug_pc(uint32 addr) {
  message(fmtHex(addr, 6));
}

string padTo(string value, int len) {
  auto newValue = value.slice(0, len);
  for (int i = newValue.length(); i < len; i++) {
    newValue += " ";
  }
  return newValue;
}

string fmtBool(bool value) {
  return value ? "true" : "false";
}

LocalGameState local;
array<GameState@> players(0);
array<GameState@> onlyLocalPlayer(1);
int playerCount = 0;

bool font_set = false;

uint32 timestamp_now = 0;
