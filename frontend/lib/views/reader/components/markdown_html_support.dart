import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../theme/app_theme.dart';

/// Parses inline CSS style string like "color: #ff0000; font-size: 16px; background-color: #fef08a;"
Map<String, String> parseCssProperties(String? style) {
  if (style == null || style.trim().isEmpty) return {};
  final Map<String, String> props = {};
  final declarations = style.split(';');
  for (final decl in declarations) {
    final parts = decl.split(':');
    if (parts.length >= 2) {
      final key = parts[0].trim().toLowerCase();
      final val = parts.sublist(1).join(':').trim();
      if (key.isNotEmpty && val.isNotEmpty) {
        props[key] = val;
      }
    }
  }
  return props;
}

/// Resolves CSS color string to Flutter Color
Color? parseHtmlColor(String? colorStr) {
  if (colorStr == null || colorStr.trim().isEmpty) return null;
  final s = colorStr.trim().toLowerCase();

  // Named HTML colors
  const namedColors = {
    'red': Colors.red,
    'blue': Colors.blue,
    'green': Colors.green,
    'yellow': Color(0xFFFACC15),
    'orange': Colors.orange,
    'purple': Colors.purple,
    'pink': Colors.pink,
    'teal': Colors.teal,
    'cyan': Colors.cyan,
    'indigo': Colors.indigo,
    'gray': Colors.grey,
    'grey': Colors.grey,
    'black': Colors.black,
    'white': Colors.white,
    'brown': Colors.brown,
    'lime': Colors.lime,
    'amber': Colors.amber,
    'deeporange': Colors.deepOrange,
    'lightblue': Colors.lightBlue,
    'lightgreen': Colors.lightGreen,
    'transparent': Colors.transparent,
  };

  if (namedColors.containsKey(s)) {
    return namedColors[s];
  }

  // Hex format (#RGB, #RRGGBB, #AARRGGBB)
  if (s.startsWith('#')) {
    try {
      return AppTheme.parseHexColor(s);
    } catch (_) {}
  }

  // rgb(...) or rgba(...)
  if (s.startsWith('rgb')) {
    final match = RegExp(r"rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)").firstMatch(s);
    if (match != null) {
      final r = int.tryParse(match.group(1) ?? '0') ?? 0;
      final g = int.tryParse(match.group(2) ?? '0') ?? 0;
      final b = int.tryParse(match.group(3) ?? '0') ?? 0;
      final aVal = double.tryParse(match.group(4) ?? '1.0') ?? 1.0;
      final a = (aVal * 255).round().clamp(0, 255);
      return Color.fromARGB(a, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }

  return null;
}

/// Robustly applies Markdown fluorescent highlight (`==text==` or `==[#HEX]text==`) to markdown content,
/// correctly preserving line prefixes (Headings `#`, list markers `-`/`*`/`·`/`•`/`1.`/`1、`/`（1）`, blockquotes `>`) and
/// properly handling multiline selections without corrupting Markdown block syntax.
String applyHighlightToMarkdown(String content, String selectedText, String colorHex) {
  if (content.isEmpty || selectedText.trim().isEmpty) return content;

  final trimmed = selectedText.trim();
  final normalizedHex = colorHex.toUpperCase();
  final tagPrefix = (normalizedHex == '#FDE047' || normalizedHex == 'FDE047')
      ? '=='
      : '==[$normalizedHex]';

  // Helper to wrap text safely without crossing any newlines
  String wrapSegment(String text) {
    if (text.isEmpty) return text;
    if (!text.contains('\n')) {
      return '$tagPrefix$text==';
    }
    return text.split('\n').map((line) {
      final lineTrimmed = line.trim();
      if (lineTrimmed.isEmpty) return line;
      final leadingMatch = RegExp(r'^\s*').firstMatch(line)?.group(0) ?? '';
      final trailingMatch = RegExp(r'\s*$').firstMatch(line)?.group(0) ?? '';
      final core = line.substring(leadingMatch.length, line.length - trailingMatch.length);
      if (core.isEmpty) return line;
      return '$leadingMatch$tagPrefix$core==$trailingMatch';
    }).join('\n');
  }

  // 1. Split selectedText by newline characters (\r\n, \r, \n) to handle multiline selections segment-by-segment
  final rawLines = trimmed
      .split(RegExp(r'\r?\n|\r'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('<!--') && !l.startsWith('-->'))
      .toList();

  if (rawLines.isEmpty) return content;

  var updatedContent = content;

  for (final rawLine in rawLines) {
    // Strip existing highlight syntax from the raw line if present in selection
    final line = rawLine.replaceAll(
      RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?|==|<mark(?:\s+[^>]*)?>|</mark>'),
      '',
    ).trim();
    if (line.isEmpty) continue;

    final lineReplacement = '$tagPrefix$line==';
    if (updatedContent.contains(lineReplacement)) {
      continue; // Already highlighted with current tag
    }

    // A. Check if the line is an entire heading line: e.g. "## Heading"
    final headingLineRegex = RegExp(
      r'^([ \t]*#{1,6}[ \t]+)' + RegExp.escape(line) + r'([ \t]*)$',
      multiLine: true,
    );
    if (headingLineRegex.hasMatch(updatedContent)) {
      updatedContent = updatedContent.replaceFirstMapped(
        headingLineRegex,
        (m) => '${m.group(1)}$tagPrefix$line==${m.group(2)}',
      );
      continue;
    }

    // B. Check if inside a heading line: e.g. "## 1. Entering..." where line is "Entering..."
    final insideHeadingRegex = RegExp(
      r'^([ \t]*#{1,6}[ \t]+.*?)(?:' + RegExp.escape(line) + r')(.*)$',
      multiLine: true,
    );
    if (insideHeadingRegex.hasMatch(updatedContent)) {
      updatedContent = updatedContent.replaceFirstMapped(
        insideHeadingRegex,
        (m) => '${m.group(1)}$tagPrefix$line==${m.group(2)}',
      );
      continue;
    }

    // C. Check if list item or blockquote: e.g. "- Item" / "· Item" / "• Item" / "1. Item" / "1、Item" / "（1）Item" / "> Quote"
    final listOrQuoteRegex = RegExp(
      r'^([ \t]*(?:[-*+•·]|\d+[\.、]|[（(]\d+[）)]|>)[ \t]*)' + RegExp.escape(line) + r'([ \t]*)$',
      multiLine: true,
    );
    if (listOrQuoteRegex.hasMatch(updatedContent)) {
      updatedContent = updatedContent.replaceFirstMapped(
        listOrQuoteRegex,
        (m) => '${m.group(1)}$tagPrefix$line==${m.group(2)}',
      );
      continue;
    }

    // D. Direct exact substring containment
    if (updatedContent.contains(line)) {
      updatedContent = updatedContent.replaceFirst(line, lineReplacement);
      continue;
    }

    // E. Matching with flexible whitespace and/or existing embedded highlight tags (supports both spaced words and CJK character sequences)
    final tagOrSpace = r'(?:\s+|==(?:\[#[0-9a-fA-F]{3,8}\])?|==|<mark(?:\s+[^>]*)?>|</mark>)*';
    bool matched = false;

    final tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length > 1) {
      final flexPattern = tokens.map((t) => RegExp.escape(t)).join(tagOrSpace);
      final flexRegex = RegExp(flexPattern);
      final match = flexRegex.firstMatch(updatedContent);
      if (match != null) {
        final matchedSpan = match.group(0)!;
        final cleanMatchedText = matchedSpan.replaceAll(
          RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?|==|<mark(?:\s+[^>]*)?>|</mark>'),
          '',
        );
        updatedContent = updatedContent.replaceFirst(matchedSpan, wrapSegment(cleanMatchedText));
        matched = true;
      }
    }

    if (!matched) {
      final chars = line.split('').where((c) => c.trim().isNotEmpty).toList();
      if (chars.isNotEmpty) {
        final charPattern = chars.map((c) => RegExp.escape(c)).join(tagOrSpace);
        final charRegex = RegExp(charPattern);
        final match = charRegex.firstMatch(updatedContent);
        if (match != null) {
          final matchedSpan = match.group(0)!;
          final cleanMatchedText = matchedSpan.replaceAll(
            RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?|==|<mark(?:\s+[^>]*)?>|</mark>'),
            '',
          );
          updatedContent = updatedContent.replaceFirst(matchedSpan, wrapSegment(cleanMatchedText));
        }
      }
    }
  }

  return updatedContent;
}

/// Robustly removes highlights (`==...==` or `<mark>...</mark>`) from markdown content
String removeHighlightFromMarkdown(String markdown, String targetText) {
  if (markdown.trim().isEmpty || targetText.trim().isEmpty) return markdown;

  final trimmed = targetText.trim();
  final cleanText = trimmed.replaceAll(
    RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?|==|<mark(?:\s+[^>]*)?>|</mark>'),
    '',
  ).trim();
  if (cleanText.isEmpty) return markdown;

  String normalize(String s) {
    return s
        .replaceAll(RegExp(r'[\s\r\n\t]+'), '')
        .replaceAll(RegExp(r'^(\$\$|\$|\\\[|\\\()|(\$\$|\$|\\\]|\\\))$'), '')
        .toLowerCase();
  }

  final cleanNorm = normalize(cleanText);
  if (cleanNorm.isEmpty) return markdown;

  // Split cleanText into normalized lines/tokens for precise matching
  final cleanLines = cleanText
      .split(RegExp(r'\r?\n|\r'))
      .map((l) => l.replaceFirst(
            RegExp(r'^[ \t]*(?:#{1,6}[ \t]+(?:\d+[\.、][ \t]*)?|[-*+•·][ \t]+|\d+[\.、][ \t]*|[（(]\d+[）)][ \t]*|>[ \t]*)'),
            '',
          ).trim())
      .where((l) => l.isNotEmpty && !l.startsWith('<!--') && !l.startsWith('-->'))
      .map(normalize)
      .where((l) => l.isNotEmpty)
      .toSet();

  var result = markdown;

  // 1. Markdown highlight blocks: ==[#HEX]content== or ==content==
  final mdHighlightRegex = RegExp(r'==(?:\[#[0-9a-fA-F]{3,8}\])?([\s\S]*?)==');
  result = result.replaceAllMapped(mdHighlightRegex, (match) {
    final rawInside = match.group(1) ?? '';
    final insideNorm = normalize(rawInside);
    if (insideNorm.isEmpty) return rawInside;

    // Check if insideNorm is part of cleanNorm or any cleanLines
    if (cleanNorm.contains(insideNorm) ||
        cleanLines.any((line) => line == insideNorm || (insideNorm.length >= 2 && line.contains(insideNorm)))) {
      return rawInside;
    }

    // Check if insideNorm contains cleanNorm (partial removal within a highlight block)
    if (insideNorm.contains(cleanNorm) && cleanNorm.length >= 2) {
      final cleanEscaped = RegExp.escape(cleanText.trim());
      final subRegex = RegExp(cleanEscaped);
      if (subRegex.hasMatch(rawInside)) {
        return rawInside;
      }
      return rawInside;
    }

    return match.group(0)!;
  });

  // 2. HTML mark tag blocks: <mark ...>content</mark>
  final htmlMarkRegex = RegExp(r'<mark(?:\s+[^>]*)?>([\s\S]*?)</mark>', caseSensitive: false);
  result = result.replaceAllMapped(htmlMarkRegex, (match) {
    final rawInside = match.group(1) ?? '';
    final insideNorm = normalize(rawInside);
    if (insideNorm.isEmpty) return rawInside;

    if (cleanNorm.contains(insideNorm) ||
        cleanLines.any((line) => line == insideNorm || (insideNorm.length >= 2 && line.contains(insideNorm)))) {
      return rawInside;
    }

    return match.group(0)!;
  });

  return result;
}

/// Preprocesses Markdown containing raw HTML blocks (like `<table>`, `<div>`, `<p>`, `<h1>`-`<h6>`, `<ul>`, `<ol>`, etc.)
/// into standardized GFM markdown or normalized custom HTML elements that flutter_markdown can natively render.
String preprocessMarkdownHtml(String raw) {
  if (raw.trim().isEmpty) return raw;

  var result = raw;

  // 1. Convert HTML Tables: <table ...> ... </table> to Markdown GFM Table
  final tableRegex = RegExp(r"""<table(?:\s+[^>]*)?>([\s\S]*?)</table>""", caseSensitive: false);
  result = result.replaceAllMapped(tableRegex, (match) {
    final tableBody = match.group(1) ?? '';
    final rows = <List<String>>[];

    final trRegex = RegExp(r"""<tr(?:\s+[^>]*)?>([\s\S]*?)</tr>""", caseSensitive: false);
    final cellRegex = RegExp(r"""<(th|td)(?:\s+[^>]*)?>([\s\S]*?)</\1>""", caseSensitive: false);

    for (final trMatch in trRegex.allMatches(tableBody)) {
      final trContent = trMatch.group(1) ?? '';
      final rowCells = <String>[];

      for (final cellMatch in cellRegex.allMatches(trContent)) {
        var cellText = cellMatch.group(2)?.trim() ?? '';
        // Clean up linebreaks inside cells and escape pipe characters
        cellText = cellText.replaceAll(RegExp(r'\r?\n+'), ' ').replaceAll('|', r'\|');
        rowCells.add(cellText);
      }

      if (rowCells.isNotEmpty) {
        rows.add(rowCells);
      }
    }

    if (rows.isEmpty) return '';

    // Determine max columns
    int maxCols = 0;
    for (final row in rows) {
      if (row.length > maxCols) maxCols = row.length;
    }
    if (maxCols == 0) return '';

    final sb = StringBuffer();
    sb.writeln();

    // Header row
    final headerCells = List<String>.from(rows.first);
    while (headerCells.length < maxCols) {
      headerCells.add('');
    }
    sb.writeln('| ${headerCells.join(' | ')} |');

    // Separator row
    final sepCells = List<String>.filled(maxCols, '---');
    sb.writeln('| ${sepCells.join(' | ')} |');

    // Body rows (skip row 0 as it was used as header)
    for (int r = 1; r < rows.length; r++) {
      final rowCells = List<String>.from(rows[r]);
      while (rowCells.length < maxCols) {
        rowCells.add('');
      }
      sb.writeln('| ${rowCells.join(' | ')} |');
    }

    sb.writeln();
    return sb.toString();
  });

  // 2. Convert <div style="text-align: center;">...</div> or <center>...</center>
  final centerDivRegex = RegExp(
    r"""<div\s+style=["'][^"']*(?:text-align:\s*center|margin:\s*auto)[^"']*["']>([\s\S]*?)</div>""",
    caseSensitive: false,
  );
  result = result.replaceAllMapped(centerDivRegex, (m) {
    return '\n\n<center>${m.group(1)?.trim() ?? ''}</center>\n\n';
  });

  // 3. Normalize generic <div> and <p> blocks that are on their own lines
  final divBlockRegex = RegExp(r"""<div(?:\s+style=["']([^"']*)["'])*>([\s\S]*?)</div>""", caseSensitive: false);
  result = result.replaceAllMapped(divBlockRegex, (m) {
    final style = m.group(1);
    final content = m.group(2)?.trim() ?? '';
    if (style != null && style.isNotEmpty) {
      return '\n\n<span style="$style">$content</span>\n\n';
    }
    return '\n\n$content\n\n';
  });

  final pBlockRegex = RegExp(r"""<p(?:\s+style=["']([^"']*)["'])*>([\s\S]*?)</p>""", caseSensitive: false);
  result = result.replaceAllMapped(pBlockRegex, (m) {
    final style = m.group(1);
    final content = m.group(2)?.trim() ?? '';
    if (style != null && style.isNotEmpty) {
      return '\n\n<span style="$style">$content</span>\n\n';
    }
    return '\n\n$content\n\n';
  });

  // 4. Normalize <h1>..<h6> HTML headings to markdown headings
  for (int h = 1; h <= 6; h++) {
    final hRegex = RegExp('<h$h(?:\\s+[^>]*)?>([\\s\\S]*?)</h$h>', caseSensitive: false);
    final prefix = '#' * h;
    result = result.replaceAllMapped(hRegex, (m) {
      return '\n\n$prefix ${m.group(1)?.trim() ?? ''}\n\n';
    });
  }

  return result;
}

// -------------------------------------------------------------
// HTML Inline Syntaxes for markdown package
// -------------------------------------------------------------

/// Matches `<u>text</u>` or `<ins>text</ins>`
class HtmlUnderlineSyntax extends md.InlineSyntax {
  HtmlUnderlineSyntax() : super(r"""<(?:u|ins)(?:\s+style=["'][^"']*["'])*>((?:(?!</(?:u|ins)>)[\s\S])+?)</(?:u|ins)>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null || text.isEmpty) return false;

    final el = md.Element('u', [md.Text(text)]);
    parser.addNode(el);
    return true;
  }
}

/// Matches `<sub>text</sub>`
class HtmlSubscriptSyntax extends md.InlineSyntax {
  HtmlSubscriptSyntax() : super(r"""<sub>((?:(?!</sub>)[\s\S])+?)</sub>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null || text.isEmpty) return false;
    parser.addNode(md.Element('sub', [md.Text(text)]));
    return true;
  }
}

/// Matches `<sup>text</sup>`
class HtmlSuperscriptSyntax extends md.InlineSyntax {
  HtmlSuperscriptSyntax() : super(r"""<sup>((?:(?!</sup>)[\s\S])+?)</sup>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null || text.isEmpty) return false;
    parser.addNode(md.Element('sup', [md.Text(text)]));
    return true;
  }
}

/// Matches `<s>text</s>`, `<strike>text</strike>`, `<del>text</del>`
class HtmlStrikeSyntax extends md.InlineSyntax {
  HtmlStrikeSyntax() : super(r"""<(?:s|strike|del)>((?:(?!</(?:s|strike|del)>)[\s\S])+?)</(?:s|strike|del)>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null || text.isEmpty) return false;
    parser.addNode(md.Element('del', [md.Text(text)]));
    return true;
  }
}

/// Matches `<b>text</b>` or `<strong>text</strong>`
class HtmlBoldSyntax extends md.InlineSyntax {
  HtmlBoldSyntax() : super(r"""<(?:b|strong)>((?:(?!</(?:b|strong)>)[\s\S])+?)</(?:b|strong)>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null || text.isEmpty) return false;
    parser.addNode(md.Element('strong', [md.Text(text)]));
    return true;
  }
}

/// Matches `<i>text</i>` or `<em>text</em>`
class HtmlItalicSyntax extends md.InlineSyntax {
  HtmlItalicSyntax() : super(r"""<(?:i|em)>((?:(?!</(?:i|em)>)[\s\S])+?)</(?:i|em)>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null || text.isEmpty) return false;
    parser.addNode(md.Element('em', [md.Text(text)]));
    return true;
  }
}

/// Matches `<font color="..." size="..." face="...">text</font>`
class HtmlFontSyntax extends md.InlineSyntax {
  HtmlFontSyntax()
      : super(
          r"""<font(?:\s+(?:color=["']([^"']*)["']|size=["']([^"']*)["']|face=["']([^"']*)["']|style=["']([^"']*)["']|\w+=["'][^"']*["']))+>([\s\S]*?)</font>""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match.group(0) ?? '';
    final text = match.group(5) ?? match.group(1) ?? '';
    if (text.isEmpty && raw.isEmpty) return false;

    final el = md.Element('font', [md.Text(text)]);

    final colorMatch = RegExp(r"""color=["']([^"']*)["']""", caseSensitive: false).firstMatch(raw);
    if (colorMatch != null) el.attributes['color'] = colorMatch.group(1) ?? '';

    final sizeMatch = RegExp(r"""size=["']([^"']*)["']""", caseSensitive: false).firstMatch(raw);
    if (sizeMatch != null) el.attributes['size'] = sizeMatch.group(1) ?? '';

    final styleMatch = RegExp(r"""style=["']([^"']*)["']""", caseSensitive: false).firstMatch(raw);
    if (styleMatch != null) el.attributes['style'] = styleMatch.group(1) ?? '';

    parser.addNode(el);
    return true;
  }
}

/// Matches `<span style="..." class="...">text</span>`
class HtmlSpanSyntax extends md.InlineSyntax {
  HtmlSpanSyntax()
      : super(
          r"""<span(?:\s+style=["']([^"']*)["'])?(?:\s+class=["']([^"']*)["'])*>((?:(?!</span>)[\s\S])+?)</span>""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final style = match.group(1);
    final text = match.group(3) ?? match.group(2) ?? '';
    if (text.isEmpty) return false;

    final el = md.Element('span', [md.Text(text)]);
    if (style != null && style.isNotEmpty) el.attributes['style'] = style;
    parser.addNode(el);
    return true;
  }
}

/// Matches `<kbd>text</kbd>`
class HtmlKbdSyntax extends md.InlineSyntax {
  HtmlKbdSyntax() : super(r"""<kbd>([\s\S]*?)</kbd>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null || text.isEmpty) return false;
    parser.addNode(md.Element('kbd', [md.Text(text)]));
    return true;
  }
}

/// Matches `<small>text</small>` or `<big>text</big>`
class HtmlSmallBigSyntax extends md.InlineSyntax {
  HtmlSmallBigSyntax() : super(r"""<(small|big)>([\s\S]*?)</\1>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tag = match.group(1)?.toLowerCase() ?? 'small';
    final text = match.group(2);
    if (text == null || text.isEmpty) return false;
    parser.addNode(md.Element(tag, [md.Text(text)]));
    return true;
  }
}

/// Matches `<ruby>base<rt>annotation</rt></ruby>`
class HtmlRubySyntax extends md.InlineSyntax {
  HtmlRubySyntax()
      : super(
          r"""<ruby>([\s\S]*?)(?:<rp>[^<]*</rp>)?<rt>([\s\S]*?)</rt>(?:<rp>[^<]*</rp>)?</ruby>""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final base = match.group(1);
    final rt = match.group(2);
    if (base == null || base.isEmpty) return false;

    final el = md.Element('ruby', [md.Text(base)]);
    el.attributes['rt'] = rt ?? '';
    parser.addNode(el);
    return true;
  }
}

/// Matches `<abbr title="...">text</abbr>`
class HtmlAbbrSyntax extends md.InlineSyntax {
  HtmlAbbrSyntax()
      : super(
          r"""<abbr(?:\s+title=["']([^"']*)["'])?>([\s\S]*?)</abbr>""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final title = match.group(1) ?? '';
    final text = match.group(2);
    if (text == null || text.isEmpty) return false;

    final el = md.Element('abbr', [md.Text(text)]);
    el.attributes['title'] = title;
    parser.addNode(el);
    return true;
  }
}

/// Matches `<br>` or `<br/>` or `<br />`
class HtmlBreakSyntax extends md.InlineSyntax {
  HtmlBreakSyntax() : super(r"""<br\s*/?>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element('br', []));
    return true;
  }
}

/// Matches `<center>text</center>`
class HtmlCenterSyntax extends md.InlineSyntax {
  HtmlCenterSyntax() : super(r"""<center>([\s\S]*?)</center>""", caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final text = match.group(1);
    if (text == null) return false;
    parser.addNode(md.Element('center', [md.Text(text)]));
    return true;
  }
}

/// Matches `<details><summary>Title</summary>Content</details>`
class HtmlDetailsSyntax extends md.InlineSyntax {
  HtmlDetailsSyntax()
      : super(
          r"""<details>\s*<summary>([\s\S]*?)</summary>([\s\S]*?)</details>""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final summary = match.group(1)?.trim() ?? '详情';
    final content = match.group(2)?.trim() ?? '';

    final el = md.Element('details', [md.Text(content)]);
    el.attributes['summary'] = summary;
    parser.addNode(el);
    return true;
  }
}

/// Matches HTML Table `<table>...</table>`
class HtmlTableSyntax extends md.InlineSyntax {
  HtmlTableSyntax()
      : super(
          r"""<table(?:\s+[^>]*)?>([\s\S]*?)</table>""",
          caseSensitive: false,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final rawTable = match.group(0);
    if (rawTable == null || rawTable.isEmpty) return false;

    final el = md.Element('html-table', []);
    el.attributes['raw'] = rawTable;
    parser.addNode(el);
    return true;
  }
}

// -------------------------------------------------------------
// Flutter Markdown Element Builders for HTML Elements
// -------------------------------------------------------------

/// Renders `<u>` and `<ins>` with underline decoration
class HtmlUnderlineElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    return Text(
      text,
      style: (preferredStyle ?? const TextStyle()).copyWith(
        decoration: TextDecoration.underline,
        decorationColor: preferredStyle?.color,
      ),
    );
  }
}

/// Renders `<sub>` with subscript vertical offset & size
class HtmlSubscriptElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final baseSize = preferredStyle?.fontSize ?? 14.0;
    return Transform.translate(
      offset: Offset(0, baseSize * 0.22),
      child: Text(
        text,
        style: (preferredStyle ?? const TextStyle()).copyWith(
          fontSize: baseSize * 0.75,
        ),
      ),
    );
  }
}

/// Renders `<sup>` with superscript vertical offset & size
class HtmlSuperscriptElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final baseSize = preferredStyle?.fontSize ?? 14.0;
    return Transform.translate(
      offset: Offset(0, -baseSize * 0.32),
      child: Text(
        text,
        style: (preferredStyle ?? const TextStyle()).copyWith(
          fontSize: baseSize * 0.75,
        ),
      ),
    );
  }
}

/// Renders `<s>`, `<strike>`, `<del>` with line-through decoration
class HtmlStrikeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    return Text(
      text,
      style: (preferredStyle ?? const TextStyle()).copyWith(
        decoration: TextDecoration.lineThrough,
      ),
    );
  }
}

/// Renders `<font>` and `<span>` with custom CSS styles (color, background, font-size, etc.)
class HtmlStyledSpanElementBuilder extends MarkdownElementBuilder {
  final bool isDark;

  HtmlStyledSpanElementBuilder({required this.isDark});

  TextStyle _computeStyle(md.Element element, TextStyle? baseStyle) {
    var style = baseStyle ?? const TextStyle();

    // 1. Direct tag attributes
    final colorAttr = element.attributes['color'];
    if (colorAttr != null) {
      final c = parseHtmlColor(colorAttr);
      if (c != null) style = style.copyWith(color: c);
    }

    final sizeAttr = element.attributes['size'];
    if (sizeAttr != null) {
      final numVal = double.tryParse(sizeAttr);
      if (numVal != null) {
        style = style.copyWith(fontSize: (style.fontSize ?? 14.0) * (numVal / 3.0).clamp(0.6, 2.5));
      }
    }

    // 2. CSS style attribute
    final css = parseCssProperties(element.attributes['style']);
    if (css.containsKey('color')) {
      final c = parseHtmlColor(css['color']);
      if (c != null) style = style.copyWith(color: c);
    }

    if (css.containsKey('background-color') || css.containsKey('background')) {
      final bg = parseHtmlColor(css['background-color'] ?? css['background']);
      if (bg != null) style = style.copyWith(backgroundColor: bg);
    }

    if (css.containsKey('font-size')) {
      final fStr = css['font-size']!;
      if (fStr.endsWith('px')) {
        final px = double.tryParse(fStr.replaceAll('px', '').trim());
        if (px != null) style = style.copyWith(fontSize: px);
      } else if (fStr.endsWith('em') || fStr.endsWith('%')) {
        final mul = double.tryParse(fStr.replaceAll(RegExp(r'[em%]'), '').trim());
        if (mul != null) {
          final scale = fStr.endsWith('%') ? mul / 100.0 : mul;
          style = style.copyWith(fontSize: (style.fontSize ?? 14.0) * scale);
        }
      }
    }

    if (css.containsKey('font-weight')) {
      final fw = css['font-weight']!;
      if (fw == 'bold' || fw == '700' || fw == '800' || fw == '900') {
        style = style.copyWith(fontWeight: FontWeight.bold);
      } else if (fw == 'normal' || fw == '400') {
        style = style.copyWith(fontWeight: FontWeight.normal);
      }
    }

    if (css.containsKey('font-style')) {
      if (css['font-style'] == 'italic') {
        style = style.copyWith(fontStyle: FontStyle.italic);
      }
    }

    if (css.containsKey('text-decoration')) {
      final dec = css['text-decoration']!;
      if (dec.contains('underline')) {
        style = style.copyWith(decoration: TextDecoration.underline);
      } else if (dec.contains('line-through')) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
    }

    return style;
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    return Text(text, style: _computeStyle(element, preferredStyle));
  }
}

/// Renders `<kbd>` as a physical keyboard keycap badge
class HtmlKbdElementBuilder extends MarkdownElementBuilder {
  final bool isDark;

  HtmlKbdElementBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final baseSize = preferredStyle?.fontSize ?? 14.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            offset: const Offset(0, 1.5),
            blurRadius: 1,
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: baseSize * 0.85,
          fontWeight: FontWeight.bold,
          color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
        ),
      ),
    );
  }
}

/// Renders `<small>` and `<big>`
class HtmlSizeElementBuilder extends MarkdownElementBuilder {
  final double scale;

  HtmlSizeElementBuilder({required this.scale});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    return Text(
      text,
      style: (preferredStyle ?? const TextStyle()).copyWith(
        fontSize: (preferredStyle?.fontSize ?? 14.0) * scale,
      ),
    );
  }
}

/// Renders `<ruby>base<rt>annotation</rt></ruby>`
class HtmlRubyElementBuilder extends MarkdownElementBuilder {
  final bool isDark;

  HtmlRubyElementBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final baseText = element.textContent;
    final rtText = element.attributes['rt'] ?? '';
    final baseSize = preferredStyle?.fontSize ?? 14.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            rtText,
            style: TextStyle(
              fontSize: (baseSize * 0.65).clamp(8.0, 16.0),
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              height: 1.0,
            ),
          ),
          Text(
            baseText,
            style: preferredStyle ?? const TextStyle(),
          ),
        ],
      ),
    );
  }
}

/// Renders `<abbr title="...">text</abbr>` with dotted underline and tooltip
class HtmlAbbrElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final title = element.attributes['title'] ?? '';

    return Tooltip(
      message: title,
      child: Text(
        text,
        style: (preferredStyle ?? const TextStyle()).copyWith(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
        ),
      ),
    );
  }
}

/// Renders `<br>` line break
class HtmlBreakElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return const SizedBox(height: 8, width: double.infinity);
  }
}

/// Renders `<center>text</center>`
class HtmlCenterElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          element.textContent,
          textAlign: TextAlign.center,
          style: preferredStyle,
        ),
      ),
    );
  }
}

/// Renders interactive collapsible `<details><summary>Title</summary>Content</details>`
class HtmlDetailsElementBuilder extends MarkdownElementBuilder {
  final bool isDark;

  HtmlDetailsElementBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final summary = element.attributes['summary'] ?? '展开查看';
    final content = element.textContent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
          ),
          title: Text(
            summary,
            style: TextStyle(
              fontSize: preferredStyle?.fontSize ?? 14,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Text(
                content,
                style: (preferredStyle ?? const TextStyle()).copyWith(
                  height: 1.6,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders HTML Table `<table>...</table>`
class HtmlTableElementBuilder extends MarkdownElementBuilder {
  final bool isDark;

  HtmlTableElementBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final rawHtml = element.attributes['raw'] ?? '';
    if (rawHtml.isEmpty) return null;

    final rows = <List<String>>[];
    final isHeaderRow = <bool>[];

    final trRegex = RegExp(r"""<tr[^>]*>([\s\S]*?)</tr>""", caseSensitive: false);
    final cellRegex = RegExp(r"""<(th|td)[^>]*>([\s\S]*?)</\1>""", caseSensitive: false);

    for (final trMatch in trRegex.allMatches(rawHtml)) {
      final trContent = trMatch.group(1) ?? '';
      final rowCells = <String>[];
      bool isHeader = false;

      for (final cellMatch in cellRegex.allMatches(trContent)) {
        if (cellMatch.group(1)?.toLowerCase() == 'th') isHeader = true;
        final cellText = cellMatch.group(2)?.replaceAll(RegExp(r"""<[^>]*>"""), '').trim() ?? '';
        rowCells.add(cellText);
      }

      if (rowCells.isNotEmpty) {
        rows.add(rowCells);
        isHeaderRow.add(isHeader);
      }
    }

    if (rows.isEmpty) return null;

    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final headerBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final baseFontSize = preferredStyle?.fontSize ?? 14.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: TableBorder.all(color: borderColor, width: 0.8),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows.asMap().entries.map((entry) {
          final rowIdx = entry.key;
          final rowCells = entry.value;
          final isHeader = isHeaderRow[rowIdx];

          return TableRow(
            decoration: BoxDecoration(
              color: isHeader ? headerBg : Colors.transparent,
            ),
            children: rowCells.map((cellText) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  cellText,
                  style: (preferredStyle ?? const TextStyle()).copyWith(
                    fontSize: baseFontSize * 0.95,
                    fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                    color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

/// Renders `<mark>` elements as elegant rounded-rectangle badges with soft border, translucent background, and subtle shadow.
class CommonMarkElementBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final double? fontSize;
  final Color? textColor;

  CommonMarkElementBuilder({
    required this.isDark,
    this.fontSize,
    this.textColor,
  });

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return _buildMark(element, preferredStyle, parentStyle);
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return _buildMark(element, preferredStyle, null);
  }

  Widget? _buildMark(md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final colorHex = element.attributes['color'] ?? '#FDE047';
    Color baseColor;
    try {
      baseColor = AppTheme.parseHexColor(colorHex);
    } catch (_) {
      baseColor = const Color(0xFFFDE047);
    }

    final highlightBg = baseColor.withValues(alpha: isDark ? 0.30 : 0.22);
    final borderCol = baseColor.withValues(alpha: isDark ? 0.75 : 0.60);

    final effectiveStyle = (parentStyle ?? const TextStyle()).merge(preferredStyle);
    final effectiveFontSize = preferredStyle?.fontSize ?? parentStyle?.fontSize ?? fontSize ?? 14.0;
    final effectiveFontWeight = preferredStyle?.fontWeight ?? parentStyle?.fontWeight ?? FontWeight.w500;
    final textCol = preferredStyle?.color ?? parentStyle?.color ?? textColor ?? (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A));

    final finalTextStyle = effectiveStyle.copyWith(
      fontSize: effectiveFontSize,
      fontWeight: effectiveFontWeight,
      color: textCol,
      letterSpacing: 0.2,
    );

    final text = element.textContent;
    if (text.isEmpty) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: highlightBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: borderCol,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: isDark ? 0.20 : 0.12),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        style: finalTextStyle,
      ),
    );
  }
}


