import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../models/app_settings.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

class SettingsDialog extends StatefulWidget {
  final AppState state;

  const SettingsDialog({super.key, required this.state});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
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
  int _settingsTab = 0;

  final List<String> _hotkeyPresets = [
    'alt+u',
    'alt+space',
    'ctrl+alt+u',
    'ctrl+shift+u',
    'alt+n',
  ];

  late String _dataDirectory;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    super.dispose();
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

  Widget _sectionTitle(String text, Color subColor) {
    return Text(
      text,
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
  ) {
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
              onTap: () => setState(() => _settingsTab = index),
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
                    fontSize: 12,
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
      Navigator.of(context).pop();
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
    final dialogBg = _isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;
    final dropdownBg = _isDarkTheme
        ? const Color(0xFF2C2C2C)
        : Colors.grey[100];
    final accentColor = AppTheme.getAccentColor(_themeColorName, _isDarkTheme);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _isDarkTheme ? Colors.white10 : Colors.black12),
      ),
      child: Container(
        width: 420,
        height:
            540, // Fixed height and ClampingScrollPhysics prevent trembling at scroll boundaries
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              _text('PodQuick 设置', 'PodQuick Settings'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const Divider(height: 20),
            _buildSettingsTabs(accentColor, textColor, subColor),
            const SizedBox(height: 14),

            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_settingsTab == 0) ...[
                      _sectionTitle(_text('语言', 'Language'), subColor),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _languageCode,
                        dropdownColor: dropdownBg,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _isDarkTheme
                                  ? Colors.white24
                                  : Colors.black12,
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
                      const SizedBox(height: 16),
                      // Trigger Mode Option
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
                              color: _isDarkTheme
                                  ? Colors.white24
                                  : Colors.black12,
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
                      const SizedBox(height: 16),

                      // Hotkey Configuration
                      if (_triggerMode != TriggerMode.hoverOnly &&
                          _triggerMode != TriggerMode.scrollOnly) ...[
                        Text(
                          _text('全局快捷键', 'Global Hotkey'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _text(
                            '可在任意界面快速呼出/收起面板。选择下方下拉框可更改快捷键：',
                            'Show or hide the panel from anywhere. Choose a preset below:',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: subColor.withOpacity(0.8),
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
                                color: _isDarkTheme
                                    ? Colors.white24
                                    : Colors.black12,
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
                        const SizedBox(height: 16),
                      ],

                      // Hover Timeout config
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
                          inactiveColor: _isDarkTheme
                              ? Colors.white12
                              : Colors.black12,
                          label: '${_hoverTimeout.toInt()}ms',
                          onChanged: (val) {
                            setState(() {
                              _hoverTimeout = val;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],

                    // Panel Width config
                    if (_settingsTab == 1) ...[
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
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.04),
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
                                            : textColor.withOpacity(0.6),
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
                                            : textColor.withOpacity(0.6),
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
                          inactiveColor: _isDarkTheme
                              ? Colors.white12
                              : Colors.black12,
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
                          inactiveColor: _isDarkTheme
                              ? Colors.white12
                              : Colors.black12,
                          label: '${_panelWidthPercent.toInt()}%',
                          onChanged: (val) {
                            setState(() {
                              _panelWidthPercent = val;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 10),

                      Text(
                        _text('区域顺序', 'Panel Order'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                                  builder:
                                      (BuildContext context, Widget? child) {
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
                                  margin: const EdgeInsets.only(right: 6),
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
                      const SizedBox(height: 16),

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
                        inactiveColor: _isDarkTheme
                            ? Colors.white12
                            : Colors.black12,
                        label: '${(_backdropOpacity * 100).round()}%',
                        onChanged: (val) {
                          setState(() {
                            _backdropOpacity = val;
                          });
                        },
                      ),
                      const SizedBox(height: 10),

                      // Theme Accent Selection
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
                                  width: 24,
                                  height: 24,
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
                                              color: color.withOpacity(0.4),
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
                      const SizedBox(height: 20),
                    ],

                    // Switches: Dark Theme & Close on Blur
                    // Auto-collapse after mouse exits
                    if (_settingsTab == 0) ...[
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
                                _autoCollapseDelay >=
                                        AppSettings.maxAutoCollapseDelay
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
                                  color: subColor.withOpacity(0.7),
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
                        inactiveColor: _isDarkTheme
                            ? Colors.white12
                            : Colors.black12,
                        label:
                            _autoCollapseDelay >=
                                AppSettings.maxAutoCollapseDelay
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
                      const SizedBox(height: 10),
                    ],

                    // Clipboard history limit
                    if (_settingsTab == 2) ...[
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
                        inactiveColor: _isDarkTheme
                            ? Colors.white12
                            : Colors.black12,
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
                          color: subColor.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Switches: Dark Theme
                    if (_settingsTab == 1) ...[
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
                      // closeOnBlur 已永久禁用，改为鼠标滚轮上滑收起
                      const SizedBox(height: 12),
                    ],

                    if (_settingsTab == 3) ...[
                      Text(
                        _text('数据存储位置', 'Data Storage Location'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _text(
                          '所有数据（剪贴板历史、收藏、便签、剪切板图片及文件）都将保存在此目录下，方便统一管理与备份。',
                          'Clipboard history, favorites, notes, images, and files are stored here for backup and management.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: subColor.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _dataDirectory,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: textColor.withOpacity(0.9),
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
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton.icon(
                                    onPressed: () {
                                      widget.state.openDirectoryPath(
                                        _dataDirectory,
                                      );
                                    },
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
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                                  ? Colors.white.withOpacity(0.03)
                                  : Colors.black.withOpacity(0.03),
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
                                    color: subColor.withOpacity(0.8),
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
                              icon: const Icon(Icons.sync_rounded, size: 14),
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
                                  color: accentColor.withOpacity(0.4),
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
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Dialog Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  child: Text(
                    _text('取消', 'Cancel'),
                    style: TextStyle(color: subColor),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_text('保存', 'Save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
