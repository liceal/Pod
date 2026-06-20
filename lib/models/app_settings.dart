import 'dart:ui';

enum TriggerMode { both, hotkeyOnly, hoverOnly, scrollOnly }

enum PanelPane { clipboard, files, notes }

class AppSettings {
  static const int defaultClipboardHistoryLimit = 50;
  static const int minClipboardHistoryLimit = 10;
  static const int maxClipboardHistoryLimit = 500;
  static const double defaultTextContentFontSize = 12.0;
  static const double minTextContentFontSize = 11.0;
  static const double maxTextContentFontSize = 22.0;
  static const int defaultAutoCollapseDelay = 0;
  static const int maxAutoCollapseDelay = 30;
  static const String defaultLanguageCode = 'zh';
  static const List<String> supportedLanguageCodes = ['system', 'zh', 'en'];
  static const List<PanelPane> defaultPanelOrder = [
    PanelPane.clipboard,
    PanelPane.notes,
    PanelPane.files,
  ];

  final TriggerMode triggerMode;
  final String hotkey; // e.g., "alt+u"
  final bool isDarkTheme;
  final int hoverTimeoutMs; // Delay before hover triggers slide-down
  final double panelWidth;
  final bool isWidthPercentage;
  final double panelWidthPercent;
  final String? _themeColorName;
  final bool? _closeOnBlur;

  /// Seconds to wait after mouse leaves before auto-collapsing.
  /// 0 = immediate when triggered, [maxAutoCollapseDelay] = disabled.
  final int autoCollapseDelay;
  final String? customFilesPath;
  final String? dataDirectory; // Unified data storage location
  final double backdropOpacity;
  final int clipboardHistoryLimit;
  final List<PanelPane> panelOrder;
  final Map<PanelPane, double> panelWeights;
  final double textContentFontSize;
  final String languageCode;
  final bool launchAtStartup;

  String get themeColorName => _themeColorName ?? 'blue';
  bool get closeOnBlur => _closeOnBlur ?? false;
  Locale? get locale {
    return switch (languageCode) {
      'zh' => const Locale('zh', 'CN'),
      'en' => const Locale('en', 'US'),
      _ => null,
    };
  }

  AppSettings({
    this.triggerMode = TriggerMode.both,
    this.hotkey = 'alt+u',
    this.isDarkTheme = true,
    this.hoverTimeoutMs = 300,
    this.panelWidth = 900.0,
    this.isWidthPercentage = true,
    this.panelWidthPercent = 100.0,
    String? themeColorName = 'blue',
    bool? closeOnBlur = false,
    int autoCollapseDelay = defaultAutoCollapseDelay,
    this.customFilesPath,
    this.dataDirectory,
    this.backdropOpacity = 0.92,
    int clipboardHistoryLimit = defaultClipboardHistoryLimit,
    List<PanelPane>? panelOrder,
    Map<PanelPane, double>? panelWeights,
    double? textContentFontSize,
    String? languageCode,
    this.launchAtStartup = false,
  }) : _themeColorName = themeColorName,
       _closeOnBlur = closeOnBlur,
       clipboardHistoryLimit = normalizeClipboardHistoryLimit(
         clipboardHistoryLimit,
       ),
       autoCollapseDelay = normalizeAutoCollapseDelay(autoCollapseDelay),
       panelOrder = normalizePanelOrder(panelOrder),
       panelWeights = normalizePanelWeights(panelWeights),
       textContentFontSize = normalizeTextContentFontSize(textContentFontSize),
       languageCode = normalizeLanguageCode(languageCode);

  static int normalizeClipboardHistoryLimit(int? value) {
    return (value ?? defaultClipboardHistoryLimit)
        .clamp(minClipboardHistoryLimit, maxClipboardHistoryLimit)
        .toInt();
  }

  static double normalizeTextContentFontSize(double? value) {
    return (value ?? defaultTextContentFontSize)
        .clamp(minTextContentFontSize, maxTextContentFontSize)
        .toDouble();
  }

  static int normalizeAutoCollapseDelay(int? value) {
    return (value ?? defaultAutoCollapseDelay)
        .clamp(0, maxAutoCollapseDelay)
        .toInt();
  }

  static String normalizeLanguageCode(String? value) {
    if (value == null || !supportedLanguageCodes.contains(value)) {
      return defaultLanguageCode;
    }
    return value;
  }

  static List<PanelPane> normalizePanelOrder(List<PanelPane>? value) {
    final result = <PanelPane>[];
    for (final pane in value ?? defaultPanelOrder) {
      if (!result.contains(pane)) {
        result.add(pane);
      }
    }
    for (final pane in defaultPanelOrder) {
      if (!result.contains(pane)) {
        result.add(pane);
      }
    }
    return List.unmodifiable(result);
  }

  static Map<PanelPane, double> normalizePanelWeights(
    Map<PanelPane, double>? value,
  ) {
    final result = <PanelPane, double>{
      PanelPane.clipboard: 1.0,
      PanelPane.files: 1.0,
      PanelPane.notes: 1.0,
    };
    if (value != null) {
      value.forEach((k, v) {
        if (result.containsKey(k)) {
          result[k] = v;
        }
      });
    }
    return Map.unmodifiable(result);
  }

  AppSettings copyWith({
    TriggerMode? triggerMode,
    String? hotkey,
    bool? isDarkTheme,
    int? hoverTimeoutMs,
    double? panelWidth,
    bool? isWidthPercentage,
    double? panelWidthPercent,
    String? themeColorName,
    bool? closeOnBlur,
    int? autoCollapseDelay,
    String? customFilesPath,
    String? dataDirectory,
    double? backdropOpacity,
    int? clipboardHistoryLimit,
    List<PanelPane>? panelOrder,
    Map<PanelPane, double>? panelWeights,
    double? textContentFontSize,
    String? languageCode,
    bool? launchAtStartup,
  }) {
    return AppSettings(
      triggerMode: triggerMode ?? this.triggerMode,
      hotkey: hotkey ?? this.hotkey,
      isDarkTheme: isDarkTheme ?? this.isDarkTheme,
      hoverTimeoutMs: hoverTimeoutMs ?? this.hoverTimeoutMs,
      panelWidth: panelWidth ?? this.panelWidth,
      isWidthPercentage: isWidthPercentage ?? this.isWidthPercentage,
      panelWidthPercent: panelWidthPercent ?? this.panelWidthPercent,
      themeColorName: themeColorName ?? this.themeColorName,
      closeOnBlur: closeOnBlur ?? this.closeOnBlur,
      autoCollapseDelay: autoCollapseDelay ?? this.autoCollapseDelay,
      customFilesPath: customFilesPath ?? this.customFilesPath,
      dataDirectory: dataDirectory ?? this.dataDirectory,
      backdropOpacity: backdropOpacity ?? this.backdropOpacity,
      clipboardHistoryLimit:
          clipboardHistoryLimit ?? this.clipboardHistoryLimit,
      panelOrder: panelOrder ?? this.panelOrder,
      panelWeights: panelWeights ?? this.panelWeights,
      textContentFontSize: textContentFontSize ?? this.textContentFontSize,
      languageCode: languageCode ?? this.languageCode,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'triggerMode': triggerMode.name,
      'hotkey': hotkey,
      'isDarkTheme': isDarkTheme,
      'hoverTimeoutMs': hoverTimeoutMs,
      'panelWidth': panelWidth,
      'isWidthPercentage': isWidthPercentage,
      'panelWidthPercent': panelWidthPercent,
      'themeColorName': themeColorName,
      'closeOnBlur': closeOnBlur,
      'autoCollapseDelay': autoCollapseDelay,
      'customFilesPath': customFilesPath,
      'dataDirectory': dataDirectory,
      'backdropOpacity': backdropOpacity,
      'clipboardHistoryLimit': clipboardHistoryLimit,
      'panelOrder': panelOrder.map((pane) => pane.name).toList(),
      'panelWeights': panelWeights.map((pane, w) => MapEntry(pane.name, w)),
      'textContentFontSize': textContentFontSize,
      'languageCode': languageCode,
      'launchAtStartup': launchAtStartup,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    TriggerMode parseTriggerMode(String? name) {
      if (name == null) return TriggerMode.both;
      return TriggerMode.values.firstWhere(
        (e) => e.name == name,
        orElse: () => TriggerMode.both,
      );
    }

    List<PanelPane> parsePanelOrder(Object? value) {
      if (value is! List) {
        return defaultPanelOrder;
      }
      final panes = value
          .whereType<String>()
          .map(
            (name) => PanelPane.values.cast<PanelPane?>().firstWhere(
              (pane) => pane?.name == name,
              orElse: () => null,
            ),
          )
          .whereType<PanelPane>()
          .toList();
      return normalizePanelOrder(panes);
    }

    Map<PanelPane, double> parsePanelWeights(Object? value) {
      final result = <PanelPane, double>{
        PanelPane.clipboard: 1.0,
        PanelPane.files: 1.0,
        PanelPane.notes: 1.0,
      };
      if (value is Map) {
        value.forEach((k, v) {
          final pane = PanelPane.values.cast<PanelPane?>().firstWhere(
            (p) => p?.name == k,
            orElse: () => null,
          );
          if (pane != null && v is num) {
            result[pane] = v.toDouble();
          }
        });
      }
      return result;
    }

    return AppSettings(
      triggerMode: parseTriggerMode(json['triggerMode'] as String?),
      hotkey: json['hotkey'] as String? ?? 'alt+u',
      isDarkTheme: json['isDarkTheme'] as bool? ?? true,
      hoverTimeoutMs: json['hoverTimeoutMs'] as int? ?? 300,
      panelWidth: (json['panelWidth'] as num?)?.toDouble() ?? 900.0,
      isWidthPercentage: json['isWidthPercentage'] as bool? ?? true,
      panelWidthPercent:
          (json['panelWidthPercent'] as num?)?.toDouble() ?? 100.0,
      themeColorName: json['themeColorName'] as String?,
      closeOnBlur: json['closeOnBlur'] as bool? ?? false,
      autoCollapseDelay:
          (json['autoCollapseDelay'] as num?)?.toInt() ??
          defaultAutoCollapseDelay,
      customFilesPath: json['customFilesPath'] as String?,
      dataDirectory: json['dataDirectory'] as String?,
      backdropOpacity: (json['backdropOpacity'] as num?)?.toDouble() ?? 0.92,
      clipboardHistoryLimit: normalizeClipboardHistoryLimit(
        (json['clipboardHistoryLimit'] as num?)?.toInt(),
      ),
      panelOrder: parsePanelOrder(json['panelOrder']),
      panelWeights: parsePanelWeights(json['panelWeights']),
      textContentFontSize:
          (json['textContentFontSize'] as num?)?.toDouble() ??
          (json['noteEditorFontSize'] as num?)?.toDouble(),
      languageCode: json['languageCode'] as String?,
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
    );
  }
}
