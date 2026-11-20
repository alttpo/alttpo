PlayersWindow @playersWindow;

class PlayersWindow {
  private GUI::Window @window;
  private GUI::Label @noPlayersLabel;
  private array<GUI::Label@> playerLabels;
  private GUI::Label @runTimerLabel;
  private GUI::Label @runWarningLabel;
  private GUI::Button @btnResetRun;
  private uint64 runTimerUpdated = 0;

  private array<GameState@>@ playersArray() {
    array<GameState@> @ps;

    if (sock is null) {
      @ps = onlyLocalPlayer;
    } else {
      @ps = players;
    }
    
    return ps;
  }

  void update() {
    // a window that is not shown is brought up to date when it is shown again:
    if (!window.visible) return;

    auto sy5 = sy(5);
    auto vl = GUI::VerticalLayout();
    vl.setSpacing();
    vl.setPadding(sy5, sy5);
    window.append(vl);
    {
      // the run timer (see RunTiming.as) and the group reset:
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      @runTimerLabel = GUI::Label();
      runTimerLabel.text = "Run: " + run_time_text();
      runTimerLabel.toolTip = "First player start to last player finish, on the server's clock";
      runTimerLabel.foregroundColor = GUI::Color(255, 255, 255);
      hz.append(runTimerLabel, GUI::Size(-1, 0));

      @btnResetRun = GUI::Button();
      btnResetRun.text = "Reset run";
      btnResetRun.toolTip =
        "Forget all synced state and reset the run timer for all players in the group, o2 players included; "
        "does not reset the console/emulator; asks first";
      btnResetRun.onActivate(@GUI::Callback(btnResetRunClicked));
      hz.append(btnResetRun, GUI::Size(0, 0));

      @runWarningLabel = GUI::Label();
      runWarningLabel.text = run_cost_warning();
      runWarningLabel.foregroundColor = GUI::Color(255, 160, 0);
      vl.append(runWarningLabel, GUI::Size(-1, 0));
    }
    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));

      array<GameState@> @ps = playersArray();
      playerLabels.resize(ps.length());

      if (ps.length() > 0) {
        // find all team numbers:
        array<uint8> teamNumbers;
        for (uint i = 0; i < ps.length(); i++) {
          auto @p = ps[i];
          if (p is null) {
            continue;
          }
          if (p.ttl <= 0) {
            continue;
          }
          if (teamNumbers.find(p.team) >= 0) {
            continue;
          }
          teamNumbers.insertLast(p.team);
        }
        teamNumbers.sortAsc();

        for (uint t = 0; t < teamNumbers.length(); t++) {
          auto team = teamNumbers[t];

          auto @lbl = GUI::Label();
          lbl.foregroundColor = GUI::Color(128, 128, 128);
          vl.append(lbl, GUI::Size(-1, 0));

          uint count = 0;
          for (uint i = 0; i < ps.length(); i++) {
            auto @p = ps[i];
            if (p is null) {
              continue;
            }
            if (p.ttl <= 0) {
              continue;
            }
            if (p.team != team) {
              continue;
            }

            count++;
            @playerLabels[i] = GUI::Label();
            string locname = "";
            if (rom !is null) {
              locname = rom.location_name(p);
            }
            playerLabels[i].text = "{0}: {1} ({2})".format({fmtInt(i), p.name, locname});
            string times = player_time_text(p);
            if (times != "") {
              playerLabels[i].text = playerLabels[i].text + " " + times;
            }
            playerLabels[i].toolTip =
              "This user is playing in your group.";
            int r = (p.player_color      ) & 0x1F;
            int g = (p.player_color >>  5) & 0x1F;
            int b = (p.player_color >> 10) & 0x1F;
            playerLabels[i].foregroundColor = GUI::Color((r * 527 + 23) >> 6, (g * 527 + 23) >> 6, (b * 527 + 23) >> 6);
            vl.append(playerLabels[i], GUI::Size(-1, 0));
          }

          lbl.text = "Team {0}: ({1})".format({fmtInt(team), fmtInt(count)});
        }
      } else {
        auto @noPlayersLabel = GUI::Label();
        noPlayersLabel.text = "No players online!";
        noPlayersLabel.toolTip =
          "No players are playing in your group!";
        noPlayersLabel.foregroundColor = GUI::Color(255,   0,   0);
        vl.append(noPlayersLabel, GUI::Size(-1, 0));
      }
    }
    vl.resize();
  }

  private void btnResetRunClicked() {
    confirm_reset_run();
  }

  // updateRunTimer refreshes the run timer while it counts up, a few times a second.
  void updateRunTimer() {
    if (runTimerLabel is null) return;
    if (!window.visible) return;
    uint64 now = chrono::monotonic::millisecond;
    if (now - runTimerUpdated < 100) return;
    runTimerUpdated = now;
    runTimerLabel.text = "Run: " + run_time_text();
    runWarningLabel.text = run_cost_warning();
  }

  PlayersWindow() {
    @window = GUI::Window(260, 48, true);
    window.title = "Online players";
    window.size = GUI::Size(sx(340), sy(16*25));
    window.backgroundColor = GUI::Color(28, 28, 28);
    windowLayout.attach("players", window);
    window.visible = true;

    update();
  }

  bool isOpen() {
    return window.visible;
  }

  void show() {
    window.visible = true;
    window.setFocused();
    update();
  }
}
