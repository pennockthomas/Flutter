import 'challenge_model.dart';
import 'friends_backend.dart';
import 'friends_models.dart';
import 'progress_summary.dart';

/// The rules of friendship: how a code is read, what adding a friend does
/// in each situation, and the made-up friends for demonstrations. The
/// storage is behind [FriendsBackend].
class FriendsService {
  FriendsService(this.backend);

  final FriendsBackend backend;

  /// Letters and digits that can't be mistaken for each other (no 0/O, 1/I).
  static const String codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int codeLength = 6;

  /// What the user typed, tidied into a code (uppercase, without spaces or
  /// dashes), or null if it can't be one.
  static String? normalizeCode(String raw) {
    final code = raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (code.length != codeLength) return null;
    for (final char in code.split('')) {
      if (!codeAlphabet.contains(char)) return null;
    }
    return code;
  }

  Future<String> myCode(String uid, String myName) =>
      backend.ensureFriendCode(uid, myName);

  /// Adds a friend by their code. Never sends progress anywhere: it only
  /// asks, and the other person has to accept.
  Future<AddFriendOutcome> addByCode({
    required String myUid,
    required String myName,
    required String rawCode,
  }) async {
    final code = normalizeCode(rawCode);
    if (code == null) return AddFriendOutcome.invalidCode;

    final target = await backend.lookupCode(code);
    if (target == null) return AddFriendOutcome.notFound;
    if (target.uid == myUid) return AddFriendOutcome.yourOwnCode;

    final mine = await backend.getRequest(myUid, target.uid);
    final theirs = await backend.getRequest(target.uid, myUid);
    if ((mine?.accepted ?? false) || (theirs?.accepted ?? false)) {
      return AddFriendOutcome.alreadyFriends;
    }
    if (mine != null) return AddFriendOutcome.alreadyRequested;
    if (theirs != null) {
      // They already asked us: saying yes to that is the same as asking.
      await backend.acceptRequest(theirs);
      return AddFriendOutcome.nowFriends;
    }

    await backend.createRequest(
      FriendRequest(
        from: myUid,
        to: target.uid,
        fromName: myName,
        toName: target.displayName,
      ),
    );
    return AddFriendOutcome.requestSent;
  }

  Future<void> accept(FriendRequest request) => backend.acceptRequest(request);

  /// Declines an incoming request, cancels an outgoing one, or removes a
  /// friend: all the same thing, the request goes away.
  Future<void> remove(FriendRequest request) => backend.deleteRequest(request);

  Stream<List<FriendRequest>> watchRequests(String uid) =>
      backend.watchRequests(uid);

  Stream<FriendSummary?> watchFriend(String uid, {String fallbackName = ''}) =>
      backend.watchFriend(uid, fallbackName: fallbackName);

  Future<List<FriendSummary>> loadDemoFriends() => backend.loadDemoFriends();

  /// Three made-up friends whose totals match the current swap list, so the
  /// numbers look right next to the user's own.
  static List<FriendSummary> buildDemoFriends(
    Map<String, Challenge> challenges,
  ) {
    final areas = progressByArea(challenges);
    // How much of each area (in the order they appear) each person has done.
    const people = [
      ('demo-mila', 'Mila Vermeer', [0.50, 0.30, 0.25]),
      ('demo-sam', 'Sam de Vries', [0.45, 0.55, 0.75]),
      ('demo-lena', 'Lena Bakker', [0.10, 0.35, 0.07]),
    ];
    return [
      for (final (id, name, shares) in people)
        () {
          final done = <AreaProgress>[
            for (var i = 0; i < areas.length; i++)
              AreaProgress(
                label: areas[i].label,
                total: areas[i].total,
                completed: (areas[i].total * shares[i % shares.length]).round(),
              ),
          ];
          return FriendSummary(
            uid: id,
            name: name,
            completed: done.fold(0, (sum, a) => sum + a.completed),
            total: done.fold(0, (sum, a) => sum + a.total),
            areas: done,
            isDemo: true,
          );
        }(),
    ];
  }

  Future<void> resetDemoFriends(Map<String, Challenge> challenges) =>
      backend.saveDemoFriends(buildDemoFriends(challenges));
}
