import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/annotation_model.dart';

class AnnotationCacheService {
  static const String _prefix = 'readn_annos_';
  static const String _pendingPrefix = 'readn_pending_annos_';

  final SharedPreferences _prefs;

  AnnotationCacheService(this._prefs);

  static Future<AnnotationCacheService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return AnnotationCacheService(prefs);
  }

  Future<void> saveAnnotations(String docId, List<PdfAnnotation> annotations) async {
    final list = annotations.map((a) => a.toJson()).toList();
    final jsonStr = jsonEncode(list);
    await _prefs.setString('$_prefix$docId', jsonStr);
  }

  List<PdfAnnotation> getAnnotations(String docId) {
    final jsonStr = _prefs.getString('$_prefix$docId');
    if (jsonStr == null || jsonStr.trim().isEmpty) return [];

    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => PdfAnnotation.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteAnnotations(String docId) async {
    await _prefs.remove('$_prefix$docId');
    await _prefs.remove('$_pendingPrefix$docId');
  }

  Future<void> addPendingSync(String docId, Map<String, dynamic> op) async {
    final list = getPendingSync(docId);
    list.add(op);
    await _prefs.setString('$_pendingPrefix$docId', jsonEncode(list));
  }

  List<Map<String, dynamic>> getPendingSync(String docId) {
    final jsonStr = _prefs.getString('$_pendingPrefix$docId');
    if (jsonStr == null || jsonStr.trim().isEmpty) return [];

    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => item as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearPendingSync(String docId) async {
    await _prefs.remove('$_pendingPrefix$docId');
  }
}
