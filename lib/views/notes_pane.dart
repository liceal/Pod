import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/note.dart';
import '../services/app_state.dart';
import '../models/app_settings.dart'; // import ThemeStyle
import 'components/animated_press.dart';

class NotesPane extends StatefulWidget {
  final AppState state;
  final bool isDark;
  final VoidCallback onShowSettings;

  const NotesPane({
    super.key,
    required this.state,
    required this.isDark,
    required this.onShowSettings,
  });

  @override
  State<NotesPane> createState() => _NotesPaneState();
}

class _NotesPaneState extends State<NotesPane> {
  late TextEditingController _editorController;
  late TextEditingController _searchController;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _markdownScrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();
  String _activeNoteId = '';
  bool _showList = true;
  bool _renderMarkdown = false;
  double _swipeDistance = 0;

  @override
  void initState() {
    super.initState();
    _editorController = TextEditingController();
    _searchController = TextEditingController();
    _searchController.text = widget.state.searchNotesQuery;
    _searchController.addListener(() {
      widget.state.searchNotesQuery = _searchController.text;
      setState(() {});
    });
    _syncActiveNote();
  }

  @override
  void didUpdateWidget(NotesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncActiveNote();
  }

  @override
  void dispose() {
    _editorController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _markdownScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _syncActiveNote() {
    final active = widget.state.activeNote;
    if (active != null) {
      if (_activeNoteId != active.id ||
          _editorController.text != active.content) {
        _activeNoteId = active.id;
        _editorController.text = active.content;
      }
    } else {
      _editorController.clear();
      _activeNoteId = '';
    }
  }

  void _onContentChanged(String val) {
    widget.state.updateActiveNoteContent(val);
  }

  Future<void> _showNoteDetail(Note note) async {
    await widget.state.selectNote(note);
    if (!mounted) return;
    _syncActiveNote();
    setState(() => _showList = false);
    _focusEditorOnNextFrame();
  }

  void _showListView() {
    setState(() => _showList = true);
  }

  void _focusEditorOnNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showList || _renderMarkdown) return;
      _editorFocusNode.requestFocus();
    });
  }

  void _toggleMarkdownRender() {
    setState(() {
      _renderMarkdown = !_renderMarkdown;
    });
    if (_renderMarkdown) {
      _editorFocusNode.unfocus();
      if (_markdownScrollController.hasClients) {
        _markdownScrollController.jumpTo(0);
      }
    } else {
      _focusEditorOnNextFrame();
    }
  }

  Future<void> _openMarkdownLink(String? href) async {
    if (href == null || href.trim().isEmpty) return;
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return;
    await launchUrl(uri);
  }

  bool _isMouseBackButton(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kBackMouseButton) != 0;
  }

  Widget _wrapDetailBackGesture(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_isMouseBackButton(event)) {
          _showListView();
        }
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dx.abs() > 48 &&
            event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() * 1.6) {
          _showListView();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _swipeDistance = 0,
        onHorizontalDragUpdate: (details) {
          _swipeDistance += details.delta.dx;
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (_swipeDistance > 80 || velocity > 520) {
            _showListView();
          }
          _swipeDistance = 0;
        },
        onHorizontalDragCancel: () => _swipeDistance = 0,
        child: child,
      ),
    );
  }

  void _showDeleteConfirmDialog(
    BuildContext context,
    Note note, {
    bool fromDetail = false,
  }) async {
    widget.state.setDialogOpen(true);
    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        title: const Text('删除便签？'),
        content: const Text('您确定要删除该便签吗？'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text('删除'),
            onPressed: () async {
              final nav = Navigator.of(ctx);
              nav.pop();
              await widget.state.deleteNote(note);
              _syncActiveNote();
              if (fromDetail) {
                _showListView();
              } else {
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
    widget.state.setDialogOpen(false);
  }

  String _getSnippet(String content) {
    final lines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return '无内容';
    return lines.first;
  }

  Widget _buildList(List<Note> allNotes) {
    return ListView.builder(
      itemCount: allNotes.length,
      itemBuilder: (context, index) {
        final note = allNotes[index];
        final snippet = _getSnippet(note.content);
        final dateStr =
            '${note.updatedAt.month}-${note.updatedAt.day} ${note.updatedAt.hour.toString().padLeft(2, '0')}:${note.updatedAt.minute.toString().padLeft(2, '0')}';

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () {
                _showNoteDetail(note);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.1,
                              color: widget.isDark
                                  ? Colors.white54
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14),
                      onPressed: () => _showDeleteConfirmDialog(
                        context,
                        note,
                        fromDetail: false,
                      ),
                      color: widget.isDark ? Colors.white54 : Colors.black45,
                      hoverColor: Colors.red.withValues(alpha: 0.1),
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      padding: const EdgeInsets.all(2),
                      tooltip: '删除便签',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetail(Note active) {
    if (_renderMarkdown) {
      final theme = Theme.of(context);
      final textColor = widget.isDark ? Colors.white : Colors.black87;
      final subColor = widget.isDark ? Colors.white70 : Colors.black54;
      final mutedBg = widget.isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.05);
      final borderColor = widget.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.10);
      final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: TextStyle(fontSize: 13, height: 1.42, color: textColor),
        a: TextStyle(
          fontSize: 13,
          height: 1.42,
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        h1: TextStyle(
          fontSize: 20,
          height: 1.22,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        h2: TextStyle(
          fontSize: 17,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        h3: TextStyle(
          fontSize: 15,
          height: 1.28,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        listBullet: TextStyle(fontSize: 13, height: 1.42, color: textColor),
        blockquote: TextStyle(fontSize: 13, height: 1.42, color: subColor),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        blockquoteDecoration: BoxDecoration(
          color: mutedBg,
          border: Border(left: BorderSide(color: borderColor, width: 3)),
        ),
        code: TextStyle(
          fontSize: 12,
          height: 1.36,
          fontFamily: 'Menlo',
          color: textColor,
          backgroundColor: mutedBg,
        ),
        codeblockPadding: const EdgeInsets.all(8),
        codeblockDecoration: BoxDecoration(
          color: mutedBg,
          borderRadius: BorderRadius.circular(6),
        ),
        tableHead: TextStyle(fontSize: 12, color: textColor),
        tableBody: TextStyle(fontSize: 12, color: textColor),
        tableBorder: TableBorder.all(color: borderColor),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 4,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor)),
        ),
      );

      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.only(left: 6, right: 6, bottom: 8),
        child: Markdown(
          data: _editorController.text,
          selectable: true,
          controller: _markdownScrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          styleSheet: markdownStyle,
          onTapLink: (text, href, title) => _openMarkdownLink(href),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
      child: TextField(
        controller: _editorController,
        focusNode: _editorFocusNode,
        scrollController: _scrollController,
        maxLines: null,
        minLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(fontSize: 13, height: 1.4),
        decoration: InputDecoration(
          hintText: '开始书写便签内容...',
          hintStyle: TextStyle(
            fontSize: 13,
            color: widget.isDark ? Colors.white24 : Colors.black26,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onChanged: _onContentChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.state.activeNote;
    final allNotes = widget.state.filteredNotes;

    if (active == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isCompact = widget.state.settings.themeStyle == ThemeStyle.compact;
    return Padding(
      padding: EdgeInsets.all(isCompact ? 2.0 : 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with search input & buttons
          SizedBox(
            height: isCompact ? 26 : 32,
            child: Row(
              children: [
                if (_showList)
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
                          hintText: '搜索便签...',
                          hintStyle: TextStyle(
                            fontSize: isCompact ? 11 : 12,
                            color: widget.isDark
                                ? Colors.white30
                                : Colors.black.withOpacity(0.3),
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 8, right: 6),
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
                              : null,
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
                  )
                else
                  const Spacer(),
                SizedBox(width: isCompact ? 2 : 4),
                if (!_showList) ...[
                  Tooltip(
                    message: _renderMarkdown ? '编辑便签' : 'Markdown 预览',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedPress(
                        onTap: _toggleMarkdownRender,
                        child: Container(
                          width: isCompact ? 26 : 32,
                          height: isCompact ? 26 : 32,
                          decoration: BoxDecoration(
                            color: _renderMarkdown
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.20)
                                : (widget.isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.04)),
                            borderRadius: BorderRadius.circular(
                              isCompact ? 0 : 8,
                            ),
                          ),
                          child: Icon(
                            _renderMarkdown
                                ? Icons.edit_rounded
                                : Icons.visibility_rounded,
                            size: 15,
                            color: _renderMarkdown
                                ? Theme.of(context).colorScheme.primary
                                : (widget.isDark
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : Colors.black.withValues(alpha: 0.6)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isCompact ? 2 : 4),
                  Tooltip(
                    message: '删除当前便签',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedPress(
                        onTap: () => _showDeleteConfirmDialog(
                          context,
                          active,
                          fromDetail: true,
                        ),
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
                            Icons.delete_outline_rounded,
                            size: 15,
                            color: widget.isDark
                                ? Colors.red[300]
                                : Colors.red[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isCompact ? 2 : 4),
                ],
                Tooltip(
                  message: '新建便签',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedPress(
                      onTap: () async {
                        await widget.state.createNote();
                        _syncActiveNote();
                        setState(() {
                          _showList = false;
                          _renderMarkdown = false;
                        });
                        _focusEditorOnNextFrame();
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
                          Icons.add_rounded,
                          size: 15,
                          color: widget.isDark
                              ? Colors.white.withOpacity(0.6)
                              : Colors.black.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isCompact ? 2 : 4),
                Tooltip(
                  message: _showList ? '当前为列表视图' : '返回列表视图',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedPress(
                      onTap: () {
                        final willShowList = !_showList;
                        setState(() => _showList = willShowList);
                        if (!willShowList) {
                          _focusEditorOnNextFrame();
                        }
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
                          Icons.menu_rounded,
                          size: 15,
                          color: widget.isDark
                              ? Colors.white.withOpacity(0.6)
                              : Colors.black.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isCompact ? 2 : 4),
                Tooltip(
                  message: '设置',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedPress(
                      onTap: widget.onShowSettings,
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
                          Icons.settings_outlined,
                          size: 15,
                          color: widget.isDark
                              ? Colors.white.withOpacity(0.6)
                              : Colors.black.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? 2 : 4),

          // Main Content Area with Transition
          Expanded(
            child: _showList
                ? _buildList(allNotes)
                : _wrapDetailBackGesture(_buildDetail(active)),
          ),
        ],
      ),
    );
  }
}
