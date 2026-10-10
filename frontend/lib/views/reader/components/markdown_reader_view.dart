import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../models/annotation_model.dart';
import '../../../models/document_model.dart';
import '../../../providers/annotation_provider.dart';
import '../../../providers/document_provider.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../services/cache/doc_cache_service.dart';
import '../../../theme/app_theme.dart';
import 'floating_selection_bar.dart';
import 'knowledge_card_dialog.dart';
import 'latex_interactive_view.dart';
import 'markdown_html_support.dart';
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
  final void Function(String text, int pageNumber)? onAskAi;

  const MarkdownReaderView({
    super.key,
    required this.document,
    required this.markdownContent,
    this.currentPage = 1,
    this.onPageChanged,
    required this.onOpenOcr,
    this.onMarkdownUpdated,
    this.onAskAi,
  });

  @override
  State<MarkdownReaderView> createState() => MarkdownReaderViewState();
}

class MarkdownReaderViewState extends State<MarkdownReaderView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _cardKeys = {};
  final Uuid _uuid = const Uuid();

  List<MarkdownPageChunk> _chunks = [];
  List<MarkdownHeadingItem> _headings = [];
  final Map<int, double> _pageHeights = {};
  final double _estimatedAverageHeight = 1000.0;

  // Active text selection state for floating menu
  MarkdownActiveSelection? _activeSelection;
  String _pendingSelectionText = '';
  int _pendingSelectionPage = 1;
  bool _isProgrammaticScrolling = false;
  int? _lastReportedPage;
  bool _hasExplicitPageMarkers = false;

  // Custom Markdown extension set supporting LaTeX formulas, Highlights, and HTML tags
  static final md.ExtensionSet _latexExtensionSet = md.ExtensionSet(
    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    <md.InlineSyntax>[
      LatexBlockInlineSyntax(),
      LatexBracketInlineSyntax(),
      LatexInlineSyntax(),
      LatexParenInlineSyntax(),
      AnnotationBadgeInlineSyntax(),
      MarkdownHighlightInlineSyntax(),
      HtmlMarkInlineSyntax(),
      HtmlUnderlineSyntax(),
      HtmlSubscriptSyntax(),
      HtmlSuperscriptSyntax(),
      HtmlStrikeSyntax(),
      HtmlBoldSyntax(),
      HtmlItalicSyntax(),
      HtmlFontSyntax(),
      HtmlSpanSyntax(),
      HtmlKbdSyntax(),
      HtmlSmallBigSyntax(),
      HtmlRubySyntax(),
      HtmlAbbrSyntax(),
      HtmlBreakSyntax(),
      HtmlCenterSyntax(),
      HtmlDetailsSyntax(),
      HtmlTableSyntax(),
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
    super.dispose();
  }

  void _processMarkdown(String rawMarkdown) {
    final preprocessed = preprocessMarkdownHtml(rawMarkdown);
    _chunks = _parseMarkdownChunks(preprocessed);
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
    bool? isMobile,
  }) {
    final bool mobile = isMobile ?? (containerSize.width < 700);
    final double menuWidth = mobile ? 248.0 : 380.0;
    final double menuHeight = mobile ? 78.0 : 48.0;

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

    final List<MarkdownPageChunk> rawChunks = [];

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
          rawChunks.add(MarkdownPageChunk(
            pageNumber: pageNum,
            content: content,
          ));
        }
      }
    } else {
      _hasExplicitPageMarkers = false;
    }

    if (rawChunks.isEmpty && rawMarkdown.trim().isNotEmpty) {
      rawChunks.add(MarkdownPageChunk(
        pageNumber: 1,
        content: rawMarkdown.trim(),
      ));
    }

    // Subdivide oversized chunks (> 80 lines) into natural page chunks honoring headers
    final List<MarkdownPageChunk> finalChunks = [];

    for (int cIdx = 0; cIdx < rawChunks.length; cIdx++) {
      final chunk = rawChunks[cIdx];
      final lines = chunk.content.split('\n');

      if (lines.length <= 80) {
        finalChunks.add(chunk);
        continue;
      }

      final List<String> currentLines = [];
      int subPage = chunk.pageNumber;
      bool inCodeBlock = false;
      bool inMathBlock = false;

      for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final line = lines[lineIdx];
        final trimmed = line.trim();

        if (trimmed.startsWith('```')) {
          inCodeBlock = !inCodeBlock;
        } else if (trimmed.startsWith(r'$$') && !trimmed.endsWith(r'$$') && trimmed.length > 2) {
          inMathBlock = !inMathBlock;
        } else if (trimmed == r'$$') {
          inMathBlock = !inMathBlock;
        }

        currentLines.add(line);

        if (!inCodeBlock && !inMathBlock) {
          final count = currentLines.length;
          final nextLine = (lineIdx + 1 < lines.length) ? lines[lineIdx + 1].trim() : '';

          bool shouldSplit = false;
          if (count >= 30 && nextLine.startsWith('# ')) {
            shouldSplit = true;
          } else if (count >= 45 && nextLine.startsWith('## ')) {
            shouldSplit = true;
          } else if (count >= 60 && nextLine.startsWith('### ')) {
            shouldSplit = true;
          } else if (count >= 80) {
            shouldSplit = true;
          }

          if (shouldSplit) {
            final text = currentLines.join('\n').trim();
            if (text.isNotEmpty) {
              finalChunks.add(MarkdownPageChunk(
                pageNumber: subPage++,
                content: text,
              ));
              currentLines.clear();
            }
          }
        }
      }

      if (currentLines.isNotEmpty) {
        final text = currentLines.join('\n').trim();
        if (text.isNotEmpty) {
          finalChunks.add(MarkdownPageChunk(
            pageNumber: subPage,
            content: text,
          ));
        }
      }
    }

    return finalChunks;
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

    // 1. Resolve targetIndex even when pages are skipped or merged across tables
    int targetIndex = _chunks.indexWhere((c) => c.pageNumber == pageNumber);
    if (targetIndex == -1) {
      // Find chunk with highest pageNumber <= requested pageNumber
      for (int i = _chunks.length - 1; i >= 0; i--) {
        if (_chunks[i].pageNumber <= pageNumber) {
          targetIndex = i;
          break;
        }
      }
    }
    if (targetIndex == -1) {
      targetIndex = 0;
    }

    final targetChunk = _chunks[targetIndex];
    final actualPageNumber = targetChunk.pageNumber;

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
      final key = _cardKeys[actualPageNumber];
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      attemptScroll(10);
    });
  }

  void _createHighlightFromSelection(
    String selectedText,
    String colorHex,
    int pageNumber,
  ) async {
    if (selectedText.trim().isEmpty) return;

    final trimmedText = selectedText.trim();
    final docProvider = context.read<DocumentProvider>();
    final annoProvider = context.read<AnnotationProvider>();

    // 1. Update chunks by applying segmented line-by-line highlight
    bool anyChunkModified = false;
    String? matchedMarkdownText;

    int chunkIdx = _chunks.indexWhere((c) => c.pageNumber == pageNumber);
    if (chunkIdx != -1) {
      final oldChunk = _chunks[chunkIdx];
      final res = applyHighlightToMarkdownWithResult(oldChunk.content, selectedText, colorHex);
      if (res.isModified) {
        _chunks[chunkIdx] = MarkdownPageChunk(
          pageNumber: oldChunk.pageNumber,
          content: res.content,
        );
        matchedMarkdownText = res.matchedText;
        anyChunkModified = true;
      }
    }

    // If targeted chunk was not modified or selection spans other chunks, search across all chunks
    if (!anyChunkModified) {
      for (int i = 0; i < _chunks.length; i++) {
        final chunk = _chunks[i];
        final res = applyHighlightToMarkdownWithResult(chunk.content, selectedText, colorHex);
        if (res.isModified) {
          _chunks[i] = MarkdownPageChunk(
            pageNumber: chunk.pageNumber,
            content: res.content,
          );
          matchedMarkdownText ??= res.matchedText;
          anyChunkModified = true;
        }
      }
    }

    if (anyChunkModified) {
      final combinedMd = _recombineChunks(_chunks);
      widget.onMarkdownUpdated?.call(combinedMd);

      try {
        await docProvider.saveMarkdown(widget.document.id, combinedMd);
      } catch (e) {
        debugPrint('Error saving markdown: $e');
      }
      if (mounted) setState(() {});
    }

    // 2. Create annotation record with empty rects (prevents drawing full-page box on PDF canvas)
    final newAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "highlight",
      pageNumber: pageNumber,
      colorHex: colorHex,
      rects: const [],
      selectedText: (matchedMarkdownText != null && matchedMarkdownText.trim().isNotEmpty)
          ? matchedMarkdownText.trim()
          : trimmedText,
      noteContent: "",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await annoProvider.addAnnotation(newAnno);
    if (mounted) {
      docProvider.updateAnnotationCount(widget.document.id, 1);
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
                  '已添加第 $pageNumber 页荧光划词高亮',
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

  void _createNoteFromSelection(
    String selectedText,
    int pageNumber,
    String noteContent,
  ) async {
    if (selectedText.trim().isEmpty || noteContent.trim().isEmpty) return;

    final trimmedText = selectedText.trim();
    final annoProvider = context.read<AnnotationProvider>();
    final docProvider = context.read<DocumentProvider>();

    final newAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "note",
      pageNumber: pageNumber,
      colorHex: "#6366F1",
      rects: const [],
      selectedText: trimmedText,
      noteContent: noteContent.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await annoProvider.addAnnotation(newAnno);
    if (mounted) {
      docProvider.updateAnnotationCount(widget.document.id, 1);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Color(0xFF818CF8), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '已添加第 $pageNumber 页批注笔记',
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
      colorHex: "#6366F1",
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
          _createNoteFromSelection(
            selectedText,
            pageNumber,
            saved.noteContent,
          );
        },
        onDelete: () {},
      ),
    );
  }

  void _openCardDialog(PdfAnnotation card) {
    showDialog(
      context: context,
      builder: (_) => KnowledgeCardDialog(
        annotation: card,
        pageNumber: card.pageNumber,
        docId: widget.document.id,
        onSave: (updated) {
          context.read<AnnotationProvider>().updateAnnotationModel(updated);
        },
        onDelete: () {
          context.read<AnnotationProvider>().deleteAnnotation(card.id);
          context.read<DocumentProvider>().updateAnnotationCount(widget.document.id, -1);
        },
        onJumpToPage: (p) => jumpToPage(p),
      ),
    );
  }

  void _openNoteDialog(PdfAnnotation note) {
    showDialog(
      context: context,
      builder: (_) => NoteEditorDialog(
        annotation: note,
        onSave: (updated) {
          context.read<AnnotationProvider>().updateAnnotationModel(updated);
        },
        onDelete: () {
          context.read<AnnotationProvider>().deleteAnnotation(note.id);
          context.read<DocumentProvider>().updateAnnotationCount(widget.document.id, -1);
        },
      ),
    );
  }

  void _handleHighlightLatex(
    String rawLatex,
    String colorHex, {
    required bool isDisplay,
    required int pageNumber,
  }) async {
    final trimmedLatex = rawLatex.trim();
    if (trimmedLatex.isEmpty) return;

    final normalizedHex = colorHex.toUpperCase();
    final tagPrefix = (normalizedHex == '#FDE047' || normalizedHex == 'FDE047')
        ? '=='
        : '==[$normalizedHex]';

    final docProvider = context.read<DocumentProvider>();
    final annoProvider = context.read<AnnotationProvider>();

    int chunkIdx = _chunks.indexWhere((c) => c.pageNumber == pageNumber);
    if (chunkIdx == -1 && _chunks.isNotEmpty) {
      chunkIdx = 0;
    }

    if (chunkIdx != -1) {
      final oldChunk = _chunks[chunkIdx];
      String content = oldChunk.content;
      bool modified = false;

      final escaped = RegExp.escape(trimmedLatex);

      // 1. Check if formula is already highlighted:
      final alreadyHighlightedRegex = RegExp(
        r'==(?:\[#[0-9a-fA-F]{3,8}\])?\s*(\$\$|\$|\\\[|\\\(|```(?:latex|math|tex)\s*\n?)\s*' +
            escaped +
            r'\s*(\$\$|\$|\\\]|\\\)|\n?```)\s*==',
      );

      if (alreadyHighlightedRegex.hasMatch(content)) {
        content = content.replaceAllMapped(alreadyHighlightedRegex, (m) {
          final openDelim = m.group(1) ?? (isDisplay ? r'$$' : r'$');
          final closeDelim = m.group(2) ?? (isDisplay ? r'$$' : r'$');
          return '$tagPrefix$openDelim$trimmedLatex$closeDelim==';
        });
        modified = true;
      } else {
        // 2. Plain formula matching
        final plainRegex = RegExp(
          r'(\$\$|\$|\\\[|\\\(|```(?:latex|math|tex)\s*\n?)\s*' +
              escaped +
              r'\s*(\$\$|\$|\\\]|\\\)|\n?```)',
        );

        if (plainRegex.hasMatch(content)) {
          content = content.replaceFirstMapped(plainRegex, (m) {
            final openDelim = m.group(1) ?? (isDisplay ? r'$$' : r'$');
            final closeDelim = m.group(2) ?? (isDisplay ? r'$$' : r'$');
            return '$tagPrefix$openDelim$trimmedLatex$closeDelim==';
          });
          modified = true;
        } else if (content.contains(trimmedLatex)) {
          content = content.replaceFirst(trimmedLatex, '$tagPrefix$trimmedLatex==');
          modified = true;
        }
      }

      if (modified) {
        _chunks[chunkIdx] = MarkdownPageChunk(
          pageNumber: oldChunk.pageNumber,
          content: content,
        );

        final combinedMd = _recombineChunks(_chunks);
        widget.onMarkdownUpdated?.call(combinedMd);

        try {
          await docProvider.saveMarkdown(widget.document.id, combinedMd);
        } catch (e) {
          debugPrint('Error saving markdown: $e');
        }
        if (mounted) setState(() {});
      }
    }

    final newAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "highlight",
      pageNumber: pageNumber,
      colorHex: colorHex,
      rects: const [],
      selectedText: isDisplay ? '\$\$$trimmedLatex\$\$' : '\$$trimmedLatex\$',
      noteContent: "",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await annoProvider.addAnnotation(newAnno);
    if (mounted) {
      docProvider.updateAnnotationCount(widget.document.id, 1);
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
                child: Text('已高亮第 $pageNumber 页 LaTeX 公式: ${isDisplay ? "\$\$$trimmedLatex\$\$" : "\$$trimmedLatex\$"}'),
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

  void _handleRemoveHighlightLatex(
    String rawLatex, {
    required bool isDisplay,
    required int pageNumber,
  }) async {
    final trimmedLatex = rawLatex.trim();
    if (trimmedLatex.isEmpty) return;

    final docProvider = context.read<DocumentProvider>();
    final annoProvider = context.read<AnnotationProvider>();

    // Also remove the corresponding PdfAnnotation from annoProvider
    final formulaText = isDisplay ? '\$\$$trimmedLatex\$\$' : '\$$trimmedLatex\$';
    var matchingAnno = annoProvider.annotations.cast<PdfAnnotation?>().firstWhere(
      (a) => a?.docId == widget.document.id &&
             (a?.selectedText.trim() == formulaText || a?.selectedText.trim() == trimmedLatex),
      orElse: () => null,
    );
    matchingAnno ??= annoProvider.annotations.cast<PdfAnnotation?>().firstWhere(
      (a) => a?.docId == widget.document.id &&
             (a?.selectedText.contains(formulaText) == true || a?.selectedText.contains(trimmedLatex) == true),
      orElse: () => null,
    );
    if (matchingAnno != null) {
      await annoProvider.deleteAnnotation(matchingAnno.id);
      docProvider.updateAnnotationCount(widget.document.id, -1);
    }

    int chunkIdx = _chunks.indexWhere((c) => c.pageNumber == pageNumber);
    if (chunkIdx == -1 && _chunks.isNotEmpty) {
      chunkIdx = 0;
    }

    if (chunkIdx != -1) {
      final oldChunk = _chunks[chunkIdx];
      String content = oldChunk.content;
      bool modified = false;

      // If matchingAnno was part of a compound selection, clean up all segments from markdown
      if (matchingAnno != null && matchingAnno.selectedText.trim().isNotEmpty) {
        final compoundClean = removeHighlightFromMarkdown(content, matchingAnno.selectedText);
        if (compoundClean != content) {
          content = compoundClean;
          modified = true;
        }
      }

      final escaped = RegExp.escape(trimmedLatex);
      final highlightedRegex = RegExp(
        r'==(?:\[#[0-9a-fA-F]{3,8}\])?\s*(\$\$|\$|\\\[|\\\(|```(?:latex|math|tex)\s*\n?)\s*' +
            escaped +
            r'\s*(\$\$|\$|\\\]|\\\)|\n?```)\s*==',
      );

      if (highlightedRegex.hasMatch(content)) {
        content = content.replaceAllMapped(highlightedRegex, (m) {
          final openDelim = m.group(1) ?? (isDisplay ? r'$$' : r'$');
          final closeDelim = m.group(2) ?? (isDisplay ? r'$$' : r'$');
          return '$openDelim$trimmedLatex$closeDelim';
        });
        modified = true;
      }

      if (modified) {
        _chunks[chunkIdx] = MarkdownPageChunk(
          pageNumber: oldChunk.pageNumber,
          content: content,
        );

        final combinedMd = _recombineChunks(_chunks);
        widget.onMarkdownUpdated?.call(combinedMd);

        try {
          await docProvider.saveMarkdown(widget.document.id, combinedMd);
        } catch (e) {
          debugPrint('Error saving markdown: $e');
        }
        if (mounted) setState(() {});
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已清除公式荧光高亮'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleAddNoteForLatex(
    String rawLatex, {
    required bool isDisplay,
    required int pageNumber,
  }) {
    final trimmedLatex = rawLatex.trim();
    final formulaText = isDisplay ? '\$\$$trimmedLatex\$\$' : '\$$trimmedLatex\$';
    _showNoteDialogForSelection(formulaText, pageNumber);
  }



  Widget _buildMarkdownContextMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
    int pageNumber,
  ) {
    // Suppress native selection context menu to prevent duplicate floating bars;
    // Selection floating bar is unified and managed exclusively by Stack's _activeSelection.
    return const SizedBox.shrink();
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 700;
    final cardMaxWidth = isMobile ? screenWidth : (880.0 * zoom).clamp(520.0, 1600.0);

    return Scaffold(
      backgroundColor: canvasBg,
      body: Stack(
        children: [
          // Virtualized Page List View with accurate Scroll Notification Listener
          _chunks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.menu_book_rounded,
                            size: 40,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '尚未生成结构化 Markdown 文档',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            '使用百度 PaddleOCR-VL 智能云端解析，可提取全文多级标题、段落排版、LaTeX 数学公式与 HTML 表格。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                          label: const Text('开始 OCR 智能解析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: widget.onOpenOcr,
                        ),
                      ],
                    ),
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
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 24, vertical: isMobile ? 12 : 20),
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

          // Auto-Popup Floating Toolbar following cursor when text is selected in Markdown mode (Appears on pointer release)
          if (_activeSelection != null)
            LayoutBuilder(
              builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 700;
                  return Stack(
                    children: [
                      _buildPositionedFloatingBar(
                        context: context,
                        pointerPos: _activeSelection!.position,
                        containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                        isMobile: isMobile,
                        child: Material(
                          type: MaterialType.transparency,
                          child: FloatingSelectionBar(
                            selectedText: _activeSelection!.text,
                            readingMode: settings.readingMode,
                            isMobile: isMobile,
                            onHighlight: (colorHex) {
                            final sel = _activeSelection;
                            if (sel != null) {
                              setState(() => _activeSelection = null);
                              _createHighlightFromSelection(
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
                          onAskAi: () {
                            final sel = _activeSelection;
                            if (sel != null) {
                              setState(() => _activeSelection = null);
                              widget.onAskAi?.call(sel.text, sel.pageNumber);
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
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final annoProvider = context.watch<AnnotationProvider>();
    final allDocAnnos = annoProvider.annotations;

    // Collect all annotations that belong to this chunk or whose selectedText is in this chunk
    final chunkAnnos = <PdfAnnotation>[];
    final Set<String> seenIds = {};

    for (final a in allDocAnnos) {
      if (seenIds.contains(a.id)) continue;
      if (a.pageNumber == chunk.pageNumber) {
        chunkAnnos.add(a);
        seenIds.add(a.id);
      } else if ((a.isCard || a.isNote) && a.selectedText.trim().isNotEmpty) {
        final text = a.selectedText.trim();
        if (chunk.content.contains(text)) {
          chunkAnnos.add(a);
          seenIds.add(a.id);
        } else {
          final cleanFormula = text.replaceAll(RegExp(r'^(\$\$|\$)|(\$\$|\$)$'), '').trim();
          if (cleanFormula.isNotEmpty && chunk.content.contains(cleanFormula)) {
            chunkAnnos.add(a);
            seenIds.add(a.id);
          }
        }
      }
    }

    final cardAndNotes = chunkAnnos
        .where((a) => (a.isCard || a.isNote) && a.selectedText.trim().isNotEmpty)
        .toList();
    final pageCards = chunkAnnos.where((a) => a.isCard).toList();
    final pageNotes = chunkAnnos.where((a) => a.isNote).toList();
    final Map<String, PdfAnnotation> annosById = {for (final a in chunkAnnos) a.id: a};

    String displayContent = chunk.content;
    for (final a in cardAndNotes) {
      final sel = a.selectedText.trim();
      final badgeTag = ' <annobadge id="${a.id}" type="${a.isCard ? "card" : "note"}"></annobadge>';
      if (!displayContent.contains('id="${a.id}"') && !displayContent.contains("id='${a.id}'")) {
        if (displayContent.contains(sel)) {
          final hlPattern = RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?' + RegExp.escape(sel) + r'==');
          if (hlPattern.hasMatch(displayContent)) {
            displayContent = displayContent.replaceFirstMapped(hlPattern, (m) {
              return '${m.group(0)}$badgeTag';
            });
          } else {
            displayContent = displayContent.replaceFirst(sel, '$sel$badgeTag');
          }
        } else {
          // If formula delimiters are in selectedText or markdown:
          final cleanFormula = sel.replaceAll(RegExp(r'^(\$\$|\$)|(\$\$|\$)$'), '').trim();
          if (cleanFormula.isNotEmpty && displayContent.contains(cleanFormula)) {
            final fHlPattern = RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?[^=]*' + RegExp.escape(cleanFormula) + r'[^=]*==');
            if (fHlPattern.hasMatch(displayContent)) {
              displayContent = displayContent.replaceFirstMapped(fHlPattern, (m) {
                return '${m.group(0)}$badgeTag';
              });
            } else {
              displayContent = displayContent.replaceFirst(cleanFormula, '$cleanFormula$badgeTag');
            }
          }
        }
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cardMaxWidth),
        child: Container(
          key: cardKey,
          margin: EdgeInsets.only(bottom: isMobile ? 16 : 24),
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
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Page Header Tab
              Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : (isSepia ? const Color(0xFFEFE4CC) : const Color(0xFFF8FAFC)),
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
                        (index + 1 < _chunks.length && _chunks[index + 1].pageNumber > chunk.pageNumber + 1)
                            ? '第 ${chunk.pageNumber} - ${_chunks[index + 1].pageNumber - 1} 页'
                            : '第 ${chunk.pageNumber} 页',
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

              // Page Cards & Notes summary strip if present on this page
              if (pageCards.isNotEmpty || pageNotes.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.02)
                        : (isSepia ? const Color(0xFFF0E5CE) : const Color(0xFFF1F5F9)),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? const Color(0xFF334155)
                            : (isSepia ? const Color(0xFFE2D6BC) : const Color(0xFFE2E8F0)),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...pageCards.map((c) {
                        final cColor = AppTheme.parseHexColor(c.colorHex);
                        return Tooltip(
                          message: '知识卡片: ${c.displayTitle} (点击查看)',
                          child: InkWell(
                            onTap: () => _openCardDialog(c),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: cColor.withValues(alpha: isDark ? 0.25 : 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: cColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.style_rounded, size: 12, color: cColor),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 160),
                                    child: Text(
                                      c.displayTitle,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      ...pageNotes.map((n) {
                        final nColor = AppTheme.parseHexColor(n.colorHex);
                        return Tooltip(
                          message: '批注笔记: ${n.displayTitle} (点击查看)',
                          child: InkWell(
                            onTap: () => _openNoteDialog(n),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: nColor.withValues(alpha: isDark ? 0.25 : 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: nColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 13, color: nColor),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 160),
                                    child: Text(
                                      n.displayTitle,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: nColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              // Markdown Content for this page with responsive SelectionArea
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 28, vertical: isMobile ? 16 : 22),
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
                    data: displayContent,
                    selectable: false,
                    softLineBreak: true,
                    extensionSet: _latexExtensionSet,
                    sizedImageBuilder: (config) {
                      return _MarkdownImageWidget(
                        uri: config.uri,
                        title: config.title,
                        alt: config.alt,
                        docId: widget.document.id,
                        isDark: isDark,
                      );
                    },
                    builders: {
                      'annobadge': _AnnotationBadgeElementBuilder(
                        annotationsById: annosById,
                        isDark: isDark,
                        onOpenCard: _openCardDialog,
                        onOpenNote: _openNoteDialog,
                      ),
                      'latex': _LatexElementBuilder(
                        textColor: textColor,
                        baseFontSize: baseFontSize,
                        codeBg: codeBg,
                        isDark: isDark,
                        pageNumber: chunk.pageNumber,
                        onHighlight: _handleHighlightLatex,
                        onRemoveHighlight: _handleRemoveHighlightLatex,
                        onAddNote: _handleAddNoteForLatex,
                        onAskAi: (rawLatex, {required bool isDisplay, required int pageNumber}) {
                          final formulaText = isDisplay ? '\$\$$rawLatex\$\$' : '\$$rawLatex\$';
                          widget.onAskAi?.call(formulaText, pageNumber);
                        },
                      ),
                      'code': _LatexCodeElementBuilder(
                        textColor: textColor,
                        baseFontSize: baseFontSize,
                        codeBg: codeBg,
                        isDark: isDark,
                        pageNumber: chunk.pageNumber,
                        onHighlight: _handleHighlightLatex,
                        onRemoveHighlight: _handleRemoveHighlightLatex,
                        onAddNote: _handleAddNoteForLatex,
                        onAskAi: (rawLatex, {required bool isDisplay, required int pageNumber}) {
                          final formulaText = isDisplay ? '\$\$$rawLatex\$\$' : '\$$rawLatex\$';
                          widget.onAskAi?.call(formulaText, pageNumber);
                        },
                      ),
                      'mark': _MarkElementBuilder(
                        textColor: textColor,
                        baseFontSize: baseFontSize,
                        codeBg: codeBg,
                        isDark: isDark,
                        pageNumber: chunk.pageNumber,
                        annotationsById: annosById,
                        onOpenCard: _openCardDialog,
                        onOpenNote: _openNoteDialog,
                        onHighlight: _handleHighlightLatex,
                        onRemoveHighlight: _handleRemoveHighlightLatex,
                        onAddNote: _handleAddNoteForLatex,
                        onAskAi: (rawLatex, {required bool isDisplay, required int pageNumber}) {
                          final formulaText = isDisplay ? '\$\$$rawLatex\$\$' : '\$$rawLatex\$';
                          widget.onAskAi?.call(formulaText, pageNumber);
                        },
                      ),
                      'u': HtmlUnderlineElementBuilder(),
                      'sub': HtmlSubscriptElementBuilder(),
                      'sup': HtmlSuperscriptElementBuilder(),
                      'del': HtmlStrikeElementBuilder(),
                      'font': HtmlStyledSpanElementBuilder(isDark: isDark),
                      'span': HtmlStyledSpanElementBuilder(isDark: isDark),
                      'kbd': HtmlKbdElementBuilder(isDark: isDark),
                      'small': HtmlSizeElementBuilder(scale: 0.82),
                      'big': HtmlSizeElementBuilder(scale: 1.18),
                      'ruby': HtmlRubyElementBuilder(isDark: isDark),
                      'abbr': HtmlAbbrElementBuilder(),
                      'br': HtmlBreakElementBuilder(),
                      'center': HtmlCenterElementBuilder(),
                      'details': HtmlDetailsElementBuilder(isDark: isDark),
                      'html-table': HtmlTableElementBuilder(isDark: isDark),
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

/// Renders LaTeX tags into interactive mathematical typography
class _LatexElementBuilder extends MarkdownElementBuilder {
  final Color textColor;
  final double baseFontSize;
  final Color codeBg;
  final bool isDark;
  final int pageNumber;
  final void Function(String rawLatex, String colorHex, {required bool isDisplay, required int pageNumber})? onHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onRemoveHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAddNote;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAskAi;

  _LatexElementBuilder({
    required this.textColor,
    required this.baseFontSize,
    required this.codeBg,
    required this.isDark,
    required this.pageNumber,
    this.onHighlight,
    this.onRemoveHighlight,
    this.onAddNote,
    this.onAskAi,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent.trim();
    if (text.isEmpty) return null;

    final isDisplay = element.attributes['display'] == 'true';
    final highlightColor = element.attributes['highlightColor'];

    try {
      final latexView = InteractiveLatexView(
        rawLatex: text,
        isDisplay: isDisplay,
        textColor: textColor,
        baseFontSize: baseFontSize,
        codeBg: codeBg,
        isDark: isDark,
        highlightColor: highlightColor,
        pageNumber: pageNumber,
        onHighlight: onHighlight,
        onRemoveHighlight: onRemoveHighlight,
        onAddNote: onAddNote,
        onAskAi: onAskAi,
      );

      if (isDisplay) {
        return latexView;
      }

      return Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              baseline: TextBaseline.alphabetic,
              child: latexView,
            ),
          ],
        ),
      );
    } catch (_) {
      return Text(text, style: preferredStyle);
    }
  }
}

/// Automatically handles ```latex or ```math fenced code blocks and renders as interactive math block
class _LatexCodeElementBuilder extends MarkdownElementBuilder {
  final Color textColor;
  final double baseFontSize;
  final Color codeBg;
  final bool isDark;
  final int pageNumber;
  final void Function(String rawLatex, String colorHex, {required bool isDisplay, required int pageNumber})? onHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onRemoveHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAddNote;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAskAi;

  _LatexCodeElementBuilder({
    required this.textColor,
    required this.baseFontSize,
    required this.codeBg,
    required this.isDark,
    required this.pageNumber,
    this.onHighlight,
    this.onRemoveHighlight,
    this.onAddNote,
    this.onAskAi,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final className = element.attributes['class'] ?? '';
    final isLatex = className.contains('language-latex') ||
        className.contains('language-tex') ||
        className.contains('language-math');

    final text = element.textContent.trim();
    if (isLatex && text.isNotEmpty) {
      return LatexFencedBlockWidget(
        rawLatex: text,
        textColor: textColor,
        baseFontSize: baseFontSize,
        codeBg: codeBg,
        isDark: isDark,
        pageNumber: pageNumber,
        onHighlight: onHighlight,
        onRemoveHighlight: onRemoveHighlight,
        onAddNote: onAddNote,
        onAskAi: onAskAi,
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

    final children = md.InlineParser(text, parser.document).parse();
    final el = md.Element('mark', children);
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

    final children = md.InlineParser(text, parser.document).parse();
    final el = md.Element('mark', children);
    if (colorHex != null && colorHex.isNotEmpty) {
      el.attributes['color'] = colorHex;
    }
    parser.addNode(el);
    return true;
  }
}

/// Renders `<mark>` elements as vibrant fluorescent highlights with rounded background & accent underline
class _MarkElementBuilder extends MarkdownElementBuilder {
  final Color textColor;
  final double baseFontSize;
  final Color codeBg;
  final bool isDark;
  final int pageNumber;
  final Map<String, PdfAnnotation>? annotationsById;
  final void Function(PdfAnnotation anno)? onOpenCard;
  final void Function(PdfAnnotation anno)? onOpenNote;
  final void Function(String rawLatex, String colorHex, {required bool isDisplay, required int pageNumber})? onHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onRemoveHighlight;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAddNote;
  final void Function(String rawLatex, {required bool isDisplay, required int pageNumber})? onAskAi;

  _MarkElementBuilder({
    required this.textColor,
    required this.baseFontSize,
    required this.codeBg,
    required this.isDark,
    required this.pageNumber,
    this.annotationsById,
    this.onOpenCard,
    this.onOpenNote,
    this.onHighlight,
    this.onRemoveHighlight,
    this.onAddNote,
    this.onAskAi,
  });

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return _buildMark(element, preferredStyle, parentStyle);
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return _buildMark(element, preferredStyle, null);
  }

  Widget? _buildMark(md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final colorHex = element.attributes['color'] ?? '#FDE047';
    Color baseColor;
    try {
      baseColor = AppTheme.parseHexColor(colorHex);
    } catch (_) {
      baseColor = const Color(0xFFFDE047);
    }

    final highlightBg = baseColor.withValues(alpha: isDark ? 0.30 : 0.22);
    final borderCol = baseColor.withValues(alpha: isDark ? 0.75 : 0.60);

    // Merge styles: ensure heading font size & weight from parentStyle or preferredStyle are preserved
    final effectiveStyle = (parentStyle ?? const TextStyle()).merge(preferredStyle);
    final effectiveFontSize = preferredStyle?.fontSize ?? parentStyle?.fontSize ?? baseFontSize;
    final effectiveFontWeight = preferredStyle?.fontWeight ?? parentStyle?.fontWeight ?? FontWeight.w600;
    final textCol = preferredStyle?.color ?? parentStyle?.color ?? (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A));

    final finalTextStyle = effectiveStyle.copyWith(
      fontSize: effectiveFontSize,
      fontWeight: effectiveFontWeight,
      color: textCol,
      letterSpacing: 0.2,
    );

    // Check if the mark content is a fenced code block: ```latex ... ``` or ```math ... ``` or ```tex ... ```
    final fullText = element.textContent.trim();
    final fencedLatexMatch = RegExp(
      r'^```(?:latex|math|tex)?\s*\n?([\s\S]+?)\n?```$',
      caseSensitive: false,
    ).firstMatch(fullText);

    if (fencedLatexMatch != null) {
      final code = fencedLatexMatch.group(1)!.trim();
      return LatexFencedBlockWidget(
        rawLatex: code,
        textColor: textCol,
        baseFontSize: effectiveFontSize,
        codeBg: codeBg,
        isDark: isDark,
        highlightColor: colorHex,
        pageNumber: pageNumber,
        onHighlight: onHighlight,
        onRemoveHighlight: onRemoveHighlight,
        onAddNote: onAddNote,
        onAskAi: onAskAi,
      );
    }

    final childWidgets = <Widget>[];
    if (element.children != null && element.children!.isNotEmpty) {
      for (final childNode in element.children!) {
        if (childNode is md.Element && childNode.tag == 'latex') {
          final isDisplay = childNode.attributes['display'] == 'true';
          childWidgets.add(
            InteractiveLatexView(
              rawLatex: childNode.textContent.trim(),
              isDisplay: isDisplay,
              textColor: textCol,
              baseFontSize: effectiveFontSize,
              codeBg: codeBg,
              isDark: isDark,
              highlightColor: colorHex,
              pageNumber: pageNumber,
              onHighlight: onHighlight,
              onRemoveHighlight: onRemoveHighlight,
              onAddNote: onAddNote,
              onAskAi: onAskAi,
            ),
          );
        } else if (childNode is md.Element && childNode.tag == 'annobadge') {
          final id = childNode.attributes['id'] ?? '';
          final anno = annotationsById?[id];
          if (anno != null && onOpenCard != null && onOpenNote != null) {
            childWidgets.add(_AnnotationBadgeElementBuilder.buildBadgeWidget(
              anno: anno,
              isDark: isDark,
              onOpenCard: onOpenCard!,
              onOpenNote: onOpenNote!,
            ));
          }
        } else if (childNode is md.Text) {
          final text = childNode.text;
          final fenced = RegExp(
            r'^```(?:latex|math|tex)?\s*\n?([\s\S]+?)\n?```$',
            caseSensitive: false,
          ).firstMatch(text.trim());
          if (fenced != null) {
            childWidgets.add(
              LatexFencedBlockWidget(
                rawLatex: fenced.group(1)!.trim(),
                textColor: textCol,
                baseFontSize: effectiveFontSize,
                codeBg: codeBg,
                isDark: isDark,
                highlightColor: colorHex,
                pageNumber: pageNumber,
                onHighlight: onHighlight,
                onRemoveHighlight: onRemoveHighlight,
                onAddNote: onAddNote,
                onAskAi: onAskAi,
              ),
            );
          } else {
            childWidgets.add(
              Text(
                childNode.text,
                style: finalTextStyle,
              ),
            );
          }
        } else if (childNode is md.Element) {
          final text = childNode.textContent;
          final fenced = RegExp(
            r'^```(?:latex|math|tex)?\s*\n?([\s\S]+?)\n?```$',
            caseSensitive: false,
          ).firstMatch(text.trim());
          if (fenced != null) {
            childWidgets.add(
              LatexFencedBlockWidget(
                rawLatex: fenced.group(1)!.trim(),
                textColor: textCol,
                baseFontSize: effectiveFontSize,
                codeBg: codeBg,
                isDark: isDark,
                highlightColor: colorHex,
                pageNumber: pageNumber,
                onHighlight: onHighlight,
                onRemoveHighlight: onRemoveHighlight,
                onAddNote: onAddNote,
                onAskAi: onAskAi,
              ),
            );
          } else {
            childWidgets.add(
              Text(
                childNode.textContent,
                style: finalTextStyle,
              ),
            );
          }
        }
      }
    }

    if (childWidgets.length == 1) {
      final first = childWidgets.first;
      if (first is InteractiveLatexView) {
        if (first.isDisplay) {
          return first;
        }
        return Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                baseline: TextBaseline.alphabetic,
                child: first,
              ),
            ],
          ),
        );
      }
      if (first is LatexFencedBlockWidget) {
        return first;
      }
    }

    Widget contentWidget;
    if (childWidgets.length == 1) {
      contentWidget = childWidgets.first;
    } else if (childWidgets.length > 1) {
      contentWidget = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: childWidgets,
      );
    } else {
      final text = element.textContent;
      if (text.isEmpty) return null;
      contentWidget = Text(
        text,
        style: finalTextStyle,
      );
    }

    final container = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: highlightBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: borderCol,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: isDark ? 0.20 : 0.12),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: contentWidget,
    );

    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: container,
          ),
        ],
      ),
    );
  }
}

/// Inline Markdown syntax matching `<annobadge id="..." type="..." />` or `<annobadge ...></annobadge>`
class AnnotationBadgeInlineSyntax extends md.InlineSyntax {
  AnnotationBadgeInlineSyntax()
      : super(
          r"""<annobadge\b(?=[^>]*\bid=["']([^"']+)["'])(?=[^>]*\btype=["']([^"']+)["'])?[^>]*(?:/>|></annobadge>)""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final rawMatch = match.group(0) ?? '';
    final idMatch = RegExp(r"""id=["']([^"']+)["']""", caseSensitive: false).firstMatch(rawMatch);
    final typeMatch = RegExp(r"""type=["']([^"']+)["']""", caseSensitive: false).firstMatch(rawMatch);

    final id = idMatch?.group(1) ?? '';
    final type = typeMatch?.group(1) ?? '';

    if (id.isEmpty) return false;

    final el = md.Element('annobadge', []);
    el.attributes['id'] = id;
    el.attributes['type'] = type;
    parser.addNode(el);
    return true;
  }
}

/// Renders in-text interactive icon badges on the left of quoted sentences / formulas
class _AnnotationBadgeElementBuilder extends MarkdownElementBuilder {
  final Map<String, PdfAnnotation> annotationsById;
  final bool isDark;
  final void Function(PdfAnnotation anno) onOpenCard;
  final void Function(PdfAnnotation anno) onOpenNote;

  _AnnotationBadgeElementBuilder({
    required this.annotationsById,
    required this.isDark,
    required this.onOpenCard,
    required this.onOpenNote,
  });

  static Widget buildBadgeWidget({
    required PdfAnnotation anno,
    required bool isDark,
    required void Function(PdfAnnotation anno) onOpenCard,
    required void Function(PdfAnnotation anno) onOpenNote,
  }) {
    final isCard = anno.isCard;
    final color = AppTheme.parseHexColor(anno.colorHex);

    return Tooltip(
      message: isCard
          ? '知识卡片: ${anno.displayTitle} (点击查看/编辑)'
          : '批注笔记: ${anno.displayTitle} (点击查看/编辑)',
      child: InkWell(
        onTap: () {
          if (isCard) {
            onOpenCard(anno);
          } else {
            onOpenNote(anno);
          }
        },
        borderRadius: BorderRadius.circular(5),
        child: Container(
          margin: const EdgeInsets.only(left: 4, right: 2),
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.28 : 0.15),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.65 : 0.45),
              width: 1.0,
            ),
          ),
          child: Icon(
            isCard ? Icons.style_rounded : Icons.edit_note_rounded,
            size: 13,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final id = element.attributes['id'] ?? '';
    final anno = annotationsById[id];
    if (anno == null) return null;

    final badge = buildBadgeWidget(
      anno: anno,
      isDark: isDark,
      onOpenCard: onOpenCard,
      onOpenNote: onOpenNote,
    );

    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: badge,
          ),
        ],
      ),
    );
  }
}

class _MarkdownImageWidget extends StatefulWidget {
  final Uri uri;
  final String? title;
  final String? alt;
  final String docId;
  final bool isDark;

  const _MarkdownImageWidget({
    required this.uri,
    this.title,
    this.alt,
    required this.docId,
    required this.isDark,
  });

  @override
  State<_MarkdownImageWidget> createState() => _MarkdownImageWidgetState();
}

class _MarkdownImageWidgetState extends State<_MarkdownImageWidget> {
  Uint8List? _localBytes;
  bool _isLoading = true;
  bool _hasError = false;
  String? _networkUrl;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _MarkdownImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.docId != widget.docId) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final uriStr = widget.uri.toString();

      // 1. Data URL (Base64)
      if (uriStr.startsWith('data:image/')) {
        final commaIdx = uriStr.indexOf(',');
        if (commaIdx != -1) {
          final base64Str = uriStr.substring(commaIdx + 1);
          final bytes = base64Decode(base64Str);
          if (mounted) {
            setState(() {
              _localBytes = bytes;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // 2. Local cache check
      final rawPath = widget.uri.path;
      final fileName = rawPath.split('/').last.split(r'\').last;
      if (fileName.isNotEmpty && widget.docId.isNotEmpty) {
        final cachedBytes = await DocCacheService().getImage(widget.docId, fileName);
        if (cachedBytes != null && cachedBytes.isNotEmpty) {
          if (mounted) {
            setState(() {
              _localBytes = cachedBytes;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // 3. Network URL / Remote API URL
      if (widget.uri.scheme == 'http' || widget.uri.scheme == 'https') {
        _networkUrl = uriStr;
      } else {
        if (!mounted) return;
        final docProvider = context.read<DocumentProvider>();
        final baseUrl = docProvider.apiService.baseUrl;
        _networkUrl = '$baseUrl/api/documents/${widget.docId}/images/$fileName';
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _openImageViewer() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (dialogCtx) => _MarkdownImageViewerDialog(
        localBytes: _localBytes,
        networkUrl: _networkUrl,
        title: widget.title ?? widget.alt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final captionText = widget.title ?? widget.alt ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _openImageViewer,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 560,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isLoading)
                      Container(
                        height: 200,
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      )
                    else if (_hasError)
                      _buildErrorWidget(isDark)
                    else if (_localBytes != null)
                      Image.memory(
                        _localBytes!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _buildErrorWidget(isDark),
                      )
                    else if (_networkUrl != null)
                      Image.network(
                        _networkUrl!,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, _, _) => _buildErrorWidget(isDark),
                      )
                    else
                      _buildErrorWidget(isDark),

                    // Hover/tap subtle hint icon overlay
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.fullscreen_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (captionText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Text(
                captionText.trim(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorWidget(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 36,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
          ),
          const SizedBox(height: 10),
          Text(
            '图片加载失败 (${widget.uri.path.split('/').last})',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('重试', style: TextStyle(fontSize: 12)),
            onPressed: _loadImage,
          ),
        ],
      ),
    );
  }
}

class _MarkdownImageViewerDialog extends StatefulWidget {
  final Uint8List? localBytes;
  final String? networkUrl;
  final String? title;

  const _MarkdownImageViewerDialog({
    this.localBytes,
    this.networkUrl,
    this.title,
  });

  @override
  State<_MarkdownImageViewerDialog> createState() => _MarkdownImageViewerDialogState();
}

class _MarkdownImageViewerDialogState extends State<_MarkdownImageViewerDialog> {
  final TransformationController _transformController = TransformationController();

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Interactive Pan & Zoom viewer
          InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.5,
            maxScale: 6.0,
            boundaryMargin: const EdgeInsets.all(80),
            child: widget.localBytes != null
                ? Image.memory(
                    widget.localBytes!,
                    fit: BoxFit.contain,
                  )
                : widget.networkUrl != null
                    ? Image.network(
                        widget.networkUrl!,
                        fit: BoxFit.contain,
                      )
                    : const SizedBox.shrink(),
          ),

          // Top action bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  if (widget.title != null && widget.title!.isNotEmpty)
                    Expanded(
                      child: Text(
                        widget.title!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  IconButton(
                    tooltip: '重置缩放',
                    icon: const Icon(Icons.restart_alt_rounded, color: Colors.white),
                    onPressed: _resetZoom,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

