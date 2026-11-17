/// 工作区初始化类型
enum WorkspaceInitType {
  /// 全新空白工作区
  blank,

  /// 复制当前工作区数据（便签、剪贴板历史与图片）
  copy,

  /// 迁移当前工作区数据（旧目录数据移至新目录）
  migrate,
}

/// 工作区配置档案 (Workspace Profile)
/// 每个工作区对应一个独立的本地存储目录，并可独立绑定云端同步服务。
class WorkspaceProfile {
  final String id;
  final String name;
  final String directoryPath;
  final String? cfWorkerUrl;
  final String? cfAccountId;
  final String? cfApiToken;
  final String? cfD1DatabaseId;
  final String? cfR2BucketName;
  final bool cfD1AutoSync;
  final int cfD1SyncIntervalMinutes;
  final String? vaultId; // 唯一配对 ID，用于校验云端数据库与本地目录是否同源
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkspaceProfile({
    required this.id,
    required this.name,
    required this.directoryPath,
    this.cfWorkerUrl,
    this.cfAccountId,
    this.cfApiToken,
    this.cfD1DatabaseId,
    this.cfR2BucketName,
    this.cfD1AutoSync = false,
    this.cfD1SyncIntervalMinutes = 5,
    this.vaultId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get hasCloudConfig =>
      (cfWorkerUrl != null && cfWorkerUrl!.trim().isNotEmpty) ||
      (cfAccountId != null &&
          cfAccountId!.trim().isNotEmpty &&
          cfApiToken != null &&
          cfApiToken!.trim().isNotEmpty);

  WorkspaceProfile copyWith({
    String? id,
    String? name,
    String? directoryPath,
    String? cfWorkerUrl,
    String? cfAccountId,
    String? cfApiToken,
    String? cfD1DatabaseId,
    String? cfR2BucketName,
    bool? cfD1AutoSync,
    int? cfD1SyncIntervalMinutes,
    String? vaultId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkspaceProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      directoryPath: directoryPath ?? this.directoryPath,
      cfWorkerUrl: cfWorkerUrl ?? this.cfWorkerUrl,
      cfAccountId: cfAccountId ?? this.cfAccountId,
      cfApiToken: cfApiToken ?? this.cfApiToken,
      cfD1DatabaseId: cfD1DatabaseId ?? this.cfD1DatabaseId,
      cfR2BucketName: cfR2BucketName ?? this.cfR2BucketName,
      cfD1AutoSync: cfD1AutoSync ?? this.cfD1AutoSync,
      cfD1SyncIntervalMinutes:
          cfD1SyncIntervalMinutes ?? this.cfD1SyncIntervalMinutes,
      vaultId: vaultId ?? this.vaultId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'directoryPath': directoryPath,
        'cfWorkerUrl': cfWorkerUrl,
        'cfAccountId': cfAccountId,
        'cfApiToken': cfApiToken,
        'cfD1DatabaseId': cfD1DatabaseId,
        'cfR2BucketName': cfR2BucketName,
        'cfD1AutoSync': cfD1AutoSync,
        'cfD1SyncIntervalMinutes': cfD1SyncIntervalMinutes,
        'vaultId': vaultId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WorkspaceProfile.fromJson(Map<String, dynamic> json) {
    return WorkspaceProfile(
      id: json['id'] as String? ?? 'default',
      name: json['name'] as String? ?? '默认工作区',
      directoryPath: json['directoryPath'] as String? ?? '',
      cfWorkerUrl: json['cfWorkerUrl'] as String?,
      cfAccountId: json['cfAccountId'] as String?,
      cfApiToken: json['cfApiToken'] as String?,
      cfD1DatabaseId: json['cfD1DatabaseId'] as String?,
      cfR2BucketName: json['cfR2BucketName'] as String?,
      cfD1AutoSync: json['cfD1AutoSync'] as bool? ?? false,
      cfD1SyncIntervalMinutes: json['cfD1SyncIntervalMinutes'] as int? ?? 5,
      vaultId: json['vaultId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  @override
  String toString() => 'WorkspaceProfile(id: $id, name: $name, path: $directoryPath)';
}
