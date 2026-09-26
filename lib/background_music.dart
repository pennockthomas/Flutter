import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// Controls the app's looping background music track as a singleton, so
/// navigating between screens doesn't restart or duplicate playback - the
/// same player just keeps running for the life of the app.
class BackgroundMusicController {
  BackgroundMusicController._();

  static final BackgroundMusicController instance =
      BackgroundMusicController._();

  static const String _trackAsset = 'sounds/background.wav';
  static const double _volume = 0.35;

  final AudioPlayer _player = AudioPlayer();
  bool _enabled = false;

  /// Reads the Background Music setting and starts or stops the track to
  /// match. Call this at app startup and whenever the setting changes.
  Future<void> syncWithSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(AppSettingKeys.backgroundMusic) ?? false;

    if (_enabled) {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource(_trackAsset), volume: _volume);
    } else {
      await _player.stop();
    }
  }

  /// Pauses/resumes playback in response to the app being backgrounded or
  /// foregrounded, without touching the Background Music setting itself.
  Future<void> handleAppLifecycleChange(bool isForegrounded) async {
    if (!_enabled) return;
    if (isForegrounded) {
      await _player.resume();
    } else {
      await _player.pause();
    }
  }
}
