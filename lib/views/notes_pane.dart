import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../models/note.dart';
import '../services/app_state.dart';
import '../utils/localization.dart';

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
  static const double _textZoomDeadZone = 0.001;
  static const double _textZoomSensitivity = 1.25;

  late TextEditingController _editorController;
  late TextEditingController _searchController;
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _editorFocusNode = FocusNode();
  final Map<String, TextSelection> _noteSelections = {};
  final Map<String, double> _noteScrollOffsets = {};
  String _activeNoteId = '';
  bool _showList = true;
  double _trackpadBackSwipeDistance = 0;
  double _trackpadBackSwipeCrossAxisDistance = 0;
  bool _didTriggerTrackpadBackSwipe = false;
  double _swipeDistance = 0;
  bool _isMouseButtonDown = false;
  bool _ignoreCurrentBackDrag = false;

  @override
  void initState() {
    super.initState();
    _editorController = TextEditingController();
    _searchController = TextEditingController();
    _searchController.text = widget.state.searchNotesQuery;
    _searchController.addListener(() {
      widget.state.searchNotesQuery = _searchController.text;
    });
    _editorFocusNode.addListener(_handleEditorFocusChanged);
    _syncActiveNote();
  }

  @override
  void didUpdateWidget(NotesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncActiveNote();
  }

  @override
  void dispose() {
    widget.state.setNoteEditorFocused(false);
    _editorFocusNode.removeListener(_handleEditorFocusChanged);
    _editorController.dispose();
    _searchController.dispose();
    _listScrollController.dispose();
    _scrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _syncActiveNote() {
    final active = widget.state.activeNote;
    if (active != null) {
      final noteChanged = _activeNoteId != active.id;
      if (noteChanged || _editorController.text != active.content) {
        if (noteChanged) {
          _saveCurrentNoteViewState();
        }
        _activeNoteId = active.id;
        _editorController.value = TextEditingValue(
          text: active.content,
          selection: _selectionForNote(active),
        );
        _restoreScrollForNote(active);
      }
    } else {
      _saveCurrentNoteViewState();
      _editorController.clear();
      _activeNoteId = '';
    }
  }

  TextSelection _selectionForNote(Note note) {
    final saved = _noteSelections[note.id];
    final offset = saved?.baseOffset ?? 0;
    final extentOffset = saved?.extentOffset ?? offset;
    return TextSelection(
      baseOffset: offset.clamp(0, note.content.length).toInt(),
      extentOffset: extentOffset.clamp(0, note.content.length).toInt(),
    );
  }

  void _restoreScrollForNote(Note note) {
    final savedOffset = _noteScrollOffsets[note.id] ?? 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _activeNoteId != note.id ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final target = savedOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _scrollController.jumpTo(target);
    });
  }

  void _saveCurrentNoteViewState() {
    if (_activeNoteId.isEmpty) return;

    final selection = _editorController.selection;
    if (selection.isValid) {
      final textLength = _editorController.text.length;
      _noteSelections[_activeNoteId] = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, textLength).toInt(),
        extentOffset: selection.extentOffset.clamp(0, textLength).toInt(),
      );
    }

    if (_scrollController.hasClients) {
      _noteScrollOffsets[_activeNoteId] = _scrollController.offset;
    }
  }

  void _clearNoteViewState(String noteId) {
    _noteSelections.remove(noteId);
    _noteScrollOffsets.remove(noteId);
  }

  void _onContentChanged(String val) {
    widget.state.updateActiveNoteContent(val);
  }

  void _handleEditorFocusChanged() {
    widget.state.setNoteEditorFocused(_editorFocusNode.hasFocus && !_showList);
  }

  Future<void> _showNoteDetail(Note note) async {
    _saveCurrentNoteViewState();
    await widget.state.selectNote(note);
    if (!mounted) return;
    _syncActiveNote();
    setState(() => _showList = false);
    _focusEditorOnNextFrame();
  }

  void _showListView() {
    _saveCurrentNoteViewState();
    _editorFocusNode.unfocus();
    widget.state.setNoteEditorFocused(false);
    setState(() => _showList = true);
  }

  void _focusEditorOnNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showList) return;
      _editorFocusNode.requestFocus();
      widget.state.setNoteEditorFocused(true);
    });
  }

  bool _isMouseBackButton(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kBackMouseButton) != 0;
  }

  void _handleBackPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse && event.buttons != 0) {
      _isMouseButtonDown = true;
    }

    if (_isMouseBackButton(event)) {
      _showListView();
    }
  }

  void _handleBackPointerUp(PointerUpEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _isMouseButtonDown = false;
    }
  }

  void _handleBackPointerCancel(PointerCancelEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _isMouseButtonDown = false;
    }
  }

  bool get _isTextZoomModifierPressed {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
  }

  void _handleEditorPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_isTextZoomModifierPressed) {
      return;
    }

    if (event.scrollDelta.dy == 0) {
      return;
    }

    final direction = event.scrollDelta.dy < 0 ? 1.0 : -1.0;
    widget.state.updateTextContentFontSize(
      widget.state.settings.textContentFontSize + direction,
    );
  }

  void _handleBackPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadBackSwipeDistance = 0;
    _trackpadBackSwipeCrossAxisDistance = 0;
    _didTriggerTrackpadBackSwipe = false;
  }

  void _handleBackPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_isTextZoomModifierPressed) {
      if (event.panDelta.dy != 0 && (event.scale - 1.0).abs() < 0.01) {
        final currentFontSize = widget.state.settings.textContentFontSize;
        final delta = event.panDelta.dy / 30.0;
        final targetFontSize = currentFontSize + delta;
        widget.state.updateTextContentFontSize(targetFontSize);
        setState(() {});
      }
      return;
    }

    if (_didTriggerTrackpadBackSwipe || (event.scale - 1.0).abs() >= 0.01) {
      return;
    }

    _trackpadBackSwipeDistance += event.panDelta.dx;
    _trackpadBackSwipeCrossAxisDistance += event.panDelta.dy.abs();

    if (_trackpadBackSwipeDistance > 80 &&
        _trackpadBackSwipeDistance.abs() >
            _trackpadBackSwipeCrossAxisDistance * 1.6) {
      _didTriggerTrackpadBackSwipe = true;
      _showListView();
    }
  }

  void _handleBackPanZoomEnd(PointerPanZoomEndEvent event) {
    _trackpadBackSwipeDistance = 0;
    _trackpadBackSwipeCrossAxisDistance = 0;
    _didTriggerTrackpadBackSwipe = false;
  }

  Widget _wrapDetailBackGesture(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleBackPointerDown,
      onPointerUp: _handleBackPointerUp,
      onPointerCancel: _handleBackPointerCancel,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dx > 48 &&
            event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs() * 1.6) {
          _showListView();
        }
      },
      onPointerPanZoomStart: _handleBackPanZoomStart,
      onPointerPanZoomUpdate: _handleBackPanZoomUpdate,
      onPointerPanZoomEnd: _handleBackPanZoomEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _swipeDistance = 0;
          _ignoreCurrentBackDrag = _isMouseButtonDown;
        },
        onHorizontalDragUpdate: (details) {
          if (_ignoreCurrentBackDrag) return;
          _swipeDistance += details.delta.dx;
        },
        onHorizontalDragEnd: (details) {
          if (!_ignoreCurrentBackDrag) {
            final velocity = details.primaryVelocity ?? 0;
            if (_swipeDistance > 80 || velocity > 520) {
              _showListView();
            }
          }
          _swipeDistance = 0;
          _ignoreCurrentBackDrag = false;
        },
        onHorizontalDragCancel: () {
          _swipeDistance = 0;
          _ignoreCurrentBackDrag = false;
        },
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
        title: Text(context.text('删除便签？', 'Delete Note?')),
        content: Text(
          context.text(
            '您确定要删除该便签吗？',
            'Are you sure you want to delete this note?',
          ),
        ),
        actions: [
          TextButton(
            child: Text(context.text('取消', 'Cancel')),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: Text(context.text('删除', 'Delete')),
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final deletedActiveNote = _activeNoteId == note.id;
              nav.pop();
              _clearNoteViewState(note.id);
              if (deletedActiveNote) {
                _activeNoteId = '';
              }
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
    if (lines.isEmpty) return context.text('无内容', 'No Content');
    return lines.first;
  }

  Widget _buildList(List<Note> allNotes) {
    return NotificationListener<OverscrollNotification>(
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
        key: const PageStorageKey<String>('notes_list_view'),
        controller: _listScrollController,
        physics: const BouncingScrollPhysics(),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
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
                        tooltip: context.text('删除便签', 'Delete Note'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _insertTab() {
    final text = _editorController.text;
    final selection = _editorController.selection;
    final start = selection.start;
    final end = selection.end;
    if (start >= 0) {
      final newText = text.replaceRange(start, end, '    ');
      _editorController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + 4),
      );
      _onContentChanged(newText);
    }
  }

  Widget _buildDetail(Note active) {
    final editorFontSize = widget.state.settings.textContentFontSize;
    final editorTextStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: editorFontSize,
          height: 1.4,
          color: widget.isDark ? Colors.white : Colors.black87,
        ) ??
        TextStyle(
          fontSize: editorFontSize,
          height: 1.4,
          color: widget.isDark ? Colors.white : Colors.black87,
        );

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.only(bottom: 8),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            _insertTab();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerSignal: _handleEditorPointerSignal,
          child: TextField(
              controller: _editorController,
              focusNode: _editorFocusNode,
              scrollController: _scrollController,
              maxLines: null,
              minLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: editorTextStyle,
              decoration: InputDecoration(
                hintText: context.text(
                  '开始书写便签内容...',
                  'Start writing note content...',
                ),
                hintStyle: editorTextStyle.copyWith(
                  color: widget.isDark ? Colors.white24 : Colors.black26,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(left: 10, right: 2),
                isDense: true,
              ),
              onChanged: _onContentChanged,
            ),
          ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with search input & buttons
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && event.scrollDelta.dy < 0) {
                if (widget.state.isExpanded && !widget.state.isAnimating) {
                  widget.state.collapsePanel();
                }
              }
            },
            child: SizedBox(
              height: 26,
              child: Row(
                children: [
                  if (_showList)
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
                            hintText: context.text(
                              '搜索便签...',
                              'Search notes...',
                            ),
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? Colors.white30
                                  : Colors.black54,
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
                                        child: const Icon(
                                          Icons.clear,
                                          size: 15,
                                        ),
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
                  const SizedBox(width: 2),
                  if (!_showList) ...[
                    Tooltip(
                      message: context.text('删除当前便签', 'Delete Current Note'),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedPress(
                          onTap: () => _showDeleteConfirmDialog(
                            context,
                            active,
                            fromDetail: true,
                          ),
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
                    const SizedBox(width: 2),
                  ],
                  Tooltip(
                    message: context.text('新建便签', 'New Note'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedPress(
                        onTap: () async {
                          await widget.state.createNote();
                          _syncActiveNote();
                          setState(() {
                            _showList = false;
                          });
                          _focusEditorOnNextFrame();
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
                  const SizedBox(width: 2),
                  Tooltip(
                    message: _showList
                        ? context.text('当前为列表视图', 'Currently list view')
                        : context.text('返回列表视图', 'Back to list view'),
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
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: widget.isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.zero,
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
                  const SizedBox(width: 2),
                  Tooltip(
                    message: context.text('设置', 'Settings'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedPress(
                        onTap: widget.onShowSettings,
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
          ),
          const SizedBox(height: 2),

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
