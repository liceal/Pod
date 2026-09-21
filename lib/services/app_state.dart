import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:uuid/uuid.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:intl/intl.dart';

import '../models/clipboard_item.dart';
import '../models/note.dart';
import '../models/app_settings.dart';
import 'r2_sync_service.dart';
import 'cf_d1_sync_service.dart';
import 'update_service.dart';

class AppState extends ChangeNotifier with WindowListener, TrayListener {
  static const _clipboardOwnerChannel = MethodChannel(
    'app.podquick/clipboard_owner',
  );

  static const _menuBarScrollChannel = MethodChannel('app.podquick/menu_bar_scroll');

  static const _focusManagerChannel = MethodChannel('app.podquick/focus_manager');

  static const _macFileOpenerChannel = MethodChannel('app.podquick/file_opener');

  static const _launchAtStartupChannel = MethodChannel(
    'app.podquick/launch_at_startup',
  );

  // Singleton
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  final _uuid = const Uuid();
  final navigatorKey = GlobalKey<NavigatorState>();
  late SharedPreferences _prefs;

  // State Variables
  AppSettings settings = AppSettings();

  bool get isChineseUi {
    final code = settings.languageCode;
    if (code == 'zh') return true;
    if (code == 'en') return false;
    try {
      final systemLocale = PlatformDispatcher.instance.locale.languageCode;
      return systemLocale != 'en';
    } catch (_) {
      return true;
    }
  }

  String text(String zh, String en) => isChineseUi ? zh : en;
  List<ClipboardItem> clipboardHistory = [];
  List<ClipboardItem> clipboardFavorites = [];
  List<FileSystemEntity> storedFiles = [];
  final List<FileUndoAction> _undoStack = [];
  final List<FileUndoAction> _redoStack = [];
  List<Note> notes = [];
  List<Note> deletedNotes = [];
  Note? activeNote;

  bool isExpanded = false;
  bool isAnimating = false;
  bool isDialogOpen = false;
  bool isMouseInside = false;
  bool isWindowFocused = false;
  bool _isNoteEditorFocused = false;
  int panelActivationVersion = 0;
  double lastCalculatedWidth = 800.0;
  double fileDisplaySize = 110.0;

  String _searchClipboardQuery = '';
  String _searchNotesQuery = '';

  String _lastSystemClipText = '';
  String _lastAppCopiedText = '';
  String? _lastSystemClipImageSignature;
  String? _lastAppCopiedImageSignature;
  bool _isCheckingClipboard = false;
  bool _ignoreNextClipboardCheck = false;
  int? _lastNativeClipboardSequence;
  bool _nativeClipboardSequenceUnavailable = false;
  bool _hasSequenceChanged = false;
  Timer? _clipboardTimer;
  Timer? _clipboardDebounceTimer;
  Timer? _notesSaveTimer;
  Timer? _autoCollapseTimer;
  Timer? _panelActivationRefreshTimer;
  Timer? _fileWatchDebounce;
  Timer? _settingsSaveDebounce;

  String _trayIconPath = '';
  StreamSubscription<FileSystemEvent>? _dirWatcher;
  StreamSubscription<FileSystemEvent>? _imagesDirWatcher;
  StreamSubscription<FileSystemEvent>? _dataDirWatcher;
  String? _lastNotesJsonCache;
  String? _lastHistoryJsonCache;
  String? _lastFavoritesJsonCache;
  Timer? _reloadNotesDebounce;
  Timer? _reloadHistoryDebounce;
  Timer? _r2SyncTimer;
  bool _isR2Syncing = false;
  String? _r2SyncStatusMessage;
  double _r2SyncProgress = 0.0;
  final List<String> _r2SyncLogs = [];

  bool get isR2Syncing => _isR2Syncing;
  String? get r2SyncStatusMessage => _r2SyncStatusMessage;
  double get r2SyncProgress => _r2SyncProgress;
  List<String> get r2SyncLogs => List.unmodifiable(_r2SyncLogs);

  bool _isD1Syncing = false;
  String? _d1SyncStatusMessage;
  final List<String> _d1SyncLogs = [];
  bool? _lastD1SyncSuccess;
  String? _lastD1SyncMessage;
  DateTime? _lastD1SyncTime;

  bool get isD1Syncing => _isD1Syncing;
  String? get d1SyncStatusMessage => _d1SyncStatusMessage;
  List<String> get d1SyncLogs => List.unmodifiable(_d1SyncLogs);
  bool? get lastD1SyncSuccess => _lastD1SyncSuccess;
  String? get lastD1SyncMessage => _lastD1SyncMessage;
  DateTime? get lastD1SyncTime => _lastD1SyncTime;

  void clearLastD1SyncStatus() {
    _lastD1SyncSuccess = null;
    _lastD1SyncMessage = null;
    notifyListeners();
  }

  void addD1Log(String message) {
    final timeStr = DateFormat('HH:mm:ss').format(DateTime.now());
    _d1SyncLogs.add('[$timeStr] $message');
    if (_d1SyncLogs.length > 100) {
      _d1SyncLogs.removeAt(0);
    }
    notifyListeners();
  }

  bool _didGrabFocus = false;
  bool _restoreFocusAfterCollapse = false;
  bool _isShuttingDown = false;
  Display? _currentDisplay;
  Map<String, double>? _nativeScreenInfo;
  DateTime _lastScrollAction = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastExpandTime;
  final Map<String, String> _itemTypeCache = {};

  // Cache for file metadata to avoid blocking synchronous IO in widget builds
  final Map<String, FileStat> _fileStatCache = {};
  final Map<String, bool> _isDirectoryCache = {};

  FileStat? getCachedFileStat(String path) {
    return _fileStatCache[path];
  }

  bool getCachedIsDirectory(String path) {
    return _isDirectoryCache[path] ?? false;
  }

  // Lightweight callback for animation-only updates
  void Function(Duration duration)? onAnimationStateChanged;

  /// Get the display where the mouse cursor currently is
  Future<Display> _getCurrentDisplay() async {
    try {
      final cursorPoint = await screenRetriever.getCursorScreenPoint();
      final displays = await screenRetriever.getAllDisplays();
      for (final display in displays) {
        final pos = display.visiblePosition ?? Offset.zero;
        final size = display.visibleSize ?? display.size;
        final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
        if (rect.contains(cursorPoint)) {
          return display;
        }
      }
    } catch (e) {
      debugPrint('Failed to get current display: $e');
    }
    return await screenRetriever.getPrimaryDisplay();
  }

  /// Get the active screen dimensions and position containing the mouse cursor
  Future<Map<String, double>> getActiveScreenInfo() async {
    final display = await _getCurrentDisplay();
    final double sw = display.size.width;
    final double sx = (display.visiblePosition ?? Offset.zero).dx;
    final double sy = (display.visiblePosition ?? Offset.zero).dy;
    return {'x': sx, 'width': sw, 'visibleY': sy};
  }

  String _imageSignature(Uint8List bytes) {
    if (bytes.isEmpty) return '0:0';
    var hash = 0;
    final step = (bytes.length / 4096).ceil().clamp(1, bytes.length).toInt();
    for (var i = 0; i < bytes.length; i += step) {
      hash = 0x1fffffff & (hash + bytes[i]);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    if (bytes.isNotEmpty) {
      hash = 0x1fffffff & (hash + bytes.first);
      hash = 0x1fffffff & (hash + bytes.last);
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return '${bytes.length}:$hash';
  }

  bool isUrl(String text) {
    if (text.length > 2048) return false;
    final trimmed = text.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }
    if (trimmed.contains(' ') ||
        trimmed.contains('\n') ||
        trimmed.contains('\r')) {
      return false;
    }
    try {
      final uri = Uri.parse(trimmed);
      return uri.scheme.isNotEmpty && uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> openUrl(String text) async {
    try {
      final uri = Uri.parse(text.trim());
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Failed to launch URL: $e');
    }
  }

  static final RegExp _hexColorRegExp = RegExp(
    r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  );
  static final RegExp _rgbColorRegExp = RegExp(
    r'^(rgb|rgba)\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*(,\s*(0?\.\d+|\d+|\d*\.\d+)\s*)?\)$',
    caseSensitive: false,
  );
  static final RegExp _hslColorRegExp = RegExp(
    r'^(hsl|hsla)\(\s*\d+\s*,\s*\d+%\s*,\s*\d+%\s*(,\s*(0?\.\d+|\d+|\d*\.\d+)\s*)?\)$',
    caseSensitive: false,
  );

  Color? parseColor(String text) {
    if (text.length > 100) return null;
    final input = text.trim();
    if (_hexColorRegExp.hasMatch(input)) {
      String hex = input.substring(1);
      if (hex.length == 3) {
        final r = hex[0];
        final g = hex[1];
        final b = hex[2];
        hex = 'FF$r$r$g$g$b$b';
      } else if (hex.length == 4) {
        final a = hex[0];
        final r = hex[1];
        final g = hex[2];
        final b = hex[3];
        hex = '$a$a$r$r$g$g$b$b';
      } else if (hex.length == 6) {
        hex = 'FF$hex';
      } else if (hex.length == 8) {
        final rr = hex.substring(0, 2);
        final gg = hex.substring(2, 4);
        final bb = hex.substring(4, 6);
        final aa = hex.substring(6, 8);
        hex = '$aa$rr$gg$bb';
      }
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(val);
    } else if (_rgbColorRegExp.hasMatch(input)) {
      final match = RegExp(
        r'\d*\.?\d+',
      ).allMatches(input).map((m) => m.group(0)!).toList();
      if (match.length >= 3) {
        final r = int.tryParse(match[0]) ?? 0;
        final g = int.tryParse(match[1]) ?? 0;
        final b = int.tryParse(match[2]) ?? 0;
        double a = 1.0;
        if (match.length >= 4) {
          a = double.tryParse(match[3]) ?? 1.0;
        }
        return Color.fromARGB(
          (a * 255).round().clamp(0, 255),
          r.clamp(0, 255),
          g.clamp(0, 255),
          b.clamp(0, 255),
        );
      }
    } else if (_hslColorRegExp.hasMatch(input)) {
      final match = RegExp(
        r'\d*\.?\d+',
      ).allMatches(input).map((m) => m.group(0)!).toList();
      if (match.length >= 3) {
        final h = double.tryParse(match[0]) ?? 0.0;
        final s = (double.tryParse(match[1]) ?? 0.0) / 100.0;
        final l = (double.tryParse(match[2]) ?? 0.0) / 100.0;
        double a = 1.0;
        if (match.length >= 4) {
          a = double.tryParse(match[3]) ?? 1.0;
        }
        return HSLColor.fromAHSL(
          a.clamp(0.0, 1.0),
          h.clamp(0.0, 360.0),
          s.clamp(0.0, 1.0),
          l.clamp(0.0, 1.0),
        ).toColor();
      }
    }
    return null;
  }

  DateTime? parseTimestamp(String text) {
    if (text.length > 50) return null;
    final input = text.trim();
    if (RegExp(r'^\d{10}$').hasMatch(input)) {
      final sec = int.tryParse(input);
      if (sec != null && sec >= 1000000000 && sec <= 2500000000) {
        return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
      }
    } else if (RegExp(r'^\d{13}$').hasMatch(input)) {
      final ms = int.tryParse(input);
      if (ms != null && ms >= 1000000000000 && ms <= 2500000000000) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return null;
  }

  String getClipboardItemType(ClipboardItem item) {
    final cached = _itemTypeCache[item.id];
    if (cached != null) return cached;

    String type = 'TEXT';
    if (item.imagePath != null) {
      type = 'IMAGE';
    } else {
      final text = item.content;
      if (text.length < 2048) {
        if (isUrl(text)) {
          type = 'URL';
        } else if (parseColor(text) != null) {
          type = 'COLOR';
        } else if (parseTimestamp(text) != null) {
          type = 'DATETIME';
        }
      }
    }
    _itemTypeCache[item.id] = type;
    return type;
  }

  bool isItemFavorite(ClipboardItem item) {
    if (item.imagePath != null) {
      return clipboardFavorites.any((x) =>
          x.imagePath != null &&
          (x.id == item.id ||
           (x.imageSignature != null && item.imageSignature != null && x.imageSignature == item.imageSignature) ||
           (x.imageSignature == null && item.imageSignature == null && getImagePath(x) == getImagePath(item))));
    }
    return clipboardFavorites.any((x) => x.content == item.content);
  }

  List<ClipboardItem> get filteredClipboardHistory {
    if (_searchClipboardQuery.isEmpty) {
      return clipboardHistory;
    }
    final query = _searchClipboardQuery.toLowerCase();
    return clipboardHistory
        .where(
          (item) =>
              item.content.toLowerCase().contains(query) ||
              (item.appName != null &&
                  item.appName!.toLowerCase().contains(query)),
        )
        .toList();
  }

  List<ClipboardItem> get filteredClipboardFavorites {
    if (_searchClipboardQuery.isEmpty) {
      return clipboardFavorites;
    }
    final query = _searchClipboardQuery.toLowerCase();
    return clipboardFavorites
        .where(
          (item) =>
              item.content.toLowerCase().contains(query) ||
              (item.appName != null &&
                  item.appName!.toLowerCase().contains(query)),
        )
        .toList();
  }

  List<Note> get filteredNotes {
    if (_searchNotesQuery.isEmpty) {
      return notes;
    }
    final query = _searchNotesQuery.toLowerCase();
    return notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(query) ||
              n.content.toLowerCase().contains(query),
        )
        .toList();
  }

  String get searchClipboardQuery => _searchClipboardQuery;
  set searchClipboardQuery(String value) {
    _searchClipboardQuery = value;
    notifyListeners();
  }

  String get searchNotesQuery => _searchNotesQuery;
  set searchNotesQuery(String value) {
    _searchNotesQuery = value;
    notifyListeners();
  }

  Future<void> _clearTrashDir() async {
    try {
      final root = await _getFilesDirectoryPath();
      final trashDir = Directory('$root/.trash');
      if (trashDir.existsSync()) {
        await trashDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to clear trash directory on startup: $e');
    }
  }

  // --- Initializer ---
  Future<void> initialize() async {
    _clearTrashDir();
    _prefs = await SharedPreferences.getInstance();
    final appSupport = await getApplicationSupportDirectory();
    _defaultDataDirSync = '${appSupport.path}/data'.replaceAll('\\', '/');

    windowManager.addListener(this);
    trayManager.addListener(this);

    // Load Local Data
    _loadSettings();
    final lastSyncMs = _prefs.getInt('last_d1_sync_time');
    if (lastSyncMs != null) {
      _lastD1SyncTime = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
    }
    await UpdateService.loadLocalVersion();
    await _syncLaunchAtStartupSetting();
    await _migrateLegacyDirectories();

    // Load historical items, notes and stored files in parallel
    await Future.wait([
      _loadClipboardHistory(),
      _loadNotes(),
      _scanStoredFiles(),
    ]);

    // Setup tray, hotkeys and directory watchers in parallel
    await Future.wait([
      _setupTray(),
      _setupHotkeys(),
      _startWatchingImagesDirectory(),
      _startWatchingDataDirectory(),
    ]);

    _startClipboardMonitoring();

    // Background cleanup of orphaned images
    _cleanupUnusedClipboardImages();

    if (Platform.isMacOS) {
      _menuBarScrollChannel.setMethodCallHandler(_onMenuBarScrollMethodCall);
    } else if (Platform.isWindows) {
      _menuBarScrollChannel.setMethodCallHandler(_onMenuBarScrollMethodCall);
    }

    // Position window
    await windowManager.setMinimumSize(const Size(1, 1));
    await applyWindowTriggerConfiguration(isStartup: true);

    // Schedule R2 Auto Sync if configured
    _scheduleR2AutoSync();
    _scheduleCfD1AutoSync();
  }

  @override
  void dispose() {
    _isShuttingDown = true;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    unawaited(forceSaveSettingsIfPending());
    _cancelRuntimeTimers();
    _menuBarScrollChannel.setMethodCallHandler(null);
    _dirWatcher?.cancel();
    _imagesDirWatcher?.cancel();
    _dataDirWatcher?.cancel();
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  void _cancelRuntimeTimers() {
    _clipboardDebounceTimer?.cancel();
    _clipboardTimer?.cancel();
    _notesSaveTimer?.cancel();
    _autoCollapseTimer?.cancel();
    _panelActivationRefreshTimer?.cancel();
    _fileWatchDebounce?.cancel();
    _settingsSaveDebounce?.cancel();
    _reloadNotesDebounce?.cancel();
    _reloadHistoryDebounce?.cancel();
    _r2SyncTimer?.cancel();
    _cfD1SyncTimer?.cancel();
  }

  // --- Cloudflare R2 Sync Methods ---

  R2SyncService? _createR2SyncService([AppSettings? overrideSettings]) {
    final s = overrideSettings ?? settings;
    final accountId = (s.r2AccountId != null && s.r2AccountId!.trim().isNotEmpty)
        ? s.r2AccountId!.trim()
        : s.cfAccountId?.trim();
    final bucketName = (s.r2BucketName != null && s.r2BucketName!.trim().isNotEmpty)
        ? s.r2BucketName!.trim()
        : s.cfR2BucketName?.trim();
    final accessKeyId = s.r2AccessKeyId?.trim();
    final secretAccessKey = s.r2SecretAccessKey?.trim();

    if (accountId == null || accountId.isEmpty ||
        bucketName == null || bucketName.isEmpty ||
        accessKeyId == null || accessKeyId.isEmpty ||
        secretAccessKey == null || secretAccessKey.isEmpty) {
      return null;
    }
    return R2SyncService(
      accountId: accountId,
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      bucketName: bucketName,
      customEndpoint: s.r2CustomEndpoint?.trim(),
    );
  }

  Future<R2TestResult> testR2Connection(AppSettings testSettings) async {
    final service = _createR2SyncService(testSettings);
    if (service == null) {
      return R2TestResult(
        success: false,
        message: '请填满所有必需的 Cloudflare R2 参数（Account ID、Access Key、Secret Key、Bucket）。',
      );
    }
    return await service.testConnection();
  }

  Future<R2SyncResult> syncWithR2({bool isManual = false}) async {
    if (!settings.r2Enabled && !isManual) {
      return R2SyncResult(success: false, message: 'Cloudflare R2 同步功能未开启');
    }
    if (_isR2Syncing) {
      return R2SyncResult(success: false, message: '正在同步中，请稍候...');
    }

    final service = _createR2SyncService();
    if (service == null) {
      return R2SyncResult(
        success: false,
        message: 'R2 配置不完整，请在设置中填写完整的 Account ID、Key 与 Bucket。',
      );
    }

    _isR2Syncing = true;
    _r2SyncStatusMessage = '正在准备同步...';
    _r2SyncProgress = 0.0;
    _r2SyncLogs.clear();
    final timeStr = DateFormat('HH:mm:ss').format(DateTime.now());
    _r2SyncLogs.add('[$timeStr] 开始云端双向同步...');
    notifyListeners();

    try {
      final dataDir = getDataDirectoryPathSync();
      final result = await service.syncAllData(
        dataDirectoryPath: dataDir,
        onProgress: (status, current, total) {
          final nowTime = DateFormat('HH:mm:ss').format(DateTime.now());
          _r2SyncStatusMessage = status;
          if (total > 0) {
            _r2SyncProgress = current / total;
          } else {
            _r2SyncProgress = 0.0;
          }
          _r2SyncLogs.add('[$nowTime] $status');
          if (_r2SyncLogs.length > 100) {
            _r2SyncLogs.removeAt(0);
          }
          notifyListeners();
        },
      );

      if (result.success) {
        final now = DateTime.now().millisecondsSinceEpoch;
        settings = settings.copyWith(r2LastSyncTime: now);
        await _prefs.setString('settings', jsonEncode(settings.toJson()));
        _r2SyncStatusMessage = result.syncedCount > 0
            ? '同步成功 (${result.syncedCount} 个文件已处理)'
            : '同步成功 (数据已保持最新)';

        if (result.syncedCount > 0) {
          await _loadNotes();
          await _loadClipboardHistory();
          await _scanStoredFiles();
        }
      } else {
        _r2SyncStatusMessage = '同步失败: ${result.message}';
      }

      _isR2Syncing = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isR2Syncing = false;
      _r2SyncStatusMessage = '同步异常: $e';
      notifyListeners();
      return R2SyncResult(success: false, message: '同步异常: $e');
    }
  }

  // --- Cloudflare D1 Sync Methods ---

  Future<void> _pullAndMergeCloudData({required Function(String msg) onLog}) async {
    onLog(text('📥 开始从 Cloudflare D1 拉取增量变更 (Git 风格拉取)...', 'Pulling deltas from Cloudflare D1 (Git-style pull)...'));

    Map<String, dynamic>? pullRes;
    final sinceTime = _lastD1SyncTime ?? DateTime.fromMillisecondsSinceEpoch(0);

    if (settings.cfD1Mode == 0) {
      final url = settings.cfWorkerUrl.trim();
      if (url.isNotEmpty) {
        final service = CfD1SyncService(workerUrl: url, isDevMode: true);
        pullRes = await service.pullFromCloudflare(since: sinceTime);
      }
    } else {
      final accountId = settings.cfAccountId?.trim() ?? '';
      final apiToken = settings.cfApiToken?.trim() ?? '';
      final dbId = settings.cfD1DatabaseId?.trim() ?? '';
      if (accountId.isNotEmpty && apiToken.isNotEmpty && dbId.isNotEmpty) {
        pullRes = await CfD1SyncService.pullFromD1RestApi(
          accountId: accountId,
          apiToken: apiToken,
          d1DatabaseId: dbId,
          since: sinceTime,
        );
      }
    }

    if (pullRes != null && pullRes['success'] == true) {
      final List<Note> remoteNotes = (pullRes['notes'] as List?)?.cast<Note>() ?? [];
      final List<ClipboardItem> remoteClipboards = (pullRes['clipboardItems'] as List?)?.cast<ClipboardItem>() ?? [];

      // 1. 合并便签 (Git 风格：墓碑检测 + 冲突备份 + 增量对比)
      int newNotesCount = 0;
      int updatedNotesCount = 0;
      int conflictsCount = 0;
      final Map<String, Note> activeMap = {};
      final Map<String, Note> tombstoneMap = {};

      for (final n in notes) activeMap[n.id] = n;
      for (final dn in deletedNotes) tombstoneMap[dn.id] = dn;

      final List<Note> backupNotes = [];

      for (final rNote in remoteNotes) {
        if (rNote.isDeleted) {
          // 云端为删除墓碑
          if (activeMap.containsKey(rNote.id)) {
            activeMap.remove(rNote.id);
            updatedNotesCount++;
          }
          tombstoneMap[rNote.id] = rNote;
          continue;
        }

        // 云端为有效便签
        if (tombstoneMap.containsKey(rNote.id)) {
          final tombstone = tombstoneMap[rNote.id]!;
          if (rNote.updatedAt.isAfter(tombstone.updatedAt)) {
            // 云端更新时间在本地删除之后（在其他端重新编辑过） -> 恢复/更新
            tombstoneMap.remove(rNote.id);
            activeMap[rNote.id] = rNote;
            newNotesCount++;
          } else {
            // 本地删除时间更新 -> 维持本地删除状态
            continue;
          }
        } else if (!activeMap.containsKey(rNote.id)) {
          // 本地没有记录 -> 直接添加
          activeMap[rNote.id] = rNote;
          newNotesCount++;
        } else {
          // 双端均有更新 -> 三方合并与冲突处理
          final localNote = activeMap[rNote.id]!;
          if (rNote.updatedAt.isAfter(localNote.updatedAt)) {
            if (localNote.updatedAt.isAfter(sinceTime) &&
                localNote.content != rNote.content &&
                localNote.content.isNotEmpty) {
              // 双方在上次同步后均修改了内容且不相同 -> 产生冲突！
              // 使用云端版本，同时将本地未上送的修改存为冲突备份
              final backup = Note(
                id: _uuid.v4(),
                title: text('[冲突备份] ${localNote.title}', '[Conflict Backup] ${localNote.title}'),
                content: localNote.content,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              backupNotes.add(backup);
              conflictsCount++;
            }
            activeMap[rNote.id] = rNote;
            updatedNotesCount++;
          }
        }
      }

      if (backupNotes.isNotEmpty) {
        for (final b in backupNotes) {
          activeMap[b.id] = b;
        }
      }

      deletedNotes = tombstoneMap.values.toList();
      await _saveDeletedNotes();

      if (newNotesCount > 0 || updatedNotesCount > 0 || conflictsCount > 0) {
        notes = activeMap.values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        if (activeNote != null) {
          final match = notes.where((n) => n.id == activeNote!.id).toList();
          if (match.isNotEmpty) {
            activeNote = match.first;
          } else if (notes.isNotEmpty) {
            activeNote = notes.first;
          }
        } else if (notes.isNotEmpty) {
          activeNote = notes.first;
        }

        await _saveNotes();
        var msg = text(
          '🎉 云端便签同步拉取完成：新增 $newNotesCount 条，更新 $updatedNotesCount 条',
          'Fetched notes: added $newNotesCount, updated $updatedNotesCount',
        );
        if (conflictsCount > 0) {
          msg += text(' (检测到 $conflictsCount 处冲突，已生成本地备份)', ' ($conflictsCount conflicts backed up)');
        }
        onLog(msg);
      } else {
        onLog(text('ℹ️ 便签已与云端同步保持最新', 'Notes up to date.'));
      }

      // 2. 合并剪贴板历史
      int newClipCount = 0;
      final Set<String> existingClipIds = {};
      for (final c in clipboardHistory) existingClipIds.add(c.id);
      for (final c in clipboardFavorites) existingClipIds.add(c.id);

      for (final rClip in remoteClipboards) {
        if (!existingClipIds.contains(rClip.id)) {
          if (rClip.isFavorite) {
            clipboardFavorites.insert(0, rClip);
          } else {
            clipboardHistory.insert(0, rClip);
          }
          existingClipIds.add(rClip.id);
          newClipCount++;
        }
      }

      if (newClipCount > 0) {
        clipboardHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        clipboardFavorites.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _saveClipboardHistory();
        await _saveClipboardFavorites();
        onLog(text('🎉 剪贴板同步完成：合并新增 $newClipCount 条记录', 'Fetched clipboards: added $newClipCount'));
      }

      notifyListeners();
    } else {
      if (pullRes != null && pullRes['error'] != null) {
        onLog(text('⚠️ 拉取云端数据失败: ${pullRes['error']}', 'Pull data failed: ${pullRes['error']}'));
      }
    }
  }

  Future<Map<String, dynamic>> _pushLocalDataToD1Internal({bool isManual = true}) async {
    addD1Log(text('开始 Cloudflare D1 数据库双向增量同步 (Git 模式)...', 'Starting Git-style D1 sync...'));

    // 1. 先拉取云端增量数据并进行合并
    await _pullAndMergeCloudData(onLog: (msg) => addD1Log(msg));

    // 2. 包含已删除墓碑在内的全量便签列表
    final allNotes = [...notes, ...deletedNotes];

    final Map<String, ClipboardItem> clipMap = {};
    for (final item in clipboardHistory) clipMap[item.id] = item;
    for (final item in clipboardFavorites) clipMap[item.id] = item;
    final allClipboards = clipMap.values.toList();

    addD1Log(text(
      '读取待推送到 D1 数据: 便签 ${allNotes.length} 条 (含删除标记 ${deletedNotes.length} 条), 剪贴板 ${allClipboards.length} 条',
      'Collected local data: ${allNotes.length} notes (${deletedNotes.length} deleted), ${allClipboards.length} clipboards',
    ));

    final settingsList = [
      {
        'key': 'app_settings',
        'value': jsonEncode(settings.toJson()),
        'updatedAt': DateTime.now().toIso8601String(),
      }
    ];

    if (settings.cfD1Mode == 0) {
      final url = settings.cfWorkerUrl.trim();
      if (url.isEmpty) {
        final err = text('未配置 Cloudflare Worker 服务端 URL', 'Worker URL is missing');
        addD1Log('❌ $err');
        return {'success': false, 'error': err};
      }
      addD1Log(text('正在通过 Worker 端点 ($url) 上传...', 'Pushing via Worker endpoint ($url)...'));
      final service = CfD1SyncService(workerUrl: url, isDevMode: true);
      final metrics = await service.pushToCloudflare(
        notes: allNotes,
        clipboardItems: allClipboards,
        settings: settingsList,
      );
      if (metrics != null && metrics.httpStatus == 200) {
        final msg = text(
          '全量同步成功！已上传便签 ${allNotes.length} 条，剪贴板 ${allClipboards.length} 条 (RTT: ${metrics.clientRttMs.toStringAsFixed(1)}ms)',
          'Successfully pushed data to Worker D1',
        );
        addD1Log('✅ $msg');
        return {
          'success': true,
          'notesCount': allNotes.length,
          'clipboardCount': allClipboards.length,
          'settingsCount': settingsList.length,
          'rttMs': metrics.clientRttMs,
          'message': msg,
        };
      } else {
        final err = text('推送到 Cloudflare Worker 失败', 'Failed to push to Cloudflare Worker');
        addD1Log('❌ $err');
        return {'success': false, 'error': err};
      }
    } else {
      final accountId = settings.cfAccountId?.trim() ?? '';
      final apiToken = settings.cfApiToken?.trim() ?? '';
      final dbId = settings.cfD1DatabaseId?.trim() ?? '';
      if (accountId.isEmpty || apiToken.isEmpty || dbId.isEmpty) {
        final err = text('请先在设置中完整填写 Account ID、API Token 和 D1 Database ID', 'Cloudflare D1 credentials missing');
        addD1Log('❌ $err');
        return {'success': false, 'error': err};
      }

      addD1Log(text('正在通过 Cloudflare REST API 直通同步...', 'Pushing directly via Cloudflare REST API...'));

      final res = await CfD1SyncService.pushLocalDataToD1RestApi(
        accountId: accountId,
        apiToken: apiToken,
        d1DatabaseId: dbId,
        notes: allNotes,
        clipboardItems: allClipboards,
        settings: settingsList,
        onLog: (msg) => addD1Log(msg),
      );

      if (res['success'] == true) {
        addD1Log('✅ ${res['message']}');
      } else {
        addD1Log('❌ 推送失败: ${res['error']}');
      }
      return res;
    }
  }

  Future<Map<String, dynamic>> syncLocalDataToD1({bool isManual = true}) async {
    if (_isD1Syncing) {
      return {'success': false, 'error': text('后台正在同步中，请稍候...', 'Sync already in progress...')};
    }
    _isD1Syncing = true;
    _d1SyncLogs.clear();
    _lastD1SyncSuccess = null;
    _lastD1SyncMessage = null;
    _d1SyncStatusMessage = text('正在同步到 Cloudflare D1...', 'Syncing to Cloudflare D1...');
    notifyListeners();

    try {
      final res = await _pushLocalDataToD1Internal(isManual: isManual);
      final isSuccess = res['success'] == true;
      _lastD1SyncSuccess = isSuccess;
      _lastD1SyncMessage = res['message'] ?? res['error'];
      if (isSuccess) {
        _lastD1SyncTime = DateTime.now();
        await _prefs.setInt('last_d1_sync_time', _lastD1SyncTime!.millisecondsSinceEpoch);
      }
      _d1SyncStatusMessage = _lastD1SyncMessage;
      return res;
    } catch (e) {
      final err = text('D1 同步发生异常: $e', 'D1 sync error: $e');
      addD1Log('❌ $err');
      _lastD1SyncSuccess = false;
      _lastD1SyncMessage = err;
      _d1SyncStatusMessage = err;
      return {'success': false, 'error': err};
    } finally {
      _isD1Syncing = false;
      notifyListeners();
    }
  }

  /// 统一全量同步：一键将本地所有的便签、剪贴板历史、应用设置同步至 D1 数据库，同时将本地图片、文件及附件同步至 R2 存储桶
  /// 全程在后台持续运行，不会被设置窗口的关闭或返回操作中断
  Future<Map<String, dynamic>> syncAllLocalDataAndFiles({bool isManual = true}) async {
    if (_isD1Syncing) {
      return {'success': false, 'error': text('后台正在全量同步中，请稍候...', 'Sync already running in background...')};
    }
    _isD1Syncing = true;
    _d1SyncLogs.clear();
    _lastD1SyncSuccess = null;
    _lastD1SyncMessage = null;
    _d1SyncStatusMessage = text('正在全量同步数据与文件...', 'Syncing all data and files...');
    notifyListeners();

    try {
      addD1Log(text('🚀 开始全量一键同步 (Cloudflare D1 数据库 + R2 文件存储)...', 'Starting full sync (D1 DB + R2 Storage)...'));

      // 1. 同步 D1 数据库数据 (便签 + 剪贴板 + 设置)
      final d1Result = await _pushLocalDataToD1Internal(isManual: isManual);

      // 2. 独立同步 Section A 的 R2 存储桶 (本地图片、剪贴板快照与文件附件)
      final bucketName = (settings.cfR2BucketName?.trim().isNotEmpty == true)
          ? settings.cfR2BucketName!.trim()
          : settings.r2BucketName?.trim();

      int skippedIdenticalCount = 0;
      int newlyUploadedCount = 0;

      if (bucketName != null && bucketName.isNotEmpty) {
        addD1Log(text('📁 正在准备同步本地文件/图片至 Cloudflare R2 存储桶 ($bucketName)...', 'Syncing files to R2 bucket ($bucketName)...'));

        try {
          final dataDir = Directory(getDataDirectoryPathSync());
          // 扫描应用实际存放图片和文件的目录
          final scanDirs = <Directory>[
            Directory('${dataDir.path}${Platform.pathSeparator}clipboard_images'),
            Directory('${dataDir.path}${Platform.pathSeparator}files'),
            Directory('${dataDir.path}${Platform.pathSeparator}images'),
            if (settings.customFilesPath != null && settings.customFilesPath!.trim().isNotEmpty)
              Directory(settings.customFilesPath!.trim()),
          ];

          final allLocalFiles = <File>[];
          for (final dir in scanDirs) {
            if (dir.existsSync()) {
              final list = dir.listSync(recursive: true).whereType<File>().toList();
              for (final f in list) {
                final name = f.path.split(Platform.pathSeparator).last;
                if (name.startsWith('.') || name.endsWith('.tmp')) continue;
                allLocalFiles.add(f);
              }
            }
          }

          if (allLocalFiles.isEmpty) {
            addD1Log(text('ℹ️ 本地暂无需要同步的图片或文件附件 (clipboard_images/files 均为空)', 'No local files to sync.'));
          } else {
            addD1Log(text('🔍 扫描到 ${allLocalFiles.length} 个本地文件，正在查询 D1 云端数据库比对差异...', 'Scanning ${allLocalFiles.length} local files, querying D1 metadata for diff...'));

            // 1. 获取 D1 云端文件元数据记录 (file_metadata 表)
            Map<String, Map<String, dynamic>> cloudMetadata = {};
            if (settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty) {
              final service = CfD1SyncService(workerUrl: settings.cfWorkerUrl, isDevMode: true);
              cloudMetadata = await service.fetchRemoteFilesMetadata();
              // 如果 Worker 返回空，且用户配置了 REST API 凭据，尝试从 REST API 直连拉取以双重保障
              if (cloudMetadata.isEmpty &&
                  settings.cfAccountId?.trim().isNotEmpty == true &&
                  settings.cfApiToken?.trim().isNotEmpty == true &&
                  settings.cfD1DatabaseId?.trim().isNotEmpty == true) {
                cloudMetadata = await CfD1SyncService.fetchRemoteFilesMetadataRestApi(
                  accountId: settings.cfAccountId!,
                  apiToken: settings.cfApiToken!,
                  d1DatabaseId: settings.cfD1DatabaseId!,
                );
              }
            } else if (settings.cfAccountId?.trim().isNotEmpty == true &&
                       settings.cfApiToken?.trim().isNotEmpty == true &&
                       settings.cfD1DatabaseId?.trim().isNotEmpty == true) {
              cloudMetadata = await CfD1SyncService.fetchRemoteFilesMetadataRestApi(
                accountId: settings.cfAccountId!,
                apiToken: settings.cfApiToken!,
                d1DatabaseId: settings.cfD1DatabaseId!,
              );
            }

            if (cloudMetadata.isNotEmpty) {
              addD1Log(text(
                'ℹ️ 成功拉取到 ${cloudMetadata.length} 条云端文件元数据记录进行比对',
                'Retrieved ${cloudMetadata.length} cloud file records for diff check',
              ));
            } else {
              addD1Log(text(
                'ℹ️ 云端暂无文件元数据记录，本次将执行全量上传并初始化建立文件索引',
                'No cloud file records found, uploading all files and initializing index',
              ));
            }

            // 2. 差异性对比：只挑选新增文件或已修改的文件（文件大小变化或修改时间更新）
            final filesToUpload = <File>[];

            for (final file in allLocalFiles) {
              final relativePath = file.path
                  .replaceFirst('${dataDir.path}${Platform.pathSeparator}', '')
                  .replaceAll('\\', '/');

              final stat = file.statSync();
              final localSize = stat.size;
              final localModified = stat.modified;

              final remote = cloudMetadata[relativePath];
              if (remote != null) {
                final remoteSize = (remote['file_size'] as num?)?.toInt() ?? -1;
                final remoteUpdatedStr = remote['updated_at'] as String?;
                DateTime? remoteUpdated;
                if (remoteUpdatedStr != null) {
                  remoteUpdated = DateTime.tryParse(remoteUpdatedStr);
                }

                // 如果文件大小完全一致，且云端更新时间不早于本地修改时间(留2秒容差)，则判定为无变动跳过
                if (remoteSize == localSize) {
                  if (remoteUpdated == null || !localModified.isAfter(remoteUpdated.add(const Duration(seconds: 2)))) {
                    skippedIdenticalCount++;
                    continue; // 差异对比通过：已是最新，跳过上传！
                  }
                }
              }

              filesToUpload.add(file);
            }

            if (filesToUpload.isEmpty) {
              addD1Log(text(
                '⚡ 差异比对完成：全部 $skippedIdenticalCount 个本地文件已与云端保持最新，智能跳过上传！',
                'Diff check: all $skippedIdenticalCount files identical, skipping upload!',
              ));
            } else {
              if (skippedIdenticalCount > 0) {
                addD1Log(text(
                  '⚡ 差异比对完成：$skippedIdenticalCount 个文件已是最新(已跳过)，仅增量上传 ${filesToUpload.length} 个新增/修改文件...',
                  'Diff check: $skippedIdenticalCount unchanged (skipped), uploading ${filesToUpload.length} new/modified...',
                ));
              } else {
                addD1Log(text(
                  '⚡ 开始上传 ${filesToUpload.length} 个文件至 R2 存储桶 ($bucketName)...',
                  'Uploading ${filesToUpload.length} files to R2...',
                ));
              }

              final r2Service = _createR2SyncService();

              for (int i = 0; i < filesToUpload.length; i++) {
                final file = filesToUpload[i];
                final relativePath = file.path
                    .replaceFirst('${dataDir.path}${Platform.pathSeparator}', '')
                    .replaceAll('\\', '/');
                final fileName = file.path.split(Platform.pathSeparator).last;
                final progressIndex = i + 1;

                if (settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty) {
                  final service = CfD1SyncService(workerUrl: settings.cfWorkerUrl, isDevMode: true);
                  final res = await service.uploadFileToR2(file: file, fileKey: relativePath);
                  if (res['success'] == true) {
                    newlyUploadedCount++;
                    addD1Log('  [$progressIndex/${filesToUpload.length}] ✅ 已增量同步: $relativePath');

                    // 双重保障：若填写了 REST API 凭据，同步把元数据也写一份到 D1，确保 100% 写入 D1 元数据
                    if (settings.cfAccountId?.trim().isNotEmpty == true &&
                        settings.cfApiToken?.trim().isNotEmpty == true &&
                        settings.cfD1DatabaseId?.trim().isNotEmpty == true) {
                      final lowerKey = relativePath.toLowerCase();
                      final mime = lowerKey.endsWith('.png')
                          ? 'image/png'
                          : (lowerKey.endsWith('.jpg') || lowerKey.endsWith('.jpeg'))
                              ? 'image/jpeg'
                              : 'application/octet-stream';
                      unawaited(CfD1SyncService.recordFileMetadataRestApi(
                        accountId: settings.cfAccountId!,
                        apiToken: settings.cfApiToken!,
                        d1DatabaseId: settings.cfD1DatabaseId!,
                        fileKey: relativePath,
                        fileName: fileName,
                        fileSize: file.lengthSync(),
                        mimeType: mime,
                      ));
                    }
                  } else {
                    addD1Log('  [$progressIndex/${filesToUpload.length}] ❌ 上传失败: $relativePath (${res['error'] ?? res['status']})');
                  }
                } else if (r2Service != null) {
                  final ok = await r2Service.uploadFile(file, relativePath);
                  if (ok) {
                    newlyUploadedCount++;
                    addD1Log('  [$progressIndex/${filesToUpload.length}] ✅ (S3) 已增量同步: $relativePath');

                    // 如果是 REST API 模式，同步记录文件元数据到 D1 数据库
                    if (settings.cfAccountId?.trim().isNotEmpty == true &&
                        settings.cfApiToken?.trim().isNotEmpty == true &&
                        settings.cfD1DatabaseId?.trim().isNotEmpty == true) {
                      final lowerKey = relativePath.toLowerCase();
                      final mime = lowerKey.endsWith('.png')
                          ? 'image/png'
                          : (lowerKey.endsWith('.jpg') || lowerKey.endsWith('.jpeg'))
                              ? 'image/jpeg'
                              : 'application/octet-stream';

                      await CfD1SyncService.recordFileMetadataRestApi(
                        accountId: settings.cfAccountId!,
                        apiToken: settings.cfApiToken!,
                        d1DatabaseId: settings.cfD1DatabaseId!,
                        fileKey: relativePath,
                        fileName: fileName,
                        fileSize: file.lengthSync(),
                        mimeType: mime,
                      );
                    }
                  } else {
                    addD1Log('  [$progressIndex/${filesToUpload.length}] ❌ (S3) 上传失败: $relativePath');
                  }
                } else {
                  addD1Log(text(
                    '⚠️ 提示: Cloudflare 官方安全规定，R2 存储桶写入仅支持【Worker 托管节点模式】或【R2 S3 协议模式】。当前未配置 Worker 节点或 S3 凭据，请在设置中配置。',
                    'Note: R2 upload requires Worker Node mode or S3 credentials.',
                  ));
                  break;
                }
              }

              addD1Log(text(
                '✅ R2 文件存储同步完成 (成功上传 $newlyUploadedCount/${filesToUpload.length} 个文件${skippedIdenticalCount > 0 ? "，跳过 $skippedIdenticalCount 个无变动文件" : ""})',
                '✅ R2 Sync completed ($newlyUploadedCount uploaded, $skippedIdenticalCount skipped)',
              ));
            }
          }
        } catch (e) {
          addD1Log(text('⚠️ R2 文件同步异常: $e', '⚠️ R2 Sync error: $e'));
        }
      } else {
        addD1Log(text(
          'ℹ️ 提示: 未填写「4. R2 存储桶名称（可选）」，本次已成功完成 D1 数据库记录同步。如需同步本地图片及大文件，请在上方填入存储桶名称。',
          'Note: R2 Bucket Name is blank. D1 database sync completed.',
        ));
      }

      final isSuccess = d1Result['success'] == true;
      final fileSummary = skippedIdenticalCount > 0 && newlyUploadedCount == 0
          ? '，全部本地文件均与云端保持最新(智能跳过 $skippedIdenticalCount 个)'
          : (newlyUploadedCount > 0
              ? '，新增/修改 $newlyUploadedCount 个文件已写入 R2${skippedIdenticalCount > 0 ? " (跳过 $skippedIdenticalCount 个未变动文件)" : ""}'
              : '');

      final message = isSuccess
          ? text(
              '云端差异化同步完成！便签与剪贴板已写入 D1 数据库$fileSummary',
              'Sync completed! Data and files synced.',
            )
          : d1Result['error'] ?? text('同步未完全成功', 'Sync failed');

      _lastD1SyncSuccess = isSuccess;
      _lastD1SyncMessage = message;
      _lastD1SyncTime = DateTime.now();
      _d1SyncStatusMessage = message;

      return {
        'success': isSuccess,
        'error': d1Result['error'] ?? (isSuccess ? null : message),
        'message': message,
        'd1Result': d1Result,
      };
    } catch (e) {
      final err = text('同步发生异常: $e', 'Sync error: $e');
      addD1Log('❌ $err');
      _lastD1SyncSuccess = false;
      _lastD1SyncMessage = err;
      _d1SyncStatusMessage = err;
      return {'success': false, 'error': err};
    } finally {
      _isD1Syncing = false;
      notifyListeners();
    }
  }

  void clearD1Logs() {
    _d1SyncLogs.clear();
    notifyListeners();
  }

  Timer? _cfD1SyncTimer;

  void _scheduleCfD1AutoSync() {
    _cfD1SyncTimer?.cancel();
    final isWorkerConfigured = settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty;
    final isRestConfigured = settings.cfD1Mode == 1 &&
        settings.cfAccountId?.trim().isNotEmpty == true &&
        settings.cfApiToken?.trim().isNotEmpty == true &&
        settings.cfD1DatabaseId?.trim().isNotEmpty == true;

    if ((!isWorkerConfigured && !isRestConfigured) || !settings.cfD1AutoSync) return;

    final intervalMinutes =
        settings.cfD1SyncIntervalMinutes > 0 ? settings.cfD1SyncIntervalMinutes : 5;

    _cfD1SyncTimer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
      if (!_isD1Syncing && !_isShuttingDown) {
        addD1Log(text('⏰ 触发定时自动增量同步 (每 $intervalMinutes 分钟)...', 'Triggering scheduled auto-sync ($intervalMinutes min)...'));
        syncAllLocalDataAndFiles(isManual: false);
      }
    });

    // 延迟 10 秒后触发初次启动/配置变更后的静默同步
    Timer(const Duration(seconds: 10), () {
      if (!_isD1Syncing && !_isShuttingDown && settings.cfD1AutoSync) {
        syncAllLocalDataAndFiles(isManual: false);
      }
    });
  }

  void _scheduleR2AutoSync() {
    _r2SyncTimer?.cancel();
    if (!settings.r2Enabled || !settings.r2AutoSync) return;

    final intervalMinutes =
        settings.r2SyncIntervalMinutes > 0 ? settings.r2SyncIntervalMinutes : 5;
    _r2SyncTimer = Timer.periodic(Duration(minutes: intervalMinutes), (_) {
      syncWithR2(isManual: false);
    });

    Timer(const Duration(seconds: 5), () {
      if (settings.r2Enabled && settings.r2AutoSync && !_isR2Syncing) {
        syncWithR2(isManual: false);
      }
    });
  }

  Future<void> quit() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;

    // Immediately hide the window to avoid UI freeze/lag visible to the user
    try {
      await windowManager.hide();
    } catch (e) {
      debugPrint('Failed to hide window during quit: $e');
    }

    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await forceSaveNotesIfPending();
    await forceSaveSettingsIfPending();
    _cancelRuntimeTimers();
    _menuBarScrollChannel.setMethodCallHandler(null);

    await Future.wait<void>([
      if (_dirWatcher != null) _dirWatcher!.cancel(),
      if (_imagesDirWatcher != null) _imagesDirWatcher!.cancel(),
      if (_dataDirWatcher != null) _dataDirWatcher!.cancel(),
    ]);
    _dirWatcher = null;
    _imagesDirWatcher = null;
    _dataDirWatcher = null;

    // Clean up tray icon and hotkeys in parallel with a strict timeout of 200ms
    try {
      await Future.wait([
        trayManager.destroy(),
        hotKeyManager.unregisterAll(),
      ]).timeout(const Duration(milliseconds: 200));
    } catch (e) {
      debugPrint('Timeout or error during tray/hotkey destruction: $e');
    }

    exit(0);
  }

  // --- Window Trigger Configuration ---
  Future<void> applyWindowTriggerConfiguration({
    bool isStartup = false,
    Display? targetDisplay,
  }) async {
    try {
      final display =
          targetDisplay ?? _currentDisplay ?? await _getCurrentDisplay();
      final screenWidth = display.size.width;
      final screenPosition = display.visiblePosition ?? Offset.zero;

      double w;
      if (settings.isWidthPercentage) {
        w = screenWidth * (settings.panelWidthPercent / 100.0);
      } else {
        w = settings.panelWidth;
      }
      lastCalculatedWidth = w;
      final double wCollapsed =
          screenWidth; // Both macOS and Windows collapsed strip span 100% screen width
      final double hCollapsed = Platform.isMacOS ? 350.0 : 3.0;

      if (isStartup) {
        WindowOptions windowOptions = WindowOptions(
          size: Size(wCollapsed, hCollapsed),
          backgroundColor: Colors.transparent,
          skipTaskbar: true,
          titleBarStyle: TitleBarStyle.hidden,
        );

        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.setAsFrameless();
          await windowManager.setMinimumSize(const Size(1, 1));
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setHasShadow(false);
          if (Platform.isWindows) {
            await windowManager.setIgnoreMouseEvents(false);
          }

          if (settings.triggerMode == TriggerMode.hotkeyOnly) {
            await windowManager.hide();
          } else {
            final x = screenPosition.dx + (screenWidth - wCollapsed) / 2;
            if (Platform.isMacOS) {
              // WindowOptions already set the size, just position and show
              await _menuBarScrollChannel.invokeMethod(
                'setWindowFrameOnScreen',
                {'x': x, 'y': 0.0, 'width': wCollapsed, 'height': hCollapsed},
              );
              await Future.delayed(const Duration(milliseconds: 50));
              await _menuBarScrollChannel.invokeMethod('showInactive');
            } else {
              final x = screenPosition.dx + (screenWidth - wCollapsed) / 2;
              windowManager
                  .setBounds(
                    Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
                  )
                  .catchError(
                    (e) => debugPrint('Failed to set startup bounds: $e'),
                  );
              await windowManager.show();
            }
          }
        });
      } else {
        // Collapsed state: hide or position collapsed bar
        // Only reset the native window configuration if the panel is currently collapsed.
        // If the panel is expanded (e.g. showing the settings dialog), we do not want to hide the window.
        if (!isExpanded) {
          await windowManager.setHasShadow(false);
          if (settings.triggerMode == TriggerMode.hotkeyOnly) {
            await windowManager.hide();
          } else if (Platform.isMacOS) {
            await windowManager.setIgnoreMouseEvents(true);
            await windowManager.hide();
          } else {
            // Windows: position collapsed bar on the correct screen
            final x = screenPosition.dx + (screenWidth - wCollapsed) / 2;
            windowManager
                .setBounds(
                  Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
                )
                .catchError(
                  (e) => debugPrint('Failed to set collapsed bounds: $e'),
                );
            await windowManager.setIgnoreMouseEvents(false);
            if (!await windowManager.isVisible()) {
              await windowManager.show();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to apply window configuration: $e');
    }
  }

  void _handleMenuBarScroll(double dy) {
    if (settings.triggerMode == TriggerMode.hotkeyOnly ||
        settings.triggerMode == TriggerMode.hoverOnly) {
      return;
    }

    if (dy > 0) {
      // Throttle expand only
      final now = DateTime.now();
      if (now.difference(_lastScrollAction).inMilliseconds < 200) return;
      _lastScrollAction = now;

      if (isAnimating && !isExpanded) {
        cancelCollapseAndExpand();
      } else if (!isExpanded && !isAnimating) {
        expandPanel(focus: true, duration: const Duration(milliseconds: 250));
      }
    } else if (dy < 0) {
      if (isExpanded && !isAnimating) {
        collapsePanel(duration: const Duration(milliseconds: 250));
      }
    }
  }

  Future<dynamic> _onMenuBarScrollMethodCall(MethodCall call) async {
    if (call.method == 'onMenuBarScroll') {
      final args = call.arguments;
      if (args is Map) {
        final double dy = (args['dy'] as num).toDouble();
        // Capture screen info as a local snapshot to avoid race conditions
        final screenInfo = Map<String, double>.from(
          args.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        );
        _nativeScreenInfo = screenInfo;
        _handleMenuBarScroll(dy);
      } else {
        _handleMenuBarScroll((args as num).toDouble());
      }
    }
    return null;
  }

  // --- Expand / Collapse Actions ---
  Future<void> togglePanel() async {
    if (isAnimating) return;
    if (isExpanded) {
      await collapsePanel();
    } else {
      await expandPanel(focus: true);
    }
  }

  Future<void> expandPanel({
    bool focus = false,
    Duration duration = const Duration(milliseconds: 280),
  }) async {
    if (isExpanded || isAnimating) return;
    isAnimating = true;
    isExpanded = true;
    _restoreFocusAfterCollapse = false;
    _lastExpandTime = DateTime.now();

    try {
      final bool shouldFocus =
          focus || settings.triggerMode == TriggerMode.hotkeyOnly;

      // Set native window FIRST, then trigger animation
      if (Platform.isMacOS) {
        var info = _nativeScreenInfo;
        if (info == null) {
          info = await getActiveScreenInfo();
          _nativeScreenInfo = info;
        }
        final sw = info['width']!;
        double w = settings.isWidthPercentage
            ? sw * (settings.panelWidthPercent / 100.0)
            : settings.panelWidth;
        if (lastCalculatedWidth != w) {
          lastCalculatedWidth = w;
          notifyListeners(); // Ensure Flutter UI updates to the new width immediately
        }
        // Move window to correct screen position (cheap)
        await _menuBarScrollChannel.invokeMethod('expandOnScreen', {
          'x': info['x']! + (sw - w) / 2,
          'y': info['visibleY']!,
          'width': w,
          'height': 350.0,
          'focus': shouldFocus,
        });
        // Wait 10ms to let the OS map the window and perform the initial frame layout
        // before starting the slide transition.
        await Future.delayed(const Duration(milliseconds: 10));
      } else {
        final nativeInfo = _nativeScreenInfo;
        double screenX;
        double screenY;
        double screenWidth;
        if (nativeInfo != null) {
          screenX = nativeInfo['x']!;
          screenY = nativeInfo['visibleY'] ?? nativeInfo['y'] ?? 0.0;
          screenWidth = nativeInfo['width']!;
        } else {
          _currentDisplay = await _getCurrentDisplay();
          final position = _currentDisplay!.visiblePosition ?? Offset.zero;
          screenX = position.dx;
          screenY = position.dy;
          screenWidth = _currentDisplay!.size.width;
        }
        double w = settings.isWidthPercentage
            ? screenWidth * (settings.panelWidthPercent / 100.0)
            : settings.panelWidth;
        lastCalculatedWidth = w;
        await windowManager.setIgnoreMouseEvents(false);
        final targetX = screenX + (screenWidth - w) / 2;
        windowManager
            .setBounds(Rect.fromLTWH(targetX, screenY, w, 350))
            .catchError((e) {
              debugPrint('Failed to set expand bounds: $e');
            });
        await windowManager.setHasShadow(true);
        if (shouldFocus) {
          _focusManagerChannel.invokeMethod('savePreviousApp');
          await windowManager.show();
          await windowManager.focus();
          isWindowFocused = true;
          await _focusManagerChannel.invokeMethod('grabFocus');
        } else {
          await windowManager.show(inactive: true);
        }
        // Wait 10ms to let the OS map the window and perform the initial frame layout
        // before starting the slide transition.
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Now trigger animation AFTER native window is ready
      onAnimationStateChanged?.call(duration);
      _refreshPanelActivationAfterShow();
      _didGrabFocus = shouldFocus;
    } catch (e) {
      debugPrint('Failed to expand panel: $e');
    } finally {
      isAnimating = false;
      startAutoCollapseTimer();
    }
  }

  Future<void> forceSaveNotesIfPending() async {
    if (_notesSaveTimer?.isActive ?? false) {
      _notesSaveTimer?.cancel();
      await _saveNotes();
    }
  }

  Future<void> forceSaveSettingsIfPending() async {
    if (_settingsSaveDebounce?.isActive ?? false) {
      _settingsSaveDebounce?.cancel();
      await _prefs.setString('settings', jsonEncode(settings.toJson()));
    }
  }

  Future<void> collapsePanel({
    Duration duration = const Duration(milliseconds: 230),
  }) async {
    if (!isExpanded || isAnimating) return;
    _autoCollapseTimer?.cancel();
    isAnimating = true;
    isExpanded = false;

    // Unfocus any active text inputs immediately to hide the OS IME and prevent cursor layout calculations
    // from blocking the main UI thread during the sliding animation.
    FocusManager.instance.primaryFocus?.unfocus();

    if (isDialogOpen) {
      try {
        final context = navigatorKey.currentContext;
        if (context != null) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        debugPrint('Failed to auto-close dialogs on collapse: $e');
      }
      isDialogOpen = false;
    }

    _restoreFocusAfterCollapse = _didGrabFocus;
    _didGrabFocus = false;

    onAnimationStateChanged?.call(duration);

    // We wait for the sliding animation to complete inside the UI before resizing the native window.
    // The UI calls AppState.onCollapseAnimationFinished() to finalize this.
  }

  Future<void> onCollapseAnimationFinished() async {
    isAnimating = false;
    _currentDisplay = null;
    _nativeScreenInfo = null;

    if (Platform.isMacOS) {
      try {
        await windowManager.setIgnoreMouseEvents(true);
      } catch (e) {
        debugPrint('Failed to set ignore mouse events on collapse: $e');
      }
    } else {
      try {
        final display = await _getCurrentDisplay();
        final screenWidth = display.size.width;
        final position = display.visiblePosition ?? Offset.zero;
        final x = position.dx;
        windowManager
            .setBounds(Rect.fromLTWH(x, position.dy, screenWidth, 3))
            .catchError(
              (e) => debugPrint('Failed to set collapsed bounds: $e'),
            );
        await windowManager.setIgnoreMouseEvents(false);
      } catch (e) {
        debugPrint('Failed to resize collapsed window: $e');
      }
    }

    unawaited(_runPostCollapseMaintenance());
  }

  Future<void> _runPostCollapseMaintenance() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (!isExpanded) {
      await _restorePreviousAppAfterCollapse();
    }
    await forceSaveNotesIfPending();
  }

  void cancelCollapseAndExpand() {
    if (!isExpanded) {
      isExpanded = true;
      isAnimating = false;
      if (_restoreFocusAfterCollapse) {
        _didGrabFocus = true;
        _restoreFocusAfterCollapse = false;
      }
      onAnimationStateChanged?.call(const Duration(milliseconds: 250));
      _refreshPanelActivationAfterShow();
    }
  }

  Future<void> _restorePreviousAppAfterCollapse() async {
    if (!_restoreFocusAfterCollapse) return;
    _restoreFocusAfterCollapse = false;
    try {
      if (Platform.isMacOS) {
        await _menuBarScrollChannel.invokeMethod('restorePreviousApp');
      } else if (Platform.isWindows) {
        await _focusManagerChannel.invokeMethod('restorePreviousApp');
      }
    } catch (e) {
      debugPrint('Failed to restore previous app focus: $e');
    }
  }

  void _refreshPanelActivationAfterShow() {
    _panelActivationRefreshTimer?.cancel();
    // Postpone to 320ms to run after the 280ms panel expand animation finishes.
    // This avoids heavy rebuilds and layout passes during the transition on all platforms.
    const delay = Duration(milliseconds: 320);

    _panelActivationRefreshTimer = Timer(delay, () {
      _panelActivationRefreshTimer = null;
      if (!isExpanded) return;
      panelActivationVersion++;
      notifyListeners();
    });
  }

  void setDialogOpen(bool open) {
    isDialogOpen = open;
  }

  void cacheFileStat(String path, FileStat stat) {
    _fileStatCache[path] = stat;
  }

  void cacheIsDirectory(String path, bool isDir) {
    _isDirectoryCache[path] = isDir;
  }

  void setNoteEditorFocused(bool focused) {
    _isNoteEditorFocused = focused;
  }

  void updateFileDisplaySize(double value) {
    fileDisplaySize = value;
    notifyListeners();
  }

  void startAutoCollapseTimer({
    bool ignoreEditableFocus = false,
    bool collapseImmediatelyWhenZero = false,
  }) {
    _autoCollapseTimer?.cancel();
    if (isDialogOpen || isMouseInside) return;
    final delay = settings.autoCollapseDelay;
    if (delay >= AppSettings.maxAutoCollapseDelay) return;
    if (!isExpanded || isAnimating) return;
    if (!ignoreEditableFocus && _isNoteEditorFocused) return;
    if (ignoreEditableFocus) {
      _isNoteEditorFocused = false;
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (delay <= 0) {
      // 0 seconds means only an explicit external focus change can collapse it.
      // Mouse-exit callers leave collapseImmediatelyWhenZero as false.
      if (collapseImmediatelyWhenZero) {
        collapsePanel();
      }
      return;
    }
    _autoCollapseTimer = Timer(Duration(seconds: delay), () {
      if (isExpanded &&
          !isAnimating &&
          !isDialogOpen &&
          !isMouseInside &&
          (ignoreEditableFocus || !_isNoteEditorFocused)) {
        collapsePanel();
      }
    });
  }

  void cancelAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
  }

  // --- Window Listeners ---
  @override
  void onWindowBlur() {
    isWindowFocused = false;
    // User clicked away — don't restore focus when auto-collapsing later
    _didGrabFocus = false;

    // Windows / macOS: Avoid closing due to transient blur events during launch
    if (_lastExpandTime != null &&
        DateTime.now().difference(_lastExpandTime!) <
            const Duration(milliseconds: 200)) {
      return;
    }

    isMouseInside = false;

    if (isAnimating) {
      // If we are currently animating (expanding), check again once it finishes
      Timer(const Duration(milliseconds: 300), () {
        if (!isWindowFocused) {
          startAutoCollapseTimer(
            ignoreEditableFocus: true,
            collapseImmediatelyWhenZero: true,
          );
        }
      });
      return;
    }

    // 失去焦点时启动自动收起计时器
    startAutoCollapseTimer(
      ignoreEditableFocus: true,
      collapseImmediatelyWhenZero: true,
    );
  }

  @override
  void onWindowFocus() {
    isWindowFocused = true;
    // Cancel auto-collapse timer when window is focused
    cancelAutoCollapseTimer();
  }

  // --- Settings Persistence ---
  void _loadSettings() {
    final settingsJson = _prefs.getString('settings');
    if (settingsJson != null) {
      try {
        settings = AppSettings.fromJson(jsonDecode(settingsJson));
      } catch (e) {
        settings = AppSettings();
      }
    } else {
      settings = AppSettings();
    }
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    final oldPath = settings.customFilesPath;
    final langChanged = settings.languageCode != newSettings.languageCode;
    _settingsSaveDebounce?.cancel();
    settings = newSettings;
    final didTrimClipboardHistory = _trimClipboardHistoryToLimit();
    await _prefs.setString('settings', jsonEncode(settings.toJson()));
    if (didTrimClipboardHistory) {
      await _saveClipboardHistory();
    }

    // Reconfigure hooks & window positions
    await _setupHotkeys();
    await applyWindowTriggerConfiguration();

    if (langChanged) {
      await _setupTray();
    }

    if (oldPath != newSettings.customFilesPath) {
      await _scanStoredFiles();
    }
    _scheduleR2AutoSync();
    _scheduleCfD1AutoSync();
    notifyListeners();
  }

  bool get _supportsLaunchAtStartup => Platform.isWindows || Platform.isMacOS;

  Future<void> _syncLaunchAtStartupSetting() async {
    if (!_supportsLaunchAtStartup) return;
    try {
      final enabled = await _launchAtStartupChannel.invokeMethod<bool>(
        'isEnabled',
      );
      if (enabled == null || enabled == settings.launchAtStartup) return;
      settings = settings.copyWith(launchAtStartup: enabled);
      await _prefs.setString('settings', jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Failed to sync launch-at-startup setting: $e');
    }
  }

  Future<void> toggleLaunchAtStartup() async {
    if (!_supportsLaunchAtStartup) return;
    final enabled = !settings.launchAtStartup;
    try {
      await _launchAtStartupChannel.invokeMethod('setEnabled', {
        'enabled': enabled,
      });
      settings = settings.copyWith(launchAtStartup: enabled);
      await _prefs.setString('settings', jsonEncode(settings.toJson()));
      await _setupTray();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update launch-at-startup setting: $e');
      await _syncLaunchAtStartupSetting();
      await _setupTray();
      notifyListeners();
    }
  }

  void updateTextContentFontSize(double value) {
    final normalized = AppSettings.normalizeTextContentFontSize(value);
    if ((settings.textContentFontSize - normalized).abs() < 0.01) return;

    settings = settings.copyWith(textContentFontSize: normalized);
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      _settingsSaveDebounce = null;
      unawaited(_prefs.setString('settings', jsonEncode(settings.toJson())));
    });
    notifyListeners();
  }

  bool _trimClipboardHistoryToLimit() {
    final limit = settings.clipboardHistoryLimit;
    if (clipboardHistory.length <= limit) return false;

    final removedItems = clipboardHistory.sublist(limit);
    clipboardHistory = clipboardHistory.take(limit).toList();
    for (final item in removedItems) {
      _itemTypeCache.remove(item.id);
      _deleteClipboardImageIfUnused(item);
    }
    return true;
  }

  void _deleteClipboardImageIfUnused(ClipboardItem item) {
    if (item.imagePath == null) return;

    final path = getImagePath(item);
    final stillHasReference =
        clipboardHistory.any(
          (x) => x.imagePath != null && getImagePath(x) == path,
        ) ||
        clipboardFavorites.any(
          (x) => x.imagePath != null && getImagePath(x) == path,
        );
    if (stillHasReference) return;

    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      debugPrint('Failed to delete unused clipboard image: $e');
    }
  }

  PhysicalKeyboardKey? _getPhysicalKey(String name) {
    final cleanName = name.trim().toLowerCase();
    if (cleanName == 'space') return PhysicalKeyboardKey.space;
    final letterMap = {
      'a': PhysicalKeyboardKey.keyA,
      'b': PhysicalKeyboardKey.keyB,
      'c': PhysicalKeyboardKey.keyC,
      'd': PhysicalKeyboardKey.keyD,
      'e': PhysicalKeyboardKey.keyE,
      'f': PhysicalKeyboardKey.keyF,
      'g': PhysicalKeyboardKey.keyG,
      'h': PhysicalKeyboardKey.keyH,
      'i': PhysicalKeyboardKey.keyI,
      'j': PhysicalKeyboardKey.keyJ,
      'k': PhysicalKeyboardKey.keyK,
      'l': PhysicalKeyboardKey.keyL,
      'm': PhysicalKeyboardKey.keyM,
      'n': PhysicalKeyboardKey.keyN,
      'o': PhysicalKeyboardKey.keyO,
      'p': PhysicalKeyboardKey.keyP,
      'q': PhysicalKeyboardKey.keyQ,
      'r': PhysicalKeyboardKey.keyR,
      's': PhysicalKeyboardKey.keyS,
      't': PhysicalKeyboardKey.keyT,
      'u': PhysicalKeyboardKey.keyU,
      'v': PhysicalKeyboardKey.keyV,
      'w': PhysicalKeyboardKey.keyW,
      'x': PhysicalKeyboardKey.keyX,
      'y': PhysicalKeyboardKey.keyY,
      'z': PhysicalKeyboardKey.keyZ,
      '0': PhysicalKeyboardKey.digit0,
      '1': PhysicalKeyboardKey.digit1,
      '2': PhysicalKeyboardKey.digit2,
      '3': PhysicalKeyboardKey.digit3,
      '4': PhysicalKeyboardKey.digit4,
      '5': PhysicalKeyboardKey.digit5,
      '6': PhysicalKeyboardKey.digit6,
      '7': PhysicalKeyboardKey.digit7,
      '8': PhysicalKeyboardKey.digit8,
      '9': PhysicalKeyboardKey.digit9,
    };
    return letterMap[cleanName];
  }

  Future<void> _setupHotkeys() async {
    await hotKeyManager.unregisterAll();
    if (settings.triggerMode == TriggerMode.hoverOnly ||
        settings.triggerMode == TriggerMode.scrollOnly) {
      return;
    }

    PhysicalKeyboardKey? key;
    List<HotKeyModifier> modifiers = [];

    final parts = settings.hotkey.toLowerCase().split('+');
    for (var part in parts) {
      if (part == 'alt') {
        modifiers.add(HotKeyModifier.alt);
      } else if (part == 'ctrl' || part == 'control') {
        modifiers.add(HotKeyModifier.control);
      } else if (part == 'shift') {
        modifiers.add(HotKeyModifier.shift);
      } else if (part == 'meta' || part == 'win' || part == 'command') {
        modifiers.add(HotKeyModifier.meta);
      } else {
        key = _getPhysicalKey(part);
      }
    }

    key ??= PhysicalKeyboardKey.keyU;
    if (modifiers.isEmpty) modifiers.add(HotKeyModifier.alt);

    HotKey hotkey = HotKey(
      key: key,
      modifiers: modifiers,
      scope: HotKeyScope.system, // Global shortcut
    );

    await hotKeyManager.register(
      hotkey,
      keyDownHandler: (hotKey) {
        togglePanel();
      },
    );
  }

  // --- System Tray ---
  Future<void> _setupTray() async {
    try {
      if (Platform.isWindows) {
        _trayIconPath = 'assets/images/tray_icon.ico';
      } else {
        _trayIconPath = 'assets/images/tray_icon.png';
      }
      await trayManager.setIcon(_trayIconPath);
    } catch (e) {
      debugPrint('Failed to set tray icon: $e');
    }

    final menuItems = [
      MenuItem(key: 'toggle', label: text('显示/隐藏 PodQuick', 'Show/Hide PodQuick')),
      if (_supportsLaunchAtStartup)
        MenuItem.checkbox(
          key: 'launchAtStartup',
          label: text('开机自启动', 'Launch at Startup'),
          checked: settings.launchAtStartup,
        ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: text('退出', 'Quit')),
    ];
    await trayManager.setContextMenu(Menu(items: menuItems));
    await trayManager.setToolTip(text('PodQuick 助手', 'PodQuick Helper'));
  }

  @override
  void onTrayIconMouseDown() {
    togglePanel();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (_isShuttingDown) return;
    if (menuItem.key == 'toggle') {
      togglePanel();
    } else if (menuItem.key == 'launchAtStartup') {
      unawaited(toggleLaunchAtStartup());
    } else if (menuItem.key == 'quit') {
      unawaited(quit());
    }
  }

  String _defaultDataDirSync = '';
  String get defaultDataDirectoryPath => _defaultDataDirSync;

  String getDataDirectoryPathSync() {
    if (settings.dataDirectory != null &&
        settings.dataDirectory!.trim().isNotEmpty) {
      return settings.dataDirectory!.trim().replaceAll('\\', '/');
    }
    return _defaultDataDirSync;
  }

  Future<String> getDataDirectoryPath() async {
    return getDataDirectoryPathSync();
  }

  String? _readMacDeviceName(String key) {
    if (!Platform.isMacOS) return null;
    try {
      final result = Process.runSync('/usr/sbin/scutil', ['--get', key]);
      if (result.exitCode == 0) {
        final value = result.stdout.toString().trim();
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    return null;
  }

  List<String> _getRawDeviceNameCandidates() {
    final names = <String>[];

    void add(String? value) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      if (!names.contains(trimmed)) names.add(trimmed);
    }

    add(_readMacDeviceName('LocalHostName'));
    add(_readMacDeviceName('ComputerName'));
    add(_readMacDeviceName('HostName'));

    try {
      add(Platform.localHostname);
    } catch (_) {
      // Fall back below.
    }

    return names.isEmpty ? ['default'] : names;
  }

  String _getRawDeviceName() {
    return _getRawDeviceNameCandidates().first;
  }

  String _cleanDeviceName(String rawName) {
    var name = rawName.trim();
    name = name.replaceFirst(
      RegExp(r'\.(local|lan)$', caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    name = name.replaceAll(RegExp(r'\s+'), '-');
    name = name.replaceAll(RegExp(r'-{2,}'), '-');
    name = name.replaceAll(RegExp(r'^[.\-]+|[.\-]+$'), '');
    return name.isEmpty ? 'default' : name;
  }

  String _getCleanDeviceName() {
    return _cleanDeviceName(_getRawDeviceName());
  }

  String _getClipboardHistoryFilename() {
    return 'clipboard_history-${_getCleanDeviceName()}.json';
  }

  Set<String> _getLegacyClipboardHistoryFilenames() {
    final current = _getClipboardHistoryFilename();
    final legacyNames = <String>{};
    for (final rawName in _getRawDeviceNameCandidates()) {
      final safeRaw = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
      legacyNames.add('clipboard_history-$safeRaw.json');
      legacyNames.add(
        'clipboard_history-${safeRaw.replaceAll(RegExp(r'\s+'), '-')}.json',
      );
      legacyNames.add('clipboard_history-${_cleanDeviceName(rawName)}.json');
    }
    legacyNames.remove(current);
    legacyNames.removeWhere(
      (name) => name.trim().isEmpty || name == 'clipboard_history-.json',
    );
    return legacyNames;
  }

  List<dynamic>? _decodeJsonList(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  String _jsonItemIdentity(dynamic item) {
    if (item is Map) {
      final id = item['id'];
      if (id is String && id.isNotEmpty) return 'id:$id';
      return 'fallback:${item['content']}|${item['timestamp']}|${item['imagePath']}';
    }
    return 'raw:${jsonEncode(item)}';
  }

  String? _mergeJsonListStrings(String? primaryJson, String incomingJson) {
    final incoming = _decodeJsonList(incomingJson);
    if (incoming == null) return primaryJson;

    final primary = primaryJson == null
        ? <dynamic>[]
        : (_decodeJsonList(primaryJson) ?? <dynamic>[]);
    final seen = primary.map(_jsonItemIdentity).toSet();
    for (final item in incoming) {
      final key = _jsonItemIdentity(item);
      if (seen.add(key)) {
        primary.add(item);
      }
    }
    return jsonEncode(primary);
  }

  File? _findCurrentDeviceHistoryFile(
    Directory dir, {
    bool includeDeviceAgnostic = false,
  }) {
    final current = File('${dir.path}/${_getClipboardHistoryFilename()}');
    if (current.existsSync()) return current;

    for (final fileName in _getLegacyClipboardHistoryFilenames()) {
      final legacy = File('${dir.path}/$fileName');
      if (legacy.existsSync()) return legacy;
    }

    if (includeDeviceAgnostic) {
      final legacy = File('${dir.path}/clipboard_history.json');
      if (legacy.existsSync()) return legacy;
    }
    return null;
  }

  Future<String?> _migrateClipboardHistoryFilenameIfNeeded(
    String dataDir,
  ) async {
    final currentFile = File('$dataDir/${_getClipboardHistoryFilename()}');
    String? mergedJson;
    if (await currentFile.exists()) {
      try {
        mergedJson = await currentFile.readAsString();
      } catch (e) {
        debugPrint(
          'Failed to read current clipboard history during migration: $e',
        );
      }
    }

    final migratedFiles = <File>[];
    for (final fileName in _getLegacyClipboardHistoryFilenames()) {
      final legacyFile = File('$dataDir/$fileName');
      if (!await legacyFile.exists()) continue;
      try {
        final legacyJson = await legacyFile.readAsString();
        mergedJson =
            _mergeJsonListStrings(mergedJson, legacyJson) ?? legacyJson;
        migratedFiles.add(legacyFile);
      } catch (e) {
        debugPrint(
          'Failed to migrate clipboard history file ${legacyFile.path}: $e',
        );
      }
    }

    if (migratedFiles.isEmpty || mergedJson == null) {
      return mergedJson;
    }

    try {
      if (!await currentFile.parent.exists()) {
        await currentFile.parent.create(recursive: true);
      }
      await currentFile.writeAsString(mergedJson);
      for (final legacyFile in migratedFiles) {
        try {
          await legacyFile.delete();
        } catch (_) {}
      }
      return mergedJson;
    } catch (e) {
      debugPrint('Failed to write migrated clipboard history file: $e');
      return mergedJson;
    }
  }

  String getImagePath(ClipboardItem item) {
    if (item.imagePath == null) return '';
    final path = item.imagePath!;
    if (path.contains(':/') || path.contains(':\\') || path.startsWith('/')) {
      final normalized = path.replaceAll('\\', '/');
      if (normalized.contains('/clipboard_images/')) {
        final filename = normalized.split('/clipboard_images/').last;
        return '${getDataDirectoryPathSync()}/clipboard_images/$filename';
      }
      return path;
    }
    return '${getDataDirectoryPathSync()}/$path';
  }

  Future<void> _migrateLegacyDirectories() async {
    try {
      final dataDir = getDataDirectoryPathSync();
      final appSupport = await getApplicationSupportDirectory();

      // Ensure data directory exists
      final dataDirObj = Directory(dataDir);
      if (!await dataDirObj.exists()) {
        await dataDirObj.create(recursive: true);
      }

      // 1. Migrate clipboard images if old dir exists and new dir doesn't exist
      final oldImagesDir = Directory('${appSupport.path}/clipboard_images');
      final newImagesDir = Directory('$dataDir/clipboard_images');
      if (await oldImagesDir.exists() &&
          !await newImagesDir.exists() &&
          oldImagesDir.path != newImagesDir.path) {
        await newImagesDir.create(recursive: true);
        await for (final entity in oldImagesDir.list()) {
          if (entity is File) {
            final name = entity.path
                .replaceAll('\\', '/')
                .split('/')
                .where((s) => s.isNotEmpty)
                .last;
            final newPath = '${newImagesDir.path}/$name';
            await entity.copy(newPath);
          }
        }
        try {
          await oldImagesDir.delete(recursive: true);
        } catch (_) {}
      }

      // 2. Migrate files if old default files dir exists and new files dir doesn't exist
      final oldDefaultFilesPath = _getOldDefaultFilesPath();
      final oldFilesDir = oldDefaultFilesPath.isNotEmpty
          ? Directory(oldDefaultFilesPath)
          : null;
      final newFilesDir = Directory('$dataDir/files');
      if (oldFilesDir != null &&
          await oldFilesDir.exists() &&
          !await newFilesDir.exists() &&
          oldFilesDir.path != newFilesDir.path) {
        await newFilesDir.create(recursive: true);
        await _copyDirectory(oldFilesDir, newFilesDir);
        try {
          await oldFilesDir.delete(recursive: true);
        } catch (_) {}
      }

      // 3. Migrate custom files path if set in AppSettings
      if (settings.customFilesPath != null &&
          settings.customFilesPath!.trim().isNotEmpty) {
        final oldCustomDir = Directory(settings.customFilesPath!.trim());
        if (await oldCustomDir.exists() &&
            oldCustomDir.path != newFilesDir.path) {
          await newFilesDir.create(recursive: true);
          await _copyDirectory(oldCustomDir, newFilesDir);
          final updated = settings.copyWith(customFilesPath: '');
          await updateSettings(updated);
          try {
            await oldCustomDir.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Failed to run legacy directories migration: $e');
    }
  }

  String _getOldDefaultFilesPath() {
    late String basePath;
    String folderName = 'PodQuick暂存';
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final oldPath = '$userProfile\\Documents\\Pod暂存';
      if (Directory(oldPath).existsSync()) {
        folderName = 'Pod暂存';
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      final oldPath = '$home/Documents/Pod暂存';
      if (Directory(oldPath).existsSync()) {
        folderName = 'Pod暂存';
      }
    }

    if (Platform.isWindows) {
      basePath = Platform.environment['USERPROFILE'] ?? '';
      basePath = '$basePath\\Documents\\$folderName';
    } else if (Platform.isMacOS) {
      basePath = Platform.environment['HOME'] ?? '';
      basePath = '$basePath/Documents/$folderName';
    } else {
      basePath = '';
    }
    return basePath;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    await for (var entity in source.list(recursive: false)) {
      final name = entity.path
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty)
          .last;
      if (entity is Directory) {
        final newDirectory = Directory('${destination.path}/$name');
        await newDirectory.create(recursive: true);
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy('${destination.path}/$name');
      }
    }
  }

  Future<bool> changeDataDirectory(String newPath) async {
    final cleanNewPath = newPath.trim().replaceAll('\\', '/');
    final currentPath = getDataDirectoryPathSync();
    if (cleanNewPath.toLowerCase() == currentPath.toLowerCase()) {
      return true;
    }

    final targetDir = Directory(cleanNewPath);
    if (!targetDir.existsSync()) {
      try {
        targetDir.createSync(recursive: true);
      } catch (e) {
        debugPrint('Failed to create target directory: $e');
        return false;
      }
    }

    final sourceDir = Directory(currentPath);

    // 1. Copy data files
    try {
      // Copy general data files
      final filesToMove = ['notes.json', 'clipboard_favorites.json'];
      for (final fileName in filesToMove) {
        final oldFile = File('${sourceDir.path}/$fileName');
        if (oldFile.existsSync()) {
          final newFile = File('${targetDir.path}/$fileName');
          oldFile.copySync(newFile.path);
        }
      }

      // Copy all clipboard history files (including device-specific ones and legacy history)
      if (sourceDir.existsSync()) {
        for (final entity in sourceDir.listSync()) {
          if (entity is File) {
            final name = entity.path.replaceAll('\\', '/').split('/').last;
            if (name == 'clipboard_history.json' ||
                (name.startsWith('clipboard_history-') &&
                    name.endsWith('.json'))) {
              entity.copySync('${targetDir.path}/$name');
            }
          }
        }
      }

      // 2. Copy clipboard_images directory
      final oldImagesDir = Directory('${sourceDir.path}/clipboard_images');
      if (oldImagesDir.existsSync()) {
        final newImagesDir = Directory('${targetDir.path}/clipboard_images');
        if (!newImagesDir.existsSync()) {
          newImagesDir.createSync(recursive: true);
        }
        for (final entity in oldImagesDir.listSync()) {
          if (entity is File) {
            final name = entity.path
                .replaceAll('\\', '/')
                .split('/')
                .where((s) => s.isNotEmpty)
                .last;
            final newFilePath = '${newImagesDir.path}/$name';
            entity.copySync(newFilePath);
          }
        }
      }

      // 3. Copy files directory
      final oldFilesDir = Directory('${sourceDir.path}/files');
      if (oldFilesDir.existsSync()) {
        final newFilesDir = Directory('${targetDir.path}/files');
        if (!newFilesDir.existsSync()) {
          newFilesDir.createSync(recursive: true);
        }
        await _copyDirectory(oldFilesDir, newFilesDir);
      }
    } catch (e) {
      debugPrint('Migration copying failed: $e');
      return false;
    }

    // 4. Update AppSettings
    final updatedSettings = settings.copyWith(dataDirectory: cleanNewPath);
    await updateSettings(updatedSettings);

    // 5. Cleanup old files (non-critical)
    try {
      final filesToDelete = ['notes.json', 'clipboard_favorites.json'];
      for (final fileName in filesToDelete) {
        final oldFile = File('${sourceDir.path}/$fileName');
        if (oldFile.existsSync()) {
          oldFile.deleteSync();
        }
      }

      // Delete all clipboard history files (including device-specific ones and legacy history)
      if (sourceDir.existsSync()) {
        for (final entity in sourceDir.listSync()) {
          if (entity is File) {
            final name = entity.path.replaceAll('\\', '/').split('/').last;
            if (name == 'clipboard_history.json' ||
                (name.startsWith('clipboard_history-') &&
                    name.endsWith('.json'))) {
              try {
                entity.deleteSync();
              } catch (_) {}
            }
          }
        }
      }

      final oldImagesDir = Directory('${sourceDir.path}/clipboard_images');
      if (oldImagesDir.existsSync()) {
        oldImagesDir.deleteSync(recursive: true);
      }

      final oldFilesDir = Directory('${sourceDir.path}/files');
      if (oldFilesDir.existsSync()) {
        oldFilesDir.deleteSync(recursive: true);
      }
    } catch (e) {
      debugPrint('Migration cleanup failed (non-critical): $e');
    }

    // 6. Reload local data inside new directory
    await _loadNotes();
    await _loadClipboardHistory();
    await _scanStoredFiles();
    await _startWatchingImagesDirectory();
    await _startWatchingDataDirectory();

    notifyListeners();
    return true;
  }

  Future<bool> syncDataFromDirectory(String sourcePath) async {
    final cleanSourcePath = sourcePath.trim().replaceAll('\\', '/');
    final currentPath = getDataDirectoryPathSync();
    if (cleanSourcePath.toLowerCase() == currentPath.toLowerCase()) {
      return true; // Same directory, nothing to sync
    }

    final sourceDir = Directory(cleanSourcePath);
    if (!sourceDir.existsSync()) {
      return false;
    }

    final targetDir = Directory(currentPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    try {
      // 1. Sync notes.json (Merge)
      final sourceNotesFile = File('${sourceDir.path}/notes.json');
      if (sourceNotesFile.existsSync()) {
        final targetNotesFile = File('${targetDir.path}/notes.json');
        List<dynamic> mergedNotesJson = [];

        List<dynamic> sourceNotes = [];
        try {
          sourceNotes = jsonDecode(sourceNotesFile.readAsStringSync()) as List;
        } catch (_) {}

        if (targetNotesFile.existsSync()) {
          List<dynamic> targetNotes = [];
          try {
            targetNotes =
                jsonDecode(targetNotesFile.readAsStringSync()) as List;
          } catch (_) {}

          final targetIds = targetNotes.map((n) => n['id']).toSet();
          mergedNotesJson.addAll(targetNotes);
          for (final note in sourceNotes) {
            if (!targetIds.contains(note['id'])) {
              mergedNotesJson.add(note);
            }
          }
        } else {
          mergedNotesJson = sourceNotes;
        }
        targetNotesFile.writeAsStringSync(jsonEncode(mergedNotesJson));
      }

      // 2. Sync clipboard_history-[deviceName].json (Merge)
      final sourceHistoryFile = _findCurrentDeviceHistoryFile(
        sourceDir,
        includeDeviceAgnostic: true,
      );
      if (sourceHistoryFile != null) {
        final targetHistoryFile = File(
          '${targetDir.path}/${_getClipboardHistoryFilename()}',
        );
        List<dynamic> mergedHistoryJson = [];

        List<dynamic> sourceHistory = [];
        try {
          sourceHistory =
              jsonDecode(sourceHistoryFile.readAsStringSync()) as List;
        } catch (_) {}

        if (targetHistoryFile.existsSync()) {
          List<dynamic> targetHistory = [];
          try {
            targetHistory =
                jsonDecode(targetHistoryFile.readAsStringSync()) as List;
          } catch (_) {}

          final targetIds = targetHistory.map((x) => x['id']).toSet();
          mergedHistoryJson.addAll(targetHistory);
          for (final item in sourceHistory) {
            if (!targetIds.contains(item['id'])) {
              mergedHistoryJson.add(item);
            }
          }
        } else {
          mergedHistoryJson = sourceHistory;
        }
        targetHistoryFile.writeAsStringSync(jsonEncode(mergedHistoryJson));
      }

      // 3. Sync clipboard_favorites.json (Merge)
      final sourceFavoritesFile = File(
        '${sourceDir.path}/clipboard_favorites.json',
      );
      if (sourceFavoritesFile.existsSync()) {
        final targetFavoritesFile = File(
          '${targetDir.path}/clipboard_favorites.json',
        );
        List<dynamic> mergedFavoritesJson = [];

        List<dynamic> sourceFavorites = [];
        try {
          sourceFavorites =
              jsonDecode(sourceFavoritesFile.readAsStringSync()) as List;
        } catch (_) {}

        if (targetFavoritesFile.existsSync()) {
          List<dynamic> targetFavorites = [];
          try {
            targetFavorites =
                jsonDecode(targetFavoritesFile.readAsStringSync()) as List;
          } catch (_) {}

          final targetIds = targetFavorites.map((x) => x['id']).toSet();
          mergedFavoritesJson.addAll(targetFavorites);
          for (final item in sourceFavorites) {
            if (!targetIds.contains(item['id'])) {
              mergedFavoritesJson.add(item);
            }
          }
        } else {
          mergedFavoritesJson = sourceFavorites;
        }
        targetFavoritesFile.writeAsStringSync(jsonEncode(mergedFavoritesJson));
      }

      // 4. Sync clipboard_images (Copy missing)
      final sourceImagesDir = Directory('${sourceDir.path}/clipboard_images');
      if (sourceImagesDir.existsSync()) {
        final targetImagesDir = Directory('${targetDir.path}/clipboard_images');
        if (!targetImagesDir.existsSync()) {
          targetImagesDir.createSync(recursive: true);
        }
        for (final entity in sourceImagesDir.listSync()) {
          if (entity is File) {
            final name = entity.path
                .replaceAll('\\', '/')
                .split('/')
                .where((s) => s.isNotEmpty)
                .last;
            final targetFilePath = '${targetImagesDir.path}/$name';
            if (!File(targetFilePath).existsSync()) {
              entity.copySync(targetFilePath);
            }
          }
        }
      }

      // 5. Sync files (Copy missing)
      final sourceFilesDir = Directory('${sourceDir.path}/files');
      if (sourceFilesDir.existsSync()) {
        final targetFilesDir = Directory('${targetDir.path}/files');
        if (!targetFilesDir.existsSync()) {
          targetFilesDir.createSync(recursive: true);
        }
        await _copyDirectory(sourceFilesDir, targetFilesDir);
      }

      await reloadAllData();
      return true;
    } catch (e) {
      debugPrint('Manual sync failed: $e');
      return false;
    }
  }

  Future<void> reloadAllData() async {
    await _loadNotes();
    await _loadClipboardHistory();
    await _scanStoredFiles();
    notifyListeners();
  }

  // --- Clipboard History ---
  Future<String> _getImagesDirectoryPath() async {
    final dataDir = getDataDirectoryPathSync();
    final imagesDir = Directory('$dataDir/clipboard_images');
    if (!imagesDir.existsSync()) {
      imagesDir.createSync(recursive: true);
    }
    return imagesDir.path;
  }

  bool _isOwnApp(String? appName) {
    if (appName == null) return false;
    try {
      final exeName = Platform.resolvedExecutable
          .split(RegExp(r'[\\/]'))
          .last
          .split('.')
          .first
          .toLowerCase();
      final lowerName = appName.toLowerCase();
      return lowerName == exeName ||
          lowerName == 'podquick' ||
          lowerName == 'pod_quick' ||
          lowerName == 'pod';
    } catch (_) {
      return appName.toLowerCase() == 'podquick' ||
          appName.toLowerCase() == 'pod_quick' ||
          appName.toLowerCase() == 'pod';
    }
  }

  Future<int?> _getNativeClipboardSequence() async {
    if ((!Platform.isWindows && !Platform.isMacOS) ||
        _nativeClipboardSequenceUnavailable) {
      return null;
    }

    try {
      final methodName = Platform.isWindows
          ? 'getClipboardSequenceNumber'
          : 'getClipboardChangeCount';
      return await _clipboardOwnerChannel.invokeMethod<int>(methodName);
    } on MissingPluginException catch (e) {
      _nativeClipboardSequenceUnavailable = true;
      debugPrint('Clipboard sequence API unavailable: $e');
      return null;
    } catch (e) {
      debugPrint('Failed to get clipboard sequence number: $e');
      return null;
    }
  }

  Future<bool> _shouldSkipUnchangedClipboard() async {
    final sequence = await _getNativeClipboardSequence();
    if (sequence == null) {
      _hasSequenceChanged = false;
      return false;
    }

    final previousSequence = _lastNativeClipboardSequence;
    _lastNativeClipboardSequence = sequence;

    if (previousSequence != null && previousSequence == sequence) {
      _hasSequenceChanged = false;
      return true;
    }

    _hasSequenceChanged = previousSequence != null;
    return false;
  }

  void _startClipboardMonitoring() {
    _clipboardOwnerChannel.setMethodCallHandler((call) async {
      if (call.method == 'onClipboardChanged') {
        _scheduleClipboardCheck();
      }
      return null;
    });

    // Schedule an initial check shortly after startup
    _scheduleClipboardCheck(delayMs: 300);
  }

  void _scheduleClipboardCheck({int delayMs = 120}) {
    _clipboardDebounceTimer?.cancel();
    _clipboardDebounceTimer = Timer(Duration(milliseconds: delayMs), () {
      _processClipboardCheck();
    });
  }

  Future<void> _processClipboardCheck() async {
    if (_isShuttingDown) return;
    if (_isCheckingClipboard) return;
    _isCheckingClipboard = true;
    if (_ignoreNextClipboardCheck) {
      _ignoreNextClipboardCheck = false;
      final sequence = await _getNativeClipboardSequence();
      if (sequence != null) {
        _lastNativeClipboardSequence = sequence;
      }
      _isCheckingClipboard = false;
      return;
    }
    try {
      // Avoid touching large clipboard payloads unless content changed.
      if (await _shouldSkipUnchangedClipboard()) {
        return;
      }

      // 1. 先检查文本，因为绝大多数情况下剪贴板中都是文本，且 Clipboard.getData 极轻量
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        final text = data.text!;
        if (text != _lastSystemClipText || _hasSequenceChanged) {
          _lastSystemClipText = text;
          _lastSystemClipImageSignature =
              null; // 切换到文本时，清空图片特征缓存，确保下次可以重新识别相同图片

          String? appName;
          String? appIconPath;
          if (Platform.isWindows || Platform.isMacOS) {
            try {
              final result = await _clipboardOwnerChannel.invokeMethod(
                'getClipboardOwner',
              );
              if (result is Map) {
                appName = result['name'] as String?;
                appIconPath = result['iconPath'] as String?;
              }
            } catch (e) {
              debugPrint('Failed to get clipboard owner info: $e');
            }
          }

          final isOwn = _isOwnApp(appName);
          final isInternalCopy = isOwn && (text == _lastAppCopiedText);

          if (!isInternalCopy) {
            await addClipboardItem(
              text,
              appName: appName,
              appIconPath: appIconPath,
            );
          }
        }
      } else {
        // 2. 文本为空或没有文本时，才去检查图片
        // 首先判断剪贴板里是否是文件，如果是文件，且全是非图片文件，则忽略其图片数据（那是文件图标）
        bool isFileIcon = false;
        try {
          final files = await Pasteboard.files();
          if (files.isNotEmpty) {
            final imageExtensions = {
              'png',
              'jpg',
              'jpeg',
              'gif',
              'webp',
              'bmp',
              'ico',
              'tiff',
              'tif',
              'heic',
              'heif',
            };
            final hasImageFile = files.any((path) {
              final ext = path.split('.').last.toLowerCase();
              return imageExtensions.contains(ext);
            });
            if (!hasImageFile) {
              isFileIcon = true;
            }
          }
        } catch (e) {
          debugPrint('Failed to check pasteboard files: $e');
        }

        if (!isFileIcon) {
          final imageBytes = await Pasteboard.image;
          if (imageBytes != null && imageBytes.isNotEmpty) {
            final imageSignature = _imageSignature(imageBytes);
            if (imageSignature != _lastSystemClipImageSignature ||
                _hasSequenceChanged) {
              _lastSystemClipImageSignature = imageSignature;
              _lastSystemClipText = ''; // 切换到图片时，清空文本缓存，确保下次可以重新识别相同文本

              String? appName;
              String? appIconPath;
              if (Platform.isWindows || Platform.isMacOS) {
                try {
                  final result = await _clipboardOwnerChannel.invokeMethod(
                    'getClipboardOwner',
                  );
                  if (result is Map) {
                    appName = result['name'] as String?;
                    appIconPath = result['iconPath'] as String?;
                  }
                } catch (e) {
                  debugPrint('Failed to get clipboard owner info: $e');
                }
              }

              final isOwn = _isOwnApp(appName);
              final isInternalCopy =
                  isOwn && (imageSignature == _lastAppCopiedImageSignature);

              if (!isInternalCopy) {
                await addClipboardImageItem(
                  imageBytes,
                  appName: appName,
                  appIconPath: appIconPath,
                  imageSignature: imageSignature,
                );
              } else {
                // 同步当前图片的签名，以防 owner 再次判定异常
                _lastAppCopiedImageSignature = imageSignature;
                _lastSystemClipImageSignature = imageSignature;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Clipboard monitoring error: $e');
    } finally {
      _isCheckingClipboard = false;
    }
  }

  Future<void> addClipboardItem(
    String content, {
    String? appName,
    String? appIconPath,
  }) async {
    // Avoid duplicates of the exact same content in recent clipboard history list
    clipboardHistory.removeWhere((item) => item.content == content);

    final newItem = ClipboardItem(
      id: _uuid.v4(),
      content: content,
      timestamp: DateTime.now(),
      appName: appName,
      appIconPath: appIconPath,
    );

    clipboardHistory.insert(0, newItem);

    _trimClipboardHistoryToLimit();

    await _saveClipboardHistory();
    notifyListeners();
  }

  Future<void> addClipboardImageItem(
    Uint8List imageBytes, {
    String? appName,
    String? appIconPath,
    String? imageSignature,
  }) async {
    try {
      final dirPath = await _getImagesDirectoryPath();
      final id = _uuid.v4();
      final filePath = '$dirPath/$id.png';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      // 去重近期图片内容（内存去重，并且可以比对全部项，不再局限于前10项）
      final currentSignature = imageSignature ?? _imageSignature(imageBytes);
      final itemsToRemove = <ClipboardItem>[];
      for (final item in clipboardHistory) {
        if (item.imagePath != null) {
          if (item.imageSignature != null) {
            if (item.imageSignature == currentSignature) {
              itemsToRemove.add(item);
            }
          } else {
            // 老版本老数据没有 signature，用原本的 legacy I/O 检查
            final oldFile = File(getImagePath(item));
            if (oldFile.existsSync()) {
              try {
                if (oldFile.lengthSync() == imageBytes.length) {
                  final oldBytes = await oldFile.readAsBytes();
                  if (_imageSignature(oldBytes) == currentSignature) {
                    itemsToRemove.add(item);
                  }
                }
              } catch (_) {}
            }
          }
        }
      }
      for (final item in itemsToRemove) {
        clipboardHistory.removeWhere((x) => x.id == item.id);
        try {
          final f = File(getImagePath(item));
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }

      final newItem = ClipboardItem(
        id: id,
        content: text('[图片]', '[Image]'),
        timestamp: DateTime.now(),
        appName: appName,
        appIconPath: appIconPath,
        imagePath: 'clipboard_images/$id.png',
        imageSignature: currentSignature,
      );

      clipboardHistory.insert(0, newItem);

      _trimClipboardHistoryToLimit();

      await _saveClipboardHistory();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to add clipboard image item: $e');
    }
  }

  Future<void> copyToClipboard(ClipboardItem item) async {
    _ignoreNextClipboardCheck = true;
    if (item.imagePath != null) {
      final file = File(getImagePath(item));
      if (file.existsSync()) {
        try {
          final bytes = await file.readAsBytes();
          final imageSignature = _imageSignature(bytes);
          _lastAppCopiedImageSignature = imageSignature;
          _lastSystemClipImageSignature = imageSignature;
          _lastSystemClipText = ''; // Clear text clip state
          _lastAppCopiedText = ''; // Clear text clip state
          await Pasteboard.writeImage(bytes);

          // 立即读回系统剪贴板中的图片以获取系统编码后的图片字节签名，彻底防止因格式转换导致签名不一致的问题
          try {
            final writtenBytes = await Pasteboard.image;
            if (writtenBytes != null && writtenBytes.isNotEmpty) {
              final clipboardSignature = _imageSignature(writtenBytes);
              _lastAppCopiedImageSignature = clipboardSignature;
              _lastSystemClipImageSignature = clipboardSignature;
            }
          } catch (e) {
            debugPrint('Failed to sync written image signature: $e');
          }

          // Update sequence number immediately to prevent the background monitor
          // from detecting this internal write as a new external copy.
          await Future.delayed(const Duration(milliseconds: 50));
          final newSeq = await _getNativeClipboardSequence();
          if (newSeq != null) {
            _lastNativeClipboardSequence = newSeq;
          }
        } catch (e) {
          debugPrint('Failed to write image to pasteboard: $e');
        }
      }
    } else {
      await copyTextToClipboard(item.content);
    }
  }

  Future<void> copyTextToClipboard(String content) async {
    _lastAppCopiedText = content;
    _lastSystemClipText = content;
    _lastSystemClipImageSignature = null; // Clear image clip state
    _lastAppCopiedImageSignature = null; // Clear image clip state
    await Clipboard.setData(ClipboardData(text: content));

    // Update sequence number immediately to prevent the background monitor
    // from detecting this internal write as a new external copy.
    await Future.delayed(const Duration(milliseconds: 50));
    final newSeq = await _getNativeClipboardSequence();
    if (newSeq != null) {
      _lastNativeClipboardSequence = newSeq;
    }
  }

  void deleteClipboardItem(String id) {
    _itemTypeCache.remove(id);
    ClipboardItem? itemToDelete;
    try {
      itemToDelete = clipboardHistory.firstWhere((item) => item.id == id);
    } catch (_) {
      try {
        itemToDelete = clipboardFavorites.firstWhere((item) => item.id == id);
      } catch (_) {}
    }

    clipboardHistory.removeWhere((item) => item.id == id);
    clipboardFavorites.removeWhere((item) => item.id == id);

    notifyListeners();

    Future.delayed(Duration.zero, () {
      _saveClipboardHistory();
      _saveClipboardFavorites();

      if (itemToDelete != null && itemToDelete.imagePath != null) {
        final path = getImagePath(itemToDelete);
        final stillHasReference =
            clipboardHistory.any((x) => getImagePath(x) == path) ||
            clipboardFavorites.any((x) => getImagePath(x) == path);
        if (!stillHasReference) {
          final file = File(path);
          file.exists().then((exists) async {
            if (exists) {
              try {
                await file.delete();
              } catch (e) {
                debugPrint('Failed to delete image file on item deletion: $e');
              }
            }
          });
        }
      }
    });
  }

  void toggleFavoriteClipboardItem(ClipboardItem item) {
    final isFav = isItemFavorite(item);
    if (isFav) {
      if (item.imagePath != null) {
        clipboardFavorites.removeWhere((x) =>
            x.imagePath != null &&
            (x.id == item.id ||
             (x.imageSignature != null && item.imageSignature != null && x.imageSignature == item.imageSignature) ||
             (x.imageSignature == null && item.imageSignature == null && getImagePath(x) == getImagePath(item))));
      } else {
        clipboardFavorites.removeWhere((x) => x.content == item.content);
      }
    } else {
      clipboardFavorites.insert(
        0,
        item.copyWith(isFavorite: true, timestamp: DateTime.now()),
      );
    }
    Future.delayed(Duration.zero, _saveClipboardFavorites);
    notifyListeners();
  }

  void clearClipboardHistory() {
    _itemTypeCache.clear();
    for (final item in clipboardHistory) {
      if (item.imagePath != null) {
        final path = getImagePath(item);
        final inFavorites = clipboardFavorites.any(
          (x) => getImagePath(x) == path,
        );
        if (!inFavorites) {
          try {
            final file = File(path);
            if (file.existsSync()) {
              file.deleteSync();
            }
          } catch (e) {
            debugPrint('Failed to delete image file during history clear: $e');
          }
        }
      }
    }
    clipboardHistory.clear();
    Future.delayed(Duration.zero, _saveClipboardHistory);
    notifyListeners();
  }

  Future<void> _cleanupUnusedClipboardImages() async {
    try {
      final dirPath = await _getImagesDirectoryPath();
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;

      final files = dir.listSync().whereType<File>();
      final usedPaths = <String>{};
      for (final item in clipboardHistory) {
        if (item.imagePath != null) {
          usedPaths.add(getImagePath(item).replaceAll('\\', '/').toLowerCase());
        }
      }
      for (final item in clipboardFavorites) {
        if (item.imagePath != null) {
          usedPaths.add(getImagePath(item).replaceAll('\\', '/').toLowerCase());
        }
      }

      for (final file in files) {
        final normalized = file.path.replaceAll('\\', '/').toLowerCase();
        if (!usedPaths.contains(normalized)) {
          try {
            file.deleteSync();
            debugPrint('Cleaned up orphaned image file: ${file.path}');
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up unused clipboard images: $e');
    }
  }

  Future<void> _loadClipboardHistory() async {
    final dataDir = getDataDirectoryPathSync();
    final migratedHistoryJson = await _migrateClipboardHistoryFilenameIfNeeded(
      dataDir,
    );

    // 1. History
    final historyFilename = _getClipboardHistoryFilename();
    final historyFile = File('$dataDir/$historyFilename');
    String? listJson = migratedHistoryJson;
    if (await historyFile.exists()) {
      try {
        listJson = await historyFile.readAsString();
      } catch (e) {
        debugPrint('Failed to read clipboard history file: $e');
      }
    } else {
      // Check if legacy device-agnostic history file exists to migrate
      final legacyFile = File('$dataDir/clipboard_history.json');
      if (await legacyFile.exists()) {
        try {
          listJson = await legacyFile.readAsString();
          // Write it to device-specific file so we don't lose history on this machine
          await historyFile.writeAsString(listJson);
        } catch (_) {}
      } else {
        // Legacy migration from SharedPreferences
        listJson = _prefs.getString('clipboard_history');
        if (listJson != null) {
          try {
            if (!await historyFile.parent.exists()) {
              await historyFile.parent.create(recursive: true);
            }
            await historyFile.writeAsString(listJson);
            await _prefs.remove('clipboard_history');
          } catch (e) {
            debugPrint(
              'Failed to migrate clipboard history from SharedPreferences: $e',
            );
          }
        }
      }
    }

    if (listJson != null) {
      _lastHistoryJsonCache = listJson;
      try {
        final decoded = jsonDecode(listJson) as List;
        clipboardHistory =
            decoded
                .map(
                  (item) =>
                      ClipboardItem.fromJson(item as Map<String, dynamic>),
                )
                .toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } catch (e) {
        clipboardHistory = [];
      }
    } else {
      clipboardHistory = [];
      _lastHistoryJsonCache = null;
    }

    // 2. Favorites
    final favoritesFile = File('$dataDir/clipboard_favorites.json');
    String? favJson;
    if (await favoritesFile.exists()) {
      try {
        favJson = await favoritesFile.readAsString();
      } catch (e) {
        debugPrint('Failed to read clipboard favorites file: $e');
      }
    } else {
      // Legacy migration from SharedPreferences
      favJson = _prefs.getString('clipboard_favorites');
      if (favJson != null) {
        try {
          if (!await favoritesFile.parent.exists()) {
            await favoritesFile.parent.create(recursive: true);
          }
          await favoritesFile.writeAsString(favJson);
          await _prefs.remove('clipboard_favorites');
        } catch (e) {
          debugPrint(
            'Failed to migrate clipboard favorites from SharedPreferences: $e',
          );
        }
      }
    }

    if (favJson != null) {
      _lastFavoritesJsonCache = favJson;
      try {
        final decoded = jsonDecode(favJson) as List;
        clipboardFavorites =
            decoded
                .map(
                  (item) =>
                      ClipboardItem.fromJson(item as Map<String, dynamic>),
                )
                .toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } catch (e) {
        clipboardFavorites = [];
      }
    } else {
      clipboardFavorites = [];
      _lastFavoritesJsonCache = null;
    }

    bool needsSaveHistory = false;
    final originalHistoryCount = clipboardHistory.length;
    final historyExistence = await Future.wait(
      clipboardHistory.map((item) async {
        if (item.imagePath != null) {
          return await File(getImagePath(item)).exists();
        }
        return true;
      }),
    );
    final newHistory = <ClipboardItem>[];
    for (int i = 0; i < clipboardHistory.length; i++) {
      if (historyExistence[i]) {
        newHistory.add(clipboardHistory[i]);
      }
    }
    clipboardHistory = newHistory;
    if (clipboardHistory.length != originalHistoryCount) {
      needsSaveHistory = true;
    }
    if (_trimClipboardHistoryToLimit()) {
      needsSaveHistory = true;
    }

    bool needsSaveFavorites = false;
    final originalFavCount = clipboardFavorites.length;
    final favExistence = await Future.wait(
      clipboardFavorites.map((item) async {
        if (item.imagePath != null) {
          return await File(getImagePath(item)).exists();
        }
        return true;
      }),
    );
    final newFavorites = <ClipboardItem>[];
    for (int i = 0; i < clipboardFavorites.length; i++) {
      if (favExistence[i]) {
        newFavorites.add(clipboardFavorites[i]);
      }
    }
    clipboardFavorites = newFavorites;
    if (clipboardFavorites.length != originalFavCount) {
      needsSaveFavorites = true;
    }

    if (needsSaveHistory) {
      await _saveClipboardHistory();
    }
    if (needsSaveFavorites) {
      await _saveClipboardFavorites();
    }
  }

  Future<void> _saveClipboardHistory() async {
    final dataDir = getDataDirectoryPathSync();
    final historyFilename = _getClipboardHistoryFilename();
    final historyFile = File('$dataDir/$historyFilename');
    try {
      if (!await historyFile.parent.exists()) {
        await historyFile.parent.create(recursive: true);
      }
      final encoded = jsonEncode(
        clipboardHistory.map((item) => item.toJson()).toList(),
      );
      _lastHistoryJsonCache = encoded;
      await historyFile.writeAsString(encoded);
    } catch (e) {
      debugPrint('Failed to save clipboard history file: $e');
    }
  }

  Future<void> _saveClipboardFavorites() async {
    final dataDir = getDataDirectoryPathSync();
    final favoritesFile = File('$dataDir/clipboard_favorites.json');
    try {
      if (!await favoritesFile.parent.exists()) {
        await favoritesFile.parent.create(recursive: true);
      }
      final encoded = jsonEncode(
        clipboardFavorites.map((item) => item.toJson()).toList(),
      );
      _lastFavoritesJsonCache = encoded;
      await favoritesFile.writeAsString(encoded);
    } catch (e) {
      debugPrint('Failed to save clipboard favorites file: $e');
    }
  }

  // --- Files Storage ---
  Future<String> getFilesDirectoryPath() => _getFilesDirectoryPath();

  Future<String> _getFilesDirectoryPath() async {
    if (settings.customFilesPath != null &&
        settings.customFilesPath!.trim().isNotEmpty) {
      final customDir = Directory(settings.customFilesPath!.trim());
      if (!customDir.existsSync()) {
        try {
          customDir.createSync(recursive: true);
        } catch (e) {
          debugPrint('Failed to create custom files directory: $e');
        }
      }
      if (customDir.existsSync()) {
        return customDir.path;
      }
    }

    final dataDir = getDataDirectoryPathSync();
    final filesDir = Directory('$dataDir/files');
    if (!filesDir.existsSync()) {
      filesDir.createSync(recursive: true);
    }
    return filesDir.path;
  }



  Future<void> _scanStoredFiles() async {
    await _scanStoredFilesInternal(rebuildWatcher: true);
  }

  Future<void> _scanStoredFilesInternal({required bool rebuildWatcher}) async {
    try {
      final path = await _getFilesDirectoryPath();
      final dir = Directory(path);
      if (!await dir.exists()) {
        storedFiles = [];
        _fileStatCache.clear();
        _isDirectoryCache.clear();
        notifyListeners();
        if (rebuildWatcher) {
          await _startWatchingFilesDirectory(path);
        }
        return;
      }

      final List<FileSystemEntity> entities = [];
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File || entity is Directory) {
          final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
          if (name.startsWith('.')) continue;
          entities.add(entity);
        }
      }

      // Fetch stats in parallel asynchronously to avoid sequential blocking
      final List<MapEntry<FileSystemEntity, DateTime>> entitiesWithTime = [];
      final Map<String, FileStat> newStats = {};
      final Map<String, bool> newDirs = {};

      await Future.wait(
        entities.map((entity) async {
          try {
            final isDir = await FileSystemEntity.isDirectory(entity.path);
            newDirs[entity.path] = isDir;
            final stat = await entity.stat();
            newStats[entity.path] = stat;
            final time = Platform.isWindows ? stat.changed : stat.modified;
            entitiesWithTime.add(MapEntry(entity, time));
          } catch (_) {
            entitiesWithTime.add(MapEntry(entity, DateTime(0)));
          }
        }),
      );

      // Sort
      entitiesWithTime.sort((a, b) => b.value.compareTo(a.value));
      storedFiles = entitiesWithTime.map((e) => e.key).toList();

      // Update cache
      _fileStatCache.clear();
      _fileStatCache.addAll(newStats);
      _isDirectoryCache.clear();
      _isDirectoryCache.addAll(newDirs);

      notifyListeners();
      // 每次扫描后重新建立监听（路径可能刚刚创建）
      if (rebuildWatcher) {
        await _startWatchingFilesDirectory(path);
      }
    } catch (e) {
      debugPrint('Error scanning files: $e');
    }
  }

  void _handleImageFileDeleted(String fileName) {
    bool changed = false;
    final targetPathPart = 'clipboard_images/$fileName';

    // 检查历史记录
    final historyLen = clipboardHistory.length;
    clipboardHistory.removeWhere(
      (item) =>
          item.imagePath != null &&
          item.imagePath!.replaceAll('\\', '/').endsWith(targetPathPart),
    );
    if (clipboardHistory.length != historyLen) {
      changed = true;
    }

    // 检查收藏记录
    final favLen = clipboardFavorites.length;
    clipboardFavorites.removeWhere(
      (item) =>
          item.imagePath != null &&
          item.imagePath!.replaceAll('\\', '/').endsWith(targetPathPart),
    );
    if (clipboardFavorites.length != favLen) {
      changed = true;
    }

    if (changed) {
      _saveClipboardHistory();
      _saveClipboardFavorites();
      notifyListeners();
    }
  }

  Future<void> _startWatchingImagesDirectory() async {
    await _imagesDirWatcher?.cancel();
    try {
      final dataDir = getDataDirectoryPathSync();
      final imagesDirPath = '$dataDir/clipboard_images';
      final dir = Directory(imagesDirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _imagesDirWatcher = dir.watch(events: FileSystemEvent.all).listen((
        event,
      ) {
        if (event is FileSystemDeleteEvent) {
          final path = event.path.replaceAll('\\', '/');
          final fileName = path.split('/').last;
          _handleImageFileDeleted(fileName);
        }
      });
    } catch (e) {
      debugPrint('Failed to watch images directory: $e');
    }
  }

  Future<void> _startWatchingDataDirectory() async {
    await _dataDirWatcher?.cancel();
    try {
      final dataDir = getDataDirectoryPathSync();
      final dir = Directory(dataDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _dataDirWatcher = dir.watch(events: FileSystemEvent.all).listen((event) {
        if (event is FileSystemModifyEvent || event is FileSystemCreateEvent) {
          final path = event.path.replaceAll('\\', '/');
          final fileName = path.split('/').last;
          final historyFilename = _getClipboardHistoryFilename();
          if (fileName == 'notes.json') {
            _reloadNotesDebounce?.cancel();
            _reloadNotesDebounce = Timer(
              const Duration(milliseconds: 200),
              _reloadNotesFromFile,
            );
          } else if (fileName == historyFilename ||
              fileName == 'clipboard_favorites.json') {
            _reloadHistoryDebounce?.cancel();
            _reloadHistoryDebounce = Timer(
              const Duration(milliseconds: 200),
              _reloadHistoryFromFile,
            );
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to watch data directory: $e');
    }
  }

  Future<void> _reloadNotesFromFile() async {
    final dataDir = getDataDirectoryPathSync();
    final notesFile = File('$dataDir/notes.json');
    if (!notesFile.existsSync()) return;
    try {
      final content = await notesFile.readAsString();
      if (content == _lastNotesJsonCache) {
        return; // Ignore if identical (self-write)
      }
      _lastNotesJsonCache = content;

      final decoded = jsonDecode(content) as List;
      notes =
          decoded
              .map((item) => Note.fromJson(item as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      // Keep activeNote synced
      if (activeNote != null) {
        final matching = notes.where((n) => n.id == activeNote!.id).toList();
        if (matching.isNotEmpty) {
          activeNote = matching.first;
        } else {
          activeNote = notes.isNotEmpty ? notes.first : null;
        }
      } else {
        activeNote = notes.isNotEmpty ? notes.first : null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to auto-reload notes: $e');
    }
  }

  Future<void> _reloadHistoryFromFile() async {
    final dataDir = getDataDirectoryPathSync();

    // 1. History
    final historyFilename = _getClipboardHistoryFilename();
    final historyFile = File('$dataDir/$historyFilename');
    bool historyChanged = false;
    if (historyFile.existsSync()) {
      try {
        final content = await historyFile.readAsString();
        if (content != _lastHistoryJsonCache) {
          _lastHistoryJsonCache = content;
          final decoded = jsonDecode(content) as List;
          clipboardHistory =
              decoded
                  .map(
                    (item) =>
                        ClipboardItem.fromJson(item as Map<String, dynamic>),
                  )
                  .toList()
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (_trimClipboardHistoryToLimit()) {
            await _saveClipboardHistory();
          }
          historyChanged = true;
        }
      } catch (e) {
        debugPrint('Failed to auto-reload clipboard history: $e');
      }
    }

    // 2. Favorites
    final favoritesFile = File('$dataDir/clipboard_favorites.json');
    bool favoritesChanged = false;
    if (favoritesFile.existsSync()) {
      try {
        final content = await favoritesFile.readAsString();
        if (content != _lastFavoritesJsonCache) {
          _lastFavoritesJsonCache = content;
          final decoded = jsonDecode(content) as List;
          clipboardFavorites =
              decoded
                  .map(
                    (item) =>
                        ClipboardItem.fromJson(item as Map<String, dynamic>),
                  )
                  .toList()
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          favoritesChanged = true;
        }
      } catch (e) {
        debugPrint('Failed to auto-reload clipboard favorites: $e');
      }
    }

    if (historyChanged || favoritesChanged) {
      notifyListeners();
    }
  }

  Future<void> _startWatchingFilesDirectory(String path) async {
    _fileWatchDebounce?.cancel();
    await _dirWatcher?.cancel();
    try {
      final dir = Directory(path);
      _dirWatcher = dir
          .watch(events: FileSystemEvent.all, recursive: true)
          .listen((event) {
            // 文件夹内容变化时重新扫描（不再重建监听，避免递归）
            _fileWatchDebounce?.cancel();
            _fileWatchDebounce = Timer(
              const Duration(milliseconds: 300),
              _rescanWithoutRebuildingWatcher,
            );
          });
    } catch (e) {
      debugPrint('Failed to watch directory: $e');
    }
  }

  void _rescanWithoutRebuildingWatcher() {
    _scanStoredFilesInternal(rebuildWatcher: false);
  }

  String _fileNameFromPath(String path) {
    final segments = path
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    return segments.isEmpty ? 'Untitled' : segments.last;
  }

  String _availableFilePath(
    String directoryPath,
    String fileName, {
    bool isDirectory = false,
  }) {
    final safeName = fileName.trim().isEmpty ? 'Untitled' : fileName.trim();
    final dotIndex = isDirectory ? -1 : safeName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? safeName.substring(0, dotIndex) : safeName;
    final extension = dotIndex > 0 ? safeName.substring(dotIndex) : '';

    var candidate = '$directoryPath/$safeName';
    var counter = 2;
    while (FileSystemEntity.typeSync(candidate) !=
        FileSystemEntityType.notFound) {
      candidate = '$directoryPath/$baseName ($counter)$extension';
      counter++;
    }
    return candidate;
  }

  String _timestampForFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<void> addDroppedFiles(
    List<String> filePaths, {
    Directory? targetDir,
  }) async {
    final destPath = targetDir?.path ?? await _getFilesDirectoryPath();
    for (var filePath in filePaths) {
      try {
        if (FileSystemEntity.isDirectorySync(filePath)) {
          // If it is a directory, copy the directory recursively or copy its folder structure
          final srcDir = Directory(filePath);
          final dirName = _fileNameFromPath(srcDir.path);
          final destDir = Directory(
            _availableFilePath(destPath, dirName, isDirectory: true),
          );
          await destDir.create(recursive: true);
          // Copy files in folder (simple shallow copy for performance/safety)
          await for (final entity in srcDir.list(recursive: true)) {
            final relativePath = entity.path.substring(srcDir.path.length);
            if (entity is File) {
              final newFile = File('${destDir.path}$relativePath');
              await newFile.parent.create(recursive: true);
              await entity.copy(newFile.path);
            } else if (entity is Directory) {
              final newSubDir = Directory('${destDir.path}$relativePath');
              await newSubDir.create(recursive: true);
            }
          }
        } else {
          final srcFile = File(filePath);
          if (srcFile.existsSync()) {
            // Extract file name
            final fileName = _fileNameFromPath(srcFile.path);
            final destFile = File(_availableFilePath(destPath, fileName));

            // Copy
            await srcFile.copy(destFile.path);

            // Preserve the original file's creation/modification time by setting the copy's last modified time
            try {
              final srcStat = srcFile.statSync();
              final creationTime = Platform.isWindows
                  ? srcStat.changed
                  : srcStat.modified;
              await destFile.setLastModified(creationTime);
            } catch (e) {
              debugPrint(
                'Failed to set last modified time for copied file: $e',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to copy file: $e');
      }
    }
    await _scanStoredFiles();
  }

  Future<int> pasteClipboardIntoFiles({Directory? targetDir}) async {
    try {
      final files = await Pasteboard.files();
      final existingFiles = files
          .where((path) => path.trim().isNotEmpty)
          .where(
            (path) =>
                FileSystemEntity.typeSync(path) !=
                FileSystemEntityType.notFound,
          )
          .toList();
      if (existingFiles.isNotEmpty) {
        await addDroppedFiles(existingFiles, targetDir: targetDir);
        return existingFiles.length;
      }
    } catch (e) {
      debugPrint('Failed to paste clipboard files: $e');
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null || imageBytes.isEmpty) return 0;

      final destPath = targetDir?.path ?? await _getFilesDirectoryPath();
      final filePath = _availableFilePath(
        destPath,
        'pasted_image_${_timestampForFileName()}.png',
      );
      await File(filePath).writeAsBytes(imageBytes);
      await _scanStoredFiles();
      return 1;
    } catch (e) {
      debugPrint('Failed to paste clipboard image: $e');
      return 0;
    }
  }

  Future<void> recordDeletedFile(String entityPath) async {
    try {
      final dataDir = getDataDirectoryPathSync();
      final filesDir = '$dataDir/files';
      final normFilesDir = filesDir.replaceAll('\\', '/');
      final normEntity = entityPath.replaceAll('\\', '/');

      String relKey = normEntity;
      if (normEntity.startsWith(normFilesDir)) {
        relKey = normEntity.substring(normFilesDir.length);
      }
      if (relKey.startsWith('/')) relKey = relKey.substring(1);
      if (relKey.isEmpty || relKey.startsWith('.') || relKey.contains('/.')) return;

      final fullKey = 'files/$relKey';

      final deletedFile = File('$dataDir/deleted_files.json');
      final Set<String> deletedKeys = {};
      if (await deletedFile.exists()) {
        try {
          final content = await deletedFile.readAsString();
          final list = jsonDecode(content) as List;
          deletedKeys.addAll(list.cast<String>());
        } catch (_) {}
      }
      deletedKeys.add(fullKey);
      await deletedFile.writeAsString(jsonEncode(deletedKeys.toList()));
    } catch (e) {
      debugPrint('Failed to record deleted file: $e');
    }
  }

  Future<void> deleteFile(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) {
        await recordDeletedFile(entity.path);

        final root = await _getFilesDirectoryPath();
        final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'deleted');

        // If it is already inside the trash, delete it permanently
        if (entity.path.contains('/.trash/') || entity.path.contains('\\.trash\\')) {
          await entity.delete(recursive: true);
          return;
        }

        final trashDir = Directory('$root/.trash');
        if (!trashDir.existsSync()) {
          await trashDir.create(recursive: true);
        }

        final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$name';
        final trashPath = '${trashDir.path}/$uniqueName';

        await entity.rename(trashPath);

        _pushUndoAction(FileUndoAction(
          type: FileUndoType.delete,
          pathA: entity.path,
          pathB: trashPath,
          isDirectory: entity is Directory,
        ));
      }
    } catch (e) {
      debugPrint('Failed to delete file to trash: $e');
      // Fallback: delete permanently if move fails
      try {
        if (entity.existsSync()) {
          await entity.delete(recursive: true);
        }
      } catch (_) {}
    } finally {
      await _scanStoredFiles();
    }
  }

  Future<bool> _openMacPath(String path, {bool reveal = false}) async {
    if (!Platform.isMacOS) return false;
    try {
      final result = await _macFileOpenerChannel.invokeMethod<bool>(
        reveal ? 'revealPath' : 'openPath',
        {'path': path},
      );
      return result == true;
    } catch (e) {
      debugPrint(
        'Native macOS ${reveal ? 'reveal' : 'open'} failed for $path: $e',
      );
      return false;
    }
  }

  Future<void> openFile(FileSystemEntity entity) async {
    try {
      if (!entity.existsSync()) return;

      if (Platform.isMacOS && await _openMacPath(entity.path)) {
        return;
      }

      final uri = Uri.file(entity.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback using process execution
        if (Platform.isWindows) {
          final winPath = entity.path.replaceAll('/', '\\');
          await Process.run('explorer.exe', [winPath]);
        } else if (Platform.isMacOS) {
          await Process.run('open', [entity.path]);
        }
      }
    } catch (e) {
      debugPrint('Failed to open file: $e');
    }
  }

  Future<void> revealFileInExplorer(FileSystemEntity entity) async {
    try {
      if (!entity.existsSync()) return;

      if (Platform.isWindows) {
        final winPath = entity.path.replaceAll('/', '\\');
        await Process.run('explorer.exe', ['/select,', winPath]);
      } else if (Platform.isMacOS) {
        final revealed = await _openMacPath(entity.path, reveal: true);
        if (!revealed) {
          await Process.run('open', ['-R', entity.path]);
        }
      } else {
        final parentPath = entity is Directory
            ? entity.path
            : entity.parent.path;
        await openDirectoryPath(parentPath);
      }
    } catch (e) {
      debugPrint('Failed to reveal file: $e');
    }
  }

  Future<bool> renameFile(FileSystemEntity entity, String newName) async {
    try {
      if (!entity.existsSync()) return false;
      final parentPath = entity.parent.path;
      final newPath = '$parentPath/$newName';
      if (entity.path == newPath) return true;

      // Check if target name already exists to prevent overwriting
      if (await FileSystemEntity.type(newPath) != FileSystemEntityType.notFound) {
        return false;
      }

      final oldPath = entity.path;
      await entity.rename(newPath);

      _pushUndoAction(FileUndoAction(
        type: FileUndoType.rename,
        pathA: oldPath,
        pathB: newPath,
        isDirectory: entity is Directory,
      ));

      return true;
    } catch (e) {
      debugPrint('Failed to rename file: $e');
      return false;
    } finally {
      await _scanStoredFiles();
    }
  }

  Future<void> createNewFile(String name, {Directory? targetDir}) async {
    try {
      final basePath = targetDir?.path ?? await _getFilesDirectoryPath();
      var fileName = name.trim().isEmpty
          ? text('新建文件.txt', 'New File.txt')
          : name.trim();
      var file = File('$basePath/$fileName');

      // Handle duplicates by adding suffix
      int counter = 2;
      final nameWithoutExt = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '';
      while (file.existsSync()) {
        file = File('$basePath/$nameWithoutExt ($counter)$ext');
        counter++;
      }

      await file.create();
      _pushUndoAction(FileUndoAction(
        type: FileUndoType.create,
        pathA: file.path,
        pathB: '',
        isDirectory: false,
      ));
      await _scanStoredFiles();
    } catch (e) {
      debugPrint('Failed to create new file: $e');
    }
  }

  Future<void> createNewDirectory(String name, {Directory? targetDir}) async {
    try {
      final basePath = targetDir?.path ?? await _getFilesDirectoryPath();
      var dirName = name.trim().isEmpty
          ? text('新建文件夹', 'New Folder')
          : name.trim();
      var dir = Directory('$basePath/$dirName');

      // Handle duplicates by adding suffix
      int counter = 2;
      while (dir.existsSync()) {
        dir = Directory('$basePath/$dirName ($counter)');
        counter++;
      }

      await dir.create();
      _pushUndoAction(FileUndoAction(
        type: FileUndoType.create,
        pathA: dir.path,
        pathB: '',
        isDirectory: true,
      ));
      await _scanStoredFiles();
    } catch (e) {
      debugPrint('Failed to create new directory: $e');
    }
  }

  Future<void> moveFileToFolder(
    FileSystemEntity source,
    Directory targetFolder,
  ) async {
    try {
      if (source.existsSync() && targetFolder.existsSync()) {
        final segments = source.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .toList();
        final fileName = segments.isEmpty ? 'Unknown' : segments.last;
        final targetPath = '${targetFolder.path}/$fileName';

        // Don't move to itself or a subfolder of itself
        if (source.path == targetFolder.path ||
            targetFolder.path.startsWith('${source.path}/')) {
          return;
        }

        final oldPath = source.path;
        if (source is File) {
          await source.rename(targetPath);
        } else if (source is Directory) {
          await source.rename(targetPath);
        }

        _pushUndoAction(FileUndoAction(
          type: FileUndoType.move,
          pathA: oldPath,
          pathB: targetPath,
          isDirectory: source is Directory,
        ));
      }
    } catch (e) {
      debugPrint('Failed to move file to folder: $e');
    }
    await _scanStoredFiles();
  }

  Future<void> openFilesDirectoryInExplorer() async {
    try {
      final path = await _getFilesDirectoryPath();
      await openDirectoryPath(path);
    } catch (e) {
      debugPrint('Failed to open directory: $e');
    }
  }

  Future<void> openDirectoryPath(String path) async {
    try {
      if (Platform.isWindows) {
        final winPath = path.replaceAll('/', '\\');
        await Process.run('explorer.exe', [winPath]);
      } else if (Platform.isMacOS) {
        final opened = await _openMacPath(path);
        if (!opened) {
          await Process.run('open', [path]);
        }
      } else {
        final uri = Uri.directory(path);
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Failed to open directory $path: $e');
    }
  }

  Timer? _d1LiveSyncDebounceTimer;

  void _triggerD1LiveAutoSync() {
    final isWorkerConfigured = settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty;
    final isRestConfigured = settings.cfD1Mode == 1 &&
        settings.cfAccountId?.trim().isNotEmpty == true &&
        settings.cfApiToken?.trim().isNotEmpty == true &&
        settings.cfD1DatabaseId?.trim().isNotEmpty == true;

    if ((!isWorkerConfigured && !isRestConfigured) || !settings.cfD1AutoSync) return;

    _d1LiveSyncDebounceTimer?.cancel();
    _d1LiveSyncDebounceTimer = Timer(const Duration(seconds: 3), () {
      if (!_isD1Syncing && !_isShuttingDown) {
        addD1Log(text('⚡ 内容变动，触发即时云端同步...', 'Change detected, triggering live cloud sync...'));
        syncLocalDataToD1(isManual: false);
      }
    });
  }

  Future<void> _loadDeletedNotes() async {
    final dataDir = getDataDirectoryPathSync();
    final file = File('$dataDir/deleted_notes.json');
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final decoded = jsonDecode(content) as List;
        deletedNotes = decoded
            .map((item) => Note.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        deletedNotes = [];
      }
    }
  }

  Future<void> _saveDeletedNotes() async {
    final dataDir = getDataDirectoryPathSync();
    final file = File('$dataDir/deleted_notes.json');
    try {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final encoded = jsonEncode(deletedNotes.map((item) => item.toJson()).toList());
      await file.writeAsString(encoded);
    } catch (e) {
      debugPrint('Failed to save deleted notes: $e');
    }
  }

  Future<void> _loadNotes() async {
    await _loadDeletedNotes();
    final dataDir = getDataDirectoryPathSync();
    final notesFile = File('$dataDir/notes.json');
    String? notesJson;

    if (await notesFile.exists()) {
      try {
        notesJson = await notesFile.readAsString();
      } catch (e) {
        debugPrint('Failed to read notes file: $e');
      }
    } else {
      // Legacy migration from SharedPreferences
      notesJson = _prefs.getString('notes');
      if (notesJson != null) {
        try {
          if (!await notesFile.parent.exists()) {
            await notesFile.parent.create(recursive: true);
          }
          await notesFile.writeAsString(notesJson);
          await _prefs.remove('notes');
        } catch (e) {
          debugPrint('Failed to migrate notes from SharedPreferences: $e');
        }
      }
    }

    if (notesJson != null) {
      _lastNotesJsonCache = notesJson; // Populate cache on load
      try {
        final decoded = jsonDecode(notesJson) as List;
        notes =
            decoded
                .map((item) => Note.fromJson(item as Map<String, dynamic>))
                .toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (e) {
        notes = [];
      }
    } else {
      notes = [];
      _lastNotesJsonCache = null;
    }

    // Add default note if empty
    if (notes.isEmpty) {
      final defaultNote = Note(
        id: _uuid.v4(),
        title: text('我的便签', 'My Notes'),
        content: text(
          '欢迎使用快捷便签！在这里您可以随手记录任何内容，它会自动帮您保存...',
          'Welcome to Quick Notes! Write anything here, it will be saved automatically...',
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      notes.add(defaultNote);
      await _saveNotes();
    }

    // Select first note
    activeNote = notes.isNotEmpty ? notes.first : null;
  }

  Future<void> _saveNotes() async {
    final dataDir = getDataDirectoryPathSync();
    final notesFile = File('$dataDir/notes.json');
    try {
      if (!await notesFile.parent.exists()) {
        await notesFile.parent.create(recursive: true);
      }
      final encoded = jsonEncode(notes.map((item) => item.toJson()).toList());
      _lastNotesJsonCache = encoded; // Populate cache on save
      await notesFile.writeAsString(encoded);
    } catch (e) {
      debugPrint('Failed to save notes: $e');
    }
  }

  Future<void> createNote() async {
    await forceSaveNotesIfPending();
    final newNote = Note(
      id: _uuid.v4(),
      title: text('新建便签 ${notes.length + 1}', 'New Note ${notes.length + 1}'),
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    notes.insert(0, newNote);
    activeNote = newNote;
    await _saveNotes();
    notifyListeners();
    _triggerD1LiveAutoSync();
  }

  Future<void> deleteNote(Note note) async {
    _notesSaveTimer?.cancel();
    notes.removeWhere((n) => n.id == note.id);

    final tombstone = note.copyWith(
      isDeleted: true,
      updatedAt: DateTime.now(),
    );
    deletedNotes.removeWhere((n) => n.id == note.id);
    deletedNotes.add(tombstone);
    await _saveDeletedNotes();

    if (notes.isEmpty) {
      activeNote = null;
      await createNote(); // Create a new empty note so there's always one
    } else if (activeNote?.id == note.id) {
      activeNote = notes.first;
    }

    await _saveNotes();
    notifyListeners();
    _triggerD1LiveAutoSync();
  }

  Future<void> deleteActiveNote() async {
    if (activeNote == null) return;
    await deleteNote(activeNote!);
  }

  Future<void> selectNote(Note note) async {
    await forceSaveNotesIfPending();
    activeNote = note;
    notifyListeners();
  }

  void updateActiveNoteContent(String content) {
    if (activeNote == null) return;

    // Update content and modified timestamp in memory
    final idx = notes.indexWhere((n) => n.id == activeNote!.id);
    if (idx != -1) {
      final updated = activeNote!.copyWith(
        content: content,
        updatedAt: DateTime.now(),
      );
      notes.removeAt(idx);
      notes.insert(0, updated);
      activeNote = updated;

      // Debounce saving to disk
      _notesSaveTimer?.cancel();
      _notesSaveTimer = Timer(const Duration(milliseconds: 800), () async {
        await _saveNotes();
        _triggerD1LiveAutoSync();
      });
    }
  }

  Future<void> updateActiveNoteTitle(String title) async {
    if (activeNote == null) return;
    _notesSaveTimer?.cancel();

    final idx = notes.indexWhere((n) => n.id == activeNote!.id);
    if (idx != -1) {
      final updated = activeNote!.copyWith(
        title: title.isEmpty ? text('无标题便签', 'Untitled Note') : title,
        updatedAt: DateTime.now(),
      );
      notes.removeAt(idx);
      notes.insert(0, updated);
      activeNote = updated;

      await _saveNotes();
      notifyListeners();
      _triggerD1LiveAutoSync();
    }
  }

  void _pushUndoAction(FileUndoAction action, {bool clearRedo = true}) {
    _undoStack.add(action);
    if (clearRedo) {
      _redoStack.clear();
    }
    if (_undoStack.length > 30) {
      final oldest = _undoStack.removeAt(0);
      if (oldest.type == FileUndoType.delete) {
        try {
          final trashEntity = oldest.isDirectory
              ? Directory(oldest.pathB)
              : File(oldest.pathB);
          if (trashEntity.existsSync()) {
            trashEntity.deleteSync(recursive: true);
          }
        } catch (e) {
          debugPrint('Failed to clean up old trash item: $e');
        }
      }
    }
  }

  Future<bool> undoLastAction() async {
    if (_undoStack.isEmpty) return false;
    final action = _undoStack.removeLast();
    bool success = false;
    try {
      switch (action.type) {
        case FileUndoType.rename:
          final currentEntity = action.isDirectory
              ? Directory(action.pathB)
              : File(action.pathB);
          if (currentEntity.existsSync()) {
            await currentEntity.rename(action.pathA);
            success = true;
          }
          break;
        case FileUndoType.move:
          final currentEntity = action.isDirectory
              ? Directory(action.pathB)
              : File(action.pathB);
          if (currentEntity.existsSync()) {
            await currentEntity.rename(action.pathA);
            success = true;
          }
          break;
        case FileUndoType.delete:
          final trashEntity = action.isDirectory
              ? Directory(action.pathB)
              : File(action.pathB);
          if (trashEntity.existsSync()) {
            final parent = Directory(action.pathA).parent;
            if (!parent.existsSync()) {
              await parent.create(recursive: true);
            }
            await trashEntity.rename(action.pathA);
            success = true;
          }
          break;
        case FileUndoType.create:
          final createdEntity = action.isDirectory
              ? Directory(action.pathA)
              : File(action.pathA);
          if (createdEntity.existsSync()) {
            await createdEntity.delete(recursive: true);
            success = true;
          }
          break;
      }
      if (success) {
        _redoStack.add(action);
      }
    } catch (e) {
      debugPrint('Failed to undo action of type ${action.type}: $e');
    } finally {
      await _scanStoredFiles();
    }
    return success;
  }

  Future<bool> redoLastAction() async {
    if (_redoStack.isEmpty) return false;
    final action = _redoStack.removeLast();
    bool success = false;
    try {
      switch (action.type) {
        case FileUndoType.rename:
          final currentEntity = action.isDirectory
              ? Directory(action.pathA)
              : File(action.pathA);
          if (currentEntity.existsSync()) {
            await currentEntity.rename(action.pathB);
            success = true;
          }
          break;
        case FileUndoType.move:
          final currentEntity = action.isDirectory
              ? Directory(action.pathA)
              : File(action.pathA);
          if (currentEntity.existsSync()) {
            await currentEntity.rename(action.pathB);
            success = true;
          }
          break;
        case FileUndoType.delete:
          final currentEntity = action.isDirectory
              ? Directory(action.pathA)
              : File(action.pathA);
          if (currentEntity.existsSync()) {
            final parent = Directory(action.pathB).parent;
            if (!parent.existsSync()) {
              await parent.create(recursive: true);
            }
            await currentEntity.rename(action.pathB);
            success = true;
          }
          break;
        case FileUndoType.create:
          final createdEntity = action.isDirectory
              ? Directory(action.pathA)
              : File(action.pathA);
          if (!createdEntity.existsSync()) {
            if (action.isDirectory) {
              await Directory(action.pathA).create(recursive: true);
            } else {
              await File(action.pathA).create();
            }
            success = true;
          }
          break;
      }
      if (success) {
        _pushUndoAction(action, clearRedo: false);
      }
    } catch (e) {
      debugPrint('Failed to redo action of type ${action.type}: $e');
    } finally {
      await _scanStoredFiles();
    }
    return success;
  }
}

enum FileUndoType { rename, move, delete, create }

class FileUndoAction {
  final FileUndoType type;
  final String pathA;
  final String pathB;
  final bool isDirectory;

  FileUndoAction({
    required this.type,
    required this.pathA,
    required this.pathB,
    required this.isDirectory,
  });
}
