import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_settings.dart';
import '../models/note.dart';
import '../models/workspace_profile.dart';
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
  static int _savedGeneralSubTab = 0;
  static int _savedPanelSubTab = 0;
  static int _savedContentSubTab = 0;
  static int _savedDataSubTab = 0;
  static int? _savedWorkerSubTab;

  bool _isCheckingUpdate = false;
  String? _updateCheckResult;
  late TriggerMode _triggerMode;
  late String _hotkey;
  late bool _invertScrollDirection;
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
  late int _generalSubTab;
  late int _panelSubTab;
  late int _contentSubTab;
  late int _dataSubTab;
  String? _fourthColumnType; // 右侧延展的第 4 栏类型: 'cf_custom_names' | 'sync_logs' | 'quick_worker_url'

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
  bool _showWorkerAdvanced = false;
  bool _isEditingWorker = false;
  late String _selectedWorkspaceId;
  String? _editingWorkspaceId;
  String? _pendingDirectoryPath;
  WorkspaceProfile? _detectedWorkspaceProfile;
  late final TextEditingController _inlineRenameController = TextEditingController();
  late final FocusNode _inlineRenameFocusNode = FocusNode();

  WorkspaceProfile get _selectedWorkspace {
    return widget.state.workspaces.firstWhere(
      (w) => w.id == _selectedWorkspaceId,
      orElse: () => widget.state.currentWorkspace,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onAppStateChanged);
    _settingsTab = _savedSettingsTab.clamp(0, 3);
    _generalSubTab = _savedGeneralSubTab.clamp(0, 3);
    _panelSubTab = _savedPanelSubTab.clamp(0, 2);
    _contentSubTab = _savedContentSubTab.clamp(0, 0);
    _dataSubTab = _savedDataSubTab.clamp(0, 2);
    _selectedWorkspaceId = widget.state.currentWorkspace.id;
    _triggerMode = widget.state.settings.triggerMode;
    _hotkey = widget.state.settings.hotkey;
    _invertScrollDirection = widget.state.settings.invertScrollDirection;
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

    _isWorkerOnline = widget.state.getWorkspaceCloudOnline(_selectedWorkspace.id);
    _workerPingRtt = widget.state.getWorkspacePingRtt(_selectedWorkspace.id);
    if (s.cfWorkerUrl.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoCheckWorkerHealth();
      });
    }
  }

  Future<void> _autoCheckWorkerHealth() async {
    final url = _cfD1WorkerUrlController.text.trim();
    if (url.isEmpty || !mounted) return;
    // 静默检测连通性，不弹加载提示，不洗掉已有已连接状态
    final service = CfD1SyncService(workerUrl: url, isDevMode: true);
    final res = await service.checkHealth();
    if (mounted) {
      setState(() {
        if (res['success'] == true) {
          _isWorkerOnline = true;
          _workerPingRtt = res['rttMs'] as double?;
          widget.state.setWorkspaceCloudOnline(_selectedWorkspace.id, true, rttMs: _workerPingRtt);
        } else {
          if (_isWorkerOnline != true) {
            _isWorkerOnline = false;
            widget.state.setWorkspaceCloudOnline(_selectedWorkspace.id, false);
          }
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
    _inlineRenameController.dispose();
    _inlineRenameFocusNode.dispose();
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

  Future<void> _pickDirectoryForSelectedWorkspace() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: _text('选择数据存储文件夹', 'Select Data Folder'),
      );
      if (selected != null && mounted) {
        final cleanPath = selected.replaceAll('\\', '/');
        final currentPath = _selectedWorkspace.directoryPath;
        if (cleanPath.toLowerCase() == currentPath.toLowerCase()) {
          setState(() {
            _pendingDirectoryPath = null;
            _detectedWorkspaceProfile = null;
          });
          return;
        }

        WorkspaceProfile? detected;
        final wsFile = File('$cleanPath/workspace.json');
        if (wsFile.existsSync()) {
          try {
            final content = wsFile.readAsStringSync();
            final decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic>) {
              detected = WorkspaceProfile.fromJson(decoded);
            }
          } catch (e) {
            debugPrint('Failed to parse detected workspace.json: $e');
          }
        }

        setState(() {
          _pendingDirectoryPath = cleanPath;
          _detectedWorkspaceProfile = detected;
        });
      }
    } catch (e) {
      debugPrint('Failed to pick directory: $e');
    } finally {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  Future<void> _applyPendingDirectory() async {
    if (_pendingDirectoryPath == null) return;
    final targetPath = _pendingDirectoryPath!;
    final detected = _detectedWorkspaceProfile;
    final isCurrent = _selectedWorkspace.id == widget.state.currentWorkspace.id;

    // 1. 构建更新后的 WorkspaceProfile（若检测到已有元数据，自动载入其云端同步配置）
    final oldProfile = _selectedWorkspace;
    WorkspaceProfile updatedProfile;
    if (detected != null) {
      updatedProfile = oldProfile.copyWith(
        directoryPath: targetPath,
        cfWorkerUrl: detected.cfWorkerUrl,
        cfAccountId: detected.cfAccountId,
        cfApiToken: detected.cfApiToken,
        cfD1DatabaseId: detected.cfD1DatabaseId,
        cfR2BucketName: detected.cfR2BucketName,
        cfD1AutoSync: detected.cfD1AutoSync,
        cfD1SyncIntervalMinutes: detected.cfD1SyncIntervalMinutes,
        vaultId: detected.vaultId ?? oldProfile.vaultId,
      );
    } else {
      updatedProfile = oldProfile.copyWith(directoryPath: targetPath);
    }

    // 2. 保存工作区档案
    await widget.state.saveWorkspaceProfile(updatedProfile);

    // 3. 立即回填输入框，使云端存储标签页能即刻看到该配置
    _cfD1WorkerUrlController.text = updatedProfile.cfWorkerUrl ?? '';
    _cfAccountIdController.text = updatedProfile.cfAccountId ?? '';
    _cfApiTokenController.text = updatedProfile.cfApiToken ?? '';
    _cfD1DatabaseIdController.text = updatedProfile.cfD1DatabaseId ?? '';
    _cfR2BucketNameController.text = updatedProfile.cfR2BucketName ?? '';
    _cfD1AutoSync = updatedProfile.cfD1AutoSync;
    _cfD1SyncIntervalMinutes = updatedProfile.cfD1SyncIntervalMinutes;

    // 4. 若为当前激活工作区，同步更新当前全局激活配置并重载数据
    if (isCurrent) {
      _dataDirectory = targetPath;
      final newSettings = widget.state.settings.copyWith(
        dataDirectory: targetPath,
        cfWorkerUrl: updatedProfile.cfWorkerUrl ?? '',
        cfAccountId: updatedProfile.cfAccountId,
        cfApiToken: updatedProfile.cfApiToken,
        cfD1DatabaseId: updatedProfile.cfD1DatabaseId,
        cfR2BucketName: updatedProfile.cfR2BucketName,
        cfD1AutoSync: updatedProfile.cfD1AutoSync,
        cfD1SyncIntervalMinutes: updatedProfile.cfD1SyncIntervalMinutes,
        vaultId: updatedProfile.vaultId,
      );
      await widget.state.updateSettings(newSettings);
      await widget.state.reloadAllData();
    }

    // 5. 清理待应用状态，使「应用」按钮消失
    setState(() {
      _pendingDirectoryPath = null;
      _detectedWorkspaceProfile = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detected != null && detected.hasCloudConfig
                ? _text('已应用目录，并自动载入云端同步节点（${detected.cfWorkerUrl}）', 'Directory applied & cloud config loaded (${detected.cfWorkerUrl})')
                : _text('已成功应用新数据存储目录！', 'Data storage directory applied!'),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  Future<void> _showCreateWorkspaceDialog() async {
    final nameCtrl = TextEditingController(text: _text('新工作区', 'New Workspace'));
    String? customPath;
    WorkspaceInitType initType = WorkspaceInitType.blank;
    bool inheritCloud = false;

    widget.state.setDialogOpen(true);
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
              title: Text(
                _text('新建工作区', 'Create Workspace'),
                style: TextStyle(color: _isDarkTheme ? Colors.white : Colors.black87, fontSize: 16),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text('工作区名称', 'Workspace Name'),
                        style: TextStyle(fontSize: 12, color: _isDarkTheme ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(color: _isDarkTheme ? Colors.white : Colors.black87, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: _text('例如：工作、个人、学习...', 'e.g., Work, Personal...'),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _text('本地存储目录', 'Local Directory'),
                        style: TextStyle(fontSize: 12, color: _isDarkTheme ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              customPath ?? _text('默认（系统自动在 workspaces/ 下创建）', 'Default (workspaces/ under app dir)'),
                              style: TextStyle(
                                fontSize: 11,
                                color: _isDarkTheme ? Colors.white60 : Colors.black45,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              await windowManager.setAlwaysOnTop(false);
                              final sel = await FilePicker.platform.getDirectoryPath(
                                dialogTitle: _text('选择存储文件夹', 'Select Folder'),
                              );
                              await windowManager.setAlwaysOnTop(true);
                              if (sel != null) {
                                setDialogState(() {
                                  customPath = sel.replaceAll('\\', '/');
                                });
                              }
                            },
                            child: Text(_text('浏览', 'Browse'), style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _text('数据初始化模式', 'Data Initialization'),
                        style: TextStyle(fontSize: 12, color: _isDarkTheme ? Colors.white70 : Colors.black54),
                      ),
                      RadioListTile<WorkspaceInitType>(
                        value: WorkspaceInitType.blank,
                        groupValue: initType,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_text('全新空白工作区（推荐）', 'Blank Workspace (Recommended)'), style: const TextStyle(fontSize: 12)),
                        subtitle: Text(_text('创建干净的空文件夹，不含历史数据', 'Create empty directory with no legacy data'), style: const TextStyle(fontSize: 10)),
                        onChanged: (v) => setDialogState(() => initType = v!),
                      ),
                      RadioListTile<WorkspaceInitType>(
                        value: WorkspaceInitType.copy,
                        groupValue: initType,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_text('复制当前工作区数据', 'Copy Current Data'), style: const TextStyle(fontSize: 12)),
                        subtitle: Text(_text('将现有的便签、剪贴板等副本拷贝到新工作区', 'Clone existing notes & clipboards into new folder'), style: const TextStyle(fontSize: 10)),
                        onChanged: (v) => setDialogState(() => initType = v!),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: inheritCloud,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_text('继承当前云端同步设置 (Cloudflare)', 'Inherit Current Cloud Config'), style: const TextStyle(fontSize: 12)),
                        subtitle: Text(_text('若勾选，将绑定相同的 Worker 云节点；不勾选则为纯本地离线使用', 'If checked, links to same Worker; otherwise offline'), style: const TextStyle(fontSize: 10)),
                        onChanged: (v) => setDialogState(() => inheritCloud = v ?? false),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(_text('取消', 'Cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.of(ctx).pop();
                    final created = await widget.state.createWorkspace(
                      name: name,
                      customPath: customPath,
                      initType: initType,
                      inheritCloudConfig: inheritCloud,
                    );
                    if (mounted) {
                      setState(() {
                        _selectedWorkspaceId = created.id;
                        _dataSubTab = 0; // 新建后右侧先显示本地存储配置
                        _pendingDirectoryPath = null;
                        _detectedWorkspaceProfile = null;
                        _dataDirectory = widget.state.getDataDirectoryPathSync();
                        _cfD1WorkerUrlController.text = created.cfWorkerUrl ?? '';
                        _cfAccountIdController.text = created.cfAccountId ?? '';
                        _cfApiTokenController.text = created.cfApiToken ?? '';
                        _cfD1DatabaseIdController.text = created.cfD1DatabaseId ?? '';
                        _cfR2BucketNameController.text = created.cfR2BucketName ?? '';
                        _cfD1AutoSync = created.cfD1AutoSync;
                        _cfD1SyncIntervalMinutes = created.cfD1SyncIntervalMinutes;
                        _isWorkerOnline = null;
                        _workerPingRtt = null;
                      });
                    }
                  },
                  child: Text(_text('创建并切换', 'Create & Switch')),
                ),
              ],
            );
          },
        );
      },
    );
    widget.state.setDialogOpen(false);
  }

  Future<void> _showNotesBackupDialog({WorkspaceProfile? workspace}) async {
    final targetWs = workspace ?? _selectedWorkspace;
    final isCurrent = targetWs.id == widget.state.currentWorkspace.id;
    widget.state.setDialogOpen(true);
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final backups = widget.state.getNotesBackups(customDir: targetWs.directoryPath);
            return AlertDialog(
              backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
              title: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 20, color: Color(0xFF007AFF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _text('【${targetWs.name}】便签本地历史快照与安全恢复', 'Notes Snapshots & Recovery [${targetWs.name}]'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _isDarkTheme ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 560,
                height: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(
                        '系统在应用启动、每次同步前以及合并冲突时均会自动为便签生成本地快照备份（保留最新 5 份）。所有快照均支持查看内容预览并一键无损还原。',
                        'Local snapshots are auto-created at launch, pre-sync, and conflict merge (up to 5 copies). All snapshots support full content preview and 1-click restore.',
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: _isDarkTheme ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          isCurrent
                              ? _text('当前有效便签: ${widget.state.notes.length} 条', 'Active Notes: ${widget.state.notes.length}')
                              : _text('工作区目录: ${targetWs.directoryPath}', 'Directory: ${targetWs.directoryPath}'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isDarkTheme ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () async {
                            final backupDir = Directory('${targetWs.directoryPath}/backups/notes');
                            if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
                            await widget.state.openDirectoryPath(backupDir.path);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF007AFF)),
                                const SizedBox(width: 3),
                                Text(
                                  _text('打开快照文件夹', 'Open Backups Folder'),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF007AFF), fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    Expanded(
                      child: backups.isEmpty
                          ? Center(
                              child: Text(
                                _text('暂无历史快照', 'No snapshots found'),
                                style: TextStyle(fontSize: 12, color: _isDarkTheme ? Colors.white38 : Colors.black38),
                              ),
                            )
                          : ListView.separated(
                              itemCount: backups.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (itemCtx, index) {
                                final b = backups[index];
                                final name = b['fileName'] as String? ?? '';
                                final count = b['count'] as int? ?? 0;
                                final modified = b['modified'] as DateTime? ?? DateTime.now();
                                final path = b['path'] as String? ?? '';
                                final sizeKb = ((b['size'] as int? ?? 0) / 1024).toStringAsFixed(1);
                                final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(modified);

                                String reasonTag = '';
                                if (name.contains('conflict_merged')) {
                                  reasonTag = _text('网盘冲突合并', 'Conflict Merged');
                                } else if (name.contains('pre_sync')) {
                                  reasonTag = _text('同步前置备份', 'Pre-Sync');
                                } else if (name.contains('cloud_merged')) {
                                  reasonTag = _text('云端同步后', 'Cloud Merged');
                                } else if (name.contains('app_launch')) {
                                  reasonTag = _text('应用启动快照', 'Launch');
                                } else if (name.contains('before_restore')) {
                                  reasonTag = _text('恢复前保护', 'Pre-Restore');
                                } else if (name.contains('recovered')) {
                                  reasonTag = _text('灾备自愈恢复', 'Disaster Recovered');
                                } else if (name.contains('manual')) {
                                  reasonTag = _text('手动备份', 'Manual');
                                } else {
                                  reasonTag = _text('自动定时快照', 'Auto-Save');
                                }

                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  leading: const Icon(Icons.description_outlined, size: 18, color: Color(0xFF007AFF)),
                                  title: Row(
                                    children: [
                                      Text(
                                        '$count ${_text("条便签", "notes")}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _isDarkTheme ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          reasonTag,
                                          style: const TextStyle(fontSize: 9.5, color: Color(0xFF007AFF), fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '$timeStr (${sizeKb}KB)',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: _isDarkTheme ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _showSnapshotPreviewDialog(
                                          filePath: path,
                                          fileName: name,
                                          modified: modified,
                                          reasonTag: reasonTag,
                                          targetWorkspace: targetWs,
                                          accentColor: const Color(0xFF007AFF),
                                          textColor: _isDarkTheme ? Colors.white : Colors.black87,
                                          subColor: _isDarkTheme ? Colors.white60 : Colors.black54,
                                        ),
                                        icon: const Icon(Icons.visibility_outlined, size: 12),
                                        label: Text(_text('预览', 'Preview'), style: const TextStyle(fontSize: 10.5)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF007AFF),
                                          side: const BorderSide(color: Color(0xFF007AFF), width: 0.8),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          minimumSize: const Size(0, 26),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      ElevatedButton(
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (c) => AlertDialog(
                                              backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
                                              title: Text(_text('确认恢复此快照？', 'Restore Snapshot?')),
                                              content: Text(_text(
                                                '即将恢复包含 $count 条便签的快照（时间: $timeStr）到工作区【${targetWs.name}】。\n系统在恢复前会自动为当前便签再备份一份，确保安全。',
                                                'Restore snapshot with $count notes ($timeStr) into workspace [${targetWs.name}]? Current notes will be backed up.',
                                              )),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(c).pop(false),
                                                  child: Text(_text('取消', 'Cancel')),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.of(c).pop(true),
                                                  child: Text(_text('确认恢复', 'Restore')),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok == true) {
                                            final res = await widget.state.restoreNotesFromBackup(path, targetDir: targetWs.directoryPath);
                                            if (res && mounted) {
                                              setDialogState(() {});
                                              setState(() {});
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(_text('🎉 成功恢复 $count 条便签至【${targetWs.name}】！', 'Successfully restored $count notes to [${targetWs.name}]!')),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          minimumSize: const Size(0, 26),
                                        ),
                                        child: Text(_text('恢复', 'Restore'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(_text('关闭', 'Close')),
                ),
              ],
            );
          },
        );
      },
    );
    widget.state.setDialogOpen(false);
  }

  Future<void> _showSnapshotPreviewDialog({
    required String filePath,
    required String fileName,
    required DateTime modified,
    required String reasonTag,
    required WorkspaceProfile targetWorkspace,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) async {
    final notes = widget.state.previewNotesBackup(filePath);
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(modified);

    await showDialog(
      context: context,
      builder: (ctx) {
        String filterText = '';
        Note? selectedNote = notes.isNotEmpty ? notes.first : null;

        return StatefulBuilder(
          builder: (previewCtx, setPreviewState) {
            final filtered = notes.where((n) {
              if (filterText.isEmpty) return true;
              return n.title.toLowerCase().contains(filterText.toLowerCase()) ||
                  n.content.toLowerCase().contains(filterText.toLowerCase());
            }).toList();

            if (selectedNote != null && !filtered.contains(selectedNote) && filtered.isNotEmpty) {
              selectedNote = filtered.first;
            }

            return AlertDialog(
              backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.visibility_rounded, size: 18, color: accentColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _text('快照内容预览', 'Snapshot Content Preview'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _isDarkTheme ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${notes.length} ${_text("条便签", "notes")}',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: accentColor),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _isDarkTheme ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                reasonTag,
                                style: TextStyle(fontSize: 10, color: subColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_text("快照时间", "Time")}: $timeStr · ${_text("工作区", "Workspace")}: ${targetWorkspace.name}',
                          style: TextStyle(fontSize: 10.5, color: subColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 760,
                height: 480,
                child: Row(
                  children: [
                    // 左侧：便签列表与搜索
                    SizedBox(
                      width: 280,
                      child: Column(
                        children: [
                          Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: _isDarkTheme ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _isDarkTheme ? Colors.white12 : Colors.black12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                Icon(Icons.search, size: 14, color: subColor),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    style: TextStyle(fontSize: 11, color: textColor),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      hintText: _text('搜索此快照中的便签...', 'Search notes in snapshot...'),
                                      hintStyle: TextStyle(fontSize: 11, color: subColor),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 7),
                                    ),
                                    onChanged: (val) {
                                      setPreviewState(() => filterText = val.trim());
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      _text('无匹配便签', 'No matching notes'),
                                      style: TextStyle(fontSize: 11, color: subColor),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 3),
                                    itemBuilder: (c, idx) {
                                      final note = filtered[idx];
                                      final isSelected = selectedNote?.id == note.id;
                                      final noteTimeStr = DateFormat('MM-dd HH:mm').format(note.updatedAt);
                                      final snippet = note.content.trim().replaceAll('\n', ' ');
                                      return InkWell(
                                        onTap: () => setPreviewState(() => selectedNote = note),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? accentColor.withValues(alpha: 0.15)
                                                : (_isDarkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSelected ? accentColor.withValues(alpha: 0.5) : Colors.transparent,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      note.title.trim().isEmpty ? _text('未命名便签', 'Untitled') : note.title,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: isSelected ? accentColor : textColor,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text(
                                                    noteTimeStr,
                                                    style: TextStyle(fontSize: 9.5, color: subColor),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                snippet.isEmpty ? _text('（无内容）', '(Empty)') : snippet,
                                                style: TextStyle(fontSize: 10, color: subColor),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 12),
                    // 右侧：当前选中便签的完整内容与详情
                    Expanded(
                      child: selectedNote == null
                          ? Center(
                              child: Text(
                                _text('请选择左侧便签查看详情', 'Select a note on left to preview'),
                                style: TextStyle(fontSize: 12, color: subColor),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        selectedNote!.title.trim().isEmpty ? _text('未命名便签', 'Untitled') : selectedNote!.title,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _isDarkTheme ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${selectedNote!.content.length} ${_text("字符", "chars")}',
                                        style: TextStyle(fontSize: 9.5, color: subColor),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${_text("创建于", "Created")}: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedNote!.createdAt)}',
                                      style: TextStyle(fontSize: 10, color: subColor),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${_text("更新于", "Updated")}: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedNote!.updatedAt)}',
                                      style: TextStyle(fontSize: 10, color: subColor),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Divider(height: 1),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _isDarkTheme ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _isDarkTheme ? Colors.white10 : Colors.black12),
                                    ),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        selectedNote!.content.isEmpty ? _text('（便签正文为空）', '(Empty content)') : selectedNote!.content,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.5,
                                          color: selectedNote!.content.isEmpty ? subColor : textColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(previewCtx).pop(),
                  child: Text(_text('关闭', 'Close'), style: TextStyle(color: subColor)),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
                        title: Text(_text('确认恢复此快照？', 'Restore Snapshot?')),
                        content: Text(_text(
                          '即将恢复包含 ${notes.length} 条便签的快照到工作区【${targetWorkspace.name}】。\n系统会自动备份当前便签，安全无忧。',
                          'Restore snapshot with ${notes.length} notes into workspace [${targetWorkspace.name}]? Current notes will be backed up.',
                        )),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(_text('取消', 'Cancel'))),
                          ElevatedButton(
                            onPressed: () => Navigator.of(c).pop(true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            child: Text(_text('确认恢复', 'Restore')),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      final ok = await widget.state.restoreNotesFromBackup(filePath, targetDir: targetWorkspace.directoryPath);
                      if (ok && mounted) {
                        Navigator.of(previewCtx).pop();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_text('🎉 成功将快照恢复至【${targetWorkspace.name}】（共 ${notes.length} 条便签）！', 'Restored ${notes.length} notes to [${targetWorkspace.name}]!')),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.restore_rounded, size: 14),
                  label: Text(
                    _text('恢复此快照 (${notes.length} 条便签)', 'Restore Snapshot (${notes.length} notes)'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _save({bool closeAfterSave = true}) async {
    final isActiveSelected = _selectedWorkspaceId == widget.state.currentWorkspace.id;
    final oldDir = widget.state.getDataDirectoryPathSync();
    final isDirChanged = isActiveSelected && (_dataDirectory.toLowerCase() != oldDir.toLowerCase());

    final updated = AppSettings(
      triggerMode: _triggerMode,
      hotkey: _hotkey,
      invertScrollDirection: _invertScrollDirection,
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
      cfWorkerUrl: isActiveSelected ? _cfD1WorkerUrlController.text.trim() : widget.state.settings.cfWorkerUrl,
      cfD1Mode: _cfD1Mode,
      cfAccountId: isActiveSelected ? _cfAccountIdController.text.trim() : widget.state.settings.cfAccountId,
      cfApiToken: isActiveSelected ? _cfApiTokenController.text.trim() : widget.state.settings.cfApiToken,
      cfD1DatabaseId: isActiveSelected ? _cfD1DatabaseIdController.text.trim() : widget.state.settings.cfD1DatabaseId,
      cfR2BucketName: isActiveSelected ? _cfR2BucketNameController.text.trim() : widget.state.settings.cfR2BucketName,
      cfD1AutoSync: isActiveSelected ? _cfD1AutoSync : widget.state.settings.cfD1AutoSync,
      cfD1SyncIntervalMinutes: isActiveSelected ? _cfD1SyncIntervalMinutes : widget.state.settings.cfD1SyncIntervalMinutes,
      activeWorkspaceId: _selectedWorkspaceId,
      vaultId: _selectedWorkspace.vaultId,
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
        // 仅更改路径 (不迁移数据)：自动切断并关闭云端同步，防止新空目录误操作触发同步
        final updatedSettings = updated.copyWith(
          dataDirectory: _dataDirectory,
          cfD1AutoSync: false,
        );
        setState(() {
          _cfD1AutoSync = false;
        });
        await widget.state.updateSettings(updatedSettings);
        await widget.state.reloadAllData();
      }
    } else {
      await widget.state.updateSettings(updated);
    }

    final curWs = _selectedWorkspace;
    await widget.state.saveWorkspaceProfile(
      curWs.copyWith(
        directoryPath: curWs.id == widget.state.currentWorkspace.id ? _dataDirectory : curWs.directoryPath,
        cfWorkerUrl: _cfD1WorkerUrlController.text.trim(),
        cfAccountId: _cfAccountIdController.text.trim(),
        cfApiToken: _cfApiTokenController.text.trim(),
        cfD1DatabaseId: _cfD1DatabaseIdController.text.trim(),
        cfR2BucketName: _cfR2BucketNameController.text.trim(),
        cfD1AutoSync: _cfD1AutoSync,
        cfD1SyncIntervalMinutes: _cfD1SyncIntervalMinutes,
      ),
    );

    if (closeAfterSave && mounted) {
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

  // ===========================================================================
  // macOS Finder 分栏风格 (Miller Columns)：从左往右逐级延展
  // 第 1 栏：一级分类 -> 第 2 栏：二级子项 -> 第 3 栏：具体配置 -> 第 4 栏：扩展子配置
  // ===========================================================================

  Widget _buildWideLayout(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
    double width,
  ) {
    final borderColor = _isDarkTheme
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final isDataTab = _settingsTab == 3;
    final hasCol4 = isDataTab || _fourthColumnType != null;

    const col1Width = 175.0;
    final col2Width = isDataTab ? 230.0 : 220.0;
    final col3Width = isDataTab ? 200.0 : (hasCol4 ? 360.0 : 420.0);
    final col4Width = isDataTab ? 430.0 : 340.0;
    final totalMinWidth =
        col1Width + col2Width + col3Width + (hasCol4 ? col4Width : 0.0);

    final columnsRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 第 1 栏：一级主设置分类
        _buildFirstColumn(
          width: col1Width,
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          borderColor: borderColor,
        ),

        // 第 2 栏：当前主分类下的二级子项列表
        _buildSecondColumn(
          width: col2Width,
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          borderColor: borderColor,
        ),

        // 第 3 栏：选中子项的配置面板（若某项含子配置，点击可继续向右延展第 4 栏）
        _buildThirdColumn(
          width: col3Width,
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          dropdownBg: dropdownBg,
          borderColor: borderColor,
        ),

        // 第 4 栏：按需向右延展的子级配置/详情面板
        if (hasCol4)
          _buildFourthColumn(
            width: col4Width,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            dropdownBg: dropdownBg,
            borderColor: borderColor,
          ),

        // 右侧剩余留白区域（保持分栏整齐感）
        if (width > totalMinWidth)
          Expanded(
            child: _buildTrailingColumnSpace(
              accentColor: accentColor,
              textColor: textColor,
              subColor: subColor,
              borderColor: borderColor,
            ),
          ),
      ],
    );

    if (width < totalMinWidth) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: SizedBox(
          width: totalMinWidth,
          child: columnsRow,
        ),
      );
    }
    return columnsRow;
  }

  Widget _buildFirstColumn({
    required double width,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color borderColor,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.black.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.35),
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部栏：返回 + 标题
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () async => await _save(),
                  borderRadius: BorderRadius.circular(5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, size: 14, color: accentColor),
                        const SizedBox(width: 3),
                        Text(
                          _text('返回', 'Back'),
                          style: TextStyle(
                            fontSize: 11.5,
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
                  _text('设置', 'Settings'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),

          // 一级分类列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: [
                _buildSidebarNavItem(
                  index: 0,
                  icon: Icons.tune_rounded,
                  label: _text('通用设置', 'General'),
                  accentColor: accentColor,
                  textColor: textColor,
                  subColor: subColor,
                ),
                const SizedBox(height: 3),
                _buildSidebarNavItem(
                  index: 1,
                  icon: Icons.dashboard_customize_outlined,
                  label: _text('面板外观', 'Panel & Layout'),
                  accentColor: accentColor,
                  textColor: textColor,
                  subColor: subColor,
                ),
                const SizedBox(height: 3),
                _buildSidebarNavItem(
                  index: 2,
                  icon: Icons.article_outlined,
                  label: _text('内容与剪贴板', 'Content'),
                  accentColor: accentColor,
                  textColor: textColor,
                  subColor: subColor,
                ),
                const SizedBox(height: 3),
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

          // 底部版本与保存按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PodQuick v${UpdateService.currentVersion}',
                  style: TextStyle(fontSize: 10, color: subColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                ElevatedButton.icon(
                  onPressed: () async => await _save(),
                  icon: const Icon(Icons.check_rounded, size: 13),
                  label: Text(
                    _text('保存设置', 'Save Settings'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(0, 28),
                    elevation: 0,
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
    );
  }

  Widget _buildSecondColumn({
    required double width,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color borderColor,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.black.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.2),
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第 2 栏顶部标题
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: _settingsTab == 3
                ? Row(
                    children: [
                      Icon(Icons.workspaces_outlined, size: 14, color: accentColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _text('工作区', 'Workspaces'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _showCreateWorkspaceDialog,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, size: 14, color: accentColor),
                              const SizedBox(width: 2),
                              Text(
                                _text('新建', 'New'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text(
                        _tabFullLabel(_settingsTab),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
          ),

          // 第 2 栏子菜单项列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(6),
              children: _buildSecondColumnItems(
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThirdColumn({
    required double width,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color dropdownBg,
    required Color borderColor,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.black.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.1),
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第 3 栏顶部标题
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                if (_settingsTab == 3) ...[
                  Icon(Icons.storage_rounded, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    _thirdColumnTitle(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_settingsTab != 3 && _fourthColumnType == null)
                  ElevatedButton(
                    onPressed: () async => await _save(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      elevation: 0,
                    ),
                    child: Text(_text('保存', 'Save'), style: const TextStyle(fontSize: 10.5)),
                  ),
              ],
            ),
          ),

          // 第 3 栏配置内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              physics: const ClampingScrollPhysics(),
              child: _buildThirdColumnBody(
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
                dropdownBg: dropdownBg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFourthColumn({
    required double width,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color dropdownBg,
    required Color borderColor,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.white.withValues(alpha: 0.015)
            : Colors.black.withValues(alpha: 0.015),
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第 4 栏顶部标题 + 收起/保存按钮
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                if (_fourthColumnType != null) ...[
                  InkWell(
                    onTap: () => setState(() {
                      _fourthColumnType = null;
                      _isEditingWorker = false;
                    }),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.arrow_back_rounded, size: 15, color: accentColor),
                    ),
                  ),
                  const SizedBox(width: 4),
                ] else ...[
                  Icon(
                    _settingsTab == 3
                        ? (_dataSubTab == 0
                            ? Icons.folder_outlined
                            : (_dataSubTab == 1 ? Icons.history_rounded : Icons.cloud_outlined))
                        : Icons.subdirectory_arrow_right_rounded,
                    size: 14,
                    color: accentColor,
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    _fourthColumnTitle(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_settingsTab == 3 && _dataSubTab == 2) ...[
                  InkWell(
                    onTap: () => GlobalSyncLogDialog.show(context, state: widget.state),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 13, color: subColor),
                          const SizedBox(width: 3),
                          Text(
                            _text('同步日志', 'Logs'),
                            style: TextStyle(fontSize: 10.5, color: subColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (_settingsTab == 3 || _fourthColumnType == null) ...[
                  ElevatedButton(
                    onPressed: () async => await _save(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      elevation: 0,
                    ),
                    child: Text(_text('保存', 'Save'), style: const TextStyle(fontSize: 10.5)),
                  ),
                ] else if (_fourthColumnType != null) ...[
                  InkWell(
                    onTap: () => setState(() {
                      _fourthColumnType = null;
                      _isEditingWorker = false;
                    }),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.close_rounded, size: 15, color: subColor),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 第 4 栏配置详情
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              physics: const ClampingScrollPhysics(),
              child: _buildFourthColumnBody(
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
                dropdownBg: dropdownBg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailingColumnSpace({
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color borderColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerRight,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: _fourthColumnType != null
              ? ElevatedButton(
                  onPressed: () async => await _save(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    elevation: 0,
                  ),
                  child: Text(_text('保存', 'Save'), style: const TextStyle(fontSize: 10.5)),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Center(
            child: Opacity(
              opacity: 0.22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.view_column_rounded, size: 28, color: subColor),
                  const SizedBox(height: 4),
                  Text(
                    'PodQuick',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
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
        _fourthColumnType = null;
      }),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: _isDarkTheme ? 0.22 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border.all(color: accentColor.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? accentColor : subColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected
                      ? (_isDarkTheme ? Colors.white : accentColor)
                      : textColor,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: selected ? accentColor : subColor.withValues(alpha: 0.5),
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
    Widget? headerTrailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.025),
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
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: textColor ?? Colors.white,
                  ),
                ),
                if (headerTrailing != null) ...[
                  const Spacer(),
                  headerTrailing,
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }

  // ===========================================================================
  // 第 2 栏、第 3 栏、第 4 栏的具体内容构建器
  // ===========================================================================

  String _tabFullLabel(int index) {
    return switch (index) {
      0 => _text('通用设置', 'General'),
      1 => _text('面板外观', 'Panel & Layout'),
      2 => _text('内容与剪贴板', 'Content & Clipboard'),
      _ => _text('数据存储与同步', 'Data & Sync'),
    };
  }

  String _cloudStatusSummary() {
    if (_isTestingCfD1) return _text('正在检测连接...', 'Testing...');
    if (_cfD1WorkerUrlController.text.trim().isEmpty) {
      return _text('未配置云端节点', 'Not configured');
    }
    final wsOnline = widget.state.getWorkspaceCloudOnline(_selectedWorkspace.id) ?? _isWorkerOnline;
    final isCur = _selectedWorkspace.id == widget.state.currentWorkspace.id;
    if (wsOnline == true || (isCur && (widget.state.lastD1SyncSuccess == true || widget.state.isD1Syncing))) {
      final rtt = (_workerPingRtt ?? widget.state.getWorkspacePingRtt(_selectedWorkspace.id));
      final rttStr = rtt != null ? ' (${rtt.toStringAsFixed(0)}ms)' : '';
      return _text('已连接$rttStr', 'Connected$rttStr');
    }
    if (wsOnline == false) {
      return _text('连接未响应', 'Unreachable');
    }
    return _text('已配置 (待测试)', 'Configured');
  }

  Color _cloudStatusDotColor() {
    if (_cfD1WorkerUrlController.text.trim().isEmpty) return Colors.grey;
    final wsOnline = widget.state.getWorkspaceCloudOnline(_selectedWorkspace.id) ?? _isWorkerOnline;
    final isCur = _selectedWorkspace.id == widget.state.currentWorkspace.id;
    if (wsOnline == true || (isCur && (widget.state.lastD1SyncSuccess == true || widget.state.isD1Syncing))) {
      return Colors.green;
    }
    if (wsOnline == false) return Colors.redAccent;
    return Colors.orangeAccent;
  }

  List<Widget> _buildSecondColumnItems({
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    if (_settingsTab == 0) {
      return [
        _buildSecondColumnItem(
          selected: _generalSubTab == 0,
          icon: Icons.translate_rounded,
          title: _text('语言与唤醒', 'Language & Wake'),
          subtitle: '${_languageLabel(_languageCode)} · ${_getTriggerModeLabel(_triggerMode)}',
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _generalSubTab = 0;
            _savedGeneralSubTab = 0;
            _fourthColumnType = null;
          }),
        ),
        const SizedBox(height: 3),
        _buildSecondColumnItem(
          selected: _generalSubTab == 1,
          icon: Icons.keyboard_rounded,
          title: _text('全局快捷键', 'Global Hotkey'),
          subtitle: _hotkey.toUpperCase().replaceAll('+', ' + '),
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _generalSubTab = 1;
            _savedGeneralSubTab = 1;
            _fourthColumnType = null;
          }),
        ),
        const SizedBox(height: 3),
        _buildSecondColumnItem(
          selected: _generalSubTab == 2,
          icon: Icons.timer_outlined,
          title: _text('悬停与自动收起', 'Hover & Collapse'),
          subtitle: '${_hoverTimeout.toInt()}ms · ${_autoCollapseDelay == 0 ? _text('点外部即收', 'Immediate') : '${_autoCollapseDelay}s'}',
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _generalSubTab = 2;
            _savedGeneralSubTab = 2;
            _fourthColumnType = null;
          }),
        ),
        const SizedBox(height: 3),
        _buildSecondColumnItem(
          selected: _generalSubTab == 3,
          icon: Icons.system_update_rounded,
          title: _text('软件更新', 'Software Update'),
          subtitle: 'v${UpdateService.currentVersion}',
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _generalSubTab = 3;
            _savedGeneralSubTab = 3;
            _fourthColumnType = null;
          }),
        ),
      ];
    } else if (_settingsTab == 1) {
      return [
        _buildSecondColumnItem(
          selected: _panelSubTab == 0,
          icon: Icons.aspect_ratio_rounded,
          title: _text('尺寸与透明度', 'Size & Opacity'),
          subtitle: '${_isWidthPercentage ? '${_panelWidthPercent.toInt()}%' : '${_panelWidth.toInt()}px'} · ${(_backdropOpacity * 100).round()}%',
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _panelSubTab = 0;
            _savedPanelSubTab = 0;
            _fourthColumnType = null;
          }),
        ),
        const SizedBox(height: 3),
        _buildSecondColumnItem(
          selected: _panelSubTab == 1,
          icon: Icons.palette_outlined,
          title: _text('主题与配色', 'Theme & Color'),
          subtitle: _isDarkTheme ? _text('深色主题', 'Dark Theme') : _text('浅色主题', 'Light Theme'),
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _panelSubTab = 1;
            _savedPanelSubTab = 1;
            _fourthColumnType = null;
          }),
        ),
        const SizedBox(height: 3),
        _buildSecondColumnItem(
          selected: _panelSubTab == 2,
          icon: Icons.drag_indicator_rounded,
          title: _text('核心区域顺序', 'Section Order'),
          subtitle: _panelOrder.map(_getPanelPaneLabel).join(' → '),
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _panelSubTab = 2;
            _savedPanelSubTab = 2;
            _fourthColumnType = null;
          }),
        ),
      ];
    } else if (_settingsTab == 2) {
      return [
        _buildSecondColumnItem(
          selected: _contentSubTab == 0,
          icon: Icons.history_rounded,
          title: _text('剪贴板记录上限', 'Clipboard Limit'),
          subtitle: '$_clipboardHistoryLimit ${_text('条历史记录', 'items')}',
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          onTap: () => setState(() {
            _contentSubTab = 0;
            _savedContentSubTab = 0;
            _fourthColumnType = null;
          }),
        ),
      ];
    } else {
      // TAB 3: 数据存储与同步 -> 第一列显示：列出所有工作区，并提供切换按钮
      return widget.state.workspaces.map((ws) {
        final isSelected = ws.id == _selectedWorkspaceId;
        final isCurrent = ws.id == widget.state.currentWorkspace.id;
        return _buildWorkspaceColumnItem(
          ws: ws,
          isSelected: isSelected,
          isCurrent: isCurrent,
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
        );
      }).toList();
    }
  }

  Future<void> _switchToWorkspace(String wsId) async {
    await widget.state.switchWorkspace(wsId);
    if (!mounted) return;
    _selectWorkspace(wsId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_text('已切换至工作区【${widget.state.currentWorkspace.name}】', 'Switched to workspace: ${widget.state.currentWorkspace.name}')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _selectWorkspace(String wsId) {
    setState(() {
      _selectedWorkspaceId = wsId;
      _dataSubTab = 0; // 点击工作区，右侧默认先展示本地存储配置
      _pendingDirectoryPath = null;
      _detectedWorkspaceProfile = null;
      _isEditingWorker = false;
      final target = _selectedWorkspace;
      if (wsId == widget.state.currentWorkspace.id) {
        _dataDirectory = widget.state.getDataDirectoryPathSync();
        _cfD1WorkerUrlController.text = widget.state.settings.cfWorkerUrl;
        _cfAccountIdController.text = widget.state.settings.cfAccountId ?? '';
        _cfApiTokenController.text = widget.state.settings.cfApiToken ?? '';
        _cfD1DatabaseIdController.text = widget.state.settings.cfD1DatabaseId ?? '';
        _cfR2BucketNameController.text = widget.state.settings.cfR2BucketName ?? '';
        _cfD1AutoSync = widget.state.settings.cfD1AutoSync;
        _cfD1SyncIntervalMinutes = widget.state.settings.cfD1SyncIntervalMinutes;
      } else {
        // 仅查看/配置非激活工作区，严禁污染当前激活工作区的 _dataDirectory
        _cfD1WorkerUrlController.text = target.cfWorkerUrl ?? '';
        _cfAccountIdController.text = target.cfAccountId ?? '';
        _cfApiTokenController.text = target.cfApiToken ?? '';
        _cfD1DatabaseIdController.text = target.cfD1DatabaseId ?? '';
        _cfR2BucketNameController.text = target.cfR2BucketName ?? '';
        _cfD1AutoSync = target.cfD1AutoSync;
        _cfD1SyncIntervalMinutes = target.cfD1SyncIntervalMinutes;
      }
      // 保留并读取工作区上次持久化的连通状态与 RTT，避免每次切换被重置为“待测试”
      _isWorkerOnline = widget.state.getWorkspaceCloudOnline(wsId);
      _workerPingRtt = widget.state.getWorkspacePingRtt(wsId);
    });

    // 后台静默健康检测（带 5 分钟节流，绝不弹窗打扰）
    final target = _selectedWorkspace;
    if (target.cfWorkerUrl != null && target.cfWorkerUrl!.trim().isNotEmpty) {
      widget.state.silentCheckWorkspaceHealth(target).then((_) {
        if (mounted && _selectedWorkspaceId == wsId) {
          setState(() {
            _isWorkerOnline = widget.state.getWorkspaceCloudOnline(wsId);
            _workerPingRtt = widget.state.getWorkspacePingRtt(wsId);
          });
        }
      });
    }
  }

  void _startInlineRename(WorkspaceProfile ws) {
    setState(() {
      _editingWorkspaceId = ws.id;
      _inlineRenameController.text = ws.name;
      _inlineRenameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: ws.name.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inlineRenameFocusNode.requestFocus();
    });
  }

  Future<void> _commitInlineRename(String wsId) async {
    final newName = _inlineRenameController.text.trim();
    if (newName.isNotEmpty) {
      await widget.state.renameWorkspace(wsId, newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text('工作区已更名为【$newName】', 'Workspace renamed to [$newName]')),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) {
      setState(() {
        _editingWorkspaceId = null;
      });
    }
  }

  void _cancelInlineRename() {
    if (mounted) {
      setState(() {
        _editingWorkspaceId = null;
      });
    }
  }

  Future<void> _deleteWorkspaceConfirm(WorkspaceProfile ws) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(_text('确认删除工作区？', 'Delete Workspace?'), style: TextStyle(color: _isDarkTheme ? Colors.white : Colors.black87)),
        content: Text(
          _text('确定要从列表中移除工作区【${ws.name}】吗？本地已有文件不会被强行销毁。', 'Remove workspace【${ws.name}】? Local files will remain.'),
          style: TextStyle(color: _isDarkTheme ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(_text('取消', 'Cancel'))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(_text('删除', 'Delete'), style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) {
      await widget.state.deleteWorkspace(ws.id);
      if (mounted) {
        _selectWorkspace(widget.state.currentWorkspace.id);
      }
    }
  }

  Widget _buildWorkspaceColumnItem({
    required WorkspaceProfile ws,
    required bool isSelected,
    required bool isCurrent,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final isEditing = _editingWorkspaceId == ws.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? accentColor.withValues(alpha: _isDarkTheme ? 0.2 : 0.1)
            : (_isDarkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.025)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? accentColor.withValues(alpha: 0.5)
              : (_isDarkTheme ? Colors.white10 : Colors.black12),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: isEditing ? null : () => _selectWorkspace(ws.id),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isEditing)
                  Row(
                    children: [
                      Icon(
                        Icons.workspaces_outlined,
                        size: 15,
                        color: accentColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SizedBox(
                          height: 26,
                          child: TextField(
                            controller: _inlineRenameController,
                            focusNode: _inlineRenameFocusNode,
                            autofocus: true,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: accentColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: accentColor.withValues(alpha: 0.7)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: accentColor, width: 1.5),
                              ),
                            ),
                            onSubmitted: (_) => _commitInlineRename(ws.id),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // √ 确认
                      Tooltip(
                        message: _text('保存名称', 'Save name'),
                        child: InkWell(
                          onTap: () => _commitInlineRename(ws.id),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.check_rounded, size: 17, color: Colors.green),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      // × 取消
                      Tooltip(
                        message: _text('取消', 'Cancel'),
                        child: InkWell(
                          onTap: _cancelInlineRename,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(Icons.close_rounded, size: 17, color: subColor),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.workspaces_outlined,
                        size: 15,
                        color: isSelected ? accentColor : subColor,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          ws.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? (_isDarkTheme ? Colors.white : accentColor) : textColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 13.5),
                        tooltip: _text('重命名', 'Rename'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        splashRadius: 13,
                        color: subColor.withValues(alpha: 0.7),
                        hoverColor: accentColor.withValues(alpha: 0.15),
                        onPressed: () => _startInlineRename(ws),
                      ),
                      if (widget.state.workspaces.length > 1) ...[
                        const SizedBox(width: 2),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 14),
                          tooltip: _text('删除工作区', 'Delete Workspace'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                          splashRadius: 13,
                          color: subColor.withValues(alpha: 0.6),
                          hoverColor: Colors.redAccent.withValues(alpha: 0.15),
                          onPressed: () => _deleteWorkspaceConfirm(ws),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ws.hasCloudConfig ? '☁️ 云端已绑定' : '💻 纯本地离线',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: subColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(
                              _text('当前激活', 'Active'),
                              style: const TextStyle(fontSize: 9.5, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    else
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: ElevatedButton.icon(
                          onPressed: () => _switchToWorkspace(ws.id),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 13),
                          label: Text(
                            _text('切换', 'Switch'),
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.hovered)) {
                                return accentColor.withValues(alpha: 0.85);
                              }
                              return accentColor;
                            }),
                            foregroundColor: const WidgetStatePropertyAll(Colors.white),
                            elevation: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.hovered)) return 2.5;
                              return 0.0;
                            }),
                            shadowColor: WidgetStatePropertyAll(accentColor.withValues(alpha: 0.5)),
                            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                            minimumSize: const WidgetStatePropertyAll(Size(0, 24)),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
                            mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
                          ),
                        ),
                      ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: isSelected ? accentColor : subColor.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

  Widget _buildSecondColumnItem({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    Color? statusDotColor,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: _isDarkTheme ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? accentColor : subColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                            color: selected
                                ? (_isDarkTheme ? Colors.white : accentColor)
                                : textColor,
                          ),
                        ),
                      ),
                      if (statusDotColor != null) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusDotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: selected ? accentColor : subColor.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }

  /// 在第 3 栏中构建可向右延展打开第 4 栏的入口行
  Widget _buildExtendableOptionRow({
    required String typeKey,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final active = _fourthColumnType == typeKey;
    return InkWell(
      onTap: () {
        setState(() {
          _fourthColumnType = active ? null : typeKey;
        });
      },
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? accentColor.withValues(alpha: _isDarkTheme ? 0.18 : 0.1)
              : (_isDarkTheme
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.025)),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active
                ? accentColor.withValues(alpha: 0.45)
                : (_isDarkTheme ? Colors.white12 : Colors.black12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: active ? accentColor : subColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active ? accentColor : textColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 9.5, color: subColor),
                  ),
                ],
              ),
            ),
            Icon(
              active ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              size: 16,
              color: active ? accentColor : subColor,
            ),
          ],
        ),
      ),
    );
  }

  String _thirdColumnTitle() {
    if (_settingsTab == 0) {
      return switch (_generalSubTab) {
        0 => _text('语言与唤醒', 'Language & Activation'),
        1 => _text('全局快捷键', 'Global Hotkey'),
        2 => _text('悬停与自动收起', 'Hover & Auto Collapse'),
        _ => _text('软件更新', 'Software Update'),
      };
    } else if (_settingsTab == 1) {
      return switch (_panelSubTab) {
        0 => _text('面板尺寸与透明度', 'Panel Dimensions & Opacity'),
        1 => _text('主题与配色', 'Theme & Accent Color'),
        _ => _text('核心区域顺序', 'Panel Section Order'),
      };
    } else if (_settingsTab == 2) {
      return _text('剪贴板记录上限', 'Clipboard History Limit');
    } else {
      return '${_selectedWorkspace.name} · ${_text('存储方式', 'Storage')}';
    }
  }

  Widget _buildThirdColumnBody({
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color dropdownBg,
  }) {
    if (_settingsTab == 0) {
      if (_generalSubTab == 0) {
        final hasExtraWakeParams = _triggerMode != TriggerMode.scrollOnly;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_text('界面语言', 'Language'), subColor),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _languageCode,
              dropdownColor: dropdownBg,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _isDarkTheme ? Colors.white24 : Colors.black12,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: accentColor),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: AppSettings.supportedLanguageCodes.map((code) {
                return DropdownMenuItem<String>(
                  value: code,
                  child: Text(_languageLabel(code), style: TextStyle(fontSize: 12, color: textColor)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _languageCode = val);
              },
            ),
            const SizedBox(height: 12),
            _sectionTitle(_text('唤醒方式', 'Activation Mode'), subColor),
            const SizedBox(height: 6),
            DropdownButtonFormField<TriggerMode>(
              value: _triggerMode,
              dropdownColor: dropdownBg,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: _isDarkTheme ? Colors.white24 : Colors.black12,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: accentColor),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: TriggerMode.values.map((mode) {
                return DropdownMenuItem<TriggerMode>(
                  value: mode,
                  child: Text(_getTriggerModeLabel(mode), style: TextStyle(fontSize: 12, color: textColor)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _triggerMode = val);
              },
            ),
            if (_triggerMode != TriggerMode.hotkeyOnly &&
                _triggerMode != TriggerMode.hoverOnly) ...[
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  _text('唤醒滚轮反向', 'Invert Scroll Wake Direction'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                ),
                subtitle: Text(
                  _text('开启后：下滚收起、上滚展开面板', 'Scroll down to collapse, up to expand'),
                  style: TextStyle(fontSize: 10.5, color: subColor),
                ),
                value: _invertScrollDirection,
                activeColor: accentColor,
                onChanged: (val) => setState(() => _invertScrollDirection = val),
              ),
            ],
            if (hasExtraWakeParams) ...[
              const SizedBox(height: 8),
              _buildExtendableOptionRow(
                typeKey: 'wake_params',
                icon: Icons.tune_rounded,
                title: _text('唤醒参数微调', 'Wake Parameters'),
                subtitle: _text('在右侧延展配置快捷键与边缘悬停延迟', 'Configure hotkey & hover delay on the right'),
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
              ),
            ],
          ],
        );
      } else if (_generalSubTab == 1) {
        return _buildHotkeyConfigContent(accentColor, textColor, subColor, dropdownBg);
      } else if (_generalSubTab == 2) {
        return _buildHoverCollapseConfigContent(accentColor, textColor, subColor);
      } else {
        return _buildSoftwareUpdateConfigContent(accentColor, textColor, subColor);
      }
    } else if (_settingsTab == 1) {
      if (_panelSubTab == 0) {
        return _buildDimensionsConfigContent(accentColor, textColor, subColor);
      } else if (_panelSubTab == 1) {
        return _buildThemeConfigContent(accentColor, textColor, subColor);
      } else {
        return _buildPanelOrderConfigContent(accentColor, textColor, subColor);
      }
    } else if (_settingsTab == 2) {
      return _buildClipboardLimitConfigContent(accentColor, textColor, subColor);
    } else {
      // TAB 3: 数据存储与同步 -> 第二列显示：本地存储、快照恢复、云端存储
      final snapshotCount = widget.state.getNotesBackupsCount(customDir: _selectedWorkspace.directoryPath);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSecondColumnItem(
            selected: _dataSubTab == 0,
            icon: Icons.folder_outlined,
            title: _text('本地存储', 'Local Storage'),
            subtitle: _text('保存目录、迁移导入与存储配置', 'Directory & Migration'),
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () => setState(() {
              _dataSubTab = 0;
              _savedDataSubTab = 0;
              _fourthColumnType = null;
            }),
          ),
          const SizedBox(height: 6),
          _buildSecondColumnItem(
            selected: _dataSubTab == 1,
            icon: Icons.history_rounded,
            title: _text('快照恢复', 'Snapshots & Recovery'),
            subtitle: snapshotCount == 0
                ? _text('暂无备份快照', 'No snapshots yet')
                : _text('$snapshotCount 份快照 · 预览与还原', '$snapshotCount snapshots · Preview & Restore'),
            statusDotColor: snapshotCount == 0 ? Colors.grey : Colors.green,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () => setState(() {
              _dataSubTab = 1;
              _savedDataSubTab = 1;
              _fourthColumnType = null;
            }),
          ),
          const SizedBox(height: 6),
          _buildSecondColumnItem(
            selected: _dataSubTab == 2,
            icon: Icons.cloud_outlined,
            title: _text('云端存储', 'Cloud Storage'),
            subtitle: _cloudStatusSummary(),
            statusDotColor: _cloudStatusDotColor(),
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () => setState(() {
              _dataSubTab = 2;
              _savedDataSubTab = 2;
              _fourthColumnType = null;
            }),
          ),
        ],
      );
    }
  }

  String _fourthColumnTitle() {
    if (_fourthColumnType == 'wake_params') return _text('唤醒方式详细参数', 'Wake Parameters');
    if (_fourthColumnType == 'local_merge') return _text('历史数据合并', 'Merge Historical Data');
    if (_fourthColumnType == 'worker_url') return _text('Worker 地址', 'Worker Address');
    if (_fourthColumnType == 'cf_auto_deploy') return _text('CF 自动部署', 'CF Auto Deploy');
    if (_settingsTab == 3) {
      if (_dataSubTab == 0) {
        return _text('本地存储配置 · ${_selectedWorkspace.name}', 'Local Storage · ${_selectedWorkspace.name}');
      }
      if (_dataSubTab == 1) {
        return _text('快照备份与恢复 · ${_selectedWorkspace.name}', 'Snapshots & Recovery · ${_selectedWorkspace.name}');
      }
      return _text('云端存储配置 · ${_selectedWorkspace.name}', 'Cloud Storage · ${_selectedWorkspace.name}');
    }
    return _text('详细配置', 'Details');
  }

  Widget _buildFourthColumnBody({
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Color dropdownBg,
  }) {
    if (_settingsTab == 3) {
      if (_fourthColumnType == 'local_merge') {
        return _buildLocalDataMergeContent(accentColor, textColor, subColor);
      }
      if (_fourthColumnType == 'cf_auto_deploy') {
        return _buildAutoDeployWorkerForm(
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          allowExtendFourthCol: false,
        );
      }
      if (_fourthColumnType == 'worker_url') {
        return _buildExistingWorkerForm(accentColor, textColor, subColor);
      }
      if (_dataSubTab == 0) {
        return _buildLocalStorageDetailsPane(accentColor, textColor, subColor, dropdownBg);
      } else if (_dataSubTab == 1) {
        return _buildSnapshotRecoveryPane(accentColor, textColor, subColor);
      } else {
        return _buildCloudStoragePane(accentColor, textColor, subColor, dropdownBg, isWide: true);
      }
    }

    switch (_fourthColumnType) {
      case 'wake_params':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_triggerMode != TriggerMode.hoverOnly &&
                _triggerMode != TriggerMode.scrollOnly) ...[
              _buildHotkeyConfigContent(accentColor, textColor, subColor, dropdownBg),
              const Divider(height: 20),
            ],
            _buildHoverCollapseConfigContent(accentColor, textColor, subColor),
          ],
        );
      case 'local_merge':
        return _buildLocalDataMergeContent(accentColor, textColor, subColor);
      case 'worker_url':
        return _buildExistingWorkerForm(accentColor, textColor, subColor);
      case 'cf_auto_deploy':
        return _buildAutoDeployWorkerForm(
          accentColor: accentColor,
          textColor: textColor,
          subColor: subColor,
          allowExtendFourthCol: false,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildInactiveWorkspaceNoticeBanner(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    if (_selectedWorkspace.id == widget.state.currentWorkspace.id) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: _isDarkTheme ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('正在查看【${_selectedWorkspace.name}】的配置', 'Viewing [${_selectedWorkspace.name}] config'),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 1),
                Text(
                  _text('当前未激活此工作区。本地数据未改动。', 'Inactive workspace. Local data remains unchanged.'),
                  style: TextStyle(fontSize: 10, color: subColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalStorageDetailsPane(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
  ) {
    final isCurrent = _selectedWorkspace.id == widget.state.currentWorkspace.id;
    final currentDir = _selectedWorkspace.directoryPath;
    final displayDirPath = _pendingDirectoryPath ?? (isCurrent ? _dataDirectory : currentDir);
    final hasPendingChange = _pendingDirectoryPath != null &&
        _pendingDirectoryPath!.toLowerCase() != currentDir.toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCurrent)
          _buildInactiveWorkspaceNoticeBanner(accentColor, textColor, subColor),

        // 1. 工作区状态卡片
        _buildCardSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.workspaces_outlined, size: 16, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _editingWorkspaceId == _selectedWorkspace.id
                        ? Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 26,
                                  child: TextField(
                                    controller: _inlineRenameController,
                                    focusNode: _inlineRenameFocusNode,
                                    autofocus: true,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(color: accentColor),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(color: accentColor, width: 1.5),
                                      ),
                                    ),
                                    onSubmitted: (_) => _commitInlineRename(_selectedWorkspace.id),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: _text('保存名称', 'Save name'),
                                child: InkWell(
                                  onTap: () => _commitInlineRename(_selectedWorkspace.id),
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.check_rounded, size: 18, color: Colors.green),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Tooltip(
                                message: _text('取消', 'Cancel'),
                                child: InkWell(
                                  onTap: _cancelInlineRename,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(Icons.close_rounded, size: 18, color: subColor),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _selectedWorkspace.name,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 14),
                                tooltip: _text('重命名工作区', 'Rename Workspace'),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                splashRadius: 14,
                                color: subColor,
                                onPressed: () => _startInlineRename(_selectedWorkspace),
                              ),
                            ],
                          ),
                  ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(
                            _text('当前激活', 'Active'),
                            style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '🔑 配对 ID (Vault ID): ${_selectedWorkspace.vaultId ?? '自动匹配'}',
                style: TextStyle(fontSize: 10, color: subColor, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 本地存储目录卡片
        _buildCardSection(
          title: _text('本地数据存储目录', 'Local Data Directory'),
          icon: Icons.folder_outlined,
          accentColor: accentColor,
          textColor: textColor,
          headerTrailing: hasPendingChange
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: ElevatedButton.icon(
                    onPressed: _applyPendingDirectory,
                    icon: const Icon(Icons.check_rounded, size: 13),
                    label: Text(
                      _text('应用', 'Apply'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 24),
                      elevation: 1,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                    ),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '便签内容、剪贴板历史记录、临时图片与暂存文件均保存在此目录中。',
                  'Notes, clipboard history, temp images, and files are stored here.',
                ),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: hasPendingChange
                      ? (_detectedWorkspaceProfile != null ? Colors.green.withValues(alpha: 0.08) : accentColor.withValues(alpha: 0.08))
                      : (_isDarkTheme ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasPendingChange
                        ? (_detectedWorkspaceProfile != null ? Colors.green.withValues(alpha: 0.4) : accentColor.withValues(alpha: 0.4))
                        : (_isDarkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                  ),
                ),
                child: SelectableText(
                  displayDirPath,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: textColor,
                  ),
                ),
              ),
              if (hasPendingChange) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_detectedWorkspaceProfile != null ? Colors.green : Colors.amber).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (_detectedWorkspaceProfile != null ? Colors.green : Colors.amber).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _detectedWorkspaceProfile != null ? Icons.cloud_done_rounded : Icons.info_outline_rounded,
                        size: 16,
                        color: _detectedWorkspaceProfile != null ? Colors.green : Colors.amber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _detectedWorkspaceProfile != null
                                  ? _text(
                                      '检测到该目录包含已有工作区【${_detectedWorkspaceProfile!.name}】',
                                      'Workspace【${_detectedWorkspaceProfile!.name}】detected in this folder',
                                    )
                                  : _text('新选中的存储目录尚未应用', 'Selected directory not yet applied'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _detectedWorkspaceProfile != null
                                  ? _text(
                                      '关联云端：${_detectedWorkspaceProfile!.hasCloudConfig ? (_detectedWorkspaceProfile!.cfWorkerUrl ?? "已配置") : "纯本地离线"}。点击「应用」将自动同步回填。',
                                      'Cloud: ${_detectedWorkspaceProfile!.hasCloudConfig ? (_detectedWorkspaceProfile!.cfWorkerUrl ?? "Configured") : "Offline"}. Click Apply to load.',
                                    )
                                  : _text('点击「应用」或下方按钮立即生效', 'Click Apply to save this directory'),
                              style: TextStyle(fontSize: 10, color: subColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickDirectoryForSelectedWorkspace,
                    icon: const Icon(Icons.edit_location_alt_rounded, size: 13),
                    label: Text(
                      _text('更改位置', 'Change Location'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  if (hasPendingChange) ...[
                    const SizedBox(width: 8),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: ElevatedButton.icon(
                        onPressed: _applyPendingDirectory,
                        icon: const Icon(Icons.check_rounded, size: 13),
                        label: Text(
                          _text('应用', 'Apply'),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => widget.state.openDirectoryPath(displayDirPath),
                    icon: const Icon(Icons.folder_open_rounded, size: 13),
                    label: Text(
                      _text('打开文件夹', 'Open in Folder'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. 数据迁移与增量合并
        _buildCardSection(
          title: _text('数据迁移与增量合并', 'Data Migration & Merge'),
          icon: Icons.sync_alt_rounded,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '更换电脑或重装系统后，可从其他文件夹导入历史数据。系统会自动进行增量合并，不会覆盖现有数据。',
                  'Import data after system reinstall. Existing data will not be overwritten.',
                ),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 8),
              if (isCurrent) ...[
                OutlinedButton.icon(
                  onPressed: _manualSyncData,
                  icon: const Icon(Icons.drive_folder_upload_rounded, size: 14),
                  label: Text(
                    _text('选择文件夹并合并数据', 'Select Folder & Merge Data'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ] else ...[
                Text(
                  _text('（请先切换至此工作区，即可进行数据合并操作）', '(Switch to this workspace to merge data)'),
                  style: TextStyle(fontSize: 10.5, color: subColor, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4. 便签历史快照
        _buildCardSection(
          title: _text('便签本地历史快照 (防误删/防覆盖)', 'Notes Local Snapshots'),
          icon: Icons.history_rounded,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '系统在启动、同步前及内容变更时自动生成本地快照（保留最新 5 份）。无论发生冲突或误改，均可撤回恢复。',
                  'Snapshots are auto-created at launch, pre-sync, and changes (up to 5 copies). Restore historical versions anytime.',
                ),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _dataSubTab = 1;
                      _savedDataSubTab = 1;
                      _fourthColumnType = null;
                    }),
                    icon: const Icon(Icons.history_rounded, size: 14),
                    label: Text(
                      _text('管理快照与安全恢复', 'Manage Snapshots & Recovery'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final backupDir = Directory('$displayDirPath/backups/notes');
                      if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
                      widget.state.openDirectoryPath(backupDir.path);
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 14),
                    label: Text(
                      _text('打开快照目录', 'Open Directory'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSnapshotRecoveryPane(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    final isCurrent = _selectedWorkspace.id == widget.state.currentWorkspace.id;
    final backups = widget.state.getNotesBackups(customDir: _selectedWorkspace.directoryPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCurrent)
          _buildInactiveWorkspaceNoticeBanner(accentColor, textColor, subColor),

        // 1. 顶部工作区快照概览卡片
        _buildCardSection(
          title: _text('工作区快照概览', 'Workspace Snapshots Overview'),
          icon: Icons.history_rounded,
          accentColor: accentColor,
          textColor: textColor,
          headerTrailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCurrent) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    await widget.state.createNotesBackup('manual');
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_text('📸 已成功为当前工作区生成手动快照！', 'Manual snapshot created successfully!')),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.camera_alt_outlined, size: 12),
                  label: Text(_text('新建快照', 'New Snapshot'), style: const TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 24),
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  final dir = Directory('${_selectedWorkspace.directoryPath}/backups/notes');
                  if (!dir.existsSync()) dir.createSync(recursive: true);
                  await widget.state.openDirectoryPath(dir.path);
                },
                icon: const Icon(Icons.folder_open_rounded, size: 12),
                label: Text(_text('打开快照目录', 'Open Folder'), style: const TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textColor,
                  side: BorderSide(color: _isDarkTheme ? Colors.white24 : Colors.black26),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 24),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '系统在应用启动、每次云端同步前、网盘冲突合并以及手动操作时均会自动生成便签快照备份（自动保留最新 5 份）。所有快照均支持查看内容预览并一键无损还原。',
                  'Local snapshots are auto-created at launch, pre-sync, conflict merge, and manual backups (up to 5 copies). All snapshots support full content preview and 1-click restore.',
                ),
                style: TextStyle(fontSize: 11, color: subColor, height: 1.4),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _isDarkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _isDarkTheme ? Colors.white10 : Colors.black12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 16, color: accentColor),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedWorkspace.name} · ',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    Text(
                      _text('共 ${backups.length} 份可用快照', '${backups.length} snapshots available'),
                      style: TextStyle(fontSize: 11, color: backups.isEmpty ? Colors.orangeAccent : Colors.green),
                    ),
                    const Spacer(),
                    if (isCurrent)
                      Text(
                        _text('当前便签数: ${widget.state.notes.length}', 'Active Notes: ${widget.state.notes.length}'),
                        style: TextStyle(fontSize: 11, color: subColor),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 快照列表卡片
        _buildCardSection(
          title: _text('历史快照列表', 'Historical Snapshots'),
          icon: Icons.list_alt_rounded,
          accentColor: accentColor,
          textColor: textColor,
          child: backups.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 36, color: subColor.withValues(alpha: 0.4)),
                      const SizedBox(height: 10),
                      Text(
                        _text('当前工作区暂无历史快照', 'No snapshots found for this workspace'),
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _text('当您在此工作区编辑便签或进行同步时，系统将自动生成快照。', 'Snapshots will be automatically created when syncing or launching.'),
                        style: TextStyle(fontSize: 10.5, color: subColor.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: backups.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: _isDarkTheme ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                  ),
                  itemBuilder: (itemCtx, index) {
                    final b = backups[index];
                    final name = b['fileName'] as String? ?? '';
                    final count = b['count'] as int? ?? 0;
                    final modified = b['modified'] as DateTime? ?? DateTime.now();
                    final path = b['path'] as String? ?? '';
                    final sizeKb = ((b['size'] as int? ?? 0) / 1024).toStringAsFixed(1);
                    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(modified);

                    String reasonTag = '';
                    if (name.contains('conflict_merged')) {
                      reasonTag = _text('网盘冲突合并', 'Conflict Merged');
                    } else if (name.contains('pre_sync')) {
                      reasonTag = _text('同步前置备份', 'Pre-Sync');
                    } else if (name.contains('cloud_merged')) {
                      reasonTag = _text('云端同步后', 'Cloud Merged');
                    } else if (name.contains('app_launch')) {
                      reasonTag = _text('应用启动快照', 'Launch');
                    } else if (name.contains('before_restore')) {
                      reasonTag = _text('恢复前保护', 'Pre-Restore');
                    } else if (name.contains('recovered')) {
                      reasonTag = _text('灾备自愈恢复', 'Disaster Recovered');
                    } else if (name.contains('manual')) {
                      reasonTag = _text('手动备份', 'Manual');
                    } else {
                      reasonTag = _text('自动定时快照', 'Auto-Save');
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(Icons.description_outlined, size: 16, color: accentColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '$count ${_text("条便签", "notes")}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        reasonTag,
                                        style: TextStyle(fontSize: 10, color: accentColor, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$timeStr · ${sizeKb} KB',
                                  style: TextStyle(fontSize: 10.5, color: subColor),
                                ),
                              ],
                            ),
                          ),
                          // 预览按钮
                          OutlinedButton.icon(
                            onPressed: () => _showSnapshotPreviewDialog(
                              filePath: path,
                              fileName: name,
                              modified: modified,
                              reasonTag: reasonTag,
                              targetWorkspace: _selectedWorkspace,
                              accentColor: accentColor,
                              textColor: textColor,
                              subColor: subColor,
                            ),
                            icon: const Icon(Icons.visibility_outlined, size: 13),
                            label: Text(_text('预览', 'Preview'), style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 26),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 恢复按钮
                          ElevatedButton.icon(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
                                  title: Text(_text('确认恢复此快照？', 'Restore Snapshot?')),
                                  content: Text(_text(
                                    '即将恢复包含 $count 条便签的快照（时间: $timeStr）到工作区【${_selectedWorkspace.name}】。\n系统在恢复前会自动为当前便签再备份一份，确保万无一失。',
                                    'Restore snapshot with $count notes ($timeStr) into workspace [${_selectedWorkspace.name}]? Current notes will be backed up.',
                                  )),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(c).pop(false),
                                      child: Text(_text('取消', 'Cancel')),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.of(c).pop(true),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                      child: Text(_text('确认恢复', 'Restore')),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                final res = await widget.state.restoreNotesFromBackup(path, targetDir: _selectedWorkspace.directoryPath);
                                if (res && mounted) {
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(_text('🎉 成功恢复 $count 条便签至【${_selectedWorkspace.name}】！', 'Successfully restored $count notes to [${_selectedWorkspace.name}]!')),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.restore_rounded, size: 13),
                            label: Text(_text('恢复', 'Restore'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 26),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 复用的单项配置组件（供分栏视图及窄屏模式共用）
  // ===========================================================================

  Widget _buildHotkeyConfigContent(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text('在任意界面快速呼出或收起面板：', 'Show or hide the panel from anywhere:'),
          style: TextStyle(fontSize: 11, color: subColor),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _hotkeyPresets.contains(_hotkey) ? _hotkey : _hotkeyPresets.first,
          dropdownColor: dropdownBg,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _isDarkTheme ? Colors.white24 : Colors.black12),
            ),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: accentColor)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: _hotkeyPresets.map((key) {
            return DropdownMenuItem<String>(
              value: key,
              child: Text(
                key.toUpperCase().replaceAll('+', ' + '),
                style: TextStyle(fontSize: 12, color: textColor),
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _hotkey = val);
          },
        ),
      ],
    );
  }

  Widget _buildHoverCollapseConfigContent(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_triggerMode != TriggerMode.hotkeyOnly &&
            _triggerMode != TriggerMode.scrollOnly) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _text('边缘悬停延迟', 'Edge Hover Delay'),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: subColor),
              ),
              Text(
                '${_hoverTimeout.toInt()} ms',
                style: TextStyle(fontSize: 11.5, color: textColor),
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
            onChanged: (val) => setState(() => _hoverTimeout = val),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _text('鼠标离开后自动收起', 'Auto-collapse Delay'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: subColor),
            ),
            Text(
              _autoCollapseDelay >= AppSettings.maxAutoCollapseDelay
                  ? _text('仅手动收起', 'Manual only')
                  : _autoCollapseDelay == 0
                      ? _text('点外部立即收起', 'Immediate on outside click')
                      : _text('$_autoCollapseDelay 秒后', 'After ${_autoCollapseDelay}s'),
              style: TextStyle(fontSize: 11, color: textColor),
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
          onChanged: (val) => setState(() => _autoCollapseDelay = val.toInt()),
        ),
      ],
    );
  }

  Widget _buildSoftwareUpdateConfigContent(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.system_update_rounded, size: 18, color: accentColor),
            const SizedBox(width: 8),
            Text(
              _text('当前版本 v${UpdateService.currentVersion}', 'Version v${UpdateService.currentVersion}'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textColor),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_updateCheckResult != null) ...[
          Text(
            _updateCheckResult!,
            style: TextStyle(
              fontSize: 11,
              color: _updateCheckResult!.contains('最新') || _updateCheckResult!.contains('up to date')
                  ? Colors.green
                  : Colors.orangeAccent,
            ),
          ),
          const SizedBox(height: 10),
        ],
        ElevatedButton.icon(
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
                      UpdateService.showUpdateDialog(context, info, isDark: _isDarkTheme);
                    } else {
                      setState(() {
                        _updateCheckResult = _text('✅ 当前已是最新版本', '✅ Up to date');
                      });
                    }
                  }
                },
          icon: _isCheckingUpdate
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.refresh_rounded, size: 14),
          label: Text(
            _isCheckingUpdate ? _text('正在检查...', 'Checking...') : _text('检查版本更新', 'Check for Updates'),
            style: const TextStyle(fontSize: 11),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          ),
        ),
      ],
    );
  }

  Widget _buildDimensionsConfigContent(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _text('面板宽度', 'Panel Width'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: subColor),
            ),
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: _isDarkTheme ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _isWidthPercentage = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: !_isWidthPercentage ? accentColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _text('固定像素', 'Pixels'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: !_isWidthPercentage ? Colors.white : textColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _isWidthPercentage = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isWidthPercentage ? accentColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _text('屏幕百分比', 'Percent'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _isWidthPercentage ? Colors.white : textColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (!_isWidthPercentage) ...[
          Align(
            alignment: Alignment.centerRight,
            child: Text('${_panelWidth.toInt()} px', style: TextStyle(fontSize: 11, color: textColor)),
          ),
          Slider(
            value: _panelWidth,
            min: 400,
            max: 1600,
            divisions: 24,
            activeColor: accentColor,
            inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
            onChanged: (val) => setState(() => _panelWidth = val),
          ),
        ] else ...[
          Align(
            alignment: Alignment.centerRight,
            child: Text('${_panelWidthPercent.toInt()}%', style: TextStyle(fontSize: 11, color: textColor)),
          ),
          Slider(
            value: _panelWidthPercent,
            min: 30,
            max: 100,
            divisions: 70,
            activeColor: accentColor,
            inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
            onChanged: (val) => setState(() => _panelWidthPercent = val),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _text('背板透明度', 'Backdrop Opacity'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: subColor),
            ),
            Text('${(_backdropOpacity * 100).round()}%', style: TextStyle(fontSize: 11.5, color: textColor)),
          ],
        ),
        Slider(
          value: _backdropOpacity,
          min: 0.35,
          max: 1.0,
          divisions: 65,
          activeColor: accentColor,
          inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
          onChanged: (val) => setState(() => _backdropOpacity = val),
        ),
      ],
    );
  }

  Widget _buildThemeConfigContent(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _text('深色主题', 'Dark Theme'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
            ),
            Switch(
              value: _isDarkTheme,
              activeColor: accentColor,
              onChanged: (val) => setState(() => _isDarkTheme = val),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _text('主题强调色', 'Accent Color'),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: subColor),
        ),
        const SizedBox(height: 8),
        Row(
          children: ['blue', 'orange', 'green', 'purple', 'red'].map((colorName) {
            final color = AppTheme.getAccentColor(colorName, _isDarkTheme);
            final isSelected = _themeColorName == colorName;
            return GestureDetector(
              onTap: () => setState(() => _themeColorName = colorName),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? (_isDarkTheme ? Colors.white : Colors.black87) : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPanelOrderConfigContent(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text('左右拖动下方模块卡片，调整主界面布局顺序：', 'Drag cards horizontally to reorder main sections:'),
          style: TextStyle(fontSize: 11, color: subColor),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            onReorder: (int oldIndex, int newIndex) {
              setState(() {
                if (oldIndex < newIndex) newIndex -= 1;
                final pane = _panelOrder.removeAt(oldIndex);
                _panelOrder.insert(newIndex, pane);
              });
            },
            children: [
              for (var index = 0; index < _panelOrder.length; index++)
                ReorderableDragStartListener(
                  key: ValueKey(_panelOrder[index]),
                  index: index,
                  child: Container(
                    width: 110,
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
    );
  }

  Widget _buildClipboardLimitConfigContent(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _text('历史记录保留上限', 'Clipboard History Limit'),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: subColor),
            ),
            Text(
              _text('$_clipboardHistoryLimit 条', '$_clipboardHistoryLimit items'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
            ),
          ],
        ),
        Slider(
          value: _clipboardHistoryLimit.toDouble(),
          min: AppSettings.minClipboardHistoryLimit.toDouble(),
          max: AppSettings.maxClipboardHistoryLimit.toDouble(),
          divisions: (AppSettings.maxClipboardHistoryLimit - AppSettings.minClipboardHistoryLimit) ~/ 10,
          activeColor: accentColor,
          inactiveColor: _isDarkTheme ? Colors.white12 : Colors.black12,
          onChanged: (val) => setState(() => _clipboardHistoryLimit = (val / 10).round() * 10),
        ),
        Text(
          _text('超过上限后自动清理最早的非收藏记录。', 'Oldest non-favorite records are removed after this limit.'),
          style: TextStyle(fontSize: 10.5, color: subColor),
        ),
      ],
    );
  }

  Widget _buildLocalDataMergeContent(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(
            '重装系统或更换目录后，可选择旧文件夹导入历史数据（自动增量合并，不覆盖现有数据）：',
            'Import and merge data from a previous folder without overwriting current items:',
          ),
          style: TextStyle(fontSize: 11, color: subColor),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isDarkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            _text(
              '默认路径参考: ${widget.state.defaultDataDirectoryPath}',
              'Default path: ${widget.state.defaultDataDirectoryPath}',
            ),
            style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: subColor),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _manualSyncData,
          icon: const Icon(Icons.drive_folder_upload_rounded, size: 14),
          label: Text(
            _text('选择文件夹并合并数据', 'Select Folder & Merge Data'),
            style: const TextStyle(fontSize: 11),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          ),
        ),
      ],
    );
  }

  Widget _buildExistingWorkerForm(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(
            '请输入已部署好的 Cloudflare Worker 地址并确认：',
            'Enter your deployed Cloudflare Worker URL and confirm:',
          ),
          style: TextStyle(fontSize: 11, color: subColor),
        ),
        const SizedBox(height: 10),
        _buildCustomTextField(
          label: _text('Worker 地址 (URL)', 'Worker URL'),
          controller: _cfD1WorkerUrlController,
          hint: 'https://pod-quick-backend.your-subdomain.workers.dev',
          textColor: textColor,
          subColor: subColor,
          accentColor: accentColor,
        ),
        const SizedBox(height: 10),

        // 引导：没有 Worker 地址？引导点击自动部署并自动回填
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _isDarkTheme
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isDarkTheme ? Colors.white10 : Colors.black12,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 14, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _text('还没有 Worker 地址？可使用「CF 自动部署」一键创建并自动回填：', 'No Worker URL yet? 1-Click Auto Deploy and fill in:'),
                  style: TextStyle(fontSize: 10.5, color: subColor),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _fourthColumnType = 'cf_auto_deploy';
                  });
                },
                icon: const Icon(Icons.rocket_launch_rounded, size: 12),
                label: Text(
                  _text('去自动部署', 'Auto Deploy'),
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 26),
                  side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (_cfD1WorkerUrlController.text.trim().isNotEmpty || widget.state.settings.cfWorkerUrl.trim().isNotEmpty) ...[
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
                      title: Text(_text('确认解除当前工作区云端绑定？', 'Disconnect Cloud Sync?'), style: TextStyle(color: textColor)),
                      content: Text(
                        _text('解除后此工作区将转为纯本地离线模式，云端原有数据仍会保留。', 'This workspace will switch to offline mode. Data on Cloudflare remains intact.'),
                        style: TextStyle(color: subColor),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(_text('取消', 'Cancel'))),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(_text('解除绑定', 'Disconnect'), style: const TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    setState(() {
                      _cfD1WorkerUrlController.clear();
                      _cfD1AutoSync = false;
                      _isEditingWorker = false;
                      _isWorkerOnline = false;
                      _fourthColumnType = null;
                      _cfD1TestMessage = null;
                    });
                    final curWs = widget.state.currentWorkspace;
                    await widget.state.updateCurrentWorkspaceProfile(
                      curWs.copyWith(
                        cfWorkerUrl: '',
                        cfD1AutoSync: false,
                      ),
                    );
                    await widget.state.updateSettings(
                      widget.state.settings.copyWith(
                        cfWorkerUrl: '',
                        cfD1AutoSync: false,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.link_off_rounded, size: 14, color: Colors.redAccent),
                label: Text(
                  _text('解除绑定', 'Disconnect'),
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 26),
                ),
              ),
            ],
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isTestingCfD1
                  ? null
                  : () => _testWorkerConnection(closeEditOnSuccess: true),
              icon: _isTestingCfD1
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 14),
              label: Text(
                _text('确认并连接', 'Confirm & Connect'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              ),
            ),
          ],
        ),
        if (widget.state.isD1Syncing || _cfD1TestMessage != null || widget.state.lastD1SyncMessage != null) ...[
          const SizedBox(height: 10),
          _buildFeedbackBanner(accentColor, textColor),
        ],
      ],
    );
  }

  Widget _buildAutoDeployWorkerForm({
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required bool allowExtendFourthCol,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部返回上一步：切换回输入 Worker 地址
        InkWell(
          onTap: () {
            setState(() {
              _fourthColumnType = 'worker_url';
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded, size: 13, color: accentColor),
                const SizedBox(width: 4),
                Text(
                  _text('返回直接填写 Worker 地址', 'Back to Worker URL'),
                  style: TextStyle(fontSize: 10.5, color: accentColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _text(
            '填写 Cloudflare 信息并确认，系统将自动部署并生成 Worker 地址：',
            'Enter Cloudflare info and confirm to auto-deploy Worker:',
          ),
          style: TextStyle(fontSize: 11, color: subColor),
        ),
        const SizedBox(height: 8),
        _buildParamFieldWithLink(
          label: _text('1. Cloudflare 账户 ID (Account ID)', '1. Account ID'),
          controller: _cfAccountIdController,
          hint: _text('32位纯字母数字，如 2a6d469...', '32-char hex, e.g. 2a6d469...'),
          tooltip: _text(
            '获取技巧：登录 Cloudflare 后，看浏览器上方 URL 地址栏，dash.cloudflare.com/ 后面的 32 位字符就是账户 ID；或者进入任意网站页面右下角直接点击复制。',
            'Tip: Log in to CF, look at your browser address bar: the 32-character string right after dash.cloudflare.com/ is your Account ID.',
          ),
          linkText: _text('🔗 获取 ID', '🔗 Get ID'),
          linkUrl: 'https://dash.cloudflare.com/',
          textColor: textColor,
          subColor: subColor,
          accentColor: accentColor,
        ),
        const SizedBox(height: 8),
        _buildParamFieldWithLink(
          label: _text('2. API 令牌 (API Token)', '2. API Token'),
          controller: _cfApiTokenController,
          hint: _text('必须包含【D1】与【Workers 脚本】编辑权限', 'Requires D1 & Workers Scripts Edit permissions'),
          tooltip: _text(
            '⚠️ 关键权限要求（创建自定义令牌）：\n1. 【账户 -> D1】-> 编辑 (Edit)（注意：D1 是单独项，不叫 Workers D1！）\n2. 【账户 -> Workers 脚本】-> 编辑 (Edit)\n3. 【账户 -> Workers R2 存储】-> 编辑 (Edit)（用于大文件/图片同步）\n4. 【账户 -> 账户设置】-> 读取 (Read)\n\n📌 提示：如果使用 R2 文件存储，需在 Cloudflare 控制台左侧点击「R2」开通激活一次（每月 10GB 免费）。',
            'Required Permissions:\n1. Account -> D1 -> Edit (Independent entry, not under Workers)\n2. Account -> Workers Scripts -> Edit\n3. Account -> Workers R2 Storage -> Edit\n4. Account -> Account Settings -> Read\n\nNote: R2 must be activated in Cloudflare dashboard (10GB free/mo).',
          ),
          linkText: _text('🔗 创建令牌', '🔗 Create Token'),
          linkUrl: 'https://dash.cloudflare.com/profile/api-tokens',
          textColor: textColor,
          subColor: subColor,
          accentColor: accentColor,
          obscureText: true,
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _showWorkerAdvanced = !_showWorkerAdvanced),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showWorkerAdvanced ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                  size: 14,
                  color: subColor,
                ),
                const SizedBox(width: 3),
                Text(
                  _text('自定义资源名称 (可选，默认自动命名)', 'Custom resource names (Optional)'),
                  style: TextStyle(fontSize: 10, color: subColor),
                ),
              ],
            ),
          ),
        ),
        if (_showWorkerAdvanced) ...[
          const SizedBox(height: 6),
          _buildCustomTextField(
            label: _text('D1 数据库名称', 'D1 Database Name'),
            controller: _cfD1DatabaseIdController,
            hint: '默认: pod-quick-d1',
            textColor: textColor,
            subColor: subColor,
            accentColor: accentColor,
          ),
          const SizedBox(height: 6),
          _buildParamFieldWithLink(
            label: _text('R2 存储桶名称', 'R2 Bucket Name'),
            controller: _cfR2BucketNameController,
            hint: '默认: pod-quick-files-apac',
            linkText: _text('🔗 开通/查看 R2', '🔗 Activate R2'),
            linkUrl: 'https://dash.cloudflare.com/?to=/:account/r2/overview',
            tooltip: _text(
              'Cloudflare R2 每月提供 10GB 永久免费存储空间。新账号请先点击链接在控制台开通激活一次 R2 服务；若未开通，系统会自动跳过 R2 并部署便签与剪贴板同步。',
              'R2 provides 10GB free storage. Please activate R2 in Cloudflare dashboard first.',
            ),
            textColor: textColor,
            subColor: subColor,
            accentColor: accentColor,
          ),
          const SizedBox(height: 6),
          _buildCustomTextField(
            label: _text('Worker 服务名称', 'Worker Service Name'),
            controller: _cfWorkerNameController,
            hint: '默认: pod-quick-backend',
            textColor: textColor,
            subColor: subColor,
            accentColor: accentColor,
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
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
                          '⚠️ 请先填入 Account ID 与 API 令牌',
                          'Please enter Account ID and API Token',
                        );
                      });
                      return;
                    }
                    setState(() {
                      _isDeployingWorker = true;
                      _cfD1TestMessage = _text('🚀 正在连接 Cloudflare API 自动部署...', 'Deploying Worker...');
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
                      onLog: (msg) => widget.state.addD1Log(msg),
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
                          _isEditingWorker = false;
                          _fourthColumnType = null;
                          _cfD1TestMessage = _text(
                            '🎉 部署成功！已自动绑定 Worker 地址',
                            '🎉 Deployed! Worker URL bound',
                          );
                          widget.state.updateSettings(
                            widget.state.settings.copyWith(
                              cfD1Mode: 0,
                              cfWorkerUrl: res['workerUrl'],
                              cfAccountId: accountId,
                              cfApiToken: apiToken,
                              cfD1DatabaseId: res['d1DatabaseId'],
                              cfR2BucketName: res['r2BucketName'] ?? bucketName,
                            ),
                          );
                          final curWs = widget.state.currentWorkspace;
                          widget.state.updateCurrentWorkspaceProfile(
                            curWs.copyWith(
                              cfWorkerUrl: res['workerUrl'],
                              cfAccountId: accountId,
                              cfApiToken: apiToken,
                              cfD1DatabaseId: res['d1DatabaseId'],
                              cfR2BucketName: res['r2BucketName'] ?? bucketName,
                              cfD1AutoSync: true,
                            ),
                          );
                        } else {
                          _cfD1TestSuccess = false;
                          _cfD1TestMessage = res['error'] ?? _text('❌ 部署失败，请检查令牌权限', 'Deployment failed');
                        }
                      });
                    }
                  },
            icon: _isDeployingWorker
                ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 14),
            label: Text(
              _isDeployingWorker ? _text('正在自动部署中...', 'Deploying...') : _text('确认并自动部署', 'Confirm & Auto Deploy'),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        if (widget.state.isD1Syncing || _cfD1TestMessage != null || widget.state.lastD1SyncMessage != null) ...[
          const SizedBox(height: 8),
          _buildFeedbackBanner(accentColor, textColor),
        ],
      ],
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
              if (_triggerMode != TriggerMode.hotkeyOnly &&
                  _triggerMode != TriggerMode.hoverOnly) ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    _text('唤醒滚轮反向（开启相反）', 'Invert Scroll Wake Direction'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  subtitle: Text(
                    _text(
                      '滚轮下滚收起、上滚展开面板（默认下滚展开、上滚收起）',
                      'Scroll down to collapse, scroll up to expand (default is inverted)',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: subColor.withValues(alpha: 0.8),
                    ),
                  ),
                  value: _invertScrollDirection,
                  activeColor: accentColor,
                  onChanged: (val) {
                    setState(() {
                      _invertScrollDirection = val;
                    });
                  },
                ),
              ],
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

            // TAB 3: 数据存储与同步 Data & Sync
            if (_settingsTab == 3) ...[
              _buildDataSyncSection(
                accentColor,
                textColor,
                subColor,
                dropdownBg,
                contentWidth,
                useTwoColumns || isWide,
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

  // ==========================================
  // TAB 3: 数据存储与同步 (左右布局 / 响应式)
  // ==========================================

  Widget _buildDataSyncSection(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
    double width,
    bool isWide,
  ) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：存储与同步分类导航 (左右布局)
          SizedBox(
            width: 175,
            child: _buildDataSyncNavMenu(accentColor, textColor, subColor),
          ),
          const SizedBox(width: 14),
          // 右侧：选中的配置面板
          Expanded(
            child: _dataSubTab == 0
                ? _buildLocalStoragePane(accentColor, textColor, subColor, dropdownBg)
                : _buildCloudStoragePane(accentColor, textColor, subColor, dropdownBg, isWide: true),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDataSyncNavMenuHorizontal(accentColor, textColor, subColor),
          const SizedBox(height: 12),
          _dataSubTab == 0
              ? _buildLocalStoragePane(accentColor, textColor, subColor, dropdownBg)
              : _buildCloudStoragePane(accentColor, textColor, subColor, dropdownBg, isWide: false),
        ],
      );
    }
  }

  Widget _buildDataSyncNavMenu(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: _isDarkTheme ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDarkTheme ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              _text('存储配置', 'Storage Config'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: subColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          _buildDataSyncNavItem(
            index: 0,
            icon: Icons.folder_special_rounded,
            title: _text('本地存储', 'Local Storage'),
            subtitle: _text('路径与数据导入', 'Path & Import'),
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
          ),
          const SizedBox(height: 4),
          _buildDataSyncNavItem(
            index: 1,
            icon: Icons.cloud_sync_rounded,
            title: _text('云端存储', 'Cloud Storage'),
            subtitle: _text('Cloudflare 同步', 'Cloudflare Sync'),
            isCloud: true,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
          ),
        ],
      ),
    );
  }

  Widget _buildDataSyncNavItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    bool isCloud = false,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final active = _dataSubTab == index;
    Color statusDotColor = Colors.grey;
    if (isCloud) {
      if (_cfD1WorkerUrlController.text.trim().isNotEmpty) {
        if (_isWorkerOnline == true) {
          statusDotColor = Colors.green;
        } else if (_isWorkerOnline == false) {
          statusDotColor = Colors.redAccent;
        } else {
          statusDotColor = Colors.orangeAccent;
        }
      }
    }

    return InkWell(
      onTap: () {
        setState(() {
          _dataSubTab = index;
          _savedDataSubTab = index;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? accentColor.withValues(alpha: _isDarkTheme ? 0.16 : 0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? accentColor.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: active ? accentColor : subColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.bold : FontWeight.w500,
                      color: active ? accentColor : textColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            if (isCloud) ...[
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusDotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataSyncNavMenuHorizontal(
    Color accentColor,
    Color textColor,
    Color subColor,
  ) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _isDarkTheme ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _dataSubTab = 0;
                _savedDataSubTab = 0;
              }),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _dataSubTab == 0 ? accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _text('本地存储', 'Local Storage'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _dataSubTab == 0 ? Colors.white : textColor,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _dataSubTab = 1;
                _savedDataSubTab = 1;
              }),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _dataSubTab == 1 ? accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _text('云端存储 (Cloudflare)', 'Cloud Storage (CF)'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _dataSubTab == 1 ? Colors.white : textColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalStoragePane(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCardSection(
          title: _text('工作区 (Workspace)', 'Workspace'),
          icon: Icons.workspaces_outlined,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '每个工作区对应一个独立的本地存储目录，并可独立绑定不同的云端同步节点。',
                  'Each workspace has its own local storage directory and can link to a distinct cloud service.',
                ),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: dropdownBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isDarkTheme
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: widget.state.currentWorkspace.id,
                          isExpanded: true,
                          dropdownColor: dropdownBg,
                          style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                          items: widget.state.workspaces.map((ws) {
                            return DropdownMenuItem<String>(
                              value: ws.id,
                              child: Text(ws.name),
                            );
                          }).toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              await widget.state.switchWorkspace(val);
                              setState(() {
                                _dataDirectory = widget.state.getDataDirectoryPathSync();
                                _cfD1WorkerUrlController.text = widget.state.settings.cfWorkerUrl;
                                _cfAccountIdController.text = widget.state.settings.cfAccountId ?? '';
                                _cfApiTokenController.text = widget.state.settings.cfApiToken ?? '';
                                _cfD1DatabaseIdController.text = widget.state.settings.cfD1DatabaseId ?? '';
                                _cfR2BucketNameController.text = widget.state.settings.cfR2BucketName ?? '';
                                _cfD1AutoSync = widget.state.settings.cfD1AutoSync;
                                _cfD1SyncIntervalMinutes = widget.state.settings.cfD1SyncIntervalMinutes;
                              });
                              if (widget.state.settings.cfWorkerUrl.trim().isNotEmpty) {
                                _autoCheckWorkerHealth();
                              } else {
                                setState(() => _isWorkerOnline = null);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showCreateWorkspaceDialog,
                    icon: const Icon(Icons.add_rounded, size: 14),
                    label: Text(_text('新建工作区', 'New Workspace'), style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  if (widget.state.workspaces.length > 1) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      tooltip: _text('删除当前工作区', 'Delete Current Workspace'),
                      color: Colors.redAccent,
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white,
                            title: Text(_text('确认删除工作区？', 'Delete Workspace?'), style: TextStyle(color: textColor)),
                            content: Text(
                              _text('确定要从列表中移除工作区【${widget.state.currentWorkspace.name}】吗？本地已有文件不会被强行销毁。', 'Remove workspace? Local files will remain.'),
                              style: TextStyle(color: subColor),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(_text('取消', 'Cancel'))),
                              TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(_text('删除', 'Delete'), style: const TextStyle(color: Colors.redAccent))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await widget.state.deleteWorkspace(widget.state.currentWorkspace.id);
                          setState(() {
                            _dataDirectory = widget.state.getDataDirectoryPathSync();
                            _cfD1WorkerUrlController.text = widget.state.settings.cfWorkerUrl;
                            _cfAccountIdController.text = widget.state.settings.cfAccountId ?? '';
                            _cfApiTokenController.text = widget.state.settings.cfApiToken ?? '';
                            _cfD1DatabaseIdController.text = widget.state.settings.cfD1DatabaseId ?? '';
                            _cfR2BucketNameController.text = widget.state.settings.cfR2BucketName ?? '';
                            _cfD1AutoSync = widget.state.settings.cfD1AutoSync;
                            _cfD1SyncIntervalMinutes = widget.state.settings.cfD1SyncIntervalMinutes;
                          });
                        }
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isDarkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(
                        '☁️ 关联云端：${widget.state.currentWorkspace.hasCloudConfig ? (widget.state.currentWorkspace.cfWorkerUrl ?? '已配置 Cloudflare') : '纯本地离线（未绑定云端）'}',
                        'Cloud Service: ${widget.state.currentWorkspace.hasCloudConfig ? (widget.state.currentWorkspace.cfWorkerUrl ?? 'Configured') : 'Offline (No Cloud)'}',
                      ),
                      style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '🔑 配对 ID (Vault ID): ${widget.state.currentWorkspace.vaultId ?? '自动匹配'}',
                      style: TextStyle(fontSize: 10, color: subColor, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCardSection(
          title: _text('本地数据存储目录', 'Local Data Directory'),
          icon: Icons.folder_outlined,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '便签内容、剪贴板历史记录、临时图片与暂存文件均保存在此目录中。',
                  'Notes, clipboard history, temp images, and files are stored here.',
                ),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _isDarkTheme
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _isDarkTheme
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: SelectableText(
                  _dataDirectory,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _selectDataDirectory,
                    icon: const Icon(Icons.edit_location_alt_rounded, size: 14),
                    label: Text(
                      _text('更改位置', 'Change Location'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => widget.state.openDirectoryPath(_dataDirectory),
                    icon: const Icon(Icons.folder_open_rounded, size: 14),
                    label: Text(
                      _text('打开文件夹', 'Open in Folder'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCardSection(
          title: _text('数据迁移与增量合并', 'Data Migration & Merge'),
          icon: Icons.sync_alt_rounded,
          accentColor: accentColor,
          textColor: textColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '更换电脑或重装系统后，可从其他文件夹导入历史数据。系统会自动进行增量合并，不会覆盖现有数据。',
                  'Import data after system reinstall. Existing data will not be overwritten.',
                ),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 8),
              Text(
                _text(
                  '默认参考路径：${widget.state.defaultDataDirectoryPath}',
                  'Default path: ${widget.state.defaultDataDirectoryPath}',
                ),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: subColor.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _manualSyncData,
                icon: const Icon(Icons.drive_folder_upload_rounded, size: 14),
                label: Text(
                  _text('选择文件夹并合并数据', 'Select Folder & Merge Data'),
                  style: const TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _sectionTitle(_text('便签本地历史快照 (防误删/防覆盖/网盘冲突自愈)', 'Notes Local Snapshots & Disaster Recovery'), subColor),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isDarkTheme ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _isDarkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(
                  '系统在应用启动、每次同步前以及内容变更时会自动生成本地快照（保留最新 5 份）。无论发生网盘冲突还是意外改动，随时可一键撤回恢复。',
                  'Local snapshots are auto-created at launch, pre-sync, and changes (up to 5 copies). You can restore any historical version anytime.',
                ),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _showNotesBackupDialog,
                    icon: const Icon(Icons.history_rounded, size: 14),
                    label: Text(
                      _text('查看快照与一键恢复', 'Snapshots & Recovery'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final backupDir = Directory('${widget.state.getDataDirectoryPathSync()}/backups/notes');
                      if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
                      await widget.state.openDirectoryPath(backupDir.path);
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 14),
                    label: Text(
                      _text('打开快照文件夹', 'Open Backups Folder'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCloudStoragePane(
    Color accentColor,
    Color textColor,
    Color subColor,
    Color dropdownBg, {
    required bool isWide,
  }) {
    final wsOnline = widget.state.getWorkspaceCloudOnline(_selectedWorkspace.id) ?? _isWorkerOnline;
    final isCur = _selectedWorkspace.id == widget.state.currentWorkspace.id;
    final isSyncing = isCur && widget.state.isD1Syncing;
    final lastSyncOk = isCur && widget.state.lastD1SyncSuccess == true;
    final effectiveRtt = _workerPingRtt ?? widget.state.getWorkspacePingRtt(_selectedWorkspace.id);

    Color statusColor;
    String statusText;
    if (_isTestingCfD1) {
      statusColor = accentColor;
      statusText = _text('正在测试连接...', 'Testing connection...');
    } else if (_cfD1WorkerUrlController.text.trim().isEmpty) {
      statusColor = Colors.grey;
      statusText = _text('未配置云端同步', 'Cloud sync not configured');
    } else if (wsOnline == true || lastSyncOk || isSyncing) {
      statusColor = Colors.green;
      statusText = isSyncing ? _text('已连接 (同步中...)', 'Connected (Syncing...)') : _text('已连接', 'Connected');
    } else if (wsOnline == false) {
      statusColor = Colors.redAccent;
      statusText = _text('连接未就绪', 'Unreachable');
    } else {
      statusColor = Colors.orangeAccent;
      statusText = _text('待测试', 'Untested');
    }

    final isCurrent = isCur;
    final hasWorkerUrl = _cfD1WorkerUrlController.text.trim().isNotEmpty;
    final isConfiguredAndHealthy = hasWorkerUrl && (wsOnline == true || lastSyncOk || isSyncing || (wsOnline == null && _selectedWorkspace.hasCloudConfig));
    final shouldCollapseConfig = isConfiguredAndHealthy && !_isEditingWorker;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCurrent)
          _buildInactiveWorkspaceNoticeBanner(accentColor, textColor, subColor),

        // 1. 顶部状态与控制卡片
        _buildCardSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (effectiveRtt != null && (wsOnline == true || lastSyncOk || isSyncing)) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${_workerPingRtt!.toStringAsFixed(0)}ms',
                      style: TextStyle(fontSize: 10, color: subColor, fontFamily: 'monospace'),
                    ),
                  ],
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _isTestingCfD1 ? null : () => _testWorkerConnection(),
                    icon: _isTestingCfD1
                        ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.speed_rounded, size: 13),
                    label: Text(_text('测试连接', 'Test'), style: const TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 26),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: (_isTestingCfD1 || widget.state.isD1Syncing)
                        ? null
                        : () {
                            if (!isCurrent) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_text('当前未激活【${_selectedWorkspace.name}】，请先切换工作区后再同步', 'Please switch to [${_selectedWorkspace.name}] before syncing')),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            _triggerSyncAll();
                          },
                    icon: widget.state.isD1Syncing
                        ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_sync_rounded, size: 13),
                    label: Text(
                      widget.state.isD1Syncing ? _text('同步中...', 'Syncing...') : _text('立即同步', 'Sync Now'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 26),
                    ),
                  ),
                ],
              ),
              if (_cfD1WorkerUrlController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _cfD1WorkerUrlController.text.trim(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: subColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: _text('复制地址', 'Copy URL'),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _cfD1WorkerUrlController.text.trim()));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_text('已复制 Worker 地址到剪贴板', 'Worker URL copied to clipboard')),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.copy_rounded, size: 13, color: subColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 16),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Text(
                    _text('后台定时自动同步', 'Auto-Sync in Background'),
                    style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 6),
                  if (_cfD1AutoSync) ...[
                    DropdownButton<int>(
                      value: _cfD1SyncIntervalMinutes,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: dropdownBg,
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
                          _save(closeAfterSave: false);
                        }
                      },
                    ),
                  ],
                  const Spacer(),
                  Switch(
                    value: _cfD1AutoSync,
                    activeColor: accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      setState(() => _cfD1AutoSync = val);
                      _save(closeAfterSave: false);
                    },
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => GlobalSyncLogDialog.show(context, state: widget.state),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        _text('同步日志 ↗', 'Logs ↗'),
                        style: TextStyle(fontSize: 10.5, color: accentColor, decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. 配置方式选项卡
        if (shouldCollapseConfig) ...[
          _buildCardSection(
            title: _text('云端连接配置', 'Cloud Connection Settings'),
            icon: Icons.cloud_done_rounded,
            accentColor: accentColor,
            textColor: textColor,
            headerTrailing: ElevatedButton.icon(
              onPressed: () => setState(() => _isEditingWorker = true),
              icon: const Icon(Icons.edit_rounded, size: 12),
              label: Text(_text('修改配置', 'Edit Config'), style: const TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 24),
                elevation: 0,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _text(
                      '当前节点服务正常，配置已折叠隐藏。如需更换节点或重新配置凭据，请点击右上角「修改配置」。',
                      'Cloud service is connected. Config is collapsed. Click Edit Config to modify.',
                    ),
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          _buildCardSection(
            title: _text('配置云端连接', 'Setup Cloud Connection'),
            icon: Icons.tune_rounded,
            accentColor: accentColor,
            textColor: textColor,
            headerTrailing: isConfiguredAndHealthy
                ? TextButton.icon(
                    onPressed: () => setState(() => _isEditingWorker = false),
                    icon: const Icon(Icons.unfold_less_rounded, size: 13),
                    label: Text(_text('收起', 'Collapse'), style: const TextStyle(fontSize: 11)),
                  )
                : null,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 32,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: _isDarkTheme ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _workerSubTab = 0),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _workerSubTab == 0 ? accentColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _text('方式一：已有 Worker 地址', 'Existing Worker URL'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _workerSubTab == 0 ? Colors.white : textColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _workerSubTab = 1),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _workerSubTab == 1 ? accentColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _text('方式二：一键自动部署到 Cloudflare', '1-Click Auto Deploy'),
                            style: TextStyle(
                              fontSize: 11,
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
                // 方式 1: 填入已有 Worker URL
                Text(
                  _text(
                    '若已搭建好 Cloudflare Worker，直接填入服务地址即可全自动双向同步：',
                    'Enter your existing Cloudflare Worker URL to start syncing:',
                  ),
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
                const SizedBox(height: 8),
                _buildCustomTextField(
                  label: _text('Worker 服务地址 (URL)', 'Worker URL'),
                  controller: _cfD1WorkerUrlController,
                  hint: 'https://pod-quick-backend.your-subdomain.workers.dev',
                  textColor: textColor,
                  subColor: subColor,
                  accentColor: accentColor,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _isTestingCfD1 ? null : () => _testWorkerConnection(),
                    icon: _isTestingCfD1
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 14),
                    label: Text(
                      _text('保存并测试连接', 'Save & Test'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                  ),
                ),
              ] else ...[
                // 方式 2: 一键自动部署
                Text(
                  _text(
                    '提供您的 Cloudflare 账户凭证，系统将全自动创建数据库并发布 Worker 服务：',
                    'Provide Cloudflare credentials to auto-create D1 and deploy Worker:',
                  ),
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
                const SizedBox(height: 10),
                if (isWide) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildParamFieldWithLink(
                          label: _text('Cloudflare 账户 ID (Account ID)', 'Account ID'),
                          controller: _cfAccountIdController,
                          hint: _text('32位纯字母数字，如 2a6d469...', '32-char hex, e.g. 2a6d469...'),
                          tooltip: _text(
                            '获取技巧：登录 Cloudflare 后，看浏览器上方 URL 地址栏，dash.cloudflare.com/ 后面的 32 位字符就是账户 ID；或者进入任意网站页面右下角直接点击复制。',
                            'Tip: Log in to CF, look at your browser address bar: the 32-character string right after dash.cloudflare.com/ is your Account ID.',
                          ),
                          linkText: _text('🔗 获取 ID', '🔗 Get ID'),
                          linkUrl: 'https://dash.cloudflare.com/',
                          textColor: textColor,
                          subColor: subColor,
                          accentColor: accentColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildParamFieldWithLink(
                          label: _text('API 令牌 (API Token)', 'API Token'),
                          controller: _cfApiTokenController,
                          hint: _text('需具备 Workers 与 D1 权限的 API Token', 'API Token with Workers & D1 permissions'),
                          tooltip: _text(
                            '⚠️ 关键权限要求（创建自定义令牌）：\n1. 【账户 -> D1】-> 编辑 (Edit)（注意：D1 是单独项，不叫 Workers D1！）\n2. 【账户 -> Workers 脚本】-> 编辑 (Edit)\n3. 【账户 -> Workers R2 存储】-> 编辑 (Edit)（用于大文件/图片同步）\n4. 【账户 -> 账户设置】-> 读取 (Read)\n\n📌 提示：如果使用 R2 文件存储，需在 Cloudflare 控制台左侧点击「R2」开通激活一次（每月 10GB 免费）。',
                            'Required Permissions:\n1. Account -> D1 -> Edit (Independent entry, not under Workers)\n2. Account -> Workers Scripts -> Edit\n3. Account -> Workers R2 Storage -> Edit\n4. Account -> Account Settings -> Read\n\nNote: R2 must be activated in Cloudflare dashboard (10GB free/mo).',
                          ),
                          linkText: _text('🔗 创建令牌', '🔗 Create Token'),
                          linkUrl: 'https://dash.cloudflare.com/profile/api-tokens',
                          textColor: textColor,
                          subColor: subColor,
                          accentColor: accentColor,
                          obscureText: true,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  _buildParamFieldWithLink(
                    label: _text('Cloudflare 账户 ID (Account ID)', 'Account ID'),
                    controller: _cfAccountIdController,
                    hint: _text('CF 首页右侧或 URL 中获取', 'Copy from CF Overview'),
                    linkText: _text('🔗 获取 ID', '🔗 Get ID'),
                    linkUrl: 'https://dash.cloudflare.com/',
                    tooltip: _text(
                      '登录 dash.cloudflare.com 后，地址栏 dash.cloudflare.com/{32位字符} 即为 Account ID，或在首页右侧栏直接复制。',
                      'Account ID can be found in dash.cloudflare.com/{32-char-id} URL or right sidebar.',
                    ),
                    textColor: textColor,
                    subColor: subColor,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 8),
                  _buildParamFieldWithLink(
                    label: _text('API 令牌 (API Token)', 'API Token'),
                    controller: _cfApiTokenController,
                    hint: _text('必须包含【D1(编辑)】与【Workers 脚本(编辑)】', 'Requires D1:Edit & Workers Scripts:Edit'),
                    linkText: _text('🔗 创建令牌', '🔗 Create Token'),
                    linkUrl: 'https://dash.cloudflare.com/profile/api-tokens',
                    tooltip: _text(
                      '⚠️ 关键权限提醒（缺少会导致数据库创建失败）：\n1. 【D1】-> 编辑 (Edit)（注意：D1 是单独项，不在 Workers 分类下！）\n2. 【Workers 脚本 (Workers Scripts)】-> 编辑 (Edit)\n3. 【Workers R2 存储】-> 编辑 (Edit)（可选，用于文件存储）\n4. 【账户设置 (Account Settings)】-> 读取 (Read)',
                      'Required Token Permissions:\n1. D1 -> Edit (Independent entry, not under Workers)\n2. Workers Scripts -> Edit\n3. Workers R2 Storage -> Edit (Optional)\n4. Account Settings -> Read',
                    ),
                    textColor: textColor,
                    subColor: subColor,
                    accentColor: accentColor,
                    obscureText: true,
                  ),
                ],
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _showWorkerAdvanced = !_showWorkerAdvanced),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showWorkerAdvanced ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                          size: 15,
                          color: subColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _text('高级设置 (可选自定义数据库/存储桶名称)', 'Advanced Options (Optional custom names)'),
                          style: TextStyle(fontSize: 10.5, color: subColor, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showWorkerAdvanced) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isDarkTheme ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _isDarkTheme ? Colors.white10 : Colors.black12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildCustomTextField(
                                label: _text('D1 数据库名称', 'D1 Database Name'),
                                controller: _cfD1DatabaseIdController,
                                hint: '默认: pod-quick-d1',
                                textColor: textColor,
                                subColor: subColor,
                                accentColor: accentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildParamFieldWithLink(
                                label: _text('R2 存储桶名称', 'R2 Bucket Name'),
                                controller: _cfR2BucketNameController,
                                hint: '默认: pod-quick-files-apac',
                                linkText: _text('🔗 开通/查看 R2', '🔗 Activate R2'),
                                linkUrl: 'https://dash.cloudflare.com/?to=/:account/r2/overview',
                                tooltip: _text(
                                  'Cloudflare R2 每月提供 10GB 永久免费存储空间。新账号请先点击链接在控制台开通激活一次 R2 服务；若未开通，系统会自动跳过 R2 并部署便签与剪贴板同步。',
                                  'R2 provides 10GB free storage. Please activate R2 in Cloudflare dashboard first.',
                                ),
                                textColor: textColor,
                                subColor: subColor,
                                accentColor: accentColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildCustomTextField(
                          label: _text('Worker 脚本服务名称', 'Worker Service Name'),
                          controller: _cfWorkerNameController,
                          hint: '默认: pod-quick-backend',
                          textColor: textColor,
                          subColor: subColor,
                          accentColor: accentColor,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
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
                                  '⚠️ 请先填入 Account ID 与 API 令牌',
                                  'Please enter Account ID and API Token',
                                );
                              });
                              return;
                            }
                            setState(() {
                              _isDeployingWorker = true;
                              _cfD1TestMessage = _text('🚀 正在连接 Cloudflare API 自动部署 Worker...', 'Deploying Worker...');
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
                              onLog: (msg) => widget.state.addD1Log(msg),
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
                                  _workerSubTab = 0;
                                  _cfD1TestMessage = _text(
                                    '🎉 部署成功！节点已上线：${res['workerUrl']}',
                                    '🎉 Deployed! Node online: ${res['workerUrl']}',
                                  );
                                  widget.state.updateSettings(
                                    widget.state.settings.copyWith(
                                      cfD1Mode: 0,
                                      cfWorkerUrl: res['workerUrl'],
                                      cfAccountId: accountId,
                                      cfApiToken: apiToken,
                                      cfD1DatabaseId: res['d1DatabaseId'],
                                      cfR2BucketName: res['r2BucketName'] ?? bucketName,
                                    ),
                                  );
                                  final curWs = widget.state.currentWorkspace;
                                  widget.state.updateCurrentWorkspaceProfile(
                                    curWs.copyWith(
                                      cfWorkerUrl: res['workerUrl'],
                                      cfAccountId: accountId,
                                      cfApiToken: apiToken,
                                      cfD1DatabaseId: res['d1DatabaseId'],
                                      cfR2BucketName: res['r2BucketName'] ?? bucketName,
                                      cfD1AutoSync: true,
                                    ),
                                  );
                                } else {
                                  _cfD1TestSuccess = false;
                                  _cfD1TestMessage = res['error'] ?? _text('❌ 部署失败，请检查令牌权限', 'Deployment failed');
                                }
                              });
                            }
                          },
                    icon: _isDeployingWorker
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.rocket_launch_rounded, size: 15),
                    label: Text(
                      _isDeployingWorker ? _text('正在自动部署中...', 'Deploying...') : _text('🚀 开始一键自动部署', '🚀 1-Click Deploy'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ],

        // 3. 反馈消息条
        if (widget.state.isD1Syncing || _cfD1TestMessage != null || widget.state.lastD1SyncMessage != null) ...[
          const SizedBox(height: 8),
          _buildFeedbackBanner(accentColor, textColor),
        ],
      ],
    );
  }

  Future<void> _testWorkerConnection({bool closeEditOnSuccess = false}) async {
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
          _isEditingWorker = false;
          _fourthColumnType = null;
          widget.state.setWorkspaceCloudOnline(_selectedWorkspace.id, true, rttMs: _workerPingRtt);
          _cfD1TestMessage = _text(
            '✅ Worker 连接正常！延迟: ${(_workerPingRtt ?? 0).toStringAsFixed(1)}ms',
            '✅ Connected! RTT: ${(_workerPingRtt ?? 0).toStringAsFixed(1)}ms',
          );
          widget.state.updateSettings(
            widget.state.settings.copyWith(
              cfD1Mode: 0,
              cfWorkerUrl: url,
            ),
          );
          final curWs = widget.state.currentWorkspace;
          widget.state.updateCurrentWorkspaceProfile(
            curWs.copyWith(
              cfWorkerUrl: url,
            ),
          );
        } else {
          _isWorkerOnline = false;
          _cfD1TestSuccess = false;
          widget.state.setWorkspaceCloudOnline(_selectedWorkspace.id, false);
          _cfD1TestMessage = _text(
            '❌ 节点连接失败: ${res['error'] ?? res['status']}',
            'Connection failed: ${res['error'] ?? res['status']}',
          );
        }
      });
    }
  }

  Widget _buildFeedbackBanner(Color accentColor, Color textColor) {
    if (widget.state.isD1Syncing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _text('🚀 正在后台全量同步中（便签、剪贴板与文件）...', '🚀 Syncing in background...'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isOk ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isOk ? Colors.green.withValues(alpha: 0.35) : Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: isOk ? Colors.green : Colors.redAccent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              showMessage,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isOk ? Colors.green : Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
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
    String tooltip = '',
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
            if (tooltip.isNotEmpty) ...[
              Tooltip(
                message: tooltip,
                preferBelow: false,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 11, color: Colors.white),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(Icons.help_outline_rounded, size: 13.5, color: subColor),
                ),
              ),
              const SizedBox(width: 4),
            ],
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
