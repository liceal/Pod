import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart' as sdd;
import 'package:pasteboard/pasteboard.dart';
import '../services/app_state.dart';
import '../utils/localization.dart';
import '../theme/app_theme.dart';
import 'components/animated_press.dart';

enum _ViewMode { grid, details }

class _PasteFilesIntent extends Intent {
  const _PasteFilesIntent();
}

class _CopyFileIntent extends Intent {
  const _CopyFileIntent();
}

class _CutFileIntent extends Intent {
  const _CutFileIntent();
}

class _DeleteFileIntent extends Intent {
  const _DeleteFileIntent();
}

class FilesPane extends StatefulWidget {
  final AppState state;
  final bool isDark;

  const FilesPane({super.key, required this.state, required this.isDark});

  @override
  State<FilesPane> createState() => _FilesPaneState();
}

class _FilesPaneState extends State<FilesPane> {
  bool _isDragging = false;
  String _searchQuery = '';
  _ViewMode _viewMode = _ViewMode.grid;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _detailsScrollController = ScrollController();
  final FocusNode _paneFocusNode = FocusNode();
  bool _isDragDropReady = false;
  String? _selectedFilePath;
  String? _cutFilePath;
  bool _showSizeSlider = false;
  String _currentRelativePath = '';

  double _swipeDistance = 0;
  double _trackpadBackSwipeDistance = 0;
  double _trackpadBackSwipeCrossAxisDistance = 0;
  bool _didTriggerTrackpadBackSwipe = false;
  bool _isMouseButtonDown = false;
  bool _ignoreCurrentBackDrag = false;
  static const int kBackMouseButton = 8; // standard back button on mouse

  void _handleBackPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse && event.buttons != 0) {
      _isMouseButtonDown = true;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kBackMouseButton) != 0) {
      _goBack();
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

  void _handleBackPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadBackSwipeDistance = 0;
    _trackpadBackSwipeCrossAxisDistance = 0;
    _didTriggerTrackpadBackSwipe = false;
  }

  void _handleBackPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_didTriggerTrackpadBackSwipe || (event.scale - 1.0).abs() >= 0.01) {
      return;
    }

    _trackpadBackSwipeDistance += event.panDelta.dx;
    _trackpadBackSwipeCrossAxisDistance += event.panDelta.dy.abs();

    if (_trackpadBackSwipeDistance > 80 &&
        _trackpadBackSwipeDistance.abs() >
            _trackpadBackSwipeCrossAxisDistance * 1.6) {
      _didTriggerTrackpadBackSwipe = true;
      _goBack();
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
          _goBack();
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
              _goBack();
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

  String _getFilesDirectoryPathSync() {
    final settings = widget.state.settings;
    if (settings.customFilesPath != null &&
        settings.customFilesPath!.trim().isNotEmpty) {
      return settings.customFilesPath!.trim();
    }
    final dataDir = widget.state.getDataDirectoryPathSync();
    return '$dataDir/files';
  }

  DateTime _getFileTime(FileSystemEntity entity) {
    try {
      if (!entity.existsSync()) return DateTime(0);
      final stat = entity.statSync();
      return Platform.isWindows ? stat.changed : stat.modified;
    } catch (_) {
      return DateTime(0);
    }
  }

  void _onFileOpen(FileSystemEntity file) {
    final root = _getFilesDirectoryPathSync();
    if (FileSystemEntity.isDirectorySync(file.path) &&
        file.path.startsWith(root)) {
      String relative = file.path.substring(root.length);
      if (relative.startsWith('/') || relative.startsWith('\\')) {
        relative = relative.substring(1);
      }
      setState(() {
        _currentRelativePath = relative.replaceAll('\\', '/');
        _searchController.clear();
        _selectedFilePath = null;
      });
    } else {
      widget.state.openFile(file);
    }
  }

  void _goBack() {
    if (_currentRelativePath.isEmpty) return;
    final parts = _currentRelativePath.split('/');
    parts.removeLast();
    setState(() {
      _currentRelativePath = parts.join('/');
      _searchController.clear();
      _selectedFilePath = null;
    });
  }

  String _getBreadcrumbText() {
    if (_currentRelativePath.isEmpty) return '';
    final rootLabel = context.text('文件', 'Files');
    return '$rootLabel / ${_currentRelativePath.replaceAll('/', ' / ')}';
  }

  @override
  void initState() {
    super.initState();
    _paneFocusNode.addListener(_onFocusChange);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isDragDropReady = true;
        });
      }
    });
  }

  void _onFocusChange() {
    if (mounted && !_paneFocusNode.hasFocus && !widget.state.isDialogOpen) {
      setState(() {
        _selectedFilePath = null;
      });
    }
  }

  @override
  void dispose() {
    _paneFocusNode.removeListener(_onFocusChange);
    _searchController.dispose();
    _gridScrollController.dispose();
    _detailsScrollController.dispose();
    _paneFocusNode.dispose();
    super.dispose();
  }

  static const _imageExts = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'ico',
    'svg',
  ];

  bool _isImage(String path) {
    if (FileSystemEntity.isDirectorySync(path)) return false;
    final ext = path.split('.').last.toLowerCase();
    return _imageExts.contains(ext);
  }

  void _copySelectedFile() {
    final path = _selectedFilePath;
    if (path != null && FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      Pasteboard.writeFiles([path]);
      setState(() {
        _cutFilePath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.text('已复制文件到剪贴板', 'File copied to clipboard'),
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _cutSelectedFile() {
    final path = _selectedFilePath;
    if (path != null && FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      Pasteboard.writeFiles([path]);
      setState(() {
        _cutFilePath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.text('已剪切文件到剪贴板', 'File cut to clipboard'),
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _deleteSelectedFile() {
    final path = _selectedFilePath;
    if (path != null && FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      final entity = FileSystemEntity.isDirectorySync(path)
          ? Directory(path)
          : File(path);
      widget.state.deleteFile(entity);
      setState(() {
        if (_selectedFilePath == path) {
          _selectedFilePath = null;
        }
        if (_cutFilePath == path) {
          _cutFilePath = null;
        }
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final root = _getFilesDirectoryPathSync();
    final targetDir = _currentRelativePath.isEmpty
        ? Directory(root)
        : Directory('$root/$_currentRelativePath');

    if (_cutFilePath != null) {
      final cutPath = _cutFilePath!;
      final entity = FileSystemEntity.isDirectorySync(cutPath)
          ? Directory(cutPath)
          : File(cutPath);
      if (entity.existsSync()) {
        if (entity.path != targetDir.path &&
            !targetDir.path.startsWith('${entity.path}/')) {
          try {
            await widget.state.moveFileToFolder(entity, targetDir);
            setState(() {
              _cutFilePath = null;
              final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
              _selectedFilePath = '${targetDir.path}/$name';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.text('已移动文件', 'File moved'),
                  style: const TextStyle(fontSize: 11),
                ),
                duration: const Duration(seconds: 1),
              ),
            );
          } catch (e) {
            debugPrint('Failed to move cut file: $e');
          }
        } else {
          setState(() {
            _cutFilePath = null;
          });
        }
        return;
      } else {
        setState(() {
          _cutFilePath = null;
        });
      }
    }

    final count = await widget.state.pasteClipboardIntoFiles(
      targetDir: targetDir,
    );
    if (!mounted) return;

    final message = count > 0
        ? context.text('已粘贴到文件', 'Pasted to files')
        : context.text(
            '剪贴板里没有可添加的文件或图片',
            'No files or images found in clipboard',
          );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 11)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset globalPosition,
    FileSystemEntity file,
    VoidCallback onDelete,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDir = file is Directory;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    widget.state.setDialogOpen(true);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'open',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.open_in_new_rounded, size: 14),
              const SizedBox(width: 8),
              Text(
                isDir
                    ? context.text('打开文件夹', 'Open Folder')
                    : context.text('打开文件', 'Open File'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'show_in_explorer',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 14),
              const SizedBox(width: 8),
              Text(
                Platform.isMacOS
                    ? context.text('在 Finder 中显示', 'Reveal in Finder')
                    : context.text('在资源管理器中显示', 'Reveal in File Explorer'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy_path',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 14),
              const SizedBox(width: 8),
              Text(
                isDir
                    ? context.text('复制文件夹路径', 'Copy Folder Path')
                    : context.text('复制文件路径', 'Copy File Path'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'rename',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 14),
              const SizedBox(width: 8),
              Text(
                context.text('重命名', 'Rename'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: isDark ? Colors.red[300] : Colors.red[700],
              ),
              const SizedBox(width: 8),
              Text(
                isDir
                    ? context.text('删除文件夹', 'Delete Folder')
                    : context.text('删除文件', 'Delete File'),
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.red[300] : Colors.red[700],
                ),
              ),
            ],
          ),
        ),
      ],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: isDark ? const Color(0xFF262626) : Colors.white,
    );
    widget.state.setDialogOpen(false);

    if (result == null) return;

    switch (result) {
      case 'open':
        _onFileOpen(file);
        break;
      case 'show_in_explorer':
        widget.state.revealFileInExplorer(file);
        break;
      case 'copy_path':
        widget.state.copyTextToClipboard(file.path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isDir
                    ? context.text(
                        '文件夹路径已复制到剪贴板',
                        'Folder path copied to clipboard',
                      )
                    : context.text(
                        '文件路径已复制到剪贴板',
                        'File path copied to clipboard',
                      ),
                style: const TextStyle(fontSize: 11),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        break;
      case 'rename':
        if (context.mounted) {
          _showRenameDialog(context, file);
        }
        break;
      case 'delete':
        onDelete();
        break;
    }
  }

  void _showRenameDialog(BuildContext context, FileSystemEntity file) async {
    final segments = file.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final currentName = segments.isNotEmpty ? segments.last : '';
    final isDir = file is Directory;
    final textController = TextEditingController(text: currentName);

    // Auto-select filename without extension if it's a file
    int selectionEnd = currentName.length;
    if (!isDir && currentName.contains('.')) {
      selectionEnd = currentName.lastIndexOf('.');
    }
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: selectionEnd,
    );

    widget.state.setDialogOpen(true);
    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        title: Text(
          isDir
              ? context.text('重命名文件夹', 'Rename Folder')
              : context.text('重命名文件', 'Rename File'),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isDir
                ? context.text('请输入文件夹名称', 'Please enter folder name')
                : context.text('请输入文件名称', 'Please enter file name'),
          ),
          onSubmitted: (val) async {
            final name = val.trim();
            if (name.isNotEmpty && name != currentName) {
              Navigator.of(ctx).pop();
              final success = await widget.state.renameFile(file, name);
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.text(
                        '重命名失败，名称可能已存在',
                        'Rename failed, name might already exist',
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } else {
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            child: Text(context.text('取消', 'Cancel')),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: Text(context.text('重命名', 'Rename')),
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty && name != currentName) {
                Navigator.of(ctx).pop();
                final success = await widget.state.renameFile(file, name);
                if (!success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.text(
                          '重命名失败，名称可能已存在',
                          'Rename failed, name might already exist',
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                Navigator.of(ctx).pop();
              }
            },
          ),
        ],
      ),
    );
    widget.state.setDialogOpen(false);
  }

  /// 返回 (图标, 颜色)
  (IconData, Color) _getFileIconAndColor(String path) {
    if (FileSystemEntity.isDirectorySync(path)) {
      return (Icons.folder_rounded, const Color(0xFFFFB300));
    }
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      // 压缩包
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
        return (Icons.inventory_2_rounded, const Color(0xFFFF9800));
      // PDF
      case 'pdf':
        return (Icons.picture_as_pdf_rounded, const Color(0xFFE53935));
      // Word
      case 'doc':
      case 'docx':
      case 'odt':
        return (Icons.article_rounded, const Color(0xFF1565C0));
      // Excel
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (Icons.table_chart_rounded, const Color(0xFF2E7D32));
      // PPT
      case 'ppt':
      case 'pptx':
        return (Icons.slideshow_rounded, const Color(0xFFD84315));
      // 文本 / 代码
      case 'txt':
        return (Icons.text_snippet_rounded, const Color(0xFF546E7A));
      case 'md':
        return (Icons.description_rounded, const Color(0xFF455A64));
      case 'json':
        return (Icons.data_object_rounded, const Color(0xFF6D4C41));
      case 'xml':
      case 'html':
        return (Icons.code_rounded, const Color(0xFFE65100));
      case 'yaml':
      case 'yml':
      case 'ini':
      case 'conf':
        return (Icons.settings_applications_rounded, const Color(0xFF5C6BC0));
      case 'dart':
      case 'flutter':
        return (Icons.flutter_dash_rounded, const Color(0xFF0288D1));
      case 'js':
      case 'ts':
      case 'vue':
      case 'py':
      case 'java':
      case 'kt':
      case 'swift':
      case 'sh':
      case 'bat':
      case 'cmd':
        return (Icons.terminal_rounded, const Color(0xFF388E3C));
      case 'css':
        return (Icons.css_rounded, const Color(0xFF1976D2));
      // 图片
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'ico':
      case 'svg':
        return (Icons.image_rounded, const Color(0xFF7B1FA2));
      // 音频
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'm4a':
      case 'aac':
        return (Icons.audio_file_rounded, const Color(0xFFF50057));
      // 视频
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'wmv':
        return (Icons.video_file_rounded, const Color(0xFF6A1B9A));
      // 可执行
      case 'exe':
      case 'msi':
        return (Icons.memory_rounded, const Color(0xFF37474F));
      default:
        return (Icons.insert_drive_file_rounded, const Color(0xFF78909C));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = AppTheme.getAccentColor(
      widget.state.settings.themeColorName,
      widget.isDark,
    );

    final rawFiles = <FileSystemEntity>[];
    if (_currentRelativePath.isEmpty) {
      rawFiles.addAll(widget.state.storedFiles);
    } else {
      final root = _getFilesDirectoryPathSync();
      final subDir = Directory('$root/$_currentRelativePath');
      if (subDir.existsSync()) {
        try {
          final listed =
              subDir
                  .listSync()
                  .where((entity) => entity is File || entity is Directory)
                  .toList()
                ..sort((a, b) {
                  final timeA = _getFileTime(a);
                  final timeB = _getFileTime(b);
                  return timeB.compareTo(timeA);
                });
          rawFiles.addAll(listed);
        } catch (e) {
          debugPrint('Error listing subfolder: $e');
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentRelativePath = '';
            });
          }
        });
        rawFiles.addAll(widget.state.storedFiles);
      }
    }

    final files = rawFiles.where((file) {
      if (_searchQuery.isEmpty) return true;
      final segments = file.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      final fileName = segments.isEmpty ? '' : segments.last.toLowerCase();
      return fileName.contains(_searchQuery.toLowerCase());
    }).toList();

    if (!_isDragDropReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.text('正在加载文件...', 'Loading files...'),
              style: TextStyle(
                fontSize: 11,
                color: widget.isDark
                    ? Colors.white30
                    : Colors.black.withOpacity(0.3),
              ),
            ),
          ],
        ),
      );
    }

    final mainContent = Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Search + View Toggle ──
              Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent &&
                      pointerSignal.scrollDelta.dy < 0) {
                    widget.state.collapsePanel();
                  }
                },
                child: Row(
                  children: [
                    if (_currentRelativePath.isNotEmpty) ...[
                      Tooltip(
                        message: context.text('返回上级', 'Back'),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedPress(
                            onTap: _goBack,
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
                                Icons.arrow_back_rounded,
                                size: 15,
                                color: widget.isDark
                                    ? Colors.white60
                                    : Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    Expanded(
                      child: _SearchBar(
                        controller: _searchController,
                        isDark: widget.isDark,
                        showFolderBtn: _searchController.text.isEmpty,
                        onOpenFolder: () {
                          final currentPath = _currentRelativePath.isEmpty
                              ? _getFilesDirectoryPathSync()
                              : '${_getFilesDirectoryPathSync()}/$_currentRelativePath';
                          widget.state.openDirectoryPath(currentPath);
                        },
                      ),
                    ),
                    const SizedBox(width: 2),
                    Tooltip(
                      message: context.text('粘贴文件或图片', 'Paste files or images'),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedPress(
                          onTap: _pasteFromClipboard,
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
                              Icons.content_paste_rounded,
                              size: 15,
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    if (_showSizeSlider) ...[
                      SizedBox(
                        width: 80,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                            activeTrackColor: widget.isDark
                                ? Colors.white60
                                : Colors.black54,
                            inactiveTrackColor: widget.isDark
                                ? Colors.white12
                                : Colors.black12,
                            thumbColor: widget.isDark
                                ? Colors.white
                                : Colors.black87,
                          ),
                          child: Slider(
                            value: widget.state.fileDisplaySize,
                            min: 60.0,
                            max: 160.0,
                            onChanged: (val) {
                              widget.state.updateFileDisplaySize(val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    Tooltip(
                      message: context.text('调整显示大小', 'Adjust display size'),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedPress(
                          onTap: () => setState(
                            () => _showSizeSlider = !_showSizeSlider,
                          ),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: _showSizeSlider
                                  ? (widget.isDark
                                        ? Colors.white.withOpacity(0.12)
                                        : Colors.black.withOpacity(0.08))
                                  : (widget.isDark
                                        ? Colors.white.withOpacity(0.06)
                                        : Colors.black.withOpacity(0.04)),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Icon(
                              Icons.photo_size_select_large_rounded,
                              size: 15,
                              color: widget.isDark
                                  ? Colors.white60
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedPress(
                        onTap: () => setState(() {
                          if (_viewMode == _ViewMode.grid) {
                            _viewMode = _ViewMode.details;
                          } else {
                            _viewMode = _ViewMode.grid;
                          }
                        }),
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
                            _viewMode == _ViewMode.grid
                                ? Icons.view_list_rounded
                                : Icons.grid_view_rounded,
                            size: 15,
                            color: widget.isDark
                                ? Colors.white60
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_currentRelativePath.isNotEmpty) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.0,
                    vertical: 1.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        size: 13,
                        color: widget.isDark ? Colors.white30 : Colors.black38,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _getBreadcrumbText(),
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.isDark
                                ? Colors.white30
                                : Colors.black38,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 2),

              // ── File Content ──
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _paneFocusNode.requestFocus(),
                  onTap: () {
                    setState(() {
                      _selectedFilePath = null;
                    });
                  },
                  onSecondaryTapUp: (details) => _showEmptySpaceContextMenu(
                    context,
                    details.globalPosition,
                  ),
                  child: _wrapDetailBackGesture(
                    files.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.move_to_inbox_outlined,
                                  size: 32,
                                  color: widget.isDark
                                      ? Colors.white24
                                      : Colors.black26,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? context.text(
                                          '未找到匹配文件',
                                          'No matching files found',
                                        )
                                      : context.text(
                                          '拖拽文件到此处',
                                          'Drag & drop files here',
                                        ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: widget.isDark
                                        ? Colors.white30
                                        : Colors.black.withOpacity(0.3),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _viewMode == _ViewMode.grid
                        ? _buildGridView(files)
                        : _buildDetailsView(files),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Drag overlay ──
        if (_isDragging)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: (widget.isDark ? Colors.black : Colors.white)
                    .withOpacity(0.88),
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              ),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: accentColor, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        size: 32,
                        color: accentColor,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.text('释放文件以添加', 'Drop files to add'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final paneContent = _isDragDropReady
        ? sdd.DropRegion(
            formats: const [sdd.Formats.fileUri],
            onDropEnter: (event) {
              final isInternal = event.session.items.any(
                (item) => item.localData == 'internal_file_drag',
              );
              if (!isInternal) {
                setState(() => _isDragging = true);
              }
            },
            onDropLeave: (event) => setState(() => _isDragging = false),
            onDropOver: (event) {
              final isInternal = event.session.items.any(
                (item) => item.localData == 'internal_file_drag',
              );
              return isInternal
                  ? sdd.DropOperation.none
                  : sdd.DropOperation.copy;
            },
            onPerformDrop: (event) async {
              final isInternal = event.session.items.any(
                (item) => item.localData == 'internal_file_drag',
              );
              if (isInternal) return;
              setState(() => _isDragging = false);
              final filePaths = <String>[];
              final items = event.session.items;
              int completed = 0;
              if (items.isEmpty) return;

              for (final item in items) {
                final reader = item.dataReader;
                if (reader != null && reader.canProvide(sdd.Formats.fileUri)) {
                  reader.getValue<Uri>(
                    sdd.Formats.fileUri,
                    (uri) {
                      if (uri != null) {
                        filePaths.add(uri.toFilePath());
                      }
                      completed++;
                      if (completed == items.length && filePaths.isNotEmpty) {
                        final targetDir = _currentRelativePath.isEmpty
                            ? null
                            : Directory(
                                '${_getFilesDirectoryPathSync()}/$_currentRelativePath',
                              );
                        widget.state.addDroppedFiles(
                          filePaths,
                          targetDir: targetDir,
                        );
                      }
                    },
                    onError: (err) {
                      completed++;
                      if (completed == items.length && filePaths.isNotEmpty) {
                        final targetDir = _currentRelativePath.isEmpty
                            ? null
                            : Directory(
                                '${_getFilesDirectoryPathSync()}/$_currentRelativePath',
                              );
                        widget.state.addDroppedFiles(
                          filePaths,
                          targetDir: targetDir,
                        );
                      }
                    },
                  );
                } else {
                  completed++;
                  if (completed == items.length && filePaths.isNotEmpty) {
                    final targetDir = _currentRelativePath.isEmpty
                        ? null
                        : Directory(
                            '${_getFilesDirectoryPathSync()}/$_currentRelativePath',
                          );
                    widget.state.addDroppedFiles(
                      filePaths,
                      targetDir: targetDir,
                    );
                  }
                }
              }
            },
            child: mainContent,
          )
        : mainContent;

    final bool isInputFocused = FocusManager.instance.primaryFocus != null &&
        FocusManager.instance.primaryFocus != _paneFocusNode;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _PasteFilesIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _PasteFilesIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _CopyFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _CopyFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyX, control: true):
            _CutFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyX, meta: true):
            _CutFileIntent(),
        SingleActivator(LogicalKeyboardKey.delete):
            _DeleteFileIntent(),
        SingleActivator(LogicalKeyboardKey.backspace):
            _DeleteFileIntent(),
      },
      child: Actions(
        actions: {
          _PasteFilesIntent: CallbackAction<_PasteFilesIntent>(
            onInvoke: (_) {
              if (!isInputFocused) {
                _pasteFromClipboard();
              }
              return null;
            },
          ),
          _CopyFileIntent: CallbackAction<_CopyFileIntent>(
            onInvoke: (_) {
              if (!isInputFocused) {
                _copySelectedFile();
              }
              return null;
            },
          ),
          _CutFileIntent: CallbackAction<_CutFileIntent>(
            onInvoke: (_) {
              if (!isInputFocused) {
                _cutSelectedFile();
              }
              return null;
            },
          ),
          _DeleteFileIntent: CallbackAction<_DeleteFileIntent>(
            onInvoke: (_) {
              if (!isInputFocused) {
                _deleteSelectedFile();
              }
              return null;
            },
          ),
        },
        child: Focus(focusNode: _paneFocusNode, child: paneContent),
      ),
    );
  }

  void _showNewNameDialog(BuildContext context, bool isFolder) async {
    final textController = TextEditingController(
      text: isFolder
          ? context.text('新建文件夹', 'New Folder')
          : context.text('新建文件.txt', 'New File.txt'),
    );
    widget.state.setDialogOpen(true);
    await showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        title: Text(
          isFolder
              ? context.text('新建文件夹', 'New Folder')
              : context.text('新建文件', 'New File'),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isFolder
                ? context.text('请输入文件夹名称', 'Please enter folder name')
                : context.text('请输入文件名称', 'Please enter file name'),
          ),
          onSubmitted: (val) async {
            final name = val.trim();
            if (name.isNotEmpty) {
              Navigator.of(ctx).pop();
              final targetDir = _currentRelativePath.isEmpty
                  ? null
                  : Directory(
                      '${_getFilesDirectoryPathSync()}/$_currentRelativePath',
                    );
              if (isFolder) {
                await widget.state.createNewDirectory(
                  name,
                  targetDir: targetDir,
                );
              } else {
                await widget.state.createNewFile(name, targetDir: targetDir);
              }
              setState(() {});
            }
          },
        ),
        actions: [
          TextButton(
            child: Text(context.text('取消', 'Cancel')),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: Text(context.text('创建', 'Create')),
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop();
                final targetDir = _currentRelativePath.isEmpty
                    ? null
                    : Directory(
                        '${_getFilesDirectoryPathSync()}/$_currentRelativePath',
                      );
                if (isFolder) {
                  await widget.state.createNewDirectory(
                    name,
                    targetDir: targetDir,
                  );
                } else {
                  await widget.state.createNewFile(name, targetDir: targetDir);
                }
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
    widget.state.setDialogOpen(false);
  }

  void _showEmptySpaceContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    widget.state.setDialogOpen(true);
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'paste',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.content_paste_rounded, size: 14),
              const SizedBox(width: 8),
              Text(
                context.text('粘贴文件或图片', 'Paste Files/Images'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'new_file',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.note_add_rounded, size: 14),
              const SizedBox(width: 8),
              Text(
                context.text('新建文件', 'New File'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'new_folder',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.create_new_folder_rounded, size: 14),
              const SizedBox(width: 8),
              Text(
                context.text('新建文件夹', 'New Folder'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'open_folder',
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 14),
              const SizedBox(width: 8),
              Text(
                context.text('打开文件目录', 'Open Files Folder'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: isDark ? const Color(0xFF262626) : Colors.white,
    );
    widget.state.setDialogOpen(false);

    if (result == null) return;

    switch (result) {
      case 'paste':
        await _pasteFromClipboard();
        break;
      case 'new_file':
        if (context.mounted) _showNewNameDialog(context, false);
        break;
      case 'new_folder':
        if (context.mounted) _showNewNameDialog(context, true);
        break;
      case 'open_folder':
        final currentPath = _currentRelativePath.isEmpty
            ? _getFilesDirectoryPathSync()
            : '${_getFilesDirectoryPathSync()}/$_currentRelativePath';
        widget.state.openDirectoryPath(currentPath);
        break;
    }
  }

  Widget _buildGridView(List<FileSystemEntity> files) {
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
      child: GridView.builder(
        key: const PageStorageKey('files_grid_view'),
        controller: _gridScrollController,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: widget.state.fileDisplaySize,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 1.0,
        ),
        itemCount: files.length,
        itemBuilder: (ctx, index) {
          final file = files[index];
          final segments = file.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .toList();
          final fileName = segments.isEmpty
              ? context.text('未知', 'Unknown')
              : segments.last;
          final (icon, iconColor) = _getFileIconAndColor(file.path);
          return _GridFileCard(
            file: file,
            fileName: fileName,
            icon: icon,
            iconColor: iconColor,
            isImage: _isImage(file.path),
            isDark: widget.isDark,
            isSelected: _selectedFilePath == file.path,
            isCut: _cutFilePath == file.path,
            onSelect: () {
              _paneFocusNode.requestFocus();
              setState(() {
                _selectedFilePath = file.path;
              });
            },
            onOpen: () => _onFileOpen(file),
            onDelete: () => widget.state.deleteFile(file),
            onContextMenu: (ctx, pos) {
              _paneFocusNode.requestFocus();
              setState(() {
                _selectedFilePath = file.path;
              });
              _showContextMenu(
                ctx,
                pos,
                file,
                () => widget.state.deleteFile(file),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDetailsView(List<FileSystemEntity> files) {
    final scaleFactor = (widget.state.fileDisplaySize / 110.0).clamp(0.8, 1.4);
    return Column(
      children: [
        // Table Headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.text('名称', 'Name'),
                  style: TextStyle(
                    fontSize: 10 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              SizedBox(
                width: 50 * scaleFactor,
                child: Text(
                  context.text('大小', 'Size'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 65 * scaleFactor,
                child: Text(
                  context.text('创建时间', 'Created'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10 * scaleFactor,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Colors.grey),
        // List items
        Expanded(
          child: NotificationListener<OverscrollNotification>(
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
              key: const PageStorageKey('files_details_view'),
              controller: _detailsScrollController,
              itemCount: files.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (ctx, index) {
                final file = files[index];
                final segments = file.uri.pathSegments
                    .where((s) => s.isNotEmpty)
                    .toList();
                final fileName = segments.isEmpty
                    ? context.text('未知', 'Unknown')
                    : segments.last;
                final (icon, iconColor) = _getFileIconAndColor(file.path);
                final stat =
                    widget.state.getCachedFileStat(file.path) ??
                    (file.existsSync() ? file.statSync() : null);
                final isDir = widget.state.getCachedIsDirectory(file.path);
                final sizeStr = isDir
                    ? '—'
                    : (stat != null ? formatFileSize(stat.size) : '—');

                String dateStr = '—';
                if (stat != null) {
                  final date = Platform.isWindows
                      ? stat.changed
                      : stat.modified;
                  dateStr =
                      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                }

                return _DetailsFileCard(
                  file: file,
                  fileName: fileName,
                  sizeStr: sizeStr,
                  dateStr: dateStr,
                  icon: icon,
                  iconColor: iconColor,
                  isImage: _isImage(file.path),
                  isDark: widget.isDark,
                  isSelected: _selectedFilePath == file.path,
                  isCut: _cutFilePath == file.path,
                  onSelect: () {
                    _paneFocusNode.requestFocus();
                    setState(() {
                      _selectedFilePath = file.path;
                    });
                  },
                  onOpen: () => _onFileOpen(file),
                  onDelete: () => widget.state.deleteFile(file),
                  onContextMenu: (ctx, pos) {
                    _paneFocusNode.requestFocus();
                    setState(() {
                      _selectedFilePath = file.path;
                    });
                    _showContextMenu(
                      ctx,
                      pos,
                      file,
                      () => widget.state.deleteFile(file),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ══════════════════════════════════════════════════
// Search Bar widget
// ══════════════════════════════════════════════════
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final bool showFolderBtn;
  final VoidCallback onOpenFolder;

  const _SearchBar({
    required this.controller,
    required this.isDark,
    required this.showFolderBtn,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.zero,
      ),
      child: TextField(
        controller: controller,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: context.text('搜索文件...', 'Search files...'),
          hintStyle: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white30 : Colors.black54,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 6),
            child: Icon(
              Icons.search_rounded,
              size: 14,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 14,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedPress(
                      onTap: () => controller.clear(),
                      child: const Icon(Icons.clear, size: 15),
                    ),
                  ),
                )
              : showFolderBtn
              ? Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedPress(
                      onTap: onOpenFolder,
                      child: const Icon(Icons.folder_open_outlined, size: 16),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// List Card
// ══════════════════════════════════════════════════
// ══════════════════════════════════════════════════
// Reusable Delete Button with Hover Feedback
// ══════════════════════════════════════════════════
class _DeleteButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _DeleteButton({required this.onTap, required this.isDark});

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isDark
                      ? Colors.red.withOpacity(0.24)
                      : Colors.red.withOpacity(0.2))
                : (widget.isDark
                      ? Colors.red.withOpacity(0.12)
                      : Colors.red.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.close,
            size: 11,
            color: _isHovered
                ? Colors.red
                : (widget.isDark ? Colors.red[300] : Colors.red[700]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// List Card
// ══════════════════════════════════════════════════

// ══════════════════════════════════════════════════
// Grid Card
// ══════════════════════════════════════════════════
class _GridFileCard extends StatefulWidget {
  final FileSystemEntity file;
  final String fileName;
  final IconData icon;
  final Color iconColor;
  final bool isImage;
  final bool isDark;
  final bool isSelected;
  final bool isCut;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final void Function(BuildContext, Offset) onContextMenu;

  const _GridFileCard({
    required this.file,
    required this.fileName,
    required this.icon,
    required this.iconColor,
    required this.isImage,
    required this.isDark,
    required this.isSelected,
    required this.isCut,
    required this.onSelect,
    required this.onOpen,
    required this.onDelete,
    required this.onContextMenu,
  });

  @override
  State<_GridFileCard> createState() => _GridFileCardState();
}

class _GridFileCardState extends State<_GridFileCard> {
  bool _isHovered = false;
  DateTime? _lastTapTime;

  @override
  Widget build(BuildContext context) {
    final isDir = widget.file is Directory;
    final accentColor = AppTheme.getAccentColor(
      AppState().settings.themeColorName,
      widget.isDark,
    );

    final card = sdd.DragItemWidget(
      dragItemProvider: (request) {
        final item = sdd.DragItem(localData: 'internal_file_drag');
        item.add(sdd.Formats.fileUri(Uri.file(widget.file.path)));
        return item;
      },
      allowedOperations: () => [sdd.DropOperation.copy],
      child: sdd.DraggableWidget(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: GestureDetector(
            onSecondaryTapUp: (details) =>
                widget.onContextMenu(context, details.globalPosition),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.zero,
                onTap: () {
                  final now = DateTime.now();
                  if (_lastTapTime != null &&
                      now.difference(_lastTapTime!) <
                          const Duration(milliseconds: 300)) {
                    _lastTapTime = null;
                    widget.onOpen();
                  } else {
                    _lastTapTime = now;
                    widget.onSelect();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? accentColor.withOpacity(widget.isDark ? 0.15 : 0.1)
                        : (_isHovered
                            ? (widget.isDark
                                  ? Colors.white.withOpacity(0.07)
                                  : Colors.black.withOpacity(0.05))
                            : (widget.isDark
                                  ? Colors.white.withOpacity(0.03)
                                  : Colors.black.withOpacity(0.02))),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                      color: widget.isSelected
                          ? accentColor
                          : (_isHovered
                              ? (widget.isDark ? Colors.white12 : Colors.black12)
                              : Colors.transparent),
                      width: widget.isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: widget.isImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.zero,
                                    child: Image.file(
                                      File(widget.file.path),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final fallbackIconSize =
                                                constraints.maxWidth * 0.45;
                                            return Icon(
                                              widget.icon,
                                              size: fallbackIconSize,
                                              color: widget.iconColor,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  )
                                : AspectRatio(
                                    aspectRatio: 1.0,
                                    child: FractionallySizedBox(
                                      widthFactor: 0.6,
                                      heightFactor: 0.6,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: widget.iconColor.withOpacity(
                                            0.12,
                                          ),
                                          borderRadius: BorderRadius.zero,
                                        ),
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final iconSize =
                                                constraints.maxWidth * 0.6;
                                            return Icon(
                                              widget.icon,
                                              size: iconSize,
                                              color: widget.iconColor,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 8.8,
                            height: 1.12,
                            color: widget.isDark
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final resultWidget = isDir
        ? sdd.DropRegion(
            formats: const [sdd.Formats.fileUri],
            onDropOver: (event) {
              return sdd.DropOperation.copy;
            },
            onPerformDrop: (event) async {
              final items = event.session.items;
              if (items.isEmpty) return;

              for (final item in items) {
                final reader = item.dataReader;
                if (reader != null && reader.canProvide(sdd.Formats.fileUri)) {
                  reader.getValue<Uri>(sdd.Formats.fileUri, (uri) {
                    if (uri != null) {
                      final sourcePath = uri.toFilePath();
                      if (item.localData == 'internal_file_drag') {
                        final sourceEntity =
                            FileSystemEntity.isDirectorySync(sourcePath)
                            ? Directory(sourcePath)
                            : File(sourcePath);
                        AppState().moveFileToFolder(
                          sourceEntity,
                          Directory(widget.file.path),
                        );
                      } else {
                        AppState().addDroppedFiles([
                          sourcePath,
                        ], targetDir: Directory(widget.file.path));
                      }
                    }
                  });
                }
              }
            },
            child: card,
          )
        : card;

    return Opacity(
      opacity: widget.isCut ? 0.55 : 1.0,
      child: resultWidget,
    );
  }
}

// ══════════════════════════════════════════════════
// File Preview Dialog
// ══════════════════════════════════════════════════
class _FilePreviewDialog extends StatefulWidget {
  final FileSystemEntity file;
  final String fileName;
  final bool isImage;
  final bool isText;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _FilePreviewDialog({
    required this.file,
    required this.fileName,
    required this.isImage,
    required this.isText,
    required this.isDark,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  String? _textContent;
  bool _loadingText = false;

  @override
  void initState() {
    super.initState();
    if (widget.isText) {
      _loadingText = true;
      File(widget.file.path)
          .readAsString()
          .then((content) {
            if (mounted) {
              setState(() {
                _textContent = content.length > 4000
                    ? '${content.substring(0, 4000)}\n' +
                          context.text(
                            '...(仅预览前 4000 字符)',
                            '...(Previewing first 4000 characters only)',
                          )
                    : content;
                _loadingText = false;
              });
            }
          })
          .catchError((_) {
            if (mounted) setState(() => _loadingText = false);
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subColor = widget.isDark ? Colors.white54 : Colors.black45;

    // File metadata
    final stat =
        AppState().getCachedFileStat(widget.file.path) ??
        (widget.file.existsSync() ? widget.file.statSync() : null);
    final size = stat != null ? _FilesPaneState.formatFileSize(stat.size) : '—';
    final creationTime = stat != null
        ? (Platform.isWindows ? stat.changed : stat.modified)
        : null;
    final createdStr = creationTime != null
        ? '${creationTime.year}-${creationTime.month.toString().padLeft(2, '0')}-${creationTime.day.toString().padLeft(2, '0')}'
        : '—';

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(size, style: TextStyle(fontSize: 11, color: subColor)),
                  const SizedBox(width: 8),
                  Text(
                    createdStr,
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(Icons.close, size: 16, color: subColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: widget.isDark ? Colors.white12 : Colors.black12,
            ),

            // ── Preview area ──
            Flexible(child: _buildPreviewBody(textColor, subColor)),

            Divider(
              height: 1,
              color: widget.isDark ? Colors.white12 : Colors.black12,
            ),

            // ── Actions ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onDelete,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.text('删除', 'Delete'),
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.isDark
                                ? Colors.red[300]
                                : Colors.red[700],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onOpen,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.text('用应用打开', 'Open with App'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
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
    );
  }

  Widget _buildPreviewBody(Color textColor, Color subColor) {
    if (widget.isImage) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(widget.file.path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, size: 48, color: subColor),
                  const SizedBox(height: 8),
                  Text(
                    context.text('无法加载图片', 'Failed to load image'),
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (widget.isText) {
      if (_loadingText) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_textContent != null) {
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Text(
              _textContent!,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        );
      }
    }

    // Generic file info
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 52, color: subColor),
          const SizedBox(height: 12),
          Text(
            context.text(
              '此文件类型不支持预览',
              'Preview not supported for this file type',
            ),
            style: TextStyle(fontSize: 13, color: subColor),
          ),
          const SizedBox(height: 4),
          Text(
            context.text(
              '点击「用应用打开」在外部程序中查看',
              'Click "Open with App" to view in an external program',
            ),
            style: TextStyle(fontSize: 11, color: subColor),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Details Card
// ══════════════════════════════════════════════════
class _DetailsFileCard extends StatefulWidget {
  final FileSystemEntity file;
  final String fileName;
  final String sizeStr;
  final String dateStr;
  final IconData icon;
  final Color iconColor;
  final bool isImage;
  final bool isDark;
  final bool isSelected;
  final bool isCut;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final void Function(BuildContext, Offset) onContextMenu;

  const _DetailsFileCard({
    required this.file,
    required this.fileName,
    required this.sizeStr,
    required this.dateStr,
    required this.icon,
    required this.iconColor,
    required this.isImage,
    required this.isDark,
    required this.isSelected,
    required this.isCut,
    required this.onSelect,
    required this.onOpen,
    required this.onDelete,
    required this.onContextMenu,
  });

  @override
  State<_DetailsFileCard> createState() => _DetailsFileCardState();
}

class _DetailsFileCardState extends State<_DetailsFileCard> {
  bool _isHovered = false;
  DateTime? _lastTapTime;

  @override
  Widget build(BuildContext context) {
    final scaleFactor = (AppState().fileDisplaySize / 110.0).clamp(0.8, 1.4);
    final isDir = widget.file is Directory;
    final accentColor = AppTheme.getAccentColor(
      AppState().settings.themeColorName,
      widget.isDark,
    );

    final card = sdd.DragItemWidget(
      dragItemProvider: (request) {
        final item = sdd.DragItem(localData: 'internal_file_drag');
        item.add(sdd.Formats.fileUri(Uri.file(widget.file.path)));
        return item;
      },
      allowedOperations: () => [sdd.DropOperation.copy],
      child: sdd.DraggableWidget(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: GestureDetector(
            onSecondaryTapUp: (details) =>
                widget.onContextMenu(context, details.globalPosition),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.zero,
                onTap: () {
                  final now = DateTime.now();
                  if (_lastTapTime != null &&
                      now.difference(_lastTapTime!) <
                          const Duration(milliseconds: 300)) {
                    _lastTapTime = null;
                    widget.onOpen();
                  } else {
                    _lastTapTime = now;
                    widget.onSelect();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 0.5 * scaleFactor,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? accentColor.withOpacity(widget.isDark ? 0.15 : 0.1)
                        : (_isHovered
                            ? (widget.isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.black.withOpacity(0.04))
                            : Colors.transparent),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                      color: widget.isSelected ? accentColor : Colors.transparent,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 17 * scaleFactor,
                        height: 17 * scaleFactor,
                        decoration: BoxDecoration(
                          color: widget.iconColor.withOpacity(0.12),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: widget.isImage
                            ? ClipRRect(
                                borderRadius: BorderRadius.zero,
                                child: Image.file(
                                  File(widget.file.path),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    widget.icon,
                                    size: 10 * scaleFactor,
                                    color: widget.iconColor,
                                  ),
                                ),
                              )
                            : Icon(
                                widget.icon,
                                size: 10 * scaleFactor,
                                color: widget.iconColor,
                              ),
                      ),
                      const SizedBox(width: 4),
                      // Name
                      Expanded(
                        child: Text(
                          widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11 * scaleFactor,
                            height: 1.12,
                            fontWeight: FontWeight.w500,
                            color: widget.isDark
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Size
                      SizedBox(
                        width: 50 * scaleFactor,
                        child: Text(
                          widget.sizeStr,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10 * scaleFactor,
                            height: 1.1,
                            color: widget.isDark
                                ? Colors.white38
                                : Colors.black45,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      // Date
                      SizedBox(
                        width: 65 * scaleFactor,
                        child: Text(
                          widget.dateStr,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10 * scaleFactor,
                            height: 1.1,
                            color: widget.isDark
                                ? Colors.white38
                                : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final resultWidget = isDir
        ? sdd.DropRegion(
            formats: const [sdd.Formats.fileUri],
            onDropOver: (event) {
              return sdd.DropOperation.copy;
            },
            onPerformDrop: (event) async {
              final items = event.session.items;
              if (items.isEmpty) return;

              for (final item in items) {
                final reader = item.dataReader;
                if (reader != null && reader.canProvide(sdd.Formats.fileUri)) {
                  reader.getValue<Uri>(sdd.Formats.fileUri, (uri) {
                    if (uri != null) {
                      final sourcePath = uri.toFilePath();
                      if (item.localData == 'internal_file_drag') {
                        final sourceEntity =
                            FileSystemEntity.isDirectorySync(sourcePath)
                            ? Directory(sourcePath)
                            : File(sourcePath);
                        AppState().moveFileToFolder(
                          sourceEntity,
                          Directory(widget.file.path),
                        );
                      } else {
                        AppState().addDroppedFiles([
                          sourcePath,
                        ], targetDir: Directory(widget.file.path));
                      }
                    }
                  });
                }
              }
            },
            child: card,
          )
        : card;

    return Opacity(
      opacity: widget.isCut ? 0.55 : 1.0,
      child: resultWidget,
    );
  }
}
