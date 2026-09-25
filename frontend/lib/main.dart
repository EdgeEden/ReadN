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
import 'theme/app_theme.dart';
import 'views/bookshelf/bookshelf_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Parallelize pdfrx and storage service initialization to accelerate startup
  final initResults = await Future.wait([
    pdfrxFlutterInitialize(),
    StorageService.init(),
  ]);

  final storageService = initResults[1] as StorageService;
  final apiService = ApiService(storageService: storageService);
  final aiService = AiService();

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        Provider<ApiService>.value(value: apiService),
        Provider<AiService>.value(value: aiService),
        ChangeNotifierProvider<DocumentProvider>(
          create: (_) => DocumentProvider(
            apiService: apiService,
            storageService: storageService,
          ),
        ),
        ChangeNotifierProvider<AnnotationProvider>(
          create: (_) => AnnotationProvider(
            apiService: apiService,
            storageService: storageService,
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
    return MaterialApp(
      title: 'ReadN - 云端多端 PDF 阅读器',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const BookshelfView(),
    );
  }
}
