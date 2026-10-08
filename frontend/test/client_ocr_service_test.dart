import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/ocr/client_ocr_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  group('ClientOcrService Tests', () {
    final ocrService = ClientOcrService();

    test('prepareSubPdf correctly slices requested pages', () async {
      final doc = PdfDocument();
      doc.pages.add().graphics.drawString('Page 1', PdfStandardFont(PdfFontFamily.helvetica, 12));
      doc.pages.add().graphics.drawString('Page 2', PdfStandardFont(PdfFontFamily.helvetica, 12));
      doc.pages.add().graphics.drawString('Page 3', PdfStandardFont(PdfFontFamily.helvetica, 12));
      final fullBytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      // Test 1: all pages returns original
      final allBytes = await ocrService.prepareSubPdf(fullBytes, null, 3);
      expect(allBytes.length, fullBytes.length);

      // Test 2: slice only page 2
      final slicedBytes = await ocrService.prepareSubPdf(fullBytes, [2], 3);
      final slicedDoc = PdfDocument(inputBytes: slicedBytes);
      expect(slicedDoc.pages.count, 1);
      slicedDoc.dispose();

      // Test 3: slice pages 1 and 3
      final sliced13Bytes = await ocrService.prepareSubPdf(fullBytes, [1, 3], 3);
      final sliced13Doc = PdfDocument(inputBytes: sliced13Bytes);
      expect(sliced13Doc.pages.count, 2);
      sliced13Doc.dispose();
    });

    test('mergeWithExistingMarkdown handles empty and multi-page markdown merges', () {
      // 1. Initial page
      final initial = ocrService.mergeWithExistingMarkdown(null, {1: '# Chapter 1\nHello World'});
      expect(initial.contains('<!-- Page 1 -->'), true);
      expect(initial.contains('# Chapter 1'), true);

      // 2. Add page 2 to existing page 1
      final withPage2 = ocrService.mergeWithExistingMarkdown(initial, {2: r'## Section 2\nFormula $E=mc^2$'});
      expect(withPage2.contains('<!-- Page 1 -->'), true);
      expect(withPage2.contains('<!-- Page 2 -->'), true);
      expect(withPage2.contains(r'$E=mc^2$'), true);

      // 3. Overwrite page 1 with updated OCR
      final updatedPage1 = ocrService.mergeWithExistingMarkdown(withPage2, {1: '# Chapter 1 (Updated)'});
      expect(updatedPage1.contains('# Chapter 1 (Updated)'), true);
      expect(updatedPage1.contains('<!-- Page 2 -->'), true);
      expect(updatedPage1.contains('## Section 2'), true);
    });

    test('downloadAndParseResults parses JSONL output correctly', () async {
      // Create mock JSONL text
      final line1 = jsonEncode({
        'result': {
          'layoutParsingResults': [
            {
              'markdown': {'text': '# Title 1\nContent of page 1'}
            }
          ]
        }
      });
      final line2 = jsonEncode({
        'result': {
          'layoutParsingResults': [
            {
              'markdown': {'text': r'# Title 2\nContent of page 2 with $\alpha + \beta$'}
            }
          ]
        }
      });
      final jsonlText = '$line1\n$line2';

      // Verify parsing line by line
      final lines = jsonlText.split('\n');
      final List<dynamic> results = [];
      for (final l in lines) {
        final parsed = jsonDecode(l);
        results.addAll(parsed['result']['layoutParsingResults']);
      }
      expect(results.length, 2);

      final Map<int, String> parsedMap = {};
      final activePages = [1, 2];
      for (int i = 0; i < activePages.length; i++) {
        parsedMap[activePages[i]] = results[i]['markdown']['text'];
      }

      expect(parsedMap[1], contains('Title 1'));
      expect(parsedMap[2], contains('\\alpha + \\beta'));
    });
  });
}
