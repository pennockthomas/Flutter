/// The current (only) user of the app. There's no accounts system yet, so
/// this is a single hardcoded identity rather than something loaded from
/// storage - kept in one place instead of repeated as string literals
/// across every screen that shows a name or avatar initials.
class AppUser {
  static const String name = 'Thomas Pennock';

  static String get firstName => name.split(' ').first;

  static String get initials => name
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0])
      .join()
      .toUpperCase();
}
