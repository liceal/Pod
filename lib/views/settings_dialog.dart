import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_settings.dart';
import '../services/app_state.dart';
import '../services/update_service.dart';
import '../services/cf_d1_sync_service.dart';
import '../theme/app_theme.dart';
import 'global_sync_log_dialog.dart';

class SettingsDialog extends StatefulWidget {
  final AppState state;
  final VoidCallback? onClose;

  const SettingsDialog({super.key, required this.state, this.onClose});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

typedef SettingsView = SettingsDialog;

class _SettingsDialogState extends State<SettingsDialog> {
  // Navigation & view state preservation across dialog open/close
  static int _savedSettingsTab = 0;
  static int _savedDataSubTab = 1; // 默认选中 Cloudflare D1 数据库同步 (推荐)
  static int? _savedWorkerSubTab;
  static bool? _savedShowWorkerConfigPanel;

  bool _isCheckingUpdate = false;
  String? _updateCheckResult;
  late TriggerMode _triggerMode;
  late String _hotkey;
  late bool _isDarkTheme;
  late double _hoverTimeout;
  late double _panelWidth;
  late bool _isWidthPercentage;
  late double _panelWidthPercent;
  late String _themeColorName;
  late bool _closeOnBlur;
  late int _autoCollapseDelay;
  late double _backdropOpacity;
  late int _clipboardHistoryLimit;
  late List<PanelPane> _panelOrder;
  late String _languageCode;
  late int _settingsTab;
  late int _dataSubTab;

  final List<String> _hotkeyPresets = [
    'alt+u',
    'alt+space',
    'ctrl+alt+u',
    'ctrl+shift+u',
    'alt+n',
  ];

  late String _dataDirectory;

  // Cloudflare D1 + Worker / REST API State
  late int _cfD1Mode;
  late TextEditingController _cfD1WorkerUrlController;
  late TextEditingController _cfAccountIdController;
  late TextEditingController _cfApiTokenController;
  late TextEditingController _cfD1DatabaseIdController;
  late TextEditingController _cfR2BucketNameController;
  late TextEditingController _cfWorkerNameController;
  late bool _cfD1AutoSync;
  late int _cfD1SyncIntervalMinutes;
  bool _isTestingCfD1 = false;
  bool _isDeployingWorker = false;
  String? _cfD1TestMessage;
  bool? _cfD1TestSuccess;
  int _workerSubTab = 0; // 0: 手动填写已有 URL, 1: 账号无 Worker 一键安装部署
  bool? _isWorkerOnline;
  double? _workerPingRtt;
  bool _showWorkerConfigPanel = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onAppStateChanged);
    _settingsTab = _savedSettingsTab;
    _dataSubTab = _savedDataSubTab.clamp(0, 1);
    _triggerMode = widget.state.settings.triggerMode;
    _hotkey = widget.state.settings.hotkey;
    _isDarkTheme = widget.state.settings.isDarkTheme;
    _hoverTimeout = widget.state.settings.hoverTimeoutMs.toDouble();
    _panelWidth = widget.state.settings.panelWidth;
    _isWidthPercentage = widget.state.settings.isWidthPercentage;
    _panelWidthPercent = widget.state.settings.panelWidthPercent;
    _themeColorName =
        (widget.state.settings.themeColorName as dynamic) ?? 'blue';
    _closeOnBlur = widget.state.settings.closeOnBlur;
    _autoCollapseDelay = widget.state.settings.autoCollapseDelay;
    _backdropOpacity = widget.state.settings.backdropOpacity;
    _clipboardHistoryLimit = widget.state.settings.clipboardHistoryLimit;
    _panelOrder = List<PanelPane>.from(widget.state.settings.panelOrder);
    _languageCode = widget.state.settings.languageCode;
    _dataDirectory = widget.state.getDataDirectoryPathSync();

    final s = widget.state.settings;
    _cfD1Mode = s.cfD1Mode;
    _cfD1WorkerUrlController = TextEditingController(text: s.cfWorkerUrl);
    _cfAccountIdController = TextEditingController(text: s.cfAccountId ?? '');
    _cfApiTokenController = TextEditingController(text: s.cfApiToken ?? '');
    _cfD1DatabaseIdController = TextEditingController(
      text: s.cfD1DatabaseId ?? '',
    );
    _cfR2BucketNameController = TextEditingController(
      text: s.cfR2BucketName ?? '',
    );
    _cfWorkerNameController = TextEditingController(text: 'pod-quick-backend');
    _cfD1AutoSync = s.cfD1AutoSync;
    _cfD1SyncIntervalMinutes = s.cfD1SyncIntervalMinutes;
    _workerSubTab = _savedWorkerSubTab ?? (s.cfWorkerUrl.trim().isNotEmpty ? 0 : 1);
    _showWorkerConfigPanel = _savedShowWorkerConfigPanel ?? s.cfWorkerUrl.trim().isEmpty;

    if (s.cfWorkerUrl.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoCheckWorkerHealth();
      });
    }
  }

  Future<void> _autoCheckWorkerHealth() async {
    final url = _cfD1WorkerUrlController.text.trim();
    if (url.isEmpty || !mounted) return;
    setState(() {
      _isTestingCfD1 = true;
    });
    final service = CfD1SyncService(workerUrl: url, isDevMode: true);
    final res = await service.checkHealth();
    if (mounted) {
      setState(() {
        _isTestingCfD1 = false;
        if (res['success'] == true) {
          _isWorkerOnline = true;
          _workerPingRtt = res['rttMs'] as double?;
          _showWorkerConfigPanel = false;
          _savedShowWorkerConfigPanel = false;
        } else {
          _isWorkerOnline = false;
          _showWorkerConfigPanel = true; // 测试未通过时自动展开配置面板
          _savedShowWorkerConfigPanel = true;
          _cfD1TestMessage = _text(
            '⚠️ Worker 节点连接未响应 (${res['error'] ?? res['status']})，请在下方核实 URL 或重新部署',
            '⚠️ Worker ping failed (${res['error'] ?? res['status']}), please verify URL or redeploy below',
          );
        }
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onAppStateChanged);
    _cfD1WorkerUrlController.dispose();
    _cfAccountIdController.dispose();
    _cfApiTokenController.dispose();
    _cfD1DatabaseIdController.dispose();
    _cfR2BucketNameController.dispose();
    _cfWorkerNameController.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _triggerSyncAll() {
    // 临时将输入框的值绑定到应用 settings，确保推送时使用的是最新输入的参数
    widget.state.settings = widget.state.settings.copyWith(
      cfD1Mode: _cfD1Mode,
      cfWorkerUrl: _cfD1WorkerUrlController.text.trim(),
      cfAccountId: _cfAccountIdController.text.trim(),
      cfApiToken: _cfApiTokenController.text.trim(),
      cfD1DatabaseId: _cfD1DatabaseIdController.text.trim(),
      cfR2BucketName: _cfR2BucketNameController.text.trim(),
      r2AccountId: _cfAccountIdController.text.trim().isNotEmpty
          ? _cfAccountIdController.text.trim()
          : widget.state.settings.r2AccountId,
      r2BucketName: _cfR2BucketNameController.text.trim().isNotEmpty
          ? _cfR2BucketNameController.text.trim()
          : widget.state.settings.r2BucketName,
    );
    _cfD1TestMessage = null;
    _cfD1TestSuccess = null;
    widget.state.clearLastD1SyncStatus();
    // 异步执行，完全解耦：即使用户点击「返回」离开设置界面，AppState 的后台 Future 也会持续运行
    widget.state.syncAllLocalDataAndFiles(isManual: true);
  }

  bool get _isChineseUi {
    if (_languageCode == 'zh') return true;
    if (_languageCode == 'en') return false;
    return Localizations.localeOf(context).languageCode == 'zh';
  }

  String _text(String zh, String en) => _isChineseUi ? zh : en;

  String _languageLabel(String code) {
    return switch (code) {
      'system' => _text('跟随系统', 'Follow System'),
      'en' => 'English',
      _ => '简体中文',
    };
  }

  String _tabLabel(int index) {
    return switch (index) {
      0 => _text('通用', 'General'),
      1 => _text('面板', 'Panel'),
      2 => _text('内容', 'Content'),
      _ => _text('数据', 'Data'),
    };
  }

  Widget _sectionTitle(
    String text,
    Color subColor, {
    TextOverflow? overflow,
    int? maxLines,
  }) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: subColor,
      ),
    );
  }

  Widget _buildSettingsTabs(
    Color accentColor,
    Color textColor,
    Color subColor,
    double width,
  ) {
    final isCompact = width < 360;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: List.generate(4, (index) {
          final selected = _settingsTab == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _settingsTab = index;
                _savedSettingsTab = index;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _tabLabel(index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : textColor,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _selectDataDirectory() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: _text('选择数据存储文件夹', 'Select Data Folder'),
      );
      if (selected != null && mounted) {
        setState(() {
          _dataDirectory = selected.replaceAll('\\', '/');
        });
      }
    } catch (e) {
      debugPrint('Failed to select directory: $e');
    } finally {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  Future<void> _manualSyncData() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: _text(
          '选择源数据文件夹（导入合并）',
          'Select Source Data Folder (Import & Merge)',
        ),
      );
      if (selected == null) return;
      final cleanSelected = selected.replaceAll('\\', '/');
      if (!mounted) return;

      widget.state.setDialogOpen(true);
      final confirm = await showDialog<bool>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (ctx) => AlertDialog(
          backgroundColor: _isDarkTheme
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          title: Text(
            _text('确认同步数据？', 'Confirm Data Sync?'),
            style: TextStyle(
              color: _isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            _text(
              '即将从所选文件夹同步并合并数据（便签、剪贴板历史、图片、文件）到当前的存储位置：\n$_dataDirectory\n\n注意：这不会覆盖已有的同名数据，而是进行增量合并。',
              'Data (notes, clipboard history, images, files) will be synced and merged into the current storage location:\n$_dataDirectory\n\nNote: This will perform an incremental merge and won\'t overwrite existing data.',
            ),
            style: TextStyle(
              color: _isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_text('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_text('确认同步', 'Confirm Sync')),
            ),
          ],
        ),
      );
      widget.state.setDialogOpen(false);

      if (confirm != true) return;

      widget.state.setDialogOpen(true);
      // Show progress
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black26,
        builder: (ctx) => Center(
          child: Card(
            color: const Color(0xFF262626),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _text('正在同步并刷新数据...', 'Syncing and refreshing data...'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final success = await widget.state.syncDataFromDirectory(cleanSelected);

      if (mounted) {
        Navigator.of(context).pop(); // pop progress dialog
      }
      widget.state.setDialogOpen(false);

      widget.state.setDialogOpen(true);
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _isDarkTheme
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          title: Text(
            success
                ? _text('同步成功', 'Sync Successful')
                : _text('同步失败', 'Sync Failed'),
            style: TextStyle(
              color: _isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            success
                ? _text(
                    '数据已成功同步并合并，界面已实时刷新！',
                    'Data synced and merged successfully! The UI has been refreshed.',
                  )
                : _text(
                    '数据同步失败，请检查文件夹权限或所选目录是否正确。',
                    'Data sync failed. Please check folder permissions or make sure the directory is correct.',
                  ),
            style: TextStyle(
              color: _isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(_text('确定', 'OK')),
            ),
          ],
        ),
      );
      widget.state.setDialogOpen(false);
    } catch (e) {
      debugPrint('Failed to sync directory: $e');
    } finally {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  Future<void> _save() async {
    final oldDir = widget.state.getDataDirectoryPathSync();
    final isDirChanged = _dataDirectory.toLowerCase() != oldDir.toLowerCase();

    final updated = AppSettings(
      triggerMode: _triggerMode,
      hotkey: _hotkey,
      isDarkTheme: _isDarkTheme,
      hoverTimeoutMs: _hoverTimeout.toInt(),
      panelWidth: _panelWidth,
      isWidthPercentage: _isWidthPercentage,
      panelWidthPercent: _panelWidthPercent,
      themeColorName: _themeColorName,
      closeOnBlur: _closeOnBlur,
      autoCollapseDelay: _autoCollapseDelay,
      customFilesPath: widget.state.settings.customFilesPath,
      dataDirectory: oldDir,
      backdropOpacity: _backdropOpacity,
      clipboardHistoryLimit: _clipboardHistoryLimit,
      panelOrder: _panelOrder,
      languageCode: _languageCode,
      r2Enabled: false,
      r2AccountId: widget.state.settings.r2AccountId,
      r2AccessKeyId: widget.state.settings.r2AccessKeyId,
      r2SecretAccessKey: widget.state.settings.r2SecretAccessKey,
      r2BucketName: widget.state.settings.r2BucketName,
      r2CustomEndpoint: widget.state.settings.r2CustomEndpoint,
      r2AutoSync: false,
      r2SyncIntervalMinutes: widget.state.settings.r2SyncIntervalMinutes,
      r2LastSyncTime: widget.state.settings.r2LastSyncTime,
      cfWorkerUrl: _cfD1WorkerUrlController.text.trim(),
      cfD1Mode: _cfD1Mode,
      cfAccountId: _cfAccountIdController.text.trim(),
      cfApiToken: _cfApiTokenController.text.trim(),
      cfD1DatabaseId: _cfD1DatabaseIdController.text.trim(),
      cfR2BucketName: _cfR2BucketNameController.text.trim(),
      cfD1AutoSync: _cfD1AutoSync,
      cfD1SyncIntervalMinutes: _cfD1SyncIntervalMinutes,
    );

    if (isDirChanged) {
      widget.state.setDialogOpen(true);
      final confirm = await showDialog<bool>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (ctx) => AlertDialog(
          backgroundColor: _isDarkTheme
              ? const Color(0xFF1E1E1E)
              : Colors.white,
          title: Text(
            _text('确认迁移数据？', 'Confirm Data Migration?'),
            style: TextStyle(
              color: _isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            _text(
              '检测到数据存储位置发生改变，是否立即将现有数据（包含历史记录、便签、图片及文件）迁移到新目录下？',
              'Data storage location changed. Do you want to migrate existing data (including history, notes, images, and files) to the new directory?',
            ),
            style: TextStyle(
              color: _isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _text('仅更改路径(不迁移数据)', 'Only Change Path (Don\'t Migrate)'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_text('迁移数据(推荐)', 'Migrate Data (Recommended)')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(_text('取消保存', 'Cancel Save')),
            ),
          ],
        ),
      );
      widget.state.setDialogOpen(false);

      if (confirm == null) {
        return;
      }

      if (confirm == true) {
        // 先保存其他设置（使用旧的数据目录作为源路径）
        await widget.state.updateSettings(updated);
        widget.state.setDialogOpen(true);
        // Show progress dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black26,
          builder: (ctx) => Center(
            child: Card(
              color: const Color(0xFF262626),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _text('正在迁移数据，请稍候...', 'Migrating data, please wait...'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final success = await widget.state.changeDataDirectory(_dataDirectory);

        if (mounted) {
          Navigator.of(context).pop(); // dismiss progress dialog
        }
        widget.state.setDialogOpen(false);

        if (!success) {
          widget.state.setDialogOpen(true);
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: _isDarkTheme
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              title: Text(_text('错误', 'Error')),
              content: Text(
                _text(
                  '数据迁移失败，未更改存储位置。请检查目标文件夹权限。',
                  'Data migration failed. Storage location remains unchanged. Please check target folder permissions.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(_text('确定', 'OK')),
                ),
              ],
            ),
          );
          widget.state.setDialogOpen(false);
          return;
        }
      } else {
        // Only path change
        final updatedSettings = updated.copyWith(dataDirectory: _dataDirectory);
        await widget.state.updateSettings(updatedSettings);
        await widget.state.reloadAllData();
      }
    } else {
      await widget.state.updateSettings(updated);
    }

    if (mounted) {
      if (widget.onClose != null) {
        widget.onClose!.call();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  String _getTriggerModeLabel(TriggerMode mode) {
    switch (mode) {
      case TriggerMode.both:
        return _text(
          '混合模式 (快捷键、边缘悬停与滚轮)',
          'Mixed (hotkey, edge hover, and wheel)',
        );
      case TriggerMode.hotkeyOnly:
        return _text('仅全局快捷键', 'Global hotkey only');
      case TriggerMode.hoverOnly:
        return _text('仅屏幕边缘悬停', 'Edge hover only');
      case TriggerMode.scrollOnly:
        return _text('仅鼠标滚轮下滑', 'Mouse wheel only');
    }
  }

  String _getPanelPaneLabel(PanelPane pane) {
    return switch (pane) {
      PanelPane.clipboard => _text('剪贴板', 'Clipboard'),
      PanelPane.notes => _text('便签', 'Notes'),
      PanelPane.files => _text('文件', 'Files'),
    };
  }

  IconData _getPanelPaneIcon(PanelPane pane) {
    return switch (pane) {
      PanelPane.clipboard => Icons.content_paste_rounded,
      PanelPane.notes => Icons.sticky_note_2_outlined,
      PanelPane.files => Icons.folder_open_rounded,
    };
  }

  Widget _buildPanelOrderBlock({
    required PanelPane pane,
    required int index,
    required Color textColor,
    required Color subColor,
    required Color accentColor,
  }) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDarkTheme
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getPanelPaneIcon(pane), size: 20, color: accentColor),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _getPanelPaneLabel(pane),
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = _isDarkTheme ? Colors.white : Colors.black87;
    final subColor = _isDarkTheme ? Colors.white60 : Colors.black54;
    final dropdownBg = _isDarkTheme
        ? const Color(0xFF2C2C2C)
        : Colors.grey[100]!;
    final accentColor = AppTheme.getAccentColor(_themeColorName, _isDarkTheme);

    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide = width >= 560;

          if (isWide) {
            return _buildWideLayout(
              accentColor,
              textColor,
              subColor,
              dropdownBg,
              width,
            );
          } else {
            return _buildNarrowLayout(
              accentColor,
              textColor,
              subColor,
              dropdownBg,
              width,
            );
          }
        },
      ),
    );
  }

  Widget _buildWideLayout(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
    double width,
  ) {
    return Row(
      children: [
        // Left Sidebar Navigation
        Container(
          width: 175,
          decoration: BoxDecoration(
            color: _isDarkTheme
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.3),
            border: Border(
              right: BorderSide(
                color: _isDarkTheme
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(left: 10, right: 10, top: 10, bottom: 6),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () async => await _save(),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded, size: 15, color: accentColor),
                            const SizedBox(width: 4),
                            Text(
                              _text('返回', 'Back'),
                              style: TextStyle(
                                fontSize: 12,
                                color: accentColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: Text(
                  _text('PodQuick 设置', 'PodQuick Settings'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Sidebar Menu Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    _buildSidebarNavItem(
                      index: 0,
                      icon: Icons.tune_rounded,
                      label: _text('通用设置', 'General'),
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const SizedBox(height: 4),
                    _buildSidebarNavItem(
                      index: 1,
                      icon: Icons.dashboard_customize_outlined,
                      label: _text('面板外观', 'Panel & Layout'),
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const SizedBox(height: 4),
                    _buildSidebarNavItem(
                      index: 2,
                      icon: Icons.article_outlined,
                      label: _text('内容与剪贴板', 'Content'),
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                    ),
                    const SizedBox(height: 4),
                    _buildSidebarNavItem(
                      index: 3,
                      icon: Icons.cloud_sync_outlined,
                      label: _text('数据存储与同步', 'Data & Sync'),
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                    ),
                  ],
                ),
              ),

              // Bottom Info & Save
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _text('v${UpdateService.currentVersion}', 'v${UpdateService.currentVersion}'),
                      style: TextStyle(fontSize: 11, color: subColor),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async => await _save(),
                      icon: const Icon(Icons.check_rounded, size: 14),
                      label: Text(
                        _text('保存设置', 'Save Settings'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Right Detail Pane
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sub Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _isDarkTheme
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      _tabLabel(_settingsTab),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () async => await _save(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        minimumSize: const Size(0, 26),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(_text('保存', 'Save'), style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),

              // Detail Content (Fluid 100% width with multi-column card grid adaptation)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  physics: const ClampingScrollPhysics(),
                  child: _buildTabContent(
                    accentColor,
                    textColor,
                    subColor,
                    dropdownBg,
                    width,
                    isWide: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
    double width,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation Header
          Row(
            children: [
              InkWell(
                onTap: () async => await _save(),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 16, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        _text('返回', 'Back'),
                        style: TextStyle(
                          fontSize: 12,
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _text('PodQuick 设置', 'PodQuick Settings'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () async => await _save(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 26),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _text('保存', 'Save'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildSettingsTabs(accentColor, textColor, subColor, width),
          const SizedBox(height: 8),

          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: _buildTabContent(
                accentColor,
                textColor,
                subColor,
                dropdownBg,
                width,
                isWide: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final selected = _settingsTab == index;
    return InkWell(
      onTap: () => setState(() {
        _settingsTab = index;
        _savedSettingsTab = index;
      }),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: _isDarkTheme ? 0.22 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: accentColor.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? accentColor : subColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected
                      ? (_isDarkTheme ? Colors.white : accentColor)
                      : textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSection({
    required Widget child,
    String? title,
    IconData? icon,
    Color? accentColor,
    Color? textColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDarkTheme
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: accentColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor ?? Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildTabContent(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
    double width, {
    required bool isWide,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth;
        final useTwoColumns = contentWidth >= 580;

        // Card A of Tab 0
        final langAndTriggerCard = _buildCardSection(
          title: _text('语言与唤醒', 'Language & Activation'),
          icon: Icons.tune_rounded,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(_text('语言', 'Language'), subColor),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _languageCode,
                dropdownColor: dropdownBg,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isDarkTheme ? Colors.white24 : Colors.black12,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: accentColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: AppSettings.supportedLanguageCodes.map((code) {
                  return DropdownMenuItem<String>(
                    value: code,
                    child: Text(
                      _languageLabel(code),
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _languageCode = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 14),
              Text(
                _text('唤醒方式', 'Activation'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<TriggerMode>(
                value: _triggerMode,
                dropdownColor: dropdownBg,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isDarkTheme ? Colors.white24 : Colors.black12,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: accentColor),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: TriggerMode.values.map((mode) {
                  return DropdownMenuItem<TriggerMode>(
                    value: mode,
                    child: Text(
                      _getTriggerModeLabel(mode),
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _triggerMode = val;
                    });
                  }
                },
              ),
            ],
          ),
        );

        // Card B of Tab 0
        final showHotkey = _triggerMode != TriggerMode.hoverOnly &&
            _triggerMode != TriggerMode.scrollOnly;
        final hotkeyCard = showHotkey
            ? _buildCardSection(
                title: _text('全局快捷键', 'Global Hotkey'),
                icon: Icons.keyboard_rounded,
                accentColor: accentColor,
                textColor: textColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(
                        '可在任意界面快速呼出/收起面板。选择下方预设值：',
                        'Show or hide the panel from anywhere. Choose a preset below:',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: subColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _hotkeyPresets.contains(_hotkey)
                          ? _hotkey
                          : _hotkeyPresets.first,
                      dropdownColor: dropdownBg,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isDarkTheme ? Colors.white24 : Colors.black12,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: accentColor),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      items: _hotkeyPresets.map((key) {
                        return DropdownMenuItem<String>(
                          value: key,
                          child: Text(
                            key.toUpperCase().replaceAll('+', ' + '),
                            style: TextStyle(
                              fontSize: 13,
                              color: textColor,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _hotkey = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              )
            : null;

        // Card C of Tab 0
        final hoverCollapseCard = _buildCardSection(
          title: _text('悬停与自动收起', 'Hover & Auto Collapse'),
          icon: Icons.timer_outlined,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_triggerMode != TriggerMode.hotkeyOnly &&
                  _triggerMode != TriggerMode.scrollOnly) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _text('边缘悬停延迟', 'Edge Hover Delay'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                      ),
                    ),
                    Text(
                      '${_hoverTimeout.toInt()} 毫秒',
                      style: TextStyle(fontSize: 12, color: textColor),
                    ),
                  ],
                ),
                Slider(
                  value: _hoverTimeout,
                  min: 100,
                  max: 1000,
                  divisions: 9,
                  activeColor: accentColor,
                  inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                  label: '${_hoverTimeout.toInt()}ms',
                  onChanged: (val) {
                    setState(() {
                      _hoverTimeout = val;
                    });
                  },
                ),
                const SizedBox(height: 10),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(
                          '鼠标离开后自动收起',
                          'Auto-collapse After Mouse Leaves',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                        ),
                      ),
                      Text(
                        _autoCollapseDelay >= AppSettings.maxAutoCollapseDelay
                            ? _text('仅手动收起', 'Manual only')
                            : _autoCollapseDelay == 0
                            ? _text(
                                '点击外部后立即收起',
                                'Immediately after outside click',
                              )
                            : _text(
                                '$_autoCollapseDelay 秒后收起',
                                'After $_autoCollapseDelay seconds',
                              ),
                        style: TextStyle(
                          fontSize: 11,
                          color: subColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Slider(
                value: _autoCollapseDelay.toDouble(),
                min: 0,
                max: AppSettings.maxAutoCollapseDelay.toDouble(),
                divisions: AppSettings.maxAutoCollapseDelay,
                activeColor: accentColor,
                inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                label: _autoCollapseDelay >= AppSettings.maxAutoCollapseDelay
                    ? _text('仅手动', 'Manual')
                    : _autoCollapseDelay == 0
                    ? _text('点外部立即', 'Outside click')
                    : _text(
                        '$_autoCollapseDelay 秒',
                        '${_autoCollapseDelay}s',
                      ),
                onChanged: (val) {
                  setState(() {
                    _autoCollapseDelay = val.toInt();
                  });
                },
              ),
            ],
          ),
        );

        // Card A of Tab 1: Dimensions & Opacity
        final dimensionsCard = _buildCardSection(
          title: _text('面板尺寸与透明度', 'Panel Dimensions & Opacity'),
          icon: Icons.aspect_ratio_rounded,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _text('面板宽度', 'Panel Width'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                    ),
                  ),
                  Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: _isDarkTheme
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isWidthPercentage = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: !_isWidthPercentage
                                  ? accentColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _text('固定像素', 'Pixels'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: !_isWidthPercentage
                                    ? Colors.white
                                    : textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isWidthPercentage = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _isWidthPercentage
                                  ? accentColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _text('屏幕百分比', 'Percent'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _isWidthPercentage
                                    ? Colors.white
                                    : textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (!_isWidthPercentage) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${_panelWidth.toInt()} px',
                      style: TextStyle(fontSize: 11, color: textColor),
                    ),
                  ],
                ),
                Slider(
                  value: _panelWidth,
                  min: 400,
                  max: 1600,
                  divisions: 24,
                  activeColor: accentColor,
                  inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                  label: '${_panelWidth.toInt()}px',
                  onChanged: (val) {
                    setState(() {
                      _panelWidth = val;
                    });
                  },
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${_panelWidthPercent.toInt()}%',
                      style: TextStyle(fontSize: 11, color: textColor),
                    ),
                  ],
                ),
                Slider(
                  value: _panelWidthPercent,
                  min: 30,
                  max: 100,
                  divisions: 70,
                  activeColor: accentColor,
                  inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                  label: '${_panelWidthPercent.toInt()}%',
                  onChanged: (val) {
                    setState(() {
                      _panelWidthPercent = val;
                    });
                  },
                ),
              ],
              const SizedBox(height: 14),

              // Backdrop opacity
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _text('背板透明度', 'Backdrop Opacity'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                    ),
                  ),
                  Text(
                    '${(_backdropOpacity * 100).round()}%',
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                ],
              ),
              Slider(
                value: _backdropOpacity,
                min: 0.35,
                max: 1.0,
                divisions: 65,
                activeColor: accentColor,
                inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                label: '${(_backdropOpacity * 100).round()}%',
                onChanged: (val) {
                  setState(() {
                    _backdropOpacity = val;
                  });
                },
              ),
            ],
          ),
        );

        // Card B of Tab 1: Theme & Accent Color
        final themeCard = _buildCardSection(
          title: _text('主题与外观', 'Theme & Appearance'),
          icon: Icons.palette_outlined,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _text('深色主题', 'Dark Theme'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  Switch(
                    value: _isDarkTheme,
                    activeColor: accentColor,
                    onChanged: (val) {
                      setState(() {
                        _isDarkTheme = val;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _text('主题颜色', 'Accent Color'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: ['blue', 'orange', 'green', 'purple', 'red']
                    .map((colorName) {
                      final color = AppTheme.getAccentColor(
                        colorName,
                        _isDarkTheme,
                      );
                      final isSelected = _themeColorName == colorName;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _themeColorName = colorName;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? (_isDarkTheme
                                        ? Colors.white
                                        : Colors.black87)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
            ],
          ),
        );

        // Card C of Tab 1: Panel Order
        final orderCard = _buildCardSection(
          title: _text('核心区域顺序', 'Panel Section Order'),
          icon: Icons.drag_indicator_rounded,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 72,
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  onReorder: (int oldIndex, int newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final pane = _panelOrder.removeAt(oldIndex);
                      _panelOrder.insert(newIndex, pane);
                    });
                  },
                  proxyDecorator:
                      (
                        Widget child,
                        int index,
                        Animation<double> animation,
                      ) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (BuildContext context, Widget? child) {
                            return Material(
                              elevation: 4.0,
                              color: Colors.transparent,
                              child: child,
                            );
                          },
                          child: child,
                        );
                      },
                  children: [
                    for (
                      var index = 0;
                      index < _panelOrder.length;
                      index++
                    )
                      ReorderableDragStartListener(
                        key: ValueKey(_panelOrder[index]),
                        index: index,
                        child: Container(
                          width: 120,
                          margin: const EdgeInsets.only(right: 8),
                          child: _buildPanelOrderBlock(
                            pane: _panelOrder[index],
                            index: index,
                            textColor: textColor,
                            subColor: subColor,
                            accentColor: accentColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TAB 0: 通用 General
            if (_settingsTab == 0) ...[
              if (useTwoColumns && hotkeyCard != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: langAndTriggerCard),
                    const SizedBox(width: 12),
                    Expanded(child: hotkeyCard),
                  ],
                ),
                hoverCollapseCard,
              ] else if (useTwoColumns && hotkeyCard == null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: langAndTriggerCard),
                    const SizedBox(width: 12),
                    Expanded(child: hoverCollapseCard),
                  ],
                ),
              ] else ...[
                langAndTriggerCard,
                if (hotkeyCard != null) hotkeyCard,
                hoverCollapseCard,
              ],
            ],

            // TAB 1: 面板 Panel
            if (_settingsTab == 1) ...[
              if (useTwoColumns) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: dimensionsCard),
                    const SizedBox(width: 12),
                    Expanded(child: themeCard),
                  ],
                ),
                orderCard,
              ] else ...[
                dimensionsCard,
                themeCard,
                orderCard,
              ],
            ],

            // TAB 2: 内容 Content
            if (_settingsTab == 2) ...[
              _buildCardSection(
                title: _text('剪贴板配置', 'Clipboard Settings'),
                icon: Icons.history_rounded,
                accentColor: accentColor,
                textColor: textColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _text('剪贴板记录上限', 'Clipboard History Limit'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                        Text(
                          _text(
                            '$_clipboardHistoryLimit 条',
                            '$_clipboardHistoryLimit items',
                          ),
                          style: TextStyle(fontSize: 12, color: textColor),
                        ),
                      ],
                    ),
                    Slider(
                      value: _clipboardHistoryLimit.toDouble(),
                      min: AppSettings.minClipboardHistoryLimit.toDouble(),
                      max: AppSettings.maxClipboardHistoryLimit.toDouble(),
                      divisions:
                          (AppSettings.maxClipboardHistoryLimit -
                              AppSettings.minClipboardHistoryLimit) ~/
                          10,
                      activeColor: accentColor,
                      inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
                      label: _text(
                        '$_clipboardHistoryLimit 条',
                        '$_clipboardHistoryLimit items',
                      ),
                      onChanged: (val) {
                        setState(() {
                          _clipboardHistoryLimit = (val / 10).round() * 10;
                        });
                      },
                    ),
                    Text(
                      _text(
                        '超过上限时会自动删除最早的非收藏记录。',
                        'Oldest non-favorite records are removed after this limit.',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: subColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // TAB 3: 数据 Data
            if (_settingsTab == 3) ...[
              _buildCardSection(
                title: _text('数据存储与同步', 'Data Storage & Cloud Sync'),
                icon: Icons.cloud_sync_outlined,
                accentColor: accentColor,
                textColor: textColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(
                        '所有数据（剪贴板历史、收藏、便签、图片及文件）都将保存在此目录下，方便统一管理与备份。',
                        'Clipboard history, favorites, notes, images, and files are stored here for backup and management.',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: subColor.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDataSubTabs(width, accentColor, textColor),

                    if (_dataSubTab == 0) ...[
                      // 1. 本地存储
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isDarkTheme
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isDarkTheme
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_special_rounded,
                                  size: 16,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _sectionTitle(
                                    _text(
                                      '本地存储目录与归档数据导入',
                                      'Local Storage Directory & Data Import',
                                    ),
                                    subColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    _dataDirectory,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: textColor.withValues(alpha: 0.9),
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _selectDataDirectory,
                                      icon: const Icon(
                                        Icons.edit_location_alt_rounded,
                                        size: 14,
                                      ),
                                      label: Text(
                                        _text('更改位置', 'Change'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: accentColor,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      onPressed: () => widget.state
                                          .openDirectoryPath(_dataDirectory),
                                      icon: const Icon(
                                        Icons.folder_open,
                                        size: 14,
                                      ),
                                      label: Text(
                                        _text('打开目录', 'Open'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: accentColor,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _isDarkTheme
                                    ? Colors.white.withValues(alpha: 0.03)
                                    : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 12,
                                        color: subColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _text(
                                          '默认存储路径（若旧数据丢失可从此处同步）：',
                                          'Default path (sync here if old data is missing):',
                                        ),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: subColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    widget.state.defaultDataDirectoryPath,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: subColor.withValues(alpha: 0.8),
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _manualSyncData,
                                icon: const Icon(
                                  Icons.sync_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  _text(
                                    '手动同步旧位置数据 / 导入其他文件夹数据',
                                    'Sync old location / import folder data',
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accentColor,
                                  side: BorderSide(
                                    color: accentColor.withValues(alpha: 0.4),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // 2. Cloudflare D1 + R2 Sync
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: _buildD1Section(
                          accentColor,
                          textColor,
                          subColor,
                          useTwoColumns || isWide,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Software Update Section
            const SizedBox(height: 4),
            _buildCardSection(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.system_update_rounded, size: 16, color: accentColor),
                        const SizedBox(width: 8),
                        Text(
                          _text(
                            '当前版本 v${UpdateService.currentVersion}',
                            'Version v${UpdateService.currentVersion}',
                          ),
                          style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w500),
                        ),
                        if (_updateCheckResult != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _updateCheckResult!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    _updateCheckResult!.contains('最新') ||
                                        _updateCheckResult!.contains('up to date')
                                    ? Colors.green
                                    : Colors.orangeAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isCheckingUpdate
                        ? null
                        : () async {
                            setState(() {
                              _isCheckingUpdate = true;
                              _updateCheckResult = null;
                            });
                            final info = await UpdateService.checkUpdate(widget.state.settings);
                            if (mounted) {
                              setState(() => _isCheckingUpdate = false);
                              if (info != null) {
                                UpdateService.showUpdateDialog(
                                  context,
                                  info,
                                  isDark: _isDarkTheme,
                                );
                              } else {
                                setState(() {
                                  _updateCheckResult = _text(
                                    '已是最新版本',
                                    'Up to date',
                                  );
                                });
                              }
                            }
                          },
                    icon: _isCheckingUpdate
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 14),
                    label: Text(
                      _isCheckingUpdate
                          ? _text('正在检查...', 'Checking...')
                          : _text('检查更新', 'Check Updates'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDataSubTabs(
    double width,
    Color accentColor,
    Color textColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          _buildSubTabButton(
            0,
            _text('1. 本地存储', '1. Local Storage'),
            accentColor,
            textColor,
          ),
          const SizedBox(width: 4),
          _buildSubTabButton(
            1,
            _text('2. D1+R2 云同步', '2. D1+R2 Cloud Sync'),
            accentColor,
            textColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabButton(
    int index,
    String label,
    Color accentColor,
    Color textColor,
  ) {
    final active = _dataSubTab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _dataSubTab = index;
          _savedDataSubTab = index;
        }),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildD1Section(Color accentColor, Color textColor, Color subColor, bool isWide) {
    final field1 = _buildParamFieldWithLink(
      label: _text('1. Account ID (Cloudflare 账户 ID)', '1. Account ID'),
      controller: _cfAccountIdController,
      hint: _text('在 Cloudflare 首页右下角或 URL 中复制', 'Copy from Cloudflare Overview page'),
      linkText: _text('🔗 前往复制 Account ID', '🔗 Open CF Dashboard'),
      linkUrl: 'https://dash.cloudflare.com/',
      tooltip: _text('登录 Cloudflare 首页，可在页面右下角 API 区域或 URL 中查看 Account ID', 'Check bottom-right sidebar on Cloudflare Overview page'),
      textColor: textColor,
      subColor: subColor,
      accentColor: accentColor,
    );

    final field2 = _buildParamFieldWithLink(
      label: _text('2. API 令牌 (API Token)', '2. API Token'),
      controller: _cfApiTokenController,
      hint: _text('具有 D1(编辑) 与 R2(编辑) 权限的 Bearer Token', 'Token with D1 & R2 edit permissions'),
      linkText: _text('🔗 1-click 前往创建 API 令牌', '🔗 1-click Create Token'),
      linkUrl: 'https://dash.cloudflare.com/profile/api-tokens',
      tooltip: _text('点击一键打开 CF 控制台“创建令牌” -> “使用自定义令牌” -> 赋予 D1(编辑) 与 R2(编辑) 权限', 'Click to open CF Console -> Create Token -> Grant D1 & R2 edit permissions'),
      textColor: textColor,
      subColor: subColor,
      accentColor: accentColor,
      obscureText: true,
    );

    final field3 = _buildParamFieldWithLink(
      label: _text('3. D1 数据库 ID (D1 Database ID)', '3. D1 Database ID'),
      controller: _cfD1DatabaseIdController,
      hint: _text('如: YOUR_D1_DATABASE_ID', 'e.g. YOUR_D1_DATABASE_ID'),
      linkText: _text('🔗 前往复制 D1 数据库 ID', '🔗 Open D1 Dashboard'),
      linkUrl: 'https://dash.cloudflare.com/?to=/:account/workers/d1',
      tooltip: _text('点击进入你的 D1 数据库，在控制台中复制 Database ID', 'Select your D1 database and copy Database ID'),
      textColor: textColor,
      subColor: subColor,
      accentColor: accentColor,
    );

    final field4 = _buildParamFieldWithLink(
      label: _text('4. R2 存储桶名称 (R2 Bucket Name - 可选)', '4. R2 Bucket Name (Optional)'),
      controller: _cfR2BucketNameController,
      hint: _text('如: pod-quick-files-apac (留空则不同步大文件/图片)', 'e.g. pod-quick-files-apac'),
      linkText: _text('🔗 前往复制 R2 存储桶', '🔗 Open R2 Dashboard'),
      linkUrl: 'https://dash.cloudflare.com/?to=/:account/r2',
      tooltip: _text('Cloudflare R2 存储桶名称，用于跨设备同步图片和大文件', 'R2 bucket name used to sync files and images'),
      textColor: textColor,
      subColor: subColor,
      accentColor: accentColor,
    );

    final deployD1Field = _buildParamFieldWithLink(
      label: _text('D1 数据库名称 / ID (可选)', 'D1 Database Name / ID (Optional)'),
      controller: _cfD1DatabaseIdController,
      hint: _text('默认: pod-quick-d1 (若已有可填库名或UUID)', 'Default: pod-quick-d1'),
      linkText: _text('🔗 打开 D1 控制台', '🔗 Open D1 Dashboard'),
      linkUrl: 'https://dash.cloudflare.com/?to=/:account/workers/d1',
      tooltip: _text('可填写您已有 D1 数据库的名字或UUID；留空则自动创建 pod-quick-d1', 'Fill existing D1 name or UUID, or leave blank to auto-create'),
      textColor: textColor,
      subColor: subColor,
      accentColor: accentColor,
    );

    final deployR2Field = _buildParamFieldWithLink(
      label: _text('R2 存储桶名称 (可选)', 'R2 Bucket Name (Optional)'),
      controller: _cfR2BucketNameController,
      hint: _text('默认: pod-quick-files-apac (若已有可填桶名)', 'Default: pod-quick-files-apac'),
      linkText: _text('🔗 打开 R2 控制台', '🔗 Open R2 Dashboard'),
      linkUrl: 'https://dash.cloudflare.com/?to=/:account/r2',
      tooltip: _text('可填写您已有 R2 存储桶的名字；留空则自动创建 pod-quick-files-apac', 'Fill existing R2 bucket name, or leave blank to auto-create'),
      textColor: textColor,
      subColor: subColor,
      accentColor: accentColor,
    );

    final deployWorkerNameField = _buildCustomTextField(
      label: _text('Worker 脚本服务名称 (可选)', 'Worker Script Name (Optional)'),
      controller: _cfWorkerNameController,
      hint: 'pod-quick-backend',
      textColor: textColor,
      subColor: subColor,
      accentColor: accentColor,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_done_rounded, size: 16, color: accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: _sectionTitle(
                _text(
                  'Cloudflare D1 数据库 + R2 文件存储',
                  'Cloudflare D1 + R2 API Sync',
                ),
                subColor,
              ),
            ),
            InkWell(
              onTap: () async {
                final accountId = _cfAccountIdController.text.trim();
                final dbId = _cfD1DatabaseIdController.text.trim();
                String url = 'https://dash.cloudflare.com/';
                if (accountId.isNotEmpty && dbId.isNotEmpty) {
                  url = 'https://dash.cloudflare.com/$accountId/d1/databases/$dbId';
                } else if (accountId.isNotEmpty) {
                  url = 'https://dash.cloudflare.com/$accountId/d1/databases';
                }
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 12, color: accentColor),
                    const SizedBox(width: 4),
                    Text(
                      _text('线上 D1 控制台 ↗', 'Online D1 Console ↗'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _text(
            '💡 方案 A 直通模式：直接在下表填入您在 Cloudflare 网页申请的 Token 和数据库 ID，100% 走您自己的账号资源。',
            '💡 Mode A Direct REST API: Enter your Account ID & Token in the GUI to use your own Cloudflare account.',
          ),
          style: TextStyle(
            fontSize: 10,
            color: subColor.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 8),

        // === 节点模式切换 Segmented Toggle ===
        Container(
          height: 30,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _isDarkTheme
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _cfD1Mode = 0);
                    if (_isWorkerOnline == null && _cfD1WorkerUrlController.text.trim().isNotEmpty) {
                      _autoCheckWorkerHealth();
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cfD1Mode == 0 ? accentColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _text('Worker 托管节点模式', 'Worker API Node'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _cfD1Mode == 0 ? Colors.white : textColor,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _cfD1Mode = 1),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cfD1Mode == 1 ? accentColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _text(
                        'Cloudflare REST API 直连 (您的账号)',
                        'Direct REST API (Your CF)',
                      ),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _cfD1Mode == 1 ? Colors.white : textColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (_cfD1Mode == 0) ...[
          // === 第一步：Worker 节点状态检查卡片 ===
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isTestingCfD1
                  ? accentColor.withValues(alpha: 0.06)
                  : ((_cfD1WorkerUrlController.text.trim().isNotEmpty && _isWorkerOnline == true)
                      ? Colors.green.withValues(alpha: 0.08)
                      : (_cfD1WorkerUrlController.text.trim().isNotEmpty && _isWorkerOnline == false)
                          ? Colors.orange.withValues(alpha: 0.08)
                          : (_isDarkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.025))),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isTestingCfD1
                    ? accentColor.withValues(alpha: 0.3)
                    : ((_cfD1WorkerUrlController.text.trim().isNotEmpty && _isWorkerOnline == true)
                        ? Colors.green.withValues(alpha: 0.3)
                        : (_cfD1WorkerUrlController.text.trim().isNotEmpty && _isWorkerOnline == false)
                            ? Colors.orange.withValues(alpha: 0.35)
                            : (_isDarkTheme ? Colors.white12 : Colors.black12)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_isTestingCfD1) ...[
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                      ),
                    ] else ...[
                      Icon(
                        _cfD1WorkerUrlController.text.trim().isEmpty
                            ? Icons.warning_amber_rounded
                            : (_isWorkerOnline == true
                                ? Icons.check_circle_rounded
                                : (_isWorkerOnline == false ? Icons.error_outline_rounded : Icons.cloud_queue_rounded)),
                        size: 16,
                        color: _cfD1WorkerUrlController.text.trim().isEmpty
                            ? Colors.orangeAccent
                            : (_isWorkerOnline == true
                                ? Colors.green
                                : (_isWorkerOnline == false ? Colors.redAccent : accentColor)),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isTestingCfD1
                                ? _text('正在探测 Worker 节点连通性...', 'Testing Worker node connectivity...')
                                : (_cfD1WorkerUrlController.text.trim().isEmpty
                                    ? _text('未配置 Worker 节点 (请在下方选择【填入已有 URL】或【一键自动安装】)', 'Worker Node Not Configured (Choose Option 1 or 2 below)')
                                    : (_isWorkerOnline == true
                                        ? _text('✅ Worker 节点正常在线 (RTT: ${_workerPingRtt?.toStringAsFixed(1)}ms)', '✅ Worker Node Online & Ready')
                                        : (_isWorkerOnline == false
                                            ? _text('❌ Worker 节点未响应或连接失败', '❌ Worker Node Unreachable')
                                            : _text('Worker 节点已在本地缓存 (待测试)', 'Worker Node Cached (Untested)')))),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          if (_cfD1WorkerUrlController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            SelectableText(
                              _cfD1WorkerUrlController.text.trim(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                                color: subColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_cfD1WorkerUrlController.text.trim().isNotEmpty) ...[
                      TextButton.icon(
                        onPressed: _isTestingCfD1
                            ? null
                            : () async {
                                setState(() {
                                  _isTestingCfD1 = true;
                                  _cfD1TestMessage = null;
                                });
                                final service = CfD1SyncService(
                                  workerUrl: _cfD1WorkerUrlController.text.trim(),
                                  isDevMode: true,
                                );
                                final res = await service.checkHealth();
                                if (mounted) {
                                  setState(() {
                                    _isTestingCfD1 = false;
                                    if (res['success'] == true) {
                                      _isWorkerOnline = true;
                                      _cfD1TestSuccess = true;
                                      _workerPingRtt = res['rttMs'] as double?;
                                      _cfD1TestMessage = _text(
                                        '✅ Worker 节点连接正常！网络往返: ${(_workerPingRtt ?? 0).toStringAsFixed(1)}ms',
                                        '✅ Worker Connected! RTT: ${(_workerPingRtt ?? 0).toStringAsFixed(1)}ms',
                                      );
                                    } else {
                                      _isWorkerOnline = false;
                                      _cfD1TestSuccess = false;
                                      _cfD1TestMessage = _text(
                                        '❌ 节点连接失败: ${res['error'] ?? res['status']}',
                                        'Connection failed',
                                      );
                                    }
                                  });
                                }
                              },
                        icon: _isTestingCfD1
                            ? const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.speed_rounded, size: 13),
                        label: Text(_text('测试', 'Test'), style: const TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showWorkerConfigPanel = !_showWorkerConfigPanel;
                            _savedShowWorkerConfigPanel = _showWorkerConfigPanel;
                          });
                        },
                        icon: Icon(_showWorkerConfigPanel ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded, size: 13),
                        label: Text(
                          _showWorkerConfigPanel ? _text('收起配置', 'Collapse') : _text('修改/重新部署', 'Config'),
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: subColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // === 第二步：配置与部署向导面板 (未配置或点击修改时展开) ===
          if (_cfD1WorkerUrlController.text.trim().isEmpty || _showWorkerConfigPanel) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isDarkTheme
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 子选项切换卡
                  Container(
                    height: 30,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _isDarkTheme
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _workerSubTab = 0;
                              _savedWorkerSubTab = 0;
                            }),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _workerSubTab == 0 ? accentColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _text('方案 1: 手动填入已有 Worker URL', 'Option 1: Fill Existing URL'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: _workerSubTab == 0 ? Colors.white : textColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _workerSubTab = 1;
                              _savedWorkerSubTab = 1;
                            }),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _workerSubTab == 1 ? accentColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _text('方案 2: 账号空白？为我一键安装部署', 'Option 2: Auto Install Worker'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: _workerSubTab == 1 ? Colors.white : textColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_workerSubTab == 0) ...[
                    // 方案 1: 手动填入已有 URL
                    _buildCustomTextField(
                      label: _text('Cloudflare Worker 边缘节点 URL', 'Cloudflare Worker URL'),
                      controller: _cfD1WorkerUrlController,
                      hint: 'https://pod-quick-backend.your-subdomain.workers.dev',
                      textColor: textColor,
                      subColor: subColor,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isTestingCfD1
                              ? null
                              : () async {
                                  final url = _cfD1WorkerUrlController.text.trim();
                                  if (url.isEmpty) {
                                    setState(() {
                                      _cfD1TestSuccess = false;
                                      _cfD1TestMessage = _text('⚠️ 请先输入 Worker 节点 URL', 'Please enter Worker URL');
                                    });
                                    return;
                                  }
                                  setState(() {
                                    _isTestingCfD1 = true;
                                    _cfD1TestMessage = null;
                                  });
                                  final service = CfD1SyncService(workerUrl: url, isDevMode: true);
                                  final res = await service.checkHealth();
                                  if (mounted) {
                                    setState(() {
                                      _isTestingCfD1 = false;
                                      if (res['success'] == true) {
                                        _isWorkerOnline = true;
                                        _cfD1TestSuccess = true;
                                        _workerPingRtt = res['rttMs'] as double?;
                                        _showWorkerConfigPanel = false;
                                        _cfD1TestMessage = _text('✅ Worker 节点验证通过并已缓存到本地！', 'Worker verified & cached!');
                                        // 自动写入设置
                                        widget.state.updateSettings(
                                          widget.state.settings.copyWith(
                                            cfD1Mode: 0,
                                            cfWorkerUrl: url,
                                          ),
                                        );
                                      } else {
                                        _isWorkerOnline = false;
                                        _cfD1TestSuccess = false;
                                        _cfD1TestMessage = _text('❌ 验证失败: ${res['error'] ?? res['status']}', 'Verification failed');
                                      }
                                    });
                                  }
                                },
                          icon: _isTestingCfD1
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded, size: 13),
                          label: Text(_text('保存并测试连接', 'Save & Test'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // 方案 2: 账号空白？一键为我安装部署
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 14, color: Colors.amber),
                              const SizedBox(width: 5),
                              Text(
                                _text('部署前权限必读 (避免 HTTP 403 错误):', 'Permissions Required (Avoid 403):'),
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _text(
                              'Cloudflare 官方安全限制：自动部署脚本需要 API 令牌具备以下两项权限：\n'
                              '• 1. Workers 脚本 (Workers Scripts) ➔ 编辑 (Edit)\n'
                              '• 2. D1 数据库 (D1 Database) ➔ 编辑 (Edit)\n'
                              '（若缺少 Workers 脚本权限，Cloudflare 将返回 Authentication error 403）',
                              'Cloudflare requires your API Token to have Workers Scripts (Edit) and D1 (Edit) permissions.',
                            ),
                            style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.9), height: 1.35),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () async {
                              final uri = Uri.parse('https://dash.cloudflare.com/profile/api-tokens');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new_rounded, size: 12, color: accentColor),
                                const SizedBox(width: 4),
                                Text(
                                  _text('🔗 1-click 前往 Cloudflare 网页端创建 / 补充 API 令牌权限 ↗', '🔗 Open CF Dashboard to grant Workers:Edit token ↗'),
                                  style: TextStyle(fontSize: 10.5, color: accentColor, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 1. 基础凭据输入
                    if (isWide) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: field1),
                          const SizedBox(width: 12),
                          Expanded(child: field2),
                        ],
                      ),
                    ] else ...[
                      field1,
                      const SizedBox(height: 8),
                      field2,
                    ],
                    const SizedBox(height: 10),

                    // 2. 自定义 / 复用已有云端资源卡片
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _isDarkTheme
                            ? Colors.white.withValues(alpha: 0.02)
                            : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isDarkTheme ? Colors.white10 : Colors.black12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.tune_rounded, size: 13, color: accentColor),
                              const SizedBox(width: 5),
                              Text(
                                _text('自定义 / 复用已有云端资源名称 (可选)', 'Custom / Reuse Existing Cloud Resources (Optional)'),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _text(
                              '💡 资源复用提示：若您在 Cloudflare 上已经创建了 D1 数据库或 R2 存储桶，可直接在下方填入它们的名字或 ID，系统会自动检测并直接绑定，不会重复创建！若留空，系统将自动以默认名 (pod-quick-d1 / pod-quick-files-apac) 全新创建。',
                              'Tip: If you already have a D1 database or R2 bucket in Cloudflare, enter their names below to bind them directly without re-creating. Leave blank to auto-create defaults.',
                            ),
                            style: TextStyle(fontSize: 9.5, color: subColor, height: 1.35),
                          ),
                          const SizedBox(height: 8),
                          if (isWide) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: deployD1Field),
                                const SizedBox(width: 10),
                                Expanded(child: deployR2Field),
                              ],
                            ),
                            const SizedBox(height: 8),
                            deployWorkerNameField,
                          ] else ...[
                            deployD1Field,
                            const SizedBox(height: 8),
                            deployR2Field,
                            const SizedBox(height: 8),
                            deployWorkerNameField,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 部署按钮
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_isDeployingWorker || widget.state.isD1Syncing)
                                ? null
                                : () async {
                                    final accountId = _cfAccountIdController.text.trim();
                                    final apiToken = _cfApiTokenController.text.trim();
                                    if (accountId.isEmpty || apiToken.isEmpty) {
                                      setState(() {
                                        _cfD1TestSuccess = false;
                                        _cfD1TestMessage = _text(
                                          '⚠️ 请先填入 Account ID 和具备 Workers 脚本与 D1 编辑权限的 API Token',
                                          'Please enter Account ID and API Token with Workers & D1 Edit permissions',
                                        );
                                      });
                                      return;
                                    }

                                    setState(() {
                                      _isDeployingWorker = true;
                                      _cfD1TestMessage = _text('🚀 正在连接 Cloudflare API 执行一键部署 Worker...', 'Deploying Worker...');
                                      _cfD1TestSuccess = null;
                                    });

                                    final d1Name = _cfD1DatabaseIdController.text.trim().isNotEmpty
                                        ? _cfD1DatabaseIdController.text.trim()
                                        : 'pod-quick-d1';
                                    final bucketName = _cfR2BucketNameController.text.trim().isNotEmpty
                                        ? _cfR2BucketNameController.text.trim()
                                        : 'pod-quick-files-apac';
                                    final workerName = _cfWorkerNameController.text.trim().isNotEmpty
                                        ? _cfWorkerNameController.text.trim()
                                        : 'pod-quick-backend';

                                    final res = await CfD1SyncService.deployWorkerAndD1(
                                      accountId: accountId,
                                      apiToken: apiToken,
                                      d1Name: d1Name,
                                      r2BucketName: bucketName,
                                      workerName: workerName,
                                      onLog: (msg) {
                                        widget.state.addD1Log(msg);
                                      },
                                    );

                                    if (mounted) {
                                      setState(() {
                                        _isDeployingWorker = false;
                                        if (res['success'] == true) {
                                          _isWorkerOnline = true;
                                          _cfD1TestSuccess = true;
                                          _cfD1WorkerUrlController.text = res['workerUrl'] ?? '';
                                          _cfD1DatabaseIdController.text = res['d1DatabaseId'] ?? '';
                                          _cfR2BucketNameController.text = res['r2BucketName'] ?? bucketName;
                                          _showWorkerConfigPanel = false;
                                          _cfD1TestMessage = _text(
                                            '🎉 Worker 节点部署成功！已绑定 D1: ${res['d1Name'] ?? d1Name} | R2: ${res['r2BucketName'] ?? bucketName}\n域名: ${res['workerUrl']}',
                                            '🎉 Worker Deployed! Bound D1: ${res['d1Name'] ?? d1Name}, R2: ${res['r2BucketName'] ?? bucketName}\nURL: ${res['workerUrl']}',
                                          );

                                          // 自动更新设置
                                          widget.state.updateSettings(
                                            widget.state.settings.copyWith(
                                              cfD1Mode: 0,
                                              cfWorkerUrl: res['workerUrl'],
                                              cfAccountId: accountId,
                                              cfApiToken: apiToken,
                                              cfD1DatabaseId: res['d1DatabaseId'],
                                              cfR2BucketName: res['r2BucketName'] ?? bucketName,
                                              r2BucketName: widget.state.settings.r2BucketName ?? (res['r2BucketName'] ?? bucketName),
                                            ),
                                          );
                                        } else {
                                          _cfD1TestSuccess = false;
                                          _cfD1TestMessage = res['error'] ?? _text('❌ 部署失败', 'Deployment failed');
                                        }
                                      });
                                    }
                                  },
                            icon: _isDeployingWorker
                                ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.rocket_launch_rounded, size: 14),
                            label: Text(
                              _isDeployingWorker
                                  ? _text('正在部署发布中...', 'Deploying...')
                                  : _text('🚀 立即一键自动安装部署 Worker', '🚀 1-Click Auto Deploy Worker'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse('https://dash.cloudflare.com/');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_browser_rounded, size: 13),
                          label: Text(_text('浏览器打开 Cloudflare ↗', 'Open Cloudflare Dash ↗'), style: const TextStyle(fontSize: 10.5)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _text(
                      '请在下方填写 Cloudflare 凭证。点击参数旁边的【🔗 前往复制/创建】链接，将自动在浏览器中打开 Cloudflare 控制台对应页面。',
                      'Fill in Cloudflare credentials below. Click the link next to each field to open Cloudflare console directly.',
                    ),
                    style: TextStyle(fontSize: 10.5, color: textColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (isWide) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field1),
                const SizedBox(width: 12),
                Expanded(child: field2),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field3),
                const SizedBox(width: 12),
                Expanded(child: field4),
              ],
            ),
          ] else ...[
            field1,
            const SizedBox(height: 8),
            field2,
            const SizedBox(height: 8),
            field3,
            const SizedBox(height: 8),
            field4,
          ],
        ],

        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_isTestingCfD1 || widget.state.isD1Syncing)
                    ? null
                    : () async {
                        setState(() {
                          _isTestingCfD1 = true;
                          _cfD1TestMessage = null;
                          _cfD1TestSuccess = null;
                        });
                        if (_cfD1Mode == 0) {
                          final service = CfD1SyncService(
                            workerUrl: _cfD1WorkerUrlController.text.trim(),
                            isDevMode: true,
                          );
                          final res = await service.checkHealth();
                          if (mounted) {
                            setState(() {
                              _isTestingCfD1 = false;
                              if (res['success'] == true) {
                                _cfD1TestSuccess = true;
                                _cfD1TestMessage = _text(
                                  '✅ D1数据库连接正常！客户端网络往返(RTT): ${(res['rttMs'] as double).toStringAsFixed(1)}ms | Worker处理: ${res['serverTimeMs'] ?? "N/A"}ms',
                                  '✅ D1 Connected! RTT: ${(res['rttMs'] as double).toStringAsFixed(1)}ms',
                                );
                              } else {
                                _cfD1TestSuccess = false;
                                _cfD1TestMessage = _text(
                                  '❌ 连接失败: ${res['error'] ?? res['status']}',
                                  'Connection failed',
                                );
                              }
                            });
                          }
                        } else {
                          final res = await CfD1SyncService.checkHealthRestApi(
                            accountId: _cfAccountIdController.text.trim(),
                            apiToken: _cfApiTokenController.text.trim(),
                            d1DatabaseId: _cfD1DatabaseIdController.text.trim(),
                          );
                          if (mounted) {
                            setState(() {
                              _isTestingCfD1 = false;
                              if (res['success'] == true) {
                                _cfD1TestSuccess = true;
                                _cfD1TestMessage = _text(
                                  '✅ Cloudflare REST API 连接成功！网络往返: ${(res['rttMs'] as double).toStringAsFixed(1)}ms',
                                  '✅ REST API Connected! RTT: ${(res['rttMs'] as double).toStringAsFixed(1)}ms',
                                );
                              } else {
                                _cfD1TestSuccess = false;
                                _cfD1TestMessage = _text(
                                  '❌ REST API 连接失败: ${res['error']}',
                                  'Connection failed',
                                );
                              }
                            });
                          }
                        }
                      },
                icon: _isTestingCfD1
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_rounded, size: 14),
                label: Text(
                  _cfD1Mode == 0
                      ? _text('测试 D1 节点延迟', 'Test D1 Node')
                      : _text('测试 API 连通性', 'Test API Connectivity'),
                  style: const TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_isTestingCfD1 || widget.state.isD1Syncing)
                    ? null
                    : () => _triggerSyncAll(),
                icon: widget.state.isD1Syncing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_rounded, size: 14),
                label: Text(
                  widget.state.isD1Syncing
                      ? _text('后台同步中...', 'Syncing...')
                      : _text('立即同步', 'Sync Now'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                ),
              ),
            ),
          ],
        ),

        // === 后台定时自动增量同步设置卡片 ===
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isDarkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _isDarkTheme ? Colors.white12 : Colors.black12),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _text('后台定时自动增量同步', 'Background Auto-Sync'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              if (_cfD1AutoSync) ...[
                DropdownButton<int>(
                  value: _cfD1SyncIntervalMinutes,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: _isDarkTheme ? const Color(0xFF252830) : Colors.white,
                  style: TextStyle(fontSize: 10.5, color: accentColor, fontWeight: FontWeight.bold),
                  items: [1, 3, 5, 10, 15, 30, 60].map((m) {
                    return DropdownMenuItem<int>(
                      value: m,
                      child: Text(_text('每 $m 分钟', 'Every $m min')),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _cfD1SyncIntervalMinutes = val);
                      _save();
                    }
                  },
                ),
                const SizedBox(width: 8),
              ],
              Switch(
                value: _cfD1AutoSync,
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) {
                  setState(() => _cfD1AutoSync = val);
                  _save();
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: () {
              GlobalSyncLogDialog.show(context, state: widget.state);
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.priority_high_rounded, size: 12, color: accentColor),
                  const SizedBox(width: 4),
                  Text(
                    _text('弹出独立全局同步控制台 ↗', 'Open Global Sync Console ↗'),
                    style: TextStyle(fontSize: 10.5, color: accentColor, decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
          ),
        ),

        // === 状态反馈横幅 (后台同步中 / 同步完成 / 测试连接结果) ===
        ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) {
            if (widget.state.isD1Syncing) {
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text(
                              '🚀 正在后台全量同步中（便签、剪贴板记录与文件/图片）...',
                              '🚀 Syncing data & files in background...',
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _text(
                              '💡 您可以随时点击左上角「返回」回到主界面查看或使用便签，后台同步不会中断。',
                              '💡 You can safely return to the main view; sync will continue in background.',
                            ),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: textColor.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            final showMessage = widget.state.lastD1SyncMessage ?? _cfD1TestMessage;
            final isSuccess = widget.state.lastD1SyncMessage != null
                ? widget.state.lastD1SyncSuccess
                : _cfD1TestSuccess;

            if (showMessage == null) return const SizedBox.shrink();

            final isOk = isSuccess == true;
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isOk
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isOk
                      ? Colors.green.withValues(alpha: 0.4)
                      : Colors.red.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOk ? Icons.check_circle_outline : Icons.error_outline,
                        size: 14,
                        color: isOk ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          showMessage,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isOk ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_cfD1TestSuccess == true &&
                      _cfD1TestMessage != null &&
                      widget.state.lastD1SyncMessage == null &&
                      !_cfD1TestMessage!.contains('全量同步') &&
                      !_cfD1TestMessage!.contains('云端')) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: widget.state.isD1Syncing
                            ? null
                            : () => _triggerSyncAll(),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            _text('👉 连接成功！点击此处立即执行全量差异同步 (D1 + R2)', '👉 Connected! Click to run full sync (D1 + R2)'),
                            style: TextStyle(
                              fontSize: 10,
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),

        // === D1 同步实时日志显示框 ===
        ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) {
            final logs = widget.state.d1SyncLogs;
            if (logs.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.terminal_rounded, size: 12, color: subColor),
                    const SizedBox(width: 4),
                    Text(
                      _text('D1 数据库同步日志记录:', 'D1 Sync Real-time Logs:'),
                      style: TextStyle(fontSize: 10, color: subColor, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: subColor.withValues(alpha: 0.2)),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: logs.map((log) {
                        return Text(
                          log,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            color: Colors.white70,
                            height: 1.35,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCustomTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required Color textColor,
    required Color subColor,
    required Color accentColor,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: subColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 10,
              color: subColor.withValues(alpha: 0.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: _isDarkTheme ? Colors.white24 : Colors.black12,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: accentColor),
            ),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }

  Widget _buildParamFieldWithLink({
    required String label,
    required TextEditingController controller,
    required String hint,
    required String linkText,
    required String linkUrl,
    required String tooltip,
    required Color textColor,
    required Color subColor,
    required Color accentColor,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: subColor,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () async {
                final uri = Uri.parse(linkUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Tooltip(
                  message: tooltip,
                  child: Text(
                    linkText,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          obscureText: obscureText,
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 10,
              color: subColor.withValues(alpha: 0.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 7,
            ),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: _isDarkTheme ? Colors.white24 : Colors.black12,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: accentColor),
            ),
          ),
        ),
      ],
    );
  }
}
