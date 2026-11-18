import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import '../models/workspace_profile.dart';
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
  List<ClipboardItem> deletedClipboards = [];
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
    if (Platform.isMacOS) {
      try {
        final res =
            await _menuBarScrollChannel.invokeMethod('getCurrentScreenInfo');
        if (res is Map) {
          return Map<String, double>.from(
            res.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
          );
        }
      } catch (e) {
        debugPrint('Failed to get macOS active screen info: $e');
      }
    }
    final display = await _getCurrentDisplay();
    final double sw = display.size.width;
    final double sx = (display.visiblePosition ?? Offset.zero).dx;
    final double sy = (display.visiblePosition ?? Offset.zero).dy;
    return {'x': sx, 'y': 0.0, 'width': sw, 'visibleY': sy};
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
    _prefs = await SharedPreferences.getInstance();
    final appSupport = await getApplicationSupportDirectory();
    _defaultDataDirSync = '${appSupport.path}/data'.replaceAll('\\', '/');

    windowManager.addListener(this);
    trayManager.addListener(this);

    // Load Local Data
    _loadSettings();
    _loadWorkspaces();
    _clearTrashDir();
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

    // 启动时自动拾遗与静默清理本地离线/外部副本
    await autoIngestAndCleanupRedundantFiles();

    // Setup tray, hotkeys and directory watchers in parallel
    await Future.wait([
      _setupTray(),
      _setupHotkeys(),
      _startWatchingImagesDirectory(),
      _startWatchingDataDirectory(),
    ]);

    _startClipboardMonitoring();

    // Background cleanup of orphaned images (on startup + periodic every 10 minutes)
    _cleanupUnusedClipboardImages();
    _clipboardCleanupTimer?.cancel();
    _clipboardCleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!_isShuttingDown) {
        _trimClipboardHistoryToLimit();
        _cleanupUnusedClipboardImages();
      }
    });

    if (Platform.isMacOS) {
      _menuBarScrollChannel.setMethodCallHandler(_onMenuBarScrollMethodCall);
    } else if (Platform.isWindows) {
      _menuBarScrollChannel.setMethodCallHandler(_onMenuBarScrollMethodCall);
    }

    // Position window
    await windowManager.setMinimumSize(const Size(1, 1));
    await applyWindowTriggerConfiguration(isStartup: true);

    // Schedule D1+R2 Auto Sync if configured
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
    _clipboardCleanupTimer?.cancel();
  }

  Timer? _clipboardCleanupTimer;

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
    onLog(text('📥 开始从 Cloudflare D1 拉取增量变更...', 'Pulling deltas from Cloudflare D1...'));

    Map<String, dynamic>? pullRes;
    // 若本地便签为空或尚未同步，全量从云端拉取 (since = epoch 0)，避免漏掉云端已有数据
    final sinceTime = notes.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : (_lastD1SyncTime ?? DateTime.fromMillisecondsSinceEpoch(0));

    if (settings.cfD1Mode == 0) {
      final url = settings.cfWorkerUrl.trim();
      if (url.isNotEmpty) {
        final service = CfD1SyncService(workerUrl: url, isDevMode: kDebugMode);
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

      // 1. 合并便签 (做法一：整篇最新修改时间覆盖 LWW，不生成冲突副本，保持列表干净)
      int newNotesCount = 0;
      int updatedNotesCount = 0;
      final Map<String, Note> activeMap = {};
      final Map<String, Note> tombstoneMap = {};

      for (final n in notes) {
        activeMap[n.id] = n;
      }
      for (final dn in deletedNotes) {
        tombstoneMap[dn.id] = dn;
      }

      for (final rNote in remoteNotes) {
        if (rNote.isDeleted) {
          // 云端为删除墓碑
          if (activeMap.containsKey(rNote.id)) {
            final localNote = activeMap[rNote.id]!;
            // 规则：若本地在云端删除之后，有实质性的新内容修改，内容绝对优先于删除 -> 坚决复活，保护本地内容！
            if (localNote.updatedAt.isAfter(rNote.updatedAt) &&
                localNote.content.trim().isNotEmpty &&
                localNote.content.trim() != rNote.content.trim()) {
              onLog(text(
                '🛡️ 便签 [${localNote.title}] 在云端已删除但本地有更新的内容，已自动保留本地便签！',
                '🛡️ Preserved note [${localNote.title}] because local has newer substantive edits.',
              ));
              // 不删除，保持在 activeMap 中，后续自动补推到云端复活
            } else {
              activeMap.remove(rNote.id);
              tombstoneMap[rNote.id] = rNote;
              updatedNotesCount++;
            }
          } else {
            tombstoneMap[rNote.id] = rNote;
          }
          continue;
        }

        // 云端为有效便签
        if (tombstoneMap.containsKey(rNote.id)) {
          final tombstone = tombstoneMap[rNote.id]!;
          if (rNote.updatedAt.isAfter(tombstone.updatedAt)) {
            // 云端更新时间在本地删除之后 -> 恢复/更新
            tombstoneMap.remove(rNote.id);
            activeMap[rNote.id] = rNote;
            newNotesCount++;
            onLog(text(
              '🛡️ 云端便签 [${rNote.title}] 在本地删除后有新修改，已自动复活保留！',
              '🛡️ Revived note [${rNote.title}] from cloud because it has newer updates.',
            ));
          } else {
            // 本地删除时间更新 -> 维持本地删除状态
            continue;
          }
        } else if (!activeMap.containsKey(rNote.id)) {
          // 本地没有记录 -> 直接添加
          activeMap[rNote.id] = rNote;
          newNotesCount++;
        } else {
          // 双端均存在
          final localNote = activeMap[rNote.id]!;
          // 1. 内容与标题完全一致（排除纯空格换行抖动）-> 直接取最新时间/版本，完全无感平滑对齐
          final bool isContentIdentical =
              localNote.content.trim() == rNote.content.trim() &&
              localNote.title.trim() == rNote.title.trim();

          if (isContentIdentical) {
            if (rNote.updatedAt.isAfter(localNote.updatedAt)) {
              activeMap[rNote.id] = rNote;
            }
          } else {
            // 2. 内容实质不同：判断是“单端正常修改（延迟同步）”还是“双端真实并发冲突”
            final DateTime baseline = _lastD1SyncTime ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bool localChangedSinceBaseline = localNote.updatedAt.isAfter(baseline);
            final bool remoteChangedSinceBaseline = rNote.updatedAt.isAfter(baseline);

            if (localChangedSinceBaseline && remoteChangedSinceBaseline) {
              // 双方都在上次同步后修改了同一条便签，且内容实质不同 -> 真实冲突！
              // 规则：最新的一方作为主便签，另一方生成一条冲突备份便签，确保字迹 100% 不丢！
              final bool remoteIsNewer = rNote.updatedAt.isAfter(localNote.updatedAt);
              final Note winner = remoteIsNewer ? rNote : localNote;
              final Note loser = remoteIsNewer ? localNote : rNote;

              activeMap[winner.id] = winner;
              updatedNotesCount++;

              // 生成冲突备份便签（赋予新 ID，标题加上【冲突备份】，内容完整保留）
              final conflictCopyId = 'note_conflict_${DateTime.now().millisecondsSinceEpoch}_${loser.id.hashCode.abs().toRadixString(36)}';
              final timeStr = DateFormat('MM-dd HH:mm').format(loser.updatedAt.toLocal());
              final conflictNote = Note(
                id: conflictCopyId,
                title: '【冲突备份-$timeStr】${loser.title}',
                content: loser.content,
                createdAt: loser.createdAt,
                updatedAt: DateTime.now(),
                isDeleted: false,
              );
              activeMap[conflictCopyId] = conflictNote;
              newNotesCount++;

              onLog(text(
                '⚠️ 检测到便签 [${winner.title}] 存在双端实质修改冲突，已自动生成【冲突备份】保留双方数据！',
                '⚠️ Conflict detected for note [${winner.title}], automatically created backup copy.',
              ));
            } else {
              // 只有一端改了（典型的断网后恢复/单点操作）：直接取时间最新的一方，0 副本，平滑无感对齐！
              if (rNote.updatedAt.isAfter(localNote.updatedAt)) {
                activeMap[rNote.id] = rNote;
                updatedNotesCount++;
              }
            }
          }
        }
      }

      // 熔断保护：如果本地原有便签大于等于 3 条，合并后条数缩减超过 50%，触发安全熔断，优先保护本地数据
      if (notes.length >= 3 && activeMap.length < (notes.length / 2)) {
        onLog(text(
          '⚠️ [安全熔断保护] 检测到云端便签数据异常缩减 (本地 ${notes.length} 条 -> 云端拟合并 ${activeMap.length} 条)，已自动拦截异常删除，全量保留本地便签！',
          '⚠️ [Safety Guard] Cloud notes delta abnormally reduced (${notes.length} -> ${activeMap.length}), prevented mass deletion.',
        ));
        for (final n in notes) {
          if (!activeMap.containsKey(n.id)) {
            activeMap[n.id] = n;
          }
        }
      }

      final cutoffTombstone = DateTime.now().subtract(const Duration(days: 7));
      deletedNotes = tombstoneMap.values
          .where((n) => n.updatedAt.isAfter(cutoffTombstone))
          .toList();
      await _saveDeletedNotes();

      if (newNotesCount > 0 || updatedNotesCount > 0) {
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
        await _createNotesBackup('cloud_merged');
        onLog(text(
          '🎉 云端便签同步完成：新增 $newNotesCount 条，更新 $updatedNotesCount 条',
          'Fetched notes: added $newNotesCount, updated $updatedNotesCount',
        ));
      } else {
        onLog(text('ℹ️ 便签已与云端保持最新', 'Notes up to date.'));
      }

      // 2. 合并剪贴板历史（支持新增、收藏状态同步及删除墓碑同步）
      int newClipCount = 0;
      int updatedClipCount = 0;
      final Map<String, ClipboardItem> historyMap = {
        for (final c in clipboardHistory) c.id: c,
      };
      final Map<String, ClipboardItem> favMap = {
        for (final c in clipboardFavorites) c.id: c,
      };
      final Map<String, ClipboardItem> delClipMap = {
        for (final c in deletedClipboards) c.id: c,
      };

      for (final rClip in remoteClipboards) {
        if (rClip.isDeleted) {
          bool removed = false;
          if (historyMap.containsKey(rClip.id)) {
            historyMap.remove(rClip.id);
            removed = true;
          }
          if (favMap.containsKey(rClip.id)) {
            favMap.remove(rClip.id);
            removed = true;
          }
          if (removed) updatedClipCount++;
          delClipMap[rClip.id] = rClip;
          continue;
        }

        if (delClipMap.containsKey(rClip.id)) {
          final tomb = delClipMap[rClip.id]!;
          if (!rClip.updatedAt.isAfter(tomb.updatedAt)) {
            continue;
          }
          delClipMap.remove(rClip.id);
        }

        final existingFav = favMap[rClip.id];
        final existingHist = historyMap[rClip.id];
        final existing = existingFav ?? existingHist;

        if (existing == null) {
          if (rClip.isFavorite) {
            favMap[rClip.id] = rClip;
          } else {
            historyMap[rClip.id] = rClip;
          }
          newClipCount++;
        } else if (rClip.updatedAt.isAfter(existing.updatedAt)) {
          // 仅当云端的时间严格晚于本地记录时，才采纳云端的收藏状态！
          // 绝对不能让云端陈旧的收藏状态反向覆盖本地刚做出的取消收藏操作。
          if (rClip.isFavorite) {
            favMap[rClip.id] = rClip;
            historyMap.remove(rClip.id);
          } else {
            favMap.remove(rClip.id);
            historyMap[rClip.id] = rClip;
          }
          updatedClipCount++;
        }
      }

      final clipTombstoneCutoff = DateTime.now().subtract(const Duration(days: 7));
      deletedClipboards = delClipMap.values
          .where((c) => c.updatedAt.isAfter(clipTombstoneCutoff))
          .toList();

      if (newClipCount > 0 || updatedClipCount > 0) {
        clipboardHistory = historyMap.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        clipboardFavorites = favMap.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        // 拉取合并后立即按本地上限裁剪超出部分的旧剪贴板记录，并在后台释放孤立图片
        _trimClipboardHistoryToLimit();
        await _saveClipboardHistory();
        await _saveClipboardFavorites();
        unawaited(_cleanupUnusedClipboardImages());
        onLog(text(
          '🎉 剪贴板同步完成：新增 $newClipCount 条，状态更新 $updatedClipCount 条',
          'Fetched clipboards: added $newClipCount, updated $updatedClipCount',
        ));
      }

      notifyListeners();
    } else {
      if (pullRes != null && pullRes['error'] != null) {
        onLog(text('⚠️ 拉取云端数据失败: ${pullRes['error']}', 'Pull data failed: ${pullRes['error']}'));
      }
    }
  }

  Future<Map<String, dynamic>> _pushLocalDataToD1Internal({bool isManual = true}) async {
    final DateTime? lastSyncBeforePull = _lastD1SyncTime;

    // 1. 先拉取云端增量数据并进行合并
    await _pullAndMergeCloudData(onLog: (msg) => addD1Log(msg));

    // 2. 组装本地便签与剪贴板（含删除墓碑）
    final allNotes = [...notes, ...deletedNotes];

    final Map<String, ClipboardItem> clipMap = {};
    for (final item in clipboardHistory) {
      clipMap[item.id] = item;
    }
    for (final item in clipboardFavorites) {
      clipMap[item.id] = item.copyWith(isFavorite: true);
    }
    for (final delItem in deletedClipboards) {
      clipMap[delItem.id] = delItem.copyWith(isDeleted: true);
    }
    final allClipboards = clipMap.values.toList();

    // 3. 自动同步时仅推送增量（改哪条传哪条），避免每次全量重传
    final List<Note> notesToPush;
    final List<ClipboardItem> clipboardsToPush;
    if (!isManual && lastSyncBeforePull != null) {
      notesToPush = allNotes.where((n) => n.updatedAt.isAfter(lastSyncBeforePull)).toList();
      clipboardsToPush = allClipboards.where((c) => c.updatedAt.isAfter(lastSyncBeforePull)).toList();
      if (notesToPush.isEmpty && clipboardsToPush.isEmpty) {
        final msg = text('已与云端保持最新（无本地新增改动需上传）', 'Up to date (no local changes to push)');
        addD1Log('ℹ️ $msg');
        return {
          'success': true,
          'notesCount': 0,
          'clipboardCount': 0,
          'settingsCount': 0,
          'message': msg,
        };
      }
    } else {
      notesToPush = allNotes;
      clipboardsToPush = allClipboards;
    }

    addD1Log(text(
      '待推送变更: 便签 ${notesToPush.length} 条, 剪贴板 ${clipboardsToPush.length} 条',
      'Pushing delta: ${notesToPush.length} notes, ${clipboardsToPush.length} clipboards',
    ));

    final settingsList = isManual
        ? [
            {
              'key': 'app_settings',
              'value': jsonEncode(settings.toJson()),
              'updatedAt': DateTime.now().toIso8601String(),
            }
          ]
        : <Map<String, dynamic>>[];

    if (settings.cfD1Mode == 0) {
      final url = settings.cfWorkerUrl.trim();
      if (url.isEmpty) {
        final err = text('未配置 Cloudflare Worker 服务端 URL', 'Worker URL is missing');
        addD1Log('❌ $err');
        return {'success': false, 'error': err};
      }
      final service = CfD1SyncService(workerUrl: url, isDevMode: kDebugMode);
      final metrics = await service.pushToCloudflare(
        notes: notesToPush,
        clipboardItems: clipboardsToPush,
        settings: settingsList,
      );
      if (metrics != null && metrics.httpStatus == 200) {
        final msg = text(
          '同步成功！上传便签 ${notesToPush.length} 条，剪贴板 ${clipboardsToPush.length} 条 (RTT: ${metrics.clientRttMs.toStringAsFixed(1)}ms)',
          'Successfully pushed data to Worker D1',
        );
        addD1Log('✅ $msg');
        return {
          'success': true,
          'notesCount': notesToPush.length,
          'clipboardCount': clipboardsToPush.length,
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

      final res = await CfD1SyncService.pushLocalDataToD1RestApi(
        accountId: accountId,
        apiToken: apiToken,
        d1DatabaseId: dbId,
        notes: notesToPush,
        clipboardItems: clipboardsToPush,
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
        setWorkspaceCloudOnline(currentWorkspace.id, true);
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
      // 0. 同步前自动自愈吸收本地外部副本，打扫干净后再创建安全快照
      await autoIngestAndCleanupRedundantFiles();
      await _createNotesBackup('pre_sync');

      addD1Log(text('🚀 开始全量一键同步 (Cloudflare D1 数据库 + R2 文件存储)...', 'Starting full sync (D1 DB + R2 Storage)...'));

      // 1. 同步 D1 数据库数据 (便签 + 剪贴板 + 设置)
      final d1Result = await _pushLocalDataToD1Internal(isManual: isManual);

      // 2. 独立同步 Section A 的 R2 存储桶 (本地图片、剪贴板快照与文件附件)
      // 若已配置 Worker URL，Worker 内部已经绑定 FILES_BUCKET，无需用户在客户端单独填写 bucketName
      final hasWorker = settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty;
      final bucketName = (settings.cfR2BucketName?.trim().isNotEmpty == true)
          ? settings.cfR2BucketName!.trim()
          : (settings.r2BucketName?.trim().isNotEmpty == true
              ? settings.r2BucketName!.trim()
              : (hasWorker ? 'pod-quick-files' : null));

      int skippedIdenticalCount = 0;
      int newlyUploadedCount = 0;
      int newlyDownloadedCount = 0;
      int deletedRemoteCount = 0;

      if (hasWorker || (bucketName != null && bucketName.isNotEmpty)) {
        addD1Log(text('📁 正在准备双向同步文件与图片...', 'Syncing files & images...'));

        try {
          // 同步文件前，先确保本地超出条数上限的剪贴板及孤立图片已清理
          _trimClipboardHistoryToLimit();
          await _cleanupUnusedClipboardImages();
          final activeClipImageKeys = _getActiveClipboardImageKeys();

          final dataDir = Directory(getDataDirectoryPathSync());
          final customFilesPath = settings.customFilesPath?.trim();

          // 扫描应用实际存放图片和文件的目录
          final scanDirs = <Directory>[
            Directory('${dataDir.path}${Platform.pathSeparator}clipboard_images'),
            Directory('${dataDir.path}${Platform.pathSeparator}files'),
            Directory('${dataDir.path}${Platform.pathSeparator}images'),
            if (customFilesPath != null && customFilesPath.isNotEmpty)
              Directory(customFilesPath),
          ];

          final allLocalFiles = <File>[];
          final allLocalDirs = <Directory>[];
          for (final dir in scanDirs) {
            if (dir.existsSync()) {
              final entities = dir.listSync(recursive: true);
              for (final e in entities) {
                if (e is Directory) {
                  final norm = e.path.replaceAll('\\', '/');
                  if (!norm.contains('.trash') && !norm.split('/').last.startsWith('.')) {
                    allLocalDirs.add(e);
                  }
                } else if (e is File) {
                  final normPath = e.path.replaceAll('\\', '/');
                  if (normPath.contains('.trash')) continue;
                  final name = e.path.split(Platform.pathSeparator).last;
                  final isKeep = name == '.keep';
                  if (!isKeep && (normPath.contains('/.') || name.startsWith('.') || name.endsWith('.tmp'))) continue;
                  allLocalFiles.add(e);
                }
              }
            }
          }

          // 核心特性：自动检测空子目录，写入并同步 .keep 占位对象到云端 R2 与 D1
          final normDataDirScan = dataDir.path.replaceAll('\\', '/');
          final normCustomScan = customFilesPath?.replaceAll('\\', '/');
          for (final d in allLocalDirs) {
            final norm = d.path.replaceAll('\\', '/');
            String cleanRel = '';
            if (normCustomScan != null && normCustomScan.isNotEmpty && norm.startsWith(normCustomScan)) {
              cleanRel = norm.substring(normCustomScan.length);
              if (cleanRel.startsWith('/')) cleanRel = cleanRel.substring(1);
              cleanRel = 'files/$cleanRel';
            } else if (norm.startsWith(normDataDirScan)) {
              cleanRel = norm.substring(normDataDirScan.length);
              if (cleanRel.startsWith('/')) cleanRel = cleanRel.substring(1);
            }
            if (!cleanRel.startsWith('files/')) continue;
            final dirName = cleanRel.split('/').last;
            if (dirName.startsWith('.') || dirName == '.trash') continue;

            // 检查该目录下是否有任何本地实际文件
            final hasChildFile = allLocalFiles.any((f) {
              final fNorm = f.path.replaceAll('\\', '/');
              return fNorm.startsWith('$norm/') && !fNorm.endsWith('/.keep');
            });
            if (!hasChildFile) {
              final keepFile = File('${d.path}${Platform.pathSeparator}.keep');
              if (!keepFile.existsSync()) {
                try {
                  keepFile.writeAsBytesSync([]);
                } catch (_) {}
              }
              if (keepFile.existsSync() && !allLocalFiles.any((f) => f.path == keepFile.path)) {
                allLocalFiles.add(keepFile);
              }
            }
          }

          // 读取本地已删除文件墓碑表 (deleted_files.json)
          final deletedFile = File('${dataDir.path}${Platform.pathSeparator}deleted_files.json');
          final Set<String> deletedKeys = {};
          if (deletedFile.existsSync()) {
            try {
              final content = deletedFile.readAsStringSync();
              final list = jsonDecode(content) as List;
              deletedKeys.addAll(list.cast<String>());
            } catch (_) {}
          }

          // 读取 / 比对 OneDrive 式本地同步快照表 (last_sync_snapshot.json)
          final snapshotFile = File('${dataDir.path}${Platform.pathSeparator}last_sync_snapshot.json');
          final Set<String> lastSyncedKeys = {};
          final bool hasSnapshot = snapshotFile.existsSync();
          if (hasSnapshot) {
            try {
              final content = snapshotFile.readAsStringSync();
              final list = jsonDecode(content) as List;
              lastSyncedKeys.addAll(list.cast<String>());
            } catch (_) {}
          }

          addD1Log(text('🔍 扫描到 ${allLocalFiles.length} 个本地文件，正在查询云端文件元数据比对差异...', 'Scanning ${allLocalFiles.length} local files, querying cloud metadata...'));

          // 1. 获取云端文件元数据记录 (file_metadata 表 / R2 List)
          Map<String, Map<String, dynamic>> cloudMetadata = {};
          CfD1SyncService? workerService;
          if (settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty) {
            workerService = CfD1SyncService(workerUrl: settings.cfWorkerUrl, isDevMode: kDebugMode);
            cloudMetadata = await workerService.fetchRemoteFilesMetadata();
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

          final r2Service = _createR2SyncService();

          // 辅助函数：根据 relativeKey 计算本地目标完整路径
          File resolveLocalTarget(String relKey) {
            if (relKey.startsWith('files/')) {
              final sub = relKey.substring('files/'.length);
              if (customFilesPath != null && customFilesPath.isNotEmpty) {
                return File('$customFilesPath/$sub');
              }
              return File('${dataDir.path}/files/$sub');
            }
            return File('${dataDir.path}/$relKey');
          }

          // 辅助函数：根据本地 File 计算云端 relativeKey
          String computeRelativeKey(File file) {
            final normPath = file.path.replaceAll('\\', '/');
            final normDataDir = dataDir.path.replaceAll('\\', '/');
            final normCustom = customFilesPath?.replaceAll('\\', '/');
            if (normCustom != null && normCustom.isNotEmpty && normPath.startsWith(normCustom)) {
              var sub = normPath.substring(normCustom.length);
              if (sub.startsWith('/')) sub = sub.substring(1);
              return 'files/$sub';
            }
            if (normPath.startsWith(normDataDir)) {
              var sub = normPath.substring(normDataDir.length);
              if (sub.startsWith('/')) sub = sub.substring(1);
              return sub;
            }
            return file.path.split(Platform.pathSeparator).last;
          }

          // 建立本地文件映射 Map<relativeKey, File>
          final Map<String, File> localMap = {};
          for (final f in allLocalFiles) {
            final k = computeRelativeKey(f);
            localMap[k] = f;
          }

          // OneDrive 式自动检测：若存在上次同步快照，自动比对找出在 OS/资源管理器中被删除的文件/文件夹 (仅限用户文件 files/)
          if (hasSnapshot) {
            for (final oldKey in lastSyncedKeys) {
              if (oldKey.startsWith('files/') && !localMap.containsKey(oldKey)) {
                deletedKeys.add(oldKey);
              }
            }
          }

          // 核心校验辅助函数：判断云端 Key 是否已被标记删除（包含文件夹父路径前缀匹配）
          bool isKeyDeleted(String key) {
            for (final delKey in deletedKeys) {
              if (key == delKey) return true;
              final prefix = delKey.endsWith('/') ? delKey : '$delKey/';
              if (key.startsWith(prefix)) return true;
            }
            return false;
          }

          // 异地删除下发：如果一个文件上次快照存在，但云端已无此文件且本地未被手动标记/修改，说明其他设备删除了该文件，本地同步清理至回收站 (仅限用户文件 files/)
          if (hasSnapshot && cloudMetadata.isNotEmpty) {
            for (final oldKey in lastSyncedKeys) {
              if (oldKey.startsWith('files/') && localMap.containsKey(oldKey) && !cloudMetadata.containsKey(oldKey) && !isKeyDeleted(oldKey)) {
                final localFile = localMap[oldKey];
                if (localFile != null && localFile.existsSync()) {
                  try {
                    final root = getDataDirectoryPathSync();
                    final trashDir = Directory('$root${Platform.pathSeparator}files${Platform.pathSeparator}.trash');
                    if (!trashDir.existsSync()) trashDir.createSync(recursive: true);
                    final name = localFile.path.split(Platform.pathSeparator).last;
                    localFile.renameSync('${trashDir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$name');
                    localMap.remove(oldKey);
                    deletedRemoteCount++;
                  } catch (_) {}
                }
              }
            }
          }

          // 2. 差异比对：
          // A. 找出云端需要物理删除的文件 (toDeleteRemote)
          // 包含：1) 本地已删除的文件(isKeyDeleted)；2) 云端剪贴板图片(clipboard_images/)中已超出历史上限或已被删除、不再被任何活跃剪贴板引用的过期图片
          // 安全守则：若当前为全新/空工作区（无本地同步快照 hasSnapshot == false 且本地有效文件较少），严禁对云端 files/ 执行任何删除！
          final isCleanWorkspace = !hasSnapshot && allLocalFiles.where((f) => computeRelativeKey(f).startsWith('files/')).isEmpty;
          final toDeleteRemote = <String>[];
          for (final entry in cloudMetadata.entries) {
            final remoteKey = entry.key;
            if (isKeyDeleted(remoteKey)) {
              if (remoteKey.startsWith('files/') && isCleanWorkspace) {
                // 空目录初始化恢复模式：保护云端 files/ 绝不误删
                continue;
              }
              toDeleteRemote.add(remoteKey);
            } else if (remoteKey.startsWith('clipboard_images/') &&
                !activeClipImageKeys.contains(remoteKey)) {
              toDeleteRemote.add(remoteKey);
            }
          }

          // B. 找出需要从云端下载的文件 (toDownload)
          final toDownload = <Map<String, dynamic>>[];
          for (final entry in cloudMetadata.entries) {
            final remoteKey = entry.key;
            final remoteInfo = entry.value;

            // 如果本地已手动/OS删除此文件或整个文件夹，跳过下载
            if (isKeyDeleted(remoteKey)) continue;
            // 忽略隐藏文件与临时文件（允许空目录占位标记 .keep）
            final isDirMarker = remoteKey.endsWith('/.keep') || remoteKey.endsWith('/');
            if (!isDirMarker && (remoteKey.contains('/.') || remoteKey.startsWith('.'))) continue;

            // 严格白名单：只同步用户文件管理(files/)或剪贴板图片(clipboard_images/)
            if (!remoteKey.startsWith('files/') && !remoteKey.startsWith('clipboard_images/')) {
              continue;
            }

            // 关键过滤：对于剪贴板图片(clipboard_images/)，只下载当前仍在有效剪贴板历史或收藏中的图片！
            // 已超出条数上限淘汰或已删除的历史图片绝不下载（已归入 toDeleteRemote 在后台静默清理）
            if (remoteKey.startsWith('clipboard_images/') &&
                !activeClipImageKeys.contains(remoteKey)) {
              continue;
            }

            // 坚决排除安装包、执行文件与更新发布信息，防止误下载到用户数据目录
            final lowerKey = remoteKey.toLowerCase();
            if (lowerKey.endsWith('.exe') ||
                lowerKey.endsWith('.dmg') ||
                lowerKey.endsWith('.pkg') ||
                lowerKey.endsWith('.setup') ||
                lowerKey.endsWith('.iss') ||
                lowerKey.endsWith('.msi') ||
                remoteKey == 'release_info.json') {
              continue;
            }

            final localFile = localMap[remoteKey];
            if (localFile == null || !localFile.existsSync()) {
              toDownload.add(remoteInfo);
            } else {
              final stat = localFile.statSync();
              final localMTime = stat.modified.toUtc();
              final remoteUpdatedStr = remoteInfo['updated_at'] as String?;
              DateTime? remoteUpdated;
              if (remoteUpdatedStr != null) {
                remoteUpdated = DateTime.tryParse(remoteUpdatedStr)?.toUtc();
              }

              // 云端时间晚于本地修改时间 > 2s -> 云端有较新版本，下载覆盖
              if (remoteUpdated != null &&
                  remoteUpdated.isAfter(localMTime.add(const Duration(seconds: 2)))) {
                toDownload.add(remoteInfo);
              }
            }
          }

          // C. 找出需要上传到云端的文件 (toUpload)
          final toUpload = <File>[];
          for (final file in allLocalFiles) {
            final relKey = computeRelativeKey(file);

            // 严格白名单：只同步属于文件管理(files/)或剪贴板图片(clipboard_images/)的内容
            if (!relKey.startsWith('files/') && !relKey.startsWith('clipboard_images/')) {
              continue;
            }
            // 对于剪贴板图片，仅上传当前仍在有效剪贴板历史或收藏中的图片
            if (relKey.startsWith('clipboard_images/') &&
                !activeClipImageKeys.contains(relKey)) {
              continue;
            }
            if (!relKey.endsWith('/.keep') && (relKey.contains('/.') || relKey.contains('.trash'))) {
              continue;
            }

            // 坚决排除安装包与程序发布信息
            final lowerRel = relKey.toLowerCase();
            if (lowerRel.endsWith('.exe') ||
                lowerRel.endsWith('.dmg') ||
                lowerRel.endsWith('.pkg') ||
                lowerRel.endsWith('.setup') ||
                lowerRel.endsWith('.iss') ||
                lowerRel.endsWith('.msi') ||
                relKey == 'release_info.json') {
              continue;
            }

            final remote = cloudMetadata[relKey];
            if (remote == null) {
              toUpload.add(file);
            } else {
              final stat = file.statSync();
              final localSize = stat.size;
              final localModified = stat.modified.toUtc();
              final remoteSize = (remote['file_size'] as num?)?.toInt() ?? -1;
              final remoteUpdatedStr = remote['updated_at'] as String?;
              DateTime? remoteUpdated;
              if (remoteUpdatedStr != null) {
                final parsed = DateTime.tryParse(remoteUpdatedStr);
                if (parsed != null) remoteUpdated = parsed.toUtc();
              }

              // 如果文件大小完全一致，且云端更新时间不早于本地修改时间(留2秒容差)，判定为无变动跳过
              if (remoteSize == localSize) {
                if (remoteUpdated == null || !localModified.isAfter(remoteUpdated.add(const Duration(seconds: 2)))) {
                  skippedIdenticalCount++;
                  continue;
                }
              }
              // 如果 remote 更新，已加入 toDownload，这里不重复加入 toUpload
              if (remoteUpdated != null && remoteUpdated.isAfter(localModified.add(const Duration(seconds: 2)))) {
                continue;
              }
              toUpload.add(file);
            }
          }

          addD1Log(text(
            '📊 差异统计: + ${toUpload.length} 上传  |  ↓ ${toDownload.length} 下载  |  - ${toDeleteRemote.length} 后台待删  |  = $skippedIdenticalCount 无变动',
            'Diff stats: + ${toUpload.length} upload | ↓ ${toDownload.length} download | - ${toDeleteRemote.length} bg delete | = $skippedIdenticalCount unchanged',
          ));

          // 3. 优先执行云端下载 (Download)，并在落盘后对齐修改时间防止“乒乓重复上传”
          for (int i = 0; i < toDownload.length; i++) {
            final remoteInfo = toDownload[i];
            final relKey = remoteInfo['file_key'] as String;
            final fileName = relKey.split('/').last;
            final progressIndex = i + 1;

            // 特殊处理：目录占位标记（.keep / / 结尾）直接在本地建立对应空目录并落盘占位符
            if (relKey.endsWith('/.keep') || relKey.endsWith('/')) {
              final cleanRel = relKey.replaceAll('/.keep', '').replaceAll(RegExp(r'/+$'), '');
              final target = resolveLocalTarget(cleanRel);
              final dir = Directory(target.path);
              if (!dir.existsSync()) {
                try { dir.createSync(recursive: true); } catch (_) {}
              }
              final keepFile = File('${dir.path}${Platform.pathSeparator}.keep');
              if (!keepFile.existsSync()) {
                try { keepFile.writeAsBytesSync([]); } catch (_) {}
              }
              newlyDownloadedCount++;
              continue;
            }

            final target = resolveLocalTarget(relKey);
            addD1Log('↓ [$progressIndex/${toDownload.length}] 下载 $fileName');

            bool ok = false;
            if (workerService != null) {
              ok = await workerService.downloadFileFromR2(fileKey: relKey, targetFile: target);
            } else if (r2Service != null) {
              ok = await r2Service.downloadFile(relKey, target);
            }

            if (ok) {
              newlyDownloadedCount++;
              // 关键：将本地文件的修改时间对齐为云端时间，避免下次同步被误判为本地新改动而重复上传
              final remoteUpdatedStr = remoteInfo['updated_at'] as String?;
              if (remoteUpdatedStr != null) {
                final parsed = DateTime.tryParse(remoteUpdatedStr);
                if (parsed != null && target.existsSync()) {
                  try {
                    target.setLastModifiedSync(parsed.toLocal());
                  } catch (_) {}
                }
              }
            } else {
              addD1Log('❌ [$progressIndex/${toDownload.length}] 下载失败: $fileName');
            }
          }

          // 4. 优先执行本地上传 (Upload)
          for (int i = 0; i < toUpload.length; i++) {
            final file = toUpload[i];
            final relativePath = computeRelativeKey(file);
            final fileName = file.path.split(Platform.pathSeparator).last;
            final progressIndex = i + 1;
            final isDirMarker = relativePath.endsWith('/.keep');
            final mime = isDirMarker ? 'inode/directory' : null;

            addD1Log('↑ [$progressIndex/${toUpload.length}] 上传 ${isDirMarker ? '📁 $relativePath' : fileName}');

            if (settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty) {
              final service = CfD1SyncService(workerUrl: settings.cfWorkerUrl, isDevMode: kDebugMode);
              final res = await service.uploadFileToR2(file: file, fileKey: relativePath, mimeType: mime);
              if (res['success'] == true) {
                newlyUploadedCount++;

                // 双重保障：若填写了 REST API 凭据，同步把元数据也写一份到 D1
                if (settings.cfAccountId?.trim().isNotEmpty == true &&
                    settings.cfApiToken?.trim().isNotEmpty == true &&
                    settings.cfD1DatabaseId?.trim().isNotEmpty == true) {
                  final lowerKey = relativePath.toLowerCase();
                  final metaMime = isDirMarker
                      ? 'inode/directory'
                      : (lowerKey.endsWith('.png')
                          ? 'image/png'
                          : (lowerKey.endsWith('.jpg') || lowerKey.endsWith('.jpeg'))
                              ? 'image/jpeg'
                              : 'application/octet-stream');
                  unawaited(CfD1SyncService.recordFileMetadataRestApi(
                    accountId: settings.cfAccountId!,
                    apiToken: settings.cfApiToken!,
                    d1DatabaseId: settings.cfD1DatabaseId!,
                    fileKey: relativePath,
                    fileName: isDirMarker ? relativePath.replaceAll('/.keep', '').split('/').last : fileName,
                    fileSize: file.lengthSync(),
                    mimeType: metaMime,
                  ));
                }
              } else {
                addD1Log('❌ [$progressIndex/${toUpload.length}] 上传失败: $fileName (${res['error'] ?? res['status']})');
              }
            } else if (r2Service != null) {
              final ok = await r2Service.uploadFile(file, relativePath);
              if (ok) {
                newlyUploadedCount++;

                if (settings.cfAccountId?.trim().isNotEmpty == true &&
                    settings.cfApiToken?.trim().isNotEmpty == true &&
                    settings.cfD1DatabaseId?.trim().isNotEmpty == true) {
                  final lowerKey = relativePath.toLowerCase();
                  final metaMime = isDirMarker
                      ? 'inode/directory'
                      : (lowerKey.endsWith('.png')
                          ? 'image/png'
                          : (lowerKey.endsWith('.jpg') || lowerKey.endsWith('.jpeg'))
                              ? 'image/jpeg'
                              : 'application/octet-stream');
                  unawaited(CfD1SyncService.recordFileMetadataRestApi(
                    accountId: settings.cfAccountId!,
                    apiToken: settings.cfApiToken!,
                    d1DatabaseId: settings.cfD1DatabaseId!,
                    fileKey: relativePath,
                    fileName: isDirMarker ? relativePath.replaceAll('/.keep', '').split('/').last : fileName,
                    fileSize: file.lengthSync(),
                    mimeType: metaMime,
                  ));
                }
              } else {
                addD1Log('❌ [$progressIndex/${toUpload.length}] (S3) 上传失败: $fileName');
              }
            } else {
              addD1Log(text(
                '⚠️ 提示: R2 存储桶写入需配置 Worker 节点或 S3 凭据。',
                'Note: R2 upload requires Worker Node mode or S3 credentials.',
              ));
              break;
            }
          }

          // 5. 下载与上传完成后，立即刷新前台文件界面与本地快照，让用户 0 等待感知最新文件
          await _scanStoredFiles();

          try {
            final currentSnapshotKeys = <String>{};
            for (final dir in scanDirs) {
              if (dir.existsSync()) {
                final list = dir.listSync(recursive: true).whereType<File>().toList();
                for (final f in list) {
                  final normPath = f.path.replaceAll('\\', '/');
                  if (normPath.contains('/.') || normPath.contains('.trash')) continue;
                  final name = f.path.split(Platform.pathSeparator).last;
                  if (name.startsWith('.') || name.endsWith('.tmp')) continue;
                  final relKey = computeRelativeKey(f);
                  if (relKey.startsWith('files/')) {
                    currentSnapshotKeys.add(relKey);
                  }
                }
              }
            }
            snapshotFile.writeAsStringSync(jsonEncode(currentSnapshotKeys.toList()));
          } catch (_) {}

          // 6. 云端文件与过期剪贴板图片销毁放到后台异步慢慢删，绝不阻塞前台同步完成状态
          if (toDeleteRemote.isNotEmpty) {
            final pendingDeletes = List<String>.from(toDeleteRemote);
            final remainingDeletedKeys = Set<String>.from(deletedKeys);
            unawaited(Future(() async {
              int cleanedCount = 0;
              for (int i = 0; i < pendingDeletes.length; i++) {
                final delKey = pendingDeletes[i];
                final fileName = delKey.split('/').last;
                bool ok = false;
                try {
                  if (workerService != null) {
                    ok = await workerService.deleteFileFromR2(delKey);
                  } else if (r2Service != null) {
                    ok = await r2Service.deleteFile(delKey);
                  }
                } catch (_) {}
                if (ok) {
                  cleanedCount++;
                  remainingDeletedKeys.remove(delKey);
                  if (pendingDeletes.length <= 5) {
                    addD1Log('🗑️ [后台清理 ${i + 1}/${pendingDeletes.length}] 已销毁云端 $fileName');
                  }
                }
              }
              if (pendingDeletes.length > 5 && cleanedCount > 0) {
                addD1Log('🗑️ 后台自动清理完成：已静默销毁云端 $cleanedCount 个过期剪贴板图片/已删文件');
              }
              try {
                if (remainingDeletedKeys.isEmpty && deletedFile.existsSync()) {
                  deletedFile.deleteSync();
                } else if (remainingDeletedKeys.isNotEmpty) {
                  deletedFile.writeAsStringSync(jsonEncode(remainingDeletedKeys.toList()));
                }
              } catch (_) {}
            }));
          }

          addD1Log(text(
            '✅ 同步完成: + $newlyUploadedCount 上传  |  ↓ $newlyDownloadedCount 下载  |  = $skippedIdenticalCount 无变动 (后台异步清理 ${toDeleteRemote.length} 项)',
            '✅ Sync completed: + $newlyUploadedCount uploaded | ↓ $newlyDownloadedCount downloaded | = $skippedIdenticalCount unchanged',
          ));
        } catch (e) {
          addD1Log(text('⚠️ 文件同步异常: $e', '⚠️ File sync error: $e'));
        }
      } else {
        addD1Log(text(
          'ℹ️ 提示: 未配置 Worker 节点或存储桶，本次已完成本地便签与记录同步。',
          'Note: Worker/Bucket not configured. Local data sync completed.',
        ));
      }

      final isSuccess = d1Result['success'] == true;
      final fileSummary = (newlyUploadedCount > 0 || newlyDownloadedCount > 0 || deletedRemoteCount > 0)
          ? '，文件存储 (+ $newlyUploadedCount 上传, - $deletedRemoteCount 销毁, ↓ $newlyDownloadedCount 下载)'
          : (skippedIdenticalCount > 0
              ? '，全部本地文件与云端保持最新 (= $skippedIdenticalCount 无变动)'
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
      if (isSuccess) {
        setWorkspaceCloudOnline(currentWorkspace.id, true);
      }

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

    // 启动/配置变更后 3 秒静默探测当前工作区云端健康状况与 Web 节点版本
    Timer(const Duration(seconds: 3), () {
      if (!_isShuttingDown) {
        silentCheckWorkspaceHealth(currentWorkspace);
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

    final double effectiveDy = settings.invertScrollDirection ? -dy : dy;

    if (effectiveDy > 0) {
      // Throttle expand only
      final now = DateTime.now();
      if (now.difference(_lastScrollAction).inMilliseconds < 200) return;
      _lastScrollAction = now;

      if (isAnimating && !isExpanded) {
        cancelCollapseAndExpand();
      } else if (!isExpanded && !isAnimating) {
        expandPanel(focus: true, duration: const Duration(milliseconds: 250));
      }
    } else if (effectiveDy < 0) {
      if (isAnimating && isExpanded) {
        cancelExpandAndCollapse();
      } else if (isExpanded && !isAnimating) {
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

        // Position window directly below the status bar
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

      // 唤醒面板时：若开启了自动同步且距离上次同步超过 15 秒，后台静默拉取一次云端最新增量
      if (settings.cfD1AutoSync &&
          !_isD1Syncing &&
          (_lastD1SyncTime == null ||
              DateTime.now().difference(_lastD1SyncTime!).inSeconds >= 15)) {
        final hasWorker = settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty;
        final hasRest = settings.cfD1Mode == 1 && (settings.cfAccountId?.trim().isNotEmpty == true);
        if (hasWorker || hasRest) {
          unawaited(syncLocalDataToD1(isManual: false));
        }
      }
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

    // 收起面板时：若有尚未落盘或尚未上传的改动，立即在后台静默落盘并上传
    if (_notesSaveTimer?.isActive ?? false) {
      _notesSaveTimer?.cancel();
      unawaited(_saveNotes().then((_) {
        if (settings.cfD1AutoSync && !_isD1Syncing) {
          _d1LiveSyncDebounceTimer?.cancel();
          unawaited(syncLocalDataToD1(isManual: false));
        }
      }));
    } else if (_d1LiveSyncDebounceTimer?.isActive ?? false) {
      _d1LiveSyncDebounceTimer?.cancel();
      if (settings.cfD1AutoSync && !_isD1Syncing) {
        unawaited(syncLocalDataToD1(isManual: false));
      }
    }

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
        await windowManager.hide();
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

  void cancelExpandAndCollapse() {
    if (isExpanded) {
      _autoCollapseTimer?.cancel();
      isExpanded = false;
      isAnimating = true;
      FocusManager.instance.primaryFocus?.unfocus();
      _restoreFocusAfterCollapse = _didGrabFocus;
      _didGrabFocus = false;
      onAnimationStateChanged?.call(const Duration(milliseconds: 200));
      unawaited(_runPostCollapseMaintenance());
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

  // --- Workspace & Vault Management ---
  final List<WorkspaceProfile> _workspaces = [];
  WorkspaceProfile? _currentWorkspace;

  List<WorkspaceProfile> get workspaces => List.unmodifiable(_workspaces);

  WorkspaceProfile get currentWorkspace {
    if (_currentWorkspace != null) return _currentWorkspace!;
    return _ensureDefaultWorkspace();
  }

  WorkspaceProfile _ensureDefaultWorkspace() {
    final curDir = getDataDirectoryPathSync();
    final profile = WorkspaceProfile(
      id: 'default',
      name: '默认工作区',
      directoryPath: curDir,
      cfWorkerUrl: settings.cfWorkerUrl,
      cfAccountId: settings.cfAccountId,
      cfApiToken: settings.cfApiToken,
      cfD1DatabaseId: settings.cfD1DatabaseId,
      cfR2BucketName: settings.cfR2BucketName,
      cfD1AutoSync: settings.cfD1AutoSync,
      cfD1SyncIntervalMinutes: settings.cfD1SyncIntervalMinutes,
      vaultId: settings.vaultId ?? 'vlt_default_${DateTime.now().millisecondsSinceEpoch}',
    );
    _currentWorkspace = profile;
    if (!_workspaces.any((w) => w.id == profile.id)) {
      _workspaces.add(profile);
    }
    return profile;
  }

  void _loadWorkspaces() {
    _workspaces.clear();
    final workspacesJson = _prefs.getString('workspaces');
    if (workspacesJson != null && workspacesJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(workspacesJson) as List;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _workspaces.add(WorkspaceProfile.fromJson(item));
          }
        }
      } catch (e) {
        debugPrint('Failed to parse workspaces from prefs: $e');
      }
    }

    final curDir = getDataDirectoryPathSync();
    final wsFile = File('$curDir/workspace.json');
    WorkspaceProfile? localProfile;
    if (wsFile.existsSync()) {
      try {
        final content = wsFile.readAsStringSync();
        localProfile = WorkspaceProfile.fromJson(jsonDecode(content));
      } catch (e) {
        debugPrint('Failed to read workspace.json from $curDir: $e');
      }
    }

    if (localProfile != null) {
      final existingIdx = _workspaces.indexWhere((w) => w.id == localProfile!.id);
      if (existingIdx >= 0) {
        _workspaces[existingIdx] = localProfile;
      } else {
        _workspaces.add(localProfile);
      }
    }

    if (_workspaces.isEmpty) {
      _ensureDefaultWorkspace();
      unawaited(_saveWorkspaceMetadataFile());
      unawaited(_saveWorkspacesList());
    }

    final activeId = settings.activeWorkspaceId ?? localProfile?.id;
    _currentWorkspace = _workspaces.firstWhere(
      (w) => w.id == activeId,
      orElse: () => _workspaces.first,
    );

    if (!wsFile.existsSync()) {
      unawaited(_saveWorkspaceMetadataFile());
    }
  }

  Future<void> _saveWorkspacesList() async {
    final list = _workspaces.map((w) => w.toJson()).toList();
    await _prefs.setString('workspaces', jsonEncode(list));
  }

  // --- Workspace Cloud Health & Connectivity Cache ---
  final Map<String, bool> _workspaceCloudOnlineMap = {};
  final Map<String, double> _workspacePingRttMap = {};
  final Map<String, DateTime> _workspaceLastHealthCheckMap = {};

  bool? getWorkspaceCloudOnline(String wsId) {
    if (_workspaceCloudOnlineMap.containsKey(wsId)) {
      return _workspaceCloudOnlineMap[wsId];
    }
    if (wsId == currentWorkspace.id && _lastD1SyncSuccess == true) {
      _workspaceCloudOnlineMap[wsId] = true;
      return true;
    }
    final everConnected = _prefs.getBool('ws_cloud_online_$wsId');
    if (everConnected == true) {
      _workspaceCloudOnlineMap[wsId] = true;
      return true;
    }
    return null;
  }

  double? getWorkspacePingRtt(String wsId) {
    if (_workspacePingRttMap.containsKey(wsId)) {
      return _workspacePingRttMap[wsId];
    }
    final savedRtt = _prefs.getDouble('ws_cloud_rtt_$wsId');
    if (savedRtt != null) {
      _workspacePingRttMap[wsId] = savedRtt;
      return savedRtt;
    }
    return null;
  }

  /// 记录各工作区探测到的线上 Worker 版本号
  final Map<String, String?> _workspaceWorkerVersionMap = {};
  bool _isAutoUpgradingWorker = false;

  String? getWorkspaceWorkerVersion(String wsId) => _workspaceWorkerVersionMap[wsId];

  bool isWorkspaceWorkerOutdated(String wsId) {
    final v = _workspaceWorkerVersionMap[wsId];
    if (v == null) return false;
    return v != CfD1SyncService.currentWorkerVersion;
  }

  void setWorkspaceCloudOnline(String wsId, bool isOnline, {double? rttMs, String? version}) {
    _workspaceCloudOnlineMap[wsId] = isOnline;
    unawaited(_prefs.setBool('ws_cloud_online_$wsId', isOnline));
    if (rttMs != null) {
      _workspacePingRttMap[wsId] = rttMs;
      unawaited(_prefs.setDouble('ws_cloud_rtt_$wsId', rttMs));
    }
    if (version != null) {
      _workspaceWorkerVersionMap[wsId] = version;
    }
    _workspaceLastHealthCheckMap[wsId] = DateTime.now();
    notifyListeners();
  }

  /// 后台静默检测工作区云端连通性与版本 (保留上次结果，不阻塞 UI，成功则维持/刷新绿色与延迟，落后则自动热升级)
  Future<void> silentCheckWorkspaceHealth(WorkspaceProfile ws) async {
    final url = ws.cfWorkerUrl?.trim() ?? '';
    if (url.isEmpty) return;

    final lastCheck = _workspaceLastHealthCheckMap[ws.id];
    if (lastCheck != null &&
        DateTime.now().difference(lastCheck).inMinutes < 5 &&
        _workspaceCloudOnlineMap[ws.id] == true &&
        _workspaceWorkerVersionMap[ws.id] == CfD1SyncService.currentWorkerVersion) {
      return;
    }

    try {
      final service = CfD1SyncService(workerUrl: url, isDevMode: kDebugMode);
      final res = await service.checkHealth();
      if (res['success'] == true) {
        final rtt = res['rttMs'] as double?;
        final serverVersion = res['version'] as String?;
        setWorkspaceCloudOnline(ws.id, true, rttMs: rtt, version: serverVersion);

        // 如果检测到线上 Web/Worker 版本与客户端内置版本不一致，且有 Cloudflare 凭据，后台自动静默热升级
        if (serverVersion != CfD1SyncService.currentWorkerVersion) {
          unawaited(_checkAndAutoUpgradeWorker(ws, detectedVersion: serverVersion));
        }
      } else {
        if (_workspaceCloudOnlineMap[ws.id] != true) {
          setWorkspaceCloudOnline(ws.id, false);
        }
      }
    } catch (_) {}
  }

  /// 自动静默热升级 Cloudflare Worker 与 Web 随行端
  Future<void> _checkAndAutoUpgradeWorker(WorkspaceProfile ws, {String? detectedVersion}) async {
    if (_isAutoUpgradingWorker) return;
    final accountId = ws.cfAccountId?.trim().isNotEmpty == true ? ws.cfAccountId!.trim() : settings.cfAccountId?.trim();
    final apiToken = ws.cfApiToken?.trim().isNotEmpty == true ? ws.cfApiToken!.trim() : settings.cfApiToken?.trim();

    if (accountId == null || accountId.isEmpty || apiToken == null || apiToken.isEmpty) {
      debugPrint('ℹ️ [Worker Upgrade] 发现线上 Web/Worker 版本 ($detectedVersion) 需升级至 ${CfD1SyncService.currentWorkerVersion}，但未配置 CF API Token，跳过静默升级。');
      return;
    }

    _isAutoUpgradingWorker = true;
    try {
      debugPrint('🚀 [Worker Upgrade] 发现线上 Web 版本 ($detectedVersion) 落后于客户端 (${CfD1SyncService.currentWorkerVersion})，正在后台静默热升级...');
      addD1Log(text(
        '🚀 检测到线上 Web 节点版本 (${detectedVersion ?? "旧版"}) 落后，开始后台静默热升级至 v${CfD1SyncService.currentWorkerVersion}...',
        'Outdated Worker version (${detectedVersion ?? "legacy"}) detected. Auto-upgrading to v${CfD1SyncService.currentWorkerVersion}...',
      ));

      String workerName = 'pod-quick-backend';
      try {
        final targetUrl = ws.cfWorkerUrl?.trim().isNotEmpty == true ? ws.cfWorkerUrl! : settings.cfWorkerUrl;
        final uri = Uri.parse(targetUrl);
        final host = uri.host;
        if (host.contains('.')) {
          workerName = host.split('.').first;
        }
      } catch (_) {}

      final res = await CfD1SyncService.updateWorkerCodeAndWeb(
        accountId: accountId,
        apiToken: apiToken,
        workerName: workerName,
        d1DatabaseId: ws.cfD1DatabaseId ?? settings.cfD1DatabaseId,
        r2BucketName: ws.cfR2BucketName ?? settings.cfR2BucketName,
        onLog: (msg) {
          debugPrint('[Worker Silent Upgrade] $msg');
          addD1Log(msg);
        },
      );

      if (res['success'] == true) {
        _workspaceWorkerVersionMap[ws.id] = CfD1SyncService.currentWorkerVersion;
        notifyListeners();
        debugPrint('🎉 [Worker Upgrade] Cloudflare Worker 与 Web 控制台已成功静默升级至 v${CfD1SyncService.currentWorkerVersion}！');
        addD1Log(text(
          '🎉 Cloudflare Worker 与 Web 随行控制台已静默升级至最新版 v${CfD1SyncService.currentWorkerVersion}！',
          'Cloudflare Worker and Web console upgraded to v${CfD1SyncService.currentWorkerVersion} successfully!',
        ));
      } else {
        debugPrint('⚠️ [Worker Upgrade] 静默升级失败: ${res['error']}');
      }
    } catch (e) {
      debugPrint('⚠️ [Worker Upgrade] 静默升级异常: $e');
    } finally {
      _isAutoUpgradingWorker = false;
    }
  }

  /// 手动触发升级 Worker 节点与 Web 控制台
  Future<Map<String, dynamic>> manualUpgradeWorkerNode({
    WorkspaceProfile? workspace,
    String? accountId,
    String? apiToken,
    Function(String msg)? onLog,
  }) async {
    final ws = workspace ?? currentWorkspace;
    final effectiveAccountId = (accountId != null && accountId.trim().isNotEmpty)
        ? accountId.trim()
        : ((ws.cfAccountId?.trim().isNotEmpty == true)
            ? ws.cfAccountId!.trim()
            : settings.cfAccountId?.trim());

    final effectiveApiToken = (apiToken != null && apiToken.trim().isNotEmpty)
        ? apiToken.trim()
        : ((ws.cfApiToken?.trim().isNotEmpty == true)
            ? ws.cfApiToken!.trim()
            : settings.cfApiToken?.trim());

    if (effectiveAccountId == null || effectiveAccountId.isEmpty || effectiveApiToken == null || effectiveApiToken.isEmpty) {
      return {
        'success': false,
        'error': text('未找到 Cloudflare API 凭据，请在下方配置中填入 Account ID 与 API Token', 'Missing CF Account ID or API Token'),
      };
    }

    String workerName = 'pod-quick-backend';
    try {
      final targetUrl = ws.cfWorkerUrl?.trim().isNotEmpty == true ? ws.cfWorkerUrl! : settings.cfWorkerUrl;
      final uri = Uri.parse(targetUrl);
      final host = uri.host;
      if (host.contains('.')) {
        workerName = host.split('.').first;
      }
    } catch (_) {}

    final res = await CfD1SyncService.updateWorkerCodeAndWeb(
      accountId: effectiveAccountId,
      apiToken: effectiveApiToken,
      workerName: workerName,
      d1DatabaseId: ws.cfD1DatabaseId ?? settings.cfD1DatabaseId,
      r2BucketName: ws.cfR2BucketName ?? settings.cfR2BucketName,
      onLog: onLog,
    );

    if (res['success'] == true) {
      _workspaceWorkerVersionMap[ws.id] = CfD1SyncService.currentWorkerVersion;
      setWorkspaceCloudOnline(ws.id, true, version: CfD1SyncService.currentWorkerVersion);
      notifyListeners();
    }
    return res;
  }

  Future<void> _saveWorkspaceMetadataFile() async {
    try {
      final cur = currentWorkspace;
      final dir = Directory(cur.directoryPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${cur.directoryPath}/workspace.json');
      await file.writeAsString(jsonEncode(cur.toJson()));
    } catch (e) {
      debugPrint('Failed to save workspace.json: $e');
    }
  }

  Future<bool> switchWorkspace(String workspaceId) async {
    final target = _workspaces.firstWhere(
      (w) => w.id == workspaceId,
      orElse: () => _workspaces.first,
    );
    if (target.id == _currentWorkspace?.id &&
        target.directoryPath.toLowerCase() == getDataDirectoryPathSync().toLowerCase()) {
      return true;
    }

    // 1. 保存当前工作区
    await _saveWorkspaceMetadataFile();
    await _saveNotes();
    await _saveClipboardHistory();

    // 2. 切换当前激活的工作区档案并同步全局配置
    _currentWorkspace = target;
    _lastD1SyncTime = null; // 重置增量同步基准时间，确保新工作区能完整感知其云端数据
    final updatedSettings = settings.copyWith(
      activeWorkspaceId: target.id,
      dataDirectory: target.directoryPath,
      cfWorkerUrl: target.cfWorkerUrl ?? '',
      cfAccountId: target.cfAccountId,
      cfApiToken: target.cfApiToken,
      cfD1DatabaseId: target.cfD1DatabaseId,
      cfR2BucketName: target.cfR2BucketName,
      cfD1AutoSync: target.cfD1AutoSync,
      cfD1SyncIntervalMinutes: target.cfD1SyncIntervalMinutes,
      vaultId: target.vaultId,
    );
    await updateSettings(updatedSettings);

    // 3. 确保存储目录存在
    final targetDir = Directory(target.directoryPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    await _saveWorkspaceMetadataFile();

    // 4. 重置并重新加载目标目录的数据
    notes = [];
    activeNote = null;
    clipboardHistory = [];
    await Future.wait([
      _loadNotes(),
      _loadClipboardHistory(),
      _scanStoredFiles(),
    ]);

    // 5. 重新配置目录监听器
    await Future.wait([
      _startWatchingImagesDirectory(),
      _startWatchingDataDirectory(),
    ]);

    // 6. 安全判定：如果是空目录且配置了云端，自动全量从云端拉取恢复数据！
    if (notes.isEmpty && clipboardHistory.isEmpty && target.hasCloudConfig) {
      debugPrint('Target workspace is empty, triggering auto-restore from cloud...');
      addD1Log(text('检测到当前工作区为空，正在自动从云端全量拉取数据恢复...', 'Empty workspace detected. Restoring all data from cloud...'));
      unawaited(syncLocalDataToD1(isManual: true));
    }

    notifyListeners();
    return true;
  }

  Future<WorkspaceProfile> createWorkspace({
    required String name,
    String? customPath,
    WorkspaceInitType initType = WorkspaceInitType.blank,
    bool inheritCloudConfig = false,
    bool autoSwitch = false,
  }) async {
    final cleanName = name.trim().isEmpty ? '新建工作区' : name.trim();
    final id = 'ws_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 6)}';

    String dirPath;
    if (customPath != null && customPath.trim().isNotEmpty) {
      dirPath = customPath.trim().replaceAll('\\', '/');
    } else {
      final baseAppSupport = await getApplicationSupportDirectory();
      String candidate = '${baseAppSupport.path}/workspaces/$cleanName'.replaceAll('\\', '/');
      // 如果候选目录已被其他现有工作区占用，追加短时间戳后缀确保目录独立隔离
      if (_workspaces.any((w) => w.directoryPath.toLowerCase() == candidate.toLowerCase())) {
        candidate = '${baseAppSupport.path}/workspaces/${cleanName}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'.replaceAll('\\', '/');
      }
      dirPath = candidate;
    }

    final targetDir = Directory(dirPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    // 依据初始化类型复制或迁移数据
    final currentDir = Directory(getDataDirectoryPathSync());
    if (initType == WorkspaceInitType.copy) {
      for (final f in ['notes.json', 'clipboard_favorites.json']) {
        final src = File('${currentDir.path}/$f');
        if (src.existsSync()) src.copySync('${targetDir.path}/$f');
      }
      // Copy clipboard history files
      if (currentDir.existsSync()) {
        for (final entity in currentDir.listSync()) {
          if (entity is File) {
            final name = entity.path.replaceAll('\\', '/').split('/').last;
            if (name == 'clipboard_history.json' ||
                (name.startsWith('clipboard_history-') && name.endsWith('.json'))) {
              entity.copySync('${targetDir.path}/$name');
            }
          }
        }
      }
      final srcImages = Directory('${currentDir.path}/clipboard_images');
      if (srcImages.existsSync()) {
        final dstImages = Directory('${targetDir.path}/clipboard_images');
        if (!dstImages.existsSync()) dstImages.createSync(recursive: true);
        for (final entity in srcImages.listSync()) {
          if (entity is File) {
            final filename = entity.path.replaceAll('\\', '/').split('/').last;
            entity.copySync('${dstImages.path}/$filename');
          }
        }
      }
      final srcFiles = Directory('${currentDir.path}/files');
      if (srcFiles.existsSync()) {
        final dstFiles = Directory('${targetDir.path}/files');
        if (!dstFiles.existsSync()) dstFiles.createSync(recursive: true);
        await _copyDirectory(srcFiles, dstFiles);
      }
    } else if (initType == WorkspaceInitType.migrate) {
      await changeDataDirectory(dirPath);
    } else if (initType == WorkspaceInitType.blank) {
      // 全新空白工作区：彻底确保目录100%绝对干净，清空所有残留文件与备份快照
      try {
        if (targetDir.existsSync()) {
          for (final entity in targetDir.listSync()) {
            try {
              entity.deleteSync(recursive: true);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    final vaultId = 'vlt_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';
    final profile = WorkspaceProfile(
      id: id,
      name: cleanName,
      directoryPath: dirPath,
      cfWorkerUrl: inheritCloudConfig ? settings.cfWorkerUrl : null,
      cfAccountId: inheritCloudConfig ? settings.cfAccountId : null,
      cfApiToken: inheritCloudConfig ? settings.cfApiToken : null,
      cfD1DatabaseId: inheritCloudConfig ? settings.cfD1DatabaseId : null,
      cfR2BucketName: inheritCloudConfig ? settings.cfR2BucketName : null,
      cfD1AutoSync: inheritCloudConfig ? settings.cfD1AutoSync : false,
      cfD1SyncIntervalMinutes: inheritCloudConfig ? settings.cfD1SyncIntervalMinutes : 5,
      vaultId: vaultId,
    );

    // 在目标目录写入工作区元数据
    try {
      final metaFile = File('${profile.directoryPath}/workspace.json');
      metaFile.writeAsStringSync(jsonEncode(profile.toJson()));
    } catch (_) {}

    _workspaces.add(profile);
    await _saveWorkspacesList();

    if (autoSwitch) {
      await switchWorkspace(id);
    }

    notifyListeners();
    return profile;
  }

  Future<void> saveWorkspaceProfile(WorkspaceProfile updated) async {
    final idx = _workspaces.indexWhere((w) => w.id == updated.id);
    if (idx >= 0) {
      _workspaces[idx] = updated;
    } else {
      _workspaces.add(updated);
    }
    if (_currentWorkspace?.id == updated.id) {
      _currentWorkspace = updated;
    }
    try {
      final dir = Directory(updated.directoryPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${updated.directoryPath}/workspace.json');
      await file.writeAsString(jsonEncode(updated.toJson()));
    } catch (e) {
      debugPrint('Failed to save workspace.json for ${updated.name}: $e');
    }
    await _saveWorkspacesList();
    notifyListeners();
  }

  Future<void> updateCurrentWorkspaceProfile(WorkspaceProfile updated) async {
    await saveWorkspaceProfile(updated);
  }

  Future<bool> renameWorkspace(String workspaceId, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return false;
    final idx = _workspaces.indexWhere((w) => w.id == workspaceId);
    if (idx < 0) return false;
    final updated = _workspaces[idx].copyWith(name: clean);
    await saveWorkspaceProfile(updated);
    notifyListeners();
    return true;
  }

  Future<bool> deleteWorkspace(String workspaceId) async {
    if (_workspaces.length <= 1) return false;
    final idx = _workspaces.indexWhere((w) => w.id == workspaceId);
    if (idx < 0) return false;

    if (_currentWorkspace?.id == workspaceId) {
      final fallback = _workspaces.firstWhere((w) => w.id != workspaceId);
      await switchWorkspace(fallback.id);
    }

    _workspaces.removeWhere((w) => w.id == workspaceId);
    await _saveWorkspacesList();
    notifyListeners();
    return true;
  }

  Set<String> _getActiveClipboardImageKeys() {
    final keys = <String>{};
    void addFromItem(ClipboardItem item) {
      final raw = item.imagePath?.trim();
      if (raw == null || raw.isEmpty) return;
      final norm = raw.replaceAll('\\', '/');
      if (norm.contains('clipboard_images/')) {
        final fileName = norm.split('clipboard_images/').last;
        if (fileName.isNotEmpty) {
          keys.add('clipboard_images/$fileName');
        }
      } else if (!norm.contains('/')) {
        keys.add('clipboard_images/$norm');
      }
    }

    for (final item in clipboardHistory) {
      addFromItem(item);
    }
    for (final item in clipboardFavorites) {
      addFromItem(item);
    }
    return keys;
  }

  bool _trimClipboardHistoryToLimit() {
    final limit = settings.clipboardHistoryLimit;
    if (clipboardHistory.length <= limit) return false;

    final now = DateTime.now();
    final removedItems = clipboardHistory.sublist(limit);
    clipboardHistory = clipboardHistory.take(limit).toList();
    for (final item in removedItems) {
      _itemTypeCache.remove(item.id);
      // 若该记录未被收藏，加入删除墓碑以便后台同步时通知云端 D1 标记清理，防止从云端反复拉回
      final inFav = clipboardFavorites.any((f) => f.id == item.id);
      if (!inFav) {
        deletedClipboards.removeWhere((x) => x.id == item.id);
        deletedClipboards.add(item.copyWith(isDeleted: true, updatedAt: now));
      }
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

    // 放入后台异步清理本地过期图片并记录云端待删墓碑，不阻塞前台
    unawaited(Future(() async {
      try {
        await recordDeletedFile(path);
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Failed to delete unused clipboard image: $e');
      }
    }));
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

    // 4. Update AppSettings and WorkspaceProfile
    final updatedSettings = settings.copyWith(dataDirectory: cleanNewPath);
    await updateSettings(updatedSettings);
    if (_currentWorkspace != null) {
      _currentWorkspace = _currentWorkspace!.copyWith(directoryPath: cleanNewPath);
      await saveWorkspaceProfile(_currentWorkspace!);
    }

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
    // 切换到新目录后，清空内存中的待删墓碑，避免将旧目录的删除指令带入新环境
    deletedNotes.clear();
    deletedClipboards.clear();
    notes.clear();
    activeNote = null;
    clipboardHistory.clear();
    clipboardFavorites.clear();
    storedFiles.clear();

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
    _triggerD1LiveAutoSync();
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
      _triggerD1LiveAutoSync();
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

    if (itemToDelete != null) {
      deletedClipboards.removeWhere((x) => x.id == id);
      deletedClipboards.add(
        itemToDelete.copyWith(isDeleted: true, updatedAt: DateTime.now()),
      );
    }

    notifyListeners();

    Future.delayed(Duration.zero, () {
      _saveClipboardHistory();
      _saveClipboardFavorites();
      _triggerD1LiveAutoSync();

      if (itemToDelete != null && itemToDelete.imagePath != null) {
        _deleteClipboardImageIfUnused(itemToDelete);
      }
    });
  }

  void toggleFavoriteClipboardItem(ClipboardItem item) {
    final now = DateTime.now();
    final isFav = isItemFavorite(item);
    if (isFav) {
      if (item.imagePath != null) {
        clipboardFavorites.removeWhere((x) =>
            x.imagePath != null &&
            (x.id == item.id ||
             (x.imageSignature != null && item.imageSignature != null && x.imageSignature == item.imageSignature) ||
             (x.imageSignature == null && item.imageSignature == null && getImagePath(x) == getImagePath(item))));
      } else {
        clipboardFavorites.removeWhere((x) => x.id == item.id || x.content == item.content);
      }
      final histIdx = clipboardHistory.indexWhere((x) => x.id == item.id);
      if (histIdx != -1) {
        clipboardHistory[histIdx] = clipboardHistory[histIdx].copyWith(
          isFavorite: false,
          updatedAt: now,
        );
      } else {
        // 关键：若不在历史列表中（例如较早前收藏的项），必须将其以 isFavorite: false 插入到历史中
        // 确保它带有最新的 updatedAt，并且在本地和推送同步时明确以非收藏状态向云端 D1 覆盖！
        clipboardHistory.insert(
          0,
          item.copyWith(isFavorite: false, updatedAt: now),
        );
      }
    } else {
      clipboardFavorites.insert(
        0,
        item.copyWith(isFavorite: true, timestamp: now, updatedAt: now),
      );
      final histIdx = clipboardHistory.indexWhere((x) => x.id == item.id);
      if (histIdx != -1) {
        clipboardHistory[histIdx] = clipboardHistory[histIdx].copyWith(
          isFavorite: true,
          updatedAt: now,
        );
      }
    }
    Future.delayed(Duration.zero, () {
      _saveClipboardFavorites();
      _saveClipboardHistory();
      _triggerD1LiveAutoSync();
    });
    notifyListeners();
  }

  void clearClipboardHistory() {
    _itemTypeCache.clear();
    final now = DateTime.now();
    final oldItems = List<ClipboardItem>.from(clipboardHistory);
    clipboardHistory.clear();
    for (final item in oldItems) {
      final inFav = clipboardFavorites.any((f) => f.id == item.id);
      if (!inFav) {
        deletedClipboards.removeWhere((x) => x.id == item.id);
        deletedClipboards.add(item.copyWith(isDeleted: true, updatedAt: now));
      }
      _deleteClipboardImageIfUnused(item);
    }
    Future.delayed(Duration.zero, () {
      _saveClipboardHistory();
      _triggerD1LiveAutoSync();
    });
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
            await recordDeletedFile(file.path);
            await file.delete();
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
      final normDataDir = dataDir.replaceAll('\\', '/');

      final deletedFile = File('$dataDir/deleted_files.json');
      final Set<String> deletedKeys = {};
      if (await deletedFile.exists()) {
        try {
          final content = await deletedFile.readAsString();
          final list = jsonDecode(content) as List;
          deletedKeys.addAll(list.cast<String>());
        } catch (_) {}
      }

      void addKeyForPath(String targetPath) {
        final normEntity = targetPath.replaceAll('\\', '/');
        String relKey = normEntity;
        if (normEntity.startsWith(normFilesDir)) {
          relKey = normEntity.substring(normFilesDir.length);
        } else if (normEntity.startsWith(normDataDir)) {
          relKey = normEntity.substring(normDataDir.length);
        }
        if (relKey.startsWith('/')) relKey = relKey.substring(1);
        if (relKey.isEmpty || relKey.startsWith('.') || relKey.contains('/.')) return;
        final fullKey = (relKey.startsWith('files/') || relKey.startsWith('clipboard_images/') || relKey.startsWith('images/'))
            ? relKey
            : 'files/$relKey';
        deletedKeys.add(fullKey);
      }

      final type = FileSystemEntity.typeSync(entityPath);
      if (type == FileSystemEntityType.directory) {
        addKeyForPath(entityPath);
        final dir = Directory(entityPath);
        if (dir.existsSync()) {
          final children = dir.listSync(recursive: true).whereType<File>();
          for (final f in children) {
            addKeyForPath(f.path);
          }
        }
      } else {
        addKeyForPath(entityPath);
      }

      await deletedFile.writeAsString(jsonEncode(deletedKeys.toList()));
    } catch (e) {
      debugPrint('Failed to record deleted file: $e');
    }
  }

  Future<void> deleteFile(FileSystemEntity entity) async {
    // 前台 0 毫秒立即从内存列表移除并刷新 UI
    final targetPathNorm = entity.path.replaceAll('\\', '/').toLowerCase();
    storedFiles.removeWhere(
      (f) => f.path.replaceAll('\\', '/').toLowerCase() == targetPathNorm,
    );
    notifyListeners();

    try {
      if (entity.existsSync()) {
        // 先记录待删路径（此时实体还在原位置，便于目录遍历）
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
    // 设置弹窗开启时，用户正在配置凭据或查看设置，不触发剪贴板复制触发的即时同步
    if (isDialogOpen) return;

    final isWorkerConfigured = settings.cfD1Mode == 0 && settings.cfWorkerUrl.trim().isNotEmpty;
    final isRestConfigured = settings.cfD1Mode == 1 &&
        settings.cfAccountId?.trim().isNotEmpty == true &&
        settings.cfApiToken?.trim().isNotEmpty == true &&
        settings.cfD1DatabaseId?.trim().isNotEmpty == true;

    if ((!isWorkerConfigured && !isRestConfigured) || !settings.cfD1AutoSync) return;

    _d1LiveSyncDebounceTimer?.cancel();
    _d1LiveSyncDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
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

    // 智能防风险：通用本地容灾拾遗，自动扫描并合并因多设备离线同步或外部拷贝产生的同类衍生副本，校验后在后台静默清理
    await autoIngestAndCleanupRedundantFiles();

    // 启动时若已有便签，自动创建一份本地快照，确保万无一失
    if (notes.isNotEmpty) {
      unawaited(_createNotesBackup('app_launch'));
    }

    // Select first note
    activeNote = notes.isNotEmpty ? notes.first : null;
  }

  /// 通用本地容灾拾遗与冗余副本静默清理 (通用规则，不针对任何特定网盘)
  /// 1. 扫描当前数据目录下因多设备离线同步或外部拷贝产生的同类衍生副本
  /// 2. 内存无损并集合并（按 ID + updatedAt 最新规则），校验条数只增不减
  /// 3. 原子落盘写入主库文件，并校验磁盘主文件有效性
  /// 4. 门禁校验全部通过后，在后台静默清理冗余副本文件
  Future<void> autoIngestAndCleanupRedundantFiles() async {
    try {
      final dataDirPath = getDataDirectoryPathSync();
      final dataDir = Directory(dataDirPath);
      if (!dataDir.existsSync()) return;

      final allEntities = dataDir.listSync();
      final allFiles = allEntities.whereType<File>().toList();

      // 1. 处理便签衍生副本 (notes-*.json / notes (*).json)
      final noteConflictFiles = allFiles.where((f) {
        final name = f.path.split(Platform.pathSeparator).last;
        if (name == 'notes.json' || name.startsWith('deleted_notes') || name.startsWith('notes_backup')) {
          return false;
        }
        return (name.startsWith('notes-') || name.startsWith('notes (')) && name.endsWith('.json');
      }).toList();

      if (noteConflictFiles.isNotEmpty) {
        final Map<String, Note> mergedNotes = {for (final n in notes) n.id: n};
        bool hasChanges = false;
        final List<File> filesVerifiedToClean = [];

        for (final cFile in noteConflictFiles) {
          try {
            if (cFile.lengthSync() == 0) {
              filesVerifiedToClean.add(cFile);
              continue;
            }
            final content = cFile.readAsStringSync();
            final decoded = jsonDecode(content) as List;
            bool fileAllPresent = true;
            for (final item in decoded) {
              if (item is Map<String, dynamic> && item['id'] != null) {
                final parsed = Note.fromJson(item);
                if (!mergedNotes.containsKey(parsed.id) || parsed.updatedAt.isAfter(mergedNotes[parsed.id]!.updatedAt)) {
                  mergedNotes[parsed.id] = parsed;
                  hasChanges = true;
                }
              } else {
                fileAllPresent = false;
              }
            }
            if (fileAllPresent) {
              filesVerifiedToClean.add(cFile);
            }
          } catch (e) {
            debugPrint('Failed to ingest note conflict file ${cFile.path}: $e');
          }
        }

        if (hasChanges) {
          notes = mergedNotes.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          await _saveNotes();
          await _createNotesBackup('auto_ingested');
          notifyListeners();
        }

        // 门禁校验：主 notes.json 存在且大小正常，方可静默删除副本
        final mainNotesFile = File('$dataDirPath/notes.json');
        if (mainNotesFile.existsSync() && mainNotesFile.lengthSync() > 10) {
          for (final f in filesVerifiedToClean) {
            try {
              f.deleteSync();
              debugPrint('🧹 静默清理已吸收的便签副本: ${f.path}');
            } catch (_) {}
          }
        }
      }

      // 2. 处理剪贴板历史衍生副本 (例如 clipboard_history-设备名-电脑名-序号.json)
      final clipConflictFiles = allFiles.where((f) {
        final name = f.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('clipboard_history-') || !name.endsWith('.json')) return false;
        // 排除当前机器的标准设备命名文件
        final currentDevFilename = _getClipboardHistoryFilename();
        if (name == currentDevFilename) return false;
        // 衍生文件特征：包含次级连字符、括号或 -数字.json
        final afterPrefix = name.substring('clipboard_history-'.length);
        return afterPrefix.contains('-') || name.contains('(') || RegExp(r'-\d+\.json$').hasMatch(name);
      }).toList();

      if (clipConflictFiles.isNotEmpty) {
        final Map<String, ClipboardItem> mergedClips = {for (final c in clipboardHistory) c.id: c};
        final List<File> clipFilesVerifiedToClean = [];
        bool hasClipChanges = false;

        for (final cFile in clipConflictFiles) {
          try {
            if (cFile.lengthSync() == 0) {
              clipFilesVerifiedToClean.add(cFile);
              continue;
            }
            final content = cFile.readAsStringSync();
            final decoded = jsonDecode(content) as List;
            for (final item in decoded) {
              if (item is Map<String, dynamic> && item['id'] != null) {
                final parsed = ClipboardItem.fromJson(item);
                if (!mergedClips.containsKey(parsed.id) || parsed.updatedAt.isAfter(mergedClips[parsed.id]!.updatedAt)) {
                  mergedClips[parsed.id] = parsed;
                  hasClipChanges = true;
                }
              }
            }
            clipFilesVerifiedToClean.add(cFile);
          } catch (e) {
            debugPrint('Failed to ingest clipboard conflict file ${cFile.path}: $e');
          }
        }

        if (hasClipChanges) {
          clipboardHistory = mergedClips.values.toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          await _saveClipboardHistory();
          notifyListeners();
        }

        for (final f in clipFilesVerifiedToClean) {
          try {
            f.deleteSync();
            debugPrint('🧹 静默清理已吸收的剪贴板副本: ${f.path}');
          } catch (_) {}
        }
      }

      // 3. 处理已删除便签与文件墓碑衍生副本 (deleted_notes-*.json, deleted_files-*.json)
      final tombstoneConflictFiles = allFiles.where((f) {
        final name = f.path.split(Platform.pathSeparator).last;
        return (name.startsWith('deleted_notes-') || name.startsWith('deleted_files-')) && name.endsWith('.json');
      }).toList();

      if (tombstoneConflictFiles.isNotEmpty) {
        for (final f in tombstoneConflictFiles) {
          try {
            final name = f.path.split(Platform.pathSeparator).last;
            final content = f.readAsStringSync();
            final decoded = jsonDecode(content) as List;
            if (name.startsWith('deleted_notes-')) {
              for (final item in decoded) {
                if (item is Map<String, dynamic> && item['id'] != null) {
                  final parsed = Note.fromJson(item);
                  if (!deletedNotes.any((dn) => dn.id == parsed.id)) {
                    deletedNotes.add(parsed);
                  }
                }
              }
              await _saveDeletedNotes();
            } else if (name.startsWith('deleted_files-')) {
              for (final item in decoded) {
                if (item is String) {
                  recordDeletedFile(item);
                }
              }
            }
            f.deleteSync();
            debugPrint('🧹 静默清理已合并的墓碑副本: ${f.path}');
          } catch (_) {}
        }
      }

      // 4. 处理衍生快照副本 (last_sync_snapshot-*.json)
      final snapshotConflictFiles = allFiles.where((f) {
        final name = f.path.split(Platform.pathSeparator).last;
        return name.startsWith('last_sync_snapshot-') && name.endsWith('.json');
      }).toList();

      if (snapshotConflictFiles.isNotEmpty) {
        for (final f in snapshotConflictFiles) {
          try {
            f.deleteSync();
            debugPrint('🧹 静默清理多余的快照副本: ${f.path}');
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('autoIngestAndCleanupRedundantFiles error: $e');
    }
  }

  DateTime? _lastNotesBackupTime;

  /// 为便签生成本地安全滚动快照备份 (保留最近 5 份)
  Future<void> createNotesBackup(String reason) => _createNotesBackup(reason);

  Future<void> _createNotesBackup(String reason) async {
    if (notes.isEmpty) return;
    try {
      final dataDir = getDataDirectoryPathSync();
      final backupDir = Directory('$dataDir/backups/notes');
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      final now = DateTime.now();
      if (_lastNotesBackupTime != null &&
          now.difference(_lastNotesBackupTime!).inMinutes < 15 &&
          reason == 'auto_save') {
        return;
      }
      _lastNotesBackupTime = now;

      final ts = DateFormat('yyyyMMdd_HHmmss').format(now);
      final count = notes.length;
      final fileName = 'notes_${ts}_count${count}_$reason.json';
      final file = File('${backupDir.path}/$fileName');

      final encoded = jsonEncode(notes.map((item) => item.toJson()).toList());
      await file.writeAsString(encoded);

      // 仅保留最近 5 份历史快照，防止磁盘空间过度占用
      const int maxSnapshots = 5;
      final allBackups = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      if (allBackups.length > maxSnapshots) {
        for (int i = maxSnapshots; i < allBackups.length; i++) {
          try {
            allBackups[i].deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Failed to create notes backup: $e');
    }
  }

  static final Map<String, int> _noteBackupCountCache = {};

  /// 高速获取快照文件总数 (仅读取目录项，不读取文件内容，耗时 < 1ms)
  int getNotesBackupsCount({String? customDir}) {
    try {
      final cleanCustomDir = customDir?.trim();
      final dataDir = (cleanCustomDir != null && cleanCustomDir.isNotEmpty)
          ? cleanCustomDir
          : getDataDirectoryPathSync();
      final backupDir = Directory('$dataDir/backups/notes');
      if (!backupDir.existsSync()) return 0;
      return backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json') && f.lengthSync() > 0)
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// 获取便签本地快照备份文件列表 (毫秒级零阻塞响应，通过文件名提取与内存缓存消除卡顿)
  List<Map<String, dynamic>> getNotesBackups({String? customDir}) {
    try {
      final cleanCustomDir = customDir?.trim();
      final dataDir = (cleanCustomDir != null && cleanCustomDir.isNotEmpty)
          ? cleanCustomDir
          : getDataDirectoryPathSync();
      final backupDir = Directory('$dataDir/backups/notes');
      if (!backupDir.existsSync()) return [];

      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      final list = <Map<String, dynamic>>[];
      for (final f in files) {
        final name = f.path.split(Platform.pathSeparator).last;
        final size = f.lengthSync();
        if (size == 0) continue; // 过滤损坏的 0 字节文件

        final mTime = f.lastModifiedSync();
        int noteCount = 0;

        // 1. 优先从文件名正则直接提取便签条数 (耗时仅 0.001ms，完全无需读取磁盘)
        final match = RegExp(r'count(\d+)').firstMatch(name);
        if (match != null) {
          noteCount = int.tryParse(match.group(1)!) ?? 0;
        } else {
          // 2. 外部或非标命名的文件，使用带大小与时间戳的静态内存缓存，只在首次读取一次
          final cacheKey = '${f.path}:$size:${mTime.millisecondsSinceEpoch}';
          if (_noteBackupCountCache.containsKey(cacheKey)) {
            noteCount = _noteBackupCountCache[cacheKey]!;
          } else {
            try {
              final content = f.readAsStringSync();
              final arr = jsonDecode(content) as List;
              noteCount = arr.length;
              _noteBackupCountCache[cacheKey] = noteCount;
            } catch (_) {
              _noteBackupCountCache[cacheKey] = 0;
            }
          }
        }

        list.add({
          'path': f.path,
          'fileName': name,
          'size': size,
          'modified': mTime,
          'count': noteCount,
        });
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  /// 预览指定快照备份文件中的便签列表
  List<Note> previewNotesBackup(String backupFilePath) {
    try {
      final file = File(backupFilePath);
      if (!file.existsSync()) return [];
      final content = file.readAsStringSync();
      final decoded = jsonDecode(content) as List;
      return decoded
          .map((item) => Note.fromJson(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Failed to preview notes backup: $e');
      return [];
    }
  }

  /// 从指定的历史快照文件恢复便签 (支持指定目标工作区目录)
  Future<bool> restoreNotesFromBackup(String backupFilePath, {String? targetDir}) async {
    try {
      final file = File(backupFilePath);
      if (!file.existsSync()) return false;

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as List;
      final restored = decoded
          .map((item) => Note.fromJson(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (restored.isEmpty) return false;

      final currentDir = getDataDirectoryPathSync().replaceAll('\\', '/');
      final isCurrent = targetDir == null ||
          targetDir.replaceAll('\\', '/').toLowerCase() == currentDir.toLowerCase();

      if (isCurrent) {
        // 恢复前先给当前状态做一份保险快照
        await _createNotesBackup('before_restore');

        notes = restored;
        activeNote = notes.isNotEmpty ? notes.first : null;
        await _saveNotes();
        notifyListeners();
        _triggerD1LiveAutoSync();
      } else {
        // 目标是非当前激活工作区，写入其 targetDir/notes.json
        final targetNotesFile = File('$targetDir/notes.json');
        if (!targetNotesFile.parent.existsSync()) {
          targetNotesFile.parent.createSync(recursive: true);
        }
        await targetNotesFile.writeAsString(jsonEncode(restored.map((n) => n.toJson()).toList()));
      }
      return true;
    } catch (e) {
      debugPrint('Failed to restore notes: $e');
      return false;
    }
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
      unawaited(_createNotesBackup('auto_save'));
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

    if (notes.isEmpty) {
      final newNote = Note(
        id: _uuid.v4(),
        title: text('新建便签 1', 'New Note 1'),
        content: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      notes.add(newNote);
      activeNote = newNote;
    } else if (activeNote?.id == note.id) {
      activeNote = notes.first;
    }

    // 前台 0 毫秒立即刷新界面，磁盘写入与云端同步放到后台
    notifyListeners();
    unawaited(Future(() async {
      await _saveDeletedNotes();
      await _saveNotes();
      _triggerD1LiveAutoSync();
    }));
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

      // Debounce saving to disk (500ms + 1500ms = 停笔 2 秒静默上云)
      _notesSaveTimer?.cancel();
      _notesSaveTimer = Timer(const Duration(milliseconds: 500), () async {
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
