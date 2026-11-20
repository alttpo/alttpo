DebugWindow @debugWindow;

// DebugWindow has the buttons that open the windows used to debug the script.
class DebugWindow {
  private GUI::Window @window;

  DebugWindow() {
    @window = GUI::Window(140, 400, true);
    window.title = "Debug";
    window.size = GUI::Size(sx(220), sy(4*30 + 20));

    auto sy5 = sy(5);
    auto vl = GUI::VerticalLayout();
    vl.setSpacing();
    vl.setPadding(sy5, sy5);
    window.append(vl);

    addButton(vl, "Memory", "Open the memory window to look at and write the game's memory.", @GUI::Callback(btnMemoryClicked));
    addButton(vl, "Sprite VRAM", "Open the window showing the sprite graphics in VRAM.", @GUI::Callback(btnVramClicked));
    addButton(vl, "OAM", "Open the window showing the OAM entries of the frame.", @GUI::Callback(btnOamClicked));
    addButton(vl, "Enemies", "Open the window showing the enemies in the room or area.", @GUI::Callback(btnEnemiesClicked));

    vl.resize();
    windowLayout.attach("debug", window);
    window.visible = true;
  }

  private void addButton(GUI::VerticalLayout @vl, const string &in text, const string &in tip, GUI::Callback @cb) {
    auto @hz = GUI::HorizontalLayout();
    vl.append(hz, GUI::Size(-1, -1));

    auto @btn = GUI::Button();
    btn.text = text;
    btn.toolTip = tip;
    btn.onActivate(cb);
    hz.append(btn, GUI::Size(-1, -1));
  }

  bool isOpen() {
    return window.visible;
  }

  void show() {
    window.visible = true;
    window.setFocused();
  }

  // callback:
  private void btnMemoryClicked() {
    openMemoryWindow();
  }

  // callback:
  private void btnVramClicked() {
    openSpritesWindow();
  }

  // callback:
  private void btnOamClicked() {
    openOamWindow();
  }

  // callback:
  private void btnEnemiesClicked() {
    openEnemyWindow();
  }
}
