import 'dart:async';

import 'package:flut/friends_backend.dart';
import 'package:flut/friends_models.dart';

/// An in-memory [FriendsBackend] for tests.
class FakeFriendsBackend implements FriendsBackend {
  final Map<String, FriendCodeInfo> codes = {};
  final Map<String, String> codeOf = {}; // uid -> code
  final Map<String, FriendRequest> requests = {};
  final Map<String, FriendSummary> friendData = {};
  List<FriendSummary> demo = [];
  final _changes = StreamController<void>.broadcast();

  int codesCreated = 0;
  Object? failLookupWith;

  void _changed() => _changes.add(null);

  void addCode(String code, String uid, String name) {
    codes[code] = FriendCodeInfo(code: code, uid: uid, displayName: name);
    codeOf[uid] = code;
  }

  void putRequest(FriendRequest request) {
    requests[request.id] = request;
    _changed();
  }

  void putFriend(FriendSummary friend) {
    friendData[friend.uid] = friend;
    _changed();
  }

  @override
  Future<String> ensureFriendCode(String uid, String displayName) async {
    final existing = codeOf[uid];
    if (existing != null) {
      codes[existing] = FriendCodeInfo(
        code: existing,
        uid: uid,
        displayName: displayName,
      );
      return existing;
    }
    codesCreated++;
    final code = 'ABC${(234 + codesCreated).toString()}';
    addCode(code, uid, displayName);
    return code;
  }

  @override
  Future<FriendCodeInfo?> lookupCode(String code) async {
    if (failLookupWith != null) throw failLookupWith!;
    return codes[code];
  }

  @override
  Future<FriendRequest?> getRequest(String from, String to) async =>
      requests['${from}_$to'];

  @override
  Future<void> createRequest(FriendRequest request) async {
    requests[request.id] = request;
    _changed();
  }

  @override
  Future<void> acceptRequest(FriendRequest request) async {
    requests[request.id] = FriendRequest(
      from: request.from,
      to: request.to,
      fromName: request.fromName,
      toName: request.toName,
      accepted: true,
    );
    _changed();
  }

  @override
  Future<void> deleteRequest(FriendRequest request) async {
    requests.remove(request.id);
    _changed();
  }

  @override
  Stream<List<FriendRequest>> watchRequests(String uid) async* {
    List<FriendRequest> mine() => [
      for (final r in requests.values)
        if (r.from == uid || r.to == uid) r,
    ];
    yield mine();
    await for (final _ in _changes.stream) {
      yield mine();
    }
  }

  @override
  Stream<FriendSummary?> watchFriend(
    String uid, {
    String fallbackName = '',
  }) async* {
    yield friendData[uid];
    await for (final _ in _changes.stream) {
      yield friendData[uid];
    }
  }

  @override
  Future<List<FriendSummary>> loadDemoFriends() async => demo;

  @override
  Future<void> saveDemoFriends(List<FriendSummary> friends) async {
    demo = friends;
  }
}
