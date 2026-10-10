import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../api_service.dart';
import '../cache/doc_cache_service.dart';

class MineruChunk {
  final int index;
  final List<int> pages;
  final Uint8List bytes;

  MineruChunk({
    required this.index,
    required this.pages,
    required this.bytes,
  });
}

class MineruOcrService {
  static const String defaultApiBase = 'https://mineru.net/api/v4';
  static const String defaultMineruToken = '';
  static const String overseasOssAccelerateDomain = 'mineru.oss-accelerate-overseas.aliyuncs.com';
  static const String globalOssAccelerateDomain = 'mineru.oss-accelerate.aliyuncs.com';
  static const String standardOssDomain = 'mineru.oss-cn-shanghai.aliyuncs.com';

  /// Applies OSS transfer acceleration by replacing standard Shanghai OSS domain with overseas/global acceleration endpoint.
  String applyOssAcceleration(String url, {bool enable = true}) {
    if (!enable || url.isEmpty) return url;
    if (url.contains(standardOssDomain)) {
      return url.replaceAll(standardOssDomain, overseasOssAccelerateDomain);
    }
    return url;
  }

  /// Splits or prepares sub-PDF chunks according to MinerU constraints (<= 200 pages & <= 180MB per chunk).
  Future<List<MineruChunk>> prepareChunks({
    required Uint8List fullPdfBytes,
    required int totalDocPages,
    List<int>? targetPages,
    int maxPagesPerChunk = 200,
  }) async {
    final List<int> activePages = (targetPages != null && targetPages.isNotEmpty)
        ? (targetPages.where((p) => p >= 1 && p <= totalDocPages).toSet().toList()..sort())
        : List.generate(totalDocPages, (i) => i + 1);

    if (activePages.isEmpty) {
      throw Exception('未指定有效的待解析页码');
    }

    // If single chunk covering full document
    if (targetPages == null && activePages.length <= maxPagesPerChunk && fullPdfBytes.lengthInBytes <= 180 * 1024 * 1024) {
      return [
        MineruChunk(index: 0, pages: activePages, bytes: fullPdfBytes),
      ];
    }

    final List<MineruChunk> chunks = [];
    final List<List<int>> pageGroups = [];
    for (int i = 0; i < activePages.length; i += maxPagesPerChunk) {
      final end = (i + maxPagesPerChunk < activePages.length) ? i + maxPagesPerChunk : activePages.length;
      pageGroups.add(activePages.sublist(i, end));
    }

    int chunkIndex = 0;
    for (final group in pageGroups) {
      final doc = PdfDocument(inputBytes: fullPdfBytes);
      try {
        final activeSet = group.toSet();
        final docCount = doc.pages.count;
        for (int i = docCount - 1; i >= 0; i--) {
          final pNo = i + 1;
          if (!activeSet.contains(pNo)) {
            doc.pages.removeAt(i);
          }
        }
        final subList = await doc.save();
        final subBytes = Uint8List.fromList(subList);
        chunks.add(MineruChunk(
          index: chunkIndex++,
          pages: group,
          bytes: subBytes,
        ));
      } finally {
        doc.dispose();
      }
    }

    return chunks;
  }

  /// Executes client-direct MinerU OCR with OSS acceleration, streaming upload speed monitoring, and auto-merge.
  Future<String> executeMineruOcr({
    required Uint8List fullPdfBytes,
    required int totalDocPages,
    List<int>? targetPages,
    String? docId,
    ApiService? apiService,
    String apiToken = defaultMineruToken,
    String modelVersion = 'vlm',
    String language = 'auto',
    bool enableFormula = true,
    bool enableTable = true,
    String layoutModel = 'doclayout_yolo',
    bool ossAccelerate = true,
    String? existingMarkdown,
    void Function(
      double progress,
      String message,
      String phase,
      double uploadSpeedMbS,
      int currentPage,
      int totalPages,
    )? onProgress,
    bool Function()? isCancelled,
  }) async {
    var cleanToken = apiToken.trim();
    if (cleanToken.toLowerCase().startsWith('bearer ')) {
      cleanToken = cleanToken.substring(7).trim();
    }
    if (cleanToken.isEmpty) {
      cleanToken = defaultMineruToken;
    }

    if (isCancelled?.call() == true) throw Exception('任务已取消');

    // 1. Silent automatic splitting
    onProgress?.call(0.05, '正在准备文档与分片...', 'preparing', 0.0, 0, totalDocPages);

    final chunks = await prepareChunks(
      fullPdfBytes: fullPdfBytes,
      totalDocPages: totalDocPages,
      targetPages: targetPages,
      maxPagesPerChunk: 200,
    );

    final totalChunks = chunks.length;
    final totalTargetPages = chunks.fold<int>(0, (sum, c) => sum + c.pages.length);
    final Map<int, String> chunkMarkdowns = {};

    final client = http.Client();

    try {
      for (final chunk in chunks) {
        if (isCancelled?.call() == true) throw Exception('任务已取消');

        final chunkNo = chunk.index + 1;
        final chunkSizeMb = chunk.bytes.lengthInBytes / (1024 * 1024);
        final baseProgress = 0.05 + (0.90 * (chunk.index / totalChunks));

        // 2. Apply for upload URL & Batch ID
        onProgress?.call(
          baseProgress,
          '正在申请 MinerU 解析任务 [分片 $chunkNo/$totalChunks]...',
          'preparing',
          0.0,
          chunk.pages.first,
          totalTargetPages,
        );

        final batchUri = Uri.parse('$defaultApiBase/file-urls/batch');
        final Map<String, dynamic> reqBody = {
          'files': [
            {
              'name': 'chunk_$chunkNo.pdf',
              'data_id': 'readn_${DateTime.now().millisecondsSinceEpoch}_$chunkNo',
            }
          ],
          'model_version': modelVersion,
          'enable_formula': enableFormula,
          'enable_table': enableTable,
          'layout_model': layoutModel,
        };
        if (language.isNotEmpty && language != 'auto') {
          reqBody['language'] = language;
        }

        final batchRes = await client.post(
          batchUri,
          headers: {
            'Authorization': 'Bearer $cleanToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(reqBody),
        ).timeout(const Duration(seconds: 45));

        if (batchRes.statusCode != 200) {
          throw Exception('MinerU API 申请上传 URL 失败 (${batchRes.statusCode}): ${batchRes.body}');
        }

        final batchData = jsonDecode(utf8.decode(batchRes.bodyBytes)) as Map<String, dynamic>;
        if (batchData['code'] != 0 || batchData['data'] == null) {
          final msg = batchData['msg'] ?? batchRes.body;
          throw Exception('MinerU API 响应错误: $msg');
        }

        final batchId = batchData['data']['batch_id'] as String;
        final fileUrls = batchData['data']['file_urls'] as List<dynamic>;
        if (fileUrls.isEmpty) {
          throw Exception('MinerU 未返回有效的上传 URL');
        }

        final rawUploadUrl = fileUrls[0] as String;
        final uploadUrl = applyOssAcceleration(rawUploadUrl, enable: ossAccelerate);

        if (isCancelled?.call() == true) throw Exception('任务已取消');

        // 3. Streamed PUT Upload with real-time speed monitoring
        onProgress?.call(
          baseProgress + (0.05 / totalChunks),
          '正在上传文档 [分片 $chunkNo/$totalChunks]: 0.0 / ${chunkSizeMb.toStringAsFixed(1)} MB (0%)',
          'uploading',
          0.0,
          chunk.pages.first,
          totalTargetPages,
        );

        final uploadStartTime = DateTime.now();
        final putRequest = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
        putRequest.headers['Content-Length'] = '${chunk.bytes.lengthInBytes}';

        const chunkSize = 256 * 1024; // 256KB chunks
        int sentBytes = 0;
        final totalBytes = chunk.bytes.lengthInBytes;

        // Feed bytes in chunks to calculate progress and speed
        Future.microtask(() async {
          for (int i = 0; i < totalBytes; i += chunkSize) {
            if (isCancelled?.call() == true) {
              putRequest.sink.addError(Exception('任务已取消'));
              await putRequest.sink.close();
              return;
            }
            final end = (i + chunkSize < totalBytes) ? i + chunkSize : totalBytes;
            final slice = chunk.bytes.sublist(i, end);
            putRequest.sink.add(slice);
            sentBytes += slice.length;

            final elapsedSeconds = DateTime.now().difference(uploadStartTime).inMilliseconds / 1000.0;
            final speedMbS = elapsedSeconds > 0 ? (sentBytes / (1024 * 1024)) / elapsedSeconds : 0.0;
            final uploadProgress = sentBytes / totalBytes;
            final sentMb = sentBytes / (1024 * 1024);
            final percent = (uploadProgress * 100).toInt();

            onProgress?.call(
              baseProgress + (0.25 * uploadProgress / totalChunks),
              '正在上传 [分片 $chunkNo/$totalChunks]: ${sentMb.toStringAsFixed(1)}/${chunkSizeMb.toStringAsFixed(1)} MB ($percent%) • ${speedMbS.toStringAsFixed(1)} MB/s',
              'uploading',
              speedMbS,
              chunk.pages.first,
              totalTargetPages,
            );

            await Future.delayed(const Duration(milliseconds: 10));
          }
          await putRequest.sink.close();
        });

        final streamedResponse = await client.send(putRequest).timeout(const Duration(seconds: 600));
        final putRes = await http.Response.fromStream(streamedResponse);


        if (putRes.statusCode != 200 && putRes.statusCode != 201) {
          throw Exception('MinerU OSS 上传失败 (${putRes.statusCode}): ${putRes.body}');
        }

        final totalUploadSeconds = DateTime.now().difference(uploadStartTime).inMilliseconds / 1000.0;
        final avgUploadSpeed = totalUploadSeconds > 0 ? chunkSizeMb / totalUploadSeconds : 0.0;

        onProgress?.call(
          baseProgress + (0.30 / totalChunks),
          '上传完成 [分片 $chunkNo/$totalChunks] • 平均速率: ${avgUploadSpeed.toStringAsFixed(1)} MB/s，云端排队解析中...',
          'processing',
          avgUploadSpeed,
          chunk.pages.first,
          totalTargetPages,
        );

        if (isCancelled?.call() == true) throw Exception('任务已取消');

        // 4. Poll MinerU Batch Result
        final pollUri = Uri.parse('$defaultApiBase/extract-results/batch/$batchId');
        String? fullZipUrl;
        const maxPollAttempts = 300; // 300 * 3s = 900s

        for (int attempt = 0; attempt < maxPollAttempts; attempt++) {
          if (isCancelled?.call() == true) throw Exception('任务已取消');

          await Future.delayed(const Duration(seconds: 3));

          if (isCancelled?.call() == true) throw Exception('任务已取消');

          final pollRes = await client.get(
            pollUri,
            headers: {'Authorization': 'Bearer $cleanToken'},
          ).timeout(const Duration(seconds: 20));

          if (pollRes.statusCode != 200) continue;

          final pollJson = jsonDecode(utf8.decode(pollRes.bodyBytes)) as Map<String, dynamic>;
          if (pollJson['code'] != 0 || pollJson['data'] == null) continue;

          final results = pollJson['data']['extract_result'] as List<dynamic>?;
          if (results == null || results.isEmpty) continue;

          final item = results[0] as Map<String, dynamic>;
          final state = item['state'] as String? ?? 'pending';
          final progInfo = item['extract_progress']?.toString() ?? '';
          final progLabel = progInfo.isNotEmpty ? ' [进度: $progInfo]' : '';

          if (state == 'pending') {
            onProgress?.call(
              baseProgress + (0.35 / totalChunks),
              'MinerU 云端任务排队中 [分片 $chunkNo/$totalChunks]...',
              'processing',
              0.0,
              chunk.pages.first,
              totalTargetPages,
            );
          } else if (state == 'running') {
            final dynamicProgress = 0.35 + (0.45 * (attempt.clamp(0, 60) / 60.0));
            onProgress?.call(
              baseProgress + (dynamicProgress / totalChunks),
              'MinerU VLM 正在深度解析 [分片 $chunkNo/$totalChunks]$progLabel...',
              'processing',
              0.0,
              chunk.pages.first,
              totalTargetPages,
            );
          } else if (state == 'done') {
            fullZipUrl = item['full_zip_url'] as String?;
            break;
          } else if (state == 'failed') {
            final errMsg = item['err_msg'] ?? '未知错误';
            throw Exception('MinerU 云端解析失败: $errMsg');
          }
        }

        if (fullZipUrl == null || fullZipUrl.isEmpty) {
          throw Exception('MinerU 解析超时或未返回结果包链接 [分片 $chunkNo]');
        }

        if (isCancelled?.call() == true) throw Exception('任务已取消');

        // 5. Download Full Zip & Extract full.md
        final zipDownloadUrl = applyOssAcceleration(fullZipUrl, enable: ossAccelerate);
        onProgress?.call(
          baseProgress + (0.85 / totalChunks),
          '正在下载结果包 [分片 $chunkNo/$totalChunks]...',
          'downloading',
          0.0,
          chunk.pages.last,
          totalTargetPages,
        );

        final zipRes = await client.get(Uri.parse(zipDownloadUrl)).timeout(const Duration(seconds: 120));
        if (zipRes.statusCode != 200) {
          throw Exception('下载结果包失败 (${zipRes.statusCode})');
        }

        final archive = ZipDecoder().decodeBytes(zipRes.bodyBytes);
        String? chunkMd;

        for (final file in archive) {
          if (!file.isFile) continue;
          final fname = file.name;
          final lowerName = fname.toLowerCase();

          // 1. Extract image files
          if (lowerName.endsWith('.jpg') ||
              lowerName.endsWith('.jpeg') ||
              lowerName.endsWith('.png') ||
              lowerName.endsWith('.webp') ||
              lowerName.endsWith('.gif') ||
              lowerName.endsWith('.svg')) {
            final cleanImgName = fname.split('/').last;
            final imgContent = file.content as List<int>;
            final uint8 = Uint8List.fromList(imgContent);

            if (docId != null && docId.isNotEmpty) {
              DocCacheService().saveImage(docId, cleanImgName, uint8);
              apiService?.uploadDocumentImage(docId, cleanImgName, uint8);
            }
          } else if (lowerName.endsWith('.md')) {
            if (fname.contains('full.md') || chunkMd == null) {
              chunkMd = utf8.decode(file.content as List<int>, allowMalformed: true);
            }
          }
        }

        if (chunkMd == null || chunkMd.trim().isEmpty) {
          throw Exception('未在 MinerU 结果包中找到 Markdown 内容 [分片 $chunkNo]');
        }

        chunkMarkdowns[chunk.index] = chunkMd.trim();
      }

      // 6. Merge Chunk Markdowns
      onProgress?.call(
        0.96,
        '正在合并 Markdown 结构化文档...',
        'merging',
        0.0,
        totalTargetPages,
        totalTargetPages,
      );

      final mergedResult = _mergeMarkdowns(
        chunks: chunks,
        chunkMarkdowns: chunkMarkdowns,
        targetPages: targetPages,
        existingMarkdown: existingMarkdown,
      );

      onProgress?.call(
        1.0,
        'MinerU 解析完成！已提取 $totalTargetPages 页高质量 Markdown。',
        'completed',
        0.0,
        totalTargetPages,
        totalTargetPages,
      );

      return mergedResult;
    } finally {
      client.close();
    }
  }

  /// Merges chunk markdowns into a unified Markdown document preserving page markers.
  String _mergeMarkdowns({
    required List<MineruChunk> chunks,
    required Map<int, String> chunkMarkdowns,
    List<int>? targetPages,
    String? existingMarkdown,
  }) {
    if (chunks.length == 1 && targetPages == null && (existingMarkdown == null || existingMarkdown.trim().isEmpty)) {
      return chunkMarkdowns[0] ?? '';
    }

    final Map<int, String> existingPagesMap = {};
    if (existingMarkdown != null && existingMarkdown.trim().isNotEmpty) {
      final pageSplits = existingMarkdown.split(RegExp(r'<!--\s*Page\s+(\d+)\s*-->', caseSensitive: false));
      final matches = RegExp(r'<!--\s*Page\s+(\d+)\s*-->', caseSensitive: false).allMatches(existingMarkdown).toList();
      if (matches.isNotEmpty && pageSplits.length > matches.length) {
        for (int i = 0; i < matches.length; i++) {
          final pNo = int.tryParse(matches[i].group(1) ?? '') ?? (i + 1);
          final content = pageSplits[i + 1].trim();
          existingPagesMap[pNo] = content;
        }
      }
    }

    for (final chunk in chunks) {
      final md = chunkMarkdowns[chunk.index];
      if (md == null || md.isEmpty) continue;
      final startPage = chunk.pages.first;
      existingPagesMap[startPage] = md;
    }

    if (existingPagesMap.isNotEmpty) {
      final sortedPnums = existingPagesMap.keys.toList()..sort();
      final buffer = StringBuffer();
      for (int i = 0; i < sortedPnums.length; i++) {
        final pNo = sortedPnums[i];
        buffer.writeln('<!-- Page $pNo -->\n');
        buffer.writeln(existingPagesMap[pNo]);
        if (i < sortedPnums.length - 1) {
          buffer.writeln('\n');
        }
      }
      return buffer.toString().trim();
    }

    return chunks.map((c) => chunkMarkdowns[c.index] ?? '').where((s) => s.isNotEmpty).join('\n\n');
  }
}
