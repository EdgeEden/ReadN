import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

enum ReaderSidebarTab {
  outline('目录', Icons.menu_book_rounded),
  search('检索', Icons.search_rounded),
  highlights('高亮', Icons.brush_rounded),
  notes('批注', Icons.edit_note_rounded),
  cards('卡片', Icons.style_rounded),
  aiChat('AI 助手', Icons.auto_awesome_rounded);

  final String label;
  final IconData icon;
  const ReaderSidebarTab(this.label, this.icon);
}

enum SidebarDockPosition {
  left,
  right,
}

class ReaderSettingsProvider extends ChangeNotifier {
  final StorageService storageService;

  ReadingMode _readingMode = ReadingMode.light;
  bool _isLeftSidebarOpen = true;
  bool _isRightSidebarOpen = false;
  bool _showAnnotations = true;
  double _zoomScale = 1.0;
  Axis _scrollDirection = Axis.vertical;

  final List<ReaderSidebarTab> _leftDockedTabs = [
    ReaderSidebarTab.outline,
    ReaderSidebarTab.search,
  ];
  final List<ReaderSidebarTab> _rightDockedTabs = [
    ReaderSidebarTab.highlights,
    ReaderSidebarTab.notes,
    ReaderSidebarTab.cards,
    ReaderSidebarTab.aiChat,
  ];

  ReaderSidebarTab _activeLeftTab = ReaderSidebarTab.outline;
  ReaderSidebarTab _activeRightTab = ReaderSidebarTab.aiChat;

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
  bool get isLeftSidebarOpen => _isLeftSidebarOpen;
  bool get isRightSidebarOpen => _isRightSidebarOpen;
  bool get isSidebarOpen => _isRightSidebarOpen; // For backward compatibility
  bool get showAnnotations => _showAnnotations;
  double get zoomScale => _zoomScale;
  Axis get scrollDirection => _scrollDirection;

  List<ReaderSidebarTab> get leftDockedTabs => List.unmodifiable(_leftDockedTabs);
  List<ReaderSidebarTab> get rightDockedTabs => List.unmodifiable(_rightDockedTabs);
  ReaderSidebarTab get activeLeftTab => _activeLeftTab;
  ReaderSidebarTab get activeRightTab => _activeRightTab;

  void setReadingMode(ReadingMode mode) {
    _readingMode = mode;
    storageService.setReadingMode(mode.name);
    notifyListeners();
  }

  void setLeftSidebarOpen(bool open) {
    _isLeftSidebarOpen = open;
    notifyListeners();
  }

  void toggleLeftSidebar() {
    _isLeftSidebarOpen = !_isLeftSidebarOpen;
    notifyListeners();
  }

  void setRightSidebarOpen(bool open) {
    _isRightSidebarOpen = open;
    notifyListeners();
  }

  void toggleRightSidebar() {
    _isRightSidebarOpen = !_isRightSidebarOpen;
    notifyListeners();
  }

  void setSidebarOpen(bool open) {
    _isRightSidebarOpen = open;
    notifyListeners();
  }

  void toggleSidebar() {
    _isRightSidebarOpen = !_isRightSidebarOpen;
    notifyListeners();
  }

  void setActiveLeftTab(ReaderSidebarTab tab) {
    _activeLeftTab = tab;
    if (!_isLeftSidebarOpen) {
      _isLeftSidebarOpen = true;
    }
    notifyListeners();
  }

  void setActiveRightTab(ReaderSidebarTab tab) {
    _activeRightTab = tab;
    if (!_isRightSidebarOpen) {
      _isRightSidebarOpen = true;
    }
    notifyListeners();
  }

  void dockTabToLeft(ReaderSidebarTab tab) {
    _rightDockedTabs.remove(tab);
    if (!_leftDockedTabs.contains(tab)) {
      _leftDockedTabs.add(tab);
    }
    _activeLeftTab = tab;
    _isLeftSidebarOpen = true;

    if (_activeRightTab == tab) {
      if (_rightDockedTabs.isNotEmpty) {
        _activeRightTab = _rightDockedTabs.first;
      } else {
        _isRightSidebarOpen = false;
      }
    }
    notifyListeners();
  }

  void dockTabToRight(ReaderSidebarTab tab) {
    _leftDockedTabs.remove(tab);
    if (!_rightDockedTabs.contains(tab)) {
      _rightDockedTabs.add(tab);
    }
    _activeRightTab = tab;
    _isRightSidebarOpen = true;

    if (_activeLeftTab == tab) {
      if (_leftDockedTabs.isNotEmpty) {
        _activeLeftTab = _leftDockedTabs.first;
      }
    }
    notifyListeners();
  }

  void openTab(ReaderSidebarTab tab) {
    if (_leftDockedTabs.contains(tab)) {
      _activeLeftTab = tab;
      _isLeftSidebarOpen = true;
    } else if (_rightDockedTabs.contains(tab)) {
      _activeRightTab = tab;
      _isRightSidebarOpen = true;
    } else {
      dockTabToLeft(tab);
    }
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
