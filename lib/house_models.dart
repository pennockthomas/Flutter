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

/// One swap in a house's shared tree: whether it's done, when that last
/// changed (milliseconds since the epoch) and who changed it. Stored at
/// `houses/{id}/swaps/{swapId}`. Unticking is a change too (`done` false).
class HouseSwap {
  final String id;
  final bool done;
  final int at;
  final String by;

  const HouseSwap({
    required this.id,
    required this.done,
    required this.at,
    required this.by,
  });

  factory HouseSwap.fromData(String id, Map<String, dynamic> data) => HouseSwap(
    id: id,
    done: data['done'] == true,
    at: (data['at'] as num?)?.toInt() ?? 0,
    by: (data['by'] as String?) ?? '',
  );

  Map<String, dynamic> toData() => {'done': done, 'at': at, 'by': by};
}

/// One unlocked (or locked again) branch of a house's shared tree. Stored at
/// `houses/{id}/tiers/{label}`.
class HouseTier {
  final String label;
  final bool open;
  final int at;
  final String by;

  const HouseTier({
    required this.label,
    required this.open,
    required this.at,
    required this.by,
  });

  factory HouseTier.fromData(String label, Map<String, dynamic> data) =>
      HouseTier(
        label: label,
        open: data['open'] == true,
        at: (data['at'] as num?)?.toInt() ?? 0,
        by: (data['by'] as String?) ?? '',
      );

  Map<String, dynamic> toData() => {'open': open, 'at': at, 'by': by};
}

/// One person's share of what the house has done: the swaps they were the
/// last to tick, in total and per day. Counts only; worked out from the
/// house's swaps by `deriveMembers`, never stored.
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
