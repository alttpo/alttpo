
funcdef void Notify(const string &in msg);

class NotificationSystem {
  // Notifications system:
  array<string> notifications(0);

  void notify(const string &in msg) {
    notifications.insertLast(msg);
    message(msg);
  }

  int notificationFrameTimer = 0;
  int renderNotifications(int ei) {
    if (notifications.length() == 0) return ei;

    // pop off the first notification if its timer is expired:
    if (notificationFrameTimer++ >= 170) {
      notifications.removeAt(0);
      notificationFrameTimer = 0;
    }
    if (notifications.length() == 0) return ei;

    // only render first two notification messages:
    int count = notifications.length();
    if (count > 2) count = 2;

    if (font_set) {
      @ppu::extra.font = ppu::fonts[0];
      font_set = false;
    }

    ppu::extra.color = ppu::rgb(26, 26, 26);
    ppu::extra.outline_color = ppu::rgb(0, 0, 0);
    auto height = ppu::extra.font.height + 1;

    for (int i = 0; i < count; i++) {
      auto msg = notifications[i];

      auto row = count - i;
      auto @label = ppu::extra[ei++];
      label.reset();
      label.index = 127;
      label.source = 4;       // OBJ1 layer
      label.priority = 0x110; // force priority to 0x10 (higher than any other priority normally used)
      label.x = 2;
      label.y = 222 - (height * row);
      auto width = ppu::extra.font.measureText(msg);
      label.width = width + 2;
      label.height = ppu::extra.font.height + 2;
      label.text(1, 1, msg);
    }

    return ei;
  }
}

NotificationSystem notificationSystem;
