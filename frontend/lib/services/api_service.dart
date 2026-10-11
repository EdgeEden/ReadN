import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/document_model.dart';
import '../models/annotation_model.dart';
import 'storage_service.dart';

class ApiService {
  final StorageService storageService;
  final http.Client _client = http.Client();

  ApiService({required this.storageService});

  String get baseUrl => storageService.getBaseUrl();

  Uri _uri(String path) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$cleanBase$cleanPath');
  }

  Future<http.Response> _executeWithRetry(
    Future<http.Response> Function(http.Client client) action,
  ) async {
    try {
      return await action(_client);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('connection closed') ||
          msg.contains('connection reset') ||
          msg.contains('connection refused') ||
          msg.contains('broken pipe') ||
          msg.contains('socketexception') ||
          msg.contains('clientexception')) {
        // Stale pooled connection dropped by remote server/NAT. Retry once with a fresh client.
        final freshClient = http.Client();
        try {
          return await action(freshClient);
        } finally {
          freshClient.close();
        }
      }
      rethrow;
    }
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      _executeWithRetry((c) => c.get(uri, headers: headers));

  Future<http.Response> _post(Uri uri, {Map<String, String>? headers, Object? body}) =>
      _executeWithRetry((c) => c.post(uri, headers: headers, body: body));

  Future<http.Response> _put(Uri uri, {Map<String, String>? headers, Object? body}) =>
      _executeWithRetry((c) => c.put(uri, headers: headers, body: body));

  Future<http.Response> _patch(Uri uri, {Map<String, String>? headers, Object? body}) =>
      _executeWithRetry((c) => c.patch(uri, headers: headers, body: body));

  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers, Object? body}) =>
      _executeWithRetry((c) => c.delete(uri, headers: headers, body: body));

  Future<bool> checkHealth() async {
    try {
      final res = await _get(_uri('/api/health')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<DocumentModel> uploadDocument({
    required List<int> fileBytes,
    required String filename,
  }) async {
    final uri = _uri('/api/documents/upload');
    final request = http.MultipartRequest('POST', uri);
    
    final multipartFile = http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
    );
    request.files.add(multipartFile);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return DocumentModel.fromJson(json);
    } else {
      throw Exception('Upload failed: ${response.statusCode} - ${response.body}');
    }
  }

  Future<List<DocumentModel>> getDocuments() async {
    final res = await _get(_uri('/api/documents'));
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(res.bodyBytes));
      return list.map((item) => DocumentModel.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to fetch documents: ${res.statusCode}');
    }
  }

  Future<DocumentModel> getDocument(String docId) async {
    final res = await _get(_uri('/api/documents/$docId'));
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return DocumentModel.fromJson(json);
    } else {
      throw Exception('Failed to fetch document $docId: ${res.statusCode}');
    }
  }

  Future<DocumentModel> updateDocumentTitle(String docId, String newTitle) async {
    final res = await _patch(
      _uri('/api/documents/$docId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'title': newTitle}),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return DocumentModel.fromJson(json);
    } else {
      throw Exception('Failed to update document: ${res.statusCode}');
    }
  }

  Future<void> deleteDocument(String docId) async {
    final res = await _delete(_uri('/api/documents/$docId'));
    if (res.statusCode != 200 && res.statusCode != 204 && res.statusCode != 404) {
      throw Exception('Failed to delete document: ${res.statusCode}');
    }
  }

  String getDocumentFileUrl(String docId) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$cleanBase/api/documents/$docId/file';
  }

  Future<Uint8List> downloadDocumentBytes(
    String docId, {
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', _uri('/api/documents/$docId/file'));
    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 206) {
      throw Exception('Failed to download document: ${streamedResponse.statusCode}');
    }
    final total = streamedResponse.contentLength ?? 0;
    int received = 0;
    final bytesBuilder = BytesBuilder(copy: false);
    await for (final chunk in streamedResponse.stream) {
      bytesBuilder.add(chunk);
      received += chunk.length;
      if (onProgress != null && total > 0) {
        onProgress(received, total);
      }
    }
    return bytesBuilder.takeBytes();
  }

  // Annotations
  Future<List<PdfAnnotation>> getAnnotations(String docId) async {
    final res = await _get(_uri('/api/documents/$docId/annotations'));
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(res.bodyBytes));
      return list.map((item) => PdfAnnotation.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to fetch annotations: ${res.statusCode}');
    }
  }

  Future<PdfAnnotation> createAnnotation(String docId, PdfAnnotation annotation) async {
    final payload = {
      'id': annotation.id,
      'type': annotation.type,
      'page_number': annotation.pageNumber,
      'color_hex': annotation.colorHex,
      'rects': annotation.rects.map((r) => r.toJson()).toList(),
      'selected_text': annotation.selectedText,
      'note_content': annotation.noteContent,
    };
    final res = await _post(
      _uri('/api/documents/$docId/annotations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return PdfAnnotation.fromJson(json);
    } else {
      throw Exception('Failed to create annotation: ${res.statusCode} - ${res.body}');
    }
  }

  Future<PdfAnnotation> updateAnnotation(
    String docId,
    String annotationId, {
    String? colorHex,
    String? noteContent,
    String? selectedText,
    String? type,
    List<NormalizedRect>? rects,
  }) async {
    final Map<String, dynamic> payload = {};
    if (colorHex != null) payload['color_hex'] = colorHex;
    if (noteContent != null) payload['note_content'] = noteContent;
    if (selectedText != null) payload['selected_text'] = selectedText;
    if (type != null) payload['type'] = type;
    if (rects != null) payload['rects'] = rects.map((r) => r.toJson()).toList();

    final res = await _put(
      _uri('/api/documents/$docId/annotations/$annotationId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return PdfAnnotation.fromJson(json);
    } else {
      throw Exception('Failed to update annotation: ${res.statusCode}');
    }
  }

  Future<void> deleteAnnotation(String docId, String annotationId) async {
    final res = await _delete(_uri('/api/documents/$docId/annotations/$annotationId'));
    if (res.statusCode != 200 && res.statusCode != 204 && res.statusCode != 404) {
      throw Exception('Failed to delete annotation: ${res.statusCode}');
    }
  }

  Future<List<PdfAnnotation>> batchSyncAnnotations(String docId, List<PdfAnnotation> annotations) async {
    final payload = {
      'annotations': annotations.map((a) => {
        'id': a.id,
        'type': a.type,
        'page_number': a.pageNumber,
        'color_hex': a.colorHex,
        'rects': a.rects.map((r) => r.toJson()).toList(),
        'selected_text': a.selectedText,
        'note_content': a.noteContent,
      }).toList()
    };
    final res = await _post(
      _uri('/api/documents/$docId/annotations/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      final List<dynamic> list = jsonDecode(utf8.decode(res.bodyBytes));
      return list.map((item) => PdfAnnotation.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Failed to batch sync annotations: ${res.statusCode}');
    }
  }

  // OCR & Structured Markdown Conversion (MinerU VLM / Baidu PaddleOCR-VL)
  Future<Map<String, dynamic>> startOcr(
    String docId, {
    String engine = "mineru",
    String? mineruToken,
    String mineruModelVersion = "vlm",
    String mineruLanguage = "auto",
    bool enableFormula = true,
    bool enableTable = true,
    bool ossAccelerate = true,
    String? apiToken,
    String? apiUrl,
    String? modelName,
    String pageScope = "all",
    List<int>? targetPages,
    bool useDocOrientationClassify = false,
    bool useDocUnwarping = false,
    bool useChartRecognition = false,
  }) async {
    final payload = {
      'engine': engine,
      'mineru_token': mineruToken,
      'mineru_model_version': mineruModelVersion,
      'mineru_language': mineruLanguage,
      'enable_formula': enableFormula,
      'enable_table': enableTable,
      'oss_accelerate': ossAccelerate,
      'api_token': apiToken,
      'api_url': apiUrl,
      'model_name': modelName,
      'page_scope': pageScope,
      'target_pages': targetPages,
      'use_doc_orientation_classify': useDocOrientationClassify,
      'use_doc_unwarping': useDocUnwarping,
      'use_chart_recognition': useChartRecognition,
    };
    final res = await _post(
      _uri('/api/documents/$docId/ocr'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to start OCR: ${res.statusCode} - ${res.body}');
    }
  }


  Future<Map<String, dynamic>> getOcrStatus(String docId) async {
    final res = await _get(_uri('/api/documents/$docId/ocr-status'));
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to get OCR status: ${res.statusCode}');
    }
  }

  Future<DocumentModel> revertOcr(
    String docId, {
    String pageScope = "current",
    List<int>? targetPages,
  }) async {
    final payload = {
      'page_scope': pageScope,
      'target_pages': targetPages,
    };
    final res = await _post(
      _uri('/api/documents/$docId/ocr/revert'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return DocumentModel.fromJson(json);
    } else {
      throw Exception('Failed to revert OCR: ${res.statusCode} - ${res.body}');
    }
  }

  // Markdown Document API
  Future<Map<String, dynamic>> getMarkdown(String docId) async {
    final res = await _get(_uri('/api/documents/$docId/markdown'));
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to get markdown: ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> saveMarkdown(String docId, String markdown) async {
    final payload = {'markdown': markdown};
    final res = await _put(
      _uri('/api/documents/$docId/markdown'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to save markdown: ${res.statusCode}');
    }
  }

  // Document Image API
  String getDocumentImageUrl(String docId, String imageName) {
    final cleanName = imageName.split('/').last;
    return _uri('/api/documents/$docId/images/$cleanName').toString();
  }

  Future<bool> uploadDocumentImage(String docId, String imageName, Uint8List imageBytes) async {
    try {
      final cleanName = imageName.split('/').last;
      final uri = _uri('/api/documents/$docId/images/$cleanName');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: cleanName));
      final streamedResponse = await request.send();
      return streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}


