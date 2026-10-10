import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'doc_cache_service.dart';

DocCacheService createDocCacheService() => DocCacheServiceWeb();

class DocCacheServiceWeb implements DocCacheService {
  static const String _dbName = 'readn_web_cache';
  static const int _dbVersion = 1;
  static const String _storePdfs = 'pdfs';
  static const String _storeMeta = 'meta';
  static const String _storeMds = 'markdowns';

  web.IDBDatabase? _db;
  Future<void>? _initFuture;

  // L1 In-Memory Cache for 0ms same-session instant response
  static const int _maxInMemoryBytes = 15 * 1024 * 1024;
  final Map<String, Uint8List> _pdfMemoryCache = {};
  final Map<String, String> _pdfMetaCache = {};
  final Map<String, String> _mdMemoryCache = {};

  @override
  Future<void> init() async {
    _initFuture ??= _openDatabase();
    await _initFuture;
  }

  Future<void> _openDatabase() async {
    final completer = Completer<void>();
    try {
      final req = web.window.indexedDB.open(_dbName, _dbVersion);

      req.onupgradeneeded = ((web.IDBVersionChangeEvent event) {
        final db = req.result as web.IDBDatabase;
        if (!db.objectStoreNames.contains(_storePdfs)) {
          db.createObjectStore(_storePdfs);
        }
        if (!db.objectStoreNames.contains(_storeMeta)) {
          db.createObjectStore(_storeMeta);
        }
        if (!db.objectStoreNames.contains(_storeMds)) {
          db.createObjectStore(_storeMds);
        }
      }).toJS;

      req.onsuccess = ((web.Event event) {
        _db = req.result as web.IDBDatabase;
        completer.complete();
      }).toJS;

      req.onerror = ((web.Event event) {
        debugPrint('IndexedDB open error: ${req.error}');
        completer.complete(); // Gracefully fallback to L1 memory cache
      }).toJS;
    } catch (e) {
      debugPrint('IndexedDB initialization failed: $e');
      completer.complete();
    }
    return completer.future;
  }

  Future<web.IDBDatabase?> _getDb() async {
    if (_db != null) return _db;
    _initFuture ??= _openDatabase();
    await _initFuture;
    return _db;
  }

  Future<JSAny?> _requestToFuture(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(request.error ?? Exception('IndexedDB request error'));
    }).toJS;
    return completer.future;
  }

  Uint8List? _jsValueToUint8List(JSAny? jsAny) {
    if (jsAny == null) return null;
    if (jsAny.isA<JSUint8Array>()) {
      return (jsAny as JSUint8Array).toDart;
    }
    if (jsAny.isA<JSArrayBuffer>()) {
      return (jsAny as JSArrayBuffer).toDart.asUint8List();
    }
    return null;
  }

  String? _jsValueToString(JSAny? jsAny) {
    if (jsAny == null) return null;
    if (jsAny.isA<JSString>()) {
      return (jsAny as JSString).toDart;
    }
    return null;
  }

  @override
  Future<void> savePdf(String docId, Uint8List bytes, {String? checksum}) async {
    // 1. Update L1 Memory Cache (only for files <= 15MB to prevent Web tab OOM)
    if (bytes.length <= _maxInMemoryBytes) {
      _pdfMemoryCache[docId] = bytes;
    }
    if (checksum != null && checksum.isNotEmpty) {
      _pdfMetaCache[docId] = checksum;
    }

    // 2. Persist to L2 IndexedDB
    try {
      final db = await _getDb();
      if (db == null) return;

      final storeNames = [_storePdfs, _storeMeta].map((s) => s.toJS).toList().toJS;
      final tx = db.transaction(storeNames, 'readwrite');
      final pdfStore = tx.objectStore(_storePdfs);
      pdfStore.put(bytes.toJS, docId.toJS);

      if (checksum != null && checksum.isNotEmpty) {
        final metaStore = tx.objectStore(_storeMeta);
        final metaJson = jsonEncode({
          'checksum': checksum,
          'size': bytes.length,
          'saved_at': DateTime.now().toIso8601String(),
        });
        metaStore.put(metaJson.toJS, docId.toJS);
      }
    } catch (e) {
      debugPrint('IndexedDB savePdf error: $e');
    }
  }

  @override
  Future<Uint8List?> getPdf(String docId, {String? expectedChecksum}) async {
    // 1. Check L1 Memory Cache
    if (_pdfMemoryCache.containsKey(docId)) {
      if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
        final cachedChecksum = _pdfMetaCache[docId];
        if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
          return null;
        }
      }
      return _pdfMemoryCache[docId];
    }

    // 2. Check L2 IndexedDB
    try {
      final db = await _getDb();
      if (db == null) return null;

      // Verify checksum from meta store if expectedChecksum is provided
      if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
        final metaTx = db.transaction(_storeMeta.toJS, 'readonly');
        final metaStore = metaTx.objectStore(_storeMeta);
        final metaReq = metaStore.get(docId.toJS);
        final metaRes = await _requestToFuture(metaReq);
        final metaStr = _jsValueToString(metaRes);
        if (metaStr != null) {
          try {
            final meta = jsonDecode(metaStr) as Map<String, dynamic>;
            final cachedChecksum = meta['checksum'] as String?;
            if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
              return null; // Checksum mismatch, invalidate cache
            }
            if (cachedChecksum != null) {
              _pdfMetaCache[docId] = cachedChecksum;
            }
          } catch (_) {}
        }
      }

      final pdfTx = db.transaction(_storePdfs.toJS, 'readonly');
      final pdfStore = pdfTx.objectStore(_storePdfs);
      final pdfReq = pdfStore.get(docId.toJS);
      final pdfRes = await _requestToFuture(pdfReq);
      final bytes = _jsValueToUint8List(pdfRes);

      if (bytes != null && bytes.isNotEmpty) {
        if (bytes.length <= _maxInMemoryBytes) {
          _pdfMemoryCache[docId] = bytes;
        }
        return bytes;
      }
    } catch (e) {
      debugPrint('IndexedDB getPdf error: $e');
    }

    return null;
  }

  @override
  Future<bool> hasPdf(String docId, {String? expectedChecksum}) async {
    if (_pdfMemoryCache.containsKey(docId)) {
      if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
        final cachedChecksum = _pdfMetaCache[docId];
        if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
          return false;
        }
      }
      return true;
    }

    try {
      final db = await _getDb();
      if (db == null) return false;

      if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
        final metaTx = db.transaction(_storeMeta.toJS, 'readonly');
        final metaStore = metaTx.objectStore(_storeMeta);
        final metaReq = metaStore.get(docId.toJS);
        final metaRes = await _requestToFuture(metaReq);
        final metaStr = _jsValueToString(metaRes);
        if (metaStr != null) {
          final meta = jsonDecode(metaStr) as Map<String, dynamic>;
          final cachedChecksum = meta['checksum'] as String?;
          if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
            return false;
          }
        }
      }

      final pdfTx = db.transaction(_storePdfs.toJS, 'readonly');
      final pdfStore = pdfTx.objectStore(_storePdfs);
      final countReq = pdfStore.count(docId.toJS);
      final countRes = await _requestToFuture(countReq);
      if (countRes != null && countRes.isA<JSNumber>()) {
        return (countRes as JSNumber).toDartInt > 0;
      }
    } catch (e) {
      debugPrint('IndexedDB hasPdf error: $e');
    }

    return false;
  }

  @override
  Future<void> deletePdf(String docId) async {
    _pdfMemoryCache.remove(docId);
    _pdfMetaCache.remove(docId);

    try {
      final db = await _getDb();
      if (db == null) return;

      final storeNames = [_storePdfs, _storeMeta].map((s) => s.toJS).toList().toJS;
      final tx = db.transaction(storeNames, 'readwrite');
      tx.objectStore(_storePdfs).delete(docId.toJS);
      tx.objectStore(_storeMeta).delete(docId.toJS);
    } catch (e) {
      debugPrint('IndexedDB deletePdf error: $e');
    }
  }

  @override
  Future<void> saveMarkdown(String docId, String content) async {
    _mdMemoryCache[docId] = content;

    try {
      final db = await _getDb();
      if (db == null) return;

      final tx = db.transaction(_storeMds.toJS, 'readwrite');
      tx.objectStore(_storeMds).put(content.toJS, docId.toJS);
    } catch (e) {
      debugPrint('IndexedDB saveMarkdown error: $e');
    }
  }

  @override
  Future<String?> getMarkdown(String docId) async {
    if (_mdMemoryCache.containsKey(docId)) {
      return _mdMemoryCache[docId];
    }

    try {
      final db = await _getDb();
      if (db == null) return null;

      final tx = db.transaction(_storeMds.toJS, 'readonly');
      final req = tx.objectStore(_storeMds).get(docId.toJS);
      final res = await _requestToFuture(req);
      final content = _jsValueToString(res);
      if (content != null) {
        _mdMemoryCache[docId] = content;
        return content;
      }
    } catch (e) {
      debugPrint('IndexedDB getMarkdown error: $e');
    }

    return null;
  }

  final Map<String, Uint8List> _imagesMemoryCache = {};

  @override
  Future<void> saveImage(String docId, String imageName, Uint8List bytes) async {
    final cleanName = imageName.split('/').last;
    _imagesMemoryCache['${docId}_$cleanName'] = bytes;
  }

  @override
  Future<Uint8List?> getImage(String docId, String imageName) async {
    final cleanName = imageName.split('/').last;
    return _imagesMemoryCache['${docId}_$cleanName'];
  }

  @override
  Future<String?> getImagePath(String docId, String imageName) async {
    return null;
  }

  @override
  Future<void> deleteImages(String docId) async {
    _imagesMemoryCache.removeWhere((k, v) => k.startsWith('${docId}_'));
  }

  @override
  Future<void> deleteMarkdown(String docId) async {
    _mdMemoryCache.remove(docId);
    await deleteImages(docId);

    try {
      final db = await _getDb();
      if (db == null) return;

      final tx = db.transaction(_storeMds.toJS, 'readwrite');
      tx.objectStore(_storeMds).delete(docId.toJS);
    } catch (e) {
      debugPrint('IndexedDB deleteMarkdown error: $e');
    }
  }

  @override
  Future<void> clearAll() async {
    _pdfMemoryCache.clear();
    _pdfMetaCache.clear();
    _mdMemoryCache.clear();
    _imagesMemoryCache.clear();

    try {
      final db = await _getDb();
      if (db == null) return;

      final storeNames = [_storePdfs, _storeMeta, _storeMds].map((s) => s.toJS).toList().toJS;
      final tx = db.transaction(storeNames, 'readwrite');
      tx.objectStore(_storePdfs).clear();
      tx.objectStore(_storeMeta).clear();
      tx.objectStore(_storeMds).clear();
    } catch (e) {
      debugPrint('IndexedDB clearAll error: $e');
    }
  }
}
