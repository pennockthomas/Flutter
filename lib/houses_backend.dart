import 'house_models.dart';

/// Storage for houses, so `HousesService` can be tested without Firebase.
/// `FirestoreHousesBackend` is the real one.
abstract class HousesBackend {
  /// The houses [uid] is in, live.
  Stream<List<House>> watchHouses(String uid);

  /// The names of the people in a house, by id, live.
  Stream<Map<String, String>> watchMemberNames(String houseId);

  /// The house's shared swaps, live (only swaps that were ever ticked).
  Stream<List<HouseSwap>> watchSwaps(String houseId);

  /// The house's unlocked branches, live.
  Stream<List<HouseTier>> watchTiers(String houseId);

  /// Invitations waiting for [uid].
  Stream<List<HouseInvite>> watchMyInvites(String uid);

  /// Invitations to a house that haven't been answered yet.
  Stream<List<HouseInvite>> watchHouseInvites(String houseId);

  Future<House> createHouse(String uid, String name);

  Future<void> renameHouse(String houseId, String name);

  Future<void> sendInvite(HouseInvite invite);

  /// Joins the house the invitation is for, then clears the invitation.
  Future<void> acceptInvite(HouseInvite invite, String uid);

  /// Removes an invitation (declined by the invited person, or cancelled).
  Future<void> deleteInvite(HouseInvite invite);

  /// Takes [memberUid] out of the house. Their numbers go first; if they
  /// were the last member the house is deleted.
  Future<void> removeMember(House house, String memberUid);

  /// Ticks or unticks swaps in the house's shared tree.
  Future<void> writeSwaps(String houseId, List<HouseSwap> swaps);

  Future<void> writeTier(String houseId, HouseTier tier);

  /// Shares your name with the house (what the others see next to your swaps).
  Future<void> publishName(String houseId, String uid, String name);
}
