import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/localization.dart';

/// 全局云端同步日志与状态查看弹窗
/// 位于便签顶栏设置按钮旁，点击感叹号/日志图标即可随时调出查看与手动触发同步
class GlobalSyncLogDialog extends StatefulWidget {
  final AppState state;
  final VoidCallback? onOpenSettings;

  const GlobalSyncLogDialog({
    super.key,
    required this.state,
    this.onOpenSettings,
  });

  static Future<void> show(
    BuildContext context, {
    required AppState state,
    VoidCallback? onOpenSettings,
  }) async {
    state.setDialogOpen(true);
    try {
      await showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (dialogCtx) => GlobalSyncLogDialog(
          state: state,
          onOpenSettings: onOpenSettings != null
              ? () {
                  Navigator.of(dialogCtx).pop();
                  onOpenSettings();
                }
              : null,
        ),
      );
    } finally {
      state.setDialogOpen(false);
    }
  }

  @override
  State<GlobalSyncLogDialog> createState() => _GlobalSyncLogDialogState();
}

class _GlobalSyncLogDialogState extends State<GlobalSyncLogDialog> {
  final ScrollController _scrollController = ScrollController();
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateUpdated);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateUpdated() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _copyLogs() {
    final text = widget.state.d1SyncLogs.join('\n');
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String _formatTime(DateTime? time) {
    if (time == null) return context.text('暂未同步', 'Never');
    final now = DateTime.now();
    final diff = now.difference(time);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    if (diff.inSeconds < 45) {
      return context.text('刚刚 ($timeStr)', 'Just now ($timeStr)');
    } else if (diff.inMinutes < 60) {
      return context.text('${diff.inMinutes} 分钟前 ($timeStr)', '${diff.inMinutes}m ago ($timeStr)');
    } else {
      return timeStr;
    }
  }

  Color _getLineColor(String line) {
    if (line.contains('❌') || line.contains('失败') || line.contains('Error') || line.contains('error')) {
      return const Color(0xFFEF9A9A);
    }
    if (line.contains('✅') || line.contains('已增量同步') || line.contains('完成') || line.contains('成功')) {
      return const Color(0xFFA5D6A7);
    }
    if (line.contains('⚠️') || line.contains('提示') || line.contains('Warning')) {
      return const Color(0xFFFFE082);
    }
    if (line.contains('🔍') || line.contains('⚡') || line.contains('比对')) {
      return const Color(0xFF90CAF9);
    }
    if (line.contains('📁') || line.contains('⏰') || line.contains('触发')) {
      return const Color(0xFFCE93D8);
    }
    return Colors.white.withValues(alpha: 0.85);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.state.settings.isDarkTheme;
    final accentColor = AppTheme.getAccentColor(
      widget.state.settings.themeColorName,
      isDark,
    );
    final isSyncing = widget.state.isD1Syncing || widget.state.isR2Syncing;
    final hasError = widget.state.lastD1SyncSuccess == false;
    final lastTime = widget.state.lastD1SyncTime;
    final logs = widget.state.d1SyncLogs;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 318),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2128) : const Color(0xFFF9FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶栏标题与操作区
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasError ? Icons.error_outline_rounded : Icons.cloud_sync_rounded,
                      size: 16,
                      color: hasError ? const Color(0xFFE57373) : accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.text('云端同步日志与状态', 'Cloud Sync Status & Logs'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 状态 Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSyncing
                            ? accentColor.withValues(alpha: 0.15)
                            : (hasError
                                ? const Color(0xFFEF5350).withValues(alpha: 0.15)
                                : (widget.state.lastD1SyncSuccess == true
                                    ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                                    : Colors.grey.withValues(alpha: 0.15))),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSyncing) ...[
                            SizedBox(
                              width: 9,
                              height: 9,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            isSyncing
                                ? context.text('后台同步中...', 'Syncing...')
                                : (hasError
                                    ? context.text('同步异常', 'Error')
                                    : (widget.state.lastD1SyncSuccess == true
                                        ? context.text('正常', 'Healthy')
                                        : context.text('待命就绪', 'Idle'))),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: isSyncing
                                  ? accentColor
                                  : (hasError
                                      ? const Color(0xFFEF5350)
                                      : (widget.state.lastD1SyncSuccess == true
                                          ? const Color(0xFF4CAF50)
                                          : Colors.grey)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // 「立即同步」按钮
                    SizedBox(
                      height: 24,
                      child: TextButton.icon(
                        onPressed: isSyncing
                            ? null
                            : () => widget.state.syncAllLocalDataAndFiles(isManual: true),
                        icon: isSyncing
                            ? SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: accentColor),
                              )
                            : Icon(Icons.refresh_rounded, size: 13, color: accentColor),
                        label: Text(
                          isSyncing ? context.text('同步中', 'Syncing') : context.text('立即同步', 'Sync Now'),
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: accentColor),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                          backgroundColor: accentColor.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 「复制日志」按钮
                    Tooltip(
                      message: _copied
                          ? context.text('已复制到剪贴板！', 'Copied to clipboard!')
                          : context.text('复制全部日志', 'Copy logs'),
                      child: InkWell(
                        onTap: _copyLogs,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 14,
                            color: _copied ? Colors.green : (isDark ? Colors.white60 : Colors.black54),
                          ),
                        ),
                      ),
                    ),
                    // 「清空日志」按钮
                    Tooltip(
                      message: context.text('清空控制台日志', 'Clear console logs'),
                      child: InkWell(
                        onTap: () => widget.state.clearD1Logs(),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 14,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    // 「设置」入口
                    if (widget.onOpenSettings != null)
                      Tooltip(
                        message: context.text('转到同步配置设置...', 'Open Sync Settings...'),
                        child: InkWell(
                          onTap: widget.onOpenSettings,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.settings_outlined,
                              size: 14,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    // 「关闭」
                    Tooltip(
                      message: context.text('关闭', 'Close'),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. 状态简报条
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.015),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 12, color: isDark ? Colors.white54 : Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      '${context.text('上次同步:', 'Last:')} ${_formatTime(lastTime)}',
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.repeat_rounded, size: 12, color: isDark ? Colors.white54 : Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      widget.state.settings.cfD1AutoSync
                          ? '${context.text('定时同步:', 'Interval:')} ${context.text('每 ${widget.state.settings.cfD1SyncIntervalMinutes} 分钟', 'Every ${widget.state.settings.cfD1SyncIntervalMinutes}m')}'
                          : context.text('定时同步: 已停用', 'Interval: Off'),
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    const Spacer(),
                    if (widget.state.lastD1SyncMessage != null)
                      Expanded(
                        flex: 2,
                        child: Text(
                          widget.state.lastD1SyncMessage!,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: hasError ? const Color(0xFFE57373) : (isDark ? Colors.white60 : Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ),
              ),

              // 3. 实时终端控制台日志区
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF11141A) : const Color(0xFF1B1E26),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: logs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.terminal_rounded,
                                size: 28,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.text(
                                  '暂无同步日志\n点击右上角「立即同步」即可开始执行云端增量同步',
                                  'No sync logs yet.\nClick "Sync Now" to start differential sync.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white.withValues(alpha: 0.35),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: logs.length,
                            itemBuilder: (context, idx) {
                              final line = logs[idx];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1.5),
                                child: SelectableText(
                                  line,
                                  style: TextStyle(
                                    fontFamily: Platform.isWindows ? 'Consolas' : 'Menlo, Courier, monospace',
                                    fontSize: 10.5,
                                    height: 1.25,
                                    color: _getLineColor(line),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
