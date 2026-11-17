import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/note.dart';
import '../models/clipboard_item.dart';

/// 性能测试与同步日志记录
class CfSyncMetrics {
  final int httpStatus;
  final double clientRttMs; // 客户端网络往返耗时
  final double? serverProcessingMs; // 服务器 D1 处理耗时
  final int notesCount;
  final int clipboardCount;
  final int settingsCount;
  final String environment;

  CfSyncMetrics({
    required this.httpStatus,
    required this.clientRttMs,
    this.serverProcessingMs,
    required this.notesCount,
    required this.clipboardCount,
    required this.settingsCount,
    required this.environment,
  });

  @override
  String toString() {
    return '📊 [CF D1 性能数据] 网络往返: ${clientRttMs.toStringAsFixed(1)}ms | D1数据库处理: ${serverProcessingMs?.toStringAsFixed(1) ?? "N/A"}ms | 同步数据量: (笔记:$notesCount, 剪贴板:$clipboardCount, 设置:$settingsCount)';
  }
}

class CfD1SyncService {
  /// Cloudflare Worker 服务端 URL (支持开发环境与线上生产环境)
  final String workerUrl;

  /// 是否开启开发调试日志 (打印性能、延迟、抓包数据)
  final bool isDevMode;

  final http.Client _client = http.Client();
  DateTime _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

  CfD1SyncService({required this.workerUrl, this.isDevMode = kDebugMode});

  String get _cleanBaseUrl {
    var url = workerUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// 1. 检查 Cloudflare Workers + D1 节点连通性与延迟测试
  Future<Map<String, dynamic>> checkHealth() async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$_cleanBaseUrl/health');

    if (isDevMode) {
      debugPrint('🔍 [CF D1 Debug] 开始连通性检查 -> $uri');
    }

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      final rttMs = stopwatch.elapsedMicroseconds / 1000.0;
      final serverTimeHeader = response.headers['x-processing-time-ms'];

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (isDevMode) {
          debugPrint(
            '✅ [CF D1 Health] 节点正常! 客户端网络往返: ${rttMs.toStringAsFixed(1)}ms, Worker处理耗时: ${serverTimeHeader ?? "N/A"}ms, D1数据库延迟: ${data['dbPingLatencyMs']}ms',
          );
        }
        return {
          'success': true,
          'rttMs': rttMs,
          'serverTimeMs': serverTimeHeader,
          'serverData': data,
        };
      } else {
        debugPrint(
          '⚠️ [CF D1 Health] 响应异常 HTTP ${response.statusCode}: ${response.body}',
        );
        return {'success': false, 'status': response.statusCode};
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint(
        '❌ [CF D1 Health] 连接失败 (${stopwatch.elapsedMilliseconds}ms): $e',
      );
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 2. 增量拉取 Cloudflare D1 数据库中的最新更新 (Pull)
  Future<Map<String, dynamic>> pullFromCloudflare({DateTime? since}) async {
    final querySince = (since ?? _lastSyncTime).toUtc().toIso8601String();
    final uri = Uri.parse(
      '$_cleanBaseUrl/api/v1/sync?since=${Uri.encodeComponent(querySince)}',
    );

    final stopwatch = Stopwatch()..start();

    if (isDevMode) {
      debugPrint('🔄 [CF D1 Sync] 开始增量拉取 (Since: $querySince)...');
    }

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      final rttMs = stopwatch.elapsedMicroseconds / 1000.0;
      final serverTimeMs = double.tryParse(
        response.headers['x-processing-time-ms'] ?? '',
      );

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        final data = resJson['data'] ?? {};

        final List<dynamic> notesRaw = data['notes'] ?? [];
        final List<dynamic> clipboardsRaw = data['clipboardItems'] ?? [];
        final List<dynamic> settingsRaw = data['settings'] ?? [];

        final metrics = CfSyncMetrics(
          httpStatus: 200,
          clientRttMs: rttMs,
          serverProcessingMs: serverTimeMs,
          notesCount: notesRaw.length,
          clipboardCount: clipboardsRaw.length,
          settingsCount: settingsRaw.length,
          environment: isDevMode ? 'Dev' : 'Prod',
        );

        if (isDevMode) {
          debugPrint(metrics.toString());
        }

        _lastSyncTime = DateTime.now();

        return {
          'success': true,
          'notes': notesRaw.map((e) => Note.fromJson(e)).toList(),
          'clipboardItems': clipboardsRaw
              .map((e) => ClipboardItem.fromJson(e))
              .toList(),
          'settings': settingsRaw,
          'metrics': metrics,
        };
      } else {
        debugPrint(
          '❌ [CF D1 Sync] 拉取失败 HTTP ${response.statusCode}: ${response.body}',
        );
        return {'success': false, 'status': response.statusCode};
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [CF D1 Sync] 网络异常: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 3. 批量推送本地变更到 Cloudflare D1 数据库 (Push)
  Future<CfSyncMetrics?> pushToCloudflare({
    List<Note>? notes,
    List<ClipboardItem>? clipboardItems,
    List<Map<String, dynamic>>? settings,
  }) async {
    final uri = Uri.parse('$_cleanBaseUrl/api/v1/sync');

    final payload = {
      'notes': (notes ?? []).map((e) => e.toJson()).toList(),
      'clipboardItems': (clipboardItems ?? []).map((e) => e.toJson()).toList(),
      'settings': settings ?? [],
    };

    final payloadString = jsonEncode(payload);
    final payloadBytes = utf8.encode(payloadString).length;

    final stopwatch = Stopwatch()..start();

    if (isDevMode) {
      debugPrint(
        '⬆️ [CF D1 Sync] 开始推送到 D1 (数据包大小: ${(payloadBytes / 1024).toStringAsFixed(2)} KB)...',
      );
    }

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: payloadString,
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      final rttMs = stopwatch.elapsedMicroseconds / 1000.0;
      final serverTimeMs = double.tryParse(
        response.headers['x-processing-time-ms'] ?? '',
      );

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        final metrics = CfSyncMetrics(
          httpStatus: 200,
          clientRttMs: rttMs,
          serverProcessingMs: serverTimeMs,
          notesCount: notes?.length ?? 0,
          clipboardCount: clipboardItems?.length ?? 0,
          settingsCount: settings?.length ?? 0,
          environment: isDevMode ? 'Dev' : 'Prod',
        );

        if (isDevMode) {
          debugPrint('✨ [CF D1 Push Success] ${metrics.toString()}');
          debugPrint('  └─ 服务器处理明细: ${resJson['metrics']}');
        }

        return metrics;
      } else {
        debugPrint(
          '❌ [CF D1 Push Fail] HTTP ${response.statusCode}: ${response.body}',
        );
        return null;
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [CF D1 Push Error] 异常: $e');
      return null;
    }
  }

  /// 4. 文件/图片直传 Cloudflare R2 + D1 数据库记录
  Future<Map<String, dynamic>> uploadFileToR2({
    required File file,
    required String fileKey,
    String? mimeType,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final uri = Uri.parse(
      '$_cleanBaseUrl/api/v1/files/upload',
    ).replace(queryParameters: {'fileKey': fileKey});
    final bytes = await file.readAsBytes();
    final stopwatch = Stopwatch()..start();

    if (isDevMode) {
      debugPrint(
        '🚀 [CF R2 Upload] 开始上传文件: $fileKey (${(bytes.length / 1024).toStringAsFixed(1)} KB)',
      );
    }

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': mimeType ?? 'application/octet-stream',
          'X-File-Key': Uri.encodeComponent(fileKey),
          'X-File-Name': Uri.encodeComponent(fileName),
        },
        body: bytes,
      );

      stopwatch.stop();
      final rttMs = stopwatch.elapsedMicroseconds / 1000.0;

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (isDevMode) {
          debugPrint(
            '🎉 [CF R2 Upload Success] 上传耗时: ${rttMs.toStringAsFixed(1)}ms | 返回: $resJson',
          );
        }
        return {
          'success': true,
          'fileUrl': '$_cleanBaseUrl${resJson['fileUrl']}',
          'rttMs': rttMs,
        };
      } else {
        return {
          'success': false,
          'status': response.statusCode,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [CF R2 Upload Error]: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 4.1 从 Cloudflare Worker 下载文件并写入本地目标路径
  Future<bool> downloadFileFromR2({
    required String fileKey,
    required File targetFile,
  }) async {
    final uri = Uri.parse(
      '$_cleanBaseUrl/api/v1/files/${Uri.encodeComponent(fileKey)}',
    );
    final stopwatch = Stopwatch()..start();

    if (isDevMode) {
      debugPrint('📥 [CF R2 Download] 开始下载文件: $fileKey -> ${targetFile.path}');
    }

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 45));
      stopwatch.stop();
      final rttMs = stopwatch.elapsedMicroseconds / 1000.0;

      if (response.statusCode == 200) {
        if (!targetFile.parent.existsSync()) {
          await targetFile.parent.create(recursive: true);
        }
        await targetFile.writeAsBytes(response.bodyBytes);
        if (isDevMode) {
          debugPrint(
            '🎉 [CF R2 Download Success] 下载完成: $fileKey (${(response.bodyBytes.length / 1024).toStringAsFixed(1)} KB, 耗时 ${rttMs.toStringAsFixed(1)}ms)',
          );
        }
        return true;
      } else {
        debugPrint(
          '⚠️ [CF R2 Download Fail] HTTP ${response.statusCode}: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [CF R2 Download Error] $fileKey: $e');
      return false;
    }
  }

  /// 4.2 从 Cloudflare Worker/R2 彻底删除文件及元数据
  Future<bool> deleteFileFromR2(String fileKey) async {
    final uri = Uri.parse(
      '$_cleanBaseUrl/api/v1/files/${Uri.encodeComponent(fileKey)}',
    );
    final stopwatch = Stopwatch()..start();

    if (isDevMode) {
      debugPrint('🗑️ [CF R2 Delete] 正在请求云端物理删除: $fileKey');
    }

    try {
      final response = await _client
          .delete(uri)
          .timeout(const Duration(seconds: 15));
      stopwatch.stop();
      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        return resJson['success'] == true;
      }
      return false;
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [CF R2 Delete Error] $fileKey: $e');
      return false;
    }
  }

  Future<Map<String, Map<String, dynamic>>> fetchRemoteFilesMetadata() async {
    final endpoints = [
      '$_cleanBaseUrl/api/v1/file-metadata',
      '$_cleanBaseUrl/api/v1/files/metadata',
    ];
    for (final ep in endpoints) {
      try {
        final uri = Uri.parse(ep);
        final response = await http
            .get(uri, headers: {'Content-Type': 'application/json'})
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['files'] is List) {
            final map = <String, Map<String, dynamic>>{};
            for (final item in data['files']) {
              if (item is Map && item['file_key'] != null) {
                map[item['file_key'].toString()] = Map<String, dynamic>.from(
                  item,
                );
              }
            }
            return map;
          }
        }
      } catch (e) {
        debugPrint('fetchRemoteFilesMetadata from $ep error: $e');
      }
    }
    return {};
  }

  /// 5. 测试 Cloudflare 官方 REST API 直通模式 (针对在 GUI 配置自己 Account ID 和 API Token 的用户)
  static Future<Map<String, dynamic>> checkHealthRestApi({
    required String accountId,
    required String apiToken,
    required String d1DatabaseId,
  }) async {
    final cleanAccountId = accountId.trim();
    final cleanToken = apiToken.trim();
    final cleanDbId = d1DatabaseId.trim();

    if (cleanAccountId.isEmpty || cleanToken.isEmpty || cleanDbId.isEmpty) {
      return {
        'success': false,
        'error': '请先完整填写 Account ID、API Token 和 D1 Database ID',
      };
    }

    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/d1/database/$cleanDbId/query',
    );

    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'sql': 'SELECT 1 as ping;'}),
          )
          .timeout(const Duration(seconds: 8));

      stopwatch.stop();
      final rttMs = stopwatch.elapsedMicroseconds / 1000.0;

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        if (resJson['success'] == true) {
          return {
            'success': true,
            'rttMs': rttMs,
            'message':
                'Cloudflare REST API 连接成功！RTT: ${rttMs.toStringAsFixed(1)}ms',
          };
        } else {
          final errors = (resJson['errors'] as List?)
              ?.map((e) => e['message'])
              .join(', ');
          return {'success': false, 'error': errors ?? '查询错误'};
        }
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      stopwatch.stop();
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 6. 使用 REST API 直接将本地所有旧数据（便签、剪贴板历史、设置）推送至 Cloudflare D1 数据库
  static Future<Map<String, dynamic>> pushLocalDataToD1RestApi({
    required String accountId,
    required String apiToken,
    required String d1DatabaseId,
    required List<Note> notes,
    required List<ClipboardItem> clipboardItems,
    List<Map<String, dynamic>>? settings,
    Function(String msg)? onLog,
  }) async {
    final cleanAccountId = accountId.trim();
    final cleanToken = apiToken.trim();
    final cleanDbId = d1DatabaseId.trim();

    if (cleanAccountId.isEmpty || cleanToken.isEmpty || cleanDbId.isEmpty) {
      return {
        'success': false,
        'error': '请先完整填写 Account ID、API Token 和 D1 Database ID',
      };
    }

    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/d1/database/$cleanDbId/query',
    );

    try {
      // 步骤 1：初始化建表结构（如果不存在）
      onLog?.call(
        '正在检查并初始化 D1 数据库表结构 (notes, clipboard_items, app_settings)...',
      );

      final initTablesStatement = {
        'sql': '''
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS clipboard_items (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    app_name TEXT,
    app_icon_path TEXT,
    image_path TEXT,
    image_signature TEXT,
    updated_at TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS file_metadata (
    file_key TEXT PRIMARY KEY,
    file_name TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT,
    r2_key TEXT NOT NULL,
    sha256 TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_files_updated_at ON file_metadata(updated_at);
''',
      };

      final initRes = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(initTablesStatement),
          )
          .timeout(const Duration(seconds: 10));

      if (initRes.statusCode != 200) {
        final errJson = jsonDecode(initRes.body);
        final errList = (errJson['errors'] as List?)
            ?.map((e) => e['message'])
            .join(', ');
        onLog?.call('❌ 建表失败: ${errList ?? initRes.body}');
        return {
          'success': false,
          'error': '初始化数据库结构失败: ${errList ?? initRes.body}',
        };
      }

      onLog?.call('✅ D1 表结构建表/校验完成');

      // 步骤 2：生成 Insert / Upsert 语句
      final List<Map<String, dynamic>> dataStatements = [];

      for (final note in notes) {
        dataStatements.add({
          'sql': '''
INSERT INTO notes (id, title, content, created_at, updated_at, version, is_deleted)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  content = excluded.content,
  created_at = excluded.created_at,
  updated_at = excluded.updated_at,
  version = excluded.version,
  is_deleted = excluded.is_deleted
WHERE excluded.updated_at >= notes.updated_at;
''',
          'params': [
            note.id,
            note.title,
            note.content,
            note.createdAt.toIso8601String(),
            note.updatedAt.toIso8601String(),
            1,
            0,
          ],
        });
      }

      for (final clip in clipboardItems) {
        dataStatements.add({
          'sql': '''
INSERT INTO clipboard_items (id, content, timestamp, is_favorite, app_name, app_icon_path, image_path, image_signature, updated_at, version, is_deleted)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  content = excluded.content,
  timestamp = excluded.timestamp,
  is_favorite = excluded.is_favorite,
  app_name = excluded.app_name,
  app_icon_path = excluded.app_icon_path,
  image_path = excluded.image_path,
  image_signature = excluded.image_signature,
  updated_at = excluded.updated_at,
  version = excluded.version,
  is_deleted = excluded.is_deleted
WHERE excluded.updated_at >= clipboard_items.updated_at;
''',
          'params': [
            clip.id,
            clip.content,
            clip.timestamp.toIso8601String(),
            clip.isFavorite ? 1 : 0,
            clip.appName,
            clip.appIconPath,
            clip.imagePath,
            clip.imageSignature,
            clip.timestamp.toIso8601String(),
            1,
            0,
          ],
        });
      }

      if (settings != null) {
        for (final s in settings) {
          dataStatements.add({
            'sql': '''
INSERT INTO app_settings (key, value, updated_at)
VALUES (?, ?, ?)
ON CONFLICT(key) DO UPDATE SET
  value = excluded.value,
  updated_at = excluded.updated_at
WHERE excluded.updated_at >= app_settings.updated_at;
''',
            'params': [
              s['key'],
              s['value'],
              s['updatedAt'] ?? DateTime.now().toIso8601String(),
            ],
          });
        }
      }

      if (dataStatements.isEmpty) {
        stopwatch.stop();
        onLog?.call('没有本地数据需要推送');
        return {
          'success': true,
          'message': '没有本地数据需要推送',
          'notesCount': 0,
          'clipboardCount': 0,
          'settingsCount': 0,
          'rttMs': stopwatch.elapsedMilliseconds.toDouble(),
        };
      }

      final totalStmts = dataStatements.length;
      onLog?.call('已生成 D1 SQL 语句: 共 $totalStmts 条数据，开始同步写入...');

      // 步骤 3：发送 Query 对象至 Cloudflare D1 REST API (并发池: 5 个并发请求)
      const concurrency = 5;
      var completedCount = 0;

      for (var i = 0; i < totalStmts; i += concurrency) {
        final chunk = dataStatements.sublist(
          i,
          i + concurrency > totalStmts ? totalStmts : i + concurrency,
        );

        final futures = chunk.map((stmtObj) async {
          final response = await http
              .post(
                uri,
                headers: {
                  'Authorization': 'Bearer $cleanToken',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(stmtObj),
              )
              .timeout(const Duration(seconds: 12));

          if (response.statusCode != 200) {
            final errJson = jsonDecode(response.body);
            final errList = (errJson['errors'] as List?)
                ?.map((e) => e['message'])
                .join(', ');
            throw Exception(errList ?? response.body);
          }
        });

        await Future.wait(futures);
        completedCount += chunk.length;

        if (completedCount % 10 == 0 || completedCount == totalStmts) {
          onLog?.call('D1 数据写入进度 [$completedCount/$totalStmts]...');
        }
      }

      stopwatch.stop();
      final totalMs = stopwatch.elapsedMicroseconds / 1000.0;

      onLog?.call('🎉 D1 所有数据写入完成！总网络往返耗时: ${totalMs.toStringAsFixed(1)}ms');

      return {
        'success': true,
        'notesCount': notes.length,
        'clipboardCount': clipboardItems.length,
        'settingsCount': settings?.length ?? 0,
        'rttMs': totalMs,
        'message':
            '云端差异化同步完成！(便签:${notes.length}条, 剪贴板:${clipboardItems.length}条, 耗时:${totalMs.toStringAsFixed(1)}ms)',
      };
    } catch (e) {
      stopwatch.stop();
      final errStr = e.toString();
      String errorMsg = errStr;
      if (errStr.contains('You do not have permission')) {
        errorMsg =
            'D1 权限不足：您的 API Token 缺乏写入/编辑权限。请前往 Cloudflare 网页控制台 ➔ API 令牌，将该 Token 权限升级为「D1: Edit (编辑权限)」。';
        onLog?.call('❌ $errorMsg');
      } else {
        onLog?.call('❌ 推送发生异常: $e');
      }
      return {'success': false, 'error': errorMsg};
    }
  }

  /// 7. 使用 Cloudflare REST API 直接上传文件至 R2 存储桶 (基于同一 API Token)
  static Future<Map<String, dynamic>> uploadFileToR2RestApi({
    required String accountId,
    required String apiToken,
    required String bucketName,
    required String fileKey,
    required File file,
    String? mimeType,
  }) async {
    final cleanAccountId = accountId.trim();
    final cleanToken = apiToken.trim();
    final cleanBucket = bucketName.trim();

    if (cleanAccountId.isEmpty || cleanToken.isEmpty || cleanBucket.isEmpty) {
      return {'success': false, 'error': '请填满 Account ID、API Token 和 R2 存储桶名称'};
    }

    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/r2/buckets/$cleanBucket/objects/${Uri.encodeComponent(fileKey)}',
    );

    try {
      final bytes = await file.readAsBytes();
      final response = await http
          .put(
            uri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': mimeType ?? 'application/octet-stream',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'fileKey': fileKey};
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 通过 D1 REST API 获取云端文件元数据记录 (用于差异性对比)
  static Future<Map<String, Map<String, dynamic>>>
  fetchRemoteFilesMetadataRestApi({
    required String accountId,
    required String apiToken,
    required String d1DatabaseId,
  }) async {
    try {
      final cleanAccountId = accountId.trim();
      final cleanToken = apiToken.trim();
      final cleanDbId = d1DatabaseId.trim();
      final uri = Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/d1/database/$cleanDbId/query',
      );

      final body = {
        'sql':
            'SELECT file_key, file_name, file_size, mime_type, updated_at FROM file_metadata;',
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final results = json['result']?[0]?['results'];
        if (results is List) {
          final map = <String, Map<String, dynamic>>{};
          for (final item in results) {
            if (item is Map && item['file_key'] != null) {
              map[item['file_key'].toString()] = Map<String, dynamic>.from(
                item,
              );
            }
          }
          return map;
        }
      }
    } catch (e) {
      debugPrint('REST API fetchRemoteFilesMetadataRestApi error: $e');
    }
    return {};
  }

  /// 通过 Cloudflare D1 REST API 拉取云端便签与剪贴板数据
  static Future<Map<String, dynamic>> pullFromD1RestApi({
    required String accountId,
    required String apiToken,
    required String d1DatabaseId,
    DateTime? since,
  }) async {
    final cleanAccountId = accountId.trim();
    final cleanToken = apiToken.trim();
    final cleanDbId = d1DatabaseId.trim();

    if (cleanAccountId.isEmpty || cleanToken.isEmpty || cleanDbId.isEmpty) {
      return {
        'success': false,
        'error': '请先完整填写 Account ID、API Token 和 D1 Database ID',
      };
    }

    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/d1/database/$cleanDbId/query',
    );
    final sinceIso = (since ?? DateTime.fromMillisecondsSinceEpoch(0))
        .toUtc()
        .toIso8601String();

    try {
      final body = {
        'sql': '''
SELECT * FROM notes WHERE updated_at > ? ORDER BY updated_at ASC LIMIT 500;
SELECT * FROM clipboard_items WHERE updated_at > ? ORDER BY updated_at ASC LIMIT 500;
''',
        'params': [sinceIso, sinceIso],
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final resJson = jsonDecode(response.body);
        final resultsList = resJson['result'] as List?;
        if (resultsList != null && resultsList.isNotEmpty) {
          final notesRaw = (resultsList[0]['results'] as List?) ?? [];
          final clipboardsRaw = resultsList.length > 1
              ? ((resultsList[1]['results'] as List?) ?? [])
              : [];

          final notes = notesRaw
              .map((e) => Note.fromJson(e as Map<String, dynamic>))
              .toList();
          final clipboardItems = clipboardsRaw
              .map((e) => ClipboardItem.fromJson(e as Map<String, dynamic>))
              .toList();

          return {
            'success': true,
            'notes': notes,
            'clipboardItems': clipboardItems,
          };
        }
      }
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}: ${response.body}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 通过 D1 REST API 记录或更新上传成功的文件元数据
  static Future<bool> recordFileMetadataRestApi({
    required String accountId,
    required String apiToken,
    required String d1DatabaseId,
    required String fileKey,
    required String fileName,
    required int fileSize,
    required String mimeType,
  }) async {
    try {
      final cleanAccountId = accountId.trim();
      final cleanToken = apiToken.trim();
      final cleanDbId = d1DatabaseId.trim();
      final uri = Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/d1/database/$cleanDbId/query',
      );

      final nowIso = DateTime.now().toIso8601String();
      final sql = '''
INSERT INTO file_metadata (file_key, file_name, file_size, mime_type, r2_key, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(file_key) DO UPDATE SET
  file_name = excluded.file_name,
  file_size = excluded.file_size,
  mime_type = excluded.mime_type,
  updated_at = excluded.updated_at;
''';

      final body = {
        'sql': sql,
        'params': [
          fileKey,
          fileName,
          fileSize,
          mimeType,
          fileKey,
          nowIso,
          nowIso,
        ],
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('recordFileMetadataRestApi error: $e');
      return false;
    }
  }

  /// 8. 一键自动化向 Cloudflare 部署 Worker 节点并关联 D1 数据库 (支持全新账号一键初始化)
  static Future<Map<String, dynamic>> deployWorkerAndD1({
    required String accountId,
    required String apiToken,
    String workerName = 'pod-quick-backend',
    String d1Name = 'pod-quick-d1',
    String r2BucketName = 'pod-quick-files-apac',
    Function(String msg)? onLog,
  }) async {
    final cleanAccountId = accountId.trim();
    final cleanToken = apiToken.trim();
    final cleanD1Name = d1Name.trim().isEmpty ? 'pod-quick-d1' : d1Name.trim();
    final cleanBucket = r2BucketName.trim().isEmpty
        ? 'pod-quick-files-apac'
        : r2BucketName.trim();
    final cleanWorker = workerName.trim().isEmpty
        ? 'pod-quick-backend'
        : workerName.trim();

    if (cleanAccountId.isEmpty || cleanToken.isEmpty) {
      return {
        'success': false,
        'error': '进行自动化部署前，请先提供 Account ID 和 API Token',
      };
    }

    onLog?.call('🚀 开始自动化部署 Worker ($cleanWorker) 到 Cloudflare...');

    try {
      // 1. 获取或创建 D1 数据库
      onLog?.call('[1/4] 检查 Cloudflare D1 数据库状态 ($cleanD1Name)...');
      String? d1Uuid;
      String? matchedDbName;

      final listD1Uri = Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/d1/database',
      );
      final listD1Res = await http
          .get(
            listD1Uri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (listD1Res.statusCode == 200) {
        final d1ListJson = jsonDecode(listD1Res.body);
        final resultList = (d1ListJson['result'] as List?) ?? [];
        final target = cleanD1Name.toLowerCase();
        for (final db in resultList) {
          final name = (db['name'] as String? ?? '').toLowerCase();
          final uuid = (db['uuid'] as String? ?? '').toLowerCase();
          if (name == target || uuid == target) {
            d1Uuid = db['uuid'];
            matchedDbName = db['name'] as String?;
            onLog?.call('✅ 发现已有 D1 数据库: ${db['name']} (ID: $d1Uuid)');
            break;
          }
        }
      }

      if (d1Uuid == null &&
          cleanD1Name.contains('-') &&
          cleanD1Name.length >= 32) {
        try {
          final directUri = Uri.parse(
            'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/d1/database/$cleanD1Name',
          );
          final directRes = await http
              .get(
                directUri,
                headers: {
                  'Authorization': 'Bearer $cleanToken',
                  'Content-Type': 'application/json',
                },
              )
              .timeout(const Duration(seconds: 8));
          if (directRes.statusCode == 200) {
            final json = jsonDecode(directRes.body);
            d1Uuid = json['result']?['uuid'] ?? cleanD1Name;
            matchedDbName = json['result']?['name'] ?? cleanD1Name;
            onLog?.call('✅ 确认已有 D1 数据库 UUID: $d1Uuid');
          }
        } catch (_) {}
      }

      if (d1Uuid == null) {
        onLog?.call('➕ 未发现同名 D1 数据库，正在自动创建 $cleanD1Name...');
        final createD1Res = await http
            .post(
              listD1Uri,
              headers: {
                'Authorization': 'Bearer $cleanToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'name': cleanD1Name}),
            )
            .timeout(const Duration(seconds: 12));

        if (createD1Res.statusCode == 200 || createD1Res.statusCode == 201) {
          final createJson = jsonDecode(createD1Res.body);
          d1Uuid = createJson['result']['uuid'];
          matchedDbName = cleanD1Name;
          onLog?.call('🎉 D1 数据库创建成功！(ID: $d1Uuid)');
        } else {
          String errorMsg = createD1Res.body;
          try {
            final errObj = jsonDecode(createD1Res.body);
            if (errObj['errors'] is List &&
                (errObj['errors'] as List).isNotEmpty) {
              final firstErr = errObj['errors'][0];
              final code = firstErr['code'];
              final message = firstErr['message'] ?? '';
              if (code == 10000 ||
                  message.toString().toLowerCase().contains('authentication')) {
                errorMsg =
                    'API 令牌权限不足！请检查令牌权限：必须勾选【D1】（或【Cloudflare D1】）的【编辑/Edit】权限！（D1 是单独项，不叫 Workers D1）';
              } else if (code == 7003) {
                errorMsg =
                    'Account ID 错误或令牌未分配给该账户，请检查 Cloudflare 首页右侧的 Account ID！';
              } else {
                errorMsg = '[$code] $message';
              }
            }
          } catch (_) {}
          onLog?.call('❌ 创建 D1 数据库失败: $errorMsg');
          return {'success': false, 'error': '创建 D1 数据库失败: $errorMsg'};
        }
      }

      // 1.5 确保 Cloudflare R2 存储桶存在并就绪
      bool hasR2Bucket = false;
      String? r2ErrorMessage;
      if (cleanBucket.isNotEmpty) {
        onLog?.call('📁 检查 Cloudflare R2 存储桶 ($cleanBucket)...');
        try {
          // 先尝试 GET 查询该存储桶是否已存在
          final checkBucketUri = Uri.parse(
            'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/r2/buckets/$cleanBucket',
          );
          final checkRes = await http
              .get(
                checkBucketUri,
                headers: {
                  'Authorization': 'Bearer $cleanToken',
                  'Content-Type': 'application/json',
                },
              )
              .timeout(const Duration(seconds: 8));

          if (checkRes.statusCode == 200) {
            hasR2Bucket = true;
            onLog?.call('✅ 发现已有同名 R2 存储桶: $cleanBucket');
          } else {
            // 存储桶不存在，尝试自动创建
            final createBucketUri = Uri.parse(
              'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/r2/buckets',
            );
            final bucketRes = await http
                .post(
                  createBucketUri,
                  headers: {
                    'Authorization': 'Bearer $cleanToken',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'name': cleanBucket,
                    'locationHint': 'apac',
                  }),
                )
                .timeout(const Duration(seconds: 10));

            if (bucketRes.statusCode == 200 || bucketRes.statusCode == 201) {
              hasR2Bucket = true;
              onLog?.call('🎉 R2 存储桶自动创建成功: $cleanBucket');
            } else if (bucketRes.statusCode == 409 ||
                bucketRes.body.contains('already exists') ||
                bucketRes.body.contains('10014')) {
              hasR2Bucket = true;
              onLog?.call('✅ 发现已有同名 R2 存储桶: $cleanBucket');
            } else {
              hasR2Bucket = false;
              String msg = bucketRes.body;
              try {
                final errJson = jsonDecode(bucketRes.body);
                if (errJson['errors'] is List &&
                    (errJson['errors'] as List).isNotEmpty) {
                  final err = errJson['errors'][0];
                  final code = err['code'];
                  final m = err['message'] ?? '';
                  if (code == 10042 ||
                      m.toString().toLowerCase().contains('not enabled') ||
                      m.toString().toLowerCase().contains('subscription')) {
                    msg =
                        'Cloudflare 账户尚未开通激活 R2 对象存储（每月 10GB 免费）。请在 CF 控制台左侧点击「R2」开通！';
                  } else if (code == 10000 ||
                      m.toString().toLowerCase().contains('authentication')) {
                    msg = 'API 令牌缺少【Workers R2 存储 -> 编辑】权限。';
                  } else {
                    msg = '[$code] $m';
                  }
                }
              } catch (_) {}
              r2ErrorMessage = msg;
              onLog?.call('⚠️ R2 存储桶创建跳过: $msg');
              onLog?.call(
                '💡 提示：将先为您完成 Worker 与 D1 数据库上线（便签、剪贴板与设置同步不受任何影响）。如需文件同步，请在 Cloudflare 仪表盘激活 R2 后再次部署。',
              );
            }
          }
        } catch (e) {
          hasR2Bucket = false;
          r2ErrorMessage = e.toString();
          onLog?.call('⚠️ R2 检查异常，跳过 R2 绑定: $e');
        }
      }

      // 2. 获取账号的 workers.dev 子域名
      onLog?.call('[2/4] 获取 Cloudflare Workers 账号子域名...');
      String? subdomain;
      final subUri = Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/workers/subdomain',
      );
      final subRes = await http
          .get(
            subUri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (subRes.statusCode == 200) {
        final subJson = jsonDecode(subRes.body);
        subdomain = subJson['result']?['subdomain'];
      }

      subdomain ??= 'my-worker';
      onLog?.call('✅ Workers 账户子域名: $subdomain');

      // 3. 发布 / 上传 Worker 脚本与 D1 绑定
      onLog?.call('[3/4] 正在编译并发布 Worker 边缘节点代码 ($cleanWorker) 到 Cloudflare...');
      final uploadScriptUri = Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/workers/scripts/$cleanWorker',
      );

      const workerJsCode = '''
export default {
  async fetch(request, env, ctx) {
    const startTime = performance.now();
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Version',
      'Access-Control-Expose-Headers': 'Server-Timing, X-Processing-Time-Ms',
    };
    if (method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
    try {
      let response;
      if (path === '/health') {
        const t0 = performance.now();
        const dbCheck = await env.DB.prepare('SELECT 1 as alive').first();
        const t1 = performance.now();
        response = new Response(JSON.stringify({ status: 'ok', database: dbCheck ? 'connected' : 'error', dbPingLatencyMs: (t1 - t0).toFixed(2) }), { headers: { 'Content-Type': 'application/json' } });
      } else if (path === '/api/v1/sync' && method === 'GET') {
        const since = url.searchParams.get('since') || '1970-01-01T00:00:00.000Z';
        const notesStmt = env.DB.prepare('SELECT * FROM notes WHERE updated_at > ? ORDER BY updated_at ASC LIMIT 500').bind(since);
        const clipboardsStmt = env.DB.prepare('SELECT * FROM clipboard_items WHERE updated_at > ? ORDER BY updated_at ASC LIMIT 500').bind(since);
        const settingsStmt = env.DB.prepare('SELECT * FROM app_settings WHERE updated_at > ?').bind(since);
        const [notesRes, clipboardsRes, settingsRes] = await env.DB.batch([notesStmt, clipboardsStmt, settingsStmt]);
        response = new Response(JSON.stringify({ success: true, since, data: { notes: notesRes.results || [], clipboardItems: clipboardsRes.results || [], settings: settingsRes.results || [] } }), { headers: { 'Content-Type': 'application/json' } });
      } else if (path === '/api/v1/sync' && method === 'POST') {
        const body = await request.json();
        const { notes = [], clipboardItems = [], settings = [] } = body;
        const stmts = [];
        for (const n of notes) {
          stmts.push(env.DB.prepare(`INSERT INTO notes (id, title, content, created_at, updated_at, version, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title=excluded.title, content=excluded.content, created_at=excluded.created_at, updated_at=excluded.updated_at, version=excluded.version, is_deleted=excluded.is_deleted WHERE excluded.updated_at >= notes.updated_at`).bind(n.id, n.title, n.content, n.createdAt || n.created_at, n.updatedAt || n.updated_at, n.version || 1, (n.is_deleted === 1 || n.is_deleted === true || n.is_deleted === '1' || n.isDeleted === 1 || n.isDeleted === true) ? 1 : 0));
        }
        for (const c of clipboardItems) {
          stmts.push(env.DB.prepare(`INSERT INTO clipboard_items (id, content, timestamp, is_favorite, app_name, app_icon_path, image_path, image_signature, updated_at, version, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET content=excluded.content, timestamp=excluded.timestamp, is_favorite=excluded.is_favorite, app_name=excluded.app_name, app_icon_path=excluded.app_icon_path, image_path=excluded.image_path, image_signature=excluded.image_signature, updated_at=excluded.updated_at, version=excluded.version, is_deleted=excluded.is_deleted WHERE excluded.updated_at >= clipboard_items.updated_at`).bind(c.id, c.content, c.timestamp, (c.is_favorite === 1 || c.is_favorite === true || c.isFavorite === 1 || c.isFavorite === true || c.isPinned === 1 || c.isPinned === true) ? 1 : 0, c.appName || c.app_name || null, c.appIconPath || c.app_icon_path || null, c.imagePath || c.image_path || null, c.imageSignature || c.image_signature || null, c.updatedAt || c.updated_at || new Date().toISOString(), c.version || 1, (c.is_deleted === 1 || c.is_deleted === true || c.is_deleted === '1' || c.isDeleted === 1 || c.isDeleted === true) ? 1 : 0));
        }
        for (const s of settings) {
          stmts.push(env.DB.prepare(`INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at WHERE excluded.updated_at >= app_settings.updated_at`).bind(s.key, s.value, s.updatedAt || s.updated_at || new Date().toISOString()));
        }
        if (stmts.length > 0) await env.DB.batch(stmts);
        response = new Response(JSON.stringify({ success: true, processedCount: stmts.length }), { headers: { 'Content-Type': 'application/json' } });
      } else if (path === '/api/v1/files/upload' && method === 'POST') {
        if (!env.FILES_BUCKET) return new Response(JSON.stringify({ error: 'R2 Bucket not configured' }), { status: 500 });
        const contentType = request.headers.get('content-type') || 'application/octet-stream';
        const urlObj = new URL(request.url);
        const queryKey = urlObj.searchParams.get('fileKey') || urlObj.searchParams.get('key');
        const rawFileKey = request.headers.get('x-file-key');
        let fileKey = queryKey || (rawFileKey ? decodeURIComponent(rawFileKey) : `file_\${Date.now()}`);
        const rawFileName = request.headers.get('x-file-name');
        const fileName = rawFileName ? decodeURIComponent(rawFileName) : (fileKey.split('/').pop() || fileKey);
        const arrayBuffer = await request.arrayBuffer();
        await env.FILES_BUCKET.put(fileKey, arrayBuffer, { httpMetadata: { contentType } });
        const nowStr = new Date().toISOString();
        try {
          await env.DB.prepare(`CREATE TABLE IF NOT EXISTS file_metadata (file_key TEXT PRIMARY KEY, file_name TEXT NOT NULL, file_size INTEGER NOT NULL, mime_type TEXT, r2_key TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);`).run();
          await env.DB.prepare(`INSERT INTO file_metadata (file_key, file_name, file_size, mime_type, r2_key, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(file_key) DO UPDATE SET file_name=excluded.file_name, file_size=excluded.file_size, mime_type=excluded.mime_type, updated_at=excluded.updated_at`).bind(fileKey, fileName, arrayBuffer.byteLength, contentType, fileKey, nowStr, nowStr).run();
        } catch (_) {}
        response = new Response(JSON.stringify({ success: true, fileKey, fileUrl: `/api/v1/files/\${encodeURIComponent(fileKey)}` }), { headers: { 'Content-Type': 'application/json' } });
      } else if ((path === '/api/v1/files/metadata' || path === '/api/v1/file-metadata') && method === 'GET') {
        try {
          await env.DB.prepare(`CREATE TABLE IF NOT EXISTS file_metadata (file_key TEXT PRIMARY KEY, file_name TEXT NOT NULL, file_size INTEGER NOT NULL, mime_type TEXT, r2_key TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);`).run();
          const metaRes = await env.DB.prepare('SELECT file_key, file_name, file_size, mime_type, updated_at FROM file_metadata').all();
          response = new Response(JSON.stringify({ success: true, files: metaRes.results || [] }), { headers: { 'Content-Type': 'application/json' } });
        } catch (e) {
          response = new Response(JSON.stringify({ success: true, files: [] }), { headers: { 'Content-Type': 'application/json' } });
        }
      } else if (path.startsWith('/api/v1/files/') && method === 'GET') {
        if (!env.FILES_BUCKET) return new Response(JSON.stringify({ error: 'R2 Bucket not configured' }), { status: 500 });
        const fileKey = decodeURIComponent(path.replace('/api/v1/files/', ''));
        const object = await env.FILES_BUCKET.get(fileKey) || await env.FILES_BUCKET.get(path.replace('/api/v1/files/', ''));
        if (!object) return new Response(JSON.stringify({ error: 'File not found' }), { status: 404 });
        const headers = new Headers();
        object.writeHttpMetadata(headers);
        headers.set('etag', object.httpEtag);
        headers.set('Cache-Control', 'public, max-age=31536000');
        response = new Response(object.body, { headers });
      } else {
        response = new Response(JSON.stringify({ error: 'Endpoint Not Found', path }), { status: 404, headers: { 'Content-Type': 'application/json' } });
      }
      const durationMs = (performance.now() - startTime).toFixed(2);
      const newHeaders = new Headers(response.headers);
      Object.entries(corsHeaders).forEach(([k, v]) => newHeaders.set(k, v));
      newHeaders.set('X-Processing-Time-Ms', durationMs);
      return new Response(response.body, { status: response.status, headers: newHeaders });
    } catch (err) {
      return new Response(JSON.stringify({ error: 'Internal Server Error', message: err.message }), { status: 500, headers: { 'Content-Type': 'application/json', ...corsHeaders } });
    }
  }
};
''';

      final bindingsList = <Map<String, dynamic>>[
        {'name': 'DB', 'type': 'd1', 'id': d1Uuid},
      ];
      if (hasR2Bucket && cleanBucket.isNotEmpty) {
        bindingsList.add({
          'name': 'FILES_BUCKET',
          'type': 'r2_bucket',
          'bucket_name': cleanBucket,
        });
      }

      final metadata = {
        'main_module': 'index.js',
        'compatibility_date': '2024-01-01',
        'bindings': bindingsList,
      };

      final request = http.MultipartRequest('PUT', uploadScriptUri)
        ..headers['Authorization'] = 'Bearer $cleanToken'
        ..files.add(
          http.MultipartFile.fromString(
            'metadata',
            jsonEncode(metadata),
            filename: 'metadata.json',
            contentType: MediaType('application', 'json'),
          ),
        )
        ..files.add(
          http.MultipartFile.fromString(
            'index.js',
            workerJsCode,
            filename: 'index.js',
            contentType: MediaType('application', 'javascript+module'),
          ),
        );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final uploadRes = await http.Response.fromStream(streamedResponse);

      if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) {
        String errorDetail = uploadRes.body;
        bool isAuthError = false;
        try {
          final errJson = jsonDecode(uploadRes.body);
          final errorList = errJson['errors'] as List?;
          if (errorList != null && errorList.isNotEmpty) {
            final firstErr = errorList.first;
            final rawMsg = (firstErr['message'] ?? '').toString();
            if (firstErr['code'] == 10000 || uploadRes.statusCode == 403) {
              isAuthError = true;
              errorDetail =
                  'API 令牌权限不足 (HTTP 403)：当前 API Token 缺少【Workers 脚本: 编辑 (Workers Scripts: Edit)】权限！\n解决办法：请前往 Cloudflare 仪表盘 -> 用户个人资料 -> API 令牌，编辑此令牌并添加「Workers 脚本: 编辑」与「D1: 编辑」权限。';
            } else if (rawMsg.contains('R2 bucket') &&
                rawMsg.contains('not found')) {
              errorDetail =
                  '绑定的 R2 存储桶不存在！\n原因：您的 Cloudflare 账户尚未在控制台开通激活「R2 对象存储」服务（每月提供 10GB 永久免费空间）。\n解决办法：\n1. 请登录 dash.cloudflare.com，在左侧菜单点击「R2」开通激活；\n2. 确保 API 令牌包含【Workers R2 存储 -> 编辑】权限。';
            } else {
              errorDetail = rawMsg.isNotEmpty ? rawMsg : uploadRes.body;
            }
          }
        } catch (_) {}

        onLog?.call(
          '❌ Worker 部署失败 (HTTP ${uploadRes.statusCode}): $errorDetail',
        );
        return {
          'success': false,
          'error': errorDetail,
          'statusCode': uploadRes.statusCode,
          'isAuthError': isAuthError,
        };
      }

      onLog?.call('✅ Worker 脚本发布与 D1 绑定完成');

      // 4. 激活 workers.dev 域名子路由
      onLog?.call('[4/4] 启用 Workers.dev 域名与路由生效 ($cleanWorker)...');
      final enableSubUri = Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/$cleanAccountId/workers/scripts/$cleanWorker/subdomain',
      );
      await http
          .post(
            enableSubUri,
            headers: {
              'Authorization': 'Bearer $cleanToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'enabled': true}),
          )
          .timeout(const Duration(seconds: 8));

      final deployedUrl = 'https://$cleanWorker.$subdomain.workers.dev';
      final bindSummary = hasR2Bucket
          ? '已绑定 D1: ${matchedDbName ?? cleanD1Name} | R2: $cleanBucket'
          : '已绑定 D1: ${matchedDbName ?? cleanD1Name} (未绑定 R2 文件桶)';
      onLog?.call(
        '🎉 恭喜！Worker 代理节点成功部署就绪！\n部署节点域名: $deployedUrl\n$bindSummary',
      );

      return {
        'success': true,
        'workerUrl': deployedUrl,
        'd1DatabaseId': d1Uuid,
        'd1Name': matchedDbName ?? cleanD1Name,
        'r2BucketName': hasR2Bucket ? cleanBucket : null,
        'hasR2Bucket': hasR2Bucket,
        'r2ErrorMessage': r2ErrorMessage,
        'workerName': cleanWorker,
        'message': 'Worker 节点部署成功！$bindSummary',
      };
    } catch (e) {
      onLog?.call('❌ 自动部署发生异常: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
