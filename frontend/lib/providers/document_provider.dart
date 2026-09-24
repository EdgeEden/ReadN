import 'package:flutter/foundation.dart';
import '../models/document_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

enum DocumentSortBy {
  updatedAt,
  title,
  fileSize,
}

class DocumentProvider extends ChangeNotifier {
  final ApiService apiService;
  final StorageService storageService;

  List<DocumentModel> _documents = [];
  bool _isLoading = false;
  bool _isUploading = false;
  String? _errorMessage;
  bool _isBackendConnected = false;
  String _searchQuery = "";
  DocumentSortBy _sortBy = DocumentSortBy.updatedAt;
  bool _isGridView = true;
  DocumentModel? _activeDocument;

  DocumentProvider({
    required this.apiService,
    required this.storageService,
  }) {
    checkConnectionAndLoad();
  }

  List<DocumentModel> get documents {
    var list = _documents.where((doc) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return doc.title.toLowerCase().contains(q) || doc.filename.toLowerCase().contains(q);
    }).toList();

    switch (_sortBy) {
      case DocumentSortBy.updatedAt:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case DocumentSortBy.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case DocumentSortBy.fileSize:
        list.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
    }
    return list;
  }

  int get totalDocumentsCount => _documents.length;
  int get totalAnnotationsCount => _documents.fold(0, (sum, doc) => sum + doc.annotationCount);

  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;
  String? get errorMessage => _errorMessage;
  bool get isBackendConnected => _isBackendConnected;
  String get searchQuery => _searchQuery;
  DocumentSortBy get sortBy => _sortBy;
  bool get isGridView => _isGridView;
  DocumentModel? get activeDocument => _activeDocument;

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSortBy(DocumentSortBy sortBy) {
    _sortBy = sortBy;
    notifyListeners();
  }

  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  void setActiveDocument(DocumentModel? doc) {
    _activeDocument = doc;
    if (doc != null) {
      storageService.setLastDocId(doc.id);
    }
    notifyListeners();
  }

  Future<void> checkConnectionAndLoad() async {
    _isBackendConnected = await apiService.checkHealth();
    notifyListeners();
    if (_isBackendConnected) {
      await loadDocuments();
    }
  }

  Future<void> loadDocuments() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _documents = await apiService.getDocuments();
      _isBackendConnected = true;
    } catch (e) {
      _errorMessage = e.toString();
      _isBackendConnected = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DocumentModel?> uploadDocument(List<int> bytes, String filename) async {
    _isUploading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newDoc = await apiService.uploadDocument(
        fileBytes: bytes,
        filename: filename,
      );
      _documents.insert(0, newDoc);
      _isBackendConnected = true;
      return newDoc;
    } catch (e) {
      _errorMessage = '上传失败: $e';
      return null;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<bool> renameDocument(String docId, String newTitle) async {
    try {
      final updated = await apiService.updateDocumentTitle(docId, newTitle);
      final index = _documents.indexWhere((d) => d.id == docId);
      if (index != -1) {
        _documents[index] = updated;
      }
      if (_activeDocument?.id == docId) {
        _activeDocument = updated;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '重命名失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteDocument(String docId) async {
    try {
      await apiService.deleteDocument(docId);
      _documents.removeWhere((d) => d.id == docId);
      if (_activeDocument?.id == docId) {
        _activeDocument = null;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '删除失败: $e';
      notifyListeners();
      return false;
    }
  }

  void updateAnnotationCount(String docId, int delta) {
    final index = _documents.indexWhere((d) => d.id == docId);
    if (index != -1) {
      final doc = _documents[index];
      _documents[index] = doc.copyWith(
        annotationCount: (doc.annotationCount + delta).clamp(0, 99999),
      );
      if (_activeDocument?.id == docId) {
        _activeDocument = _documents[index];
      }
      notifyListeners();
    }
  }

  Future<bool> triggerOcr(
    String docId, {
    String engine = "adobe",
    String? adobeClientId,
    String? adobeClientSecret,
    String adobeLocale = "zh-CN",
    String adobeType = "searchable_image_exact",
    String? apiToken,
    String? apiUrl,
    String? modelName,
    String pageScope = "all",
    List<int>? targetPages,
    String languages = "chi_sim+eng+equ",
    bool useDocOrientationClassify = false,
    bool useDocUnwarping = false,
    bool useChartRecognition = false,
  }) async {
    try {
      await apiService.startOcr(
        docId,
        engine: engine,
        adobeClientId: adobeClientId,
        adobeClientSecret: adobeClientSecret,
        adobeLocale: adobeLocale,
        adobeType: adobeType,
        apiToken: apiToken,
        apiUrl: apiUrl,
        modelName: modelName,
        pageScope: pageScope,
        targetPages: targetPages,
        languages: languages,
        useDocOrientationClassify: useDocOrientationClassify,
        useDocUnwarping: useDocUnwarping,
        useChartRecognition: useChartRecognition,
      );
      final index = _documents.indexWhere((d) => d.id == docId);
      if (index != -1) {
        _documents[index] = _documents[index].copyWith(ocrStatus: "processing");
      }
      if (_activeDocument?.id == docId) {
        _activeDocument = _activeDocument?.copyWith(ocrStatus: "processing");
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '启动 OCR 失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> checkOcrProgress(String docId) async {
    try {
      final status = await apiService.getOcrStatus(docId);
      final statusStr = status['status'] as String? ?? "none";
      if (statusStr == "completed") {
        // Refresh document info
        final updatedDoc = await apiService.getDocument(docId);
        final index = _documents.indexWhere((d) => d.id == docId);
        if (index != -1) {
          _documents[index] = updatedDoc;
        }
        if (_activeDocument?.id == docId) {
          _activeDocument = updatedDoc;
        }
        notifyListeners();
      }
      return status;
    } catch (e) {
      return {'status': 'failed', 'error': e.toString()};
    }
  }

  Future<bool> revertOcr(
    String docId, {
    String pageScope = "current",
    List<int>? targetPages,
  }) async {
    try {
      final updatedDoc = await apiService.revertOcr(
        docId,
        pageScope: pageScope,
        targetPages: targetPages,
      );
      final index = _documents.indexWhere((d) => d.id == docId);
      if (index != -1) {
        _documents[index] = updatedDoc;
      }
      if (_activeDocument?.id == docId) {
        _activeDocument = updatedDoc;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '恢复原始文字层失败: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> getMarkdown(String docId) async {
    try {
      return await apiService.getMarkdown(docId);
    } catch (e) {
      return {'doc_id': docId, 'has_markdown': false, 'markdown': '', 'error': e.toString()};
    }
  }

  Future<bool> saveMarkdown(String docId, String markdown) async {
    try {
      await apiService.saveMarkdown(docId, markdown);
      return true;
    } catch (e) {
      _errorMessage = '保存 Markdown 失败: $e';
      notifyListeners();
      return false;
    }
  }
}

