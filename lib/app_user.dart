import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The person using the app: the name they chose, and what's derived from it
/// (first name, avatar initials). Kept on the device, so it works without an
/// account; it's also what friends will see once signed in.
///
/// Call [load] once at startup. Screens that show the name listen to
/// [listenable] so a change in the Profile shows everywhere at once.
class AppUser {
  static const String _prefKey = 'profile.name';
  static const int maxNameLength = 30;

  static final ValueNotifier<String> _name = ValueNotifier<String>('');

  static ValueListenable<String> get listenable => _name;

  /// The chosen name, or '' if none has been entered yet.
  static String get name => _name.value;

  static bool get hasName => _name.value.isNotEmpty;

  /// The name for display, with a stand-in until one has been entered.
  static String get displayName => hasName ? name : 'You';

  static String get firstName => hasName ? name.split(' ').first : 'You';

  /// First letter of the first and last word, uppercased ("Thomas van der
  /// Berg" → "TB"); one letter for a single word, "?" before a name exists.
  static String get initials {
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String first(String word) =>
        String.fromCharCode(word.runes.first).toUpperCase();
    return parts.length == 1
        ? first(parts.first)
        : first(parts.first) + first(parts.last);
  }

  /// The name as it would be saved (trimmed, inner spaces collapsed), or null
  /// if it isn't acceptable: empty, longer than [maxNameLength], or containing
  /// control characters.
  static String? cleanName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty || cleaned.length > maxNameLength) return null;
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(cleaned)) return null;
    return cleaned;
  }

  /// Loads the saved name; call before the first screen that shows it.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _name.value = prefs.getString(_prefKey) ?? '';
  }

  /// Saves [raw] as the name. Returns false (and changes nothing) if it isn't
  /// acceptable, see [cleanName].
  static Future<bool> setName(String raw) async {
    final cleaned = cleanName(raw);
    if (cleaned == null) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, cleaned);
    _name.value = cleaned;
    return true;
  }

  /// Forgets the name in memory (tests only; call [load] to bring it back).
  @visibleForTesting
  static void clearForTest() => _name.value = '';
}
