import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  bool _showFavoritesOnly = false;

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
    return Padding(
      padding: EdgeInsets.all(isCompact ? 2.0 : 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Field & Favorite Toggle
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
                          padding: const EdgeInsets.only(left: 8.0, right: 6.0),
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
                                              barrierColor: Colors.transparent,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('清空剪贴板历史？'),
                                                content: const Text(
                                                  '这将删除所有的剪贴板历史记录，此操作不可撤销。',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text('取消'),
                                                    onPressed: () =>
                                                        Navigator.of(ctx).pop(),
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
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
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

          // History List with transition animation
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<bool>(_showFavoritesOnly),
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          _showFavoritesOnly
                              ? (_searchController.text.isNotEmpty
                                    ? '没有找到匹配的收藏项'
                                    : '没有收藏的记录')
                              : (_searchController.text.isNotEmpty
                                    ? '没有找到匹配项'
                                    : '剪贴板历史为空'),
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
                            isFavorite: widget.state.isItemFavorite(
                              item.content,
                            ),
                            onCopy: () =>
                                widget.state.copyToClipboard(item),
                            onFavoriteToggle: () =>
                                widget.state.toggleFavoriteClipboardItem(item),
                            onDelete: () {
                              widget.state.deleteClipboardItem(item.id);
                              // Deferred rebuild — card hides instantly via its own state
                              Future.delayed(Duration.zero, () {
                                if (mounted) setState(() {});
                              });
                            },
                          );
                        },
                      ),
              ),
            ),
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
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;

  const ClipboardItemCard({
    super.key,
    required this.item,
    required this.isDark,
    required this.accentColor,
    required this.isFavorite,
    required this.onCopy,
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
        : (type == 'XML' ? Colors.green : (type == 'URL' ? Colors.indigo : Colors.blue));
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(widget.isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 0.5,
        ),
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

  void _showAllContentDialog(BuildContext context) async {
    AppState().setDialogOpen(true);
    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => _DetailDialogContent(
        item: widget.item,
        isDark: widget.isDark,
        accentColor: widget.accentColor,
        onCopy: widget.onCopy,
      ),
    );
    AppState().setDialogOpen(false);
  }

  void _handleTap() {
    if (_isCopied) {
      _showAllContentDialog(context);
      return;
    }
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
                      if (widget.item.imagePath == null && (itemType == 'JSON' || itemType == 'XML' || itemType == 'URL'))
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
                                : (widget.isDark ? Colors.white70 : Colors.black87),
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
                                onTap: () => _showAllContentDialog(context),
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
// Advanced Image Detail Preview component with controller
// ══════════════════════════════════════════════════
class _ImageDetailPreview extends StatefulWidget {
  final String imagePath;
  final bool isDark;

  const _ImageDetailPreview({required this.imagePath, required this.isDark});

  @override
  State<_ImageDetailPreview> createState() => _ImageDetailPreviewState();
}

class _ImageDetailPreviewState extends State<_ImageDetailPreview> {
  final TransformationController _transformationController = TransformationController();
  int? _width;
  int? _height;
  String _fileSize = '';
  double _lastWidth = 500.0;
  double _lastHeight = 260.0;

  @override
  void initState() {
    super.initState();
    _loadImageInfo();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _loadImageInfo() {
    try {
      final file = File(widget.imagePath);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes > 1024 * 1024) {
          _fileSize = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
        } else {
          _fileSize = '${(bytes / 1024).toStringAsFixed(1)} KB';
        }

        final provider = FileImage(file);
        final stream = provider.resolve(const ImageConfiguration());
        ImageStreamListener? listener;
        bool callbackCalled = false;
        listener = ImageStreamListener((ImageInfo info, bool _) {
          callbackCalled = true;
          if (listener != null) {
            stream.removeListener(listener!);
          }
          if (mounted) {
            setState(() {
              _width = info.image.width;
              _height = info.image.height;
            });
          }
        });
        stream.addListener(listener);
        if (callbackCalled && listener != null) {
          stream.removeListener(listener);
        }
      }
    } catch (_) {}
  }

  void _zoom(double factor) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.5, 5.0);
    final double actualFactor = targetScale / currentScale;

    if ((actualFactor - 1.0).abs() < 0.001) return;

    final double px = _lastWidth / 2;
    final double py = _lastHeight / 2;

    final translation = Matrix4.translationValues(px, py, 0.0);
    final scale = Matrix4.identity()..scale(actualFactor, actualFactor, 1.0);
    final invTranslation = Matrix4.translationValues(-px, -py, 0.0);

    final transform = translation * scale * invTranslation;
    _transformationController.value = transform * matrix;
  }

  void _reset() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final hasDimension = _width != null && _height != null;
    final infoText = hasDimension ? '${_width} × ${_height} ($_fileSize)' : _fileSize;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (infoText.isNotEmpty)
                Text(
                  infoText,
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.isDark ? Colors.white38 : Colors.black38,
                  ),
                )
              else
                const SizedBox(),
              Row(
                children: [
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
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _lastWidth = constraints.maxWidth;
              _lastHeight = constraints.maxHeight;

              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: widget.isDark ? const Color(0xFF151515) : const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: CheckerboardPainter(
                            squareSize: 8.0,
                            lightColor: widget.isDark ? const Color(0xFF1C1C1C) : Colors.white,
                            darkColor: widget.isDark ? const Color(0xFF141414) : const Color(0xFFF2F2F2),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          maxScale: 5.0,
                          minScale: 0.5,
                          boundaryMargin: const EdgeInsets.all(240.0),
                          child: SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: Center(
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
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
                  ? (widget.isDark ? Colors.white12 : Colors.black.withOpacity(0.06))
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
                      ? (widget.isDark ? Colors.white12 : Colors.black.withOpacity(0.06))
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
                  ? (widget.isDark ? Colors.white12 : Colors.black.withOpacity(0.06))
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
// Lightweight Syntax Highlighting for JSON / XML
// ══════════════════════════════════════════════════
TextSpan _highlightJson(String text, bool isDark) {
  final keyColor = isDark ? const Color(0xFFCE9178) : const Color(0xFF0451A5);
  final stringColor = isDark ? const Color(0xFFCE9178) : const Color(0xFFA31515);
  final numberColor = isDark ? const Color(0xFFB5CEA8) : const Color(0xFF098658);
  final boolColor = isDark ? const Color(0xFF569CD6) : const Color(0xFF0000FF);
  final defaultColor = isDark ? Colors.white70 : Colors.black87;

  final List<TextSpan> spans = [];
  final regExp = RegExp(
    r'("[^"]*"\s*:)|("[^"]*")|(\b(?:true|false|null)\b)|(-?\d+(?:\.\d+)?)',
    multiLine: true,
  );

  int lastIndex = 0;
  for (final match in regExp.allMatches(text)) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(
        text: text.substring(lastIndex, match.start),
        style: TextStyle(color: defaultColor),
      ));
    }

    if (match.group(1) != null) {
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(color: keyColor, fontWeight: FontWeight.w600),
      ));
    } else if (match.group(2) != null) {
      spans.add(TextSpan(
        text: match.group(2),
        style: TextStyle(color: stringColor),
      ));
    } else if (match.group(3) != null) {
      spans.add(TextSpan(
        text: match.group(3),
        style: TextStyle(color: boolColor, fontWeight: FontWeight.bold),
      ));
    } else if (match.group(4) != null) {
      spans.add(TextSpan(
        text: match.group(4),
        style: TextStyle(color: numberColor),
      ));
    }

    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    spans.add(TextSpan(
      text: text.substring(lastIndex),
      style: TextStyle(color: defaultColor),
    ));
  }

  return TextSpan(children: spans);
}

TextSpan _highlightXml(String text, bool isDark) {
  final tagColor = isDark ? const Color(0xFF569CD6) : const Color(0xFF800000);
  final attrColor = isDark ? const Color(0xFF9CDCFE) : const Color(0xFFFF0000);
  final valueColor = isDark ? const Color(0xFFCE9178) : const Color(0xFF0000FF);
  final commentColor = isDark ? Colors.grey : Colors.grey;
  final defaultColor = isDark ? Colors.white70 : Colors.black87;

  final List<TextSpan> spans = [];
  final regExp = RegExp(
    r'(<!--.*?-->)|(<\/?[\w:-]+)|([\w:-]+\s*=\s*"[^"]*")|(\/?>)',
    multiLine: true,
    dotAll: true,
  );

  int lastIndex = 0;
  for (final match in regExp.allMatches(text)) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(
        text: text.substring(lastIndex, match.start),
        style: TextStyle(color: defaultColor),
      ));
    }

    if (match.group(1) != null) {
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(color: commentColor, fontStyle: FontStyle.italic),
      ));
    } else if (match.group(2) != null) {
      spans.add(TextSpan(
        text: match.group(2),
        style: TextStyle(color: tagColor, fontWeight: FontWeight.w600),
      ));
    } else if (match.group(3) != null) {
      final pair = match.group(3)!;
      final eqIndex = pair.indexOf('=');
      if (eqIndex != -1) {
        final attr = pair.substring(0, eqIndex);
        final val = pair.substring(eqIndex);
        spans.add(TextSpan(
          text: attr,
          style: TextStyle(color: attrColor),
        ));
        spans.add(TextSpan(
          text: '=',
          style: TextStyle(color: defaultColor),
        ));
        spans.add(TextSpan(
          text: val,
          style: TextStyle(color: valueColor),
        ));
      } else {
        spans.add(TextSpan(
          text: pair,
          style: TextStyle(color: attrColor),
        ));
      }
    } else if (match.group(4) != null) {
      spans.add(TextSpan(
        text: match.group(4),
        style: TextStyle(color: tagColor, fontWeight: FontWeight.w600),
      ));
    }

    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    spans.add(TextSpan(
      text: text.substring(lastIndex),
      style: TextStyle(color: defaultColor),
    ));
  }

  return TextSpan(children: spans);
}

// ══════════════════════════════════════════════════
// High-Performance Code/Text Dialog Content Component
// ══════════════════════════════════════════════════
class _DetailDialogContent extends StatefulWidget {
  final ClipboardItem item;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onCopy;

  const _DetailDialogContent({
    required this.item,
    required this.isDark,
    required this.accentColor,
    required this.onCopy,
  });

  @override
  State<_DetailDialogContent> createState() => _DetailDialogContentState();
}

class _DetailDialogContentState extends State<_DetailDialogContent> {
  late final TransformationController _transformationController;
  late final ScrollController _scrollController;

  bool _showFormatted = false;
  bool _isFormatAvailable = false;
  late final String _prettyContent;
  late final List<String> _prettyLines;
  late final List<String> _rawLines;

  // Highlight cache fields
  List<TextSpan?>? _rawHighlightedSpans;
  List<TextSpan?>? _prettyHighlightedSpans;
  bool? _lastIsDark;

  int? _imgWidth;
  int? _imgHeight;
  String _fileSizeStr = '';
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _scrollController = ScrollController();

    final itemType = AppState().getClipboardItemType(widget.item);
    final isLargeText = widget.item.content.length > 200000;

    String pretty = widget.item.content;
    if (!isLargeText) {
      if (itemType == 'JSON') {
        final fmt = AppState().tryFormatJson(widget.item.content);
        if (fmt != null) {
          pretty = fmt;
          _isFormatAvailable = true;
        }
      } else if (itemType == 'XML') {
        final fmt = AppState().tryFormatXml(widget.item.content);
        if (fmt != null) {
          pretty = fmt;
          _isFormatAvailable = true;
        }
      }
    }
    _prettyContent = pretty;
    _showFormatted = _isFormatAvailable;
    _prettyLines = _prettyContent.split('\n');
    _rawLines = widget.item.content.split('\n');

    final isImage = itemType == 'IMAGE';
    if (isImage) {
      _loadFileStats();
      _resolveImageSize();
    }
  }

  void _loadFileStats() {
    try {
      final file = File(AppState().getImagePath(widget.item));
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
      final provider = FileImage(File(AppState().getImagePath(widget.item)));
      final stream = provider.resolve(const ImageConfiguration());
      ImageStreamListener? listener;
      bool callbackCalled = false;
      listener = ImageStreamListener((ImageInfo info, bool _) {
        callbackCalled = true;
        if (listener != null) {
          stream.removeListener(listener!);
        }
        if (mounted) {
          setState(() {
            _imgWidth = info.image.width;
            _imgHeight = info.image.height;
            _resolved = true;
          });
        }
      });
      stream.addListener(listener);
      if (callbackCalled && listener != null) {
        stream.removeListener(listener);
      }
    } catch (_) {}
  }

  TextSpan _getSpan(int index, String line, String itemType, bool isDark, bool formatted) {
    if (formatted) {
      _prettyHighlightedSpans ??= List<TextSpan?>.filled(_prettyLines.length, null);
      if (_prettyHighlightedSpans![index] == null) {
        final truncatedLine = line.length > 10000
            ? '${line.substring(0, 10000)}... [该行超长已截断预览]'
            : line;
        _prettyHighlightedSpans![index] = itemType == 'JSON'
            ? _highlightJson(truncatedLine, isDark)
            : (itemType == 'XML' ? _highlightXml(truncatedLine, isDark) : TextSpan(text: truncatedLine));
      }
      return _prettyHighlightedSpans![index]!;
    } else {
      _rawHighlightedSpans ??= List<TextSpan?>.filled(_rawLines.length, null);
      if (_rawHighlightedSpans![index] == null) {
        final truncatedLine = line.length > 10000
            ? '${line.substring(0, 10000)}... [该行超长已截断预览]'
            : line;
        _rawHighlightedSpans![index] = TextSpan(text: truncatedLine);
      }
      return _rawHighlightedSpans![index]!;
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _zoom(double factor, double lastWidth, double lastHeight) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.5, 5.0);
    final double actualFactor = targetScale / currentScale;

    if ((actualFactor - 1.0).abs() < 0.001) return;

    final double px = lastWidth / 2;
    final double py = lastHeight / 2;

    final translation = Matrix4.translationValues(px, py, 0.0);
    final scale = Matrix4.identity()..scale(actualFactor, actualFactor, 1.0);
    final invTranslation = Matrix4.translationValues(-px, -py, 0.0);

    final transform = translation * scale * invTranslation;
    _transformationController.value = transform * matrix;
  }

  void _reset() {
    _transformationController.value = Matrix4.identity();
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
    final infoText = hasDimension ? '${_imgWidth}×${_imgHeight} ($_fileSizeStr)' : _fileSizeStr;

    if (_lastIsDark != widget.isDark) {
      _lastIsDark = widget.isDark;
      _rawHighlightedSpans = null;
      _prettyHighlightedSpans = null;
    }
    final displayLines = _showFormatted ? _prettyLines : _rawLines;

    return Dialog(
      backgroundColor: bgColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                        style: TextStyle(
                          fontSize: 9,
                          color: subColor,
                        ),
                      ),
                      if (isImage && infoText.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          infoText,
                          style: TextStyle(
                            fontSize: 9,
                            color: subColor,
                          ),
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
                      // Zoom tools
                      if (isImage) ...[
                        _ToolbarButton(
                          icon: Icons.zoom_in_rounded,
                          tooltip: '放大',
                          isDark: widget.isDark,
                          onTap: () => _zoom(1.2, dialogWidth, contentMaxHeight),
                        ),
                        const SizedBox(width: 4),
                        _ToolbarButton(
                          icon: Icons.zoom_out_rounded,
                          tooltip: '缩小',
                          isDark: widget.isDark,
                          onTap: () => _zoom(0.8, dialogWidth, contentMaxHeight),
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
                      // Format toggle
                      if (_isFormatAvailable) ...[
                        Text(
                          '格式化',
                          style: TextStyle(fontSize: 9, color: subColor),
                        ),
                        const SizedBox(width: 2),
                        Transform.scale(
                          scale: 0.6,
                          child: Switch(
                            value: _showFormatted,
                            activeColor: themeAccent,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) {
                              setState(() {
                                _showFormatted = val;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
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
                          imagePath: AppState().getImagePath(widget.item),
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
                          Navigator.of(context).pop();
                        },
                      ),
                      const SizedBox(width: 4),
                      // Close button
                      _ToolbarButton(
                        icon: Icons.close_rounded,
                        tooltip: '关闭',
                        isDark: widget.isDark,
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),

            // Content
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxHeight: contentMaxHeight),
                width: double.infinity,
                padding: isImage ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: CheckerboardPainter(
                                      squareSize: 8.0,
                                      lightColor: widget.isDark ? const Color(0xFF1C1C1C) : Colors.white,
                                      darkColor: widget.isDark ? const Color(0xFF141414) : const Color(0xFFF2F2F2),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: InteractiveViewer(
                                    transformationController: _transformationController,
                                    maxScale: 5.0,
                                    minScale: 0.5,
                                    boundaryMargin: const EdgeInsets.all(240.0),
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: double.infinity,
                                      child: Center(
                                        child: Image.file(
                                          File(AppState().getImagePath(widget.item)),
                                          fit: BoxFit.contain,
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
                    : SelectionArea(
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: displayLines.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final line = displayLines[index];
                              final textSpan = _getSpan(index, line, itemType, widget.isDark, _showFormatted);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Line number
                                    SelectionContainer.disabled(
                                      child: SizedBox(
                                        width: 28,
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontFamily: 'Courier New',
                                            fontSize: 9,
                                            color: widget.isDark ? Colors.white24 : Colors.black26,
                                          ),
                                          textAlign: TextAlign.end,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Code content
                                    Expanded(
                                      child: Text.rich(
                                        textSpan,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          height: 1.3,
                                          fontFamily: 'Courier New',
                                          color: itemType == 'URL' ? themeAccent : textColor,
                                          decoration: itemType == 'URL' ? TextDecoration.underline : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
