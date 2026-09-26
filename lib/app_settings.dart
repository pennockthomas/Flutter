import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingKeys {
  static const backgroundDarkness = 'settings.background_darkness';
  static const startupSound = 'settings.startup_sound';
  static const systemSounds = 'settings.system_sounds';
  static const backgroundMusic = 'settings.background_music';
  static const dailyReminders = 'settings.daily_reminders';
  static const milestoneAlerts = 'settings.milestone_alerts';
  static const friendUpdates = 'settings.friend_updates';
  static const shareTotalProgress = 'settings.share_total_progress';
  static const shareCategoryProgress = 'settings.share_category_progress';
  static const shareChecklistItems = 'settings.share_checklist_items';
  static const reducedMotion = 'settings.reduced_motion';
}

class AppSounds {
  static const String tierUnlocked = 'sounds/new unlock.wav';
  static const String challengeFinished = 'sounds/Finished.wav';
}

class AppSettings {
  static final ValueNotifier<double> backgroundDarkness = ValueNotifier<double>(
    0.2,
  );

  /// Whether camera/transition animations should be skipped in favor of
  /// snapping instantly. Read synchronously wherever an animation is about
  /// to start; call [loadReducedMotion] once at startup to populate it and
  /// [setReducedMotion] when the Settings toggle changes.
  static final ValueNotifier<bool> reducedMotion = ValueNotifier<bool>(false);

  static final AudioPlayer _effectsPlayer = AudioPlayer();

  static Future<void> loadBackgroundDarkness({
    double fallbackDarkness = 0.2,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    backgroundDarkness.value =
        prefs.getDouble(AppSettingKeys.backgroundDarkness) ?? fallbackDarkness;
  }

  static Future<void> setBackgroundDarkness(double value) async {
    backgroundDarkness.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(AppSettingKeys.backgroundDarkness, value);
  }

  static Future<void> loadReducedMotion() async {
    final prefs = await SharedPreferences.getInstance();
    reducedMotion.value = prefs.getBool(AppSettingKeys.reducedMotion) ?? false;
  }

  static void setReducedMotion(bool value) {
    reducedMotion.value = value;
  }

  /// Plays the platform's UI click sound (no custom audio asset needed)
  /// when the System Sounds setting is enabled. Call this from places like
  /// checking off a checklist item, where a little audio feedback helps.
  static Future<void> playSystemSoundIfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(AppSettingKeys.systemSounds) ?? true;
    if (!enabled) return;
    await SystemSound.play(SystemSoundType.click);
  }

  /// Plays a bundled sound effect (see [AppSounds]) when the System Sounds
  /// setting is enabled, for moments a plain platform click isn't enough
  /// (unlocking a new tier, finishing a challenge's checklist).
  static Future<void> playSoundEffectIfEnabled(String assetPath) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(AppSettingKeys.systemSounds) ?? true;
    if (!enabled) return;
    await _effectsPlayer.play(AssetSource(assetPath));
  }
}

class AppBackgroundOverlay extends StatefulWidget {
  final double fallbackDarkness;

  const AppBackgroundOverlay({super.key, this.fallbackDarkness = 0.2});

  @override
  State<AppBackgroundOverlay> createState() => _AppBackgroundOverlayState();
}

class _AppBackgroundOverlayState extends State<AppBackgroundOverlay> {
  late double _darkness = widget.fallbackDarkness;

  @override
  void initState() {
    super.initState();
    _darkness = AppSettings.backgroundDarkness.value;
    AppSettings.loadBackgroundDarkness(
      fallbackDarkness: widget.fallbackDarkness,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AppSettings.backgroundDarkness,
      builder: (context, darkness, child) {
        _darkness = darkness;
        return Positioned.fill(
          child: Container(color: Colors.black.withOpacity(_darkness)),
        );
      },
    );
  }
}
