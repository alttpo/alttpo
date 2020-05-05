// ALTTP script to draw current Link sprites on top of rendered frame:
net::Socket@ sock;
net::Address@ address;
SettingsWindow @settings;

bool debug = false;
bool debugData = false;
bool debugOAM = false;
bool debugSprites = false;
bool debugGameObjects = false;

void init() {
  // Auto-detect ROM version:
  @rom = detect();

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

  @worldMap = WorldMap();

  if (debugOAM) {
    @oamWindow = OAMWindow();
  }

  if (debugGameObjects) {
    @gameSpriteWindow = GameSpriteWindow();
  }
}

// TODO: debug window to show current full area and place GameSprites on it with X,Y coordinates

GameState local;
array<GameState@> players(0);
uint8 isRunning;

bool intercepting = false;

// called when bsnes changes its color palette:
void palette_updated() {
  //message("palette_updated()");
  if (@worldMap != null) {
    worldMap.redrawMap();
  }
}
