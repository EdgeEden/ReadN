import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/ocr/mineru_ocr_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  group('MineruOcrService Unit Tests', () {
    final mineruService = MineruOcrService();

    test('applyOssAcceleration replaces standard Shanghai domain with overseas accelerate endpoint', () {
      const origUrl = 'https://mineru.oss-cn-shanghai.aliyuncs.com/api-upload/extract/2026/test.pdf?Expires=123';
      final acceleratedUrl = mineruService.applyOssAcceleration(origUrl, enable: true);
      expect(acceleratedUrl, contains('mineru.oss-accelerate-overseas.aliyuncs.com'));
      expect(acceleratedUrl, contains('Expires=123'));

      final disabledUrl = mineruService.applyOssAcceleration(origUrl, enable: false);
      expect(disabledUrl, equals(origUrl));
    });

    test('prepareChunks correctly slices small document without re-encoding', () async {
      final doc = PdfDocument();
      doc.pages.add().graphics.drawString('Page 1', PdfStandardFont(PdfFontFamily.helvetica, 12));
      doc.pages.add().graphics.drawString('Page 2', PdfStandardFont(PdfFontFamily.helvetica, 12));
      final pdfBytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      final chunks = await mineruService.prepareChunks(
        fullPdfBytes: pdfBytes,
        totalDocPages: 2,
        maxPagesPerChunk: 200,
      );

      expect(chunks.length, equals(1));
      expect(chunks[0].pages, equals([1, 2]));
    });

    test('prepareChunks slices multi-page document into chunks of maxPagesPerChunk', () async {
      final doc = PdfDocument();
      for (int i = 0; i < 5; i++) {
        doc.pages.add().graphics.drawString('Page ${i + 1}', PdfStandardFont(PdfFontFamily.helvetica, 12));
      }
      final pdfBytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      final chunks = await mineruService.prepareChunks(
        fullPdfBytes: pdfBytes,
        totalDocPages: 5,
        targetPages: [1, 2, 3, 4, 5],
        maxPagesPerChunk: 2,
      );

      expect(chunks.length, equals(3));
      expect(chunks[0].pages, equals([1, 2]));
      expect(chunks[1].pages, equals([3, 4]));
      expect(chunks[2].pages, equals([5]));
    });
  });
}

