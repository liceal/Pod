class ClipboardItem {
  final String id;
  final String content;
  final DateTime timestamp;
  final bool isFavorite;
  final String? appName;
  final String? appIconPath;
  final String? imagePath;
  final String? imageSignature;

  ClipboardItem({
    required this.id,
    required this.content,
    required this.timestamp,
    this.isFavorite = false,
    this.appName,
    this.appIconPath,
    this.imagePath,
    this.imageSignature,
  });

  ClipboardItem copyWith({
    String? content,
    DateTime? timestamp,
    bool? isFavorite,
    String? appName,
    String? appIconPath,
    String? imagePath,
    String? imageSignature,
  }) {
    return ClipboardItem(
      id: id,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isFavorite: isFavorite ?? this.isFavorite,
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
      'isPinned': isFavorite,
      'isFavorite': isFavorite,
      'is_favorite': isFavorite ? 1 : 0,
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

    bool fav = false;
    if (json['isFavorite'] is bool) {
      fav = json['isFavorite'] as bool;
    } else if (json['isPinned'] is bool) {
      fav = json['isPinned'] as bool;
    } else if (json['is_favorite'] != null) {
      fav = (json['is_favorite'] == 1 || json['is_favorite'] == true || json['is_favorite'] == '1');
    }

    return ClipboardItem(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      timestamp: ts,
      isFavorite: fav,
      appName: json['appName'] as String? ?? json['app_name'] as String?,
      appIconPath: json['appIconPath'] as String? ?? json['app_icon_path'] as String?,
      imagePath: json['imagePath'] as String? ?? json['image_path'] as String?,
      imageSignature: json['imageSignature'] as String? ?? json['image_signature'] as String?,
    );
  }
}
