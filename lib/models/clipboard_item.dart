class ClipboardItem {
  final String id;
  final String content;
  final DateTime timestamp;
  final bool isFavorite;
  final String? appName;
  final String? appIconPath;

  ClipboardItem({
    required this.id,
    required this.content,
    required this.timestamp,
    this.isFavorite = false,
    this.appName,
    this.appIconPath,
  });

  ClipboardItem copyWith({
    String? content,
    DateTime? timestamp,
    bool? isFavorite,
    String? appName,
    String? appIconPath,
  }) {
    return ClipboardItem(
      id: id,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isFavorite: isFavorite ?? this.isFavorite,
      appName: appName ?? this.appName,
      appIconPath: appIconPath ?? this.appIconPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isPinned': isFavorite,
      'appName': appName,
      'appIconPath': appIconPath,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isFavorite: json['isPinned'] as bool? ?? json['isFavorite'] as bool? ?? false,
      appName: json['appName'] as String?,
      appIconPath: json['appIconPath'] as String?,
    );
  }
}
