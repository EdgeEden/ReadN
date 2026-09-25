import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

Future<void> exportFile({
  required String fileName,
  String? textContent,
  List<int>? bytes,
  String mimeType = 'text/markdown;charset=utf-8',
}) async {
  final outputFilePath = await FilePicker.platform.saveFile(
    dialogTitle: '导出文件',
    fileName: fileName,
  );
  if (outputFilePath != null) {
    final file = File(outputFilePath);
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else if (textContent != null) {
      await file.writeAsString(textContent, encoding: utf8);
    }
  }
}

