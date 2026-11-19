// ResetRunWindow asks the player to confirm a group reset before it is started, so that a stray click on "Reset run"
// doesn't reset everyone else's run and synced state.
ResetRunWindow @resetRunWindow;

// confirm_reset_run shows the confirmation; its "Reset for everyone" button starts the group reset, or, when offline,
// "Reset my state" clears only our own client state.
void confirm_reset_run() {
  if (resetRunWindow is null) {
    @resetRunWindow = ResetRunWindow();
  }
  resetRunWindow.show();
}

class ResetRunWindow {
  private GUI::Window @window;
  private array<GUI::Label@> lines;
  private GUI::Button @btnReset;

  ResetRunWindow() {
    @window = GUI::Window(200, 160, true);
    window.title = "Reset the run for everyone?";
    window.size = GUI::Size(sx(460), sy(16*11));
    window.dismissable = false;
    window.backgroundColor = GUI::Color(28, 28, 28);
    window.font = GUI::Font("{sans}", 12);

    auto sy5 = sy(5);
    auto vl = GUI::VerticalLayout();
    vl.setSpacing();
    vl.setPadding(sy5, sy5);
    window.append(vl);

    for (uint i = 0; i < 6; i++) {
      auto @l = GUI::Label();
      vl.append(l, GUI::Size(-1, 0));
      lines.insertLast(l);
    }

    auto @hz = GUI::HorizontalLayout();
    vl.append(hz, GUI::Size(-1, 0));
    auto @spacer = GUI::Label();
    hz.append(spacer, GUI::Size(-1, 0));

    auto @btnCancel = GUI::Button();
    btnCancel.text = "Cancel";
    btnCancel.onActivate(@GUI::Callback(btnCancelClicked));
    hz.append(btnCancel, GUI::Size(0, 0));

    @btnReset = GUI::Button();
    btnReset.text = "Reset for everyone";
    btnReset.onActivate(@GUI::Callback(btnResetClicked));
    hz.append(btnReset, GUI::Size(0, 0));

    vl.resize();
  }

  private void set_line(uint i, const string &in text, const GUI::Color &in color) {
    lines[i].text = text;
    lines[i].foregroundColor = color;
  }

  // update words the confirmation for a group reset, or, without a server connection, for clearing only our own
  // client state:
  private void update() {
    auto white = GUI::Color(255, 255, 255);
    auto yellow = GUI::Color(255, 239, 0);
    if (sock is null || local.index < 0) {
      window.title = "Reset your own client state?";
      set_line(0, "Reset your own client state?", GUI::Color(255, 107, 107));
      set_line(1, "You are offline: not connected to the server. This only resets your own client", white);
      set_line(2, "state: it clears the game state and players alttpo remembers, and your run timer.", white);
      set_line(3, "No other player is affected.", white);
      set_line(4, "", white);
      set_line(5, "", white);
      btnReset.text = "Reset my state";
    } else {
      window.title = "Reset the run for everyone?";
      set_line(0, "Reset the run for everyone?", GUI::Color(255, 107, 107));
      set_line(1, "This resets the run timer for every player in the group, o2 players included,", white);
      set_line(2, "and clears all synchronized game state for everyone.", white);
      set_line(3, "To fully reset, every player first resets their console or emulator, and then", yellow);
      set_line(4, "one player presses Reset. A player still in the old game would sync its state", yellow);
      set_line(5, "back to everyone after the reset.", yellow);
      btnReset.text = "Reset for everyone";
    }
  }

  void show() {
    update();
    window.visible = true;
  }

  private void btnCancelClicked() {
    window.visible = false;
  }

  private void btnResetClicked() {
    window.visible = false;
    runReset.request();
  }
}
