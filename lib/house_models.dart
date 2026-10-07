/// A house: a small group of people (max [maxMembers]) who can see each
/// other's swap counts. Stored at `houses/{id}`.
class House {
  static const int maxMembers = 8;
  static const int maxNameLength = 40;
  static const String defaultName = 'House';

  final String id;
  final String name;
  final List<String> memberUids;
  final String createdBy;

  const House({
    required this.id,
    required this.name,
    required this.memberUids,
    required this.createdBy,
  });

  bool hasMember(String uid) => memberUids.contains(uid);
  bool get isFull => memberUids.length >= maxMembers;

  factory House.fromData(String id, Map<String, dynamic> data) => House(
    id: id,
    name: (data['name'] as String?) ?? defaultName,
    memberUids: [
      for (final uid in (data['memberUids'] as List<dynamic>? ?? const []))
        if (uid is String) uid,
    ],
    createdBy: (data['createdBy'] as String?) ?? '',
  );

  /// The name as it would be saved (trimmed, spaces tidied), or null if it
  /// isn't acceptable (empty or longer than [maxNameLength]).
  static String? cleanName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty || cleaned.length > maxNameLength) return null;
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(cleaned)) return null;
    return cleaned;
  }
}

/// One member's shared numbers within a house: totals and how many swaps
/// they ticked on each day. Counts only, never which swaps. Stored at
/// `houses/{id}/members/{uid}` and written by that member.
class HouseMember {
  final String uid;
  final String name;
  final int completed;
  final int total;

  /// Swaps ticked per day, keyed `yyyy-MM-dd`.
  final Map<String, int> days;

  const HouseMember({
    required this.uid,
    required this.name,
    required this.completed,
    required this.total,
    this.days = const {},
  });

  double get progress => total == 0 ? 0 : completed / total;

  String get initials {
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String first(String word) =>
        String.fromCharCode(word.runes.first).toUpperCase();
    return parts.length == 1
        ? first(parts.first)
        : first(parts.first) + first(parts.last);
  }

  factory HouseMember.fromData(String uid, Map<String, dynamic>? data) {
    int count(Object? value) =>
        (value is num && value >= 0) ? value.toInt() : 0;
    final days = <String, int>{};
    final raw = data?['days'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) {
          final n = count(value);
          if (n > 0) days[key] = n;
        }
      });
    }
    final name = (data?['name'] as String?) ?? '';
    return HouseMember(
      uid: uid,
      name: name.isEmpty ? 'EcoSteps friend' : name,
      completed: count(data?['completed']),
      total: count(data?['total']),
      days: days,
    );
  }

  Map<String, dynamic> toData() => {
    'name': name,
    'completed': completed,
    'total': total,
    'days': days,
  };
}

/// An invitation to join a house, stored at `houseInvites/{houseId}_{to}`.
class HouseInvite {
  final String houseId;
  final String houseName;
  final String from;
  final String fromName;
  final String to;

  const HouseInvite({
    required this.houseId,
    required this.houseName,
    required this.from,
    required this.fromName,
    required this.to,
  });

  String get id => '${houseId}_$to';

  factory HouseInvite.fromData(Map<String, dynamic> data) => HouseInvite(
    houseId: data['houseId'] as String,
    houseName: (data['houseName'] as String?) ?? House.defaultName,
    from: data['from'] as String,
    fromName: (data['fromName'] as String?) ?? '',
    to: data['to'] as String,
  );

  Map<String, dynamic> toData() => {
    'houseId': houseId,
    'houseName': houseName,
    'from': from,
    'fromName': fromName,
    'to': to,
    'status': 'pending',
  };
}
