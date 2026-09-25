Future<void> exportFile({
  required String fileName,
  String? textContent,
  List<int>? bytes,
  String mimeType = 'text/markdown;charset=utf-8',
}) async {
  throw UnsupportedError('Cannot export file on this platform.');
}

