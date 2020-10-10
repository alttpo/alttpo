SettingsWindow @settings;

// NOTE: these functions must only be used to scale Size and never Position.
float sx(float x) {
  return x * GUI::dpiX;
}

float sy(float y) {
  return y * GUI::dpiY;
}

class SettingsWindow {
  private GUI::Window @window;
  private GUI::LineEdit @txtServerAddress;
  private GUI::LineEdit @txtGroup;
  private GUI::LineEdit @txtName;
  private GUI::LineEdit @txtTeam;
  private GUI::LineEdit @txtColor;
  private GUI::CheckLabel @chkTunic;
  private GUI::HorizontalSlider @slRed;
  private GUI::HorizontalSlider @slGreen;
  private GUI::HorizontalSlider @slBlue;
  private GUI::SNESCanvas @colorCanvas;
  private GUI::CheckLabel @chkShowLabels;
  private GUI::CheckLabel @chkShowMyLabel;
  private GUI::CheckLabel @chkEnablePvP;
  private GUI::CheckLabel @chkPvPFF;
  private GUI::CheckLabel @chkKeySync;
  private GUI::CheckLabel @chkRaceMode;
  private GUI::CheckLabel @chkBridge;
  private GUI::Label @lblBridgeMessage;
  private GUI::CheckLabel @chkDiscordEnable;
  private GUI::CheckLabel @chkDiscordPrivate;
  private GUI::ComboButton @ddlFont;
  private GUI::Button @btnConnect;
  private GUI::Button @btnDisconnect;

  bool started;

  private string serverAddress;
  string ServerAddress {
    get { return serverAddress; }
    set { serverAddress = value; }
  }

  private string groupPadded;
  string GroupPadded {
    get { return groupPadded; }
  }

  private string groupTrimmed;
  string GroupTrimmed {
    get { return groupTrimmed; }
    set {
      groupTrimmed = value;
      groupPadded = padTo(value, 20);
    }
  }

  private uint8 team;
  uint8 Team {
    get { return team; }
    set { team = value; }
  }

  private string name;
  string Name {
    get { return name; }
    set { name = value; }
  }

  uint16 player_color;
  uint16 PlayerColor {
    get { return player_color; }
    set { player_color = value; }
  }

  private bool syncTunic;
  bool SyncTunic { get { return syncTunic; } }

  private uint16 syncTunicLightColors;
  uint16 SyncTunicLightColors { get { return syncTunicLightColors; } }

  private uint16 syncTunicDarkColors;
  uint16 SyncTunicDarkColors { get { return syncTunicDarkColors; } }

  private bool showLabels;
  bool ShowLabels { get { return showLabels; } }

  private bool showMyLabel;
  bool ShowMyLabel { get { return showMyLabel; } }

  private ppu::Font@ font;
  ppu::Font@ Font {
    get { return font; }
  }
  private uint fontIndex;
  uint FontIndex {
    get { return fontIndex; }
    set {
      fontIndex = value;
      @font = ppu::fonts[value];
      font_set = false; // global
    }
  }

  private int bridgeState;
  bool Bridge {
    get { return bridgeState != 0; }
  }

  void bridgeStateUpdated(int state) {
    bridgeState = state;
    bool enabled = (state != 0);
    chkBridge.checked = enabled;
    raceMode = enabled;
    chkRaceMode.checked = enabled;
  }

  void bridgeMessageUpdated(const string &in msg) {
    lblBridgeMessage.text = msg;
  }
  
  private bool enablePvp;
  bool EnablePvP {
    get { return enablePvP; }
  }

  private bool raceMode;
  bool RaceMode {
    get { return raceMode; }
  }

  private bool discordEnable;
  bool DiscordEnable {
    get { return discordEnable; }
  }

  private bool discordPrivate;
  bool DiscordPrivate {
    get { return discordPrivate; }
  }

  private void setColorSliders() {
    // set the color sliders:
    slRed.position   = ( player_color        & 31);
    slGreen.position = ((player_color >>  5) & 31);
    slBlue.position  = ((player_color >> 10) & 31);
  }

  private void setColorText() {
    // set the color text display:
    txtColor.text = fmtHex(player_color, 4);
  }

  private void setServerSettingsGUI() {
    txtServerAddress.text = serverAddress;
    txtGroup.text = groupTrimmed;
  }

  private void setPlayerSettingsGUI() {
    txtName.text = name;
    txtTeam.text = fmtInt(team);
    chkTunic.checked = syncTunic;
    setColorSliders();
    setColorText();
  }

  private void setFeaturesGUI() {
    chkShowLabels.checked = showLabels;
    chkShowMyLabel.checked = showMyLabel;
    chkEnablePvP.checked = enablePvP;
    chkPvPFF.checked = enablePvPFriendlyFire;
    chkKeySync.checked = enableSmallKeySync;
    chkRaceMode.checked = raceMode;
    chkDiscordEnable.checked = discordEnable;
    chkDiscordPrivate.checked = discordPrivate;

    // set selected font option:
    ddlFont[fontIndex].setSelected();
  }

  private uint16 parse_player_color(string &in text) {
    uint64 value = text.hex();

    if (value > 0x7fff) value = 0x7fff;
    return uint16(value);
  }

  void load() {
    // try to load previous settings from disk:
    auto doc = UserSettings::load("alttpo.bml");
    auto version = doc["version"].naturalOr(0);
    serverAddress = doc["server/address"].textOr(ServerAddress);
    if (version == 0) {
      if (serverAddress == "bittwiddlers.org") serverAddress = "alttp.online";
    }
    groupTrimmed = doc["server/group"].textOr(GroupTrimmed);
    name = doc["player/name"].textOr(Name);
    team = doc["player/team"].naturalOr(Team);
    player_color = parse_player_color(doc["player/color"].textOr("0x" + fmtHex(player_color, 4)));
    syncTunic = doc["player/syncTunic"].booleanOr(true);
    syncTunicLightColors = doc["player/syncTunic/lightColors"].naturalOr(0x1400);
    syncTunicDarkColors = doc["player/syncTunic/darkColors"].naturalOr(0x0A00);
    if (version == 0) {
      if (syncTunicLightColors == 0x400) syncTunicLightColors = 0x1400;
      if (syncTunicLightColors == 0x200) syncTunicLightColors = 0x0A00;
    }

    showLabels = doc["feature/showLabels"].booleanOr(true);
    showMyLabel = doc["feature/showMyLabel"].booleanOr(false);
    FontIndex = doc["feature/fontIndex"].naturalOr(0);
    enablePvP = doc["feature/enablePvP"].booleanOr(true);
    enablePvPFriendlyFire = doc["feature/enablePvPFriendlyFire"].booleanOr(false);
    raceMode = doc["feature/raceMode"].booleanOr(false);
    enableSmallKeySync = doc["feature/enableSmallKeySync"].booleanOr(false);
    discordEnable = doc["feature/discordEnable"].booleanOr(false);
    discordPrivate = doc["feature/discordPrivate"].booleanOr(false);

    // set GUI controls from values:
    setServerSettingsGUI();
    setPlayerSettingsGUI();
    setFeaturesGUI();

    // apply player changes:
    playerSettingsChanged();
  }

  void save() {
    // grab latest values from GUI:
    ServerAddress = txtServerAddress.text;
    GroupTrimmed = txtGroup.text;
    Name = txtName.text;
    Team = uint8(txtTeam.text.natural());
    PlayerColor = parse_player_color(txtColor.text);

    syncTunic = chkTunic.checked;
    showLabels = chkShowLabels.checked;
    showMyLabel = chkShowMyLabel.checked;
    raceMode = chkRaceMode.checked;

    auto doc = BML::Node();
    doc.create("version").value = "1";
    doc.create("server/address").value = ServerAddress;
    doc.create("server/group").value = GroupTrimmed;
    doc.create("player/name").value = Name;
    doc.create("player/team").value = fmtInt(Team);
    doc.create("player/color").value = "0x" + fmtHex(player_color, 4);
    doc.create("player/syncTunic").value = fmtBool(syncTunic);
    doc.create("player/syncTunic/lightColors").value = "0b" + fmtBinary(syncTunicLightColors, 16);
    doc.create("player/syncTunic/darkColors").value = "0b" + fmtBinary(syncTunicDarkColors, 16);
    doc.create("feature/showLabels").value = fmtBool(showLabels);
    doc.create("feature/showMyLabel").value = fmtBool(showMyLabel);
    doc.create("feature/fontIndex").value = fmtInt(fontIndex);
    doc.create("feature/enablePvP").value = fmtBool(enablePvP);
    doc.create("feature/enablePvPFriendlyFire").value = fmtBool(enablePvPFriendlyFire);
    doc.create("feature/raceMode").value = fmtBool(raceMode);
    doc.create("feature/enableSmallKeySync").value = fmtBool(enableSmallKeySync);
    doc.create("feature/discordEnable").value = fmtBool(discordEnable);
    doc.create("feature/discordPrivate").value = fmtBool(discordPrivate);
    UserSettings::save("alttpo.bml", doc);
  }

  SettingsWindow() {
    @window = GUI::Window(140, 32, true);
    window.title = "Join a Game";
    window.size = GUI::Size(sx(320), sy(18*25));
    window.dismissable = false;

    auto sx150 = sx(150);
    auto sx100 = sx(100);
    auto sx40 = sx(40);
    auto sy20 = sy(20);
    auto sx5 = sx(5);
    auto sy5 = sy(5);
    auto sx64 = sx(64);
    auto sy64 = sy(64);

    auto vl = GUI::VerticalLayout();
    vl.setSpacing();
    vl.setPadding(sy5, sy5);
    window.append(vl);
    {
      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Address:";
        lbl.toolTip =
          "Server address (hostname or IP address) to connect to. If unsure, use the default `alttpo.online`.\n\n"
          "If running your own server, enter its hostname or IP address here. Note that alttpo.online is hosted in "
          "New Jersey, USA on a Linode VPS.";
        hz.append(lbl, GUI::Size(sx100, 0));

        @txtServerAddress = GUI::LineEdit();
        txtServerAddress.onChange(@GUI::Callback(save));
        hz.append(txtServerAddress, GUI::Size(-1, sy20));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Group:";
        lbl.toolTip =
          "Group name to join on the server, a.k.a. the lobby name (case-insensitive, max 20 chars).\n\n"
          "Private groups are not available yet so try to make your group name unique and hard to guess if you don't "
          "want other players joining. Also be sure to enable Hide Group Name if using Discord integration.\n\n"
          "Group name is updated in real time so if you change this while connected, you will move between groups.";
        hz.append(lbl, GUI::Size(sx100, 0));

        @txtGroup = GUI::LineEdit();
        txtGroup.onChange(@GUI::Callback(save));
        hz.append(txtGroup, GUI::Size(-1, sy20));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Player Name:";
        lbl.toolTip =
          "Your player's name which will show up on other players' screens if they have the `Show Player Labels` "
          "feature enabled (max 20 chars). Enable `Show My Label` to see your own player name on your own screen.\n\n"
          "Your player name is updated in real time so players will see changes as you make them in this text box.";
        hz.append(lbl, GUI::Size(sx100, 0));

        @txtName = GUI::LineEdit();
        txtName.onChange(@GUI::Callback(txtNameChanged));
        hz.append(txtName, GUI::Size(-1, sy20));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Team Number:";
        lbl.toolTip =
          "Your player's team number which will determine which items and state get synced to you. Only players in the "
          "same team get the same items and progress synced among themselves. Each team is independent of one another.";
        hz.append(lbl, GUI::Size(sx100, 0));

        @txtTeam = GUI::LineEdit();
        txtTeam.onChange(@GUI::Callback(txtTeamChanged));
        hz.append(txtTeam, GUI::Size(-1, sy20));
      }

      // player color:
      {
        {
          auto @hz = GUI::HorizontalLayout();
          vl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "Player Color:";
          lbl.toolTip =
            "Your player's primary color. Use the Red, Green, Blue sliders below to select your color. This color "
            "is used as your map marker color as seen on the map window. It can also be used to customize your avatar's "
            "tunic color if you enable that feature below.\n\n"
            "If you're a turbo nerd you can enter a 15-bit BGR hex color here. Note that it is NOT a 24-bit RGB hex "
            "colors.";
          hz.append(lbl, GUI::Size(sx100, sy20));

          @txtColor = GUI::LineEdit();
          txtColor.text = "7fff";
          txtColor.onChange(@GUI::Callback(colorTextChanged));
          hz.append(txtColor, GUI::Size(-1, sy20));
        }

        @chkTunic = GUI::CheckLabel();
        chkTunic.text = "Use player color as tunic color";
        chkTunic.toolTip =
          "If enabled, changes your avatar's tunic colors to use your primary player color and a secondary 75% "
          "brightness version of your primary color to shade the tunic with. Other players will see your customized "
          "tunic as well.\n\n"
          "For custom sprites, this feature may have unpredictable effects on the sprite's appearance.";
        chkTunic.checked = true;
        chkTunic.onToggle(@GUI::Callback(chkTunicChanged));
        vl.append(chkTunic, GUI::Size(-1, 0));

        auto @chl = GUI::HorizontalLayout();
        vl.append(chl, GUI::Size(-1, 0));

        auto @cvl = GUI::VerticalLayout();
        chl.append(cvl, GUI::Size(-1, -1));
        {
          auto @hz = GUI::HorizontalLayout();
          cvl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "Red";
          lbl.toolTip = "Adjust the red component of your player color (0..31)";
          hz.append(lbl, GUI::Size(sx40, sy20));

          @slRed = GUI::HorizontalSlider();
          slRed.toolTip = "Adjust the red component of your player color (0..31)";
          hz.append(slRed, GUI::Size(-1, 0));
          slRed.length = 31;
          slRed.position = 31;
          slRed.onChange(@GUI::Callback(colorSliderChanged));
        }
        {
          auto @hz = GUI::HorizontalLayout();
          cvl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "Green";
          lbl.toolTip = "Adjust the green component of your player color (0..31)";
          hz.append(lbl, GUI::Size(sx40, sy20));

          @slGreen = GUI::HorizontalSlider();
          slGreen.toolTip = "Adjust the green component of your player color (0..31)";
          hz.append(slGreen, GUI::Size(-1, 0));
          slGreen.length = 31;
          slGreen.position = 31;
          slGreen.onChange(@GUI::Callback(colorSliderChanged));
        }
        {
          auto @hz = GUI::HorizontalLayout();
          cvl.append(hz, GUI::Size(-1, 0));

          auto @lbl = GUI::Label();
          lbl.text = "Blue";
          lbl.toolTip = "Adjust the blue component of your player color (0..31)";
          hz.append(lbl, GUI::Size(sx40, sy20));

          @slBlue = GUI::HorizontalSlider();
          slBlue.toolTip = "Adjust the blue component of your player color (0..31)";
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
        chl.append(colorCanvas, GUI::Size(sx64, sy64));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        @chkShowLabels = GUI::CheckLabel();
        chkShowLabels.text = "Show Player Labels";
        chkShowLabels.toolTip =
          "Enable this to see other players' name labels rendered on screen beneath their avatars.";
        chkShowLabels.checked = true;
        chkShowLabels.onToggle(@GUI::Callback(chkShowLabelsChanged));
        hz.append(chkShowLabels, GUI::Size(sx150, 0));

        @chkShowMyLabel = GUI::CheckLabel();
        chkShowMyLabel.text = "Show My Label";
        chkShowMyLabel.toolTip =
          "Enable this to see your own player name label rendered on screen beneath your avatar.";
        chkShowMyLabel.checked = true;
        chkShowMyLabel.onToggle(@GUI::Callback(chkShowMyLabelChanged));
        hz.append(chkShowMyLabel, GUI::Size(sx150, 0));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        auto @lbl = GUI::Label();
        lbl.text = "Label Font:";
        lbl.toolTip =
          "Choose the on-screen font to render player labels with.";
        hz.append(lbl, GUI::Size(sx100, 0));

        @ddlFont = GUI::ComboButton();
        ddlFont.toolTip =
          "Choose the on-screen font to render player labels with.";
        hz.append(ddlFont, GUI::Size(0, 0));

        uint len = ppu::fonts_count;
        for (uint i = 0; i < len; i++) {
          auto di = GUI::ComboButtonItem();
          auto @f = ppu::fonts[i];
          di.text = f.displayName;
          ddlFont.append(di);
        }
        ddlFont[0].setSelected();

        ddlFont.onChange(@GUI::Callback(ddlFontChanged));
        ddlFont.enabled = true;
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        @chkEnablePvP = GUI::CheckLabel();
        chkEnablePvP.text = "Enable PvP";
        chkEnablePvP.toolTip =
          "Enable this to enable PvP. This will allow you to hit or even kill players in other teams.";
        chkEnablePvP.checked = ::enablePvP;
        chkEnablePvP.onToggle(@GUI::Callback(chkEnablePvPChanged));
        hz.append(chkEnablePvP, GUI::Size(sx150, 0));

        @chkPvPFF = GUI::CheckLabel();
        chkPvPFF.text = "PvP Friendly Fire";
        chkPvPFF.toolTip =
          "Enables friendly-fire mode for PvP.";
        chkPvPFF.checked = ::enablePvPFriendlyFire;
        chkPvPFF.onToggle(@GUI::Callback(chkPvPFFChanged));
        hz.append(chkPvPFF, GUI::Size(sx150, 0));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        @chkRaceMode = GUI::CheckLabel();
        chkRaceMode.text = "Disable sync";
        chkRaceMode.toolTip =
          "Enable this feature to disable synchronization with other players in the group. This can be used to have "
          "one or more players race one player who does not share the others' items, progress, or world state.\n\n"
          "Specifically, this feature disables item sync, progress sync, overworld sync, underworld sync, and "
          "real-time screen sync for both overworld and underworld areas.";
        chkRaceMode.checked = false;
        chkRaceMode.onToggle(@GUI::Callback(chkRaceModeChanged));
        hz.append(chkRaceMode, GUI::Size(sx150, 0));

        @chkKeySync = GUI::CheckLabel();
        chkKeySync.text = "Enable Small Key Sync";
        chkKeySync.toolTip =
          "EXPERIMENTAL! Enable this to sync small keys. This may cause small keys to be lost.";
        chkKeySync.checked = ::enableSmallKeySync;
        chkKeySync.onToggle(@GUI::Callback(chkKeySyncChanged));
        hz.append(chkKeySync, GUI::Size(sx150, 0));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        @chkBridge = GUI::CheckLabel();
        chkBridge.text = "QUsb2Snes Bridge";
        chkBridge.toolTip =
          "Enable this feature to connect to QUsb2Snes application to play multi-world games with ALttPO enabled for "
          "the visual aspect to see other players live in the same world.";
        chkBridge.checked = false;
        chkBridge.onToggle(@GUI::Callback(chkBridgeChanged));
        hz.append(chkBridge, GUI::Size(sx150, 0));

        @lblBridgeMessage = GUI::Label();
        lblBridgeMessage.text = "";
        lblBridgeMessage.toolTip =
          "Current status of QUsb2Snes connection";
        hz.append(lblBridgeMessage, GUI::Size(-1, 0));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, 0));

        @chkDiscordEnable = GUI::CheckLabel();
        chkDiscordEnable.text = "Discord Integration";
        if (discord::enabled) {
          chkDiscordEnable.toolTip =
          "Enable to integrate ALttPO with Discord so that others can see that you're playing ALttPO, which ROM version, "
          "and which randomizer seed if applicable. By default, your group name will be shown unless you disable that "
          "with `Hide Group Name`.";
        } else {
          chkDiscordEnable.toolTip =
          "Discord integration is not supported by this build of bsnes because is was either manually disabled during "
          "build or because your processor architecture is not supported by the official Discord Game SDK.";
        }
        chkDiscordEnable.enabled = discord::enabled;
        chkDiscordEnable.checked = false;
        chkDiscordEnable.onToggle(@GUI::Callback(chkDiscordEnableChanged));
        hz.append(chkDiscordEnable, GUI::Size(sx150, 0));

        @chkDiscordPrivate = GUI::CheckLabel();
        chkDiscordPrivate.text = "Hide Group Name";
        chkDiscordPrivate.toolTip =
          "Enable this to hide your group name from Discord if you're playing a private game.";
        chkDiscordPrivate.enabled = discord::enabled;
        chkDiscordPrivate.checked = false;
        chkDiscordPrivate.onToggle(@GUI::Callback(chkDiscordPrivateChanged));
        hz.append(chkDiscordPrivate, GUI::Size(sx150, 0));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @btnConnect = GUI::Button();
        btnConnect.text = "Connect";
        btnConnect.toolTip =
          "Click this button to connect to the server and join your group.\n\n"
          "Make sure everyone in your group is using the same ALTTP ROM version and/or randomizer seed, otherwise "
          "unpredictable effects may occur.\n\n"
          "Also, if resuming a game and cooperating with others, make sure to join with the proper save game file.";
        btnConnect.onActivate(@GUI::Callback(btnConnectClicked));
        hz.append(btnConnect, GUI::Size(-1, -1));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @btnDisconnect = GUI::Button();
        btnDisconnect.enabled = false;
        btnDisconnect.text = "Disconnect";
        btnDisconnect.toolTip =
          "Click this button to disconnect from the server and join another group.";
        btnDisconnect.onActivate(@GUI::Callback(btnDisconnectClicked));
        hz.append(btnDisconnect, GUI::Size(-1, -1));
      }
    }

    vl.resize();
    window.visible = true;
    window.setFocused();
  }

  // callback:
  private void chkBridgeChanged() {
    auto enabled = chkBridge.checked;
    if (enabled) {
      bridge.start();
    } else {
      bridge.stop();
      bridgeMessageUpdated("");
    }
  }

  // callback:
  private void chkDiscordPrivateChanged() {
    discordPrivateWasChanged();
  }

  private void discordPrivateWasChanged(bool persist = true) {
    discordPrivate = chkDiscordPrivate.checked;

    if (!persist) return;
    save();
  }

  // callback:
  private void chkDiscordEnableChanged() {
    discordEnableWasChanged();
  }

  private void discordEnableWasChanged(bool persist = true) {
    discordEnable = chkDiscordEnable.checked;

    if (!persist) return;
    save();
  }

  // callback:
  private void chkEnablePvPChanged() {
    enablePvPWasChanged();
  }
  
  private void enablePvPWasChanged(bool persist = true) {
    enablePvP = chkEnablePvP.checked;

    if (!persist) return;
    save();
  }

  // callback:
  private void chkPvPFFChanged() {
    enablePvPFFWasChanged();
  }

  private void enablePvPFFWasChanged(bool persist = true) {
    enablePvPFriendlyFire = chkPvPFF.checked;

    if (!persist) return;
    save();
  }

  // callback:
  private void chkKeySyncChanged() {
    keySyncWasChanged();
  }

  private void keySyncWasChanged(bool persist = true) {
    enableSmallKeySync = chkKeySync.checked;

    if (!persist) return;
    save();
  }

  private void chkRaceModeChanged() {
    raceModeWasChanged();
  }

  private void raceModeWasChanged(bool persist = true) {
    raceMode = chkRaceMode.checked;

    if (!persist) return;
    save();
  }

  // callback:
  private void ddlFontChanged() {
    FontIndex = ddlFont.selected.offset;

    fontWasChanged();
  }

  private void fontWasChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void txtNameChanged() {
    nameWasChanged();
  }

  void nameWasChanged(bool persist = true) {
    if (local !is null) {
      local.name = txtName.text.strip();
    }

    if (!persist) return;
    save();
  }

  // callback:
  private void txtTeamChanged() {
    teamWasChanged();
  }

  void teamWasChanged(bool persist = true) {
    if (local !is null) {
      local.team = uint8(txtTeam.text.natural());
    }

    if (!persist) return;
    save();
  }

  void playerSettingsChanged() {
    nameWasChanged(false);
    teamWasChanged(false);
    colorWasChanged(false);
  }

  // callback:
  private void chkTunicChanged() {
    syncTunic = chkTunic.checked;
    save();
  }

  // callback:
  private void chkShowMyLabelChanged() {
    showMyLabel = chkShowMyLabel.checked;
    save();
  }

  // callback:
  private void chkShowLabelsChanged() {
    showLabels = chkShowLabels.checked;
    save();
  }

  // callback:
  private void btnConnectClicked() {
    connect();
  }

  // callback:
  private void btnDisconnectClicked() {
    disconnect();
  }

  void connect() {
    save();

    started = true;
    players.resize(0);

    if (local !is null) {
      local.reset();
    }
    playerSettingsChanged();

    connected();
  }

  void disconnect() {
    @sock = null;
    started = false;
    players.resize(0);

    if (local !is null) {
      local.reset();
    }
    playerSettingsChanged();

    disconnected();
  }

  void connected() {
    btnConnect.enabled = false;
    btnDisconnect.enabled = true;
    
    playersWindow.update();
  }

  void disconnected() {
    btnConnect.enabled = true;
    btnDisconnect.enabled = false;
    
    playersWindow.update();
  }

  // callback:
  private void colorTextChanged() {
    player_color = parse_player_color(txtColor.text);

    setColorSliders();

    colorWasChanged();
  }

  // callback:
  private void colorSliderChanged() {
    player_color = (slRed.position & 31) |
      ((slGreen.position & 31) <<  5) |
      ((slBlue.position  & 31) << 10);

    setColorText();

    colorWasChanged();
  }

  void colorWasChanged(bool persist = true) {
    if (local !is null) {
      if (local.player_color == player_color) return;

      // assign to player:
      local.player_color = player_color;
    }

    colorCanvas.fill(player_color | 0x8000);
    colorCanvas.update();

    if (worldMapWindow !is null) {
      worldMapWindow.renderPlayers();
    }

    if (!persist) return;

    // persist settings to disk:
    save();
  }
}
