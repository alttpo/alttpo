// Remembers the size and the position (relative to the main emulator window) of every GUI window and restores them
// the next time the script starts. The layout is stored in the settings file next to the settings (see
// SettingsWindow::save() and ::load()) under `window/<key>/{x,y,width,height}`.
//
// A window is saved whenever it is moved, resized or closed, and all open windows are saved when the script unloads.
WindowLayout windowLayout;

// not a possible position or size, means that the settings file has no value:
const int64 layoutUnknown = -999999;

// the windows that have a saved layout:
const array<string> windowKeys = {"settings", "advanced", "map", "players", "memory", "vram", "oam", "enemies"};

// the saved geometry of one window; sizes are of the window's client area:
class WindowGeom {
  string key;
  bool has = false;
  int x;
  int y;
  int w;
  int h;
}

// a window the layout keeps track of:
class ManagedWindow {
  string key;
  GUI::Window @window;

  ManagedWindow(const string &in key, GUI::Window @window) {
    this.key = key;
    @this.window = window;
  }

  // callback:
  void moved() {
    windowLayout.changed(this);
  }

  // callback:
  void sized() {
    windowLayout.changed(this);
  }

  // callback: only called for windows that the user can dismiss; the default of hiding the window is replaced by
  // this, so hide it here:
  void closed() {
    // remember where the window was before it goes away:
    windowLayout.changed(this);
    window.visible = false;
  }
}

class WindowLayout {
  private array<WindowGeom@> geoms;
  private array<ManagedWindow@> managed;

  // set once the settings were read; nothing is saved before so that the GUI's initial state cannot overwrite the file:
  private bool loaded = false;
  // set while the saved layout is applied so the resulting move and size events are not saved again:
  private bool applying = false;

  // where the main emulator window was on the screen:
  private bool mainHas = false;
  private int mainX;
  private int mainY;
  private uint pollFrames = 0;

  private WindowGeom@ geomFor(const string &in key) {
    for (uint i = 0; i < geoms.length(); i++) {
      if (geoms[i].key == key) return geoms[i];
    }
    auto @g = WindowGeom();
    g.key = key;
    geoms.insertLast(g);
    return g;
  }

  // attach starts keeping track of the window and applies the saved layout to it if there is one:
  void attach(const string &in key, GUI::Window @window) {
    auto @m = ManagedWindow(key, window);
    managed.insertLast(m);

    window.onMove(@GUI::Callback(m.moved));
    window.onSize(@GUI::Callback(m.sized));
    window.onClose(@GUI::Callback(m.closed));

    apply(m);
  }

  private void apply(ManagedWindow @m) {
    auto @g = geomFor(m.key);
    if (!g.has) return;

    applying = true;
    m.window.size = GUI::Size(g.w, g.h);
    m.window.setRelativePosition(g.x, g.y);
    applying = false;
  }

  // load reads the saved layout from the settings file and applies it to the windows already attached; windows
  // attached later get it when they attach:
  void load(BML::Node doc) {
    int64 mx = doc["window/main/x"].integerOr(layoutUnknown);
    int64 my = doc["window/main/y"].integerOr(layoutUnknown);
    if (mx != layoutUnknown && my != layoutUnknown) {
      mainHas = true;
      mainX = int(mx);
      mainY = int(my);

      // put the main window back first since the other windows are positioned relative to it:
      applying = true;
      GUI::setMainWindowPosition(mainX, mainY);
      applying = false;
    }

    for (uint i = 0; i < windowKeys.length(); i++) {
      read(doc, windowKeys[i]);
    }
    loaded = true;

    for (uint i = 0; i < managed.length(); i++) {
      apply(managed[i]);
    }
  }

  private void read(BML::Node doc, const string &in key) {
    auto @g = geomFor(key);
    auto prefix = "window/" + key + "/";
    int64 x = doc[prefix + "x"].integerOr(layoutUnknown);
    int64 y = doc[prefix + "y"].integerOr(layoutUnknown);
    int64 w = doc[prefix + "width"].integerOr(layoutUnknown);
    int64 h = doc[prefix + "height"].integerOr(layoutUnknown);
    if (x == layoutUnknown || y == layoutUnknown || w == layoutUnknown || h == layoutUnknown) return;
    if (w < 50 || h < 50) return;

    g.has = true;
    g.x = int(x);
    g.y = int(y);
    g.w = int(w);
    g.h = int(h);
  }

  // save writes the layout of every window known to the settings document:
  void save(BML::Node doc) {
    if (mainHas) {
      doc.create("window/main/x").value = fmtInt(mainX);
      doc.create("window/main/y").value = fmtInt(mainY);
    }

    for (uint i = 0; i < geoms.length(); i++) {
      auto @g = geoms[i];
      if (!g.has) continue;

      auto prefix = "window/" + g.key + "/";
      doc.create(prefix + "x").value = fmtInt(g.x);
      doc.create(prefix + "y").value = fmtInt(g.y);
      doc.create(prefix + "width").value = fmtInt(g.w);
      doc.create(prefix + "height").value = fmtInt(g.h);
    }
  }

  // capture reads the current geometry of a window; returns true if it differs from the one saved:
  private bool capture(ManagedWindow @m) {
    // a window that is not shown has no real geometry; keep what was saved:
    if (!m.window.visible) return false;

    GUI::Size size;
    size = m.window.geometry.size;
    GUI::Position pos;
    pos = m.window.relativePosition;
    int w = int(size.width);
    int h = int(size.height);
    if (w < 50 || h < 50) return false;

    int x = int(pos.x);
    int y = int(pos.y);

    auto @g = geomFor(m.key);
    if (g.has && g.x == x && g.y == y && g.w == w && g.h == h) return false;

    g.has = true;
    g.x = x;
    g.y = y;
    g.w = w;
    g.h = h;
    return true;
  }

  // captureMain reads the position of the main emulator window; returns true if it differs from the one saved:
  private bool captureMain() {
    GUI::Position pos;
    pos = GUI::mainWindowPosition;
    int x = int(pos.x);
    int y = int(pos.y);
    if (mainHas && mainX == x && mainY == y) return false;

    mainHas = true;
    mainX = x;
    mainY = y;
    return true;
  }

  // poll saves the layout if the main emulator window was moved, which the script is not told about; called every
  // frame:
  void poll() {
    if (!loaded || applying) return;
    if (++pollFrames < 30) return;
    pollFrames = 0;

    if (captureMain()) settings.save();
  }

  // changed is called when a window was moved, resized or closed:
  void changed(ManagedWindow @m) {
    if (applying || !loaded) return;

    // a window moved relative to the main window is only meaningful with the main window's position saved with it:
    bool mainChanged = captureMain();
    if (!capture(m) && !mainChanged) return;

    settings.save();
  }

  // saveAll captures all the windows that are open and saves the layout; called when the script unloads:
  void saveAll() {
    if (!loaded) return;

    bool any = captureMain();
    for (uint i = 0; i < managed.length(); i++) {
      if (capture(managed[i])) any = true;
    }
    if (any) settings.save();
  }

}
