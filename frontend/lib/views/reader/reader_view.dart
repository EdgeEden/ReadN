import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/annotation_model.dart';
import '../../models/document_model.dart';
import '../../providers/ai_provider.dart';
import '../../providers/annotation_provider.dart';
import '../../providers/document_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../services/cache/doc_cache_service.dart';
import '../../theme/app_theme.dart';
import 'components/floating_selection_bar.dart';
import 'components/knowledge_card_dialog.dart';
import 'components/markdown_html_support.dart';
import 'components/markdown_reader_view.dart';
import 'components/note_editor_dialog.dart';
import 'components/ocr_dialog.dart';
import 'components/page_jump_dialog.dart';
import 'components/reader_bottom_bar.dart';
import 'components/reader_mobile_sheet.dart';
import 'components/reader_sidebar.dart';
import 'components/reader_top_bar.dart';

class PdfActiveSelectionState {
  final String text;
  final List<PdfPageTextRange> ranges;
  final Offset position;

  const PdfActiveSelectionState({
    required this.text,
    required this.ranges,
    required this.position,
  });
}

class ArbitraryPointMenuState {
  final int pageNumber;
  final NormalizedRect normalizedRect;
  final Offset position;
  final bool isTouch;

  const ArbitraryPointMenuState({
    required this.pageNumber,
    required this.normalizedRect,
    required this.position,
    this.isTouch = false,
  });
}

class PdfReaderScreen extends StatefulWidget {
  final DocumentModel document;

  const PdfReaderScreen({super.key, required this.document});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> with TickerProviderStateMixin {
  late PdfViewerController _pdfController;
  late DocumentModel _doc;
  int _currentPage = 1;
  late final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(1);
  Timer? _pageSaveDebounceTimer;
  int _totalPages = 0;
  Uint8List? _pdfBytes;
  Uri? _pdfUri;
  bool _useUriSource = false;
  bool _isLoadingPdf = true;
  double? _downloadProgress;
  int? _downloadReceived;
  int? _downloadTotal;
  String? _loadError;
  bool _isOcrBannerDismissed = false;
  OcrStatusInfo? _ocrStatusInfo;
  Timer? _ocrPollTimer;
  final Uuid _uuid = const Uuid();

  ReaderViewMode _viewMode = ReaderViewMode.pdf;
  bool _hasActivatedMarkdown = false;
  String? _markdownContent;
  bool _isLoadingMarkdown = false;
  String? _markdownError;
  final GlobalKey<MarkdownReaderViewState> _markdownKey = GlobalKey<MarkdownReaderViewState>();
  double _basePdfZoom = 1.0;
  PdfActiveSelectionState? _pdfActiveSelection;
  ArbitraryPointMenuState? _arbitraryMenuState;
  Offset _pointerDownGlobalPosition = Offset.zero;
  bool _wasSelectionActiveOnPointerDown = false;

  // Edge auto-scrolling state
  Ticker? _edgeScrollTicker;
  Duration _lastEdgeScrollElapsed = Duration.zero;
  Offset? _currentPointerLocalPosition;
  bool _isPointerDown = false;
  Size _currentViewerSize = Size.zero;

  // Stylus & Palm Rejection state
  bool _isStylusContacting = false;
  DateTime? _lastStylusContactTime;
  Matrix4? _stylusInteractionStartMatrix;
  PointerDeviceKind? _lastPointerDeviceKind;
  PointerDeviceKind? _currentInteractionDeviceKind;

  bool _isPalmRejectionActive(bool isStylusMode) {
    if (!isStylusMode) return false;
    if (_isStylusContacting) return true;
    if (_lastStylusContactTime != null) {
      return DateTime.now().difference(_lastStylusContactTime!).inMilliseconds < 500;
    }
    return false;
  }

  // Outline (TOC) & Search state
  List<OutlineItem> _outlineItems = [];
  bool _isOutlineLoading = false;
  String _searchQuery = '';
  List<SearchResultItem> _searchResults = [];
  bool _isSearching = false;
  bool _isImmersiveMode = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onPdfControllerUpdate);
    _doc = widget.document;
    if (_viewMode == ReaderViewMode.markdown) {
      _hasActivatedMarkdown = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnnotationProvider>().loadAnnotations(_doc.id);
      final lastPage = context.read<DocumentProvider>().storageService.getLastReadPage(_doc.id);
      if (lastPage > 1) {
        _currentPage = lastPage;
        _currentPageNotifier.value = lastPage;
      }
      _fetchPdfData();
      if (_doc.hasMarkdown) {
        _fetchMarkdownData();
      }

      if (_doc.ocrStatus == "processing") {
        _startPollingOcr();
      }
    });
  }

  @override
  void dispose() {
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    _stopEdgeScrollTicker();
    _pdfController.removeListener(_onPdfControllerUpdate);
    _ocrPollTimer?.cancel();
    _pageSaveDebounceTimer?.cancel();
    if (_currentPage >= 1) {
      try {
        context.read<DocumentProvider>().storageService.setLastReadPage(_doc.id, _currentPage);
      } catch (_) {}
    }
    _currentPageNotifier.dispose();
    super.dispose();
  }

  void _startEdgeScrollTicker() {
    if (_edgeScrollTicker != null && _edgeScrollTicker!.isActive) return;
    _lastEdgeScrollElapsed = Duration.zero;
    _edgeScrollTicker?.dispose();
    _edgeScrollTicker = createTicker(_onEdgeScrollTick);
    _edgeScrollTicker!.start();
  }

  void _stopEdgeScrollTicker() {
    _edgeScrollTicker?.stop();
    _edgeScrollTicker?.dispose();
    _edgeScrollTicker = null;
    _lastEdgeScrollElapsed = Duration.zero;
  }

  void _checkAndTriggerEdgeScroll(Offset localPos, Size viewerSize) {
    if (!_pdfController.isReady || viewerSize.width <= 0 || viewerSize.height <= 0) return;
    const double edgeMarginY = 80.0;
    const double edgeMarginX = 60.0;
    final bool nearEdge = localPos.dy < edgeMarginY ||
        localPos.dy > viewerSize.height - edgeMarginY ||
        localPos.dx < edgeMarginX ||
        localPos.dx > viewerSize.width - edgeMarginX;

    if (nearEdge) {
      _startEdgeScrollTicker();
    }
  }

  void _onEdgeScrollTick(Duration elapsed) {
    if (!_isPointerDown || !mounted || !_pdfController.isReady) {
      _stopEdgeScrollTicker();
      return;
    }
    final localPos = _currentPointerLocalPosition;
    final viewerSize = _currentViewerSize;
    if (localPos == null || viewerSize.width <= 0 || viewerSize.height <= 0) return;

    const double edgeMarginY = 80.0;
    const double edgeMarginX = 60.0;

    double vy = 0.0;
    if (localPos.dy < edgeMarginY) {
      final ratio = ((edgeMarginY - localPos.dy) / edgeMarginY).clamp(0.0, 1.5);
      vy = 300.0 + 600.0 * ratio; // scroll up (content moves down)
    } else if (localPos.dy > viewerSize.height - edgeMarginY) {
      final ratio = ((localPos.dy - (viewerSize.height - edgeMarginY)) / edgeMarginY).clamp(0.0, 1.5);
      vy = -(300.0 + 600.0 * ratio); // scroll down (content moves up)
    }

    double vx = 0.0;
    if (localPos.dx < edgeMarginX) {
      final ratio = ((edgeMarginX - localPos.dx) / edgeMarginX).clamp(0.0, 1.5);
      vx = 300.0 + 600.0 * ratio; // scroll left (content moves right)
    } else if (localPos.dx > viewerSize.width - edgeMarginX) {
      final ratio = ((localPos.dx - (viewerSize.width - edgeMarginX)) / edgeMarginX).clamp(0.0, 1.5);
      vx = -(300.0 + 600.0 * ratio); // scroll right (content moves left)
    }

    if (vx == 0.0 && vy == 0.0) {
      _lastEdgeScrollElapsed = elapsed;
      return;
    }

    final double dt = _lastEdgeScrollElapsed == Duration.zero
        ? 0.016
        : ((elapsed - _lastEdgeScrollElapsed).inMicroseconds / 1000000.0).clamp(0.005, 0.05);
    _lastEdgeScrollElapsed = elapsed;

    final double stepX = vx * dt;
    final double stepY = vy * dt;

    final m = _pdfController.value.clone();
    m.storage[12] += stepX;
    m.storage[13] += stepY;
    final clamped = _pdfController.calcMatrixForClampedToNearestBoundary(m, viewSize: viewerSize);
    _pdfController.value = clamped;

    if (_stylusInteractionStartMatrix != null) {
      _stylusInteractionStartMatrix = clamped.clone();
    }
  }

  void _onPdfControllerUpdate() {
    if (!mounted || _viewMode != ReaderViewMode.pdf || !_pdfController.isReady) return;
    if (_edgeScrollTicker != null && _edgeScrollTicker!.isActive) return;
    final settings = context.read<ReaderSettingsProvider>();
    if (settings.isStylusMode &&
        (_currentInteractionDeviceKind == PointerDeviceKind.stylus ||
            _isStylusContacting ||
            _isPalmRejectionActive(true))) {
      if (_stylusInteractionStartMatrix != null) {
        _pdfController.stopInteractiveViewerAnimation();
        _pdfController.value = _stylusInteractionStartMatrix!;
        return;
      }
    }
    if (_basePdfZoom > 0) {
      final ratio = _pdfController.currentZoom / _basePdfZoom;
      if ((ratio - settings.zoomScale).abs() > 0.05) {
        settings.setZoomScale(ratio);
      }
    }
  }

  void _startPollingOcr() {
    _ocrPollTimer?.cancel();
    _ocrPollTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final res = await context.read<DocumentProvider>().checkOcrProgress(_doc.id);
      final statusInfo = OcrStatusInfo.fromJson(res);
      if (!mounted) return;

      setState(() {
        _ocrStatusInfo = statusInfo;
        if (statusInfo.isCompleted || statusInfo.status == "completed") {
          _doc = _doc.copyWith(hasMarkdown: true, ocrStatus: "completed");
        }
      });

      if (statusInfo.isCompleted) {
        timer.cancel();
        if (!mounted) return;
        final updatedDoc = await context.read<DocumentProvider>().apiService.getDocument(_doc.id);
        if (mounted) {
          setState(() {
            _doc = updatedDoc;
          });
          await _fetchMarkdownData(forceReload: true);
        }
      } else if (statusInfo.isFailed) {
        timer.cancel();
      }
    });
  }


  Future<void> _fetchMarkdownData({bool forceReload = false}) async {
    if (!forceReload && _markdownContent != null && _markdownContent!.isNotEmpty) return;

    final docProvider = context.read<DocumentProvider>();
    final docCache = docProvider.docCacheService;

    // 1. Cache-first check
    if (!forceReload) {
      final cachedMd = await docCache.getMarkdown(_doc.id);
      if (cachedMd != null && cachedMd.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _markdownContent = cachedMd;
            _isLoadingMarkdown = false;
            _doc = _doc.copyWith(hasMarkdown: true);
          });
          if (_outlineItems.isEmpty) {
            _loadOutline();
          }
        }
      }
    }

    if (_markdownContent == null || _markdownContent!.trim().isEmpty) {
      setState(() {
        _isLoadingMarkdown = true;
        _markdownError = null;
      });
    }

    // 2. Background cloud fetch
    try {
      final res = await docProvider.getMarkdown(_doc.id);
      if (mounted) {
        final content = (res['markdown'] as String?) ?? '';
        if (content.trim().isNotEmpty) {
          await docCache.saveMarkdown(_doc.id, content);
          setState(() {
            _markdownContent = content;
            _isLoadingMarkdown = false;
            _doc = _doc.copyWith(hasMarkdown: true);
          });
          if (_outlineItems.isEmpty) {
            _loadOutline();
          }
        } else {
          setState(() {
            _isLoadingMarkdown = false;
          });
        }
      }
    } catch (e) {
      if (mounted && (_markdownContent == null || _markdownContent!.isEmpty)) {
        setState(() {
          _isLoadingMarkdown = false;
          _markdownError = e.toString();
        });
      }
    }
  }

  void _onViewModeChanged(ReaderViewMode mode) {
    final targetPage = _currentPage;
    setState(() {
      _viewMode = mode;
      _pdfActiveSelection = null;
      _arbitraryMenuState = null;
      _wasSelectionActiveOnPointerDown = false;
      if (mode == ReaderViewMode.markdown) {
        _hasActivatedMarkdown = true;
      }
    });
    if (mode == ReaderViewMode.markdown) {
      if (_markdownContent == null || _markdownContent!.trim().isEmpty) {
        _fetchMarkdownData(forceReload: true).then((_) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _markdownKey.currentState?.jumpToPage(targetPage);
            });
            _loadOutline();
            if (_searchQuery.isNotEmpty) {
              _performSearch(_searchQuery);
            }
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _markdownKey.currentState?.jumpToPage(targetPage);
        });
        _loadOutline();
        if (_searchQuery.isNotEmpty) {
          _performSearch(_searchQuery);
        }
      }
    } else {
      // Switching to PDF mode: jump to targetPage reliably
      void goToPdfPage(int retries) {
        if (!mounted || _viewMode != ReaderViewMode.pdf) return;
        if (_pdfController.isReady) {
          _pdfController.goToPage(pageNumber: targetPage);
        } else if (retries > 0) {
          Future.delayed(const Duration(milliseconds: 50), () => goToPdfPage(retries - 1));
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        goToPdfPage(8);
      });
      _loadOutline();
      if (_searchQuery.isNotEmpty) {
        _performSearch(_searchQuery);
      }
    }
  }

  Future<void> _fetchPdfData() async {
    final docProvider = context.read<DocumentProvider>();
    final docCache = docProvider.docCacheService;

    // 1. Universal Cache-First check (Web IndexedDB / Desktop & Mobile local disk)
    // If the document was previously opened or uploaded, load immediately with zero network delay!
    try {
      final cachedBytes = await docCache.getPdf(_doc.id, expectedChecksum: _doc.checksum);
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        if (mounted) {
          setState(() {
            _pdfBytes = cachedBytes;
            _useUriSource = false;
            _isLoadingPdf = false;
            _loadError = null;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Error checking local PDF cache: $e');
    }

    // 2. Cache miss: download full file stream with progress callback and store in cache
    // Downloading in a single HTTP stream is vastly faster than hundreds of 64KB range requests,
    // avoids blank pages during rendering, and populates IndexedDB / disk cache for next time.
    if (_doc.fileSize <= 60 * 1024 * 1024) {
      try {
        if (mounted) {
          setState(() {
            _isLoadingPdf = true;
            _downloadProgress = 0.0;
            _downloadReceived = 0;
            _downloadTotal = _doc.fileSize;
            _loadError = null;
          });
        }

        final bytes = await docProvider.apiService.downloadDocumentBytes(
          _doc.id,
          onProgress: (received, total) {
            if (mounted) {
              setState(() {
                _downloadReceived = received;
                _downloadTotal = total;
                _downloadProgress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
              });
            }
          },
        );

        // Store into persistent cache (IndexedDB on Web, Disk on mobile/desktop)
        await docCache.savePdf(_doc.id, bytes, checksum: _doc.checksum);

        if (mounted) {
          setState(() {
            _pdfBytes = bytes;
            _useUriSource = false;
            _isLoadingPdf = false;
            _loadError = null;
          });
        }
        return;
      } catch (e) {
        debugPrint('Single-stream download failed, falling back to URI streaming: $e');
      }
    }

    // 3. Fallback for massive files (>60MB) or if direct download failed:
    // Fall back to HTTP Range URI streaming
    try {
      final storage = docProvider.storageService;
      final rawUrl = _doc.getFileUrl(storage.getBaseUrl());
      final separator = rawUrl.contains('?') ? '&' : '?';
      final fileUrl = '$rawUrl${separator}v=${_doc.updatedAt.millisecondsSinceEpoch}';
      final uri = Uri.parse(fileUrl);
      if (mounted) {
        setState(() {
          _pdfUri = uri;
          _useUriSource = true;
          _isLoadingPdf = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPdf = false;
          _loadError = e.toString();
        });
      }
    }
  }

  void _showOcrDialog() {
    showDialog(
      context: context,
      builder: (ctx) => OcrDialog(
        document: _doc,
        currentPage: _currentPage,
        onOcrStarted: () {
          setState(() {
            _doc = _doc.copyWith(ocrStatus: 'processing');
          });
          _startPollingOcr();
        },
        onOcrCompleted: () async {
          final updatedDoc = await context.read<DocumentProvider>().apiService.getDocument(_doc.id);
          if (mounted) {
            setState(() {
              _doc = updatedDoc;
            });
            _fetchMarkdownData(forceReload: true);
          }
        },
      ),
    );
  }

  void _saveCurrentPage(int page) {
    if (page >= 1 && _currentPage != page) {
      _currentPage = page;
      _currentPageNotifier.value = page;
      _pageSaveDebounceTimer?.cancel();
      _pageSaveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          context.read<DocumentProvider>().storageService.setLastReadPage(_doc.id, page);
        }
      });
    }
  }

  void _handleAskAi(String text, int pageNumber) {
    if (text.trim().isEmpty) return;
    final aiProv = context.read<AiProvider>();
    aiProv.setPendingQuote(text.trim(), pageNumber: pageNumber);

    // Automatically reveal the AI Chat sidebar on desktop, or pull up mobile bottom sheet
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (isMobile) {
      _openMobileSheet(context, ReaderSidebarTab.aiChat);
    } else {
      final settings = context.read<ReaderSettingsProvider>();
      settings.openTab(ReaderSidebarTab.aiChat);
    }
  }

  Future<String?> _getPageContext(int pageNumber) async {
    // 1. If Markdown content is available, find that page chunk
    if (_markdownContent != null && _markdownContent!.isNotEmpty) {
      final pageRegex = RegExp(r'<!--\s*Page\s+(\d+)\s*-->', caseSensitive: false);
      final matches = pageRegex.allMatches(_markdownContent!).toList();
      if (matches.isNotEmpty) {
        for (int i = 0; i < matches.length; i++) {
          final m = matches[i];
          final pNum = int.tryParse(m.group(1) ?? '') ?? (i + 1);
          if (pNum == pageNumber) {
            final start = m.end;
            final end = (i + 1 < matches.length) ? matches[i + 1].start : _markdownContent!.length;
            final chunk = _markdownContent!.substring(start, end).trim();
            if (chunk.isNotEmpty) return chunk;
          }
        }
      } else {
        return _markdownContent;
      }
    }

    // 2. If in PDF mode and pdfController is ready, extract page text
    if (_pdfController.isReady && pageNumber >= 1 && pageNumber <= _totalPages) {
      try {
        final pageText = await _pdfController.document.pages[pageNumber - 1].loadText();
        final text = pageText?.fullText.trim();
        if (text != null && text.isNotEmpty) {
          return text;
        }
      } catch (e) {
        debugPrint('Error loading PDF page text for AI context: $e');
      }
    }

    return null;
  }

  void _onJumpToPage(int page) {
    if (_pdfActiveSelection != null) {
      setState(() => _pdfActiveSelection = null);
    }
    if (_viewMode == ReaderViewMode.pdf) {
      if (_pdfController.isReady) {
        _pdfController.goToPage(pageNumber: page);
        _saveCurrentPage(page);
      }
    } else {
      _saveCurrentPage(page);
      _markdownKey.currentState?.jumpToPage(page);
    }
  }

  void _openMobileSheet(BuildContext context, ReaderSidebarTab tab) {
    ReaderMobileBottomSheet.show(
      context: context,
      initialTab: tab,
      outlineItems: _outlineItems,
      isOutlineLoading: _isOutlineLoading,
      searchQuery: _searchQuery,
      searchResults: _searchResults,
      isSearching: _isSearching,
      onSearchChanged: _onSearchQueryChanged,
      onClearSearch: () => setState(() {
        _searchQuery = '';
        _searchResults = [];
      }),
      onJumpToPage: _onJumpToPage,
      currentPage: _currentPage,
      totalPages: _totalPages > 0 ? _totalPages : (_doc.pageCount > 0 ? _doc.pageCount : 1),
      documentTitle: _doc.title,
      docId: _doc.id,
      onGetPageContext: _getPageContext,
      onZoomIn: _handleZoomIn,
      onZoomOut: _handleZoomOut,
      onResetZoom: _handleResetZoom,
      onFitWidth: _handleFitWidth,
      onDeleteAnnotation: _handleDeleteAnnotation,
      onAddNewNote: (page) => _openNewNoteDialogForPage(page),
    );
  }

  void _openMobileProgressSheet(BuildContext context) {
    final totalP = _totalPages > 0 ? _totalPages : (_doc.pageCount > 0 ? _doc.pageCount : 1);
    ReaderMobileProgressSheet.show(
      context: context,
      currentPage: _currentPage,
      totalPages: totalP,
      onJumpToPage: _onJumpToPage,
      onZoomIn: _handleZoomIn,
      onZoomOut: _handleZoomOut,
      onResetZoom: _handleResetZoom,
      onFitWidth: _handleFitWidth,
      isMarkdownMode: _viewMode == ReaderViewMode.markdown,
      onToggleImmersive: () => setState(() => _isImmersiveMode = !_isImmersiveMode),
    );
  }

  // -------------------------------------------------------------
  // Outline (TOC) Extraction & Mapping (Adapts to Active Mode)
  // -------------------------------------------------------------
  Future<void> _loadOutline() async {
    if (!mounted) return;
    setState(() => _isOutlineLoading = true);

    if (_viewMode == ReaderViewMode.markdown) {
      if (_markdownContent != null && _markdownContent!.isNotEmpty) {
        final items = _parseMarkdownHeadings(_markdownContent!);
        if (items.isNotEmpty) {
          if (mounted) {
            setState(() {
              _outlineItems = items;
              _isOutlineLoading = false;
            });
            return;
          }
        }
      }
      try {
        if (_pdfController.isReady) {
          final outline = await _pdfController.document.loadOutline().timeout(const Duration(seconds: 4));
          if (outline.isNotEmpty) {
            final items = outline.map((node) => _mapPdfOutlineNode(node, 1)).toList();
            if (mounted) {
              setState(() {
                _outlineItems = items;
                _isOutlineLoading = false;
              });
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading PDF outline fallback: $e');
      }
    } else {
      // PDF Mode
      try {
        if (_pdfController.isReady) {
          final outline = await _pdfController.document.loadOutline().timeout(const Duration(seconds: 4));
          if (outline.isNotEmpty) {
            final items = outline.map((node) => _mapPdfOutlineNode(node, 1)).toList();
            if (mounted) {
              setState(() {
                _outlineItems = items;
                _isOutlineLoading = false;
              });
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading PDF outline: $e');
      }

      if (_markdownContent != null && _markdownContent!.isNotEmpty) {
        final items = _parseMarkdownHeadings(_markdownContent!);
        if (items.isNotEmpty) {
          if (mounted) {
            setState(() {
              _outlineItems = items;
              _isOutlineLoading = false;
            });
            return;
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _outlineItems = [];
        _isOutlineLoading = false;
      });
    }
  }

  OutlineItem _mapPdfOutlineNode(PdfOutlineNode node, int level) {
    return OutlineItem(
      title: node.title,
      pageNumber: node.dest?.pageNumber ?? 1,
      level: level,
      children: node.children.map((child) => _mapPdfOutlineNode(child, level + 1)).toList(),
    );
  }

  List<OutlineItem> _parseMarkdownHeadings(String rawMarkdown) {
    if (rawMarkdown.trim().isEmpty) return [];
    final lines = rawMarkdown.split('\n');
    final List<OutlineItem> headings = [];
    int pageNum = 1;
    final pageRegex = RegExp(r'<!--\s*Page\s+(\d+)\s*-->', caseSensitive: false);

    for (final line in lines) {
      final match = pageRegex.firstMatch(line);
      if (match != null) {
        pageNum = int.tryParse(match.group(1) ?? '') ?? pageNum;
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.startsWith('# ') || trimmed.startsWith('## ') || trimmed.startsWith('### ') || trimmed.startsWith('#### ')) {
        int level = 1;
        String title = trimmed;
        if (trimmed.startsWith('#### ')) {
          level = 4;
          title = trimmed.substring(5);
        } else if (trimmed.startsWith('### ')) {
          level = 3;
          title = trimmed.substring(4);
        } else if (trimmed.startsWith('## ')) {
          level = 2;
          title = trimmed.substring(3);
        } else if (trimmed.startsWith('# ')) {
          level = 1;
          title = trimmed.substring(2);
        }
        headings.add(OutlineItem(
          title: title.replaceAll(RegExp(r'[*_`#]'), '').trim(),
          pageNumber: pageNum,
          level: level,
        ));
      }
    }
    return headings;
  }

  // -------------------------------------------------------------
  // Full-Text Search Implementation
  // -------------------------------------------------------------
  Future<List<SearchResultItem>> _searchPdfText(String query) async {
    if (query.trim().isEmpty || !_pdfController.isReady) return [];
    final q = query.trim().toLowerCase();
    final List<SearchResultItem> results = [];

    final pages = _pdfController.pages;
    for (int i = 0; i < pages.length; i++) {
      if (!mounted || _searchQuery != query) return [];
      if (i > 0 && i % 6 == 0) {
        await Future.delayed(Duration.zero);
      }
      final page = pages[i];
      final pageNum = page.pageNumber;
      try {
        final pageText = await page.loadText();
        final fullText = pageText?.fullText ?? '';
        if (fullText.isEmpty) continue;
        final lower = fullText.toLowerCase();

        int count = 0;
        int idx = lower.indexOf(q);
        int firstIdx = idx;

        while (idx != -1) {
          count++;
          idx = lower.indexOf(q, idx + q.length);
        }

        if (count > 0) {
          final snippetStart = (firstIdx - 20).clamp(0, fullText.length);
          final snippetEnd = (firstIdx + q.length + 40).clamp(0, fullText.length);
          final snippet = fullText.substring(snippetStart, snippetEnd).replaceAll('\n', ' ');

          results.add(SearchResultItem(
            pageNumber: pageNum,
            matchCount: count,
            snippet: '...$snippet...',
          ));
          if (results.length >= 60) break;
        }
      } catch (e) {
        // continue
      }
    }
    return results;
  }

  List<SearchResultItem> _searchMarkdownText(String query) {
    if (query.trim().isEmpty || _markdownContent == null) return [];
    final q = query.trim().toLowerCase();
    final List<SearchResultItem> results = [];
    final pageRegex = RegExp(r'<!--\s*Page\s+(\d+)\s*-->', caseSensitive: false);
    final matches = pageRegex.allMatches(_markdownContent!).toList();

    if (matches.isNotEmpty) {
      for (int i = 0; i < matches.length; i++) {
        final currentMatch = matches[i];
        final pageNum = int.tryParse(currentMatch.group(1) ?? '') ?? (i + 1);
        final start = currentMatch.end;
        final end = (i + 1 < matches.length) ? matches[i + 1].start : _markdownContent!.length;
        final content = _markdownContent!.substring(start, end);
        final lower = content.toLowerCase();

        int count = 0;
        int idx = lower.indexOf(q);
        int firstIdx = idx;

        while (idx != -1) {
          count++;
          idx = lower.indexOf(q, idx + q.length);
        }

        if (count > 0) {
          final snippetStart = (firstIdx - 20).clamp(0, content.length);
          final snippetEnd = (firstIdx + q.length + 40).clamp(0, content.length);
          final snippet = content.substring(snippetStart, snippetEnd).replaceAll('\n', ' ');

          results.add(SearchResultItem(
            pageNumber: pageNum,
            matchCount: count,
            snippet: '...$snippet...',
          ));
        }
      }
    } else {
      final lower = _markdownContent!.toLowerCase();
      int count = 0;
      int idx = lower.indexOf(q);
      int firstIdx = idx;
      while (idx != -1) {
        count++;
        idx = lower.indexOf(q, idx + q.length);
      }
      if (count > 0) {
        final snippetStart = (firstIdx - 20).clamp(0, _markdownContent!.length);
        final snippetEnd = (firstIdx + q.length + 40).clamp(0, _markdownContent!.length);
        final snippet = _markdownContent!.substring(snippetStart, snippetEnd).replaceAll('\n', ' ');
        results.add(SearchResultItem(
          pageNumber: 1,
          matchCount: count,
          snippet: '...$snippet...',
        ));
      }
    }
    return results;
  }

  void _onSearchQueryChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (query.trim().isEmpty) {
        _searchResults = [];
        _isSearching = false;
        return;
      }
    });

    _performSearch(query);
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);

    List<SearchResultItem> results = [];
    if (_markdownContent != null && _markdownContent!.isNotEmpty) {
      results = _searchMarkdownText(query);
    } else if (_viewMode == ReaderViewMode.pdf && _pdfController.isReady) {
      results = await _searchPdfText(query);
    } else {
      results = _searchMarkdownText(query);
    }

    if (mounted && _searchQuery == query) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  // -------------------------------------------------------------
  // Zoom & Scale Actions
  // -------------------------------------------------------------
  void _handleZoomIn() {
    final settings = context.read<ReaderSettingsProvider>();
    if (_viewMode == ReaderViewMode.pdf) {
      if (_pdfController.isReady) {
        final currentRatio = _basePdfZoom > 0 ? (_pdfController.currentZoom / _basePdfZoom) : _pdfController.currentZoom;
        final targetRatio = (currentRatio * 1.20).clamp(0.5, 4.0);
        _pdfController.setZoom(_pdfController.centerPosition, _basePdfZoom * targetRatio);
        settings.setZoomScale(targetRatio);
      }
    } else {
      settings.setZoomScale((settings.zoomScale * 1.20).clamp(0.5, 4.0));
    }
  }

  void _handleZoomOut() {
    final settings = context.read<ReaderSettingsProvider>();
    if (_viewMode == ReaderViewMode.pdf) {
      if (_pdfController.isReady) {
        final currentRatio = _basePdfZoom > 0 ? (_pdfController.currentZoom / _basePdfZoom) : _pdfController.currentZoom;
        final targetRatio = (currentRatio / 1.20).clamp(0.5, 4.0);
        _pdfController.setZoom(_pdfController.centerPosition, _basePdfZoom * targetRatio);
        settings.setZoomScale(targetRatio);
      }
    } else {
      settings.setZoomScale((settings.zoomScale / 1.20).clamp(0.5, 4.0));
    }
  }

  void _handleResetZoom() {
    final settings = context.read<ReaderSettingsProvider>();
    if (_viewMode == ReaderViewMode.pdf && _pdfController.isReady) {
      if (_basePdfZoom > 0) {
        _pdfController.setZoom(_pdfController.centerPosition, _basePdfZoom);
      }
    }
    settings.setZoomScale(1.0);
  }

  void _handleFitWidth() {
    if (_pdfController.isReady) {
      final m = _pdfController.calcMatrixFitWidthForPage(pageNumber: _currentPage);
      if (m != null) {
        _pdfController.goTo(m);
      }
    }
  }

  Widget _buildPositionedFloatingBar({
    required BuildContext context,
    required Offset pointerPos,
    required Size containerSize,
    required Widget child,
    bool? isMobile,
  }) {
    final bool mobile = isMobile ?? (containerSize.width < 700);
    final double menuWidth = mobile ? 248.0 : 420.0;
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

  Widget _buildPositionedArbitraryMenu({
    required BuildContext context,
    required ArbitraryPointMenuState menuState,
    required Size containerSize,
    required bool isMobile,
    required ReadingMode readingMode,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSepia = readingMode == ReadingMode.sepia;

    final Color bgColor = isSepia
        ? const Color(0xFFFBF0D9)
        : (isDark ? const Color(0xFF1E293B) : Colors.white);
    final Color textColor = isSepia
        ? const Color(0xFF433422)
        : (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A));
    final Color borderColor = isSepia
        ? const Color(0xFFDCC8A4)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));

    final double menuWidth = isMobile ? 260.0 : 200.0;
    final double menuHeight = isMobile ? 48.0 : 138.0;

    double left = menuState.position.dx - (isMobile ? menuWidth / 2 : 16);
    if (left < 16) left = 16;
    if (left + menuWidth > containerSize.width - 16) {
      left = containerSize.width - menuWidth - 16;
    }
    if (left < 0) left = 0;

    double top = menuState.position.dy - (isMobile ? menuHeight + 16 : 10);
    if (top < 10) {
      top = menuState.position.dy + 20;
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
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: menuWidth,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(isMobile ? 24 : 12),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: isMobile
                ? _buildMobileArbitraryMenuContent(menuState, textColor, theme)
                : _buildDesktopArbitraryMenuContent(menuState, textColor, theme),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopArbitraryMenuContent(
    ArbitraryPointMenuState menuState,
    Color textColor,
    ThemeData theme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            setState(() => _arbitraryMenuState = null);
            _openNewNoteDialogForPage(
              menuState.pageNumber,
              normalizedRect: menuState.normalizedRect,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF6366F1)),
                const SizedBox(width: 10),
                Text(
                  '在此处添加批注',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 0.8, color: theme.dividerColor.withValues(alpha: 0.1)),
        InkWell(
          onTap: () {
            setState(() => _arbitraryMenuState = null);
            _openNewCardDialogForPage(
              menuState.pageNumber,
              normalizedRect: menuState.normalizedRect,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.style_rounded, size: 16, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 10),
                Text(
                  '在此处添加知识卡片',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 0.8, color: theme.dividerColor.withValues(alpha: 0.1)),
        InkWell(
          onTap: () {
            setState(() => _arbitraryMenuState = null);
            _handleAskAi("提问关于第 ${menuState.pageNumber} 页的内容", menuState.pageNumber);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 10),
                Text(
                  '提问 AI (第 ${menuState.pageNumber} 页)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileArbitraryMenuContent(
    ArbitraryPointMenuState menuState,
    Color textColor,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton.icon(
            onPressed: () {
              setState(() => _arbitraryMenuState = null);
              _openNewNoteDialogForPage(
                menuState.pageNumber,
                normalizedRect: menuState.normalizedRect,
              );
            },
            icon: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF6366F1)),
            label: Text('批注', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Container(height: 16, width: 1, color: theme.dividerColor.withValues(alpha: 0.2)),
          TextButton.icon(
            onPressed: () {
              setState(() => _arbitraryMenuState = null);
              _openNewCardDialogForPage(
                menuState.pageNumber,
                normalizedRect: menuState.normalizedRect,
              );
            },
            icon: const Icon(Icons.style_rounded, size: 16, color: Color(0xFF8B5CF6)),
            label: Text('卡片', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Container(height: 16, width: 1, color: theme.dividerColor.withValues(alpha: 0.2)),
          TextButton.icon(
            onPressed: () {
              setState(() => _arbitraryMenuState = null);
              _handleAskAi("提问关于第 ${menuState.pageNumber} 页的内容", menuState.pageNumber);
            },
            icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF0EA5E9)),
            label: Text('问AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  void _createHighlightFromSelection({
    required String colorHex,
    required String selectedText,
    required List<PdfPageTextRange> textRanges,
  }) {
    if (textRanges.isEmpty) return;

    final firstRange = textRanges.first;
    final pageNumber = firstRange.pageNumber;
    if (!_pdfController.isReady || pageNumber > _pdfController.pages.length) return;

    final page = _pdfController.pages[pageNumber - 1];
    final List<NormalizedRect> normalizedRects = [];

    for (final range in textRanges) {
      final bounds = range.bounds;
      final norm = NormalizedRect(
        x: bounds.left / page.width,
        y: bounds.bottom / page.height,
        width: bounds.width / page.width,
        height: bounds.height / page.height,
      );
      normalizedRects.add(norm);
    }

    final newAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "highlight",
      pageNumber: pageNumber,
      colorHex: colorHex,
      rects: normalizedRects,
      selectedText: selectedText.trim(),
      noteContent: "",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    context.read<AnnotationProvider>().addAnnotation(newAnno);
    context.read<DocumentProvider>().updateAnnotationCount(widget.document.id, 1);

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

  void _createNoteFromSelection({
    required String selectedText,
    required List<PdfPageTextRange> textRanges,
    required String noteContent,
  }) {
    if (textRanges.isEmpty || noteContent.trim().isEmpty) return;

    final firstRange = textRanges.first;
    final pageNumber = firstRange.pageNumber;
    if (!_pdfController.isReady || pageNumber > _pdfController.pages.length) return;

    final page = _pdfController.pages[pageNumber - 1];
    final List<NormalizedRect> normalizedRects = [];

    for (final range in textRanges) {
      final bounds = range.bounds;
      final norm = NormalizedRect(
        x: bounds.left / page.width,
        y: bounds.bottom / page.height,
        width: bounds.width / page.width,
        height: bounds.height / page.height,
      );
      normalizedRects.add(norm);
    }

    final newAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "note",
      pageNumber: pageNumber,
      colorHex: "#6366F1",
      rects: normalizedRects,
      selectedText: selectedText.trim(),
      noteContent: noteContent.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    context.read<AnnotationProvider>().addAnnotation(newAnno);
    context.read<DocumentProvider>().updateAnnotationCount(widget.document.id, 1);

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

  ({int pageNumber, NormalizedRect normalizedRect})? _resolvePdfPageCoordinates(Offset viewerLocalPos) {
    if (!_pdfController.isReady) return null;
    final docPos = _pdfController.localToDocument(viewerLocalPos);

    final pageLayouts = _pdfController.layout.pageLayouts;
    if (pageLayouts.isEmpty) return null;

    int? hitIndex;
    Rect? hitPageRect;
    for (int i = 0; i < pageLayouts.length; i++) {
      if (pageLayouts[i].contains(docPos)) {
        hitIndex = i;
        hitPageRect = pageLayouts[i];
        break;
      }
    }

    if (hitIndex == null || hitPageRect == null) {
      double minDistance = double.infinity;
      for (int i = 0; i < pageLayouts.length; i++) {
        final rect = pageLayouts[i];
        final dist = (rect.center - docPos).distanceSquared;
        if (dist < minDistance) {
          minDistance = dist;
          hitIndex = i;
          hitPageRect = rect;
        }
      }
    }

    if (hitIndex == null || hitPageRect == null) return null;

    final normX = ((docPos.dx - hitPageRect.left) / hitPageRect.width).clamp(0.01, 0.99);
    final normY = ((docPos.dy - hitPageRect.top) / hitPageRect.height).clamp(0.01, 0.99);

    return (
      pageNumber: hitIndex + 1,
      normalizedRect: NormalizedRect(
        x: normX,
        y: normY,
        width: 0.02,
        height: 0.02,
      ),
    );
  }

  void _handleSecondaryClick(Offset localPos, {bool isTouch = false}) {
    final resolved = _resolvePdfPageCoordinates(localPos);
    if (resolved == null) return;

    if (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText) {
      _pdfController.textSelectionDelegate.clearTextSelection();
    }

    if (mounted) {
      setState(() {
        _pdfActiveSelection = null;
        _arbitraryMenuState = ArbitraryPointMenuState(
          pageNumber: resolved.pageNumber,
          normalizedRect: resolved.normalizedRect,
          position: localPos,
          isTouch: isTouch,
        );
      });
    }
  }

  void _openNewNoteDialogForPage(int pageNumber, {NormalizedRect? normalizedRect}) {
    final rects = normalizedRect != null
        ? [normalizedRect]
        : <NormalizedRect>[];

    final tempAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "note",
      pageNumber: pageNumber,
      colorHex: "#6366F1",
      rects: rects,
      selectedText: "",
      noteContent: "",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    showDialog(
      context: context,
      builder: (ctx) => NoteEditorDialog(
        annotation: tempAnno,
        onSave: (saved) {
          final newAnno = saved.copyWith(
            rects: rects,
            type: "note",
          );
          context.read<AnnotationProvider>().addAnnotation(newAnno);
          context.read<DocumentProvider>().updateAnnotationCount(widget.document.id, 1);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFF818CF8), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已在第 $pageNumber 页添加批注笔记',
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
        },
        onDelete: () {},
      ),
    );
  }

  void _openNewCardDialogForPage(int pageNumber, {NormalizedRect? normalizedRect}) {
    final rects = normalizedRect != null
        ? [normalizedRect]
        : <NormalizedRect>[];

    final tempAnno = PdfAnnotation(
      id: _uuid.v4(),
      docId: widget.document.id,
      type: "card",
      pageNumber: pageNumber,
      colorHex: "#8B5CF6",
      rects: rects,
      selectedText: "",
      noteContent: "",
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    showDialog(
      context: context,
      builder: (ctx) => KnowledgeCardDialog(
        annotation: tempAnno,
        pageNumber: pageNumber,
        docId: widget.document.id,
        startInEditMode: true,
        onSave: (saved) {
          final cardAnno = saved.copyWith(
            rects: rects,
            type: "card",
          );
          context.read<AnnotationProvider>().addAnnotation(cardAnno);
          context.read<DocumentProvider>().updateAnnotationCount(widget.document.id, 1);
        },
        onDelete: () {},
        onJumpToPage: _onJumpToPage,
      ),
    );
  }

  void _openPdfNoteDialog(PdfAnnotation note) {
    showDialog(
      context: context,
      builder: (_) => NoteEditorDialog(
        annotation: note,
        onSave: (saved) {
          context.read<AnnotationProvider>().updateAnnotation(
            saved.id,
            colorHex: saved.colorHex,
            noteContent: saved.noteContent,
          );
        },
        onDelete: () {
          _handleDeleteAnnotation(note);
        },
      ),
    );
  }

  void _openPdfCardDialog(PdfAnnotation card) {
    showDialog(
      context: context,
      builder: (_) => KnowledgeCardDialog(
        annotation: card,
        pageNumber: card.pageNumber,
        docId: _doc.id,
        onSave: (updated) {
          context.read<AnnotationProvider>().updateAnnotationModel(updated);
        },
        onDelete: () {
          _handleDeleteAnnotation(card);
        },
        onJumpToPage: _onJumpToPage,
      ),
    );
  }

  String _removeHighlightFromMarkdown(String markdown, String targetText) {
    return removeHighlightFromMarkdown(markdown, targetText);
  }

  void _handleDeleteAnnotation(PdfAnnotation anno) async {
    final docProvider = context.read<DocumentProvider>();
    final annoProvider = context.read<AnnotationProvider>();

    await annoProvider.deleteAnnotation(anno.id);
    docProvider.updateAnnotationCount(_doc.id, -1);

    if (anno.selectedText.trim().isNotEmpty) {
      final text = anno.selectedText.trim();
      var currentMd = _markdownContent;
      if (currentMd == null || currentMd.isEmpty) {
        final cached = await DocCacheService().getMarkdown(_doc.id);
        if (cached != null && cached.isNotEmpty) {
          currentMd = cached;
        }
      }

      if (currentMd != null && currentMd.isNotEmpty) {
        final updatedMd = _removeHighlightFromMarkdown(currentMd, text);
        if (updatedMd != currentMd) {
          if (mounted) {
            setState(() {
              _markdownContent = updatedMd;
            });
          }
          try {
            await docProvider.saveMarkdown(_doc.id, updatedMd);
          } catch (e) {
            debugPrint('Error saving markdown after deleting annotation: $e');
          }
        }
      }
    }
  }

  void _paintPageAnnotations(Canvas canvas, Rect pageRect, PdfPage page, {bool isDark = false}) {
    final annoProvider = context.read<AnnotationProvider>();
    final settings = context.read<ReaderSettingsProvider>();
    if (!settings.showAnnotations) return;

    final pageAnnos = annoProvider.getAnnotationsForPage(page.pageNumber);
    if (pageAnnos.isEmpty) return;

    final focusedId = annoProvider.focusedAnnotationId;

    for (final anno in pageAnnos) {
      // 只有荧光高亮 (Highlight) 才在 Canvas 上绘制底色填充矩形
      // 批注 (Note) 和知识卡片 (Card) 仅在页面上通过 pageOverlaysBuilder 挂载可交互徽标，不绘制底色框
      if (!anno.isHighlight) continue;

      final isFocused = focusedId == anno.id;
      final highlightColor = AppTheme.getHighlightColorForRendering(
        anno.colorHex,
        isDark: isDark,
        alpha: isFocused ? 0.65 : 0.45,
      );

      final paint = Paint()
        ..color = highlightColor
        ..style = PaintingStyle.fill;

      final borderPaint = isFocused
          ? (Paint()
            ..color = isDark ? Colors.white : Theme.of(context).colorScheme.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0)
          : null;

      for (final norm in anno.rects) {
        final pdfRect = PdfRect(
          norm.x * page.width,
          (norm.y + norm.height) * page.height,
          (norm.x + norm.width) * page.width,
          norm.y * page.height,
        );

        final screenRect = pdfRect.toRectInDocument(page: page, pageRect: pageRect);
        final rrect = RRect.fromRectAndRadius(screenRect, const Radius.circular(3));
        canvas.drawRRect(rrect, paint);

        if (borderPaint != null) {
          canvas.drawRRect(rrect, borderPaint);
        }
      }
    }
  }

  List<Widget> _buildPdfPageOverlays(BuildContext context, Rect pageRect, PdfPage page) {
    final annoProvider = context.watch<AnnotationProvider>();
    final settings = context.watch<ReaderSettingsProvider>();
    if (!settings.showAnnotations) return const [];

    final isDark = settings.readingMode == ReadingMode.dark;
    final pageAnnos = annoProvider.getAnnotationsForPage(page.pageNumber);
    final badges = <Widget>[];

    for (final anno in pageAnnos) {
      if (!anno.isNote && !anno.isCard) continue;

      double badgeLeft = 8.0;
      double badgeTop = 8.0;

      if (anno.rects.isNotEmpty) {
        final firstNorm = anno.rects.first;
        if (anno.isPointAnnotation || anno.selectedText.trim().isEmpty) {
          badgeLeft = (firstNorm.x * pageRect.width - 13.0).clamp(4.0, max(4.0, pageRect.width - 30.0));
          badgeTop = (firstNorm.y * pageRect.height - 13.0).clamp(2.0, max(2.0, pageRect.height - 30.0));
        } else {
          final pdfRect = PdfRect(
            firstNorm.x * page.width,
            (firstNorm.y + firstNorm.height) * page.height,
            (firstNorm.x + firstNorm.width) * page.width,
            firstNorm.y * page.height,
          );
          final screenRect = pdfRect.toRectInDocument(page: page, pageRect: pageRect);

          badgeLeft = screenRect.left - pageRect.left - 24.0;
          if (badgeLeft < 4.0) {
            badgeLeft = (screenRect.left - pageRect.left).clamp(4.0, max(4.0, pageRect.width - 24.0));
          }
          badgeTop = (screenRect.top - pageRect.top - 2.0).clamp(2.0, max(2.0, pageRect.height - 24.0));
        }
      }

      badges.add(
        Positioned(
          left: badgeLeft,
          top: badgeTop,
          child: _buildInteractiveAnnotationBadge(anno, isDark),
        ),
      );
    }

    return badges;
  }

  Widget _buildInteractiveAnnotationBadge(PdfAnnotation anno, bool isDark) {
    final isCard = anno.isCard;
    final color = AppTheme.parseHexColor(anno.colorHex);

    return Tooltip(
      message: isCard
          ? '知识卡片: ${anno.displayTitle} (点击查看/编辑)'
          : (anno.isPointAnnotation ? '图钉批注: ${anno.displayTitle} (点击查看/编辑)' : '批注笔记: ${anno.displayTitle} (点击查看/编辑)'),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            if (isCard) {
              _openPdfCardDialog(anno);
            } else {
              _openPdfNoteDialog(anno);
            }
          },
          borderRadius: BorderRadius.circular(7),
          child: Container(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.all(4.0),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: color,
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.16),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(
              isCard ? Icons.style_rounded : Icons.edit_note_rounded,
              size: 14.5,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPdfPageSummaryStrip(bool isDark) {
    return ValueListenableBuilder<int>(
      valueListenable: _currentPageNotifier,
      builder: (context, curPage, _) {
        final annoProvider = context.watch<AnnotationProvider>();
        final settings = context.watch<ReaderSettingsProvider>();
        if (!settings.showAnnotations) return const SizedBox.shrink();

        final isSepia = settings.readingMode == ReadingMode.sepia;
        final pageAnnos = annoProvider.getAnnotationsForPage(curPage);
        final pageCards = pageAnnos.where((a) => a.isCard).toList();
        final pageNotes = pageAnnos.where((a) => a.isNote).toList();

        if (pageCards.isEmpty && pageNotes.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
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
                    onTap: () => _openPdfCardDialog(c),
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
                    onTap: () => _openPdfNoteDialog(n),
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
              Tooltip(
                message: '在当前第 $curPage 页添加批注笔记',
                child: InkWell(
                  onTap: () => _openNewNoteDialogForPage(curPage),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 12, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          '记批注',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollapsedRail(
    SidebarDockPosition position,
    ReaderSettingsProvider settings,
    bool isDark,
    ThemeData theme,
  ) {
    final isLeft = position == SidebarDockPosition.left;
    final dockedTabs = isLeft ? settings.leftDockedTabs : settings.rightDockedTabs;
    final totalPages = _totalPages > 0 ? _totalPages : (_doc.pageCount > 0 ? _doc.pageCount : 1);

    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(
          left: isLeft ? BorderSide.none : BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          right: isLeft ? BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)) : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Tab shortcut icons
          ...dockedTabs.map((tab) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: IconButton(
                icon: Icon(tab.icon, size: 18),
                tooltip: '展开 ${tab.label}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  if (isLeft) {
                    settings.setActiveLeftTab(tab);
                    settings.setLeftSidebarOpen(true);
                  } else {
                    settings.setActiveRightTab(tab);
                    settings.setRightSidebarOpen(true);
                  }
                },
              ),
            );
          }),
          const Spacer(),

          // If left rail: Show compact page jump & zoom controls even when collapsed
          if (isLeft) ...[
            // 1. Page Navigation
            ValueListenableBuilder<int>(
              valueListenable: _currentPageNotifier,
              builder: (context, currentPage, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                    tooltip: '上一页 (P.${currentPage > 1 ? currentPage - 1 : 1})',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                    onPressed: currentPage > 1 ? () => _onJumpToPage(currentPage - 1) : null,
                  ),
                  Tooltip(
                    message: '点击跳转页面 (共 $totalPages 页)',
                    child: InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => PageJumpDialog(
                            currentPage: currentPage,
                            totalPages: totalPages,
                            onJump: _onJumpToPage,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '$currentPage',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    tooltip: '下一页 (P.${currentPage < totalPages ? currentPage + 1 : totalPages})',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                    onPressed: currentPage < totalPages ? () => _onJumpToPage(currentPage + 1) : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Divider(
                height: 1,
                thickness: 1,
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),

            // 2. Zoom Controls
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 16),
              tooltip: '放大 (20%)',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: _handleZoomIn,
            ),
            Tooltip(
              message: '点击重置缩放 (100%)',
              child: InkWell(
                onTap: _handleResetZoom,
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Consumer<ReaderSettingsProvider>(
                    builder: (context, s, _) => Text(
                      '${(s.zoomScale * 100).toInt()}%',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 16),
              tooltip: '缩小 (20%)',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: _handleZoomOut,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Divider(
                height: 1,
                thickness: 1,
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
          ],

          // Expand Sidebar Button
          IconButton(
            icon: Icon(isLeft ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 20),
            tooltip: isLeft ? '展开左边栏' : '展开右边栏',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              if (isLeft) {
                settings.setLeftSidebarOpen(true);
              } else {
                settings.setRightSidebarOpen(true);
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readingMode = context.select<ReaderSettingsProvider, ReadingMode>((s) => s.readingMode);
    final isDark = readingMode == ReadingMode.dark;
    final isLeftSidebarOpen = context.select<ReaderSettingsProvider, bool>((s) => s.isLeftSidebarOpen);
    final isRightSidebarOpen = context.select<ReaderSettingsProvider, bool>((s) => s.isRightSidebarOpen);
    final leftDockedTabs = context.select<ReaderSettingsProvider, List<ReaderSidebarTab>>((s) => s.leftDockedTabs);
    final rightDockedTabs = context.select<ReaderSettingsProvider, List<ReaderSidebarTab>>((s) => s.rightDockedTabs);
    final settings = context.read<ReaderSettingsProvider>();

    ThemeData activeTheme;
    switch (readingMode) {
      case ReadingMode.dark:
        activeTheme = AppTheme.darkTheme;
        break;
      case ReadingMode.sepia:
        activeTheme = AppTheme.sepiaTheme;
        break;
      case ReadingMode.light:
        activeTheme = AppTheme.lightTheme;
        break;
    }

    final canvasBg = AppTheme.getReaderBgColor(readingMode);

    // Color filter for dark mode and sepia mode
    ColorFilter? pdfFilter;
    if (readingMode == ReadingMode.dark) {
      pdfFilter = AppTheme.darkPdfColorFilter;
    } else if (readingMode == ReadingMode.sepia) {
      pdfFilter = AppTheme.sepiaPdfColorFilter;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        return Theme(
          data: activeTheme,
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                if (_arbitraryMenuState != null) {
                  setState(() => _arbitraryMenuState = null);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              backgroundColor: canvasBg,
              bottomNavigationBar: isMobile && !_isImmersiveMode
                ? ValueListenableBuilder<int>(
                    valueListenable: _currentPageNotifier,
                    builder: (context, curPage, _) => ReaderBottomBar(
                      currentPage: curPage,
                      totalPages: _totalPages > 0 ? _totalPages : (_doc.pageCount > 0 ? _doc.pageCount : 1),
                      onTabSelected: (tab) => _openMobileSheet(context, tab),
                      onOpenProgress: () => _openMobileProgressSheet(context),
                      isMarkdownMode: _viewMode == ReaderViewMode.markdown,
                    ),
                  )
                : null,
            body: SafeArea(
              top: !_isImmersiveMode,
              bottom: !_isImmersiveMode,
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Top Bar
                      if (!_isImmersiveMode)
                        ValueListenableBuilder<int>(
                          valueListenable: _currentPageNotifier,
                          builder: (context, curPage, _) => ReaderTopBar(
                            isMobile: isMobile,
                            document: _doc,
                            ocrProgress: _ocrStatusInfo,
                            currentPage: curPage,
                            totalPages: _totalPages > 0 ? _totalPages : (_doc.pageCount > 0 ? _doc.pageCount : 1),
                            onJumpToPage: _onJumpToPage,
                            onOpenOcr: _showOcrDialog,
                            viewMode: _viewMode,
                            onViewModeChanged: _onViewModeChanged,
                            hasMarkdown: _doc.hasMarkdown || (_markdownContent != null && _markdownContent!.trim().isNotEmpty),
                            onZoomIn: _handleZoomIn,
                            onZoomOut: _handleZoomOut,
                            onResetZoom: _handleResetZoom,
                            onPrevPage: () {
                              if (_currentPage > 1) {
                                _onJumpToPage(_currentPage - 1);
                              }
                            },
                            onNextPage: () {
                              if (_currentPage < _totalPages) {
                                _onJumpToPage(_currentPage + 1);
                              }
                            },
                          ),
                        ),

                      // Scanned / Image PDF OCR Banner
                      if (_viewMode == ReaderViewMode.pdf && !_doc.hasTextLayer && _doc.ocrStatus != 'completed' && _doc.ocrStatus != 'processing' && !_isOcrBannerDismissed && !_isImmersiveMode)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5).withValues(alpha: isDark ? 0.25 : 0.08),
                            border: Border(
                              bottom: BorderSide(
                                color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF818CF8), size: 18),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  '提示：当前为扫描版/纯图片 PDF。可使用百度 PaddleOCR-VL 提取结构化 Markdown、数学公式与表格排版！',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                                label: const Text('OCR 提取 Markdown'),
                                onPressed: _showOcrDialog,
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: '关闭提示',
                                onPressed: () => setState(() => _isOcrBannerDismissed = true),
                              ),
                            ],
                          ),
                        ),

                      // Main Viewer & Flexible Sidebars (Left / Main / Right)
                      Expanded(
                        child: Row(
                          children: [
                            // 1. Left Sidebar (Desktop & Tablet only: !isMobile)
                            if (!isMobile) ...[
                              if (isLeftSidebarOpen && leftDockedTabs.isNotEmpty)
                                ValueListenableBuilder<int>(
                                  valueListenable: _currentPageNotifier,
                                  builder: (context, curPage, _) => ReaderSidebar(
                                    position: SidebarDockPosition.left,
                                    outlineItems: _outlineItems,
                                    isOutlineLoading: _isOutlineLoading,
                                    searchQuery: _searchQuery,
                                    searchResults: _searchResults,
                                    isSearching: _isSearching,
                                    onSearchChanged: _onSearchQueryChanged,
                                    onClearSearch: () => setState(() {
                                      _searchQuery = '';
                                      _searchResults = [];
                                    }),
                                    onJumpToPage: _onJumpToPage,
                                    currentPage: curPage,
                                    totalPages: _totalPages > 0 ? _totalPages : (_doc.pageCount > 0 ? _doc.pageCount : 1),
                                    documentTitle: _doc.title,
                                    docId: _doc.id,
                                    onGetPageContext: _getPageContext,
                                    onZoomIn: _handleZoomIn,
                                    onZoomOut: _handleZoomOut,
                                    onResetZoom: _handleResetZoom,
                                    onFitWidth: _handleFitWidth,
                                    onDeleteAnnotation: _handleDeleteAnnotation,
                                    onAddNewNote: (page) => _openNewNoteDialogForPage(page),
                                  ),
                                )
                              else
                                _buildCollapsedRail(SidebarDockPosition.left, settings, isDark, activeTheme),
                            ],

                            // 2. Main Document Viewer Body (IndexedStack preserves viewer state & page layout across switches)
                            Expanded(
                              child: IndexedStack(
                                index: _viewMode == ReaderViewMode.pdf ? 0 : 1,
                                children: [
                                  Column(
                                    children: [
                                      _buildPdfPageSummaryStrip(isDark),
                                      Expanded(
                                        child: Stack(
                                          children: [
                                            if (_isLoadingPdf)
                                              Center(
                                                child: _buildPdfLoadingWidget(
                                                  activeTheme,
                                                  isDark,
                                                  progress: _downloadProgress,
                                                  received: _downloadReceived,
                                                  total: _downloadTotal,
                                                ),
                                              )
                                            else if (_loadError != null)
                                              Center(
                                                child: _buildPdfErrorWidget(_loadError!, _fetchPdfData, activeTheme),
                                              )
                                            else if ((_useUriSource && _pdfUri != null) || _pdfBytes != null)
                                              _buildPdfViewer(canvasBg, pdfFilter, isDark),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_hasActivatedMarkdown)
                                    _buildMarkdownContent(context, activeTheme, isDark)
                                  else
                                    const SizedBox.shrink(),
                                ],
                              ),
                            ),

                            // 3. Right Sidebar (Desktop & Tablet only: !isMobile)
                            if (!isMobile) ...[
                              if (isRightSidebarOpen && rightDockedTabs.isNotEmpty)
                                ValueListenableBuilder<int>(
                                  valueListenable: _currentPageNotifier,
                                  builder: (context, curPage, _) => ReaderSidebar(
                                    position: SidebarDockPosition.right,
                                    outlineItems: _outlineItems,
                                    isOutlineLoading: _isOutlineLoading,
                                    searchQuery: _searchQuery,
                                    searchResults: _searchResults,
                                    isSearching: _isSearching,
                                    onSearchChanged: _onSearchQueryChanged,
                                    onClearSearch: () => setState(() {
                                      _searchQuery = '';
                                      _searchResults = [];
                                    }),
                                    onJumpToPage: _onJumpToPage,
                                    currentPage: curPage,
                                    totalPages: _totalPages > 0 ? _totalPages : (_doc.pageCount > 0 ? _doc.pageCount : 1),
                                    documentTitle: _doc.title,
                                    docId: _doc.id,
                                    onGetPageContext: _getPageContext,
                                    onZoomIn: _handleZoomIn,
                                    onZoomOut: _handleZoomOut,
                                    onResetZoom: _handleResetZoom,
                                    onFitWidth: _handleFitWidth,
                                    onDeleteAnnotation: _handleDeleteAnnotation,
                                    onAddNewNote: (page) => _openNewNoteDialogForPage(page),
                                  ),
                                )
                              else if (!isRightSidebarOpen && rightDockedTabs.isNotEmpty)
                                _buildCollapsedRail(SidebarDockPosition.right, settings, isDark, activeTheme),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Floating exit immersion button on mobile
                  if (isMobile && _isImmersiveMode)
                    Positioned(
                      bottom: 24,
                      right: 20,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => setState(() => _isImmersiveMode = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.black87 : Colors.white).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fullscreen_exit_rounded, size: 16, color: activeTheme.colorScheme.primary),
                                const SizedBox(width: 4),
                                const Text('退出沉浸', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildPdfLoadingWidget(
    ThemeData activeTheme,
    bool isDark, {
    double? progress,
    int? received,
    int? total,
  }) {
    return Container(
      width: 380,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        color: activeTheme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress != null)
            SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      activeTheme.colorScheme.primary,
                    ),
                    backgroundColor: activeTheme.colorScheme.primary.withValues(alpha: 0.15),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  activeTheme.colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            '正在载入《${widget.document.title}》',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    activeTheme.colorScheme.primary,
                  ),
                  backgroundColor: activeTheme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),
            ),
          Text(
            progress != null && total != null && total > 0 && received != null
                ? '正在极速传输: ${(received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB'
                : '正在流式准备渲染...',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPdfErrorWidget(String error, VoidCallback onRetry, ThemeData activeTheme) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: activeTheme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
          const SizedBox(height: 14),
          const Text(
            '文档加载失败',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 8),
          Text('错误原因: $error', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新载入'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer(Color canvasBg, ColorFilter? pdfFilter, bool isDark) {
    final settings = context.read<ReaderSettingsProvider>();
    final activeTheme = Theme.of(context);
    final reloadToken = '${_doc.id}_${_doc.ocrStatus}_${_doc.updatedAt.millisecondsSinceEpoch}';

    final viewerParams = PdfViewerParams(
      backgroundColor: Colors.transparent,
      margin: 16.0,
      calculateInitialPageNumber: (document, controller) => _currentPage.clamp(1, max(1, document.pages.length)),
      pageDropShadow: isDark
          ? const BoxShadow(color: Colors.transparent)
          : (settings.readingMode == ReadingMode.sepia
              ? const BoxShadow(
                  color: Color(0x335C3A10),
                  blurRadius: 6,
                  spreadRadius: 1,
                  offset: Offset(0, 2),
                )
              : const BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: Offset(0, 2),
                )),
      enableKeyboardNavigation: true,
      matchTextColor: Colors.amber.withValues(alpha: 0.5),
      activeMatchTextColor: Colors.orange.withValues(alpha: 0.8),
      pagePaintCallbacks: [
        (canvas, pageRect, page) => _paintPageAnnotations(canvas, pageRect, page, isDark: isDark),
      ],
      pageOverlaysBuilder: (viewerContext, pageRect, page) =>
          _buildPdfPageOverlays(viewerContext, pageRect, page),
      textSelectionParams: PdfTextSelectionParams(
        enabled: true,
        showContextMenuAutomatically: false,
        onTextSelectionChange: (textSelection) {
          if (settings.isStylusMode && _lastPointerDeviceKind == PointerDeviceKind.touch) {
            if (textSelection.hasSelectedText) {
              _pdfController.textSelectionDelegate.clearTextSelection();
            }
            return;
          }
          if (!textSelection.hasSelectedText) {
            if (_pdfActiveSelection != null && mounted) {
              setState(() => _pdfActiveSelection = null);
            }
          }
        },
      ),
      onInteractionStart: (details) {
        if (settings.isStylusMode &&
            (_currentInteractionDeviceKind == PointerDeviceKind.stylus ||
                _isStylusContacting ||
                _isPalmRejectionActive(true))) {
          _pdfController.stopInteractiveViewerAnimation();
          if (_stylusInteractionStartMatrix != null && _pdfController.isReady) {
            _pdfController.value = _stylusInteractionStartMatrix!;
          }
        }
      },
      onInteractionUpdate: (details) {
        if (settings.isStylusMode &&
            (_currentInteractionDeviceKind == PointerDeviceKind.stylus ||
                _isStylusContacting ||
                _isPalmRejectionActive(true))) {
          _pdfController.stopInteractiveViewerAnimation();
          if (_stylusInteractionStartMatrix != null && _pdfController.isReady) {
            _pdfController.value = _stylusInteractionStartMatrix!;
          }
        }
      },
      onInteractionEnd: (details) {
        if (settings.isStylusMode &&
            (_currentInteractionDeviceKind == PointerDeviceKind.stylus ||
                _isStylusContacting ||
                _isPalmRejectionActive(true))) {
          _pdfController.stopInteractiveViewerAnimation();
          if (_stylusInteractionStartMatrix != null && _pdfController.isReady) {
            _pdfController.value = _stylusInteractionStartMatrix!;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _pdfController.stopInteractiveViewerAnimation();
            if (_stylusInteractionStartMatrix != null && _pdfController.isReady) {
              _pdfController.value = _stylusInteractionStartMatrix!;
            }
          });
        }
      },
      onGeneralTap: (context, controller, details) {
        if (settings.isStylusMode) {
          final isTouch = _lastPointerDeviceKind == PointerDeviceKind.touch;
          if (isTouch) {
            if (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText) {
              _pdfController.textSelectionDelegate.clearTextSelection();
            }
            return true; // Suppress touch word selection, double-tap, long-press, context menus
          }
          if (_lastPointerDeviceKind == PointerDeviceKind.stylus ||
              _lastPointerDeviceKind == PointerDeviceKind.invertedStylus) {
            if (details.type == PdfViewerGeneralTapType.longPress) {
              if (details.tapOn == PdfViewerPart.background) {
                _handleSecondaryClick(details.localPosition, isTouch: true);
                return true;
              }
              return false; // Stylus long press on text selects word
            } else if (details.type == PdfViewerGeneralTapType.secondaryTap) {
              _handleSecondaryClick(details.localPosition, isTouch: false);
              return true;
            }
          }
        } else {
          if (details.type == PdfViewerGeneralTapType.longPress) {
            if (details.tapOn == PdfViewerPart.background) {
              _handleSecondaryClick(details.localPosition, isTouch: true);
              return true;
            }
            // Long press on nonSelectedText / selectedText: let pdfrx select word cleanly
            return false;
          } else if (details.type == PdfViewerGeneralTapType.secondaryTap) {
            _handleSecondaryClick(details.localPosition, isTouch: false);
            return true;
          }
        }
        return false;
      },
      buildContextMenu: (viewerContext, params) {
        params.dismissContextMenu();
        return null;
      },
      onPageChanged: (pageNumber) {
        if (pageNumber != null && _viewMode == ReaderViewMode.pdf) {
          _saveCurrentPage(pageNumber);
        }
      },
      onViewerReady: (document, controller) {
        if (mounted) {
          setState(() {
            _totalPages = document.pages.length;
          });
          if (controller.currentZoom > 0) {
            _basePdfZoom = controller.currentZoom;
          }
          context.read<ReaderSettingsProvider>().setZoomScale(1.0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentPage > 1 && controller.isReady) {
              controller.goToPage(pageNumber: _currentPage);
            }
          });
          _loadOutline();
        }
      },
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        final total = (totalBytes != null && totalBytes > 0) ? totalBytes : _doc.fileSize;
        final progress = (total > 0 && bytesDownloaded > 0) ? (bytesDownloaded / total).clamp(0.0, 1.0) : null;
        return Center(
          child: _buildPdfLoadingWidget(activeTheme, isDark, progress: progress, received: bytesDownloaded, total: total),
        );
      },
      errorBannerBuilder: (context, error, stackTrace, documentRef) {
        return Center(
          child: _buildPdfErrorWidget(error.toString(), _fetchPdfData, activeTheme),
        );
      },
    );

    Widget pdfViewerWidget;
    if (_useUriSource && _pdfUri != null) {
      pdfViewerWidget = PdfViewer.uri(
        _pdfUri!,
        key: ValueKey('uri_$reloadToken'),
        controller: _pdfController,
        preferRangeAccess: true,
        params: viewerParams,
      );
    } else {
      pdfViewerWidget = PdfViewer.data(
        _pdfBytes!,
        key: ValueKey('data_$reloadToken'),
        sourceName: reloadToken,
        controller: _pdfController,
        params: viewerParams,
      );
    }

    if (pdfFilter != null) {
      pdfViewerWidget = ColorFiltered(
        colorFilter: pdfFilter,
        child: pdfViewerWidget,
      );
    }

    return LayoutBuilder(
      builder: (viewerContext, constraints) {
        final isMobile = constraints.maxWidth < 700;
        _currentViewerSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            MouseRegion(
              cursor: MouseCursor.defer,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  final isStylus = event.kind == PointerDeviceKind.stylus ||
                      event.kind == PointerDeviceKind.invertedStylus;
                  final isTouch = event.kind == PointerDeviceKind.touch;

                  if (isTouch && _isPalmRejectionActive(settings.isStylusMode)) {
                    return; // Ignore palm touch completely
                  }

                  _lastPointerDeviceKind = event.kind;

                  final renderBox = viewerContext.findRenderObject() as RenderBox?;
                  final stackPos = renderBox != null
                      ? renderBox.globalToLocal(event.position)
                      : event.localPosition;

                  _isPointerDown = true;
                  _pointerDownGlobalPosition = event.position;
                  _currentPointerLocalPosition = stackPos;

                  if (isStylus) {
                    _currentInteractionDeviceKind = PointerDeviceKind.stylus;
                    _isStylusContacting = true;
                    _lastStylusContactTime = DateTime.now();
                    _pdfController.stopInteractiveViewerAnimation();
                    if (_pdfController.isReady) {
                      _stylusInteractionStartMatrix = _pdfController.value.clone();
                    }
                  } else if (isTouch) {
                    _currentInteractionDeviceKind = PointerDeviceKind.touch;
                    _stylusInteractionStartMatrix = null;
                  } else {
                    _currentInteractionDeviceKind = event.kind;
                    _stylusInteractionStartMatrix = null;
                  }

                  if (_arbitraryMenuState != null) {
                    setState(() => _arbitraryMenuState = null);
                  }

                  // Secondary click (mouse right-click or stylus side-button)
                  final isSecondary = event.buttons == kSecondaryMouseButton || (event.buttons & 32 != 0);
                  if (isSecondary) {
                    if (_pdfActiveSelection != null) {
                      setState(() => _pdfActiveSelection = null);
                    }
                    if (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText) {
                      _pdfController.textSelectionDelegate.clearTextSelection();
                    }
                    _wasSelectionActiveOnPointerDown = false;
                    _handleSecondaryClick(stackPos, isTouch: false);
                    return;
                  }

                  // Check if there was an active selection before this pointer down
                  final hadActiveSelection = _pdfActiveSelection != null ||
                      (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText);
                  _wasSelectionActiveOnPointerDown = hadActiveSelection;
                  // Note: Do NOT clear text selection here on pointer down,
                  // allowing selection handles to be freely dragged.
                  // Tap dismissals are cleanly handled onPointerUp.
                },
                onPointerMove: (event) {
                  final isStylus = event.kind == PointerDeviceKind.stylus ||
                      event.kind == PointerDeviceKind.invertedStylus;
                  final isTouch = event.kind == PointerDeviceKind.touch;

                  if (isTouch && _isPalmRejectionActive(settings.isStylusMode)) {
                    return;
                  }

                  final renderBox = viewerContext.findRenderObject() as RenderBox?;
                  final stackPos = renderBox != null
                      ? renderBox.globalToLocal(event.position)
                      : event.localPosition;

                  _currentPointerLocalPosition = stackPos;

                  if (isStylus) {
                    _lastStylusContactTime = DateTime.now();
                    if (_edgeScrollTicker == null || !_edgeScrollTicker!.isActive) {
                      if (_pdfController.isReady && _stylusInteractionStartMatrix != null) {
                        _pdfController.stopInteractiveViewerAnimation();
                        _pdfController.value = _stylusInteractionStartMatrix!;
                      }
                    }
                  } else if (isTouch && settings.isStylusMode) {
                    if (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText) {
                      _pdfController.textSelectionDelegate.clearTextSelection();
                    }
                  }

                  // Trigger edge auto-scroll during text selection or handle dragging
                  final isSelectingOrHandle = (settings.isStylusMode && isStylus) ||
                      (event.buttons == kPrimaryMouseButton) ||
                      _wasSelectionActiveOnPointerDown ||
                      (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText);

                  if (isSelectingOrHandle) {
                    _checkAndTriggerEdgeScroll(stackPos, _currentViewerSize);
                  }
                },
                onPointerCancel: (event) {
                  _isPointerDown = false;
                  _stopEdgeScrollTicker();

                  final isStylus = event.kind == PointerDeviceKind.stylus ||
                      event.kind == PointerDeviceKind.invertedStylus;
                  final isTouch = event.kind == PointerDeviceKind.touch;

                  if (isTouch && _isPalmRejectionActive(settings.isStylusMode)) {
                    return;
                  }

                  if (isStylus) {
                    _isStylusContacting = false;
                    _lastStylusContactTime = DateTime.now();
                    _pdfController.stopInteractiveViewerAnimation();
                    if (_stylusInteractionStartMatrix != null && _pdfController.isReady) {
                      _pdfController.value = _stylusInteractionStartMatrix!;
                    }
                  }
                  _wasSelectionActiveOnPointerDown = false;
                },
                onPointerUp: (event) async {
                  _isPointerDown = false;
                  _stopEdgeScrollTicker();

                  final isStylus = event.kind == PointerDeviceKind.stylus ||
                      event.kind == PointerDeviceKind.invertedStylus;
                  final isTouch = event.kind == PointerDeviceKind.touch;

                  if (isTouch && _isPalmRejectionActive(settings.isStylusMode)) {
                    return;
                  }

                  if (isStylus) {
                    _isStylusContacting = false;
                    _lastStylusContactTime = DateTime.now();
                    _pdfController.stopInteractiveViewerAnimation();
                    if (_stylusInteractionStartMatrix != null && _pdfController.isReady) {
                      _pdfController.value = _stylusInteractionStartMatrix!;
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _pdfController.stopInteractiveViewerAnimation();
                      if (_stylusInteractionStartMatrix != null && _pdfController.isReady) {
                        _pdfController.value = _stylusInteractionStartMatrix!;
                      }
                    });
                  }

                  // In stylus mode, finger touch should never trigger text selection floating bar
                  if (settings.isStylusMode && isTouch) {
                    if (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText) {
                      _pdfController.textSelectionDelegate.clearTextSelection();
                    }
                    _wasSelectionActiveOnPointerDown = false;
                    return;
                  }

                  final isTap = (event.position - _pointerDownGlobalPosition).distance < 10;
                  if (_wasSelectionActiveOnPointerDown && isTap) {
                    _wasSelectionActiveOnPointerDown = false;
                    if (_pdfActiveSelection != null) {
                      setState(() => _pdfActiveSelection = null);
                    }
                    if (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText) {
                      _pdfController.textSelectionDelegate.clearTextSelection();
                    }
                    return;
                  }
                  _wasSelectionActiveOnPointerDown = false;

                  final renderBox = viewerContext.findRenderObject() as RenderBox?;
                  final stackPos = renderBox != null
                      ? renderBox.globalToLocal(event.position)
                      : event.localPosition;

                  await Future.delayed(const Duration(milliseconds: 50));
                  if (!mounted) return;
                  if (_pdfController.isReady && _pdfController.textSelectionDelegate.hasSelectedText) {
                    final text = await _pdfController.textSelectionDelegate.getSelectedText();
                    final ranges = await _pdfController.textSelectionDelegate.getSelectedTextRanges();
                    if (text.trim().isNotEmpty && ranges.isNotEmpty && mounted) {
                      setState(() {
                        _pdfActiveSelection = PdfActiveSelectionState(
                          text: text,
                          ranges: ranges,
                          position: stackPos,
                        );
                      });
                    }
                  }
                },
                child: pdfViewerWidget,
              ),
            ),
            if (_pdfActiveSelection != null)
              _buildPositionedFloatingBar(
                context: context,
                pointerPos: _pdfActiveSelection!.position,
                containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                isMobile: isMobile,
                child: Material(
                  type: MaterialType.transparency,
                  child: FloatingSelectionBar(
                    selectedText: _pdfActiveSelection!.text,
                    readingMode: settings.readingMode,
                    isMobile: isMobile,
                    onHighlight: (colorHex) {
                      final sel = _pdfActiveSelection;
                      if (sel != null) {
                        setState(() => _pdfActiveSelection = null);
                        _createHighlightFromSelection(
                          colorHex: colorHex,
                          selectedText: sel.text,
                          textRanges: sel.ranges,
                        );
                        _pdfController.textSelectionDelegate.clearTextSelection();
                      }
                    },
                    onAddNote: () {
                      final sel = _pdfActiveSelection;
                      if (sel != null) {
                        setState(() => _pdfActiveSelection = null);
                        final firstRange = sel.ranges.first;
                        final pageNum = firstRange.pageNumber;
                        final tempAnno = PdfAnnotation(
                          id: _uuid.v4(),
                          docId: widget.document.id,
                          type: "note",
                          pageNumber: pageNum,
                          colorHex: "#6366F1",
                          rects: const [],
                          selectedText: sel.text,
                          noteContent: "",
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        );

                        showDialog(
                          context: context,
                          builder: (ctx) => NoteEditorDialog(
                            annotation: tempAnno,
                            onSave: (saved) {
                              _createNoteFromSelection(
                                selectedText: sel.text,
                                textRanges: sel.ranges,
                                noteContent: saved.noteContent,
                              );
                            },
                            onDelete: () {},
                          ),
                        );
                        _pdfController.textSelectionDelegate.clearTextSelection();
                      }
                    },
                    onAskAi: () {
                      final sel = _pdfActiveSelection;
                      if (sel != null) {
                        final pageNum = sel.ranges.isNotEmpty ? sel.ranges.first.pageNumber : _currentPage;
                        setState(() => _pdfActiveSelection = null);
                        _handleAskAi(sel.text, pageNum);
                        _pdfController.textSelectionDelegate.clearTextSelection();
                      }
                    },
                    onDismiss: () {
                      setState(() => _pdfActiveSelection = null);
                      _pdfController.textSelectionDelegate.clearTextSelection();
                    },
                  ),
                ),
              ),
            if (_arbitraryMenuState != null)
              _buildPositionedArbitraryMenu(
                context: context,
                menuState: _arbitraryMenuState!,
                containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                isMobile: isMobile,
                readingMode: settings.readingMode,
              ),
          ],
        );
      },
    );
  }

  Widget _buildMarkdownContent(BuildContext context, ThemeData theme, bool isDark) {
    if (_isLoadingMarkdown) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '正在提取并解析 Markdown 结构...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                '正在渲染多级标题、代码块与 LaTeX 数学公式',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_markdownError != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
              const SizedBox(height: 14),
              const Text(
                'Markdown 加载失败',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              Text('错误原因: $_markdownError', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试加载'),
                onPressed: () => _fetchMarkdownData(forceReload: true),
              ),
            ],
          ),
        ),
      );
    }

    if (_markdownContent != null && _markdownContent!.trim().isNotEmpty) {
      return MarkdownReaderView(
        key: _markdownKey,
        document: _doc,
        markdownContent: _markdownContent!,
        currentPage: _currentPage,
        onPageChanged: (page) {
          _saveCurrentPage(page);
        },
        onOpenOcr: _showOcrDialog,
        onMarkdownUpdated: (newMd) {
          setState(() {
            _markdownContent = newMd;
          });
        },
        onAskAi: _handleAskAi,
      );
    }

    return _buildEmptyMarkdownView(context, theme, isDark);
  }

  Widget _buildEmptyMarkdownView(BuildContext context, ThemeData theme, bool isDark) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withValues(alpha: isDark ? 0.2 : 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 40,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '尚未生成 Markdown 文档',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '当前文档尚未提取 Markdown 结构内容。使用百度 PaddleOCR-VL 识别引擎，可自动提取排版、多级标题、表格并完美渲染 LaTeX 数学公式。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text(
                '执行 PaddleOCR-VL 解析 (生成 MD)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              onPressed: _showOcrDialog,
            ),
          ],
        ),
      ),
    );
  }
}
