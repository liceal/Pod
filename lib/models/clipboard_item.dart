class ClipboardItem {
  final String id;
  final String content;
  final DateTime timestamp;
  final DateTime updatedAt;
  final bool isFavorite;
  final bool isDeleted;
  final String? appName;
  final String? appIconPath;
  final String? imagePath;
  final String? imageSignature;

  ClipboardItem({
    required this.id,
    required this.content,
    required this.timestamp,
    DateTime? updatedAt,
    this.isFavorite = false,
    this.isDeleted = false,
    this.appName,
    this.appIconPath,
    this.imagePath,
    this.imageSignature,
  }) : updatedAt = updatedAt ?? timestamp;

  ClipboardItem copyWith({
    String? content,
    DateTime? timestamp,
    DateTime? updatedAt,
    bool? isFavorite,
    bool? isDeleted,
    String? appName,
    String? appIconPath,
    String? imagePath,
    String? imageSignature,
  }) {
    return ClipboardItem(
      id: id,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      isDeleted: isDeleted ?? this.isDeleted,
      appName: appName ?? this.appName,
      appIconPath: appIconPath ?? this.appIconPath,
      imagePath: imagePath ?? this.imagePath,
      imageSignature: imageSignature ?? this.imageSignature,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'isPinned': isFavorite,
      'isFavorite': isFavorite,
      'is_favorite': isFavorite ? 1 : 0,
      'isDeleted': isDeleted,
      'is_deleted': isDeleted ? 1 : 0,
      'appName': appName,
      'app_name': appName,
      'appIconPath': appIconPath,
      'app_icon_path': appIconPath,
      'imagePath': imagePath,
      'image_path': imagePath,
      'imageSignature': imageSignature,
      'image_signature': imageSignature,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    final timeStr = json['timestamp'] as String? ?? json['updated_at'] as String?;
    final ts = timeStr != null ? (DateTime.tryParse(timeStr) ?? DateTime.now()) : DateTime.now();

    final updStr = json['updatedAt'] as String? ?? json['updated_at'] as String?;
    final upd = updStr != null ? (DateTime.tryParse(updStr) ?? ts) : ts;

    bool fav = false;
    if (json['isFavorite'] is bool) {
      fav = json['isFavorite'] as bool;
    } else if (json['isPinned'] is bool) {
      fav = json['isPinned'] as bool;
    } else if (json['is_favorite'] != null) {
      fav = (json['is_favorite'] == 1 || json['is_favorite'] == true || json['is_favorite'] == '1');
    }

    bool del = false;
    if (json['isDeleted'] is bool) {
      del = json['isDeleted'] as bool;
    } else if (json['is_deleted'] != null) {
      del = (json['is_deleted'] == 1 || json['is_deleted'] == true || json['is_deleted'] == '1');
    }

    return ClipboardItem(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      timestamp: ts,
      updatedAt: upd,
      isFavorite: fav,
      isDeleted: del,
      appName: json['appName'] as String? ?? json['app_name'] as String?,
      appIconPath: json['appIconPath'] as String? ?? json['app_icon_path'] as String?,
      imagePath: json['imagePath'] as String? ?? json['image_path'] as String?,
      imageSignature: json['imageSignature'] as String? ?? json['image_signature'] as String?,
    );
  }
}
