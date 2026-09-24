import 'package:flutter/material.dart';

class NormalizedRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const NormalizedRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory NormalizedRect.fromJson(Map<String, dynamic> json) {
    return NormalizedRect(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  Rect toRect() {
    return Rect.fromLTWH(x, y, width, height);
  }

  static NormalizedRect fromRect(Rect rect) {
    return NormalizedRect(
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
    );
  }
}

class PdfAnnotation {
  final String id;
  final String docId;
  final String type; // "highlight" or "note"
  final int pageNumber; // 1-indexed
  final String colorHex;
  final List<NormalizedRect> rects;
  final String selectedText;
  final String noteContent;
  final DateTime createdAt;
  final DateTime updatedAt;

  PdfAnnotation({
    required this.id,
    required this.docId,
    this.type = "highlight",
    required this.pageNumber,
    this.colorHex = "#FFE066",
    required this.rects,
    this.selectedText = "",
    this.noteContent = "",
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isNote => type == "note" || noteContent.trim().isNotEmpty;

  factory PdfAnnotation.fromJson(Map<String, dynamic> json) {
    final rawRects = json['rects'] as List<dynamic>? ?? [];
    return PdfAnnotation(
      id: json['id'] as String,
      docId: json['doc_id'] as String,
      type: json['type'] as String? ?? "highlight",
      pageNumber: (json['page_number'] as num).toInt(),
      colorHex: json['color_hex'] as String? ?? "#FFE066",
      rects: rawRects.map((r) => NormalizedRect.fromJson(r as Map<String, dynamic>)).toList(),
      selectedText: json['selected_text'] as String? ?? "",
      noteContent: json['note_content'] as String? ?? "",
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'doc_id': docId,
      'type': type,
      'page_number': pageNumber,
      'color_hex': colorHex,
      'rects': rects.map((r) => r.toJson()).toList(),
      'selected_text': selectedText,
      'note_content': noteContent,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PdfAnnotation copyWith({
    String? id,
    String? docId,
    String? type,
    int? pageNumber,
    String? colorHex,
    List<NormalizedRect>? rects,
    String? selectedText,
    String? noteContent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PdfAnnotation(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      type: type ?? this.type,
      pageNumber: pageNumber ?? this.pageNumber,
      colorHex: colorHex ?? this.colorHex,
      rects: rects ?? this.rects,
      selectedText: selectedText ?? this.selectedText,
      noteContent: noteContent ?? this.noteContent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

