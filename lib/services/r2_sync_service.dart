import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class R2TestResult {
  final bool success;
  final String message;

  R2TestResult({required this.success, required this.message});
}

class R2SyncResult {
  final bool success;
  final int syncedCount;
  final String message;

  R2SyncResult({
    required this.success,
    this.syncedCount = 0,
    required this.message,
  });
}

class R2ObjectInfo {
  final String key;
  final String etag;
  final int size;
  final DateTime lastModified;

  R2ObjectInfo({
    required this.key,
    required this.etag,
    required this.size,
    required this.lastModified,
  });
}

class R2SyncService {
  final String accountId;
  final String accessKeyId;
  final String secretAccessKey;
  final String bucketName;
  final String? customEndpoint;
  final String region;

  R2SyncService({
    required this.accountId,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.bucketName,
    this.customEndpoint,
    this.region = 'auto',
  });

  String get _host {
    if (customEndpoint != null && customEndpoint!.trim().isNotEmpty) {
      final clean = customEndpoint!.trim().replaceAll(RegExp(r'^https?://'), '');
      return clean.endsWith('/') ? clean.substring(0, clean.length - 1) : clean;
    }
    return '${accountId.trim()}.r2.cloudflarestorage.com';
  }

  String get _baseUrl => 'https://$_host';

  String _encodePath(String pathStr) {
    return pathStr.split('/').map((segment) => Uri.encodeComponent(segment)).join('/');
  }

  /// Sign request using AWS SigV4
  Map<String, String> _buildHeaders({
    required String method,
    required String path,
    Map<String, String>? queryParams,
    List<int>? payloadBytes,
    String contentType = 'application/octet-stream',
  }) {
    final now = DateTime.now().toUtc();
    final amzDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
    final dateStamp = DateFormat('yyyyMMdd').format(now);

    final payload = payloadBytes ?? <int>[];
    final payloadHash = sha256.convert(payload).toString();

    // Canonical Query String
    String canonicalQueryString = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      final sortedKeys = queryParams.keys.toList()..sort();
      canonicalQueryString = sortedKeys
          .map((k) => '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(queryParams[k]!)}')
          .join('&');
    }

    final hostHeader = _host;
    final canonicalHeaders =
        'host:$hostHeader\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    final signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = [
      method.toUpperCase(),
      path,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    // Signing Key Calculation
    final kDate = Hmac(sha256, utf8.encode('AWS4$secretAccessKey')).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode('s3')).bytes;
    final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;

    final signature = Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();
    final authorizationHeader =
        'AWS4-HMAC-SHA256 Credential=$accessKeyId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

    final headers = <String, String>{
      'Host': hostHeader,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization': authorizationHeader,
    };

    if (contentType.isNotEmpty) {
      headers['Content-Type'] = contentType;
    }

    return headers;
  }

  /// Test connection by listing bucket
  Future<R2TestResult> testConnection() async {
    try {
      if (accountId.trim().isEmpty ||
          accessKeyId.trim().isEmpty ||
          secretAccessKey.trim().isEmpty ||
          bucketName.trim().isEmpty) {
        return R2TestResult(
          success: false,
          message: '请填满所有必需的 Cloudflare R2 参数（Account ID、Access Key、Secret Key、Bucket）。',
        );
      }

      final rawPath = '/${bucketName.trim()}';
      final canonicalPath = _encodePath(rawPath);
      final queryParams = {'list-type': '2', 'max-keys': '1'};
      final headers = _buildHeaders(
        method: 'GET',
        path: canonicalPath,
        queryParams: queryParams,
      );

      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          final client = http.Client();
          try {
            final uri = Uri.parse('$_baseUrl$canonicalPath?list-type=2&max-keys=1');
            final response = await client.get(uri, headers: headers).timeout(
              const Duration(seconds: 12),
            );

            if (response.statusCode == 200) {
              return R2TestResult(
                success: true,
                message: '连接成功！凭证有效且已成功连通 Cloudflare R2 存储桶。',
              );
            } else if (response.statusCode == 403) {
              return R2TestResult(
                success: false,
                message: '连接失败 (403 权限拒绝)：请检查 Access Key ID、Secret Key 权限或 Bucket 名称。',
              );
            } else if (response.statusCode == 404) {
              return R2TestResult(
                success: false,
                message: '连接失败 (404 存储桶不存在)：请检查 Bucket 名称及 Account ID 是否正确。',
              );
            } else {
              return R2TestResult(
                success: false,
                message: '连接失败 HTTP ${response.statusCode}: ${response.body}',
              );
            }
          } finally {
            client.close();
          }
        } catch (e) {
          if (attempt == 2) {
            final errStr = e.toString();
            if (errStr.contains('HandshakeException') || errStr.contains('terminated during handshake')) {
              return R2TestResult(
                success: false,
                message: '网络 TLS 握手中断：与 Cloudflare R2 建立加密连接失败。请检查 VPN/代理软件设置或网络连接。',
              );
            }
            return R2TestResult(
              success: false,
              message: '网络异常或连接超时: $e',
            );
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      return R2TestResult(success: false, message: '连接超时，请重试');
    } catch (e) {
      return R2TestResult(
        success: false,
        message: '网络异常: $e',
      );
    }
  }

  /// List remote objects in bucket
  Future<List<R2ObjectInfo>> listRemoteObjects({String prefix = ''}) async {
    final rawPath = '/${bucketName.trim()}';
    final canonicalPath = _encodePath(rawPath);
    final queryParams = <String, String>{'list-type': '2'};
    if (prefix.isNotEmpty) {
      queryParams['prefix'] = prefix;
    }

    final headers = _buildHeaders(
      method: 'GET',
      path: canonicalPath,
      queryParams: queryParams,
    );

    final queryString = queryParams.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final uri = Uri.parse('$_baseUrl$canonicalPath?$queryString');

    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final client = http.Client();
        try {
          final response = await client.get(uri, headers: headers).timeout(
            const Duration(seconds: 15),
          );

          final xmlBody = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (response.statusCode != 200) {
            throw Exception('R2 ListObjects error (${response.statusCode}): $xmlBody');
          }

          return _parseListObjectsXml(xmlBody);
        } finally {
          client.close();
        }
      } catch (e) {
        if (attempt == 2) rethrow;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return [];
  }

  List<R2ObjectInfo> _parseListObjectsXml(String xmlStr) {
    final list = <R2ObjectInfo>[];
    final contentsRegExp = RegExp(r'<Contents>(.*?)</Contents>', dotAll: true);
    final keyRegExp = RegExp(r'<Key>(.*?)</Key>');
    final etagRegExp = RegExp(r'<ETag>(.*?)</ETag>');
    final sizeRegExp = RegExp(r'<Size>(.*?)</Size>');
    final lastModRegExp = RegExp(r'<LastModified>(.*?)</LastModified>');

    for (final match in contentsRegExp.allMatches(xmlStr)) {
      final block = match.group(1) ?? '';
      final keyMatch = keyRegExp.firstMatch(block);
      final etagMatch = etagRegExp.firstMatch(block);
      final sizeMatch = sizeRegExp.firstMatch(block);
      final lastModMatch = lastModRegExp.firstMatch(block);

      if (keyMatch != null) {
        String key = keyMatch.group(1)!;
        key = key
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'");
        final etag = (etagMatch?.group(1) ?? '').replaceAll('&quot;', '').replaceAll('"', '');
        final size = int.tryParse(sizeMatch?.group(1) ?? '0') ?? 0;
        final lastModStr = lastModMatch?.group(1) ?? '';
        final lastMod = DateTime.tryParse(lastModStr) ?? DateTime.fromMillisecondsSinceEpoch(0);

        list.add(R2ObjectInfo(
          key: key,
          etag: etag,
          size: size,
          lastModified: lastMod,
        ));
      }
    }

    return list;
  }

  /// Upload file to R2
  Future<bool> uploadFile(File file, String remoteKey) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    final cleanKey = remoteKey.startsWith('/') ? remoteKey.substring(1) : remoteKey;
    final rawPath = '/${bucketName.trim()}/$cleanKey';
    final canonicalPath = _encodePath(rawPath);

    String contentType = 'application/octet-stream';
    final lowerKey = cleanKey.toLowerCase();
    if (lowerKey.endsWith('.png')) contentType = 'image/png';
    else if (lowerKey.endsWith('.jpg') || lowerKey.endsWith('.jpeg')) contentType = 'image/jpeg';
    else if (lowerKey.endsWith('.json')) contentType = 'application/json';
    else if (lowerKey.endsWith('.txt') || lowerKey.endsWith('.md')) contentType = 'text/plain; charset=utf-8';

    final headers = _buildHeaders(
      method: 'PUT',
      path: canonicalPath,
      payloadBytes: bytes,
      contentType: contentType,
    );

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final client = http.Client();
        try {
          final uri = Uri.parse('$_baseUrl$canonicalPath');
          final response = await client.put(uri, headers: headers, body: bytes).timeout(
            const Duration(seconds: 45),
          );
          if (response.statusCode == 200 || response.statusCode == 201) {
            return true;
          }
        } finally {
          client.close();
        }
      } catch (e) {
        if (attempt == 3) break;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return false;
  }

  /// Download file from R2
  Future<bool> downloadFile(String remoteKey, File localTargetFile) async {
    final cleanKey = remoteKey.startsWith('/') ? remoteKey.substring(1) : remoteKey;
    final rawPath = '/${bucketName.trim()}/$cleanKey';
    final canonicalPath = _encodePath(rawPath);

    final headers = _buildHeaders(
      method: 'GET',
      path: canonicalPath,
    );

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final client = http.Client();
        try {
          final uri = Uri.parse('$_baseUrl$canonicalPath');
          final response = await client.get(uri, headers: headers).timeout(
            const Duration(seconds: 45),
          );

          if (response.statusCode == 200) {
            if (!await localTargetFile.parent.exists()) {
              await localTargetFile.parent.create(recursive: true);
            }
            await localTargetFile.writeAsBytes(response.bodyBytes);
            return true;
          }
        } finally {
          client.close();
        }
      } catch (e) {
        if (attempt == 3) break;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return false;
  }

  /// Perform incremental bidirectional sync of dataDirectory
  Future<R2SyncResult> syncAllData({
    required String dataDirectoryPath,
    void Function(String status, int current, int total)? onProgress,
  }) async {
    try {
      final dir = Directory(dataDirectoryPath);
      if (!await dir.exists()) {
        return R2SyncResult(success: false, message: '本地数据目录不存在: $dataDirectoryPath');
      }

      onProgress?.call('正在连接 R2 获取云端文件列表...', 0, 0);
      final remoteObjects = await listRemoteObjects();
      final remoteMap = <String, R2ObjectInfo>{
        for (final item in remoteObjects) item.key: item,
      };

      onProgress?.call('正在扫描本地数据文件...', 0, 0);
      final localEntities = await dir.list(recursive: true).toList();
      final localFiles = localEntities.whereType<File>().toList();

      final normalizedBase = dataDirectoryPath.replaceAll('\\', '/');
      final localMap = <String, File>{};
      for (final f in localFiles) {
        final normPath = f.path.replaceAll('\\', '/');
        final relPath = normPath.startsWith(normalizedBase)
            ? normPath.substring(normalizedBase.length)
            : normPath;
        final cleanRel = relPath.startsWith('/') ? relPath.substring(1) : relPath;
        if (cleanRel.isEmpty || cleanRel.startsWith('.') || cleanRel.contains('/.')) continue;
        localMap[cleanRel] = f;
      }

      final toUpload = <String, File>{};
      for (final entry in localMap.entries) {
        final relKey = entry.key;
        final localFile = entry.value;
        final stat = await localFile.stat();
        final localMTime = stat.modified.toUtc();
        final remoteObj = remoteMap[relKey];

        if (remoteObj == null || localMTime.isAfter(remoteObj.lastModified.add(const Duration(seconds: 2)))) {
          toUpload[relKey] = localFile;
        }
      }

      final toDownload = <R2ObjectInfo>[];
      for (final remoteObj in remoteObjects) {
        final relKey = remoteObj.key;
        final localFile = localMap[relKey];
        if (localFile == null) {
          toDownload.add(remoteObj);
        } else {
          final stat = await localFile.stat();
          final localMTime = stat.modified.toUtc();
          if (remoteObj.lastModified.isAfter(localMTime.add(const Duration(seconds: 2)))) {
            toDownload.add(remoteObj);
          }
        }
      }

      final totalTasks = toUpload.length + toDownload.length;
      if (totalTasks == 0) {
        onProgress?.call('本地与云端已是最新状态', 0, 0);
        return R2SyncResult(
          success: true,
          syncedCount: 0,
          message: '同步成功！本地与云端已保持最新 (无需要变更的文件)。',
        );
      }

      int processed = 0;
      int syncCount = 0;
      int failCount = 0;

      for (final entry in toUpload.entries) {
        processed++;
        onProgress?.call('正在上传 ($processed/$totalTasks): ${entry.key}', processed, totalTasks);
        try {
          final ok = await uploadFile(entry.value, entry.key);
          if (ok) {
            syncCount++;
          } else {
            failCount++;
          }
        } catch (_) {
          failCount++;
        }
      }

      for (final remoteObj in toDownload) {
        processed++;
        onProgress?.call('正在下载 ($processed/$totalTasks): ${remoteObj.key}', processed, totalTasks);
        final localTarget = localMap[remoteObj.key] ?? File('$dataDirectoryPath/${remoteObj.key}');
        try {
          final ok = await downloadFile(remoteObj.key, localTarget);
          if (ok) {
            syncCount++;
          } else {
            failCount++;
          }
        } catch (_) {
          failCount++;
        }
      }

      if (failCount > 0) {
        onProgress?.call('部分文件同步失败 ($syncCount 成功, $failCount 失败)', totalTasks, totalTasks);
        return R2SyncResult(
          success: false,
          syncedCount: syncCount,
          message: '部分文件同步失败 ($syncCount 个已同步, $failCount 个失败)。建议重新尝试或检查网络连接。',
        );
      }

      onProgress?.call('同步成功！增量处理了 $syncCount 个文件', totalTasks, totalTasks);
      return R2SyncResult(
        success: true,
        syncedCount: syncCount,
        message: '同步成功！增量处理了 $syncCount 个文件。',
      );
    } catch (e) {
      onProgress?.call('同步发生异常: $e', 0, 0);
      return R2SyncResult(
        success: false,
        message: '同步异常: $e',
      );
    }
  }
}
