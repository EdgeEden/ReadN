import 'package:flutter/material.dart';
import '../models/annotation_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/cache/annotation_cache_service.dart';

class AnnotationProvider extends ChangeNotifier {
  final ApiService apiService;
  final StorageService storageService;
  final AnnotationCacheService annotationCacheService;

  String? _currentDocId;
  List<PdfAnnotation> _annotations = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  String _activeHighlightColor = "#FFE066";
  PdfAnnotation? _selectedAnnotation;
  String? _focusedAnnotationId;
  String _filterQuery = "";
  String? _filterColorHex;

  AnnotationProvider({
    required this.apiService,
    required this.storageService,
    required this.annotationCacheService,
  }) {
    _activeHighlightColor = storageService.getDefaultHighlightColor();
  }

  List<PdfAnnotation> get annotations => _annotations;

  List<PdfAnnotation> get filteredAnnotations {
    return _annotations.where((a) {
      if (_filterColorHex != null && a.colorHex.toLowerCase() != _filterColorHex!.toLowerCase()) {
        return false;
      }
      if (_filterQuery.trim().isNotEmpty) {
        final q = _filterQuery.toLowerCase();
        final matchText = a.selectedText.toLowerCase().contains(q);
        final matchNote = a.noteContent.toLowerCase().contains(q);
        if (!matchText && !matchNote) return false;
      }
      return true;
    }).toList();
  }

  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String get activeHighlightColor => _activeHighlightColor;
  PdfAnnotation? get selectedAnnotation => _selectedAnnotation;
  String? get focusedAnnotationId => _focusedAnnotationId;
  String get filterQuery => _filterQuery;
  String? get filterColorHex => _filterColorHex;

  void setActiveHighlightColor(String colorHex) {
    _activeHighlightColor = colorHex;
    storageService.setDefaultHighlightColor(colorHex);
    notifyListeners();
  }

  void setSelectedAnnotation(PdfAnnotation? annotation) {
    _selectedAnnotation = annotation;
    notifyListeners();
  }

  void setFocusedAnnotationId(String? id) {
    _focusedAnnotationId = id;
    notifyListeners();
  }

  void setFilterQuery(String query) {
    _filterQuery = query;
    notifyListeners();
  }

  void setFilterColorHex(String? colorHex) {
    _filterColorHex = colorHex;
    notifyListeners();
  }

  List<PdfAnnotation> getAnnotationsForPage(int pageNumber) {
    return _annotations.where((a) => a.pageNumber == pageNumber).toList();
  }

  Future<void> loadAnnotations(String docId) async {
    _currentDocId = docId;

    // 1. Cache-first instant rendering
    final cached = annotationCacheService.getAnnotations(docId);
    if (cached.isNotEmpty) {
      _annotations = cached;
      _isLoading = false;
      notifyListeners();
    } else {
      _isLoading = true;
      _annotations = [];
      notifyListeners();
    }

    // 2. Background cloud fetch & sync
    try {
      final cloudList = await apiService.getAnnotations(docId);
      _annotations = cloudList;
      await annotationCacheService.saveAnnotations(docId, cloudList);
    } catch (e) {
      debugPrint("Error loading cloud annotations (using cache): $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<PdfAnnotation?> addAnnotation(PdfAnnotation anno) async {
    if (_currentDocId == null) return null;
    
    // Optimistic UI update & immediate local cache save
    _annotations.add(anno);
    await annotationCacheService.saveAnnotations(_currentDocId!, _annotations);
    _isSyncing = true;
    notifyListeners();

    try {
      final created = await apiService.createAnnotation(_currentDocId!, anno);
      final idx = _annotations.indexWhere((a) => a.id == anno.id);
      if (idx != -1) {
        _annotations[idx] = created;
        await annotationCacheService.saveAnnotations(_currentDocId!, _annotations);
      }
      return created;
    } catch (e) {
      debugPrint("Failed to sync annotation to cloud: $e");
      return anno;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<bool> updateAnnotation(
    String annoId, {
    String? colorHex,
    String? noteContent,
    String? selectedText,
    String? type,
    List<NormalizedRect>? rects,
  }) async {
    if (_currentDocId == null) return false;
    final idx = _annotations.indexWhere((a) => a.id == annoId);
    if (idx == -1) return false;

    final orig = _annotations[idx];
    final updated = orig.copyWith(
      colorHex: colorHex,
      noteContent: noteContent,
      selectedText: selectedText,
      type: type,
      rects: rects,
      updatedAt: DateTime.now(),
    );
    _annotations[idx] = updated;
    if (_selectedAnnotation?.id == annoId) {
      _selectedAnnotation = updated;
    }
    await annotationCacheService.saveAnnotations(_currentDocId!, _annotations);
    notifyListeners();

    try {
      await apiService.updateAnnotation(
        _currentDocId!,
        annoId,
        colorHex: colorHex,
        noteContent: noteContent,
        selectedText: selectedText,
        type: type,
        rects: rects,
      );
      return true;
    } catch (e) {
      debugPrint("Failed to update annotation on cloud: $e");
      return false;
    }
  }

  Future<bool> updateAnnotationModel(PdfAnnotation anno) async {
    return updateAnnotation(
      anno.id,
      colorHex: anno.colorHex,
      noteContent: anno.noteContent,
      selectedText: anno.selectedText,
      type: anno.type,
      rects: anno.rects,
    );
  }

  Future<bool> deleteAnnotation(String annoId) async {
    if (_currentDocId == null) return false;
    final idx = _annotations.indexWhere((a) => a.id == annoId);
    if (idx == -1) return false;

    final removed = _annotations.removeAt(idx);
    if (_selectedAnnotation?.id == annoId) {
      _selectedAnnotation = null;
    }
    await annotationCacheService.saveAnnotations(_currentDocId!, _annotations);
    notifyListeners();

    try {
      await apiService.deleteAnnotation(_currentDocId!, annoId);
      return true;
    } catch (e) {
      debugPrint("Failed to delete annotation on cloud: $e");
      // Revert if critical
      _annotations.insert(idx, removed);
      await annotationCacheService.saveAnnotations(_currentDocId!, _annotations);
      notifyListeners();
      return false;
    }
  }
}
