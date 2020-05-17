net::Socket@ sock;
net::Address@ address;

bool debug = false;
bool debugData = false;
bool debugOAM = false;
bool debugSprites = false;
bool debugGameObjects = false;
bool enableMap = true;
bool enableBgMusic = true;

void init() {
  //message("init()");

  @settings = SettingsWindow();
  settings.ServerAddress = "bittwiddlers.org";
  settings.Group = "tile-sync";
  settings.Name = "";
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

// TODO: debug window to show current full area and place GameSprites on it with X,Y coordinates

LocalGameState local;
array<GameState@> players(0);
