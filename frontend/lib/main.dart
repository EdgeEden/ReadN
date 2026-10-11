import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'providers/ai_provider.dart';
import 'providers/annotation_provider.dart';
import 'providers/document_provider.dart';
import 'providers/reader_settings_provider.dart';
import 'services/ai_service.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'services/cache/doc_cache_service.dart';
import 'services/cache/annotation_cache_service.dart';
import 'services/stylus_pointer_adapter.dart';
import 'theme/app_theme.dart';
import 'views/bookshelf/bookshelf_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StylusPointerAdapter.init();
  
  // Parallelize pdfrx, storage service, and cache service initialization
  final docCacheService = DocCacheService();
  final initResults = await Future.wait([
    pdfrxFlutterInitialize(),
    StorageService.init(),
    AnnotationCacheService.init(),
    docCacheService.init(),
  ]);

  final storageService = initResults[1] as StorageService;
  final annotationCacheService = initResults[2] as AnnotationCacheService;
  final apiService = ApiService(storageService: storageService);
  final aiService = AiService();

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<ApiService>.value(value: apiService),
        Provider<AiService>.value(value: aiService),
        Provider<DocCacheService>.value(value: docCacheService),
        Provider<AnnotationCacheService>.value(value: annotationCacheService),
        ChangeNotifierProvider<DocumentProvider>(
          create: (_) => DocumentProvider(
            apiService: apiService,
            storageService: storageService,
            docCacheService: docCacheService,
          ),
        ),
        ChangeNotifierProvider<AnnotationProvider>(
          create: (_) => AnnotationProvider(
            apiService: apiService,
            storageService: storageService,
            annotationCacheService: annotationCacheService,
          ),
        ),
        ChangeNotifierProvider<ReaderSettingsProvider>(
          create: (_) => ReaderSettingsProvider(
            storageService: storageService,
          ),
        ),
        ChangeNotifierProvider<AiProvider>(
          create: (_) => AiProvider(
            storageService: storageService,
            aiService: aiService,
          ),
        ),
      ],
      child: const ReadNApp(),
    ),
  );
}

class ReadNApp extends StatelessWidget {
  const ReadNApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ReaderSettingsProvider>().readingMode;
    ThemeData activeTheme;
    switch (mode) {
      case ReadingMode.dark:
        activeTheme = AppTheme.darkTheme;
        break;
      case ReadingMode.sepia:
        activeTheme = AppTheme.sepiaTheme;
        break;
      case ReadingMode.light:
        activeTheme = AppTheme.lightTheme;
        break;
    }

    return MaterialApp(
      title: 'ReadN - 云端多端 PDF 阅读器',
      debugShowCheckedModeBanner: false,
      theme: activeTheme,
      darkTheme: activeTheme,
      themeMode: ThemeMode.light,
      home: const BookshelfView(),
    );
  }
}
