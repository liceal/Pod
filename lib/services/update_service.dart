import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/localization.dart';
import 'r2_sync_service.dart';

class AppVersionInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String windowsUrl;
  final String macUrl;

  AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.windowsUrl,
    required this.macUrl,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version'] as String? ?? '1.0.0',
      buildNumber: json['buildNumber'] as int? ?? 1,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      windowsUrl: json['windowsUrl'] as String? ?? '',
      macUrl: json['macUrl'] as String? ?? '',
    );
  }
}

class UpdateService {
  static String _currentVersion = '1.0.0';
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
        _currentVersion = json['version'] as String;
      }
    } catch (e) {
      debugPrint('读取内置 release_info.json 失败: $e');
    }
  }

  static R2SyncService get _syncService => R2SyncService(
        accountId: 'YOUR_CLOUDFLARE_ACCOUNT_ID',
        accessKeyId: 'YOUR_R2_ACCESS_KEY_ID',
        secretAccessKey:
            'YOUR_R2_SECRET_ACCESS_KEY',
        bucketName: 'pod-quick',
      );

  /// 检查是否有新版本（优先读取 release_info.json，回退备选时间戳比对）
  static Future<AppVersionInfo?> checkUpdate() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/podquick_release_info.json');
      final hasReleaseInfo = await _syncService.downloadFile('release_info.json', tempFile);

      if (hasReleaseInfo && await tempFile.exists()) {
        final bytes = await tempFile.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        final json = jsonDecode(content) as Map<String, dynamic>;
        final latestVersion = json['version'] as String? ?? '1.0.0';
        final releaseNotes = json['releaseNotes'] as String? ?? '';

        if (_isHigherVersion(latestVersion, currentVersion)) {
          return AppVersionInfo(
            version: latestVersion,
            buildNumber: 2,
            releaseNotes: releaseNotes.isNotEmpty
                ? releaseNotes
                : '修复已知问题与性能优化。',
            windowsUrl: 'PodQuick.exe',
            macUrl: 'PodQuick.dmg',
          );
        }
      }

      // 如果未找到 release_info.json，通过 HEAD 请求进行时间戳比对
      final remoteFile = Platform.isWindows ? 'PodQuick.exe' : 'PodQuick.dmg';
      final remoteInfo = await _syncService.getObjectInfo(remoteFile);

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
            version: '云端最新构建 ($dateStr)',
            buildNumber: remoteInfo.lastModified.millisecondsSinceEpoch,
            releaseNotes: '检测到线上发布了最新的单文件构建版本！\n• 发布时间: $dateStr\n• 文件大小: $sizeMB MB',
            windowsUrl: 'PodQuick.exe',
            macUrl: 'PodQuick.dmg',
          );
        }
      }
    } catch (e) {
      debugPrint('检查更新失败: $e');
    }
    return null;
  }

  /// 比较版本号大小 (如 1.0.1 > 1.0.0)
  static bool _isHigherVersion(String latest, String current) {
    final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final l = i < lParts.length ? lParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// 后台持续独立下载任务（即使窗口隐藏/收起/销毁，下载依然静默稳定进行）
  static Future<void> startBackgroundDownload(AppVersionInfo info) async {
    if (isDownloading) return;

    isDownloading = true;
    downloadProgress = 0.0;
    hasError = false;
    pendingUpdateInfo = info;
    downloadStatusText = '正在准备下载...';
    _notify();

    try {
      if (Platform.isMacOS) {
        final downloadUrl = info.macUrl;
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

      // Windows 自动流式下载更新
      final tempDir = await getTemporaryDirectory();
      final targetFile = File('${tempDir.path}\\PodQuick_New_Setup.exe');
      if (await targetFile.exists()) await targetFile.delete();

      downloadStatusText = '正在从云端下载 PodQuick.exe...';
      _notify();

      final ok = await _syncService.downloadFile(
        'PodQuick.exe',
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

      if (!ok || !await targetFile.exists()) {
        throw Exception('下载失败，请检查网络连接');
      }

      downloadProgress = 1.0;
      downloadStatusText = '更新下载完成，正在平滑重启应用...';
      _notify();

      // 大厂级原位置无感平滑升级 (In-Place Outer Launcher & Payload Update)
      if (Platform.isWindows) {
        final outerLauncherPath = Platform.environment['PODQUICK_LAUNCHER_PATH'];
        final currentExePath = (outerLauncherPath != null && File(outerLauncherPath).existsSync())
            ? outerLauncherPath
            : Platform.resolvedExecutable;

        final currentExe = File(currentExePath);
        final oldExePath = '$currentExePath.old';
        final oldExe = File(oldExePath);

        // 1. 若存在残留的 .old 文件先进行清除
        if (await oldExe.exists()) {
          try { await oldExe.delete(); } catch (_) {}
        }

        // 2. 将用户双击运行的真正外部桌面/目录 PodQuick.exe 重命名为 .old
        await currentExe.rename(oldExePath);

        // 3. 将新下载的最新 PodQuick.exe 放置到原本的用户物理文件位置
        await targetFile.copy(currentExePath);
        try { await targetFile.delete(); } catch (_) {}

        // 4. 清理旧的版本标记，确保新启动器重新释放最新的 1.0.2 payload
        try {
          final tempAppDir = File(Platform.resolvedExecutable).parent;
          final versionMarkerFile = File('${tempAppDir.path}\\launcher.version');
          if (await versionMarkerFile.exists()) {
            await versionMarkerFile.delete();
          }
        } catch (_) {}

        // 5. 后台 2.5 秒后拉起原位置的新版 PodQuick.exe，并静默清理 .old 临时文件
        final cleanCurrentPath = currentExePath.replaceAll('/', '\\');
        final cleanOldPath = oldExePath.replaceAll('/', '\\');
        final psCommand = "Start-Sleep -Seconds 2.5; Remove-Item '$cleanOldPath' -ErrorAction SilentlyContinue; Start-Process '$cleanCurrentPath'";

        await Process.start(
          'powershell.exe',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psCommand],
          mode: ProcessStartMode.detached,
        );
      } else {
        await Process.start(targetFile.path, [], mode: ProcessStartMode.detached);
      }
      exit(0);
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
