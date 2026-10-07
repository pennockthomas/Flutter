import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'house_models.dart';
import 'houses_backend.dart';

/// [HousesBackend] on Cloud Firestore. Layout and permissions are in
/// `firestore.rules` (and tested in `tool/rules_test`):
///
/// - `houses/{id}`: name, memberUids, createdBy
/// - `houses/{id}/members/{uid}`: that member's name
/// - `houses/{id}/swaps/{swapId}` and `tiers/{label}`: the shared tree
/// - `houseInvites/{houseId}_{uid}`: pending invitations
class FirestoreHousesBackend implements HousesBackend {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _house(String id) =>
      _db.collection('houses').doc(id);

  DocumentReference<Map<String, dynamic>> _invite(String id) =>
      _db.collection('houseInvites').doc(id);

  @override
  Stream<List<House>> watchHouses(String uid) {
    return _db
        .collection('houses')
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs) House.fromData(doc.id, doc.data()),
          ]..sort((a, b) => a.id.compareTo(b.id)),
        );
  }

  @override
  Stream<Map<String, String>> watchMemberNames(String houseId) {
    return _house(houseId)
        .collection('members')
        .snapshots()
        .map(
          (snapshot) => {
            for (final doc in snapshot.docs)
              doc.id: (doc.data()['name'] as String?) ?? '',
          },
        );
  }

  @override
  Stream<List<HouseSwap>> watchSwaps(String houseId) {
    return _house(houseId)
        .collection('swaps')
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              HouseSwap.fromData(doc.id, doc.data()),
          ],
        );
  }

  @override
  Stream<List<HouseTier>> watchTiers(String houseId) {
    return _house(houseId)
        .collection('tiers')
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs)
              HouseTier.fromData(doc.id, doc.data()),
          ],
        );
  }

  List<HouseInvite> _decodeInvites(QuerySnapshot<Map<String, dynamic>> s) {
    final invites = <HouseInvite>[];
    for (final doc in s.docs) {
      try {
        invites.add(HouseInvite.fromData(doc.data()));
      } catch (e) {
        debugPrint('Skipping an unreadable house invite ${doc.id}: $e');
      }
    }
    return invites;
  }

  @override
  Stream<List<HouseInvite>> watchMyInvites(String uid) {
    return _db
        .collection('houseInvites')
        .where('to', isEqualTo: uid)
        .snapshots()
        .map(_decodeInvites);
  }

  @override
  Stream<List<HouseInvite>> watchHouseInvites(String houseId) {
    return _db
        .collection('houseInvites')
        .where('houseId', isEqualTo: houseId)
        .snapshots()
        .map(_decodeInvites);
  }

  @override
  Future<House> createHouse(String uid, String name) async {
    final doc = _db.collection('houses').doc();
    await doc.set({
      'name': name,
      'memberUids': [uid],
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return House(id: doc.id, name: name, memberUids: [uid], createdBy: uid);
  }

  @override
  Future<void> renameHouse(String houseId, String name) =>
      _house(houseId).update({'name': name});

  @override
  Future<void> sendInvite(HouseInvite invite) {
    return _invite(
      invite.id,
    ).set({...invite.toData(), 'createdAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> acceptInvite(HouseInvite invite, String uid) async {
    // Joining needs the invitation to exist, so it's cleared afterwards.
    await _house(invite.houseId).update({
      'memberUids': FieldValue.arrayUnion([uid]),
    });
    await _invite(invite.id).delete();
  }

  @override
  Future<void> deleteInvite(HouseInvite invite) => _invite(invite.id).delete();

  @override
  Future<void> removeMember(House house, String memberUid) async {
    // Their numbers go first, while they are still a member.
    await _house(house.id).collection('members').doc(memberUid).delete();
    if (house.memberUids.length <= 1) {
      await _house(house.id).delete();
    } else {
      await _house(house.id).update({
        'memberUids': FieldValue.arrayRemove([memberUid]),
      });
    }
  }

  @override
  Future<void> writeSwaps(String houseId, List<HouseSwap> swaps) async {
    // A batch holds up to 500 writes; a tree has about a hundred swaps.
    final batch = _db.batch();
    final collection = _house(houseId).collection('swaps');
    for (final swap in swaps) {
      batch.set(collection.doc(swap.id), swap.toData());
    }
    await batch.commit();
  }

  @override
  Future<void> writeTier(String houseId, HouseTier tier) {
    return _house(
      houseId,
    ).collection('tiers').doc(tier.label).set(tier.toData());
  }

  @override
  Future<void> publishName(String houseId, String uid, String name) {
    return _house(houseId).collection('members').doc(uid).set({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
