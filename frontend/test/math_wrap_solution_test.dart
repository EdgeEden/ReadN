import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:frontend/views/reader/components/markdown_reader_view.dart';

void main() {
  testWidgets('Verify returning Text.rich from _MarkElementBuilder merges text without line break', (tester) async {
    const rawMd = '<!-- Page 1 -->\n\n选择==离散电平的数值使满足== ==\$M > A_{max} / A_{N}\$== ==，则可以使量化噪声的==影响最小化，这里 \$A_{N}\$ 是模拟信号的均方根噪声振幅。比率 \$A_{max} / A_{N}\$ 称为动态范围 (dynamic range) ，通常用对数形式表示为分贝数：';

    // We create the custom builders with the proposed change:
    // When mark finishes, wrap container in Text.rich(TextSpan(children: [WidgetSpan(child: container)]))
    Widget markBuilder(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
      final container = Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: Colors.yellow.withOpacity(0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.yellow),
        ),
        child: Text(element.textContent, style: preferredStyle),
      );

      return Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: container,
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: MarkdownBody(
              data: rawMd,
              extensionSet: md.ExtensionSet(
                md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                [
                  LatexInlineSyntax(),
                  MarkdownHighlightInlineSyntax(),
                  ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                ],
              ),
              builders: {
                'latex': _TestLatexBuilder(),
                'mark': _TestMarkBuilder(markBuilder),
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Wrap widget children count is exactly 1 (all inlines merged)
    final wrapFinder = find.byType(Wrap);
    expect(wrapFinder, findsOneWidget);
    final wrap = tester.widget<Wrap>(wrapFinder.first);
    expect(wrap.children.length, 1);

    // Verify the single Text widget contains both the prefixes and the subsequent text
    final textWidget = tester.widget<Text>(find.byType(Text).first);
    final fullPlainText = textWidget.textSpan?.toPlainText() ?? '';
    expect(fullPlainText, contains('选择'));
    expect(fullPlainText, contains('影响最小化'));
    print('SUCCESS: Verified Wrap has exactly 1 merged Text widget!');
    print('Plain text: $fullPlainText');
  });
}

class _TestLatexBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Text('\$${element.textContent}\$', style: preferredStyle),
          ),
        ],
      ),
    );
  }
}

class _TestMarkBuilder extends MarkdownElementBuilder {
  final Widget Function(BuildContext, md.Element, TextStyle?, TextStyle?) builder;
  _TestMarkBuilder(this.builder);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return builder(context, element, preferredStyle, parentStyle);
  }
}
