import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'doc_cache_service.dart';

DocCacheService createDocCacheService() => DocCacheServiceIo();

class DocCacheServiceIo implements DocCacheService {
  Directory? _cacheDir;
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized && _cacheDir != null) return;
    try {
      final baseDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${baseDir.path}/readn_cache');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      _initialized = true;
    } catch (e) {
      // Fallback to system temp directory for tests/headless environments
      try {
        final tempDir = Directory.systemTemp;
        _cacheDir = Directory('${tempDir.path}/readn_cache');
        if (!await _cacheDir!.exists()) {
          await _cacheDir!.create(recursive: true);
        }
        _initialized = true;
      } catch (_) {}
    }
  }

  Future<Directory> _getDir() async {
    if (!_initialized || _cacheDir == null) {
      await init();
    }
    return _cacheDir!;
  }

  File _getPdfFile(Directory dir, String docId) => File('${dir.path}/pdf_$docId.bin');
  File _getMetaFile(Directory dir, String docId) => File('${dir.path}/meta_$docId.json');
  File _getMdFile(Directory dir, String docId) => File('${dir.path}/md_$docId.md');

  @override
  Future<void> savePdf(String docId, Uint8List bytes, {String? checksum}) async {
    try {
      final dir = await _getDir();
      final pdfFile = _getPdfFile(dir, docId);
      await pdfFile.writeAsBytes(bytes, flush: true);

      if (checksum != null && checksum.isNotEmpty) {
        final metaFile = _getMetaFile(dir, docId);
        final meta = {
          'checksum': checksum,
          'size': bytes.length,
          'saved_at': DateTime.now().toIso8601String(),
        };
        await metaFile.writeAsString(jsonEncode(meta), flush: true);
      }
    } catch (e) {
      debugPrint('Error saving PDF to local cache: $e');
    }
  }

  @override
  Future<Uint8List?> getPdf(String docId, {String? expectedChecksum}) async {
    try {
      final dir = await _getDir();
      final pdfFile = _getPdfFile(dir, docId);
      if (!await pdfFile.exists()) return null;

      if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
        final metaFile = _getMetaFile(dir, docId);
        if (await metaFile.exists()) {
          final content = await metaFile.readAsString();
          final meta = jsonDecode(content) as Map<String, dynamic>;
          final cachedChecksum = meta['checksum'] as String?;
          if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
            // Checksum mismatch, cache is outdated
            return null;
          }
        }
      }

      return await pdfFile.readAsBytes();
    } catch (e) {
      debugPrint('Error reading PDF from local cache: $e');
      return null;
    }
  }

  @override
  Future<bool> hasPdf(String docId, {String? expectedChecksum}) async {
    try {
      final dir = await _getDir();
      final pdfFile = _getPdfFile(dir, docId);
      if (!await pdfFile.exists()) return false;

      if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
        final metaFile = _getMetaFile(dir, docId);
        if (await metaFile.exists()) {
          final content = await metaFile.readAsString();
          final meta = jsonDecode(content) as Map<String, dynamic>;
          final cachedChecksum = meta['checksum'] as String?;
          if (cachedChecksum != null && cachedChecksum != expectedChecksum) {
            return false;
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deletePdf(String docId) async {
    try {
      final dir = await _getDir();
      final pdfFile = _getPdfFile(dir, docId);
      if (await pdfFile.exists()) await pdfFile.delete();
      final metaFile = _getMetaFile(dir, docId);
      if (await metaFile.exists()) await metaFile.delete();
    } catch (e) {
      debugPrint('Error deleting PDF from cache: $e');
    }
  }

  @override
  Future<void> saveMarkdown(String docId, String content) async {
    try {
      final dir = await _getDir();
      final mdFile = _getMdFile(dir, docId);
      await mdFile.writeAsString(content, flush: true);
    } catch (e) {
      debugPrint('Error saving Markdown to cache: $e');
    }
  }

  @override
  Future<String?> getMarkdown(String docId) async {
    try {
      final dir = await _getDir();
      final mdFile = _getMdFile(dir, docId);
      if (await mdFile.exists()) {
        return await mdFile.readAsString();
      }
      return null;
    } catch (e) {
      debugPrint('Error reading Markdown from cache: $e');
      return null;
    }
  }

  @override
  Future<void> deleteMarkdown(String docId) async {
    try {
      final dir = await _getDir();
      final mdFile = _getMdFile(dir, docId);
      if (await mdFile.exists()) await mdFile.delete();
      await deleteImages(docId);
    } catch (e) {
      debugPrint('Error deleting Markdown from cache: $e');
    }
  }

  Directory _getImagesDir(Directory baseDir, String docId) =>
      Directory('${baseDir.path}${Platform.pathSeparator}${docId}_images');

  File _getImageFile(Directory baseDir, String docId, String imageName) {
    final cleanName = imageName.split(Platform.pathSeparator).last.split('/').last;
    return File('${_getImagesDir(baseDir, docId).path}${Platform.pathSeparator}$cleanName');
  }

  @override
  Future<void> saveImage(String docId, String imageName, Uint8List bytes) async {
    try {
      final dir = await _getDir();
      final imgDir = _getImagesDir(dir, docId);
      if (!await imgDir.exists()) {
        await imgDir.create(recursive: true);
      }
      final file = _getImageFile(dir, docId, imageName);
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('Error saving image to cache: $e');
    }
  }

  @override
  Future<Uint8List?> getImage(String docId, String imageName) async {
    try {
      final dir = await _getDir();
      final file = _getImageFile(dir, docId, imageName);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e) {
      debugPrint('Error reading image from cache: $e');
      return null;
    }
  }

  @override
  Future<String?> getImagePath(String docId, String imageName) async {
    try {
      final dir = await _getDir();
      final file = _getImageFile(dir, docId, imageName);
      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> deleteImages(String docId) async {
    try {
      final dir = await _getDir();
      final imgDir = _getImagesDir(dir, docId);
      if (await imgDir.exists()) {
        await imgDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error deleting images from cache: $e');
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      final dir = await _getDir();
      if (await dir.exists()) {
        final entries = dir.listSync();
        for (final entry in entries) {
          entry.deleteSync(recursive: true);
        }
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
}
