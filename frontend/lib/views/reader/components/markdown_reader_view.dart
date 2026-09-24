import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../models/annotation_model.dart';
import '../../../models/document_model.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/document_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../theme/app_theme.dart';
import 'floating_selection_bar.dart';
import 'note_editor_dialog.dart';

class MarkdownPageChunk {
  final int pageNumber;
  final String content;

  const MarkdownPageChunk({
    required this.pageNumber,
    required this.content,
  });
}

class MarkdownHeadingItem {
  final String title;
  final int level;
  final int pageNumber;
  final int chunkIndex;

  const MarkdownHeadingItem({
    required this.title,
    required this.level,
    required this.pageNumber,
    required this.chunkIndex,
  });
}

class SearchMatchItem {
  final int chunkIndex;
  final int pageNumber;
  final int matchCount;
  final String previewSnippet;

  const SearchMatchItem({
    required this.chunkIndex,
    required this.pageNumber,
    required this.matchCount,
    required this.previewSnippet,
  });
}

class MarkdownActiveSelection {
  final String text;
  final int pageNumber;
  final Offset position;

  const MarkdownActiveSelection({
    required this.text,
    required this.pageNumber,
    required this.position,
  });
}

class MarkdownReaderView extends StatefulWidget {
  final DocumentModel document;
  final String markdownContent;
  final int currentPage;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback onOpenOcr;
  final ValueChanged<String>? onMarkdownUpdated;

  const MarkdownReaderView({
    super.key,
    required this.document,
    required this.markdownContent,
    this.currentPage = 1,
    this.onPageChanged,
    required this.onOpenOcr,
    this.onMarkdownUpdated,
  });

  @override
  State<MarkdownReaderView> createState() => MarkdownReaderViewState();
}

class MarkdownReaderViewState extends State<MarkdownReaderView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<int, GlobalKey> _cardKeys = {};
  final Uuid _uuid = const Uuid();

  List<MarkdownPageChunk> _chunks = [];
  List<MarkdownHeadingItem> _headings = [];
  final Map<int, double> _pageHeights = {};
  final double _estimatedAverageHeight = 1000.0;

  bool _isSearching = false;
  String _searchQuery = "";
  List<SearchMatchItem> _searchMatches = [];
  int _totalSearchMatches = 0;

  // Active text selection state for floating menu
  MarkdownActiveSelection? _activeSelection;
  String _pendingSelectionText = '';
  int _pendingSelectionPage = 1;
  bool _isProgrammaticScrolling = false;
  int? _lastReportedPage;
  bool _hasExplicitPageMarkers = false;

  // Custom Markdown extension set supporting LaTeX formulas and Highlight syntax
  static final md.ExtensionSet _latexExtensionSet = md.ExtensionSet(
    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    <md.InlineSyntax>[
      LatexBlockInlineSyntax(),
      LatexBracketInlineSyntax(),
      LatexInlineSyntax(),
      LatexParenInlineSyntax(),
      MarkdownHighlightInlineSyntax(),
      HtmlMarkInlineSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ],
  );

  @override
  void initState() {
    super.initState();
    _lastReportedPage = widget.currentPage;
    _processMarkdown(widget.markdownContent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.currentPage > 1) {
        jumpToPage(widget.currentPage);
      }
    });
  }

  @override
  void didUpdateWidget(covariant MarkdownReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdownContent != widget.markdownContent) {
      _processMarkdown(widget.markdownContent);
    }
    if (oldWidget.currentPage != widget.currentPage &&
        widget.currentPage > 0 &&
        widget.currentPage != _lastReportedPage &&
        !_isProgrammaticScrolling) {
      _lastReportedPage = widget.currentPage;
      jumpToPage(widget.currentPage);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _processMarkdown(String rawMarkdown) {
    _chunks = _parseMarkdownChunks(rawMarkdown);
    _extractHeadings();
    _cardKeys.clear();
    for (final chunk in _chunks) {
      _cardKeys[chunk.pageNumber] = GlobalKey();
    }
    _pageHeights.clear();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_isProgrammaticScrolling) return false;
    if (_activeSelection != null && notification is ScrollUpdateNotification) {
      setState(() => _activeSelection = null);
    }
    if (notification is ScrollUpdateNotification || notification is ScrollEndNotification) {
      _detectVisiblePage();
    }
    return false;
  }

  Widget _buildPositionedFloatingBar({
    required BuildContext context,
    required Offset pointerPos,
    required Size containerSize,
    required Widget child,
  }) {
    const double menuWidth = 380.0;
    const double menuHeight = 48.0;

    double left = pointerPos.dx - (menuWidth / 2);
    if (left < 16) left = 16;
    if (left + menuWidth > containerSize.width - 16) {
      left = containerSize.width - menuWidth - 16;
    }
    if (left < 0) left = 0;

    double top = pointerPos.dy - menuHeight - 16;
    if (top < 10) {
      top = pointerPos.dy + 20;
    }
    if (top + menuHeight > containerSize.height - 10) {
      top = containerSize.height - menuHeight - 10;
    }
    if (top < 0) top = 0;

    return Positioned(
      left: left,
      top: top,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        builder: (context, val, animChild) {
          return Transform.scale(
            scale: val,
            alignment: Alignment.center,
            child: animChild,
          );
        },
        child: child,
      ),
    );
  }

  void _detectVisiblePage() {
    if (!_scrollController.hasClients || _chunks.isEmpty || _isProgrammaticScrolling) return;

    int? detectedPage;
    const double targetY = 100.0; // Point below top bar (60px) + margin

    for (final entry in _cardKeys.entries) {
      final pageNum = entry.key;
      final ctx = entry.value.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.attached) {
          final pos = box.localToGlobal(Offset.zero);
          final height = box.size.height;
          _pageHeights[pageNum] = height;

          // Deterministic single-point intersection
          if (pos.dy <= targetY && (pos.dy + height) > targetY) {
            detectedPage = pageNum;
            break;
          }
        }
      }
    }

    // Boundary check: if scrolled to top and first card top starts below targetY
    if (detectedPage == null) {
      for (final entry in _cardKeys.entries) {
        final ctx = entry.value.currentContext;
        if (ctx != null) {
          final box = ctx.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize && box.attached) {
            final pos = box.localToGlobal(Offset.zero);
            if (pos.dy > targetY) {
              detectedPage = entry.key;
              break;
            }
          }
        }
      }
    }

    if (detectedPage != null) {
      if (detectedPage != _lastReportedPage) {
        _lastReportedPage = detectedPage;
        widget.onPageChanged?.call(detectedPage);
      }
      return;
    }

    // Fallback: Calculate via scroll offset and cached heights
    final offset = _scrollController.offset;
    double accumulated = 0;
    int fallbackPage = _chunks.first.pageNumber;
    for (int i = 0; i < _chunks.length; i++) {
      final pNum = _chunks[i].pageNumber;
      final h = _pageHeights[pNum] ?? _estimatedAverageHeight;
      if (offset >= accumulated - 50 && offset < accumulated + h) {
        fallbackPage = pNum;
        break;
      }
      accumulated += h;
    }
    if (fallbackPage != _lastReportedPage) {
      _lastReportedPage = fallbackPage;
      widget.onPageChanged?.call(fallbackPage);
    }
  }

  List<MarkdownPageChunk> _parseMarkdownChunks(String rawMarkdown) {
    if (rawMarkdown.trim().isEmpty) return [];

    final pageRegex = RegExp(r'<!--\s*Page\s+(\d+)\s*-->', caseSensitive: false);
    final matches = pageRegex.allMatches(rawMarkdown).toList();

    final List<MarkdownPageChunk> chunks = [];

    if (matches.isNotEmpty) {
      _hasExplicitPageMarkers = true;
      for (int i = 0; i < matches.length; i++) {
        final currentMatch = matches[i];
        final pageNumStr = currentMatch.group(1);
        final pageNum = int.tryParse(pageNumStr ?? '') ?? (i + 1);

        final startIndex = currentMatch.end;
        final endIndex = (i + 1 < matches.length) ? matches[i + 1].start : rawMarkdown.length;
        final content = rawMarkdown.substring(startIndex, endIndex).trim();

        if (content.isNotEmpty) {
          chunks.add(MarkdownPageChunk(
            pageNumber: pageNum,
            content: content,
          ));
        }
      }
    } else {
      _hasExplicitPageMarkers = false;
    }

    // Fallback: If no <!-- Page X --> markers present, split by top-level H1 headers or ~70 lines
    if (chunks.isEmpty) {
      final lines = rawMarkdown.split('\n');
      final List<String> currentChunkLines = [];
      int chunkPage = 1;

      for (final line in lines) {
        currentChunkLines.add(line);
        if (currentChunkLines.length >= 70 || (currentChunkLines.length >= 30 && line.trim().startsWith('# '))) {
          final chunkText = currentChunkLines.join('\n').trim();
          if (chunkText.isNotEmpty) {
            chunks.add(MarkdownPageChunk(
              pageNumber: chunkPage++,
              content: chunkText,
            ));
            currentChunkLines.clear();
          }
        }
      }
      if (currentChunkLines.isNotEmpty) {
        final chunkText = currentChunkLines.join('\n').trim();
        if (chunkText.isNotEmpty) {
          chunks.add(MarkdownPageChunk(
            pageNumber: chunkPage,
            content: chunkText,
          ));
        }
      }
    }

    if (chunks.isEmpty && rawMarkdown.trim().isNotEmpty) {
      chunks.add(MarkdownPageChunk(
        pageNumber: 1,
        content: rawMarkdown.trim(),
      ));
    }

    return chunks;
  }

  String _recombineChunks(List<MarkdownPageChunk> chunks) {
    if (chunks.isEmpty) return '';
    if (_hasExplicitPageMarkers) {
      final sb = StringBuffer();
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        sb.writeln('<!-- Page ${chunk.pageNumber} -->');
        sb.writeln();
        sb.writeln(chunk.content);
        if (i < chunks.length - 1) {
          sb.writeln();
        }
      }
      return sb.toString();
    } else {
      if (chunks.length == 1) {
        return chunks.first.content;
      }
      return chunks.map((c) => c.content).join('\n\n');
    }
  }

  void _extractHeadings() {
    _headings = [];
    for (int chunkIdx = 0; chunkIdx < _chunks.length; chunkIdx++) {
      final chunk = _chunks[chunkIdx];
      final lines = chunk.content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        int level = 0;
        String cleanTitle = "";

        if (trimmed.startsWith('#### ')) {
          level = 4;
          cleanTitle = trimmed.substring(5).trim();
        } else if (trimmed.startsWith('### ')) {
          level = 3;
          cleanTitle = trimmed.substring(4).trim();
        } else if (trimmed.startsWith('## ')) {
          level = 2;
          cleanTitle = trimmed.substring(3).trim();
        } else if (trimmed.startsWith('# ')) {
          level = 1;
          cleanTitle = trimmed.substring(2).trim();
        }

        if (level > 0 && cleanTitle.isNotEmpty) {
          _headings.add(MarkdownHeadingItem(
            title: cleanTitle,
            level: level,
            pageNumber: chunk.pageNumber,
            chunkIndex: chunkIdx,
          ));
        }
      }
    }
  }

  void jumpToPage(int pageNumber) {
    if (_chunks.isEmpty) return;

    int targetIndex = _chunks.indexWhere((c) => c.pageNumber == pageNumber);
    if (targetIndex == -1) {
      targetIndex = (pageNumber - 1).clamp(0, _chunks.length - 1);
    }

    _lastReportedPage = pageNumber;
    _isProgrammaticScrolling = true;

    void attemptScroll(int attemptsLeft) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        if (attemptsLeft > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => attemptScroll(attemptsLeft - 1));
        }
        return;
      }

      // 1. If target card is already rendered in the DOM, align it right below the top bar!
      final key = _cardKeys[pageNumber];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: 0.0,
        ).then((_) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _isProgrammaticScrolling = false;
              if (_lastReportedPage != pageNumber) {
                _lastReportedPage = pageNumber;
                widget.onPageChanged?.call(pageNumber);
              }
            }
          });
        });
        return;
      }

      // 2. Compute cumulative target offset
      double targetOffset = 0;
      for (int i = 0; i < targetIndex; i++) {
        final pNum = _chunks[i].pageNumber;
        targetOffset += _pageHeights[pNum] ?? _estimatedAverageHeight;
      }

      final position = _scrollController.position;
      final maxExtent = position.maxScrollExtent;
      final currentOffset = position.pixels;

      // Jump towards targetOffset to force ListView.builder to build slivers around targetOffset
      final nextOffset = targetOffset.clamp(0.0, maxExtent > 0 ? maxExtent : targetOffset);
      if ((nextOffset - currentOffset).abs() > 1.0) {
        _scrollController.jumpTo(nextOffset);
      }

      // Check in next frame if slivers have now been instantiated
      if (attemptsLeft > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          attemptScroll(attemptsLeft - 1);
        });
      } else {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            _isProgrammaticScrolling = false;
            if (_lastReportedPage != pageNumber) {
              _lastReportedPage = pageNumber;
              widget.onPageChanged?.call(pageNumber);
            }
          }
        });
      }
    }

    attemptScroll(10);
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
      _searchMatches = [];
      _totalSearchMatches = 0;

      if (_searchQuery.isNotEmpty) {
        for (int i = 0; i < _chunks.length; i++) {
          final chunk = _chunks[i];
          final text = chunk.content.toLowerCase();
          int count = 0;
          int matchIndex = text.indexOf(_searchQuery);
          int firstMatchIndex = matchIndex;

          while (matchIndex != -1) {
            count++;
            matchIndex = text.indexOf(_searchQuery, matchIndex + _searchQuery.length);
          }

          if (count > 0) {
            _totalSearchMatches += count;
            final snippetStart = (firstMatchIndex - 20).clamp(0, chunk.content.length);
            final snippetEnd = (firstMatchIndex + _searchQuery.length + 30).clamp(0, chunk.content.length);
            final snippet = chunk.content.substring(snippetStart, snippetEnd).replaceAll('\n', ' ');

            _searchMatches.add(SearchMatchItem(
              chunkIndex: i,
              pageNumber: chunk.pageNumber,
              matchCount: count,
              previewSnippet: '...$snippet...',
            ));
          }
        }
      }
    });
  }

  void _createAnnotationFromSelection(
    String selectedText,
    String colorHex,
    int pageNumber, {
    String noteContent = "",
  }) async {
    if (selectedText.trim().isEmpty) return;

    final trimmedText = selectedText.trim();
    final normalizedHex = colorHex.toUpperCase();
    final tagPrefix = (normalizedHex == '#FDE047' || normalizedHex == 'FDE047')
        ? '=='
        : '==[$normalizedHex]';
    final replacement = '$tagPrefix$trimmedText==';

    final docProvider = context.read<DocumentProvider>();
    final annoProvider = context.read<AnnotationProvider>();

    // 1. Update the chunk and combined markdown with highlight syntax
    int chunkIdx = _chunks.indexWhere((c) => c.pageNumber == pageNumber);
    if (chunkIdx == -1 && _chunks.isNotEmpty) {
      chunkIdx = 0;
    }

    if (chunkIdx != -1) {
      final oldChunk = _chunks[chunkIdx];
      if (!oldChunk.content.contains(replacement) && oldChunk.content.contains(trimmedText)) {
        final newChunkContent = oldChunk.content.replaceFirst(trimmedText, replacement);
        _chunks[chunkIdx] = MarkdownPageChunk(
          pageNumber: oldChunk.pageNumber,
          content: newChunkContent,
        );

        final combinedMd = _recombineChunks(_chunks);
        widget.onMarkdownUpdated?.call(combinedMd);

        try {
          await docProvider.saveMarkdown(widget.document.id, combinedMd);
        } catch (e) {
          debugPrint('Error saving markdown: $e');
        }
      }
    }

    // 2. Create annotation record with empty rects (prevents drawing full-page box on PDF canvas)
    final newAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: noteContent.isNotEmpty ? "note" : "highlight",
      pageNumber: pageNumber,
      colorHex: colorHex,
      rects: const [],
      selectedText: trimmedText,
      noteContent: noteContent,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await annoProvider.addAnnotation(newAnno);
    if (mounted) {
      docProvider.updateAnnotationCount(widget.document.id, 1);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.parseHexColor(colorHex),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  noteContent.isNotEmpty ? '已添加第 $pageNumber 页批注与笔记' : '已添加第 $pageNumber 页荧光划词高亮',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showNoteDialogForSelection(String selectedText, int pageNumber) {
    if (selectedText.trim().isEmpty) return;

    final tempAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "note",
      pageNumber: pageNumber,
      colorHex: context.read<AnnotationProvider>().activeHighlightColor,
      rects: const [],
      selectedText: selectedText.trim(),
      noteContent: "",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    showDialog(
      context: context,
      builder: (_) => NoteEditorDialog(
        annotation: tempAnno,
        onSave: (saved) {
          _createAnnotationFromSelection(
            selectedText,
            saved.colorHex,
            pageNumber,
            noteContent: saved.noteContent,
          );
        },
        onDelete: () {},
      ),
    );
  }

  void _showHeadingsOutlineSheet() {
    final settings = context.read<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: theme.cardTheme.color,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          constraints: const BoxConstraints(maxHeight: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.list_alt_rounded, color: theme.colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '文档大纲 / 目录',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    '${_headings.length} 个章节标题',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (_headings.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      '未检测到 H1 / H2 / H3 标题标记',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _headings.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final item = _headings[idx];

                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          jumpToPage(item.pageNumber);
                        },
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: (item.level - 1) * 16.0 + 8.0,
                            right: 8.0,
                            top: 10.0,
                            bottom: 10.0,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item.level == 1
                                    ? Icons.bookmark_rounded
                                    : item.level == 2
                                        ? Icons.label_important_rounded
                                        : Icons.subdirectory_arrow_right_rounded,
                                size: 16,
                                color: item.level == 1
                                    ? theme.colorScheme.primary
                                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: item.level == 1 ? 14 : 13,
                                    fontWeight: item.level <= 2 ? FontWeight.bold : FontWeight.normal,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'P.${item.pageNumber}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
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
          ),
        );
      },
    );
  }

  Widget _buildMarkdownContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
    int pageNumber,
  ) {
    // ignore: deprecated_member_use
    final value = selectableRegionState.textEditingValue;
    final text = value.text;
    final start = value.selection.start.clamp(0, text.length);
    final end = value.selection.end.clamp(0, text.length);
    final selectedText = (start < end) ? text.substring(start, end) : '';

    if (selectedText.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return AdaptiveTextSelectionToolbar(
      anchors: selectableRegionState.contextMenuAnchors,
      children: [
        FloatingSelectionBar(
          selectedText: selectedText,
          readingMode: context.read<ReaderSettingsProvider>().readingMode,
          onHighlight: (colorHex) {
            _createAnnotationFromSelection(selectedText, colorHex, pageNumber);
            selectableRegionState.hideToolbar();
          },
          onAddNote: () {
            selectableRegionState.hideToolbar();
            _showNoteDialogForSelection(selectedText, pageNumber);
          },
          onDismiss: () {
            selectableRegionState.hideToolbar();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettingsProvider>();
    final theme = Theme.of(context);
    final isDark = settings.readingMode == ReadingMode.dark;
    final isSepia = settings.readingMode == ReadingMode.sepia;

    // Theme color mappings
    final canvasBg = isDark
        ? const Color(0xFF0F172A)
        : isSepia
            ? const Color(0xFFFBF6E9)
            : const Color(0xFFFFFFFF);

    final cardBg = isDark
        ? const Color(0xFF1E293B)
        : isSepia
            ? const Color(0xFFF7EED9)
            : const Color(0xFFFFFFFF);

    final textColor = isDark
        ? const Color(0xFFF1F5F9)
        : isSepia
            ? const Color(0xFF3D2714)
            : const Color(0xFF1E293B);

    final codeBg = isDark
        ? const Color(0xFF0F172A)
        : isSepia
            ? const Color(0xFFEFE6CF)
            : const Color(0xFFF1F5F9);

    final zoom = settings.zoomScale.clamp(0.5, 4.0);
    final baseFontSize = 15.5 * zoom;
    final cardMaxWidth = (880.0 * zoom).clamp(520.0, 1600.0);

    return Scaffold(
      backgroundColor: canvasBg,
      body: Stack(
        children: [
          Column(
            children: [
              // Markdown Helper Sub-Toolbar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : (isSepia ? const Color(0xFFEFE6CF) : const Color(0xFFF8FAFC)),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Outline / Table of Contents Button
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _showHeadingsOutlineSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.menu_book_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '目录 (${_headings.length})',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Search Toggle Button
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() {
                        _isSearching = !_isSearching;
                        if (!_isSearching) {
                          _searchController.clear();
                          _onSearchChanged("");
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _isSearching
                              ? theme.colorScheme.primary.withValues(alpha: 0.15)
                              : theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isSearching
                                ? theme.colorScheme.primary
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 16,
                              color: _isSearching ? theme.colorScheme.primary : null,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '全文检索',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isSearching ? theme.colorScheme.primary : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Page Count Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '共 ${_chunks.length} 页 • 虚拟流畅渲染',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Copy Markdown Button
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      tooltip: '复制全文 Markdown',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.markdownContent));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Markdown 全文已复制到剪贴板'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      },
                    ),

                    // Trigger Re-OCR / Baidu Update
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: '重新解析或更新 Markdown (百度 API)',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onOpenOcr,
                    ),
                  ],
                ),
              ),

              // Search Toolbar & Quick Match Jump List
              if (_isSearching)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: r'搜索文档内容与公式 (如: 神经网络、定理、$$)...',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: InputBorder.none,
                              ),
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            Text(
                              _totalSearchMatches > 0
                                  ? '共 $_totalSearchMatches 处匹配 (${_searchMatches.length} 个页面)'
                                  : '未找到匹配结果',
                              style: TextStyle(
                                fontSize: 12,
                                color: _totalSearchMatches > 0 ? theme.colorScheme.primary : Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged("");
                            },
                          ),
                        ],
                      ),
                      if (_searchMatches.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          height: 38,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _searchMatches.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 6),
                            itemBuilder: (ctx, idx) {
                              final match = _searchMatches[idx];
                              return ActionChip(
                                avatar: CircleAvatar(
                                  radius: 9,
                                  backgroundColor: theme.colorScheme.primary,
                                  child: Text(
                                    '${match.matchCount}',
                                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                label: Text('第 ${match.pageNumber} 页'),
                                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                onPressed: () {
                                  jumpToPage(match.pageNumber);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

              // Virtualized Page List View with accurate Scroll Notification Listener
              Expanded(
                child: _chunks.isEmpty
                    ? Center(
                        child: Text(
                          '暂无 Markdown 内容',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: _onScrollNotification,
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (event) {
                            _pendingSelectionText = '';
                            if (_activeSelection != null) {
                              setState(() => _activeSelection = null);
                            }
                          },
                          onPointerUp: (event) async {
                            final renderBox = context.findRenderObject() as RenderBox?;
                            final stackPos = renderBox != null
                                ? renderBox.globalToLocal(event.position)
                                : event.localPosition;
                            await Future.delayed(const Duration(milliseconds: 50));
                            if (!mounted) return;
                            if (_pendingSelectionText.isNotEmpty) {
                              setState(() {
                                _activeSelection = MarkdownActiveSelection(
                                  text: _pendingSelectionText,
                                  pageNumber: _pendingSelectionPage,
                                  position: stackPos,
                                );
                              });
                            }
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            // ignore: deprecated_member_use
                            cacheExtent: 1200,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                            itemCount: _chunks.length,
                            itemBuilder: (context, index) {
                              final chunk = _chunks[index];

                              return _buildPageCard(
                                context: context,
                                chunk: chunk,
                                index: index,
                                theme: theme,
                                isDark: isDark,
                                isSepia: isSepia,
                                cardBg: cardBg,
                                textColor: textColor,
                                codeBg: codeBg,
                                baseFontSize: baseFontSize,
                                cardMaxWidth: cardMaxWidth,
                              );
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),

          // Auto-Popup Floating Toolbar following cursor when text is selected in Markdown mode (Appears on pointer release)
          if (_activeSelection != null)
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    _buildPositionedFloatingBar(
                      context: context,
                      pointerPos: _activeSelection!.position,
                      containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                      child: Material(
                        type: MaterialType.transparency,
                        child: FloatingSelectionBar(
                          selectedText: _activeSelection!.text,
                          readingMode: settings.readingMode,
                          onHighlight: (colorHex) {
                            final sel = _activeSelection;
                            if (sel != null) {
                              setState(() => _activeSelection = null);
                              _createAnnotationFromSelection(
                                sel.text,
                                colorHex,
                                sel.pageNumber,
                              );
                            }
                          },
                          onAddNote: () {
                            final sel = _activeSelection;
                            if (sel != null) {
                              setState(() => _activeSelection = null);
                              _showNoteDialogForSelection(sel.text, sel.pageNumber);
                            }
                          },
                          onDismiss: () {
                            setState(() => _activeSelection = null);
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPageCard({
    required BuildContext context,
    required MarkdownPageChunk chunk,
    required int index,
    required ThemeData theme,
    required bool isDark,
    required bool isSepia,
    required Color cardBg,
    required Color textColor,
    required Color codeBg,
    required double baseFontSize,
    required double cardMaxWidth,
  }) {
    final cardKey = _cardKeys.putIfAbsent(chunk.pageNumber, () => GlobalKey());

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cardMaxWidth),
        child: Container(
          key: cardKey,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : (isSepia ? const Color(0xFFE2D6BC) : const Color(0xFFE2E8F0)),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : (isSepia ? 0.05 : 0.04)),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Page Header Tab
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : (isSepia ? const Color(0xFFEFE4CC) : const Color(0xFFF8FAFC)),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : (isSepia ? const Color(0xFFE2D6BC) : const Color(0xFFE2E8F0)),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '第 ${chunk.pageNumber} 页',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${index + 1} / ${_chunks.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Markdown Content for this page with responsive SelectionArea
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                child: SelectionArea(
                  onSelectionChanged: (SelectedContent? content) {
                    final selText = content?.plainText.trim() ?? '';
                    if (selText.isNotEmpty) {
                      _pendingSelectionText = selText;
                      _pendingSelectionPage = chunk.pageNumber;
                    }
                  },
                  contextMenuBuilder: (context, selectableRegionState) =>
                      _buildMarkdownContextMenu(context, selectableRegionState, chunk.pageNumber),
                  child: MarkdownBody(
                    data: chunk.content,
                    selectable: false,
                    extensionSet: _latexExtensionSet,
                    builders: {
                      'latex': _LatexElementBuilder(
                        textColor: textColor,
                        baseFontSize: baseFontSize,
                        codeBg: codeBg,
                        isDark: isDark,
                      ),
                      'code': _LatexCodeElementBuilder(
                        textColor: textColor,
                        baseFontSize: baseFontSize,
                        codeBg: codeBg,
                        isDark: isDark,
                      ),
                      'mark': _MarkElementBuilder(
                        isDark: isDark,
                      ),
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: baseFontSize,
                        height: 1.7,
                        color: textColor,
                        letterSpacing: 0.2,
                      ),
                      h1: TextStyle(
                        fontSize: baseFontSize * 1.8,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.4,
                      ),
                      h2: TextStyle(
                        fontSize: baseFontSize * 1.5,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.4,
                      ),
                      h3: TextStyle(
                        fontSize: baseFontSize * 1.25,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.4,
                      ),
                      h4: TextStyle(
                        fontSize: baseFontSize * 1.1,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.4,
                      ),
                      code: TextStyle(
                        fontSize: baseFontSize * 0.9,
                        fontFamily: 'monospace',
                        backgroundColor: codeBg,
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: codeBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      codeblockPadding: const EdgeInsets.all(14),
                      blockquote: TextStyle(
                        fontSize: baseFontSize * 0.95,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: codeBg.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border(
                          left: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 4,
                          ),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      tableBody: TextStyle(fontSize: baseFontSize * 0.95, color: textColor),
                      tableHead: TextStyle(fontSize: baseFontSize * 0.95, fontWeight: FontWeight.bold, color: textColor),
                      tableBorder: TableBorder.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        width: 1,
                      ),
                      tableCellsPadding: const EdgeInsets.all(8),
                      listBullet: TextStyle(fontSize: baseFontSize, color: theme.colorScheme.primary),
                      horizontalRuleDecoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                        ),
                      ),
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

/// Matches inline math like `$E=mc^2$`
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax() : super(r'(?<!\\)\$(?!\$)((?:\\.|[^\$])+?)(?<!\\)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = match.group(1);
    if (formula == null || formula.trim().isEmpty) return false;
    final el = md.Element.text('latex', formula.trim());
    el.attributes['display'] = 'false';
    parser.addNode(el);
    return true;
  }
}

/// Matches display math blocks like `$$\sum_{i=1}^n x_i$$`
class LatexBlockInlineSyntax extends md.InlineSyntax {
  LatexBlockInlineSyntax() : super(r'(?<!\\)\$\$((?:\\.|[\s\S])+?)(?<!\\)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = match.group(1);
    if (formula == null || formula.trim().isEmpty) return false;
    final el = md.Element.text('latex', formula.trim());
    el.attributes['display'] = 'true';
    parser.addNode(el);
    return true;
  }
}

/// Matches inline LaTeX formulas written as `\(...\)`
class LatexParenInlineSyntax extends md.InlineSyntax {
  LatexParenInlineSyntax() : super(r'\\\(((?:\\.|[\s\S])+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = match.group(1);
    if (formula == null || formula.trim().isEmpty) return false;
    final el = md.Element.text('latex', formula.trim());
    el.attributes['display'] = 'false';
    parser.addNode(el);
    return true;
  }
}

/// Matches display LaTeX formulas written as `\[...\]`
class LatexBracketInlineSyntax extends md.InlineSyntax {
  LatexBracketInlineSyntax() : super(r'\\\[((?:\\.|[\s\S])+?)\\\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = match.group(1);
    if (formula == null || formula.trim().isEmpty) return false;
    final el = md.Element.text('latex', formula.trim());
    el.attributes['display'] = 'true';
    parser.addNode(el);
    return true;
  }
}

/// Renders LaTeX tags into mathematical typography with flutter_math_fork
class _LatexElementBuilder extends MarkdownElementBuilder {
  final Color textColor;
  final double baseFontSize;
  final Color codeBg;
  final bool isDark;

  _LatexElementBuilder({
    required this.textColor,
    required this.baseFontSize,
    required this.codeBg,
    required this.isDark,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent.trim();
    if (text.isEmpty) return null;

    final isDisplay = element.attributes['display'] == 'true';

    try {
      if (isDisplay) {
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                text,
                mathStyle: MathStyle.display,
                textStyle: TextStyle(
                  color: textColor,
                  fontSize: baseFontSize * 1.1,
                ),
                onErrorFallback: (err) {
                  return Text(
                    text,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: textColor,
                      fontSize: baseFontSize * 0.9,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      } else {
        return Math.tex(
          text,
          mathStyle: MathStyle.text,
          textStyle: TextStyle(
            color: textColor,
            fontSize: baseFontSize * 1.02,
          ),
          onErrorFallback: (err) {
            return Text(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                color: textColor,
                fontSize: baseFontSize * 0.9,
              ),
            );
          },
        );
      }
    } catch (_) {
      return Text(text, style: preferredStyle);
    }
  }
}

/// Automatically handles ```latex or ```math fenced code blocks and renders as math
class _LatexCodeElementBuilder extends MarkdownElementBuilder {
  final Color textColor;
  final double baseFontSize;
  final Color codeBg;
  final bool isDark;

  _LatexCodeElementBuilder({
    required this.textColor,
    required this.baseFontSize,
    required this.codeBg,
    required this.isDark,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final className = element.attributes['class'] ?? '';
    final isLatex = className.contains('language-latex') ||
        className.contains('language-tex') ||
        className.contains('language-math');

    final text = element.textContent.trim();
    if (isLatex && text.isNotEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: codeBg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              text,
              mathStyle: MathStyle.display,
              textStyle: TextStyle(
                color: textColor,
                fontSize: baseFontSize * 1.1,
              ),
              onErrorFallback: (err) {
                return Text(
                  text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: textColor,
                    fontSize: baseFontSize * 0.9,
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return null;
  }
}

/// Matches standard & extended Markdown highlight syntax:
/// `==text==` (default yellow) or `==[#HEX]text==` (custom color hex)
class MarkdownHighlightInlineSyntax extends md.InlineSyntax {
  MarkdownHighlightInlineSyntax()
      : super(r'==(?:\[(#[0-9a-fA-F]{3,8})\])?((?:(?!==)[\s\S])+?)==');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final colorHex = match.group(1);
    final text = match.group(2);
    if (text == null || text.trim().isEmpty) return false;

    final el = md.Element('mark', [md.Text(text)]);
    if (colorHex != null && colorHex.isNotEmpty) {
      el.attributes['color'] = colorHex;
    }
    parser.addNode(el);
    return true;
  }
}

/// Matches HTML `<mark data-color="#HEX">text</mark>` or `<mark>text</mark>`
class HtmlMarkInlineSyntax extends md.InlineSyntax {
  HtmlMarkInlineSyntax()
      : super(
          r"""<mark(?:\s+data-color=["'](#[0-9a-fA-F]{3,8})["'])?(?:\s+style=["'][^"']*["'])*>((?:(?!</mark>)[\s\S])+?)</mark>""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final colorHex = match.group(1);
    final text = match.group(2);
    if (text == null || text.trim().isEmpty) return false;

    final el = md.Element('mark', [md.Text(text)]);
    if (colorHex != null && colorHex.isNotEmpty) {
      el.attributes['color'] = colorHex;
    }
    parser.addNode(el);
    return true;
  }
}

/// Renders `<mark>` elements as vibrant fluorescent highlights with rounded background & accent underline
class _MarkElementBuilder extends MarkdownElementBuilder {
  final bool isDark;

  _MarkElementBuilder({
    required this.isDark,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (text.isEmpty) return null;

    final colorHex = element.attributes['color'] ?? '#FDE047';
    Color baseColor;
    try {
      baseColor = AppTheme.parseHexColor(colorHex);
    } catch (_) {
      baseColor = const Color(0xFFFDE047);
    }

    final highlightBg = baseColor.withValues(alpha: isDark ? 0.40 : 0.35);
    final borderCol = baseColor.withValues(alpha: isDark ? 0.85 : 0.75);
    final textCol = preferredStyle?.color ?? (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: highlightBg,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          bottom: BorderSide(
            color: borderCol,
            width: 2.2,
          ),
        ),
      ),
      child: Text(
        text,
        style: (preferredStyle ?? const TextStyle()).copyWith(
          color: textCol,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
