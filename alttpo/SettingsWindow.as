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
  private GUI::Window @advancedWindow;
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
  private GUI::CheckLabel @chkSyncSmEnemies;
  private GUI::CheckLabel @chkSyncLttpEnemies;

  private GUI::CheckLabel @chkSyncSprites;
  private GUI::CheckLabel @chkSyncUnderworld;
  private GUI::CheckLabel @chkSyncOverworld;
  private GUI::CheckLabel @chkSyncItems;
  private GUI::CheckLabel @chkSyncPendants;
  private GUI::CheckLabel @chkSyncSmallKeys;
  private GUI::CheckLabel @chkSyncUnderworldLocal;
  private GUI::CheckLabel @chkSyncOverworldLocal;
  private GUI::CheckLabel @chkSyncTorches;
  private GUI::CheckLabel @chkSyncSfx;
  private GUI::CheckLabel @chkSyncEnemiesKilled;
  private GUI::CheckLabel @chkKillDeadEnemies;
  private GUI::CheckLabel @chkSyncChests;
  private GUI::CheckLabel @chkSyncHearts;
  private GUI::CheckLabel @chkSyncDungeonItems;
  private GUI::CheckLabel @chkSyncCrystals;
  private GUI::CheckLabel @chkSyncProgress;

  private GUI::CheckLabel @chkBridge;
  private GUI::Label @lblBridgeMessage;
  private GUI::CheckLabel @chkConnectorLib;
  private GUI::Label @lblConnectorLibMessage;
  private GUI::CheckLabel @chkDiscordEnable;
  private GUI::CheckLabel @chkDiscordPrivate;
  private GUI::ComboButton @ddlFont;
  private GUI::ComboButton @preset;
  private GUI::Button @btnConnect;
  private GUI::Button @btnDisconnect;
  private GUI::Button @btnAdvanced;
  private GUI::Button @btnOpenMap;
  private GUI::Button @btnOpenPlayers;
  private GUI::Button @btnOpenDebug;
  private GUI::CheckLabel @chkOpenMap;
  private GUI::CheckLabel @chkOpenPlayers;
  private GUI::CheckLabel @chkOpenDebug;
  private GUI::CheckLabel @chkOpenMemory;
  private GUI::CheckLabel @chkOpenVram;
  private GUI::CheckLabel @chkOpenOam;
  private GUI::CheckLabel @chkOpenEnemies;
  private GUI::Label @lblRunTimer;
  private GUI::Label @lblRunWarning;
  private GUI::Label @lblRunMine;
  private GUI::Button @btnResetRun;
  private uint64 runTimerUpdated = 0;
  private GUI::Button @btnPresetDefault;
  private GUI::Button @btnPresetMultiworld;

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

    // only enable race mode when enabling qusb2snes, don't disable it if disconnected:
    // TODO: disable all sync instead?
    //if (enabled) {
    //  raceMode = enabled;
    //  chkRaceMode.checked = enabled;
    //}
  }

  void bridgeMessageUpdated(const string &in msg) {
    lblBridgeMessage.text = msg;
  }

  private int connectorLibState;
  bool ConnectorLibConnected {
    get { return connectorLibState != 0; }
  }

  void connectorLibStateUpdated(int state) {
    connectorLibState = state;
    bool enabled = (state != 0);
    chkConnectorLib.checked = enabled;
  }

  void connectorLibMessageUpdated(const string &in msg) {
    lblConnectorLibMessage.text = msg;
  }

  private bool enablePvP = false;
  bool EnablePvP {
    get { return enablePvP; }
  }

  private bool enablePvPFriendlyFire = false;
  bool EnablePvPFriendlyFire {
    get { return enablePvPFriendlyFire; }
  }

  private bool syncSprites;
  bool SyncSprites { get { return syncSprites; } }
  private bool syncUnderworld;
  bool SyncUnderworld { get { return syncUnderworld; } }
  private bool syncOverworld;
  bool SyncOverworld { get { return syncOverworld; } }
  private bool syncItems;
  bool SyncItems { get { return syncItems; } }
  private bool syncPendants;
  bool SyncPendants { get { return syncPendants; } }
  private bool syncSmallKeys;
  bool SyncSmallKeys { get { return syncSmallKeys; } }
  // syncUnderworldLocal ("Underworld (Local)") shares what players in the same room do while they are there, like
  // o2: manipulable objects (pots, blocks, pegs, big rocks) and the items under pots, crystal switches, star tiles,
  // room state (trap doors, chests, keys, key doors, switches) and flying floor tiles:
  private bool syncUnderworldLocal;
  bool SyncUnderworldLocal { get { return syncUnderworldLocal; } }
  // syncOverworldLocal ("Overworld (Local)") shares what players in the same area do while they are there, like o2:
  // map16 changes (lifted bushes and rocks, bombed walls, ...) and the area's events (entrance animations, the desert
  // statues, the lumberjacks' tree):
  private bool syncOverworldLocal;
  bool SyncOverworldLocal { get { return syncOverworldLocal; } }
  // SyncLocal tells whether the local sync toggle of the world the local player is in is on, for what is shared in
  // both worlds (ancillae):
  bool SyncLocal {
    get {
      if (local !is null && local.is_in_dungeon_module()) return syncUnderworldLocal;
      return syncOverworldLocal;
    }
  }
  private bool syncTorches;
  bool SyncTorches { get { return syncTorches; } }
  private bool syncSfx;
  bool SyncSfx { get { return syncSfx; } }
  // syncEnemiesKilled ("Enemy Dead List") shares which enemies players in the same room or area killed, like
  // o2; see EnemiesKilled.as:
  private bool syncEnemiesKilled;
  bool SyncEnemiesKilled { get { return syncEnemiesKilled; } }
  // killDeadEnemies ("Kill Dead Enemies") kills the live enemies the dead list says are dead; needs syncEnemiesKilled:
  private bool killDeadEnemies;
  bool KillDeadEnemies { get { return killDeadEnemies; } }
  private bool syncChests;
  bool SyncChests { get { return syncChests; } }
  private bool syncHearts;
  bool SyncHearts { get { return syncHearts; } }
  private bool syncDungeonItems;
  bool SyncDungeonItems { get { return syncDungeonItems; } }
  private bool syncCrystals;
  bool SyncCrystals { get { return syncCrystals; } }
  private bool syncProgress;
  bool SyncProgress { get { return syncProgress; } }
  private bool syncsmenemies;
  bool SyncSmEnemies { get { return syncsmenemies; } }
  private bool synclttpenemies;
  bool SyncLttpEnemies { get { return synclttpenemies; } }

  // which windows open when the script starts, see openDefaultWindows():
  private bool openMap = true;
  private bool openPlayers = true;
  private bool openDebug = false;
  private bool openMemory = false;
  private bool openVram = false;
  private bool openOam = false;
  private bool openEnemies = false;
  bool OpenMap { get { return openMap; } }
  bool OpenPlayers { get { return openPlayers; } }
  bool OpenDebug { get { return openDebug; } }
  bool OpenMemory { get { return openMemory; } }
  bool OpenVram { get { return openVram; } }
  bool OpenOam { get { return openOam; } }
  bool OpenEnemies { get { return openEnemies; } }

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
    chkDiscordEnable.checked = discordEnable;
    chkDiscordPrivate.checked = discordPrivate;

    chkSyncSprites.checked = syncSprites;
    chkSyncUnderworld.checked = syncUnderworld;
    chkSyncOverworld.checked = syncOverworld;
    chkSyncItems.checked = syncItems;
    chkSyncPendants.checked = syncPendants;
    chkSyncSmallKeys.checked = syncSmallKeys;
    chkSyncUnderworldLocal.checked = syncUnderworldLocal;
    chkSyncOverworldLocal.checked = syncOverworldLocal;
    chkSyncTorches.checked = syncTorches;
    chkSyncSfx.checked = syncSfx;
    chkSyncEnemiesKilled.checked = syncEnemiesKilled;
    chkKillDeadEnemies.checked = killDeadEnemies;
    chkSyncChests.checked = syncChests;
    chkSyncHearts.checked = syncHearts;
    chkSyncDungeonItems.checked = syncDungeonItems;
    chkSyncCrystals.checked = syncCrystals;
    chkSyncProgress.checked = syncProgress;
    chkSyncSmEnemies.checked = syncsmenemies;
    chkSyncLttpEnemies.checked = synclttpenemies;

    chkOpenMap.checked = openMap;
    chkOpenPlayers.checked = openPlayers;
    chkOpenDebug.checked = openDebug;
    chkOpenMemory.checked = openMemory;
    chkOpenVram.checked = openVram;
    chkOpenOam.checked = openOam;
    chkOpenEnemies.checked = openEnemies;

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

    syncSprites = doc["feature/syncSprites"].booleanOr(true);
    syncUnderworld = doc["feature/syncUnderworld"].booleanOr(true);
    syncOverworld = doc["feature/syncOverworld"].booleanOr(true);
    syncItems = doc["feature/syncItems"].booleanOr(true);
    syncPendants = doc["feature/syncPendants"].booleanOr(true);
    syncSmallKeys = doc["feature/syncSmallKeys"].booleanOr(true);
    // the local toggles replace the former Tilemap toggle; start from its value:
    bool syncTilemap = doc["feature/syncTilemap"].booleanOr(true);
    syncUnderworldLocal = doc["feature/syncUnderworldLocal"].booleanOr(syncTilemap);
    syncOverworldLocal = doc["feature/syncOverworldLocal"].booleanOr(syncTilemap);
    syncTorches = doc["feature/syncTorches"].booleanOr(true);
    syncSfx = doc["feature/syncSfx"].booleanOr(true);
    syncEnemiesKilled = doc["feature/syncEnemiesKilled"].booleanOr(true);
    killDeadEnemies = doc["feature/killDeadEnemies"].booleanOr(true);
    syncChests = doc["feature/syncChests"].booleanOr(true);
    syncHearts = doc["feature/syncHearts"].booleanOr(true);
    syncDungeonItems = doc["feature/syncDungeonItems"].booleanOr(true);
    syncCrystals = doc["feature/syncCrystals"].booleanOr(true);
    syncProgress = doc["feature/syncProgress"].booleanOr(true);
    syncsmenemies = doc["feature/syncsmenemies"].booleanOr(true);
    synclttpenemies = doc["feature/synclttpenemies"].booleanOr(true);

    discordEnable = doc["feature/discordEnable"].booleanOr(false);
    discordPrivate = doc["feature/discordPrivate"].booleanOr(false);

    openMap = doc["windows/openMap"].booleanOr(true);
    openPlayers = doc["windows/openPlayers"].booleanOr(true);
    openDebug = doc["windows/openDebug"].booleanOr(false);
    openMemory = doc["windows/openMemory"].booleanOr(false);
    openVram = doc["windows/openVram"].booleanOr(false);
    openOam = doc["windows/openOam"].booleanOr(false);
    openEnemies = doc["windows/openEnemies"].booleanOr(false);

    // restore the size and position of the windows:
    windowLayout.load(doc);

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

    auto doc = BML::Node();
    doc.create("version").value = "2";
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

    doc.create("feature/syncSprites").value = fmtBool(syncSprites);
    doc.create("feature/syncUnderworld").value = fmtBool(syncUnderworld);
    doc.create("feature/syncOverworld").value = fmtBool(syncOverworld);
    doc.create("feature/syncItems").value = fmtBool(syncItems);
    doc.create("feature/syncPendants").value = fmtBool(syncPendants);
    doc.create("feature/syncSmallKeys").value = fmtBool(syncSmallKeys);
    doc.create("feature/syncUnderworldLocal").value = fmtBool(syncUnderworldLocal);
    doc.create("feature/syncOverworldLocal").value = fmtBool(syncOverworldLocal);
    doc.create("feature/syncTorches").value = fmtBool(syncTorches);
    doc.create("feature/syncSfx").value = fmtBool(syncSfx);
    doc.create("feature/syncEnemiesKilled").value = fmtBool(syncEnemiesKilled);
    doc.create("feature/killDeadEnemies").value = fmtBool(killDeadEnemies);
    doc.create("feature/syncChests").value = fmtBool(syncChests);
    doc.create("feature/syncHearts").value = fmtBool(syncHearts);
    doc.create("feature/syncDungeonItems").value = fmtBool(syncDungeonItems);
    doc.create("feature/syncCrystals").value = fmtBool(syncCrystals);
    doc.create("feature/syncProgress").value = fmtBool(syncProgress);
    doc.create("feature/syncsmenemies").value = fmtBool(syncsmenemies);
    doc.create("feature/synclttpenemies").value = fmtBool(synclttpenemies);

    doc.create("feature/discordEnable").value = fmtBool(discordEnable);
    doc.create("feature/discordPrivate").value = fmtBool(discordPrivate);

    doc.create("windows/openMap").value = fmtBool(openMap);
    doc.create("windows/openPlayers").value = fmtBool(openPlayers);
    doc.create("windows/openDebug").value = fmtBool(openDebug);
    doc.create("windows/openMemory").value = fmtBool(openMemory);
    doc.create("windows/openVram").value = fmtBool(openVram);
    doc.create("windows/openOam").value = fmtBool(openOam);
    doc.create("windows/openEnemies").value = fmtBool(openEnemies);
    windowLayout.save(doc);

    UserSettings::save("alttpo.bml", doc);
  }

  SettingsWindow() {
    @window = GUI::Window(140, 32, true);
    window.title = "Join a Game";
    window.size = GUI::Size(sx(320), sy(13*25 + 20));
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

      // player color:
      {
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
      
      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @btnAdvanced = GUI::Button();
        btnAdvanced.enabled = true;
        btnAdvanced.text = "Advanced Settings";
        btnDisconnect.toolTip =
          "Click this button to open the advanced settings window.";
        btnAdvanced.onActivate(@GUI::Callback(btnAdvancedClicked));
        hz.append(btnAdvanced, GUI::Size(-1, -1));
      }

      {
        // open the windows that were closed:
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @btnOpenMap = GUI::Button();
        btnOpenMap.text = "World Map";
        btnOpenMap.toolTip = "Click this button to open the world map window showing where the players are.";
        btnOpenMap.onActivate(@GUI::Callback(btnOpenMapClicked));
        hz.append(btnOpenMap, GUI::Size(-1, -1));

        @btnOpenPlayers = GUI::Button();
        btnOpenPlayers.text = "Players";
        btnOpenPlayers.toolTip = "Click this button to open the window listing the players online in your group.";
        btnOpenPlayers.onActivate(@GUI::Callback(btnOpenPlayersClicked));
        hz.append(btnOpenPlayers, GUI::Size(-1, -1));
      }

      {
        // the run timer, shared with o2 (see RunTiming.as):
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @lblRunTimer = GUI::Label();
        lblRunTimer.text = "Run:";
        lblRunTimer.toolTip = "First player start to last player finish, on the server's clock";
        hz.append(lblRunTimer, GUI::Size(-1, 0));

        @btnResetRun = GUI::Button();
        btnResetRun.text = "Reset run";
        btnResetRun.toolTip =
          "Forget all synced state and reset the run timer for all players in the group, o2 players included; "
          "does not reset the console/emulator; asks first";
        btnResetRun.onActivate(@GUI::Callback(btnResetRunClicked));
        hz.append(btnResetRun, GUI::Size(0, 0));
      }

      {
        // the local player's own time, on its own line so that the run timer's line keeps room for "Reset run":
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @lblRunMine = GUI::Label();
        lblRunMine.toolTip = "Your own time: your start to your finish, and your lag frames";
        hz.append(lblRunMine, GUI::Size(-1, 0));
      }

      {
        auto @hz = GUI::HorizontalLayout();
        vl.append(hz, GUI::Size(-1, -1));

        @lblRunWarning = GUI::Label();
        lblRunWarning.foregroundColor = GUI::Color(255, 160, 0);
        hz.append(lblRunWarning, GUI::Size(-1, 0));
      }
    }

    vl.resize();
    build_advanced();
    windowLayout.attach("settings", window);
    windowLayout.attach("advanced", advancedWindow);
    window.visible = true;
    window.setFocused();
  }

  void doActivate() {
    window.doActivate();
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
  private void chkConnectorLibChanged() {
    auto enabled = chkConnectorLib.checked;
    if (enabled) {
      ConnectorLib::connector.start();
    } else {
      ConnectorLib::connector.stop();
      connectorLibMessageUpdated("");
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
    enablePvP = chkEnablePvP.checked;
    enablePvPWasChanged();
  }

  private void enablePvPWasChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkPvPFFChanged() {
    enablePvPFriendlyFire = chkPvPFF.checked;
    enablePvPFFWasChanged();
  }

  private void enablePvPFFWasChanged(bool persist = true) {
    if (!persist) return;
    save();
  }


  // callback:
  private void chkSyncSpritesChanged() {
    syncSprites = chkSyncSprites.checked;
    syncSpritesChanged();
  }

  private void syncSpritesChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncUnderworldChanged() {
    syncUnderworld = chkSyncUnderworld.checked;
    syncUnderworldChanged();
  }

  private void syncUnderworldChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncOverworldChanged() {
    syncOverworld = chkSyncOverworld.checked;
    syncOverworldChanged();
  }

  private void syncOverworldChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncItemsChanged() {
    syncItems = chkSyncItems.checked;
    syncItemsChanged();
  }

  private void syncItemsChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncPendantsChanged() {
    syncPendants = chkSyncPendants.checked;
    syncPendantsChanged();
  }

  private void syncPendantsChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncSmallKeysChanged() {
    syncSmallKeys = chkSyncSmallKeys.checked;
    syncSmallKeysChanged();
  }

  private void syncSmallKeysChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncUnderworldLocalChanged() {
    syncUnderworldLocal = chkSyncUnderworldLocal.checked;
    save();
  }

  // callback:
  private void chkSyncOverworldLocalChanged() {
    syncOverworldLocal = chkSyncOverworldLocal.checked;
    save();
  }

  // callback:
  private void chkSyncTorchesChanged() {
    syncTorches = chkSyncTorches.checked;
    save();
  }

  // callback:
  private void chkSyncSfxChanged() {
    syncSfx = chkSyncSfx.checked;
    save();
  }

  // callback:
  private void chkSyncEnemiesKilledChanged() {
    syncEnemiesKilled = chkSyncEnemiesKilled.checked;
    save();
  }

  // callback:
  private void chkKillDeadEnemiesChanged() {
    killDeadEnemies = chkKillDeadEnemies.checked;
    save();
  }

  // callback:
  private void chkSyncChestsChanged() {
    syncChests = chkSyncChests.checked;
    syncChestsChanged();
  }

  private void syncChestsChanged(bool persist = true) {
    if (local !is null) {
      local.set_room_masks(syncChests);
    }
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncHeartsChanged() {
    syncHearts = chkSyncHearts.checked;
    syncHeartsChanged();
  }

  private void syncHeartsChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncDungeonItemsChanged() {
    syncDungeonItems = chkSyncDungeonItems.checked;
    syncDungeonItemsChanged();
  }

  private void syncDungeonItemsChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncCrystalsChanged() {
    syncCrystals = chkSyncCrystals.checked;
    syncCrystalsChanged();
  }

  private void syncCrystalsChanged(bool persist = true) {
    if (!persist) return;
    save();
  }

  // callback:
  private void chkSyncProgressChanged() {
    syncProgressChanged();
  }

  private void syncProgressChanged(bool persist = true) {
    syncProgress = chkSyncProgress.checked;

    if (!persist) return;
    save();
  }
  
  // callback:
  private void chkSyncSmEnemiesChanged() {
    syncSmEnemiesChanged();
  }

  private void syncSmEnemiesChanged(bool persist = true) {
    syncsmenemies = chkSyncSmEnemies.checked;
    if (local !is null) local.timeInRoom = 0;
    if (!persist) return;
    save();
  }


  // callback:
  private void chkSyncLttpEnemiesChanged() {
    syncLttpEnemiesChanged();
  }

  private void syncLttpEnemiesChanged(bool persist = true) {
    synclttpenemies = chkSyncLttpEnemies.checked;
    if (local !is null) local.timeInRoom = 0;
    if (!persist) return;
    save();
  }


  // callback:
  private void ddlFontChanged() {
    FontIndex = ddlFont.selected.offset;

    fontWasChanged();
  }
  
  private void btnPresetDefaultClicked() {
    disconnect();
    txtServerAddress.text = "alttp.online";
    txtTeam.text = "0";
    ddlFont[0].setSelected();

    syncSprites = true;
    syncUnderworld = true;
    syncOverworld = true;
    syncItems = true;
    syncPendants = true;
    syncSmallKeys = false;
    syncUnderworldLocal = true;
    syncOverworldLocal = true;
    syncTorches = true;
    syncSfx = true;
    syncEnemiesKilled = true;
    killDeadEnemies = true;
    syncChests = true;
    syncHearts = true;
    syncDungeonItems = true;
    syncCrystals = true;
    syncProgress = true;

    enablePvP = false;
    chkEnablePvP.checked = enablePvP;
    enablePvPFriendlyFire = false;
    chkPvPFF.checked = enablePvPFriendlyFire;
    chkDiscordEnable.checked = false;
    chkDiscordPrivate.checked = false;
    chkBridge.checked = false;
    chkConnectorLib.checked = false;
    chkShowLabels.checked = true;
    chkShowMyLabel.checked = true;

    setFeaturesGUI();
    syncChestsChanged();
  }
  
  private void btnPresetMultiworldClicked() {
    disconnect();

    syncSprites = true;
    syncUnderworld = false;
    syncOverworld = false;
    syncItems = false;
    syncPendants = false;
    syncSmallKeys = false;
    syncUnderworldLocal = false;
    syncOverworldLocal = false;
    syncTorches = false;
    syncSfx = true;
    syncEnemiesKilled = false;
    killDeadEnemies = false;
    syncChests = true;
    syncHearts = false;
    syncDungeonItems = false;
    syncCrystals = false;
    syncProgress = false;

    enablePvP = false;
    chkEnablePvP.checked = enablePvP;
    enablePvPFriendlyFire = false;
    chkPvPFF.checked = enablePvPFriendlyFire;
    if(!chkBridge.checked) {chkBridge.checked = true; chkBridgeChanged();}
    chkConnectorLib.checked = false;

    setFeaturesGUI();
    syncChestsChanged();
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

  private void btnResetRunClicked() {
    confirm_reset_run();
  }

  // updateRunTimer refreshes the run timer and the warning a few times a second.
  void updateRunTimer() {
    if (lblRunTimer is null) return;
    uint64 now = chrono::monotonic::millisecond;
    if (now - runTimerUpdated < 100) return;
    runTimerUpdated = now;
    string t = run_time_text();
    string mine = player_time_text(local);
    lblRunTimer.text = "Run: " + t;
    lblRunMine.text = mine != "" ? "you: " + mine : "";
    lblRunWarning.text = run_cost_warning();
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

    if (playersWindow !is null) {
      playersWindow.update();
    }
  }

  void disconnected() {
    btnConnect.enabled = true;
    btnDisconnect.enabled = false;

    if (playersWindow !is null) {
      playersWindow.update();
    }
  }
  
  //callback
  private void btnAdvancedClicked(){
    advancedWindow.visible = true;
    advancedWindow.setFocused();
  }

  // callback:
  private void btnOpenMapClicked() {
    openMapWindow();
  }

  // callback:
  private void btnOpenPlayersClicked() {
    openPlayersWindow();
  }

  // callback:
  private void btnOpenDebugClicked() {
    openDebugWindow();
  }

  // callback:
  private void chkOpenMapChanged() {
    openMap = chkOpenMap.checked;
    save();
  }

  // callback:
  private void chkOpenPlayersChanged() {
    openPlayers = chkOpenPlayers.checked;
    save();
  }

  // callback:
  private void chkOpenDebugChanged() {
    openDebug = chkOpenDebug.checked;
    save();
  }

  // callback:
  private void chkOpenMemoryChanged() {
    openMemory = chkOpenMemory.checked;
    save();
  }

  // callback:
  private void chkOpenVramChanged() {
    openVram = chkOpenVram.checked;
    save();
  }

  // callback:
  private void chkOpenOamChanged() {
    openOam = chkOpenOam.checked;
    save();
  }

  // callback:
  private void chkOpenEnemiesChanged() {
    openEnemies = chkOpenEnemies.checked;
    save();
  }

  private void makeCheckboxPair(
    GUI::VerticalLayout@ vl, GUI::Size sz,
    GUI::CheckLabel@ &out chk1, GUI::Callback@ cb1, string txt1, string tip1, bool val1,
    GUI::CheckLabel@ &out chk2, GUI::Callback@ cb2, string txt2, string tip2, bool val2
  ) {
    auto @hz = GUI::HorizontalLayout();
    vl.append(hz, GUI::Size(-1, 0));

    @chk1 = GUI::CheckLabel();
    chk1.text = txt1;
    chk1.toolTip = tip1;
    chk1.checked = val1;
    chk1.onToggle(cb1);
    hz.append(chk1, sz);

    @chk2 = GUI::CheckLabel();
    chk2.text = txt2;
    chk2.toolTip = tip2;
    chk2.checked = val2;
    chk2.onToggle(cb2);
    hz.append(chk2, sz);
  }

  private void build_advanced() {
    @advancedWindow = GUI::Window(475, 32, true);;
    advancedWindow.title = "Advanced Settings";
    advancedWindow.size = GUI::Size(sx(190*2), sy(660));

    auto sx150 = sx(190);
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
    advancedWindow.append(vl);
    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      auto @lbl = GUI::Label();
      lbl.text = "Server Address:";
      lbl.toolTip =
        "Server address (hostname or IP address) to connect to. If unsure, use the default `alttp.online`.\n\n"
        "If running your own server, enter its hostname or IP address here. Note that alttp.online is hosted in "
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
      lbl.text = "Team Number:";
      lbl.toolTip =
        "Your player's team number which will determine which items and state get synced to you. Only players in the "
        "same team get the same items and progress synced among themselves. Each team is independent of one another.";
      hz.append(lbl, GUI::Size(sx100, 0));

      @txtTeam = GUI::LineEdit();
      txtTeam.onChange(@GUI::Callback(txtTeamChanged));
      hz.append(txtTeam, GUI::Size(-1, sy20));
    }

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

      auto @lbl = GUI::Label();
      lbl.text = "Sync:";
      hz.append(lbl, GUI::Size(sx100, 0));
    }

    // the same layout as o2's web UI:
    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncItems, @GUI::Callback(chkSyncItemsChanged),
      "Items",
      "Enable to sync items (e.g. bow, boomerang, hookshot, powder)",
      true,
      chkSyncDungeonItems, @GUI::Callback(chkSyncDungeonItemsChanged),
      "Dungeon Items",
      "Enable to sync per-dungeon items (map, compass, big key)",
      true
    );

    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncPendants, @GUI::Callback(chkSyncPendantsChanged),
      "Pendants",
      "Enable to sync pendants",
      true,
      chkSyncCrystals, @GUI::Callback(chkSyncCrystalsChanged),
      "Crystals",
      "Enable to sync crystals",
      true
    );

    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncProgress, @GUI::Callback(chkSyncProgressChanged),
      "Progress",
      "Enable to sync world progress flags (rain state, bottle vendor, hobo, aga1, aga2, etc.)",
      true,
      chkSyncHearts, @GUI::Callback(chkSyncHeartsChanged),
      "Hearts",
      "Enable to sync heart container and piece counts",
      true
    );

    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncSmallKeys, @GUI::Callback(chkSyncSmallKeysChanged),
      "Small Keys",
      "Enable to sync small keys; syncs key changes as deltas, so keys should not be lost, though a key may be duplicated in rare cases",
      false,
      chkSyncChests, @GUI::Callback(chkSyncChestsChanged),
      "Chests",
      "Enable to sync chests opened in underworld rooms",
      true
    );

    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncOverworld, @GUI::Callback(chkSyncOverworldChanged),
      "Overworld (Global)",
      "Overworld area flags kept by every player: opened entrances, bombed walls, heart pieces and other events, once the area loads",
      true,
      chkSyncUnderworld, @GUI::Callback(chkSyncUnderworldChanged),
      "Underworld (Global)",
      "Dungeon room flags kept by every player: chests, keys, doors and bosses, once the room loads",
      true
    );

    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncOverworldLocal, @GUI::Callback(chkSyncOverworldLocalChanged),
      "Overworld (Local)",
      "What players in the same area do while there: lifted bushes and rocks and the secrets under them, bombed walls, entrance animations",
      true,
      chkSyncUnderworldLocal, @GUI::Callback(chkSyncUnderworldLocalChanged),
      "Underworld (Local)",
      "What players in the same room do while there: pots and the items under them, blocks, pegs, crystal switches, star tiles, trap doors, switches, chests, flying floor tiles",
      true
    );

    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncTorches, @GUI::Callback(chkSyncTorchesChanged),
      "Torches",
      "Torches lit by players in the same room",
      true,
      chkSyncSfx, @GUI::Callback(chkSyncSfxChanged),
      "Sound Effects",
      "Sound effects of players in the same room or area",
      true
    );

    makeCheckboxPair(
      vl, GUI::Size(sx150, 0),
      chkSyncSprites, @GUI::Callback(chkSyncSpritesChanged),
      "Sprites",
      "Enable to allow other players to see your player sprite on their screens",
      true,
      chkSyncEnemiesKilled, @GUI::Callback(chkSyncEnemiesKilledChanged),
      "Enemy Dead List",
      "Enemies killed by players in the same room or area stay dead when the game would spawn them again here; enemies themselves are synced by the LTTP enemy sync",
      true
    );

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @chkKillDeadEnemies = GUI::CheckLabel();
      chkKillDeadEnemies.text = "Kill Dead Enemies";
      chkKillDeadEnemies.toolTip = "Immediately kill the enemies here that players in the same room or area killed, when their dead list updates; needs Enemy Dead List";
      chkKillDeadEnemies.checked = killDeadEnemies;
      chkKillDeadEnemies.onToggle(@GUI::Callback(chkKillDeadEnemiesChanged));
      hz.append(chkKillDeadEnemies, GUI::Size(sx150, 0));
    }

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      auto @lbl = GUI::Label();
      lbl.text = "PvP:";
      hz.append(lbl, GUI::Size(sx100, 0));

      @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @chkEnablePvP = GUI::CheckLabel();
      chkEnablePvP.text = "Enable PvP";
      chkEnablePvP.toolTip =
        "Enable this to enable PvP. This will allow you to hit or even kill players in other teams.";
      chkEnablePvP.checked = enablePvP;
      chkEnablePvP.onToggle(@GUI::Callback(chkEnablePvPChanged));
      hz.append(chkEnablePvP, GUI::Size(sx150, 0));

      @chkPvPFF = GUI::CheckLabel();
      chkPvPFF.text = "PvP Friendly Fire";
      chkPvPFF.toolTip =
        "Enables friendly-fire mode for PvP.";
      chkPvPFF.checked = enablePvPFriendlyFire;
      chkPvPFF.onToggle(@GUI::Callback(chkPvPFFChanged));
      hz.append(chkPvPFF, GUI::Size(sx150, 0));
    }
    
    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      auto @lbl = GUI::Label();
      lbl.text = "Enemies:";
      hz.append(lbl, GUI::Size(sx100, 0));

      @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @chkSyncSmEnemies = GUI::CheckLabel();
      chkSyncSmEnemies.text = "SM  (BETA)";
      chkSyncSmEnemies.toolTip =
        "Enable this to sync enemies in Metroid only";
      chkSyncSmEnemies.checked = SyncSmEnemies;
      chkSyncSmEnemies.onToggle(@GUI::Callback(chkSyncSmEnemiesChanged));
      hz.append(chkSyncSmEnemies, GUI::Size(sx150, 0));

      @chkSyncLttpEnemies = GUI::CheckLabel();
      chkSyncLttpEnemies.text = "LTTP (BETA)";
      chkSyncLttpEnemies.toolTip =
        "Enable this to sync enemies in LTTP only";
      chkSyncLttpEnemies.checked = SyncLttpEnemies;
      chkSyncLttpEnemies.onToggle(@GUI::Callback(chkSyncLttpEnemiesChanged));
      hz.append(chkSyncLttpEnemies, GUI::Size(sx150, 0));
    }

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      auto @lbl = GUI::Label();
      lbl.text = "Discord:";
      hz.append(lbl, GUI::Size(sx100, 0));

      @hz = GUI::HorizontalLayout();
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
      vl.append(hz, GUI::Size(-1, 0));

      auto @lbl = GUI::Label();
      lbl.text = "External Connections:";
      hz.append(lbl, GUI::Size(sx150, 0));

      @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @chkBridge = GUI::CheckLabel();
      chkBridge.text = "QUsb2Snes Bridge";
      chkBridge.toolTip =
        "Enable this feature to connect to QUsb2Snes application to play multi-world games with ALttPO enabled for "
        "the visual aspect to see other players live in the same world.";
      chkBridge.checked = false;
      chkBridge.onToggle(@GUI::Callback(chkBridgeChanged));
      hz.append(chkBridge, GUI::Size(sx150, 0));

      @chkConnectorLib = GUI::CheckLabel();
      chkConnectorLib.text = "ConnectorLib";
      chkConnectorLib.toolTip =
        "Enable this feature to connect to CrowdControl, EmoTracker, or any other ConnectorLib server. If it becomes "
        "unchecked, that means a connection could not be made. Please make sure to enable the ConnectorLib server in "
        "the application you want to connect to and try checking this box again.";
      chkConnectorLib.checked = false;
      chkConnectorLib.onToggle(@GUI::Callback(chkConnectorLibChanged));
      hz.append(chkConnectorLib, GUI::Size(sx150, 0));

      @lblBridgeMessage = GUI::Label();
      lblBridgeMessage.text = "";
      lblBridgeMessage.toolTip =
        "Current status of QUsb2Snes connection";
      hz.append(lblBridgeMessage, GUI::Size(sx150, 0));

      @lblConnectorLibMessage = GUI::Label();
      lblConnectorLibMessage.text = "";
      lblConnectorLibMessage.toolTip =
        "Current status of ConnectorLib connection";
      hz.append(lblConnectorLibMessage, GUI::Size(sx150, 0));
    }

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      auto @lbl = GUI::Label();
      lbl.text = "Open these windows at startup:";
      lbl.toolTip = "The windows that open by themselves when the script starts. Any window can be opened later.";
      hz.append(lbl, GUI::Size(-1, 0));

      makeCheckboxPair(vl, GUI::Size(sx150, 0),
        chkOpenMap, @GUI::Callback(chkOpenMapChanged), "World Map", "Open the world map window at startup.", openMap,
        chkOpenPlayers, @GUI::Callback(chkOpenPlayersChanged), "Players", "Open the online players window at startup.", openPlayers
      );
      makeCheckboxPair(vl, GUI::Size(sx150, 0),
        chkOpenDebug, @GUI::Callback(chkOpenDebugChanged), "Debug", "Open the debug window at startup.", openDebug,
        chkOpenMemory, @GUI::Callback(chkOpenMemoryChanged), "Memory", "Open the memory window at startup.", openMemory
      );
      makeCheckboxPair(vl, GUI::Size(sx150, 0),
        chkOpenVram, @GUI::Callback(chkOpenVramChanged), "Sprite VRAM", "Open the sprite VRAM window at startup.", openVram,
        chkOpenOam, @GUI::Callback(chkOpenOamChanged), "OAM", "Open the OAM window at startup.", openOam
      );

      @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @chkOpenEnemies = GUI::CheckLabel();
      chkOpenEnemies.text = "Enemies";
      chkOpenEnemies.toolTip = "Open the enemies window at startup.";
      chkOpenEnemies.checked = openEnemies;
      chkOpenEnemies.onToggle(@GUI::Callback(chkOpenEnemiesChanged));
      hz.append(chkOpenEnemies, GUI::Size(sx150, 0));

      @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @btnOpenDebug = GUI::Button();
      btnOpenDebug.text = "Debug Windows...";
      btnOpenDebug.toolTip = "Click this button to open the debug window, which opens the windows used to debug the script.";
      btnOpenDebug.onActivate(@GUI::Callback(btnOpenDebugClicked));
      hz.append(btnOpenDebug, GUI::Size(-1, -1));
    }

    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      auto @lbl = GUI::Label();
      lbl.text = "Presets:";
      hz.append(lbl, GUI::Size(sx150, 0));

      @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @btnPresetDefault = GUI::Button();
      btnPresetDefault.text = "Default";
      btnPresetDefault.toolTip =
        "Restore the Default settings for alttpo";
      btnPresetDefault.onActivate(@GUI::Callback(btnPresetDefaultClicked));
      hz.append(btnPresetDefault, GUI::Size(-1, -1));

      @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @btnPresetMultiworld = GUI::Button();
      btnPresetMultiworld.text = "Multiworld";
      btnPresetMultiworld.toolTip =
        "Settings for multiworld, Enables RaceMode and the QUsb2Snes Bridge.";
      btnPresetMultiworld.onActivate(@GUI::Callback(btnPresetMultiworldClicked));
      hz.append(btnPresetMultiworld, GUI::Size(-1, -1));
    }
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
