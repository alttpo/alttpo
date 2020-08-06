
namespace discord {
  int lastConnect = 1;
  int presenceCount = 1;
  uint64 timeStart = 0;
  uint64 timeEnd = 0;
  bool enabled_cache;
  bool enabled_is_cached = false;

  void cartridge_loaded() {
    timeStart = 0;
    timeEnd = 0;
  }

  void pre_frame() {
    // check if discord integration is enabled by host:
    if (!enabled_is_cached) {
      enabled_cache = enabled;
      enabled_is_cached = true;
    }

    if (!enabled_cache) return;

    auto module = bus::read_u8(0x7E0010);
    // measure when game starts:
    if (timeStart == 0) {
      // when we enter module 5, start the timer:
      if (module >= 0x05 && module <= 0x19) {
        timeStart = chrono::realtime::second;
      }
    } else {
      if (timeEnd == 0) {
        if (module == 0x19) {
          timeEnd = chrono::realtime::second;
        }
      }
    }

    // create our discord integration instance:
    if (!created) {
      if (--lastConnect > 0) return;

      // attempt reconnect every 10 seconds:
      lastConnect = 10 * 60;

      //logLevel = 4;  // DEBUG
      if (create(725722436351426643) != 0) {
        message("discord::create() failed with err=" + fmtInt(result));
        return;
      }

      message("discord: connected!");
    }
    if (!created) return;

    // update presence on regular cadence:
    if (--presenceCount <= 0) {
      // every 5 seconds:
      presenceCount = 5 * 60;

      auto activity = Activity();
      activity.Type = 1;  // Playing
      activity.Details = rom.title;

      activity.Assets.LargeImage = "logo";
      activity.Assets.LargeText = "ALttPO";
      //activity.Assets.SmallImage = "logo";
      //activity.Assets.SmallText = "small text";

      if (settings.started) {
        if (settings.DiscordPrivate) {
          activity.State = "In Private Group";
        } else {
          activity.State = "Group '" + settings.GroupTrimmed + "'";
        }

        // party size:
        if (playerCount > 0) {
          activity.Party.Id = settings.GroupTrimmed;
          activity.Party.Size.MaxSize = 64;
          activity.Party.Size.CurrentSize = playerCount;
        }
      }

      // Nothing to do with timeEnd since Timestamps.End creates a countdown timer.
      if (timeEnd == 0) {
        activity.Timestamps.Start = timeStart;
      }
      activity.Instance = true;
      activityManager.UpdateActivity(activity, null);
    }

    if (runCallbacks() != 0) {
      message("discord::runCallbacks() failed with err=" + fmtInt(result));
      return;
    }
  }
}
