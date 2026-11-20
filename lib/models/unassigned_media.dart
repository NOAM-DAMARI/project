import 'lesson_import_info.dart';
import 'media.dart';

class UnassignedMedia with MediaFields {
  final String id;
  final LessonImportInfo? lessonInfo;
  final DateTime added;

  UnassignedMedia({required this.id, this.lessonInfo, DateTime? added})
      : added = added ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'lessonInfo': lessonInfo?.toJson(),
        'added': added.toIso8601String(),
        ...mediaJson(),
      };

  factory UnassignedMedia.fromJson(Map json) => UnassignedMedia(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        lessonInfo: json['lessonInfo'] is Map
            ? LessonImportInfo.fromJson(json['lessonInfo'] as Map)
            : null,
        added: DateTime.tryParse(json['added']?.toString() ?? ''),
      )..readMedia(json);
}
