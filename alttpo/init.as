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

// called when cartridge powered on or reset or after init when cartridge already loaded and script loaded afterwards:
void post_power(bool reset) {
  //message("post_power()");

  // Auto-detect ROM version:
  @rom = detect();

  // patch the ROM code to inject our control routine:
  if (!reset) {
    // read the JSL target address from the RESET vector code:
    rom.read_main_routing();

    // create the patch buffer that holds our temporary code:
    pb.power(true);

    // intercept at PC=`JSR ClearOamBuffer; JSL MainRouting`:
    cpu::register_pc_interceptor(rom.fn_pre_main_loop, @on_main_loop);

    init_torches();
  }

  if (@worldMapWindow != null) {
    worldMapWindow.loadMap();
    worldMapWindow.drawMap();
  }
}

// TODO: debug window to show current full area and place GameSprites on it with X,Y coordinates

GameState local;
array<GameState@> players(0);
