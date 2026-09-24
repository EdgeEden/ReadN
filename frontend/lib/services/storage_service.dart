import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyBaseUrl = 'readn_base_url';
  static const String _keyReadingMode = 'readn_reading_mode';
  static const String _keyLastDocId = 'readn_last_doc_id';
  static const String _keyLastPagePrefix = 'readn_last_page_';
  static const String _keyDefaultHighlightColor = 'readn_default_highlight_color';

  static const String defaultBaseUrl = 'http://localhost:8000';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  String getBaseUrl() {
    return _prefs.getString(_keyBaseUrl) ?? defaultBaseUrl;
  }

  Future<bool> setBaseUrl(String url) {
    var clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return _prefs.setString(_keyBaseUrl, clean);
  }

  String getReadingMode() {
    return _prefs.getString(_keyReadingMode) ?? 'light';
  }

  Future<bool> setReadingMode(String mode) {
    return _prefs.setString(_keyReadingMode, mode);
  }

  String getDefaultHighlightColor() {
    return _prefs.getString(_keyDefaultHighlightColor) ?? '#FFE066';
  }

  Future<bool> setDefaultHighlightColor(String colorHex) {
    return _prefs.setString(_keyDefaultHighlightColor, colorHex);
  }

  String? getLastDocId() {
    return _prefs.getString(_keyLastDocId);
  }

  Future<bool> setLastDocId(String docId) {
    return _prefs.setString(_keyLastDocId, docId);
  }

  int getLastReadPage(String docId) {
    return _prefs.getInt('$_keyLastPagePrefix$docId') ?? 1;
  }

  Future<bool> setLastReadPage(String docId, int page) {
    return _prefs.setInt('$_keyLastPagePrefix$docId', page);
  }
}

