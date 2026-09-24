import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/document_model.dart';
import 'package:frontend/models/annotation_model.dart';

void main() {
  test('DocumentModel serialization test', () {
    final doc = DocumentModel(
      id: 'doc-123',
      filename: 'sample.pdf',
      title: 'Sample PDF Document',
      fileSize: 1048576,
      pageCount: 15,
      hasTextLayer: false,
      ocrStatus: 'processing',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      annotationCount: 3,
    );

    final json = doc.toJson();
    final parsed = DocumentModel.fromJson(json);

    expect(parsed.id, 'doc-123');
    expect(parsed.title, 'Sample PDF Document');
    expect(parsed.pageCount, 15);
    expect(parsed.hasTextLayer, false);
    expect(parsed.ocrStatus, 'processing');
    expect(parsed.formattedSize, '1.0 MB');
    expect(parsed.annotationCount, 3);
  });

  test('PdfAnnotation serialization test', () {
    final anno = PdfAnnotation(
      id: 'anno-456',
      docId: 'doc-123',
      type: 'highlight',
      pageNumber: 2,
      colorHex: '#69DB7C',
      rects: [
        const NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05),
      ],
      selectedText: 'Flutter & pdfrx are super fast',
      noteContent: 'Key insight for mobile & web',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final json = anno.toJson();
    final parsed = PdfAnnotation.fromJson(json);

    expect(parsed.id, 'anno-456');
    expect(parsed.colorHex, '#69DB7C');
    expect(parsed.rects.length, 1);
    expect(parsed.rects.first.width, 0.5);
    expect(parsed.isNote, true);
  });

  test('OcrStatusInfo serialization and getters test', () {
    final statusJson = {
      'doc_id': 'doc-123',
      'status': 'processing',
      'progress': 0.65,
      'current_page': 6,
      'total_pages': 10,
      'message': '正在识别第 6 / 10 页 (含数学符号)...',
    };

    final info = OcrStatusInfo.fromJson(statusJson);
    expect(info.docId, 'doc-123');
    expect(info.status, 'processing');
    expect(info.isProcessing, true);
    expect(info.isCompleted, false);
    expect(info.currentPage, 6);
    expect(info.totalPages, 10);
    expect(info.progress, 0.65);
    expect(info.message, contains('第 6 / 10 页'));
  });
}

