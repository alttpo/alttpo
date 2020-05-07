net::Socket@ sock;
net::Address@ address;

bool debug = false;
bool debugData = false;
bool debugOAM = false;
bool debugSprites = false;
bool debugGameObjects = false;

void init() {
  //message("init()");

  @settings = SettingsWindow();
  settings.ServerAddress = "bittwiddlers.org";
  settings.Group = "enemy-sync";
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

  @worldMapWindow = WorldMapWindow();

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
}

// called when cartridge powered on or reset or after init when cartridge already loaded and script loaded afterwards:
void post_power(bool reset) {
  //message("post_power()");

  if (!reset) {
    // intercept at PC=`JSR ClearOamBuffer; JSL MainRouting`:
    cpu::register_pc_interceptor(rom.fn_pre_main_loop, @on_main_loop);

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

// TODO: debug window to show current full area and place GameSprites on it with X,Y coordinates

GameState local;
array<GameState@> players(0);
