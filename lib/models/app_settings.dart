import 'dart:ui';

enum TriggerMode { both, hotkeyOnly, hoverOnly, scrollOnly }

enum PanelPane { clipboard, files, notes }

const Object _sentinel = Object();

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
  final bool invertScrollDirection; // Reverse scroll wake direction (scroll down collapses, scroll up expands)
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

  // Cloudflare R2 Data Synchronization Settings
  final bool r2Enabled;
  final String? r2AccountId;
  final String? r2AccessKeyId;
  final String? r2SecretAccessKey;
  final String? r2BucketName;
  final String? r2CustomEndpoint;
  final bool r2AutoSync;
  final int r2SyncIntervalMinutes;
  final int? r2LastSyncTime;

  // Cloudflare D1 + R2 Sync Settings
  final String cfWorkerUrl;
  final int cfD1Mode; // 0 = Worker API, 1 = Direct Cloudflare REST API
  final String? cfAccountId;
  final String? cfApiToken;
  final String? cfD1DatabaseId;
  final String? cfR2BucketName;
  final bool cfD1AutoSync;
  final int cfD1SyncIntervalMinutes;

  // Workspace & Vault ID
  final String? activeWorkspaceId;
  final String? vaultId;

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
    this.invertScrollDirection = false,
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
    this.r2Enabled = false,
    this.r2AccountId,
    this.r2AccessKeyId,
    this.r2SecretAccessKey,
    this.r2BucketName,
    this.r2CustomEndpoint,
    this.r2AutoSync = true,
    this.r2SyncIntervalMinutes = 5,
    this.r2LastSyncTime,
    this.cfWorkerUrl = '',
    this.cfD1Mode = 0,
    this.cfAccountId,
    this.cfApiToken,
    this.cfD1DatabaseId,
    this.cfR2BucketName,
    this.cfD1AutoSync = true,
    this.cfD1SyncIntervalMinutes = 5,
    this.activeWorkspaceId,
    this.vaultId,
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
    bool? invertScrollDirection,
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
    bool? r2Enabled,
    String? r2AccountId,
    String? r2AccessKeyId,
    String? r2SecretAccessKey,
    String? r2BucketName,
    String? r2CustomEndpoint,
    bool? r2AutoSync,
    int? r2SyncIntervalMinutes,
    int? r2LastSyncTime,
    String? cfWorkerUrl,
    int? cfD1Mode,
    Object? cfAccountId = _sentinel,
    Object? cfApiToken = _sentinel,
    Object? cfD1DatabaseId = _sentinel,
    Object? cfR2BucketName = _sentinel,
    bool? cfD1AutoSync,
    int? cfD1SyncIntervalMinutes,
    String? activeWorkspaceId,
    Object? vaultId = _sentinel,
  }) {
    return AppSettings(
      triggerMode: triggerMode ?? this.triggerMode,
      hotkey: hotkey ?? this.hotkey,
      invertScrollDirection:
          invertScrollDirection ?? this.invertScrollDirection,
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
      r2Enabled: r2Enabled ?? this.r2Enabled,
      r2AccountId: r2AccountId ?? this.r2AccountId,
      r2AccessKeyId: r2AccessKeyId ?? this.r2AccessKeyId,
      r2SecretAccessKey: r2SecretAccessKey ?? this.r2SecretAccessKey,
      r2BucketName: r2BucketName ?? this.r2BucketName,
      r2CustomEndpoint: r2CustomEndpoint ?? this.r2CustomEndpoint,
      r2AutoSync: r2AutoSync ?? this.r2AutoSync,
      r2SyncIntervalMinutes: r2SyncIntervalMinutes ?? this.r2SyncIntervalMinutes,
      r2LastSyncTime: r2LastSyncTime ?? this.r2LastSyncTime,
      cfWorkerUrl: cfWorkerUrl ?? this.cfWorkerUrl,
      cfD1Mode: cfD1Mode ?? this.cfD1Mode,
      cfAccountId: identical(cfAccountId, _sentinel)
          ? this.cfAccountId
          : cfAccountId as String?,
      cfApiToken: identical(cfApiToken, _sentinel)
          ? this.cfApiToken
          : cfApiToken as String?,
      cfD1DatabaseId: identical(cfD1DatabaseId, _sentinel)
          ? this.cfD1DatabaseId
          : cfD1DatabaseId as String?,
      cfR2BucketName: identical(cfR2BucketName, _sentinel)
          ? this.cfR2BucketName
          : cfR2BucketName as String?,
      cfD1AutoSync: cfD1AutoSync ?? this.cfD1AutoSync,
      cfD1SyncIntervalMinutes:
          cfD1SyncIntervalMinutes ?? this.cfD1SyncIntervalMinutes,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      vaultId: identical(vaultId, _sentinel)
          ? this.vaultId
          : vaultId as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'triggerMode': triggerMode.name,
      'hotkey': hotkey,
      'invertScrollDirection': invertScrollDirection,
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
      'r2Enabled': r2Enabled,
      'r2AccountId': r2AccountId,
      'r2AccessKeyId': r2AccessKeyId,
      'r2SecretAccessKey': r2SecretAccessKey,
      'r2BucketName': r2BucketName,
      'r2CustomEndpoint': r2CustomEndpoint,
      'r2AutoSync': r2AutoSync,
      'r2SyncIntervalMinutes': r2SyncIntervalMinutes,
      'r2LastSyncTime': r2LastSyncTime,
      'cfWorkerUrl': cfWorkerUrl,
      'cfD1Mode': cfD1Mode,
      'cfAccountId': cfAccountId,
      'cfApiToken': cfApiToken,
      'cfD1DatabaseId': cfD1DatabaseId,
      'cfR2BucketName': cfR2BucketName,
      'cfD1AutoSync': cfD1AutoSync,
      'cfD1SyncIntervalMinutes': cfD1SyncIntervalMinutes,
      'activeWorkspaceId': activeWorkspaceId,
      'vaultId': vaultId,
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
      invertScrollDirection: json['invertScrollDirection'] as bool? ?? false,
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
      r2Enabled: json['r2Enabled'] as bool? ?? false,
      r2AccountId: json['r2AccountId'] as String?,
      r2AccessKeyId: json['r2AccessKeyId'] as String?,
      r2SecretAccessKey: json['r2SecretAccessKey'] as String?,
      r2BucketName: json['r2BucketName'] as String?,
      r2CustomEndpoint: json['r2CustomEndpoint'] as String?,
      r2AutoSync: json['r2AutoSync'] as bool? ?? true,
      r2SyncIntervalMinutes: (json['r2SyncIntervalMinutes'] as num?)?.toInt() ?? 5,
      r2LastSyncTime: (json['r2LastSyncTime'] as num?)?.toInt(),
      cfWorkerUrl: json['cfWorkerUrl'] as String? ?? '',
      cfD1Mode: json['cfD1Mode'] as int? ?? 0,
      cfAccountId: json['cfAccountId'] as String?,
      cfApiToken: json['cfApiToken'] as String?,
      cfD1DatabaseId: json['cfD1DatabaseId'] as String?,
      cfR2BucketName: json['cfR2BucketName'] as String?,
      cfD1AutoSync: json['cfD1AutoSync'] as bool? ?? true,
      cfD1SyncIntervalMinutes: (json['cfD1SyncIntervalMinutes'] as num?)?.toInt() ?? 5,
      activeWorkspaceId: json['activeWorkspaceId'] as String?,
      vaultId: json['vaultId'] as String?,
    );
  }
}
