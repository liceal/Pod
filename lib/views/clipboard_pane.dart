import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/clipboard_item.dart';
import '../models/app_settings.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'components/animated_press.dart';

class ClipboardPane extends StatefulWidget {
  final AppState state;
  final bool isDark;

  const ClipboardPane({super.key, required this.state, required this.isDark});

  @override
  State<ClipboardPane> createState() => _ClipboardPaneState();
}

class _ClipboardPaneState extends State<ClipboardPane> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, Matrix4> _imageDetailTransforms = {};
  int _detailOpenVersion = 0;
  bool _showFavoritesOnly = false;
  bool _detailWrapCodeLines = true;
  ClipboardItem? _detailItem;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.state.searchClipboardQuery;
    _searchController.addListener(() {
      widget.state.searchClipboardQuery = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openDetail(ClipboardItem item) {
    setState(() {
      _detailOpenVersion++;
      _detailItem = item;
    });
  }

  void _closeDetail() {
    setState(() {
      final item = _detailItem;
      if (item != null) {
        _imageDetailTransforms.remove(item.id);
      }
      _detailItem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _showFavoritesOnly
        ? widget.state.filteredClipboardFavorites
        : widget.state.filteredClipboardHistory;
    final accentColor = AppTheme.getAccentColor(
      widget.state.settings.themeColorName,
      widget.isDark,
    );

    final isCompact = widget.state.settings.themeStyle == ThemeStyle.compact;
    final detailItem = _detailItem;
    final detailItemType = detailItem == null
        ? null
        : widget.state.getClipboardItemType(detailItem);
    final detailKeyVersion = detailItemType == 'IMAGE'
        ? widget.state.panelActivationVersion
        : 0;
    final listContent = items.isEmpty
        ? Center(
            child: Text(
              _showFavoritesOnly
                  ? (_searchController.text.isNotEmpty
                        ? '没有找到匹配的收藏项'
                        : '没有收藏的记录')
                  : (_searchController.text.isNotEmpty ? '没有找到匹配项' : '剪贴板历史为空'),
              style: TextStyle(
                fontSize: 12,
                color: widget.isDark
                    ? Colors.white30
                    : Colors.black.withOpacity(0.3),
              ),
            ),
          )
        : ListView.builder(
            key: PageStorageKey<String>(
              _showFavoritesOnly ? 'favs_list' : 'all_list',
            ),
            controller: _scrollController,
            itemCount: items.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final item = items[index];

              return ClipboardItemCard(
                key: ValueKey(item.id),
                item: item,
                isDark: widget.isDark,
                accentColor: accentColor,
                isFavorite: widget.state.isItemFavorite(item.content),
                onCopy: () => widget.state.copyToClipboard(item),
                onOpenDetail: () => _openDetail(item),
                onFavoriteToggle: () =>
                    widget.state.toggleFavoriteClipboardItem(item),
                onDelete: () {
                  if (_detailItem?.id == item.id) {
                    _detailItem = null;
                  }
                  _imageDetailTransforms.remove(item.id);
                  widget.state.deleteClipboardItem(item.id);
                  Future.delayed(Duration.zero, () {
                    if (mounted) setState(() {});
                  });
                },
              );
            },
          );
    return Padding(
      padding: EdgeInsets.all(isCompact ? 2.0 : 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Field & Favorite Toggle
          if (detailItem == null) ...[
            Listener(
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent &&
                    pointerSignal.scrollDelta.dy < 0) {
                  widget.state.collapsePanel();
                }
              },
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: isCompact ? 26 : 32,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(isCompact ? 0 : 8),
                      ),
                      child: TextField(
                        controller: _searchController,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(fontSize: isCompact ? 11 : 12),
                        decoration: InputDecoration(
                          hintText: _showFavoritesOnly
                              ? '搜索收藏记录...'
                              : '搜索剪贴板记录...',
                          hintStyle: TextStyle(
                            fontSize: isCompact ? 11 : 12,
                            color: widget.isDark
                                ? Colors.white30
                                : Colors.black.withOpacity(0.3),
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(
                              left: 8.0,
                              right: 6.0,
                            ),
                            child: Icon(
                              Icons.search_rounded,
                              size: 14,
                              color: widget.isDark
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.black.withOpacity(0.5),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 14,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: AnimatedPress(
                                      onTap: () => _searchController.clear(),
                                      child: const Icon(Icons.clear, size: 15),
                                    ),
                                  ),
                                )
                              : (widget
                                            .state
                                            .filteredClipboardHistory
                                            .isNotEmpty &&
                                        !_showFavoritesOnly
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: AnimatedPress(
                                            onTap: () async {
                                              widget.state.setDialogOpen(true);
                                              await showDialog(
                                                context: context,
                                                barrierColor:
                                                    Colors.transparent,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('清空剪贴板历史？'),
                                                  content: const Text(
                                                    '这将删除所有的剪贴板历史记录，此操作不可撤销。',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      child: const Text('取消'),
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            ctx,
                                                          ).pop(),
                                                    ),
                                                    TextButton(
                                                      child: const Text('立即清空'),
                                                      onPressed: () {
                                                        widget.state
                                                            .clearClipboardHistory();
                                                        setState(() {});
                                                        Navigator.of(ctx).pop();
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              );
                                              widget.state.setDialogOpen(false);
                                            },
                                            child: const Icon(
                                              Icons.delete_sweep_outlined,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      )
                                    : null),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 16,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isCompact ? 2 : 4),
                  Tooltip(
                    message: _showFavoritesOnly ? '所有记录' : '收藏记录',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedPress(
                        onTap: () {
                          setState(() {
                            _showFavoritesOnly = !_showFavoritesOnly;
                          });
                        },
                        child: Container(
                          width: isCompact ? 26 : 32,
                          height: isCompact ? 26 : 32,
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(
                              isCompact ? 0 : 8,
                            ),
                          ),
                          child: Icon(
                            _showFavoritesOnly
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 16,
                            color: _showFavoritesOnly
                                ? Colors.amber
                                : (widget.isDark
                                      ? Colors.white.withOpacity(0.6)
                                      : Colors.black.withOpacity(0.6)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isCompact ? 2 : 4),
          ],

          // History List with transition animation
          Expanded(
            child: detailItem != null
                ? _DetailDialogContent(
                    key: ValueKey(
                      'clipboard-detail-${detailItem.id}-$detailKeyVersion-$_detailOpenVersion',
                    ),
                    item: detailItem,
                    isDark: widget.isDark,
                    accentColor: accentColor,
                    onCopy: () => widget.state.copyToClipboard(detailItem),
                    embedded: true,
                    onBack: _closeDetail,
                    wrapCodeLines: _detailWrapCodeLines,
                    initialImageTransform: detailItemType == 'IMAGE'
                        ? _imageDetailTransforms[detailItem.id]
                        : null,
                    onImageTransformChanged: detailItemType == 'IMAGE'
                        ? (value) {
                            _imageDetailTransforms[detailItem.id] = value
                                .clone();
                          }
                        : null,
                    onWrapCodeLinesChanged: (value) {
                      _detailWrapCodeLines = value;
                    },
                  )
                : listContent,
          ),
        ],
      ),
    );
  }
}

class ClipboardItemCard extends StatefulWidget {
  final ClipboardItem item;
  final bool isDark;
  final Color accentColor;
  final bool isFavorite;
  final VoidCallback onCopy;
  final VoidCallback onOpenDetail;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;

  const ClipboardItemCard({
    super.key,
    required this.item,
    required this.isDark,
    required this.accentColor,
    required this.isFavorite,
    required this.onCopy,
    required this.onOpenDetail,
    required this.onFavoriteToggle,
    required this.onDelete,
  });

  @override
  State<ClipboardItemCard> createState() => _ClipboardItemCardState();
}

class _ClipboardItemCardState extends State<ClipboardItemCard> {
  bool _isHovered = false;
  bool _isCopied = false;
  bool _isDeleted = false;
  DateTime? _lastTapTime;

  Widget _buildAppIcon() {
    final iconPath = widget.item.appIconPath;
    if (iconPath != null && iconPath.isNotEmpty) {
      final file = File(iconPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: 14,
          height: 14,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.article_outlined,
            size: 14,
            color: widget.isDark ? Colors.white30 : Colors.black38,
          ),
        );
      }
    }
    return Icon(
      Icons.article_outlined,
      size: 14,
      color: widget.isDark ? Colors.white30 : Colors.black38,
    );
  }

  Widget _buildThumbnail(bool isCompact) {
    final width = isCompact ? 44.0 : 60.0;
    final height = isCompact ? 22.0 : 36.0;
    final imagePath = AppState().getImagePath(widget.item);
    final file = File(imagePath);
    if (file.existsSync()) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.red.withOpacity(0.1),
              child: const Icon(Icons.broken_image, size: 12),
            ),
          ),
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      color: Colors.grey.withOpacity(0.2),
      child: const Icon(Icons.broken_image, size: 12),
    );
  }

  Widget _buildBadge(String type) {
    final Color color = type == 'JSON'
        ? Colors.blue
        : (type == 'XML'
              ? Colors.green
              : (type == 'URL' ? Colors.indigo : Colors.blue));
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(widget.isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  void _handleTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
      _lastTapTime = null;
      widget.onOpenDetail();
      return;
    }
    _lastTapTime = now;
    widget.onCopy();
    setState(() => _isCopied = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  void _handleFavoriteToggle() {
    widget.onFavoriteToggle();
  }

  void _handleDelete() {
    setState(() => _isDeleted = true);
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeleted) return const SizedBox.shrink();

    final themeAccent = widget.accentColor;
    final isCompact = AppState().settings.themeStyle == ThemeStyle.compact;
    final itemType = AppState().getClipboardItemType(widget.item);

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(bottom: isCompact ? 1 : 3),
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: isCompact ? 3 : 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isCompact ? 0 : 6),
            border: Border.all(
              color: _isCopied
                  ? themeAccent.withOpacity(0.35)
                  : Colors.transparent,
              width: 1,
            ),
            gradient: _isCopied
                ? LinearGradient(
                    colors: [
                      themeAccent.withOpacity(0.16),
                      themeAccent.withOpacity(0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: !_isCopied && _isHovered
                ? (widget.isDark
                      ? Colors.white.withOpacity(0.04)
                      : Colors.black.withOpacity(0.03))
                : Colors.transparent,
            boxShadow: _isCopied
                ? [
                    BoxShadow(
                      color: themeAccent.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: widget.item.appName ?? '未知应用',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAppIcon(),
                      if (widget.item.imagePath == null &&
                          (itemType == 'JSON' ||
                              itemType == 'XML' ||
                              itemType == 'URL'))
                        _buildBadge(itemType),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    if (widget.item.imagePath != null)
                      _buildThumbnail(isCompact)
                    else
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: widget.isFavorite
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: _isCopied
                                ? themeAccent
                                : (widget.isDark
                                      ? Colors.white70
                                      : Colors.black87),
                          ),
                          child: Text(
                            widget.item.content.trim().replaceAll('\n', ' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Fixed-width right section — no layout shift
              SizedBox(
                width: 78,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                  child: _isCopied
                      ? SizedBox(
                          height: 24,
                          child: Row(
                            key: const ValueKey('copied_indicator'),
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: themeAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '已复制',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: themeAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SizedBox(
                          height: 24,
                          child: Row(
                            key: const ValueKey('normal_actions'),
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _IconActionButton(
                                icon: Icons.info_outline,
                                iconColor: widget.isDark
                                    ? Colors.white60
                                    : Colors.black54,
                                hoverBgColor: widget.isDark
                                    ? Colors.white.withOpacity(0.15)
                                    : Colors.black.withOpacity(0.1),
                                visible: _isHovered,
                                isDark: widget.isDark,
                                onTap: widget.onOpenDetail,
                              ),
                              _IconActionButton(
                                icon: widget.isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                iconColor: widget.isFavorite
                                    ? Colors.amber
                                    : (widget.isDark
                                          ? Colors.white60
                                          : Colors.black54),
                                hoverBgColor: widget.isDark
                                    ? Colors.amber.withOpacity(0.15)
                                    : Colors.amber.withOpacity(0.1),
                                visible: _isHovered || widget.isFavorite,
                                isDark: widget.isDark,
                                onTap: _handleFavoriteToggle,
                              ),
                              _IconActionButton(
                                icon: Icons.close,
                                iconColor: widget.isDark
                                    ? Colors.red.withOpacity(0.7)
                                    : Colors.red,
                                hoverBgColor: widget.isDark
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.red.withOpacity(0.1),
                                visible: _isHovered,
                                isDark: widget.isDark,
                                onTap: _handleDelete,
                              ),
                            ],
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

// ══════════════════════════════════════════════════
// Reusable icon button with independent hover highlight
// ══════════════════════════════════════════════════
class _IconActionButton extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color hoverBgColor;
  final bool visible;
  final bool isDark;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.iconColor,
    required this.hoverBgColor,
    required this.visible,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_IconActionButton> createState() => _IconActionButtonState();
}

class _IconActionButtonState extends State<_IconActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: widget.visible ? widget.iconColor : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Checkerboard Background Painter for Transparent PNGs
// ══════════════════════════════════════════════════
class CheckerboardPainter extends CustomPainter {
  final double squareSize;
  final Color lightColor;
  final Color darkColor;

  CheckerboardPainter({
    this.squareSize = 8.0,
    required this.lightColor,
    required this.darkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintLight = Paint()..color = lightColor;
    final paintDark = Paint()..color = darkColor;

    for (double y = 0; y < size.height; y += squareSize) {
      int row = (y / squareSize).floor();
      for (double x = 0; x < size.width; x += squareSize) {
        int col = (x / squareSize).floor();
        final rect = Rect.fromLTWH(x, y, squareSize, squareSize);
        if ((row + col) % 2 == 0) {
          canvas.drawRect(rect, paintLight);
        } else {
          canvas.drawRect(rect, paintDark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════
// Toolbar Button Component with Hover State
// ══════════════════════════════════════════════════
class _ToolbarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark
                        ? Colors.white12
                        : Colors.black.withOpacity(0.06))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: widget.isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Save Image to Desktop Action Button Component
// ══════════════════════════════════════════════════
class _HeaderSaveImageButton extends StatefulWidget {
  final String imagePath;
  final bool isDark;

  const _HeaderSaveImageButton({required this.imagePath, required this.isDark});

  @override
  State<_HeaderSaveImageButton> createState() => _HeaderSaveImageButtonState();
}

class _HeaderSaveImageButtonState extends State<_HeaderSaveImageButton> {
  bool _saved = false;
  bool _hovered = false;

  Future<void> _save() async {
    try {
      final desktopPath = Platform.environment['USERPROFILE'] != null
          ? '${Platform.environment['USERPROFILE']}\\Desktop'
          : null;
      if (desktopPath == null) return;

      final file = File(widget.imagePath);
      if (!file.existsSync()) return;

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final destFile = File('$desktopPath\\Pod_Clip_$timestamp.png');
      await file.copy(destFile.path);

      setState(() {
        _saved = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _saved = false;
          });
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _saved ? '已保存至桌面' : '保存图片到桌面',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _save,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _saved
                  ? Colors.green.withOpacity(0.2)
                  : (_hovered
                        ? (widget.isDark
                              ? Colors.white12
                              : Colors.black.withOpacity(0.06))
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              _saved ? Icons.check_rounded : Icons.save_alt_rounded,
              size: 14,
              color: _saved
                  ? Colors.green
                  : (widget.isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Open URL in Browser Action Button Component
// ══════════════════════════════════════════════════
class _HeaderOpenUrlButton extends StatefulWidget {
  final String url;
  final bool isDark;
  final Color accentColor;

  const _HeaderOpenUrlButton({
    required this.url,
    required this.isDark,
    required this.accentColor,
  });

  @override
  State<_HeaderOpenUrlButton> createState() => _HeaderOpenUrlButtonState();
}

class _HeaderOpenUrlButtonState extends State<_HeaderOpenUrlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '在浏览器打开链接',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () {
            AppState().openUrl(widget.url);
            Navigator.of(context).pop();
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.accentColor.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.open_in_new_rounded,
              size: 14,
              color: widget.accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Header Copy Button Component
// ══════════════════════════════════════════════════
class _HeaderCopyButton extends StatefulWidget {
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;

  const _HeaderCopyButton({
    required this.isDark,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_HeaderCopyButton> createState() => _HeaderCopyButtonState();
}

class _HeaderCopyButtonState extends State<_HeaderCopyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '复制内容并关闭',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.isDark
                        ? Colors.white12
                        : Colors.black.withOpacity(0.06))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.copy_all_rounded,
              size: 14,
              color: widget.isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Lightweight Detail Syntax Highlighting
// ══════════════════════════════════════════════════
const int _maxDetailHighlightLength = 120000;

final RegExp _detailJsonPattern = RegExp(
  r'("(?:\\.|[^"\\])*"\s*:)|("(?:\\.|[^"\\])*")|(\b(?:true|false|null)\b)|(-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)',
  multiLine: true,
);

final RegExp _detailXmlPattern = RegExp(
  r'''(<!--[\s\S]*?-->)|(<\/?[\w:.-]+)|([\w:.-]+)(?=\s*=)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(\/?>)''',
  multiLine: true,
);

final RegExp _detailCodePattern = RegExp(
  r'(//[^\n\r]*)|(/\*[\s\S]*?\*/)|("(?:\\.|[^"\\])*")|'
  r"('(?:\\.|[^'\\])*')|"
  r'\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|default|defer|def|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|func|function|get|if|implements|import|in|interface|is|late|let|library|mixin|namespace|new|null|operator|override|package|part|private|public|return|set|static|struct|super|switch|this|throw|true|try|typedef|using|var|void|while|with|yield)\b|'
  r'\b(String|int|double|num|bool|List|Map|Set|Future|Stream|Widget|State|BuildContext|[A-Z][A-Za-z0-9_]*)\b|'
  r'\b(\d+(?:\.\d+)?)\b|'
  r'\b([A-Za-z_][A-Za-z0-9_]*)(?=\s*\()',
  multiLine: true,
);

bool _canHighlightDetailText(String itemType, String text) {
  return (itemType == 'JSON' || itemType == 'XML' || itemType == 'CODE') &&
      text.length <= _maxDetailHighlightLength;
}

TextSpan _highlightMatches(
  String text,
  RegExp pattern,
  TextStyle baseStyle,
  TextStyle Function(Match match) styleFor,
) {
  final spans = <TextSpan>[];
  var lastIndex = 0;

  for (final match in pattern.allMatches(text)) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
    }
    spans.add(TextSpan(text: match.group(0), style: styleFor(match)));
    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    spans.add(TextSpan(text: text.substring(lastIndex)));
  }

  return TextSpan(style: baseStyle, children: spans);
}

TextSpan _highlightDetailJson(String text, bool isDark, TextStyle baseStyle) {
  final keyColor = isDark ? const Color(0xFF9CDCFE) : const Color(0xFF0451A5);
  final stringColor = isDark
      ? const Color(0xFFCE9178)
      : const Color(0xFFA31515);
  final numberColor = isDark
      ? const Color(0xFFB5CEA8)
      : const Color(0xFF098658);
  final boolColor = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);

  return _highlightMatches(text, _detailJsonPattern, baseStyle, (match) {
    if (match.group(1) != null) {
      return TextStyle(color: keyColor, fontWeight: FontWeight.w600);
    }
    if (match.group(2) != null) {
      return TextStyle(color: stringColor);
    }
    if (match.group(3) != null) {
      return TextStyle(color: boolColor, fontWeight: FontWeight.w600);
    }
    return TextStyle(color: numberColor);
  });
}

TextSpan _highlightDetailXml(String text, bool isDark, TextStyle baseStyle) {
  final tagColor = isDark ? const Color(0xFF569CD6) : const Color(0xFF800000);
  final attrColor = isDark ? const Color(0xFF9CDCFE) : const Color(0xFFFF0000);
  final valueColor = isDark ? const Color(0xFFCE9178) : const Color(0xFF0000FF);
  final commentColor = isDark
      ? Colors.white.withOpacity(0.35)
      : Colors.black.withOpacity(0.4);

  return _highlightMatches(text, _detailXmlPattern, baseStyle, (match) {
    if (match.group(1) != null) {
      return TextStyle(color: commentColor, fontStyle: FontStyle.italic);
    }
    if (match.group(2) != null || match.group(5) != null) {
      return TextStyle(color: tagColor, fontWeight: FontWeight.w600);
    }
    if (match.group(3) != null) {
      return TextStyle(color: attrColor);
    }
    return TextStyle(color: valueColor);
  });
}

TextSpan _highlightDetailCode(String text, bool isDark, TextStyle baseStyle) {
  final commentColor = isDark
      ? const Color(0xFF6A9955)
      : const Color(0xFF008000);
  final stringColor = isDark
      ? const Color(0xFFCE9178)
      : const Color(0xFFA31515);
  final keywordColor = isDark
      ? const Color(0xFF569CD6)
      : const Color(0xFF0000FF);
  final typeColor = isDark ? const Color(0xFF4EC9B0) : const Color(0xFF267F99);
  final numberColor = isDark
      ? const Color(0xFFB5CEA8)
      : const Color(0xFF098658);
  final functionColor = isDark
      ? const Color(0xFFDCDCAA)
      : const Color(0xFF795E26);

  return _highlightMatches(text, _detailCodePattern, baseStyle, (match) {
    if (match.group(1) != null || match.group(2) != null) {
      return TextStyle(color: commentColor, fontStyle: FontStyle.italic);
    }
    if (match.group(3) != null || match.group(4) != null) {
      return TextStyle(color: stringColor);
    }
    if (match.group(5) != null) {
      return TextStyle(color: keywordColor, fontWeight: FontWeight.w600);
    }
    if (match.group(6) != null) {
      return TextStyle(color: typeColor);
    }
    if (match.group(7) != null) {
      return TextStyle(color: numberColor);
    }
    return TextStyle(color: functionColor);
  });
}

TextSpan _highlightDetailText(
  String text,
  String itemType,
  bool isDark,
  TextStyle baseStyle,
) {
  if (text.length > _maxDetailHighlightLength) {
    return TextSpan(text: text, style: baseStyle);
  }

  return switch (itemType) {
    'JSON' => _highlightDetailJson(text, isDark, baseStyle),
    'XML' => _highlightDetailXml(text, isDark, baseStyle),
    'CODE' => _highlightDetailCode(text, isDark, baseStyle),
    _ => TextSpan(text: text, style: baseStyle),
  };
}

// ══════════════════════════════════════════════════
// Text / Image Detail Content Component
// ══════════════════════════════════════════════════
class _DetailDialogContent extends StatefulWidget {
  final ClipboardItem item;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onCopy;
  final bool embedded;
  final VoidCallback? onBack;
  final bool wrapCodeLines;
  final Matrix4? initialImageTransform;
  final ValueChanged<Matrix4>? onImageTransformChanged;
  final ValueChanged<bool>? onWrapCodeLinesChanged;

  const _DetailDialogContent({
    super.key,
    required this.item,
    required this.isDark,
    required this.accentColor,
    required this.onCopy,
    this.embedded = false,
    this.onBack,
    this.wrapCodeLines = true,
    this.initialImageTransform,
    this.onImageTransformChanged,
    this.onWrapCodeLinesChanged,
  });

  @override
  State<_DetailDialogContent> createState() => _DetailDialogContentState();
}

class _DetailDialogContentState extends State<_DetailDialogContent> {
  late final TransformationController _transformationController;
  late final ScrollController _scrollController;
  late final ScrollController _horizontalScrollController;

  bool _highlightEnabled = false;
  bool _isHighlightAvailable = false;
  bool _wrapCodeLines = true;

  int? _imgWidth;
  int? _imgHeight;
  String _fileSizeStr = '';
  String? _imagePath;
  File? _imageFile;
  TextSpan? _cachedDetailTextSpan;
  String? _cachedDetailText;
  String? _cachedDetailItemType;
  bool? _cachedDetailIsDark;
  bool? _cachedDetailHighlightEnabled;
  TextStyle? _cachedDetailTextStyle;
  double _lastImageViewportWidth = 320.0;
  double _lastImageViewportHeight = 220.0;
  double _swipeDistance = 0;
  bool _isImageDetail = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _scrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    _wrapCodeLines = widget.wrapCodeLines;

    final itemType = AppState().getClipboardItemType(widget.item);
    _isHighlightAvailable = _canHighlightDetailText(
      itemType,
      widget.item.content,
    );
    _highlightEnabled = _isHighlightAvailable;

    final isImage = itemType == 'IMAGE';
    _isImageDetail = isImage;
    if (isImage) {
      _imagePath = AppState().getImagePath(widget.item);
      _imageFile = File(_imagePath!);
      final initialTransform = widget.initialImageTransform;
      if (initialTransform != null) {
        _transformationController.value = initialTransform.clone();
      }
      _transformationController.addListener(_handleImageTransformChanged);
      _loadFileStats();
      _resolveImageSize();
    }
  }

  void _loadFileStats() {
    try {
      final file = _imageFile ?? File(AppState().getImagePath(widget.item));
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes > 1024 * 1024) {
          _fileSizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
        } else {
          _fileSizeStr = '${(bytes / 1024).toStringAsFixed(1)} KB';
        }
      }
    } catch (_) {}
  }

  void _resolveImageSize() {
    try {
      final provider = FileImage(
        _imageFile ?? File(AppState().getImagePath(widget.item)),
      );
      final stream = provider.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      var callbackCalled = false;
      var listenerAttached = false;
      listener = ImageStreamListener((ImageInfo info, bool _) {
        callbackCalled = true;
        if (listenerAttached) {
          stream.removeListener(listener);
          listenerAttached = false;
        }
        if (mounted) {
          setState(() {
            _imgWidth = info.image.width;
            _imgHeight = info.image.height;
          });
        }
      });
      stream.addListener(listener);
      listenerAttached = true;
      if (callbackCalled && listenerAttached) {
        stream.removeListener(listener);
        listenerAttached = false;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_isImageDetail) {
      _transformationController.removeListener(_handleImageTransformChanged);
    }
    _transformationController.dispose();
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _handleImageTransformChanged() {
    widget.onImageTransformChanged?.call(_transformationController.value);
  }

  void _zoomAt(double factor, Offset focalPoint) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.5, 5.0);
    final double actualFactor = targetScale / currentScale;

    if ((actualFactor - 1.0).abs() < 0.001) return;

    final double px = focalPoint.dx;
    final double py = focalPoint.dy;

    final translation = Matrix4.translationValues(px, py, 0.0);
    final scale = Matrix4.identity()..scale(actualFactor, actualFactor, 1.0);
    final invTranslation = Matrix4.translationValues(-px, -py, 0.0);

    final transform = translation * scale * invTranslation;
    _transformationController.value = transform * matrix;
  }

  void _zoom(double factor) {
    _zoomAt(
      factor,
      Offset(_lastImageViewportWidth / 2, _lastImageViewportHeight / 2),
    );
  }

  TextSpan _getDetailTextSpan(
    String displayText,
    String itemType,
    TextStyle textStyle,
  ) {
    if (_cachedDetailTextSpan != null &&
        _cachedDetailText == displayText &&
        _cachedDetailItemType == itemType &&
        _cachedDetailIsDark == widget.isDark &&
        _cachedDetailHighlightEnabled == _highlightEnabled &&
        _cachedDetailTextStyle == textStyle) {
      return _cachedDetailTextSpan!;
    }

    final span = _highlightEnabled
        ? _highlightDetailText(displayText, itemType, widget.isDark, textStyle)
        : TextSpan(text: displayText, style: textStyle);

    _cachedDetailTextSpan = span;
    _cachedDetailText = displayText;
    _cachedDetailItemType = itemType;
    _cachedDetailIsDark = widget.isDark;
    _cachedDetailHighlightEnabled = _highlightEnabled;
    _cachedDetailTextStyle = textStyle;

    return span;
  }

  void _reset() {
    _transformationController.value = Matrix4.identity();
  }

  bool get _hasHorizontalOverflow {
    return _horizontalScrollController.hasClients &&
        _horizontalScrollController.position.maxScrollExtent > 0.5;
  }

  bool _isRightSwipeSignal(double dx, double dy) {
    return widget.embedded &&
        !_hasHorizontalOverflow &&
        dx.abs() > 28 &&
        dx.abs() > dy.abs() * 1.4;
  }

  void _handleBackPointerSignal(PointerSignalEvent event) {
    if (!widget.embedded || event is! PointerScrollEvent) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    if (_isRightSwipeSignal(dx, dy)) {
      widget.onBack?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeAccent = widget.accentColor;
    final bgColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subColor = widget.isDark ? Colors.white54 : Colors.black45;
    final timeStr = DateFormat('HH:mm:ss').format(widget.item.timestamp);
    final itemType = AppState().getClipboardItemType(widget.item);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final isImage = itemType == 'IMAGE';
    final isLargeText = widget.item.content.length > 200000;

    final dialogWidth = isImage
        ? (screenWidth * 0.92).clamp(300.0, 720.0)
        : (screenWidth * 0.88).clamp(300.0, 620.0);
    final contentMaxHeight = isImage
        ? (screenHeight - 70.0).clamp(150.0, 290.0)
        : (screenHeight - 80.0).clamp(100.0, 255.0);

    final hasDimension = _imgWidth != null && _imgHeight != null;
    final infoText = hasDimension
        ? '${_imgWidth}×${_imgHeight} ($_fileSizeStr)'
        : _fileSizeStr;

    final displayText = widget.item.content;

    final detailBody = Container(
      width: widget.embedded ? double.infinity : dialogWidth,
      height: widget.embedded ? double.infinity : null,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isImage ? '图片详情' : '内容详情',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($timeStr)',
                      style: TextStyle(fontSize: 9, color: subColor),
                    ),
                    if (isImage && infoText.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        infoText,
                        style: TextStyle(fontSize: 9, color: subColor),
                      ),
                    ],
                    if (!isImage && isLargeText) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(超长文本已优化渲染性能)',
                        style: TextStyle(
                          fontSize: 9,
                          color: themeAccent.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    if (widget.embedded) ...[
                      _ToolbarButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: '返回列表',
                        isDark: widget.isDark,
                        onTap: widget.onBack ?? () {},
                      ),
                      const SizedBox(width: 4),
                    ],
                    // Zoom tools
                    if (isImage) ...[
                      _ToolbarButton(
                        icon: Icons.zoom_in_rounded,
                        tooltip: '放大',
                        isDark: widget.isDark,
                        onTap: () => _zoom(1.2),
                      ),
                      const SizedBox(width: 4),
                      _ToolbarButton(
                        icon: Icons.zoom_out_rounded,
                        tooltip: '缩小',
                        isDark: widget.isDark,
                        onTap: () => _zoom(0.8),
                      ),
                      const SizedBox(width: 4),
                      _ToolbarButton(
                        icon: Icons.settings_backup_restore_rounded,
                        tooltip: '重置',
                        isDark: widget.isDark,
                        onTap: _reset,
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Code highlight toggle
                    if (_isHighlightAvailable) ...[
                      Text(
                        '代码高亮',
                        style: TextStyle(fontSize: 9, color: subColor),
                      ),
                      const SizedBox(width: 2),
                      Transform.scale(
                        scale: 0.6,
                        child: Switch(
                          value: _highlightEnabled,
                          activeColor: themeAccent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            setState(() {
                              _highlightEnabled = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (!isImage) ...[
                      _ToolbarButton(
                        icon: _wrapCodeLines
                            ? Icons.wrap_text_rounded
                            : Icons.short_text_rounded,
                        tooltip: _wrapCodeLines ? '取消自动换行' : '自动换行',
                        isDark: widget.isDark,
                        onTap: () {
                          final willWrap = !_wrapCodeLines;
                          if (willWrap &&
                              _horizontalScrollController.hasClients) {
                            _horizontalScrollController.jumpTo(0);
                          }
                          setState(() {
                            _wrapCodeLines = willWrap;
                          });
                          widget.onWrapCodeLinesChanged?.call(willWrap);
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                    // Open URL button
                    if (itemType == 'URL') ...[
                      _HeaderOpenUrlButton(
                        url: widget.item.content,
                        isDark: widget.isDark,
                        accentColor: themeAccent,
                      ),
                      const SizedBox(width: 4),
                    ],
                    // Save image button
                    if (isImage) ...[
                      _HeaderSaveImageButton(
                        imagePath:
                            _imagePath ?? AppState().getImagePath(widget.item),
                        isDark: widget.isDark,
                      ),
                      const SizedBox(width: 4),
                    ],
                    // Copy button
                    _HeaderCopyButton(
                      isDark: widget.isDark,
                      accentColor: themeAccent,
                      onTap: () {
                        widget.onCopy();
                        if (!widget.embedded) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    // Close button
                    _ToolbarButton(
                      icon: Icons.close_rounded,
                      tooltip: widget.embedded ? '返回列表' : '关闭',
                      isDark: widget.isDark,
                      onTap: () {
                        if (widget.embedded) {
                          widget.onBack?.call();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),

          // Content
          if (widget.embedded)
            Expanded(
              child: _buildDetailContent(
                isImage: isImage,
                contentMaxHeight: contentMaxHeight,
                displayText: displayText,
                itemType: itemType,
                textColor: textColor,
                themeAccent: themeAccent,
              ),
            )
          else
            Flexible(
              child: _buildDetailContent(
                isImage: isImage,
                contentMaxHeight: contentMaxHeight,
                displayText: displayText,
                itemType: itemType,
                textColor: textColor,
                themeAccent: themeAccent,
              ),
            ),
        ],
      ),
    );

    if (widget.embedded) {
      final detailWithEsc = Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                widget.onBack?.call();
                return null;
              },
            ),
          },
          child: Focus(autofocus: true, child: detailBody),
        ),
      );

      if (isImage) {
        return detailWithEsc;
      }

      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handleBackPointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _swipeDistance = 0,
          onHorizontalDragUpdate: (details) {
            _swipeDistance += details.delta.dx;
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (!_hasHorizontalOverflow &&
                (_swipeDistance > 80 || velocity > 520)) {
              widget.onBack?.call();
            }
            _swipeDistance = 0;
          },
          onHorizontalDragCancel: () {
            _swipeDistance = 0;
          },
          child: detailWithEsc,
        ),
      );
    }

    final dialogWithEsc = Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: detailBody),
      ),
    );

    return Dialog(
      backgroundColor: bgColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: dialogWithEsc,
    );
  }

  Widget _buildDetailContent({
    required bool isImage,
    required double contentMaxHeight,
    required String displayText,
    required String itemType,
    required Color textColor,
    required Color themeAccent,
  }) {
    return Container(
      constraints: widget.embedded
          ? const BoxConstraints.expand()
          : BoxConstraints(maxHeight: contentMaxHeight),
      width: double.infinity,
      padding: isImage
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: isImage
          ? null
          : BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withOpacity(0.02)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(6),
            ),
      child: isImage
          ? LayoutBuilder(
              builder: (context, constraints) {
                _lastImageViewportWidth = constraints.maxWidth;
                _lastImageViewportHeight = constraints.maxHeight;
                final imageFile =
                    _imageFile ?? File(AppState().getImagePath(widget.item));

                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: CheckerboardPainter(
                              squareSize: 8.0,
                              lightColor: widget.isDark
                                  ? const Color(0xFF1C1C1C)
                                  : Colors.white,
                              darkColor: widget.isDark
                                  ? const Color(0xFF141414)
                                  : const Color(0xFFF2F2F2),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            maxScale: 5.0,
                            minScale: 0.5,
                            boundaryMargin: const EdgeInsets.all(240.0),
                            panEnabled: true,
                            scaleEnabled: true,
                            trackpadScrollCausesScale: true,
                            child: SizedBox(
                              width: double.infinity,
                              height: double.infinity,
                              child: Center(
                                child: Image.file(
                                  imageFile,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = constraints.maxWidth;
                final viewportHeight = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : contentMaxHeight;
                final textStyle = TextStyle(
                  fontSize: 10.5,
                  height: 1.32,
                  fontFamily: 'Menlo',
                  color: itemType == 'URL' ? themeAccent : textColor,
                  decoration: itemType == 'URL'
                      ? TextDecoration.underline
                      : null,
                );

                final textContent = Text.rich(
                  _getDetailTextSpan(displayText, itemType, textStyle),
                  softWrap: _wrapCodeLines,
                  overflow: TextOverflow.visible,
                );

                final scrollBehavior = ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false);

                if (_wrapCodeLines) {
                  return SelectionArea(
                    child: Scrollbar(
                      controller: _scrollController,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.vertical,
                      thumbVisibility: true,
                      thickness: 4,
                      radius: const Radius.circular(999),
                      child: ScrollConfiguration(
                        behavior: scrollBehavior,
                        child: SizedBox(
                          height: viewportHeight,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            child: SizedBox(
                              width: viewportWidth,
                              child: textContent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return SelectionArea(
                  child: Scrollbar(
                    controller: _scrollController,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.vertical,
                    thumbVisibility: true,
                    thickness: 4,
                    radius: const Radius.circular(999),
                    child: Scrollbar(
                      controller: _horizontalScrollController,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      thumbVisibility: false,
                      thickness: 3,
                      radius: const Radius.circular(999),
                      child: ScrollConfiguration(
                        behavior: scrollBehavior,
                        child: SizedBox(
                          height: viewportHeight,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            child: SingleChildScrollView(
                              controller: _horizontalScrollController,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: viewportWidth,
                                ),
                                child: textContent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
