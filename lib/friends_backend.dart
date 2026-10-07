import 'friends_models.dart';

/// Storage for friends, so the logic in `FriendsService` can be tested
/// without Firebase. `FirestoreFriendsBackend` is the real one.
abstract class FriendsBackend {
  /// The signed-in user's friend code, creating one the first time. Also
  /// keeps the name stored next to the code up to date.
  Future<String> ensureFriendCode(String uid, String displayName);

  Future<FriendCodeInfo?> lookupCode(String code);

  /// The request from [from] to [to], if there is one.
  Future<FriendRequest?> getRequest(String from, String to);

  Future<void> createRequest(FriendRequest request);

  Future<void> acceptRequest(FriendRequest request);

  Future<void> deleteRequest(FriendRequest request);

  /// Every request to or from [uid], pending and accepted.
  Stream<List<FriendRequest>> watchRequests(String uid);

  /// A friend's name and shared counts, live. Emits null if they can't be
  /// read (not friends, or removed).
  Stream<FriendSummary?> watchFriend(String uid, {String fallbackName});

  Future<List<FriendSummary>> loadDemoFriends();

  /// Replaces the demo friends (only the app's owner is allowed to).
  Future<void> saveDemoFriends(List<FriendSummary> friends);
}
