import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class ReaderSettingsProvider extends ChangeNotifier {
  final StorageService storageService;

  ReadingMode _readingMode = ReadingMode.light;
  bool _isSidebarOpen = false;
  bool _showAnnotations = true;
  double _zoomScale = 1.0;
  Axis _scrollDirection = Axis.vertical;

  ReaderSettingsProvider({required this.storageService}) {
    final savedMode = storageService.getReadingMode();
    switch (savedMode) {
      case 'sepia':
        _readingMode = ReadingMode.sepia;
        break;
      case 'dark':
        _readingMode = ReadingMode.dark;
        break;
      default:
        _readingMode = ReadingMode.light;
    }
  }

  ReadingMode get readingMode => _readingMode;
  bool get isSidebarOpen => _isSidebarOpen;
  bool get showAnnotations => _showAnnotations;
  double get zoomScale => _zoomScale;
  Axis get scrollDirection => _scrollDirection;

  void setReadingMode(ReadingMode mode) {
    _readingMode = mode;
    storageService.setReadingMode(mode.name);
    notifyListeners();
  }

  void toggleSidebar() {
    _isSidebarOpen = !_isSidebarOpen;
    notifyListeners();
  }

  void setSidebarOpen(bool open) {
    _isSidebarOpen = open;
    notifyListeners();
  }

  void toggleShowAnnotations() {
    _showAnnotations = !_showAnnotations;
    notifyListeners();
  }

  void setZoomScale(double zoom) {
    _zoomScale = zoom.clamp(0.5, 4.0);
    notifyListeners();
  }

  void setScrollDirection(Axis direction) {
    _scrollDirection = direction;
    notifyListeners();
  }
}

