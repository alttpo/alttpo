
namespace discord {
  int lastConnect = 1;
  int presenceCount = 1;
  uint64 timeStart = 0;
  uint64 timeEnd = 0;

  void cartridge_loaded() {
    timeStart = 0;
    timeEnd = 0;
  }

  void pre_frame() {
    // measure when game starts:
    if (timeStart == 0) {
      // when we enter module 5, start the timer:
      if (local.module >= 0x05 && local.module <= 0x19) {
        timeStart = ::chrono::timestamp;
      }
    } else {
      if (timeEnd == 0) {
        if (local.module == 0x19) {
          timeEnd = ::chrono::timestamp;
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
      activity.Type = 1;  // playing
      activity.Details = ::rom.title;
      if (!settings.started) {
        //activity.State = "Disconnected";
      } else {
        activity.State = "Connected";
      }
      activity.Assets.LargeImage = "logo";
      activity.Assets.LargeText = "ALttPO";
      //activity.Assets.SmallImage = "logo";
      //activity.Assets.SmallText = "small text";
      activity.Timestamps.Start = timeStart;
      activity.Timestamps.End = timeEnd;
      activity.Instance = true;
      activityManager.UpdateActivity(activity, null);
    }

    if (runCallbacks() != 0) {
      message("discord::runCallbacks() failed with err=" + fmtInt(result));
      return;
    }
  }
}
