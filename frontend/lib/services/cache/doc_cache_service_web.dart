import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'doc_cache_service.dart';

DocCacheService createDocCacheService() => DocCacheServiceWeb();

class DocCacheServiceWeb implements DocCacheService {
  final Map<String, Uint8List> _pdfMemoryCache = {};
  final Map<String, String> _pdfMetaCache = {};
  final Map<String, String> _mdMemoryCache = {};
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  @override
  Future<void> savePdf(String docId, Uint8List bytes, {String? checksum}) async {
    _pdfMemoryCache[docId] = bytes;
    if (checksum != null && checksum.isNotEmpty) {
      _pdfMetaCache[docId] = checksum;
    }
  }

  @override
  Future<Uint8List?> getPdf(String docId, {String? expectedChecksum}) async {
    if (!_pdfMemoryCache.containsKey(docId)) return null;

    if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
      final cachedChecksum = _pdfMetaCache[docId];
      if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
        return null;
      }
    }
    return _pdfMemoryCache[docId];
  }

  @override
  Future<bool> hasPdf(String docId, {String? expectedChecksum}) async {
    if (!_pdfMemoryCache.containsKey(docId)) return false;

    if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
      final cachedChecksum = _pdfMetaCache[docId];
      if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> deletePdf(String docId) async {
    _pdfMemoryCache.remove(docId);
    _pdfMetaCache.remove(docId);
  }

  @override
  Future<void> saveMarkdown(String docId, String content) async {
    _mdMemoryCache[docId] = content;
  }

  @override
  Future<String?> getMarkdown(String docId) async {
    return _mdMemoryCache[docId];
  }

  @override
  Future<void> deleteMarkdown(String docId) async {
    _mdMemoryCache.remove(docId);
  }

  @override
  Future<void> clearAll() async {
    _pdfMemoryCache.clear();
    _pdfMetaCache.clear();
    _mdMemoryCache.clear();
  }
}
