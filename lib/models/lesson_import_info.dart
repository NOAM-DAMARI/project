class LessonImportInfo {
  final String title;
  final int? number;
  final String parasha;
  final String parashaKind;

  const LessonImportInfo({
    required this.title,
    this.number,
    this.parasha = '',
    this.parashaKind = 'weekly',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'number': number,
        'parasha': parasha,
        'parashaKind': parashaKind,
      };

  factory LessonImportInfo.fromJson(Map json) => LessonImportInfo(
        title: json['title']?.toString() ?? '',
        number: (json['number'] as num?)?.toInt(),
        parasha: json['parasha']?.toString() ?? '',
        parashaKind: json['parashaKind'] == 'event' ? 'event' : 'weekly',
      );
}
