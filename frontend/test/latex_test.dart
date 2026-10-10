import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

void main() {
  testWidgets('Test MarkdownBody imageBuilder and imageDirectory', (tester) async {
    const md = '![Alt Text](images/sample.jpg)';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: md,
            sizedImageBuilder: (config) {
              return Container(key: const ValueKey('custom_image'));
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('custom_image')), findsOneWidget);
  });
}
