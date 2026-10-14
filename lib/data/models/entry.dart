enum EntryStatus {
  none('none', 'None'),
  reading('reading', 'Reading'),
  completed('completed', 'Completed'),
  planned('planned', 'Planned'),
  dropped('dropped', 'Dropped');

  const EntryStatus(this.value, this.label);

  final String value;
  final String label;

  static EntryStatus fromCsv(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return EntryStatus.none;
    for (final status in EntryStatus.values) {
      if (status.value == normalized) return status;
    }
    return EntryStatus.none;
  }

  static bool isValidCsv(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return EntryStatus.values.any((status) => status.value == normalized);
  }
}

class Entry {
  const Entry({
    required this.id,
    required this.title,
    this.artist = '',
    this.status = EntryStatus.none,
    this.rating = 0,
    this.progress = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String artist;
  final EntryStatus status;
  final int rating;
  final String progress;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Entry copyWith({
    int? id,
    String? title,
    String? artist,
    EntryStatus? status,
    int? rating,
    String? progress,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Entry(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      progress: progress ?? this.progress,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toDb() => <String, Object?>{
        'id': id,
        'title': title,
        'artist': artist,
        'status': status.value,
        'rating': rating,
        'progress': progress,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Entry.fromDb(Map<String, Object?> row) => Entry(
        id: row['id']! as int,
        title: row['title']! as String,
        artist: (row['artist'] as String?) ?? '',
        status: EntryStatus.fromCsv((row['status'] as String?) ?? ''),
        rating: (row['rating'] as int?) ?? 0,
        progress: (row['progress'] as String?) ?? '',
        notes: (row['notes'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((row['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((row['updated_at'] as int?) ?? 0),
      );

  Map<String, Object?> toSnapshot() => <String, Object?>{
        'id': id,
        'title': title,
        'artist': artist,
        'status': status.value,
        'rating': rating,
        'progress': progress,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Entry.fromSnapshot(Map<String, Object?> json) => Entry(
        id: (json['id'] as num).toInt(),
        title: json['title']! as String,
        artist: (json['artist'] as String?) ?? '',
        status: EntryStatus.fromCsv((json['status'] as String?) ?? ''),
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as String?) ?? '',
        notes: (json['notes'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch((json['created_at'] as num?)?.toInt() ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((json['updated_at'] as num?)?.toInt() ?? 0),
      );
}

class EntryDraft {
  const EntryDraft({
    required this.title,
    this.artist = '',
    this.status = EntryStatus.none,
    this.rating = 0,
    this.progress = '',
    this.notes = '',
  });

  final String title;
  final String artist;
  final EntryStatus status;
  final int rating;
  final String progress;
  final String notes;
}
