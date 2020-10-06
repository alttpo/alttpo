PlayersWindow @playersWindow;

class PlayersWindow {
  private GUI::Window @window;
  private GUI::VerticalLayout @vl;
  private GUI::HorizontalLayout @hz;
  private GUI::Label @noPlayersLabel;
  
  private array<GUI::Label@> playerLabels;
  
  private array<GameState@> playersArray() {
    array<GameState@> @ps;

    if (sock is null) {
      @ps = onlyLocalPlayer;
    } else {
      @ps = players;
    }
    
    return ps;
  }
  
  void update()
  {
    auto sy5 = sy(5);
    auto vl = GUI::VerticalLayout();
    vl.setSpacing();
    vl.setPadding(sy5, sy5);
    window.append(vl);
    {
      auto @hz = GUI::HorizontalLayout();
      vl.append(hz, GUI::Size(-1, 0));
      
      array<GameState@> @ps = playersArray();
      playerLabels.resize(ps.length());
      
      if(ps.length() > 0 && settings.started)
      {
        for (uint i = 0; i < ps.length(); i++) {
          auto @p = ps[i];
          
          @playerLabels[i] = GUI::Label();
          playerLabels[i].text = (fmtInt(i) + ": " + p.name);
          playerLabels[i].toolTip =
            "This user is playing in your group.";
          int r = (p.player_color      ) & 0x1F;
          int g = (p.player_color >>  5) & 0x1F;
          int b = (p.player_color >> 10) & 0x1F;
          playerLabels[i].foregroundColor = GUI::Color((r * 527 + 23) >> 6, (g * 527 + 23) >> 6, (b * 527 + 23) >> 6);
          vl.append(playerLabels[i], GUI::Size(-1, 0));
        }
      }
      else
      {
        auto @noPlayersLabel = GUI::Label();
        noPlayersLabel.text = "No players online!";
        noPlayersLabel.toolTip =
          "No players are playing in your group!";
        noPlayersLabel.foregroundColor = GUI::Color(255,   0,   0);
        vl.append(noPlayersLabel, GUI::Size(-1, 0));
      }
    }
    vl.resize();
    window.visible = true;
  }
  
  PlayersWindow() {
    @window = GUI::Window(-260, 48, true);
    window.title = "Online players";
    window.size = GUI::Size(sx(260), sy(16*25));
    window.dismissable = false;
    window.backgroundColor = GUI::Color(28, 28, 28);
    window.font = GUI::Font("{sans}", 12);
    
    update();
  }
}
