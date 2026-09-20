class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  Note copyWith({
    String? title,
    String? content,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    final createdStr = json['createdAt'] as String? ?? json['created_at'] as String?;
    final updatedStr = json['updatedAt'] as String? ?? json['updated_at'] as String?;
    final created = createdStr != null ? (DateTime.tryParse(createdStr) ?? DateTime.now()) : DateTime.now();
    final updated = updatedStr != null ? (DateTime.tryParse(updatedStr) ?? created) : created;

    bool deleted = false;
    if (json['is_deleted'] != null) {
      deleted = (json['is_deleted'] == 1 || json['is_deleted'] == true || json['is_deleted'] == '1');
    } else if (json['isDeleted'] != null) {
      deleted = (json['isDeleted'] == true || json['isDeleted'] == 1);
    }

    return Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: created,
      updatedAt: updated,
      isDeleted: deleted,
    );
  }
}

