net::Socket@ sock;
net::Address@ address;

bool debug = false;
bool debugData = false;
bool debugNet = false;
bool debugOAM = false;
bool debugSprites = false;
bool debugGameObjects = false;

bool enableMap = true;
bool enableBgMusic = true;

bool enableObjectSync = false;
bool enableRenderToExtra = true;

void init() {
  //message("init()");

  @settings = SettingsWindow();
  settings.ServerAddress = "bittwiddlers.org";
  settings.GroupTrimmed = "group1";
  settings.Name = "player1";
  settings.PlayerColor = ppu::rgb(28, 2, 2);
  settings.load();

  if (debug) {
    //settings.ServerAddress = "127.0.0.1";
    //settings.Group = "debug";
    settings.start();
    settings.hide();
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

  // read the JSL target address from the RESET vector code:
  rom.read_main_routing();

  // patch the ROM code to inject our control routine:
  pb.power(true);

  // register ROM intercepts for local player:
  local.register();
}

// called when cartridge powered on or reset or after init when cartridge already loaded and script loaded afterwards:
void post_power(bool reset) {
  //message("post_power()");

  if (!reset) {
    // intercept at PC=`JSR ClearOamBuffer; JSL MainRouting`:
    cpu::register_pc_interceptor(rom.fn_pre_main_loop, @on_main_loop);

    //cpu::register_pc_interceptor(0x008D13, @debug_pc);  // in NMI - scrolling OW tilemap update on every 16x16 change
    //cpu::register_pc_interceptor(0x02F273, @debug_pc);  // in main loop - scrolling OW tilemap update on every 16x16 change

    init_torches();
  }

  @onlyLocalPlayer[0] = local;

  if (@worldMapWindow != null) {
    worldMapWindow.loadMap();
    worldMapWindow.drawMap();
  }
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

bool font_set = false;
