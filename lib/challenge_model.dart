class Challenge {
  final String label;
  final String description;
  final List<String> unlocks;

  const Challenge({
    required this.label,
    required this.description,
    required this.unlocks,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      label: json['id'] as String,
      description: json['description'] as String,
      unlocks: List<String>.from(json['unlocks'] as List),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': label, 'description': description, 'unlocks': unlocks};
  }
}
