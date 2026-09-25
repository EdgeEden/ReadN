// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

Future<void> exportFile({
  required String fileName,
  String? textContent,
  List<int>? bytes,
  String mimeType = 'text/markdown;charset=utf-8',
}) async {
  final data = bytes ?? (textContent != null ? utf8.encode(textContent) : <int>[]);
  final blob = html.Blob([data], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

