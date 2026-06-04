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
import 'package:dart_style/dart_style.dart';

import '../models/clipboard_item.dart';
import '../models/note.dart';
import '../models/app_settings.dart';

class AppState extends ChangeNotifier with WindowListener, TrayListener {
  static const _clipboardOwnerChannel = MethodChannel(
    'app.pod/clipboard_owner',
  );

  static const _menuBarScrollChannel = MethodChannel('app.pod/menu_bar_scroll');

  static const _focusManagerChannel = MethodChannel('app.pod/focus_manager');

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
  double lastCalculatedWidth = 800.0;
  double fileDisplaySize = 110.0;

  String _searchClipboardQuery = '';
  String _searchNotesQuery = '';

  String _lastSystemClipText = '';
  String _lastAppCopiedText = '';
  String? _lastSystemClipImageSignature;
  String? _lastAppCopiedImageSignature;
  bool _isCheckingClipboard = false;
  Timer? _clipboardTimer;
  Timer? _notesSaveTimer;
  Timer? _autoCollapseTimer;
  Timer? _fileWatchDebounce;

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
  Display? _currentDisplay;
  Map<String, double>? _nativeScreenInfo;
  DateTime _lastScrollAction = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastExpandedScreenX = -1;
  final Map<String, String> _itemTypeCache = {};

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

  String _stripMarkdownBlock(String text) {
    var trimmed = text.trim();
    final regExp = RegExp(r'^```[a-zA-Z0-9_-]*\s*\n?([\s\S]*?)\n?```$', multiLine: true);
    final match = regExp.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)?.trim() ?? trimmed;
    }
    return trimmed;
  }

  dynamic _decodeLooseJson(String jsonStr) {
    var s = jsonStr.trim();
    // 1. Replace single quotes wrapping keys/values with double quotes
    s = s.replaceAllMapped(RegExp(r"'([^'\\]*(?:\\.[^'\\]*)*)'"), (match) {
      final content = match.group(1) ?? '';
      final safeContent = content.replaceAll('"', '\\"');
      return '"$safeContent"';
    });
    // 2. Add double quotes to unquoted keys, e.g. {a: 1} -> {"a": 1}
    s = s.replaceAllMapped(RegExp(r'([{\s,])([a-zA-Z_$.][a-zA-Z0-9_$.]*)\s*:'), (match) {
      final prefix = match.group(1) ?? '';
      final key = match.group(2) ?? '';
      return '$prefix"$key":';
    });
    // 3. Remove trailing commas, e.g. {"a": 1,} -> {"a": 1}
    s = s.replaceAll(RegExp(r',\s*}'), '}');
    s = s.replaceAll(RegExp(r',\s*]'), ']');
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  String? tryFormatJson(String text) {
    var trimmed = text.trim();
    trimmed = _stripMarkdownBlock(trimmed);
    if (trimmed.endsWith(';')) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trim();
    }
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final parsed = jsonDecode(trimmed);
        final encoder = const JsonEncoder.withIndent('  ');
        return encoder.convert(parsed);
      } catch (_) {
        // Fallback to loose decode for standard-wrapped text
      }
    }

    // Attempt to extract the JSON payload, e.g. "const data = { ... };"
    int firstBrace = trimmed.indexOf('{');
    int firstBracket = trimmed.indexOf('[');
    int startIdx = -1;
    int endIdx = -1;
    if (firstBrace != -1 && (firstBracket == -1 || firstBrace < firstBracket)) {
      startIdx = firstBrace;
      endIdx = trimmed.lastIndexOf('}');
    } else if (firstBracket != -1) {
      startIdx = firstBracket;
      endIdx = trimmed.lastIndexOf(']');
    }

    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      final substring = trimmed.substring(startIdx, endIdx + 1);
      try {
        final parsed = jsonDecode(substring);
        final encoder = const JsonEncoder.withIndent('  ');
        return encoder.convert(parsed);
      } catch (_) {
        try {
          final looseDecoded = _decodeLooseJson(substring);
          if (looseDecoded != null) {
            final encoder = const JsonEncoder.withIndent('  ');
            return encoder.convert(looseDecoded);
          }
        } catch (_) {}
      }
    }
    return null;
  }

  String? tryFormatXml(String text) {
    var trimmed = text.trim();
    trimmed = _stripMarkdownBlock(trimmed);
    int firstAngle = trimmed.indexOf('<');
    int lastAngle = trimmed.lastIndexOf('>');
    if (firstAngle != -1 && lastAngle != -1 && lastAngle > firstAngle) {
      final substring = trimmed.substring(firstAngle, lastAngle + 1);
      if (!substring.contains('</') && !substring.contains('/>')) return null;
      try {
        return _formatXmlString(substring);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String? tryFormatCode(String text) {
    var trimmed = text.trim();
    trimmed = _stripMarkdownBlock(trimmed);
    
    final openBraceCount = '{'.allMatches(trimmed).length;
    final closeBraceCount = '}'.allMatches(trimmed).length;
    
    // Check if braces are balanced and there are multiple lines with code traits
    if (openBraceCount >= 1 && openBraceCount == closeBraceCount && '\n'.allMatches(trimmed).length >= 1) {
      final codeKeywords = RegExp(
        r'\b(class|void|import|final|const|var|return|public|private|function|def|if|for|while|static|fn|let|package|using|namespace)\b|=>|;',
      );
      if (codeKeywords.hasMatch(trimmed)) {
        return _formatCurlyBraceCode(trimmed);
      }
    }
    return null;
  }

  String _formatCurlyBraceCode(String code) {
    final lines = code.split('\n');
    final sb = StringBuffer();
    int indent = 0;
    
    for (var line in lines) {
      var cleanLine = line.trim();
      if (cleanLine.isEmpty) {
        sb.writeln();
        continue;
      }

      // Beautify spaces around common symbols (VS Code style cleanup)
      cleanLine = cleanLine.replaceAll(RegExp(r',(?!\s)'), ', ');
      cleanLine = cleanLine.replaceAllMapped(RegExp(r':(?!\s)(?!//)'), (m) => ': ');
      cleanLine = cleanLine.replaceAll(RegExp(r'(?<!\s){'), ' {');
      
      // Align lines starting with closing brackets or control blocks (else/catch/finally)
      final regex = RegExp(r'^([\}\]]|else\b|catch\b|finally\b)');
      bool isClosingOrControl = regex.hasMatch(cleanLine);
      int printIndent = isClosingOrControl ? (indent - 1).clamp(0, 100) : indent;
      
      sb.write('  ' * printIndent);
      sb.writeln(cleanLine);
      
      // Update persistent indentation
      int opens = '{'.allMatches(cleanLine).length;
      int closes = '}'.allMatches(cleanLine).length;
      indent += (opens - closes);
      if (indent < 0) indent = 0;
    }
    
    return sb.toString().trim();
  }

  String _formatXmlString(String xml) {
    final regExp = RegExp(r'(<[^>]+>)|([^<]+)');
    final matches = regExp.allMatches(xml);
    final sb = StringBuffer();
    int indent = 0;
    for (final match in matches) {
      final token = match.group(0)?.trim() ?? '';
      if (token.isEmpty) continue;
      if (token.startsWith('</')) {
        indent = (indent - 1).clamp(0, 100);
        sb.write('\n${'  ' * indent}$token');
      } else if (token.startsWith('<') && (token.endsWith('/>') || token.startsWith('<?') || token.startsWith('<!'))) {
        sb.write('\n${'  ' * indent}$token');
      } else if (token.startsWith('<')) {
        sb.write('\n${'  ' * indent}$token');
        indent++;
      } else {
        sb.write('\n${'  ' * indent}$token');
      }
    }
    return sb.toString().trim();
  }

  bool isUrl(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) return false;
    try {
      final uri = Uri.parse(trimmed);
      return uri.isAbsolute;
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

  String getClipboardItemType(ClipboardItem item) {
    final cached = _itemTypeCache[item.id];
    if (cached != null) return cached;

    String type = 'TEXT';
    if (item.imagePath != null) {
      type = 'IMAGE';
    } else {
      final text = item.content;
      if (isUrl(text)) {
        type = 'URL';
      } else if (tryFormatJson(text) != null) {
        type = 'JSON';
      } else if (tryFormatXml(text) != null) {
        type = 'XML';
      } else if (tryFormatCode(text) != null) {
        type = 'CODE';
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
      return List.from(clipboardHistory)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    final query = _searchClipboardQuery.toLowerCase();
    return clipboardHistory
        .where((item) =>
            item.content.toLowerCase().contains(query) ||
            (item.appName != null && item.appName!.toLowerCase().contains(query)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<ClipboardItem> get filteredClipboardFavorites {
    if (_searchClipboardQuery.isEmpty) {
      return List.from(clipboardFavorites)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    final query = _searchClipboardQuery.toLowerCase();
    return clipboardFavorites
        .where((item) =>
            item.content.toLowerCase().contains(query) ||
            (item.appName != null && item.appName!.toLowerCase().contains(query)))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<Note> get filteredNotes {
    if (_searchNotesQuery.isEmpty) {
      return List.from(notes)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    final query = _searchNotesQuery.toLowerCase();
    return notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(query) ||
              n.content.toLowerCase().contains(query),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
    await _loadClipboardHistory();
    await _loadNotes();
    await _scanStoredFiles();

    // Setup hooks
    await _setupTray();
    await _setupHotkeys();
    _startClipboardMonitoring();
    await _startWatchingImagesDirectory();
    await _startWatchingDataDirectory();

    // Background cleanup of orphaned images
    _cleanupUnusedClipboardImages();

    if (Platform.isMacOS || Platform.isWindows) {
      _menuBarScrollChannel.setMethodCallHandler((call) async {
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
      });
    }

    // Position window
    await windowManager.setMinimumSize(const Size(1, 1));
    await applyWindowTriggerConfiguration(isStartup: true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _clipboardTimer?.cancel();
    _notesSaveTimer?.cancel();
    _autoCollapseTimer?.cancel();
    _fileWatchDebounce?.cancel();
    _dirWatcher?.cancel();
    _imagesDirWatcher?.cancel();
    hotKeyManager.unregisterAll();
    super.dispose();
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
      final double wCollapsed = Platform.isMacOS ? screenWidth : w;
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
              await windowManager.setBounds(
                Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
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
            await windowManager.setBounds(
              Rect.fromLTWH(x, screenPosition.dy, wCollapsed, hCollapsed),
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

    try {
      final bool shouldFocus =
          focus || settings.triggerMode == TriggerMode.hotkeyOnly;

      // Set native window FIRST, then trigger animation
      if (Platform.isMacOS) {
        final info = _nativeScreenInfo;
        if (info != null) {
          final sw = info['width']!;
          double w = settings.isWidthPercentage
              ? sw * (settings.panelWidthPercent / 100.0)
              : settings.panelWidth;
          if (lastCalculatedWidth != w) {
            lastCalculatedWidth = w;
            notifyListeners(); // Ensure Flutter UI updates to the new width immediately
          }
          _lastExpandedScreenX = info['x']!;
          // Move window to correct screen position (cheap)
          _menuBarScrollChannel.invokeMethod('expandOnScreen', {
            'x': info['x']! + (sw - w) / 2,
            'y': info['visibleY']!,
            'width': w,
            'height': 350.0,
            'focus': shouldFocus,
          });
          // The native window is resized immediately without display block,
          // and animated natively via CoreAnimation in MainFlutterWindow.swift.
          // This avoids Flutter timeout issues entirely and gives 60fps animations.
        }
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
        await windowManager.setBounds(
          Rect.fromLTWH(targetX, screenY, w, 350),
        );
        await windowManager.setHasShadow(true);
        if (shouldFocus) {
          _focusManagerChannel.invokeMethod('savePreviousApp');
          await windowManager.show();
          await windowManager.focus();
        } else {
          await windowManager.show(inactive: true);
        }
      }

      // Now trigger animation AFTER native window is ready
      onAnimationStateChanged?.call(duration);
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

  Future<void> collapsePanel({
    Duration duration = const Duration(milliseconds: 280),
  }) async {
    if (!isExpanded || isAnimating) return;
    _autoCollapseTimer?.cancel();
    isAnimating = true;
    isExpanded = false;

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

    if (_didGrabFocus) {
      if (Platform.isMacOS) {
        _menuBarScrollChannel.invokeMethod('restorePreviousApp');
      } else {
        _focusManagerChannel.invokeMethod('restorePreviousApp');
      }
      _didGrabFocus = false;
    }

    if (Platform.isMacOS) {
      windowManager.setIgnoreMouseEvents(true);
    }
    onAnimationStateChanged?.call(duration);

    // Save notes in background to avoid blocking focus restore and UI
    forceSaveNotesIfPending();

    // We wait for the sliding animation to complete inside the UI before resizing the native window.
    // The UI calls AppState.onCollapseAnimationFinished() to finalize this.
  }

  Future<void> onCollapseAnimationFinished() async {
    isAnimating = false;
    _currentDisplay = null;
    _nativeScreenInfo = null;

    if (!Platform.isMacOS) {
      try {
        final display = await _getCurrentDisplay();
        final screenWidth = display.size.width;
        final position = display.visiblePosition ?? Offset.zero;
        final x = position.dx + (screenWidth - lastCalculatedWidth) / 2;
        await windowManager.setBounds(
          Rect.fromLTWH(x, position.dy, lastCalculatedWidth, 3),
        );
        await windowManager.setIgnoreMouseEvents(false);
      } catch (e) {
        debugPrint('Failed to resize collapsed window: $e');
      }
    }
  }

  void cancelCollapseAndExpand() {
    if (!isExpanded) {
      isExpanded = true;
      isAnimating = false;
      onAnimationStateChanged?.call(const Duration(milliseconds: 250));
    }
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
    if (isDialogOpen || isMouseInside) return;
    final delay = settings.autoCollapseDelay;
    if (delay <= 0) return;
    if (!isExpanded || isAnimating) return;
    _autoCollapseTimer = Timer(Duration(seconds: delay), () {
      if (isExpanded && !isAnimating) {
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
    settings = newSettings;
    await _prefs.setString('settings', jsonEncode(settings.toJson()));

    // Reconfigure hooks & window positions
    await _setupHotkeys();
    await applyWindowTriggerConfiguration();

    if (oldPath != newSettings.customFilesPath) {
      await _scanStoredFiles();
    }
    notifyListeners();
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
    if (menuItem.key == 'toggle') {
      togglePanel();
    } else if (menuItem.key == 'quit') {
      windowManager.destroy();
    }
  }

  String _defaultDataDirSync = '';
  String get defaultDataDirectoryPath => _defaultDataDirSync;

  String getDataDirectoryPathSync() {
    if (settings.dataDirectory != null && settings.dataDirectory!.trim().isNotEmpty) {
      return settings.dataDirectory!.trim().replaceAll('\\', '/');
    }
    return _defaultDataDirSync;
  }

  Future<String> getDataDirectoryPath() async {
    return getDataDirectoryPathSync();
  }

  Future<String> _getDefaultDataDirectoryPath() async {
    final appSupport = await getApplicationSupportDirectory();
    return '${appSupport.path}/data'.replaceAll('\\', '/');
  }

  String _getCleanDeviceName() {
    try {
      final rawName = Platform.localHostname;
      return rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    } catch (_) {
      return 'default';
    }
  }

  String _getClipboardHistoryFilename() {
    return 'clipboard_history-${_getCleanDeviceName()}.json';
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
      if (!dataDirObj.existsSync()) {
        dataDirObj.createSync(recursive: true);
      }

      // 1. Migrate clipboard images if old dir exists and new dir doesn't exist
      final oldImagesDir = Directory('${appSupport.path}/clipboard_images');
      final newImagesDir = Directory('$dataDir/clipboard_images');
      if (oldImagesDir.existsSync() && !newImagesDir.existsSync() && oldImagesDir.path != newImagesDir.path) {
        newImagesDir.createSync(recursive: true);
        for (final entity in oldImagesDir.listSync()) {
          if (entity is File) {
            final name = entity.path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;
            final newPath = '${newImagesDir.path}/$name';
            entity.copySync(newPath);
          }
        }
        try {
          oldImagesDir.deleteSync(recursive: true);
        } catch (_) {}
      }

      // 2. Migrate files if old default files dir exists and new files dir doesn't exist
      final oldDefaultFilesPath = _getOldDefaultFilesPath();
      final oldFilesDir = oldDefaultFilesPath.isNotEmpty ? Directory(oldDefaultFilesPath) : null;
      final newFilesDir = Directory('$dataDir/files');
      if (oldFilesDir != null && oldFilesDir.existsSync() && !newFilesDir.existsSync() && oldFilesDir.path != newFilesDir.path) {
        newFilesDir.createSync(recursive: true);
        await _copyDirectory(oldFilesDir, newFilesDir);
        try {
          oldFilesDir.deleteSync(recursive: true);
        } catch (_) {}
      }

      // 3. Migrate custom files path if set in AppSettings
      if (settings.customFilesPath != null && settings.customFilesPath!.trim().isNotEmpty) {
        final oldCustomDir = Directory(settings.customFilesPath!.trim());
        if (oldCustomDir.existsSync() && oldCustomDir.path != newFilesDir.path) {
          newFilesDir.createSync(recursive: true);
          await _copyDirectory(oldCustomDir, newFilesDir);
          final updated = settings.copyWith(customFilesPath: '');
          await updateSettings(updated);
          try {
            oldCustomDir.deleteSync(recursive: true);
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
    if (!destination.existsSync()) {
      destination.createSync(recursive: true);
    }
    await for (var entity in source.list(recursive: false)) {
      final name = entity.path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;
      if (entity is Directory) {
        final newDirectory = Directory('${destination.path}/$name');
        newDirectory.createSync(recursive: true);
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        entity.copySync('${destination.path}/$name');
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
                (name.startsWith('clipboard_history-') && name.endsWith('.json'))) {
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
            final name = entity.path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;
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
                (name.startsWith('clipboard_history-') && name.endsWith('.json'))) {
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
            targetNotes = jsonDecode(targetNotesFile.readAsStringSync()) as List;
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
      final historyFilename = _getClipboardHistoryFilename();
      final sourceHistoryFile = File('${sourceDir.path}/$historyFilename');
      if (sourceHistoryFile.existsSync()) {
        final targetHistoryFile = File('${targetDir.path}/$historyFilename');
        List<dynamic> mergedHistoryJson = [];

        List<dynamic> sourceHistory = [];
        try {
          sourceHistory = jsonDecode(sourceHistoryFile.readAsStringSync()) as List;
        } catch (_) {}

        if (targetHistoryFile.existsSync()) {
          List<dynamic> targetHistory = [];
          try {
            targetHistory = jsonDecode(targetHistoryFile.readAsStringSync()) as List;
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
      final sourceFavoritesFile = File('${sourceDir.path}/clipboard_favorites.json');
      if (sourceFavoritesFile.existsSync()) {
        final targetFavoritesFile = File('${targetDir.path}/clipboard_favorites.json');
        List<dynamic> mergedFavoritesJson = [];

        List<dynamic> sourceFavorites = [];
        try {
          sourceFavorites = jsonDecode(sourceFavoritesFile.readAsStringSync()) as List;
        } catch (_) {}

        if (targetFavoritesFile.existsSync()) {
          List<dynamic> targetFavorites = [];
          try {
            targetFavorites = jsonDecode(targetFavoritesFile.readAsStringSync()) as List;
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
            final name = entity.path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).last;
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

  void _startClipboardMonitoring() {
    _clipboardTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isCheckingClipboard) return;
      _isCheckingClipboard = true;
      try {
        // 1. 先检查文本，因为绝大多数情况下剪贴板中都是文本，且 Clipboard.getData 极轻量
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data != null && data.text != null && data.text!.isNotEmpty) {
          final text = data.text!;
          if (text != _lastSystemClipText) {
            _lastSystemClipText = text;
            _lastSystemClipImageSignature = null; // 切换到文本时，清空图片特征缓存，确保下次可以重新识别相同图片
            
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
              final imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'tiff', 'tif', 'heic', 'heif'};
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
                final isInternalCopy = isOwn && (imageSignature == _lastAppCopiedImageSignature);

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

    // Limit size
    if (clipboardHistory.length > 50) {
      final removed = clipboardHistory.removeLast();
      if (removed.imagePath != null) {
        try {
          final f = File(getImagePath(removed));
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }

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

      // 限制大小
      if (clipboardHistory.length > 50) {
        final removed = clipboardHistory.removeLast();
        if (removed.imagePath != null) {
          try {
            final f = File(getImagePath(removed));
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
      }

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
      final stillHasReference = clipboardHistory.any((x) => getImagePath(x) == path) ||
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
        final inFavorites = clipboardFavorites.any((x) => getImagePath(x) == path);
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

    // 1. History
    final historyFilename = _getClipboardHistoryFilename();
    final historyFile = File('$dataDir/$historyFilename');
    String? listJson;
    if (historyFile.existsSync()) {
      try {
        listJson = historyFile.readAsStringSync();
      } catch (e) {
        debugPrint('Failed to read clipboard history file: $e');
      }
    } else {
      // Check if legacy device-agnostic history file exists to migrate
      final legacyFile = File('$dataDir/clipboard_history.json');
      if (legacyFile.existsSync()) {
        try {
          listJson = legacyFile.readAsStringSync();
          // Write it to device-specific file so we don't lose history on this machine
          historyFile.writeAsStringSync(listJson);
        } catch (_) {}
      } else {
        // Legacy migration from SharedPreferences
        listJson = _prefs.getString('clipboard_history');
        if (listJson != null) {
          try {
            if (!historyFile.parent.existsSync()) {
              historyFile.parent.createSync(recursive: true);
            }
            historyFile.writeAsStringSync(listJson);
            await _prefs.remove('clipboard_history');
          } catch (e) {
            debugPrint('Failed to migrate clipboard history from SharedPreferences: $e');
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
            .toList();
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
    if (favoritesFile.existsSync()) {
      try {
        favJson = favoritesFile.readAsStringSync();
      } catch (e) {
        debugPrint('Failed to read clipboard favorites file: $e');
      }
    } else {
      // Legacy migration from SharedPreferences
      favJson = _prefs.getString('clipboard_favorites');
      if (favJson != null) {
        try {
          if (!favoritesFile.parent.existsSync()) {
            favoritesFile.parent.createSync(recursive: true);
          }
          favoritesFile.writeAsStringSync(favJson);
          await _prefs.remove('clipboard_favorites');
        } catch (e) {
          debugPrint('Failed to migrate clipboard favorites from SharedPreferences: $e');
        }
      }
    }

    if (favJson != null) {
      _lastFavoritesJsonCache = favJson;
      try {
        final decoded = jsonDecode(favJson) as List;
        clipboardFavorites = decoded
            .map((item) => ClipboardItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (e) {
        clipboardFavorites = [];
      }
    } else {
      clipboardFavorites = [];
      _lastFavoritesJsonCache = null;
    }

    bool needsSaveHistory = false;
    final originalHistoryCount = clipboardHistory.length;
    clipboardHistory = clipboardHistory.where((item) {
      if (item.imagePath != null) {
        final file = File(getImagePath(item));
        return file.existsSync();
      }
      return true;
    }).toList();
    if (clipboardHistory.length != originalHistoryCount) {
      needsSaveHistory = true;
    }

    bool needsSaveFavorites = false;
    final originalFavCount = clipboardFavorites.length;
    clipboardFavorites = clipboardFavorites.where((item) {
      if (item.imagePath != null) {
        final file = File(getImagePath(item));
        return file.existsSync();
      }
      return true;
    }).toList();
    if (clipboardFavorites.length != originalFavCount) {
      needsSaveFavorites = true;
    }

    if (needsSaveHistory) {
      _saveClipboardHistory();
    }
    if (needsSaveFavorites) {
      _saveClipboardFavorites();
    }
  }

  Future<void> _saveClipboardHistory() async {
    final dataDir = getDataDirectoryPathSync();
    final historyFilename = _getClipboardHistoryFilename();
    final historyFile = File('$dataDir/$historyFilename');
    try {
      if (!historyFile.parent.existsSync()) {
        historyFile.parent.createSync(recursive: true);
      }
      final encoded = jsonEncode(
        clipboardHistory.map((item) => item.toJson()).toList(),
      );
      _lastHistoryJsonCache = encoded;
      historyFile.writeAsStringSync(encoded);
    } catch (e) {
      debugPrint('Failed to save clipboard history file: $e');
    }
  }

  Future<void> _saveClipboardFavorites() async {
    final dataDir = getDataDirectoryPathSync();
    final favoritesFile = File('$dataDir/clipboard_favorites.json');
    try {
      if (!favoritesFile.parent.existsSync()) {
        favoritesFile.parent.createSync(recursive: true);
      }
      final encoded = jsonEncode(
        clipboardFavorites.map((item) => item.toJson()).toList(),
      );
      _lastFavoritesJsonCache = encoded;
      favoritesFile.writeAsStringSync(encoded);
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
    clipboardHistory.removeWhere((item) => item.imagePath != null && item.imagePath!.replaceAll('\\', '/').endsWith(targetPathPart));
    if (clipboardHistory.length != historyLen) {
      changed = true;
    }
    
    // 检查收藏记录
    final favLen = clipboardFavorites.length;
    clipboardFavorites.removeWhere((item) => item.imagePath != null && item.imagePath!.replaceAll('\\', '/').endsWith(targetPathPart));
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
      _imagesDirWatcher = dir.watch(events: FileSystemEvent.all).listen((event) {
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
          } else if (fileName == historyFilename || fileName == 'clipboard_favorites.json') {
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
      if (content == _lastNotesJsonCache) return; // Ignore if identical (self-write)
      _lastNotesJsonCache = content;

      final decoded = jsonDecode(content) as List;
      notes = decoded
          .map((item) => Note.fromJson(item as Map<String, dynamic>))
          .toList();

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
              .map((item) => ClipboardItem.fromJson(item as Map<String, dynamic>))
              .toList();
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
              .map((item) => ClipboardItem.fromJson(item as Map<String, dynamic>))
              .toList();
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

  Future<void> openFile(FileSystemEntity entity) async {
    try {
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
        await Process.run('open', [path]);
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

    if (notesFile.existsSync()) {
      try {
        notesJson = notesFile.readAsStringSync();
      } catch (e) {
        debugPrint('Failed to read notes file: $e');
      }
    } else {
      // Legacy migration from SharedPreferences
      notesJson = _prefs.getString('notes');
      if (notesJson != null) {
        try {
          if (!notesFile.parent.existsSync()) {
            notesFile.parent.createSync(recursive: true);
          }
          notesFile.writeAsStringSync(notesJson);
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
            .toList();
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
      if (!notesFile.parent.existsSync()) {
        notesFile.parent.createSync(recursive: true);
      }
      final encoded = jsonEncode(notes.map((item) => item.toJson()).toList());
      _lastNotesJsonCache = encoded; // Populate cache on save
      notesFile.writeAsStringSync(encoded);
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
      notes[idx] = updated;
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
      notes[idx] = updated;
      activeNote = updated;

      await _saveNotes();
      notifyListeners();
    }
  }
}
