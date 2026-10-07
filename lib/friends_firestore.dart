import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'friends_backend.dart';
import 'friends_models.dart';
import 'friends_service.dart';

/// [FriendsBackend] on Cloud Firestore. The data layout and who may read or
/// write what are in `firestore.rules`:
///
/// - `users/{uid}`: name and `friendCode`
/// - `users/{uid}/progress/summary`: the counts friends see
/// - `friendCodes/{code}`: `{uid, displayName}`, looked up by code only
/// - `friendRequests/{from}_{to}`: pending or accepted
/// - `demoFriends/{id}`: made-up friends for demonstrations
class FirestoreFriendsBackend implements FriendsBackend {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _codeDoc(String code) =>
      _db.collection('friendCodes').doc(code);

  DocumentReference<Map<String, dynamic>> _requestDoc(String id) =>
      _db.collection('friendRequests').doc(id);

  static String _safeName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'EcoSteps friend';
    return trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed;
  }

  String _randomCode() {
    final random = Random.secure();
    return List.generate(
      FriendsService.codeLength,
      (_) =>
          FriendsService.codeAlphabet[random.nextInt(
            FriendsService.codeAlphabet.length,
          )],
    ).join();
  }

  @override
  Future<String> ensureFriendCode(String uid, String displayName) async {
    final name = _safeName(displayName);
    final existing = (await _user(uid).get()).data()?['friendCode'] as String?;
    if (existing != null) {
      // Keep the name next to the code current, and put the code back if it
      // was ever removed.
      final codeDoc = _codeDoc(existing);
      final snapshot = await codeDoc.get();
      if (!snapshot.exists) {
        await codeDoc.set({'uid': uid, 'displayName': name});
      } else if (snapshot.data()?['uid'] == uid &&
          snapshot.data()?['displayName'] != name) {
        await codeDoc.set({'uid': uid, 'displayName': name});
      }
      return existing;
    }

    // A new code: try random ones until one is free (they rarely collide).
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = _randomCode();
      final created = await _db.runTransaction((transaction) async {
        final codeDoc = _codeDoc(code);
        if ((await transaction.get(codeDoc)).exists) return false;
        transaction.set(codeDoc, {'uid': uid, 'displayName': name});
        transaction.set(_user(uid), {
          'friendCode': code,
        }, SetOptions(merge: true));
        return true;
      });
      if (created) return code;
    }
    throw StateError('Could not create a friend code. Try again.');
  }

  @override
  Future<FriendCodeInfo?> lookupCode(String code) async {
    final data = (await _codeDoc(code).get()).data();
    if (data == null || data['uid'] is! String) return null;
    return FriendCodeInfo(
      code: code,
      uid: data['uid'] as String,
      displayName: (data['displayName'] as String?) ?? '',
    );
  }

  @override
  Future<FriendRequest?> getRequest(String from, String to) async {
    final data = (await _requestDoc('${from}_$to').get()).data();
    return data == null ? null : FriendRequest.fromData(data);
  }

  @override
  Future<void> createRequest(FriendRequest request) {
    return _requestDoc(request.id).set({
      ...request.toData(),
      'fromName': _safeName(request.fromName),
      'toName': _safeName(request.toName),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> acceptRequest(FriendRequest request) {
    return _requestDoc(request.id).update({'status': 'accepted'});
  }

  @override
  Future<void> deleteRequest(FriendRequest request) {
    return _requestDoc(request.id).delete();
  }

  List<FriendRequest> _decodeRequests(QuerySnapshot<Map<String, dynamic>> s) {
    final requests = <FriendRequest>[];
    for (final doc in s.docs) {
      try {
        requests.add(FriendRequest.fromData(doc.data()));
      } catch (e) {
        debugPrint('Skipping an unreadable friend request ${doc.id}: $e');
      }
    }
    return requests;
  }

  @override
  Stream<List<FriendRequest>> watchRequests(String uid) {
    late final StreamController<List<FriendRequest>> controller;
    StreamSubscription<Object?>? sentSubscription;
    StreamSubscription<Object?>? receivedSubscription;
    var sent = <FriendRequest>[];
    var received = <FriendRequest>[];
    var haveSent = false;
    var haveReceived = false;

    void emit() {
      if (haveSent && haveReceived) controller.add([...sent, ...received]);
    }

    final requests = _db.collection('friendRequests');
    controller = StreamController<List<FriendRequest>>(
      onListen: () {
        sentSubscription = requests
            .where('from', isEqualTo: uid)
            .snapshots()
            .listen((snapshot) {
              sent = _decodeRequests(snapshot);
              haveSent = true;
              emit();
            }, onError: controller.addError);
        receivedSubscription = requests
            .where('to', isEqualTo: uid)
            .snapshots()
            .listen((snapshot) {
              received = _decodeRequests(snapshot);
              haveReceived = true;
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await sentSubscription?.cancel();
        await receivedSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<FriendSummary?> watchFriend(String uid, {String fallbackName = ''}) {
    late final StreamController<FriendSummary?> controller;
    StreamSubscription<Object?>? profileSubscription;
    StreamSubscription<Object?>? summarySubscription;
    Map<String, dynamic>? profile;
    Map<String, dynamic>? summary;
    var haveProfile = false;
    var haveSummary = false;

    void emit() {
      if (!haveProfile || !haveSummary) return;
      controller.add(
        FriendSummary.fromData(
          uid: uid,
          name: (profile?['displayName'] as String?) ?? fallbackName,
          summary: summary,
        ),
      );
    }

    // Not allowed any more (the friendship was removed): show nothing.
    void lost(Object error) => controller.add(null);

    controller = StreamController<FriendSummary?>(
      onListen: () {
        profileSubscription = _user(uid).snapshots().listen((snapshot) {
          profile = snapshot.data();
          haveProfile = true;
          emit();
        }, onError: lost);
        summarySubscription = _user(uid)
            .collection('progress')
            .doc('summary')
            .snapshots()
            .listen((snapshot) {
              summary = snapshot.data();
              haveSummary = true;
              emit();
            }, onError: lost);
      },
      onCancel: () async {
        await profileSubscription?.cancel();
        await summarySubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<FriendSummary>> loadDemoFriends() async {
    final snapshot = await _db.collection('demoFriends').get();
    final friends = [
      for (final doc in snapshot.docs)
        FriendSummary.fromData(
          uid: doc.id,
          name: (doc.data()['name'] as String?) ?? '',
          summary: doc.data(),
          isDemo: true,
        ),
    ]..sort((a, b) => a.uid.compareTo(b.uid));
    return friends;
  }

  @override
  Future<void> saveDemoFriends(List<FriendSummary> friends) async {
    final collection = _db.collection('demoFriends');
    final batch = _db.batch();
    final keep = {for (final friend in friends) friend.uid};
    for (final doc in (await collection.get()).docs) {
      if (!keep.contains(doc.id)) batch.delete(doc.reference);
    }
    for (final friend in friends) {
      batch.set(collection.doc(friend.uid), friend.toDemoJson());
    }
    await batch.commit();
  }
}
