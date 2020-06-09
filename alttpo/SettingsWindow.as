SettingsWindow @settings;

class SettingsWindow {
  private GUI::Window @window;
  private GUI::LineEdit @txtServerAddress;
  private GUI::LineEdit @txtGroup;
  private GUI::LineEdit @txtName;
  private GUI::LineEdit @txtColor;
  private GUI::HorizontalSlider @slRed;
  private GUI::HorizontalSlider @slGreen;
  private GUI::HorizontalSlider @slBlue;
  private GUI::SNESCanvas @colorCanvas;
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
  uint16 player_color;
  uint16 PlayerColor {
    get { return player_color; }
  }

  SettingsWindow() {
    @window = GUI::Window(120, 32, true);
    window.title = "Join a Game";
    window.size = GUI::Size(280, 10*25);
    window.dismissable = false;

    auto vl = GUI::VerticalLayout();
    vl.setSpacing();
    vl.setPadding(5, 5);
    {
      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Address:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtServerAddress = GUI::LineEdit();
        hz.append(txtServerAddress, GUI::Size(-1, 20));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Group:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtGroup = GUI::LineEdit();
        hz.append(txtGroup, GUI::Size(-1, 20));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Player Name:";
        hz.append(lbl, GUI::Size(100, 0));

        @txtName = GUI::LineEdit();
        hz.append(txtName, GUI::Size(-1, 20));
      }

      // player color:
      {
        {
          auto @hz = GUI::HorizontalLayout();
          vl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "Player Color:";
          hz.append(lbl, GUI::Size(100, 20));

          @txtColor = GUI::LineEdit();
          txtColor.text = "7fff";
          txtColor.onChange(@GUI::Callback(colorTextChanged));
          hz.append(txtColor, GUI::Size(-1, 20));
        }

        auto @chl = GUI::HorizontalLayout();
        vl.append(chl, GUI::Size(-1, 0));

        auto @cvl = GUI::VerticalLayout();
        chl.append(cvl, GUI::Size(-1, -1));
        {
          auto @hz = GUI::HorizontalLayout();
          cvl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "R";
          hz.append(lbl, GUI::Size(20, 20));

          @slRed = GUI::HorizontalSlider();
          hz.append(slRed, GUI::Size(-1, 0));
          slRed.length = 31;
          slRed.position = 31;
          slRed.onChange(@GUI::Callback(colorSliderChanged));
        }
        {
          auto @hz = GUI::HorizontalLayout();
          cvl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "G";
          hz.append(lbl, GUI::Size(20, 20));

          @slGreen = GUI::HorizontalSlider();
          hz.append(slGreen, GUI::Size(-1, 0));
          slGreen.length = 31;
          slGreen.position = 31;
          slGreen.onChange(@GUI::Callback(colorSliderChanged));
        }
        {
          auto @hz = GUI::HorizontalLayout();
          cvl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "B";
          hz.append(lbl, GUI::Size(20, 20));

          @slBlue = GUI::HorizontalSlider();
          hz.append(slBlue, GUI::Size(-1, 0));
          slBlue.length = 31;
          slBlue.position = 31;
          slBlue.onChange(@GUI::Callback(colorSliderChanged));
        }

        @colorCanvas = GUI::SNESCanvas();
        colorCanvas.size = GUI::Size(64, 64);
        colorCanvas.setAlignment(0.5, 0.5);
        colorCanvas.fill(0x7FFF | 0x8000);
        colorCanvas.update();
        chl.append(colorCanvas, GUI::Size(64, 64));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @ok = GUI::Button();
        ok.text = "Connect";
        ok.onActivate(@GUI::Callback(this.startClicked));
        hz.append(ok, GUI::Size(-1, -1));
      }
    }
    window.append(vl);

    vl.resize();
    window.visible = true;
    window.setFocused();
    colorSliderChanged();
  }

  private void startClicked() {
    start();
    hide();
  }

  private void colorTextChanged() {
    player_color = txtColor.text.hex();

    // reset the sliders:
    slRed.position   = ( player_color        & 31);
    slGreen.position = ((player_color >>  5) & 31);
    slBlue.position  = ((player_color >> 10) & 31);

    colorWasChanged();
  }

  private void colorSliderChanged() {
    player_color = (slRed.position & 31) |
      ((slGreen.position & 31) <<  5) |
      ((slBlue.position  & 31) << 10);

    // reset the text display:
    txtColor.text = fmtHex(player_color, 4);

    colorWasChanged();
  }

  private void colorWasChanged() {
    if (local.player_color == player_color) return;

    // assign to player:
    local.player_color = player_color;

    colorCanvas.fill(player_color | 0x8000);
    colorCanvas.update();

    if (@worldMapWindow != null) {
      worldMapWindow.renderPlayers();
    }
  }

  void start() {
    serverAddress = txtServerAddress.text;
    assignGroup(txtGroup.text);
    name = txtName.text;
    started = true;
  }

  void show() {
    ok.enabled = true;
  }

  void hide() {
    ok.enabled = false;
  }
};
