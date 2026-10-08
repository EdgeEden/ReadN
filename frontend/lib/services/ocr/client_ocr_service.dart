import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ClientOcrService {
  static const String defaultApiUrl = 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs';
  static const String defaultModelName = 'PaddleOCR-VL-1.6';
  static const String defaultBaiduToken = 'REDACTED_BAIDU_TOKEN';

  static const Map<String, dynamic> defaultOptionalPayload = {
    'markdownIgnoreLabels': [
      'header',
      'header_image',
      'footer',
      'footer_image',
      'number',
      'footnote',
      'aside_text'
    ],
    'useDocOrientationClassify': false,
    'useDocUnwarping': false,
    'useLayoutDetection': true,
    'useChartRecognition': false,
    'useSealRecognition': true,
    'useOcrForImageBlock': false,
    'mergeTables': true,
    'relevelTitles': true,
    'layoutShapeMode': 'auto',
    'promptLabel': 'ocr',
    'repetitionPenalty': 1,
    'temperature': 0,
    'topP': 1,
    'minPixels': 147384,
    'maxPixels': 2822400,
    'layoutNms': true,
    'restructurePages': true
  };

  /// Prepares sub-PDF bytes containing only the requested target pages (1-indexed).
  /// If targetPages is null or covers all pages, returns the full PDF bytes directly.
  Future<Uint8List> prepareSubPdf(Uint8List fullPdfBytes, List<int>? targetPages, int totalPages) async {
    if (targetPages == null || targetPages.isEmpty) {
      return fullPdfBytes;
    }

    final activePages = targetPages.where((p) => p >= 1 && p <= totalPages).toSet();
    if (activePages.length >= totalPages || activePages.isEmpty) {
      return fullPdfBytes;
    }

    final doc = PdfDocument(inputBytes: fullPdfBytes);
    try {
      final docCount = doc.pages.count;
      for (int i = docCount - 1; i >= 0; i--) {
        final pageNum = i + 1;
        if (!activePages.contains(pageNum)) {
          doc.pages.removeAt(i);
        }
      }
      final List<int> subBytes = await doc.save();
      return Uint8List.fromList(subBytes);
    } finally {
      doc.dispose();
    }
  }

  /// Submits the OCR job to Baidu AI Studio PaddleOCR-VL API.
  Future<String> submitJob({
    required Uint8List pdfBytes,
    required String apiToken,
    String apiUrl = defaultApiUrl,
    String modelName = defaultModelName,
    Map<String, dynamic>? optionalPayload,
  }) async {
    var cleanToken = apiToken.trim();
    if (cleanToken.toLowerCase().startsWith('bearer ')) {
      cleanToken = cleanToken.substring(7).trim();
    }

    final payload = Map<String, dynamic>.from(defaultOptionalPayload);
    if (optionalPayload != null) {
      payload.addAll(optionalPayload);
    }

    final uri = Uri.parse(apiUrl);
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'bearer $cleanToken';
    request.fields['model'] = modelName;
    request.fields['optionalPayload'] = jsonEncode(payload);
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        pdfBytes,
        filename: 'ocr_target.pdf',
        contentType: MediaType('application', 'pdf'),
      ),
    );

    final streamedResponse = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('百度 PaddleOCR 提交失败 (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['code'] != 0 || data['data'] == null || data['data']['jobId'] == null) {
      final msg = data['msg'] ?? response.body;
      throw Exception('百度 PaddleOCR API 响应错误: $msg');
    }

    return data['data']['jobId'] as String;
  }

  /// Polls the Baidu OCR job until completed, failed, or cancelled.
  Future<String> pollJobProgress({
    required String jobId,
    required String apiToken,
    String apiUrl = defaultApiUrl,
    required int targetPagesCount,
    void Function(double progress, String message, int currentPage, int totalPages)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var cleanToken = apiToken.trim();
    if (cleanToken.toLowerCase().startsWith('bearer ')) {
      cleanToken = cleanToken.substring(7).trim();
    }

    const maxRetries = 150; // 150 * 2s = 300s
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      if (isCancelled?.call() == true) {
        throw Exception('OCR 任务已取消');
      }

      await Future.delayed(const Duration(seconds: 2));

      if (isCancelled?.call() == true) {
        throw Exception('OCR 任务已取消');
      }

      final uri = Uri.parse('$apiUrl/$jobId');
      final res = await http.get(
        uri,
        headers: {'Authorization': 'bearer $cleanToken'},
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        continue;
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? {};
      final state = data['state'] as String? ?? 'pending';
      final extractProgress = data['extractProgress'] as Map<String, dynamic>? ?? {};
      final extractedPages = (extractProgress['extractedPages'] as num?)?.toInt() ?? 0;
      final totalPages = (extractProgress['totalPages'] as num?)?.toInt() ?? targetPagesCount;

      if (state == 'pending') {
        onProgress?.call(
          0.20,
          '百度星河 PaddleOCR-VL 云端任务排队中...',
          0,
          targetPagesCount,
        );
      } else if (state == 'running') {
        final double prog = 0.20 + 0.70 * (extractedPages / (totalPages > 0 ? totalPages : 1));
        onProgress?.call(
          prog.clamp(0.20, 0.90),
          '百度 PaddleOCR 正在识别第 $extractedPages/$totalPages 页 (排版、表格与公式)...',
          extractedPages,
          totalPages,
        );
      } else if (state == 'done') {
        onProgress?.call(
          0.95,
          '识别完成，正在解析 Markdown 内容与数学公式...',
          targetPagesCount,
          targetPagesCount,
        );

        final resultUrlObj = data['resultUrl'];
        if (resultUrlObj is Map) {
          final url = resultUrlObj['jsonUrl'] ?? resultUrlObj['jsonlUrl'];
          if (url != null) return url.toString();
        } else if (resultUrlObj is String && resultUrlObj.isNotEmpty) {
          return resultUrlObj;
        }
        throw Exception('未从百度 PaddleOCR 识别结果中获取到有效的结果下载链接');
      } else if (state == 'failed') {
        final err = data['errorMsg'] ?? '未知错误';
        throw Exception('百度 PaddleOCR 任务失败: $err');
      }
    }

    throw Exception('百度 PaddleOCR 识别超时，请检查网络或稍后重试');
  }

  /// Downloads and parses the recognition result JSON/JSONL, mapping activePages to Markdown texts.
  Future<Map<int, String>> downloadAndParseResults(String resultUrl, List<int> activePages) async {
    final res = await http.get(Uri.parse(resultUrl)).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw Exception('获取百度 OCR 结果文件失败 (${res.statusCode})');
    }

    final text = utf8.decode(res.bodyBytes).trim();
    final List<dynamic> pageResults = [];

    final lines = const LineSplitter().convert(text);
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final lineData = jsonDecode(trimmed);
        if (lineData is Map<String, dynamic>) {
          final result = lineData['result'];
          if (result is Map && result['layoutParsingResults'] is List) {
            pageResults.addAll(result['layoutParsingResults'] as List);
          } else if (lineData['layoutParsingResults'] is List) {
            pageResults.addAll(lineData['layoutParsingResults'] as List);
          } else if (lineData.containsKey('prunedResult') || lineData.containsKey('markdown')) {
            pageResults.add(lineData);
          }
        }
      } catch (_) {}
    }

    if (pageResults.isEmpty) {
      try {
        final dataObj = jsonDecode(text);
        if (dataObj is Map && dataObj['result'] is Map && dataObj['result']['layoutParsingResults'] is List) {
          pageResults.addAll(dataObj['result']['layoutParsingResults'] as List);
        } else if (dataObj is List) {
          pageResults.addAll(dataObj);
        }
      } catch (_) {}
    }

    final Map<int, String> resultMap = {};
    for (int i = 0; i < activePages.length; i++) {
      final pageNum = activePages[i];
      if (i < pageResults.length) {
        final item = pageResults[i];
        String mdText = '';
        if (item is Map) {
          if (item['markdown'] is Map) {
            mdText = item['markdown']['text']?.toString() ?? '';
          } else if (item['text'] != null) {
            mdText = item['text'].toString();
          }
        }
        resultMap[pageNum] = mdText;
      }
    }

    return resultMap;
  }

  /// Merges newly parsed page markdowns with existing markdown preserving <!-- Page X --> structure.
  String mergeWithExistingMarkdown(String? existingMarkdown, Map<int, String> newPagesMap) {
    final Map<int, String> pagesDict = {};

    if (existingMarkdown != null && existingMarkdown.trim().isNotEmpty) {
      final pageRegex = RegExp(r'<!--\s*Page\s+(\d+)\s*-->', caseSensitive: false);
      final matches = pageRegex.allMatches(existingMarkdown).toList();

      if (matches.isNotEmpty) {
        for (int i = 0; i < matches.length; i++) {
          final pageNum = int.tryParse(matches[i].group(1) ?? '');
          if (pageNum == null) continue;

          final contentStart = matches[i].end;
          final contentEnd = (i + 1 < matches.length) ? matches[i + 1].start : existingMarkdown.length;
          final content = existingMarkdown.substring(contentStart, contentEnd).trim();
          pagesDict[pageNum] = content;
        }
      }
    }

    // Merge/overwrite new pages
    for (final entry in newPagesMap.entries) {
      if (entry.value.trim().isNotEmpty) {
        pagesDict[entry.key] = entry.value.trim();
      }
    }

    if (pagesDict.isEmpty) {
      return '';
    }

    final sortedPageNumbers = pagesDict.keys.toList()..sort();
    final buffer = StringBuffer();
    for (int i = 0; i < sortedPageNumbers.length; i++) {
      final pageNum = sortedPageNumbers[i];
      buffer.writeln('<!-- Page $pageNum -->');
      buffer.writeln();
      buffer.write(pagesDict[pageNum]);
      if (i < sortedPageNumbers.length - 1) {
        buffer.writeln();
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Complete high-level execution flow for client-side direct OCR.
  Future<String> executeClientOcr({
    required Uint8List fullPdfBytes,
    required int totalDocPages,
    List<int>? targetPages,
    required String apiToken,
    String apiUrl = defaultApiUrl,
    String modelName = defaultModelName,
    bool useDocOrientationClassify = false,
    bool useDocUnwarping = false,
    bool useChartRecognition = false,
    String? existingMarkdown,
    void Function(double progress, String message, int currentPage, int totalPages)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // 1. Resolve active pages (1-indexed)
    final List<int> activePages;
    if (targetPages == null || targetPages.isEmpty) {
      activePages = List.generate(totalDocPages, (i) => i + 1);
    } else {
      activePages = targetPages.where((p) => p >= 1 && p <= totalDocPages).toSet().toList()..sort();
    }

    if (activePages.isEmpty) {
      throw Exception('目标页码范围无效');
    }

    onProgress?.call(0.05, '正在准备文档页面与切片...', 0, activePages.length);

    // 2. Prepare sub-PDF if selective page range
    final pdfBytesToUpload = await prepareSubPdf(fullPdfBytes, targetPages, totalDocPages);

    if (isCancelled?.call() == true) throw Exception('OCR 任务已取消');

    onProgress?.call(0.12, '正在上传文档至百度 AI Studio 星河平台...', 0, activePages.length);

    // 3. Submit OCR job
    final jobId = await submitJob(
      pdfBytes: pdfBytesToUpload,
      apiToken: apiToken,
      apiUrl: apiUrl,
      modelName: modelName,
      optionalPayload: {
        'useDocOrientationClassify': useDocOrientationClassify,
        'useDocUnwarping': useDocUnwarping,
        'useChartRecognition': useChartRecognition,
      },
    );

    // 4. Poll job until completion
    final resultUrl = await pollJobProgress(
      jobId: jobId,
      apiToken: apiToken,
      apiUrl: apiUrl,
      targetPagesCount: activePages.length,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );

    // 5. Download and parse results
    onProgress?.call(0.96, '正在提取 Markdown 标题、LaTeX 公式与表格...', activePages.length, activePages.length);
    final pageMarkdownMap = await downloadAndParseResults(resultUrl, activePages);

    // 6. Merge with existing Markdown
    final mergedMarkdown = mergeWithExistingMarkdown(existingMarkdown, pageMarkdownMap);
    if (mergedMarkdown.isEmpty) {
      throw Exception('未从百度 OCR 识别结果中提取到有效 Markdown 内容');
    }

    onProgress?.call(1.0, '解析完成，已就绪结构化 Markdown 文档！', activePages.length, activePages.length);
    return mergedMarkdown;
  }
}
