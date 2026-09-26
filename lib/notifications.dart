import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_settings.dart';

/// Wraps flutter_local_notifications for EcoSteps' two notification
/// features: a daily reminder at a fixed time, and one-off milestone
/// alerts fired when the user finishes something.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int _dailyReminderId = 1;
  static const int _milestoneAlertId = 2;
  static const int _reminderHour = 18; // 6pm - no UI yet to customize this.
  static const int _reminderMinute = 0;
  // Run with --dart-define=TEST_DAILY_REMINDER=true to test the real daily
  // scheduling/cancellation flow without waiting until 6pm. Release builds
  // always use the normal schedule.
  static const bool _testDailyReminder =
      kDebugMode && bool.fromEnvironment('TEST_DAILY_REMINDER');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(
        tz.getLocation(await FlutterTimezone.getLocalTimezone()),
      );
    } catch (e) {
      // Fall back to whatever tz.local already defaults to rather than
      // crashing app startup over a timezone lookup failure.
    }

    const settings = InitializationSettings(iOS: DarwinInitializationSettings());
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> _requestPermissions() async {
    await _ensureInitialized();
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return granted ?? false;
  }

  /// Reads the Daily Reminders setting and schedules or cancels the
  /// repeating reminder to match. Call at startup and whenever the
  /// Settings toggle changes.
  Future<void> syncDailyReminders() async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(AppSettingKeys.dailyReminders) ?? true;

    if (!enabled) {
      await _plugin.cancel(_dailyReminderId);
      return;
    }

    if (!await _requestPermissions()) return;

    final scheduledTime = _testDailyReminder
        ? tz.TZDateTime.now(tz.local).add(const Duration(minutes: 2))
        : _nextInstanceOf(hour: _reminderHour, minute: _reminderMinute);

    await _plugin.zonedSchedule(
      _dailyReminderId,
      'EcoSteps',
      "Got a minute? Check off today's eco-friendly swaps.",
      scheduledTime,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    if (_testDailyReminder) {
      debugPrint('Test daily reminder scheduled for $scheduledTime');
    }
  }

  /// Shows a one-off notification for a milestone (e.g. finishing a
  /// challenge's checklist), if the Milestone Alerts setting is on.
  Future<void> showMilestoneAlert({
    required String title,
    required String body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(AppSettingKeys.milestoneAlerts) ?? true;
    if (!enabled) return;
    if (!await _requestPermissions()) return;

    await _plugin.show(
      _milestoneAlertId,
      title,
      body,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
        ),
      ),
    );
  }

  tz.TZDateTime _nextInstanceOf({required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
