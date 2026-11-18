// ResetRunWindow asks the player to confirm a group reset before it is started, so that a stray click on "Reset run"
// doesn't reset everyone else's run and synced state.
ResetRunWindow @resetRunWindow;

// confirm_reset_run shows the confirmation; its "Reset for everyone" button starts the group reset.
void confirm_reset_run() {
  if (resetRunWindow is null) {
    @resetRunWindow = ResetRunWindow();
  }
  resetRunWindow.show();
}

class ResetRunWindow {
  private GUI::Window @window;

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

    line(vl, "Reset the run for everyone?", GUI::Color(255, 107, 107));
    line(vl, "This resets the run timer for every player in the group, o2 players included,", GUI::Color(255, 255, 255));
    line(vl, "and clears all synchronized game state for everyone.", GUI::Color(255, 255, 255));
    line(vl, "To fully reset, every player first resets their console or emulator, and then", GUI::Color(255, 239, 0));
    line(vl, "one player presses Reset. A player still in the old game would sync its state", GUI::Color(255, 239, 0));
    line(vl, "back to everyone after the reset.", GUI::Color(255, 239, 0));

    auto @hz = GUI::HorizontalLayout();
    vl.append(hz, GUI::Size(-1, 0));
    auto @spacer = GUI::Label();
    hz.append(spacer, GUI::Size(-1, 0));

    auto @btnCancel = GUI::Button();
    btnCancel.text = "Cancel";
    btnCancel.onActivate(@GUI::Callback(btnCancelClicked));
    hz.append(btnCancel, GUI::Size(0, 0));

    auto @btnReset = GUI::Button();
    btnReset.text = "Reset for everyone";
    btnReset.onActivate(@GUI::Callback(btnResetClicked));
    hz.append(btnReset, GUI::Size(0, 0));

    vl.resize();
  }

  private void line(GUI::VerticalLayout @vl, const string &in text, const GUI::Color &in color) {
    auto @l = GUI::Label();
    l.text = text;
    l.foregroundColor = color;
    vl.append(l, GUI::Size(-1, 0));
  }

  void show() {
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
