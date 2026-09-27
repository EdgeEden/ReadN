import 'dart:typed_data';
import 'doc_cache_service_io.dart' if (dart.library.js_interop) 'doc_cache_service_web.dart';

abstract class DocCacheService {
  factory DocCacheService() => createDocCacheService();

  Future<void> init();

  Future<void> savePdf(String docId, Uint8List bytes, {String? checksum});

  Future<Uint8List?> getPdf(String docId, {String? expectedChecksum});

  Future<bool> hasPdf(String docId, {String? expectedChecksum});

  Future<void> deletePdf(String docId);

  Future<void> saveMarkdown(String docId, String content);

  Future<String?> getMarkdown(String docId);

  Future<void> deleteMarkdown(String docId);

  Future<void> clearAll();
}
