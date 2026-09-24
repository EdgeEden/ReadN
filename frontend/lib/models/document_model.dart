import 'package:intl/intl.dart';

class DocumentModel {
  final String id;
  final String filename;
  final String title;
  final int fileSize;
  final int pageCount;
  final String? checksum;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int annotationCount;
  final bool hasTextLayer;
  final String ocrStatus;

  DocumentModel({
    required this.id,
    required this.filename,
    required this.title,
    required this.fileSize,
    required this.pageCount,
    this.checksum,
    required this.createdAt,
    required this.updatedAt,
    this.annotationCount = 0,
    this.hasTextLayer = true,
    this.ocrStatus = "none",
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as String,
      filename: json['filename'] as String,
      title: json['title'] as String,
      fileSize: (json['file_size'] as num).toInt(),
      pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
      checksum: json['checksum'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      annotationCount: (json['annotation_count'] as num?)?.toInt() ?? 0,
      hasTextLayer: (json['has_text_layer'] as bool?) ?? true,
      ocrStatus: (json['ocr_status'] as String?) ?? "none",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'title': title,
      'file_size': fileSize,
      'page_count': pageCount,
      'checksum': checksum,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'annotation_count': annotationCount,
      'has_text_layer': hasTextLayer,
      'ocr_status': ocrStatus,
    };
  }

  DocumentModel copyWith({
    String? id,
    String? filename,
    String? title,
    int? fileSize,
    int? pageCount,
    String? checksum,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? annotationCount,
    bool? hasTextLayer,
    String? ocrStatus,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      title: title ?? this.title,
      fileSize: fileSize ?? this.fileSize,
      pageCount: pageCount ?? this.pageCount,
      checksum: checksum ?? this.checksum,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      annotationCount: annotationCount ?? this.annotationCount,
      hasTextLayer: hasTextLayer ?? this.hasTextLayer,
      ocrStatus: ocrStatus ?? this.ocrStatus,
    );
  }

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    return DateFormat('yyyy-MM-dd HH:mm').format(updatedAt);
  }

  String getFileUrl(String baseUrl) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$cleanBase/api/documents/$id/file';
  }
}

class OcrStatusInfo {
  final String docId;
  final String status;
  final double progress;
  final int currentPage;
  final int totalPages;
  final String message;
  final String? error;

  OcrStatusInfo({
    required this.docId,
    required this.status,
    required this.progress,
    required this.currentPage,
    required this.totalPages,
    required this.message,
    this.error,
  });

  factory OcrStatusInfo.fromJson(Map<String, dynamic> json) {
    return OcrStatusInfo(
      docId: json['doc_id'] as String? ?? '',
      status: json['status'] as String? ?? 'none',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      currentPage: (json['current_page'] as num?)?.toInt() ?? 0,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}

