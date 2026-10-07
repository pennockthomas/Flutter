import 'package:cloud_firestore/cloud_firestore.dart';

import 'progress_merge.dart';

/// Where a signed-in account's swap progress lives in the cloud. A small
/// interface so the sync logic can be tested without Firebase.
abstract class ProgressRemote {
  /// Reads the account's stored state, hands it to [merge] (which combines it
  /// with the local data), and stores the merged state if it changed, all as
  /// one atomic step so two devices syncing at once can't overwrite each
  /// other. [merge] may run more than once.
  Future<void> exchange(
    String uid,
    Future<MergeResult> Function(List<ItemStamp> remote) merge,
  );

  /// The account's stored state, now and whenever another device changes it.
  Stream<List<ItemStamp>> watch(String uid);
}

/// `users/{uid}/progress/state`: one document per account holding every swap
/// that's ever been ticked or unticked (see [ItemStamp]). A list rather than
/// a map, because swap ids contain dots, which Firestore treats as field
/// paths in some calls.
class FirestoreProgressRemote implements ProgressRemote {
  static const int schemaVersion = 1;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('progress')
      .doc('state');

  static List<ItemStamp> decode(Map<String, dynamic>? data) {
    final items = data?['items'];
    if (items is! List) return const [];
    final stamps = <ItemStamp>[];
    for (final item in items) {
      try {
        stamps.add(ItemStamp.fromJson(Map<String, dynamic>.from(item as Map)));
      } catch (_) {
        // Skip an entry we can't read rather than failing the whole sync.
      }
    }
    return stamps;
  }

  @override
  Future<void> exchange(
    String uid,
    Future<MergeResult> Function(List<ItemStamp> remote) merge,
  ) {
    final doc = _doc(uid);
    return FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(doc);
      final result = await merge(decode(snapshot.data()));
      if (result.remoteChanged) {
        transaction.set(doc, {
          'schema': schemaVersion,
          'items': [for (final stamp in result.remote) stamp.toJson()],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Stream<List<ItemStamp>> watch(String uid) {
    return _doc(uid)
        .snapshots()
        // Our own writes echo back before the server confirms them; the
        // local data already has those.
        .where((snapshot) => !snapshot.metadata.hasPendingWrites)
        .map((snapshot) => decode(snapshot.data()));
  }
}
