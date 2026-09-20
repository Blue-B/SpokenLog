class RecordingCollection {
  const RecordingCollection({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RecordingCollection.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return RecordingCollection(
      id: json['id']?.toString() ?? 'collection_${now.microsecondsSinceEpoch}',
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : '보관함',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
    );
  }
}
