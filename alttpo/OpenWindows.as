// Opens the windows, creating them the first time. Windows are never destroyed so they keep their size and position
// while closed. Which windows open at startup are settings of the Advanced Settings window.

void openMapWindow() {
  if (worldMapWindow is null) {
    @worldMapWindow = WorldMapWindow();
    // draw the map if the game is loaded already:
    if (rom !is null && local !is null) {
      worldMapWindow.cartridge_loaded();
    }
  }
  worldMapWindow.show();
}

void openPlayersWindow() {
  if (playersWindow is null) {
    @playersWindow = PlayersWindow();
  }
  playersWindow.show();
}

void openDebugWindow() {
  if (debugWindow is null) {
    @debugWindow = DebugWindow();
  }
  debugWindow.show();
}

// the windows below show the game's state so there has to be a game:
bool noGameLoaded(const string &in what) {
  if (rom is null || local is null) {
    message("The " + what + " window opens once a game is loaded");
    return true;
  }
  return false;
}

void openMemoryWindow() {
  if (noGameLoaded("Memory")) return;

  if (memoryWindow is null) {
    @memoryWindow = MemoryWindow();
  }
  memoryWindow.show();
}

void openSpritesWindow() {
  if (noGameLoaded("Sprite VRAM")) return;

  if (sprites is null) {
    @sprites = SpritesWindow();
  }
  sprites.show();
}

void openOamWindow() {
  if (noGameLoaded("OAM")) return;

  if (oamWindow is null) {
    @oamWindow = OAMWindow();
  }
  oamWindow.show();
}

void openEnemyWindow() {
  if (noGameLoaded("Enemies")) return;

  if (enemyWindow is null) {
    @enemyWindow = EnemyWindow();
  }
  enemyWindow.show();
}

// openStartupWindows opens the windows that do not need a game when the script starts:
void openStartupWindows() {
  if (settings.OpenMap) openMapWindow();
  if (settings.OpenPlayers) openPlayersWindow();
  if (settings.OpenDebug) openDebugWindow();
}

// openStartupGameWindows opens the windows that need a game once it is loaded:
void openStartupGameWindows() {
  if (settings.OpenMemory || debugMemory) openMemoryWindow();
  if (settings.OpenVram || debugSprites) openSpritesWindow();
  if (settings.OpenOam || debugOAM) openOamWindow();
  if (settings.OpenEnemies || debugEnemyWindow) openEnemyWindow();
}
