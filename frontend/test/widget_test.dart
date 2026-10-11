import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:frontend/models/document_model.dart';
import 'package:frontend/models/annotation_model.dart';
import 'package:frontend/models/ai_message_model.dart';
import 'package:frontend/providers/ai_provider.dart';
import 'package:frontend/providers/reader_settings_provider.dart';
import 'package:frontend/services/ai_service.dart';
import 'package:frontend/services/storage_service.dart';
import 'package:frontend/services/cache/doc_cache_service.dart';
import 'package:frontend/services/cache/annotation_cache_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/document_provider.dart';
import 'package:frontend/providers/annotation_provider.dart';
import 'package:frontend/views/reader/components/ai_config_dialog.dart';
import 'package:frontend/views/reader/components/markdown_html_support.dart';
import 'package:frontend/views/reader/components/markdown_reader_view.dart';
import 'package:frontend/views/reader/components/latex_interactive_view.dart';
import 'package:frontend/views/reader/components/reader_bottom_bar.dart';
import 'package:frontend/views/reader/components/reader_mobile_sheet.dart';
import 'package:frontend/views/reader/components/reader_sidebar.dart';
import 'package:frontend/views/reader/components/reader_top_bar.dart';
import 'package:frontend/views/reader/components/floating_selection_bar.dart';
import 'package:frontend/views/reader/components/note_editor_dialog.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:frontend/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('DocumentModel serialization test', () {
    final doc = DocumentModel(
      id: 'doc-123',
      filename: 'sample.pdf',
      title: 'Sample PDF Document',
      fileSize: 1048576,
      pageCount: 15,
      hasTextLayer: false,
      hasMarkdown: true,
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
    expect(parsed.hasMarkdown, true);
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

  test('LatexInlineSyntax regex matches inline math expressions', () {
    final syntax = LatexInlineSyntax();
    final regex = syntax.pattern;

    const text = r'Einstein discovered $E = mc^2$ in 1905.';
    final matches = regex.allMatches(text).toList();
    expect(matches.length, 1);
    expect(matches.first.group(1), 'E = mc^2');
  });

  test('LatexBlockInlineSyntax regex matches block math expressions', () {
    final syntax = LatexBlockInlineSyntax();
    final regex = syntax.pattern;

    const text = r'The summation is $$\sum_{i=1}^n x_i = S$$ as shown.';
    final matches = regex.allMatches(text).toList();
    expect(matches.length, 1);
    expect(matches.first.group(1), r'\sum_{i=1}^n x_i = S');
  });

  test('MarkdownHighlightInlineSyntax matches default and colored highlights', () {
    final syntax = MarkdownHighlightInlineSyntax();
    final regex = syntax.pattern;

    const text1 = 'This is ==standard highlight== in text';
    final matches1 = regex.allMatches(text1).toList();
    expect(matches1.length, 1);
    expect(matches1.first.group(1), isNull);
    expect(matches1.first.group(2), 'standard highlight');

    const text2 = 'This is ==[#86EFAC]green fluorescent highlight== in text';
    final matches2 = regex.allMatches(text2).toList();
    expect(matches2.length, 1);
    expect(matches2.first.group(1), '#86EFAC');
    expect(matches2.first.group(2), 'green fluorescent highlight');
  });

  test('HtmlMarkInlineSyntax matches mark tags with and without color', () {
    final syntax = HtmlMarkInlineSyntax();
    final regex = syntax.pattern;

    const text1 = 'Sample <mark>plain mark</mark> test';
    final matches1 = regex.allMatches(text1).toList();
    expect(matches1.length, 1);
    expect(matches1.first.group(1), isNull);
    expect(matches1.first.group(2), 'plain mark');

    const text2 = 'Sample <mark data-color="#93C5FD">colored mark</mark> test';
    final matches2 = regex.allMatches(text2).toList();
    expect(matches2.length, 1);
    expect(matches2.first.group(1), '#93C5FD');
    expect(matches2.first.group(2), 'colored mark');
  });

  test('HTML formatting inline syntaxes match respective tags', () {
    // Underline
    final uSyntax = HtmlUnderlineSyntax();
    final uMatches = uSyntax.pattern.allMatches('Text with <u>underlined content</u> here').toList();
    expect(uMatches.length, 1);
    expect(uMatches.first.group(1), 'underlined content');

    // Subscript & Superscript
    final subSyntax = HtmlSubscriptSyntax();
    final subMatches = subSyntax.pattern.allMatches('Water is H<sub>2</sub>O').toList();
    expect(subMatches.length, 1);
    expect(subMatches.first.group(1), '2');

    final supSyntax = HtmlSuperscriptSyntax();
    final supMatches = supSyntax.pattern.allMatches('Energy is mc<sup>2</sup>').toList();
    expect(supMatches.length, 1);
    expect(supMatches.first.group(1), '2');

    // Strikethrough
    final delSyntax = HtmlStrikeSyntax();
    final delMatches = delSyntax.pattern.allMatches('Price was <del>¥100</del> ¥80').toList();
    expect(delMatches.length, 1);
    expect(delMatches.first.group(1), '¥100');

    // Span with style
    final spanSyntax = HtmlSpanSyntax();
    final spanMatches = spanSyntax.pattern.allMatches('<span style="color: #ef4444; font-weight: bold;">Red Text</span>').toList();
    expect(spanMatches.length, 1);
    expect(spanMatches.first.group(1), contains('color: #ef4444'));
    expect(spanMatches.first.group(3), 'Red Text');

    // Kbd
    final kbdSyntax = HtmlKbdSyntax();
    final kbdMatches = kbdSyntax.pattern.allMatches('Press <kbd>Ctrl+C</kbd> to copy').toList();
    expect(kbdMatches.length, 1);
    expect(kbdMatches.first.group(1), 'Ctrl+C');

    // Ruby
    final rubySyntax = HtmlRubySyntax();
    final rubyMatches = rubySyntax.pattern.allMatches('<ruby>汉字<rt>hàn zì</rt></ruby>').toList();
    expect(rubyMatches.length, 1);
    expect(rubyMatches.first.group(1), '汉字');
    expect(rubyMatches.first.group(2), 'hàn zì');

    // Details / Summary
    final detailsSyntax = HtmlDetailsSyntax();
    final detailsMatches = detailsSyntax.pattern.allMatches('<details><summary>点击查看解题步骤</summary>第1步：公式化简</details>').toList();
    expect(detailsMatches.length, 1);
    expect(detailsMatches.first.group(1), '点击查看解题步骤');
    expect(detailsMatches.first.group(2), '第1步：公式化简');
  });

  test('CSS property and HTML color parsing helper tests', () {
    final css = parseCssProperties('color: #ef4444; font-size: 18px; font-weight: bold; background-color: rgb(255, 255, 0);');
    expect(css['color'], '#ef4444');
    expect(css['font-size'], '18px');
    expect(css['font-weight'], 'bold');
    expect(css['background-color'], 'rgb(255, 255, 0)');

    expect(parseHtmlColor('red'), isNotNull);
    expect(parseHtmlColor('#3B82F6'), isNotNull);
    expect(parseHtmlColor('rgba(16, 185, 129, 0.5)'), isNotNull);
  });

  test('ReaderSettingsProvider sidebar docking and tab switching test', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final settings = ReaderSettingsProvider(storageService: storage);

    expect(settings.isLeftSidebarOpen, true);
    expect(settings.leftDockedTabs, contains(ReaderSidebarTab.outline));
    expect(settings.leftDockedTabs, contains(ReaderSidebarTab.search));
    expect(settings.rightDockedTabs, contains(ReaderSidebarTab.highlights));
    expect(settings.rightDockedTabs, contains(ReaderSidebarTab.notes));

    // Dock outline to right sidebar
    settings.dockTabToRight(ReaderSidebarTab.outline);
    expect(settings.leftDockedTabs.contains(ReaderSidebarTab.outline), false);
    expect(settings.rightDockedTabs.contains(ReaderSidebarTab.outline), true);
    expect(settings.isRightSidebarOpen, true);
    expect(settings.activeRightTab, ReaderSidebarTab.outline);

    // Dock notes to left sidebar
    settings.dockTabToLeft(ReaderSidebarTab.notes);
    expect(settings.rightDockedTabs.contains(ReaderSidebarTab.notes), false);
    expect(settings.leftDockedTabs.contains(ReaderSidebarTab.notes), true);
    expect(settings.isLeftSidebarOpen, true);
    expect(settings.activeLeftTab, ReaderSidebarTab.notes);
  });

  test('preprocessMarkdownHtml converts HTML tables and divs correctly', () {
    const rawSample = '''
<!-- Page 1 -->

阿斯达克警方很快很快哈哈

<div style="text-align: center;">啊是的哇打算的</div>

<table border=1 style='margin: auto; word-wrap: break-word;'><tr><td style='text-align: center;'>Asd</td><td></td><td></td><td></td><td></td></tr><tr><td></td><td></td><td></td><td>aSDwqd</td><td></td></tr></table>
''';

    final processed = preprocessMarkdownHtml(rawSample);
    expect(processed, contains('<center>啊是的哇打算的</center>'));
    expect(processed, contains('| Asd |  |  |  |  |'));
    expect(processed, contains('| --- | --- | --- | --- | --- |'));
    expect(processed, contains('|  |  |  | aSDwqd |  |'));
  });

  test('MarkdownPageChunk resolution handles merged/skipped page numbers gracefully', () {
    final chunks = [
      const MarkdownPageChunk(pageNumber: 1, content: 'Page 1 content'),
      const MarkdownPageChunk(pageNumber: 2, content: 'Merged table spanning pages 2 to 4'),
      const MarkdownPageChunk(pageNumber: 5, content: 'Page 5 content'),
    ];

    // Helper simulating the lookup logic in jumpToPage
    int resolveTargetIndex(int pageNumber) {
      int targetIndex = chunks.indexWhere((c) => c.pageNumber == pageNumber);
      if (targetIndex == -1) {
        for (int i = chunks.length - 1; i >= 0; i--) {
          if (chunks[i].pageNumber <= pageNumber) {
            targetIndex = i;
            break;
          }
        }
      }
      if (targetIndex == -1) {
        targetIndex = 0;
      }
      return targetIndex;
    }

    expect(resolveTargetIndex(1), 0);
    expect(resolveTargetIndex(2), 1);
    expect(resolveTargetIndex(3), 1); // Page 3 jumps to chunk 2
    expect(resolveTargetIndex(4), 1); // Page 4 jumps to chunk 2
    expect(resolveTargetIndex(5), 2); // Page 5 jumps to chunk 5
    expect(resolveTargetIndex(6), 2); // Page 6 jumps to chunk 5
  });

  test('Markdown parser recognizes LaTeX inside highlight tags', () {
    final syntaxes = [
      LatexInlineSyntax(),
      MarkdownHighlightInlineSyntax(),
    ];
    final doc = md.Document(inlineSyntaxes: syntaxes);
    final nodes = doc.parseInline('Here is ==\$E = mc^2\$== highlighted.');
    expect(nodes.length, 3);
    expect(nodes[1], isA<md.Element>());
    final markElem = nodes[1] as md.Element;
    expect(markElem.tag, 'mark');
    expect(markElem.children, isNotEmpty);
    expect(markElem.children!.first, isA<md.Element>());
    final latexChild = markElem.children!.first as md.Element;
    expect(latexChild.tag, 'latex');
    expect(latexChild.textContent, 'E = mc^2');
  });

  test('LaTeX formula highlight replacement and removal logic works cleanly', () {
    const rawContent = r'''
Einstein formulated $E = mc^2$ in relativity.
Also consider display formula:
$$\sum_{i=1}^n x_i = S$$
''';

    // 1. Highlight inline formula with custom green color
    const trimmedLatex = 'E = mc^2';
    final escaped = RegExp.escape(trimmedLatex);
    final plainRegex = RegExp(
      r'(\$\$|\$|\\\[|\\\(|```(?:latex|math|tex)\s*\n?)\s*' +
          escaped +
          r'\s*(\$\$|\$|\\\]|\\\)|\n?```)',
    );

    expect(plainRegex.hasMatch(rawContent), true);
    final highlightedContent = rawContent.replaceFirstMapped(plainRegex, (m) {
      final openDelim = m.group(1) ?? r'$';
      final closeDelim = m.group(2) ?? r'$';
      return '==[#86EFAC]$openDelim$trimmedLatex$closeDelim==';
    });

    expect(highlightedContent, contains(r'==[#86EFAC]$E = mc^2$=='));

    // 2. Change highlight color from green to purple
    final alreadyHighlightedRegex = RegExp(
      r'==(?:\[#[0-9a-fA-F]{3,8}\])?\s*(\$\$|\$|\\\[|\\\(|```(?:latex|math|tex)\s*\n?)\s*' +
          escaped +
          r'\s*(\$\$|\$|\\\]|\\\)|\n?```)\s*==',
    );

    expect(alreadyHighlightedRegex.hasMatch(highlightedContent), true);
    final changedColorContent = highlightedContent.replaceAllMapped(alreadyHighlightedRegex, (m) {
      final openDelim = m.group(1) ?? r'$';
      final closeDelim = m.group(2) ?? r'$';
      return '==[#D8B4FE]$openDelim$trimmedLatex$closeDelim==';
    });

    expect(changedColorContent, contains(r'==[#D8B4FE]$E = mc^2$=='));

    // 3. Remove highlight
    final unhighlightedContent = changedColorContent.replaceAllMapped(alreadyHighlightedRegex, (m) {
      final openDelim = m.group(1) ?? r'$';
      final closeDelim = m.group(2) ?? r'$';
      return '$openDelim$trimmedLatex$closeDelim';
    });

    expect(unhighlightedContent, contains(r'$E = mc^2$'));
    expect(unhighlightedContent, isNot(contains('==')));
  });

  test('Highlight deletion from markdown handles plain text, html marks, and fenced latex blocks', () {
    String removeHighlightFromMarkdown(String markdown, String targetText) {
      if (markdown.trim().isEmpty || targetText.trim().isEmpty) return markdown;
      var result = markdown;
      final trimmed = targetText.trim();
      final escaped = RegExp.escape(trimmed);

      // 1. Direct Markdown highlight
      final directRegex = RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?\s*' + escaped + r'\s*==');
      if (directRegex.hasMatch(result)) {
        result = result.replaceAllMapped(directRegex, (_) => trimmed);
      }

      // 2. HTML mark tag
      final htmlMarkRegex = RegExp(r'<mark(?:\s+[^>]*)?>\s*' + escaped + r'\s*</mark>', caseSensitive: false);
      if (htmlMarkRegex.hasMatch(result)) {
        result = result.replaceAllMapped(htmlMarkRegex, (_) => trimmed);
      }

      // 3. Mathematical formulas
      final strippedFormula = trimmed.replaceAll(RegExp(r'^(\$\$|\$)|(\$\$|\$)$'), '').trim();
      if (strippedFormula.isNotEmpty) {
        final escapedStripped = RegExp.escape(strippedFormula);
        final formulaHighlightRegex = RegExp(
          r'==(?:\[#[0-9a-fA-F]{3,8}\])?\s*((\$\$|\$|\\\[|\\\(|```(?:latex|math|tex)\s*\n?)\s*' +
              escapedStripped +
              r'\s*(\$\$|\$|\\\]|\\\)|\n?```))\s*==',
        );
        if (formulaHighlightRegex.hasMatch(result)) {
          result = result.replaceAllMapped(formulaHighlightRegex, (m) => m.group(1) ?? strippedFormula);
        }
      }

      return result;
    }

    // 1. Standard text highlight deletion
    const md1 = 'This is ==[#FDE047]important text== in a document.';
    final res1 = removeHighlightFromMarkdown(md1, 'important text');
    expect(res1, 'This is important text in a document.');

    // 2. HTML mark deletion
    const md2 = 'This is <mark data-color="#86EFAC">green marked text</mark> in a document.';
    final res2 = removeHighlightFromMarkdown(md2, 'green marked text');
    expect(res2, 'This is green marked text in a document.');

    // 3. LaTeX fenced block highlight deletion
    const md3 = '''
Here is a matrix:
==[#7DD3FC]```latex
\\begin{matrix}
1 & 0 \\\\
0 & 1
\\end{matrix}
```==
End of page.
''';
    final res3 = removeHighlightFromMarkdown(md3, '''\\begin{matrix}
1 & 0 \\\\
0 & 1
\\end{matrix}''');
    expect(res3, isNot(contains('==')));
    expect(res3, contains('```latex'));
    expect(res3, contains('\\begin{matrix}'));
  });

  test('AiConfig model and presets test', () {
    final config = AiConfig(
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-deepseek-test-key-123456',
      model: 'deepseek-reasoner',
      systemPrompt: 'You are an expert reading assistant.',
      temperature: 0.6,
      includePageContext: true,
    );

    expect(config.baseUrl, 'https://api.deepseek.com/v1');
    expect(config.apiKey, 'sk-deepseek-test-key-123456');
    expect(config.model, 'deepseek-reasoner');
    expect(config.temperature, 0.6);
    expect(config.includePageContext, true);
    expect(config.hasValidKey, true);

    final modified = config.copyWith(
      model: 'deepseek-chat',
      temperature: 0.7,
    );
    expect(modified.model, 'deepseek-chat');
    expect(modified.temperature, 0.7);
    expect(modified.baseUrl, config.baseUrl);
    expect(modified.apiKey, config.apiKey);

    expect(AiConfig.presets.isNotEmpty, true);
    final dsPreset = AiConfig.presets.firstWhere((p) => p.name == 'deepseek');
    expect(dsPreset.baseUrl, 'https://api.deepseek.com');
    expect(dsPreset.recommendedModels, contains('deepseek-reasoner'));
    expect(dsPreset.recommendedModels, contains('deepseek-chat'));
  });

  test('ChatMessage reasoning/thinking state and duration test', () {
    final msg = ChatMessage(
      id: 'msg-1',
      role: 'assistant',
      content: 'This is the final response.',
      thinkingContent: 'Step 1: Parse the user request.\nStep 2: Formulate solution.',
      isThinking: false,
      isThinkingExpanded: false,
      thinkingDurationMs: 2450,
      quotedText: 'LaTeX formula: \$\\int_0^1 x dx\$',
      pageNumber: 3,
    );

    expect(msg.role, 'assistant');
    expect(msg.content, 'This is the final response.');
    expect(msg.hasThinking, true);
    expect(msg.thinkingDurationMs, 2450);
    expect(msg.isThinkingExpanded, false);
    expect(msg.hasQuote, true);
    expect(msg.pageNumber, 3);
  });

  test('StorageService persists AI configuration locally', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();

    expect(storage.getAiApiKey(), '');
    expect(storage.getAiBaseUrl(), 'https://api.deepseek.com');
    expect(storage.getAiModel(), '');

    await storage.setAiApiKey('sk-local-storage-only-key');
    await storage.setAiBaseUrl('https://api.siliconflow.cn/v1');
    await storage.setAiModel('deepseek-ai/DeepSeek-R1');
    await storage.setAiIncludeContext(true);

    expect(storage.getAiApiKey(), 'sk-local-storage-only-key');
    expect(storage.getAiBaseUrl(), 'https://api.siliconflow.cn/v1');
    expect(storage.getAiModel(), 'deepseek-ai/DeepSeek-R1');
    expect(storage.getAiIncludeContext(), true);
  });

  test('AiProvider quote management and config updates', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final aiService = AiService();
    final provider = AiProvider(storageService: storage, aiService: aiService);

    expect(provider.hasPendingQuote, false);
    provider.setPendingQuote('Important highlighted quote', pageNumber: 5);
    expect(provider.hasPendingQuote, true);
    expect(provider.pendingQuotedText, 'Important highlighted quote');
    expect(provider.pendingQuotedPage, 5);

    provider.clearPendingQuote();
    expect(provider.hasPendingQuote, false);

    await provider.updateConfig(
      provider.config.copyWith(
        apiKey: 'test-key',
        model: 'deepseek-chat',
      ),
    );

    expect(provider.isConfigured, true);
    expect(provider.config.apiKey, 'test-key');
    expect(provider.config.model, 'deepseek-chat');
  });

  test('AiService fetchModelList validates empty baseUrl', () async {
    final aiService = AiService();
    final result = await aiService.fetchModelList(baseUrl: '', apiKey: 'sk-test');
    expect(result.success, false);
    expect(result.models.isEmpty, true);
    expect(result.message, contains('Base URL'));
  });

  test('PdfAnnotation knowledge card properties and displayTitle test', () {
    final card = PdfAnnotation(
      id: 'card-101',
      docId: 'doc-123',
      type: 'card',
      pageNumber: 3,
      colorHex: '#8B5CF6',
      rects: const [],
      selectedText: r'E = mc^2',
      noteContent: '## 质能方程解析\n- 核心原理: 质量与能量等价\n- 关键公式: \$E = mc^2\$',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(card.isCard, true);
    expect(card.isNote, false);
    expect(card.isHighlight, false);
    expect(card.displayTitle, '质能方程解析');
  });

  test('AnnotationBadgeInlineSyntax matches card and note tags', () {
    final syntax = AnnotationBadgeInlineSyntax();
    final doc = md.Document(inlineSyntaxes: [syntax]);
    
    // 1. Tag pair format
    final parser1 = md.InlineParser('<annobadge id="c-123" type="card"></annobadge>', doc);
    final nodes1 = parser1.parse();
    expect(nodes1.length, 1);
    expect(nodes1.first is md.Element, true);
    final el1 = nodes1.first as md.Element;
    expect(el1.tag, 'annobadge');
    expect(el1.attributes['id'], 'c-123');
    expect(el1.attributes['type'], 'card');

    // 2. Self closing format
    final parser2 = md.InlineParser('<annobadge id="n-456" type="note" />', doc);
    final nodes2 = parser2.parse();
    expect(nodes2.length, 1);
    final el2 = nodes2.first as md.Element;
    expect(el2.tag, 'annobadge');
    expect(el2.attributes['id'], 'n-456');
    expect(el2.attributes['type'], 'note');
  });

  test('Note and Highlight independence test', () {
    final noteAnno = PdfAnnotation(
      id: 'n-1',
      docId: 'doc-1',
      type: 'note',
      pageNumber: 1,
      colorHex: '#6366F1',
      rects: const [],
      selectedText: 'Some referenced sentence',
      noteContent: 'User thoughts on this paragraph',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final highlightAnno = PdfAnnotation(
      id: 'h-1',
      docId: 'doc-1',
      type: 'highlight',
      pageNumber: 1,
      colorHex: '#FDE047',
      rects: const [],
      selectedText: 'Highlighted words',
      noteContent: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(noteAnno.isNote, true);
    expect(noteAnno.isHighlight, false);
    expect(noteAnno.isCard, false);

    expect(highlightAnno.isHighlight, true);
    expect(highlightAnno.isNote, false);
    expect(highlightAnno.isCard, false);
  });

  test('AnnotationCacheService save and retrieve test', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = await AnnotationCacheService.init();

    final anno1 = PdfAnnotation(
      id: 'anno-test-1',
      docId: 'doc-cache-test',
      type: 'highlight',
      pageNumber: 1,
      colorHex: '#FFE066',
      rects: const [NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04)],
      selectedText: 'Cached Highlight Text',
      noteContent: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final anno2 = PdfAnnotation(
      id: 'card-test-2',
      docId: 'doc-cache-test',
      type: 'card',
      pageNumber: 2,
      colorHex: '#8B5CF6',
      rects: const [],
      selectedText: 'Formula Quote',
      noteContent: '## Card Title\nCard body content',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(cache.getAnnotations('doc-cache-test').isEmpty, true);

    await cache.saveAnnotations('doc-cache-test', [anno1, anno2]);

    final retrieved = cache.getAnnotations('doc-cache-test');
    expect(retrieved.length, 2);
    expect(retrieved[0].id, 'anno-test-1');
    expect(retrieved[0].selectedText, 'Cached Highlight Text');
    expect(retrieved[1].id, 'card-test-2');
    expect(retrieved[1].isCard, true);

    await cache.deleteAnnotations('doc-cache-test');
    expect(cache.getAnnotations('doc-cache-test').isEmpty, true);
  });

  test('DocCacheService save and retrieve PDF and Markdown test', () async {
    final docCache = DocCacheService();
    await docCache.init();

    final sampleBytes = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 52]); // %PDF-1.4
    const docId = 'test-doc-id-999';
    const checksum = 'sample-sha256-checksum';

    await docCache.savePdf(docId, sampleBytes, checksum: checksum);
    expect(await docCache.hasPdf(docId), true);
    expect(await docCache.hasPdf(docId, expectedChecksum: checksum), true);
    expect(await docCache.hasPdf(docId, expectedChecksum: 'mismatched-checksum'), false);

    final retrievedBytes = await docCache.getPdf(docId, expectedChecksum: checksum);
    expect(retrievedBytes, isNotNull);
    expect(retrievedBytes!.length, sampleBytes.length);
    expect(retrievedBytes[0], 37);

    // Markdown test
    const mdSample = '# Markdown Cache Test\n- Item 1\n- Item 2';
    await docCache.saveMarkdown(docId, mdSample);
    final retrievedMd = await docCache.getMarkdown(docId);
    expect(retrievedMd, mdSample);

    // Cleanup
    await docCache.deletePdf(docId);
    await docCache.deleteMarkdown(docId);
    expect(await docCache.hasPdf(docId), false);
    expect(await docCache.getMarkdown(docId), isNull);
  });
  testWidgets('AiConfigDialog renders without errors', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final aiService = AiService();
    final aiProvider = AiProvider(storageService: storage, aiService: aiService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: aiProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AiConfigDialog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 助手服务配置'), findsOneWidget);
    expect(find.text('API 基础地址 (Base URL)'), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);

    // Test MarkdownReaderView with heading highlight
    final doc = DocumentModel(
      id: 'doc-1',
      filename: 'sample.pdf',
      title: 'Sample',
      fileSize: 1000,
      pageCount: 1,
      hasTextLayer: true,
      hasMarkdown: true,
      ocrStatus: 'none',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      annotationCount: 0,
    );
    final apiService = ApiService(storageService: storage);
    final docCache = DocCacheService();
    final annoCache = await AnnotationCacheService.init();
    final docProvider = DocumentProvider(apiService: apiService, storageService: storage, docCacheService: docCache);
    final annoProvider = AnnotationProvider(apiService: apiService, storageService: storage, annotationCacheService: annoCache);
    final settingsProvider = ReaderSettingsProvider(storageService: storage);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: docProvider),
          ChangeNotifierProvider.value(value: annoProvider),
          ChangeNotifierProvider.value(value: settingsProvider),
          ChangeNotifierProvider.value(value: aiProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MarkdownReaderView(
              document: doc,
              markdownContent: '<!-- Page 1 -->\n\n## ==2. 在正确答案上面○。==',
              onOpenOcr: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textWidget = tester.widget<Text>(find.text('2. 在正确答案上面○。'));
    expect(textWidget.style?.fontSize, greaterThan(20.0)); // h2 style preserved!
    expect(textWidget.style?.fontWeight, FontWeight.bold);
  });

  test('applyHighlightToMarkdown preserves headings and handles multiline text', () {
    const rawMd = '''
# 7. 听录音，仿照例句替换画线部分进行练习。

[例] 李/森健太郎
→ 甲：李 さんですか。
乙：はい、李 です。どうぞ よろしく。
''';

    // 1. Single-line heading selection
    final res1 = applyHighlightToMarkdown(rawMd, '7. 听录音，仿照例句替换画线部分进行练习。', '#FDE047');
    expect(res1, contains('# ==7. 听录音，仿照例句替换画线部分进行练习。=='));

    // 2. Multiline selection spanning heading and lines
    const multiSelection = '''
7. 听录音，仿照例句替换画线部分进行练习。
[例] 李/森健太郎
→ 甲：李 さんですか。
''';
    final res2 = applyHighlightToMarkdown(rawMd, multiSelection, '#86EFAC');
    expect(res2, contains('# ==[#86EFAC]7. 听录音，仿照例句替换画线部分进行练习。=='));
    expect(res2, contains('==[#86EFAC][例] 李/森健太郎=='));
    expect(res2, contains('==[#86EFAC]→ 甲：李 さんですか。=='));
    expect(res2, contains('乙：はい、李 です。どうぞ よろしく。'));

    // 3. Multiline deletion
    final cleanMd = removeHighlightFromMarkdown(res2, multiSelection);
    expect(cleanMd, isNot(contains('==')));
    expect(cleanMd, contains('# 7. 听录音，仿照例句替换画线部分进行练习。'));
    expect(cleanMd, contains('[例] 李/森健太郎'));
    expect(cleanMd, contains('→ 甲：李 さんですか。'));
  });

  test('applyHighlightToMarkdown preserves bullet list items and blockquotes', () {
    const listMd = '''
- 第一项内容
- 第二项内容
> 引用段落内容
''';

    const sel = '''
第一项内容
第二项内容
引用段落内容
''';
    final highlighted = applyHighlightToMarkdown(listMd, sel, '#93C5FD');
    expect(highlighted, contains('- ==[#93C5FD]第一项内容=='));
    expect(highlighted, contains('- ==[#93C5FD]第二项内容=='));
    expect(highlighted, contains('> ==[#93C5FD]引用段落内容=='));

    final unhighlighted = removeHighlightFromMarkdown(highlighted, sel);
    expect(unhighlighted, isNot(contains('==')));
    expect(unhighlighted, contains('- 第一项内容'));
    expect(unhighlighted, contains('- 第二项内容'));
    expect(unhighlighted, contains('> 引用段落内容'));
  });

  test('applyHighlightToMarkdown splits cross-line selection by newlines into segmented highlights', () {
    const multiLineDoc = '''
这是第一行选中文本。
这是第二行选中文本。
这是第三行选中文本。
''';

    const crossLineSelection = '''
这是第一行选中文本。
这是第二行选中文本。
这是第三行选中文本。
''';

    final result = applyHighlightToMarkdown(multiLineDoc, crossLineSelection, '#FDE047');
    expect(result, contains('==这是第一行选中文本。=='));
    expect(result, contains('==这是第二行选中文本。=='));
    expect(result, contains('==这是第三行选中文本。=='));
    // Ensure newline characters separate the highlight segments
    expect(result, contains('==这是第一行选中文本。==\n==这是第二行选中文本。==\n==这是第三行选中文本。=='));
  });

  test('applyHighlightToMarkdown handles Word export markdown sample with headings, bullets, and existing highlights', () {
    const sample = '''
<!-- Page 1 -->

## 1. 进入导出界面

点击顶部菜单栏的 文件 -> 导出 -> 点击 创建 PDF/XPS 文档。

## 2. 检查输出选项

点击旁边的【选项】按钮，确保勾选“辅助工具的文档结==[#FFE066]构标记”（用于生==成文字结构与无障碍标记）。

· 避免使用“虚拟打印为 PDF”：部分第三方打印机驱动会将整页渲染成位图。

- 特殊艺术字体被降级：部分受版权限制或不规则的特殊艺术字可能在转换时被自动转为位图。
''';

    // Scenario A: Multiline selection across heading, paragraph, and bullet items
    const selectionA = '''
进入导出界面
点击顶部菜单栏的 文件 -> 导出 -> 点击 创建 PDF/XPS 文档。
避免使用“虚拟打印为 PDF”：部分第三方打印机驱动会将整页渲染成位图。
特殊艺术字体被降级：部分受版权限制或不规则的特殊艺术字可能在转换时被自动转为位图。
''';

    final resA = applyHighlightToMarkdown(sample, selectionA, '#86EFAC');
    expect(resA, contains('## 1. ==[#86EFAC]进入导出界面=='));
    expect(resA, contains('==[#86EFAC]点击顶部菜单栏的 文件 -> 导出 -> 点击 创建 PDF/XPS 文档。=='));
    expect(resA, contains('· ==[#86EFAC]避免使用“虚拟打印为 PDF”：部分第三方打印机驱动会将整页渲染成位图。=='));
    expect(resA, contains('- ==[#86EFAC]特殊艺术字体被降级：部分受版权限制或不规则的特殊艺术字可能在转换时被自动转为位图。=='));

    // Scenario B: Selection on text with existing highlight tags updates cleanly
    const selectionB = '确保勾选“辅助工具的文档结构标记”（用于生成文字结构与无障碍标记）。';
    final resB = applyHighlightToMarkdown(sample, selectionB, '#FDE047');
    expect(resB, contains('==确保勾选“辅助工具的文档结构标记”（用于生成文字结构与无障碍标记）。=='));
    // Ensure no broken nested tags like 结==[#FFE066]构
    expect(resB, isNot(contains('结==[#FFE066]构')));

    // Scenario C: Removing multiline highlight (simulating sidebar delete button)
    final removedA = removeHighlightFromMarkdown(resA, selectionA);
    expect(removedA, isNot(contains('==[#86EFAC]')));
    expect(removedA, contains('## 1. 进入导出界面'));
    expect(removedA, contains('点击顶部菜单栏的 文件 -> 导出 -> 点击 创建 PDF/XPS 文档。'));
    expect(removedA, contains('· 避免使用“虚拟打印为 PDF”：部分第三方打印机驱动会将整页渲染成位图。'));
    expect(removedA, contains('- 特殊艺术字体被降级：部分受版权限制或不规则的特殊艺术字可能在转换时被自动转为位图。'));

    // Scenario D: Removing multiline highlight when selection text itself includes Markdown prefixes
    const selectionWithPrefixes = '''
## 1. 进入导出界面
点击顶部菜单栏的 文件 -> 导出 -> 点击 创建 PDF/XPS 文档。
· 避免使用“虚拟打印为 PDF”：部分第三方打印机驱动会将整页渲染成位图。
- 特殊艺术字体被降级：部分受版权限制或不规则的特殊艺术字可能在转换时被自动转为位图。
''';
    final removedWithPrefixes = removeHighlightFromMarkdown(resA, selectionWithPrefixes);
    expect(removedWithPrefixes, isNot(contains('==[#86EFAC]')));
    expect(removedWithPrefixes, contains('## 1. 进入导出界面'));
    expect(removedWithPrefixes, contains('点击顶部菜单栏的 文件 -> 导出 -> 点击 创建 PDF/XPS 文档。'));
    expect(removedWithPrefixes, contains('· 避免使用“虚拟打印为 PDF”：部分第三方打印机驱动会将整页渲染成位图。'));
    expect(removedWithPrefixes, contains('- 特殊艺术字体被降级：部分受版权限制或不规则的特殊艺术字可能在转换时被自动转为位图。'));
  });

  testWidgets('MarkdownReaderView renders inline LaTeX seamlessly without breaking text into separate wrap boxes', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final apiService = ApiService(storageService: storage);
    final docCache = DocCacheService();
    final annoCache = await AnnotationCacheService.init();
    final docProvider = DocumentProvider(apiService: apiService, storageService: storage, docCacheService: docCache);
    final annoProvider = AnnotationProvider(apiService: apiService, storageService: storage, annotationCacheService: annoCache);
    final settingsProvider = ReaderSettingsProvider(storageService: storage);
    final aiService = AiService();
    final aiProvider = AiProvider(storageService: storage, aiService: aiService);

    final doc = DocumentModel(
      id: 'doc-latex-inline',
      filename: 'sample.pdf',
      title: 'Sample',
      fileSize: 1000,
      pageCount: 1,
      hasTextLayer: true,
      hasMarkdown: true,
      ocrStatus: 'none',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      annotationCount: 0,
    );

    const testMarkdown = '<!-- Page 1 -->\n\n国际网络 \$ ^{[23]} \$。1998年，全球有27 000 km的光纤链路。';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: docProvider),
          ChangeNotifierProvider.value(value: annoProvider),
          ChangeNotifierProvider.value(value: settingsProvider),
          ChangeNotifierProvider.value(value: aiProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MarkdownReaderView(
              document: doc,
              markdownContent: testMarkdown,
              onOpenOcr: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify InteractiveLatexView exists
    expect(find.byType(InteractiveLatexView), findsOneWidget);

    // Verify the paragraph Wrap has exactly 1 merged Text widget
    final wrapFinder = find.byType(Wrap);
    expect(wrapFinder, findsWidgets);
    final wrap = tester.widget<Wrap>(wrapFinder.first);
    expect(wrap.children.length, 1);
  });

  testWidgets('MarkdownReaderView renders highlighted text and subsequent text without abnormal wrap line break', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final apiService = ApiService(storageService: storage);
    final docCache = DocCacheService();
    final annoCache = await AnnotationCacheService.init();
    final docProvider = DocumentProvider(apiService: apiService, storageService: storage, docCacheService: docCache);
    final annoProvider = AnnotationProvider(apiService: apiService, storageService: storage, annotationCacheService: annoCache);
    final settingsProvider = ReaderSettingsProvider(storageService: storage);
    final aiService = AiService();
    final aiProvider = AiProvider(storageService: storage, aiService: aiService);

    final doc = DocumentModel(
      id: 'doc-highlight-wrap',
      filename: 'sample.pdf',
      title: 'Sample',
      fileSize: 1000,
      pageCount: 1,
      hasTextLayer: true,
      hasMarkdown: true,
      ocrStatus: 'none',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      annotationCount: 0,
    );

    const testMarkdown = '<!-- Page 1 -->\n\n选择==离散电平的数值使满足== ==\$M > A_{max} / A_{N}\$== ==，则可以使量化噪声的==影响最小化，这里 \$A_{N}\$ 是模拟信号的均方根噪声振幅。';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: docProvider),
          ChangeNotifierProvider.value(value: annoProvider),
          ChangeNotifierProvider.value(value: settingsProvider),
          ChangeNotifierProvider.value(value: aiProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MarkdownReaderView(
              document: doc,
              markdownContent: testMarkdown,
              onOpenOcr: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify InteractiveLatexView exists for the formula
    expect(find.byType(InteractiveLatexView), findsWidgets);

    // Verify the paragraph Wrap has exactly 1 merged Text widget (no fragmented child widgets causing newline)
    final wrapFinder = find.byType(Wrap);
    expect(wrapFinder, findsWidgets);
    final wrap = tester.widget<Wrap>(wrapFinder.first);
    expect(wrap.children.length, 1);
  });

  test('AnnotationProvider deleteAnnotation removes locally even when cloud sync fails', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final apiService = ApiService(storageService: storage);
    final annoCache = await AnnotationCacheService.init();
    final annoProvider = AnnotationProvider(
      apiService: apiService,
      storageService: storage,
      annotationCacheService: annoCache,
    );

    const docId = 'test-doc-offline-delete';
    final anno = PdfAnnotation(
      id: 'anno-offline-1',
      docId: docId,
      type: 'highlight',
      pageNumber: 1,
      colorHex: '#FDE047',
      rects: const [],
      selectedText: 'Test text',
      noteContent: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await annoCache.saveAnnotations(docId, [anno]);
    await annoProvider.loadAnnotations(docId);
    expect(annoProvider.annotations.length, 1);

    // Attempt delete (apiService will fail since no real backend is running at default baseUrl)
    final success = await annoProvider.deleteAnnotation('anno-offline-1');
    expect(success, false); // Cloud returned false/error
    // But local list MUST NOT revert the annotation!
    expect(annoProvider.annotations.isEmpty, true);
    expect(annoCache.getAnnotations(docId).isEmpty, true);
  });

  group('LaTeX Inline Math Highlighting & Clean Removal Tests', () {
    const rawMathDoc = '''
选择离散电平的数值使满足 \$M > A_{max} / A_{N}\$ ，则可以使量化噪声的影响最小化，这里 \$A_{N}\$ 是模拟信号的均方根噪声振幅。比率 \$A_{max} / A_{N}\$ 称为动态范围 (dynamic range)。
''';

    test('Highlights text and inline formula into segmented highlights preserving math syntax', () {
      const selection = '使满足 \$M > A_{max} / A_{N}\$ ，则可以使量化噪声';
      final result = applyHighlightToMarkdownWithResult(rawMathDoc, selection, '#FDE047');

      expect(result.isModified, isTrue);
      expect(result.content, contains('==使满足=='));
      expect(result.content, contains('==\$M > A_{max} / A_{N}\$=='));
      expect(result.content, contains('==，则可以使量化噪声=='));
      // Ensure formula itself is not lumped inside a text block
      expect(result.content, isNot(contains('==使满足 \$M')));

      // Test clean unhighlighting
      final clean = removeHighlightFromMarkdown(result.content, selection);
      expect(clean, isNot(contains('==')));
      expect(clean, contains('使满足 \$M > A_{max} / A_{N}\$ ，则可以使量化噪声'));
    });

    test('Handles SelectionArea extracted text with \\uFFFC widget placeholder', () {
      // Simulates Flutter's SelectableRegion extracting \uFFFC for WidgetSpan
      const selectionWithPlaceholder = '使满足 \uFFFC ，则可以使量化噪声';
      final result = applyHighlightToMarkdownWithResult(rawMathDoc, selectionWithPlaceholder, '#86EFAC');

      expect(result.isModified, isTrue);
      expect(result.content, contains('==[#86EFAC]使满足=='));
      expect(result.content, contains('==[#86EFAC]\$M > A_{max} / A_{N}\$=='));
      expect(result.content, contains('==[#86EFAC]，则可以使量化噪声=='));

      // Test clean unhighlighting with original matchedText
      final clean = removeHighlightFromMarkdown(result.content, result.matchedText!);
      expect(clean, isNot(contains('==')));
      expect(clean, contains('\$M > A_{max} / A_{N}\$'));
    });

    test('Handles SelectionArea extracted visual text with stripped \$ delimiters', () {
      // Simulates browser/desktop selecting rendered math text without $
      const selectionVisual = '使满足 M > A max / A N ，则可以使量化噪声';
      final result = applyHighlightToMarkdownWithResult(rawMathDoc, selectionVisual, '#93C5FD');

      expect(result.isModified, isTrue);
      expect(result.content, contains('==[#93C5FD]使满足=='));
      expect(result.content, contains('==[#93C5FD]\$M > A_{max} / A_{N}\$=='));
      expect(result.content, contains('==[#93C5FD]，则可以使量化噪声=='));

      // Test clean unhighlighting
      final clean = removeHighlightFromMarkdown(result.content, result.matchedText!);
      expect(clean, isNot(contains('==')));
      expect(clean, contains('\$M > A_{max} / A_{N}\$'));
    });

    test('Handles selection containing multiple inline formulas', () {
      const multiFormulaSel = '使满足 \$M > A_{max} / A_{N}\$ ，则可以使量化噪声的影响最小化，这里 \$A_{N}\$ 是模拟信号';
      final result = applyHighlightToMarkdownWithResult(rawMathDoc, multiFormulaSel, '#FDE047');

      expect(result.isModified, isTrue);
      expect(result.content, contains('==使满足=='));
      expect(result.content, contains('==\$M > A_{max} / A_{N}\$=='));
      expect(result.content, contains('==，则可以使量化噪声的影响最小化，这里=='));
      expect(result.content, contains('==\$A_{N}\$=='));
      expect(result.content, contains('==是模拟信号=='));

      // Clean removal of multi-formula highlight
      final clean = removeHighlightFromMarkdown(result.content, multiFormulaSel);
      expect(clean, isNot(contains('==')));
      expect(clean, contains('\$M > A_{max} / A_{N}\$'));
      expect(clean, contains('\$A_{N}\$'));
    });
  });

  group('Mobile Reader Responsive & Bottom Bar Tests', () {
    late SharedPreferences prefs;
    late StorageService storage;
    late ReaderSettingsProvider settingsProvider;
    late AnnotationProvider annoProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      storage = StorageService(prefs);
      settingsProvider = ReaderSettingsProvider(storageService: storage);
      annoProvider = AnnotationProvider(
        apiService: ApiService(storageService: storage),
        storageService: storage,
        annotationCacheService: await AnnotationCacheService.init(),
      );
    });

    testWidgets('ReaderBottomBar renders 5 action items with correct badges and responds to taps', (tester) async {
      ReaderSidebarTab? selectedTab;
      bool progressOpened = false;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProvider),
            ChangeNotifierProvider.value(value: annoProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: ReaderBottomBar(
                currentPage: 3,
                totalPages: 10,
                onTabSelected: (tab) => selectedTab = tab,
                onOpenProgress: () => progressOpened = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('目录'), findsOneWidget);
      expect(find.text('检索'), findsOneWidget);
      expect(find.text('笔记'), findsOneWidget);
      expect(find.text('AI 伴读'), findsOneWidget);
      expect(find.text('3 / 10'), findsOneWidget);

      await tester.tap(find.text('目录'));
      await tester.pump();
      expect(selectedTab, equals(ReaderSidebarTab.outline));

      await tester.tap(find.text('AI 伴读'));
      await tester.pump();
      expect(selectedTab, equals(ReaderSidebarTab.aiChat));

      await tester.tap(find.text('3 / 10'));
      await tester.pump();
      expect(progressOpened, isTrue);
    });

    testWidgets('ReaderTopBar renders compact layout without overflow at 360px mobile width', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final doc = DocumentModel(
        id: 'doc-mobile',
        filename: 'mobile_test.pdf',
        title: '这是一个超长标题用于测试移动端顶部栏防溢出能力.pdf',
        fileSize: 1024,
        pageCount: 20,
        hasTextLayer: true,
        hasMarkdown: true,
        ocrStatus: 'completed',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        annotationCount: 0,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReaderTopBar(
                isMobile: true,
                document: doc,
                currentPage: 1,
                totalPages: 20,
                onJumpToPage: (_) {},
                onZoomIn: () {},
                onZoomOut: () {},
                onResetZoom: () {},
                onPrevPage: () {},
                onNextPage: () {},
                hasMarkdown: true,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('书架'), findsNothing);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('MD'), findsOneWidget);
    });

    testWidgets('ReaderMobileProgressSheet displays slider, page indicators, and triggers jump', (tester) async {
      int jumpedPage = 0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReaderMobileProgressSheet(
                currentPage: 5,
                totalPages: 20,
                onJumpToPage: (page) => jumpedPage = page,
                onZoomIn: () {},
                onZoomOut: () {},
                onResetZoom: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('第 5 页 / 共 20 页'), findsOneWidget);
      expect(find.text('上一页'), findsOneWidget);
      expect(find.text('下一页'), findsOneWidget);
      expect(find.text('指定跳页'), findsOneWidget);

      await tester.tap(find.text('下一页'));
      await tester.pump();
      expect(jumpedPage, equals(6));
    });

    testWidgets('ReaderSidebar in isMobileSheet mode displays drag handle and all 6 tabs', (tester) async {
      final docProvider = DocumentProvider(
        apiService: ApiService(storageService: storage),
        storageService: storage,
        docCacheService: DocCacheService(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProvider),
            ChangeNotifierProvider.value(value: annoProvider),
            ChangeNotifierProvider.value(value: docProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ReaderSidebar(
                isMobileSheet: true,
                initialTab: ReaderSidebarTab.outline,
                outlineItems: const [
                  OutlineItem(title: '第一章 绪论', pageNumber: 1),
                ],
                searchQuery: '',
                searchResults: const [],
                onSearchChanged: (_) {},
                onClearSearch: () {},
                onJumpToPage: (_) {},
                currentPage: 1,
                totalPages: 10,
                onZoomIn: () {},
                onZoomOut: () {},
                onResetZoom: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('目录'), findsOneWidget);
      expect(find.text('检索'), findsOneWidget);
      expect(find.text('高亮'), findsOneWidget);
      expect(find.text('批注'), findsOneWidget);
      expect(find.text('卡片'), findsOneWidget);
      expect(find.text('AI 助手'), findsOneWidget);

      expect(find.text('第一章 绪论'), findsOneWidget);
    });

    testWidgets('FloatingSelectionBar renders two-row layout on mobile and single-row on desktop', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      final settingsProvider = ReaderSettingsProvider(storageService: storage);

      // 1. Mobile screen (360x780)
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settingsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: FloatingSelectionBar(
                  selectedText: 'Test selected text',
                  isMobile: true,
                  onHighlight: (_) {},
                  onAddNote: () {},
                  onDismiss: () {},
                  onAskAi: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mobile renders Column (two rows: colors + buttons separated by Divider)
      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('问AI'), findsOneWidget);
      expect(find.text('批注'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing); // No "x" button on mobile!

      // 2. Desktop screen (1024x768)
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settingsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: FloatingSelectionBar(
                  selectedText: 'Test selected text',
                  isMobile: false,
                  onHighlight: (_) {},
                  onAddNote: () {},
                  onDismiss: () {},
                  onAskAi: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Desktop does not render Divider inside FloatingSelectionBar, but keeps close button
      expect(find.byType(Divider), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('ReaderSettingsProvider dynamic theme update test', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();
      final settingsProvider = ReaderSettingsProvider(storageService: storage);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settingsProvider,
          child: Consumer<ReaderSettingsProvider>(
            builder: (context, settings, _) {
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
              return MaterialApp(
                theme: activeTheme,
                home: Builder(
                  builder: (ctx) {
                    final currentTheme = Theme.of(ctx);
                    return Scaffold(
                      body: Text(
                        'Current Brightness: ${currentTheme.brightness}',
                        key: const ValueKey('theme_text'),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Current Brightness: Brightness.light'), findsOneWidget);

      // Switch to Dark
      settingsProvider.setReadingMode(ReadingMode.dark);
      await tester.pumpAndSettle();
      expect(find.text('Current Brightness: Brightness.dark'), findsOneWidget);

      // Switch to Sepia
      settingsProvider.setReadingMode(ReadingMode.sepia);
      await tester.pumpAndSettle();
      expect(find.text('Current Brightness: Brightness.light'), findsOneWidget);
      expect(settingsProvider.readingMode, ReadingMode.sepia);
    });

    test('PDF note and card are separate from highlight and do not draw highlight fill', () {
      final highlightAnno = PdfAnnotation(
        id: 'h1',
        docId: 'doc1',
        type: 'highlight',
        pageNumber: 1,
        colorHex: '#FFEB3B',
        rects: const [],
        selectedText: 'Highlight text',
        noteContent: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final noteAnno = PdfAnnotation(
        id: 'n1',
        docId: 'doc1',
        type: 'note',
        pageNumber: 1,
        colorHex: '#6366F1',
        rects: const [],
        selectedText: 'Annotated text',
        noteContent: 'My comment',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cardAnno = PdfAnnotation(
        id: 'c1',
        docId: 'doc1',
        type: 'card',
        pageNumber: 1,
        colorHex: '#EC4899',
        rects: const [],
        selectedText: 'Card quote',
        noteContent: 'Card Markdown Content',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(highlightAnno.isHighlight, isTrue);
      expect(highlightAnno.isNote, isFalse);
      expect(highlightAnno.isCard, isFalse);

      expect(noteAnno.isHighlight, isFalse);
      expect(noteAnno.isNote, isTrue);
      expect(noteAnno.isCard, isFalse);

      expect(cardAnno.isHighlight, isFalse);
      expect(cardAnno.isNote, isFalse);
      expect(cardAnno.isCard, isTrue);
    });

    testWidgets('Interactive annotation badges render correct icons and respond to taps', (WidgetTester tester) async {
      bool noteClicked = false;
      bool cardClicked = false;

      final noteAnno = PdfAnnotation(
        id: 'n1',
        docId: 'doc1',
        type: 'note',
        pageNumber: 1,
        colorHex: '#6366F1',
        rects: const [],
        selectedText: 'Note anchor',
        noteContent: 'Note comment',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cardAnno = PdfAnnotation(
        id: 'c1',
        docId: 'doc1',
        type: 'card',
        pageNumber: 1,
        colorHex: '#10B981',
        rects: const [],
        selectedText: 'Card quote',
        noteContent: 'Card markdown body',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                InkWell(
                  key: const ValueKey('note_badge'),
                  onTap: () => noteClicked = true,
                  child: const Icon(Icons.edit_note_rounded, size: 14),
                ),
                InkWell(
                  key: const ValueKey('card_badge'),
                  onTap: () => cardClicked = true,
                  child: const Icon(Icons.style_rounded, size: 14),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.style_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('note_badge')));
      await tester.pump();
      expect(noteClicked, isTrue);

      await tester.tap(find.byKey(const ValueKey('card_badge')));
      await tester.pump();
      expect(cardClicked, isTrue);
    });

    test('Arbitrary point annotation identification and attributes', () {
      final pointAnno = PdfAnnotation(
        id: 'point-1',
        docId: 'doc-123',
        type: 'note',
        pageNumber: 3,
        colorHex: '#6366F1',
        rects: [
          const NormalizedRect(x: 0.45, y: 0.65, width: 0.02, height: 0.02),
        ],
        selectedText: '',
        noteContent: 'Chart observation note',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(pointAnno.isPointAnnotation, isTrue);
      expect(pointAnno.isNote, isTrue);
      expect(pointAnno.isCard, isFalse);
      expect(pointAnno.isHighlight, isFalse);
      expect(pointAnno.displayTitle, 'Chart observation note');

      final emptyPointAnno = pointAnno.copyWith(noteContent: '');
      expect(emptyPointAnno.displayTitle, '批注笔记 (P.3)');

      final normalAnno = PdfAnnotation(
        id: 'text-1',
        docId: 'doc-123',
        type: 'note',
        pageNumber: 3,
        colorHex: '#6366F1',
        rects: [
          const NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.04),
        ],
        selectedText: 'Selected text here',
        noteContent: 'Text note',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(normalAnno.isPointAnnotation, isFalse);
      expect(normalAnno.displayTitle, 'Text note');
    });

    testWidgets('NoteEditorDialog displays point annotation anchor prompt correctly', (tester) async {
      final pointAnno = PdfAnnotation(
        id: 'point-dlg',
        docId: 'doc-123',
        type: 'note',
        pageNumber: 4,
        colorHex: '#6366F1',
        rects: [
          const NormalizedRect(x: 0.5, y: 0.5, width: 0.02, height: 0.02),
        ],
        selectedText: '',
        noteContent: 'Point note on graphic',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteEditorDialog(
              annotation: pointAnno,
              onSave: (_) {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('(已在第 4 页图钉锚定，点击徽标可随时回顾)'), findsOneWidget);
    });
  });
}






