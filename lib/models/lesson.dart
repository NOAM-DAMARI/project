import 'media.dart';

class Seg {
  int ms;
  String text;
  Seg(this.ms, this.text);
  Map toJson() => {'ms': ms, 'text': text};
  factory Seg.fromJson(Map j) =>
      Seg((j['ms'] as num?)?.toInt() ?? 0, j['text'] ?? '');
}

/// גרסת תמלול שמורה (ממנוע מסוים), לצורך השוואה בין מנועים.
class TranscriptVersion {
  String id, providerId, label;
  DateTime created;
  List<Seg> segs;
  TranscriptVersion(
      {required this.id,
      required this.providerId,
      required this.label,
      DateTime? created,
      List<Seg>? segs})
      : created = created ?? DateTime.now(),
        segs = segs ?? [];

  Map toJson() => {
        'id': id,
        'providerId': providerId,
        'label': label,
        'created': created.toIso8601String(),
        'segs': segs,
      };

  factory TranscriptVersion.fromJson(Map j) => TranscriptVersion(
        id: j['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        providerId: j['providerId']?.toString() ?? '',
        label: j['label']?.toString() ?? 'תמלול',
        created: DateTime.tryParse(j['created']?.toString() ?? ''),
        segs: ((j['segs'] ?? []) as List).map((e) => Seg.fromJson(e)).toList(),
      );
}

class Lesson with MediaFields {
  String id, title, notes, summary;

  /// פרשת שבוע או שם אירוע אישי.
  String parasha = '';
  String parashaKind = 'weekly';

  /// מספר שיעור – עד 4 ספרות (1–9999)
  int? number;

  /// סוג התאריך שמוצג לשיעור: 'g' לועזי, 'h' עברי
  String dateKind = 'g';
  bool fav = false;
  DateTime date, added;
  List<String> points = [];
  List<String> pointNotes = [];
  List<Seg> pointTimes = [];

  /// End time in milliseconds for each point, when the user defines a range.
  List<int> pointEnds = [];

  /// נושא לכל נקודה (סיפורים / הלכות / מנהגים / חידושים / אזהרות) ותת-נושא חופשי
  List<String> pointCats = [];
  List<String> pointSubs = [];
  List<Seg> marks = [], transcript = [];

  /// כל התמלולים שנעשו לשיעור (ממנועים שונים). [transcript] הוא התמלול הראשי.
  List<TranscriptVersion> transcripts = [];

  Lesson({
    required this.id,
    required this.title,
    this.notes = '',
    this.summary = '',
    DateTime? date,
  })  : date = date ?? DateTime.now(),
        added = DateTime.now();

  Map toJson() => {
        'id': id,
        'title': title,
        'parasha': parasha,
        'parashaKind': parashaKind,
        'number': number,
        'dateKind': dateKind,
        'notes': notes,
        'summary': summary,
        'fav': fav,
        'date': date.toIso8601String(),
        'added': added.toIso8601String(),
        'points': points,
        'pointNotes': pointNotes,
        'pointTimes': pointTimes,
        'pointEnds': pointEnds,
        'pointCats': pointCats,
        'pointSubs': pointSubs,
        'marks': marks,
        'transcript': transcript,
        'transcripts': transcripts,
        ...mediaJson(),
      };

  factory Lesson.fromJson(Map j) => Lesson(
        id: j['id'],
        title: j['title'] ?? '',
        notes: j['notes'] ?? '',
        summary: j['summary'] ?? '',
        date: DateTime.tryParse(j['date'] ?? ''),
      )
        ..fav = j['fav'] == true
        ..parasha = j['parasha']?.toString() ?? ''
        ..parashaKind = j['parashaKind'] == 'event' ? 'event' : 'weekly'
        ..number = (j['number'] as num?)?.toInt()
        ..dateKind = j['dateKind'] == 'h' ? 'h' : 'g'
        ..pointCats = List<String>.from(j['pointCats'] ?? [])
        ..pointSubs = List<String>.from(j['pointSubs'] ?? [])
        ..added = DateTime.tryParse(j['added'] ?? '') ?? DateTime.now()
        ..points = List<String>.from(j['points'] ?? [])
        ..pointNotes = List<String>.from(j['pointNotes'] ?? [])
        ..pointTimes = ((j['pointTimes'] ?? []) as List)
            .map((e) => Seg.fromJson(e))
            .toList()
        ..pointEnds = List<int>.from((j['pointEnds'] ?? []) as List)
        ..marks =
            ((j['marks'] ?? []) as List).map((e) => Seg.fromJson(e)).toList()
        ..transcript = ((j['transcript'] ?? []) as List)
            .map((e) => Seg.fromJson(e))
            .toList()
        ..transcripts = ((j['transcripts'] ?? []) as List)
            .map((e) => TranscriptVersion.fromJson(e))
            .toList()
        ..readMedia(j);
}
