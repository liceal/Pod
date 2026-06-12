import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/clipboard_item.dart';
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
        : NotificationListener<OverscrollNotification>(
            onNotification: (notification) {
              if (notification.overscroll < 0) {
                if (widget.state.isExpanded && !widget.state.isAnimating) {
                  widget.state.collapsePanel();
                  return true;
                }
              }
              return false;
            },
            child: ListView.builder(
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
            ),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
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
                      height: 26,
                      decoration: BoxDecoration(
                        color: widget.isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.zero,
                      ),
                      child: TextField(
                        controller: _searchController,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: _showFavoritesOnly
                              ? '搜索收藏记录...'
                              : '搜索剪贴板记录...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: widget.isDark
                                ? Colors.white30
                                : Colors.black54,
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
                  const SizedBox(width: 2),
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
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.zero,
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
            const SizedBox(height: 2),
          ],

          // History List with transition animation
          Expanded(
            child: detailItem != null
                ? _DetailDialogContent(
                    key: ValueKey(
                      'clipboard-detail-${detailItem.id}-$detailKeyVersion-$_detailOpenVersion',
                    ),
                    item: detailItem,
                    state: widget.state,
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
      return Image.file(
        File(iconPath),
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
    return Icon(
      Icons.article_outlined,
      size: 14,
      color: widget.isDark ? Colors.white30 : Colors.black38,
    );
  }

  Widget _buildThumbnail() {
    const double width = 44.0;
    const double height = 22.0;
    final imagePath = AppState().getImagePath(widget.item);
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
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: widget.isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.black.withOpacity(0.04),
            child: const Icon(Icons.broken_image, size: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String type) {
    final Color color = type == 'URL'
        ? Colors.indigo
        : (type == 'IMAGE'
              ? Colors.teal
              : (type == 'COLOR'
                    ? Colors.deepOrange
                    : (type == 'DATETIME' ? Colors.purple : Colors.blue)));
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
    final itemType = AppState().getClipboardItemType(widget.item);
    final itemTextStyle = Theme.of(context).textTheme.bodySmall;

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
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
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
                        if (itemType == 'URL' ||
                            itemType == 'IMAGE' ||
                            itemType == 'COLOR' ||
                            itemType == 'DATETIME')
                          _buildBadge(itemType),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (widget.item.imagePath != null)
                        _buildThumbnail()
                      else if (itemType == 'COLOR')
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color:
                                      AppState().parseColor(
                                        widget.item.content,
                                      ) ??
                                      Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: widget.isDark
                                        ? Colors.white30
                                        : Colors.black26,
                                    width: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  style: (itemTextStyle ?? const TextStyle()).copyWith(
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
                                    widget.item.content.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (itemType == 'DATETIME')
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 12,
                                color: widget.isDark
                                    ? Colors.white30
                                    : Colors.black38,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                  style: (itemTextStyle ?? const TextStyle()).copyWith(
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
                                    '${widget.item.content.trim()} ➔ ${DateFormat('yyyy-MM-dd HH:mm:ss').format(AppState().parseTimestamp(widget.item.content)!)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            style: (itemTextStyle ?? const TextStyle()).copyWith(
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
                // Dynamic-width right section — collapses completely to let text stretch to the right
                _isCopied
                    ? SizedBox(
                        height: 24,
                        child: Row(
                          key: const ValueKey('copied_indicator'),
                          mainAxisSize: MainAxisSize.min,
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
                    : (_isHovered || widget.isFavorite)
                    ? SizedBox(
                        height: 24,
                        child: Row(
                          key: const ValueKey('normal_actions'),
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isHovered) ...[
                              _IconActionButton(
                                icon: Icons.info_outline,
                                iconColor: widget.isDark
                                    ? Colors.white60
                                    : Colors.black54,
                                hoverBgColor: widget.isDark
                                    ? Colors.white.withOpacity(0.15)
                                    : Colors.black.withOpacity(0.1),
                                isDark: widget.isDark,
                                onTap: widget.onOpenDetail,
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (_isHovered || widget.isFavorite) ...[
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
                                isDark: widget.isDark,
                                onTap: _handleFavoriteToggle,
                              ),
                              if (_isHovered) const SizedBox(width: 4),
                            ],
                            if (_isHovered)
                              _IconActionButton(
                                icon: Icons.close,
                                iconColor: widget.isDark
                                    ? Colors.red.withOpacity(0.7)
                                    : Colors.red,
                                hoverBgColor: widget.isDark
                                    ? Colors.red.withOpacity(0.15)
                                    : Colors.red.withOpacity(0.1),
                                isDark: widget.isDark,
                                onTap: _handleDelete,
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
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
  final bool isDark;
  final VoidCallback onTap;

  const _IconActionButton({
    required this.icon,
    required this.iconColor,
    required this.hoverBgColor,
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
          child: Icon(widget.icon, size: 14, color: widget.iconColor),
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
// Text / Image Detail Content Component
// ══════════════════════════════════════════════════
class _DetailDialogContent extends StatefulWidget {
  final ClipboardItem item;
  final AppState state;
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
    required this.state,
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

  bool _wrapCodeLines = true;

  int? _imgWidth;
  int? _imgHeight;
  String _fileSizeStr = '';
  String? _imagePath;
  File? _imageFile;
  double _lastImageViewportWidth = 320.0;
  double _lastImageViewportHeight = 220.0;
  bool _isImageDetail = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _scrollController = ScrollController();
    _horizontalScrollController = ScrollController();
    _wrapCodeLines = widget.wrapCodeLines;

    final itemType = AppState().getClipboardItemType(widget.item);
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
    if (event is! PointerScrollEvent) return;

    if (!_isImageDetail &&
        _isTextZoomModifierPressed &&
        event.scrollDelta.dy != 0) {
      final direction = event.scrollDelta.dy < 0 ? 1.0 : -1.0;
      widget.state.updateTextContentFontSize(
        widget.state.settings.textContentFontSize + direction,
      );
      setState(() {});
      return;
    }

    if (!widget.embedded) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    if (_isRightSwipeSignal(dx, dy)) {
      widget.onBack?.call();
    }
  }

  bool get _isTextZoomModifierPressed {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
  }

  void _handleBackMouseButton(PointerDownEvent event) {
    if (!widget.embedded) return;
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kBackMouseButton) != 0) {
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
        ? '$_imgWidth×$_imgHeight ($_fileSizeStr)'
        : _fileSizeStr;

    final displayText = widget.item.content;

    final detailBody = Container(
      width: widget.embedded ? double.infinity : dialogWidth,
      height: widget.embedded ? double.infinity : null,
      padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            height: widget.embedded ? 26.0 : null,
            padding: widget.embedded
                ? const EdgeInsets.symmetric(horizontal: 8.0)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isImage ? '图片详情' : '内容详情',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($timeStr)',
                      style: TextStyle(fontSize: 14, color: subColor),
                    ),
                    if (isImage && infoText.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        infoText,
                        style: TextStyle(fontSize: 14, color: subColor),
                      ),
                    ],
                    if (!isImage && isLargeText) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(超长文本已优化渲染性能)',
                        style: TextStyle(
                          fontSize: 14,
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
          SizedBox(height: widget.embedded ? 2.0 : 3.0),

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
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleBackMouseButton,
          child: detailWithEsc,
        );
      }

      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleBackMouseButton,
        onPointerSignal: _handleBackPointerSignal,
        child: detailWithEsc,
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
      child: Listener(
        onPointerSignal: _handleBackPointerSignal,
        child: dialogWithEsc,
      ),
    );
  }

  Widget _buildFormatCopyRow(
    String label,
    String value,
    Color themeAccent,
    Color textColor,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.isDark ? Colors.white10 : Colors.black12,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white30 : Colors.black45,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 11,
                color: textColor,
              ),
            ),
          ),
          _CopyButton(value: value, themeAccent: themeAccent),
        ],
      ),
    );
  }

  Widget _buildColorDetailDashboard(
    String text,
    Color themeAccent,
    Color textColor,
    double contentMaxHeight,
  ) {
    final parsedColor = AppState().parseColor(text) ?? Colors.transparent;
    final r = parsedColor.red;
    final g = parsedColor.green;
    final b = parsedColor.blue;
    final opacity = parsedColor.opacity;

    final hexStr =
        '#${parsedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final rgbStr = 'rgb($r, $g, $b)';
    final rgbaStr = 'rgba($r, $g, $b, ${opacity.toStringAsFixed(2)})';
    final flutterStr =
        'Color(0x${parsedColor.value.toRadixString(16).toUpperCase()})';

    return Container(
      constraints: BoxConstraints(maxHeight: contentMaxHeight),
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: parsedColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.isDark ? Colors.white24 : Colors.black12,
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: parsedColor.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: themeAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  opacity < 1.0 ? '透明色' : '不透明',
                  style: TextStyle(
                    fontSize: 9,
                    color: themeAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildFormatCopyRow('HEX', hexStr, themeAccent, textColor),
                  _buildFormatCopyRow('RGB', rgbStr, themeAccent, textColor),
                  _buildFormatCopyRow('RGBA', rgbaStr, themeAccent, textColor),
                  _buildFormatCopyRow(
                    'Flutter',
                    flutterStr,
                    themeAccent,
                    textColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatetimeDetailDashboard(
    String text,
    Color themeAccent,
    Color textColor,
    double contentMaxHeight,
  ) {
    final dt = AppState().parseTimestamp(text);
    if (dt == null) return const SizedBox.shrink();

    final localStr = DateFormat('yyyy-MM-dd / HH:mm:ss').format(dt);
    final utcStr =
        DateFormat('yyyy-MM-dd / HH:mm:ss').format(dt.toUtc()) + ' UTC';
    final isoStr = dt.toIso8601String();

    final weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final weekdayStr = weekdays[dt.weekday - 1];

    final tzOffset = dt.timeZoneOffset;
    final tzSign = tzOffset.isNegative ? '-' : '+';
    final tzHours = tzOffset.inHours.abs().toString().padLeft(2, '0');
    final tzMins = (tzOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final tzStr = 'GMT$tzSign$tzHours:$tzMins';

    return Container(
      constraints: BoxConstraints(maxHeight: contentMaxHeight),
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isDark ? Colors.white10 : Colors.black12,
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 20,
                  color: themeAccent,
                ),
                const SizedBox(height: 8),
                Text(
                  weekdayStr,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tzStr,
                  style: TextStyle(
                    fontSize: 8,
                    color: widget.isDark ? Colors.white30 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildFormatCopyRow('本地时间', localStr, themeAccent, textColor),
                  _buildFormatCopyRow('UTC 时间', utcStr, themeAccent, textColor),
                  _buildFormatCopyRow(
                    'ISO 8601',
                    isoStr,
                    themeAccent,
                    textColor,
                  ),
                  _buildFormatCopyRow('原始戳', text, themeAccent, textColor),
                ],
              ),
            ),
          ),
        ],
      ),
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
          : (itemType == 'COLOR'
                ? _buildColorDetailDashboard(
                    displayText,
                    themeAccent,
                    textColor,
                    contentMaxHeight,
                  )
                : (itemType == 'DATETIME'
                      ? _buildDatetimeDetailDashboard(
                          displayText,
                          themeAccent,
                          textColor,
                          contentMaxHeight,
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final viewportHeight = constraints.hasBoundedHeight
                                ? constraints.maxHeight
                                : contentMaxHeight;
                            final contentFontSize =
                                widget.state.settings.textContentFontSize;
                            final textStyle =
                                (Theme.of(context).textTheme.bodySmall ??
                                        const TextStyle())
                                    .copyWith(
                              fontSize: contentFontSize,
                              height: 1.32,
                              color: itemType == 'URL'
                                  ? themeAccent
                                  : textColor,
                              decoration: itemType == 'URL'
                                  ? TextDecoration.underline
                                  : null,
                            );

                            final scrollBehavior = ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false);

                            Widget finalContainer;
                            if (displayText.length > 30000) {
                              finalContainer = SizedBox(
                                height: viewportHeight,
                                child: _LargeTextDetailView(
                                  text: displayText,
                                  style: textStyle,
                                  wrapLines: _wrapCodeLines,
                                  verticalController: _scrollController,
                                  horizontalController:
                                      _horizontalScrollController,
                                ),
                              );
                            } else if (_wrapCodeLines) {
                              finalContainer = ScrollConfiguration(
                                behavior: scrollBehavior,
                                child: SizedBox(
                                  height: viewportHeight,
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    physics: const BouncingScrollPhysics(),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: SelectableText(
                                        displayText,
                                        style: textStyle,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              finalContainer = ScrollConfiguration(
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
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: SelectableText(
                                          displayText,
                                          style: textStyle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            if (_wrapCodeLines) {
                              return Scrollbar(
                                controller: _scrollController,
                                notificationPredicate: (n) =>
                                    n.metrics.axis == Axis.vertical,
                                thumbVisibility: true,
                                thickness: 4,
                                radius: const Radius.circular(999),
                                child: finalContainer,
                              );
                            }

                            return Scrollbar(
                              controller: _scrollController,
                              notificationPredicate: (n) =>
                                  n.metrics.axis == Axis.vertical,
                              thumbVisibility: true,
                              thickness: 4,
                              radius: const Radius.circular(999),
                              child: Scrollbar(
                                controller: _horizontalScrollController,
                                notificationPredicate: (n) =>
                                    n.metrics.axis == Axis.horizontal,
                                thumbVisibility: false,
                                thickness: 3,
                                radius: const Radius.circular(999),
                                child: finalContainer,
                              ),
                            );
                          },
                        ))),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String value;
  final Color themeAccent;
  const _CopyButton({required this.value, required this.themeAccent});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.value));
          if (mounted) {
            setState(() => _copied = true);
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) setState(() => _copied = false);
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _copied
                ? Colors.green.withOpacity(0.15)
                : widget.themeAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            _copied ? Icons.check_rounded : Icons.copy_all_rounded,
            size: 11,
            color: _copied ? Colors.green : widget.themeAccent,
          ),
        ),
      ),
    );
  }
}

class _LargeTextDetailView extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool wrapLines;
  final ScrollController verticalController;
  final ScrollController horizontalController;

  const _LargeTextDetailView({
    required this.text,
    required this.style,
    required this.wrapLines,
    required this.verticalController,
    required this.horizontalController,
  });

  @override
  State<_LargeTextDetailView> createState() => _LargeTextDetailViewState();
}

class _LargeTextDetailViewState extends State<_LargeTextDetailView> {
  late List<String> _lines;

  @override
  void initState() {
    super.initState();
    _lines = widget.text.split('\n');
  }

  @override
  void didUpdateWidget(_LargeTextDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _lines = widget.text.split('\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scrollBehavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);

    if (widget.wrapLines) {
      return SelectionArea(
        child: ScrollConfiguration(
          behavior: scrollBehavior,
          child: ListView.builder(
            controller: widget.verticalController,
            physics: const BouncingScrollPhysics(),
            itemCount: _lines.length,
            padding: const EdgeInsets.all(8.0),
            itemBuilder: (context, index) {
              return Text(_lines[index], style: widget.style);
            },
          ),
        ),
      );
    } else {
      return SelectionArea(
        child: ScrollConfiguration(
          behavior: scrollBehavior,
          child: SingleChildScrollView(
            controller: widget.horizontalController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: 10000,
              child: ListView.builder(
                controller: widget.verticalController,
                physics: const BouncingScrollPhysics(),
                itemCount: _lines.length,
                padding: const EdgeInsets.all(8.0),
                itemBuilder: (context, index) {
                  return Text(
                    _lines[index],
                    style: widget.style,
                    softWrap: false,
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
  }
}
