import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/localization.dart';
import '../models/app_settings.dart';
import 'r2_sync_service.dart';

class AppVersionInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String windowsUrl;
  final String macUrl;
  final String? macArmUrl;
  final String? macIntelUrl;
  final String? htmlUrl;

  AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.windowsUrl,
    required this.macUrl,
    this.macArmUrl,
    this.macIntelUrl,
    this.htmlUrl,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version'] as String? ?? '1.0.0',
      buildNumber: json['buildNumber'] as int? ?? 1,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      windowsUrl: json['windowsUrl'] as String? ?? '',
      macUrl: json['macUrl'] as String? ?? '',
      macArmUrl: json['macArmUrl'] as String?,
      macIntelUrl: json['macIntelUrl'] as String?,
      htmlUrl: json['htmlUrl'] as String?,
    );
  }
}

class UpdateService {
  static const String githubOwner = 'liceal';
  static const String githubRepo = 'Pod';

  static String _currentVersion = '1.1.3';
  static String get currentVersion => _currentVersion;
  static const int currentBuildNumber = 1;

  // 全局独立持久化下载状态（脱离弹窗生命周期，窗口收起/快捷键藏起时后台不间断下载）
  static bool isDownloading = false;
  static double downloadProgress = 0.0;
  static String downloadStatusText = '';
  static bool hasError = false;
  static AppVersionInfo? pendingUpdateInfo;
  static final ValueNotifier<int> stateNotifier = ValueNotifier<int>(0);

  static void _notify() {
    stateNotifier.value++;
  }

  /// 加载打包内置的 release_info.json 获取当前软件版本的正式版本号
  static Future<void> loadLocalVersion() async {
    try {
      final jsonStr = await rootBundle.loadString('release_info.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (json['version'] != null && (json['version'] as String).isNotEmpty) {
        _currentVersion = (json['version'] as String).replaceFirst(RegExp(r'^[vV]'), '');
      }
    } catch (e) {
      debugPrint('读取内置 release_info.json 失败: $e');
    }
  }

  /// 检测当前 macOS 是否为 Apple Silicon (ARM64)
  static Future<bool> _isAppleSiliconMac() async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await Process.run('uname', ['-m']);
      final arch = res.stdout.toString().trim().toLowerCase();
      if (arch.contains('arm64') || arch.contains('aarch64')) {
        return true;
      }
    } catch (_) {}
    return Platform.version.toLowerCase().contains('arm64');
  }

  static R2SyncService? getSyncService([AppSettings? settings]) {
    if (settings == null) return null;
    final accountId = settings.r2AccountId?.trim() ?? settings.cfAccountId?.trim() ?? '';
    final accessKeyId = settings.r2AccessKeyId?.trim() ?? '';
    final secretAccessKey = settings.r2SecretAccessKey?.trim() ?? '';
    final bucketName = settings.r2BucketName?.trim() ?? settings.cfR2BucketName?.trim() ?? '';
    if (accountId.isEmpty || accessKeyId.isEmpty || secretAccessKey.isEmpty || bucketName.isEmpty) {
      return null;
    }
    return R2SyncService(
      accountId: accountId,
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      bucketName: bucketName,
      customEndpoint: settings.r2CustomEndpoint,
    );
  }

  /// 检查是否有新版本（优先通过 GitHub Releases 官方公开仓库检查，回退至 R2）
  static Future<AppVersionInfo?> checkUpdate([AppSettings? settings]) async {
    // 1. 优先从 GitHub Public Repository Releases 检查最新版本
    try {
      final ghInfo = await _checkGitHubRelease();
      if (ghInfo != null) {
        return ghInfo;
      }
    } catch (e) {
      debugPrint('GitHub Release 检查更新异常: $e');
    }

    // 2. 备选回退：如果配置了私有 R2 存储桶，尝试从 R2 检查
    final syncService = getSyncService(settings);
    if (syncService == null) return null;
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/podquick_release_info.json');
      final hasReleaseInfo = await syncService.downloadFile('release_info.json', tempFile);

      if (hasReleaseInfo && await tempFile.exists()) {
        final bytes = await tempFile.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        final json = jsonDecode(content) as Map<String, dynamic>;
        final latestVersion = (json['version'] as String? ?? '1.0.0').replaceFirst(RegExp(r'^[vV]'), '');
        final releaseNotes = json['releaseNotes'] as String? ?? '';
        final winUrl = json['windowsUrl'] as String? ?? 'PodQuick_Setup.exe';
        final macArm = json['macArmUrl'] as String? ?? 'PodQuick-arm.dmg';
        final macX86 = json['macX86Url'] as String? ?? 'PodQuick-x86.dmg';
        final isArm = await _isAppleSiliconMac();
        final rawMacUrl = json['macUrl'] as String? ?? '';
        final macUrl = isArm
            ? (macArm.isNotEmpty ? macArm : rawMacUrl)
            : (macX86.isNotEmpty ? macX86 : rawMacUrl);

        if (_isHigherVersion(latestVersion, currentVersion)) {
          return AppVersionInfo(
            version: latestVersion,
            buildNumber: 2,
            releaseNotes: releaseNotes.isNotEmpty
                ? releaseNotes
                : '修复已知问题与性能优化。',
            windowsUrl: winUrl.isNotEmpty ? winUrl : 'PodQuick_Setup.exe',
            macUrl: macUrl.isNotEmpty ? macUrl : 'PodQuick.dmg',
          );
        }
      }

      final remoteFile = Platform.isWindows ? 'PodQuick_Setup.exe' : 'PodQuick.dmg';
      final remoteInfo = await syncService.getObjectInfo(remoteFile);

      if (remoteInfo != null) {
        final currentExePath = Platform.resolvedExecutable;
        final currentExe = File(currentExePath);
        final localLastModified = currentExe.existsSync()
            ? await currentExe.lastModified()
            : DateTime.fromMillisecondsSinceEpoch(0);

        if (remoteInfo.lastModified.isAfter(localLastModified.add(const Duration(minutes: 1)))) {
          final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(remoteInfo.lastModified.toLocal());
          final sizeMB = (remoteInfo.size / (1024 * 1024)).toStringAsFixed(1);
          return AppVersionInfo(
            version: '云端最新安装包 ($dateStr)',
            buildNumber: remoteInfo.lastModified.millisecondsSinceEpoch,
            releaseNotes: '检测到线上发布了最新版本的标准安装包！\n• 发布时间: $dateStr\n• 文件大小: $sizeMB MB',
            windowsUrl: 'PodQuick_Setup.exe',
            macUrl: 'PodQuick.dmg',
          );
        }
      }
    } catch (e) {
      debugPrint('R2 检查更新失败: $e');
    }
    return null;
  }

  /// 查询 GitHub Releases Latest API
  static Future<AppVersionInfo?> _checkGitHubRelease() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest');
      final req = await client.getUrl(uri);
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'PodQuick-Updater');
      final res = await req.close();
      if (res.statusCode != 200) return null;

      final bodyStr = await res.transform(utf8.decoder).join();
      final data = jsonDecode(bodyStr) as Map<String, dynamic>;

      final rawTag = (data['tag_name'] as String? ?? '').trim();
      if (rawTag.isEmpty) return null;
      final latestVersion = rawTag.replaceFirst(RegExp(r'^[vV]'), '');

      if (!_isHigherVersion(latestVersion, currentVersion)) {
        return null;
      }

      final releaseNotes = (data['body'] as String? ?? '').trim();
      final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$githubOwner/$githubRepo/releases';
      final assets = (data['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      String winUrl = '';
      String macArmUrl = '';
      String macIntelUrl = '';
      String macFallbackUrl = '';

      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final downloadUrl = asset['browser_download_url'] as String? ?? '';
        if (downloadUrl.isEmpty) continue;

        if (name.endsWith('.exe')) {
          if (name.contains('setup') || winUrl.isEmpty) {
            winUrl = downloadUrl;
          }
        } else if (name.endsWith('.dmg')) {
          if (name.contains('applesilicon') || name.contains('arm64') || name.contains('aarch64') || name.contains('-arm') || name.contains('_arm')) {
            macArmUrl = downloadUrl;
          } else if (name.contains('intel') || name.contains('x86_64') || name.contains('x64') || name.contains('x86')) {
            macIntelUrl = downloadUrl;
          } else {
            macFallbackUrl = downloadUrl;
          }
        }
      }

      final isArmMac = await _isAppleSiliconMac();
      final resolvedMacUrl = isArmMac
          ? (macArmUrl.isNotEmpty ? macArmUrl : (macFallbackUrl.isNotEmpty ? macFallbackUrl : htmlUrl))
          : (macIntelUrl.isNotEmpty ? macIntelUrl : (macFallbackUrl.isNotEmpty ? macFallbackUrl : htmlUrl));

      return AppVersionInfo(
        version: latestVersion,
        buildNumber: 2,
        releaseNotes: releaseNotes.isNotEmpty ? releaseNotes : '修复已知问题与性能优化。',
        windowsUrl: winUrl.isNotEmpty ? winUrl : htmlUrl,
        macUrl: resolvedMacUrl,
        macArmUrl: macArmUrl.isNotEmpty ? macArmUrl : null,
        macIntelUrl: macIntelUrl.isNotEmpty ? macIntelUrl : null,
        htmlUrl: htmlUrl,
      );
    } finally {
      client.close();
    }
  }

  /// 比较版本号大小 (如 1.1.1 > 1.1.0)
  static bool _isHigherVersion(String latest, String current) {
    final lClean = latest.split('-').first.replaceFirst(RegExp(r'^[vV]'), '');
    final cClean = current.split('-').first.replaceFirst(RegExp(r'^[vV]'), '');
    final lParts = lClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final cParts = cClean.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final l = i < lParts.length ? lParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// HTTP 流式下载文件（支持 GitHub Release 重定向与进度回调）
  static Future<bool> _downloadFromHttpUrl(
    String url,
    File targetFile, {
    required void Function(int downloaded, int total) onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'PodQuick-Updater');
      final res = await req.close();
      if (res.statusCode != 200) return false;

      final total = res.contentLength;
      int downloaded = 0;
      final sink = targetFile.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          downloaded += chunk.length;
          onProgress(downloaded, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return true;
    } catch (e) {
      debugPrint('HTTP 下载安装包失败: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// 后台持续独立下载任务（支持 GitHub Releases 直连下载与 R2 下载）
  static Future<void> startBackgroundDownload(AppVersionInfo info, [AppSettings? settings]) async {
    if (isDownloading) return;

    isDownloading = true;
    downloadProgress = 0.0;
    hasError = false;
    pendingUpdateInfo = info;
    downloadStatusText = '正在准备下载安装包...';
    _notify();

    try {
      if (Platform.isMacOS) {
        final downloadUrl = info.macUrl;
        if (downloadUrl.startsWith('http') && downloadUrl.toLowerCase().endsWith('.dmg')) {
          final tempDir = await getTemporaryDirectory();
          final fileName = downloadUrl.split('/').last;
          final targetFile = File('${tempDir.path}/$fileName');
          if (await targetFile.exists()) {
            try {
              await targetFile.delete();
            } catch (_) {}
          }
          downloadStatusText = '正在下载 macOS 安装包 ($fileName)...';
          _notify();

          final ok = await _downloadFromHttpUrl(
            downloadUrl,
            targetFile,
            onProgress: (downloaded, total) {
              if (total > 0) {
                downloadProgress = downloaded / total;
                final currentMB = (downloaded / (1024 * 1024)).toStringAsFixed(1);
                final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
                final percent = (downloadProgress * 100).toInt();
                downloadStatusText = '正在下载: $currentMB MB / $totalMB MB ($percent%)';
              } else {
                final currentMB = (downloaded / (1024 * 1024)).toStringAsFixed(1);
                downloadStatusText = '已下载: $currentMB MB';
              }
              _notify();
            },
          );

          if (ok && await targetFile.exists()) {
            downloadProgress = 1.0;
            downloadStatusText = '下载完成，正在挂载打开 DMG 安装包...';
            _notify();
            await Process.run('open', [targetFile.path]);
            isDownloading = false;
            _notify();
            return;
          }
        }

        final uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('无法打开下载链接: $downloadUrl');
        }
        isDownloading = false;
        _notify();
        return;
      }

      // Windows 静默下载标准安装包 (PodQuick_Setup.exe) 并进行覆盖升级
      final tempDir = await getTemporaryDirectory();
      final remoteUrlOrKey = info.windowsUrl.isNotEmpty ? info.windowsUrl : 'PodQuick_Setup.exe';
      final targetFile = File('${tempDir.path}\\PodQuick_Setup.exe');
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      bool ok = false;
      if (remoteUrlOrKey.startsWith('http')) {
        if (!remoteUrlOrKey.toLowerCase().endsWith('.exe')) {
          // 如果指向的是 Release 网页而非直接 .exe，则在浏览器中打开
          final uri = Uri.parse(remoteUrlOrKey);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            isDownloading = false;
            _notify();
            return;
          }
        }
        downloadStatusText = '正在从 GitHub Release 下载安装包...';
        _notify();
        ok = await _downloadFromHttpUrl(
          remoteUrlOrKey,
          targetFile,
          onProgress: (downloaded, total) {
            if (total > 0) {
              downloadProgress = downloaded / total;
              final currentMB = (downloaded / (1024 * 1024)).toStringAsFixed(1);
              final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
              final percent = (downloadProgress * 100).toInt();
              downloadStatusText = '正在下载安装包: $currentMB MB / $totalMB MB ($percent%)';
            } else {
              final currentMB = (downloaded / (1024 * 1024)).toStringAsFixed(1);
              downloadStatusText = '已下载: $currentMB MB';
            }
            _notify();
          },
        );
      } else {
        final syncService = getSyncService(settings);
        if (syncService == null) {
          throw Exception('未找到可用的更新下载源');
        }
        downloadStatusText = '正在从云端下载安装包 ($remoteUrlOrKey)...';
        _notify();
        ok = await syncService.downloadFile(
          remoteUrlOrKey,
          targetFile,
          onProgress: (downloaded, total) {
            if (total > 0) {
              downloadProgress = downloaded / total;
              final currentMB = (downloaded / (1024 * 1024)).toStringAsFixed(1);
              final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
              final percent = (downloadProgress * 100).toInt();
              downloadStatusText = '正在下载安装包: $currentMB MB / $totalMB MB ($percent%)';
            } else {
              final currentMB = (downloaded / (1024 * 1024)).toStringAsFixed(1);
              downloadStatusText = '已下载: $currentMB MB';
            }
            _notify();
          },
        );
      }

      if (!ok || !await targetFile.exists()) {
        throw Exception('安装包下载失败，请检查网络连接');
      }

      downloadProgress = 1.0;
      downloadStatusText = '安装包下载完成，正在启动升级程序...';
      _notify();

      if (Platform.isWindows) {
        final cleanPath = targetFile.path.replaceAll('/', '\\');
        await Process.start(
          cleanPath,
          ['/SILENT', '/SP-'],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } else {
        await Process.start(targetFile.path, [], mode: ProcessStartMode.detached);
        exit(0);
      }
    } catch (e) {
      isDownloading = false;
      hasError = true;
      downloadStatusText = '更新失败: $e';
      _notify();
    }
  }

  /// 弹出更新窗口
  static Future<void> showUpdateDialog(
    BuildContext context,
    AppVersionInfo info, {
    bool isDark = true,
  }) async {
    pendingUpdateInfo = info;
    await showDialog(
      context: context,
      barrierDismissible: true, // 允许随时点击空白处/快捷键收起，下载绝不中断
      builder: (ctx) => _UpdateModalDialog(info: info, isDark: isDark),
    );
  }
}

class _UpdateModalDialog extends StatelessWidget {
  final AppVersionInfo info;
  final bool isDark;

  const _UpdateModalDialog({
    required this.info,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF252526) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final accentColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);

    return ValueListenableBuilder<int>(
      valueListenable: UpdateService.stateNotifier,
      builder: (context, _, __) {
        final isDownloading = UpdateService.isDownloading;
        final progress = UpdateService.downloadProgress;
        final statusText = UpdateService.downloadStatusText;
        final hasError = UpdateService.hasError;

        return AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.system_update_rounded, color: accentColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.text('发现新版本', 'New Version Available'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    Text(
                      'v${info.version} (当前 v${UpdateService.currentVersion})',
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: subColor,
                tooltip: context.text('收起窗口（后台继续下载）', 'Hide window (Continue in background)'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.text('更新说明：', 'Release Notes:'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      info.releaseNotes.isNotEmpty
                          ? info.releaseNotes
                          : context.text('修复已知问题与性能优化。', 'Bug fixes and performance improvements.'),
                      style: TextStyle(fontSize: 12, color: textColor, height: 1.5),
                    ),
                  ),
                ),
                if (isDownloading || progress > 0) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    backgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
                ],
                if (hasError) ...[
                  const SizedBox(height: 12),
                  Text(
                    statusText,
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                isDownloading
                    ? context.text('后台下载（收起）', 'Background Download')
                    : context.text('稍后再说', 'Later'),
                style: TextStyle(color: subColor),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isDownloading
                  ? null
                  : () => UpdateService.startBackgroundDownload(info),
              child: Text(
                isDownloading
                    ? context.text('后台下载中...', 'Downloading in background...')
                    : context.text('立即更新', 'Update Now'),
              ),
            ),
          ],
        );
      },
    );
  }
}
