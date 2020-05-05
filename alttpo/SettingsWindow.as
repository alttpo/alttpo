
class SettingsWindow {
  private gui::Window @window;
  private gui::LineEdit @txtServerAddress;
  private gui::LineEdit @txtGroup;
  private gui::LineEdit @txtName;
  private gui::Button @ok;

  private string serverAddress;
  string ServerAddress {
    get { return serverAddress; }
    set {
      serverAddress = value;
      txtServerAddress.text = value;
    }
  }

  private string group;
  string Group {
    get { return group; }
    set {
      txtGroup.text = value;
      assignGroup(value);
    }
  }

  private void assignGroup(string value) {
    // pad out to exactly 20 bytes:
    auto newValue = value.slice(0, 20);
    for (int i = newValue.length(); i < 20; i++) {
      newValue += " ";
    }
    group = newValue;
  }

  private string name;
  string Name {
    get { return name; }
    set {
      name = value;
      txtName.text = value;
    }
  }

  bool started;

  SettingsWindow() {
    @window = gui::Window(164, 22, true);
    window.title = "Join a Game";
    window.size = gui::Size(256, 24*5);

    auto vl = gui::VerticalLayout();
    {
      auto @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Address:";
        hz.append(lbl, gui::Size(100, 0));

        @txtServerAddress = gui::LineEdit();
        hz.append(txtServerAddress, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Group:";
        hz.append(lbl, gui::Size(100, 0));

        @txtGroup = gui::LineEdit();
        hz.append(txtGroup, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        auto @lbl = gui::Label();
        lbl.text = "Player Name:";
        hz.append(lbl, gui::Size(100, 0));

        @txtName = gui::LineEdit();
        hz.append(txtName, gui::Size(140, 20));
      }
      vl.append(hz, gui::Size(0, 0));

      @hz = gui::HorizontalLayout();
      {
        @ok = gui::Button();
        ok.text = "Connect";
        @ok.on_activate = @gui::ButtonCallback(this.startClicked);
        hz.append(ok, gui::Size(-1, -1));
      }
      vl.append(hz, gui::Size(-1, -1));
    }
    window.append(vl);

    vl.resize();
    window.visible = true;
  }

  private void startClicked(gui::Button @self) {
    start();
    hide();
  }

  void start() {
    serverAddress = txtServerAddress.text;
    assignGroup(txtGroup.text);
    name = txtName.text;
    started = true;
  }

  void show() {
    window.visible = true;
  }

  void hide() {
    window.visible = false;
  }
};
