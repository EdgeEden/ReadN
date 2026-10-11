import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _keyBaseUrl = 'readn_base_url';
  static const String _keyReadingMode = 'readn_reading_mode';
  static const String _keyLastDocId = 'readn_last_doc_id';
  static const String _keyLastPagePrefix = 'readn_last_page_';
  static const String _keyDefaultHighlightColor = 'readn_default_highlight_color';
  static const String _keyStylusMode = 'readn_stylus_mode';
  static const String _keyAiBaseUrl = 'readn_ai_base_url';
  static const String _keyAiApiKey = 'readn_ai_api_key';
  static const String _keyAiModel = 'readn_ai_model';
  static const String _keyAiSystemPrompt = 'readn_ai_system_prompt';
  static const String _keyAiTemperature = 'readn_ai_temperature';
  static const String _keyAiIncludeContext = 'readn_ai_include_context';

  static const String defaultBaseUrl = 'http://localhost:18903';
  static const String defaultAiBaseUrl = 'https://api.deepseek.com';
  static const String defaultAiModel = '';
  static const String defaultAiSystemPrompt =
      '你是一个专业、严谨且富有洞察力的学术阅读与文献分析助手。擅长深入解析复杂概念、推导数学公式、提取文献核心观点以及准确翻译。请用中文回答，排版清晰美观，涉及公式时使用标准 LaTeX 格式（行内公式用 \$...\$，独立公式块用 \$\$...\$\$ 或 ```latex ）。';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  String getBaseUrl() {
    final saved = _prefs.getString(_keyBaseUrl);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin != 'null' && !origin.startsWith('file:')) {
        return origin;
      }
    }
    return defaultBaseUrl;
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

  // -------------------------------------------------------------
  // AI Assistant Local Settings (Never sent to backend server)
  // -------------------------------------------------------------
  String getAiBaseUrl() {
    return _prefs.getString(_keyAiBaseUrl) ?? defaultAiBaseUrl;
  }

  Future<bool> setAiBaseUrl(String url) {
    var clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    return _prefs.setString(_keyAiBaseUrl, clean);
  }

  String getAiApiKey() {
    return _prefs.getString(_keyAiApiKey) ?? '';
  }

  Future<bool> setAiApiKey(String key) {
    return _prefs.setString(_keyAiApiKey, key.trim());
  }

  String getAiModel() {
    return _prefs.getString(_keyAiModel) ?? defaultAiModel;
  }

  Future<bool> setAiModel(String model) {
    return _prefs.setString(_keyAiModel, model.trim());
  }

  String getAiSystemPrompt() {
    return _prefs.getString(_keyAiSystemPrompt) ?? defaultAiSystemPrompt;
  }

  Future<bool> setAiSystemPrompt(String prompt) {
    return _prefs.setString(_keyAiSystemPrompt, prompt.trim());
  }

  double getAiTemperature() {
    return _prefs.getDouble(_keyAiTemperature) ?? 0.6;
  }

  Future<bool> setAiTemperature(double temperature) {
    return _prefs.setDouble(_keyAiTemperature, temperature.clamp(0.0, 2.0));
  }

  bool getAiIncludeContext() {
    return _prefs.getBool(_keyAiIncludeContext) ?? true;
  }

  Future<bool> setAiIncludeContext(bool includeContext) {
    return _prefs.setBool(_keyAiIncludeContext, includeContext);
  }

  bool getStylusMode() {
    return _prefs.getBool(_keyStylusMode) ?? false;
  }

  Future<bool> setStylusMode(bool enabled) {
    return _prefs.setBool(_keyStylusMode, enabled);
  }
}

