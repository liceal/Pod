import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  late ThemeStyle _themeStyle;
  late double _backdropOpacity;
  late int _clipboardHistoryLimit;

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
    _themeStyle = widget.state.settings.themeStyle;
    _backdropOpacity = widget.state.settings.backdropOpacity;
    _clipboardHistoryLimit = widget.state.settings.clipboardHistoryLimit;
    _dataDirectory = widget.state.getDataDirectoryPathSync();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _selectDataDirectory() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择数据存储文件夹',
      );
      if (selected != null && mounted) {
        setState(() {
          _dataDirectory = selected.replaceAll('\\', '/');
        });
      }
    } catch (e) {
      debugPrint('Failed to select directory: $e');
    }
  }

  Future<void> _manualSyncData() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择源数据文件夹（导入合并）',
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
            '确认同步数据？',
            style: TextStyle(
              color: _isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            '即将从所选文件夹同步并合并数据（便签、剪贴板历史、图片、暂存文件）到当前的存储位置：\n$_dataDirectory\n\n注意：这不会覆盖已有的同名数据，而是进行增量合并。',
            style: TextStyle(
              color: _isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认同步'),
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
        builder: (ctx) => const Center(
          child: Card(
            color: Color(0xFF262626),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(
                    '正在同步并刷新数据...',
                    style: TextStyle(
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
            success ? '同步成功' : '同步失败',
            style: TextStyle(
              color: _isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            success ? '数据已成功同步并合并，界面已实时刷新！' : '数据同步失败，请检查文件夹权限或所选目录是否正确。',
            style: TextStyle(
              color: _isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      widget.state.setDialogOpen(false);
    } catch (e) {
      debugPrint('Failed to sync directory: $e');
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
      themeStyle: _themeStyle,
      backdropOpacity: _backdropOpacity,
      clipboardHistoryLimit: _clipboardHistoryLimit,
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
            '确认迁移数据？',
            style: TextStyle(
              color: _isDarkTheme ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            '检测到数据存储位置发生改变，是否立即将现有数据（包含历史记录、便签、图片及暂存文件）迁移到新目录下？',
            style: TextStyle(
              color: _isDarkTheme ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('仅更改路径(不迁移数据)'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('迁移数据(推荐)'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消保存'),
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
          builder: (ctx) => const Center(
            child: Card(
              color: Color(0xFF262626),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      '正在迁移数据，请稍候...',
                      style: TextStyle(
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
              title: const Text('错误'),
              content: const Text('数据迁移失败，未更改存储位置。请检查目标文件夹权限。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('确定'),
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
        return '混合模式 (快捷键、边缘悬停与滚轮)';
      case TriggerMode.hotkeyOnly:
        return '仅全局快捷键';
      case TriggerMode.hoverOnly:
        return '仅屏幕边缘悬停';
      case TriggerMode.scrollOnly:
        return '仅鼠标滚轮下滑';
    }
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
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'Pod 设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const Divider(height: 20),

            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trigger Mode Option
                    Text(
                      '唤醒方式',
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
                        '全局快捷键',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '可在任意界面快速呼出/收起面板。选择下方下拉框可更改快捷键：',
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
                              style: TextStyle(fontSize: 13, color: textColor),
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
                            '边缘悬停延迟',
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

                    // Panel Width config
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '面板宽度',
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
                                    '固定像素',
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
                                    '屏幕百分比',
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

                    // Backdrop opacity
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '背板透明度',
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
                      '主题颜色',
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

                    // Switches: Dark Theme & Close on Blur
                    // Auto-collapse after mouse exits
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '鼠标离开后自动收起',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: subColor,
                              ),
                            ),
                            Text(
                              _autoCollapseDelay == 0
                                  ? '已禁用'
                                  : '$_autoCollapseDelay 秒后收起',
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
                      max: 30,
                      divisions: 30,
                      activeColor: accentColor,
                      inactiveColor: _isDarkTheme
                          ? Colors.white12
                          : Colors.black12,
                      label: _autoCollapseDelay == 0
                          ? '禁用'
                          : '$_autoCollapseDelay 秒',
                      onChanged: (val) {
                        setState(() {
                          _autoCollapseDelay = val.toInt();
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    // Clipboard history limit
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '剪贴板记录上限',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                        Text(
                          '$_clipboardHistoryLimit 条',
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
                      label: '$_clipboardHistoryLimit 条',
                      onChanged: (val) {
                        setState(() {
                          _clipboardHistoryLimit = (val / 10).round() * 10;
                        });
                      },
                    ),
                    Text(
                      '超过上限时会自动删除最早的非收藏记录。',
                      style: TextStyle(
                        fontSize: 11,
                        color: subColor.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Switches: Dark Theme
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '深色主题',
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

                    const Divider(height: 24),
                    Text(
                      '数据存储位置',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '所有数据（剪贴板历史、收藏、便签、剪切板图片及暂存文件）都将保存在此目录下，方便统一管理与备份。',
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
                                  label: const Text(
                                    '更改位置',
                                    style: TextStyle(fontSize: 11),
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
                                  icon: const Icon(Icons.folder_open, size: 14),
                                  label: const Text(
                                    '打开目录',
                                    style: TextStyle(fontSize: 11),
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
                                    '默认存储路径（若旧数据丢失可从此处同步）：',
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
                            label: const Text(
                              '手动同步旧位置数据 / 导入其他文件夹数据',
                              style: TextStyle(fontSize: 11),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(
                                color: accentColor.withOpacity(0.4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                  child: Text('取消', style: TextStyle(color: subColor)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
