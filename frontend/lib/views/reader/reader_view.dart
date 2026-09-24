import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart' hide PdfAnnotation;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/annotation_model.dart';
import '../../models/document_model.dart';
import '../../providers/annotation_provider.dart';
import '../../providers/document_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../theme/app_theme.dart';
import 'components/annotation_sidebar.dart';
import 'components/floating_selection_bar.dart';
import 'components/note_editor_dialog.dart';
import 'components/ocr_dialog.dart';
import 'components/page_jump_dialog.dart';
import 'components/reader_top_bar.dart';

class PdfReaderScreen extends StatefulWidget {
  final DocumentModel document;

  const PdfReaderScreen({super.key, required this.document});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  late PdfViewerController _pdfController;
  late DocumentModel _doc;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isDocumentLoaded = false;
  Uint8List? _pdfBytes;
  bool _isLoadingPdf = true;
  String? _loadError;
  bool _isOcrBannerDismissed = false;
  OcrStatusInfo? _ocrStatusInfo;
  Timer? _ocrPollTimer;
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _doc = widget.document;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnnotationProvider>().loadAnnotations(_doc.id);
      final lastPage = context.read<DocumentProvider>().storageService.getLastReadPage(_doc.id);
      if (lastPage > 1) {
        _currentPage = lastPage;
      }
      _fetchPdfData();

      if (_doc.ocrStatus == "processing") {
        _startPollingOcr();
      }
    });
  }

  @override
  void dispose() {
    _ocrPollTimer?.cancel();
    super.dispose();
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
          _doc = _doc.copyWith(hasTextLayer: true, ocrStatus: "completed");
        }
      });

      if (statusInfo.isCompleted) {
        timer.cancel();
        await _fetchPdfData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                  SizedBox(width: 8),
                  Text('双层可检索 PDF 转换成功！已支持划词高亮与数学公式。'),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else if (statusInfo.isFailed) {
        timer.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('OCR 转换失败: ${statusInfo.error ?? "未知错误"}'),
              backgroundColor: Colors.red.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  Future<void> _fetchPdfData() async {
    setState(() {
      _isLoadingPdf = true;
      _loadError = null;
    });

    try {
      final storage = context.read<DocumentProvider>().storageService;
      final rawUrl = _doc.getFileUrl(storage.getBaseUrl());
      final separator = rawUrl.contains('?') ? '&' : '?';
      final fileUrl = '$rawUrl${separator}t=${DateTime.now().millisecondsSinceEpoch}';
      final uri = Uri.parse(fileUrl);

      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 || response.statusCode == 206) {
        if (mounted) {
          setState(() {
            _pdfBytes = response.bodyBytes;
            _isLoadingPdf = false;
          });
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
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
            _fetchPdfData();
          }
        },
      ),
    );
  }

  void _saveCurrentPage(int page) {
    if (page >= 1) {
      setState(() => _currentPage = page);
      context.read<DocumentProvider>().storageService.setLastReadPage(_doc.id, page);
    }
  }

  void _onJumpToPage(int page) {
    if (_pdfController.isReady) {
      _pdfController.goToPage(pageNumber: page);
      _saveCurrentPage(page);
    }
  }

  void _createHighlightFromSelection({
    required String colorHex,
    required String selectedText,
    required List<PdfPageTextRange> textRanges,
    String noteContent = "",
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
      type: noteContent.isNotEmpty ? "note" : "highlight",
      pageNumber: pageNumber,
      colorHex: colorHex,
      rects: normalizedRects,
      selectedText: selectedText,
      noteContent: noteContent,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    context.read<AnnotationProvider>().addAnnotation(newAnno);
    context.read<DocumentProvider>().updateAnnotationCount(widget.document.id, 1);
  }

  void _paintPageAnnotations(Canvas canvas, Rect pageRect, PdfPage page, {bool isDark = false}) {
    final annoProvider = context.read<AnnotationProvider>();
    final settings = context.read<ReaderSettingsProvider>();
    if (!settings.showAnnotations) return;

    final pageAnnos = annoProvider.getAnnotationsForPage(page.pageNumber);
    if (pageAnnos.isEmpty) return;

    final focusedId = annoProvider.focusedAnnotationId;

    for (final anno in pageAnnos) {
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

      if (anno.isNote && anno.rects.isNotEmpty) {
        final firstNorm = anno.rects.first;
        final pdfRect = PdfRect(
          firstNorm.x * page.width,
          (firstNorm.y + firstNorm.height) * page.height,
          (firstNorm.x + firstNorm.width) * page.width,
          firstNorm.y * page.height,
        );
        final firstScreenRect = pdfRect.toRectInDocument(page: page, pageRect: pageRect);

        final pinCenter = Offset(firstScreenRect.right + 4, firstScreenRect.top);
        final pinPaint = Paint()
          ..color = AppTheme.getHighlightColorForRendering(anno.colorHex, isDark: isDark, alpha: 1.0)
          ..style = PaintingStyle.fill;

        canvas.drawCircle(pinCenter, 5.0, pinPaint);
        canvas.drawCircle(
          pinCenter,
          5.0,
          Paint()
            ..color = isDark ? Colors.white70 : Colors.black45
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      }
    }
  }

  Widget? _buildContextMenu(BuildContext context, PdfViewerContextMenuBuilderParams params) {
    if (!params.isTextSelectionEnabled) return null;

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        params.textSelectionDelegate.getSelectedText(),
        params.textSelectionDelegate.getSelectedTextRanges(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final selectedText = (snapshot.data![0] as String?) ?? '';
        final ranges = (snapshot.data![1] as List<PdfPageTextRange>?) ?? [];
        if (selectedText.trim().isEmpty || ranges.isEmpty) {
          return const SizedBox.shrink();
        }

        Widget floatingBar = FloatingSelectionBar(
          selectedText: selectedText,
          onHighlight: (colorHex) {
            _createHighlightFromSelection(
              colorHex: colorHex,
              selectedText: selectedText,
              textRanges: ranges,
            );
            params.dismissContextMenu();
          },
          onAddNote: () {
            final firstRange = ranges.first;
            final pageNum = firstRange.pageNumber;
            final tempAnno = PdfAnnotation(
              id: _uuid.v4(),
              docId: widget.document.id,
              pageNumber: pageNum,
              rects: [],
              selectedText: selectedText,
              noteContent: "",
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

            showDialog(
              context: context,
              builder: (ctx) => NoteEditorDialog(
                annotation: tempAnno,
                onSave: (saved) {
                  _createHighlightFromSelection(
                    colorHex: saved.colorHex,
                    selectedText: selectedText,
                    textRanges: ranges,
                    noteContent: saved.noteContent,
                  );
                },
                onDelete: () {},
              ),
            );
            params.dismissContextMenu();
          },
          onDismiss: () {
            params.dismissContextMenu();
          },
        );

        final settings = context.read<ReaderSettingsProvider>();
        if (settings.readingMode == ReadingMode.dark) {
          floatingBar = ColorFiltered(
            colorFilter: AppTheme.darkPdfInverseColorFilter,
            child: floatingBar,
          );
        } else if (settings.readingMode == ReadingMode.sepia) {
          floatingBar = ColorFiltered(
            colorFilter: AppTheme.sepiaPdfInverseColorFilter,
            child: floatingBar,
          );
        }

        return floatingBar;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ReaderSettingsProvider>();
    final isDark = settings.readingMode == ReadingMode.dark;

    ThemeData activeTheme;
    switch (settings.readingMode) {
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

    final canvasBg = AppTheme.getReaderBgColor(settings.readingMode);

    // Color filter for dark mode and sepia mode
    ColorFilter? pdfFilter;
    if (settings.readingMode == ReadingMode.dark) {
      pdfFilter = AppTheme.darkPdfColorFilter;
    } else if (settings.readingMode == ReadingMode.sepia) {
      pdfFilter = AppTheme.sepiaPdfColorFilter;
    }

    return Theme(
      data: activeTheme,
      child: Scaffold(
        backgroundColor: canvasBg,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar
              ReaderTopBar(
                document: _doc,
                ocrProgress: _ocrStatusInfo,
                currentPage: _currentPage,
                totalPages: _totalPages,
                onJumpToPage: _onJumpToPage,
                onOpenOcr: _showOcrDialog,
                onZoomIn: () {
                  if (_pdfController.isReady) {
                    _pdfController.zoomUp();
                    settings.setZoomScale(_pdfController.currentZoom);
                  }
                },
                onZoomOut: () {
                  if (_pdfController.isReady) {
                    _pdfController.zoomDown();
                    settings.setZoomScale(_pdfController.currentZoom);
                  }
                },
                onResetZoom: () {
                  if (_pdfController.isReady) {
                    _pdfController.setZoom(_pdfController.centerPosition, 1.0);
                    settings.setZoomScale(1.0);
                  }
                },
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

              // Scanned / Image PDF OCR Banner (Only when not started and text layer missing)
              if (!_doc.hasTextLayer && _doc.ocrStatus != 'completed' && _doc.ocrStatus != 'processing' && !_isOcrBannerDismissed)
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
                          '提示：当前为扫描版/纯图片 PDF，暂无内嵌文字。一键转换为双层可检索 PDF (OCR) 即可开启鼠标划词与荧光高亮！',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text('生成双层PDF'),
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

              // Main PDF Viewer Area
              Expanded(
                child: Row(
                  children: [
                    // PDF Canvas
                    Expanded(
                      child: Stack(
                        children: [
                          if (_isLoadingPdf)
                            Center(
                              child: Container(
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
                                      '正在载入《${widget.document.title}》...',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '文件大小 ${widget.document.formattedSize} • 正在准备 WebAssembly 渲染',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (_loadError != null)
                            Center(
                              child: Container(
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
                                    Text('错误原因: $_loadError', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    const SizedBox(height: 18),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('重新载入'),
                                      onPressed: _fetchPdfData,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (_pdfBytes != null)
                            _buildPdfViewer(canvasBg, pdfFilter, isDark),

                          // Bottom Floating Capsule Toolbar
                          if (_isDocumentLoaded && _totalPages > 0)
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0F172A).withValues(alpha: 0.92)
                                        : Colors.white.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.keyboard_arrow_left_rounded, size: 22),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        tooltip: '上一页',
                                        onPressed: _currentPage > 1 ? () => _onJumpToPage(_currentPage - 1) : null,
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => PageJumpDialog(
                                              currentPage: _currentPage,
                                              totalPages: _totalPages,
                                              onJump: _onJumpToPage,
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          child: Text(
                                            '$_currentPage / $_totalPages 页',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.keyboard_arrow_right_rounded, size: 22),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        tooltip: '下一页',
                                        onPressed: _currentPage < _totalPages ? () => _onJumpToPage(_currentPage + 1) : null,
                                      ),
                                      Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 8),
                                        width: 1,
                                        height: 18,
                                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.fit_screen_rounded, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        tooltip: '适应宽度',
                                        onPressed: () {
                                          if (_pdfController.isReady) {
                                            final m = _pdfController.calcMatrixFitWidthForPage(pageNumber: _currentPage);
                                            if (m != null) {
                                              _pdfController.goTo(m);
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Right Drawer: Annotations
                    if (settings.isSidebarOpen)
                      AnnotationSidebar(
                        onJumpToPage: (page) {
                          _onJumpToPage(page);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPdfViewer(Color canvasBg, ColorFilter? pdfFilter, bool isDark) {
    final settings = context.read<ReaderSettingsProvider>();
    Widget viewer = PdfViewer.data(
      _pdfBytes!,
      key: ValueKey('${_doc.id}_${_doc.ocrStatus}_${_pdfBytes?.length}'),
      sourceName: '${_doc.id}_${_doc.ocrStatus}_${_pdfBytes?.length}',
      controller: _pdfController,
      params: PdfViewerParams(
        backgroundColor: Colors.transparent,
        margin: 16.0,
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
        buildContextMenu: _buildContextMenu,
        textSelectionParams: const PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: true,
        ),
        onPageChanged: (pageNumber) {
          if (pageNumber != null) {
            _saveCurrentPage(pageNumber);
          }
        },
        onViewerReady: (document, controller) {
          if (mounted) {
            setState(() {
              _totalPages = document.pages.length;
              _isDocumentLoaded = true;
            });
            if (_currentPage > 1) {
              controller.goToPage(pageNumber: _currentPage);
            }
          }
        },
      ),
    );

    if (pdfFilter != null) {
      viewer = ColorFiltered(
        colorFilter: pdfFilter,
        child: viewer,
      );
    }

    return viewer;
  }
}
