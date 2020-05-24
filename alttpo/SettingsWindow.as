SettingsWindow @settings;

class SettingsWindow {
  private GUI::Window @window;
  private GUI::LineEdit @txtServerAddress;
  private GUI::LineEdit @txtGroup;
  private GUI::LineEdit @txtName;
  private GUI::Button @ok;

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
    @window = GUI::Window(164, 22, true);
    window.title = "Join a Game";
    window.size = GUI::Size(256, 24*5);

    auto vl = GUI::VerticalLayout();
    {
      auto @hz = GUI::HorizontalLayout();
      {
        auto @lbl = GUI::Label();
        lbl.text = "Address:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtServerAddress = GUI::LineEdit();
        hz.append(txtServerAddress, GUI::Size(140, 20));
      }
      vl.append(hz, GUI::Size(0, 0));

      @hz = GUI::HorizontalLayout();
      {
        auto @lbl = GUI::Label();
        lbl.text = "Group:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtGroup = GUI::LineEdit();
        hz.append(txtGroup, GUI::Size(140, 20));
      }
      vl.append(hz, GUI::Size(0, 0));

      @hz = GUI::HorizontalLayout();
      {
        auto @lbl = GUI::Label();
        lbl.text = "Player Name:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtName = GUI::LineEdit();
        hz.append(txtName, GUI::Size(140, 20));
      }
      vl.append(hz, GUI::Size(0, 0));

      @hz = GUI::HorizontalLayout();
      {
        @ok = GUI::Button();
        ok.text = "Connect";
        @ok.on_activate = @GUI::Callback(this.startClicked);
        hz.append(ok, GUI::Size(-1, -1));
      }
      vl.append(hz, GUI::Size(-1, -1));
    }
    window.append(vl);

    vl.resize();
    window.visible = true;
  }

  private void startClicked() {
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
