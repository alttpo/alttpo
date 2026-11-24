
funcdef void Notify(const string &in msg);

class Notification {
  string msg;
  // how many frames it stays up:
  int frames = 60;
  uint16 color = 0;
}

class NotificationSystem {
  // Notifications system:
  array<Notification@> notifications(0);

  void notify(const string &in msg) {
    auto @n = Notification();
    n.msg = msg;
    n.color = ppu::rgb(26, 26, 26);
    notifications.insertLast(n);
    message(msg);
  }

  // warn shows a message that stands out: bright orange and up on screen for 5.5 seconds.
  void warn(const string &in msg) {
    auto @n = Notification();
    n.msg = msg;
    n.frames = 330;
    n.color = ppu::rgb(31, 18, 0);
    notifications.insertLast(n);
    message(msg);
  }

  int notificationFrameTimer = 0;
  int renderNotifications(int ei) {
    if (notifications.length() == 0) return ei;

    // pop off the first notification if its timer is expired:
    if (notificationFrameTimer++ >= notifications[0].frames) {
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

    ppu::extra.outline_color = ppu::rgb(0, 0, 0);
    auto height = ppu::extra.font.height + 1;

    for (int i = 0; i < count; i++) {
      auto msg = notifications[i].msg;
      ppu::extra.color = notifications[i].color;

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
