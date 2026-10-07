import 'friends_models.dart';
import 'house_models.dart';
import 'houses_backend.dart';

/// Why a house action wasn't done.
enum HouseProblem {
  invalidName,
  houseFull,
  alreadyInHouse,
  alreadyInvited,
  tooManyHouses,
}

class HouseException implements Exception {
  final HouseProblem problem;

  const HouseException(this.problem);

  @override
  String toString() => 'HouseException($problem)';
}

/// A plain sentence for something that went wrong with a house.
String describeHouseError(Object error) {
  if (error is HouseException) {
    switch (error.problem) {
      case HouseProblem.invalidName:
        return 'A house name needs 1 to ${House.maxNameLength} characters.';
      case HouseProblem.houseFull:
        return 'This house is full (${House.maxMembers} people).';
      case HouseProblem.alreadyInHouse:
        return 'They are already in this house.';
      case HouseProblem.alreadyInvited:
        return 'You already invited them.';
      case HouseProblem.tooManyHouses:
        return 'You can be in up to ${HousesService.maxHouses} houses.';
    }
  }
  return "That didn't work. Check your connection and try again.";
}

/// The rules of houses: names, who can be invited, joining and leaving. The
/// storage is behind [HousesBackend].
class HousesService {
  HousesService(this.backend);

  final HousesBackend backend;

  /// How many houses one person can be in.
  static const int maxHouses = 5;

  Stream<List<House>> watchHouses(String uid) => backend.watchHouses(uid);

  Stream<List<HouseMember>> watchMemberStats(String houseId) =>
      backend.watchMemberStats(houseId);

  Stream<List<HouseInvite>> watchMyInvites(String uid) =>
      backend.watchMyInvites(uid);

  Stream<List<HouseInvite>> watchHouseInvites(String houseId) =>
      backend.watchHouseInvites(houseId);

  /// A new house with just you in it, named "House" until you rename it.
  Future<House> createHouse(String uid, {String? name}) async {
    final cleaned = House.cleanName(name ?? House.defaultName);
    if (cleaned == null) throw const HouseException(HouseProblem.invalidName);
    return await backend.createHouse(uid, cleaned);
  }

  Future<void> rename(House house, String rawName) async {
    final cleaned = House.cleanName(rawName);
    if (cleaned == null) throw const HouseException(HouseProblem.invalidName);
    await backend.renameHouse(house.id, cleaned);
  }

  /// Which of [friends] (the other person's id and name, for each accepted
  /// friendship) can still be invited to [house]: not in it, not invited.
  static List<({String uid, String name})> invitableFriends({
    required House house,
    required List<({String uid, String name})> friends,
    required List<HouseInvite> pendingInvites,
  }) {
    final invited = {for (final invite in pendingInvites) invite.to};
    return [
      for (final friend in friends)
        if (!house.hasMember(friend.uid) && !invited.contains(friend.uid))
          friend,
    ];
  }

  /// The accepted friends of [me], from the friendship requests.
  static List<({String uid, String name})> friendsOf(
    String me,
    List<FriendRequest> requests,
  ) => [
    for (final request in requests)
      if (request.accepted)
        (uid: request.otherUid(me), name: request.otherName(me)),
  ];

  Future<void> invite({
    required House house,
    required String fromUid,
    required String fromName,
    required String friendUid,
    List<HouseInvite> pendingInvites = const [],
  }) async {
    if (house.hasMember(friendUid)) {
      throw const HouseException(HouseProblem.alreadyInHouse);
    }
    if (pendingInvites.any((invite) => invite.to == friendUid)) {
      throw const HouseException(HouseProblem.alreadyInvited);
    }
    if (house.isFull) throw const HouseException(HouseProblem.houseFull);
    await backend.sendInvite(
      HouseInvite(
        houseId: house.id,
        houseName: house.name,
        from: fromUid,
        fromName: fromName,
        to: friendUid,
      ),
    );
  }

  Future<void> accept(HouseInvite invite, String uid) =>
      backend.acceptInvite(invite, uid);

  /// Declines an invitation, or cancels one you sent.
  Future<void> dropInvite(HouseInvite invite) => backend.deleteInvite(invite);

  Future<void> leave(House house, String uid) =>
      backend.removeMember(house, uid);

  /// Any member can remove another (everyone in a house is equal).
  Future<void> removeMember(House house, String memberUid) =>
      backend.removeMember(house, memberUid);

  Future<void> publishStats(String houseId, String uid, HouseMember stats) =>
      backend.publishStats(houseId, uid, stats);
}
