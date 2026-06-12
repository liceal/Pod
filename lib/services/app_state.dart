import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

import '../models/clipboard_item.dart';
import '../models/note.dart';
import '../models/app_settings.dart';

class AppState extends ChangeNotifier with WindowListener, TrayListener {
  static const _clipboardOwnerChannel = MethodChannel(
    'app.pod/clipboard_owner',
  );

  static const _menuBarScrollChannel = MethodChannel('app.pod/menu_bar_scroll');

  static const _focusManagerChannel = MethodChannel('app.pod/focus_manager');

  static const _macFileOpenerChannel = MethodChannel('app.pod/file_opener');

  // Singleton
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  final _uuid = const Uuid();
  final navigatorKey = GlobalKey<NavigatorState>();
  late SharedPreferences _prefs;

  // State Variables
  AppSettings settings = AppSettings();
  List<ClipboardItem> clipboardHistory = [];
  List<ClipboardItem> clipboardFavorites = [];
  List<FileSystemEntity> storedFiles = [];
  List<Note> notes = [];
  Note? activeNote;

  bool isExpanded = false;
  bool isAnimating = false;
  bool isDialogOpen = false;
  bool isMouseInside = false;
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
  int? _lastNativeClipboardSequence;
  bool _nativeClipboardSequenceUnavailable = false;
  Timer? _clipboardTimer;
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

  bool _didGrabFocus = false;
  bool _restoreFocusAfterCollapse = false;
  bool _isShuttingDown = false;
  Display? _currentDisplay;
  Map<String, double>? _nativeScreenInfo;
  DateTime _lastScrollAction = DateTime.fromMillisecondsSinceEpoch(0);
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
    if (trimmed.contains(' ') || trimmed.contains('\n') || trimmed.contains('\r')) {
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
      final match = RegExp(r'\d*\.?\d+').allMatches(input).map((m) => m.group(0)!).toList();
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
      final match = RegExp(r'\d*\.?\d+').allMatches(input).map((m) => m.group(0)!).toList();
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

  bool isItemFavorite(String content) {
    return clipboardFavorites.any((x) => x.content == content);
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

  // --- Initializer ---
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final appSupport = await getApplicationSupportDirectory();
    _defaultDataDirSync = '${appSupport.path}/data'.replaceAll('\\', '/');

    windowManager.addListener(this);
    trayManager.addListener(this);

    // Load Local Data
    _loadSettings();
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
    _clipboardTimer?.cancel();
    _notesSaveTimer?.cancel();
    _autoCollapseTimer?.cancel();
    _panelActivationRefreshTimer?.cancel();
    _fileWatchDebounce?.cancel();
    _settingsSaveDebounce?.cancel();
    _reloadNotesDebounce?.cancel();
    _reloadHistoryDebounce?.cancel();
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
      final double wCollapsed = screenWidth; // Both macOS and Windows collapsed strip span 100% screen width
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
              windowManager.setBounds(
                Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
              ).catchError((e) => debugPrint('Failed to set startup bounds: $e'));
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
            windowManager.setBounds(
              Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
            ).catchError((e) => debugPrint('Failed to set collapsed bounds: $e'));
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
        windowManager.setBounds(Rect.fromLTWH(targetX, screenY, w, 350)).catchError((e) {
          debugPrint('Failed to set expand bounds: $e');
        });
        await windowManager.setHasShadow(true);
        if (shouldFocus) {
          _focusManagerChannel.invokeMethod('savePreviousApp');
          await windowManager.show();
          await windowManager.focus();
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
        windowManager.setBounds(
          Rect.fromLTWH(x, position.dy, screenWidth, 3),
        ).catchError((e) => debugPrint('Failed to set collapsed bounds: $e'));
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
    notifyListeners();
  }

  void updateFileDisplaySize(double value) {
    fileDisplaySize = value;
    notifyListeners();
  }

  void startAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
    if (isDialogOpen || isMouseInside || _hasEditableTextFocus) return;
    final delay = settings.autoCollapseDelay;
    if (delay <= 0) return;
    if (!isExpanded || isAnimating) return;
    _autoCollapseTimer = Timer(Duration(seconds: delay), () {
      if (isExpanded &&
          !isAnimating &&
          !isDialogOpen &&
          !isMouseInside &&
          !_hasEditableTextFocus) {
        collapsePanel();
      }
    });
  }

  void cancelAutoCollapseTimer() {
    _autoCollapseTimer?.cancel();
  }

  bool get _hasEditableTextFocus {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;

    try {
      if (context.widget is EditableText) return true;

      var found = false;
      context.visitAncestorElements((element) {
        if (element.widget is EditableText) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    } catch (_) {
      return false;
    }
  }

  // --- Window Listeners ---
  @override
  void onWindowBlur() {
    // 失去焦点时启动自动收起计时器
    if (Platform.isMacOS) {
      startAutoCollapseTimer();
    }
    // User clicked away — don't restore focus when auto-collapsing later
    _didGrabFocus = false;
  }

  @override
  void onWindowFocus() {
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

    if (oldPath != newSettings.customFilesPath) {
      await _scanStoredFiles();
    }
    notifyListeners();
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
      MenuItem(key: 'toggle', label: '显示/隐藏 Pod'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出'),
    ];
    await trayManager.setContextMenu(Menu(items: menuItems));
    await trayManager.setToolTip('Pod 助手');
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

  Future<String?> _migrateClipboardHistoryFilenameIfNeeded(String dataDir) async {
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
    if (Platform.isWindows) {
      basePath = Platform.environment['USERPROFILE'] ?? '';
      basePath = '$basePath\\Documents\\Pod暂存';
    } else if (Platform.isMacOS) {
      basePath = Platform.environment['HOME'] ?? '';
      basePath = '$basePath/Documents/Pod暂存';
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
      return lowerName == exeName || lowerName == 'pod';
    } catch (_) {
      return appName.toLowerCase() == 'pod';
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
      return await _clipboardOwnerChannel.invokeMethod<int>(
        methodName,
      );
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
    if (sequence == null) return false;

    final previousSequence = _lastNativeClipboardSequence;
    _lastNativeClipboardSequence = sequence;
    return previousSequence != null && previousSequence == sequence;
  }

  void _startClipboardMonitoring() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isShuttingDown) return;
      if (_isCheckingClipboard) return;
      _isCheckingClipboard = true;
      try {
        // Avoid touching large clipboard payloads unless content changed.
        if (await _shouldSkipUnchangedClipboard()) {
          return;
        }

        // 1. 先检查文本，因为绝大多数情况下剪贴板中都是文本，且 Clipboard.getData 极轻量
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data != null && data.text != null && data.text!.isNotEmpty) {
          final text = data.text!;
          if (text != _lastSystemClipText) {
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
              if (imageSignature != _lastSystemClipImageSignature) {
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
    });
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
        content: '[图片]',
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

    if (itemToDelete != null && itemToDelete.imagePath != null) {
      final path = getImagePath(itemToDelete);
      final stillHasReference =
          clipboardHistory.any((x) => getImagePath(x) == path) ||
          clipboardFavorites.any((x) => getImagePath(x) == path);
      if (!stillHasReference) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (e) {
          debugPrint('Failed to delete image file on item deletion: $e');
        }
      }
    }

    Future.delayed(Duration.zero, () {
      _saveClipboardHistory();
      _saveClipboardFavorites();
    });
    notifyListeners();
  }

  void toggleFavoriteClipboardItem(ClipboardItem item) {
    final isFav = isItemFavorite(item.content);
    if (isFav) {
      clipboardFavorites.removeWhere((x) => x.content == item.content);
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
        clipboardHistory = decoded
            .map((item) => ClipboardItem.fromJson(item as Map<String, dynamic>))
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
        clipboardFavorites = decoded
            .map((item) => ClipboardItem.fromJson(item as Map<String, dynamic>))
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
    final historyExistence = await Future.wait(clipboardHistory.map((item) async {
      if (item.imagePath != null) {
        return await File(getImagePath(item)).exists();
      }
      return true;
    }));
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
    final favExistence = await Future.wait(clipboardFavorites.map((item) async {
      if (item.imagePath != null) {
        return await File(getImagePath(item)).exists();
      }
      return true;
    }));
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

  DateTime _getFileTime(FileSystemEntity entity) {
    try {
      if (!entity.existsSync()) return DateTime(0);
      final stat = entity.statSync();
      // On Windows, stat.changed is creation time (birth time)
      return Platform.isWindows ? stat.changed : stat.modified;
    } catch (_) {
      return DateTime(0);
    }
  }

  Future<void> _scanStoredFiles() async {
    try {
      final path = await _getFilesDirectoryPath();
      final dir = Directory(path);
      if (!await dir.exists()) {
        storedFiles = [];
        _fileStatCache.clear();
        _isDirectoryCache.clear();
        notifyListeners();
        await _startWatchingFilesDirectory(path);
        return;
      }
      
      final List<FileSystemEntity> entities = [];
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File || entity is Directory) {
          entities.add(entity);
        }
      }

      // Fetch stats in parallel asynchronously to avoid sequential blocking
      final List<MapEntry<FileSystemEntity, DateTime>> entitiesWithTime = [];
      final Map<String, FileStat> newStats = {};
      final Map<String, bool> newDirs = {};

      await Future.wait(entities.map((entity) async {
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
      }));

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
      await _startWatchingFilesDirectory(path);
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
      notes = decoded
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
          clipboardHistory = decoded
              .map(
                (item) => ClipboardItem.fromJson(item as Map<String, dynamic>),
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
          clipboardFavorites = decoded
              .map(
                (item) => ClipboardItem.fromJson(item as Map<String, dynamic>),
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
      _dirWatcher = dir.watch(events: FileSystemEvent.all).listen((event) {
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
    _getFilesDirectoryPath().then((path) {
      try {
        final dir = Directory(path);
        storedFiles =
            dir
                .listSync()
                .where((entity) => entity is File || entity is Directory)
                .toList()
              ..sort((a, b) {
                final timeA = _getFileTime(a);
                final timeB = _getFileTime(b);
                return timeB.compareTo(timeA);
              });
        notifyListeners();
      } catch (_) {}
    });
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
          final dirName = srcDir.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last;
          final destDir = Directory('$destPath/$dirName');
          if (!destDir.existsSync()) {
            await destDir.create(recursive: true);
          }
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
            final fileName = srcFile.uri.pathSegments.last;
            final destFile = File('$destPath/$fileName');

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

  Future<void> deleteFile(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) {
        await entity.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to delete file: $e');
    }
    await _scanStoredFiles();
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

  Future<void> createNewFile(String name) async {
    try {
      final basePath = await _getFilesDirectoryPath();
      var fileName = name.trim().isEmpty ? '新建文件.txt' : name.trim();
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
      await _scanStoredFiles();
    } catch (e) {
      debugPrint('Failed to create new file: $e');
    }
  }

  Future<void> createNewDirectory(String name) async {
    try {
      final basePath = await _getFilesDirectoryPath();
      var dirName = name.trim().isEmpty ? '新建文件夹' : name.trim();
      var dir = Directory('$basePath/$dirName');

      // Handle duplicates by adding suffix
      int counter = 2;
      while (dir.existsSync()) {
        dir = Directory('$basePath/$dirName ($counter)');
        counter++;
      }

      await dir.create();
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

        if (source is File) {
          await source.rename(targetPath);
        } else if (source is Directory) {
          await source.rename(targetPath);
        }
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

  Future<void> _loadNotes() async {
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
        notes = decoded
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
        title: '我的便签',
        content: '欢迎使用快捷便签！在这里您可以随手记录任何内容，它会自动帮您保存...',
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
      title: '新建便签 ${notes.length + 1}',
      content: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    notes.insert(0, newNote);
    activeNote = newNote;
    await _saveNotes();
    notifyListeners();
  }

  Future<void> deleteNote(Note note) async {
    _notesSaveTimer?.cancel();
    notes.removeWhere((n) => n.id == note.id);

    if (notes.isEmpty) {
      activeNote = null;
      await createNote(); // Create a new empty note so there's always one
    } else if (activeNote?.id == note.id) {
      activeNote = notes.first;
    }

    await _saveNotes();
    notifyListeners();
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
      });
    }
  }

  Future<void> updateActiveNoteTitle(String title) async {
    if (activeNote == null) return;
    _notesSaveTimer?.cancel();

    final idx = notes.indexWhere((n) => n.id == activeNote!.id);
    if (idx != -1) {
      final updated = activeNote!.copyWith(
        title: title.isEmpty ? '无标题便签' : title,
        updatedAt: DateTime.now(),
      );
      notes.removeAt(idx);
      notes.insert(0, updated);
      activeNote = updated;

      await _saveNotes();
      notifyListeners();
    }
  }
}
